# Maze Racer

A fast-paced 3D first-person maze racer with roguelike progression, built in **Godot 4.7**.

---

## The core idea

**Speed is not a choice. It is a condition.**

You move forward automatically and your speed climbs on its own — +1x every 15 seconds,
forever, up to 10x. You never ask for speed. You only manage it. The whole game is
reading a randomly generated maze accurately at speeds that outpace comfortable reaction.

Three keys, and that is the entire control scheme:

| Key | Action |
|---|---|
| `←` | Turn left at the next left-opening |
| `→` | Turn right at the next right-opening |
| `↓` | 180° reversal / un-stick from a crash |

## Two currencies, kept separate

The design's central rule: **speed comes from not crashing, time comes from routing well.**

Making a *correct* turn does not make you faster. Not crashing does. A player who takes a
wrong-but-clean route keeps every bit of their speed — the maze punishes bad routing with
distance, never with speed. Collapsing those two currencies into one would flatten the
game into a single dimension, so they stay apart.

## The barrier

Borrowed from lightcycle games: you get a small regenerating grace pool before wall
contact actually hurts you. Base capacity is half a second.

Turn out before it empties and **nothing happens at all** — no damage, no speed loss. Let
it empty and you crash: speed resets to 1x, you take damage, and you sit parked until you
press `↓`.

That window is the skill ceiling. A good player brushes walls constantly and never pays
for it; a cautious player never gets close enough to find out.

## Mazes and gates

Mazes are generated with a randomized-DFS carve, then **braided** — 12–25% of walls
removed to create genuine loops. Loops matter: a wrong turn does not always mean
backtracking, so "commit and route around" becomes a real decision instead of an
automatic 180.

Five **gates** sit on the optimal route through each maze. Pass one and the timer pauses
for an upgrade pick. Gates sit on the solve path deliberately — collecting them *is*
engaging with the maze, where a distance-travelled trigger would reward aimless wandering.

Three mazes per run, escalating in loop density and dead-end density more than raw size.
Upgrades carry between mazes.

| | Maze 1 | Maze 2 | Maze 3 |
|---|---|---|---|
| Grid | 60×60 | 75×75 | 90×90 |
| Loops | 12% | 18% | 25% |
| Target time | ~2 min | ~3 min | ~4–5 min |

## Upgrades

Nine lines, weighted toward changing *decisions* rather than numbers — Path Indicator
changes how you read a junction; Fast Turnaround changes whether you commit or reverse.

The headline is the **Path Indicator**: flashes green for the correct turn and red for
the wrong one. It works off a live BFS distance field rather than a baked path, so it
stays correct even when you are off the canonical route — which, in a maze full of loops,
is constantly.

## Status

Design complete. Implementation not started — see the build order in
[CLAUDE.md](CLAUDE.md) §9. Phase 1 is movement feel on a hand-authored test maze.

## Playing it

Double-click **Maze Racer** on the desktop.

← → turn, ↓ reverses — and un-sticks you after a crash.

## Running it from a shell

Godot 4.7. The path to the binary lives in `tools/godot-path.txt`.

```
powershell -ExecutionPolicy Bypass -File tools\play.ps1     # play (focused window)
powershell -ExecutionPolicy Bypass -File tools\launch.ps1   # develop (captures logs)
```

`launch.ps1` writes a session log to `logs/history/` and extracts errors into
`logs/errors.log`. Use `-Quit <seconds>` to auto-close, `-Headless -Script <res://path>`
for the harnesses.

### Tests

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SmokeTest.gd
```

Maze generation, the distance field, turn/buffer resolution, and the penalty math are all
pure logic and must stay headlessly testable. If verifying a rule needs a rendered frame,
the rule is in the wrong place.

## Docs

| File | Contents |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Full design: movement, speed, penalties, generation, upgrades, build order |
| [docs/plans/](docs/plans/) · [docs/specs/](docs/specs/) | Implementation plans and specs |
