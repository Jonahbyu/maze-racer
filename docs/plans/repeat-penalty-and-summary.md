# Repeat-cell penalty and the end-of-run summary

Two changes, one shipped together because the second is how the first becomes
legible: a penalty the player cannot see the total of is a mystery, not a rule.

## 1. The repeat-cell penalty

**-250 points every time the racer enters a cell it has already been in.** Not
once per distinct cell -- every re-entry.

### Why every re-entry, and not once per cell

This is the fix for the farming exploit (a 1M-point run made by driving back and
forth in one corridor near the exit). Section 8b was built around "wandering must
not outscore optimal play" and answers it with the time multiplier -- which works
per maze and fails outright for a player who declines to finish one. The
multiplier applies at BANK time and floors at 0.20x, so a subtotal that grows
forever beats it.

Charging once per distinct cell measures route redundancy but does not close the
exploit: after one lap the loop is fully marked and every subsequent lap is free
again. Charging every re-entry makes the farming loop cost ~250/cell *per lap*,
forever, which is the only version that actually bites.

### Sizing

-250 is 4.2 clean turns at 1.0x, and about 0.4 turns at 6x. That asymmetry is
deliberate and correct: the exploit runs at high speed, where a turn pays
360 and a repeat costs 250, so a farming lap nets far less than it did while
still leaving legitimate high-speed driving profitable. At low speed a repeat
costs more than the turn pays, so early-maze flailing is punished hardest --
which is where a lost player actually is.

### It is charged on backtracks too, with no exemption

A 180 out of a dead end pays the reversal cost AND the repeat cells on the way
out. One rule, no special cases. Section 11.2 says bad routing is punished by
distance and time; this makes it points as well, which is the same currency the
score is measured in. An exemption for "honest" mistakes would need the game to
decide which mistakes are honest, and the farming loop would dress itself as one.

### It does NOT scale with earn_multiplier

Score Multiplier is a bonus on points EARNED. Scaling the penalty by it would
make backtracking more expensive the more of that line you take -- an upgrade
that punishes you for owning it. Same reasoning as the flat crash penalty: a
penalty that scales with the player's ability to earn charges most exactly when
it hurts most.

### Where the tracking lives

`Racer` owns a `visited` dictionary keyed by cell, and emits `cell_entered(cell,
repeat)` from `_on_enter_cell`. Two notes:

- `_on_enter_cell` currently returns early on exit and gate cells. Visit
  tracking must happen BEFORE those returns, or a gate cell is free to farm --
  and gates sit on the solve path, which is exactly where a player loops.
- The dictionary resets per maze, with the start cell pre-marked. Carrying it
  across mazes would be wrong: a new maze is new ground by definition.

`Score.add_repeat()` is the award, symmetrical with `add_crash()`. `Score`
counts `repeat_cells` for the summary.

## 2. The end-of-run summary screen

Replaces the one-line HUD message on BOTH run-end paths -- death and completion.
Dying is when a player most wants to know what went wrong, so sending the
breakdown only to winners is backwards.

### Contents

- Final score, large.
- Per-maze table: name, subtotal, time, multiplier, banked score. `Score` already
  records all five in `maze_results`; nothing new is needed.
- Run totals: time, clean turns, scraped turns, crashes, repeat cells (and the
  points those cost).
- The final build: every line held, with its rank.
- Outcome line: cleared, or died on which maze.

### Design constraints

- It is a full modal, unlike `UpgradeScreen`. A gate pick deliberately leaves the
  world visible because the player is going back to it; a finished run is not
  going back, and the corridor behind the cards is a distraction from the only
  screen in the game that is meant to be read slowly.
- Built from `Score.maze_results` and `Upgrades.ranks`, never from its own
  tallies. A summary that recomputes anything can disagree with the HUD.
- No new tuning numbers restated in it. The repeat cost is read from `Tuning`.

## 3. Test coverage

`RulesTest`:
- A re-entered cell charges the penalty; a fresh one does not.
- The SAME cell entered a third time charges again (the farming case -- this is
  the assertion that distinguishes the two readings of the rule).
- The penalty ignores `earn_multiplier`.
- Gate and exit cells are tracked (the early-return trap above).
- `visited` resets per maze.
- Monotonicity still holds across the six modelled runs of section 8b.
- A modelled FARMING run must score below a modelled clean run. This is the
  assertion the exploit would have failed, and the reason the existing
  monotonicity test missed it: every run it models finishes the maze.

`SceneTest`:
- The summary screen opens on death and on completion, and lists one row per
  completed maze.
