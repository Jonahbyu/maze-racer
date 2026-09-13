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

**`progress` is centred on the cell centre, and that phase is the contract.** It runs
**−0.5 .. +0.5**, where 0.0 is the cell centre and ±0.5 are the two drawn grid lines
bounding the cell. So "past the line" and "in the new cell" are the same statement, and
`_travel` advances `cell` at the line — where the player watches it happen — rather than half
a cell later.

It used to run **0..1 between cell *centres***, which put it half a cell out of phase with
every line the player can see. For the whole upper half of a traversal the marker was drawn
inside the next cell while every rule still read the old one, so a press made on crossing a
line resolved against the openings of the cell just left. Measured on a maze-1 autopilot:
**75.6% of immediate turns resolved against the cell behind the marker, at a flat 0.500-cell
error every time.** In play that is exactly *"I'm across the line and it still turned me into
the previous cell."*

The flat 0.500 is what identifies it as geometry rather than timing. It is not a spread of
near-misses that a delay could shift — it is one constant half-cell offset, so **an input
delay cannot fix it**: cancelling half a cell takes 500ms at 1x and 62ms at 8x, and a fixed
delay under-corrects when slow and over-corrects when fast. Scaling it by speed just
re-derives the geometric fix badly, while breaking §11.3 (the press does nothing visible for
N ms) and fighting §4 (the buffer is in *cells, not seconds*, precisely so forgiveness does
not scale with speed).

Re-measured after the change, over all five mazes: **0 of 353 turns** resolve against the
wrong cell, and the marker is never drawn outside its own cell. One frame in 15,833 rounds to
a neighbouring cell, which is a tie exactly on a line.

**The cell in front of a wall is driven through, not skipped.** Blocked-ahead is not the
same event as *pinned against the wall*: entering that cell puts the racer at its leading
edge with a full cell still to cover, and only the far side of it is the wall face. Pressing
into the wall on the entry frame instead teleported the marker most of a cell in a single
step and then froze it there while the barrier drained — *"I get into the last cell before a
wall, it freezes, jumps to the wall and I crash there, with no movement in the last cell."*
Measured: a 3.4m jump in one frame, and 47 frames of travel lost.

Two paths did it and both had to change — `_travel`'s boundary handler, and `step`'s dispatch,
which sent any racer in a blocked cell straight to `_press_into_wall` however far into the
cell it had got. **This was masked before `progress` was centred**, because the cell advanced
at the *centre*, so only half a cell went missing rather than a whole one; centring the phase
did not cause it, it made it visible. `RulesTest` asserts the travel directly — no single
frame may move more than a few frames' worth, and the cell must take dozens of frames to
cross — because "it crashed eventually" is true of both the correct and the broken version.

**A turn on the way IN to a cell starts the new corridor at the centre.** Progress is measured
along `facing`, and a pivot changes `facing` — so a *negative* progress (still short of the
centre, which is where the racer is for the first half of every cell) would be re-read as that
distance **backwards** along the new heading and draw the marker out through the side wall.
Measured: 1.949m off a cell centre whose corridor half-width is 1.77m, which no camera
position can see past — it broke the "marker is never hidden" rule (§12) on 20–40 of every
2000 autopilot frames. Clamped to 0, not reflected: a racer turning at the mouth of a cell is,
for the new corridor, at that corridor's start. This is the same trade the scrape case records
below, and it resolves the same way — the two distances are not the same point.

**A turn pivots; it never rewinds.** Resolving a turn used to reset `progress` to 0, which
snapped the player back to the centre of a cell they had already half-crossed. In play that
read as *"I reached the new grid line, turned, and it threw me back to an old one and I
missed my turn"* — the grid lines are the timing contract (§11.3), and a turn that silently
moves you to a different line than the one you just crossed breaks it outright. The player
is at a real point in the corridor; turning is a rotation, so the distance already covered
still counts toward the next boundary.

The one exception is escaping a scrape, where `progress` is pinned to the **wall face** to
mean "hard against the wall" rather than to mean a position at all (§12, the `progress`
trap). Pivoting out of a scrape starts from the cell centre because that is where the player
actually is. The pin was `1.0` under the old centre-to-centre phase, which was a value a
whole cell forward; centred, the face is just under `+0.5` and so is already a sane position
rather than one `world_position()` has to rescue.

**That reset has to happen on both escape paths**, and for a long time it only happened on
one. A turn pressed *while already scraping* went through `request_turn`'s immediate path,
which cleared `scraping` but left `progress` at the wall pin — so the pivot interpolated that
pin down the newly-opened corridor and threw the marker **a full cell forward in a single
frame**, landing it hard against the next boundary. (The pin was literally `1.0` at the time,
under the old centre-to-centre phase, which is what made the jump a whole cell.) That is the "I turn and I'm suddenly at
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
new heading at the player's own dialled rate, and travel resumes once the view agrees with
the facing.

**The camera used to swing 3.5× faster during the freeze, and that multiplier has been
removed.** The reasoning was that a freeze the camera does not spend is just a stutter — but
measured, the cure was far worse: at the default dial the boost closed **70% of the whole
turn in a single frame**, and at dials 0–5 a literal 100%. The camera lurched almost the
entire way round on frame one and then crept through the remainder, which is precisely the
"small jolt when turning" that was reported.

**It could not be smoothed, only removed.** Decaying the boost rather than switching it off
was tried first and genuinely helped at the slow end — worst frame-to-frame slowdown 3.90×
→ 1.14× — and did *nothing* at the default, because there the lurch **is** the boost rather
than the way it ends. Measured at the default dial: 3.58× before, **1.25× after**, which is
just the natural shape of an exponential ease.

**The stutter it guarded against does not materialise.** On the plain dial rate the default
still completes **73.8%** of its swing inside the freeze, so the hold is still doing the
catching-up. The slow settings finish well after it, which is what the player chose them for.
`SceneTest` asserts no frame breaks the swing's velocity; verified by restoring the
multiplier, where it fails at `worst frame-to-frame slowdown 3.33x`.

It also pays for itself against the ramp. At 8x a corner arrives and is gone inside 125ms;
the freeze buys a **fixed, speed-independent** moment to read the new corridor, which is the
one thing the ramp otherwise takes away.

**The clock keeps running.** The freeze is a pause in *position*, not in the systemic
pressure of §3 — the speed ramp advances throughout, because a freeze that stopped it would
make cornering a way to duck the game's central mechanic. And the run timer advances, so the
freeze is a real cost in the currency §8 says the player is fighting. Snap Turn (§7) buys it
back down.

**The MARKER swings too, and it used to be the one thing that did not.** The camera eased
onto a new heading from the start; the arrow under it took `racer.facing` directly, so it
rotated 90° in a **single frame** while the view it sits in glided over many. Measured on a
maze-1 autopilot: a worst per-frame marker step of **180.00°** against the camera's 26.25°,
and 26 such flips in 2000 frames. So "the camera transition is smooth" was already true and
the complaint was still right — **what teleports is the arrow, not the eye**, and a marker
snapping under a gliding camera reads as the whole world jumping.

This is the `LANE_TURN_KICK_RATE` lesson (§12) on the rotational axis. That constant exists
because applying the lateral kick as one step made it *"a second snap stapled to the 90°
snap"* — this is the 90° snap it was stapled to, and it is smoothed the same way: by easing
a **display** value while `facing` still flips in one frame, so no rule can see it.

**The rate scales with the angle remaining, which is what makes a 180 resolve FASTER in wall
time than a 90** — 159ms against 186ms, despite covering twice the ground. A plain
exponential ease is the opposite: fastest at the start and crawling at the end, so the last
few degrees of a reversal would take as long as the first sixty, and `REVERSE_FREEZE` is only
1.6× `TURN_FREEZE` — a 180 easing at the 90's rate would still be swinging after the hold
released.

**It deliberately does NOT take `TURN_FREEZE_CAM_MULTIPLIER`.** That 3.5× exists so the
*camera* can catch up to a pivot it was not present for; the marker **is** the thing that
pivoted, so it has nothing to catch up to. Applying it anyway drove the per-frame step
straight into its own clamp — measured, a 90 closed **100% of its angle in one frame** at
every rate from 14 upward, which is the snap the whole change removes, reintroduced by the
multiplier.

**Tuned against the FIRST FRAME's step, not the total duration**, because the first frame is
what the eye reads as a snap. At `MARKER_YAW_RATE` 18 the opening frame of a 180 covered
**86°** — a near-instant half-flip wearing a smaller number. At 12 it covers 49°, and the
swing measures as a clean 22-frame deceleration: `48.6, 33.0, 23.4, 17.2, 12.9, 9.8, …, 0.2`
degrees per frame, where it was previously one 180° step.

`SceneTest` asserts it by driving real `_process` calls and reading `_marker.rotation` —
never by re-deriving the curve locally, which is the trap the camera-dial check one function
up already records. Verified by restoring the direct assignment: it fails at
`biggest step 90.0 deg of a 90 deg swing`.

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
- **Base capacity: 0.125 seconds** of sustained wall contact — halved from 0.25, which
  was itself halved from 0.5. An eighth of a second is about **eight frames at 60fps**:
  enough to clip a corner and leave, nowhere near enough to ride a wall. Together with
  the per-contact HP charge above, wall contact is now a cost you pay and never a pool
  you spend — the barrier has become a **reflex window** rather than a resource.

  **`BARRIER_PER_RANK` stays at 0.25**, so a rank is now worth *twice* the base and a
  single one **triples** the pool. That sharpens the §11.5 argument rather than breaking
  it: the first rank of Barrier Capacity is the difference between no room and real room,
  which is a decision about how you drive rather than a bigger number.
- **Regenerates** when not in contact — base **0.15/sec**, so a full refill takes ~3.3s of
  clean travel. It was 0.25, and that was too generous: the pool was effectively always full
  by the next corridor, so the interesting question — *can I afford this brush?* — never got
  asked, and consecutive scrapes cost nothing extra. At 0.15 scrapes **compound**, which is
  what makes Barrier Regen a line worth taking rather than a rounding error.
- **Touching a wall costs 1 HP, once, the moment contact begins** (`SCRAPE_DAMAGE`).
  Escaping clean and riding it to the last frame cost the same single point.
- **If the player turns out of the wall before the barrier empties, that 1 HP is the whole
  price.** No speed loss, no park, no crash — the racer keeps driving, a point down.
- **If the barrier empties, the player crashes** (§5.4), and the crash damage lands *on top*
  of the contact charge already paid.

**Contact is not a crash, and the separation is the point.** A crash parks the racer, resets
speed to the floor, fires `crashed`, and brings the pull-back camera and the held recovery
prompt with it. Contact does none of that — it moves HP and nothing else. So the barrier no
longer decides *whether* wall contact costs anything; it decides whether the cost stays one
point or escalates into the full per-maze crash damage.

**This reverses the original rule that a clean escape was free**, which §11.4 built the skill
ceiling on. It is a design change, not a tuning tweak, and it is recorded plainly because the
surrounding text was written against the old promise: anything reading "a good player brushes
walls constantly and never pays for it" predates this decision.

**Charged once per contact, not per second.** Contact *duration* is precisely what the barrier
already measures, so billing HP for it too would put two systems on the same timer charging
for the same thing. Per-second would also make HP fractional on a bar the player reads as
whole points. Leaving the wall and touching it again is a second contact and charges again —
`RulesTest` asserts that directly, because "once per contact" is otherwise indistinguishable
from "once ever" in a test that only ever touches one wall.

**It is flat and does not scale per maze.** The crash damage is the escalation lever (§5.5); a
contact charge that climbed with it would make late-maze brushing punishing enough that the
question the barrier exists to ask — *can I afford this brush?* — collapses back to a flat no.

**A scrape can kill.** Death is checked on the contact charge, so a player at 1 HP dies to a
wall touch. Without that, HP would stop meaning anything at exactly the moment it matters most
— a run could survive indefinitely on contact alone. It reads as its own event: `died` fires
without `crashed`, so the crash framing never appears for a death the player did not crash
into.

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

- **50 HP**, and **death is ON**: HP reaching 0 ends the run.
- **Wall damage scales per maze: 3, 5, 7, 9, 11** (`WALL_DAMAGE` + `WALL_DAMAGE_PER_MAZE`
  × maze). Against 50 HP that is 17 crashes on maze 1 and 5 on maze 5:

  | | Maze 1 | Maze 2 | Maze 3 | Maze 4 | Maze 5 |
  |---|---|---|---|---|---|
  | Damage per crash | 3 | 5 | 7 | 9 | 11 |
  | Crashes to die | 17 | 10 | 8 | 6 | **5** |

  **The pool has come down twice — 100 → 75 → 50 — on the same argument each time**, which
  is the honest record that it had not gone far enough. HP has to be a number the player
  *watches*, and a pool absorbing twenty-five crashes on maze 1 stayed decorative through
  the whole first half of a run — the same failure §5.5 records for the *flat* damage rate,
  surviving into the scaled one at successively smaller sizes.

  **The per-contact charge now sits underneath all of it**, and that is the real change at
  50: fifty wall touches is a whole run's worth of HP, so the damage curve is no longer the
  only thing draining the pool (§5.1).

  **The damage curve deliberately did not move with it.** Rescaling damage to hold the crash
  counts steady would have undone the change; maze 5 falling from 9 crashes to 6 and now to
  5 *is* the point, not a side effect to be corrected. Cutting the pool rather than raising damage also
  keeps the early mazes survivable while sharpening the late ones, because a fixed subtraction
  against a smaller pool bites hardest where the subtraction is already largest.

  **Repair Field gets stronger for free, and that is intended.** It heals a flat 0.6–2.0 HP
  per second of clean travel, so against a smaller pool each rank restores a larger *share*
  of it. The line that pays for driving clean between crashes should gain value exactly when
  crashes get more expensive.

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

---

## 5b. Coins

Small gold discs, floating and slowly spinning, scattered through every maze.
Each one held raises the **speed floor by +0.05x**, up to a cap of **20** — a full
purse is +1.00x. They are also the shop's currency (§7b).

| | |
|---|---|
| Bonus per coin | +0.05x on the speed **floor** |
| Cap | 20 held, **falling by 1 on every crash**, floored at 5 |
| On a crash | keep **half, rounded down** |
| Banked | on **clearing a maze**, never on a death |
| Placement | ignores the solve path, the distance field, the gates and the exit |

### It is the FLOOR, not the ramp

The ramp is the game's central pressure (§3) and Momentum is already the line
that prices it; a currency that accelerated the climb would be a second Momentum
with no wall-contact reset to pay for it. The floor is the number a crash
**resets to**, so coins buy back exactly what a crash takes away — which is what
makes losing half of them on a crash legible rather than arbitrary.

It is additive on top of Base Speed ranks, so the two compound. **Every rule that
needs a floor reads `Racer.speed_floor()`**, never `Upgrades.speed_floor()` — the
two answers differ the moment a coin is held, and a rule still reading the
upgrade floor would let speed bleed below what the coins pay for. `Upgrades`
keeps its own untouched: it knows nothing about coins, and the card text and the
compendium bar are still right to read it.

### The cap ratchets down, and that is the only permanent cost

Halving the purse is a setback the player drives back out of in a minute.
**A crash also takes a point off the cap for the rest of the run**, and that never
returns — so a crash-heavy run is permanently capable of less, and the twentieth
coin belongs only to someone who has not crashed at all. It is the ratchet the
rest of the coin economy lacks.

**The bonus reads against the LIVE cap.** A crash that drops the cap below what is
held stops paying for the surplus immediately; without that the cap would be a
claim the game never enforced. The surplus is **unpaid, never destroyed** — it
stays in the purse and stays bankable, because it is money the player genuinely
collected. It floors at 5 rather than 0, or a run could reach a state where every
coin still drawn in the world is uncollectable — the same "visible and
unreachable" failure the sealed-pocket exclusion avoids.

Halving rounds **down**: 9 becomes 4, not 5. A crash already costs HP, the parked
time, the speed reset and 1000 points; coins are the fifth cost, and the only one
the player watches accumulate **before** they pay it, which is what makes a full
purse feel worth protecting.

### Banking is per MAZE, which is what survives a bad ending

**Clearing a maze commits the purse to the shop wallet.** A death never does. So a
player who clears maze 1 holding 10 and then dies in maze 2 with an empty purse
still keeps those 10. Banking only at the end of a run would mean a death wiped
everything four mazes of driving had earned.

**Banking does not spend.** The coins keep paying their speed bonus for the rest of
the run — they are spent money in the shop's ledger and a live resource in the
maze, and the whole point of banking per maze is that the player never has to
choose between the two.

Every run starts with an **empty purse** whatever the wallet holds, which is what
keeps the shop out of the simulation entirely: banked coins buy cosmetics and can
never make a run easier.

### Placement ignores routing, exactly as landmarks do

A coin is visible from a distance and is worth detouring for, so a currency that
preferred the optimal route would be telling the player which way to go — and
Path Indicator, Gate Compass and Golden Trail are **paid** lines sold on answering
exactly that. Coins say *there is value here*, never *the exit is this way*.

What that buys is the decision the coin exists to create: **a coin down a dead end
is a real choice** between a speed bonus and the 180 it costs to take it. If coins
only ever sat on the way to the exit there would be no choice in them at all —
they would simply be collected by driving well.

Measured on the shipped densities, coins land on the solve path at roughly its
own share of the grid (0–3% against 2–4%), which is the check that no bias
crept in. Every maze carries comfortably more than the cap — 22 to 32 — so the
player chooses **which** to detour for; a maze holding exactly 20 would make the
choice for them.

**The start and exit cells are excluded, and that is not a routing read.** The start
would hand out a free coin before the player had driven anywhere, and the exit
ends the maze on contact — a coin there could never be banked, which reads as one
that failed to collect. Sealed pockets are excluded too: a coin the player can
see and never reach is the one thing worse than no coin.

Coins draw from a **third RNG stream**, separate from both the carve and the
landmarks. Sharing the landmark stream would mean the coin density silently
redrew every landmark in the game, since each extra draw shifts the whole
downstream sequence — the knobs have to be independent of each other, not merely
of the maze.

Collection is **membership in the cell, never a radius**, the reason §7 gives for
the gate footprint: a radius fires diagonally through wall corners and collects
through solid geometry. A collected cell does not pay twice — reversing over a
taken coin is ordinary play in a looped maze, and one that re-armed would make a
single corridor an infinite purse.

### One node per coin, because coins MOVE

Every other repeated object in the maze — walls, grid lines, landmarks — is baked
into a shared surface precisely because it is **static**. A coin spins and bobs, so
it needs its own transform each frame, and that means a node. The mesh and
material are shared, so the cost is one draw call per coin and not one material
per coin. A maze carries tens of coins rather than the thousands of cells the
walls do, which is what makes this affordable where the same approach would not
be for walls.

**A disc standing on EDGE, spun about Y**, so it alternately faces the player and
presents its edge — the read that says "coin" rather than "glowing pillar". A disc
lying flat on the floor would be a line from the trailing camera's low angle,
which is the mistake the wall-mounted Path Indicator panels made (§7).

The **spin is what separates a coin from a landmark** at a glance: both are small
bright objects standing in a corridor, and at 8x a static one is read as scenery.
The bob is phase-offset per cell so neighbouring coins are not in lockstep — a row
of them rising as one reads as a single animated object rather than as several.

A collected coin is **removed outright rather than dimmed** like a spent gate. A
spent gate is kept because it is a landmark: tall, on the solve path, and the best
evidence in the game that a corridor has been driven (§7). A coin is small, sits
anywhere, and carries no such information; a dimmed one would only be a thing the
player keeps trying to collect.

**The size and height were set from rendered frames, not calculated.** At radius 0.55
the disc was a sliver several cells out. `COIN_HOVER_HEIGHT` is measured against
`CAM_HEIGHT` (2.3) rather than picked: a coin at eye level is seen against the dark
corridor mouth, where a low one competes with the floor grid lines the player is
actually reading (§11.3).

### On the HUD

The counter reads **held and the live cap** — "12/20" and "12/17" are the same purse
and very different runs, and the cap is the number that falls permanently. It sits
in the **left group with speed**, because a coin is +0.05 on the floor and the two
are one thought; the right group is the timer and the score, and the timer's width
changes past a minute so nothing may share its line (the §9d collision).

It is **read off the racer every frame** rather than driven by the collection signal
alone. A counter updated only on collection goes stale the moment anything else
moves the purse — a crash halves it and shrinks the cap, and the maze boundary
carries both forward — so the display would disagree with the speed the player is
actually driving at. It goes **dim at the cap**, since further coins bank for the
shop but buy no more speed.

A crash **announces** the new purse and cap. The cap falling is the one permanent
consequence in the economy, and a number that quietly drops during a crash — when
the camera is pulling back and a recovery prompt is held — is a rule the player
never sees fire.

`RulesTest` asserts the economy; `CoinProbe.gd` reports placement per maze and is
how the routing-leak check is made; `CoinShot.gd` is the picture half.

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

The ledger now runs **45 picks against 75 ranks**: 40 gates plus the five loadout picks
below, against a tree that comfortably outgrows what a perfect run collects. It has kept
growing since — Platinum Trail, Quadrant and Compass all landed after the count above was
first written — so **read the total off `Upgrades.DEFINITIONS` rather than trusting this
number**, which is a measurement and not a rule. Measured on
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
| **Barrier Capacity** | +0.25s of wall-contact grace per rank | Directly widens the skill-expression window. Against a 0.125s base a single rank **triples** the pool, so rank 1 is the biggest step in the tree |
| **Barrier Regen** | Faster barrier refill | Pairs with capacity; matters most in tight twisty sections |
| **Gate Compass** | Points toward the next gate | A soft directional hint — weaker than Path Indicator, but always on |
| **Snap Turn** | Shortens the post-turn freeze: 0.10s → 0.075 → 0.055 → 0.04 | Buys back time, the currency of §8. Never removes the freeze — see below |
| **Golden Trail** | On a timer, a gold streak runs the whole route to the **next uncollected gate**, at 2x player speed, lingering 2s | Periodic, not continuous. Rank sets the interval; reach is a fixed duration times your speed |
| **Platinum Trail** | The same in silver, running the shortest route to the **exit** — but only after **5 gates** are banked | The "finish fast" line to Golden's "collect your upgrades". The two never draw at once |
| **Wall Armor** | Reduces crash HP damage by 1 per rank | Now load-bearing: death is on and wall damage scales per maze (§5.5). Subtracts *after* the per-maze scaling, so a rank is the same flat point everywhere |
| **Trail Memory** | Ground you have driven is tinted on the floor and the minimap — lit on the first pass, darker with every re-crossing. Remembered for 1:00 / 1:30 / 2:00 / 2:30 / 3:00 / the rest of the maze | Six ranks. Answers "have I been here", never "which way" — the §6 line, and the only *paid* line sitting on it |
| **Cornering** | Cuts the per-turn cost: 0.03x → 0.024 → 0.018 → 0.012 | Moves the §5.3 equilibrium directly, so it changes *routing*, not a stat — a Cornering build affords turn-heavy routes that would bleed an unupgraded racer dry. Never reaches zero |
| **Expiry Grace** | Shrinks the expired-input penalty: 0.5x → 0.38 → 0.26 → 0.15 | Pairs with Buffer Window into a real "press early, press often" build. Never zero — an expired press must always mean something |
| **Repair Field** | Restores 0.6 / 1.2 / 2.0 HP per second of **clean** travel | The answer to scaling wall damage. Pays for the same thing the speed ramp does (§3) and cannot be farmed: no regen while parked or scraping |
| **Quadrant** | A corner box dividing the maze 2×2 / 3×3 / 4×4, lighting the region you are in, with the start and the exit both outlined | Position, never route. Quadrant 1 holds the start, the highest holds the exit — so a lit region between two marked ends says how far through you are without saying which way to turn |
| **Compass** | A physical compass — a fixed dial with cardinal ticks and a red-tipped needle swinging to real north — with the cardinal letter beside it | Absolute, where Gate Compass is relative. The dial is fixed and the needle turns, the opposite of the minimap. Tells the truth — the exit is south-east, not north |
| **Momentum** | +12% to the speed ramp rate per rank, **lost on any wall contact** and rebuilt over ~4s of clean travel | The first line on the ramp itself (§3). Prices the §11.4 skill ceiling in the game's own currency — and it moves the §5.3 equilibrium, so re-measure rather than re-derive |
| **Second Wind** | Bank one crash save per rank, refilled by clearing a gate. Spent automatically when the barrier empties | The only non-attritional damage line: it saves the run from the crash that ends it, rather than making crashes cheaper. Does not refund the per-contact HP |
| **Deep Breath** | Keep holding a direction through a turn and that turn's freeze *extends* by up to 0.25 / 0.5 / 0.75s, on a **10s cooldown** | The true opposite of Snap Turn. Any turn qualifies — the cooldown is the limiter, which is what let the old early-press gate go. The ramp RUNS through it; measured at +0.27x and 6 uses a maze, so what you spend is ~2s of the budget |
| **Overclock** | Hold a direction, then `↓`: burn 2.5 / 1.8 / 1.2 HP per second for +2x speed | The first line that *spends* a resource for pace. Direction-first so it can never steal the 180; floors at 1 HP so it cannot kill you |
| **Gate Size** | Rank 1 raises the gate marker; ranks 2–3 widen its collection **footprint** to a 5-cell plus and beyond | Puts a decision in gate collection for the first time — a wide gate straddles a wall, so a parallel corridor can bank the pick |
| **Extra Card** | 4 upgrade cards at every pick, then 5 | An investment: the cost is the pick itself, so it is only correct early. Cards narrow to fit rather than the row overflowing |

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

