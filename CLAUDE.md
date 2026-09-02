# Project — Maze Racer

A fast-paced 3D first-person maze racer with roguelike progression. You move forward
automatically down a grid corridor at ever-increasing speed. Arrow keys commit turns.
Survive five increasingly complex mazes, taking upgrades at gates along the way.

Built in **Godot 4.7**. The Godot project lives in this same folder — `project.godot`,
`scenes/`, and `scripts/` sit alongside these design docs. **The `.md` files are the
source of truth for the design; the code implements them.**

Genre DNA: Armagetron/Tron lightcycles (grid movement, the wall-contact grace window),
endless runners (auto-forward, speed as pressure), roguelite deckbuilders (gate-gated
upgrade picks that reshape strategy).

---

## Working Practices

### Self-instructions

- **Update these docs only when a change lands and is confirmed working.** Ask first;
  don't rewrite the design silently. The exception is a rule **decided in conversation** —
  write that down the same turn, because it's the reasoning being captured, not a claim
  about shipped code.
- **Record what isn't derivable from the code.** Design reasoning, tuning rationale,
  invariants, and gotchas belong here. File lists, function inventories, and scene trees
  drift the moment the code moves — grep answers those faster and is never out of date.
- **Say what's actually verified.** "Harness passes" means it was run this session. If it
  wasn't, say so.

### Jonah never launches Godot

**Claude owns the full Godot loop here — editing, running, testing, and reading errors.**
Jonah should never have to open the editor to check whether something works. That means:

- Run the game yourself via `tools/launch.ps1` and read `logs/errors.log`.
- Run the headless harnesses yourself and report what broke.
- Never end a turn with "open Godot and see if it works."

If a change genuinely can't be verified headlessly or from a captured log, say so
explicitly rather than quietly leaving it unverified.

### Design before code

**Design before code, always.** A mechanic that isn't settled in `CLAUDE.md` isn't ready
to be written in GDScript — building first means the docs get back-filled to match
whatever the code happened to do, which is backwards.

Scale the ceremony to the work:

| Situation | What to do |
|---|---|
| A tuning number, a bug fix, one upgrade's value | Just do it. |
| A new mechanic that touches movement or penalties | Settle it here first, then build. |
| A multi-file change (generation rewrite, new hazard system) | `writing-plans`, then execute. |
| A whole phase from §9 | `brainstorming` → `writing-plans` → execute. |

Plans and specs go in `docs/plans/` and `docs/specs/` (overriding the skills' default
`docs/superpowers/` path). Create those directories when the first one is written.

### Skills

Skills are installed globally at `~/.claude/skills/`. Invoke them with the `Skill` tool —
never `Read` the skill files. The relevant set:

| Skill | When |
|---|---|
| `writing-plans` | A multi-file change or a full phase from the build order |
| `systematic-debugging` | Any bug or harness failure, **before** proposing a fix |
| `test-driven-development` | Adding a rule to movement/penalties — write the assertion first |
| `verification-before-completion` | Before claiming anything passes, is fixed, or is done |
| `verify` | Confirming a change works by actually running the game |
| `dispatching-parallel-agents` | 2+ genuinely independent tasks |
| `skill-reflect` | End of a substantial session |

**Not applicable** despite being installed: `using-git-worktrees` and
`finishing-a-development-branch` (this project is not a git repo — delete this line if it
is ever `git init`-ed); `frontend-design` (this is Godot, not web); the whole marketing
family; `stop-slop` (prose, not gameplay).

**Scale to the work.** `using-superpowers` says to invoke a skill on even a 1% chance it
applies, and `brainstorming` declares a hard gate before any creative work. Read literally
that means a design session before every tuning tweak, which is wrong here — the planning
table above governs instead. **When a skill and these docs conflict, the docs win.**

---

## 1. Core Loop

```
spawn → auto-forward at 1.0x → read junctions → turn cleanly → speed climbs
   → hit a gate → timer pauses, pick 1 of 3 upgrades → resume
   → repeat ×8 gates → maze exit → next maze (upgrades carry)
   → clear maze 5 → run complete
```

The tension: speed climbs on its own and never stops climbing. Going fast is not a
choice, it is the default. The player's job is to keep reading the maze accurately at
speeds that outpace comfortable reaction. Crashing is the tax on being unprepared.

---

## 2. Movement Model

### Grid-locked, on-rails

The player is **always moving forward** along their facing direction. There is no free
steering, no analog input, no strafing. The maze is a square grid; the player travels
cell-to-cell along corridor centers.

Crucially: **every cell boundary is a visible grid line** on the floor. The grid line is
the timing reference. The player can see exactly when they cross into a new cell, which
is what makes precise-but-fair input possible at 8x speed. This is the contract — see
§11.3.

### Inputs

| Key | Action |
|---|---|
| `←` | Turn left at the next left-opening |
| `→` | Turn right at the next right-opening |
| `↓` | 180° reversal / un-stick from a crash |
| `Esc` / `P` | Pause |

That is the entire *driving* control scheme. No accelerator, no brake. Speed is systemic.

**Pause is not a fourth driving input.** The three-key contract is about what steers the
racer, and pause steers nothing — it is the same category as closing the window. It stops
the simulation *and* the run timer, because the timer is the score (§8) and a pause that let
it run would penalise stepping away from the keyboard.

**It blurs the minimap**, for exactly the reason a gate does (§7). A paused, static,
zoomed-out map is a free solve of the entire maze — without the blur, pause would be a
strictly better gate screen: available any time, at no cost, for as long as you like.

One interaction worth knowing: the crash prompt is a *held* HUD message, so pausing while
parked overwrites it, and unpausing clears it — which would leave the player stopped with
nothing on screen telling them why, the exact failure the held message exists to prevent.
Unpausing re-shows it if the crash is still current.

### Turn resolution

A directional press does **not** turn immediately. It arms a *pending turn* that resolves
at the next cell boundary where that direction is open:

1. Player presses `←`.
2. Pending-left is armed with a buffer of N cells (§4).
3. At each cell boundary crossed, check: is there an opening to the left?
   - **Yes** → the turn resolves. Player pivots and continues down the new corridor.
     Cost: −0.03x speed (§5.3).
   - **No** → buffer decrements by the distance travelled. If the buffer is exhausted,
     the input **expires** into a slowdown penalty (§5.2).

This is why pressing early is survivable but not free, and why Buffer Window is the
single most quality-of-life upgrade in the game.

**One immediate turn per cell.** A press whose side is open *right here* resolves on the
spot rather than waiting for the boundary — otherwise the player sails past the opening
they were aiming at. But only the first such press in a cell does. A second press before
the next boundary arms the buffer like any other early input.

Without that lockout, two quick presses in an open junction both fired instantly, and two
lefts is a 180: a double-tap while rounding a corner span the player back the way they
came. The lockout clears on entering a new cell and on an explicit 180, which is never the
accidental input this guards against.

**A turn pivots; it never rewinds.** Resolving a turn used to reset `progress` to 0, which
snapped the player back to the centre of a cell they had already half-crossed. In play that
read as *"I reached the new grid line, turned, and it threw me back to an old one and I
missed my turn"* — the grid lines are the timing contract (§11.3), and a turn that silently
moves you to a different line than the one you just crossed breaks it outright. The player
is at a real point in the corridor; turning is a rotation, so the distance already covered
still counts toward the next boundary.

The one exception is escaping a scrape, where `progress` is pinned at 1.0 to mean "hard
against the wall" rather than to mean a position at all (§12, the `progress` trap). Pivoting
out of a scrape starts from the cell centre because that is where the player actually is.

**That reset has to happen on both escape paths**, and for a long time it only happened on
one. A turn pressed *while already scraping* went through `request_turn`'s immediate path,
which cleared `scraping` but left `progress` at 1.0 — so the pivot interpolated that 1.0
down the newly-opened corridor and threw the marker **a full cell forward in a single
frame**, landing it hard against the next boundary. That is the "I turn and I'm suddenly at
the front of the cell" bug, and it fired on the majority of measured turns, because pressing
a direction while brushing a wall is ordinary play, not an edge case.

Resetting to the cell centre is a real reposition — about 1.4m — and there is **no
continuous alternative**. Carrying the drawn wall-face position through the pivot instead
was tried and measured *worse* (1.95m), because the wall face is 1.38m along the **old**
heading, so reusing that number sends the marker the same distance down the **new** one. The
two are not the same point. The freeze below is what makes the reposition readable rather
than something to hide.

### The turn freeze

**A turn holds the player still for a beat before the new corridor starts moving.** Base
**0.10s**, and **0.16s** for a 180 — longer because a reversal swings the view through a
full half-turn, and the corridor behind you is the one thing you have not been looking at.

A pivot is not a continuous motion. Facing changes in one frame, and the drawn position can
move with it. Trying to *hide* that discontinuity was the wrong instinct — the scrape-escape
measurement above shows there is no formulation that removes it. Freezing on it turns the
jump into **a beat the player can see**: the world holds still, the camera swings onto the
new heading at **3.5x** its normal rate, and travel resumes once the view agrees with the
facing. A freeze the camera does not spend would just be a stutter.

It also pays for itself against the ramp. At 8x a corner arrives and is gone inside 125ms;
the freeze buys a **fixed, speed-independent** moment to read the new corridor, which is the
one thing the ramp otherwise takes away.

**The clock keeps running.** The freeze is a pause in *position*, not in the systemic
pressure of §3 — the speed ramp advances throughout, because a freeze that stopped it would
make cornering a way to duck the game's central mechanic. And the run timer advances, so the
freeze is a real cost in the currency §8 says the player is fighting. Snap Turn (§7) buys it
back down.

**It consumes only as much of the frame as it needs.** Swallowing the whole `delta` and
returning was wrong twice: a 0.10s freeze ends *inside* the frame that crosses it but still
ate that frame whole, leaking up to a frame of travel per corner; and any frame longer than
the freeze — a hitch, or a slow machine — was discarded entirely, which makes the same
stutter last longer on worse hardware. `RulesTest` caught this as zero travel after the
window, and it is a frame-rate-independence bug, not a tuning one.

**A turn always takes the NEXT opening, never the one behind.** After a turn, the corridor
just left is locked out of turn resolution until the player leaves that cell. At a
crossroads, without this, a second press folds straight back into the corridor just exited —
a 180 the player neither asked for nor paid the 180's price for.

**The 180 is exempt**, and that exemption is the point: going back is precisely what `↓`
means, it is explicit, and it is expensive. The lockout exists to stop *accidental*
reversals arriving through the turn keys at the cheap 90° price, not to restrict the input
that reversal is for.

### The 180

`↓` reverses facing in place. It is always legal — you came from there, so it is open by
definition. Cost is a large speed penalty (§5.3). This is the "I misread the maze and
need to backtrack" button and it is meant to hurt. Fast Turnaround attacks that cost
directly.

`↓` is also the un-stick input after a crash (§5.4). Same key, and that is deliberate:
the crash recovery *is* a turnaround.

---

## 3. Speed

### The ramp

Speed is a multiplier on base traversal rate. **Base rate: 1 cell per second at 1.0x.**

Speed accrues **linearly with time-not-crashing**:

```
+1.0x per 10 seconds of clean travel   →   0.10x per second
```

So 2x at 10s, 3x at 20s, 4x at 30s. This is *clean travel* time — the ramp does not
advance while parked in a crash.

**Speed does not increase from making correct turns. It increases from not crashing.**
This distinction is deliberate and load-bearing: the player is rewarded for clean
execution, not for solving the maze. A player who takes a wrong-but-clean route keeps
their speed. The maze punishes bad routing with *distance and time*, never with speed.
Collapsing these two currencies would make the game one-dimensional.

### Cap

**Hard cap: 10.0x** — 10 cells/sec, 100ms per cell, roughly 6 frames at 60fps. Reaching
it takes 90 seconds of completely clean travel, which in practice will almost never
happen. The cap is a safety rail, not a goal, and it should stay absurd.

### Floor

**Minimum: 1.0x.** Speed never drops below base. The player is never stopped except while
parked in a crash. (Base Speed upgrades raise this floor — §7.)

### Post-crash re-acceleration

After un-sticking, the player accelerates at **2.5× the normal ramp rate**
(0.1667x/sec) until reaching 1.0x, then reverts to the standard rate. Recovery should
feel snappy — the crash already cost time and the full speed reset; a slow crawl back
would punish twice.

> **Tuning note:** the linear ramp is aggressive by design. If playtesting shows runs
> consistently falling apart from unreadability past ~6x, the first lever is lengthening
> the interval (10s → 12s), **not** lowering the cap.

---

## 4. The Buffer Window

The buffer is the forgiveness window on an early directional press.

**Measured in cells, not seconds.** This is deliberate. A time-based buffer would get
*more* forgiving as speed rises — more cells pass per unit time — which inverts the
difficulty curve exactly when the game should be getting harder. A cell-based buffer
keeps forgiveness constant and honest at every speed.

- **Base buffer: 1.0 cells.** The rule this encodes: **a press made at any point while
  you are in a cell is still live when you reach the far side of it.** You never have to
  time an input to a fraction of a cell — enter a cell, press, and the turn lands at the
  next opening.
- Upgrades extend it in small increments (+0.15 cells per rank).
- The buffer is consumed by distance travelled. Press `←` with 0.2 buffer, travel 0.2
  cells with no left opening → the input expires → slowdown.

**Why a full cell:** the grid lines make the boundary readable, so the buffer is not there
to compensate for a hidden deadline — it is there so that a *correct read* pressed early
still lands. At 0.2 it punished ordinary play rather than panic. At 0.4 it still covered
only the last two-fifths of the approach, so an input fired early in a cell — a perfectly
reasonable read of a junction already in view — expired into a slowdown before the junction
arrived. **That punished reading ahead, which is the exact skill the game asks for**, and
it worsened with speed, because a cell passes faster than a player re-presses.

At 1.0 the buffer spans exactly the cell it was armed in, so the slowdown is reserved for
what it was designed for: an input aimed at an opening that **is not there**.

---

## 5. Barrier, Damage, and Penalties

### 5.1 The Barrier — the lightcycle "give"

The player has a **barrier**: a small regenerating pool that absorbs wall contact.

- Moving into a wall **drains the barrier continuously**.
- **Base capacity: 0.25 seconds** of sustained wall contact. It was 0.5, and that was
  long enough that an unupgraded racer could sit against a wall for most of a cell and
  still leave clean — so the question the barrier exists to ask, *can I afford this
  brush?*, had an easy yes at rank 0. Halving it makes a brush a real commitment from
  maze 1 onward.

  **`BARRIER_PER_RANK` deliberately stays at 0.25**, so a single rank now *doubles* the
  pool rather than adding half again. That turns Barrier Capacity from a rounding error
  into a genuine early pick, which is §11.5's test: the rank changes whether the player
  brushes walls at all, not merely how long they may.
- **Regenerates** when not in contact — base **0.15/sec**, so a full refill takes ~3.3s of
  clean travel. It was 0.25, and that was too generous: the pool was effectively always full
  by the next corridor, so the interesting question — *can I afford this brush?* — never got
  asked, and consecutive scrapes cost nothing extra. At 0.15 scrapes **compound**, which is
  what makes Barrier Regen a line worth taking rather than a rounding error.
- **If the player turns out of the wall before the barrier empties, nothing happens.** No
  damage, no speed loss, no crash. This is the skill expression: a good player brushes
  walls constantly and never pays for it.
- **If the barrier empties, the player crashes** (§5.4).

The barrier bar is the most important HUD element. It is the difference between "I am
cutting it fine" and "I am about to lose several seconds."

### 5.2 Slowdown — expired input

An armed turn whose buffer ran out without finding an opening.

- **Cost: −0.5x speed**, immediate.
- No HP damage. No barrier drain. No stun. **This is not a crash.**
- The pending input is cleared — **the player must press the direction again** to make the
  turn. An expired press does not stay queued.

This is the cheap, frequent, teaching penalty. It says *you were early* without derailing
the run.

### 5.3 Turn costs

| Turn | Cost |
|---|---|
| Clean 90° left/right | −0.03x |
| 180° reversal | −0.75x (base; reduced by Fast Turnaround) |

