class_name HoopsArena
extends Arena
## Dunk your Friends: an indoor basketball arena. Brawl as usual, then shoot whoever you knock out through one of the
## two giant hoops. A shot needs the right charge for its distance (the prompt says how much); release under the rim
## and it's a slam dunk. 3 points from beyond the arc. Three baskets in a row and you're ON FIRE: every shot goes in
## and scores +1 until someone else scores.

signal basket(hoop: int, by: int, victim: int, pts: int, kind: String)

const HX := 12.5  # half the court's length (along x)
const HZ := 7.0  # half its width
const HOOP_X := 10.8  # rim centres at x = ±HOOP_X
const RIM_Y := 3.1
const RIM_R := 0.9  # a balled-up player is 1.1 m across
const THREE_R := 6.4  # the three-point arc, round the spot under the rim
const DUNK_R := 2.4  # release this close to a rim and you dunk
const SHOT_TOL := 0.2  # how far off the ideal charge a shot can be and still go in
const FIRE_AT := 3  # baskets in a row to catch fire
const ROWS := 7  # the stands
const TREAD := 0.9
const RISE := 0.55
const STAND_FRONT := HZ + 1.6

const COURT_SHADER := """
shader_type spatial;
uniform vec2 half_size = vec2(12.5, 7.0);
uniform float hoop_x = 10.8;
uniform float three_r = 6.4;
uniform vec3 paint = vec3(0.1, 0.27, 0.72);
uniform float coat = 0.0;  // high graphics: lacquered maple
varying vec3 wp;
float h(float n) { return fract(sin(n * 91.7) * 43758.5); }
float line(float d) { return smoothstep(0.06, 0.035, abs(d)); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	// Maple boards running the length of the court, joints staggered row to row.
	float row = floor(p.y / 0.2);
	float along = p.x + h(row) * 3.0;
	float plank = floor(along / 2.4);
	float grain = sin(along * 9.0 + h(row + plank) * 30.0 + sin(along * 1.3 + row) * 2.0) * 0.5 + 0.5;
	vec3 wood = mix(vec3(0.78, 0.53, 0.3), vec3(0.9, 0.68, 0.42), h(row * 7.0 + plank) * 0.7 + grain * 0.2);
	wood *= mix(0.8, 1.0, smoothstep(0.0, 0.04, fract(p.y / 0.2)) * smoothstep(0.0, 0.015, fract(along / 2.4)));
	float box = max(abs(p.x) - half_size.x, abs(p.y) - half_size.y);
	vec3 c = box > 0.0 ? mix(wood, paint * 0.75, 0.9) : wood;  // the painted apron outside the lines
	float l = line(box) + line(p.x) * step(abs(p.y), half_size.y);
	float r = length(p);
	c = mix(c, paint, step(r, 1.8) * 0.85);  // the centre circle, painted
	l += line(r - 1.8) + line(r - 0.6);
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		float ft = half_size.x - 5.8;  // the free-throw line
		float key = max(s * p.x - half_size.x, max(ft - s * p.x, abs(p.y) - 2.45));
		c = mix(c, paint, step(key, 0.0) * 0.85);
		l += line(key) + line(length(vec2(p.x - s * ft, p.y)) - 1.8) * step(s * p.x, ft + 0.1);
		vec2 q = vec2(p.x - s * hoop_x, p.y);
		float court_side = step(s * q.x, 0.0);
		l += line(length(q) - three_r) * court_side * step(s * p.x, half_size.x);
		l += line(abs(p.y) - three_r) * (1.0 - court_side) * step(s * p.x, half_size.x);
	}
	c = mix(c, vec3(0.97, 0.96, 0.92), clamp(l, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.18;
	SPECULAR = 0.6;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.06;
}
"""

const NET_SHADER := """
shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec2 g = vec2(UV.x * 18.0 + UV.y * 4.0, UV.x * 18.0 - UV.y * 4.0);  // a diamond mesh of cord
	float d = min(abs(fract(g.x) - 0.5), abs(fract(g.y) - 0.5));
	ALBEDO = vec3(0.97, 0.97, 0.95);
	ROUGHNESS = 0.9;
	ALPHA = step(d, 0.07);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

const LED_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 a = vec3(1.0, 0.45, 0.1);
uniform vec3 b = vec3(0.1, 0.3, 0.9);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = fract((wp.x + wp.z) * 0.06 - TIME * 0.15);  // colour panels scrolling along the ribbon boards
	vec3 c = mix(a, b, smoothstep(0.45, 0.5, t) - smoothstep(0.95, 1.0, t));
	float px = step(0.3, fract(wp.x * 14.0 + wp.z * 14.0)) * step(0.3, fract(wp.y * 14.0));
	ALBEDO = c * (0.55 + 0.45 * px) * 1.6;
}
"""