### Trail Memory paints where you have been

**Ground the player has driven is tinted, on the maze floor and on the minimap.** A cell
driven once lifts *above* the palette floor; every re-crossing takes it down, past the base
floor into shadow. Fresh ground is dark, ground you know glows, ground you have flogged is
burnt out.

**It answers "have I been here", never "which way"** — the same line landmarks (§6), spent
gate markers (§7) and the rear-view mirror (§12) sit on. Everything it shows is ground the
player has already covered, so it adds **memory**, not routing, and cannot cannibalise Path
Indicator, Gate Compass or Golden Trail. It is the only *paid* line on that side of the
divide, which makes it the strongest statement of the position rather than a departure.

**The lit-then-darkening shape is not the same as "darker every visit"**, and the difference
is forced by the palettes. Every maze's floor sits under 0.08 — a strictly monotonic dimming
has nowhere to go, so the first few visits would be indistinguishable from each other and
from untrodden ground. Lifting on the first visit gives the scale somewhere to start, and it
puts the brightest reading on the most useful fact: *this is ground you have seen once*.

**The ranks are a memory DURATION, which is the one place this deliberately departs from
§4.** The buffer is measured in cells precisely so forgiveness does not grow with speed. This
is not forgiveness, it is memory — and "the last minute of driving" is the thing a player
actually wants to hold. It does mean the trail covers more ground at 8x, which is correct: at
8x you have genuinely driven more ground in that minute. Sized against the 180s maze budget
(§8b), rank 1 at 60s is a third of a maze — enough to recognise a loop you just closed, not
enough to map the maze.

**A lapsing cell fades over 3s rather than snapping off.** Cells reach their deadlines
individually, so a hard cutoff would blink them out one at a time, which reads as a rendering
fault rather than as memory. With a fade the tail visibly retreats, and ranking up is
*watching the tail stretch* rather than something only verifiable by counting.

**The count expires with the cell**, so a lapsed cell reads as never driven — which is what
makes the top rank a difference in what is **known** rather than only in what is drawn.

**The record is kept whether or not the line is held.** The upgrade gates the *drawing*. A
player who takes it at gate 4 lights up ground they have demonstrably already covered, where
gating the recording would hand them a blank trail through a maze they have half-driven — the
opposite of memory.

**It is a separate record from `Racer.visited`**, which looks like it covers the same ground
and does not. That dictionary holds a bool — "has this cell been re-entered" — and exists to
charge the §8b repeat-ground penalty once per cell. Widening it to carry counts and timestamps
would put a display feature inside a load-bearing scoring rule.

**The clock is the racer's own accumulated driving time, not a wall clock**, so the trail
stops ageing while the game is paused or a card screen is open. A memory that lapsed during an
upgrade pick would punish the player for reading their cards. It advances *before* the parked
early-return, because a parked racer is still sitting in the world watching their trail.

#### The floor is a shader over a per-cell texture

The floor is one `PlaneMesh`, and per-cell shading needs machinery it did not have. It reads
an `ImageTexture` holding **one texel per cell**, so lighting a cell is a single pixel write —
O(1) at any maze size, with no extra draw call.

**The two obvious alternatives are traps this project has already paid for.** Rebuilding a
trail mesh is the `GoldenTrail` failure in §12 exactly — that ribbon cost 23ms a frame and
looked like a hang, and a maxed trail at maze 5 covers thousands of cells. A pooled set of
quads near the player (the `PathIndicator` pattern) works for three strips at one junction,
caps how much trail can exist, and pops as the pool re-assigns.

**The texture stores a signed value packed around 0.5** — above lifts, below darkens — which
is what keeps it single-channel and 8-bit. `FORMAT_R8` was suspected of not round-tripping
through `Image.set_pixel`; it was measured against a `FORMAT_RGBA8` control and the two are
byte-identical, so the deviation is plain 8-bit quantisation and R8 stands. **Diagnose that
class of fault by direct read-back, never by looking at the floor** — a floor rendering
correctly at neutral is exactly what a failed write looks like.

**The upload is once per frame, not once per cell.** `ImageTexture.update` re-sends the whole
image; doing that per changed cell would be hundreds of uploads a frame on a busy trail.

**The shader is written in code and kept WebGL2-safe**, since the web build runs
`gl_compatibility` while desktop runs Forward+ (§12). The cell coordinate is derived in the
**vertex** stage: Godot 4's fragment `VERTEX` is *view* space, so deriving a world position
there is easy to get subtly wrong, and the floor is a flat axis-aligned plane the rasteriser
interpolates exactly. Sampled `filter_nearest` — a cell is a hard square of memory, and linear
filtering would bleed the tint half a cell past the walls it stops at.

**The floor plane's half-cell offset and the shader's `origin_offset` cancel exactly.** The
`PlaneMesh` is centred, so it sits half a cell short of half the full extent; the shader adds
that same half cell back before dividing by `CELL_SIZE`. Verified at cells 0, 1, 30 and 59 —
`floor(cell_uv)` equals the cell index at both edges and the centre of each. Change one
without the other and the tint lands half a cell from the cells it represents.

> **A shader that fails to compile renders a plausible floor, and a clean run appends nothing
> to `logs/errors.log`** — so absence of errors is weak evidence. Confirm compilation
> *positively* by enumerating the material's uniforms; Godot populates that list only on a
> successful parse. And note `launch.ps1 -Quit N` boots `Main.tscn`, the **Shell/menu**, where
> `_build_floor` never runs — it cannot verify floor work at all.