90° turns are nearly free — the game wants the player turning constantly. The 180 costs
real speed but is survivable: it started at −2.0x, which taxed a misread twice (the
distance *and* a serious speed loss) and made every dead end punishing. At −0.75x the maze
punishes bad routing mainly with **distance and time**, which is the currency separation in
§11.2. It stays ~25x a 90, so committing to a route and rounding a loop is still
meaningfully cheaper than reversing — the decision the 180 exists to create.

> **The turn cost is far more load-bearing than it looks.** A DFS-carved maze forces a
> turn on roughly **55% of cells**, so the cost is paid almost continuously and fights the
> ramp head-on. Speed settles at an equilibrium where ramp-gain per second equals
> turn-cost per second:
>
> ```
> equilibrium ≈ RAMP_PER_SEC / (turn_ratio × TURN_COST)
>             = 0.10 / (0.55 × TURN_COST)
> ```
>
> At the original −0.1x — against the original 15s ramp — that equilibrium was **1.21x**:
> speed could never meaningfully climb, and the 10x cap was unreachable in principle
> rather than merely in practice. A full autopilot run finished at 1.71x after six minutes
> of flawless driving.
>
> The two numbers move the settling point in opposite directions, and both have since been
> retuned. Measured on full autopilot runs:
>
> | TURN_COST | ramp | measured final speed | run time |
> |---|---|---|---|
> | −0.10x | 15s | 1.71x | ~6 min |
> | −0.03x | 15s | 3.51x | 205s |
> | **−0.03x** | **10s** | **4.45x** | **179s** |
>
> The 1.5x faster ramp lifted the settling point by almost exactly 1.5x, which is what the
> formula predicts — it is linear in `RAMP_PER_SEC`.
>
> This is the single most sensitive pair of numbers in the game. If corridors are ever made
> straighter (lower turn ratio), or either number moves again, re-derive rather than
> re-guess.

### 5.4 Crash — barrier depleted

- **HP damage: 1** (base wall damage).
- **Speed resets to 1.0x** (or the Base Speed floor). Not bled — reset. The crash is the
  meaningful event and needs to read as a hard stop.
- **The player is parked**, motionless, until they press `↓`. The camera pulls back
  *and lifts*, aiming down at the player, and the recovery prompt holds on screen until
  they un-stick rather than fading.
- On un-stick, re-accelerate at 2.5× rate (§3).
- The barrier begins regenerating immediately on un-stick.
### 5.5 HP

- **100 HP**, and **death is ON**: HP reaching 0 ends the run.
- **Wall damage scales per maze: 3, 5, 7, 9, 11** (`WALL_DAMAGE` + `WALL_DAMAGE_PER_MAZE`
  × maze). Against 100 HP that is ~33 crashes on maze 1 and ~9 on maze 5, measured.

**This reverses the original "no death in v1" call, deliberately, and it is a change of genre
rather than a tuning tweak.** §8 said the timer was the *only* thing the player fights, and
that is no longer true — a run can now end. Recorded plainly because the rest of these docs
were written against the old assumption, and anything that reads "there is no death" predates
this decision.

**The two halves only make sense as a pair.** Damage was a flat 1, which made HP decorative:
100 crashes to die in a game whose longest run is a few minutes, so the number on the HUD
never meant anything. §5.5 always intended HP to "become relevant in the late mazes", but a
flat rate cannot do that — the same damage against a fixed pool is the same pressure
everywhere. Scaling per maze is what turns HP into an escalation lever alongside size and
loop density (§8). Equally, death against a flat 1 would essentially never fire, so enabling
it without the curve would have been a flag with no consequence.

Together they give the two HP lines something real to bite into: **Wall Armor** stops being
near-useless, and **Repair Field** (§7) becomes the reason to drive clean between crashes
rather than merely the reason to avoid them.

- Armor subtracts **after** the per-maze scaling, so a rank is worth the same flat point on
  every maze rather than being multiplied up where damage is already largest.
- A dead racer is finished: it stops moving, and the run ends where it stands. There is no
  un-stick, because the racer is already parked from the crash that killed it.
- Death is checked **after** the crash signal fires, so a fatal crash still reads as a crash
  — the HUD message, the camera pull-back and the recovery framing all happen normally, and
  the death lands on top. Emitting death first would leave the player looking at a stopped
  racer with no account of what hit them.


The crash view is three changes working together, and each covers a failure the others
do not:

- **Retreat alone is not enough.** A crash happens with a wall ahead, often in a dead end
  or a fresh corner, so the anti-clip clamp regularly eats the entire pull-back and the
  camera does not move at all. **Height is the axis that stays available**, so the crash
  view lifts as well as retreating — still capped below `WALL_HEIGHT`, for the usual
  reason.
- **Lifting without re-aiming points the camera into the wall.** Holding the normal
  `CAM_LOOK_HEIGHT` from a raised eye fills the frame with one flat face and hides the
  marker, the corridor, and everything the pull-back existed to show. The aim drops to
  `CAM_CRASH_LOOK_HEIGHT` so the camera looks *down* at the stopped player.
- **The prompt has to outlast the fade.** Messages fade after 1.6s, but the player stays
  parked until they press `↓` — which can be far longer. A prompt that vanishes while the
  state it describes is still active leaves them stopped with no explanation on screen, so
  the crash message is *held* and cleared by the `unstuck` signal.

### 5.6 A dead end is marked by a landmark, not a sign

**Removed: the wall indicator.** A no-entry mark used to light on the end wall of a dead
end once it was within 2.5 cells, ramping amber to red as it closed. It is gone, and the
**landmark now carries the whole job** — every dead end is decorated (§6), so the thing at
the end of the corridor is a spire or a monolith rather than a warning sign.

**Why the sign went and the decoration stayed.** Both mark the same cell, so the question
was only which one should. The sign was the weaker of the two on every axis that matters:

- **It told the player something the corridor was about to tell them anyway.** A dead end
  is ~2.5 cells of warning at best, and the 180 that answers it costs −0.75x whether it is
  pressed early or late (§5.3). The sign bought a fraction of a second on an input that is
  not a timing test — unlike a *turn*, which must land inside a cell boundary and is what
  the grid-line contract in §11.3 actually exists for.
- **It said nothing on the second visit.** Every dead end got the identical mark, so the
  sign could not distinguish one the player had already wasted a reversal on from a fresh
  one. That is precisely the read a looped maze needs and the one §6 built landmarks to
  give — and the sign sat on top of it, at eye height, on the exact wall the landmark
  stands against.
- **Two signals for one cell is one too many.** Six landmark hues were chosen to dodge
  every colour already spoken for (§8), and the sign's amber→red ramp was one of the
  reservations they were dodging. Removing it gives that band back.

**The trade is a small loss of warning for a permanent gain in memory.** The player now
reads a dead end from the silhouette ahead — which is visible at a distance, is *different
every time*, and means "you have been here before" on the second look. The sign never
could.

**This does not hand any routing away.** A landmark still answers "have I been here",
never "which way" — placement ignores the solve path, the distance field, the gates and
the exit entirely (§6). Path Indicator, Gate Compass and Golden Trail keep their monopoly
on the route ahead, which is the same line the wall indicator was itself careful to hold.

`SceneTest` asserts the replacement directly, over the grid *and* over real play: no dead
end may be left bare, and every dead end the seeking autopilot actually drives into must
carry a landmark. The two halves catch different failures — the placement pass can list a
cell the mesh builder never emits.

---

## 6. Maze Generation

### Requirements

- **Grid size:** 60×60 for maze 1, configurable per maze (§8).
- **Must contain loops.** A perfect maze — exactly one path between any two cells — is not
  what this game wants. Loops mean a wrong turn does not always mean backtracking;
  sometimes the smart play is to commit and route around, which is a far more interesting
  decision than "180 immediately."
- **Must have a guaranteed solve path** from entrance to exit.
- **Dead ends** are the punishment for misreads. Their density is a difficulty knob.

### Algorithm

1. **Carve a perfect maze** — iterative randomized DFS (recursive backtracker) with an
   explicit stack. Produces long winding corridors, which suits a speed game far better
   than the short choppy corridors Prim's or Kruskal's tend to give.

   The carve takes a **`straighten` bias** (0.0-1.0): the chance it keeps going the way it
   arrived when that direction is still open. This is the only effective lever on corridor
   length. Measured on 60x60, averaged over 8 seeds:

   | straighten | avg straight run | longest |
   |---|---|---|
   | 0.00 | 1.6 cells | 8 |
   | 0.50 | 2.4 cells | 10 |
   | **0.60** | **3.0 cells** | **15** |
   | 0.70 | 3.7 cells | 19 |

   Above ~0.65 the maze starts degenerating into axis-aligned combs. **Braiding barely
   affects this** — going 6% to 12% moved the average run from 1.95 to 1.77, i.e. noise.
   Reach for `straighten` when corridors feel too choppy, not for the braid factor.
2. **Braid in loops** — remove walls between cells that are adjacent in space but distant
   in the maze graph. Target **12–20%** braid factor for maze 1.
3. **Solve** — BFS from the exit across the whole grid, storing both the canonical solve
   path and a **full distance field**: BFS distance to the exit for *every* cell.
4. **Place gates** — 8, at even intervals along the canonical solve path.
5. **Cull one-cell stubs** — see below. Runs *before* density tuning.
6. **Tune dead ends** — a dead end is any cell with exactly one open neighbor. Add or
   remove to hit the per-maze target density.
7. **Cull zigzags** — thin the corner-into-corner pairs that force two turns back to
   back. Runs after both dead-end stages, before the straight-run cap.
8. **Cap straight runs** — bound the longest corridor with no turn available. Runs
   **last**, after every other wall-knocking stage.
9. **Place landmarks** — decorative structures in sealed pockets, dead ends, and outside
   the boundary. Runs after everything, on its own RNG stream, and reads nothing the
   rules depend on.

### Straight runs are capped at 8 cells

A **straight run** is what it is to the player: consecutive cells with no opening to either
side, so there is nothing to read and no decision to make. `MAX_STRAIGHT_CELLS = 8`.

The `straighten` carve bias lengthens corridors on *average* but **cannot bound them** — it
is a per-step probability, so a long run is always possible, and at 0.70 the measured
longest passed 40 cells. A 40-cell straight is dead time in a game whose entire tension is
reading junctions at speed.

Enforced as a post-carve pass rather than by lowering `straighten`, because the two want
opposite things: **the bias sets the typical corridor length, the cap sets the ceiling.**
Lowering the bias to control the tail would shorten every corridor.

It must run **after** both dead-end stages. Those open walls, which can merge two corridors
into a new over-long run — capping before them measurably left runs over the limit in the
finished maze. Measured after (6 seeds each): longest 7–8, **zero** runs over cap.

`RunLengthProbe.gd` is the instrument.

### Forced immediate turns are thinned

A **corner** is a cell with exactly two *perpendicular* openings: you arrive from one side
and the only way on is a 90. It is not a junction — a junction offers a **choice**, which is
the decision the whole game is built on, while a corner offers only an **obligation**. A
**zigzag** is a corner whose exit leads straight into another corner, so the player pays two
commits back to back with no cell between them to read the second from.

**It is a timing problem, not a routing one, and it worsens exactly as the ramp climbs.** At
6x a cell passes in 167ms, so a zigzag demands two commits inside a third of a second — and
the player is still inside the turn freeze (§2) from the first when the second arrives. §11.3
says every timing demand must be visible before it is demanded; the second corner *is*
visible, but there is no room left to act on it. Long staircases are worse: measured, the
unbiased mazes carried **300–500 chains of three or more** forced turns each.

**The cull opens a wall rather than closing one**, like every other stage in the pipeline.
Knocking the wall ahead of the second corner turns the forced turn into an *optional* one —
the player may still take it, they are no longer made to. That distinction is the point: the
pass removes **obligations, not corners**, so the maze keeps its shape and loses only the
coercion. It prefers the wall opposite an existing opening, since opening a corner's fourth
side adds a route while leaving both approaches still forced to turn.

It runs **after both dead-end stages** (those open walls and so mint new corners) and
**before the straight-run cap**, which has to stay the last word on corridor length.

**The knob was mostly inert before this existed, by accident.** Only maze 1 sets
`straighten`; mazes 2–5 have no entry and fall back to `0.0`, a pure random DFS that turns at
nearly every cell. So the set *anti-escalated* — maze 2 measured the worst of all five at 57%
of corners being zigzags, against maze 1's 40%. Measured, 8 seeds each:

| | Maze 1 | Maze 2 | Maze 3 | Maze 4 | Maze 5 |
|---|---|---|---|---|---|
| Before | 40% | 57% | 51% | 44% | 40% |
| After | **12%** | **7%** | **14%** | **20%** | **24%** |
| 3+ chains before | 103 | 509 | 469 | 359 | 311 |
| 3+ chains after | 13 | 11 | 31 | 69 | 111 |

The long staircases collapse fastest, which is the right shape — a lone zigzag is a moment of
pressure, four in a row is unreadable.

`zigzag_keep` is the fraction **kept**, and like `shallow_keep` it is **not** the share that
survives: one opened wall often resolves several neighbouring zigzags at once, so the response
is steep and non-linear. At 0.35 the pass wiped out essentially *all* of them. **Set these by
measuring with `ZigzagProbe`, never by writing the share you want.**

**They still exist, deliberately.** At zero every corridor reads as an escape hatch and the
maze loses the moments of real pressure the ramp is supposed to create.

**Side effect worth knowing: this raises the equilibrium speed.** §5.3 settles speed where
ramp-gain equals turn-cost per second, and that formula is linear in the turn ratio — fewer
forced corners means a lower ratio. Measured on a full `RunTest` autopilot, final speed went
**4.45x → 5.13x** with solve time roughly unchanged (~273s). If the knob moves again,
re-derive rather than re-guess.

### One-cell stubs are a separate knob from dead-end density

A **stub** is a dead end whose single opening leads straight back to a junction: the
player turns in, crosses one cell, and must immediately 180 back out. It carries no route
to misread and no decision to get wrong — it just taxes a reversal.

Measured on the original parameters, stubs were the *majority* of all dead ends in mazes 2
and 3 (212 of 316, and 247 of 348), which made the 180 the most common thing a player did.
That is the wrong shape: §11.2 wants bad routing punished by distance and time, and a stub
is neither — it is a reversal toll.

They need their own generation stage because the two knobs otherwise **compete for the same
removals**. Maze 3's density target (324 cells) sits barely under what carve-plus-braid
leaves (337), so ordering the density pass to drain stubs first gave it only 13 removals to
spend and cleared almost none of them. Culling stubs in a dedicated pass first, then
letting density tuning take whatever is still over target, is what actually works.

`shallow_keep` is the fraction of stubs *kept*, and it is **not** the share that survives —
see §8. Tuned against `DeadEndProbe`, the five mazes run 0.15 / 0.20 / 0.12 / 0.11 / 0.10.
Keeping some matters: at zero the maze reads as uniformly safe, and the occasional stub is
what stops the player trusting every opening blindly. **It was the frequency that was
wrong, not the existence.** Measured after the cull (8 seeds each):

| | dead ends | stubs | stubs beside the solve path |
|---|---|---|---|
| Maze 1 | 90 (2.5%) | 0 | 0.0 |
| Maze 2 | 156 (2.8%) | 53 | 1.6 |
| Maze 3 | 188 (2.3%) | 87 | 2.3 |

`DeadEndProbe.gd` is the instrument; re-run it after touching either knob.

### The distance field is the important part

Store BFS-from-exit distance for every cell, not just the canonical path. This is what
makes the Path Indicator (§7) correct in a looped maze: the indicator points along
whichever direction **decreases distance-to-exit from the player's current cell**,
recomputed live. A baked canonical path would give nonsense the moment the player steps
off it — which, in a maze full of loops, happens constantly and is often the correct play.

**Seeding:** every maze generates from an explicit seed, and the run seed is stored. This
makes bugs reproducible and makes a future daily-run mode nearly free.

### Landmarks make a looped maze legible