var _flights := {}  # host: ball pid -> {by, hoop, pts, kind, t, rim, scored, after, carrier}
var _prev_y := {}  # host: pid -> last tick's height (a basket is a fall through the rim)
var _streak := {}  # host: pid -> baskets in a row
var _on_fire := {}  # pid -> their flames (every peer; the host's rules read it too)
var _nets: Array[Node3D] = []
var _rims: Array[StaticBody3D] = []
var _boards: Array[Node3D] = []
var _confetti: Array[CPUParticles3D] = []
var _crowd: ShaderMaterial
var _cheer := 0.0
var _dancers: Array[Node3D] = []
var _beams: Array = []  # [SpotLight3D, phase] (high graphics)


func _init() -> void:
	go_word = "Tip off!"
	throw_word = "SHOOT!"
	stats = [["Baskets", "baskets"], ["3PT", "threes"], ["KO", "kos"]]


func setup(is_server: bool) -> void:
	_server = is_server
	half_w = HX + 1.0
	if is_server and game:
		basket.connect(_score)
	_environment()
	_court()
	for i in 2:
		_hoop(i)
	_stands()
	_decor()
	if Look.fast():
		Look.no_shadow(self)


func spawn_point(i: int) -> Vector3:
	return Vector3(((i % 4) - 1.5) * 2.6, 1.2, -1.6 if i < 4 else 1.6)


func rim(i: int) -> Vector3:
	## Rim centre of hoop 0 (left) or 1 (right).
	return Vector3(HOOP_X if i == 1 else -HOOP_X, RIM_Y, 0.0)


static func ideal_power(d: float) -> float:
	## The charge (0..1) a shot from d metres (to the spot under the rim) needs.
	return clampf((d - 2.0) / 10.0, 0.0, 1.0)


func target(by: Beast, f: Vector3) -> int:
	## The hoop a shot goes for: one you're under, else one you face, from the court side of its backboard. -1: none.
	var best := -1
	var best_dot := 0.3
	for i in 2:
		var to := (rim(i) - by.global_position) * Vector3(1, 0, 1)
		if signf(by.global_position.x) == signf(rim(i).x) and absf(by.global_position.x) > HOOP_X + 0.4:
			continue  # behind the backboard
		if to.length() < DUNK_R:
			return i
		var dot := f.dot(to.normalized())
		if dot > best_dot:
			best = i
			best_dot = dot
	return best


# ---------------------------------------------------------------- shooting (host)

func launched(by: Beast, ball: Beast) -> void:
	## Replace the bowl with a shot: an arc at the hoop, long or short by how far the charge was off.
	var f := by._forward()
	var i := target(by, f)
	var power := clampf(by.charge / Beast.FULL_CHARGE, 0.0, 1.0)  # still set: the match clears it after the throw
	var kind := "shot"
	var pts := 2
	var dir := f
	var to := by.global_position + f * (2.0 + power * 10.0)
	if i >= 0:
		var c := rim(i)
		var flat := (c - by.global_position) * Vector3(1, 0, 1)
		var d := flat.length()
		dir = flat / d if d > 0.05 else f
		if d < DUNK_R:
			kind = "dunk"
			to = c
		else:
			pts = 3 if d > THREE_R else 2
			var err := power - ideal_power(d)
			var tol := SHOT_TOL + (0.08 if by._assist else 0.0)
			var off := 0.0 if absf(err) <= tol or _on_fire.has(by.pid) else signf(err) * (0.45 + (absf(err) - tol) * 7.0)
			to = c + dir * (off + randf_range(-0.1, 0.1)) + dir.cross(Vector3.UP) * randf_range(-0.25, 0.25) * absf(off)  # misses go wide too
	var from := by.global_position + dir * 1.05 + Vector3.UP * 0.6
	if kind == "dunk":  # up over their head, and the dunker leaps for the rim with them
		from = by.global_position + dir * 0.2 + Vector3.UP * 1.4
		by.add_collision_exception_with(ball)
		ball.add_collision_exception_with(_rims[i])  # it goes up past the rim from underneath before slamming down through it
		by.linear_velocity = dir * 2.5 + Vector3.UP * 6.5
	to.y = RIM_Y + 0.1  # semi-implicit Euler drops a hair below the true parabola
	var reach := ((to - from) * Vector3(1, 0, 1)).length()
	var apex := maxf(from.y, RIM_Y) + (0.8 if kind == "dunk" else 1.1 + 0.16 * reach)
	ball.global_position = from
	ball.linear_velocity = arc(from, to, apex)
	ball.angular_velocity = Vector3.UP.cross(dir) * -6.0  # backspin
	ball.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE  # no air drag in flight, so the arc lands where it's aimed
	ball.linear_damp = 0.0
	_flights[ball.pid] = {by = by.pid, hoop = i, pts = pts, kind = kind, t = 0.0, rim = false, scored = false, after = 0.0, carrier = by}