**Only a rendered frame caught the tuning, and every headless assertion was green while it was
wrong.** The first frames measured driven ground at **3.2x the untrodden floor** (237 against
74), which read as a white slab dropped into the corridor rather than as the same floor lit —
worst on Ember and The Vault, where a cold cyan patch sat inside a warm palette and overrode
the per-maze identity §8 exists to establish. **The grid lines inverted**: dark seams on light
ground instead of bright marks on dark, which breaks the timing contract (§11.3) exactly where
the player reads it, and the near-white player marker was nearly lost against the floor it
sits on (§12's hard rule).

**The fault was the lift, not the darkening** — the natural suspect and the wrong one. The
positive branch multiplied albedo by `1 + signed*2.4` *on top of* the `TRAIL_COL_MIX` hue
push, so rank-1 ground was paying twice. At 0.8 lit ground sits at 1.80x. Separately the
darkening end was too shallow to see at all (visits 4 and 5 reached 14% and 25%), so the tint
table now runs to 0.0 and the negative branch to 0.9: the curve descends monotonically from
1.80x through **1.03x at visit 3** — the crossover between lit and burnt — down to 0.62x.

**The normalisation is derived from `TRAIL_TINT_BY_VISITS` rather than transcribed.** It maps
the lit rank onto the texture's +1.0 ceiling, and it began life as a hand-written `2.4` — a
copy of `TRAIL_TINT_BY_VISITS[1] - 1.0` that would have gone silently wrong the moment the
table was retuned. The same transcription trap §12 records for tests, in tuning clothes.

**`TRAIL_COL_MIX` stays well under 1.0 and is the lever to reach for first** if a future
palette makes the trail compete: the grid lines are the timing contract and must stay the
dominant marking on the floor.

**On the minimap the trail draws beneath every other cell state.** The exit, live gates and
spent gates all override it — those answer "where am I going" and "what have I opened", worth
more at a glance than "have I been here", and a gate whose square went grey with re-crossings
would be a gate the player could no longer find. **The map's trail colours are brighter than
the floor's**, deliberately, exactly as `COL_GATE_SPENT` is: a map cell is a handful of pixels
on an already-dark disc where the floor is a large surface under fog and a headlight. Matching
the hue is what makes them read as the same thing. The map needed no retuning when the floor
did.

`RulesTest` asserts the record and asserts the **separation** directly, driving two racers on
one seed with the line maxed and untaken and requiring they never diverge — the failure hardest
to notice, since the trail hangs off the `Racer` and is *reachable* from every movement rule
even though none may read it (the same trap landmarks have, §6). `SceneTest` asserts the floor
is wired to the record, since a shader that never receives its texture renders a perfectly
plausible plain floor. `TrailMemoryShot.gd` is the picture half — **not** `TrailShot.gd`,
which is the Golden/Platinum instrument.

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

> **A long ribbon down a corridor is a trail, not a broken strip.** At a
> junction the two look alike, and a mis-oriented strip would sit at exactly the right
> position — so it was diagnosed as a rotation bug and "fixed" twice against geometry that
> measured correct the whole time. `PathStripShot.gd` keeps **both** trail lines out of its
> frames on purpose, so anything lying lengthwise in those shots is a real bug. Platinum is
> excluded on its own merits and not merely by association: it is the same ribbon in silver,
> and silver against a lit floor strip is if anything the easier of the two to misread.

### The two trails: Golden and Platinum

A streak fires from the player on a timer, runs the whole route ahead of them, and
fades. It is **periodic, not continuous** — that is the whole design.

There are **two lines**, the same mechanism aimed at two different questions:

| | Golden | Platinum |
|---|---|---|
| Routes to | the nearest **gate not yet taken** | the **exit** |
| Colour | warm gold | cool silver-white |
| Interval by rank | 12s / 8s / 5s | 15s / 10s / 6s |
| Available | always | only after **5 gates** are banked |

**Rank sets the interval, not a length.** The trail runs the *entire* route to its
target, and how far the player actually sees is set by **their own speed**: the head
advances at 2x the racer's cell rate for at most `TRAIL_MAX_DRAW` (2.5s), so a 1x
racer is shown ~5 cells and an 8x racer ~40. That is deliberately the opposite of the
fixed cell count it replaced, which handed the fast player — who has the least time to
read a junction — exactly as much lookahead as the slow one. **Reach is a duration
scaled by speed, which is the one thing that makes lookahead worth more when the game
is harder.**

The old `TRAIL_CELLS_BY_RANK` was deleted rather than kept at a large value. A cap
that never binds is a number a later reader has to prove inert before they can ignore
it — the same trap §8 records for the dead-end density target.

**A gate is not on the distance-field gradient, which is why `route_to` exists.**
`route_from` descends the field, and the field knows exactly one destination. Walking
toward a gate frequently means walking *away* from the exit, so no amount of reading
`distance_field` answers it; Golden needs a plain BFS to an arbitrary cell. It is
bounded for the same reason `_reaches_exit_avoiding` is, but generously: unlike a
branch classification, this must never return a *wrong* answer when it runs long. A
target beyond the cap yields **no route at all**, which reads as the trail waiting a
cycle rather than as it pointing somewhere untrue.

**Golden takes the nearest uncollected gate by route length, not by placement order.**
Gate order is a property of the canonical solve path, and a braided maze (§8) routinely
puts a later gate closer than an earlier one. Sending the streak to gate 2 while gate 5
is round the corner would be advice the player is right to ignore, which is worse than
no advice. Once every gate is taken Golden falls back to the exit, so the line does not
go dead for the rest of the maze.

#### Platinum waits for five gates, and the two never draw at once

**Platinum says nothing until `PLATINUM_MIN_GATES` (5 of 8) are banked.** The two lines
own different halves of a maze: up to that point the live question is *where are my
upgrades*, and a silver ribbon pointing at the exit during that stretch is an invitation
to skip picks the player has already spent a card on. Past it the question genuinely
becomes *get me out*. Five is late enough that the gate tour is clearly the early maze's
business, early enough that Platinum still has real maze left to be useful in rather
than firing once on the way through the exit arch.

**The two must never be on screen together, and this had to be enforced.** They are
ribbons of the same shape on the same floor, and gates sit on the solve path — so most
of the time the route to the next gate *is* the route to the exit and the two lie
exactly on top of each other. Drawn together the near one simply paints over the far
one, and the player sees one ribbon in a muddled colour: worse than either alone, and it
destroys the one thing the split is for, which is seeing the two **disagree**.

This is not an edge case. At rank 3 the intervals are 5s and 6s against a draw phase of
up to 2.5s plus a 2s linger, so overlap is the common case — and the first rendered frame
of both lines together showed exactly that, gold over silver with the silver reading as a
white smear underneath. **Only a rendered frame could show it**; both nodes were behaving
correctly on their own terms.

The gate threshold does most of the work, since before gate 5 only Golden can fire at
all. The **interlock** covers what is left: a trail whose cooldown expires while the
other is drawing **defers rather than skips** — the cooldown is not reset, so it fires
the moment the other clears. Skipping the cycle would make a rank of Platinum quietly
worth less than its card claims whenever Golden happened to be busy.

`RulesTest` asserts both directly, and the overlap check carries a **second assertion
that Platinum fired at all** — "never overlaps" is trivially true of a line that never
appears. Verified by removing the interlock: the check fails without it and passes with
it.

#### Both, mechanically

- **Travels at 2x the player's current speed**, so it pulls away and stays ahead.
  Tying it to live speed rather than a fixed rate keeps it legible: at 5x the
  player would otherwise outrun a fixed-rate streak and see it trailing behind. It
  is now also what makes *reach* scale with speed, since length no longer does.
- **The draw phase is bounded in seconds** (`TRAIL_MAX_DRAW`). With the route
  uncapped, a slow racer would still be drawing when the next firing was due, so a
  trail could monopolise its own line and never re-snapshot from the player's
  current cell — which is the thing that keeps the ribbon honest.
- **Lingers 2s** after it finishes drawing, so a trail fired just before a
  junction is still on screen when the junction arrives.
- **Free and automatic.** No input, no speed cost. Adding a fourth key would
  break the three-input contract in §2, and an automatic timer that
  silently taxed speed would be unreadable.
- **One node class serves both**, differing only in target and colour. A second class
  would have been a second copy of the ribbon, the shader and the timing to keep in
  step — the parallel-array trap of §6 and §9c wearing different clothes. `mode` is a
  **setter** because `Game` assigns it after `add_child`, which is when `_ready` builds
  the material; a plain field would have left a platinum trail wearing gold, a failure
  nothing headless can see.
- **Card text is derived from the tuning tables**, never written out — including the
  gate threshold. Same reason Fast Turnaround's is (§7): a description that restates a
  tuning value goes stale silently, and the player makes a decision on it.

**Why they do not duplicate Path Indicator.** Path Indicator answers *this
junction, right now*, every junction, forever. A trail answers *where does
this whole corridor go*, a few times a minute, and says nothing in between. One
is a continuous readout, the other is an occasional map. Taking both is meant to
be strong; taking either alone leaves a real gap.

`TrailShot.gd` is the picture half. It **seeks a frame where Platinum is mid-firing**
rather than shooting on a timer — the silver line appearing at all is the fixture, since
Golden shows in every other frame of a run — and it reports `OVERLAP` on every shot,
which must always be false.

### Six lines added on the axes the tree had missed

Sorted by the question each answers, the tree had four lines on *which way ahead*, four on
*have I been here*, two on input forgiveness, four on the speed economy, four on the damage
economy, one on score and three abilities. Two gaps stood out.

**Nothing touched the speed ramp itself.** §3 is the game's central mechanic, and every
"speed" line before this touched *costs and floors* — Cornering, Snap Turn, Fast Turnaround,
Base Speed. The ramp rate, the number the whole difficulty curve hangs off, had no line on it.

**Nothing was conditional.** Every line was a flat always-on number, so no card changed *when*
you drive a certain way — only what a thing costs. An upgrade that only pays off if you drive
differently is §11.5 at its strongest, and the tree had none outside the legendaries.

| Line | Ranks | Effect |
|---|---|---|
| **Momentum** | 4 | +12% speed ramp rate per rank, **lost on any wall contact** and rebuilt over ~4s of clean travel |
| **Second Wind** | 3 | Bank a crash save per rank, refilled by clearing a gate. Spent automatically when the barrier empties |
| **Deep Breath** | 3 | Keep holding a direction through a turn: that turn's freeze *extends*, up to +0.25/0.5/0.75s, on a 10s cooldown. The ramp runs |
| **Overclock** | 3 | Hold a direction, then press `↓`: burn HP for +2x speed. Ranks cut the burn 2.5 → 1.8 → 1.2 HP/sec |
| **Gate Size** | 3 | Rank 1 raises the gate marker; ranks 2–3 widen its **footprint** to a 5-cell plus, then further |
| **Extra Card** | 2 | 4 cards at every pick, then 5 |

Eighteen ranks, taking the tree from 81 to 99 against 45 picks — so the §7 promise that a
perfect run cannot max everything holds with more room than before, not less.

#### Momentum puts a line on the ramp, and prices it in wall contact

`SPEED_RAMP_PER_SEC` is 0.10. Each rank adds 12%, so rank 4 is 0.148/s — 5x arrives in ~27s
rather than 40s.

**The reset condition is the whole design, and it is CONTACT, not a crash.** Every other
damage-adjacent line in the tree is attritional: soak more, heal faster, crash for less. This
one makes the §11.4 skill ceiling pay in the currency §3 says the game is actually about. A
brush already costs 1 HP and the barrier; now it costs your *acceleration* too, so the expert
who drives genuinely untouched pulls away from the one who merely survives — which is exactly
the separation §11.4 asks tuning to protect.

**It rebuilds rather than being lost for the maze.** A single scrape killing the bonus for
good would make the line a lottery on the first mistake, and §5.1's whole question — *can I
afford this brush?* — needs an answer other than "never". The bonus climbs back over ~4s of
clean travel, roughly the barrier's own refill time, so the two costs of a scrape run on the
same clock.

**This moves the §5.3 equilibrium, and it is the ramp side of that formula.** The settling
point is `RAMP_PER_SEC / (turn_ratio × TURN_COST)` and is linear in the ramp, so the line
lifts it directly. **Measured with `MomentumProbe`, on an optimal router with the ranks
forced:**

| Build | Maze 1 | Maze 5 |
|---|---|---|
| Momentum 0 (baseline) | 4.95x | 4.69x |
| Momentum 1 | 5.27x | 5.08x |
| Momentum 2 | 5.56x | 5.44x |
| Momentum 3 | 5.85x | 5.80x |
| **Momentum 4** | **6.12x** | **6.15x** |
| Momentum 4 + Cornering 3 | 6.44x | **7.12x** |
| Cornering 3 alone | 5.26x | — |

**The prediction from the formula was 7.2x for Momentum alone, and it was wrong** — the line
by itself reaches 6.15x, and only the *pair* with Cornering gets near 7.2x. That is exactly
why §5.3 says re-derive rather than re-guess: the formula gives the shape, not the number.
The cap stays comfortably out of reach at 7.12x, so it remains the safety rail §3 wants
rather than a target.

**Read the settling point off maze 5, not maze 1.** Maze 1 finishes in ~41s, which is before
the ramp has settled, so its figures are what a build *reaches there* rather than the
equilibrium itself. The two agree to within 0.05x at rank 4, which is what says the number is
a settling point and not an artefact of run length.

> **`MomentumProbe` must steer once per CELL, never once per frame.** Its first version
> re-requested a turn every frame, which spams the buffer: the racer crashed 13 times and
> died after 122 cells, and the probe duly reported an equilibrium of **1.00x** for every
> build in the table — a flat, plausible-looking column that was measuring a dying racer
> rather than a settling one. The tell was `turns/s` at 0.11 against the 0.62 a 5x racer
> actually makes. This is `RepeatProbe`'s frame-versus-cell lesson (§12) arriving in a
> different instrument.

#### Second Wind is the insurance the tree had none of

One charge per rank, refilled by clearing a gate — so the resource is tied to the pacing beat
that already exists rather than to a new timer. When the barrier empties, a charge is consumed
instead of crashing: no park, no speed reset, no crash damage, and the barrier refills.

**It does not refund the contact charge.** §5.1 bills 1 HP the moment contact *begins*, well
before the barrier drains, so a save that covered that too would make the whole wall touch
free and delete the question the barrier exists to ask. You pay the point; you skip the crash.

**Wall Smasher wins when both are live.** They fire at the same instant — barrier empty, wall
ahead — and the legendary is both the rarer thing and the better outcome, since it opens a
real hole in the maze (§7) rather than merely preventing a stop. Second Wind's charge is
preserved in that case, which is what keeps the two from silently competing for one save.

**Every other damage line is attritional, and this one is not.** Barrier Capacity, Barrier
Regen, Wall Armor and Repair Field all change how much a crash costs or how fast you recover
from it; none saves the run from the single crash that ends it at 5 HP on maze 5. Now that
death is on (§5.5), that was the largest gap in the tree.

#### Deep Breath is the true opposite of Snap Turn

Keep holding a direction through a turn and the freeze on that turn *extends*, up to
+0.25/0.5/0.75s — long enough to be a **look** rather than a longer corner. On a **10s
cooldown**. No speed cost; you are paying time to buy reading room.

**The COOLDOWN is the limiter, and it is what replaced an early-press gate.** The line
used to fire only on a turn that resolved out of the *buffer*, and that gate existed
because the line had no other limiter at all: the key that *requests* a turn is still
down when the 0.10s freeze ends, because nobody releases an arrow inside a tenth of a
second — so `held_direction != 0` was true at every turn the player made, and the
extension was automatic rather than asked for. Measured at the time: an immediate turn
ran **34 frames of freeze against 7**, on a corner the player never asked to extend.

**A cooldown does that job better, which is why the gate could go.** It bounds uses per
minute *directly* rather than inferring intent from when the press happened to land, so
the extension is now a decision at **every** junction instead of only at the ones read
early. Gating on the buffer meant a junction misread — arriving without having committed
— was also a junction you were not allowed to stop and look at, which is backwards: the
moment you most want a beat to read is the one you did not see coming.

**The allowance grew with the cooldown, because it is now a stop rather than a slow
corner.** 0.15–0.45s against an ordinary 0.10s freeze was a corner that lasted slightly
longer; 0.75s at max rank is a beat the player halts and reads in. Six uses a maze at that
length is a different mechanic from sixty at the old one.

**A 180 does not extend.** `REVERSE_FREEZE` is already the longest hold in the game — 1.6x
a corner's, because the view swings through a full half-turn — and the corridor behind is
ground the player has just driven, so there is nothing new to read. The allowance is
cleared on a reversal and the cooldown is deliberately left alone, since a 180 spends
nothing.

**The cooldown is armed when the extension is GRANTED, not when it ends**, so the 10s
covers the pause itself rather than starting after it. It ticks on the racer's own
accumulated driving time and sits below the `PARKED` early return, so a crashed racer is
not quietly recharging while it waits to be un-stuck — the same clock the legendary
cooldowns use, and for the same reason. A fresh maze opens with it ready: it is a
within-maze pacing limit, not a resource carried across the boundary.

**The ramp RUNS through the extension, and this reverses the rule that held before the
cooldown existed.** The ramp used to be *rewound* for the extension, on the reasoning that
holding at every corner would gain speed for free and turn a turn-heavy maze into a speed
pump — the extension paying *more* than it costs. That reasoning was correct for an
**unlimited** hold and is what the cooldown removes.

**Jonah's call, made against that objection, and the measurement showed the objection was
sized wrong.** The estimate against it was ~6 uses a *minute*; `DeepBreathProbe` measures
**6 uses a maze**, because a 62s maze at a 10s cooldown simply does not allow more.
Measured on maze 5, an optimal router holding the direction throughout:

| Rank | Final speed | Time | Uses |
|---|---|---|---|
| 0 (control) | 4.69x | 62s | 0 |
| 1 | 4.78x | 63s | 6 |
| 2 | 4.87x | 64s | 6 |
| **3** | **4.96x** | **64s** | **6** |

**+0.27x at max rank against ~2s of the 180s budget.** At the ÷30 time multiplier those 2s
cost about −0.07x on the maze multiplier, so the trade is favourable and the line is worth
using — but it is not free, and at six uses a maze it is nowhere near a pump. **The control
block is what says the gesture is the whole mechanism:** every rank reads exactly 4.69x and
**0 uses** when the direction is not held, so the line is completely inert unless asked for.

> **Neither `RunTest` nor `RulesTest` could have answered that.** RunTest's autopilot never
> *holds* a direction, so its final speed is identical with the line maxed and untaken — the
> same blind spot §7 records for Momentum, where a full run took the line only to rank 1.
> RulesTest asserts one extension in isolation, which says nothing about six of them
> compounding across a maze. `DeepBreathProbe.gd` is the instrument.

**Two lines on one mechanic, pulling opposite ways, is the point.** Snap Turn says *I read
fast, give me the clock back*; Deep Breath says *let me stop and look*. They are never
sensibly taken together, and a card that is worthless to your build is a stronger statement
about that build than one more +0.15.

**It respects the three-key contract (§2)** because it is a *held* existing key, not a fourth
binding — the same reasoning that made the legendary gesture a double-tap.

> **The harness assertions INVERTED with the rule, and that is the point of keeping them
> paired.** Two of them previously encoded the gate ("an immediate turn does NOT extend") and
> the rewind ("the extension does not pay speed"); both now assert the opposite, and the
> cooldown got the assertions it had none of. Verified in both directions, because a test that
> cannot fail is not evidence: disabling the cooldown arm fails at `first 51 frames, second 51`
> — the two turns identical because nothing limits them — and restoring the early-press gate
> fails six checks at `7 frames vs 7`.

> **A buffered turn does not freeze on the press.** It resolves at the next boundary, tens of
> frames later — measured at 43. A harness that starts measuring the freeze immediately after
> `request_turn` reads **zero frames**, which looks exactly like the extension failing to fire.
> Drive until the freeze starts, then measure it.

> **The cooldown check needs a maze that can host TWO turns.** `_make_branch` is two rows tall
> with a single opening, so a second turn is geometrically impossible in it — the fixture is
> `_make_room`, where every direction is open and both turns are therefore the same kind, which
> is what makes the two freezes comparable. A difference between them is then the cooldown and
> nothing else.

#### Overclock spends HP for pace, and the gesture is direction-first

Hold a direction, then press `↓`: speed climbs +2x above its current value while both are
held, burning 2.5 / 1.8 / 1.2 HP per second by rank.

**Direction-first is what keeps it off the 180.** `↓` is already the reversal and the un-stick
(§2), plus the legendary double-tap, so a fourth meaning has to be placed where it cannot
steal the other three. The direction must *already be held* when `↓` lands; a `↓` arriving
alone is always a reversal. That makes the 180 the default and the overclock the deliberate
gesture, and it costs the common case nothing.

**It cannot kill you.** The burn floors at 1 HP and cuts out. Dying to your own accelerator
with no wall involved reads as a bug rather than as a cost, and every other death in the game
comes from contact (§5.5).

**Blocked while parked**, for the reason the legendary gesture is: `↓` on a parked racer means
un-stick, and a recovery press must never be spent on something else.

**It is the first line that lets the player SPEND a resource for pace.** Everything else in
the damage economy accumulates protection. This turns the HP pool into a currency and makes
Repair Field an engine rather than a safety net — the "burn and heal" build is a way to drive
that the tree could not previously express.

#### Gate Size finally puts a decision in gate collection

Rank 1 raises and widens the marker. Ranks 2 and 3 widen the **footprint** as well: the gate
is collected from a 5-cell plus, then wider still.

**The marker used to grow only UPWARD, and that made the line read as doing nothing.**
Reported as *"the increase gate size upgrade isn't visually making the gates bigger"*, and the
fault was geometric rather than a matter of degree. `_marker_mesh` scaled only its `top`; the
crossed slabs' `wide` and `thin` were fixed multiples of `CELL_SIZE`. Measured on a controlled
pair — one seed, one gate, one camera pose, varying only the rank — the mesh AABB ran
**5.55 → 9.16 on Y and held a flat 3.0 × 3.0 on XZ at every rank.**

**The camera is what turns that into invisibility.** It is capped below `WALL_HEIGHT` (§12), so
everything a taller marker adds is added *above the wall line*, at the far end of a corridor,
where perspective compresses it to a few pixels. The part of the marker at eye level — the part
the player is looking at while collecting it — was pixel-identical at every rank. So the line
was buying its whole effect in the one band the player least looks at, and none of it in the
band where "my gate got bigger" is actually asked.

**So a rank now widens as well as raises**, `GATE_SIZE_GIRTH_BY_RANK` beside the height table.
Girth scales *both* slab axes, so the marker keeps its proportions rather than fattening into a
cube.

**Bounded by the corridor, and that bound sets the top of the table.** The base slab is
`CELL_SIZE * 0.75` = 3.0m in a 4.0m cell, so the widest rank leaves 8cm of clearance each side.
A marker reaching the wall is not a wider gate — it is a gate with its ends buried, and at 0.55
alpha that reads as a rendering fault rather than as an upgrade. **1.30 was tried first and
sits exactly ON the bound**, which `RulesTest` rejects deliberately: a top rank resting on the
limit has no margin for a later change to `CELL_SIZE` or to the 0.75 base, and would start
intersecting on the first tweak to either rather than failing a test.

**Girth defaults to 1.0 through the mesh builder so the EXIT is untouched.** The exit takes the
same `_marker_mesh`, and height is what separates a gate from the exit at distance (§7) — an
exit that grew with the player's Gate Size rank would blur a distinction the markers keep on
purpose.

**The card text and the compendium demo both had to move with it.** The card said "Gates stand
taller", which was accurate before and incomplete after; the demo drew the marker as a
fixed-width bar while its footprint widened, so the picture would have contradicted the card.

> **`AddedLinesShot` already shot this line and could not have caught it.** It restarts the run
> per rank, so its two frames land at different distances on different mazes — which shows a
> marker is *there* and can never show one is *bigger*. `GateSizeShot.gd` is the controlled
> instrument: one seed, one gate, one camera pose, at **two distances**, because the two halves
> fail differently. Far is the "can I see it coming" question `GateShot` asks; near is where
> the fault actually lived, since at 1.5 cells the added height is off the top of the frame
> entirely and only width can read.

> **It must SEEK a gate with clear corridor behind it.** Its own first version took `gates[0]`,
> which on the fixture seed sits hard against the maze's west edge — so the camera parked 5
> cells back sat inside the boundary wall and produced a frame with **no marker in it at all**,
> which reads exactly like the upgrade having failed. The one thing this instrument must never
> be able to say by accident. It now walks all four approaches and fails loudly when no gate
> has one, rather than shooting whatever is in front of it.

**The wide gate can straddle a wall, and that is the feature.** Collection is a cell-membership
test, so a footprint reaching into the corridor *next door* means a parallel route banks the
pick. §7 notes that gates sit on the solve path and collecting them "is engagement with the
solve" — but the collection itself has no decision in it at all: you are on the cell or you are
not. A footprint spanning corridors makes routing *near* a gate worth something, where there
was previously nothing to decide.

**Membership, never a distance check.** A radius would fire diagonally through wall corners,
collecting a gate through solid geometry — the maze's walls are the basis of every other rule,
and a gate that ignored them would be the one object in the game that does.

**A footprint cell the player can never reach is not painted on the minimap.** The plus can
land in a sealed pocket, which is harmless in the world (nothing drives there) and misleading
on the map, where it would read as a gate that cannot be got to.

**It gives the lane sub-grid its first bit of meaning.** §12 makes lanes display-only on
purpose, and they stay that way — but a gate spanning cells laterally means the lane you are in
can decide whether you clip its edge, so the sub-grid becomes visible in an outcome for the
first time without any rule reading it.

#### Extra Card is an investment, and the cost is the pick itself

4 cards at rank 1, 5 at rank 2.

**Spending a card to make every later card better is a shape nothing else in the tree has.**
It is only correct early, and it is self-balancing for exactly that reason: taking it at gate 7
of maze 5 is a wasted pick, and the player can work that out. No rule is needed to stop them.

**The "guarantee a new line" rule has to scale with the count.** §7 guarantees one fresh line
among three while fewer than three are started; against five cards that guarantee is nearly
free and stops meaning anything. It scales as one per three cards offered, so the promise stays
the same *proportion* of the screen it always was.

**The cards narrow rather than the row overflowing.** §12 records that the row width is derived
from `CARD_SIZE` — five 320px cards plus separation is ~1750px against a 1600px viewport, so
the width is now derived from the count instead. All cards stay equal to each other; they just
get slimmer. A second row was rejected: a card screen is read fast under a stopped clock, and
1–5 spread across two rows is a slower read than five in a line.

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
- **The same check broke again the same way one line further on, and Second Wind is the
  second save.** `_press_into_wall` tries Wall Smasher, then Second Wind, and only then
  crashes — so a banked charge **absorbs the crash and the racer never parks**. Taking every
  upgrade line banks the full complement, so the racer has to burn them all before the
  assertion can see a park, and whether the 400-frame budget covers that depends on the maze
  the seed drew. **Measured at roughly 1 failure in 6 runs.** Fixed by emptying the charges
  rather than raising the budget: the check is named for the crash, and a racer spending
  saves is exercising Second Wind instead. Verified both ways — 10 consecutive clean runs
  emptied, and the failure returning at 2 in 6 with the charges re-armed.

  **An intermittent failure whose message names the wrong system is the expensive part.**
  "driving into a wall crashes" points at the crash path, which was correct throughout. When
  a check that takes *every* upgrade line starts flaking, suspect the lines that change the
  outcome it asserts before suspecting the outcome.
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

### Quadrant and Compass — where you are, and which way you point

Two lines, deliberately separate, answering two questions the maze never
otherwise answers.

| Line | Ranks | Effect |
|---|---|---|
| **Quadrant** | 3 | A small box in the corner drawing the maze divided into 2×2 / 3×3 / 4×4, with the region you occupy lit |
| **Compass** | 1 | A physical compass: a fixed dial with a red-tipped needle pointing at real north, and the cardinal letter beside it |

**They sit on the "have I been here" side of the line**, which is the only
reason they are safe to add. Landmarks (§6), the spent gate marker (§7) and the
rear-view mirror (§12) all hold that line, and it is what keeps this from
cannibalising Path Indicator, Gate Compass and Golden Trail — three *paid* lines
sold on answering the route ahead. A quadrant number tells the player which
sixteenth of the maze they stand in; it says nothing about which opening to
take, and the box is **position only**, with no highlight for the region ahead.

**The box is not a minimap and does not compete with one.** The minimap is
local — 6 to 24 cells of actual corridor, rotated to the direction of travel
(§12). The quadrant box is global, static, and carries no walls at all: 16 cells
of nothing but *which sixteenth*. On a 100×100 maze the widest minimap covers
under a quarter of one quadrant, so the two never overlap in what they show, and
a player holding both is reading two different scales rather than the same
information twice.

#### Quadrants are numbered, and the exit is always the highest

Numbering runs **row-major from the start corner**: quadrant 1 contains
`start_cell`, and the last quadrant contains `exit_cell`. At 2×2 the exit is 4,
at 3×3 it is 9, at 4×4 it is 16.

That is a fact about the generator rather than a rule imposed on it. `start_cell`
is `(0,0)` and `exit_cell` is `(width-1, height-1)` — opposite corners — so
row-major numbering from the start necessarily puts the exit last. **The
numbering is derived from those two cells, never from a literal**, so a
generator that ever moves either one keeps the promise instead of quietly
breaking it. `RulesTest` asserts the two ends directly.

**"You are in 6 of 16" is a progress statement, not a route.** It says how far
through the maze the player has worked without saying how to get further, which
is exactly the split §11.2 asks for: routing stays the player's problem, and
what this buys is knowing whether the last two minutes of driving actually went
anywhere. In a maze braided to 30% that is a genuinely hard thing to know.

#### Both ends are outlined, which is what makes it a PROGRESS read

The start's region and the exit's region are each outlined, never filled — the
fill is reserved for the region the player occupies.

**Marking only the exit gave the player one end of a measurement.** A lit square
at 6 of 16 says where you stand; a lit square *between a marked start and a
marked finish* says how far along you are. The exit was outlined from the
beginning and the start was not, so the box was doing the position half of its
job and leaving the player to remember the other end.

**It gives nothing away.** Both ends are facts the numbering already promises —
quadrant 1 holds `start_cell` and the highest holds `exit_cell` — so this draws
a statement the player has already been told rather than adding a new one. It
stays on the "have I been here" side of the line and still answers nothing about
which opening to take.

**Both are read from the maze's own cells, never from the first and last quadrant
NUMBER.** The numbering derives its ends from those two cells, so restating them
as 1 and `total` would be a second copy of that derivation — and it would go
quietly wrong the moment a generator moved either corner, which is exactly the
case the derived numbering exists to survive.

**An end the player is standing in is suppressed**, because the fill would sit
under the outline and the two would read as one muddled square. The occupied
region is the more urgent fact, and the count above the grid still says "1 of
16", so nothing is lost.

> **The start's colour separates by HUE, and the first attempt got that wrong.**
> A cool blue-grey was the obvious "quieter than the exit" choice and measured
> **invisible in a rendered frame**: it sits in the same hue family as the box's
> own grid and frame, so on the two sides where the start cell borders the outer
> frame it merged into it completely and the corner read as bare grid. The exit's
> amber was legible instantly — because amber is a *different hue* from
> everything around it, not because it is brighter. The start is now a **violet**,
> the one band left once amber is the exit, green is Path Indicator, white is the
> exit marker and the marker itself, red is the crash state (§8), and blue is this
> widget's own frame. Only a rendered frame shows this: every headless assertion
> was green while the outline was there and unreadable.

`SceneTest` asserts the start outline sits at `start_cell`'s region, that the
start is region 1, and that **the two ends are distinct regions** — an outline
marking one corner twice says nothing at all. Verified by pointing the start feed
at `exit_cell`: two named failures. The compendium's demo draws both ends too,
for the reason the demo exists — a grid with only a travelling light shows the
position half of the mechanic and not the progress half.

#### The compass tells the truth about north, and the exit is not in it

North is north: `-Y` on the grid, the direction `Maze.N` already means. **The
exit is in the SOUTH-EAST**, because the start is the north-west corner and the
exit is the opposite one.

**An "exit is always north" compass was considered and rejected.** Relabelling
the bearing so the exit reads north makes the compass a second route hint
wearing a cardinal costume — and it would disagree with the minimap, which draws
real cells in real orientation. Moving the exit to the north edge instead is a
generation change touching the solve path, the gate spacing and every measured
solve time in §8, to buy a property the quadrant number already gives for free:
**the exit is the highest quadrant**, whichever compass direction that is.

So the two lines together answer the corner question without either one lying.
The quadrant box says the exit is at 16 and you are at 6; the compass says you
are pointing west. The player draws the conclusion, which is the part that is
supposed to be theirs.

**The compass is one rank, like Gate Compass.** There is no second thing a
cardinal readout can do — it is either on or it is not, and a rank that added
eight-point bearings would be precision nobody routes on at 8x.

**It reads absolute, where Gate Compass reads relative.** Gate Compass shows an
arrow *relative to facing* ("turn that way"), because it is a bearing to a
target. This one shows the heading you are facing, because it is a statement
about orientation itself. Two absolute readouts would be redundant; two relative
ones could not tell you which way is north at all.

#### It is drawn as a physical compass: a fixed dial and a swinging needle

A ring with four cardinal ticks and a two-tone needle. **The dial is fixed and
the needle rotates**, which is how a hand compass works.

**That is the exact opposite of the minimap, deliberately.** The map rotates
because it shows the *corridor*, and at 8x "the corridor on my left is drawn on
the map's right" is not a translation anyone performs (§12). A compass shows the
**world's** orientation, so its whole value is that north stays where north is.
A dial that rotated with the player would just be the letter again, drawn larger.

**The needle's north half is red**, because that is the convention every physical
compass uses and it is worth borrowing outright — a player who has held one
already knows which end is north, so the widget needs no legend. It is the one
place a red is allowed here: red is the crash state (§8), but that read is on the
**player marker, in the world**, and a needle in an instrument at the top of the
screen is never mistaken for the racer going red. Inventing a non-red north for
consistency's sake would throw away the only piece of shared knowledge the shape
relies on.

**Two-tone, not one.** A single-colour bar reads as an *axis* rather than a
direction, and which end points north is the entire question.

**The letter is kept alongside the needle rather than replaced by it.** The needle
answers "which way is north" at a glance; the letter names the heading exactly. At
8x a needle a few degrees off is ambiguous where a letter never is, so the two are
not redundant.

**The FACING is carried into the widget, not re-derived from the letter.** The
needle needs an angle, and mapping the string back to a direction would be a
second copy of `Maze.CARDINAL_NAMES` to keep in step. `SceneTest` asserts the
widget carries the racer's own facing, that all four headings give **distinct**
angles — a mapping returning a constant would agree with the racer on whichever
heading happened to be current — and that north points **up**. A dial fed a stale
facing renders a perfectly plausible compass pointing north forever, which no
rendered frame would catch either, since north is a legitimate heading.

#### It is a HUD element, not a world object

Every other "have I been here" signal in the game is in the world — a landmark,
a spent gate, a mirror — and this one is not, because **it is a fact about the
whole maze rather than about anywhere in it**. There is no cell a quadrant box
belongs to, which is the same argument §7 makes for keeping Gate Compass on the
HUD after moving Path Indicator off it.

**TOP-CENTRE, under the HUD's top row, the two halves SIDE BY SIDE.** The
compass sits beside the quadrant box rather than in its own slot: the two are
read together, and a player holding only one gets that one alone.

**It used to be top-LEFT, stacked under the rear-view mirror**, which was where
the empty space happened to be rather than where the read belongs. Both halves
answer *where am I, and which way am I pointing* — a question about the corridor
dead ahead — so they now sit on the axis the eye already tracks. That is the same
argument §12 makes for the minimap moving to bottom-**centre**, under the marker:
the cluster, the marker and the map stack vertically, so checking any of them is
a flick along one line rather than a saccade into a corner and back.

**Side by side because the top-centre band is WIDE and SHORT.** The HUD's top row
ends at y=70 and the corridor vanishing point must stay clear, so the space
available there is horizontal. Stacking the pair would push the compass down into
the corridor the player is reading.

**Centred on the WHOLE cluster, grid plus dial.** Centring the grid alone would
push the compass off-axis by half its own width, which is what `SceneTest` is
phrased to catch — a one-pixel tolerance, not a band.

**It hangs off the HUD top row's measured bottom edge, never off a constant** —
the same rule that had it hanging off the mirror before. The widget sizes itself
from the shorter viewport edge, so a literal offset would be correct at one
screen size and overlapping at every other: the hard-coded-band trap §12 records
for the upgrade card row. `SceneTest` asserts clearance **at desktop and phone
sizes**, and still asserts it does not intersect the mirror — the check that the
move actually vacated the left column.

> **The upgrade toast was drawn straight through both, and only a rendered frame
> showed it.** The HUD's message band sat at a hard-coded `140`, which was clear
> for as long as nothing had ever been in the top centre — so the first frame
> after the move had *"GATE SIZE RANK 1"* written across the grid and the compass
> dial at once, leaving all three unreadable. The band is now pushed below the
> cluster's **measured** bottom rather than to a new literal, which would be the
> same trap one step along, and it is pushed when the box's visibility *changes*
> as well as on resize — the box appears the moment either line is taken, at a
> gate, so otherwise the toast announcing that very pick is the one drawn through
> the widget it just created. Verified by restoring the literal: it fails at both
> sizes, `message top 140.0 vs box bottom 229.5`.

Two things only a rendered frame caught, and both are the §12 lesson that *rect
clearance is not text clearance*:

- **The count label reached up into the mirror.** "12 of 16" was drawn at a
  negative offset above the grid, which put it outside this widget's rect and
  inside the one stacked above. The two boxes never overlapped; their text did.
  Both bands are now part of the box's own rect.
- **The cardinal letter was a smudge.** At 15px in the dim label blue it was
  illegible against the corridor, and a readout the player has to squint at is
  not one they check at 8x — it is the only orientation cue on screen. It is now
  22px in near-white, on a band wider than the glyph so the outline is not
  clipped by the rect edge.

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

---

## 7b. The Shop

Coins banked by clearing mazes (§5b) buy cosmetics. `CUSTOMIZATION -> SHOP`.

| Kind | Price |
|---|---|
| Colour | 12 |
| Pattern (decal) | 18 |
| Maze colourway | 25 |
| Marker shape | 40 |

**A SECOND path to a cosmetic, never a replacement for the achievement that grants
it.** Achievements still award for free; the shop sells what the player has not
earned. Both routes write the same `earned` set on `Unlocks`, so nothing
downstream — the pickers, the paired-table assertions §10 records — has to know
which way an item arrived.

**What the shop may sell is the whole safety argument.** Cosmetics only, exactly as
§10 narrows meta-progression: a shape, a colour, a decal, a palette. The line to
hold is unchanged — **if a purchase would change a number the racer reads, it does
not belong here.** Coins in the wallet buy nothing in a run, because every run
starts with an empty purse whatever the wallet holds.

**Priced by how much a kind CHANGES the marker, not by how many exist.** A colour is
a repaint; a shape is a different silhouette and is the half of the marker that
answers facing (§12), so it is the dearest. A palette restyles a whole maze and
sits between. A run banks somewhere under 20 coins when driven well, so a shape is
several good runs and a colour is roughly one — the shop is a reason to come back,
not a catalogue cleared in an evening.

**Stock is read off `Unlocks.lockable_ids()`, never off the four `Tuning` tables.**
Listing from the tables would put the **defaults** on the shelf — items every player
already owns and none can buy, which is a row that can only ever refuse. It also
means a cosmetic added later is stocked by construction, rather than needing an
edit here; `RulesTest` asserts every lockable id has a price, walking the list
rather than naming it.

**Buying something already owned is REFUSED rather than charged.** Taking money for
an item the player holds is the one outcome a shop must never produce, and it is
genuinely reachable since achievements grant for free. Every refusal **says why** —
a button that silently ignores a press reads as broken, which is worse than one
that reads as unaffordable, the same reason a locked palette chip states its
requirement.

**Three chip states, not two.** Owned, affordable, and out of reach: a chip the
player cannot yet afford has to read differently from one they can, or the shop
gives no sense of what to save for and becomes a wall of identical buttons that
refuse most presses.

**The rows SCROLL.** Four kinds against tables already running to 25 palettes and 19
colours is far more than a panel holds, and the alternative is the §8c overrun — a
panel sized to a band it outgrows, with CLOSE pushed off the screen edge.

**It sits under CUSTOMIZATION, beside MARKER and MAZE COLOURS**, because it sells
exactly what those two screens wear: a player who opens CUSTOMIZATION to change
their marker and finds it locked is one press from the screen that sells it.

**The wallet lives on `Unlocks`** — the one piece of state there that is not a
cosmetic, allowed for the same reason the cosmetics are: nothing in the simulation
may read it. It persists in its own `wallet` section of `settings.cfg` rather than
among the earned ids, since that section is a set of `id -> true` and a number
sitting in it would be read back as a cosmetic called "coins" by anything walking
the keys.

> **`Unlocks._save()` writes the player's real profile, so a harness that buys
> anything must set `suppress_save`.** Without it, `RulesTest` grants the player
> cosmetics and spends coins they never earned — the rule §12 records for
> `TouchShot` and `MarkerPickerShot` arriving in a third place: a tool must not
> write the state it is inspecting.

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
| Re-entering a cell already driven this maze | **−100**, once per cell |
| Travel or a turn on ground already driven | **nothing** — repeat ground pays 0% |
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

### Re-crossed ground earns nothing, and costs 100 once

Two rules working as a pair, and only the first is the anti-exploit one.

**Ground already driven this maze pays no points at all** — no travel income, no turn
award. **This is the fix for a real exploit.** A player sat near the exit driving back and
forth in one corridor and banked over a million points, and the time multiplier cannot stop
them: it is applied at *bank* time and floors at 0.20x, so a player who declines to finish
the maze never reaches that discipline, and a subtotal that grows forever beats any fixed
floor.

**The penalty was the wrong lever, and pricing was never going to work.** The rule used to
be −250 charged on *every* re-entry, on the reasoning that charging once per cell leaves a
loop "fully marked after one lap and free forever after". That reasoning is correct about
the loop and wrong about what funds it: the thing paying for a farming lap is the **turn
award**, at `60 × speed` — 360 a cell at 6x. A penalty has to out-price an award ten times
its size, and it never actually did. Measured across lap counts, a farmer beat an honest run
**at 250 too** (330,426 against 296,954 at 20 laps); closing it by penalty alone needed
**350**, which would have made ordinary backtracking punishing to fix a problem ordinary
backtracking never caused.

Removing the income kills it at source. A farming lap earns nothing, so the loop stops being
a pump and becomes pure elapsed time — and the time multiplier then does the work it was
always meant to do. Measured, a farmer now loses ground **monotonically at every lap count**
instead of peaking above an honest run.

**It costs an honest player nothing.** An optimal router never re-enters a cell, so it earns
precisely what it did before — verified, a full `RunTest` autopilot is unchanged at zero
repeats. What it does cost is a genuinely lost player, who drives their recovery lap for time
rather than points. That is the right way round, and it is the same statement §11.2 makes
about bad routing being punished by distance and time.

**A turn on repeat ground is still tallied, only unpaid.** The summary reports what the
player did, and withholding the points must not also erase the record.

**The penalty is now charged once per distinct cell, at 100.** With the earning rule doing
the anti-farming work, this number is free to be what it should be: a moderate, legible cost
for covering redundant ground. At 250-every-time it bled an ordinary run far too fast — a
couple of dead ends and one wrong loop cost thousands of points for reading the maze
imperfectly, which is what the maze is *for*. Measured on the wandering driver, the charge
fell from 35,250 to 6,800.

Once-per-cell is safe *because* the earning rule exists. It measures how much redundant
ground a route covered, which is the honest thing to charge for; the objection to it — that a
loop goes free after lap one — no longer bites, since lap two onward now earns nothing rather
than being merely under-fined.

**Both are flat, and neither scales with the Score Multiplier upgrade.** That line is a bonus
on points *earned*; applying it to a penalty would make backtracking more expensive the more
of it the player holds — an upgrade that punishes you for owning it. Same reasoning as the
flat crash penalty.

**Backtracking out of a dead end pays it too, with no exemption.** An exemption for "honest"
mistakes would require the game to judge which mistakes are honest, and a farming loop would
dress itself as one.

The racer tracks visited cells **per maze, not per run** — a new maze is new ground by
definition — and the record is written *before* `_on_enter_cell`'s early returns for gates
and the exit. Those cells sit on the solve path, which is precisely the ground a looping
player re-covers, so tracking them after the returns would have left the most farmable
cells in the maze free.

**The two flags are separate on purpose.** `cell_entered` carries `repeat` — true on *every*
re-crossing, gating the earning — and `first_repeat`, true only the first time, charging the
penalty. Collapsing them into one would force the two rules onto the same cadence, and they
genuinely want different ones: earning is a property of each crossing, the penalty a property
of the cell.

> **A single sample of a curve says nothing about its maximum.** The old assertion modelled
> **one** fixed lap count (60) and passed while the exploit was live, because a farmer's score
> peaks early and then decays as the multiplier bites — 60 laps sat past the peak. The check
> now sweeps lap counts from 1 to 400 and takes the worst. This is the §12 "did we get lucky"
> trap wearing different clothes: the fixture was not random, it was just one point.

**Measured against real play, not only against a model.** `RepeatProbe.gd` drives three
styles over the same maze 1:

| Style | Distinct cells | Cells charged | Penalty | Subtotal |
|---|---|---|---|---|
| Optimal router | 145 | **0** | 0 | +10,681 (finishes) |
| Wanderer (random turns) | 135 | 68 | −6,800 | −16,793 |
| Farmer (paces one corridor) | 9 | **9** | −900 | −823 |

**The optimal router pays nothing at all** — a distance-field driver never re-crosses ground,
so both rules are completely invisible to good play, and a full `RunTest` autopilot confirms
it at zero repeats across all five mazes. The farmer covers **nine cells** and banks
**zero**: its penalty is now trivial (−900), and what actually stops it is that ten thousand
laps of those nine cells would earn nothing. That is the same behaviour that scored over a
million points before this existed.

Note the wanderer's charge against the old rule: **−6,800 where it used to be −35,250**. That
5x drop is the point of the retune — an imperfectly-read maze should cost time and distance,
not tens of thousands of points.

`RulesTest` asserts the every-re-entry rule directly, and models a farming run that **must
score below an honest one**. That assertion is what the existing monotonicity check could
not give: every run it models *finishes its maze*, so all of them are disciplined by the
multiplier, and the exploit lives entirely in refusing to be.

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

## 8c. The End-of-Run Summary

A full-screen breakdown at the end of every run, on **both** terminal paths — a cleared run
and a death. Dying is when a player most wants to know what went wrong, so sending the
breakdown only to winners would withhold it from the run that most needs explaining.

It replaces a one-line HUD message that said nothing but the total.

**It shows:** the final score; a per-maze table of subtotal, time, multiplier and banked
score; run totals for time, clean turns, scraped turns, crashes and repeated cells — each
penalty with the points it cost; and the finishing build, every line with its rank.

**A full modal, unlike the gate screen.** §7 deliberately leaves the corridor visible behind
an upgrade pick because the player is going straight back to it. A finished run is not going
back, and this is the one screen in the game meant to be read slowly rather than glanced at
under time pressure — so the world behind it is a distraction rather than context.

**It recomputes nothing.** Every figure is read from `Score.maze_results`, the `Score`
tallies and `Upgrades.ranks`. A summary that derived its own totals could disagree with the
HUD the player was watching a second earlier, and the player would have no way to tell which
was lying.

**Repeated cells are shown with their cost, not just their count.** The penalty is new and
invisible while driving — a player who loses 12,000 points to backtracking needs to be told
that is what happened, or the score reads as arbitrary. This is why the penalty and the
screen shipped together: a rule the player cannot see the effect of is a mystery, not a rule.

**A partially-banked maze is marked with its percentage.** A death banks on gates taken
(§8b), so an unmarked row would look like the maze merely scored badly rather than having
been cut short.

**Dismissing it reports to `Shell` rather than tearing the run down.** `Game` emits
`run_dismissed` and `Shell` swaps back to the menu — the same shape as the trailer's
`finished` signal, and for the same reason: owning the mode swap is `Shell`'s whole job, and
a harness that loads `Game.tscn` bare simply never connects it.

### Three things only a rendered frame caught

`SceneTest` asserts the screen opens, banks correctly and reports back. None of that can see
one Control drawn over another, so `SummaryShot.gd` exists for the same reason `TouchShot`
does — and it found all three of these:

- **The live HUD drew straight through it.** Speed, gates, the timer and the barrier bars
  sat on top of the modal. Every one is a frozen number from a run that has *ended*, drawn
  over the screen reporting what those numbers finally came to — two accounts of the same
  run, one of them stale. The summary now hides what it covers and restores it on dismiss.
- **The panel height was a hard-coded band, and it overran.** 660px fitted the death screen's
  three maze rows and nine-line build *by luck*; a cleared run with five rows and a sixteen-
  line build pushed the last row off the screen edge and *"press SPACE or ESC to continue"*
  off entirely — so the best run in the game ended on a screen with no visible way out. This
  is the §12 hard-coded-layout trap exactly, and the fix is the same: a `CenterContainer`
  sizes the panel to its contents instead of a band guessed in advance.
- **A green multiplier beside a maze that banked zero.** The dead maze showed subtotal
  −13,060, a bright green x5.53 and a score of 0 — the row congratulating the player on the
  worst maze of the run. The multiplier was correct on its own terms (the maze *was* quick);
  it simply says nothing when there is nothing left to multiply. A maze that banked nothing
  now reads dim: neither good nor a penalty, just spent.

> The tool's own two shots came out **identical** at first. `_capture` ran in the same frame
> that built the new screen, and `process_frame` fires before the UI is drawn — so the second
> shot caught the first screen. Build on one frame, capture on the next. This is the same
> trap `GateSpentShot` records for camera aiming, arriving through the UI instead.

**The crash prompt has to be cleared, not faded.** It is a *held* message (§5.4), so a fatal
crash leaves it on screen; `clear_held_message` releases it into the ordinary 1.6s fade,
which would show through the modal for a third of a second. `HUD.clear_message` removes it
outright.

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

**The menu is painted art, not a live maze.** A background image and a logo, both in
`art/`, over which the title screen draws its columns. The "no 3D behind the menu"
rule still holds and for the unchanged reason — the trailer is the moving shop window,
and rendering a maze behind the menu would pay for it twice — but a still image is not
a live maze. It costs one texture and no simulation, so it buys the first impression
without taking that trade.

**The art has to be the game.** The background is a one-point-perspective neon corridor:
cyan on the left, magenta on the right, a lit vanishing point, a reflective grid floor.
That is a painted version of what the player is about to drive down, which is the only
reason it is worth the legibility cost below. Generic sci-fi scenery would not have been.

**One scrim over the art, and the columns keep their own.** The image is brightest at the
vanishing point — dead centre, directly behind the button stack — so white button text
needs the whole image dimmed before any UI lands on it. The per-column scrims stay on top
of that. They were written when the art "was not written yet and must not be able to make
either column unreadable", and the art existing is an argument for keeping them: it is
bright in exactly the place both columns bracket.

**Textures are loaded by path at run time, never `preload`ed.** `preload` resolves at
*parse* time, so a missing file is a hard parse error that takes `MainMenu` down with it —
and `ShellTest` and `MenuShot` both instantiate that class. Art that has not been dropped
in yet would fail harnesses that have nothing to do with art. Guarded through
`ResourceLoader.exists` first, so an expected absence does not put a red line in
`logs/errors.log` either; that log is the primary feedback channel and stops being worth
reading if it carries lines that are fine.

**The text title is the fallback, and is live code.** With no logo file present the menu
draws `MAZE RACER` as it always did. That is what every harness sees and what ships if the
file ever goes missing — a menu with no title at all reads as a broken build.

**A full-rect backdrop is identified by a group, not by its type.** `_place_left` moves
every column child to the left anchor when the menu splits in two, and skipped the
background by testing `is ColorRect` — a type standing in for an intent. A `TextureRect`
is not a `ColorRect`, so the background art was dragged into the left column and cropped
to it. `GROUP_BACKDROP` states the property directly: this node spans the screen. Anything
added later says so for itself instead of needing the filter widened again.

**`ShellTest` carried the same bug, and only real art could expose it.** Its
single-column-fallback check walked the menu's children skipping `is ColorRect`, so once
the backdrop became a `TextureRect` the test demanded a full-rect node be centred at 0.5
and failed — reporting a layout regression that did not exist. It now skips by
`GROUP_BACKDROP` too. Worth recording because the assertion and the code had drifted apart
in *identical* ways: a type test used as an intent test is wrong in both places, and
fixing only the code leaves the harness lying.

**The logo ships from a source with a real alpha channel, and every attempt to key one
from a flattened image was worse.** `art/logo.png` is trimmed and centred from a 2172px
RGBA original — nothing is keyed, smoothed or reconstructed. Measured against the keyed
attempts it replaced: **alpha-edge roughness 0.020, against 0.173 keyed from a checkerboard
screenshot and 0.124 after rebuilding the halo synthetically.**

**Why the keyed versions failed, recorded so nobody retries it.** Two flattened sources
were tried — a wordmark on a transparency checkerboard, and one on flat white:

- **On the checkerboard**, unpremultiplying dragged mid-grey into the partial-alpha band,
  so the "glow" came out **dark grey (93, 91, 103) around a core of (184, 197, 233)**. A
  halo darker than what it surrounds is not light; on black it read as grey wadding packed
  around each letter, bridging the gaps so MAZE became one blob rather than four glyphs.
- **On flat white**, the letter fills measured **252–255** — three levels off the plate —
  because that rendering put nearly all its colour in a thin outline. Every key came out
  either hollow or streaked, and the marks across the letters were the outline's
  anti-aliasing, which was all the tonal information the file had.

Both are the same lesson: **a flattened image has thrown away the alpha it is being asked
to reproduce, and no threshold recovers information that is not there.** The fix is a
better source, not a better key.

**A logo is centred on its SOLID artwork, not on its glow.** The menu centres the logo's
box, so whatever sits at the box's centre lines up with the button stack. The glow is
asymmetric — the right dash spills further than the left — so cropping to total extent left
the wordmark 10px off the buttons' centre line, which reads as sloppiness rather than as
anything explicable. The asset is padded so the solid letters are centred; measured at 0px
offset against the PLAY button.

**`LOGO_SIZE` tracks the asset's aspect ratio.** `KEEP_ASPECT_CENTERED` fits the art inside
the box, so a box shaped differently from the image leaves the logo undersized on one axis
with dead space on the other. The box is a bound, not a claim about the image — but it has
to be roughly the right shape, and it must be re-checked whenever the asset is replaced.

**Panels were opened up once there was something behind them to see.** The leaderboard
scrim (0.88) and the button faces (0.96) were chosen when the menu was a flat near-black
fill, where opacity cost nothing. Against the art they read as slabs pasted over a
photograph — the leaderboard in particular became a black rectangle with a hard vertical
seam down the screen, so the panel stopped looking like part of the menu and started
looking like a hole cut in it. At 0.62 and 0.72 the corridor carries through both and the
text stays legible, because `COL_SCRIM` has already dimmed the whole image before either
lands. **The rule is that the art is dimmed once, globally, and the panels then only need
enough fill to separate text from it** — every panel dimming it again independently is
what produced the slabs.

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

## 9b-2. Leaderboards and Seeded Runs

Three boards — **general** (any seed), **daily** and **monthly** (a maze everyone
shares) — served from the same `pistachio-kitchen` Firebase project the cookbook uses.
Full plan in `docs/plans/leaderboards.md`. The decisions worth keeping here:

**The seed is derived from the date, never fetched.** `Tuning.seed_for_date()` hashes
`YYYY-MM-DD`; every client computes the same number with no network call, so a daily run
starts instantly and works offline — only the *board* needs Firebase. Publishing seeds from
Firestore was rejected because it puts a round trip in front of the PLAY button, and a failed
fetch would mean no daily run at all.

**FNV-1a, not `String.hash()`.** The engine's hash is not contractually stable across Godot
versions, and a seed that changed on an engine upgrade would silently redraw every past daily
maze — making old scores incomparable with new ones on a board whose whole premise is that
the maze is fixed.

**The name is picked BEFORE the first run, not after it.** A one-time prompt on the first
PLAY, then never again. It was originally asked for on the end-of-run summary, on the
reasoning that a finished score is when a player has a reason to care what it is filed
under — and that is true, but it leaves a real hole: the run has *already posted* by the
time the summary draws, so a first score lands on the board as `anon` and is only renamed
if the player then fills the field in. A score good enough to reach a board is exactly the
one that must not be anonymous.

**It never blocks PLAY.** SKIP starts the run and posts as `anon`, and the summary keeps
its field so a name can still be set afterwards. A player who will not name themselves is
not a player who should be stopped from playing. The prompt is also skipped entirely when
there is no board to post to — desktop, every harness, or an unreachable service — since
it would otherwise be asking for something nothing will use.

**A dimmed menu is still a menu.** The first version drew only the full-screen scrim, and a
rendered frame showed the title landing on the logo's wordmark with the PLAY button visible
straight through the name field. The prompt needs its own filled card to sit on, or it reads
as text scattered over the screen rather than as something to answer.

**Anonymous auth, not the cookbook's email/password.** Nobody makes an account before their
first two-minute run, and a score that needs a signup to count is a score that gets thrown
away. The name is asked for at the **end-of-run summary**, which is the one moment the player
has a reason to care what their score is filed under. The cost — clearing browser storage
loses the identity, with no recovery — is real and accepted.

**Cheating: rules reject the impossible, and nothing pretends to do more.** A static site
cannot stop someone editing the page. Firestore rules bound the score, the time, the maze
count and the board; the document ID is pinned to `uid_board_seed` on the shared boards, so a
player holds **one entry per shared maze** and cannot flood a board by replaying it. Updates
must be an *improvement*, so a worse replay never lowers a standing entry and an attacker who
reached someone else's row still cannot vandalise it downward. Every score stores the **seed
it was driven on**, which is what keeps a future replay-validation upgrade possible; it is
deliberately not pretending to be one now.

**Two things the live service rejected that no local check could have caught.** Both were
found by driving the real endpoints with a real anonymous token, and both would have looked
identical from here — a board that silently never fills:

- **`string()` on a number does not rebuild the document ID.** The create rule pinned the ID
  to `uid_board_ + string(seed)`, and measured against the deployed rules a legitimate daily
  score was rejected with `1442907934` *and* `1442907934.0` as the suffix — the comparison was
  simply never true, so **both shared boards were unwritable**. The general board hid it
  completely, because that branch short-circuits before the comparison is reached: the one
  board that worked was the one that skipped the broken clause. The rule now matches the ID's
  *shape* (`_[0-9]+`) rather than rebuilding it, which keeps one-entry-per-player-per-board
  while leaving the seed's value to `scoreIsPlausible`.
- **`authorizedDomains` did not include `jonahbyu.github.io`.** Firebase Auth rejects requests
  from any origin not on that list, so even with anonymous sign-in enabled the live site could
  not have authenticated at all — and the symptom would have been indistinguishable from the
  sign-in provider still being off.

Verified against the deployed rules with a real token: a legitimate daily write is accepted, a
better score overwrites, a **worse score is rejected**, posting under another uid is rejected,
and a 999,999,999 score is rejected.

### It works on desktop too, over REST

`Leaderboard` carries two transports behind one public surface
(`docs/plans/leaderboard-desktop.md`): the JS bridge in a browser, and plain `HTTPRequest`
against the same project everywhere else. Desktop was originally left out on the reasoning
that the boards are a web feature — but that made the desktop shortcut a practice mode that
posted nothing and showed no history, since run history is Firestore-backed rather than a
local file.

**The refresh token is persisted, and that is what makes desktop one player.** A fresh
anonymous sign-up on every launch mints a *new uid each time*, so every run would post as a
different person and the history would always be empty. The token lives in `settings.cfg`
beside the display name.

**Desktop and browser are still different players.** Anonymous auth has no cross-device
identity — the browser's uid lives in browser storage and a desktop process cannot reach it.
Linking them needs a real signup, which this game deliberately does not ask for. A player who
uses both holds two entries under one display name; recorded as a known cost.

**The ID token lasts an hour and is refreshed before every post.** A run takes minutes, so a
credential that is merely valid *now* is not good enough — it has to survive the post at the
end. REST is switched off entirely when `DisplayServer` reports headless, so no harness ever
waits on a network.

### Three failures that only the live service could show

- **The autoload was never registered.** `Leaderboard` was missing from `project.godot`
  entirely — `git log -S "Leaderboard="` finds it in no commit — so the feature was **inert in
  every build shipped**, web included. The panel drew its offline state, which is exactly what
  it should do when the service is unreachable, so nothing looked broken.
- **The boards needed composite Firestore indexes.** A filter plus an order-by on a different
  field requires one, and none existed, so *every* board and history query failed with
  `FAILED_PRECONDITION` — on desktop and in the browser alike. Three are now deployed from
  `firebase/firestore.indexes.json`; they take a few minutes to build, and queries fail until
  the state reads `READY`.
- **A stale admin token read as an empty database.** Mid-diagnosis, a listing returned 0 rows
  and looked like proof that desktop writes were silently failing. The writes had landed; the
  *read* was using an ID token that had expired an hour earlier. An expired credential and an
  empty collection are indistinguishable if only the row count is checked — verify the token
  before believing the emptiness.

`tools/web-leaderboard-probe.py` is the matching instrument for the HOSTED build: it drives
the live page in headless Chrome over CDP, signs in through the real bridge, posts a score and
reads the board back. Curl against the same endpoints proves the *service*; only this proves
the *page* — the identical gap that let a silent web build pass every check. It runs headless
so it never opens a window.

`tools/web-touch-probe.py` is the touch equivalent, and it answers the one question no
headless harness can: what a browser actually DELIVERS for a single tap. Measured
against production, one finger raises **1 `touchstart` and 1 `mousedown`** -- the double
delivery behind the phantom-turn bug (§9d). It does not count turns; that is
`ShellTest`'s assertion, and exposing a counter to JS would put test scaffolding in
shipping code.

`LeaderboardProbe.gd` is the instrument, and it is not a test: it drives the real REST backend
against the live project and reports sign-in, the post state, the board and the history. It
exists for the same reason `MusicProbe` does — every harness runs headless with REST disabled,
so they prove the wiring and say nothing about whether desktop can actually reach Firebase.
Its own first version looked the autoload up from `_init`'s deferred call, which fires *before
autoloads enter the tree*, and reported the node missing from a project where it was correctly
registered.

**Transport is `JavaScriptBridge` into `shell.html`**, the shape the audio unlock established
(§12) — Godot has no Firebase SDK, and the REST API would mean hand-rolling token refresh.
The JS side **cannot call back into Godot**, so every async result is parked in a slot and
polled. Desktop has no bridge at all: the boards are simply empty there, and the game is
otherwise identical.

**Nothing in the simulation may read `Leaderboard`.** Same separation landmarks, music and
settings have — the autoload is absent in every harness, and a dead network must never be
what stops a run starting. The trailer is excluded from posting on `trailer_seed`, the flag
that already suppresses the HUD banner and the loadout pick.

### The menu is grouped into submenus, and the cog is gone

**Four entries at the root — PLAY, CUSTOMIZATION, LEADERBOARD, OTHER — each opening a short
list with a BACK row.**

**The flat list reached nine buttons, and nine do not fit a phone.** Measured on the 844×390
screen `MenuShot` and `TouchShot` both use: nine wrap to 5 rows of 2 and need **718 viewport
units against a 440-unit band**. The previous answer was `PHONE_HIDDEN`, which simply
switched five entries off — so **MARKER, UPGRADES and MAZE COLOURS were unreachable on the
platform most likely to be someone's only device**, and every cosmetic added to them was
invisible there. That is the same failure §9b-2 records for the leaderboards being hidden
with no other way in, and the same one §9d records for the board button that fixed it.

**Grouping fixes the count structurally rather than by shrinking buttons toward the tap
floor.** Shrinking was measured first and does work — at 480 units wide all nine fit as 3×3,
bottom at 384 against the 440 limit — but it spends the fix on making every target smaller
on the smallest screen, which is backwards. It costs desktop nothing: four entries is a
shorter read than nine, and the screens a player opens once a session are one press further
away than the one they open every time.

**`MENUS` is a table, and the root is just another row in it.** Adding a screen is a table
entry rather than an edit in several places — the failure §6 records for landmark density
and §9c for music tracks. **BACK is appended by the builder rather than declared**, so a menu
cannot be entered with no way out; relying on each row to remember its own escape is exactly
the per-entry duty that goes stale on the row nobody looks at.

**The trail back is a STACK, not a parent pointer**, so a menu reached from two places
returns where it came from.

**`PHONE_HIDDEN` survives, holding only QUIT** — which does nothing meaningful in a browser
tab. It is now a statement about one platform-inapplicable row rather than a way to make a
too-long list fit.

**The settings cog is no longer built.** SETTINGS is a labelled row in OTHER, and two doors
to one panel is two things to keep in step — §9d already had to rescue the cog once on a
phone, where its 17px rect sat *inside* the pause pad and was unhittable. The builder and its
drawn icon are kept rather than deleted, since `_place_cog` and `_tint_cog` are already
null-guarded and the in-game cog is a separate control; deleting live code to express a
layout decision would make restoring it a rewrite.

> **The submenu title landed across the logo, and only a rendered frame showed it.** Hung off
> `ROW_TOP` it sat at −86..−52, **inside the logo's own box** (−286..−75), so
> "CUSTOMIZATION" was drawn over the wordmark's *RACER*. It now hangs off the logo's measured
> bottom and the first row is pushed down by the space it takes. `ShellTest` asserts both
> clearances; verified failing at `title top -86, logo bottom -75`.

> **A flat font size is a COUNT, not a size** — the title's first version at 22 viewport units
> measured ~9 CSS px on the phone. It scales from the live viewport-to-screen scale like the
> buttons and the hint, which is the §9d lesson arriving on the one label added since.

`SubmenuShot.gd` is the picture half: every menu at phone dimensions, since the grouping
exists for that screen. `MenuShot` still shoots the root at three widths.

### The daily and monthly runs each get their own button

`PLAY` / `PLAY DAILY` / `PLAY MONTHLY` / `WATCH TRAILER` / `QUIT`. The two new
entries start the ordinary game on a date-derived seed rather than the wall clock.

**Everything below the menu already existed.** `Game.board` derives the seed and
decides which board the run posts to, and `Tuning.seed_for_board()` has answered all
three cases since the leaderboards landed — nothing ever *set* it, so the shared
mazes were reachable only from code. The change is three lines of plumbing:
`play_pressed` carries a board, `Shell.start_game()` takes one, and `_build_game`
assigns it **before `add_child`** — `Game._ready` derives `run_seed` from it, so a
board set afterwards arrives one maze too late, the same ordering `trailer_seed`
needs and for the same reason.

**A button per board, not a selector beside PLAY.** A three-way toggle would make a
daily run two presses and would need the lit board legible at a glance; a labelled
button says which maze it starts by being pressed. The stack height is derived from
the button count, so growing it from three to five costs only the space it takes.

**The stack stays top-anchored, and centring it was tried and is wrong.** Hanging the
row from its own centre keeps it balanced as it grows, but at five buttons every
centre that clears the bottom edge pushes the stack's top above the logo's baseline
(−75), so the title and the first button overlap. The two constraints genuinely
fight, and hanging from a fixed top below the logo is what satisfies both. Measured
at five buttons: the row runs −40..+342 with the hint ending at +402 against 450
available. **The number that needed deriving was the stack's height, not its top** —
the height reads the count and so was never the §12 trap; the top is a gap below the
logo, which does not change with the count.

`ShellTest` asserts the wiring through the **menu's own signal** rather than by
calling `start_game` directly, because that is the half that rots: a button bound to
the wrong board, or a signal that drops its argument, leaves `start_game` perfectly
correct and the player on the wrong maze. The seeds are read from `Tuning` rather
than restated — a literal hash would be a transcription check (§12) and would go
stale the day after it was written.

Verified across two separate processes: `DAILY` and `MONTHLY` produced identical
seeds and identical maze signatures both times, while `GENERAL` moved with the clock
and drew a different maze — which is the whole property the buttons exist to expose.

### The menu is two columns

Left: title and buttons. Right: the board. Behind: a background art piece, which is why the
art carries **one scrim over the whole image** rather than each column boxing itself off —
the art is bright at the vanishing point, directly behind the button stack.

**The split is decided on WINDOW width, not viewport width, and that is not a detail.**
`project.godot` sets `stretch/mode="canvas_items"`, so the viewport stays at 1600×900 whatever
the window does — `get_viewport_rect().size.x` is *always* 1600, and a test against it can
never fail. The phone shot came back showing a scaled-down desktop layout rather than the
fallback, which reads exactly like the fallback being broken when it was in fact never
reachable.

**Aspect ratio was tried first and is simply the wrong signal.** A handset in landscape
(844×390 = 2.16) is *wider* than a desktop 16:9 (1.78), so no threshold on aspect separates
them at all. Physical width does: 844 against 1600.

**Backdrop nodes are exempted by GROUP, not by class.** `_place_left` shifts every child into
the left column, so anything spanning the screen must be excluded or the art slides off with
the buttons. The original test was `c is ColorRect`, which stopped being sufficient the moment
the background became a `TextureRect` too — a group says what those nodes *are* rather than
what class they happen to be.

Two collisions only a rendered frame caught: the **settings cog was drawn underneath the
board's fourth tab**, having always lived in the top-right corner the panel now owns; and the
panel was inset top and bottom, so a scrim that stopped short of both edges read as a floating
card that had failed to size itself.

`MenuShot.gd` is the instrument, and it shoots **three widths** — wide, narrow and phone —
because the split is width-dependent and a single size proves nothing about the branch it does
not take.

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

**One tap must be ONE turn, and a phone does not send one event per tap.**
`input_devices/pointing/emulate_mouse_from_touch` defaults to **true**, so every finger
press arrives twice: the `InputEventScreenTouch`, then an `InputEventMouseButton` Godot
synthesizes from that same finger. `_on_pad_input` accepted both, so a single thumb press
fired the handler **twice** — the racer turned when the thumb landed and again a moment
later. In play that is a phantom input on every single turn, which makes the game
unplayable on the one platform the pads exist for.

**`accept_event()` does not stop it.** The emulated event is *generated from* the touch
rather than propagated from it, so it arrives however the first one was handled. This is
not an event-consumption problem; the two events have to be told apart.

**Every simpler fix is wrong, and both were tried and measured:**

- **Ignore mouse events outright** — kills the pads on desktop, where they are the only
  way to check this without a phone in hand.
- **Switch on `is_touchscreen_available()`** — a laptop with a touchscreen then loses its
  mouse. The device does not decide; a *specific event* being an echo does.
- **A sticky per-pad "a finger owns this" flag, cleared on the touch release** — the
  emulated mouse *release* arrives **after** the touch release, so the pad no longer
  recognises it and runs the release branch a second time, emitting
  `held_direction_changed` twice. `_held_dirs` survives that (erase is idempotent) but the
  signal does not, and Deep Breath and Overclock both listen to it. **A direction dropped
  twice is the same phantom input in different clothes.**
- **The same flag, never cleared** — the pad goes permanently deaf to a real mouse.

**So the guard is a timestamp, not a flag.** A touch stamps its pad; a mouse event on that
pad within `ECHO_WINDOW_MS` (250ms) is its echo and is dropped. The echo is generated in
the same input flush as the touch, so it is always a few milliseconds away, and no human
produces a genuine click that close to a finger press on the same pad. On a desktop no
touch ever arrives, so the window is never open and the mouse path is untouched.

**The timestamp deliberately outlives `clear_held()`.** That runs whenever the overlay
hides — a gate, a pause, the setting going off — and it clears *gestures*. An echo still in
flight is not a gesture, so clearing the stamp there would let the first tap after every
upgrade pick double-fire again.

> **Every pad test drove `_steer()` or a synthetic MOUSE event, so none of them could see
> this** — the bug lives in the event *dispatch*, not in the chord logic, and no harness
> had ever sent an `InputEventScreenTouch` at all. That is why a bug on every turn survived
> 83 passing assertions about the pads. `ShellTest` now drives a real touch **followed by
> its emulated mouse twin**, which is what a phone actually sends, and asserts one turn and
> exactly one held-direction change per edge. Verified by disabling the guard: four
> assertions fail, including `turns 2` from one tap.

> **A "mouse-only still works" check has to use a pad no touch has reached.** Tapping the
> pad the touch test just used lands inside its echo window, where suppression is correct
> behaviour rather than a bug — and reading that as a regression sends you at the fix
> instead of at the test.

**Measured on the live page, not inferred.** `tools/web-touch-probe.py` drives the hosted
build in headless Chrome over CDP, dispatches one real touch, and counts the DOM events
that result. Against production: **1 `touchstart` and 1 `mousedown` for a single finger**,
and the same pair on release. The browser synthesizes the mouse event itself, on top of
what Godot does internally — so the double delivery is real at both layers, and the
harness's hand-built event pair is a faithful model of it rather than a guess.

> Two things that made the probe report nothing while the events were flowing, both worth
> knowing before writing another one. **The touch events land on `window` and `document`,
> never on the `canvas` element** — a canvas-scoped listener counts zero. And **the tap
> point has to come from the canvas's `getBoundingClientRect()`**, in CSS pixels, not from
> `clientWidth`. Its first version got both wrong and printed `touchstart: 0`, which reads
> exactly like touch emulation being off.
>
> It says `INCONCLUSIVE` rather than `PASS` when it sees no touch at all, which is the only
> reason that was caught rather than banked as a green run — the CI-gate lesson (§12)
> applied to an instrument instead of a workflow.

**What the probe does NOT do is count turns.** Godot exposes no such counter to JS, and
adding one would put test scaffolding in shipping game code. The count is `ShellTest`'s
assertion; the probe's job is to show that the *delivery* the harness models is what a
browser really sends.

### The echo is not delivered to the pad that was touched

The per-pad echo stamp above fixed the double turn and left a second bug behind it, which
reads in play as **a turning slowdown on a straight corridor, for an input never made**.

**Measured on the live page, the order is not what the fix assumed:**

```
touchstart@10963   touchend@11115   mousedown@11115   mouseup@11115
```

The browser's synthesized `mousedown` arrives **after `touchend`** — 152ms later, at the
position the finger **lifted** from. A thumb that lands on one pad and lifts slightly to
the side therefore sends its echo to a **different pad**, whose window no touch ever
opened. The guard passes it through as a genuine click and the racer turns a second time.

On a straight corridor that second turn finds no opening, so it arms the buffer and
**expires into the −0.5x slowdown** (§5.2) a second or so later — a penalty arriving long
after the thumb left the glass, with nothing on screen connecting the two. Reproduced
headlessly: the same seed and 240 frames scores 1 slowdown after a tap and 0 without one.

**So the stamp is one timestamp for the whole overlay, not one per pad.** A device
delivering touches is not also being clicked by a mouse, so suppressing mouse input
briefly across every pad costs nothing real.

> **A "mouse-only still works" check can no longer escape the window by using another
> pad**, which is what the previous version did. It models a desktop by pushing the stamp
> out of range instead — a real desktop emits no `InputEventScreenTouch` at all, so the
> window is never open in the first place.

**A release must also verify the direction is actually held.** `released` is just
`not event.pressed`, so any release-shaped event ran the release branch — including one
whose press was never seen, which is routine: `clear_held()` runs on every phase change and
drops `_held_dirs` while a finger is still on the glass, so the eventual lift arrives with
nothing behind it. Emitting there reports a direction change the player never made, and
`Game` feeds that into `_set_held_direction`, which cancels an Overclock.

#### The echo is generated from the LIFT, so a held tap escaped the window

The overlay-wide stamp above fixed the cross-pad case and left a third bug behind it: the
double turn came back, along with phantom slowdowns and *"I have to press pause twice"*.

**One cause, and it is a timing gap rather than a routing one.** The stamp was taken on the
touch **press**, and the window was 250ms. Measured on the live page with a realistic 450ms
thumb rest:

```
touchstart@10388   touchend@10871   mousedown@10871
```

The browser generates its echo from the **lift**, so it arrives **483ms after the press** —
outside any press-anchored window still short enough to be safe. **Every press held longer
than `ECHO_WINDOW_MS` therefore escaped the guard entirely** and was taken for a genuine
click. That is the double turn, the phantom slowdown it expires into on a straight corridor
(§5.2), and the pause that toggles straight back off, all from one gap.

**The earlier fix appeared to work only because the probe held for 120ms.** A tap that brief
is not what a thumb does, and the instrument's unrealistic hold is what hid the bug from its
own measurement — the tool agreeing with the code because both were wrong about the same
thing.

**So the stamp is refreshed by every touch event, press and release alike.** What the window
must then cover is only the gap from the lift, which is a few milliseconds however long the
finger stayed down; the hold's length stops mattering, which is the property being bought.
`ECHO_WINDOW_MS` is 600 rather than something tight against the measurement, because the
cost is asymmetric: too short and a real tap fires twice, too long and a genuine mouse click
is ignored for a fraction of a second *on a device that has just delivered a touch*.

> **`ShellTest`'s first version of this assertion could not fail**, which is the same trap
> §9d already records one paragraph up. It aged the stamp *after* the release — but the
> release re-stamps, so the echo landed inside the window however the window was measured,
> and the check passed against the very bug it was named for. The hold has to be modelled
> between the press and the release. Verified by restoring the press-only stamp: it fails at
> `turns 2`, which is the bug exactly.

#### No time window can work, because the echo is racing the frame rate

The 600ms window shipped and **the double turn came back on production anyway**. Two
timestamp schemes had now been beaten in play — 250ms, then 600 — and that is the signal
that the approach is wrong rather than the number.

**The echo is not generated by the browser at all in the case that matters.** Godot's
`emulate_mouse_from_touch` synthesizes it **inside the engine**, from the touch, and
delivers it on whatever frame the engine gets to it. So its delay is a function of *engine
load*, not of the input stack — prompt when idle, late under load. A phone at 8x is
precisely the loaded case, which is why the window failed exactly where the game is
hardest and looked fine everywhere else.

Measured directly: an echo delayed past the window produces **2 turns from one tap**. No
value fixes that. It has to be long enough never to be beaten by a slow frame and short
enough that a desktop's genuine clicks stay responsive, and those two requirements do not
overlap — the first has no upper bound, because a frame can always be slower.

**So the guard is a latch on a fact rather than a bet on a clock.** Once the overlay has
seen a real `InputEventScreenTouch`, this device steers by finger, and every
`InputEventMouseButton` it will ever deliver *to a pad* is a synthesized twin of one.
Dropping them all is correct and costs nothing: a touchscreen player has no mouse to lose.
Desktop is untouched, because no touch ever arrives and the latch never closes; a laptop
with both takes the mouse until a finger lands and steers by finger from then on, which is
the input the player just chose.

**The latch is never cleared**, and that is the point — a player does not stop having a
touchscreen part-way through a run. Clearing it on a phase change is what would re-open
the mouse path for the first tap after every gate.

> **The DOM probe cannot see this bug at all, and that is why it kept reporting PASS.**
> Measured in the running game, one tap raises **1 `touchstart`, 1 `touchend` and 0
> `mousedown`** — the canvas takes pointer capture, so the *browser* synthesizes nothing.
> The duplicate is created inside the engine, downstream of anything JavaScript can
> observe. An instrument that watches the wrong layer returns a clean result forever.

> **A screenshot of the hosted page before the splash PLAY is pressed is the SHELL, not the
> game.** `tools/web/shell.html` draws its own title, key legend and PLAY button to unlock
> the `AudioContext` (§12), and the engine has not started behind it. A frame captured
> there shows an ancient-looking menu and reads exactly like Pages serving a stale build —
> which is how it was misdiagnosed once, as far as checking `pages/builds` and the deployed
> `.pck`. Click the splash button, wait, and only then capture.

> **Searching a `.pck` for a string proves nothing either way.** The export compresses
> them, so `QUIT TO MENU` and `LEADERBOARD` are both absent from a build that plainly
> contains them — and so are `PLAY DAILY` and `SETTINGS`, which have shipped for weeks.
> That control is what showed the search was the broken instrument rather than the deploy.

> **A headless Chrome does not report a touchscreen**, so `DisplayServer.is_touchscreen_available()`
> is false and the pads default OFF in every CDP probe — a pad tap then lands on empty
> corridor and the frame shows a crashed racer with no pads at all. Forcing the preference
> in a throwaway local export is the way to photograph them; the shipped `Settings.gd` must
> be restored the moment the build is made.

### Pause and settings are one control

They were two, and on a phone that is a **17 CSS px cog beside a 72px pad** — the cog also
still carrying the gear *character* that `MainMenu` had already abandoned for drawn polygons,
so it rendered as a tofu box. Two targets in one corner, one of them unhittable and the other
doing half the job. Worse, the cog's whole rect sat **inside the pause pad**, which is added
later and won every tap.

**Pausing now opens the settings panel.** The game is held, and the things a held game is for
— volume, controls, leaving — are on it. CLOSE resumes, which is the one press it always was.
It costs desktop nothing, since `ESC` already reaches the same method, and it removes the only
reason the in-game cog existed on a phone; the cog stays for a mouse and stands down whenever
the pads are up.

**QUIT TO MENU lives there too**, and it is the panel's first conditional row — the title
screen's mount has no run to leave, so the row would be a button that either does nothing or
re-enters the screen the player is already on. The panel **reports** the press through
`quit_to_menu` and `Game` re-emits `run_dismissed`, the same signal the end-of-run summary
uses, because owning the mode swap is `Shell`'s job.

### The menu's buttons were sized for a desktop too

The third feature caught by the viewport not being the screen. Measured on the 828x295 phone,
the six-button stack rendered **118 x 18 CSS px with 7.9px labels** — under half the 44px
minimum, on the platform where the menu is hardest to use.

**One column cannot be rescued by tuning, and the arithmetic is not close:** six buttons at
44px need **895 of the viewport's 900 units**. No separation tweak and no dropped hint fits
them. What a phone actually has is *width* — 2526 units against 900 — and a single column
spends none of it.

So the row is a **grid** that wraps into as many columns as the band needs, and the phone
shows a **reduced set**: the three ways to start a run plus the board. `MARKER` is a cosmetic
choice made once, `WATCH TRAILER` is a reel nobody opens on a phone they came to play on, and
`QUIT` does nothing meaningful in a browser tab. They are named rather than counted, so adding
a button later cannot silently push a different one off.

**The leaderboards were unreachable on a phone, not merely hidden.** Below
`TWO_COLUMN_MIN_WINDOW_WIDTH` the panel is switched off with no other way in. A `LEADERBOARD`
button now opens the **same panel** re-parented into a scrim — not a second board, which would
be the parallel-array trap (§6) with the off-screen copy the one that rots. It is rebuilt at
the screen's scale on the way in and back at 1.0 on the way out.

> **Rescale only while the panel is IN the tree.** The rebuild refreshes its rows, which reads
> the `Leaderboard` autoload through `get_node_or_null` — an *error* on a detached node rather
> than a null, which would put a red line in `logs/errors.log` on every open.

**A `PanelContainer` sizes to its CONTENTS and ignores an offset smaller than they need.** The
settings card's computed height said 676 and it laid out at **783**, running off the bottom
with CLOSE past the screen edge — the §8c overrun in a second place. The fix is to size the
*rows*, from a **measured** fixed cost (275, broken down as heading 95, spacers 14 and card
margins 164) rather than an estimated one, and to give the decorative `PANEL_RISE` back
exactly as far as any remaining overflow requires.

> **Guarding a degenerate viewport is not enough; guard the SCALE.** A headless run reports a
> stretch scale of **0.04 on a 64x64 dummy** — finite, comfortably above any near-zero check,
> and meaningless. Worse, a `Window` reports a plausible 1600x900 visible rect while its
> transform is still the dummy's, so a size check passes and the scale is fiction: measured,
> that produced **1100-unit buttons** in the harness while every assertion still read as
> plausible. The bound is on the scale itself (0.15–8.0), below any real device and far above
> the dummy.

> **A harness cannot change the window width**, so which buttons a phone hides is not
> assertable headlessly (`window_set_size` is ignored by the dummy `DisplayServer`, §12) —
> `MenuShot`'s phone frame covers it. What *is* asserted is the sizing, driven through the
> menu's own path with the scale forced: **recomputing the numbers in the test asserts the
> arithmetic against itself** and passes even when the constants are wrong. Verified by
> reverting to the flat desktop sizing, where the checks fail at `20.3 CSS px` and
> `7.9 CSS px` — the measurements that started this.

### The viewport is not the screen, and three bugs came out of that

`stretch/mode` is `canvas_items` with `aspect="expand"`, so the viewport height is pinned at
900 and the width stretches. **A phone whose canvas measures 828×295 CSS pixels gets a
~2526×900 viewport**, and everything is drawn at **0.33x**. Every desktop pixel constant is
therefore a third of its intended size on the one platform that most needs the room.

| | desktop | measured phone |
|---|---|---|
| Pause pad | 158×117 | **52×38** (44×44 is the published minimum) |
| Upgrade card | 320 wide, 17px text | **105 wide, 5.6px text** |
| Card row | 63% of screen | **40% of screen** |

- **The pause pad was unhittable, not unwired.** Every signal fired correctly in the
  harness and on the probe; the target was simply below the minimum both Apple and Google
  publish, and hard against the screen edge where the browser's own gestures compete. Now
  0.18 of the short edge, which measures 72×53 on that phone.
- **The settings cog sat entirely inside the pause pad** at every viewport size, and the
  pads are added to `UIRoot` after the cog — so the pad swallowed every tap and the cog was
  unreachable on the only platform with a pause pad. The pad now hangs below `COG_BOTTOM`.
- **The cards were too small *and* surrounded by empty space**, which is the tell that a
  constant was measured on the wrong surface. The row is now a share of the viewport and
  the cards **grow** as well as shrink; only shrinking left them at their desktop width,
  since 320px was never over budget in a 2526px viewport.

**Card text is sized from `get_stretch_transform()`**, which is the viewport-to-screen
scale the engine itself applies. Scaling the font by the card's *width* does not work — the
same card width is a different physical size on different screens, by a factor nothing
about the card can see.

> **A rendered frame caught what no assertion could: the steering pads were drawn over the
> upgrade cards**, arrow across the first card's text, rect over its tap area. They are
> added last so a tap reaches a pad rather than the world, and that puts them above the
> modal too. They now stand down off the **phase**, in one place, the way the mirror's
> freeze is derived — pause keeps its pad, since unpausing must stay reachable.
>
> The tool had to set the phase as well as present the screen. Forcing the cards open alone
> produced a frame that could not show the pads standing down, so the instrument was
> reporting on a state the game never enters.

**The pads report HELD direction, not only presses.** Deep Breath and Overclock (§7) both
need a key to still be *down* rather than merely to have been pressed, which the keyboard gets
from key-release events. The pads already tracked exactly this in `_held_dirs` for the reverse
chord and simply did not expose it — so both lines were **inert on a phone while working on a
desktop**, the tap-versus-key divergence this section exists to prevent, and no keyboard-driven
test would ever have seen it. It routes through the same `_set_held_direction` the keyboard
uses, so the two cannot drift apart.

**Releasing one finger of a chord reports what is STILL held, never a bare 0** — otherwise
lifting one thumb would cut a Deep Breath extension short mid-corner. Hiding the overlay does
report 0, for the same reason the chord state is cleared there.

> **`ShellTest`'s first version of that assertion was a false positive.** It pressed the second
> pad and then released the first, but the *press* emits too — so the sentinel already held the
> right value before the release ran, and the check passed with the release emit deleted
> entirely. Verified by breaking the code deliberately: it stayed green. The sentinel is now
> reset between the press and the release. A test that cannot fail is not evidence, and the only
> way to know is to break the thing it watches.

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

### Meta-progression — NARROWED, not deferred outright

**Cosmetic unlocks are IN. Everything else stays deferred.**

Marker shapes, colours and decals start locked and are earned by achievements, Geometry
Dash style — every one visible from the first run with its requirement named, so the picker
is a goal list rather than a menu.

**The rule was narrowed rather than broken, and the distinction is the whole argument.**
Every example this section originally named — *new upgrade lines, starting bonuses, maze
modifiers* — changes how a run **plays**, which is what "v1 is a single self-contained run"
protects. A marker shape changes nothing: §12 already asserts the simulation cannot read the
choice, by driving two racers side by side on one seed.

**The line to hold, forever: if an unlock would change a number the racer reads, it does not
belong in this system.** Persistent upgrade lines, starting bonuses and maze modifiers all
still fail that test and all stay out.

**A bare starting loadout**, deliberately: arrow, white, plain, maze 1's colourway, and
nothing else. A first-time player has no cosmetic choice at all, which is the cost, and it
buys the thing the feature exists for — every other entry in the picker is something to
earn. Asserted as a COUNT of one per kind, because the starting set grows by accident:
colour 2's default and the five authored palettes each looked like a separate necessity and
together made nine free cosmetics.

**The defaults can never be locked.** A saved name that no longer resolves falls back to
them (§12), so a locked default would strand a player with no marker — and a profile with no
unlocked palette could assign nothing at all. `RulesTest` asserts it.

**Fifty-eight achievements against fifty-six cosmetics** — 8 shapes, 19 colours, 8 decals
and 25 palettes. The set grew on the axes it had missed: **speed of solving** (`maze_results`
records per-maze time and multiplier, which nothing read for a long time), **consistency**
across a whole run rather than a single peak moment, and the **extremes of the damage
economy**. A player can be fast and scruffy or clean and slow, so these do not fall out of
the thresholds that were already there.

**No two achievements may fire on the same condition**, and this is asserted by sweep rather
than by reading. Two goals with one condition unlock as a pair, which spends two entries to
ask one question — and it is invisible, since both look correct alone. The sweep found three
real collisions that had shipped: the four authored-palette grants duplicated the four
maze-progress *shape* achievements exactly, `palette_orchid` duplicated `clear_run`, and
`palette_cobalt` duplicated `flawless`.

> **A field held CONSTANT in the sweep makes everything that reads it look identical.** The
> first version pinned time, per-maze score and gate progress and reported **116 pairs**,
> almost all of them false. It also could not produce a run that *reaches* the last maze
> without clearing it — ordinary play, the player died there — so "reach maze 5" and "clear
> all five" appeared identical when they are not. Randomised and seeded, the real count is
> **zero across 4000 runs**.

**The achievement table and the cosmetic tables are asserted paired in BOTH directions.** A
cosmetic no achievement grants is unreachable forever; an achievement granting a typo is a
goal with no reward. Both fail silently and neither shows in a rendered frame — the picker
simply displays a locked square for good. Verified by pointing one grant at a colour that
does not exist: two failures from the one typo, one from each direction.

**Requirements read data the game already keeps** — `Score`'s tallies and per-maze results,
and the finishing `Upgrades`. Peak speed is the one addition and the only change this
feature makes to a file the simulation touches. The gate achievement reads `progress` off a
banked maze, which §8b already defines as gates taken over gates available, rather than
growing `Score` a field to suit it. **Do not add a field to `Score` to satisfy an
achievement** — pick a requirement the existing data supports.

**Evaluated at `_post_run` and nowhere else**, whose own comment already calls it the only
point at which a run is genuinely over. Not during play: an unlock popup over a corridor at
8x is a distraction placed exactly where §11.3 says the player has no attention to spare.
It sits **before** the leaderboard guard, which returns early when that autoload is absent —
awarding after it would make unlocks depend on the network being reachable.

> **A script whose `class_name` matches its autoload name fails to parse** — *"Class Unlocks
> hides an autoload singleton"* — and the autoload then never loads at all, which reads
> exactly like forgetting to register it. `Music`, `Settings` and `Leaderboard` all omit
> `class_name` for the same reason. `ShellTest` asserts the registration, and caught this
> immediately: §9b-2 records `Leaderboard` shipping **inert in every build for weeks**
> through the same hole.

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
   **Amended:** contact is no longer free — every wall touch costs a flat 1 HP (§5.1). The
   ceiling is now about how *cheaply* a good player brushes, not about brushing for nothing;
   what the barrier still buys is the difference between one point and a full crash.
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

### The rear-view mirror

**A small box in the top-left corner showing the corridor behind, live, at all times.**
Free and always on, from the first frame of maze 1.

**It is safe to give away because it answers "have I been here", never "which way".** That
is the same line landmarks (§6) and spent gate markers (§7) sit on, and it is what keeps
the mirror from cannibalising Path Indicator, Gate Compass and Golden Trail — three *paid*
lines all sold on answering the route ahead. Everything a mirror can show is ground the
player has already driven. What it adds is **memory**, not routing: a corridor you are
about to reverse into is one you can see before committing the −0.75x (§5.3), and a
landmark or spent gate you have passed stays legible a moment longer than the eye alone
would keep it.

**It renders the real world through a second camera, sharing the main `World3D`.** That
sharing is the whole construction: the maze, the marker, the gates, the Path Indicator
strips and the Golden Trail in the mirror are the *same nodes* as on screen, so nothing can
drift out of step with the main view. A separate scene would be a second copy of the world
to keep in sync — the parallel-array trap of §6 and §9c wearing different clothes. Verified
in a rendered frame: the mirror picks up each maze's palette and has drawn a landmark and a
green floor strip in it, neither of which a faked view would have.

**Top-left, under the speed row, because every other corner is spoken for.** The timer's
width *changes past a minute*, so nothing may share its line (the §9d collision); bottom-
left is the barrier and integrity bars; bottom-centre is the minimap. Top-left under the row
is the one band empty on both platforms — the touch pads are bottom-anchored and the pause
pad is top-*right*.

**Aimed off the racer's facing, not the camera's trailing yaw.** The chase camera lags
through a pivot deliberately, so the swing reads smoothly and the turn freeze pays for it
(§2) — but a mirror that lagged would spend every corner showing the wall it was in the
middle of leaving. The mirror is an instrument; it points behind you the moment you are
facing the new way.

**It freezes off the phase, in one place, rather than beside each of the seven sites that
blur the minimap.** Those sites blur because each knows it is opening a modal; the mirror
only cares whether the clock is stopped, so deriving it from the phase means a phase added
later cannot forget. It **stops rendering** rather than blurring — it only ever shows ground
already driven, so there is nothing to scramble, and what is being refused is a free look at
a static world on a stopped clock (§2, §7).

**Sized off the shorter viewport edge, with a floor and not a ceiling** — the §9d lesson,
that a pixel is a count rather than a size and a pixel *cap* hands the smallest screen the
smallest box.

Two things only a rendered frame caught, both fixed:

- **The frame cut through the maze name.** The top row's band ends at y=70 and the mirror
  was placed at 86, so the two *rects* did not overlap — but the maze name and gate count
  sit on the row's baseline, well below its nominal top, and the text did. Rect clearance is
  not text clearance.
- **The view was 40% empty ceiling.** A 95° lens over a 3m corridor sees a lot of nothing
  above the wall line, and aiming *below* the eye — the intuitive way to frame a mirror —
  only adds more of it. The aim now sits slightly *above* the eye, trading ceiling the
  player cannot use for the floor grid and wall bands where every recognisable feature is.

`SceneTest` asserts the wiring — most importantly that the sub-viewport shares the main
world, since a `SubViewport` silently builds its own empty one otherwise and renders as flat
background, which looks like a mirror that is merely dark rather than one wired wrong. It
also checks the camera faces opposite the racer, rides with them, and that the box clears
both HUD bands **at two sizes**, desktop and phone. `RearViewShot.gd` is the picture half:
it **seeks a corner** rather than shooting on a timer, for the reason `PaletteShot` seeks a
junction — a straight corridor shows two identical walls receding, which is exactly the
frame that cannot tell a working mirror from one aimed forward.

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

### The camera's catch-up is the player's to set

**A `CAMERA` slider on the settings panel, 0..50.** 0 is a snap — the view is on the new
corridor the frame the racer pivots. 50 trails so far behind that the camera is still coming
round many cells later, so it is genuinely *not always behind you*. Default is **20**.

**It went 0..10 → 0..20 → 0..30 → 0..50, and each growth bought something different.** The
first doubling bought **resolution**: both ends held, so the dial became finer rather than
laggier. The second moved the **DEFAULT** off the midpoint, adding ten notches of lag above
it. The third lowered **`CAM_YAW_RATE_SLOW` itself** — the first time the dial's slowest
camera actually got slower, rather than the dial merely reaching further along the same curve.

**The old "not below about 2" bound was measured and found already breached.** That comment
justified 2.5 on the §11.3 rule that the view must not still be swinging when the next
junction arrives — but at 2.5 the swing takes **867ms to settle, which is 4.3 cells at 5x**.
The number was not the edge of the rule, it was just the slowest rate anyone had asked for.

**What the rule actually protects is that the corridor is READABLE when the player has to act,
not that the swing has finished.** Measured as the share of a 90° completed after one cell:

| rate | @1x | @3x | @5x | @8x |
|---|---|---|---|---|
| 2.50 (old slowest) | 97% | 81% | 74% | 68% |
| **1.00 (new slowest)** | **73%** | **47%** | **41%** | **35%** |
| 0.80 | 65% | 40% | 34% | 29% |

At 1.0 the player is 41% round after a cell at 5x and the corridor is resolving — heavy lag,
but the view is still arriving. **Below about 0.8** it stops being a lag and becomes a camera
that never catches up, which is the fault §11.3 forbids.

**The default has stayed on notch 20 across both of the last two changes**, which is what
`CAM_DEFAULT_DIAL_FRACTION` is re-solved to preserve — it went ½ → ⅔ → ⅖ while the *notch*
never moved. The shipped camera is the one number a player who never opens the setting is
entitled to keep. Measured across the whole dial: 0:62.90, 1:57.90, 10:27.47, **20:12.00**,
30:5.24, 40:2.29, 50:1.00, with notch 20 landing at exactly 12.000000.

**Lowering the slow end also fixed a wasted stretch at the fast end.** On the 0..30 dial
`SNAP` had to rise to ~276 to keep the default on notch 20, and anything above 60 closes the
whole angle in one frame at 60fps — so **notches 0–9 were all the same rigid lock**. At
`SLOW = 1.0` the fast end re-solves to 62.9, barely above that threshold, so notch 0 is still
a true one-frame snap and notch 1 is already distinguishable from it.

**The curve is reshaped on every one of these, not restretched, so a saved setting does NOT
carry across at a multiple of its old number.** A `settings.cfg` holds a bare notch: a player
on the old 0..30 maximum (notch 30, rate 2.5) lands on **rate 5.24** here — a snappier camera
than they chose — and has to travel up the longer dial to get it back.

`RulesTest` asserts the default lands on a **whole notch** — the slider steps by 1, so a
default at 19.4 would round-trip to the right rate and still be unreachable by the control the
player uses — that it sits at the **declared fraction** of the travel, and that the **last
notch is still the slow end**. Verified by moving the fraction to 0.61: two failures, at
`got 12.492489, expected 12.000000` and `got 18.000000, expected 18.300000`.

**A RATE, not a duration, and that is what keeps it a view setting rather than a game rule.**
The turn freeze is a rule: it holds the racer still, it costs run time, and Snap Turn buys it
down (§2, §7). This dial does not touch it. What it changes is only how much of the swing the
camera spends *inside* that hold — which is a question about the eye and nothing else.

**There is no longer a freeze multiplier on top of it** (§2), which means the dial now
governs the turn outright. It used to be multiplied past its own fast end during the one
moment the player is actually watching the camera move — so the setting that was supposed to
control cornering was the setting cornering ignored.

**So the simulation still cannot read it.** The racer pivots, freezes and resumes identically
at every value. `RulesTest` asserts that directly — two racers on one seed, driven the same,
requiring they never diverge *and* that their freezes never differ — which is the same
separation the marker shape and the maze palettes have.

> That separation check's first version **ran 900 frames with zero freezes**, because it
> pressed a direction on a fixed interval: the racer parks against the first wall it meets,
> and `request_turn` returns immediately on a `PARKED` racer. It is now routed toward the
> exit through `request_turn`, and un-sticks. **Not `_run_clean`**, which assigns `facing`
> directly — that rotates the racer without ever *resolving* a turn, so it never freezes, and
> the dial only touches the swing onto a new heading. The "was exercised" guard is what
> caught it; without one the check would have passed while asserting nothing.

**The curve is GEOMETRIC between the ends, not linear.** Rate is a reciprocal-feeling
quantity: the visible difference between 90 and 60 is nothing, while the difference between 4
and 2.5 is the whole top half of the dial. A linear map spends most of its travel where
nothing changes and crams every setting anyone would pick into the last two notches.

**`CAM_YAW_RATE_SNAP` is DERIVED so the shipped rate lands on a whole notch.** A hand-picked
snap rate and a whole-number dial are two incompatible demands — with the ends chosen
independently the nearest notch to the shipped 12.0 was **10.48**, so the setting a player
never touches would not have been the camera the game shipped with. Solving for the **endpoint**
fixes that by construction: `SNAP = (DEFAULT / SLOW^f)^(1/(1-f))`, where `f` is
`CAM_DEFAULT_DIAL_FRACTION`. At f = ½ that reduces to the original `SNAP = DEFAULT² / SLOW`,
the geometric mean of the ends. `RulesTest` asserts the round trip *exactly* rather than
within a tolerance, because a loose one hides the thing the derivation exists to guarantee —
verified failing at 10.48 with the ends picked by hand.

**That derivation is why every dial extension needed no arithmetic.** Going to 20 kept f = ½,
so the default simply moved from notch 5 to notch 10 and stayed the same camera. Going to 30
moved f to ⅔, and the fast end re-solved on its own to keep the default on notch 20 — the slow
end never had to move, which preserved the maximum lag. Going to 50 moved f to ⅖ *and* dropped
the slow end to 1.0, and the fast end re-solved again to hold notch 20 at exactly 12.000000.
A hand-written default would have had to be re-derived by hand three times and would have been
the one number nobody checked.

> **Two instruments restated the old maximum as a literal and would have gone silently
> half-blind.** `RulesTest`'s monotonicity sweep ran `range(1, 11)` and `CamSensShot` shot
> `[0, 5, 10]` — against a 20-notch dial the first covers only the notches that already
> worked and the second photographs the fast half three times while never capturing the new
> slow end, which is the one frame the tool exists to produce. Both now read the bound off
> `CAM_SENSITIVITY_MAX`. The sweep's guard measures **what the loop actually walked**, not
> what the dial says it should have: a guard phrased against the constant passes happily
> while the loop beside it still stops at a stale literal. Verified by restoring the literal —
> it fails at `walked 10 of 20, reached 10.0`.

> **`CamSensShot` steered by indexing a `[0,1,2,3]` table, and `Maze` directions are BIT
> FLAGS** — N=1, E=2, S=4, W=8. So `order.find(r.facing)` returned **−1 for every real
> heading**, no turn was ever requested, and the tool only caught pivots the autopilot
> happened to make on its own. That is why `pivot found: false` moved between runs *on the
> same seed*: it was luck rather than the dial. It now compares against the racer's own
> `left_direction()` / `right_direction()`, and a miss is `printerr` rather than a quiet
> `false` printed beside a saved file — a frame with no pivot in it is indistinguishable from
> the dial doing nothing, which is the one thing this instrument must never say by accident.

**The slow end stops at 1.0.** Below about 0.8 the view has covered under a third of its swing
by the time the next junction arrives at 5x, and a camera that never catches up stops being a
lag and starts being a fault: §11.3 says every timing demand must be visible before it is
demanded, and a corridor the player cannot see yet is the one thing no preference should be
able to buy.

**`SceneTest` asserts the dial is actually WIRED**, by driving `_process` and measuring the
yaw the camera really moved. Nothing in `RulesTest` can see this: a dial that maps beautifully
and is then ignored renders a completely plausible game.

> **Its own first version could not fail.** It re-derived the swing from `game._cam_yaw_rate`
> in a local loop, and **passed against a deliberately hard-coded `12.0`** in the yaw update —
> it was reading the field the break did not touch, and restating arithmetic the game was no
> longer performing. Driving the real `_process` is what makes it evidence. Verified failing at
> `snap 0.4118 vs lag 0.4118` — the identical figure at both ends being the hard-coded rate
> exactly.

**Both camera invariants are re-asserted at the dial's extremes**, because the dial changes
camera *geometry*: `back` is derived from `_cam_yaw`, so a lagged eye sits where a snapped one
never does, and the default-dial pass cannot see it. Measured: zero clipped frames and zero
blind frames at both ends over 2000 frames each.

**What a lagged camera legitimately shows is more of the maze**, and that is the cost of
picking 10 rather than a bug. Pointing across the corridor rather than down it, the eye sees
over wall tops at a distance. `CAM_HEIGHT` is unchanged at 2.3 and still under the 3.0 wall,
so the §12 height rule is intact — the flattening it forbids comes from *raising* the camera,
and nothing here does.

`CamSensShot.gd` is the picture half, and it **seeks a pivot** rather than shooting on a
timer, for the reason `PaletteShot` seeks a junction: at rest both ends of the dial look
identical, since the swing has already finished. It shoots a fixed number of frames *into* a
turn at each end, which is the only frame pair where snap and lag are distinguishable. Its
own first run reported `pivot found: false` on two of three shots because it did not
un-stick a parked racer — a frame with no pivot in it is indistinguishable from the feature
doing nothing.


### The marker is the player's to pick — shape, colour AND pattern

**A picker on the main menu offers the inner shape, a colour and a decal.** Purely cosmetic,
chosen once and remembered, and all three are unlocked by achievements (§10).

**This section previously read "its colour is not", and that has been reversed.** The
reasoning below is kept because it explains the constraint the new design works within — the
history is what a future reader needs, not a deleted paragraph.

- **Near-white was mandatory, and is now only the default.** The marker went white because
  maze 3's palette turned the walls green and the thing the player steers with matched the
  scenery it has to be picked out from. A free colour picker hands that failure back
  *chosen* — a player who picks lime is harder to see in The Vault. **Jonah asked for the
  free picker after that objection was put**, so it is a decision rather than an oversight,
  and the cost is real and stays the player's. The palettes are deliberately **not** excluded
  from the swatches: hiding the colours that cause the problem would be pretending to offer a
  choice while removing its consequences. The picker previews the state colours instead, so
  the cost is visible before it is paid.

**What is NOT given away is the state read, and that is what makes the free choice safe.**
The colour goes on the **inner mark**; the **ring stays the state channel** and is never
player-coloured. Scrape-amber and crash-red override **both** surfaces, so the read is a
**transition rather than a hue** — a player who picks crash red still sees their marker
change on a scrape. `SceneTest` asserts exactly that, and asserts it with a non-state colour:
an earlier version set the player colour *to* crash red, which made the correct code and the
regression produce the same value, and the check passed against the very bug it was named
for.

**That also fixed a defect this section already recorded.** `update_state` recoloured only
the ring, so a scrape left the inner mark pure white and a frame with the barrier visibly
half-drained was pixel-identical to a clean one — on the larger of the two surfaces, and the
one the trailing camera actually sees. The colour feature and that fix are the same change.

#### Two colours: the mark, and what fills the decal's cuts

**The player picks two colours.** The first is the mark; the second fills the decal's cuts.
The pattern row is hidden when `PLAIN` is selected, since a plain mark has no cuts to fill.

**A dark seam separates them, and it is the mechanism rather than decoration.** The inlay is
drawn dimmer than the mark (`INLAY_ENERGY`) and inset from the cut, so a gap of unlit surface
runs around every piece. Without it, two bright colours meeting edge to edge merge into one
shape on an unshaded surface — the same saturation failure that forced the decal to become a
hole. **No contrast rule between two independently chosen colours can prevent that.**

> **This section used to end "a seam guarantees the read at any pair", and that is measured
> false.** Shot in a real corridor against a cobalt control: cobalt draws two unmistakable
> bands, and **white-on-white draws a plain grey arrow with no pattern visible at all** at the
> trailing camera's angle. The seam *separates* two colours; it does not manufacture a second
> one where none exists. The claim was written from the construction rather than from a frame,
> which is the §12 lesson about the decal itself arriving one layer up.

**So the two defaults are the SAME colour, and `Settings` separates them when a decal first
goes on.** Colour 2 defaults to white alongside the mark, so a fresh profile owns exactly one
colour rather than two — the default decal is `PLAIN`, which has no cuts to fill, so nothing
is drawn in colour 2 until a decal is earned. `set_marker_decal` seeds it at that moment, and
only while the two are still equal, so a player who deliberately matches them later keeps it.

**The seeded shade is DERIVED from the mark, never taken from the table.** Every colour but
the default is earned, so seeding from `MARKER_COLOURS` would hand out a locked cosmetic
through a back door the picker's own swatch rows carefully guard. Darkening the player's own
mark grants nothing — it is the colour they already have, dimmed — and `RulesTest` asserts
that the result matches no table entry. Verified in a frame: the seeded shade reads as
clearly as the cobalt control.

**The fill is built from the same cutters `_cut_decal` subtracts**, intersected with the
outline rather than removed from it — so it is exactly the shape of the hole by construction,
and the two can never disagree about where the pattern is.

**The inlay follows the state colours, darkened rather than matched.** Leaving it alone would
keep the pattern in its resting colour on a marker that has gone crash-red, reading as a
stuck patch; matching it would merge the two surfaces exactly when the player most needs to
recognise their own marker.

**The two defaults are now IDENTICAL — both white — and cobalt is earned.** They differed
precisely so a white pattern on a white mark could not read as a broken decal, and that
concern is real; it is answered by seeding at the moment a decal is taken rather than by
spending a second free cosmetic on it. Cobalt was unlocked from the start purely to be the
second default, which is a cosmetic nobody had to earn — the mirror of the "achievement
granting something already held" bug, and now asserted in both directions.

### Maze palettes are the player's to assign, one per maze

**Unlock a colourway by reaching the maze that wears it, then assign any unlocked palette to
any maze slot.** `MAZE COLOURS` on the menu.

**Whole palettes, never a single hue, and that is the whole safety argument.** A palette is
six interlocking colours — wall, grid, floor, ambient, fog, emission — and §8 records two
separate bugs from mixing them wrong: maze 3's green ambient lighting every wall face in the
same hue as its own neon, and ember's yellow grid driving ambient warm until every wall
turned milky brown with the floor grid washed out against it. **Both came from DERIVING the
rest of the palette from one colour**, which is exactly what a per-hue picker would have to
do. Every entry offered is authored and tuned as a set, so no assignment a player can make
reproduces either failure.

**Twenty-five colourways: maze 1's, unlocked, plus twenty-four earned.**

**Displaying a colourway and being able to REASSIGN it are different rights, and only the
first is free.** All five authored palettes were briefly unlocked, on the reasoning that a
first run must show the game as written — and that reasoning is correct but does not need
the unlock: `Game` resolves an unassigned slot through `default_palette_id()`, which never
consults the earned set, so **every maze still wears its own hue on a fresh profile** with
only one palette owned. The escalation §8 tuned is intact either way.

What the five free entries actually bought was a screen that opened fully stocked. They were
simultaneously every maze's default *and* every slot's alternative, so `MAZE COLOURS` had
five ready choices on it and nothing read as earnable — the failure being that the count of
*visible* unlocks, not the count of *reachable* mazes, is what makes the screen a goal list.
What is earned now is the right to move a colourway onto a slot it does not belong to.

**Maze 1's is the one that can never be locked**, since a profile with nothing earned could
otherwise assign nothing at all — a screen with no legal move on it. Index 0 rather than a
literal, since `default_palette_id()` maps maze N to `PALETTES[N]`.

**The four "reach maze N" achievements grant the mazes' OWN colourways**, which is the
pairing worth having: reaching The Ember is what earns the right to put ember somewhere
else. The reward is the thing the player just drove through, and needs no explaining. The
four generated palettes that previously held those slots moved onto score, speed and
survival — two goals sharing one requirement unlock as a pair, which spends two entries to
ask one question.

**`RulesTest` asserts the starting set by COUNT, not by name**: exactly one of each kind. A
named check would have to be widened every time a cosmetic is added, and widening it is
exactly how the palettes reached five. Verified by restoring the old behaviour, where it
fails at `a fresh profile has exactly one palette (5)`.

**The twenty extras are GENERATED against a measured rule, not hand-picked**, because the
failure mode is invisible in a swatch. Ambient is mixed from the **grid** colour
(`Game._apply_palette` blends it 20/80 toward neutral), and warm ambient reads as a *lit
surface* where cool ambient reads as *shadow* — which is what turned every wall milky brown
when ember's grid was yellow.

Measured across the five authored palettes, ambient R−B runs **−0.222 (cyan) to −0.026
(ember)**, ember being the one that had to be pulled back. So the bound is ember's own value,
and every generated palette shifts its grid hue toward blue in proportion to how warm its
wall is — ember's correction, applied systematically. The worst of the twenty lands at
**−0.032**.

`RulesTest` asserts the rule over the **whole table**, so a palette added later by hand
cannot reintroduce the failure silently. Verified by giving one a yellow grid: it fails by
name at **+0.018**.

**The achievements spread across different axes** — progress, score, speed, cornering,
scraping, build width, and even failure — so no single style of run sweeps them. A player who
never crashes never earns CRIMSON; one who never scrapes never earns JADE.

**Maze 1's palette is never lockable.** A profile with nothing unlocked could otherwise
assign nothing at all. Every maze also defaults to *its own* authored colourway, so a fresh
profile sees exactly the game as written — the identity §8 tuned, with braid factor rising as
the hues get colder.

**`Game` resolves the assignment once**, where `palette_index` is set, so the mesh, the
environment and the HUD banner all read one answer. Three separate lookups would be three
chances for the world and the banner to disagree about what colour a maze is.

**The trailer is excluded**, gated on `trailer_seed` like the HUD banner and the loadout
pick: the reel is a fixed shop window of the game as authored, and a player's colour choices
must not restyle it.

`RulesTest` asserts the choice **moves nothing** — two racers on one seed, driven
identically — for the reason the marker shape gets the same check: the palette is reachable
from every node in the tree even though no movement rule may read it. `MazeColoursShot.gd` is
the picture half, shooting a fresh profile and an assigned one, because whether a locked chip
reads as locked is not something an assertion can judge.

> **A lost line continuation made `_is_default` return true for everything**, so nothing was
> ever locked — and the screen looked plausible, because every chip simply rendered as
> available. §12's leading-operator trap arriving through a dropped backslash rather than a
> leading `+`. Found by asking the autoload directly rather than by reading the frame again.

> **An achievement can grant something already unlocked**, which is a goal that pays nothing.
> The pairing check ran lockable → achievement only, and missed it when colour 2's default
> moved to cobalt. It now asserts the reverse direction too.

#### A decal is a hole cut in the mark, never a patch drawn on it

**Decals are generated from the outline**, not authored per shape. One drawing per
shape-and-decal pairing is a shapes × decals grid — six by five today, and a seventh shape
means five more drawings or five silent blanks. That is the parallel-array failure §6 records
for landmark density, and the stale cell is always the one nobody looks at. `RulesTest`
asserts the **whole cross product**, so a shape added later is decorated by construction or
the harness goes red.

**The mark saturates to white, which is why a patch cannot work.** It is
`SHADING_MODE_UNSHADED` at emission 3.0, so what renders is `albedo + emission × energy` and
the silhouette blows out. **Five fixes were spent on the decal's own properties before a
real-game frame was read** — raising the lift, lowering the emission, clearing the mark's
volume, reparenting the node, and finally a bright red plane floating half a unit above it,
which also did not appear. That last one is what proved the problem was never a property of
the decal. **When a surface is not visible, establish where it actually is before adjusting
how it is drawn.**

A hole cannot be washed out: the dark floor shows through it however bright the mark becomes,
and it holds at every state colour for free, since the gap has no colour of its own to keep
in step.

**A cut is measured against the shape's width WHERE IT LANDS, never against the shape's
widest point.** That distinction is what separates a pattern from a scratch, and it is
the fault the whole set was reported on: *"the decals need to be a lot better"*, against a
LIGHTCYCLE showing two hairline nicks and no pattern at all.

`NOTCH` was the extreme case — **it drew nothing whatever.** Its wedge was a triangle with
a base out at ±`reach` and an apex inside the mark, so it had narrowed almost to a needle by
the time it crossed the flank. Measured with `DecalProbe`: it removed **0.0–1.7%** of the
mark on every shape, left it in **one piece**, and produced a sliver too thin to survive the
inlay's seam inset — so on **seven of eight shapes the second colour was never drawn**. A
menu entry, an achievement to unlock it, and no geometry.

The same error made `TIP` and `TAIL` 5% scrapes rather than elements: a band sized off the
global width is thickest where the shape is widest, which is exactly where it is least
needed. Measured before and after, as a share of the mark removed:

| | STRIPE | NOTCH | TIP | TAIL | CHEVRONS |
|---|---|---|---|---|---|
| Before | 24–31% | **0.0–1.7%** | 4.8–11.9% | 9.2–17.9% | 21–30% |
| After | 29–40% | **7.0–11.3%** | 8.5–21% | 11.9–23.9% | 24–35% |

**`NOTCH` is placed where the shape has the most flank to lose, which is NOT its widest
line.** The obvious target was tried and is wrong on the barbed shapes: on the arrow and the
dart the widest line is at the very tips of the rear barbs, where there is width but almost
no body between them, and cutting there measured **3.5% and 2.6%** against 7.6% and 9.0% at
mid-body — worse than what it replaced, on two of the eight. The score is now half-width
times how much shape lies behind it, which picks the shoulder of a barbed mark and the true
widest line of a plain one. **`RulesTest` caught that regression**, which is the only reason
it is recorded as a measurement rather than shipped as an improvement.

> **"Produces geometry" and "leaves something to draw" do not add up to "is visible", and
> `NOTCH` shipped through exactly that gap.** Both assertions passed on a decal that drew
> nothing, because the cut *result* did change — by a hair. The harness now asserts the cut
> **removes a real share of the mark** and that what it removes **still survives
> `INLAY_INSET`**; those fail independently, since a decal can cut a perfectly good hole and
> fill none of it. The inlay half must be measured at the size the marker is really built
> at, because the seam is in metres and an outline-space check passes on geometry that
> vanishes in play. Verified by restoring the old wedge: **15 failures naming the measured
> percentages**, where the previous assertions stayed green.

`DecalProbe.gd` is the instrument — not a test. It reports, per shape and decal, the share
removed, how many pieces the mark ends in, and **how many inlay pieces survive the seam**.
That last column is the one nothing else reports and the one that exposed `NOTCH`.

`DecalShot.gd` is the picture half: every decal on the lightcycle, from the ordinary
trailing camera. It reads the decal list from `MARKER_DECALS` rather than naming them, so
one added later is photographed by construction. The shape is deliberately the one the fault
was reported on — its long parallel flanks are the least forgiving body in the table, so a
band that reads there reads anywhere.

**A cutter must SPAN the shape.** The first working version intersected each band with the
outline before subtracting it, so the bands stopped *at* the edge and left the flanks joined —
and at 12% of height near the tail they bit where the mark is narrow, reading as a single nick
in the trailing edge. Cuts now land where the silhouette is **widest**, so the gap survives the
trailing camera's foreshortening, which already ate a shallow taper once.

**`SPLIT` is a thin centre slot, not half the mark**, because removing half leaves a shape
that no longer reads as pointing — the one property every marker shape must keep.

**An `EDGE` decal was tried and removed.** Subtracting an inset copy leaves a *ring*, which is
an outline plus a hole, and the extrusion builds one closed loop per piece — so it came back as
the plain shape plus a clockwise hole the extruder would have filled in solid. `NOTCH` replaces
it with wedges cut from each flank, which is one loop. Recorded in the table so nobody re-adds
it without first giving the extrusion real hole support.

**The extrusion handles multiple pieces**, because a stripe genuinely severs the mark
(measured: 2 pieces on every shape). Depth is measured across the **whole** mark so the pieces
share one slope rather than each rising to full height and reading as a staircase.

> **Two weaker assertions were tried for "the cut landed" and both were wrong in opposite
> directions.** A face **count** missed real changes — splitting a delta yields another
> triangle. The **AABB** missed more: a stripe cut from the middle does not move the outer
> bounds at all. It compares vertex data.
- **Amber and red must keep reading as STATE.** The scrape and crash colours work precisely
  because the resting marker carries no hue of its own (§12). A tinted resting marker makes
  the drain-to-red a shift between two hues rather than the arrival of one, which is a weaker
  read at exactly the moment it matters most.
- **The ring is not on the menu either.** It answers position and wall clearance, which is
  half of what the marker is for; the shapes vary the half that answers *facing*. Every
  option is therefore still a footprint plus a direction, and a player cannot pick their way
  into a marker that fails to say which way they point.

**Every shape has to point.** That is the acceptance test for adding one, not a matter of
taste — a symmetric mark would read as position only, and the arrow exists because a bare
ring says nothing about direction. Each option is longer along its facing axis than across
it, and each has a distinguishable front.

#### Pointing is the rule; being an arrow is not

**Six of the fourteen shapes are not blades.** The first eight all answered "which way" the
same way — a tip at the front and a taper behind it — which is one idea drawn eight times.
Once the table became a picker rather than a default, that made the screen a row of
near-identical triangles: a menu where every option is a variation on the one already
selected.

The requirement is only that a shape **points**. TEARDROP points by where its mass sits,
KEYHOLE by a wide head on a narrow stem, HAMMER by a crossbar with no forward point at all,
SHUTTLE by rear fins, TRIDENT by three prongs, BEACON by a staircase. All six are held to the
same acceptance test and all six pass it.

**HAMMER is the strongest statement of the rule**, because its leading edge is square. It
points purely by which end carries the crossbar — and it works for a reason worth keeping:
the bar is the widest thing on the shape and sits at the extreme front, so the trailing
camera sees a broad line with a tail running away from it. A blade seen at that angle is a
sliver; this is not.

**TEARDROP shipped as an EGG on its first outline, and only a rendered frame caught it.**
Drawn convex the whole way round with the nose merely narrower than the tail, it rendered
from the trailing camera as a featureless oval pointing nowhere — the lightcycle's original
failure exactly, arriving through a curve instead of a shallow taper. It passed every
headless assertion for the same reason that one did: the outline genuinely is longer than it
is wide, and what defeats both is foreshortening compressing the length axis until a gentle
change at one end is indistinguishable from a gentle change at the other.

**So the fix is a STEP, not a sharper slope.** The nose pinches in hard and runs nearly
parallel ahead of that, which puts a corner in the silhouette where there was only curvature.
A corner survives compression; a curve does not. That is the same argument KEYHOLE's waist
and BEACON's staircase rest on, and it is the general lesson: **at this camera angle a shape
points by a discontinuity in its outline, not by a gradient.** `length > half_width × 2` is
necessary and never sufficient, which is why `MarkerShot` is not optional for a new entry.

**Each new shape needed an achievement on an axis nothing else uses**, since the tables are
paired in both directions and no two achievements may fire on one condition. Two of the six
needed a helper that did not exist — total run time — and it is **derived from
`Score.maze_results` rather than stored**, because §10 forbids growing `Score` a field to
satisfy an achievement.

#### Ten of them are objects, and the table is twenty-four

A key, an anchor, a nib, a plough, a hook, a comb, a bolt, a shield, a pin and a bracket.
These are a different kind of choice from the six above: a player takes the key because it
is a key, not because its silhouette resolves well, and the picker is better for holding
both sorts.

**They are still held to the same acceptance test**, and three of the sixteen non-blades
failed it on the first outline — all in the same way, and none of it visible to any
assertion:

| Shape | First outline | Why it failed |
|---|---|---|
| TEARDROP | convex all round, nose merely narrower | read as an **egg** |
| SHIELD | smooth taper to a rear point | read as a **rounded slab** |
| HOOK | two equal bulges, one barbed | read as a **blob** |

**The pattern is now unmistakable, and it is worth stating as the rule: at the trailing
camera's angle a shape points by a DISCONTINUITY in its outline, never by a gradient.**
Foreshortening compresses the length axis, and what it removes first is exactly the fine
detail a smooth shape relies on — so a taper, a curve, or "one end slightly bigger" all
vanish, while a step, a crossbar, a waist or a barb survive. All three were fixed the same
way: replace the slope with a hard step. `length > half_width × 2` is necessary and never
sufficient, which is why `MarkerShot` is not optional for a new entry.

**A shape also has to leave the generated DECALS room to work**, which HOOK found the hard
way. Every decal is a function of the outline, so an outline with no flank is one the
pattern set cannot decorate: NOTCH bites a wedge sized against the local half-width, and
the hook's thin shank gave it nothing to take — measured at **2.8% and then 3.8% of the
mark removed, against the 4% floor** `RulesTest` sets, which is the band separating a real
decal from one that silently draws nothing. Widening the shank to 0.42 cleared it. That
check is the one NOTCH itself once shipped invisible straight through, so it earned its
keep on a second shape.

**`MarkerShot` could not photograph a table this long, and said nothing about it.** Its
autopilot routes optimally, so it clears all five mazes in a few thousand frames — and once
the run is over there is no racer, no corridor and no racing phase, so every guard in the
shot loop returns forever. The loop can only end at the last shape, so the tool ran to the
launcher's timeout having printed nothing since its last capture: **17 of 24 files, exit 0,
no `RESULT` line.** A partial set that reads as the remaining shapes having failed to build.

That is the §12 rule about an unguarded wait being a hang rather than a failing assertion,
arriving in an instrument. The wait is now guarded and **says so**, and a finished run is
**restarted** so the remaining shapes are still shot — bounded by `MAX_RESTARTS`, so a game
that cannot start fails loudly instead of looping. The "is the run over" test reads the
racer's own `finished` and `dead` flags rather than naming the phase enum's integers, which
would be the restatement trap: `Game` carries no `class_name`, so the enum is not reachable
by identifier from a tool.

#### Forty-four shapes and twenty-eight decals, checked as a grid

Twenty more of each. The shapes are tools, craft and abstract marks — COMPASS, AXE, ANVIL,
WRENCH, TORCH, RUDDER, SAIL, GLIDER, PROW, FIN, SPADE, CROWN, LANTERN, OBELISK, CHALICE,
CARET, RIVET, RATCHET, TALLY, SIGIL — and the decals fill the space *between* the eight that
shipped rather than adding eight more unrelated ideas: three bands where STRIPE has two, a
row of bites where NOTCH has one, a chevron pointing the other way, a slot off the centre
line.

**The cross product is now 1,232 pairings and that is the whole reason this was tractable.**
A decal is a function of an outline, so every one of the twenty new patterns has to bite on
every one of the forty-four shapes, including the awkward ones the table has accumulated —
the concave CHEVRON, the three-vertex DELTA, HOOK's slim shank, RATCHET's asymmetry.
`RulesTest` walks all of it: **39,051 assertions**, up from 7,375.

**Five of the twenty decals failed their first tuning and one was abandoned outright.** None
of it was visible in the drawing:

| Decal | What went wrong |
|---|---|
| KEEL | **abandoned** — a slot stopping short of both ends is a HOLE |
| NOCK, BEAK | a V at the extremity cannot reach the floor on a pointed shape |
| SCALLOP, SERRATE | too shallow on HAMMER, which has least length to spend |
| WAIST | 3.5% on HOOK — the shape that forced the floor to exist |
| QUARTERS, RAILS | cut a fine gap and filled no inlay on NIB and SPEAR |

**KEEL is the one worth keeping in the record**, because it is the removed EDGE decal's
failure reached from a different direction. A lengthways slot that stops short of both ends
leaves an inner loop, and `Geometry2D.clip_polygons` returns a hole as its own polygon —
measured on the delta, the cut came back as 2 pieces totalling **more** area than the shape
started with (2.007 against 1.805), because the inner loop's area adds. It cannot be built
until the extrusion grows real hole support, and that is now recorded twice.

**The minimum widths are what the narrow shapes needed, not larger proportions.** QUARTERS
and RAILS both cut a healthy 21% out of the NIB and then filled nothing, because what
survived was thinner than `INLAY_INSET`. Raising the *floor* from 0.003 to 0.010 fixed both;
widening the proportion would have made them heavy-handed on every wide shape to rescue two
narrow ones.

**RATCHET found a real limit in the generator, and the SHAPE was redrawn rather than the
generator changed.** It is the table's only asymmetric entry — saw teeth down one flank —
and `NOTCH` sizes both its wedges from `_half_width_at`, which takes the **widest** crossing.
So it measured the toothed flank at 0.506 and cut the plain flank, only 0.30 wide there,
mostly through empty space: 2.9% removed against the 4% floor. The general rule is worth
having: **every flank decal assumes lateral symmetry**, so an asymmetric shape has to carry
width on both sides even where only one of them carries the detail.

**Four shapes read wrong in a frame and every headless assertion was green for all four.**
LANTERN and CHALICE were the two-broad-ends construction — and the comments written beside
them *claimed they were safe*, on the reasoning that a narrow cap and a wide foot are
"different objects rather than different sizes of one". That was reasoned from the drawing
and not from a frame, which is the exact move this file keeps recording as a mistake. In the
frame both were featureless stacks. RIVET and SPADE were milder versions of the same thing:
a step small enough that compression closed it, reading as a plain taper.

All four were fixed the same way, and it is the same fix as TEARDROP, SHIELD and HOOK before
them: **exaggerate the step until it survives.** "There is a step in the outline" and "the
step is visible" are different claims, and only the second one matters.

**The picker now scrolls to what is already chosen**, which was a minor annoyance at eight
shapes and a real defect at forty-four. The list opens at the top, so a player whose marker
was the last entry opened the screen with **no lit button anywhere in view** — measured, the
selected button sat at y 846 against a 440px viewport, 406 pixels below the fold. It reads as
the picker having forgotten the choice. `ensure_control_visible` is deferred, because nothing
has a rect until the frame after the card is built: the shot tools' "build on one frame, act
on the next" rule arriving in the screen itself.

`PickerScrollShot.gd` is the instrument, and it exists because **`MarkerPickerShot` cannot
answer this question**: that tool opens the picker and *then* calls `_pick()`, so the on-open
scroll has long since fired and its frame shows the top of the list whether the scroll works
or not. Verified in both directions — with the deferred call commented out it reports
`button y 846.0..892.0 within viewport 0..440.0  FAIL`, and with it, `394.0..440.0  PASS`.

> **A rendered-frame tool run with `-Headless` reports PASS and saves nothing.** There is no
> viewport texture, so `root.get_texture()` is null and every `save_png` fails — but the loop
> still reaches its end and prints `RESULT: PASS`. Thirty stale files from an earlier session
> sat on disk looking like a partial success, which is the OneDrive-timestamp trap and the
> stale-log trap arriving together. **Check the frames' own timestamps, not their presence.**

**Forty new achievements, and the binding constraint was never naming them.** No two may fire
on the same condition, swept over randomised runs, and sixty-odd thresholds on crashes,
scrapes, turns, speed, score and HP were already spoken for. Two new quantities carry the
overflow — the **worst** multiplier banked rather than the best, and the **spread** between a
run's fastest and slowest maze — and both are derived from `maze_results` rather than stored,
because §10 forbids growing `Score` a field to satisfy an achievement and forty new entries is
exactly the pressure that rule exists to resist.

The sweep caught one real collision while the set was being drafted: a "collect every gate in
one maze" entry was bit-for-bit identical to `the_long_way`. It moved onto the time spread.

**It is a menu button rather than a settings-panel row**, which is a deliberate exception to
the rule that put MOBILE CONTROLS behind the cog. That rule is about *preferences* — things
the player sets once to make the game work on their hardware. This is closer to picking a
character: it is the one cosmetic choice in the game, it wants to be seen rather than found,
and it needs a preview, which is a panel row's worth of screen on its own.

**The sixth button forced the stack to stop hanging from a fixed size.** At `BUTTON_SIZE.y`
62 and `SEPARATION` 18 the row ran −40..+342 with the hint ending at +402 against 450
available; a sixth button takes that to +482 and pushes the hint clean off the bottom edge.
The two constraints already recorded for this stack genuinely fight at six — no top that
clears the logo's −75 baseline also keeps the hint on screen at full button height.

**So the height is derived from the count against the available band, with a floor** — not
set to a new literal that happens to fit six. Picking 56 would be the same hard-coded-band
trap one step along (§12), correct at six and overflowing again at seven. The row now shrinks
its buttons to fit and stops shrinking at a legible minimum, which is the same shape of fix
the minimap uses against the barrier bars: shrink to the gap, and when shrinking would cost
legibility, give up something else instead.

**Nothing in the simulation may read the choice.** Movement, turn resolution, the buffer, the
barrier and the penalties behave identically whichever shape is drawn — the same separation
landmarks (§6), music (§9c) and touch controls (§9d) have. The shape is passed to
`PlayerMarker` and read nowhere else, and `Settings` is absent in every harness that
instantiates `Game.tscn` bare, so the read is guarded rather than assumed.

**The shapes are a table, never a parallel array.** Each entry names itself and carries its
own outline, so adding one is a table entry rather than an edit in several places — the
failure §6 records for landmark density and §9c for music tracks. The saved preference is
stored by **name**, not by index: an index would silently re-point every existing player's
choice at a different shape the moment the table is reordered, and a name that no longer
exists falls back to the arrow rather than crashing.

`RulesTest` asserts the table's shape rather than its contents — every entry points (its
outline reaches further along the facing axis than across it), every entry has a distinct
name, and an unknown name resolves to the default. `SceneTest` asserts the marker builds for
every shape in the table and that the choice moves nothing about the racer. `MarkerShot.gd`
is the picture half: one frame per shape from the ordinary trailing camera, since whether a
silhouette reads as pointing at that angle is exactly what no headless assertion can see.