Randomly generated decorative structures — spires, monoliths, trees, arches, rings,
rubble — placed through the maze so a corridor has an identity beyond "corridor". Full
spec in `docs/specs/landmarks.md`.

**They answer "have I been here before?", never "which way should I go?"** Placement
ignores the solve path, the distance field, the gates and the exit entirely, and nothing
about a landmark's type, height or colour correlates with any of them. That line is the
whole reason the feature is safe: Path Indicator, Gate Compass and Golden Trail are all
*paid* lines sold on answering "which way", and free scenery that hinted at the route
would cannibalise three upgrades at once. This is the line the wall indicator held too,
before it was removed in favour of the landmark itself (§5.6).

Recognising a landmark is worth something only because the player remembers what they did
last time they saw it. That is player-supplied knowledge, not a given answer.

The problem it fixes is real and gets worse with the escalation levers: §8 makes loop
density "the most interesting knob", and §11.2 wants bad routing punished by distance and
time. Both assume the player can *notice* they have looped. In a 25%-braided 90×90 maze of
uniform corridors they cannot — a re-crossed junction is indistinguishable from a fresh
one, so the punishment lands without the lesson.

**Two tiers, answering different questions.** *Local* landmarks stay under the wall line
and are seen only from the corridor they sit in, so they make one junction recognisable.
*Skyline* landmarks tower over the walls and make a whole region recognisable.

**Skyline landmarks are seen as spires past the wall tops, never from above.** The camera
is capped below `WALL_HEIGHT` on purpose (§12), so a landmark earns distant visibility by
being tall itself, from a low eye. Only its *upper* portion is ever seen far off, which is
why each skyline type is shaped to be identifiable from its top alone. Measured: at 1.5×
`WALL_HEIGHT` a landmark satisfies "clears the wall" and still fails the purpose — a few
pixels of top edge through fog. They sit at 3–4× instead.

**Never in a cell the player drives through.** Collision is deliberately not modelled —
the barrier and crash rules are defined against maze walls only (§5), and a second class
of solid thing would mean two collision systems disagreeing at speed. So landmarks go only
in sealed pockets, at the far end of dead ends, and outside the boundary.

The dead-end case is the most valuable: §6 makes dead ends the punishment for a misread,
and a dead end with a statue in it is a punishment the player *remembers*. Turning around
at the same broken pillar twice is unambiguous evidence of a re-tried route.

**Density is a per-maze knob (`landmarks` in `Tuning.MAZES`), not a parallel array.** An
array indexed by maze number goes stale the moment a maze is added — the same failure as a
test restating a tuning number (§12). A first pass scaled density down hard as mazes grew
and measured 0.19 landmarks per 100 cells in maze 5: a player could cross the biggest,
loopiest maze and never meet one, switching the feature off exactly where it is needed
most. `LandmarkProbe.gd` is the instrument.

**Every dead end is decorated unconditionally; `landmarks` thins only the sealed
pockets.** The two used to share one pool, so the density knob thinned both together and
left 6–16% of dead ends bare. That was survivable while the wall indicator marked a dead
end for free, and is not now that it is gone (§5.6) — the landmark is the only thing left
that tells the end of a corridor from a corridor that merely turns, and a bare one is a
reversal with nothing to remember it by, the "punishment without the lesson" failure this
whole feature exists to fix. Measured after the split: **0 bare dead ends** across all
five mazes on 4 seeds each (2,187 dead ends). Pockets stay on the knob because they are
glimpsed from outside and carry no such promise.

**Tuned high, and the late mazes RISE rather than fall.** Measured: 131–187 landmarks per
maze. The instinct to thin them out as mazes grow
is backwards, because the eligible set — sealed pockets and dead ends — does not scale with
area, so a flat fraction leaves a 100×100 maze sparse per unit of ground actually covered.
Maze 5 needs the *highest* fraction (0.95) to reach even 1.09 landmarks per 100 cells
against maze 1's 2.11. The late mazes now sit near the eligible-cell ceiling, which is the
practical maximum short of putting landmarks in corridors — which the no-collision rule
forbids.

**Colour is fixed across all mazes**, joining gates, the exit, the player marker and the
HUD (§8) — a landmark seen in maze 1 and again in maze 3 should read as the same kind of
object. The six hues sit in the gaps left by everything that already owns a colour: amber→red
amber-yellow is gates, white is the exit and the marker, green/red is
Path Indicator, and the five palettes own cyan, magenta, green, ember and violet. **That
reserved list runs in both directions** — a future colourway in deep blue would put the
spire's hue on every wall.

**Emission is tuned between two measured failures**, not guessed. At 0.55 a skyline
landmark four cells out was a grey speck, because fog sits between the camera and
everything. At 1.25 one filling a dead end blew out to flat white — the silhouette, which
is the entire way a landmark is recognised, was lost exactly where the player is closest to
it. Silhouette is now the entire dead-end read (§5.6), so blowing it out is not a cosmetic
loss.

**Nothing in the simulation may read a landmark.** Movement, turn resolution, the buffer,
the barrier, penalties and the distance field behave identically whether landmarks exist or
not. Placement runs on its **own RNG stream** — sharing the carve's generator would mean
the density knob silently redrew every maze, since each extra draw shifts the whole
downstream sequence — and it runs **last**, after every wall-knocking stage, because the
dead-end passes open walls and a cell that was a sealed pocket mid-pipeline may not be one
at the end.

`RulesTest` asserts the separation directly by driving two racers side by side on the same
seed, one maze decorated and one not, and requiring they never diverge. This is the failure
mode hardest to notice: landmark data hangs off the `Maze`, so it is *reachable* from the
rules layer even though it must never be *used* there — the same trap lanes have (§12).

`LandmarkShot.gd` is the visual check, and it **seeks a landmark** rather than shooting on
a timer, for the reason `PaletteShot` seeks a junction.

---

## 7. Upgrades

### Delivery: Gates

Upgrades come from **gates** — physical archways placed on the canonical solve path, **8
per maze**.

Eight rather than five: at five, a three-maze run handed out 15 picks against nine upgrade
lines, so a build barely got past one rank in the lines it cared about and the cards stopped
being a *choice* between strategies and started being a scramble to start anything at all.
Twenty-four picks was enough to actually max two or three lines and feel the compounding that
§7 is built around, while still being far short of taking everything.

**That capacity problem is now settled: the tree grew.** Forty gates against a tree holding
38 total ranks used to mean a clean run maxed *everything*, with the last picks having
nothing left to take — which broke the §11.5 promise that upgrades change *decisions*, since
if every line ends maxed the choice was only ever about ordering.

It was deliberately **not** fixed by cutting gates per maze. Gates are also the pacing beat
and the timer pause, so thinning them would have changed the rhythm of a maze to solve a
problem in the upgrade tree. Instead the tree was grown on both axes at once — three new
lines (Cornering, Expiry Grace, Repair Field) and higher `max_rank` on the four lines that
could carry it — which fixes the shortfall *and* adds real choices rather than just deeper
stats.

The ledger now runs **45 picks against 48 ranks**: 40 gates plus the five loadout picks
below, against a tree that can absorb slightly more than a perfect run collects. Measured on
a full `RunTest` autopilot, the finishing build has genuine gaps in it — Path Indicator 3 and
Minimap 2 on one seed, Buffer Window 6 and Expiry Grace 1 on another — so the last pick is
still a decision. `RunTest` prints a `note:` line if that inverts again; it no longer does.

### Every maze opens with a loadout pick

**The start of each maze is a pick, before the racer has covered any ground.** Five per run,
one per maze, on top of the eight gates.

A maze used to open with whatever build the previous one ended on, so arriving somewhere new
— which §8 wants to read as *arriving* — came with no decision attached. The player crossed a
threshold into a new grid size, a new palette and a new braid factor, and their only input
was to keep driving. A pick on entry means every maze starts by asking what you want to be
for it, which is when that question is most interesting: the maze's character is on screen
and none of it has been driven yet.

**It reuses the gate card screen exactly**, with only the title changed — `THE TANGLE —
CHOOSE YOUR LOADOUT` against `GATE 3 — CHOOSE AN UPGRADE`. The player already knows how to
read three cards and press 1, 2 or 3; a second interface saying the same thing in a different
shape would be two things to keep in sync for no gain. The *moment* still reads as distinct,
because the title names the maze rather than a gate number.

Everything a gate pick does, the loadout does: the timer stops, the minimap blurs, the world
stays visible behind the cards. The blur matters for the same anti-abuse reason §7 gives —
a paused zoomed-out map at the mouth of an unexplored maze is the most valuable free solve in
the game, not the least.

**The maze-name banner gives way to it.** The HUD used to announce the maze name on the same
frame, which drew the name twice in two sizes, overlapping. The banner is the decoration and
the title is load-bearing, so the banner is suppressed when a loadout opens.

**The trailer is exempt**, gated on `trailer_seed` — the same flag that already suppresses
the HUD banner, for the same reason (§9b). The reel calls `_start_maze` five times in thirty
seconds against pre-built upgrade sets, so a card screen on every cut would bury the reel in
modal UI it never asked for.

One consequence worth knowing for anything that drives the game: **a run now boots into
`UPGRADING`, not `RACING`**, and steering is correctly inert until a card is taken. Every
harness and every shot tool takes the first card offered before driving. `SceneTest` asserts
the new contract directly — boots on the pick, races once it is taken.

**Why gates rather than distance-travelled:** gates sit on the optimal route, so
collecting them *is* engagement with the solve. A player who routes well reaches them
faster and with more clock left. Distance-travelled would reward aimless wandering, which
is precisely backwards.

### Gates rise above the wall line

The gate marker is **taller than `WALL_HEIGHT`**, so it is visible over the walls from
several corridors away rather than only once the player is already in its corridor.

It was 0.9× wall height — just *under* the walls — which meant a gate gave no warning at
all. At a speed where a cell passes in 125ms, "you can see it once you are in the corridor
with it" is not a warning. Seeing one coming is the entire reason a gate is a physical
object in the world instead of a HUD readout: it sits on the solve path, it pauses the
timer, and it is the thing the player is routing *toward*.

This is the same argument the skyline landmark tier rests on. The camera is capped below
`WALL_HEIGHT` on purpose (§12), so **height is the only way anything becomes visible from
the next corridor over** — raising the camera instead would flatten the maze into a floor
plan.

**The exit stays taller than a gate** (2.6× vs 1.85×). Now that both clear the walls,
height is what separates them at distance: a gate is a waypoint, the exit ends the maze,
and mistaking one for the other at speed is a real routing error. Colour separates them up
close (amber-yellow vs white).

**The marker is two crossed slabs, not one.** A single flat slab is nearly invisible
edge-on, so a gate approached down a *perpendicular* corridor showed as a thin vertical
sliver — which is exactly the approach that most needs the warning, since a gate straight
ahead is already obvious. Crossing them guarantees a broad face toward the camera from any
angle.

`GateShot.gd` is the check: it shoots from 2.5–6 cells out, because the question is not
"is there a gate here" but "can I see it coming".

### Gate behavior

1. The player passes through the arch.
2. **The timer pauses.**
3. Three upgrade cards appear. The player picks one.
4. **The 3D world stays rendered and visible behind the cards** — the player sees exactly
   as much of the corridor as they did at the moment of passing. This is intentional; it
   is not scouting, it is just not blacking out the screen.
5. **The minimap blurs heavily during selection.** This is the anti-abuse measure: a
   paused, static, zoomed-out map would otherwise let the player solve the entire maze at
   leisure at every gate. Blur it hard enough to be genuinely unreadable.
6. Selection made → cards dismiss → minimap unblurs → timer resumes.

### A taken gate stays, dimmed — in the world and on the minimap

A cleared gate **recolours to a cool blue** rather than disappearing. The world marker keeps
its silhouette at reduced glow, and the minimap paints its cell blue where a live gate is
amber.

**It used to be deleted outright, and that threw away the best landmark in the game.** The
marker is deliberately taller than the wall line (§7), so it is visible from several
corridors away — which makes a spent gate the most recognisable object the maze has, and it
sits on the solve path, so its position is meaningful rather than incidental. Deleting it
meant a corridor the player had demonstrably driven looked exactly like one they had never
seen.

That is the problem §6 gives landmarks to solve, arriving through a different door. Loop
density is called "the most interesting knob" and §11.2 wants bad routing punished by
distance and time — both assume the player can *notice* they have looped. A gate they
already opened is the least ambiguous possible evidence.

**It answers "have I been here", never "which way".** That is the same line landmarks sit
on, and it is what keeps this from cannibalising Path Indicator, Gate Compass and Golden
Trail: the marker records the player's own history, which is knowledge they already had and
merely could not see. It adds nothing about the route ahead.

**Blue, and not a dimmer amber.** A spent gate that was merely a faint amber would read as
a live one seen far off through fog. It must also stay clear of **white**, which is the
exit: mistaking a cleared gate for the exit is a much worse error than mistaking it for a
live one. A first pass at a desaturated blue-grey rendered nearly white against the night
sky and had to be deepened toward blue; **that only showed up in a rendered frame.**

**The minimap's blue is brighter than the world's, deliberately.** The two are read against
opposite backgrounds — the marker against a near-black sky, the map cell against wall strokes
that are *already* blue. Matching the hue is what makes them read as the same thing; matching
the value would have made the map cell vanish into the strokes around it.

**A spent marker starts above the camera** (`GATE_SPENT_BASE`) instead of at the floor. The
marker is transparent and drawn double-sided, because the player passes *through* a gate — so
one still reaching the floor puts the eye inside it on every re-crossing and **washes the
whole screen its colour**. That was invisible while the marker was deleted on the spot;
keeping it made it permanent. Raising the base loses only the part at eye level, which on a
cleared gate is not a doorway any more, and keeps the part above the wall line that does all
the work.

`GateSpentShot.gd` is the instrument. It **seeks a gate** rather than shooting on a timer,
for the reason `GateShot` and `PaletteShot` do, and it shoots three frames per gate: before,
after, and a **look back** from two cells on. The look-back is the one that matters — facing
away from a marker says nothing about how it reads, and the first two attempts at this
change both looked fine from in front while being wrong from behind.

> Aiming a camera for a shot has to fight `Game._process`, which re-frames every tick.
> `process_frame` fires *before* a node's `_process`, so aiming and capturing in one frame
> gets the aim overwritten in between — producing a forward-facing frame that looks exactly
> like the feature having failed. Stop the game, aim, and capture on the *next* frame.

### Upgrade lines

Upgrades **carry between mazes** within a run. They do not persist across runs — v1 has no
meta-progression (§10).

| Line | Effect | Notes |
|---|---|---|
| **Path Indicator** | A **strip across the floor of each gap** at a **T**: **green** optimal, **yellow** a longer route that works, **red** leads nowhere | The headline upgrade. Uses the live distance field (§6). Later ranks: earlier warning, more lookahead |
| **Minimap** | Circular minimap centered on the player | Each rank **zooms out** — more maze visible. Blurs at gates |
| **Buffer Window** | +0.15 cells of turn buffer per rank | The pure quality-of-life line; makes sloppy input viable |
| **Fast Turnaround** | Reduces 180° cost: −0.75x → −0.55x → −0.4x → −0.25x | Makes aggressive exploration and error recovery viable |
| **Base Speed** | Raises the speed *floor* above 1.0x | Compounding — less time in the slow band after every crash |
| **Barrier Capacity** | +0.25s of wall-contact grace per rank | Directly widens the skill-expression window |
| **Barrier Regen** | Faster barrier refill | Pairs with capacity; matters most in tight twisty sections |
| **Gate Compass** | Points toward the next gate | A soft directional hint — weaker than Path Indicator, but always on |
| **Snap Turn** | Shortens the post-turn freeze: 0.10s → 0.075 → 0.055 → 0.04 | Buys back time, the currency of §8. Never removes the freeze — see below |
| **Golden Trail** | On a timer, a golden streak shoots from the player along the optimal route, travelling at 2x player speed and lingering 2s | Periodic, not continuous — it answers "where does this go" a few times a minute rather than at every junction |
| **Wall Armor** | Reduces crash HP damage by 1 per rank | Now load-bearing: death is on and wall damage scales per maze (§5.5). Subtracts *after* the per-maze scaling, so a rank is the same flat point everywhere |
| **Cornering** | Cuts the per-turn cost: 0.03x → 0.024 → 0.018 → 0.012 | Moves the §5.3 equilibrium directly, so it changes *routing*, not a stat — a Cornering build affords turn-heavy routes that would bleed an unupgraded racer dry. Never reaches zero |
| **Expiry Grace** | Shrinks the expired-input penalty: 0.5x → 0.38 → 0.26 → 0.15 | Pairs with Buffer Window into a real "press early, press often" build. Never zero — an expired press must always mean something |
| **Repair Field** | Restores 0.6 / 1.2 / 2.0 HP per second of **clean** travel | The answer to scaling wall damage. Pays for the same thing the speed ramp does (§3) and cannot be farmed: no regen while parked or scraping |