static func arc(from: Vector3, to: Vector3, apex: float) -> Vector3:
	## Launch velocity that peaks at height apex and comes down through to.
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var up := sqrt(2.0 * g * maxf(apex - from.y, 0.05))
	var t := up / g + sqrt(2.0 * maxf(apex - to.y, 0.05) / g)
	return (to - from) * Vector3(1, 0, 1) / t + Vector3.UP * up


func server_update(dt: float, beasts: Array) -> void:
	for b: Beast in beasts:
		var y := b.global_position.y
		var py: float = _prev_y.get(b.pid, y)
		_prev_y[b.pid] = y
		var fl: Dictionary = _flights.get(b.pid, {})
		if not fl.is_empty():
			fl.t += dt
			if fl.scored:
				fl.after += dt
		if b.state != Beast.BALL:
			if not fl.is_empty():
				_end_flight(b)  # caught in the air (a block!) or woke up
			continue
		for i in 2:
			var c := rim(i)
			var flat := Vector2(b.global_position.x - c.x, b.global_position.z - c.z).length()
			if not fl.is_empty() and Vector2(flat - RIM_R, y - RIM_Y).length() < Beast.BALL_R + 0.14:
				fl.rim = true
			if py > RIM_Y and y <= RIM_Y and flat < RIM_R - 0.25 and b.last_toucher != 0 and b.last_toucher != b.pid \
					and not fl.get("scored", false):
				_basket(b, i, fl)
				fl = _flights[b.pid]
		if not fl.is_empty() and ((fl.scored and (fl.after > 1.2 or (fl.after > 0.25 and b._grounded))) \
				or (not fl.scored and fl.t > 0.4 and b._grounded) or fl.t > 5.0):
			_end_flight(b)
		if y > RIM_Y + 0.4 and b.linear_velocity.length() < 0.3:  # come to rest on a backboard: roll off it
			b.apply_central_impulse(Vector3(-signf(b.global_position.x), 0.5, 0.0) * 2.0 * b.mass)


func _basket(b: Beast, i: int, fl: Dictionary) -> void:
	var pts: int = fl.get("pts", 2)
	var kind: String = fl.get("kind", "shot")
	if kind == "shot":
		kind = "three" if pts == 3 else ("swish" if not fl.get("rim", true) else "shot")
	if fl.is_empty():  # tipped or punted in
		fl = {by = b.last_toucher, hoop = i, pts = 2, kind = kind, t = 0.0, rim = true, carrier = null}
		_flights[b.pid] = fl
	fl.scored = true
	fl.after = 0.0
	b.linear_velocity = Vector3(b.linear_velocity.x * 0.2, minf(b.linear_velocity.y, -3.0), b.linear_velocity.z * 0.2)  # down through the net
	basket.emit(i, b.last_toucher, b.pid, pts, kind)


func _end_flight(b: Beast) -> void:
	var fl: Dictionary = _flights[b.pid]
	_flights.erase(b.pid)
	b.linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	b.linear_damp = 0.1  # Beast.setup's
	if is_instance_valid(fl.get("carrier")):
		fl.carrier.remove_collision_exception_with(b)
	if fl.get("kind") == "dunk":
		b.remove_collision_exception_with(_rims[fl.hoop])
	if fl.get("scored", false) and b.state == Beast.BALL:
		b._wake()  # through the hoop and back in the game: nobody gets dunked twice in one go


