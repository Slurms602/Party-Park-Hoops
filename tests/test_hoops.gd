extends SceneTree
## Headless check of shooting through the real input path: knockout -> grab -> charge -> shot -> basket.
## Run from the repo root: godot --headless --path game -s minigames/hoops/tests/test_hoops.gd

const DT := 1.0 / 60.0
var _fails := 0
var _arena: HoopsArena
var _baskets := []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_arena = HoopsArena.new()
	world.add_child(_arena)
	_arena.setup(true)
	_arena.basket.connect(func(hoop, by, victim, pts, kind): _baskets.append([hoop, by, victim, pts, kind]))
	var shooter := _beast(world, 1, Vector3.ZERO)
	var victim := _beast(world, 2, Vector3(2, 0.9, 0))
	var rim := _arena.rim(1)

	var got: Array = await _shoot(shooter, victim, rim + Vector3(-4.5, 0, 0), HoopsArena.ideal_power(4.5))
	_check(got.size() == 5 and got[0] == 1 and got[1] == 1 and got[3] == 2 and got[4] in ["shot", "swish"],
		"a jump shot at the right power goes in for 2 (%s)" % [got])
	for i in 120:
		if victim.state == Beast.STAND:
			break
		await _drive([shooter, victim], {}, 1)
	_check(victim.state == Beast.STAND, "whoever went through the hoop wakes up as they land")

	got = await _shoot(shooter, victim, rim + Vector3(-5.5, 0, 5.0), HoopsArena.ideal_power(Vector2(5.5, 5.0).length()))
	_check(got.size() == 5 and got[3] == 3 and got[4] == "three", "past the arc it's a three (%s)" % [got])

	got = await _shoot(shooter, victim, rim + Vector3(-1.5, 0, 0.3), 0.0)
	_check(got.size() == 5 and got[4] == "dunk" and got[3] == 2, "under the rim it's a slam dunk (%s)" % [got])

	got = await _shoot(shooter, victim, rim + Vector3(-8.0, 0, 0), 0.0)
	_check(got.is_empty(), "a tap from past the arc falls short (%s)" % [got])

	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _shoot(shooter: Beast, victim: Beast, at: Vector3, power: float) -> Array:
	## Stand at `at` facing the right hoop, knock the victim out, pick them up and shoot at `power`. The basket, or [].
	var all := [shooter, victim]
	at.y = 0.0
	var to := (_arena.rim(1) - at) * Vector3(1, 0, 1)
	var dir := to.normalized()
	shooter.global_position = at + Vector3.UP * 0.95
	shooter.linear_velocity = Vector3.ZERO
	shooter.facing = atan2(-dir.x, -dir.z)
	for i in 600:  # the last shot's landing wakes them up
		if victim.state == Beast.STAND:
			break
		await _drive(all, {}, 1)
	victim.global_position = shooter.global_position + dir * 1.0
	victim.linear_velocity = Vector3.ZERO
	await _drive(all, {}, 20)
	victim.immune = 0.0
	victim.take_hit(1, dir, 500.0, 0.5)
	await _drive(all, {}, 20)
	await _drive(all, {grab = true}, 3)
	if shooter.holding != victim:
		_check(false, "picked them up (shooter %s, victim %s state %d, holding %s)" % [shooter.global_position, victim.global_position, victim.state, shooter.holding])
		return []
	shooter.facing = atan2(-dir.x, -dir.z)
	await _drive(all, {grab = true, punch = true}, maxi(roundi(power * Beast.FULL_CHARGE / DT) - 1, 1))
	_baskets.clear()
	await _drive(all, {grab = true}, 1)
	for i in 300:
		if not _baskets.is_empty():
			break
		await _drive(all, {}, 1)
	return [] if _baskets.is_empty() else _baskets[0]


func _beast(world: Node3D, id: int, pos: Vector3) -> Beast:
	var b := Beast.new()
	world.add_child(b)
	b.setup(id, {name = "P%d" % id, color = Color.WHITE}, _arena, true)
	b.global_position = pos
	return b


func _drive(beasts: Array, inp: Dictionary, frames: int) -> void:
	for f in frames:
		beasts[0].sim(inp, DT)
		for b in beasts.slice(1):
			b.sim({}, DT)
		_arena.server_update(DT, beasts)
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