**Four lines were deepened** to grow the tree against the pick count above: Buffer Window and
Base Speed to 7 ranks, Barrier Capacity and Barrier Regen to 6. These were chosen because
they scale linearly with no tuning cliff — each rank is another +0.15 cells, +0.25x floor, or
+0.25s of grace, so a seventh rank is arithmetic rather than a new balance question.

**Fast Turnaround's card text is derived from `Tuning.REVERSE_COST_BY_RANK`, not written
out.** The hand-written strings had drifted badly — they still advertised "1.5x instead of
2.0x" long after the 180 was retuned to 0.75x (§5.3), so the cards were quoting numbers the
game had not charged for a long time. A description that restates a tuning value is the same
transcription trap §12 flags for tests, and it is worse here because the player reads it and
makes a decision on it.

### Path Indicator is a strip on the floor, across the gap

**One lit strip laid across the mouth of each opening at a junction**, on the cell boundary,
in one of three colours.

It got here in two moves. It began as three chevrons pinned to the centre of the HUD, which
was wrong in two ways at once:

- **It floated the answer in the air**, in screen space, over a junction it had no fixed
  relationship to. The player had to map a flat overlay back onto the 3D corridor rushing at
  them — at exactly the moment they had least time to do it.
- **It trained them to watch the HUD instead of the maze.** The upgrade that is supposed to
  make junctions *readable* was pulling the eye off the corridor.

Moving it into the world fixed both, but it went onto the **walls** — one panel on the far
wall of the neighbouring cell, one cell down each branch. That is a surface you read by
looking *into* a corridor, so the answer sat **past** the decision rather than on it, and
where a branch continued straight there was no far wall at all and the panel fell back to
whatever side wall existed.

**The floor strip marks the gap itself** — the thing the player is actually choosing between.
It lies on the cell boundary, which is already the timing contract the whole control scheme
runs on (§11.3), so the answer lands on a mark the player is watching anyway, and it is the
last point at which the choice is still live: past that line, the turn has been taken. Every
opening has a floor by definition, so there is no fallback case and nothing can ever float.

### Three colours, because a looped maze has three answers

| Colour | Meaning |
|---|---|
| **Green** | The optimal route — the way Golden Trail would go |
| **Yellow** | A longer way that still reaches the exit |
| **Red** | Leads nowhere: a dead end, or a pocket that only drains back through here |

**The middle colour is the point.** Red/green said "correct" and "wrong", and in a maze
braided to 30% (§8) that is a lie: most branches that are not optimal still reach the exit.
Measured across the five mazes, **VIABLE routes outnumber BEST ones everywhere** — 1,638
against 1,243 in maze 1, 9,913 against 8,386 in maze 5, with only ~120 genuinely BAD per
maze. A two-colour scheme was painting thousands of working routes red per maze.

That is not a cosmetic complaint. Telling a player to reverse out of a corridor that works
collapses the routing decision §11.2 exists to protect, and it fights the §5.3 tuning that
deliberately made the 180 cheap enough to stop punishing a misread twice.

**Only green pulses**; yellow and red hold steady. Motion is the strongest signal in
peripheral vision, so spending it on the one best answer keeps that gap findable without
being looked at directly — which is the whole reason for putting this in the world instead of
the HUD. Yellow already separates from green by hue; giving it motion too would put two
things moving and leave the player choosing between them.

**Ties come out green on both.** Two openings that each cut the distance by one are genuinely
equally optimal; `best_direction()` returns whichever it scanned first, which is an
implementation detail, not a claim the other is worse. Painting one yellow would send the
player down a route that is not slower — teaching them the colours lie.

The classification is `Maze.branch_quality()`, in the rules layer rather than the renderer,
because it is the rule behind a colour the player routes on. `RulesTest` asserts all three
cases and that a BEST branch is always as short as `best_direction()`.

**The branch search must stay bounded.** Deciding VIABLE versus BAD is a flood out from the
branch with the junction walled off, and unbounded it is O(cells) per call. That is free for
the one or two branches at the cell the player occupies, and a trap for anything sweeping the
grid: a probe classifying every junction in all five mazes **ran over six minutes with no
error and no output** before it was killed. Capped at `BRANCH_SEARCH_CELLS`, and short-
circuited the moment the flood rejoins the distance field below the junction's own value, the
same sweep takes 193–567ms. The cap also makes the answer *more* correct — a route needing
more than 400 cells to rejoin is not the "longer way round" yellow promises.

**Placement and orientation need separate assertions.** `SceneTest` checks each lit strip
lies on the boundary of a genuinely open neighbour *and* that its span is perpendicular to
the direction it marks. This is the inverse of the check it replaced — the wall panels had to
be flush against a wall face; a strip marks an opening, so a wall under it is now the failure.

> **A long gold ribbon down a corridor is the Golden Trail, not a broken strip.** At a
> junction the two look alike, and a mis-oriented strip would sit at exactly the right
> position — so it was diagnosed as a rotation bug and "fixed" twice against geometry that
> measured correct the whole time. `PathStripShot.gd` keeps Golden Trail out of its frames on
> purpose, so anything lying lengthwise in those shots is a real bug.

### Golden Trail

A golden streak fires from the player on a timer, runs forward along the
distance-field-descending route, and fades. It is **periodic, not continuous** --
that is the whole design.

| Rank | Interval | Length |
|---|---|---|
| 1 | 12s | 10 cells |
| 2 | 8s | 15 cells |
| 3 | 5s | 20 cells |

- **Travels at 2x the player's current speed**, so it pulls away and stays ahead.
  Tying it to live speed rather than a fixed rate keeps it legible: at 5x the
  player would otherwise outrun a fixed-rate streak and see it trailing behind.
- **Lingers 2s** after it finishes drawing, so a trail fired just before a
  junction is still on screen when the junction arrives.
- **Free and automatic.** No input, no speed cost. Adding a fourth key would
  break the three-input contract in section 2, and an automatic timer that
  silently taxed speed would be unreadable.

**Why it does not duplicate Path Indicator.** Path Indicator answers *this
junction, right now*, every junction, forever. Golden Trail answers *where does
this whole corridor go*, a few times a minute, and says nothing in between. One
is a continuous readout, the other is an occasional map. Taking both is meant to
be strong; taking either alone leaves a real gap.

### Legendaries

**Rare, active, and capped at one per run.** Three lines, three ranks each, each on a
cooldown and each answering a different failure the ordinary tree cannot touch.

| Legendary | Effect | Ranks scale |
|---|---|---|
| **Wall Smasher** | Crash into a wall and instead **break through it, keeping your speed**. The wall is destroyed. At the maze boundary it turns you around rather than breaking | Cooldown 45s → 30s → 20s |
| **Flying Vision** | Double-tap `↓` to **stop the world and look**: a free camera over the maze for 5s, then a countdown before play resumes | Cooldown 45s → 30s → 20s |
| **Auto-Steer** | Double-tap `↓` to hand control to the router for a burst at **2x speed**, following the distance field. Invulnerable while it runs | Duration 3s → 4.5s → 6s |

**One per run is the whole shape of the line.** These are not stronger versions of ordinary
upgrades — they are abilities, with an input and a cooldown, and the ordinary tree has none.
Taking one is a commitment to a *style* for the whole run, which is §11.5 at its strongest:
the pick changes how the player drives, not what a number reads.

**Rarity is enforced at the offer, not the take.** Once any legendary is held, no legendary
is ever offered again — the cards simply stop containing them. That is cleaner than letting a
player take a second and refusing it, which would waste a pick and read as a bug.

#### They trigger on a double-tap, and the guards matter more than the gesture

`↓` already means two things (§2): the 180, and the crash un-stick. A third meaning has to be
placed carefully or it fires when the player meant one of the first two.

- **Never while `PARKED`.** A crashed player mashing `↓` to recover would otherwise burn the
  ability at the exact moment they did not want it. Parked taps un-stick and nothing else.
- **A genuine double-180 still fires it.** Accepted deliberately: reversing twice in quick
  succession is rare, the ability is on a 45s cooldown, and adding more conditions to
  suppress it would make activation unpredictable, which is worse than an occasional early
  fire.
- **No new key.** The three-key driving contract in §2 holds — a legendary is reached through
  the input the player already has, which is why the gesture is a double-tap rather than a
  fourth binding.

**Legendaries 2 and 3 share the gesture, and that is safe precisely because of the one-per-run
cap.** They can never coexist, so the double-tap means exactly one thing in any given run.

#### Wall Smasher genuinely rewrites the maze

The broken wall is **removed from the maze**, and the distance field, solve path and minimap
are all rebuilt from it. A smash can therefore open a real shortcut, and Path Indicator, Gate
Compass and Golden Trail will route through the new hole because they read the live field
(§6).

That is the point: a wall break that left routing untouched would have the indicator pointing
the player around a wall that is no longer there — visibly, obviously wrong. Rebuilding is a
plain BFS over the grid, which is cheap at a maximum of once per 20s.

**The maze boundary is the exception**, and it turns the player around instead. Breaking the
outer wall would put the racer outside the grid, where there is no cell, no distance value and
no floor — every query downstream returns garbage. The boundary is the one wall that is
structural rather than decorative.

**A smash consumes the crash, not the barrier.** It fires at the moment a crash *would* have
happened — barrier empty, wall ahead — so it is a save, not a bypass. The barrier still drains
normally, the player still feels the scrape, and the ability turns the ending into a
breakthrough instead of a stop.

#### Flying Vision stops the clock, deliberately and completely

Both the run timer and the maze budget stop. **This makes using it on cooldown strictly
optimal**, which is a known and accepted cost — recorded here so a later reader does not
"fix" it as an oversight. The alternative considered was leaving the maze budget running so
the look-around cost multiplier the way the turn freeze costs time (§2); it was rejected in
favour of the ability being unambiguously a *relief*, which is what makes it feel legendary
rather than merely useful.

It shows **more than the minimap** — a real camera lifted over the maze, which is the one
place the §12 rule "camera height stays below `WALL_HEIGHT`" is suspended. That rule exists so
corridors feel enclosed *while driving*; Flying Vision is explicitly not driving, and the
whole ability is the reprieve from that enclosure.

The **countdown before play resumes** is not decoration. Returning a player straight to a
running simulation after five seconds of a static overhead view, at whatever speed they left,
would hand back control while they are still re-orienting. The countdown is the re-entry.

#### Rarity is a measured number, not a feeling

`LEGENDARY_DRAW_WEIGHT` is 0.04 — an unstarted legendary is drawn at 4% the weight of an
ordinary line. **Tuned against a simulation, because a run makes 45 picks and even a small
per-card weight compounds into near-certainty across a whole run.** Measured over 2000
simulated runs:

| weight | runs that see one | first sighting |
|---|---|---|
| 0.180 | 100.0% | pick 8.3 |
| 0.100 | 98.3% | pick 12.8 |
| 0.060 | 92.2% | pick 17.4 |
| **0.040** | **81.8%** | **pick 20.2** |
| 0.025 | 66.0% | pick 22.4 |
| 0.015 | 48.1% | pick 23.7 |

At the 0.18 first tried, a legendary was guaranteed and usually arrived during maze 1 — not
rare at all. Below 0.025 most runs never meet a tier carrying three whole abilities. 0.04
makes one a genuine find that reshapes the back half of a run, first seen around maze 3.

**A held legendary draws at full weight.** Upgrading the one you have should not be a
lottery — the rarity is in *finding* it, not in feeding it.

**The "guarantee a new line early" rule never offers a legendary.** That rule (§7) exists so
early picks feel like they open options; spending it on the rare tier would make a legendary
a near-certain opener and undo everything above.

#### Auto-Steer is an escape button, not a speed boost

It follows the distance field at 2x for its duration, and the player is **invulnerable
throughout**. The router takes the optimal turn every time, so it should never touch a wall —
but at doubled speed a single mistimed frame would be brutal, and an escape button that can
kill you is not one. Invulnerability makes it reliable, which is the property it is bought
for.

It is the answer to being *lost*, where Flying Vision is the answer to not *knowing*. One
shows you the maze; the other drives you out of it.

It steers by **requesting** turns rather than forcing them, so each one goes through ordinary
turn resolution and pays the ordinary turn cost. The burst is an autopilot, not a second
movement mode — a separate path would be a second set of movement rules to keep in step with
the first.

#### Traps found while building these

- **The un-stick tap leaks into the gesture.** Guarding the double-tap on `state == RUNNING`
  is not enough: the *first* tap on a parked racer un-sticks it, so by the second tap the
  racer is running and the ability fires — which is exactly the recovery mash the guard
  exists to stop. A press that un-sticks now returns immediately and clears the tap, so the
  player must press again, deliberately, once actually moving. `SceneTest` asserts it.
- **A test whose premise is "drive into a wall and crash" stops being true once Wall Smasher
  exists.** `SceneTest` takes every upgrade line before its crash check, so the racer
  correctly broke through instead. The check now puts the legendary on cooldown — the same
  shape as the §12 note about a harness inheriting the previous test's state.
- **`UpgradeScreen` only ever hid itself on a card press.** Any other route out of a pick
  left the cards rendering over live gameplay, because the screen is a `Control` that knows
  nothing about the phase machine. It now has a `dismiss()` that every exit calls.

### Score Multiplier

A non-legendary line: **+15% to points earned per rank, four ranks** (§8b).

It scales the maze subtotal *before* the time multiplier, so it compounds with good routing
rather than substituting for it — a player who takes Score Multiplier and routes badly still
banks a small number multiplied by a small number. At max rank a run is worth ~75% more.

Deliberately **not** added to the time multiplier, which is already the dominant term in the
score (§8b): a line that pushed that number directly would be a must-pick, and would flatten
the choice between it and the survival lines it is supposed to compete with.

### Snap Turn reduces the freeze, never removes it

At max rank the freeze is still **40% of base**. The freeze is what makes a corner readable
at speed (§2), so zeroing it would hand the maxed build back the unreadable pivot the freeze
exists to fix — an upgrade that makes the game worse the more you take it. What the line
buys is *time*: the freeze runs on the clock, and the clock is the score.

This is §11.5 in practice. Snap Turn changes a decision rather than a stat — it makes
committing to a turn-heavy route cheaper, which shifts routing strategy, instead of just
making a number bigger.

**Card presentation:** 3 weighted-random cards from the available pool. Never offer a
maxed line. If the player has fewer than 3 lines started, guarantee at least one *new*
line among the three — early picks should feel like they open options, not deepen one
stat.

---

## 8. Progression — Five Mazes

Upgrades carry forward. Each maze escalates **complexity**, not merely size.

| | Maze 1 | Maze 2 | Maze 3 | Maze 4 | Maze 5 |
|---|---|---|---|---|---|
| Name | The Grid | The Ember | The Tangle | The Labyrinth | The Vault |
| Grid | 60×60 | 70×70 | 80×80 | 90×90 | 100×100 |
| Braid factor (loops) | 6% | 12% | 18% | 25% | 30% |
| One-cell stubs kept | 15% | 11% | 12% | 11% | 10% |
| Zigzags kept | 62% | 56% | 62% | 70% | 78% |
| Gates | 8 | 8 | 8 | 8 | 8 |
| Measured solve time | ~54s | ~55s | ~59s | ~57s | ~56s |