# ---------------------------------------------------------------- scoring (host) and the show (everyone)

func _score(i: int, by: int, victim: int, pts: int, kind: String) -> void:
	var scores: Dictionary = game.scores
	if game.over or not scores.has(by):
		return
	for pid in _streak:
		if pid != by:
			_streak[pid] = 0
			if _on_fire.has(pid):
				game.send(_ev_fire, [pid, false])
	_streak[by] = _streak.get(by, 0) + 1
	var fire := _on_fire.has(by)
	var total := pts + (1 if fire else 0)
	scores[by].total += total
	scores[by].baskets = scores[by].get("baskets", 0) + 1
	if pts == 3:
		scores[by].threes = scores[by].get("threes", 0) + 1
	game.push_scores()
	game.send(_ev_basket, [i, by, victim, total, kind, fire])
	if not fire and _streak[by] >= FIRE_AT:
		game.send(_ev_fire, [by, true])


@rpc("authority", "call_local", "reliable")
func _ev_basket(i: int, by: int, victim: int, pts: int, kind: String, fire: bool) -> void:
	var net = get_node("/root/Net")  # autoloads by path: tests compile this script without them
	var sfx = get_node("/root/Sfx")
	var music = get_node("/root/Music")
	var who: String = net.players[by].name if net.players.has(by) else "?"
	var col: Color = net.players[by].color if net.players.has(by) else Color.WHITE
	var vic: String = net.players[victim].name if net.players.has(victim) else "?"
	var vcol: Color = net.players[victim].color if net.players.has(victim) else Color.WHITE
	var c := rim(i)
	var hud = game.hud
	var extra := "  ·  ON FIRE" if fire else ""
	_swish(i, kind == "dunk")
	_confetti[i].restart()
	_confetti[i].emitting = true
	_cheer = 1.0
	sfx.play("cheer", c, 2.0)
	if Look.high():
		game.burst(c, Color("ff8c2a"), 50, 7.0, true)
		game.flash(c, Color("ffd36b"), 8.0, 9.0)
	match kind:
		"dunk":
			hud.callout("SLAM DUNK!", Color("ff8c2a"), "%s dunked %s  +%d%s" % [who, vic, pts, extra], true)
			screen_board.flash("SLAM DUNK!", Color("ff8c2a"))
			game.ring(Vector3(c.x, 0.0, 0.0), Color("ff8c2a"))
			music.duck(1.4)
			sfx.play_ui("strike")
		"three":
			hud.callout("THREE!", Color("2de2ff"), "%s from downtown  +%d%s" % [who, pts, extra])
			screen_board.flash("THREE!", Color("2de2ff"))
			music.duck(1.0)
			sfx.play_ui("spare")
		_:
			hud.feed_event(who, col, ("SWISH +%d" if kind == "swish" else "BUCKET +%d") % pts, Color("3ddc97") if kind == "swish" else Color("2a7fff"),
				vic, vcol)
			sfx.play_ui("ding")


@rpc("authority", "call_local", "reliable")
func _ev_fire(pid: int, on: bool) -> void:
	if is_instance_valid(_on_fire.get(pid)):  # gone with their player if they left
		_on_fire[pid].queue_free()
	_on_fire.erase(pid)
	if not on:
		return
	var b: Beast = game.beasts.get(pid) if game else null
	_on_fire[pid] = _flames(b) if b else null
	if b and game.hud:
		game.hud.callout("ON FIRE!", Color("ff5a1a"), "%s can't miss: +1 a basket until someone else scores" % b.display_name)
		get_node("/root/Sfx").play_ui("hurry")


func _flames(b: Beast) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var blob := SphereMesh.new()
	blob.radius = 0.13
	blob.height = 0.26
	blob.radial_segments = 6
	blob.rings = 3
	p.mesh = blob
	p.material_override = Look.neon(Color("ff6a1a"), 5.0)
	p.amount = 18 if Look.fast() else 36
	p.lifetime = 0.55
	p.local_coords = false  # a trail behind them as they run
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 3.0, 0)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	p.scale_amount_curve = shrink
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3.UP * 0.1
	b.add_child(p)
	return p