### The upgrade compendium

**A browsable screen off the menu listing every upgrade line, each with an animated diagram
of what the mechanic does.** Reached from an `UPGRADES` button beside `MARKER`, for the same
reason that one is not behind the cog: it is not a *preference*, it is a reference a player
opens to decide what to take.

**Demos are 2D drawings, not live racers.** `MarkerPicker` can afford a 3D preview because
it previews **one** object; this screen has an entry per line, and a real racer would need a
real `Maze` — dragging the simulation into a menu screen. §12 says the simulation must never
require a rendered frame, and the inverse holds here.

**Lines with no visible on-screen effect get a labelled BAR, not an invented animation.**
Cornering, Wall Armor, Score Multiplier and five others change a number and nothing else.
Motion drawn for a mechanic that has none is the HUD-chevron mistake of §7 — a picture
pulling the eye somewhere the mechanic is not. Five kinds cover everything: `CORRIDOR`,
`BAR`, `GAUGE`, `PANEL`, `STILL`.

**Every number is derived from a real `Upgrades` taken to that rank**, and the per-rank text
comes from `next_rank_description()` — the same call the cards use, so the two can never
disagree. A compendium contradicting a card is worse than no compendium.

**`DEMOS` is a table, asserted for total coverage in both directions**, so adding an upgrade
line and forgetting this screen fails a test by name rather than drawing a blank box forever.
Verified by deleting an entry.