Solve times are from a full `RunTest` autopilot — an optimal router, so they are a floor
rather than a target. A five-maze run takes the autopilot ~280s.

**Grid size steps by a constant 10 rather than accelerating.** The size lever is the blunt
one (see below), and with five mazes it gets used five times; a geometric ladder would have
put maze 5 somewhere absurd while adding nothing the braid factor does not add better.

### The dead-end density target is inert on the later mazes, and that is a trap

`dead_ends` reads like the main knob and mostly is not. `_tune_dead_ends` **only removes** —
it returns early when a maze is already under target. Carve-plus-braid plus the stub cull
leaves the big late mazes *below* their target, so the number does nothing there: lowering
maze 4's target from 0.036 to 0.030 and maze 5's from 0.042 to 0.032 changed the measured
output **not at all, on any seed**.

So on the later mazes the real levers are **`braid`** (more loops open more walls, which
*removes* dead ends) and **`shallow_keep`**. Density consequently *falls* across the back
half — 2.8% at maze 2 down to 1.1% at maze 5 — and that predates the five-maze ladder: the
original three had the same shape, peaking at maze 2 (2.78%) and falling at maze 3 (2.32%).

`shallow_keep` is likewise **not** the measured stub share. The cull runs before the density
pass, which then has no budget to drain what is left, so the fraction that survives runs
well above the number set. At the original 0.25/0.35 the late mazes measured 34% and 46%
stubs; the values in the table are tuned *against `DeadEndProbe`* to land at 20/22/24%.
**Set these by measuring, never by writing the share you want.**

### Each maze has its own palette

| | Maze 1 | Maze 2 | Maze 3 | Maze 4 | Maze 5 |
|---|---|---|---|---|---|
| Neon | cyan | ember (red-orange) | magenta / violet | acid green | deep violet |

Arriving in a new maze should read as **arriving somewhere**, not as the same corridor with
a bigger grid. Hue carries all of it; value and saturation stay in the same band across all
five, because brightness is already doing a job elsewhere — the barrier bar goes red when
low — and a dim maze would
make those reads land differently maze to maze.

**The order is not the order they were added.** Ember sits second and deep violet last so no
two adjacent mazes share a neighbourhood on the wheel — appending the two new hues to the end
would have run magenta straight into violet, the one adjacency in this set that reads as the
same maze twice. Green separates them instead.

**Ember is red-orange, never amber.** The gate markers are amber-yellow, so an amber maze
would put the thing the player most needs to pick out into the same hue as every wall
around them.

**A warm palette drives the ambient warm, and warm ambient reads as a lit surface.** Ambient
is mixed from the palette's `grid` colour, so ember's first grid — a bright yellow — pushed
ambient to warm-neutral where every other palette lands cool. Cool ambient on a dark wall
reads as *shadow*; warm-neutral ambient reads as *lit*, and every wall face turned milky
brown with the floor grid washed out against it. This is the §8 green-ambient failure and the
§12 "too bright" failure arriving by a third route — through the **grid colour**, two steps
removed from anything that looks like a light. The check is the sign of R−B on the resulting
ambient: every palette must land negative. Ember's grid was pulled back to a desaturated
gold, separating from the wall by *value* rather than hue.

**Fog, ambient and the headlight move with the palette.** They sit *between* the camera and
every surface, so leaving them blue pushes a cyan haze over a magenta maze and greys the
whole thing out. The recolour only half-lands otherwise.

**But ambient stays close to neutral.** At a 50/50 blend toward the maze hue, maze 3 lit
every wall face in the same green as its own neon edges and the corridor washed flat — walls,
caps and grid collapsing into one colour field with no depth left. That is the same failure
the wall-face brightness is tuned against (§12, "too bright"), arriving through the light
instead of the material.

Three things deliberately **do not** recolour:

- **Gate and exit markers.** They are navigation, not decoration — a gate must be
  identifiable as a gate on sight, not re-learned once per maze.
- **The player marker**, which is near-white. It was green, which was fine until maze 3's
  walls went green too and the thing the player steers with matched the scenery it has to be
  picked out from. White cannot collide with any saturated palette, so future colourways are
  safe against it. Scrape-amber and crash-red still read as *state* precisely because the
  resting colour carries no hue.
- **The HUD**, for the reasons in §7.

The grid lines recolour but must stay the readable thing on the floor — they are the timing
contract (§11.3), and that is the one entry never to darken for the sake of a look.

`PaletteShot.gd` renders one junction frame per maze, which is how a palette gets checked
without anyone opening the editor.

Escalation levers, in order of impact:

1. **Loop density** — the most interesting knob. More loops means more moments where the
   player is not lost but is also not on the fastest route, and cannot tell which.
2. **Dead-end density** — raw punishment for misreads; each one costs a 180.
3. **Size** — the blunt instrument. Longer runs, more sustained concentration.

**Not** a lever: one-cell stub frequency. Raising it adds reversals without adding
decisions, which reads as tedium rather than difficulty (§6).

### Timer

A run timer, always visible, pausing during gate selection **and during the maze-start
loadout pick** (§7).

It used to be *the score*, and the only thing the player fought. **Neither is true now** —
death is on (§5.5), so a run can end outright, and a real points system (§8b) has taken over
as the score. The timer's job is now to drive the **per-maze time multiplier**, which is
where it does most of its work.

---

## 8b. Score

Points, banked per maze, multiplied by how much of that maze's time budget was left.

### The awards

| Event | Points |
|---|---|
| Each second of clean travel (running, not parked) | `10 × speed` |
| Clean turn — barrier untouched | `60 × speed` |
| Scraped turn — barrier drained and escaped | `24 × speed` (40%) |
| Crash | **−1000** |
| Maze complete | subtotal × time multiplier, banked |

**Everything scales with speed**, which is what makes the §3 ramp pay off in the score rather
than only in the clock. A turn taken at 6x is worth six times one taken at the floor, so the
player who holds speed through a turn-heavy section is paid for exactly the thing that is
hard.

**A scraped turn is worth 40% of a clean one, not zero.** §11.4 calls wall-brushing the
skill ceiling and says to protect it in tuning, so scoring it as a failure would turn the
expert texture into a penalty. At 40% a clean turn is clearly better, while a scrape still
pays far more than the crash it avoided — brushing stays viable expert play rather than
becoming a mistake.

**Crashes cost a flat 1000**, about 1.7% of a typical maze subtotal, ~14% across eight
crashes. Deliberately flat rather than speed-scaled: a crash already resets speed to the
floor, so a speed-scaled penalty would charge the most at the exact moment it also removes
the ability to earn. The flat figure is a fourth cost on top of parked time, the speed reset
and the HP (§5.4), and it is sized to be *felt* without being able to sink a run on its own.

### The time multiplier

**Budget: 180 seconds per maze**, roughly 3x what a perfect autopilot needs (measured
~54–59s per maze, §8).

```
under budget:  mult = 1.0 + (seconds_left / 30)
over  budget:  mult = 1.0 - (seconds_over / 120),  floored at 0.20
```

**Asymmetric on purpose.** Leftover time is rewarded steeply (÷30) because that is the
routing skill the score exists to measure; overtime decays gently (÷120) because a hard
penalty there flattens every slow run onto the floor, and two runs that both score 0.20x are
indistinguishable no matter how differently they were driven. The floor is 0.20 rather than
0 so a badly-overrun maze still banks *something* — points already earned should not
evaporate entirely.

**Why 180s and not the 7 minutes first proposed.** At 420s a perfect run banks ~360 leftover
seconds and so does a mediocre one; the multiplier stops discriminating and becomes a flat
inflation of everyone's score. 180s puts a good human run at 60–100s left and a sloppy one
near zero, which is the range where the multiplier actually measures something.

### The hard part: wandering must not outscore optimal play

**This is the trap the whole design had to be built around, and the naive version fails it.**

A per-turn award looks like it rewards skill, but turn count is a property of the *route*,
not of the driver: a lost player covers more ground and therefore makes **more** turns. On a
modelled maze the optimal route is ~165 turns and a badly-routed one ~429. Per-second income
compounds the same way — driving longer earns longer. So a scoring system built the obvious
way pays the *worse* player more, and no amount of tuning the award sizes fixes it, because
every award moves in the wrong direction together.

Measured across the parameter space: with speed-scaled per-second points and per-turn awards,
the best achievable margin for a perfect run over a merely-great one was **1.05** — a coin
flip — and only at multiplier settings so steep they flattened everything else.

**The time multiplier is what has to overcome it**, and it has to be strong enough to beat a
~2.6x detour. At ÷30 it is, comfortably:

| Run | Subtotal | Mult | Maze score |
|---|---|---|---|
| Perfect router (55s, 5.5x) | 57,475 | 5.17x | **296,954** |
| Great (90s, 5.0x) | 64,989 | 4.00x | 259,956 |
| Good (120s, 4.0x) | 58,656 | 3.00x | 175,968 |
| Scrappy (150s, 3.0x) | 47,387 | 2.00x | 94,774 |
| Struggling (200s, 2.0x) | 34,492 | 0.83x | 28,743 |
| Bad (260s, 1.5x) | 28,610 | 0.33x | 9,537 |

Note the perfect run's subtotal is *lower* than the great run's — it made fewer turns and
drove for less time — and it still wins by 14% on the multiplier alone. **Faster is always
better, monotonically**, which is the property the system exists to have. Spread from best to
worst is ~31x.

> If any award size or the budget moves, **re-check monotonicity** rather than assuming it
> survives. It is not a property of the numbers being sensible; it is a property of the
> multiplier being strong enough, and it broke in every naive configuration tried.

### Death scores what was actually achieved

A run that ends on HP 0 (§5.5) keeps every banked maze. The maze in progress scores:

```
subtotal × (gates_taken / gates_in_maze) × time multiplier
```

**Gates are the progress measure because they are already the maze's own milestones** — 8 of
them, evenly spaced along the solve path (§7), so "5 of 8 gates" is a real statement about
how far through the maze the player got, and it needs no new tracking. Distance travelled
would reward wandering for exactly the reasons above.

The time multiplier still applies, which means dying *slowly* scores worse than dying at the
same point *quickly* — consistent with every other part of the system.

### Implementation notes

**`Score` is pure logic, like `Racer`** — node-free, renderer-free, headlessly testable
(§12). `Game` feeds it events; it never reads the world. `RulesTest` asserts the awards, the
multiplier's shape, banking, partial banking, and — most importantly — **monotonicity across
a spread of six modelled runs**, so a future tuning change that re-inverts fast-versus-slow
fails a test rather than shipping.

**The subtotal may go negative from crashes, and is clamped only once, at banking.** Clamping
per crash would make crashes free the moment the subtotal hit zero — exactly when the player
is doing worst and least deserves the discount. Clamping at bank time means a wrecked maze
banks zero but can never eat the scores of mazes already completed.

**A scraped turn is identified by `Racer.last_turn_scraped`, not by reading `scraping`.** The
scrape-escape path clears `scraping` *before* pivoting, so a listener on `turned` always sees
false and every escape would score as a clean corner. The flag is recorded at the moment of
the turn. This keeps the rules layer ignorant of scoring — it records what happened, and the
score decides what that is worth.

**The HUD shows the projected total, not the banked one**, so the number on screen is always
the score the player actually has, including the maze in progress at its current multiplier.
Beside it sits the live multiplier and the budget countdown, which **goes negative rather
than stopping at zero** — a countdown that floors at 0:00 hides how far over the player is,
and how far over is precisely what the shrinking multiplier depends on. It turns amber
inside the last 30s and red once over.

**Measured on a full `RunTest` autopilot: 452,947** across five mazes, with per-maze
subtotals rising (7,913 → 24,344) as speed climbs and multipliers nearly flat (5.43 → 5.05)
because an optimal router solves every maze in the same narrow band. **The flat multipliers
are not the knob failing** — verified separately, the same subtotal banks 283,333 at a 40s
finish and 10,000 at 320s, a 28x spread. The multiplier discriminates on *time*, and an
autopilot simply does not vary its time.

---

## 9. Build Order

Build in this order. Each phase should be playable before the next begins.

**Phase 1 — Movement feel.** Hand-authored 10×10 test maze, no generation. Grid-locked
forward movement, the three inputs, pending-turn resolution, visible grid lines,
first-person camera. *Goal: turning at a junction feels crisp.* **Do not proceed until it
does** — everything else is built on this.

**Phase 2 — Speed and penalties.** The ramp, cap, floor, turn costs, the barrier, wall
contact, crash/park/un-stick, slowdown on expired input. HUD: speed, barrier, HP. *Goal:
the speed/risk tension is legible with no maze complexity at all.*

**Phase 3 — Generation.** DFS carve, braiding, BFS solve, distance field, dead-end tuning,
seeding. Full 60×60. *Goal: a real maze that is solvable and genuinely loops.*

**Phase 4 — Gates and upgrades.** Gate placement, pause, card UI, the upgrade system, all
nine lines. *Goal: a complete single-maze run.*

**Phase 5 — Full run.** All five mazes, escalating params, upgrade carry-over, run timer,
completion screen.

**Phase 6 — Feel and polish.** Neon aesthetic, bloom, speed-scaled FOV, motion streaks,
audio (engine pitch tracking speed is the single highest-value cue), crash shake, minimap
rendering and blur.

---

## 9b. The Menu and the Trailer

Full spec in `docs/specs/trailer.md`. The design decisions worth keeping here:

**The trailer is seeded from a checked-in constant, never the clock.** It is the first
thing a new player sees, so a reel that generated a fresh maze each time would sometimes
open on a blank corridor and sometimes drive into a dead end on camera. This is the same
"did we get lucky" failure §12 flags for tests, and it matters more here because there is
no second take.

**Each segment carries its own pre-built upgrade set and opening speed**, rebuilt from
scratch rather than carried forward. The reel is *cut*, not continuous, so a segment is a
statement about what that maze looks like with that build — carrying ranks forward would
make the later entries depend on the order the earlier ones happen to be written in. Maze 1
shows the bare game; maze 5 shows Path Indicator strips, a wide minimap and the Golden Trail
at 6.4x, because a trailer that showed the last maze with a rank-0 HUD would be advertising
the wrong game.

**A gate segment cuts to just short of a real gate.** Gates sit at even intervals along the
solve path (§6), so the first is far more than five seconds of driving from the start — a
reel that waited for one would spend its whole runtime in plain corridor. The racer is
placed a few cells back and drives into a genuine gate cell, so nothing about the gate
itself is faked; only where the segment starts.

**The caption sits in the lower third, never centred.** Centred, it lands exactly on the
corridor vanishing point, which is where the Path Indicator strips, the Golden Trail and the
wall indicator all draw — the reel would have been captioning over its own subject matter,
hiding the upgrades the later segments exist to show.

**The trailer adds no rules.** It drives the real `Game` through its ordinary public
surface with the same distance-field autopilot `RunTest` uses, and nothing in `Racer` knows
it exists.

---

## 9c. Music

Full spec in `docs/specs/music.md`. The decisions worth keeping here:

**One autoload, because `Shell._swap` frees the entire live child.** A player
parented under the menu or the game dies with it on every mode change, which
restarts the track from zero each time the player presses a button and cuts the
audio dead at the swap frame. `Music` sits above the shell and is never freed,
which is also what lets "the same track across a transition does not restart" be
expressible at all — it needs one player that remembers what it is playing.

**A track is named by the thing that plays it, never by a parallel array.** A
maze names its track in its own `Tuning.MAZES` entry, exactly as it names its
`landmarks` density and for exactly the reason in §6: an array indexed by maze
number goes stale the moment a maze is added, and it fails *silently* — maze 6
reads index 5 of a 5-entry array and plays nothing, with no error. The menu and
trailer name theirs as constants on `Music`, since neither is a maze.

**All five mazes share one track today, and that is placement, not design.**
There are two tracks in hand. Point a maze at a different name and it plays it.

**Looping is set in code, not in the `.import` file.** Godot's mp3 importer
defaults `loop=false`, so every track added would need its import file hand-edited
— a per-file step whose failure mode is music that simply stops a minute in with
no error anywhere. `Music` sets it on the stream at load, so anything dropped in
the table loops because it is music. The stream is `duplicate()`d first: `load()`
returns a shared cached resource, and both players can hold the same file
mid-crossfade.