func _swish(i: int, dunk: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_nets[i], "scale", Vector3(0.85, 1.45, 0.85), 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(_nets[i], "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if dunk:  # the whole backboard shudders
		var board := _boards[i]
		var tb := create_tween()
		for k in 6:
			tb.tween_property(board, "rotation:z", 0.05 * (1.0 if k % 2 == 0 else -1.0) * (1.0 - k / 6.0), 0.05)
		tb.tween_property(board, "rotation:z", 0.0, 0.05)


func _process(dt: float) -> void:
	_cheer = maxf(_cheer - dt * 0.45, 0.0)
	if _crowd:
		_crowd.set_shader_parameter("cheer", _cheer)
	var t := Time.get_ticks_msec() * 0.001
	for k in _dancers.size():
		var d := _dancers[k]
		d.position.y = absf(sin(t * (7.0 + k))) * (0.08 + _cheer * 0.6)
		(d.get_child(0) as BowlerModel).pose(dt, {dance = true})
	for b in _beams:
		var ph: float = b[1]
		var spd := 1.0 + _cheer * 3.0
		b[0].look_at(Vector3(sin(t * 0.5 * spd + ph) * 9.0, 0.0, cos(t * 0.37 * spd + ph * 1.3) * 5.0))


# ---------------------------------------------------------------- prompts and bots

func carry_prompts(me: Beast) -> Array:
	var i := target(me, me._forward())
	if i < 0:
		return [["HOLD LMB", "WIND UP"], ["RELEASE", "THROW"], ["!", "FACE A HOOP TO SHOOT", true]]
	var d := ((rim(i) - me.global_position) * Vector3(1, 0, 1)).length()
	if d < DUNK_R:
		return [["LMB", "SLAM DUNK!"]]
	return [["HOLD LMB", "SHOOT AT %d%% POWER" % (roundi(ideal_power(d) * 10.0) * 10)], ["RELEASE", "FOR 3!" if d > THREE_R else "FOR 2"]]


func bot_carry(b: Beast, m: Dictionary, inp: Dictionary, dt: float) -> Dictionary:
	## Carry them to a spot (under the rim, mid-range or out past the arc), face the hoop, charge about right, shoot.
	var pos := b.global_position
	if m.get("carry_id", 0) != b.holding.get_instance_id():
		m.carry_id = b.holding.get_instance_id()
		m.hoop = 0 if pos.x < 0.0 else 1
		var r: float = [1.4, randf_range(3.5, 5.5), randf_range(6.8, 8.0)].pick_random()
		var a := randf_range(-1.1, 1.1)  # round the hoop, from the court side
		var c := rim(m.hoop)
		m.spot = Vector3(c.x - signf(c.x) * cos(a) * r, 0.0, clampf(sin(a) * r, -HZ + 0.8, HZ - 0.8))
		m.wind = -1.0
	var to: Vector3 = (m.spot - pos) * Vector3(1, 0, 1)
	if to.length() > 0.6 and m.wind < 0.0:
		inp.move = Vector2(to.x, to.z).normalized()
		return inp
	var at := (rim(m.hoop) - pos) * Vector3(1, 0, 1)
	inp.move = Vector2(at.x, at.z).normalized() * 0.2  # face the hoop while winding up
	if m.wind < 0.0:
		m.wind = 0.0
		m.goal = clampf(ideal_power(at.length()) + randfn(0.0, 0.13), 0.0, 1.0) * Beast.FULL_CHARGE
	m.wind += dt
	inp.punch = m.wind < m.goal
	if not inp.punch:
		m.carry_id = 0  # shot: next carry picks a new spot
	return inp


func bot_home(t: float) -> Vector3:
	return Vector3(sin(t * 0.4) * 6.0, 0.0, cos(t * 0.3) * 3.0)


# ---------------------------------------------------------------- building

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0a0d1c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffe9cf")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = not Look.fast()
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssr_enabled = true  # the lacquered floor mirrors the players and the lights
	env.ssr_max_steps = 48
	env.fog_enabled = true
	env.fog_light_color = Color("141a33")
	env.fog_density = 0.006
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	if Look.high():
		Look.dress_env(env, Color("fff1dc"), 0.02)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()  # the arena's ceiling rig: one strong key straight over the court
	sun.rotation_degrees = Vector3(-70, 15, 0)
	sun.light_color = Color("fff4e2")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 0.0
	if Look.fast():
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	for x in [-8.0, 0.0, 8.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, 8.0, 0.0)
		l.omni_range = 14.0
		l.light_energy = 1.3
		l.light_color = Color("fff0dc")
		add_child(l)
	if Look.high():
		var cols := [Color("ff8c2a"), Color("2de2ff"), Color("ff3fb4"), Color("ffe14d")]
		for k in cols.size():
			var b := SpotLight3D.new()
			b.position = Vector3((k - 1.5) * 7.0, 11.0, -3.0)
			b.light_color = cols[k]
			b.light_energy = 6.0
			b.spot_range = 22.0
			b.spot_angle = 10.0
			b.spot_attenuation = 0.1
			b.light_volumetric_fog_energy = 6.0
			add_child(b)
			_beams.append([b, k * 1.9])


func _court() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = COURT_SHADER
	mat.set_shader_parameter("half_size", Vector2(HX, HZ))
	mat.set_shader_parameter("hoop_x", HOOP_X)
	mat.set_shader_parameter("three_r", THREE_R)
	mat.set_shader_parameter("coat", 1.0 if Look.high() else 0.0)
	_solid(Vector3(HX * 2.0 + 8.0, 1.0, HZ * 2.0 + 6.0), Vector3(0, -0.5, 0), mat, 0.9)
	var logo := Label3D.new()  # centre court
	logo.text = "PP"
	logo.font = Look.title_font()
	logo.font_size = 200
	logo.outline_size = 0
	logo.modulate = Color("ff8c2a")
	logo.pixel_size = 0.008
	logo.rotation_degrees = Vector3(-90, 0, 0)
	logo.position = Vector3(0, 0.01, 0)
	add_child(logo)
	for s in [-1.0, 1.0]:  # lettering on the near apron
		var word := Label3D.new()
		word.text = "PARTY PARK"
		word.font = Look.title_font()
		word.font_size = 110
		word.modulate = Color(1, 1, 1, 0.85)
		word.pixel_size = 0.008
		word.rotation_degrees = Vector3(-90, 0, 0)
		word.position = Vector3(s * 6.5, 0.01, HZ + 0.95)
		add_child(word)
	# Walls, tall enough to keep a lob in: the near one is invisible (the camera looks in over it) behind a low ribbon
	# board; the far side and the ends are the stands' fronts.
	var led := ShaderMaterial.new()
	led.shader = Shader.new()
	led.shader.code = LED_SHADER
	for w in [[Vector3(HX * 2.0 + 8.0, 0.7, 0.3), Vector3(0, 0, HZ + 2.0)], [Vector3(HX * 2.0 + 8.0, 1.0, 0.3), Vector3(0, 0, -STAND_FRONT + 0.15)],
			[Vector3(0.3, 1.0, HZ * 2.0 + 6.0), Vector3(-HX - 3.85, 0, 0)], [Vector3(0.3, 1.0, HZ * 2.0 + 6.0), Vector3(HX + 3.85, 0, 0)]]:
		var size: Vector3 = w[0]
		Look.mesh(self, Look.box(size), led, w[1] + Vector3.UP * size.y * 0.5)
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, 10.0, size.z)
		_body(shape, w[1] + Vector3.UP * 5.0)


func _hoop(i: int) -> void:
	var s := 1.0 if i == 1 else -1.0
	var c := rim(i)
	var orange := Look.toy(Color("ff6a1a"), 0.3)
	orange.metallic = 0.4
	var ring := TorusMesh.new()
	ring.inner_radius = RIM_R - 0.06
	ring.outer_radius = RIM_R + 0.06
	ring.rings = 48
	ring.ring_segments = 8
	Look.mesh(self, ring, orange, c)
	var rim_body := StaticBody3D.new()  # a ring of little spheres: shots rattle round it and bounce out
	rim_body.position = c
	rim_body.add_to_group("rim")
	rim_body.physics_material_override = PhysicsMaterial.new()
	rim_body.physics_material_override.bounce = 0.45
	for k in 16:
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.08
		cs.shape = sph
		cs.position = Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * RIM_R
		rim_body.add_child(cs)
	add_child(rim_body)
	_rims.append(rim_body)
	var net := CylinderMesh.new()
	net.top_radius = RIM_R
	net.bottom_radius = RIM_R * 0.62
	net.height = 1.1
	net.cap_top = false
	net.cap_bottom = false
	net.radial_segments = 24
	var nm := ShaderMaterial.new()
	nm.shader = Shader.new()
	nm.shader.code = NET_SHADER
	var holder := Node3D.new()  # the net hangs from the rim: scale it from the top
	holder.position = c
	add_child(holder)
	Look.mesh(holder, net, nm, Vector3(0, -0.55, 0))
	_nets.append(holder)
	# The backboard: glass in a white frame with the shooter's square, on a padded stanchion behind the baseline.
	var board := Node3D.new()
	board.position = Vector3(s * (HOOP_X + RIM_R + 0.35), RIM_Y + 0.8, 0)
	add_child(board)
	_boards.append(board)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.93, 1.0, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	Look.mesh(board, Look.box(Vector3(0.08, 2.2, 3.6)), glass)
	var white := Look.toy(Color("f4f1ea"), 0.4, false)
	for k in [[Vector3(0.1, 0.12, 3.7), Vector3(0, 1.1, 0)], [Vector3(0.1, 0.12, 3.7), Vector3(0, -1.1, 0)],
			[Vector3(0.1, 2.3, 0.12), Vector3(0, 0, 1.8)], [Vector3(0.1, 2.3, 0.12), Vector3(0, 0, -1.8)]]:
		Look.mesh(board, Look.box(k[0]), white, k[1])
	var square := Look.neon(Color("ff6a1a"), 0.6)
	for k in [[Vector3(0.1, 0.07, 1.5), Vector3(0, 0.2, 0)], [Vector3(0.1, 0.07, 1.5), Vector3(0, -0.75, 0)],
			[Vector3(0.1, 1.0, 0.07), Vector3(0, -0.27, 0.72)], [Vector3(0.1, 1.0, 0.07), Vector3(0, -0.27, -0.72)]]:
		Look.mesh(board, Look.box(k[0]), square, k[1] - Vector3(s * 0.05, 0, 0))
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.15, 2.2, 3.6)
	_body(bb, board.position, 0.5)
	Look.mesh(self, Look.box(Vector3(0.36, 0.08, 0.3)), orange, Vector3(s * (HOOP_X + RIM_R + 0.15), RIM_Y, 0))  # rim bracket
	var steel := Look.toy(Color("2b2f3a"), 0.4)
	var post_x := s * (HX + 1.6)
	Look.mesh(self, Look.box(Vector3(absf(post_x - board.position.x), 0.28, 0.28)), steel, Vector3((post_x + board.position.x) * 0.5, RIM_Y + 1.0, 0))
	_solid(Vector3(0.35, RIM_Y + 1.15, 0.35), Vector3(post_x, (RIM_Y + 1.15) * 0.5, 0), steel)
	_solid(Vector3(1.4, 1.1, 2.2), Vector3(post_x, 0.55, 0), Look.toy(Color("1f4fd1"), 0.6))  # the padded base
	var conf := Venues.confetti(self, c + Vector3(0, 1.5, 0), 2.0)
	_confetti.append(conf)