**The demo is a bubble beside the focused row, not a fixed pane.** The list is the subject —
a player deciding between Cornering and Snap Turn wants both names in view — and a pane would
spend half the screen permanently on one of them. Being transient, the bubble can also be
*larger* than a pane could afford. The affordance is the row's own hover and focus, never an
(i) glyph: that would be the tofu-box failure §9d records for the settings cog, plus a second
focus stop on every row.

**Bubble placement is derived from the row's measured rect and clamped**, never a fixed
offset — the hard-coded-band trap, where a constant is correct for the row it was tuned
against and runs off the bottom for the last one. `ShellTest` asserts it at **both ends** of
the list, because the top passes trivially; verified by removing the clamp, where the last
row's bubble ran 697px past the panel bottom.

**Three things only rendered frames caught**, none visible to any assertion:

- **The demo box came out 152px tall.** A `VBoxContainer` gives a minimum-sized child exactly
  its minimum, and the caption plus a seven-rank list took the rest — a 6-cell corridor in
  152px draws a 52px cell, which is a strip rather than a diagram.
- **The list expanded past the panel and pushed the heading off the top.** A
  `PanelContainer` sizes to its contents and ignores an offset smaller than they need — the
  §8c overrun in a third place. The list's height is derived from the panel box minus a
  measured header cost.