**Pause ducks; it does not stop.** Music continuing quietly says the game is held
rather than gone, and a volume change keeps the track's position where a stop
would lose it. This is the one audio behaviour tied to a game rule — it hangs off
the same `_set_paused` that blurs the minimap (§2).

**Nothing in the simulation may read `Music`.** Movement, turn resolution, the
buffer, the barrier and the penalties behave identically with the audio server
absent, which is what `--headless` gives every harness. Same separation landmarks
have (§6): the rules layer can *reach* the autoload and must never *use* it.

**The trailer keeps its own track across its cuts.** `Game._start_maze` requests
the maze's music, and the trailer calls that method five times in thirty seconds
— so the call is gated on `trailer_seed`, the same flag that already suppresses
the HUD maze banner for the same reason.

---

## 9d. Mobile Controls

On-screen pads so the game is playable on a phone, toggled from the main menu.

**The pads add no rules.** Each one calls the same `_on_turn_input` /
`_on_reverse_input` / `_on_pause_input` on `Game` that the keyboard path calls —
which is why the keyboard branches were pulled out of `_unhandled_input` into
named methods rather than the pads getting their own copy. The phase gating lives
in those methods now, so a tap and a key press cannot diverge on it. That is the
part that would have rotted silently: a pad that still turned during an upgrade
pick would be driving the racer while the timer is stopped, and no harness driving
only the keyboard would ever see it.

**Two pads and a pause, mirroring §2 exactly.** Left and right steer; there is no
accelerator or brake to add, because speed is systemic. Pause gets a pad despite
§2 calling it "not a fourth driving input" for the reason that section already
gives: it steers nothing, it is the same category as closing the window, and on a
phone there is no `Esc` key to fall back to.

**The 180 is left and right together, not a pad.** It had its own pad, and that pad
sat in the middle of the bottom edge — directly under the player marker and the
corridor vanishing point, which is where the Path Indicator strips, the Golden
Trail all draw. A control parked over the thing it is
helping you read is the mistake the HUD chevrons made (§7), and the trailer caption
avoids for the same reason (§9b).

**The first press turns; the second completes the chord.** The obvious alternative
— hold both presses briefly and see whether a chord is forming — was rejected on
the buffer maths. The buffer is 1.0 cells (§4), which at the 10x cap is 100ms, so
any hold long enough to detect a chord would spend a large fraction of the entire
forgiveness window on *every* turn, and worst exactly where the game is hardest.
Turning first costs the common case nothing.

The price is that a chord also fires one turn on the way in, and that is the right
way round: a 90 is nearly free at −0.03x (§5.3) and the racer is pivoted rather than
moved, so the stray turn is cheap and immediately undone by the reversal. Charging
every ordinary turn a fraction of its buffer to avoid it would be a far larger and
constant cost.

**The chord is mobile only.** The keyboard keeps `↓` and never acquires a
left+right gesture — pressing both arrows at once on a desktop is an ordinary
accident, and it must stay two turns. This is free rather than enforced: the
gesture lives entirely in `TouchControls`, which does not exist when the pads are
off, and the keyboard reaches `_on_reverse_input` directly. `ShellTest` asserts it
with the pads switched off, since a later refactor that moved chord handling up
into `Game` would break it silently.

**Held state must be cleared, or the chord latches.** A finger that slides off a pad
before lifting may never deliver its release to that pad, which leaves a direction
held and turns *every later tap* into a reverse. Releasing clears it, and hiding the
overlay clears whatever is left — the failure is invisible until the second gesture,
so `ShellTest` asserts a lone press is a turn again after a chord.

**A pad fires on PRESS, not release**, so it is a `Panel` rather than a `Button`.
A `Button` emits on release, and at 8x a cell is 125ms — a press-to-release round
trip is a meaningful fraction of the buffer (§4). The turn should be armed the
instant the thumb lands.

**The setting is an override, not a detection.** `DisplayServer.is_touchscreen_available()`
picks the *default* only. Making it the switch would leave a phone player no way to
recover if the probe read wrong, and would give a desktop tester no way to see the
pads at all — the pads handle mouse clicks as well as touch for exactly that reason.

**`Settings` is an autoload for the same reason `Music` is** (§9c): `Shell._swap`
frees the entire live child on every mode change, and this preference is set on the
menu and read by the game — the menu is freed on the way there. It persists to
`user://settings.cfg`, so the choice survives a restart.

**Writing goes through `set_touch_controls()`, never a bare property setter.** A
setter was tried and is wrong: loading from disk assigns the same field, and a
setter cannot tell a restore from a choice — it re-saved the file it had just read
and fired the change signal before the menu existed to hear it.

**Nothing in the simulation may read `Settings`.** Movement, turn resolution, the
buffer, the barrier and the penalties behave identically with the autoload absent,
which is what every harness that instantiates `Game.tscn` bare gets. Same separation
landmarks (§6) and music (§9c) have, and every read is guarded rather than assumed —
a missing preference must never be what stops the game starting.

### The pads must clear the bands the HUD already owns

Three collisions, all of them found by a rendered frame and none of them visible to
any headless assertion:

- **The left pad sat on top of the barrier and integrity bars.** The barrier bar is
  the most important element on screen (§5.1); a tap target over it is strictly
  worse than a pad an inch higher. The steering pads now stop short of the HUD's
  bottom 120px band.
- **The pause pad was drawn through the timer.** The timer is right-aligned in the
  HUD's top row and its width *changes as the run passes a minute*, so anything
  sharing that line collides with it eventually. Pause sits below the row, not
  beside it.
- **The pads ran off the bottom edge**, because a screen fraction alone does not
  bound anything.

**The pause icon is drawn, not typed.** It was `‖` (U+2016), which is a
*typographic* mark meant to sit in running text, so the font drew it at text stroke
weight and it read as two hairlines rattling around inside a 70px pad. No font size
fixes that -- scaling a hairline scales its height, not its weight -- and the pause
symbol in most UI fonts is not a text character at all. Two `ColorRect` bars give
the icon a weight chosen for the pad rather than inherited from a typeface, and they
stay crisp at whatever DPI a phone happens to have, which the web build cannot
predict. The three steering pads keep their glyphs: arrowheads are solid shapes in
the font and render correctly.

The bands are constants on `TouchControls` rather than measured off the live HUD,
because the HUD builds its layout from literals too and a queried rect is only
correct after a frame has been laid out. If either moves, both move — they are one
screen.

**Sized against the shorter screen edge, never in pixels.** The pads were a screen
fraction *capped at a pixel maximum*, and the cap is what made them unusably small
on a phone: a handset reports a large pixel viewport, so the cap won every time and
handed the smallest screen the same 260px pad as a desktop window. **A pixel is a
count, not a size** — how big it is depends entirely on the device. The short edge
is the honest reference because it is the one a thumb has to span in landscape. The
minimum is now a floor rather than a ceiling: a small window needs protecting from
a target too small to hit, while a big screen genuinely wants a big one.

**The HUD bands need the same clamp.** `HUD_BOTTOM_BAND` is 120px measured off a
desktop layout, which on a 390px-tall phone is nearly a third of the display —
reserving it whole pushed the pads clean off the bottom edge. Clamped to a share of
the viewport, the pads overlap the far left of that band on a small screen, which
costs nothing: they sit hard against the margins and the bars are only ~320px wide,
so what they overlap is the empty space beside them.

**Every icon is drawn, never typed.** The steering arrows were `◀`/`▶` and broke on
mobile for exactly the reason the pause glyph did — a character is only as reliable
as the font behind it, and the web export on a phone falls back to whatever that
device ships. A missing glyph renders blank or as a tofu box, so *the control the
player steers with can simply vanish*, on hardware that cannot be tested from here.
`Polygon2D` owes nothing to a font and scales exactly with the pad.

**The minimap moves below the player on mobile.** Bottom-left is right on a desktop
for the §12 reason — map and corridor are read together, so the map belongs near the
marker. With pads up that corner *is* a thumb, and the map would sit under the hand
holding the phone: the same argument reaching a different answer because the screen
now has hands on it. Centred under the marker keeps the short glance and is the one
part of the bottom edge no thumb occupies. It also has to shrink, and
`custom_minimum_size` must be cleared to let it — a Control cannot go below its
minimum, so the offsets are silently ignored otherwise.

The menu row has the same shape of fix — its height is derived from the button count,
because the literal `180` fitted three buttons by luck and a fourth overflowed it
outright (the §12 hard-coded-layout-band trap, again).

**`TouchShot` shoots at phone dimensions and must not write the saved preference.**
A desktop-sized shot cannot show any of the above, since every size above is derived
from the short edge. And an instrument that flipped the setting through `Settings`
persisted it to `user://settings.cfg` and left the player's own choice changed — a
later desktop `Screenshot.gd` run then came back full of thumb pads, which reads
exactly like a layout regression and is not one. It sets `pads.visible` directly
instead. **A tool must not write the state it is inspecting.**

---

## 10. Deferred — Designed, Not Built

Recorded so the architecture leaves room. **Do not implement in v1.**

### ~~Death~~ — SHIPPED, no longer deferred
HP reaching 0 ends the run. **This is now on** (§5.5), together with per-maze wall damage
scaling. Left listed here only so the change is traceable from where it was first planned.

### Hazards / bosses
Intended for later stages or as final-maze encounters. The theme is *pressure that makes the
maze itself hostile*, not a health-bar enemy:

- **The Burner** — ignites the player's trail on a delay, burning cells they occupied ~5
  seconds ago. Makes backtracking and 180s genuinely dangerous and turns loops into a
  resource. The strongest of the three: it attacks the player's default error-recovery
  strategy rather than their stats.
- **The Thief** — periodically strips a random upgrade. Creates "protect your build"
  pressure and reshuffles priorities.
- **Damaging walls** — scale wall damage past 1 so HP becomes a real constraint. The
  simplest lever, and probably the first to turn on when death is enabled.

### Meta-progression
Persistent unlocks across runs — new upgrade lines, starting bonuses, maze modifiers. Out
of scope for v1; v1 is a single self-contained run.

### Daily run
Fixed seed per day, shared leaderboard. The Phase 3 seeding work makes this nearly free.

---

## 11. Design Principles

Refer back to these when a decision is unclear.

1. **Speed is not a choice, it is a condition.** The player never asks for speed; they
   manage it. All design pressure comes from speed they did not opt into.
2. **Clean execution and correct routing are separate currencies.** Speed comes from not
   crashing. Time comes from routing well. Keep them distinct — collapsing them flattens
   the game.
3. **Grid lines are the contract.** Every timing demand made of the player must be visible
   on screen before it is demanded. The game is hard, never unfair.
4. **The barrier is the skill ceiling.** Brushing walls without crashing is the expert-play
   texture. Protect it in tuning — it is what separates a good player from a cautious one.
5. **Upgrades should change decisions, not just numbers.** Path Indicator changes how you
   read junctions; Fast Turnaround changes whether you commit or reverse. Prefer upgrades
   that shift strategy over upgrades that shift stats.

---

## 12. Technical Setup

**Godot 4.7**, Forward+ renderer, GDScript.

**Aesthetic:** retro neon / lightcycle — emissive wireframe walls on dark ground, bloom,
speed-scaled FOV, motion streaks. Cheap to render and it maximizes the sensation of speed,
which is the whole game.

**Walls have zero thickness.** They are single quads, opaque, drawn double-sided
(`CULL_DISABLED`) because with no thickness each wall is shared by the corridors on both
sides. They were solid boxes (0.5, briefly 0.7) on the theory that a flat wall shows
nothing edge-on so corridor mouths would read as slits cut in paper. Play showed the
reverse: the slab's side faces and end caps were plainly visible passing any opening, every
junction advertised the wall's depth, and the maze read as a pile of 3D blocks instead of a
clean grid. **Opacity is a material property, not a geometric one** — what thickness bought
was a visible side face, and that was the thing that looked wrong. It was also the direct
cause of the doubled-wall and banded-panel artifacts, both of which existed only because
there was a slab to decorate.

### Lanes — a lateral sub-grid

The corridor is subdivided into **5 lanes** (−2..+2, 0 being the centre line), drawn as a
dimmer, thinner floor grid beneath the cell boundaries.

**Display only.** The maze graph, turn resolution, the buffer and the barrier all still
work in whole cells, so the simulation stays headlessly testable (§12). `RulesTest` asserts
the separation directly — a lane kick must not move `cell` or `progress` — because a lane
value that started influencing movement would be invisible in every other test.

**A turn throws you wide** toward the outside of the corner, and you then **settle onto the
nearest lane line and stay there**. The kick is **one lane, eased in** — not two, and not
instant. At a two-lane kick it equalled `LANE_MAX`, so every corner slammed the marker from
dead centre to hard against the outer wall: the lateral position was binary with no middle,
the "arc" had no shape, and coming out of a corner already touching the wall meant the
barrier was draining before the player had done anything wrong. And applying it as a single
`lane += KICK` step made it a *second* snap stapled to the 90° pivot — the weight this
mechanic exists to convey is only visible if the kick takes time. One lane also leaves the
outer lane as somewhere a **second** turn the same way can take you, which is what makes the
sub-grid read as a range of positions rather than a toggle. That is the entire mechanic: a corner reads as an arc
with weight instead of an instant 90° snap. **No new input** — lane is a consequence of
turning, never something the player steers, which keeps the three-key contract in §2 intact.

**You hold your lane; the corridor does not reel you back in.** The kick originally decayed
all the way to the centre line, which meant the game was continuously pulling the player
sideways out from under themselves toward a position they never chose and could not stop.
Settling on whichever lane line the kick landed nearest makes the lateral position *theirs*
until the next turn moves it — and it gives the lane lines a job, since the player is
demonstrably **on** one rather than sliding between them.

A crash still recentres, because a crash is a hard stop and the marker should not stay
parked against the wall it hit.

Settling runs on wall-clock time, not distance: at 8x a distance-based drift would snap
back within a fraction of a cell and the kick would never be seen.

**The lane lines must stay dimmer than the cell boundaries.** The boundaries are the timing
contract (§11.3); at equal weight the floor becomes undifferentiated graph paper and the
one reference the control scheme depends on is destroyed. Tried at 0.30 emission and it did
exactly that — they sit at 0.10 with half albedo and a 0.012 half-width.

**HUD layout:** speed and maze info top-left, timer top-right, barrier/HP bottom-left, and
the **minimap centred along the bottom edge, directly below the player marker**. The map
sits near the marker because the two are read together at speed — a diagonal glance across
the whole screen costs the read the map exists to give.

**Centred finishes a move that bottom-left only started.** The map began in the top-right
and came to the bottom-left on exactly the argument above; centring applies it once more,
because the marker is *on the centre line*, slightly below the middle of the screen. The
shortest glance from it is straight down, not down and away. It also puts the map on the
axis the eye is already tracking: the corridor vanishing point, the marker and the map now
stack vertically, so checking the map is a flick along one line rather than a saccade to a
different part of the screen and back.

**Mobile arrived here first**, for the extra reason §9d gives — with pads up the bottom-left
corner *is* a thumb. Both platforms now want the same position, so the remaining branch is
about size and clearance only, never about which corner.

**The cost of centring is a collision the corner placement could never have.** The barrier
and integrity bars are hard against the left margin in the *same* bottom band, so below
roughly 890px wide the map runs over them. It shrinks to the gap, and when shrinking would
take it below a legible minimum it **slides right instead** — the barrier bar is the most
important element on screen (§5.1) and wins those pixels outright. Off-centre by a few
pixels costs almost nothing; an unreadable map centred perfectly costs everything.

`SceneTest` asserts this at **two widths**, because the wide case passes trivially — the
clamp is not even binding there, so a broken clamp would be invisible if only one size were
tested. Headless runs ignore `window_set_size` entirely (the dummy `DisplayServer`), so the
test drives `UIRoot` directly after releasing its full-rect anchors; resizing the window
looks like it varies something and does not.

**The Gate Compass had to move too**, and both edges of its gap are real: at screen centre it
lands on the player marker, and at its old offset it lands on the map. Moving it clear of one
put it squarely on the other — which only a rendered frame shows.