func _stands() -> void:
	## Seating on three sides (the camera's side stays open), packed with fans who jump when someone scores.
	var seats := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tiers := [SurfaceTool.new(), SurfaceTool.new()]
	for st: SurfaceTool in tiers:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var every := 0.85 if not Look.fast() else 1.7
	var end_x := HX + 4.0
	for side in 3:  # 0: far side, 1: left end, 2: right end
		var length := HX * 2.0 + 8.0 if side == 0 else HZ * 2.0 + 4.0
		for k in ROWS:
			var h := 1.0 + k * RISE
			var d := (STAND_FRONT if side == 0 else end_x) + (k + 0.5) * TREAD
			var xf := Transform3D(Basis(), Vector3(0, h * 0.5, -d)) if side == 0 \
				else Transform3D(Basis(Vector3.UP, PI * 0.5 if side == 1 else -PI * 0.5), Vector3(-d if side == 1 else d, h * 0.5, -1.0))
			tiers[k % 2].append_from(Look.box(Vector3(length, h, TREAD)), 0, xf)
			var n := int(length / every)
			for e in n:
				if rng.randf() < 0.12:
					continue
				var along := (e + 0.5) * every - length * 0.5
				var p := xf * Vector3(along, h * 0.5 + 0.45, 0.0)
				seats.append([p, fposmod(atan2(p.z, p.x) / TAU, 1.0)])
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = tiers[k].commit()
		mi.material_override = Look.toy(Color("1d2a5a") if k == 0 else Color("16214a"), 0.7, false)
		add_child(mi)
	_crowd = Venues.crowd(self, seats)
	var back := STAND_FRONT + ROWS * TREAD
	_solid(Vector3(HX * 2.0 + 10.0, 14.0, 0.5), Vector3(0, 7.0, -back - 0.3), Look.toy(Color("0e1430"), 0.9, false))