- **The bubble then covered the heading anyway**, which reads as the title never being built.
  Both labels were present, visible and correctly placed the whole time. **Rect containment
  is not clearance** — the bubble is clamped below the header band, not merely inside the
  panel.

`CompendiumShot.gd` is the picture half: one frame per demo **kind** rather than per line,
plus the first and last rows where placement fails. It shoots **mid-animation**, because a
demo that never advances is identical to a working one in a frame taken at t=0 — the reason
`QuadrantShot` seeks a region change.

#### The card scrolls, because three tables do not fit a screen

**The choice tables sit in a `ScrollContainer`; the preview and CLOSE do not.**

`PANEL_SIZE` was a hard-coded `Vector2(760, 830)` and the contents measured
**1054** — so the card laid out at 1054 whatever the constant said, and ran
**189px off the bottom of a 900-tall viewport**. The PATTERN COLOUR swatches and
CLOSE were simply not on screen, which is the §8c overrun for the **fourth**
time: the summary panel, the settings card, the compendium list, and now this.
A `PanelContainer` sizes to its CONTENTS and ignores an offset smaller than they
need, so declaring a height it cannot honour buys nothing at all.

**Raising the constant alone would have been the same trap one step along.** The
number is right for 8 shapes, 8 decals and 19 colours, and wrong on the next
cosmetic added — and this screen grows by design, since every entry in it is an
achievement reward (§10). It is raised anyway, to the measured 1054, but only as
an upper **bound**: the viewport clamp is what keeps the card on screen, and the
old 830 merely denied a tall display the chance to show every table at once.