**The minimap rotates with the player: the direction of travel is always toward the top.**
A north-up map demands a mental rotation at exactly the moment there is no time for one —
at 8x a cell passes in 125ms, and *"the corridor on my left is the one drawn on the map's
right"* is not a translation anyone performs at that speed. Rotating means a left turn on
screen is a left turn on the map, so the map can be read the way the corridor is. This is
§11.3 applied to the HUD: a timing demand has to be legible when it is made, and a map that
needs decoding first is not.

The player arrow is therefore **fixed pointing up** and never rotates — the map turns under
it. Rotating both would double-apply the transform and leave the arrow permanently wrong.
The wall strokes rotate with their cells for the same reason: drawn unrotated they stay
axis-aligned while the cells turn, which reads as the walls sliding off the cells they
belong to.

The cost is that the maze's absolute orientation is no longer legible. That is an acceptable
trade because recognising *where you are* was never this map's job at these radii — that is
what landmarks are for (§6).

**View: third person.** The camera trails behind and slightly above a player marker — a
glowing ring with an arrow inside it, sitting on the floor. First person hid the two things
the player most needs: where they actually sit in the corridor, and which way they point.
The ring answers position and wall clearance, the arrow answers facing, and the marker
turns red as the barrier drains so danger reads without looking away from the corridor.

Four constraints on that camera, each learned the hard way:

- **Trail distance stays under one cell.** Further back and the camera lands in the
  previous cell, which is solid whenever the player just turned, sits in a dead end, or
  hugs the maze boundary. At the edge it ends up outside the boundary wall looking in.
- **Camera height stays below `WALL_HEIGHT`.** Above it the camera sees over every wall at
  once, the maze flattens into a floor plan, and corridors stop feeling enclosed.
- **Two independent anti-clip passes.** A ray march back along the camera's own yaw, plus a
  per-axis push-out of any wall slab the eye has drifted into. The march alone leaves ~0.4%
  of frames clipped, because a camera swinging through a turn also moves *sideways* into
  corners it never pointed at. `SceneTest` asserts zero clipped frames over 2000 frames of
  autopilot.
- **The marker is never obscured.** A third pass, and the only one that asks about the
  marker at all — see below.

### The player marker must never be hidden

**No wall may ever come between the camera and the player token.** It is the thing the
player steers with — it answers position, wall clearance and facing at once, and it carries
the barrier state as colour — so a hidden marker is strictly worse than an awkward camera
angle. This is a hard rule, not a preference.

The two anti-clip passes above do **not** deliver it, and the gap between them is the whole
bug: they keep the *eye* out of walls, which is a different question from whether the
*segment* from eye to marker is clear. Swinging through a corner, the camera sits in
perfectly open space while the line to the marker cuts the inside corner of the turn — so
the wall just rounded wipes across the marker for a few frames, exactly when the player most
needs to see where they landed.

**Pull in, don't slide sideways.** Sliding the eye around an obstruction changes the viewing
angle mid-corner, which reads as the camera lurching on its own, and it swings the corridor
being entered out of frame just as it is needed. Closing the distance keeps the camera on
the axis it already holds and shortens the segment until it fits the open space: the view
tightens through a corner and opens again after, which reads as hugging the turn.

**Lifting does not work here**, which is worth recording because it is the obvious next move
and the crash camera's success with it makes it look right. Walls run floor to `WALL_HEIGHT`
with no gap and the camera is capped below that, so a level sight line is blocked at *every*
height the camera can legally hold — raising the eye only tilts the view down, it never
clears the wall. (The crash camera lifts to show the player *what they hit*, which is a
different goal from seeing *past* it.) So when the normal pull-in floor is not enough, the
last resort is to close the distance the rest of the way. A very tight camera for a frame or
two is a far smaller failure than the marker disappearing.

`SceneTest` asserts **zero blind frames over the same 2000-frame autopilot** — folded into
the existing clipping loop rather than a second one, since a separate pass would double the
harness runtime to assert over identical play. It caught a real residual case at the
pull-in floor, which is what the last-resort branch exists for.

### Layout

```
project.godot
scenes/
  Main.tscn      # the Shell -- boots to the menu
  Game.tscn      # the run controller, on its own so harnesses can load it bare
audio/
  music/         # looping tracks, one file per entry in Tuning.TRACKS
scripts/
  core/          # movement, speed, generation, upgrades, run state
  ui/            # HUD, upgrade cards, minimap, menu, trailer overlay, touch pads
tools/           # launch + export scripts, godot-path.txt
docs/plans/      # implementation plans
docs/specs/      # design specs
logs/            # errors.log + history/ (gitignored)
```

**`Main.tscn` is the shell, not the game.** It used to boot `Game.gd` directly,
which left nowhere to put a menu and nowhere to launch the trailer from.
`Shell.gd` now owns exactly one of { menu, game, trailer } at a time, and the
game lives in its own `Game.tscn` — so every harness instantiates the game
*bare*, with no menu in front of it, exactly as before. A harness that loaded
`Main.tscn` would now get a `Shell` and find no `racer` on it.

### Running the game

Godot lives at the path in `tools/godot-path.txt` (currently the 4.7 build in
`~/Downloads/`). There are two launchers, and they are not interchangeable.

**`tools/launch.ps1` — development.** Uses the *console* build, because the GUI build
detaches from the console and produces no capturable stdout/stderr; error logging depends
on it.

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Quit 15
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```

Writes a full session log to `logs/history/` and extracts errors and warnings into
`logs/errors.log`. **Read that log after every run** — it is the primary feedback channel,
since Jonah is not opening the editor.

**`tools/play.ps1` — playing.** Uses the GUI build (no console window behind the game) and
**forces the window to the foreground with keyboard focus**. Launched from the desktop
shortcut via `tools/MazeRacer.vbs`, which starts it with no console flash.

> **A launched game that is not focused looks exactly like a broken one.** Started
> detached, Godot comes up behind other windows without focus, so arrow keys go to
> whatever had focus before — the game runs perfectly and appears to ignore all input.
> `play.ps1` fixes this with `AttachThreadInput` around `SetForegroundWindow`, because
> Windows refuses to let a background process take foreground on its own. Never launch the
> game for Jonah with a bare detached call.

### The desktop shortcut

`Maze Racer.lnk` on the Desktop → `tools/MazeRacer.vbs` → `tools/play.ps1`. Icon is
`tools/MazeRacer.ico`, generated by `python tools/make_icon.py` (which also writes
`icon.png` for the game window). Re-run that script after changing the icon design.

### The web build and GitHub Pages

The game is published at **https://jonahbyu.github.io/maze-racer/**, built and deployed by
`.github/workflows/deploy.yml` on every push to `main`. The workflow runs `RulesTest` and
`SceneTest` first, so a red harness blocks the deploy rather than shipping over it.

The repo is **public**, and that is a hosting requirement rather than a preference: Pages
on a private repo needs a paid plan, and the API rejects it on Free with *"Your current
plan does not support GitHub Pages for this repository."* Going public also lifted a
second block — an OAuth token without the **`workflow`** scope cannot write
`.github/workflows/` on a private repo, over git push *or* the Contents API, where it
fails as a bare 404 rather than a permission error.

`tools/deploy-web.ps1` publishes straight from this machine, bypassing CI. It is the
fallback for when Actions is broken or unavailable; the normal path is to push and let the
workflow run.

Two things about Pages that are easy to get wrong:

- **Pages does not build the first time on its own.** After first pointing it at a source,
  the build list stays empty and the site 404s indefinitely — five minutes of polling
  showed no build ever queued. `POST /repos/{owner}/{repo}/pages/builds` kicks off the
  first one. Note this applies to branch (`legacy`) mode; in `workflow` mode the deploy job
  publishes directly.
- **`build_type` decides which artifact is actually served, and a successful deploy job
  does not change it.** With Pages left on `legacy`/`gh-pages`, the CI run went green while
  the live site was still an older manual push — green checkmarks against a stale site is
  the failure mode to watch for. Setting `build_type=workflow` is what hands CI the site.

**Build outside the project folder.** OneDrive holds locks on synced directories, so
removing an in-tree `build/` fails partway with "Device or resource busy". The deploy
script builds into `$env:TEMP`; CI is unaffected.

### Headless tests

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/<Name>Test.gd
```

Six harnesses, each answering a different question:

| Harness | Question it answers |
|---|---|
| `RulesTest.gd` | Are the rules right? Generation, distance field, turn and buffer resolution, barrier, penalties, upgrades, the turn freeze, the three-way branch classification behind the Path Indicator, the zigzag cull, landmark placement, marker heights, the per-maze damage curve, HP regen and death, the score — awards, multiplier, banking and monotonicity — the legendaries, including the one-per-run cap, draw rarity, wall smashing and auto-steer, and the record of gates already taken. 293 assertions. |
| `SceneTest.gd` | Does the game boot and run? Node setup, HUD construction, signal wiring, the gate/upgrade round trip, camera clipping, wall-indicator placement, path-indicator strip placement and orientation, dead-end decoration, the crash camera, pause, landmark mesh winding, marker sight lines, the maze-start loadout pick, Flying Vision's held clocks and raised camera, the spent-gate marker, the minimap's placement at two window widths, and the gate marker names surviving a mesh rebuild. 109 assertions. |
| `RunTest.gd` | Is the game finishable? Plays a complete run through every maze in `Tuning.MAZES` on an autopilot and reports speed, time, crashes, per-maze gates, the final build, and the score breakdown per maze. |
| `ShellTest.gd` | Can a player get in? The menu boots, PLAY reaches a running game, WATCH TRAILER reaches the reel, finishing the reel comes back, the mobile-controls toggle survives the menu-to-game swap, and the left+right reverse chord resolves without latching and stays off the keyboard, and the pads scale to a phone screen. 43 assertions. |
| `TrailerTest.gd` | Does the trailer show what it claims? Every maze appears in the declared order, each gate segment opens its cards, and every segment covers real ground. 21 assertions. |
| `MusicTest.gd` | Does the music table hold together? Every declared track resolves to a real file, every maze names a track that exists, the autoload is registered and processing, and the transport crossfades, ducks and loops. 103 assertions. |

`TrailerShot.gd` is the picture half of `TrailerTest` — it renders the reel and
saves a frame per segment plus each gate moment, which is the only way to check
captions, palettes and card layout without watching it.

`RunLengthProbe.gd` reports straight-run lengths, which is how the 8-cell cap in §6 is
verified; "over cap" must always read 0.

`LandmarkProbe.gd` reports landmark counts, tier split and dead-end coverage per maze,
which is how the `landmarks` density knob gets tuned. `LandmarkShot.gd` shoots a frame
next to a landmark in each maze, seeking one rather than shooting on a timer.

`GateShot.gd` shoots each maze from 2.5-6 cells short of a gate, which is how the
above-the-wall gate marker gets checked -- the question it answers is "can I see it
coming", so shooting from on top of a gate would show nothing.

`GateSpentShot.gd` is the picture half of the taken-gate work (§7): three frames per gate --
approaching it live, just past it, and **looking back at it** from two cells on. Only the
look-back answers the question the change is about, since a marker behind the camera says
nothing about how it reads. It seeks a gate rather than shooting on a timer, and it caught
both the full-screen colour wash and the near-white first colour, neither of which any
headless assertion could see.

`ZigzagProbe.gd` reports forced-turn corners, corner-into-corner zigzags and chains of
three or more, both over the whole grid and **along the canonical solve path** — the second
is what the player actually drives through, since a maze can carry plenty of zigzags in its
backwaters and still feel clean on the route. It is how `zigzag_keep` gets tuned.

`DeadEndProbe.gd` is not a test either — it reports dead-end density and one-cell-stub
frequency per maze, which is how the two knobs in §6 get tuned without guessing.

`MusicProbe.gd` is not a test either -- it boots the real project **with audio**
and reports each player's volume and playback head across a menu -> PLAY ->
pause -> resume script. It exists because `MusicTest` runs headless with no
audio driver and so passed a system that was silent in play; only a real device
shows the fade actually arriving.

`TouchShot.gd` is the picture half of the mobile-controls work: it shoots the menu and
the pads in play, **at phone dimensions** (844x390), since every mobile size is derived
from the short screen edge and a desktop-sized shot shows none of it. Pad layout is precisely what no headless harness can check, and it
caught all three HUD collisions above.

`Screenshot.gd` is not a test — it runs the real game with rendering and saves frames to
`logs/`, which is how the visuals get checked without anyone opening the editor.

`PaletteShot.gd` is the same idea aimed at one question: it jumps straight to each maze and
shoots a frame **at a junction**, so both the per-maze palette (§8) and the floor-strip Path
Indicator (§7) are actually in the picture. It seeks a junction rather than shooting on a
timer, because a shot taken on a timer lands in a plain corridor and shows nothing of the
indicator it exists to check.

`PathStripShot.gd` aims at the Path Indicator alone, and it seeks a junction where **two or
more colours are actually on screen** — a frame showing three strips that all say the same
thing does not demonstrate the scheme. It keeps Golden Trail out of the shot deliberately:
the trail is a long gold ribbon drawn *along* the route, it looks exactly like a strip laid
the wrong way, and mistaking it for one cost two "fixes" to geometry that measured correct
throughout.

Maze generation, the distance field, buffer/turn resolution, and the penalty math are all
pure logic and **must** stay testable headlessly. Movement *feel* is not — that needs a
real run and a captured log.

Keep it that way: **the simulation layer must never require a rendered frame.** If testing
a rule needs the renderer, the rule is in the wrong place.

### Traps that have cost real time

- **GDScript has no leading-operator line continuation.** Breaking a long expression with
  the `+` at the *start* of the next line is a parse error, and it surfaces as
  "Could not resolve class X, because of a parser error" in every *other* file that
  references the class — pointing anywhere but the actual broken line.
- **A new `class_name` is invisible until the project is re-imported.** Adding a script
  with a fresh `class_name` and immediately running a harness fails with "Identifier not
  declared" — the same symptom as the missing-cache trap, but on an up-to-date project.
  Re-run `--import` after adding one.
- **A node's name is assigned on ENTRY TO THE TREE, so a name set before `add_child` is
  overwritten — and a name that collides with a node still in the tree is resolved by
  renaming the NEW node.** This is the cause of **"gates don't change colour in the other
  zones"**. `MazeMesh.build` cleared the previous maze with `queue_free`, which is
  *deferred*, so the outgoing markers were still present — still holding `Gate0`, `Gate1`…
  — while the new ones were added, and each new marker was silently renamed to
  `@MeshInstance3D@N`. `clear_gate` looks its marker up by name, so it recoloured nothing.

  **Maze 1 is the only maze it spares**, having no previous markers to collide with, which
  is exactly why every existing instrument missed it: `GateShot`, `GateSpentShot` and
  SceneTest's gate round trip all run on maze 1.

  Worse than "not found": the lookups kept *succeeding*, resolving to the **dying**
  originals. Measured on the old code — build 1 clean, build 2 leaves 6 renamed markers,
  build 3 leaves 12, accumulating per maze. So a check that only asked "did `get_node`
  return something" passed throughout. Counting **strays** is what caught it.

  Two halves to the fix, and both are worth keeping: `remove_child` before `queue_free`, so
  the name is free before it is reused; and set `name` **after** `add_child`, so the
  assignment is not thrown away. `SceneTest._check_gate_names_survive_a_rebuild` builds the
  mesh three times with no frames in between — ticking the tree between builds lets the
  deferred frees land and passes against the broken code.
- **An index into a second array is a claim that two orderings agree.** `gate_entered`
  carried `gates_taken` — a running *count* — while `MazeMesh` names its markers by the
  gate's *placement* in `maze.gates`. Found while chasing the bug above and fixed on its
  own merits, though **measured not to fire in play**: `_place_gates` walks the solve path
  in order, so a gate can only be collected by standing on that path and path positions are
  reached in increasing order however much the player loops. The count and the placement
  therefore agree for as long as every gate sits on one path — and would diverge silently
  the moment anything put one off it. `RulesTest._test_gate_index_is_placement` declares its
  gates out of order rather than hoping a driver stumbles into the case.

  The same parameter was also doing two jobs: the card header wants the count ("GATE 3"),
  the mesh wants the placement. Now separate, because a header reading "GATE 5" on the
  second pick would tell the player they had missed three.