func _decor() -> void:
	# The big screen over the far stands, in a frame with the arena's name.
	var back := STAND_FRONT + ROWS * TREAD
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 520)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	screen_board = Scoreboard.new()
	screen_board.draw.connect(func(): vp.render_target_update_mode = SubViewport.UPDATE_ONCE)
	screen_board.big = true
	screen_board.show_frames = false
	screen_board.heading = "DUNK YOUR FRIENDS"
	screen_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(screen_board)
	var scr := QuadMesh.new()
	scr.size = Vector2(10.5, 3.4)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = vp.get_texture()
	var at := Vector3(0, 6.9, -back + 0.2)
	Look.mesh(self, scr, sm, at).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Look.mesh(self, Look.box(Vector3(11.1, 4.0, 0.3)), Look.toy(Color("11131c"), 0.4, false), at - Vector3(0, 0, 0.2))
	Look.mesh(self, Look.box(Vector3(11.3, 0.12, 0.35)), Look.neon(Color("ff8c2a"), 2.0), at + Vector3(0, 2.05, -0.15))
	var sign := Label3D.new()
	sign.text = "PARTY PARK ARENA"
	sign.font = Look.title_font()
	sign.font_size = 120
	sign.outline_size = 22
	sign.modulate = Color("fff4df")
	sign.outline_modulate = Color("ff6a1a")
	sign.pixel_size = 0.008
	sign.position = at + Vector3(0, 2.7, 0)
	add_child(sign)
	# Championship banners hanging either side of the screen.
	var titles := ["CHAMPS", "DUNK\nCITY", "ALL\nSTARS", "FINALS"]
	for k in titles.size():
		var x := (-1.0 if k < 2 else 1.0) * (8.0 + (k % 2) * 3.2)
		var flag := Node3D.new()
		flag.position = Vector3(x, 8.4, -back + 0.1)
		add_child(flag)
		Look.mesh(flag, Look.box(Vector3(2.2, 3.0, 0.05)), Look.toy(Color("1f4fd1") if k % 2 == 0 else Color("e8323c"), 0.8, false))
		var l := Label3D.new()
		l.text = titles[k]
		l.font = Look.title_font()
		l.font_size = 90
		l.modulate = Color("ffd23f")
		l.pixel_size = 0.008
		l.position = Vector3(0, 0.1, 0.04)
		flag.add_child(l)
	# Cheerleaders on the far sideline, dancing the whole game and going wild for every basket.
	var skins := [{hat = "headband", outfit = "stripes", accent = "orange", shoes = "neon", eyes = "sparkle"},
		{hat = "party", outfit = "zigzag", accent = "blue", shoes = "candy", eyes = "round"}]
	for k in (0 if Look.fast() else 4):  # each is a whole player model: phones skip them
		var holder := Node3D.new()
		holder.position = Vector3((-1.0 if k < 2 else 1.0) * (3.5 + (k % 2) * 2.2), 0.76, -HZ - 1.0)  # the model's origin is its middle
		add_child(holder)
		var dancer := Node3D.new()
		holder.add_child(dancer)
		var m := BowlerModel.new()
		dancer.add_child(m)
		m.build(Color("ff8c2a") if k % 2 == 0 else Color("2f6bff"), Skins.sanitize(skins[k % 2]))
		dancer.scale = Vector3.ONE * 0.8
		_dancers.append(dancer)
	# The scorer's table between them.
	_solid(Vector3(4.0, 0.9, 0.7), Vector3(0, 0.45, -HZ - 1.15), Look.toy(Color("11131c"), 0.4))
	var table := Label3D.new()
	table.text = "DUNK YOUR FRIENDS"
	table.font = Look.title_font()
	table.font_size = 64
	table.modulate = Color("ff8c2a")
	table.pixel_size = 0.006
	table.position = Vector3(0, 0.5, -HZ - 0.79)
	add_child(table)