**What scrolls is the part that grows.** The heading, preview, state and name
answer *what am I looking at*, and CLOSE answers *how do I leave* — pinning both
is the whole point, because CLOSE was the row that went missing. The compendium
records the mirror of this: a list that grew until it pushed its own title off
the top. The list's height is **derived** from the panel box minus a measured
fixed cost (heading 42, preview 156, state 20, name 34, CLOSE 46, separations
60, margins 48 = 406), so a shorter screen shortens the LIST rather than losing
rows off the end of it.

**A tail spacer after the last swatch row**, because a row sliced by the scroll
boundary reads as a **clipped control** rather than as more content below — the
exact misread this screen was reported for. The spacer is what turns a cut-off
row into a visible bottom of the list.

**The preview gave up 44px of its height (200 → 156) and none of its width.**
The marker lies flat on the floor and the camera looks *down* at it, so the box
was taller than the silhouette ever filled — dead space above and below. The
shapes are longer along their facing axis than across it, so height was the
surplus axis. That 44px goes to the list, which was the part actually short of
room.

**`_fit` is re-run on `size_changed`, not only at build.** The card is built
once, so a height derived only at build time is correct for the window the
screen opened on and stale for every resize after — the stale half of the
hard-coded-band trap. Measured across eight viewport heights, 700 to 1600: the
card scales 658 → 1054, CLOSE is on screen at every one, PATTERN COLOUR is
reachable at every one, and at 1200+ the scrollbar disappears entirely because
everything fits.

> **Only a rendered frame showed the second half.** With the card fitting and
> every assertion green, the first frame still had the COLOUR swatches sliced
> mid-row at the scroll edge — a boundary that reads as broken rather than as
> scrollable. Fitting the card and making the cut legible are two different
> fixes, and passing the first does not imply the second.

#### Four traps found while building the picker

All four were found by a rendered frame, and every headless assertion was green
through all of them.

- **A fan cannot make a concave shape.** The inner mark was built by fanning
  triangles from a single apex to every outline edge, which was correct for the
  arrow and silently *fills in* any notch — the chevron rendered as a plain solid
  triangle, identical to the delta. The outline was right the whole time and the
  mesh built from it was not, so every assertion about the outline passed. It is
  now triangulated with `Geometry2D.triangulate_polygon`, which closes any simple
  polygon and leaves a notch a notch.
- **A shallow taper reads as NO taper at the trailing camera's angle.** The first
  lightcycle was a near-rectangular slab with a merely cut nose. In play it drew
  as a **symmetric diamond** — pointing nowhere — because foreshortening at a
  shallow angle compresses the length axis and eats a gentle taper entirely. It
  satisfied the "longer than it is wide" rule outright, which is why that rule is
  necessary and not sufficient: the nose has to be long and narrow enough to
  survive the compression, and the tail is notched so the two ends can never read
  alike.
- **`Geometry2D` winds for 2D, which is INWARD once y becomes +Z.** Every shape
  came out inside-out, at a signed volume of about −0.01. Nothing looked wrong,
  because the material is unshaded — the same trap the landmark drums and the wall
  boxes both hit. `SceneTest` asserts the signed volume per shape rather than a
  vertex count; the count it replaced was a restatement of the builder and broke
  the moment the fan became a triangulation with a rim, reporting six failures
  about a mesh that was fine.
- **`look_at` on a node that is not yet in a tree silently does nothing.** It
  works in global space, so the preview camera kept its default orientation and
  the picker rendered an **empty box** — which reads as the preview being unwired
  rather than as the camera being aimed at nothing. Aim after `add_child`. The
  matching framing numbers are tuned against rendered frames rather than
  calculated: the arithmetic said the marker should fill 65% of the box and it did
  not, because the aim point and the box's centre are not the same thing once the
  camera looks down at a shape lying on the floor.

`PickerScrollShot.gd` answers one question `MarkerPickerShot` structurally cannot: does the
picker OPEN on the shape the player already holds? That tool opens the screen and *then*
moves the highlight, so the on-open scroll has already fired and its frame shows the top of
the list either way. This one saves a late-table shape first, opens the screen once, and
measures where the selected button actually landed against the scroll viewport -- a question
with exactly one frame in it. It restores the preference on the way out, since `Settings`
persists on every write.

`MarkerPickerShot.gd` is the other half — the picker's SCREEN rather than the shapes in
play. Two different failures: a shape can read perfectly in a corridor and still be
unchoosable, and the preview in particular is the thing most likely to come back blank,
since a mis-aimed camera renders a plausible dark panel rather than an error. It shoots
the first and last entry, because a lit button is a lit button in any single frame — the
same reason `QuadrantShot` seeks a region change. It **restores the saved preference on
the way out**: the picker persists through `Settings`, so without that the tool leaves the
player on whichever shape it shot last and its own next run opens on that instead of the
default. A tool must not write the state it is inspecting.

> **The marker's state colour is on the RING, which the trailing camera barely
> sees.** `update_state` recolours only the ring material, so a scrape leaves the
> inner mark pure white — measured, a frame with the barrier bar visibly
> half-drained is pixel-identical to a clean one. This predates the picker and is
> recorded rather than fixed, but §5.1 calls the barrier read load-bearing and
> §12 makes the marker carry it, so the colour is currently landing somewhere the
> player mostly cannot see.

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
`.github/workflows/deploy.yml` on every push to `main`. The workflow runs all four
harnesses first, so a red harness blocks the deploy rather than shipping over it.

**That gate was inert from the first CI run until it was fixed, and both halves of why are
worth keeping.** Measured on the deployed workflow: every harness step ran in ~0.3s against
the ~50s `RulesTest` takes locally, and printed no test output at all.

- **Godot links `libfontconfig` even under `--headless`, and the CI image does not ship
  it.** The engine died on startup with `libfontconfig.so.1: cannot open shared object
  file`, then signal 11, **before any harness ran**. The image having the engine and the
  export templates pre-installed is exactly what made this easy to miss — the one thing it
  lacks is a library the engine loads on a path nothing else in the build touches.
- **The steps then greped for failure in a crash log and found none.** `grep -qiE
  '(^| )FAIL|assertion failed' rules.log && exit 1 || true` — a crashed run writes no
  `FAIL`, so the grep matched nothing, `|| true` swallowed the non-match, and the step went
  green. **Every deploy since the first one shipped untested.**

The grep was independently wrong in the *other* direction too, which is what makes it the
wrong instrument rather than a broken one: a **passing** run prints `passed: 544   failed:
0`, and ` failed: 0` matches `(^| )FAIL` case-insensitively. So the check would have failed
a green run and passed a crashed one — backwards on both ends.

**Use the harness's exit code, not its output.** Every harness already ends
`quit(1 if _failed > 0 else 0)`, which is the authoritative answer and cannot be confused
by a summary line that contains the word "failed". Verified in both directions, because a
gate that cannot fail is not evidence (§12): a deliberately broken assertion exits 1, and
the restored harness exits 0 at 544 passed.

> **A green checkmark is not a passing test — check that the step took long enough to have
> run.** This is the same failure as the stale-log trap below and the `build_type` note
> above: the signal looked right and was measuring nothing.

**The crash underneath it was `file_logging/log_path` pointing into `res://`.** `logs/` is
gitignored, so **a fresh clone has no `res://logs`** — and the engine creates the log
directory during startup, before any script runs. When it cannot, it dies with signal 11.
So the harnesses never executed a single assertion, in CI or in any new checkout. `res://`
is read-only in an exported build as well, which is the same bug waiting on a second path.

Fixed by pointing it at **`user://logs/godot.log`**, which is always writable and always
exists. This does not affect `logs/errors.log`: `launch.ps1` creates `logs/` itself and
captures stdout separately, so the primary feedback channel is unchanged.

**Reproduce this class of failure by cloning the repo to a temp directory**, not by
re-running in the working copy — the working copy has `logs/` sitting there from every
previous run, which is exactly what hides it. Verified: the fresh clone crashed at signal
11, and passes 544/544 after the fix.