- **Node references captured before a maze change go stale.** `_start_maze` builds a new
  `Racer` *and* a new `Maze` for each maze in the run, so a harness that grabs
  `game.racer` once and loops is inspecting an orphan from maze 2 onward. This produced a
  test failure that looked exactly like an indicator bug and cost two wrong hypotheses —
  re-read both from `game` every frame.
- **`progress` means two different things, and only one of them is a position.** Travel
  runs 0..1 between cell centres, but `_press_into_wall` pins it at 1.0 to mean "hard
  against the wall" — and interpolating *that* literally put the player a full cell
  forward, standing inside the wall, or entirely outside the maze at a boundary. First
  person hid it completely (inside a wall looking out just reads as "close to it"); third
  person showed the marker buried in the wall it was stopped at. `world_position()` clamps
  to the wall face for display while leaving `progress` untouched, because the rules
  depend on it reaching 1.0.
- **Near-plane choice is a depth-precision decision, not just a clipping one.** At
  `near = 0.05` against `far = 220` the 4400:1 ratio spent almost the whole depth buffer
  on the first few centimetres — which nothing occupies, since the anti-clip pass keeps
  the eye 0.45m clear of any wall. The starved far range made the wall bands z-fight with
  the faces they sit on, showing up as a shimmering stripe along every side wall. Both
  halves needed fixing: `near` to 0.25, and the band offset from 0.015 to 0.06.
- **A coplanar decal on a thick wall slab has no correct offset — move it off the wall.**
  The neon side band was a vertical strip on the wall face, and every offset failed a
  different way: pushed 0.06 *outside* it floated in open air, drove through perpendicular
  walls at corners and hung in space beyond them (the "double wall"); pulled 0.06 *inside*
  it was buried in solid geometry and only rendered by winning a depth fight it should
  lose, which showed up as ribbed **"panel" striping** on every wall end. Chasing the
  offset back and forth is the trap; the construction itself is wrong. The band now lies
  **flat on the floor** at the wall base, where it is clear of every wall surface in depth
  and bounded by the corridor rather than the slab — and it reads better at speed, running
  alongside the grid lines the player already tracks (§11.3) instead of competing with
  them from up on the wall.
- **Accumulating a typed array inside a nested generation loop hung generation outright.**
  The straight-run cap first built each run as an `Array[Vector2i]`, appending per cell and
  reassigning `run = []` at each break, inside a loop over every cell in both axes. On a
  20x20 maze `generate()` never returned. Rewritten to track the run as a **start index
  plus a length** — the cell list was never needed, since a run is contiguous and any
  position in it is computable — it completes instantly. Worth knowing because the symptom
  was a total hang with no error, and the obvious suspects (an unbounded fixed-point loop,
  a non-terminating pass) were both innocent; the loop was already bounded at 4 passes.
- **When a run times out, the log is not written — so you are reading the PREVIOUS run's
  log.** Three diagnoses in a row were made against stale output that looked plausible and
  was hours old. Check the log's timestamp against the clock before trusting it, or have
  the probe write to `user://` and flush after each stage, which is what actually located
  the hang above.
- **Blotchy "texture" on a wall is gradient banding, not the material.** Dark fog over
  dark wall faces in an almost-monochrome blue palette means the fog blend crosses only
  ~7 8-bit steps over the first two metres, and each step reads as a flat plateau — which
  looks exactly like a mottled texture or a transparency bug on surfaces that are in fact
  fully opaque. It is worst up close because that is where the gradient is steepest, so
  "am I too near the wall?" is the natural guess and the wrong one. **Check by toggling
  `fog_enabled` before touching the material**; if the mottling vanishes, it was banding.
  The fixes are `get_viewport().use_debanding = true` (dithers the output; this scene is
  close to the worst case for banding and wants it on) plus `fog_depth_begin` a couple of
  cells out, so the tightest part of the curve is not sitting on the nearest wall.
- **Parallel quads need real separation, not a hairline.** The wall-top cap floats over the
  slab's own top face. At 0.05 the two still interleaved at grazing angles and every
  distant wall top grew a **sawtooth fringe**; 0.16 resolves across a 90-cell maze. Same
  root cause as the near/far note above — depth precision at distance — and the same
  lesson: separate coplanar surfaces geometrically and generously.
- **A wall-clock seed makes a test flaky, not thorough.** `Game` seeds itself from
  `Time.get_unix_time_from_system()`, so SceneTest's dead-end check drew a different
  maze every run; once the one-cell stubs were culled it failed roughly two runs in three
  purely on whether the autopilot happened to meet a dead end inside 900 frames. The check
  now pins `run_seed` to a checked-in constant. A test that samples a random fixture is
  answering "did we get lucky" rather than "does the rule hold".
- **`StandardMaterial3D` has no polygon-offset/depth-bias property in 4.7.** Only
  `render_priority` (transparent sorting only), `depth_draw_mode`, and `no_depth_test`.
  Coplanar surfaces have to be separated geometrically.
- **A harness that reuses one scene inherits the previous test's state.** `SceneTest`
  runs its checks in sequence against a single `Game`, so a test that assumed the racer's
  current cell had a wall to crash into passed or failed depending on where the earlier
  tests happened to leave it. Search for the state you need rather than assuming it.
- **An unsteered racer re-crashes, so a recovery assertion has to steer.** SceneTest's crash
  check un-stuck the racer and then ran 90 frames with **no input at all** — which just
  reverses down the corridor and parks against the next wall. The camera was correctly still
  raised for that *second* crash, and the assertion read it as the first crash's recovery
  having failed. It looked exactly like a camera regression and is not one. This is the
  autopilot trap below in reverse: there the test had to *seek* a failure state, here it has
  to actively steer to **avoid** one.
- **A knob that is only ever a removal target goes inert the moment the source undershoots
  it.** `_tune_dead_ends` returns early when a maze is already under target, so on the big
  late mazes — where braiding and the stub cull have already opened more walls than the
  target allows — the `dead_ends` number does nothing at all. Two rounds of tuning it
  produced byte-identical probe output on every seed, which reads exactly like a caching bug
  or a stale log and is neither. **Check whether a stage is even binding before tuning its
  input**: one `print` of the early-return branch answers in a second what re-running the
  probe cannot answer at all.
- **A palette can wash out the lighting without containing a single bright colour.** Ambient
  is mixed from the palette's `grid` entry, so a grid hue chosen purely for floor legibility
  silently sets how every wall face is lit. A yellow grid — picked so the timing lines would
  not vanish into an orange wall — drove ambient warm, and warm ambient reads as a lit
  surface where cool ambient reads as shadow: every wall turned milky brown. The wall
  albedo was in band the whole time and was the natural suspect. **The diagnostic is the
  sign of R−B on the mixed ambient, not the wall colours**; all five palettes must land
  negative.
- **A test that restates a tuning number is a transcription check, not an assertion.**
  `check("five gates", gates.size() == 5)` failed the moment the gate count became a knob
  worth turning, and told you nothing except that two literals had drifted apart. Read the
  value from `Tuning.MAZES` and the assertion starts checking that generation *honours* the
  configuration, which is the thing actually worth knowing.
- **A solve-path autopilot cannot exercise failure states.** `SceneTest`'s dead-end
  check drove toward the exit via `best_direction`, which is optimal and therefore never
  enters a dead end — so a check whose whole subject is dead ends went from asserting a
  policy to asserting nothing, and only the "was exercised" guard caught it. A test for a punishment mechanic has to *seek* the punishment; the check now hunts
  for adjacent dead ends and turns into them. **That seeker then needed deepening too:**
  it looked only one cell to each side, and culling the one-cell stubs left maze 1 with
  only *deep* dead ends, which a single-cell lookahead cannot see at all. It now follows a
  corridor several cells while it offers no choice.
- **`set_anchors_preset()` rewrites offsets.** Calling it and then setting `offset_*` looks
  right and silently does nothing, because the preset already overwrote them. Set the four
  `anchor_*` values directly instead — or call `set_anchors_and_offsets_preset()`,
  which sets both. This put the whole barrier/HP block off-screen, and separately gave
  `UpgradeScreen` a degenerate rect that hung all three cards off the top-left corner,
  mostly out of frame. **A centred child of a Control with no rect is not centred** —
  0.5 anchors resolve against 0×0, so every offset measures from the origin.
- **Rebuilding a mesh every frame to animate it is the wrong tool.** `GoldenTrail` first
  redrew its whole `SurfaceTool` ribbon each frame to advance the head: **23ms per frame**
  for one trail, more than a whole 60fps budget on its own, and in a headless loop it
  compounded until the harness looked like it had hung. The vertex data never changes as
  the streak advances — only how much of it is visible — so the ribbon is now built
  once per firing and revealed by a shader uniform. Same picture, 1ms per 500 frames.
- **A node's `_ready` has not necessarily run when a harness calls into it.** A test that
  adds a node and drives it synchronously in the same frame hits every field still null.
  `GoldenTrail` builds lazily on first use rather than trusting `_ready`.
- **Hard-coded layout bands only look centred by coincidence.** The upgrade card row used a
  fixed ±510px span for three 320px cards; the numbers lined up by luck and would have
  drifted the moment the card size or count changed. The row width is now derived from
  `CARD_SIZE` and the separation.
- **A `Control` parented straight to a `CanvasLayer` gets no rect.** Anchors then resolve
  against 0×0 and every bottom- or right-anchored child lands off-screen. Everything hangs
  off one full-rect `UIRoot` under the layer for exactly this reason.
- **GDScript lambdas capture locals by value.** `var hit := false;
  sig.connect(func(): hit = true)` never updates `hit` — the lambda mutates its own copy,
  so the assertion silently passes nothing. `RulesTest` uses a `SignalRecorder` object
  instead.
- **A fresh clone has no `.godot/` class cache**, so every `class_name` fails to resolve
  with "Identifier not declared" — a parse error that looks like a code bug. `launch.ps1`
  runs `--import` once when the cache is missing.
- **`Start-Process -ArgumentList` does not quote array elements**, so the space in
  "Maze Racer" truncated the project path. The path is quoted explicitly in `launch.ps1`.
- **A revolved shape and a box wind in opposite directions from the same-looking code.**
  The landmark drums (spire, tree, rings) were emitted `lo0 -> lo1 -> hi1 -> hi0`, which
  reads as the obvious quad order and is **clockwise seen from outside** with +Y up and
  the angle sweeping +X toward +Z — so every revolved landmark was inward-wound while
  every box-built one (monolith, arch, rubble) was correct. Nothing looked wrong, because
  the material is unshaded; the signed-volume assertion is what caught it, reporting
  −1415 and naming the three surfaces. Same root cause as the wall-box trap below, and the
  same lesson: **winding cannot be eyeballed, it has to be asserted.** Reuse the
  divergence-theorem check for any new closed geometry rather than trusting the vertex
  order looks sensible.
- **Inverted triangle winding is invisible until culling is enabled.** The wall boxes were
  built with all five faces wound inward. Nothing looked wrong while the material was
  `CULL_DISABLED`; switching to `CULL_BACK` made every wall see-through at close range.
  `SceneTest` now asserts the wall mesh's **signed volume is positive** — the divergence
  theorem applied to the whole surface, which flips sign exactly when the winding does and
  needs no knowledge of where individual walls sit. Two earlier attempts at this assertion
  reasoned about per-cell slab geometry and were both wrong, because walls are emitted as
  each cell's N/W faces plus outer boundaries, so a cell's east wall belongs to its
  neighbour.
- **A Web export preset fails with "configuration errors" and no further detail, and
  `--verbose` adds nothing.** The message comes from two separate validators, and the one
  that actually fired was `has_valid_project_configuration()` rejecting
  `vram_texture_compression/for_mobile=true` — the project has no ETC2/ASTC import settings
  to satisfy it. The obvious suspects (missing templates, the threads variant, the PWA
  isolation flag) were all innocent, and permuting them one at a time found nothing because
  none of them was the cause. **Hand-writing `export_presets.cfg` is the trap**: the engine
  registers a fixed option list with specific defaults, and a preset that omits keys or
  changes a default away from what the project supports is rejected as a whole. The option
  list in `platform/web/export/export_plugin.cpp` (`get_export_options`) is the reference —
  read it rather than guessing, since `EditorExport` is not exposed to GDScript and the
  editor will not generate a preset unaided.
- **The web build must use the `nothreads` template.** `variant/thread_support=true` selects
  a template that needs `SharedArrayBuffer`, which requires COOP/COEP response headers —
  and **GitHub Pages cannot set headers at all**, so a threaded build fails to start there
  with a console error and a blank canvas. `thread_support=false` is what makes the hosted
  build work. Verify with `grep -c pthread build/web/index.js`; it must be 0.
- **Forward+ does not run in a browser without WebGPU.** `renderer/rendering_method.web` is
  overridden to `gl_compatibility` so the desktop build keeps Forward+ while the web build
  targets WebGL2. A per-platform override, not a downgrade — the two builds want different
  renderers and the `.web` suffix is how one project ships both.
- **The browser starts every `AudioContext` suspended, and Godot never resumes
  it.** The web build shipped completely silent while every desktop harness and
  the real-device `MusicProbe` passed, because desktop has no autoplay policy to
  violate. Measured over CDP against the live page: the context read
  `"suspended"` on load and was **still** `"suspended"` after both a click and a
  keypress — the engine exposes a `_godot_audio_resume()` internally but binds it
  to no gesture. **Nothing in GDScript can fix this**; `AudioServer` cannot see
  the context's state, so a GDScript "replay the track on first input" retry just
  restarts it into a dead context. The fix lives in `tools/web/shell.html`: a
  constructor hook in `<head>` collects each context as the engine creates it
  (`GodotAudio` is module-internal and never reaches `window`), and the PLAY
  click calls `resume()` on them. Verified back to `"running"` with the audio
  clock advancing 4.01s over 4s.
- **A silent web build is invisible to every check this project has.** The
  harnesses are headless, `MusicProbe` runs on WASAPI, and the export succeeds —
  so "it works locally and in CI" says nothing at all about whether the hosted
  game makes a sound. Driving the built page in a real browser over CDP is the
  only instrument that answers it.
- **`process_mode` says WHEN a node may process; `set_process` says that it
  should.** `Music` set `PROCESS_MODE_ALWAYS` in `_ready` and never called
  `set_process(true)`, so its fade loop never ticked and every player sat at the
  -80dB it starts at: `playing == true`, a decoded 158s stream, a live WASAPI
  device, and total silence. Nothing errors, and **no headless harness can catch
  it** — `--headless` has no audio driver, so the assertion has to be
  `is_processing()`, not anything about sound. The reason the fix is a one-liner
  and the diagnosis was not is that every *obvious* suspect reports healthy.
- **A node's `name` set before `add_child` does not stick.** Godot assigns a
  generated name on entry to the tree, so `n.name = "Music"; root.add_child(n)`
  lands the node at `/root/@Node@2`. This is silent, and it is worse when an
  autoload of the same name exists: `get_node("/root/Music")` then resolves to a
  **different, real** node, so the probe reported the music dead while the game
  was in fact playing it correctly. Set the name *after* adding, and in a probe
  that runs under the real project, look the autoload up rather than
  constructing a second copy — `--script` replaces the main scene but autoloads
  still load.
- **`--headless` proves the wiring, never the sound.** `MusicTest` passed 35
  assertions against a system that was completely inaudible. Anything about
  audio that matters to a player needs a real device and a probe that reports
  the playback head advancing; `MusicProbe.gd` is that instrument.
- **Correct outward normals make corridor interiors darker.** The inside faces then point
  away from the directional light and receive ambient only. A `DirectionalLight3D` cannot
  reach into a corridor at all; the `OmniLight3D` headlight in `Game.gd` is what gives
  nearby walls shape. Keep it dim — turned up it flattens the near wall into a colour
  field and destroys the depth it exists to create.
