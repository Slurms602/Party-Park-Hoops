# Dunk your Friends

A [Party Park](https://github.com/Slurms602/Party-Park) minigame: an indoor basketball arena. Brawl as usual, then
shoot whoever you knock out through one of the two giant hoops.

- **Shooting:** carry a knocked-out player, face a hoop and hold punch. The prompt tells you how much power the shot
  needs from where you stand; release close to it and it goes in, too much or too little hits the rim or the board.
- **Points:** 2 for a basket, 3 from beyond the arc. Release under the rim for a **slam dunk** (no charge needed).
- **On fire:** three baskets in a row and you're on fire: every shot goes in and scores +1, until someone else scores.
- Whoever goes through the hoop wakes up as they land, so nobody gets dunked twice in one go.

This repo is one folder of the game: it's mounted at `game/minigames/hoops` in Party-Park and can't run on its own.
To work on it, clone Party-Park with `--recursive` and work in that folder. Party-Park's `CLAUDE.md` explains how
minigames plug in.

- `minigame.gd`: how the game lists this minigame (name, rules, length)
- `hoops_arena.gd`: the arena, the shot model, scoring, and what bots do with someone they're carrying
- `tests/test_hoops.gd`: a headless check of a jump shot, a three, a slam dunk and a miss
