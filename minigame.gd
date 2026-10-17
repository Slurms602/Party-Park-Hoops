## Hoops: knock people out, then shoot them through giant basketball hoops. This folder is its own git repo.
## MAPS is what the game knows about this minigame (see Arena.maps).

const MAPS := {
	hoops = {name = "Dunk your Friends", map = "Party Park Arena", rules = "Knock them out and shoot them through a hoop. Charge to the right power, 3 points from past the arc, slam dunks from under the rim. Most points wins.",
		seconds = 75.0, arena = preload("hoops_arena.gd")},
}