**The same line was also corrupted in the file.** `enable_file_logging=true` had been
mashed into a comment with every space and newline stripped —
`cleanwhennothingwas#actuallychecked.…file_logging/enable_file_logging=true` — which is a
garbage key the engine ignores, so file logging was silently off. It entered in `e115e29`
and shipped in every build since. Restored, and the comment now uses `;` (the ini comment
character `project.godot` actually uses) rather than `#`.

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
| `RulesTest.gd` | Are the rules right? Generation, distance field, turn and buffer resolution, barrier, penalties, upgrades, the turn freeze, the three-way branch classification behind the Path Indicator, the zigzag cull, landmark placement, marker heights, the per-maze damage curve, HP regen and death, the score — awards, multiplier, banking and monotonicity — the two trail lines — gate routing, the five-gate gate on Platinum, and that the two never draw at once — the legendaries, including the one-per-run cap, draw rarity, wall smashing and auto-steer, the record of gates already taken, the repeat-cell penalty charged once per cell, the suppressed earning on repeat ground and the racer's visited-cell record, the flat per-contact wall charge and that it is billed once per contact rather than per second, that a modelled farming run scores below an honest one at every lap count swept, the date-derived daily and monthly seeds, and the quadrant numbering — that the start is always quadrant 1 and the exit always the highest, at every rank — together with the assertion that a quadrant ignores the maze's routing entirely, and the Trail Memory record — visit counting, the expiry fade, the count resetting with the cell, the per-rank windows, and that none of it moves the racer, and the six added lines — Momentum's ramp and its reset on contact, Second Wind spending a charge without refunding the contact HP, Deep Breath extending the freeze by its full allowance while paying no speed for it, Overclock burning HP without ever killing and without inflating `speed` itself, the gate footprint being a cardinal plus that a diagonal never satisfies, and that every Gate Size rank WIDENS the marker as well as raising it -- the half that was missing, since height alone lands entirely above the wall line where the capped camera barely sees it -- with the widest rank asserted to still clear the corridor walls, derived from CELL_SIZE rather than restated, and the card count, and the marker shape table -- that every entry points forward and is longer than it is wide, that ids are unique, that an unknown id falls back to the arrow, and that the choice never moves the racer, the marker decal table -- every decal generated from the outline it decorates, asserted across the WHOLE cross product of shapes and decals so a shape added later is decorated by construction, and the cut RESULT bounded rather than the cutter, and that every decal actually REMOVES a visible share of the mark and still FILLS an inlay piece after the seam inset -- the pair of checks NOTCH shipped invisible straight through, since "produces geometry" is true of a cut that changes the mark by a hair, the cosmetic unlock tables -- paired in both directions, since a cosmetic no achievement grants is unreachable and an achievement granting a typo is a goal with no reward, that the three defaults are never lockable, that a run which drove nowhere earns nothing by vacuous truth, and peak speed surviving a maze bank, and the compendium's demo table, covering every upgrade line in both directions. and the maze palettes -- stable ids, each maze defaulting to its own authored colourway, and the assignment moving nothing about the racer, and that no achievement grants something a fresh profile already has, which is the reverse of the pairing check and the direction it missed, and the STARTING SET counted by kind rather than named -- exactly one shape, colour, decal and palette -- since a named check has to be widened every time a cosmetic is added and widening it is how the palettes reached five free entries, and that no two achievements fire on the SAME condition, swept over 600 randomised run shapes on a fixed seed, since two goals with one condition unlock as a pair and each looks correct alone, and the camera sensitivity dial -- the rate curve's ends and its monotonicity, the derived default landing on a whole notch -- with the monotonicity sweep's bound READ off CAM_SENSITIVITY_MAX and guarded on what the loop actually walked, since a guard phrased against the constant passes while the loop beside it stops at a stale literal -- and the separation: two racers on one seed that must never diverge and whose FREEZES must never differ, since the freeze is a rule and this dial is only a view, and Deep Breath's COOLDOWN -- driven through real turns rather than by assigning `freeze` by hand, asserting that ANY turn extends by the whole allowance (the early-press gate is gone, and the two assertions that encoded it now assert the opposite), that the extension ACCRUES speed (the ramp rewind is gone too), that a second turn inside the cooldown does NOT extend while one past it does, and that both the immediate turn and the second turn actually froze at all, since "does not extend" is trivially true of a racer that never turned -- plus that an untaken line never extends, since the grant is gated on has_deep_breath() rather than on a non-zero allowance. the COINS -- collection, the per-cell no-double-pay rule, the bonus reading against the LIVE cap rather than the static one, the crash halving rounded down, the cap ratcheting permanently downward to its floor, and banking per maze surviving a later wipe -- coin placement ignoring the solve path, and the shop -- every lockable cosmetic priced, a re-buy refused rather than charged, and a default neither stocked nor purchasable. 39,051 assertions. |
| `SceneTest.gd` | Does the game boot and run? Node setup, HUD construction, signal wiring, the gate/upgrade round trip, camera clipping, wall-indicator placement, path-indicator strip placement and orientation, dead-end decoration, the crash camera, pause, landmark mesh winding, marker sight lines, the maze-start loadout pick, Flying Vision's held clocks and raised camera, the spent-gate marker, the minimap's placement at two window widths, the gate marker names surviving a mesh rebuild, the rear-view mirror sharing the main world and clearing the HUD bands at two sizes, the quadrant box lighting the racer's own region and clearing the mirror at two sizes, and the end-of-run summary on both the death and completion paths, and the trail floor's shader, its per-cell texture sized to the grid, and the upgrade gating the drawing rather than the recording, and that every marker shape builds a closed, outward-wound solid inside its ring, that the steering pads stand down while an upgrade pick is open while the pause pad stays up, and that a pause press both pauses AND opens the settings panel, that closing it resumes, that the cog stands down while the pads are up, and that QUIT TO MENU reports run_dismissed rather than tearing the run down itself, that every marker shape builds with every decal and stays a closed solid once cut, and that scrape-amber and crash-red override a player-chosen colour on BOTH surfaces -- asserted with a colour that is not itself a state colour, since an earlier version used crash red and so passed against the exact regression it was named for, and that the camera sensitivity dial actually REACHES the camera -- measured by driving _process and reading the yaw the camera really moved, since a dial that maps correctly and is then ignored renders a perfectly plausible game -- with both camera invariants re-asserted at the dial's extremes, because the dial changes camera geometry and the default-dial pass cannot see it, and the quadrant box's two ends -- the start outline at start_cell's region, the start being region 1, and the two ends being DISTINCT regions, since an outline marking one corner twice says nothing at all, and the cluster's move to the top CENTRE -- centred on the whole grid-plus-dial width to a pixel, clearing the HUD's top row, clearing the MESSAGE band (the collision only a rendered frame caught) and no longer touching the mirror -- together with the compass needle carrying the racer's own facing, every heading giving a distinct angle, and north pointing up, and that the player MARKER EASES onto a new heading rather than snapping to it -- measured by driving real _process calls and reading _marker.rotation, since re-deriving the curve locally is the trap the camera-dial check beside it records -- and that the CAMERA's swing carries no velocity discontinuity, the jolt the removed turn-freeze multiplier caused by closing 70% of the turn in one frame at the default dial. 5,323 assertions. |
| `RunTest.gd` | Is the game finishable? Plays a complete run through every maze in `Tuning.MAZES` on an autopilot and reports speed, time, crashes, per-maze gates, the final build, and the score breakdown per maze. |
| `ShellTest.gd` | Can a player get in? The menu boots, PLAY reaches a running game, WATCH TRAILER reaches the reel, finishing the reel comes back, the mobile-controls toggle survives the menu-to-game swap, and the left+right reverse chord resolves without latching and stays off the keyboard, the pads scale to a phone screen, and the leaderboard panel switches all four views, toggles sort and draws malformed rows safely with the service offline, the PLAY DAILY and PLAY MONTHLY buttons each start a game on their own date-derived seed, and the pads reporting held direction on press, on a partial chord release and on hide, and that one real touch tap -- driven with the emulated mouse event a phone sends after it -- is exactly one turn and one held-direction change per edge -- including when that echo lands on a DIFFERENT pad, which is what a browser really sends -- that an unmatched release emits nothing, that a held tap whose emulated echo arrives LATE -- the case no time window can survive, since the echo is synthesized inside the engine and delivered on whatever frame it reaches -- is still one turn, that the pause pad clears the settings cog at two viewport sizes and stays above the 44px tap minimum on a phone, and that the menu's own buttons and labels clear that minimum on glass, that the Unlocks autoload is REGISTERED -- the hole Leaderboard shipped inert through for weeks -- and that the UPGRADES button opens the compendium, lists every line, and keeps its bubble inside the panel at BOTH ends of the list, since the top passes trivially, and the grouped menus -- every row of every menu REACHABLE by walking the table rather than by naming the rows, every submenu carrying a way back, the trail returning to the root, and the submenu title clearing both the logo above it and the first row below. 143 assertions. |
| `TrailerTest.gd` | Does the trailer show what it claims? Every maze appears in the declared order, each gate segment opens its cards, and every segment covers real ground. 22 assertions. |
| `MusicTest.gd` | Does the music table hold together? Every declared track resolves to a real file, every maze names a track that exists, the autoload is registered and processing, and the transport crossfades, ducks and loops. 105 assertions. |

`TrailerShot.gd` is the picture half of `TrailerTest` — it renders the reel and
saves a frame per segment plus each gate moment, which is the only way to check
captions, palettes and card layout without watching it.

`CoinProbe.gd` is not a test -- it reports, per maze, how many coins were placed, how many
sit ON the canonical solve path, and how many are invalid (duplicated, on the start or exit,
or in a sealed pocket). The solve-path column is the one that matters: it is the routing-leak
check §5b rests on, and it has to be read against the path's own share of the grid rather
than against zero, since an unbiased scatter lands some coins there by chance.

`CoinShot.gd` is the picture half of the coins. It **seeks a coin** rather than shooting on a
timer -- a timed shot lands in an empty corridor and produces a frame that cannot tell a
working coin from one that never spawned, the reason `PaletteShot` seeks a junction. It walks
the corridor cell by cell rather than testing alignment, because a coin sharing an axis may
sit behind a wall, which is the fault `AddedLinesShot` records for its first two versions.

> **Its autopilot must steer toward COINS, not toward the exit.** An exit-seeking router takes
> the optimal route, and coin placement deliberately ignores that route -- measured, it met a
> coin in 1 maze of 5 and reported "no coin found" for the other four, which is an instrument
> that photographs nothing. It routes by a bounded BFS, once per **cell** rather than once per
> frame: flooding a 100x100 grid every frame made the first version appear to hang outright,
> which is `RepeatProbe`'s frame-versus-cell lesson in a third instrument. The parent-chain
> walk needs a hop guard too -- the start cell is its own parent, so a chain that reaches it
> without matching spins forever, and an unguarded wait is a hang rather than a failure.

> **Only a rendered frame caught the coin's size and height.** At `COIN_RADIUS` 0.55 the disc
> was a sliver several cells out, and every headless assertion was green -- the mesh measured
> exactly 1.1 x 1.1 x 0.12 with gold albedo and emission on, which is a correct coin that
> cannot be seen. Diagnosed by probing the built mesh and material directly rather than by
> looking at the frame again, the same way the palette lock was.

`ShopShot.gd` is the picture half of the shop (§7b): one frame with an empty wallet, where the
screen is a goal list, and one with a partial wallet, where the three chip states are all on
screen at once. A single shot shows one half of the mechanic. It **restores the wallet and the
earned set on the way out** and sets `suppress_save` throughout -- verified against the real
`settings.cfg`, which still read `coins=0` afterwards.

> **Build on one frame, capture on the NEXT.** Its first version opened the screen and shot it
> in the same frame, and `process_frame` fires before the UI is drawn -- so it photographed
> "0 COINS" against a wallet of 30. That reads exactly like a stale label in the shop and is
> not; it is the trap §8c already records for `SummaryShot`, whose own two shots came out
> identical for the same reason.

`RunLengthProbe.gd` reports straight-run lengths, which is how the 8-cell cap in §6 is
verified; "over cap" must always read 0.

`LandmarkProbe.gd` reports landmark counts, tier split and dead-end coverage per maze,
which is how the `landmarks` density knob gets tuned. `LandmarkShot.gd` shoots a frame
next to a landmark in each maze, seeking one rather than shooting on a timer.

`AddedLinesShot.gd` shoots the Gate Size line as a controlled pair — the same question at rank
0 and rank 3, both **5 cells straight down an open corridor**. Measured: at rank 0 the marker is
**not visible at all** at that distance, and at rank 3 it is unmissable, with a *second* gate
also showing over the wall from a corridor the racer is not in. That is the §7 above-the-wall
argument arriving one step further out than it was first measured, and it is what the line
actually buys.

> It **seeks a gate straight ahead with an OPEN line of sight**, walking the corridor cell by
> cell. Alignment is not visibility: two earlier versions checked only that a gate shared an
> axis and was in range, and both shot a gate sitting behind a wall — producing a rank 0
> "control" frame of a dead end, which makes a before/after pair worthless for the one question
> the shots exist to answer.

`GateShot.gd` shoots each maze from 2.5-6 cells short of a gate, which is how the
above-the-wall gate marker gets checked -- the question it answers is "can I see it
coming", so shooting from on top of a gate would show nothing.

`GateSizeShot.gd` is the CONTROLLED picture of Gate Size -- one seed, one gate, one camera
pose, varying only the rank, at two distances. `AddedLinesShot` also shoots this line and
cannot answer the question it exists for: it restarts the run per rank, so its frames land at
different distances on different mazes, which shows a marker is there and never that one is
bigger. It SEEKS a gate with clear corridor behind it on all four approaches and fails loudly
when none has one -- its first version took gates[0], which on the fixture seed sits against
the maze's west edge, and shot the inside of the boundary wall.

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

`RepeatProbe.gd` is not a test — it reports repeat-cell counts for an optimal, a wandering
and a farming driver on the same maze, which is how the −250 penalty is checked against play
rather than against a model. Its own farming driver reversed on a **frame** interval at
first, which at the 1x start speed never left the opening cell and reported zero repeats —
reading exactly like the penalty failing to fire when nothing had in fact been farmed. It
paces by cells covered instead.

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

`MenuShot.gd` is the picture half of the two-column menu: the same screen at three widths,
since the column split is width-dependent and one size cannot show the branch it does not
take. It feeds the panel rows directly rather than reaching Firebase — an instrument that
needed the network would fail whenever Jonah is offline — and its longest fake name sits at
the 24-character limit the rules enforce, which is the case that would push the score column
off the panel.

`SummaryShot.gd` is the picture half of the end-of-run summary (§8c): one frame per terminal
path, death and completion. The completion shot deliberately builds the **tallest** case — all
five maze rows and a sixteen-line build including a legendary — because the short death screen
fits any layout and proves nothing about the one that overruns.

`MomentumProbe.gd` is not a test — it reports the equilibrium speed a forced build actually
settles at, which is how the Momentum line's effect on the §5.3 pair was measured rather than
predicted. It exists because `RunTest` cannot answer the question: its autopilot takes whatever
cards it is offered, and a full run took Momentum only to rank 1 of 4, so its final speed says
nothing about the line's ceiling. It measures maze 1 **and** maze 5, because maze 1 finishes in
~41s — before the ramp settles — so its figures are what a build reaches there rather than the
settling point.

> **It must steer once per CELL, never once per frame.** The first version re-requested a turn
> every frame, which spams the buffer: the racer crashed 13 times and died after 122 cells, and
> the probe reported a flat **1.00x** for every build in the table. A plausible-looking column
> of identical numbers, measuring a dying racer rather than a settling one. The tell was
> `turns/s` at 0.11 against the 0.62 a 5x racer actually makes. This is `RepeatProbe`'s
> frame-versus-cell lesson arriving in a second instrument.

`DeepBreathProbe.gd` is not a test -- it reports what the held extension actually costs and
pays, per rank, on maze 5 with a control row per rank that does NOT hold the direction. It
exists because neither `RunTest` nor `RulesTest` can answer the question: RunTest's autopilot
never holds a direction, so its final speed is identical with the line maxed and untaken --
the same blind spot `MomentumProbe` records for its own line -- and RulesTest asserts one
extension in isolation, which says nothing about six of them compounding across a maze. It is
what showed the ramp-runs change to be +0.27x and ~2s of budget at max rank rather than the
pump it was predicted to be. Steered once per CELL, never per frame, the lesson `RepeatProbe`
and `MomentumProbe` both record.

`AddedLinesShot.gd` is the picture half of the two added lines that change the screen: the card
row at 3, 4 and 5 cards, and the gate marker at Gate Size rank 0 against rank 3. The card row is
§12's hard-coded-layout trap — five 320px cards overrun a 1600px viewport — and no headless
assertion can see a row overflowing or text clipped from a narrowed card.

> It **seeks a gate straight ahead**, 2–5 cells out, for the reason `GateShot` does. Its first
> version accepted any gate within 4 cells on either axis and shot one sitting level with the
> marker, which shows the marker's colour and nothing whatever about its height. It also
> dismisses any upgrade pick immediately: the first run let a card screen open over the gate and
> produced a frame of the card row where the marker should have been.

`DecalProbe.gd` is not a test -- it reports, per shape and decal, the share of the mark the
cut REMOVES, how many pieces the mark ends in, and how many INLAY pieces survive the seam
inset. That last column is the one no other instrument reports and the one that exposed
NOTCH drawing nothing on seven of eight shapes.

`DecalShot.gd` is the picture half: every decal on the LIGHTCYCLE, from the ordinary
trailing camera, which is the angle that turns a shallow cut into no cut at all. It reads
the list from `MARKER_DECALS` rather than naming the decals, so one added later is
photographed by construction. Not to be confused with `InlayPairShot.gd`, which holds the
decal fixed and varies the COLOUR PAIR -- the two instruments cross the same grid the other
way.

`MazeColoursShot.gd` is the picture half of the maze-colour screen: a fresh profile (four
palettes locked, which is what a new player sees) and an assigned one. The chips are drawn in
their own palette's colours, so whether a locked chip reads as locked -- and whether a dark
palette's chip is visible against the card at all -- are rendered-frame questions. It restores
BOTH the earned set and every slot assignment on the way out.

`CompendiumShot.gd` is the picture half of the upgrade compendium: one frame per demo KIND
rather than per line -- five kinds is what the drawing code has, and 28 frames of which a
dozen are the same corridor function is a slower read for no more coverage -- plus the first
and last rows, where bubble placement fails, plus the LONGEST CAPTION in the table. That last
one is a different question from the longest demo: a caption that overflows its box clips
silently, no assertion sees it, and every other frame of that kind is drawn from a short one.
It shoots mid-animation, because a demo that never advances is identical to a working one in
a frame taken at t=0.

`CamSensShot.gd` is the picture half of the camera sensitivity dial. It **seeks a pivot**
rather than shooting on a timer, for the reason `PaletteShot` seeks a junction -- at rest both
ends of the dial look identical, because the swing has already finished -- and shoots a fixed
number of frames INTO a turn at each end of the dial and at the default. The three positions
are DERIVED from `CAM_SENSITIVITY_MIN`/`MAX` rather than written out — a literal `[0, 5, 10]`
was correct while the dial ended at 10 and would have shot the fast half three times while
never photographing the new slow end, which is the one frame the tool exists to produce. It
un-sticks a parked racer, since a frame with no pivot in it is indistinguishable from the
feature doing nothing.

`Screenshot.gd` is not a test — it runs the real game with rendering and saves frames to
`logs/`, which is how the visuals get checked without anyone opening the editor.

`PaletteShot.gd` is the same idea aimed at one question: it jumps straight to each maze and
shoots a frame **at a junction**, so both the per-maze palette (§8) and the floor-strip Path
Indicator (§7) are actually in the picture. It seeks a junction rather than shooting on a
timer, because a shot taken on a timer lands in a plain corridor and shows nothing of the
indicator it exists to check.

`TrailShot.gd` is the picture half of the two trail lines (§7). It **seeks a frame where
Platinum is mid-firing** rather than shooting on a timer — Platinum is not eligible until
5 of 8 gates are banked, so an untimed shot lands in the first half of a maze and can only
ever show Golden, which every other frame of a run already shows. Its budget is
deliberately large for the same reason: a budget sized for "wait for a junction" expires
long before the fixture can exist, and the tool then shoots a frame with no silver in it
and reports success.

It reports `OVERLAP` on every shot, which must always be false. The tool's **first
version** held out for both trails visible together, and the frame it produced is why the
interlock exists — gold drawn over silver down the same corridor, the silver reading as a
white smear beneath it. Both nodes were behaving correctly on their own terms; only the
rendered frame showed the result.

`PathStripShot.gd` aims at the Path Indicator alone, and it seeks a junction where **two or
more colours are actually on screen** — a frame showing three strips that all say the same
thing does not demonstrate the scheme. It keeps Golden Trail out of the shot deliberately:
the trail is a long gold ribbon drawn *along* the route, it looks exactly like a strip laid
the wrong way, and mistaking it for one cost two "fixes" to geometry that measured correct
throughout.

`QuadrantShot.gd` is the picture half of the Quadrant box and the Compass (§7): three
frames at each of the three ranks. It **seeks a region change** rather than shooting on a
timer, and that is the whole point of the tool — a box that never updated would look
*identical* to a working one in any single frame, since a lit square is a lit square.
Shooting either side of a crossing is the only frame pair that shows the highlight
actually move. It caught both the count label reaching into the mirror and the cardinal
letter being too faint to read, and later the start outline's first colour being
**invisible against the box's own grid** while every headless assertion was green — and,
after the pair moved to the top centre, the upgrade **toast drawn straight through both the
grid and the compass dial**, which no assertion had any reason to look for.

`TrailMemoryShot.gd` is the picture half of Trail Memory (§7): two frames per maze, one down
a stretch driven once and one over ground crossed four times. It **drives a loop** rather than
shooting on a timer, for the reason `PaletteShot` seeks a junction — an optimal router never
re-crosses anything, so a timed shot shows a uniform trail and cannot tell the darkening rule
from a trail that has no darkening rule at all. It paces by **cells covered, never frames**,
the lesson `RepeatProbe` records. Not to be confused with `TrailShot.gd`, which is the
Golden/Platinum instrument. It caught the over-bright first tuning that every headless
assertion passed.

`RearViewShot.gd` is the picture half of the rear-view mirror (§12): two frames per maze,
one a cell or two **past a turn** and one at a junction. It seeks the corner rather than
shooting on a timer for the reason `PaletteShot` seeks a junction — down a straight corridor
the mirror shows two identical walls receding, which is precisely the frame that cannot
distinguish a working mirror from one aimed forward. It caught both the frame cutting
through the maze name and the view being 40% empty ceiling.

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
- **A harness can report PASS at a STALE assertion count while a file it depends on fails to
  parse.** Adding constants and a static function to `Tuning.gd` and immediately running
  `RulesTest` produced `passed: 3609  failed: 0` — a clean green run — while the log also
  carried `Parse Error: Cannot find member "CAM_SENSITIVITY_MIN" in base "Tuning"` and
  `Failed to load script "res://scripts/core/Settings.gd"`. The autoload was dead, the new
  test never ran, and the count was the *previous* build's. `--import` fixed it and the count
  jumped to 3725 with two real failures.

  **The count is the instrument, not the RESULT line.** A green PASS whose total has not moved
  after adding assertions is evidence the additions never executed — the same shape as the CI
  gate that went green on a crashed run, and the "check it took long enough to have run" note
  below. Grep the log for `Parse Error` as well as `FAIL`, and compare the total against the
  one in the harness table.
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
- **A node reference captured before `_process` is stale AFTER it** — the same trap as the
  one below, but *within a single loop iteration*. SceneTest's sight check read
  `game.racer` at the top of the frame, called `game._process()`, then compared the new
  camera against that racer's marker. When the call finished a maze it built a new `Racer`
  on a new grid, so the check measured a **333m sight line spanning two different mazes**
  and reported it as the marker being hidden. It looked exactly like a camera bug, and the
  camera was correct throughout — two wrong fixes went into the camera before the stale
  reference was measured (`stale=true`, old cell (59,59) against new cell (0,0)).
  **It fired on ~1 run in 5, on exactly one frame**, because it needs the maze to change on
  the very frame sampled. Anything read before a `_process` must be re-read after it, or
  compared only against values captured at the same instant.
- **A test that waits on a `progress` value is a test that encodes the phase.** Recentring
  `progress` on the cell centre turned `while r3.progress < 0.7:` into an unbounded loop,
  because 0.7 is no longer reachable — and an unguarded wait on an impossible value is a
  **hang, not a failing assertion**. The harness produced no output at all, which reads like
  a parse error or a broken launcher and is neither. Every wait loop in a harness needs a
  guard and a `check` that the guard did not fire; that turns "this can never happen" into a
  named failure instead of silence.
- **A test can pass on inherited state for years and only fail once an unrelated fix removes
  it.** SceneTest's "driving into a wall crashes" never drove into a wall: `_run()` calls
  `_on_exit_reached()` further up, which leaves `racer.finished` true, and `step()` returns
  on its first line when finished — so the racer sat motionless for the whole 400-frame
  budget. It passed because earlier checks happened to leave it already `PARKED` from a crash
  they caused. The check asserted the previous test's side effect, under the name of the
  crash path. Its own comment already warned about exactly this and still listed only the
  input fields; `finished`, `dead` and the phase were the ones that mattered.
- **A "last resort" that returns a number without checking it is not a last resort.** The
  camera's sight-clearing pass fell back to `CAM_SIGHT_HARD_MIN` and returned it blind, so
  when even that distance was blocked the marker stayed hidden — the exact rule the pass
  exists to guarantee. It now walks down to `CAM_SIGHT_FLOOR` and returns the first distance
  that genuinely clears. **A branch that promises an invariant has to verify it**, or it is
  just a hopeful default.
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
