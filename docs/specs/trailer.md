# Attract-mode trailer

A self-playing showreel, reachable from the main menu, that shows all five
mazes, the upgrade tree escalating, and what a gate actually does -- in about a
minute, with no input and no risk of embarrassing itself.

## Why it exists

The game has no shop window. Everything good about it -- the palettes, the
speed ramp, the wall-mounted Path Indicator, the gate pause -- only appears
after someone has played for a couple of minutes. The trailer front-loads all
of it.

It also earns its keep as a **development instrument**: it is the only thing
that drives the real renderer through every maze, every palette and the gate
round trip in one pass. `PaletteShot` checks stills; this checks motion.

## The main menu

There was no main menu at all -- `Main.tscn` booted straight into `Game.gd`.
The trailer needs somewhere to be launched *from*, so the menu is part of this
work rather than a separate job.

`Main.tscn` now boots `Shell.gd`, which owns exactly one child scene at a time:
the menu, a real game, or the trailer. `Game.gd` is untouched and still the run
controller -- the shell instantiates it exactly as before, so nothing about a
normal run changes.

## Determinism

**Seeded from a constant, never the clock.** `TRAILER_SEED` is checked in, so
every play of the trailer is frame-for-frame the same maze, the same corners,
the same gates. A trailer that generated a fresh maze each time would be a
demo that occasionally shows a boring corridor and occasionally drives into a
dead end on camera -- the exact "did we get lucky" failure CLAUDE.md section 12
calls out for tests, and it matters more here because this is the thing a new
player sees first.

The autopilot is the same distance-field router `RunTest` uses. It routes
correctly through loops, so it never strands itself; combined with a fixed seed
the whole reel is reproducible.

## Segment structure

Five segments, one per maze, ~5s each, plus a title card and an outro.

Each segment carries **its own pre-built upgrade set**, applied before the maze
starts. This is the point of the reel: maze 1 shows the bare game, and by maze
5 the Path Indicator is lighting junctions, the minimap is wide, and the
Golden Trail is firing. The build escalates because that is what a real run
looks like, and a trailer that showed maze 5 with a rank-0 HUD would be
advertising the wrong game.

Speed is seeded per segment too -- later mazes open already fast, because
arriving at maze 5 at 1.0x would misrepresent the pressure the game is built
around.

## Gates

**Three of the five segments show a gate**, and they show it by *arriving* at
one: the racer is placed a short distance back along the solve path from a real
gate cell, so the gate is passed through on camera and the upgrade screen comes
up the way it does in play.

Placing the racer rather than waiting is deliberate. Gates sit at even
intervals along the solve path (CLAUDE.md section 6), so the first one is far
more than five seconds of driving from the start -- a trailer that waited for a
gate would spend its whole runtime in corridor. The segment is a cut, not a
continuous run, and cutting to just before the interesting thing is what a
trailer is.

The card screen then **holds for ~2.2s before a pick is made**, so the cards are
readable. The pick is scripted per segment rather than random, so the reel
always shows a card worth reading.

## Skipping

Any key or click ends the trailer and returns to the menu. An attract mode that
cannot be escaped is a hostage situation, and the one thing a player pressing a
key during a trailer wants is to start playing.

## What it must not do

- **No new rules.** The trailer drives the real `Game` through its real public
  surface. It sets up state and presses the same buttons a player would; it
  does not reimplement movement, and nothing in `Racer` knows it exists.
- **No timer meaning.** The run timer runs, but it is scenery here -- the reel
  is cut, so the number is not a score of anything.
