# Every tuning number from CLAUDE.md, in one place.
#
# The design doc is the source of truth; this file is its transcription. When a
# number changes here it changes in CLAUDE.md too, and the section reference on
# each block says where.
class_name Tuning
extends RefCounted

# --- Speed (CLAUDE.md section 3) ---------------------------------------------

# Cells per second at 1.0x.
const BASE_CELL_RATE := 1.0

# +1.0x per 10 seconds of clean travel.
#
# This is the pressure dial for the whole game: speed is not a choice, it is a
# condition (section 11.1), and this is how fast the condition tightens. At 15s
# the climb was gentle enough that a careful player could sit comfortably; 10s
# means 2x at ten seconds and 4x at thirty, so the maze starts outrunning
# comfortable reaction much sooner.
#
# It also raises the equilibrium the turn cost fights against (section 5.3):
# equilibrium = RAMP / (turn_ratio * TURN_COST), so a 1.5x faster ramp lifts the
# settling point by the same factor. Re-derive rather than re-guess if either
# number moves again.
const SPEED_RAMP_PER_SEC := 1.0 / 10.0

# Safety rail, not a goal. 10 cells/sec is ~6 frames per cell at 60fps.
const SPEED_CAP := 10.0

# Speed never drops below this. Base Speed upgrades raise it.
const SPEED_FLOOR := 1.0

# After un-sticking from a crash, climb back at 2.5x the normal rate until
# reaching the floor. Recovery should feel snappy -- the crash already cost the
# time and the reset.
const RECOVERY_RAMP_MULTIPLIER := 2.5

# --- Turning (CLAUDE.md sections 2, 4, 5.3) ----------------------------------

# Buffer is measured in CELLS, not seconds. A time-based buffer would get more
# forgiving as speed rises, inverting the difficulty curve exactly when the game
# should get harder.
#
# ONE FULL CELL at base. The rule this encodes: a press made at any point while
# you are in a cell is still live when you reach the far side of it, so the turn
# lands at the next opening rather than expiring. You never have to time a press
# to a fraction of a cell -- see the input-timing note in CLAUDE.md section 4.
#
# At 0.4 the buffer covered only the last two-fifths of the approach, so an
# input fired early in a cell -- a perfectly reasonable read of a junction you
# can already see -- expired into a slowdown before the junction arrived. That
# punished reading AHEAD, which is the exact skill the game is asking for, and
# it got worse with speed because a cell passes faster than a player re-presses.
const BASE_BUFFER_CELLS := 1.0
const BUFFER_PER_RANK := 0.15

# 90-degree turns are nearly free: the game wants constant turning.
#
# This number is far more load-bearing than it looks. A DFS-carved maze forces a
# turn on ~55% of cells, so the cost is paid constantly, and it fights the ramp
# directly: speed settles where ramp-gain per second equals turn-cost per
# second, at roughly RAMP / (turn_ratio * TURN_COST).
#
# At 0.10 that equilibrium is 1.21x -- speed could never climb at all, and the
# 10x cap was unreachable in principle rather than merely in practice. At 0.03
# it settles near 4x on maze 1, with more headroom as the player learns to hold
# straighter lines. Measured, not guessed (see the turn-ratio probe in
# RunTest's notes).
const TURN_COST := 0.03

# The 180 is a real but survivable cost.
#
# It started at 2.0 -- "the real decision point, and it is meant to hurt" --
# which made every dead end a serious speed loss on top of the distance, taxing
# a misread twice. At 0.75 backtracking still costs something real, but the maze
# punishes bad routing mainly with DISTANCE AND TIME, which is the currency
# separation in section 11.2: routing badly should cost the clock, not the speed
# earned by not crashing.
#
# Still ~25x a 90 (0.03), so committing to a route and rounding a loop stays
# meaningfully cheaper than reversing -- the decision the 180 exists to create.
const REVERSE_COST := 0.75

# Fast Turnaround ranks, indexed by rank (0 = no upgrade). Roughly halving by
# the top rank, so the line changes how freely a player explores rather than
# just shaving a number (section 11.5).
const REVERSE_COST_BY_RANK := [0.75, 0.55, 0.4, 0.25]

# --- Barrier and damage (CLAUDE.md section 5) --------------------------------

# Seconds of sustained wall contact before a crash.
#
# Halved from 0.5. The barrier is the skill ceiling (CLAUDE.md section 11.4),
# and half a second of grace was long enough that an unupgraded racer could sit
# against a wall through most of a cell and still leave clean -- so the question
# the barrier exists to ask, "can I afford this brush?", had an easy yes at rank
# 0. At 0.25 a brush is a genuine commitment from the first maze.
#
# Halved again, 0.25 -> 0.125. An eighth of a second is roughly eight frames at
# 60fps: enough to clip a corner and leave, and nowhere near enough to ride a
# wall. Combined with the flat per-contact charge (SCRAPE_DAMAGE), touching a
# wall is now unambiguously a cost and holding one is a crash -- the barrier has
# stopped being a pool the player can spend and become a reflex window.
#
# BARRIER_PER_RANK stays at 0.25, so it is now worth TWICE the base: one rank
# TRIPLES the pool. That deepens the section 11.5 argument rather than breaking
# it -- the first rank of Barrier Capacity is the difference between no room and
# real room, which is a decision about how you drive, not a bigger number.
const BASE_BARRIER := 0.125
const BARRIER_PER_RANK := 0.25

# Full refill in 3.3s of clean travel at base -- slower than the 0.25 it started
# at. The barrier is the skill ceiling (CLAUDE.md section 11.4), and a refill
# fast enough to be back before the next corridor made scraping close to free:
# the pool was always full, so the interesting question -- "can I afford this
# brush?" -- never got asked. Regen is now slow enough that consecutive scrapes
# compound, which is what makes Barrier Regen a line worth taking.
const BASE_BARRIER_REGEN := 0.15
const BARRIER_REGEN_PER_RANK := 0.15

# Was 100, then 75, now 50. The same argument each time and it had not gone far
# enough: HP has to be a number the player watches, and a pool that absorbs
# twenty-five crashes on maze 1 is decorative for the whole first half of a run.
#
# At 50 the crash counts are 17 / 10 / 8 / 6 / 5 across the five mazes, so maze 5
# kills in five crashes. The per-contact charge sits underneath that, which is
# the real change: 50 wall touches is now a whole run's worth of HP, and the
# damage curve is not the only thing draining the pool any more.
#
# The damage curve is again deliberately NOT rescaled. Cutting the pool rather
# than raising damage keeps a fixed subtraction biting hardest where it is
# already largest, and Repair Field's flat HP/sec restores a larger SHARE of a
# smaller pool -- the line that pays for driving clean gains value exactly as
# crashes get more expensive.
const MAX_HP := 50

# --- Coins (CLAUDE.md section 5b) --------------------------------------------

# Each coin held raises the speed FLOOR by this much, additively on top of
# whatever Base Speed ranks have bought. At the cap that is a full +1.00x.
#
# It is the floor rather than the ramp deliberately. The ramp is the game's
# central pressure (section 3) and Momentum is already the line that prices it;
# a currency that accelerated the climb would make coins a second Momentum with
# no wall-contact reset to pay for it. The floor is the number a crash RESETS
# to, so coins buy back exactly what a crash takes away -- which is what makes
# losing half of them on a crash legible rather than arbitrary.
const COIN_SPEED_BONUS := 0.05

# Coins held at once, before crashes eat into it. 20 * 0.05 is +1.00x, so a full
# purse doubles the base floor and no more -- deliberately of the same order as a
# maxed Base Speed line (7 ranks * 0.25 = 1.75x) rather than dwarfing it.
#
# Collection past the cap is not an error and is not refused: the coin is taken,
# banked toward the shop, and the surplus simply does not raise the floor.
# Refusing it would leave coins sitting in a corridor the player has cleared,
# which reads as a bug.
const COIN_CAP := 20

# Every crash permanently lowers the cap by this much for the rest of the run.
#
# This is what stops a purse from being fully recoverable. Halving alone is a
# setback the player drives back out of in a minute; a cap that never recovers
# means a crash-heavy run is PERMANENTLY capable of less, and the twentieth coin
# is only ever held by someone who has not crashed at all. It is the ratchet the
# rest of the coin economy lacks.
#
# The bonus is recomputed against the live cap, so a crash that takes the cap
# below what is held trims the purse down to it -- otherwise the cap would be a
# claim the game did not enforce.
const COIN_CAP_LOST_PER_CRASH := 1

# The cap never falls below this. At zero a run could reach a state where coins
# are uncollectable for its whole remainder, which turns every coin still drawn
# in the world into a thing that cannot be picked up -- the same "visible and
# unreachable" failure the sealed-pocket exclusion avoids.
const COIN_CAP_MIN := 5

# What SURVIVES a crash, rounded DOWN. Half is the harsh read on an odd purse --
# 9 coins becomes 4, not 5 -- which is consistent with a crash being the event
# the whole barrier system exists to avoid (section 5.4).
#
# A crash already costs HP, the parked time, the speed reset and 1000 points.
# Coins are the fifth cost, and the only one the player can see accumulating
# BEFORE they pay it, which is what makes a full purse feel like something worth
# protecting rather than a number that only goes up.
const COIN_CRASH_KEEP := 0.5

# Coins scattered per maze, as a fraction of open cells.
#
# Placement IGNORES the solve path, the distance field, the gates and the exit,
# for exactly the reason landmark placement does (section 6): a coin the player
# can see is a reason to go somewhere, and a currency that clustered on the
# optimal route would be a free Path Indicator. Coins say "there is value here",
# never "the exit is this way" -- so they must be able to sit down a dead end,
# and often do.
#
# Tuned so a maze carries comfortably more than the cap: the player chooses
# WHICH to detour for, and a maze that held exactly 20 would make the choice for
# them. Denser on the early mazes in absolute terms because those are smaller --
# the fraction falls as the grids grow so a late maze is not carpeted.
const COIN_DENSITY := 0.006
const COIN_DENSITY_BY_MAZE := [0.006, 0.005, 0.0042, 0.0036, 0.0032]

# A coin is collected by standing in its cell. Membership, never a radius --
# the reason section 7 gives for the gate footprint: a radius fires diagonally
# through wall corners, collecting through solid geometry.

# Wall damage per crash on maze 1, climbing by WALL_DAMAGE_PER_MAZE each maze:
# 3, 5, 7, 9, 11. Against 75 HP that is 25 crashes on maze 1 and 6 on maze 5.
#
# The curve itself is unchanged; only the pool moved. Damage is deliberately NOT
# rescaled alongside it, because the point of the cut is to make the late mazes
# lethal rather than to keep the crash count where it was -- maze 5 falling from
# 9 crashes to 6 is the change, not a side effect of it.
#
# It was a flat 1, which made HP decorative -- 100 crashes to die, in a game
# whose longest run is a few minutes. Section 5.5 always intended HP to "become
# relevant in the late mazes"; a flat rate cannot do that, because the same
# number against a fixed pool is the same pressure everywhere. Scaling per maze
# is what turns HP into an escalation lever alongside size and loop density
# (section 8), and it is what gives Wall Armor and HP Regen something to bite.
const WALL_DAMAGE := 3
const WALL_DAMAGE_PER_MAZE := 2

# Every wall touch costs this, once, at the moment contact begins -- whether the
# player escapes clean or rides it into a crash. The barrier no longer buys free
# contact; it only decides whether a touch stays a 1-point scrape or escalates
# into the full per-maze crash damage above.
#
# This reverses CLAUDE.md sections 5.1 and 11.4, which said a good player brushes
# walls constantly and never pays for it. That was a deliberate design change,
# not a tuning tweak: wall contact is now always a cost, and the skill is in how
# MUCH it costs rather than in getting it free.
#
# Charged once per contact rather than per second, because contact DURATION is
# what the barrier already measures -- billing HP for it too would put two
# systems on the same timer, and a per-second rate would make HP fractional on a
# bar that reads as whole points.
#
# It is flat and does NOT scale per maze. The escalation lever is the crash
# damage above; a scrape charge that climbed alongside it would make late-maze
# wall contact punishing enough that the barrier's question -- can I afford this
# brush? -- collapses back to a flat no.
const SCRAPE_DAMAGE := 1

# An expired turn input. Cheap, frequent, and teaching -- it says "you were
# early" without derailing the run. Not a crash: no HP, no barrier drain.
const SLOWDOWN_PENALTY := 0.5

# Death is ON. HP reaching 0 ends the run.
#
# This reverses the original v1 call (section 5.5, "no death in v1") and it is a
# real change of genre, not a tuning tweak: the timer stops being the ONLY thing
# the player fights (section 8). It was turned on deliberately, together with
# the scaling wall damage above -- the two only make sense as a pair, since
# damage that scales toward a pool that can never empty is a number with no
# consequence, and death against a flat 1 damage would almost never fire.
const DEATH_ENABLED := true

# --- Upgrades (CLAUDE.md section 7) ------------------------------------------

const BASE_SPEED_PER_RANK := 0.25
const WALL_ARMOR_PER_RANK := 1

# Cornering: the per-turn speed cost by rank (index 0 = no upgrade).
#
# This line moves the section 5.3 equilibrium DIRECTLY -- speed settles where
# ramp-gain per second equals turn-cost per second, so halving the cost roughly
# doubles the settling point. That is why it is a routing decision rather than a
# stat: a Cornering build can afford a turn-heavy route that would bleed an
# unupgraded racer dry. It never reaches zero, because a free turn would remove
# the choice the cost exists to create.
const TURN_COST_BY_RANK := [0.03, 0.024, 0.018, 0.012]

# Expiry Grace: the slowdown penalty for an expired input, by rank.
#
# Pairs with Buffer Window into a genuine "press early, press often" build.
# Never zero -- an expired press must always mean something, or the buffer stops
# being a window and becomes an invitation to mash.
const SLOWDOWN_PENALTY_BY_RANK := [0.5, 0.38, 0.26, 0.15]

# HP Regen: HP restored per second of clean (non-parked, non-scraping) travel.
#
# Rank 0 is zero -- without the line, HP only ever goes down. It regenerates on
# CLEAN travel specifically, so it rewards the same thing the speed ramp does
# (section 3) and cannot be farmed by sitting still.
const HP_REGEN_BY_RANK := [0.0, 0.6, 1.2, 2.0]

# Path Indicator: how many cells ahead the junction warning appears, by rank.
const INDICATOR_LOOKAHEAD_BY_RANK := [0.0, 1.0, 2.0, 3.5]

# Minimap radius in cells, by rank. Rank 0 means no minimap at all.
const MINIMAP_RADIUS_BY_RANK := [0.0, 6.0, 10.0, 16.0, 24.0]

# --- Trail Memory ------------------------------------------------------------
# How long a driven cell is remembered, by rank, in SECONDS.
#
# A memory DURATION rather than a cell count, which is the one place this line
# deliberately departs from section 4's "measure forgiveness in cells, not
# seconds" rule. That rule exists so forgiveness does not grow with speed; this
# is not forgiveness, it is memory, and memory of "the last minute of driving"
# is the thing a player actually wants to hold. It does mean the trail covers
# more ground at 8x than at 1x -- which is correct: at 8x you have genuinely
# driven more ground in that minute.
#
# Sized against the 180s maze budget (section 8b). Rank 1 at 60s is a third of
# a maze, which is enough to recognise a loop you just closed and not enough to
# map the maze. The final rank is the whole maze, which is why it is the last.
const TRAIL_WINDOW_INFINITE := -1.0
const TRAIL_WINDOW_BY_RANK := [
	0.0,                     # untaken -- callers must check has_trail_memory()
	60.0,                    # 1:00
	90.0,                    # 1:30
	120.0,                   # 2:00
	150.0,                   # 2:30
	180.0,                   # 3:00
	TRAIL_WINDOW_INFINITE,   # the whole maze
]

# How long a cell spends fading out at the end of its window. The tail of the
# trail visibly retreats rather than individual cells blinking off -- a cell
# that snapped off at its own deadline would read as a rendering fault, and
# ranking up would be invisible except by counting. With a fade, ranking up is
# watching the tail stretch.
const TRAIL_FADE := 3.0

# The tint applied to remembered ground, as a multiplier on the palette's floor
# colour, indexed by visit count.
#
# Index 1 (a single visit) LIFTS the floor: ground you have driven once glows
# faintly, which is the "have I been here" answer. Every further visit takes it
# DOWN, past the base floor into shadow, so heavily re-crossed ground burns out.
# Fresh ground is dark, known ground glows, flogged ground is black.
#
# That shape is deliberate and is not the same as "darker with every visit". A
# strictly monotonic dimming has nowhere to go on a floor that is already near
# black (every palette's floor sits under 0.08), so the first few visits would
# be indistinguishable from each other and from untrodden ground.
const TRAIL_TINT_BY_VISITS := [
	1.0,    # 0 -- untrodden, the palette's own floor
	3.4,    # 1 -- lit
	2.1,    # 2
	1.1,    # 3
	0.4,    # 4
	0.0,    # 5+ -- burnt out
]

# Colour the lit trail is pushed toward, mixed with the palette floor rather
# than replacing it, so the trail reads as the same floor lit rather than as a
# different surface painted on top. Neutral-cool on purpose: it must not collide
# with the three route colours the Path Indicator owns (green/yellow/red), with
# gate amber, or with exit white (section 8's reserved list).
const TRAIL_COL := Color(0.30, 0.62, 0.85)

# How far the tint pushes toward TRAIL_COL at full intensity. Well under 1.0 --
# the grid lines are the timing contract (section 11.3) and must stay the
# dominant marking on the floor, so the trail is a wash beneath them and never
# a surface that competes with them.
const TRAIL_COL_MIX := 0.45

# Golden Trail: seconds between firings, by rank. Index 0 is rank 0 -- no trail.
#
# Rank no longer sets a LENGTH. The trail runs the whole route to its target,
# and how far that reaches is the player's own speed: it draws at
# TRAIL_SPEED_MULTIPLIER times the racer's current cell rate, so at 8x it
# stretches several times as far in the same wall-clock moment as it does at 1x.
# That is the point -- lookahead is worth most exactly when a cell passes in
# 125ms, and a fixed cell count hands the fast player the same short streak it
# hands the slow one.
#
# The old TRAIL_CELLS_BY_RANK is gone rather than retained at a large value: a
# cap that never binds is a number the reader has to prove inert before they can
# ignore it, which is the same trap CLAUDE.md section 8 records for the dead-end
# density target.
const TRAIL_INTERVAL_BY_RANK := [0.0, 12.0, 8.0, 5.0]

# Gates that must be banked before Platinum will fire at all.
#
# The two lines own different halves of a maze. Up to here the live question is
# "where are my upgrades" and Golden answers it; a silver ribbon pointing at the
# exit during that stretch is an invitation to skip picks the player has already
# spent a card on. Past it the question is genuinely "get me out".
#
# 5 of 8 -- late enough that the gate tour is the clear business of the early
# maze, early enough that Platinum still has a real stretch of maze to be useful
# in rather than firing once on the way through the exit arch.
const PLATINUM_MIN_GATES := 5

# Platinum Trail: the same shape, aimed at the exit instead of the next gate.
# Slower firings at equal rank than Golden, because its route is the one the
# player is scored on finishing (section 8b) and it answers a bigger question --
# a continuous readout of the whole solve would flatten the maze.
const PLATINUM_INTERVAL_BY_RANK := [0.0, 15.0, 10.0, 6.0]

# The streak runs at this multiple of the player's CURRENT speed, so it always
# pulls ahead. A fixed rate would trail behind a player at 5x, which inverts the
# whole point of a forward scout.
const TRAIL_SPEED_MULTIPLIER := 2.0

# The longest a single firing may spend DRAWING, in seconds. Bounds the reach:
# the head runs at TRAIL_SPEED_MULTIPLIER times the racer's cell rate for at
# most this long, so a 1x racer is shown ~5 cells and an 8x racer ~40 -- the
# same wall-clock moment of lookahead, scaled by how fast it is being consumed.
#
# It also stops a long route outliving its own cycle. The shortest interval is
# 5s (rank 3 Golden), so a draw phase that could exceed that would leave the
# trail permanently mid-flight and never re-snapshot from the player's current
# cell, which is what keeps the ribbon honest.
const TRAIL_MAX_DRAW := 2.5

# How long the fully-drawn trail holds before fading, in seconds. Long enough
# that a trail fired just before a junction is still there when it arrives.
const TRAIL_LINGER := 2.0

# Quadrant: how many divisions per axis, by rank. Rank 0 is no box at all.
#
# Per AXIS rather than a total count, because the box is drawn as a grid and the
# axis count is what a renderer actually needs -- storing 4/9/16 would mean
# taking a square root back out at every draw, and would let a non-square total
# be written by accident.
#
# The quadrant a cell falls in is derived from the maze's own dimensions, so a
# maze of any size divides correctly and nothing here restates a grid size.
const QUADRANT_DIVISIONS_BY_RANK := [0, 2, 3, 4]

const CARDS_PER_GATE := 3

# --- The six added lines (CLAUDE.md section 7) -------------------------------

# Momentum. A multiplier on SPEED_RAMP_PER_SEC, indexed by rank.
#
# +12% a rank, so rank 4 runs the ramp at 0.148/s against a base 0.10 -- 5x in
# ~27s rather than 40s. This is the FIRST line on the ramp itself: every other
# speed line in the tree touches costs and floors (Cornering, Snap Turn, Fast
# Turnaround, Base Speed), so the number the whole difficulty curve hangs off
# had nothing on it.
#
# It moves the section 5.3 equilibrium, which is linear in the ramp rate:
# equilibrium = RAMP / (turn_ratio * TURN_COST). Rank 4 lifts a measured 5.13x
# toward ~7.2x, and a maxed Momentum + Cornering build brings the 10x cap within
# reach for the first time. Accepted deliberately -- but the standing rule from
# section 5.3 applies: RE-MEASURE on RunTest rather than trusting the formula.
const MOMENTUM_RAMP_BY_RANK := [1.0, 1.12, 1.24, 1.36, 1.48]

# How long the Momentum bonus takes to rebuild after wall contact resets it.
#
# The bonus is LOST ON CONTACT, not on a crash -- that is what makes the line
# price the section 11.4 skill ceiling in the currency section 3 says the game
# is about. It rebuilds rather than being gone for the maze, because a single
# scrape ending the line for good would make it a lottery on the first mistake
# and would answer section 5.1's "can I afford this brush?" with a flat never.
#
# ~4s is roughly the barrier's own refill time at base regen, so the two costs
# of a scrape run down the same clock.
const MOMENTUM_REBUILD_SECONDS := 4.0

# Second Wind. Banked crash saves, one per rank, refilled by clearing a gate.
const SECOND_WIND_PER_RANK := 1

# Deep Breath. How much a held direction may EXTEND the turn freeze, by rank.
#
# The true opposite of Snap Turn: that line buys the clock back, this one spends
# it to buy reading room. Never sensibly taken together, which is the point --
# a card worthless to your build says more about that build than another +0.15.
#
# Long enough to be a real LOOK rather than a longer corner. 0.75s at max rank
# against the ordinary 0.10s freeze is a beat the player stops and reads in; the
# 0.15-0.45 it replaced was a corner that lasted slightly longer, which is a
# different thing and was not what the card promised.
const DEEP_BREATH_BY_RANK := [0.0, 0.25, 0.50, 0.75]

# Deep Breath's cooldown, in seconds of accumulated driving time.
#
# The COOLDOWN is what limits the line, which is why the early-press gate could
# be dropped. That gate existed because the line had no other limiter: the key
# requesting a turn is still down when a 0.10s freeze ends, so a held direction
# was true at every corner and the extension was automatic rather than asked
# for. A cooldown bounds uses per minute DIRECTLY -- ~6 a minute here -- rather
# than relying on the player not having pressed early, so the extension can now
# fire on any turn and still be a decision.
#
# Ticked on the racer's own accumulated driving time, never a wall clock, so it
# does not run down during an upgrade pick or a pause -- the same clock Trail
# Memory ages on, and for the same reason.
const DEEP_BREATH_COOLDOWN := 10.0

# Overclock. HP burned per second while the gesture is held, by rank.
#
# The first line that SPENDS a resource for pace rather than accumulating
# protection, which turns the HP pool into a currency and makes Repair Field an
# engine instead of a safety net.
const OVERCLOCK_HP_PER_SEC_BY_RANK := [0.0, 2.5, 1.8, 1.2]

# The speed added while overclocking, above the racer's current value.
const OVERCLOCK_SPEED_BONUS := 2.0

# Overclock never kills: the burn stops here. Dying to your own accelerator with
# no wall involved reads as a bug rather than as a cost, and every other death
# in the game comes from contact (section 5.5).
const OVERCLOCK_MIN_HP := 1

# Gate Size. The collection footprint's reach in cells, by rank.
#
# Rank 1 buys height only (see GATE_SIZE_HEIGHT_BY_RANK) and leaves the
# footprint at the gate's own cell. Rank 2 reaches one cell in each cardinal
# direction -- a 5-cell plus -- and rank 3 reaches two.
#
# MEMBERSHIP, never a distance check: a radius would fire diagonally through
# wall corners and collect a gate through solid geometry, which would make the
# gate the one object in the game that ignores the maze's walls.
const GATE_SIZE_REACH_BY_RANK := [0, 0, 1, 2]

# The gate marker's height multiplier by rank, on top of GATE_MARKER_HEIGHT.
const GATE_SIZE_HEIGHT_BY_RANK := [1.0, 1.35, 1.5, 1.65]

# And its GIRTH multiplier -- how much wider the crossed slabs get.
#
# Height alone was measured not to read, and the reason is geometric rather than
# a matter of degree. The camera is capped below WALL_HEIGHT (section 12), so
# everything a taller marker adds is added ABOVE the wall line, at the far end
# of a corridor, where perspective compresses it to a few pixels. The part of
# the marker the player is actually looking at while collecting it -- the part
# at eye level, in the cell -- was pixel-identical at every rank. Measured on a
# controlled pair (one seed, one gate, one camera pose, varying only the rank):
# the mesh AABB went 5.55 -> 9.16 on Y and stayed a flat 3.0 x 3.0 on XZ.
#
# So a rank now widens as well as raises. Width is the axis that reads from
# inside the corridor, which is where "my gate got bigger" is actually asked.
#
# BOUNDED BY THE CORRIDOR, and that is what sets the top of the table. The base
# slab is CELL_SIZE * 0.75 = 3.0m in a 4.0m cell, so 1.28 takes it to 3.84m and
# leaves 8cm of clearance each side. Past that the marker intersects the side
# walls -- which is not a wider gate, it is a gate with its ends buried, and at
# 0.55 alpha it would read as a rendering fault rather than as an upgrade.
#
# 1.30 was tried first and sits EXACTLY on the clearance bound, which RulesTest
# rejects on purpose: a top rank resting on the limit has no margin for a future
# change to CELL_SIZE or to the 0.75 base, and would start intersecting on the
# first tweak to either rather than failing a test.
const GATE_SIZE_GIRTH_BY_RANK := [1.0, 1.12, 1.21, 1.28]

# Extra Card. Cards offered at a pick, by rank -- an investment line whose cost
# is the pick itself, so it is only correct early and needs no rule to say so.
#
# The row DERIVES its card width from this count (section 12's hard-coded-band
# trap): five 320px cards plus separation is ~1750px against a 1600px viewport.
const CARDS_BY_EXTRA_RANK := [CARDS_PER_GATE, 4, 5]

# --- Score (CLAUDE.md section 8b) --------------------------------------------
#
# Every award scales with speed, which is what makes the section 3 ramp pay off
# in the score and not only on the clock.

# Points per second of clean travel, times current speed. Not while parked.
const SCORE_PER_SECOND := 10.0

# A turn taken with the barrier untouched, times current speed.
const SCORE_TURN_CLEAN := 60.0

# A turn taken out of a scrape, times current speed. 40% of a clean turn: a
# clean turn must be clearly better, but section 11.4 calls wall-brushing the
# skill ceiling, so scoring a scrape as a failure would turn the expert texture
# into a penalty. It still pays far more than the crash it avoided.
const SCORE_TURN_SCRAPED := 24.0

# Flat, NOT speed-scaled. A crash already resets speed to the floor, so a
# speed-scaled penalty would charge most at the moment it also removes the
# ability to earn. ~1.7% of a typical maze subtotal.
const SCORE_CRASH_PENALTY := 1000.0

# Seconds allowed per maze before the multiplier drops below 1.0. Roughly 3x
# what a perfect autopilot needs (measured ~54-59s per maze), which puts a good
# human run at 60-100s left and a sloppy one near zero. At the 420s first
# proposed, every run banked ~360s and the multiplier stopped discriminating.
const SCORE_TIME_BUDGET := 180.0

# Asymmetric by design (CLAUDE.md section 8b): leftover time is rewarded steeply
# because that is the routing skill being measured, while overtime decays gently
# so two badly-overrun runs stay distinguishable instead of both flooring.
const SCORE_MULT_DIVISOR := 30.0
const SCORE_OVERTIME_DIVISOR := 120.0
const SCORE_MULT_FLOOR := 0.20

# Charged ONCE per distinct cell re-entered this maze, however many times the
# racer crosses it again after that. It measures how much redundant ground a
# route covered, which is the honest thing to charge for.
#
# It used to be charged on EVERY re-entry, at 250, because charging once per
# cell leaves a farming loop free from its second lap onward -- and a subtotal
# that grows forever beats a time multiplier that floors at 0.20x. That
# reasoning was sound about the loop and wrong about the lever: the thing
# funding a farming lap is the turn award (60 x speed = 360/cell at 6x), so the
# penalty had to out-price an award ten times its size, and it never actually
# managed it. Measured across lap counts, a farmer beat an honest run at 250
# too; the old assertion only passed because it modelled one fixed lap count,
# past the peak.
#
# SCORE_EARN_ON_REPEAT below is what closes it properly -- with no income on
# ground already driven, a farming lap earns nothing and the time multiplier
# does the rest. That frees this number to be what it should be: a moderate,
# legible cost for backtracking rather than a deterrent sized to fight an
# exploit.
#
# 100 is ~1.7 clean turns at 1.0x. At 250 an ordinary run bled far too fast --
# a couple of dead ends and one wrong loop cost thousands of points for reading
# the maze imperfectly, which is what the maze is FOR.
#
# Flat and NOT scaled by the Score Multiplier upgrade, for the same reason the
# crash penalty is flat: a penalty that scaled with the player's ability to earn
# would make backtracking more expensive the more of that line they took.
const SCORE_REPEAT_CELL_PENALTY := 100.0

# What fraction of the ordinary travel and turn awards a cell pays when it has
# already been driven this maze. Zero: re-crossed ground earns nothing.
#
# This is the actual anti-farming rule (CLAUDE.md 8b). A farming loop is
# profitable exactly because a turn pays 60 x speed regardless of whether the
# corner is new, so pacing a braided ring at 6x mints 360/cell forever. Removing
# the income removes the exploit at its source, and the time multiplier then
# punishes the wasted seconds on its own -- measured, a farmer loses ground
# monotonically at every lap count instead of peaking above an honest run.
#
# It costs an honest player nothing: an optimal router never re-enters a cell,
# so it earns precisely what it did before. What it does cost is a genuinely
# lost player, who now drives their recovery lap for time rather than points --
# which is the right way round, and is the same statement section 11.2 makes
# about routing being punished by distance and time.
const SCORE_EARN_ON_REPEAT := 0.0

# Score Multiplier upgrade: +15% earned points per rank, applied to the maze
# subtotal BEFORE the time multiplier so it compounds with routing rather than
# substituting for it (CLAUDE.md section 7).
const SCORE_BONUS_PER_RANK := 0.15

# --- Legendaries (CLAUDE.md section 7) ---------------------------------------
#
# Rare, active, one per run. Each is an ability with an input and a cooldown,
# which is what separates the tier from the ordinary tree.

# Cooldown by rank for the two cooldown-scaling legendaries. Index 0 is rank 0
# and is never used -- a legendary at rank 0 is not held at all.
const LEGENDARY_COOLDOWN_BY_RANK := [0.0, 45.0, 30.0, 20.0]

# Auto-Steer scales its DURATION rather than its cooldown.
const AUTOSTEER_DURATION_BY_RANK := [0.0, 3.0, 4.5, 6.0]
const AUTOSTEER_COOLDOWN := 45.0
const AUTOSTEER_SPEED_MULTIPLIER := 2.0

# Flying Vision: how long the world is held, then the countdown back in. The
# countdown is not decoration -- returning a player straight to a running
# simulation after five seconds of a static overhead view hands back control
# while they are still re-orienting.
const VISION_DURATION := 5.0
const VISION_COUNTDOWN := 3.0

# How high the vision camera lifts, in cells. This is the one place the
# "camera stays below WALL_HEIGHT" rule (section 12) is suspended: that rule
# exists so corridors feel enclosed WHILE DRIVING, and this is explicitly not
# driving.
const VISION_CAMERA_HEIGHT := 34.0

# Two taps within this window count as a double-tap. Long enough to be
# reachable at speed, short enough that two deliberate 180s a beat apart are
# not mistaken for one.
const DOUBLE_TAP_WINDOW := 0.40

# How heavily an UNSTARTED legendary is weighted against an ordinary line in the
# card draw. A uniform draw would surface one as often as Buffer Window, which
# would make "rare" a label rather than a fact. Once a legendary is held it
# draws at full weight -- upgrading the one you have should not be a lottery.
#
# TUNED BY MEASUREMENT, not by feel: a run makes 45 picks, so even a small
# per-card weight accumulates into near-certainty across a whole run. Measured
# over 2000 simulated runs (share of runs that are ever OFFERED one, and the
# pick number it first shows up at):
#
#   weight  runs seeing one  first sighting
#   0.180        100.0%        pick 8.3
#   0.100         98.3%        pick 12.8
#   0.060         92.2%        pick 17.4
#   0.040         81.8%        pick 20.2      <- chosen
#   0.025         66.0%        pick 22.4
#   0.015         48.1%        pick 23.7
#
# 0.04 makes a legendary a genuine find that reshapes the back half of a run
# -- first seen around maze 3 -- while still letting most runs actually play
# with a tier that carries three whole abilities. At 0.18 it was guaranteed by
# maze 1 and not rare at all; below 0.025 most runs never meet one.
const LEGENDARY_DRAW_WEIGHT := 0.04

# --- Music (docs/specs/music.md) ---------------------------------------------

# Every track, keyed by a short name. Adding one is an entry here plus a file in
# audio/music/ -- no code change.
#
# `volume_db` trims the PLAYER, not the bus, so evening out two differently
# mastered tracks does not move the player's own volume setting.
const TRACKS := {
	"find_the_way": {
		"path": "res://audio/music/find-the-way.mp3",
		"volume_db": -8.0,
	},
	"ah_eh_oh": {
		"path": "res://audio/music/ah-eh-oh.mp3",
		"volume_db": -9.0,
	},
	# One per maze, in maze order. Each was written to its palette (section 8):
	# cyan, ember, magenta, acid green, deep violet.
	"cyan_plucks": {
		"path": "res://audio/music/cyan-plucks.mp3",
		"volume_db": -9.0,
	},
	"burnt_orange_maze": {
		"path": "res://audio/music/burnt-orange-maze.mp3",
		"volume_db": -9.0,
	},
	"neon_maze_run": {
		"path": "res://audio/music/neon-maze-run.mp3",
		"volume_db": -9.0,
	},
	"acid_green_chase": {
		"path": "res://audio/music/acid-green-chase.mp3",
		"volume_db": -9.0,
	},
	"cold_minor_maze": {
		"path": "res://audio/music/cold-minor-maze.mp3",
		"volume_db": -9.0,
	},
	"factory_maze": {
		"path": "res://audio/music/factory-maze.mp3",
		"volume_db": -9.0,
	},
}

# Tracks that suit any maze, drawn from when a maze's own pool does not win the
# roll. This is the "sprinkle anywhere" tier: a maze's own list carries the
# tracks written to its palette (section 8), and these carry the ones that
# belong to the game rather than to one maze.
#
# A name here must also exist in TRACKS. MusicTest asserts it, because a typo
# would otherwise fail silently at the exact moment a maze rolled it.
const SHARED_TRACKS := [
	"ah_eh_oh",
	"find_the_way",
]

# Chance a maze plays from SHARED_TRACKS instead of its own pool.
#
# Low on purpose. The per-maze tracks are what make arriving in a maze read as
# arriving somewhere (section 8), and that is exactly the job a shared track
# cannot do -- so the sprinkle is a variation on the palette, never the usual
# case. At 0.5 the palette association never forms; at 0 the run is identical
# every time, which is what this exists to fix.
const SHARED_TRACK_CHANCE := 0.25

# --- Mazes (CLAUDE.md section 8) ---------------------------------------------

# Two independent dead-end knobs, and they are not interchangeable.
#
# `dead_ends` is overall density -- the share of cells that terminate. It is the
# punishment budget for a misread route.
#
# `shallow_keep` is the fraction of ONE-CELL STUBS kept: dead ends hanging
# straight off a junction, where the player turns in, crosses a single cell, and
# must immediately 180 out. Those carry no route decision, so at high frequency
# they just tax reversals. Measured on the stock parameters they were the
# majority of all dead ends in mazes 2 and 3 (212 of 316, 247 of 348).
#
# They need separate knobs because they compete for the same removals: the late
# mazes' density targets sit barely under what carve-plus-braid leaves, so a
# shallow-first ordering inside the density pass had almost no budget and
# drained nearly none of them. Maze.gd culls stubs in their own stage first.
const MAZES := [
	{
		"name": "The Grid",
		# The track this maze plays, named here rather than in an array indexed
		# by maze number -- that goes stale silently the moment a maze is added
		# (docs/specs/music.md, the rule landmarks already follow).
		#
		# A maze names its own tracks, rather than an array indexed by maze
		# number -- that goes stale the moment a maze is added, and silently
		# (docs/specs/music.md, the rule landmarks already follow).
		#
		# A LIST, one of which is drawn per visit, so replaying a maze is not
		# note-for-note the same. A bare string is still legal for a maze that
		# wants exactly one. Music.play_for_maze may instead draw from
		# SHARED_TRACKS -- see SHARED_TRACK_CHANCE.
		#
		# The first entry is the track written to this maze's palette; the rest
		# are the ones that also suit it.
		"music": ["cyan_plucks", "neon_maze_run"],
		"palette": 0,
		"width": 60,
		"height": 60,
		"braid": 0.06,
		"dead_ends": 0.025,
		# Fraction of one-cell stubs kept. Maze 1 is the introduction: a
		# turnaround here teaches nothing the player has the speed to act on.
		"shallow_keep": 0.15,
		"zigzag_keep": 0.62,
		"gates": 8,
		# Densest of the set. Maze 1 is where the vocabulary is learned, so the
		# player needs to meet several types before landmarks can mean anything.
		"landmarks": 0.85,
		# Longer straight runs than the later mazes, so maze 1 reads as an
		# introduction: room to build speed and to see a junction coming before
		# having to decide.
		#
		# This is the carve bias, not the braid. Braiding barely moves corridor
		# length (measured: 1.95 -> 1.77 avg run going 0.06 -> 0.12) because the
		# randomised DFS is what turns constantly. Biasing the carve to continue
		# straight is the actual lever: 0.60 gives ~3.0 avg run against ~1.6
		# unbiased, with a longest around 15. Higher starts producing
		# axis-aligned combs -- 0.70 pushed the longest straight past 40.
		"straighten": 0.60,
	},
	{
		"name": "The Ember",
		"music": ["burnt_orange_maze", "factory_maze"],
		"palette": 3,
		"width": 70,
		"height": 70,
		"braid": 0.12,
		"dead_ends": 0.028,
		"shallow_keep": 0.11,
		"zigzag_keep": 0.56,
		"gates": 8,
		"landmarks": 0.80,
	},
	{
		"name": "The Tangle",
		"music": ["neon_maze_run", "cyan_plucks"],
		"palette": 1,
		"width": 80,
		"height": 80,
		"braid": 0.18,
		"dead_ends": 0.030,
		"shallow_keep": 0.12,
		"zigzag_keep": 0.62,
		"gates": 8,
		"landmarks": 0.88,
	},
	{
		"name": "The Labyrinth",
		"music": ["acid_green_chase", "neon_maze_run"],
		"palette": 2,
		"width": 90,
		"height": 90,
		"braid": 0.25,
		"dead_ends": 0.030,
		"shallow_keep": 0.11,
		"zigzag_keep": 0.70,
		"gates": 8,
		"landmarks": 0.92,
	},
	{
		"name": "The Vault",
		"music": ["cold_minor_maze", "factory_maze", "acid_green_chase"],
		"palette": 4,
		"width": 100,
		"height": 100,
		# Loop density is the most interesting escalation lever (CLAUDE.md
		# section 8): more loops means more moments where the player is not
		# lost but is also not on the fastest route, and cannot tell which.
		# The last maze leans on it hardest.
		"braid": 0.30,
		"dead_ends": 0.032,
		# The run's last maze keeps the most stubs: by here the player has the
		# upgrades and the speed to be genuinely punished by one they misread,
		# which is the only reason to keep any at all.
		#
		# The NUMBER is not the measured outcome. shallow_keep is the fraction
		# kept by the cull stage, but the later density pass runs afterwards and
		# has almost no budget at high braid, so the stubs it would otherwise
		# drain survive: at 0.35 this maze measured 52% of all dead ends as
		# stubs. Tuned against DeadEndProbe rather than set to the intended
		# share directly -- re-run it after touching braid or dead_ends here.
		"shallow_keep": 0.10,
		"zigzag_keep": 0.78,
		"gates": 8,
		# Sparsest. By here the maze is 100x100 and a fixed fraction of a much
		# larger eligible set would be a forest -- scarcity is what makes a
		# landmark memorable (see LANDMARK_DENSITY).
		"landmarks": 0.95,
	},
]

# --- Per-maze palettes (CLAUDE.md section 8) ---------------------------------
#
# Each maze gets its own neon colourway, so arriving in a new maze reads as
# arriving somewhere -- not just as the same corridor with a bigger grid.
#
# The palette is the ONLY thing that changes; wall, grid and marker geometry are
# identical across every one. That matters because the grid lines are the timing
# contract (section 11.3): recolouring them is safe, restyling or reweighting
# them is not.
#
# Hue is the whole signal, and consecutive mazes are spaced far apart on the
# wheel so no two in a row are confusable at a glance. Value and saturation stay
# in the same band across all five, because brightness is already doing a job --
# the barrier bar goes red when low -- and a dim maze would make that read land
# differently maze to maze.
#
# THE ORDER IS NOT THE ORDER THEY WERE ADDED. Cyan, ember, magenta, green,
# violet: the two warm hues are held apart by magenta, and violet is kept off
# magenta's shoulder by putting green between them. Appending ember and violet
# to the end instead would have run magenta straight into violet, which is the
# one adjacency on this wheel that reads as the same maze twice.
#
# Ember is deliberately RED-orange rather than amber. NEON_GATE is amber-yellow,
# so an amber maze would put the navigation signal the player most needs to pick
# out into the same hue as every wall around them.
#
# `grid` must stay the readable one. It is the floor reference the whole control
# scheme rests on, so it is the one entry that should never be tuned dark to
# suit an aesthetic.
const PALETTES := [
	{
		"id": "cyan",
		"label": "GRID CYAN",
		# Maze 1 -- cyan. The stock lightcycle blue.
		"wall": Color(0.12, 0.85, 1.0),
		"grid": Color(0.30, 0.55, 0.85),
		"floor": Color(0.03, 0.04, 0.07),
		"wall_albedo": Color(0.13, 0.17, 0.25),
		"wall_emission": Color(0.07, 0.12, 0.20),
		"fog": Color(0.02, 0.05, 0.10),
	},
	{
		"id": "magenta",
		"label": "MAGENTA",
		# Maze 2 -- magenta / violet. Warmer and denser, matching the step up in
		# braid factor: the maze starts closing in.
		"wall": Color(1.0, 0.25, 0.85),
		"grid": Color(0.70, 0.42, 0.90),
		"floor": Color(0.06, 0.03, 0.08),
		"wall_albedo": Color(0.22, 0.14, 0.26),
		"wall_emission": Color(0.18, 0.07, 0.20),
		"fog": Color(0.07, 0.02, 0.09),
	},
	{
		"id": "acid",
		"label": "ACID GREEN",
		# Maze 3 -- acid green. The most alien of the set, and far from both of
		# its neighbours on the wheel.
		"wall": Color(0.35, 1.0, 0.45),
		"grid": Color(0.45, 0.80, 0.45),
		"floor": Color(0.02, 0.06, 0.04),
		"wall_albedo": Color(0.13, 0.24, 0.16),
		"wall_emission": Color(0.06, 0.18, 0.09),
		"fog": Color(0.02, 0.08, 0.04),
	},
	{
		"id": "ember",
		"label": "EMBER",
		# Palette 3 -- ember. Bright red-orange, held clear of the amber the
		# gate markers use.
		#
		# The grid line lifts toward gold, but only just. It first went to a
		# bright yellow (0.95, 0.68, 0.30) on the reasoning that a grid in the
		# wall's own hue vanishes into the wall glow -- true, but it drove the
		# AMBIENT warm, and ambient is mixed from the grid colour. Every other
		# palette lands ambient cool (R-B between -0.11 and -0.22); yellow put
		# ember at +0.02, and cool ambient on a dark wall reads as shadow while
		# neutral-warm ambient reads as a LIT SURFACE. Every wall face turned
		# milky brown, the floor grid washed out against it, and the corridor
		# lost its depth -- the exact failure documented for maze 3's green in
		# CLAUDE.md section 8, arriving through the light rather than the
		# material.
		#
		# Held cool-leaning instead, with the separation from the wall coming
		# from VALUE (a paler, desaturated gold against saturated orange)
		# rather than from hue.
		"wall": Color(1.0, 0.45, 0.10),
		"grid": Color(0.85, 0.62, 0.42),
		"floor": Color(0.055, 0.028, 0.018),
		# Darker than the cool palettes' albedo at equal luminance, because a
		# warm hue at the same measured luminance reads lighter than a cool one.
		"wall_albedo": Color(0.21, 0.13, 0.085),
		"wall_emission": Color(0.19, 0.085, 0.025),
		"fog": Color(0.065, 0.03, 0.014),
	},
	{
		"id": "violet",
		"label": "DEEP VIOLET",
		# Palette 4 -- deep violet. The run's last maze, and the coldest and
		# deepest of the five.
		#
		# Pushed BLUE of maze 2's magenta rather than merely darker: value and
		# saturation stay in the same band across the set (see above), so hue is
		# the only axis available to separate two colourways that are otherwise
		# neighbours. The grid lifts toward periwinkle for the same reason the
		# ember grid lifts toward yellow -- a violet line on a violet floor is
		# the least readable pairing in the whole set.
		"wall": Color(0.62, 0.35, 1.0),
		"grid": Color(0.62, 0.60, 0.95),
		"floor": Color(0.035, 0.025, 0.07),
		"wall_albedo": Color(0.17, 0.14, 0.28),
		"wall_emission": Color(0.11, 0.06, 0.22),
		"fog": Color(0.04, 0.025, 0.10),
	},
	# --- Unlockable colourways ------------------------------------------------
	#
	# The five above are the mazes' OWN palettes and their order is load-bearing:
	# default_palette_id() maps maze N to PALETTES[N]. Everything below is extra
	# choice, appended so that mapping never moves.
	#
	# GENERATED against the measured rule rather than hand-picked, because the
	# failure mode is not visible in the swatch. Ambient is mixed from the GRID
	# colour (Game._apply_palette blends it 20/80 toward neutral), and warm
	# ambient reads as a LIT surface where cool ambient reads as shadow -- which
	# is what turned every wall milky brown when ember's grid was yellow.
	#
	# Measured across the five authored palettes, ambient R-B runs -0.222 (cyan)
	# to -0.026 (ember), and ember is the one that had to be pulled back. So the
	# rule is: ambient R-B must stay NEGATIVE, and ember's -0.026 is the outer
	# limit. Every palette below is generated with its grid hue shifted toward
	# blue in proportion to how warm its wall is -- ember's correction, applied
	# systematically. The worst of the twenty lands at -0.032.
	#
	# RulesTest asserts the rule over the WHOLE table, so a palette added later
	# by hand cannot reintroduce the failure silently.
	{
		"id": "ice",
		"label": "ICE",
		# Pale blue, the coldest read in the set.
		"wall": Color(0.120, 0.894, 1.000),
		"grid": Color(0.400, 0.752, 0.800),
		"floor": Color(0.029, 0.061, 0.065),
		"wall_albedo": Color(0.136, 0.223, 0.235),
		"wall_emission": Color(0.042, 0.172, 0.190),
		"fog": Color(0.027, 0.078, 0.085),
	},
	{
		"id": "azure",
		"label": "AZURE",
		# Deeper than ice, still unmistakably blue.
		"wall": Color(0.120, 0.578, 1.000),
		"grid": Color(0.360, 0.589, 0.800),
		"floor": Color(0.029, 0.048, 0.065),
		"wall_albedo": Color(0.136, 0.188, 0.235),
		"wall_emission": Color(0.042, 0.119, 0.190),
		"fog": Color(0.027, 0.057, 0.085),
	},
	{
		"id": "cobalt",
		"label": "COBALT",
		# Blue pushed toward indigo.
		"wall": Color(0.120, 0.314, 1.000),
		"grid": Color(0.320, 0.426, 0.800),
		"floor": Color(0.029, 0.037, 0.065),
		"wall_albedo": Color(0.136, 0.158, 0.235),
		"wall_emission": Color(0.042, 0.074, 0.190),
		"fog": Color(0.027, 0.040, 0.085),
	},
	{
		"id": "indigo",
		"label": "INDIGO",
		# The dark end of blue, before violet takes over.
		"wall": Color(0.296, 0.120, 1.000),
		"grid": Color(0.448, 0.360, 0.800),
		"floor": Color(0.036, 0.029, 0.065),
		"wall_albedo": Color(0.156, 0.136, 0.235),
		"wall_emission": Color(0.071, 0.042, 0.190),
		"fog": Color(0.039, 0.027, 0.085),
	},
	{
		"id": "orchid",
		"label": "ORCHID",
		# Violet leaning pink.
		"wall": Color(0.771, 0.120, 1.000),
		"grid": Color(0.692, 0.384, 0.800),
		"floor": Color(0.056, 0.029, 0.065),
		"wall_albedo": Color(0.209, 0.136, 0.235),
		"wall_emission": Color(0.151, 0.042, 0.190),
		"fog": Color(0.070, 0.027, 0.085),
	},
	{
		"id": "plum",
		"label": "PLUM",
		# Deep and dusty, the quietest of the purples.
		"wall": Color(1.000, 0.120, 0.965),
		"grid": Color(0.800, 0.400, 0.784),
		"floor": Color(0.065, 0.029, 0.064),
		"wall_albedo": Color(0.235, 0.136, 0.231),
		"wall_emission": Color(0.190, 0.042, 0.184),
		"fog": Color(0.085, 0.027, 0.083),
	},
	{
		"id": "fuchsia",
		"label": "FUCHSIA",
		# Hot pink, the loudest hue offered.
		"wall": Color(1.000, 0.120, 0.648),
		"grid": Color(0.800, 0.360, 0.571),
		"floor": Color(0.065, 0.029, 0.051),
		"wall_albedo": Color(0.235, 0.136, 0.196),
		"wall_emission": Color(0.190, 0.042, 0.131),
		"fog": Color(0.085, 0.027, 0.062),
	},
	{
		"id": "rose",
		"label": "ROSE",
		# Pink softened toward red.
		"wall": Color(1.000, 0.120, 0.384),
		"grid": Color(0.800, 0.424, 0.400),
		"floor": Color(0.065, 0.029, 0.040),
		"wall_albedo": Color(0.235, 0.136, 0.166),
		"wall_emission": Color(0.190, 0.042, 0.086),
		"fog": Color(0.085, 0.027, 0.045),
	},
	{
		"id": "crimson",
		"label": "CRIMSON",
		# Blood red. Warm, so the grid is pulled cool.
		"wall": Color(1.000, 0.120, 0.173),
		"grid": Color(0.440, 0.562, 0.800),
		"floor": Color(0.065, 0.029, 0.031),
		"wall_albedo": Color(0.235, 0.136, 0.142),
		"wall_emission": Color(0.190, 0.042, 0.051),
		"fog": Color(0.085, 0.027, 0.031),
	},
	{
		"id": "coral",
		"label": "CORAL",
		# Red-orange, distinct from ember's pure orange.
		"wall": Color(1.000, 0.305, 0.120),
		"grid": Color(0.464, 0.528, 0.800),
		"floor": Color(0.065, 0.037, 0.029),
		"wall_albedo": Color(0.235, 0.157, 0.136),
		"wall_emission": Color(0.190, 0.073, 0.042),
		"fog": Color(0.085, 0.039, 0.027),
	},
	{
		"id": "bronze",
		"label": "BRONZE",
		# Burnt orange, the warmest ground in the set.
		"wall": Color(1.000, 0.569, 0.120),
		"grid": Color(0.480, 0.483, 0.800),
		"floor": Color(0.065, 0.047, 0.029),
		"wall_albedo": Color(0.235, 0.187, 0.136),
		"wall_emission": Color(0.190, 0.117, 0.042),
		"fog": Color(0.085, 0.057, 0.027),
	},
	{
		"id": "sand",
		"label": "SAND",
		# Pale gold.
		"wall": Color(1.000, 0.754, 0.120),
		"grid": Color(0.502, 0.496, 0.800),
		"floor": Color(0.065, 0.055, 0.029),
		"wall_albedo": Color(0.235, 0.207, 0.136),
		"wall_emission": Color(0.190, 0.149, 0.042),
		"fog": Color(0.085, 0.069, 0.027),
	},
	{
		"id": "olive",
		"label": "OLIVE",
		# Yellow-green, the murkiest of the greens.
		"wall": Color(0.877, 1.000, 0.120),
		"grid": Color(0.525, 0.480, 0.800),
		"floor": Color(0.060, 0.065, 0.029),
		"wall_albedo": Color(0.221, 0.235, 0.136),
		"wall_emission": Color(0.169, 0.190, 0.042),
		"fog": Color(0.077, 0.085, 0.027),
	},
	{
		"id": "lime",
		"label": "LIME",
		# Bright yellow-green.
		"wall": Color(0.560, 1.000, 0.120),
		"grid": Color(0.447, 0.440, 0.800),
		"floor": Color(0.047, 0.065, 0.029),
		"wall_albedo": Color(0.186, 0.235, 0.136),
		"wall_emission": Color(0.116, 0.190, 0.042),
		"fog": Color(0.056, 0.085, 0.027),
	},
	{
		"id": "jade",
		"label": "JADE",
		# Green with blue in it.
		"wall": Color(0.120, 1.000, 0.261),
		"grid": Color(0.400, 0.800, 0.704),
		"floor": Color(0.029, 0.065, 0.035),
		"wall_albedo": Color(0.136, 0.235, 0.152),
		"wall_emission": Color(0.042, 0.190, 0.066),
		"fog": Color(0.027, 0.085, 0.036),
	},
	{
		"id": "mint",
		"label": "MINT",
		# Pale green-cyan.
		"wall": Color(0.120, 1.000, 0.578),
		"grid": Color(0.416, 0.800, 0.731),
		"floor": Color(0.029, 0.065, 0.048),
		"wall_albedo": Color(0.136, 0.235, 0.188),
		"wall_emission": Color(0.042, 0.190, 0.119),
		"fog": Color(0.027, 0.085, 0.057),
	},
	{
		"id": "teal",
		"label": "TEAL",
		# The blue-green midpoint.
		"wall": Color(0.120, 1.000, 0.894),
		"grid": Color(0.384, 0.800, 0.750),
		"floor": Color(0.029, 0.065, 0.061),
		"wall_albedo": Color(0.136, 0.235, 0.223),
		"wall_emission": Color(0.042, 0.190, 0.172),
		"fog": Color(0.027, 0.085, 0.078),
	},
	{
		"id": "aqua",
		"label": "AQUA",
		# Cyan pushed slightly green.
		"wall": Color(0.120, 1.000, 1.000),
		"grid": Color(0.360, 0.800, 0.800),
		"floor": Color(0.029, 0.065, 0.065),
		"wall_albedo": Color(0.136, 0.235, 0.235),
		"wall_emission": Color(0.042, 0.190, 0.190),
		"fog": Color(0.027, 0.085, 0.085),
	},
	{
		"id": "slate",
		"label": "SLATE",
		# Desaturated blue-grey, the most restrained option.
		"wall": Color(0.120, 0.472, 1.000),
		"grid": Color(0.560, 0.656, 0.800),
		"floor": Color(0.029, 0.044, 0.065),
		"wall_albedo": Color(0.136, 0.176, 0.235),
		"wall_emission": Color(0.042, 0.101, 0.190),
		"fog": Color(0.027, 0.050, 0.085),
	},
	{
		"id": "ash",
		"label": "ASH",
		# Near-neutral with a cold cast.
		"wall": Color(0.120, 0.208, 1.000),
		"grid": Color(0.624, 0.642, 0.800),
		"floor": Color(0.029, 0.033, 0.065),
		"wall_albedo": Color(0.136, 0.146, 0.235),
		"wall_emission": Color(0.042, 0.057, 0.190),
		"fog": Color(0.027, 0.033, 0.085),
	},
]

# Gate and exit markers keep a FIXED colour across every maze. They are
# navigation, not decoration: a gate must be identifiable as a gate the instant
# it comes into view, and recolouring it per maze would mean re-learning what
# the bright thing in the corridor once per maze.
const NEON_GATE := Color(1.0, 0.85, 0.15)
const NEON_EXIT := Color(1.0, 1.0, 1.0)

# Coins, fixed across every maze for the reason gates and the exit are: a coin
# is a thing you learn to recognise once. Warm gold, and it has to separate from
# NEON_GATE's amber-yellow at distance -- so a coin is small and SPINS while a
# gate is a tall static slab, and the two never read alike in motion even where
# the hues are neighbours.
const NEON_COIN := Color(1.0, 0.78, 0.22)

# How the coin sits and moves. It floats clear of the floor so the disc is seen
# edge-on from the trailing camera rather than lying flat where it would be a
# line, and spins slowly enough to read as an object turning rather than as a
# flicker at 8x.
# Measured against CAM_HEIGHT (2.3) rather than picked: a coin at eye level is
# seen against the far wall and the dark corridor mouth behind it, where a low
# one is seen against the lit floor grid and competes with the timing lines the
# player is actually reading (section 11.3). Just under two thirds of eye height
# puts it clear of the floor markings and still well below the wall line, so it
# never reads as a gate.
const COIN_HOVER_HEIGHT := 1.4
# Big enough to read at MAX_AHEAD cells down a corridor. At 0.55 the disc was a
# sliver at distance -- measured in a rendered frame, which is the only place a
# size like this can be judged.
const COIN_RADIUS := 0.72
const COIN_THICKNESS := 0.14
const COIN_SPIN_RATE := 1.6          # radians/sec
# A slow vertical bob, so a coin is distinguishable from a static landmark at a
# glance even before its spin resolves.
const COIN_BOB_HEIGHT := 0.18
const COIN_BOB_RATE := 1.9

# A gate already taken. Cool and dim against the live gate's warm amber, so the
# two separate on HUE as well as brightness -- brightness alone is what the wall
# indicator ramps on (section 5.6), and a spent gate seen far off through fog
# would otherwise read as a live one that is merely distant.
#
# A taken gate used to be DELETED outright, which threw away the one thing it is
# still good for. It carries no upgrade any more, but it is a landmark the
# player unquestionably visited -- the strongest possible answer to "have I been
# here before?" in a looped maze (section 6), and unlike a landmark it is
# already known to sit on the solve path.
#
# It must never be mistaken for the exit, which is why this is blue-grey rather
# than a desaturated amber: the exit is white, and washing a gate toward
# neutral would walk it straight into the exit's colour.
#
# Rendered and checked rather than picked on paper: at (0.35, 0.5, 0.65) the
# marker came out close to WHITE against the night sky, which walks it into the
# exit's colour -- and mistaking a spent gate for the exit is a far worse error
# than mistaking it for a live one. Deepened and pushed further toward blue so
# the hue survives the unshaded material and the bloom around it.
const NEON_GATE_SPENT := Color(0.16, 0.34, 0.62)

# How much of a live gate's glow a spent one keeps. It has to stay visible as a
# marker while losing every bit of its pull as a destination -- the whole reason
# the marker is bright is that the player is routing toward it, and a taken gate
# is the one thing in the maze they specifically should not route toward.
const GATE_SPENT_ENERGY := 0.35
const GATE_SPENT_ALPHA := 0.28

# Where a spent gate's marker STARTS, as a multiple of WALL_HEIGHT. A live gate
# runs from the floor up; a spent one is cut off at the ankles and left hanging.
#
# This is not decoration, it fixes a real failure. The marker is transparent and
# CULL_DISABLED (the player drives THROUGH a gate, so both faces have to draw),
# and the camera sits at CAM_HEIGHT -- well inside the slab. Driving through a
# live gate therefore puts the eye inside the marker for a frame or two, which
# washes the whole screen its colour. That was invisible while a taken gate was
# deleted on the spot; keeping the marker made it permanent, and a player who
# re-crossed a cleared gate got a full-screen tint every time.
#
# Raising the base above the camera is better than making the marker opaque or
# thinner: it keeps the part that does the work. What makes a gate visible from
# several corridors away is the section ABOVE the wall line (GATE_MARKER_HEIGHT
# is 1.85x wall height for exactly that reason), and none of that is touched.
# The only part removed is the part at eye level, which on a spent gate is not
# a doorway any more -- there is nothing left to drive through.
#
# Sits just above CAM_HEIGHT / WALL_HEIGHT, with clearance for the camera's
# vertical give on a crash pull-back.
const GATE_SPENT_BASE := 0.95


# Marker heights, as a multiple of WALL_HEIGHT.
#
# Both CLEAR THE WALL LINE, and that is the whole point of the numbers.
#
# Gates were 0.9 -- just UNDER the walls -- so a gate was invisible until the
# player was already in its corridor, which is no warning at all at a speed
# where a cell passes in 125ms. A gate is navigation (section 7): it sits on the
# solve path, it pauses the timer, and it is the thing the player is routing
# TOWARD, so seeing one two corridors away is the entire reason it is a physical
# object in the world rather than a HUD readout.
#
# This is the same argument the skyline landmark tier rests on: the camera is
# capped below WALL_HEIGHT on purpose (section 12), so the ONLY way anything is
# visible from the next corridor over is by being tall enough to clear the walls
# itself. Raising the camera instead would flatten the maze into a floor plan.
#
# The exit stays TALLER than a gate. Now that both clear the walls, height is
# what separates them at distance -- a gate is a waypoint, the exit ends the
# maze, and mistaking one for the other at speed is a real routing error.
# Colour separates them up close (amber-yellow vs white).
const GATE_MARKER_HEIGHT := 1.85

# How close a widened gate marker may come to the corridor's side walls.
#
# The bound exists because Gate Size widens the marker (GATE_SIZE_GIRTH_BY_RANK)
# and the corridor does not widen with it. A slab that reached the wall would be
# drawn intersecting it, and at 0.55 alpha that reads as a rendering fault, not
# as a bigger gate. Enforced in the mesh rather than only in the table, so a
# future rank added to the table cannot quietly bury the marker.
const GATE_MARKER_WALL_CLEARANCE := 0.05
const EXIT_MARKER_HEIGHT := 2.6


# --- World scale -------------------------------------------------------------

# Metres per maze cell. Corridors want to feel tight at speed.
const CELL_SIZE := 4.0
const WALL_HEIGHT := 3.0

# Wall thickness. ZERO -- walls are flat planes, not boxes.
#
# They were boxes (0.5, briefly 0.7) on the theory that a flat wall shows
# nothing edge-on, so corridor mouths would read as slits cut in paper. Play
# showed the reverse: the slab's side faces and end caps were clearly visible
# passing any opening, every junction advertised the wall's depth, and the maze
# read as a pile of 3D blocks instead of a clean lightcycle grid. Thickness was
# also the direct cause of the doubled-wall and banded-panel artifacts, both of
# which existed only because there was a slab to decorate.
#
# Walls stay fully OPAQUE at zero thickness -- opacity is a material property,
# not a geometric one. What thickness bought was a visible side face, and that
# was exactly the thing that looked wrong.
#
# Kept as a named constant rather than deleted: it appears in the
# centre-to-wall-face maths in several places (`CELL_SIZE * 0.5 -
# WALL_THICKNESS * 0.5`), where zero is simply the correct value and those
# expressions stay meaningful if walls ever gain thickness again.
const WALL_THICKNESS := 0.0

# Eye sits high in the corridor so the glowing wall tops stay in frame and the
# floor grid reads well ahead. Down near 1.6 the view is all wall and the grid
# lines -- the timing contract -- crowd into the bottom of the screen.
const EYE_HEIGHT := 2.1

# Camera FOV scales with speed -- the cheapest and strongest speed cue there is.
const FOV_BASE := 75.0
const FOV_AT_CAP := 105.0

# --- Third-person camera -----------------------------------------------------
#
# The camera trails behind and above the player marker rather than sitting in
# its head. First person hid the one thing the player most needs to see: where
# they actually are in the corridor, and which way they are pointed. With the
# marker visible, a turn reads instantly and wall proximity is obvious.

# How far behind the marker the camera sits, in metres.
#
# Kept under one cell (4m). Further back and the camera lands in the previous
# cell, which is solid wall whenever the player just turned a corner or is in a
# dead end -- and at the maze edge it ends up outside the boundary wall
# entirely, looking in through it.
const CAM_DISTANCE := 3.2

# How far above the floor. Must stay BELOW WALL_HEIGHT (3.0): above it the
# camera sees over every wall at once, the maze flattens into a floor plan, and
# the corridor stops feeling enclosed.
const CAM_HEIGHT := 2.3

# How far above the floor the camera aims. Looking slightly above the marker
# puts the corridor ahead in frame rather than the floor at the player's feet.
const CAM_LOOK_HEIGHT := 1.35

# The camera pulls back as speed rises, widening the view when reaction time is
# shortest. Small, for the same reason CAM_DISTANCE is: it must not push the
# camera into the cell behind.
const CAM_DISTANCE_AT_CAP := 0.6

# --- Crash camera ------------------------------------------------------------
#
# On a crash the camera pulls back and lifts, so being stopped at a wall reads
# instantly as a state change rather than just "the picture stopped moving".
#
# Distance alone is not enough: a crash happens WITH A WALL AHEAD, and often in
# a dead end or fresh corner, so the anti-clip clamp frequently eats the entire
# pull-back. Height is the axis that stays available when backing up does not,
# which is why the crash view lifts as well as retreats.
const CAM_CRASH_DISTANCE := 2.0
const CAM_CRASH_HEIGHT := 1.5

# Still capped below WALL_HEIGHT, for the same reason the normal camera is: rise
# above the walls and the maze flattens into a floor plan.
const CAM_CRASH_HEIGHT_MAX := WALL_HEIGHT - 0.35

# Where the crash view aims. Low, so the camera looks DOWN at the stopped player
# rather than level into the wall they just hit -- aiming at normal look height
# from a raised eye fills the screen with one flat wall face and hides
# everything the pull-back was meant to show.
const CAM_CRASH_LOOK_HEIGHT := 0.35

# Seconds for the crash view to ease in and out. Fast enough to feel like a
# reaction, slow enough not to snap.
const CAM_CRASH_EASE := 6.0

# --- Camera sensitivity ------------------------------------------------------
#
# How fast the chase camera slews onto a new heading after a pivot, as a player
# preference on a 0..50 dial, shipped at notch 20. 0 is a snap -- the view is on
# the new corridor the frame the racer turns. 50 trails so far behind that the
# camera is still coming round many cells after the freeze has ended and the
# racer is already moving, so it is genuinely NOT always behind you.
#
# A RATE, not a duration, and that distinction is what keeps it a view setting
# rather than a game rule. The freeze (TURN_FREEZE) is a rule -- it holds the
# racer still, it costs run time, and Snap Turn buys it down. This dial does not
# touch it. What it changes is only how much of the swing the camera spends
# INSIDE that hold, which is a question about the view and nothing else.
#
# So the simulation still cannot read this: the racer pivots, freezes and
# resumes identically at every setting. Only the eye behaves differently, which
# is the same separation the marker shape and the maze palettes have.
const CAM_YAW_RATE_DEFAULT := 12.0

# The slow end of the dial, in the same units as CAM_YAW_RATE_DEFAULT (the
# fraction of the remaining angle closed per second).
#
# At 1.0 a 90-degree pivot is nowhere near the new heading when the 0.10s freeze
# ends even with the freeze multiplier applied, so the camera is still visibly
# coming round several cells later -- which is exactly what the dial's top end
# is being asked for.
#
# It was 2.5, and the comment here said "not lower: below about 2 the view is
# still swinging when the NEXT junction arrives". MEASURED, that bound was
# already breached at 2.5: the swing takes 867ms to settle, which is 4.3 cells
# at 5x. The old number was not the edge of the section 11.3 rule, it was just
# the slowest rate anyone had asked for.
#
# What the rule actually protects is that the corridor is READABLE by the time
# the player has to act on it, not that the swing has finished. Measured as the
# share of a 90 completed after one cell has passed:
#
#     rate    @1x     @3x     @5x     @8x
#     2.50    97%     81%     74%     68%
#     1.00    73%     47%     41%     35%
#     0.80    65%     40%     34%     29%
#
# At 1.0 the player is 41% round after a cell at 5x and the new corridor is
# resolving; the lag is heavy but the view is still arriving. Below about 0.8 it
# stops being a lag and becomes a camera that never catches up at all, which is
# the fault the rule forbids -- a corridor the player cannot see yet is the one
# thing no preference should be able to buy.
const CAM_YAW_RATE_SLOW := 1.0

# Where the default sits on the dial, as a fraction of its travel.
#
# TWO FIFTHS, so on a 0..50 dial the shipped camera is notch 20 and the THIRTY
# notches above it are all lag the dial did not previously reach. It was
# implicitly one HALF while the default was the geometric mean of the two ends
# (what SNAP = DEFAULT^2 / SLOW encodes), then two thirds on the 0..30 dial.
#
# The notch itself has not moved across either change -- the default has been 20
# since the dial reached 30, and stays 20 here. What changes is the fraction of
# the TRAVEL that notch represents, because the dial got longer above it.
#
# Named rather than left implicit because the derivation below reads it: moving
# the default along the dial is a change to THIS number, and the endpoint
# re-solves to keep the default landing exactly on a whole notch.
const CAM_DEFAULT_DIAL_FRACTION := 20.0 / 50.0

# The fast end, DERIVED so that the shipped rate lands exactly on a whole notch
# rather than between two of them.
#
# A hand-picked snap rate and a whole-number dial are two incompatible demands:
# with the ends chosen independently, the notch nearest the default was 10.5
# against the shipped 12.0, so the setting a player never touches would not have
# been the camera the game shipped with. Solving for the ENDPOINT instead fixes
# that by construction.
#
# The general form, since the default is no longer the midpoint. On a geometric
# curve DEFAULT = SNAP^(1-f) * SLOW^f, so SNAP = (DEFAULT / SLOW^f)^(1/(1-f)) --
# which reduces to the old DEFAULT^2 / SLOW at f = 1/2. Solving it this way is
# what let the dial grow to 30 notches with the default moved to 20 while BOTH
# ends kept their meaning: verified, notch 20 comes out at exactly 12.000000.
#
# It comes out around 276, well past the ~57.6 it used to be -- but that is a
# distinction without a difference in play. Anything above 60 closes the WHOLE
# remaining angle inside one frame at 60fps, and the per-frame step is clamped
# to 1.0 regardless, so every notch up to about 9 is the same rigid lock. That
# is not a defect: 0 on the dial is meant to be indistinguishable from the
# camera being welded to the racer's facing, and the notches near it are simply
# more of that same answer.
const CAM_YAW_RATE_SNAP := pow(
	CAM_YAW_RATE_DEFAULT / pow(CAM_YAW_RATE_SLOW, CAM_DEFAULT_DIAL_FRACTION),
	1.0 / (1.0 - CAM_DEFAULT_DIAL_FRACTION))

# The dial the player actually sees. Whole numbers, because a camera lag is not
# a thing anyone tunes to a decimal place.
#
# FIFTY notches, and the growth has bought different things each time.
#
# 10 -> 20 bought RESOLUTION: both ends held, so the dial became finer rather
# than laggier. 20 -> 30 moved the DEFAULT off the midpoint, adding ten notches
# of lag above it. 30 -> 50 went further and lowered CAM_YAW_RATE_SLOW itself,
# which is the first time the dial's slowest camera has actually got slower.
#
# The default has stayed on notch 20 throughout the last two, which is what
# CAM_DEFAULT_DIAL_FRACTION is re-solved to preserve -- the shipped camera is
# the one number a player who never opens the setting is entitled to keep.
#
# The curve is reshaped on every one of these, not restretched, so a setting
# does NOT carry across at a simple multiple of its old number. Worth knowing
# because a saved settings.cfg holds a bare notch: a player sitting on the old
# 0..30 maximum (notch 30, rate 2.5) lands on rate 5.24 here, a snappier camera
# than they chose, and has to travel up the longer dial to get it back.
const CAM_SENSITIVITY_MIN := 0.0
const CAM_SENSITIVITY_MAX := 50.0

# Where the dial sits on a fresh profile.
#
# DERIVED from CAM_YAW_RATE_DEFAULT rather than written as a literal, so the
# default setting and the rate the game shipped with cannot drift apart -- the
# transcription trap section 12 records for tests, in tuning clothes. It is the
# dial position whose rate is the old hard-coded 12.0, so a player who never
# opens the setting gets exactly the camera the game had before it existed.
static func cam_sensitivity_default() -> float:
	return round(cam_sensitivity_for_rate(CAM_YAW_RATE_DEFAULT))


# The slew rate a dial position asks for.
#
# GEOMETRIC between the two ends, not linear. Rate is a reciprocal-feeling
# quantity: the visible difference between 90 and 60 is nothing, while the
# difference between 4 and 2.5 is the whole top half of the dial. A linear map
# would spend most of its travel in the range where nothing changes and cram
# every setting anyone would actually pick into the last two notches.
static func cam_yaw_rate(sensitivity: float) -> float:
	var t: float = clampf(
		(sensitivity - CAM_SENSITIVITY_MIN)
			/ (CAM_SENSITIVITY_MAX - CAM_SENSITIVITY_MIN), 0.0, 1.0)
	return CAM_YAW_RATE_SNAP * pow(CAM_YAW_RATE_SLOW / CAM_YAW_RATE_SNAP, t)


# The inverse, so the default dial position can be derived from the rate rather
# than transcribed alongside it.
static func cam_sensitivity_for_rate(rate: float) -> float:
	var r: float = clampf(rate, CAM_YAW_RATE_SLOW, CAM_YAW_RATE_SNAP)
	var t: float = (log(r / CAM_YAW_RATE_SNAP)
		/ log(CAM_YAW_RATE_SLOW / CAM_YAW_RATE_SNAP))
	return CAM_SENSITIVITY_MIN + t * (CAM_SENSITIVITY_MAX - CAM_SENSITIVITY_MIN)

# --- Line of sight -----------------------------------------------------------
#
# The player marker must NEVER be hidden by a wall. It is the thing the player
# steers with -- it answers position, wall clearance and facing all at once
# (section 12) -- so a marker behind geometry is strictly worse than a bad
# camera angle. This is a hard rule, not a preference.
#
# The two existing anti-clip passes keep the EYE out of walls; neither checks
# whether a wall sits BETWEEN the eye and the marker. Those are different
# questions, and the gap between them is exactly the case that bites: swinging
# through a corner the camera sits in clear space while the segment to the
# marker clips the inside corner of the turn, so the wall you just came past
# wipes across the marker for a few frames -- precisely when the player most
# needs to see where they landed.
#
# Walls are WALL_HEIGHT (3.0) and the camera is capped below that, so it can
# never see OVER one. Sight is therefore a pure floor-plane problem.

# How close the sight line may pass to a wall face before the camera is pulled
# in. A little clearance rather than zero, so the marker is not left grazing a
# corner it is technically just clear of.
const CAM_SIGHT_MARGIN := 0.18

# Smallest distance the camera may be pulled to while clearing the sight line.
# Below this the view is inside the marker and the corridor stops reading.
const CAM_SIGHT_MIN_DISTANCE := 0.9

# Absolute last-resort camera distance, used only when nothing at
# CAM_SIGHT_MIN_DISTANCE clears the marker.
#
# Note that LIFTING is not an option in this case: walls run floor to
# WALL_HEIGHT with no gap and the camera is capped below that, so a level sight
# line is blocked at every height the camera can hold. Closing the distance is
# the only lever left, and an uncomfortably tight camera for a frame or two
# beats the marker vanishing.
const CAM_SIGHT_HARD_MIN := 0.35

# The absolute floor on camera-to-marker distance, below CAM_SIGHT_HARD_MIN.
#
# Reached only when even the hard minimum leaves the marker blocked, which the
# geometry does allow just after a turn: the marker is closest to the corner it
# has rounded, and _sight_blocked() holds CAM_SIGHT_MARGIN of clearance off
# every wall face on top of the distance.
#
# It is not zero because eye and target would then coincide on the floor plane,
# and look_at() warns about colinear vectors every frame it happens. A sliver
# keeps the camera's basis well-defined while sitting effectively on the marker.
const CAM_SIGHT_FLOOR := 0.06

# --- Player marker -----------------------------------------------------------

# A ring with an arrow inside it, sitting on the floor. The ring reads position
# and wall clearance; the arrow reads facing.
#
# Roughly a sixth of a cell across. The marker has to be small enough that the
# corridor around it stays visible -- it is a position indicator, not a vehicle,
# and at cell-filling size it hides the very walls the player is judging
# clearance against.
const MARKER_RADIUS := 0.62
const MARKER_HEIGHT := 0.22

# --- Marker shapes (CLAUDE.md, "The marker's shape is the player's to pick") --
#
# The inner mark inside the ring, as a pickable table. Cosmetic only: nothing in
# the simulation reads the choice, and every entry draws in the SAME near-white
# as the arrow always did. Colour is deliberately NOT on the menu -- the marker
# is white because a saturated marker collides with a maze palette, and because
# scrape-amber and crash-red only read as STATE while the resting colour carries
# no hue of its own.
#
# A TABLE, not a parallel array: each entry names itself and carries its own
# outline, so adding a shape is one entry here rather than an edit in several
# places -- the failure recorded for landmark density and music tracks. The
# preference is stored by `id`, never by index, because an index would silently
# re-point every existing player's choice at a different shape the moment this
# table is reordered.
#
# `outline` is the shape's footprint on the floor, in units of MARKER_RADIUS,
# with -Z forward. Wound counter-clockwise seen from above, which is what the
# builder's fan expects. Winding cannot be eyeballed (section 12) -- it is
# asserted rather than trusted.
#
# EVERY ENTRY MUST POINT. That is the acceptance test for adding one, not a
# matter of taste: a symmetric mark reads as position only, and the ring already
# says that. Each outline reaches further along its facing axis than across it,
# and each has a distinguishable front. RulesTest asserts exactly this.
const MARKER_SHAPE_DEFAULT := "arrow"

const MARKER_SHAPES := [
	{
		"id": "arrow",
		"label": "ARROW",
		# The original: a tip ahead, two barbs behind, and a notched tail so the
		# shape reads as an arrow rather than a plain triangle at a glance.
		"outline": [
			Vector2(0.0, -1.15),
			Vector2(0.85, 0.75),
			Vector2(0.0, 0.32),
			Vector2(-0.85, 0.75),
		],
	},
	{
		"id": "dart",
		"label": "DART",
		# Narrower and deeper than the arrow, with a harder tail notch. Reads as
		# faster at a glance, which is the whole point of offering it.
		"outline": [
			Vector2(0.0, -1.30),
			Vector2(0.62, 0.85),
			Vector2(0.0, 0.10),
			Vector2(-0.62, 0.85),
		],
	},
	{
		"id": "delta",
		"label": "DELTA",
		# A plain swept triangle -- no tail notch, so it reads as a solid wedge.
		# The broadest silhouette in the table, which is the one that holds up
		# best against a busy wall.
		"outline": [
			Vector2(0.0, -1.20),
			Vector2(0.95, 0.70),
			Vector2(-0.95, 0.70),
		],
	},
	{
		"id": "chevron",
		"label": "CHEVRON",
		# An open V: the arrow with its middle cut away. Lighter on screen, and
		# it lets more of the floor grid through the marker -- the grid lines
		# are the timing contract, so a mark that hides less of them is a real
		# option rather than only a different look.
		"outline": [
			Vector2(0.0, -1.15),
			Vector2(0.90, 0.62),
			Vector2(0.44, 0.86),
			Vector2(0.0, -0.30),
			Vector2(-0.44, 0.86),
			Vector2(-0.90, 0.62),
		],
	},
	{
		"id": "kite",
		"label": "KITE",
		# Longer ahead than behind, so it points by proportion rather than by a
		# barb. The tail is a single vertex, which keeps the rear silhouette
		# clean where the arrow's notch can read as noise at distance.
		"outline": [
			Vector2(0.0, -1.25),
			Vector2(0.72, 0.05),
			Vector2(0.0, 0.95),
			Vector2(-0.72, 0.05),
		],
	},
	{
		"id": "cycle",
		"label": "LIGHTCYCLE",
		# The genre nod (Armagetron/Tron): a long hull with a drawn-out nose and
		# a swept tail.
		#
		# The FIRST version was a near-rectangular slab with a merely cut nose,
		# and it rendered as a symmetric DIAMOND from the trailing camera --
		# pointing nowhere. It passed every headless assertion, because the
		# outline genuinely is longer than it is wide; what defeated it was
		# foreshortening, which turns a shallow taper into no taper at all at
		# the angle the marker is actually seen from. Only a rendered frame
		# showed it. The nose is now long and narrow enough to survive that
		# compression, and the tail is notched so the two ends can never read
		# alike.
		"outline": [
			Vector2(0.0, -1.35),
			Vector2(0.20, -0.70),
			Vector2(0.44, 0.35),
			Vector2(0.36, 0.85),
			Vector2(0.0, 0.55),
			Vector2(-0.36, 0.85),
			Vector2(-0.44, 0.35),
			Vector2(-0.20, -0.70),
		],
	},
	{
		"id": "spear",
		"label": "SPEAR",
		# A long narrow head on a slim shaft. The most extreme aspect ratio in
		# the table, which is the point: where KITE points by proportion and
		# ARROW by a barb, this points by being unmistakably longer than wide
		# even after the trailing camera compresses its length axis -- the
		# failure that defeated the lightcycle's first outline.
		"outline": [
			Vector2(0.0, -1.40),
			Vector2(0.34, -0.42),
			Vector2(0.13, -0.30),
			Vector2(0.16, 0.90),
			Vector2(-0.16, 0.90),
			Vector2(-0.13, -0.30),
			Vector2(-0.34, -0.42),
		],
	},
	{
		"id": "wedge",
		"label": "WEDGE",
		# A broad flat-backed triangle with the rear corners drawn out past the
		# base. Reads as pointing from its bulk rather than from a fine nose,
		# so it holds up where SPEAR is thinnest -- the two are deliberately
		# opposite answers to the same requirement.
		"outline": [
			Vector2(0.0, -1.15),
			Vector2(0.86, 0.55),
			Vector2(0.52, 0.92),
			Vector2(-0.52, 0.92),
			Vector2(-0.86, 0.55),
		],
	},

	# --- Shapes that are not blades ---------------------------------------
	#
	# Every entry above answers "which way" the same way: a tip at the front
	# and a taper behind it. That is one idea drawn eight times, and once the
	# table is a picker rather than a default it becomes a row of near-identical
	# triangles -- a menu where every option is a variation on the one already
	# selected.
	#
	# The requirement is that a shape POINTS, not that it is an arrow. These
	# six answer the same question by other means: by where the bulk sits, by
	# a stem against a head, by an asymmetric outline that has a clear front
	# without ever coming to a point. The acceptance test is unchanged and they
	# are held to it -- longer along the facing axis than across it, reaching
	# forward, and distinguishable front from back after the trailing camera
	# has compressed the length axis.
	{
		"id": "teardrop",
		"label": "TEARDROP",
		# Points by MASS, not by a tip: a slim nose swelling to a broad rear.
		# The widest line sits BEHIND centre, where every blade above puts it
		# ahead of the tail, and the rear is a single smooth curve -- so it is
		# the roundest entry in the table without being a blob.
		#
		# THE FIRST VERSION WAS AN EGG. Drawn convex the whole way round, with
		# the nose merely narrower than the tail, it rendered from the trailing
		# camera as a featureless oval pointing NOWHERE -- the lightcycle's
		# original failure exactly, and it passed every headless assertion for
		# the same reason: the outline genuinely is longer than it is wide, and
		# what defeated it was foreshortening compressing the length axis until
		# a gentle curve at one end was indistinguishable from a gentle curve at
		# the other.
		#
		# So the nose is a STEP rather than a slope. The shape pinches in hard
		# at -0.55 and runs nearly parallel ahead of that, which puts a corner
		# in the silhouette where there was only curvature -- a corner survives
		# compression, which is the same argument KEYHOLE's waist rests on. The
		# rear stays a smooth curve, so the two ends can never read alike.
		"outline": [
			Vector2(0.0, -1.34),
			Vector2(0.17, -1.16),
			Vector2(0.19, -0.62),
			Vector2(0.46, -0.44),
			Vector2(0.58, 0.20),
			Vector2(0.44, 0.74),
			Vector2(0.0, 0.96),
			Vector2(-0.44, 0.74),
			Vector2(-0.58, 0.20),
			Vector2(-0.46, -0.44),
			Vector2(-0.19, -0.62),
			Vector2(-0.17, -1.16),
		],
	},
	{
		"id": "keyhole",
		"label": "KEYHOLE",
		# A wide head on a narrow stem: two masses joined at a waist. It points
		# because the head is at the front and the stem trails, which is a
		# read that survives foreshortening better than a taper does -- the
		# waist is a hard step in the silhouette rather than a gradual change,
		# and a step cannot be compressed away the way the lightcycle's first
		# nose was.
		"outline": [
			Vector2(0.0, -1.28),
			Vector2(0.46, -0.92),
			Vector2(0.52, -0.30),
			Vector2(0.22, 0.02),
			Vector2(0.30, 0.92),
			Vector2(-0.30, 0.92),
			Vector2(-0.22, 0.02),
			Vector2(-0.52, -0.30),
			Vector2(-0.46, -0.92),
		],
	},
	{
		"id": "hammer",
		"label": "HAMMER",
		# A flat bar across the FRONT with a shaft behind it -- a T. The only
		# entry with no forward point at all: its leading edge is square, and
		# it points purely by which end carries the crossbar.
		#
		# That makes it the strongest test of the "must point" rule in the
		# table, and it passes for a reason worth keeping: the crossbar is the
		# widest thing on the shape and sits at the extreme front, so the
		# trailing camera sees a broad line with a tail running away from it.
		# A blade seen at that angle is a sliver; this is not.
		"outline": [
			Vector2(0.55, -1.10),
			Vector2(0.55, -0.62),
			Vector2(0.20, -0.62),
			Vector2(0.20, 0.95),
			Vector2(-0.20, 0.95),
			Vector2(-0.20, -0.62),
			Vector2(-0.55, -0.62),
			Vector2(-0.55, -1.10),
		],
	},
	{
		"id": "shuttle",
		"label": "SHUTTLE",
		# A slim body with swept fins at the BACK. The bulk is rearward and the
		# nose is the narrowest part, so the read is the opposite of the
		# teardrop's -- and the fins give the tail a distinctive outline of its
		# own, which is what keeps the two ends from ever being confused.
		#
		# It is the widest entry in the table at the fins, and it is legal
		# because that width is at one end rather than at the waist: the length
		# rule is measured against half-width, and a shape wide only at its
		# tail still reads as long.
		"outline": [
			Vector2(0.0, -1.32),
			Vector2(0.24, -0.80),
			Vector2(0.28, 0.28),
			Vector2(0.70, 0.62),
			Vector2(0.70, 0.90),
			Vector2(0.24, 0.78),
			Vector2(0.0, 0.92),
			Vector2(-0.24, 0.78),
			Vector2(-0.70, 0.90),
			Vector2(-0.70, 0.62),
			Vector2(-0.28, 0.28),
			Vector2(-0.24, -0.80),
		],
	},
	{
		"id": "trident",
		"label": "TRIDENT",
		# Three prongs forward on a single stem: a centre spike flanked by two
		# shorter ones, with the gaps between them open to the floor. It points
		# by having three fronts and one back.
		#
		# The most open silhouette here after the chevron, and for the same
		# reason that one is worth having -- the floor grid is the timing
		# contract, so a mark that lets more of it through is a real option
		# rather than only a different look.
		"outline": [
			Vector2(0.0, -1.30),
			Vector2(0.22, -0.42),
			Vector2(0.56, -0.72),
			Vector2(0.60, 0.10),
			Vector2(0.24, 0.35),
			Vector2(0.20, 0.95),
			Vector2(-0.20, 0.95),
			Vector2(-0.24, 0.35),
			Vector2(-0.60, 0.10),
			Vector2(-0.56, -0.72),
			Vector2(-0.22, -0.42),
		],
	},
	{
		"id": "beacon",
		"label": "BEACON",
		# A stepped tower: narrow at the front and widening in two hard stages
		# toward the back. It points by a staircase rather than by a slope,
		# which is the same argument the keyhole's waist rests on -- a step
		# survives compression where a taper does not -- drawn as a repeating
		# feature rather than as a single joint.
		#
		# The narrowest entry in the table by half-width, so it is the one that
		# hides least of the floor beneath it.
		"outline": [
			Vector2(0.0, -1.30),
			Vector2(0.38, -0.62),
			Vector2(0.24, -0.48),
			Vector2(0.50, 0.30),
			Vector2(0.26, 0.30),
			Vector2(0.34, 0.95),
			Vector2(-0.34, 0.95),
			Vector2(-0.26, 0.30),
			Vector2(-0.50, 0.30),
			Vector2(-0.24, -0.48),
			Vector2(-0.38, -0.62),
		],
	},

	# --- Shapes that are OBJECTS ------------------------------------------
	#
	# The six above answer "which way" by abstract means -- mass, a waist, a
	# crossbar. These ten are recognisable THINGS, which is a different kind of
	# choice: a player picks the key because it is a key, not because its
	# silhouette resolves well, and the picker is better for holding both sorts.
	#
	# Every one still earns its place the same way. A thing whose front and back
	# are equally featureless is not a marker however charming it is, so each
	# entry here points by a DISCONTINUITY -- a tooth, a crossbar, a split, a
	# step -- rather than by a taper. That is the rule the teardrop's first
	# outline was written against: at the trailing camera's angle a gradient is
	# compressed away and a corner is not.
	{
		"id": "key",
		"label": "KEY",
		# The bow at the BACK and the bit teeth at the front, which is the way a
		# key is held rather than the way it is drawn on a signpost.
		#
		# It points by its teeth: three square steps cut into the shaft, which
		# make the most irregular outline in the table and read as an object
		# rather than as a mark. That irregularity is also why it is safe --
		# there is no angle at which the toothed end and the ring end could be
		# confused.
		#
		# The bow is a ring drawn SOLID rather than as a loop. A true hole would
		# be a second closed contour, which the extruder builds as its own
		# outward loop and fills in -- the failure the removed EDGE decal
		# records. A solid bow reads as a bow at this size anyway.
		"outline": [
			Vector2(0.0, -1.34),
			Vector2(0.16, -1.30),
			Vector2(0.16, -1.02),
			Vector2(0.34, -1.02),
			Vector2(0.34, -0.78),
			Vector2(0.16, -0.78),
			Vector2(0.16, -0.50),
			Vector2(0.30, -0.50),
			Vector2(0.30, -0.28),
			Vector2(0.16, -0.28),
			Vector2(0.16, 0.30),
			Vector2(0.44, 0.44),
			Vector2(0.52, 0.76),
			Vector2(0.30, 0.98),
			Vector2(0.0, 1.04),
			Vector2(-0.30, 0.98),
			Vector2(-0.52, 0.76),
			Vector2(-0.44, 0.44),
			Vector2(-0.16, 0.30),
			Vector2(-0.16, -0.28),
			Vector2(-0.30, -0.28),
			Vector2(-0.30, -0.50),
			Vector2(-0.16, -0.50),
			Vector2(-0.16, -0.78),
			Vector2(-0.34, -0.78),
			Vector2(-0.34, -1.02),
			Vector2(-0.16, -1.02),
			Vector2(-0.16, -1.30),
		],
	},
	{
		"id": "anchor",
		"label": "ANCHOR",
		# A stock bar across the front and two flukes sweeping back. It points
		# by the same mechanism HAMMER does -- a broad crossbar at the extreme
		# front -- but the flukes give the tail an outline of its own, so the
		# two ends differ at both ends rather than only at one.
		"outline": [
			Vector2(0.0, -1.28),
			Vector2(0.18, -1.10),
			Vector2(0.14, -0.88),
			Vector2(0.52, -0.88),
			Vector2(0.52, -0.66),
			Vector2(0.14, -0.66),
			Vector2(0.14, 0.34),
			Vector2(0.46, 0.16),
			Vector2(0.60, 0.40),
			Vector2(0.20, 0.88),
			Vector2(0.0, 0.96),
			Vector2(-0.20, 0.88),
			Vector2(-0.60, 0.40),
			Vector2(-0.46, 0.16),
			Vector2(-0.14, 0.34),
			Vector2(-0.14, -0.66),
			Vector2(-0.52, -0.66),
			Vector2(-0.52, -0.88),
			Vector2(-0.14, -0.88),
			Vector2(-0.18, -1.10),
		],
	},
	{
		"id": "nib",
		"label": "NIB",
		# A pen nib: a split point ahead of a shouldered barrel. The narrowest
		# entry in the table, and the split is what keeps it from being SPEAR
		# drawn thinner -- the notch at the tail and the shoulder step are both
		# hard features rather than tapers.
		"outline": [
			Vector2(0.0, -1.36),
			Vector2(0.10, -1.06),
			Vector2(0.06, -0.94),
			Vector2(0.06, -0.60),
			Vector2(0.26, -0.42),
			Vector2(0.30, 0.42),
			Vector2(0.20, 0.94),
			Vector2(0.0, 0.80),
			Vector2(-0.20, 0.94),
			Vector2(-0.30, 0.42),
			Vector2(-0.26, -0.42),
			Vector2(-0.06, -0.60),
			Vector2(-0.06, -0.94),
			Vector2(-0.10, -1.06),
		],
	},
	{
		"id": "plough",
		"label": "PLOUGH",
		# A chisel nose on a waisted body with swept wings behind it. Two steps
		# in the same silhouette -- in at the waist, out again at the wings --
		# so the shape reads as three distinct sections at a glance.
		"outline": [
			Vector2(0.0, -1.24),
			Vector2(0.30, -0.96),
			Vector2(0.26, -0.42),
			Vector2(0.62, 0.28),
			Vector2(0.36, 0.34),
			Vector2(0.30, 0.94),
			Vector2(-0.30, 0.94),
			Vector2(-0.36, 0.34),
			Vector2(-0.62, 0.28),
			Vector2(-0.26, -0.42),
			Vector2(-0.30, -0.96),
		],
	},
	{
		"id": "hook",
		"label": "HOOK",
		# A barbed head on a slim shank. The barbs sweep BACKWARD off the point,
		# so the front is a spike with two flared shoulders behind it and the
		# tail is a plain squared end -- the two could not be confused.
		#
		# THE FIRST VERSION WAS TWO EQUAL BULGES and read as a featureless blob.
		# It pointed, on paper, by which bulge carried the barb; in a rendered
		# frame both bulges compressed to the same rounded mass and the barb was
		# not resolvable at all. That is the third shape to fail this way, and
		# the pattern is now unmistakable: a shape whose two ends are the same
		# SIZE cannot rely on one of them carrying a finer detail, because the
		# detail is what foreshortening removes first.
		#
		# It points by the barbs instead, which are a hard reversal in the
		# outline rather than a swelling.
		# The shank is 0.42 rather than the 0.20 first drawn, and the reason is
		# the DECALS rather than the read. NOTCH bites a wedge from each flank
		# at mid-body, sized as a fraction of the half-width THERE -- so a thin
		# shank leaves it nothing to take. Measured on the way up: 0.20 removed
		# 2.8% of the mark and 0.34 removed 3.8%, both under the 4% floor
		# RulesTest sets, which is the band separating a real decal from one
		# that silently draws nothing. At 0.42 it clears.
		#
		# Worth stating as a general rule, since it is the first shape to hit
		# it: A SHAPE HAS TO LEAVE THE GENERATED DECALS ROOM TO WORK. Every
		# decal is a function of the outline, so an outline with no flank is one
		# the pattern set cannot decorate -- that is part of the acceptance test
		# for a new entry, not a separate concern discovered afterwards.
		"outline": [
			Vector2(0.0, -1.30),
			Vector2(0.58, -0.42),
			Vector2(0.42, -0.52),
			Vector2(0.42, 0.82),
			Vector2(0.0, 0.98),
			Vector2(-0.42, 0.82),
			Vector2(-0.42, -0.52),
			Vector2(-0.58, -0.42),
		],
	},
	{
		"id": "comb",
		"label": "COMB",
		# Five prongs of unequal length forward off a plain bar. TRIDENT with
		# more teeth and no symmetry between them, which is what makes it a
		# separate entry rather than a re-tuning: the prongs read as a ragged
		# edge, where a trident reads as three deliberate points.
		"outline": [
			Vector2(0.0, -1.24),
			Vector2(0.12, -0.84),
			Vector2(0.30, -1.14),
			Vector2(0.40, -0.76),
			Vector2(0.56, -0.98),
			Vector2(0.60, -0.52),
			Vector2(0.26, -0.36),
			Vector2(0.24, 0.92),
			Vector2(-0.24, 0.92),
			Vector2(-0.26, -0.36),
			Vector2(-0.60, -0.52),
			Vector2(-0.56, -0.98),
			Vector2(-0.40, -0.76),
			Vector2(-0.30, -1.14),
			Vector2(-0.12, -0.84),
		],
	},
	{
		"id": "bolt",
		"label": "BOLT",
		# A lightning stroke: three zigzag steps narrowing toward the front,
		# with a notched tail. Every vertex is a corner, so nothing about it can
		# be compressed away -- the opposite extreme from the teardrop, and the
		# entry that most obviously belongs to a neon game.
		"outline": [
			Vector2(0.0, -1.36),
			Vector2(0.34, -0.62),
			Vector2(0.14, -0.56),
			Vector2(0.44, 0.10),
			Vector2(0.20, 0.18),
			Vector2(0.40, 0.96),
			Vector2(0.0, 0.56),
			Vector2(-0.40, 0.96),
			Vector2(-0.20, 0.18),
			Vector2(-0.44, 0.10),
			Vector2(-0.14, -0.56),
			Vector2(-0.34, -0.62),
		],
	},
	{
		"id": "shield",
		"label": "SHIELD",
		# Broad and flat across the FRONT, narrowing to a tail behind. The only
		# entry whose narrow end is at the back, which is legal because the rule
		# is that a shape must point -- not that it must point with a tip -- and
		# the flat leading edge is unmistakably a front.
		#
		# It is the widest silhouette here and the one that holds up best
		# against a busy wall, which is DELTA's job in the blade half of the
		# table, done the other way round.
		#
		# THE FIRST VERSION TAPERED SMOOTHLY TO A REAR POINT AND READ AS A
		# ROUNDED SLAB. Foreshortening compressed the rear taper to nothing, so
		# the shape had a broad end and a slightly-less-broad end and pointed
		# nowhere -- the teardrop's egg, arriving from the other direction. The
		# frame is the only thing that showed it; the outline passed every
		# assertion, since it genuinely is longer than it is wide.
		#
		# So the waist is a STEP: the flanks pull in hard at +0.30 and run
		# nearly parallel behind it, which puts two corners in the silhouette
		# where there was only curvature. Same remedy as the teardrop's nose,
		# and the same reason -- a corner survives compression, a slope does
		# not.
		"outline": [
			Vector2(0.0, -1.16),
			Vector2(0.46, -1.04),
			Vector2(0.58, -0.56),
			Vector2(0.54, 0.22),
			Vector2(0.24, 0.34),
			Vector2(0.22, 0.96),
			Vector2(0.0, 1.06),
			Vector2(-0.22, 0.96),
			Vector2(-0.24, 0.34),
			Vector2(-0.54, 0.22),
			Vector2(-0.58, -0.56),
			Vector2(-0.46, -1.04),
		],
	},
	{
		"id": "pin",
		"label": "PIN",
		# A thumbtack seen side on: a broad head at the front, a hard shoulder,
		# then a needle running back to a notched tail. The head-and-shoulder
		# step is KEYHOLE's waist inverted -- head forward rather than back --
		# and the two are deliberately opposite readings of the same device.
		"outline": [
			Vector2(0.0, -1.32),
			Vector2(0.44, -1.08),
			Vector2(0.50, -0.72),
			Vector2(0.22, -0.56),
			Vector2(0.18, 0.34),
			Vector2(0.34, 0.52),
			Vector2(0.30, 0.92),
			Vector2(0.0, 0.82),
			Vector2(-0.30, 0.92),
			Vector2(-0.34, 0.52),
			Vector2(-0.18, 0.34),
			Vector2(-0.22, -0.56),
			Vector2(-0.50, -0.72),
			Vector2(-0.44, -1.08),
		],
	},
	{
		"id": "bracket",
		"label": "BRACKET",
		# A staple: two square legs reaching forward off a rear spine, with the
		# span between them open to the floor. The most open silhouette in the
		# table -- more so than CHEVRON or TRIDENT -- so it hides the least of
		# the floor grid, which is the timing contract the player reads.
		#
		# Square rather than swept, deliberately: every other open shape here
		# opens with angled prongs, and a right-angled one is a different
		# object rather than a narrower version of the same one.
		"outline": [
			Vector2(0.0, -1.22),
			Vector2(0.20, -1.02),
			Vector2(0.56, -1.02),
			Vector2(0.56, -0.66),
			Vector2(0.26, -0.66),
			Vector2(0.26, 0.42),
			Vector2(0.52, 0.42),
			Vector2(0.52, 0.94),
			Vector2(-0.52, 0.94),
			Vector2(-0.52, 0.42),
			Vector2(-0.26, 0.42),
			Vector2(-0.26, -0.66),
			Vector2(-0.56, -0.66),
			Vector2(-0.56, -1.02),
			Vector2(-0.20, -1.02),
		],
	},

	# --- Shapes that are TOOLS, CRAFT and MARKS ----------------------------
	#
	# Twenty more, and the table is forty-four. The three groups before this one
	# each answered "which way" a different way -- blades by a tip, abstracts by
	# a waist or a crossbar, objects by being a recognisable thing -- and this
	# block widens the last of those rather than adding a fourth idea: a player
	# who wants an axe wants an axe, and the picker is a better screen for
	# holding forty-four opinions than eight.
	#
	# EVERY ENTRY HERE WAS CHECKED AGAINST THE WHOLE DECAL SET BEFORE IT WAS
	# WRITTEN, which is new. A decal is a function of the outline, so a shape is
	# not finished when it reads well -- it is finished when all twenty-eight
	# patterns still bite on it. RATCHET is the entry that proves the check
	# earns its keep: see its own note.
	{
		"id": "compass",
		"label": "COMPASS",
		# Two legs hinged at a head: the drawing compass. It points by the head
		# being a solid block and the legs splaying open behind it, so the front
		# is mass and the back is a gap -- which is the strongest version of the
		# discontinuity rule, since a gap cannot be compressed into anything.
		"outline": [
			Vector2(0.00, -1.30), Vector2(0.26, -1.06), Vector2(0.24, -0.62),
			Vector2(0.54, 0.92), Vector2(0.30, 1.00), Vector2(0.10, 0.10),
			Vector2(-0.10, 0.10), Vector2(-0.30, 1.00), Vector2(-0.54, 0.92),
			Vector2(-0.24, -0.62), Vector2(-0.26, -1.06),
		],
	},
	{
		"id": "axe",
		"label": "AXE",
		# A broad bit at the front, a haft behind. The bit's shoulders are a
		# hard step off the haft, and that step is the whole read -- the same
		# device HAMMER uses, with the mass at the front rather than spread
		# across a bar.
		"outline": [
			Vector2(0.00, -1.24), Vector2(0.30, -1.16), Vector2(0.62, -0.80),
			Vector2(0.58, -0.36), Vector2(0.22, -0.28), Vector2(0.20, 0.90),
			Vector2(0.00, 0.98), Vector2(-0.20, 0.90), Vector2(-0.22, -0.28),
			Vector2(-0.58, -0.36), Vector2(-0.62, -0.80), Vector2(-0.30, -1.16),
		],
	},
	{
		"id": "anvil",
		"label": "ANVIL",
		# A horn forward, a waisted body, a flat base behind. Three sections and
		# two steps, so the silhouette is legible even when foreshortening has
		# taken most of its length.
		"outline": [
			Vector2(0.00, -1.32), Vector2(0.20, -1.02), Vector2(0.56, -0.72),
			Vector2(0.52, -0.34), Vector2(0.24, -0.20), Vector2(0.28, 0.44),
			Vector2(0.60, 0.62), Vector2(0.58, 0.96), Vector2(-0.58, 0.96),
			Vector2(-0.60, 0.62), Vector2(-0.28, 0.44), Vector2(-0.24, -0.20),
			Vector2(-0.52, -0.34), Vector2(-0.56, -0.72), Vector2(-0.20, -1.02),
		],
	},
	{
		"id": "wrench",
		"label": "WRENCH",
		# An open jaw at the front, a plain shaft behind. The jaw is a notch in
		# the LEADING edge rather than a narrowing of it, which is why it
		# survives the angle: a gap between two prongs stays a gap however hard
		# the length axis is squashed, where a taper into a point does not.
		"outline": [
			Vector2(0.00, -0.86), Vector2(0.22, -1.30), Vector2(0.52, -1.22),
			Vector2(0.48, -0.66), Vector2(0.24, -0.44), Vector2(0.22, 0.88),
			Vector2(0.00, 0.98), Vector2(-0.22, 0.88), Vector2(-0.24, -0.44),
			Vector2(-0.48, -0.66), Vector2(-0.52, -1.22), Vector2(-0.22, -1.30),
		],
	},
	{
		"id": "torch",
		"label": "TORCH",
		# A flame head stepped off a plain handle, with a collar between them.
		# The collar is the tell: two steps close together read as a deliberate
		# join, where one step alone could be a taper caught mid-way.
		"outline": [
			Vector2(0.00, -1.34), Vector2(0.34, -0.94), Vector2(0.30, -0.62),
			Vector2(0.44, -0.54), Vector2(0.42, -0.34), Vector2(0.22, -0.26),
			Vector2(0.20, 0.80), Vector2(0.30, 0.96), Vector2(-0.30, 0.96),
			Vector2(-0.20, 0.80), Vector2(-0.22, -0.26), Vector2(-0.42, -0.34),
			Vector2(-0.44, -0.54), Vector2(-0.30, -0.62), Vector2(-0.34, -0.94),
		],
	},
	{
		"id": "rudder",
		"label": "RUDDER",
		# A raked blade with a stepped trailing edge -- a fin cut square at the
		# back rather than tapered, so the two ends differ in KIND and not
		# merely in width.
		"outline": [
			Vector2(0.00, -1.30), Vector2(0.42, -0.60), Vector2(0.38, 0.26),
			Vector2(0.56, 0.34), Vector2(0.54, 0.94), Vector2(-0.54, 0.94),
			Vector2(-0.56, 0.34), Vector2(-0.38, 0.26), Vector2(-0.42, -0.60),
		],
	},
	{
		"id": "sail",
		"label": "SAIL",
		# A leading edge that steps out twice -- a gaff sail's head and clew.
		# Two steps on one flank pair and one plain edge behind them, which
		# reads as rigging rather than as a blade.
		"outline": [
			Vector2(0.00, -1.28), Vector2(0.24, -1.04), Vector2(0.58, -0.44),
			Vector2(0.34, -0.30), Vector2(0.50, 0.44), Vector2(0.26, 0.56),
			Vector2(0.24, 0.96), Vector2(-0.24, 0.96), Vector2(-0.26, 0.56),
			Vector2(-0.50, 0.44), Vector2(-0.34, -0.30), Vector2(-0.58, -0.44),
			Vector2(-0.24, -1.04),
		],
	},
	{
		"id": "glider",
		"label": "GLIDER",
		# Swept wings well FORWARD on a slim fuselage, with tail fins behind.
		# The wings sit ahead of centre deliberately: SHUTTLE puts its fins at
		# the back and points by them, and this is the same argument run the
		# other way, so the two are opposite readings rather than near-copies.
		"outline": [
			Vector2(0.00, -1.34), Vector2(0.18, -0.98), Vector2(0.66, -0.52),
			Vector2(0.62, -0.22), Vector2(0.18, -0.34), Vector2(0.16, 0.52),
			Vector2(0.46, 0.78), Vector2(0.42, 0.96), Vector2(-0.42, 0.96),
			Vector2(-0.46, 0.78), Vector2(-0.16, 0.52), Vector2(-0.18, -0.34),
			Vector2(-0.62, -0.22), Vector2(-0.66, -0.52), Vector2(-0.18, -0.98),
		],
	},
	{
		"id": "prow",
		"label": "PROW",
		# A ship's bow: a sharp cutwater, a hard step out to the beam, and a
		# square transom behind. The step is what keeps the cutwater from
		# reading as a plain taper.
		"outline": [
			Vector2(0.00, -1.34), Vector2(0.24, -0.72), Vector2(0.56, -0.30),
			Vector2(0.54, 0.52), Vector2(0.44, 0.94), Vector2(-0.44, 0.94),
			Vector2(-0.54, 0.52), Vector2(-0.56, -0.30), Vector2(-0.24, -0.72),
		],
	},
	{
		"id": "fin",
		"label": "FIN",
		# A dorsal fin: a raked leading edge and a notched trailing one. The
		# notch is small and is not what carries the read -- the rake is, since
		# the widest line sits far back and the shape leans forward off it.
		"outline": [
			Vector2(0.00, -1.32), Vector2(0.46, 0.06), Vector2(0.44, 0.44),
			Vector2(0.24, 0.36), Vector2(0.26, 0.94), Vector2(-0.26, 0.94),
			Vector2(-0.24, 0.36), Vector2(-0.44, 0.44), Vector2(-0.46, 0.06),
		],
	},
	{
		"id": "spade",
		"label": "SPADE",
		# A blade with SQUARE shoulders, a stepped shaft, and a notched tail.
		#
		# SHIELD is the other broad-fronted entry and its shoulders are swept;
		# squaring them is what makes this a separate shape rather than a
		# re-tuning, because at this angle a right angle and a curve are two of
		# the very few things that still read differently once length has
		# compressed away.
		#
		# The shoulders and the tail notch are both harder than the first
		# outline, which read as a plain taper for RIVET's reason.
		"outline": [
			Vector2(0.00, -1.24), Vector2(0.54, -1.14), Vector2(0.54, -0.52),
			Vector2(0.20, -0.38), Vector2(0.18, 0.46), Vector2(0.38, 0.58),
			Vector2(0.36, 1.00), Vector2(0.00, 0.86), Vector2(-0.36, 1.00),
			Vector2(-0.38, 0.58), Vector2(-0.18, 0.46), Vector2(-0.20, -0.38),
			Vector2(-0.54, -0.52), Vector2(-0.54, -1.14),
		],
	},
	{
		"id": "crown",
		"label": "CROWN",
		# Three points forward off a solid band. TRIDENT's prongs are separate
		# and read as three things; these sit on a continuous rim and read as
		# one -- the difference is the band, not the points.
		"outline": [
			Vector2(0.00, -1.26), Vector2(0.16, -0.80), Vector2(0.34, -1.16),
			Vector2(0.46, -0.76), Vector2(0.62, -1.04), Vector2(0.58, -0.40),
			Vector2(0.30, -0.26), Vector2(0.28, 0.90), Vector2(-0.28, 0.90),
			Vector2(-0.30, -0.26), Vector2(-0.58, -0.40), Vector2(-0.62, -1.04),
			Vector2(-0.46, -0.76), Vector2(-0.34, -1.16), Vector2(-0.16, -0.80),
		],
	},
	{
		"id": "lantern",
		"label": "LANTERN",
		# A capped body: a NARROW flat cap forward, a long parallel glass, and a
		# WIDE flat foot behind.
		#
		# THE FIRST OUTLINE READ AS A STACK OF BANDS POINTING NOWHERE, and the
		# comment written beside it claimed the opposite -- that a narrow cap
		# and a round foot were "different objects rather than different sizes
		# of one", so the shape was safe. That was reasoned from the
		# construction and not from a frame, which is the one move this file
		# keeps recording as a mistake: the two ends measured close enough in
		# width that foreshortening made them the same, and the waist between
		# them was too shallow to survive at all.
		#
		# The fix is the fix every time: make the difference a STEP. The foot is
		# now nearly three times the cap's width and sits hard at the tail, so
		# what the eye gets is a wide bar at one end and a thin one at the
		# other rather than a gradient between two similar blocks.
		"outline": [
			Vector2(0.00, -1.30), Vector2(0.20, -1.22), Vector2(0.20, -0.96),
			Vector2(0.44, -0.86), Vector2(0.40, 0.34), Vector2(0.22, 0.46),
			Vector2(0.24, 0.70), Vector2(0.60, 0.80), Vector2(0.58, 1.00),
			Vector2(-0.58, 1.00), Vector2(-0.60, 0.80), Vector2(-0.24, 0.70),
			Vector2(-0.22, 0.46), Vector2(-0.40, 0.34), Vector2(-0.44, -0.86),
			Vector2(-0.20, -0.96), Vector2(-0.20, -1.22),
		],
	},
	{
		"id": "obelisk",
		"label": "OBELISK",
		# A pyramidion on a stepped shaft with a plinth. Two hard steps and no
		# curve anywhere -- the most purely architectural entry in the table, and
		# the one that best demonstrates the rule, since it points using nothing
		# BUT discontinuities.
		"outline": [
			Vector2(0.00, -1.32), Vector2(0.26, -0.94), Vector2(0.22, -0.60),
			Vector2(0.34, -0.52), Vector2(0.30, 0.48), Vector2(0.50, 0.60),
			Vector2(0.48, 0.96), Vector2(-0.48, 0.96), Vector2(-0.50, 0.60),
			Vector2(-0.30, 0.48), Vector2(-0.34, -0.52), Vector2(-0.22, -0.60),
			Vector2(-0.26, -0.94),
		],
	},
	{
		"id": "chalice",
		"label": "CHALICE",
		# A wide square bowl forward, a thin stem, a flat foot behind.
		#
		# IT FAILED THE SAME WAY LANTERN DID and for the same written reason --
		# "different shapes rather than different sizes" was a claim about the
		# drawing, not about the frame, and in the frame it was a squat blob.
		# Two shapes failing identically off one piece of reasoning is what
		# makes it worth recording twice.
		#
		# The bowl is now much the WIDER end and its rim is square, so the shape
		# reads front-heavy at a glance instead of relying on the stem to
		# separate two similar masses.
		"outline": [
			Vector2(0.00, -1.18), Vector2(0.58, -1.10), Vector2(0.58, -0.74),
			Vector2(0.44, -0.62), Vector2(0.16, -0.46), Vector2(0.14, 0.44),
			Vector2(0.40, 0.56), Vector2(0.38, 0.98), Vector2(-0.38, 0.98),
			Vector2(-0.40, 0.56), Vector2(-0.14, 0.44), Vector2(-0.16, -0.46),
			Vector2(-0.44, -0.62), Vector2(-0.58, -0.74), Vector2(-0.58, -1.10),
		],
	},
	{
		"id": "caret",
		"label": "CARET",
		# A stepped chevron: two arms meeting at a point, each with a notch cut
		# in its outer edge. CHEVRON is the plain V, so the notches are what
		# keep this from being the same silhouette at a smaller scale.
		"outline": [
			Vector2(0.00, -1.30), Vector2(0.40, -0.62), Vector2(0.66, 0.10),
			Vector2(0.44, 0.20), Vector2(0.52, 0.86), Vector2(0.24, 0.92),
			Vector2(0.00, 0.06), Vector2(-0.24, 0.92), Vector2(-0.52, 0.86),
			Vector2(-0.44, 0.20), Vector2(-0.66, 0.10), Vector2(-0.40, -0.62),
		],
	},
	{
		"id": "rivet",
		"label": "RIVET",
		# A broad head, a hard collar, and a square shank.
		#
		# The first outline read as a plain taper: the head was only a little
		# wider than the shank and the collar step was small enough that
		# compression closed it. Both are exaggerated here -- the head is more
		# than twice the shank and the collar is a real right angle -- because
		# a step only counts if it survives, and "there is a step in the
		# outline" is not the same claim as "the step is visible".
		"outline": [
			Vector2(0.00, -1.26), Vector2(0.50, -1.14), Vector2(0.52, -0.84),
			Vector2(0.22, -0.70), Vector2(0.22, 0.56), Vector2(0.42, 0.68),
			Vector2(0.40, 0.98), Vector2(-0.40, 0.98), Vector2(-0.42, 0.68),
			Vector2(-0.22, 0.56), Vector2(-0.22, -0.70), Vector2(-0.52, -0.84),
			Vector2(-0.50, -1.14),
		],
	},
	{
		"id": "ratchet",
		"label": "RATCHET",
		# Saw teeth down ONE flank, against a straight plain flank. The only
		# asymmetric entry in the table, which buys a read nothing else offers:
		# it says which way you point AND which way is left.
		#
		# IT ALSO FOUND A LIMIT IN THE DECAL GENERATOR, and the first outline had
		# to be redrawn for it rather than the generator changed. NOTCH sizes
		# both its wedges from _half_width_at, which takes the WIDEST crossing --
		# so on an asymmetric shape it measured the toothed flank at 0.506 and
		# cut the plain flank, only 0.30 wide there, mostly through empty space.
		# Measured: 2.9% of the mark removed against the 4% floor.
		#
		# The plain flank is now a straight 0.52 edge, so both sides have body to
		# give and the cut lands at 5.5%. Recorded because the general rule is
		# worth having: EVERY FLANK DECAL ASSUMES LATERAL SYMMETRY, and an
		# asymmetric shape has to be wide on both sides even where only one of
		# them carries the detail.
		"outline": [
			Vector2(0.00, -1.30), Vector2(0.32, -1.02), Vector2(0.32, -0.72),
			Vector2(0.56, -0.56), Vector2(0.32, -0.36), Vector2(0.56, -0.28),
			Vector2(0.32, -0.08), Vector2(0.56, 0.00), Vector2(0.32, 0.20),
			Vector2(0.56, 0.28), Vector2(0.32, 0.48), Vector2(0.32, 0.92),
			Vector2(0.00, 1.00), Vector2(-0.52, 0.92), Vector2(-0.52, -0.72),
			Vector2(-0.32, -1.02),
		],
	},
	{
		"id": "tally",
		"label": "TALLY",
		# A bar with three square teeth off the TRAILING edge -- COMB reversed,
		# so the ragged end is the back and the clean bar is the front. The pair
		# is deliberate: it shows that where a feature sits matters more than
		# what the feature is.
		"outline": [
			Vector2(0.00, -1.24), Vector2(0.36, -1.06), Vector2(0.34, 0.28),
			Vector2(0.58, 0.34), Vector2(0.56, 0.62), Vector2(0.34, 0.58),
			Vector2(0.34, 0.96), Vector2(-0.34, 0.96), Vector2(-0.34, 0.58),
			Vector2(-0.56, 0.62), Vector2(-0.58, 0.34), Vector2(-0.34, 0.28),
			Vector2(-0.36, -1.06),
		],
	},
	{
		"id": "sigil",
		"label": "SIGIL",
		# A diamond head on a barred stem -- a rune rather than a tool. The
		# crossbar sits BEHIND the head, the opposite arrangement to ANCHOR,
		# where the bar is the leading edge and the flukes trail.
		"outline": [
			Vector2(0.00, -1.34), Vector2(0.40, -0.86), Vector2(0.22, -0.52),
			Vector2(0.56, -0.44), Vector2(0.54, -0.18), Vector2(0.22, -0.26),
			Vector2(0.20, 0.88), Vector2(0.00, 0.98), Vector2(-0.20, 0.88),
			Vector2(-0.22, -0.26), Vector2(-0.54, -0.18), Vector2(-0.56, -0.44),
			Vector2(-0.22, -0.52), Vector2(-0.40, -0.86),
		],
	},
]


# The table entry for an id, falling back to the default rather than failing.
#
# A stored name that no longer exists is the ordinary consequence of a shape
# being renamed or dropped between builds -- it must land the player on the
# arrow, not crash their game or leave them with no marker at all.
static func marker_shape(id: String) -> Dictionary:
	for shape in MARKER_SHAPES:
		if shape["id"] == id:
			return shape
	for shape in MARKER_SHAPES:
		if shape["id"] == MARKER_SHAPE_DEFAULT:
			return shape
	return MARKER_SHAPES[0]


# The palette a maze uses, by id, falling back to the maze's own default rather
# than failing -- the promise every other table here makes.
static func palette_by_id(id: String) -> Dictionary:
	for entry in PALETTES:
		if entry.get("id", "") == id:
			return entry
	return PALETTES[0]


# The DEFAULT palette for a maze slot: the one that maze was authored with.
#
# By INDEX here rather than by id, because this is the identity relationship --
# palette N is maze N's own colourway, and section 8 tuned the two together
# (braid factor rising as the hues get colder). A player override sits on top of
# this, never in place of it.
static func default_palette_id(maze_index: int) -> String:
	var i := clampi(maze_index, 0, PALETTES.size() - 1)
	return String(PALETTES[i].get("id", ""))


# --- Marker colours ----------------------------------------------------------
#
# PRESETS, not a wheel. Each one is earned by an achievement (Unlocks), so the
# set has to be enumerable and stable -- a free RGB picker cannot be unlocked.
#
# Stored by NAME like the shapes and decals, so reordering the table cannot
# re-point a saved choice or an earned unlock at something else.
#
# The maze palettes are deliberately NOT avoided. Section 12 objected to a
# colour picker because a marker matching the walls is hard to see, and that
# objection is real -- lime IS maze 3's wall colour. The choice was asked for
# anyway, and hiding the colours that make it visible would be pretending to
# offer a choice while removing its consequences. The picker previews the state
# colours instead, so the cost is visible before it is paid.
const MARKER_COLOUR_DEFAULT := "white"

# Colour 2 defaults to WHITE, the same as the mark, so a fresh profile starts
# with exactly ONE colour unlocked rather than two.
#
# It was cobalt, on the reasoning that the two defaults must differ or a white
# pattern on a white mark reads as a broken decal. That reasoning assumed a
# player could SEE a pattern on a fresh profile, and they cannot: the default
# decal is PLAIN, which has no cuts to fill, so colour 2 is not drawn at all
# until a decal is earned. By then the picker has shown them the second row.
#
# And white-on-white is not invisible anyway, because the inlay is a recessed
# surface rather than a flat fill: it is drawn at INLAY_ENERGY against the
# mark's 3.0, dropped by INLAY_DROP and inset by INLAY_INSET, so a dark seam
# runs around every piece and the pattern reads as dimmer white inside brighter
# white. That seam is what section 12 says guarantees the read AT ANY PAIR --
# an identical pair is simply the hardest case of the rule, not an exception to
# it. Verified in a rendered frame rather than argued.
const MARKER_COLOUR_2_DEFAULT := "white"

# How far colour 2 is darkened from the mark when the two still match and a
# decal goes on. Settings separates them at that moment, because white-on-white
# draws no visible pattern at all -- measured against a cobalt control in a
# rendered frame, not argued.
#
# A DERIVED SHADE rather than a table colour, and that is the whole point: every
# entry in MARKER_COLOURS except the default is EARNED, so seeding colour 2 from
# the table would hand out a locked cosmetic through a back door the picker's
# own swatch rows carefully guard. Darkening the player's own mark grants
# nothing -- it is the colour they already have, dimmed.
#
# 0.55 rather than a subtle nudge: the inlay is already drawn dimmer than the
# mark, and the measured failure above is precisely that a small difference
# vanishes at the trailing camera's angle.
const MARKER_COLOUR_2_DARKEN := 0.55

const MARKER_COLOURS := [
	{"id": "white", "label": "WHITE", "colour": Color(1.0, 1.0, 1.0)},
	{"id": "ice", "label": "ICE", "colour": Color(0.30, 0.85, 1.0)},
	{"id": "cobalt", "label": "COBALT", "colour": Color(0.25, 0.55, 1.0)},
	{"id": "violet", "label": "VIOLET", "colour": Color(0.65, 0.45, 1.0)},
	{"id": "magenta", "label": "MAGENTA", "colour": Color(1.0, 0.40, 0.85)},
	{"id": "coral", "label": "CORAL", "colour": Color(1.0, 0.45, 0.35)},
	{"id": "gold", "label": "GOLD", "colour": Color(1.0, 0.80, 0.30)},
	{"id": "lime", "label": "LIME", "colour": Color(0.55, 0.95, 0.45)},
	{"id": "jade", "label": "JADE", "colour": Color(0.20, 0.85, 0.65)},
	{"id": "steel", "label": "STEEL", "colour": Color(0.75, 0.78, 0.85)},
	{"id": "rust", "label": "RUST", "colour": Color(0.85, 0.42, 0.20)},
	{"id": "amber", "label": "AMBER", "colour": Color(1.0, 0.68, 0.18)},
	{"id": "rose", "label": "ROSE", "colour": Color(1.0, 0.55, 0.70)},
	{"id": "mint", "label": "MINT", "colour": Color(0.60, 1.0, 0.80)},
	{"id": "sky", "label": "SKY", "colour": Color(0.55, 0.80, 1.0)},
	{"id": "plum", "label": "PLUM", "colour": Color(0.55, 0.30, 0.70)},
	{"id": "sand", "label": "SAND", "colour": Color(0.90, 0.82, 0.62)},
	{"id": "teal", "label": "TEAL", "colour": Color(0.20, 0.70, 0.72)},
	{"id": "crimson", "label": "CRIMSON", "colour": Color(0.80, 0.15, 0.25)},
]


# The table entry for a colour id, falling back to the default rather than
# failing -- the same promise marker_shape() and marker_decal() make.
static func marker_colour(id: String) -> Dictionary:
	for entry in MARKER_COLOURS:
		if entry["id"] == id:
			return entry
	for entry in MARKER_COLOURS:
		if entry["id"] == MARKER_COLOUR_DEFAULT:
			return entry
	return MARKER_COLOURS[0]


# --- Marker decals -----------------------------------------------------------
#
# A pattern laid over whatever inner mark the player has chosen.
#
# A decal is a FUNCTION OF AN OUTLINE, never authored artwork. Drawing one per
# shape-and-decal pairing is a shapes x decals grid -- six by five today, and a
# seventh shape means five more drawings or five silent blanks. That is the
# parallel-array failure section 6 records for landmark density and 9c for music
# tracks, and the stale cell is always the one nobody looks at.
#
# Generating from the outline means a shape added later is decorated correctly
# by construction. RulesTest asserts the whole cross product rather than
# trusting it.
#
# The two shapes that make this real are already in MARKER_SHAPES and are not
# special-cased anywhere: the chevron is CONCAVE, and the delta has only three
# vertices. Every decal below is built by CLIPPING or INSETTING the polygon it
# was handed, which is what lets one rule cover both.
const MARKER_DECAL_DEFAULT := "none"

const MARKER_DECALS := [
	{
		"id": "none",
		"label": "PLAIN",
		# The shape as drawn, and the default. A marker with no pattern is the
		# most legible one -- a decal is a choice, not an improvement on it.
	},
	{
		"id": "stripe",
		"label": "STRIPE",
		# Two bands across the facing axis. Racing stripes, and the clearest
		# read of the four at the trailing camera's shallow angle.
	},
	{
		"id": "notch",
		"label": "NOTCH",
		# A wedge cut from each flank, so the mark reads as having shoulders.
		#
		# This replaced an "EDGE" decal that subtracted an INSET COPY of the
		# outline. That is the prettiest idea in the set and it cannot be built
		# here: subtracting an inset leaves a RING, which is an outline plus a
		# hole, and the mark is extruded as a single closed loop per piece. A
		# ring came back as an outer loop identical to the plain shape (so the
		# decal did nothing) plus a clockwise hole the extruder would have
		# filled in solid. Recorded so nobody re-adds it without first giving
		# the extrusion real hole support.
	},
	{
		"id": "tip",
		"label": "TIP",
		# The forward third. The only decal that REINFORCES facing, which is
		# the one thing every shape in the table must say (section 12, "Every
		# shape has to point").
	},
	{
		"id": "chevrons",
		"label": "CHEVRONS",
		# Three shallow Vs pointing the way the mark points. STRIPE's bands are
		# flat and say nothing about direction; these repeat the shape's own
		# facing, so the pattern reinforces the one property every marker must
		# keep.
	},
	{
		"id": "bars",
		"label": "BARS",
		# Two lengthways slots either side of centre -- the lateral counterpart
		# to SPLIT, which cuts one slot down the middle.
	},
	{
		"id": "tail",
		"label": "TAIL",
		# A band just ahead of the trailing edge, mirroring TIP at the nose.
		# The two are deliberately a pair: on a shape where the nose reads
		# strongly the tail is the quieter choice, and vice versa.
	},
	{
		"id": "split",
		"label": "SPLIT",
		# One half along the facing axis. The boldest of the set, and the one
		# that most changes the silhouette's read at distance.
	},

	# --- Twenty more, and the set is twenty-eight -------------------------
	#
	# The eight above are one of each idea. These fill the space BETWEEN them:
	# three bands where STRIPE has two, a row of bites where NOTCH has one, a
	# chevron pointing the other way, a slot off the centre line. A pattern set
	# is a set of near-neighbours or it is eight unrelated marks, and the picker
	# is a better screen for the former.
	#
	# EVERY ONE IS CHECKED ON ALL FORTY-FOUR SHAPES, which is 1,232 pairings
	# RulesTest walks in full. That is not ceremony: five of these twenty failed
	# on their first tuning and one had to be abandoned outright, and none of it
	# was visible in the drawing.
	{
		"id": "triband",
		"label": "TRIBAND",
		# Three even bands across the facing axis -- STRIPE's two, with a
		# marching rhythm rather than a pair.
	},
	{
		"id": "pinstripe",
		"label": "PINSTRIPE",
		# Four fine bands. The finest rhythm in the set that still survives
		# INLAY_INSET on the narrowest shape, which is what sets the thickness
		# rather than taste.
	},
	{
		"id": "wedges",
		"label": "WEDGES",
		# Two bands that TAPER across the mark, thick on one flank and thin on
		# the other. STRIPE's bands are parallel and say nothing about which way
		# is which; these lean.
	},
	{
		"id": "ladder",
		"label": "LADDER",
		# A lengthways spine with rungs off it -- the only entry that cuts on
		# both axes at once, so it reads as a structure rather than a pattern.
	},
	{
		"id": "scallop",
		"label": "SCALLOP",
		# Three bites down each flank. NOTCH takes one deep wedge; a row of them
		# reads as fluted rather than shouldered.
	},
	{
		"id": "shoulders",
		"label": "SHOULDERS",
		# A SQUARE step cut from each flank where NOTCH cuts a wedge. Same
		# placement, right-angled tool, and it reads as machined.
	},
	{
		"id": "serrate",
		"label": "SERRATE",
		# Saw teeth down both flanks, the two sides out of phase so the mark
		# cannot read as symmetrical at a glance.
	},
	{
		"id": "waist",
		"label": "WAIST",
		# One long bite from each flank at mid-body, pinching the mark in the
		# middle -- the device KEYHOLE uses as a SHAPE, offered as a pattern.
	},
	{
		"id": "quarters",
		"label": "QUARTERS",
		# Three lengthways slots: SPLIT's centre line and BARS' pair together, so
		# the mark reads as four ribbons.
	},
	{
		"id": "rails",
		"label": "RAILS",
		# Two slots out on the flanks, leaving a broad centre. BARS pushed
		# outward, so what survives is a wide spine with thin edges.
	},
	{
		"id": "offset",
		"label": "OFFSET",
		# One slot beside the centre line. The only ASYMMETRIC decal, so it says
		# which way is left as well as which way is forward -- the pattern
		# counterpart to the RATCHET shape.
	},
	{
		"id": "arrows",
		"label": "ARROWS",
		# Chevrons pointing BACKWARD. CHEVRONS repeat the shape's own facing;
		# these read as flow coming off the tail, which is the same information
		# arriving from the other end.
	},
	{
		"id": "delta_cut",
		"label": "DELTA",
		# A single deep V across the body -- one chevron rather than three, so it
		# is a statement instead of a texture.
	},
	{
		"id": "nock",
		"label": "NOCK",
		# A V bitten into the trailing edge: a fletching notch, cut from behind
		# rather than across.
	},
	{
		"id": "beak",
		"label": "BEAK",
		# The nose cut to a V from the front, NOCK's mirror. It reinforces facing
		# at the end that already carries it, which is TIP's job done with a
		# shape rather than a band.
	},
	{
		"id": "collar",
		"label": "COLLAR",
		# Two bands close together near the nose. TIP's single band reads as a
		# cut; a pair reads as one element.
	},
	{
		"id": "bookend",
		"label": "BOOKEND",
		# A band at each end at once -- TIP and TAIL together, so what survives
		# is the body alone with both ends detached.
	},
	{
		"id": "crosshair",
		"label": "CROSSHAIR",
		# One band across and one slot along, crossing at the centre: the mark
		# quartered. The most legible composite at distance.
	},
	{
		"id": "grid",
		"label": "GRID",
		# Two cuts on each axis, so the mark comes back as a lattice. The busiest
		# pattern in the set and the one that most changes the silhouette.
	},
	{
		"id": "harpoon",
		"label": "HARPOON",
		# A flank wedge each side plus a nose band -- NOTCH and TIP as a single
		# element, which reads as a barbed head rather than as two decals.
	},
]


# The table entry for a decal id, falling back to the default rather than
# failing -- the same promise marker_shape() makes, for the same reason.
static func marker_decal(id: String) -> Dictionary:
	for decal in MARKER_DECALS:
		if decal["id"] == id:
			return decal
	for decal in MARKER_DECALS:
		if decal["id"] == MARKER_DECAL_DEFAULT:
			return decal
	return MARKER_DECALS[0]


# The polygons a decal contributes, given the outline it decorates.
#
# Every branch CLIPS or INSETS the polygon it was handed, so none may assume a
# vertex count, a symmetry or a tail notch. Clipping is what makes a concave
# chevron work without a special case: the band is a plain rectangle and the
# intersection does all the shaping.
#
# Returns polygons in the outline's own space. Empty for "none", which is the
# plain shape.
#
# EVERY CUT IS MEASURED AGAINST THE SHAPE'S WIDTH WHERE THE CUT LANDS, never
# against its global maximum. That distinction is what separates a pattern from
# a scratch, and getting it wrong is what made NOTCH invisible: its wedge apex
# sat at a fraction of `max_x`, but every shape in the table tapers, so at
# mid-body the apex fell OUTSIDE the silhouette and the triangle only grazed the
# flank. Measured with DecalProbe before the fix -- NOTCH removed 0.0-1.7% of
# the mark on every shape, left it in ONE piece, and filled NOTHING on seven of
# eight, because a sliver that thin does not survive the inlay's seam inset. It
# was a menu entry that drew nothing, and RulesTest passed it because the cut
# RESULT did change, by a hair.
#
# The same error made TIP and TAIL 5% scrapes rather than elements: a band sized
# off the global width is thickest where the shape is widest, which is exactly
# where it is least needed.
static func decal_polygons(id: String, outline: Array) -> Array:
	var poly := PackedVector2Array()
	for v in outline:
		poly.append(v)
	if poly.size() < 3:
		return []

	# The shape's own extent, so every decal is proportional to what it
	# decorates. A fixed band width would be right for the delta and wrong for
	# the dart.
	var min_y: float = poly[0].y
	var max_y: float = poly[0].y
	var max_x := 0.0
	for p in poly:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		max_x = maxf(max_x, absf(p.x))
	var height: float = maxf(max_y - min_y, 0.0001)
	# Wider than the shape, so a clipping rectangle always spans it fully. The
	# intersection is what bounds the result, never this number.
	var reach: float = max_x * 2.0 + 1.0

	match id:
		MARKER_DECAL_DEFAULT:
			return []
		"stripe":
			# Two bands cut ACROSS the facing axis, placed where the shape is
			# WIDEST rather than at even fractions of its length.
			#
			# Measured in a real-game frame: at 12% of height and sitting near
			# the tail, the bands landed where the mark is narrow and read as a
			# single nick in the trailing edge -- correct geometry, no pattern.
			# The gap has to be a real fraction of the silhouette to survive the
			# trailing camera's foreshortening, which already ate a shallow
			# taper once (section 12, the lightcycle nose).
			var out: Array = []
			for frac in [0.40, 0.68]:
				var y: float = min_y + height * frac
				var band := PackedVector2Array([
					Vector2(-reach, y),
					Vector2(reach, y),
					Vector2(reach, y + height * 0.13),
					Vector2(-reach, y + height * 0.13),
				])
				# NOT intersected with the shape. A cutter is subtracted from
				# the outline (PlayerMarker._cut_decal), so it must SPAN the
				# shape to cut clean through it -- an intersected band stops at
				# the outline and leaves the flanks joined.
				out.append(band)
			return out
		"notch":
			# A wedge bitten into each flank at mid-body, so the mark reads as
			# having shoulders.
			#
			# The wedge is built from the SILHOUETTE EDGE inward, not from a
			# distant base to an inner apex. That construction is the whole
			# reason this decal exists twice: a triangle whose base sits out at
			# +/-reach has narrowed almost to a needle by the time it crosses
			# the actual flank, so it removed 1% of the mark and filled nothing
			# (measured, DecalProbe, on every shape in the table). The width
			# that matters is the width AT THE EDGE, so that is what is
			# specified -- the base sits just outside the local half-width and
			# the apex `depth` further in.
			#
			# Both numbers are fractions of the shape's half-width AT THIS
			# HEIGHT rather than of its global maximum, since every shape tapers
			# and the two differ most on the narrow ones where a decal is
			# hardest to see.
			#
			# This replaced an "EDGE" decal that subtracted an INSET COPY of the
			# outline. That is the prettiest idea in the set and it cannot be
			# built here: subtracting an inset leaves a RING, which is an
			# outline plus a hole, and the mark is extruded as a single closed
			# loop per piece. A ring came back as an outer loop identical to the
			# plain shape (so the decal did nothing) plus a clockwise hole the
			# extruder would have filled in solid. Recorded so nobody re-adds it
			# without first giving the extrusion real hole support.
			var out2: Array = []
			# Placed where the shape has the most flank to lose, not at a fixed
			# fraction of its length. A flank cut needs flank to bite into: at
			# 52% of height the wedges landed up the lightcycle's narrow nose
			# and read as two small nicks even after they were sized correctly
			# -- visible, but not the shoulders the decal is for.
			var mid: float = _flank_y(poly, min_y, max_y)
			var bite: float = height * 0.17
			var halfw: float = _half_width_at(poly, mid, max_x)
			var depth: float = halfw * 0.62
			for side in [-1.0, 1.0]:
				# Just outside the flank, so the cut reaches the edge cleanly
				# however the outline slopes through this band.
				var outer: float = (halfw + depth) * side
				out2.append(PackedVector2Array([
					Vector2(outer, mid - bite),
					Vector2((halfw - depth) * side, mid),
					Vector2(outer, mid + bite),
				]))
			return out2
		"tip":
			# The nose cut off as a separate forward element. Facing is -Y here,
			# so forward is the LOW end.
			#
			# The band is placed far enough back that the shape has real width
			# to show a gap, and is thick enough to survive the trailing
			# camera's foreshortening. At 9% of height it measured a 5% sliver
			# and read as a scratch -- STRIPE's first failure, in a second
			# decal.
			#
			# A cutter, so it spans the shape rather than being clipped to it.
			var lo: float = min_y + height * 0.26
			var out3: Array = [PackedVector2Array([
				Vector2(-reach, lo),
				Vector2(reach, lo),
				Vector2(reach, lo + height * 0.13),
				Vector2(-reach, lo + height * 0.13),
			])]
			return out3
		"split":
			# A slot down the centre line, splitting the mark lengthways.
			#
			# A THIN slot rather than a whole half: removing half the mark
			# leaves a shape that no longer reads as pointing, which is the one
			# property every marker shape must keep (section 12).
			var slot: float = maxf(max_x * 0.11, 0.004)
			return [PackedVector2Array([
				Vector2(-slot, min_y - height),
				Vector2(slot, min_y - height),
				Vector2(slot, max_y + height),
				Vector2(-slot, max_y + height),
			])]
		"chevrons":
			# Three shallow Vs pointing the way the mark points, cut across the
			# body. Where STRIPE is two flat bands, these carry direction --
			# they read as motion rather than as decoration.
			#
			# Each is a cutter and must SPAN the shape, so the arms run out to
			# +/-reach and the V is formed by the notch between them.
			var out4: Array = []
			var arm: float = height * 0.10
			for frac in [0.32, 0.53, 0.74]:
				var y: float = min_y + height * frac
				out4.append(PackedVector2Array([
					Vector2(-reach, y),
					Vector2(0.0, y - arm),
					Vector2(reach, y),
					Vector2(reach, y + arm * 0.85),
					Vector2(0.0, y - arm + arm * 0.85),
					Vector2(-reach, y + arm * 0.85),
				]))
			return out4
		"bars":
			# Two slots either side of the centre line, running lengthways --
			# the lateral counterpart to SPLIT's single central slot.
			#
			# Offset far enough out that the centre survives between them: a
			# mark cut into three thin ribbons stops reading as a solid shape,
			# which is the same failure SPLIT's thin-slot note records.
			var out5: Array = []
			var barw: float = maxf(max_x * 0.10, 0.003)
			for side in [-1.0, 1.0]:
				var cx: float = max_x * 0.40 * side
				out5.append(PackedVector2Array([
					Vector2(cx - barw, min_y - height),
					Vector2(cx + barw, min_y - height),
					Vector2(cx + barw, max_y + height),
					Vector2(cx - barw, max_y + height),
				]))
			return out5
		"tail":
			# A band cut just ahead of the trailing edge, mirroring TIP at the
			# other end. Facing is -Y, so the tail is the HIGH end.
			#
			# Sized like TIP and for the same reason: at 10% of height it left a
			# 3.7% sliver on the dart, which is not a band, it is a crack.
			var hi: float = max_y - height * 0.30
			return [PackedVector2Array([
				Vector2(-reach, hi),
				Vector2(reach, hi),
				Vector2(reach, hi + height * 0.13),
				Vector2(-reach, hi + height * 0.13),
			])]
		"triband":
			# Three even bands. STRIPE's construction with a third band and a
			# tighter thickness, so the two are a pair rather than a duplicate.
			var t_out: Array = []
			for frac in [0.28, 0.50, 0.72]:
				var ty: float = min_y + height * frac
				t_out.append(PackedVector2Array([
					Vector2(-reach, ty),
					Vector2(reach, ty),
					Vector2(reach, ty + height * 0.095),
					Vector2(-reach, ty + height * 0.095),
				]))
			return t_out
		"pinstripe":
			# Four fine bands. The thickness is the smallest in the set and is
			# bounded from BELOW by the inlay seam rather than by taste: a band
			# thinner than this cuts a visible gap and then fills none of it,
			# which is NOTCH's failure arriving through a band.
			var p_out: Array = []
			for frac in [0.26, 0.42, 0.58, 0.74]:
				var py: float = min_y + height * frac
				p_out.append(PackedVector2Array([
					Vector2(-reach, py),
					Vector2(reach, py),
					Vector2(reach, py + height * 0.062),
					Vector2(-reach, py + height * 0.062),
				]))
			return p_out
		"wedges":
			# Two bands that taper ACROSS the mark. Each is thick on the left
			# flank and thin on the right, so the pattern leans -- where
			# STRIPE's parallel bands are the same everywhere they cross.
			var w_out: Array = []
			for frac in [0.36, 0.64]:
				var wy: float = min_y + height * frac
				w_out.append(PackedVector2Array([
					Vector2(-reach, wy),
					Vector2(reach, wy - height * 0.02),
					Vector2(reach, wy + height * 0.06),
					Vector2(-reach, wy + height * 0.17),
				]))
			return w_out
		"ladder":
			# A spine along the facing axis with rungs across it. The only
			# entry that cuts both axes, and the rungs are deliberately thinner
			# than TRIBAND's so the spine stays the dominant line.
			var l_out: Array = [PackedVector2Array([
				Vector2(-maxf(max_x * 0.085, 0.004), min_y - height),
				Vector2(maxf(max_x * 0.085, 0.004), min_y - height),
				Vector2(maxf(max_x * 0.085, 0.004), max_y + height),
				Vector2(-maxf(max_x * 0.085, 0.004), max_y + height),
			])]
			for frac in [0.34, 0.52, 0.70]:
				var ly: float = min_y + height * frac
				l_out.append(PackedVector2Array([
					Vector2(-reach, ly),
					Vector2(reach, ly),
					Vector2(reach, ly + height * 0.055),
					Vector2(-reach, ly + height * 0.055),
				]))
			return l_out
		"scallop":
			# Three bites down each flank, each sized against the half-width AT
			# ITS OWN HEIGHT -- so the row follows the silhouette in rather than
			# cutting a straight line through a tapering shape.
			#
			# The depth and the bite are both larger than the first draft, which
			# measured 3.8% on the HAMMER: that shape is a crossbar with a short
			# tail, so it has the least length in the table to spread three cuts
			# over. A shallow row is the NOTCH failure in miniature.
			var sc_out: Array = []
			for frac in [0.30, 0.50, 0.70]:
				var scy: float = min_y + height * frac
				var sch: float = _half_width_at(poly, scy, max_x)
				var scd: float = sch * 0.62
				var scb: float = height * 0.13
				for side in [-1.0, 1.0]:
					sc_out.append(PackedVector2Array([
						Vector2((sch + scd) * side, scy - scb),
						Vector2((sch - scd) * side, scy),
						Vector2((sch + scd) * side, scy + scb),
					]))
			return sc_out
		"shoulders":
			# NOTCH's placement with a square tool. Same _flank_y, same
			# half-width scaling -- what differs is the corner, and at this
			# camera angle a right angle and a point are two of the very few
			# things that still read differently once length has compressed.
			var sh_mid: float = _flank_y(poly, min_y, max_y)
			var sh_half: float = _half_width_at(poly, sh_mid, max_x)
			var sh_depth: float = sh_half * 0.52
			var sh_bite: float = height * 0.13
			var sh_out: Array = []
			for side in [-1.0, 1.0]:
				var sh_in: float = (sh_half - sh_depth) * side
				var sh_o: float = (sh_half + sh_depth) * side
				sh_out.append(PackedVector2Array([
					Vector2(sh_in, sh_mid - sh_bite),
					Vector2(sh_o, sh_mid - sh_bite),
					Vector2(sh_o, sh_mid + sh_bite),
					Vector2(sh_in, sh_mid + sh_bite),
				]))
			return sh_out
		"serrate":
			# Saw teeth down both flanks, the two sides offset by half a step so
			# the mark never reads as symmetrical. Ten cuts, each sized against
			# the local half-width like SCALLOP's.
			var se_out: Array = []
			for i in 5:
				var sey: float = min_y + height * (0.24 + 0.15 * float(i))
				var seh: float = _half_width_at(poly, sey, max_x)
				var sed: float = seh * 0.54
				var seb: float = height * 0.095
				var se_side: float = -1.0 if i % 2 == 0 else 1.0
				se_out.append(PackedVector2Array([
					Vector2((seh + sed) * se_side, sey - seb),
					Vector2((seh - sed) * se_side, sey),
					Vector2((seh + sed) * se_side, sey + seb),
				]))
				var sey2: float = sey + height * 0.075
				var seh2: float = _half_width_at(poly, sey2, max_x)
				var sed2: float = seh2 * 0.54
				se_out.append(PackedVector2Array([
					Vector2((seh2 + sed2) * -se_side, sey2 - seb),
					Vector2((seh2 - sed2) * -se_side, sey2),
					Vector2((seh2 + sed2) * -se_side, sey2 + seb),
				]))
			return se_out
		"waist":
			# One LONG bite from each flank -- NOTCH's wedge stretched until the
			# mark pinches rather than merely gaining shoulders.
			#
			# The bite is 0.42 of the height each way. At 0.30 it removed 3.5%
			# on the HOOK, whose slim shank is the least flank in the table --
			# the same shape that forced the 4% floor to be measured in the
			# first place, failing a second decal for the same reason.
			var wa_mid: float = _flank_y(poly, min_y, max_y)
			var wa_half: float = _half_width_at(poly, wa_mid, max_x)
			var wa_depth: float = wa_half * 0.72
			var wa_bite: float = height * 0.42
			var wa_out: Array = []
			for side in [-1.0, 1.0]:
				wa_out.append(PackedVector2Array([
					Vector2((wa_half + wa_depth) * side, wa_mid - wa_bite),
					Vector2((wa_half - wa_depth) * side, wa_mid),
					Vector2((wa_half + wa_depth) * side, wa_mid + wa_bite),
				]))
			return wa_out
		"quarters":
			# Three lengthways slots -- SPLIT's centre line plus BARS' pair.
			#
			# THE MINIMUM WIDTH IS WHAT THE NARROW SHAPES NEEDED, not a larger
			# proportion. At a 0.003 floor the slots cut a healthy 21% out of
			# the NIB and the SPEAR and then filled NO inlay piece, because what
			# survived was thinner than INLAY_INSET -- a decal that draws a gap
			# and no second colour, which is exactly the pair of failures the
			# harness asserts separately.
			var q_w: float = maxf(max_x * 0.075, 0.010)
			var q_out: Array = []
			for cx in [0.0, max_x * 0.52, -max_x * 0.52]:
				q_out.append(PackedVector2Array([
					Vector2(cx - q_w, min_y - height),
					Vector2(cx + q_w, min_y - height),
					Vector2(cx + q_w, max_y + height),
					Vector2(cx - q_w, max_y + height),
				]))
			return q_out
		"rails":
			# BARS pushed out toward the flanks, so what survives is a broad
			# spine rather than three even ribbons. Floored at 0.010 for the
			# reason QUARTERS is, and held at 0.60 rather than further out:
			# hard against the edge there is nothing left to fill once the seam
			# is inset.
			var r_w: float = maxf(max_x * 0.10, 0.010)
			var r_out: Array = []
			for side in [-1.0, 1.0]:
				var rcx: float = max_x * 0.60 * side
				r_out.append(PackedVector2Array([
					Vector2(rcx - r_w, min_y - height),
					Vector2(rcx + r_w, min_y - height),
					Vector2(rcx + r_w, max_y + height),
					Vector2(rcx - r_w, max_y + height),
				]))
			return r_out
		"offset":
			# One slot beside the centre line rather than on it. The only
			# asymmetric decal in the set, so it distinguishes left from right
			# as well as front from back -- the pattern counterpart to RATCHET,
			# and the only other place in these tables where handedness is
			# information rather than an accident.
			var o_w: float = maxf(max_x * 0.12, 0.004)
			var o_cx: float = max_x * 0.34
			return [PackedVector2Array([
				Vector2(o_cx - o_w, min_y - height),
				Vector2(o_cx + o_w, min_y - height),
				Vector2(o_cx + o_w, max_y + height),
				Vector2(o_cx - o_w, max_y + height),
			])]
		"arrows":
			# CHEVRONS reversed: the vees point back down the mark rather than
			# forward along it, which reads as flow leaving the tail. Same
			# construction, so the two stay a matched pair.
			var a_out: Array = []
			var a_arm: float = height * 0.10
			for frac in [0.30, 0.51, 0.72]:
				var ay: float = min_y + height * frac
				a_out.append(PackedVector2Array([
					Vector2(-reach, ay),
					Vector2(0.0, ay + a_arm),
					Vector2(reach, ay),
					Vector2(reach, ay + a_arm * 0.85),
					Vector2(0.0, ay + a_arm * 1.85),
					Vector2(-reach, ay + a_arm * 0.85),
				]))
			return a_out
		"delta_cut":
			# One deep V across the body instead of three shallow ones.
			#
			# THICKER THAN IT IS DEEP, and that is the tuning rather than the
			# drawing: a deep thin V measured 4.6% on the NIB, barely over the
			# floor, because its arms run out to the flanks exactly where that
			# shape has least to give. Trading vee depth for band thickness
			# keeps the chevron read and doubles what it removes on the worst
			# shape in the table.
			var d_y: float = min_y + height * 0.52
			var d_arm: float = height * 0.24
			return [PackedVector2Array([
				Vector2(-reach, d_y),
				Vector2(0.0, d_y - d_arm),
				Vector2(reach, d_y),
				Vector2(reach, d_y + height * 0.16),
				Vector2(0.0, d_y - d_arm + height * 0.16),
				Vector2(-reach, d_y + height * 0.16),
			])]
		"nock":
			# A V bitten into the trailing edge -- a fletching notch.
			#
			# It SPANS PAST max_y rather than stopping inside the outline. A cut
			# that stops inside leaves a HOLE, and Geometry2D.clip_polygons
			# returns a hole as its own loop, which the extruder then builds as
			# an outward loop and fills in solid -- the removed EDGE decal's
			# failure exactly. Measured while drafting: a version that stopped
			# short came back as 2 pieces totalling MORE area than the shape
			# started with, because the inner loop's area adds.
			#
			# PLACED WELL INBOARD, at 0.42 of the height rather than the 0.24
			# first written. A V at the extremity cannot reach the visibility
			# floor on a pointed shape: it removes only the part of the end
			# BELOW the vee, which is a fraction of a fraction. Measured, the
			# arrow carries 36.7% of its area in its rear third and the trident
			# only 22.2%, and at 0.24 the cut took 1.1% on the kite.
			var n_y: float = max_y - height * 0.42
			return [PackedVector2Array([
				Vector2(-reach, n_y),
				Vector2(0.0, n_y + height * 0.22),
				Vector2(reach, n_y),
				Vector2(reach, max_y + height),
				Vector2(-reach, max_y + height),
			])]
		"beak":
			# NOCK's mirror, cut into the nose. Named BEAK rather than PROW
			# because a shape in the other table is already called that, and two
			# picker rows reading PROW would be a puzzle even though the ids are
			# namespaced (shape:prow against decal:beak) and could not collide. Inboard for the same reason and
			# further still: the front of a pointed shape is the THINNER end --
			# the trident carries just 9.0% of its area in its forward third,
			# where the same shape carries 22.2% behind. A shallow nose V
			# measured 0.4% removed and failed on 35 of the 44 shapes.
			var pr_y: float = min_y + height * 0.46
			return [PackedVector2Array([
				Vector2(-reach, pr_y),
				Vector2(0.0, pr_y - height * 0.20),
				Vector2(reach, pr_y),
				Vector2(reach, min_y - height),
				Vector2(-reach, min_y - height),
			])]
		"collar":
			# Two bands close together near the nose. TIP's single band reads as
			# the nose having been cut off; a close pair reads as a fitting.
			var c_out: Array = []
			for frac in [0.22, 0.36]:
				var cy: float = min_y + height * frac
				c_out.append(PackedVector2Array([
					Vector2(-reach, cy),
					Vector2(reach, cy),
					Vector2(reach, cy + height * 0.075),
					Vector2(-reach, cy + height * 0.075),
				]))
			return c_out
		"bookend":
			# TIP and TAIL at once, so what survives is the body with both ends
			# detached. Offered as one entry rather than left to the player
			# because the two bands have to be placed against each OTHER -- at
			# their own default heights they crowd the body on the short shapes.
			var b_out: Array = [PackedVector2Array([
				Vector2(-reach, min_y + height * 0.24),
				Vector2(reach, min_y + height * 0.24),
				Vector2(reach, min_y + height * 0.34),
				Vector2(-reach, min_y + height * 0.34),
			])]
			b_out.append(PackedVector2Array([
				Vector2(-reach, max_y - height * 0.34),
				Vector2(reach, max_y - height * 0.34),
				Vector2(reach, max_y - height * 0.24),
				Vector2(-reach, max_y - height * 0.24),
			]))
			return b_out
		"crosshair":
			# One band across and one slot along, crossing at the centre.
			var x_w: float = maxf(max_x * 0.085, 0.004)
			var x_y: float = min_y + height * 0.46
			return [
				PackedVector2Array([
					Vector2(-reach, x_y),
					Vector2(reach, x_y),
					Vector2(reach, x_y + height * 0.105),
					Vector2(-reach, x_y + height * 0.105),
				]),
				PackedVector2Array([
					Vector2(-x_w, min_y - height),
					Vector2(x_w, min_y - height),
					Vector2(x_w, max_y + height),
					Vector2(-x_w, max_y + height),
				]),
			]
		"grid":
			# Two cuts on each axis: the mark comes back as a lattice. The
			# busiest pattern in the set, and the individual cuts are the
			# thinnest of any composite for that reason -- four of them at
			# CROSSHAIR's weights would leave very little mark.
			var g_w: float = maxf(max_x * 0.07, 0.003)
			var g_out: Array = []
			for frac in [0.34, 0.62]:
				var gy: float = min_y + height * frac
				g_out.append(PackedVector2Array([
					Vector2(-reach, gy),
					Vector2(reach, gy),
					Vector2(reach, gy + height * 0.075),
					Vector2(-reach, gy + height * 0.075),
				]))
			for side in [-1.0, 1.0]:
				var gcx: float = max_x * 0.42 * side
				g_out.append(PackedVector2Array([
					Vector2(gcx - g_w, min_y - height),
					Vector2(gcx + g_w, min_y - height),
					Vector2(gcx + g_w, max_y + height),
					Vector2(gcx - g_w, max_y + height),
				]))
			return g_out
		"harpoon":
			# NOTCH and TIP as ONE element -- a flank wedge each side plus a
			# nose band -- so it reads as a barbed head rather than as two
			# decals that happen to be on at once.
			var h_mid: float = _flank_y(poly, min_y, max_y)
			var h_half: float = _half_width_at(poly, h_mid, max_x)
			var h_depth: float = h_half * 0.50
			var h_bite: float = height * 0.12
			var h_out: Array = [PackedVector2Array([
				Vector2(-reach, min_y + height * 0.24),
				Vector2(reach, min_y + height * 0.24),
				Vector2(reach, min_y + height * 0.325),
				Vector2(-reach, min_y + height * 0.325),
			])]
			for side in [-1.0, 1.0]:
				h_out.append(PackedVector2Array([
					Vector2((h_half + h_depth) * side, h_mid - h_bite),
					Vector2((h_half - h_depth) * side, h_mid),
					Vector2((h_half + h_depth) * side, h_mid + h_bite),
				]))
			return h_out
	return []


# The shape's half-width at a given height along the facing axis.
#
# This is what lets a cut be proportional to the silhouette WHERE IT LANDS
# rather than to the shape's widest point, which is the distinction that decides
# whether a flank cut bites or misses (see decal_polygons). Every shape in the
# table tapers, so the two numbers differ most on exactly the narrow shapes
# where a decal is hardest to see in the first place.
#
# Walks the edges and takes the widest crossing of the horizontal line at `y`,
# which needs no assumption about vertex count, winding or convexity -- the
# chevron is concave and the delta has three vertices.
#
# Falls back to the global half-width when the line misses the polygon entirely,
# so a caller can never place an apex against nothing.
static func _half_width_at(poly: PackedVector2Array, y: float,
		fallback: float) -> float:
	var widest := 0.0
	var hit := false
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if is_equal_approx(a.y, b.y):
			continue
		var lo: float = minf(a.y, b.y)
		var hi: float = maxf(a.y, b.y)
		if y < lo or y > hi:
			continue
		var t: float = (y - a.y) / (b.y - a.y)
		widest = maxf(widest, absf(a.x + (b.x - a.x) * t))
		hit = true
	if not hit or widest <= 0.0001:
		return fallback
	return widest


# Where along the facing axis a flank decal has the most silhouette to bite.
#
# NOT simply the widest point. On a barbed shape -- the arrow and the dart --
# the widest line is at the very tips of the rear barbs, where there is width
# but almost no body between them: measured, cutting there removed 3.5% and
# 2.6% of the mark against 7.6% and 9.0% at mid-body, so the "obvious" target
# was the worse one on two of the eight shapes and RulesTest caught it.
#
# What a wedge actually needs is width AND something behind it, so the score is
# the half-width times how much of the shape lies further back. That picks the
# shoulder of a barbed shape and the true widest line of a plain one, which is
# the same place a human would point at.
#
# Sampled rather than solved, since an outline is an arbitrary polygon: the
# chevron is concave, so the best line need not fall on a vertex at all.
static func _flank_y(poly: PackedVector2Array, min_y: float,
		max_y: float) -> float:
	var best: float = (min_y + max_y) * 0.5
	var top := -1.0
	var steps := 48
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var y: float = min_y + (max_y - min_y) * t
		var w: float = _half_width_at(poly, y, -1.0)
		if w <= 0.0:
			continue
		# Falls off toward either end, so a line with nothing behind it loses
		# to one with body on both sides.
		var score: float = w * (1.0 - absf(t - 0.5) * 1.2)
		if score > top:
			top = score
			best = y
	return best


# --- Landmarks (docs/specs/landmarks.md) -------------------------------------
#
# Decorative structures whose only job is to answer "have I been here before?".
# They carry NO navigational information: placement ignores the solve path, the
# distance field, the gates and the exit entirely.
#
# That line is what makes the feature safe to add at all. Three upgrade lines
# are sold on answering "which way" -- Path Indicator (the headline upgrade),
# Gate Compass, Golden Trail -- and free scenery that hinted at the route would
# cannibalise all three. This is the line the wall indicator held too, before it
# was removed in favour of the landmark itself (section 5.6) -- a dead end is now
# marked by the decoration standing in it, nothing more.
#
# What they DO fix is that a braided maze is unreadable as a loop: a re-crossed
# junction is indistinguishable from a fresh one, so the distance-and-time
# punishment in section 11.2 lands without the lesson.

# Landmark type ids. Order matters only as an index into LANDMARK_TYPES.
enum {
	LANDMARK_SPIRE,
	LANDMARK_MONOLITH,
	LANDMARK_TREE,
	LANDMARK_ARCH,
	LANDMARK_RINGS,
	LANDMARK_RUBBLE,
}

# Two tiers, answering different questions.
#
# SKYLINE landmarks clear WALL_HEIGHT and are visible several corridors away, so
# they make a REGION recognisable. LOCAL ones stay under the wall line and are
# seen only from the corridor they sit in, so they make one JUNCTION
# recognisable.
#
# Skyline landmarks are seen as spires poking up past the wall tops, NEVER from
# above: the camera is capped below WALL_HEIGHT on purpose (CAM_HEIGHT, and
# again for the crash view) because above it the maze flattens into a floor
# plan. So only the UPPER portion of a skyline landmark is ever seen at
# distance, which is why each one is shaped to be identifiable from its top
# alone.
#
# The hues are held clear of every reserved colour in the game. Amber-yellow is
# gates, white is the exit and the player marker, green/red is the Path
# Indicator, red is the barrier bar when low, and
# the five maze palettes own cyan, magenta, green, ember and violet. Landmarks
# take the gaps: deep blue, bone, teal, rose, pale violet, slate.
#
# All six are LOW saturation and LOW emission relative to the neon. A landmark
# must be visible but never brighter than a gate -- gates and the exit have to
# stay the most eye-catching things in the maze, because they are navigation and
# landmarks explicitly are not.
#
# They do NOT recolour per maze. They join the short list of fixed-colour things
# (gates, exit, player marker, HUD -- section 8): a landmark seen in maze 1 and
# again in maze 2 should read as the same kind of object, and per-maze tinting
# would mean re-learning the vocabulary three times a run for no gain.
const LANDMARK_TYPES := [
	{
		"name": "spire",
		"skyline": true,
		"colour": Color(0.30, 0.42, 0.85),
		"height": 13.0,
	},
	{
		"name": "monolith",
		"skyline": true,
		"colour": Color(0.55, 0.53, 0.46),
		"height": 9.5,
	},
	{
		"name": "tree",
		"skyline": true,
		"colour": Color(0.35, 0.70, 0.66),
		"height": 11.0,
	},
	{
		"name": "arch",
		"skyline": false,
		"colour": Color(0.82, 0.45, 0.52),
		"height": 2.4,
	},
	{
		"name": "rings",
		"skyline": false,
		"colour": Color(0.62, 0.55, 0.82),
		"height": 2.0,
	},
	{
		"name": "rubble",
		"skyline": false,
		"colour": Color(0.52, 0.55, 0.60),
		"height": 0.9,
	},
]

# A skyline landmark must clear the wall line by enough to be unmistakably
# ABOVE it rather than level with it. Asserted in RulesTest against every entry
# marked skyline, so a future type cannot quietly be added at wall height and
# lose the whole point of the tier.
#
# The actual heights sit far above this floor -- roughly 3-4x WALL_HEIGHT. A
# first pass put them at 1.5x, which satisfies the rule and still fails the
# PURPOSE: with the camera capped at 2.3 and fog over everything, a landmark
# that merely clears the wall shows a few pixels of top edge. It has to tower to
# be recognisable from the next corridor over.
const LANDMARK_SKYLINE_MIN := WALL_HEIGHT + 1.5

# Emission energy. Tuned between two failures seen in captured frames, not
# guessed:
#
#   TOO DIM (0.55)   a skyline landmark four cells out was a grey speck. Fog
#                    sits between the camera and everything, and an unlit
#                    surface loses to it well before it reaches the wall line.
#
#   TOO BRIGHT (1.25) a landmark filling a dead end blew out to flat white, so
#                    the silhouette -- the entire way a landmark is recognised
#                    (see LANDMARK_TYPES) -- was lost exactly where the player
#                    is closest to it. It also washed over the no-entry wall
#                    indicator painted on that same end wall, and a decoration
#                    must never outshout a navigation signal.
#
# Still under the neon's 2.2, so gates and the exit stay the most eye-catching
# things in the maze.
const LANDMARK_EMISSION := 0.9

# Fallback landmark density for a maze whose config omits the key.
#
# Density is a per-maze knob (`landmarks` in MAZES) rather than a parallel array
# indexed by maze number, deliberately: an array beside a five-entry MAZES list
# is a transcription that goes stale the moment a maze is added, which is the
# same failure as a test restating a tuning number (CLAUDE.md section 12).
const LANDMARK_DENSITY := 0.24

# Landmarks placed OUTSIDE the maze boundary, giving it an exterior. Skyline
# tier only -- a local one out there would never clear the boundary wall and so
# would never be seen at all.
const LANDMARK_EXTERIOR_COUNT := 55

# How far beyond the boundary wall the exterior ring sits, in cells. Far enough
# that they read as distant scenery rather than as part of the maze, close
# enough to stay inside the fog.
const LANDMARK_EXTERIOR_MIN_CELLS := 3.0
const LANDMARK_EXTERIOR_MAX_CELLS := 9.0


# --- Lanes (lateral sub-grid) ------------------------------------------------
#
# A corridor is one cell wide as far as the RULES are concerned -- the maze
# graph, turn resolution, the buffer and the barrier all still work in whole
# cells, and the simulation stays headlessly testable (CLAUDE.md section 12).
# Lanes are a DISPLAY-LAYER offset on top of that: where inside the corridor the
# marker actually sits.
#
# The point is that a turn should look like it has weight. Cornering throws you
# wide, toward the outside of the turn, and you drift back toward the centre
# line over the following cells. Nothing about the maze changes; what changes is
# that a corner reads as an arc instead of an instant 90-degree snap.
#
# NO NEW INPUT. Lane is a consequence of turning, never a thing the player
# steers, which keeps the three-key contract in section 2 intact.
const LANE_COUNT := 5
const LANE_MAX := 2          # lanes run -2..+2, 0 being the corridor centre

# How far apart lanes sit, derived so the outermost lane leaves the marker clear
# of the wall rather than buried in it.
const LANE_SPACING := (CELL_SIZE * 0.5 - MARKER_RADIUS - 0.25) / float(LANE_MAX)

# How far a turn throws the player toward the outside of the corner, in lanes.
#
# ONE lane, not two. At 2.0 the kick equalled LANE_MAX, so every single corner
# slammed the marker from the centre line to hard against the outer wall -- the
# lateral position was binary (dead centre or pinned to the edge), the arc had
# no middle, and coming out of a corner already touching the wall meant the
# barrier was draining before the player had done anything wrong. A one-lane
# kick leaves the outer lane as somewhere a *second* turn in the same direction
# can take you, which is what makes the sub-grid read as a range of positions
# rather than a toggle.
const LANE_TURN_KICK := 1.0

# --- Turn freeze -------------------------------------------------------------
#
# A turn stops the racer dead for a beat before the new corridor starts moving.
#
# A pivot is not a continuous motion: facing changes in one frame, and the drawn
# position can move with it -- a scrape escape repositions the marker over a
# metre, and there is no formulation that makes that continuous (both were
# measured; see Racer._press_into_wall). Trying to HIDE the discontinuity was
# the wrong instinct. Freezing on it turns the jump into a beat the player can
# actually see: the world holds still, the camera swings round to the new
# heading, and travel resumes once the view agrees with the facing.
#
# It also pays for itself against the speed ramp. At 8x a corner arrives and is
# gone inside 125ms; the freeze buys a fixed, speed-independent moment to read
# the new corridor, which is the one thing the ramp otherwise takes away. It
# does NOT stop the clock -- the run timer keeps running, so the freeze is a
# real cost in the currency section 8 says the player is fighting, and Snap
# Turn buys it back down.
const TURN_FREEZE := 0.10

# The freeze the 180 gets. Longer, because a reversal flips the view through a
# full half-turn -- twice the camera travel, and the corridor behind you is the
# one thing you have not been looking at.
const REVERSE_FREEZE := 0.16

# REMOVED: the camera used to slew 3.5x faster while the turn freeze ran.
#
# The reasoning was that a freeze the camera does not spend is just a stutter --
# the player held still and still looking the old way when released. Measured,
# the cure was far worse than the disease: at the default dial the boost closed
# 70% of the entire turn in a SINGLE FRAME, and at dials 0-5 a literal 100%. The
# camera lurched almost the whole way round on frame one and then crept through
# the remainder, which is the jolt that was reported.
#
# It could not be smoothed, only removed. Decaying the boost instead of
# switching it off was tried first and measurably helped (worst frame-to-frame
# slowdown 3.90x -> 1.14x at the slow end), and did nothing at the default,
# because there the lurch is the boost ITSELF rather than the way it ends.
#
# The stutter it guarded against does not materialise: on the plain dial rate
# the default still completes 73.8% of its swing inside the freeze. The slow
# settings finish well after it, which is what the player chose them for.
#
# Do not reintroduce a multiplier here. If the camera needs to be faster during
# a turn, that is the DIAL's job -- a multiplier on top of it pushes the rate
# past the dial's own fast end during the one moment the player is watching.


# How fast the player MARKER swings onto a new heading, as a fraction of the
# remaining angle closed per second -- the same units as CAM_YAW_RATE_DEFAULT.
#
# The marker used to take the racer's facing directly, so it rotated 90 degrees
# in ONE FRAME while the camera it sits under eased over many. Measured on a
# maze-1 autopilot: a worst per-frame marker step of 180.00 degrees against the
# camera's 26.25, and 26 such snaps in 2000 frames. So "the camera transition is
# smooth" was already true and the complaint was still right -- what teleports is
# the arrow, not the eye, and a marker that snaps under a gliding camera reads as
# the whole world jumping.
#
# This is the LANE_TURN_KICK_RATE lesson on the rotational axis. That constant
# exists because applying the lateral kick as a single step made it "a second
# snap stapled to the 90-degree snap"; this is the 90-degree snap it was stapled
# to, and it is smoothed the same way -- by easing a DISPLAY value, with the
# simulation's own `facing` still flipping in one frame.
#
# Faster than the camera's own rate at every dial setting, deliberately. The
# marker answers facing (section 12) and is the thing the player steers with, so
# it must never be the laggier of the two: a marker trailing BEHIND a view that
# has already arrived points at a wall. Leading the camera is what makes the
# swing read as the racer turning and the view following, which is the actual
# relationship.
# Tuned against the FIRST FRAME's step, which is what the eye reads as a snap --
# not against the total duration. At 12.0 a 90 moves 21 degrees on its first
# frame and a 180 moves 49, so neither flips in one frame, and the swings settle
# in 186ms and 159ms. Both run a little past their freeze, which is correct: the
# camera does too, and a swing still finishing as the racer moves off is what
# reads as the view FOLLOWING rather than being welded on.
#
# Higher was measured and rejected. At 18.0 the first frame of a 180 covered 86
# degrees -- a near-instant half-flip, which is the snap this constant exists to
# remove wearing a smaller number.
#
# It deliberately took no freeze multiplier even when the camera still had one.
# That 3.5x existed so the CAMERA could catch up to a pivot it was not present
# for; the marker is the thing that pivoted, so it has nothing to catch up to.
# Applying it anyway drove the per-frame step straight into its own clamp --
# measured, a 90 closed 100% of its angle in one frame at every rate from 14
# upward, which is the snap this constant exists to remove, reintroduced by the
# multiplier. The camera's own multiplier has since been removed outright, for
# the same reason measured on the camera instead.
const MARKER_YAW_RATE := 12.0

# How much the marker's swing accelerates with the size of the angle left.
#
# The ask was "faster depending on the lag", and a bare exponential ease is the
# opposite: it is fastest at the start and crawls at the end, so the LAST few
# degrees of a 180 take as long as the first sixty. Scaling the rate by the
# remaining angle makes a reversal resolve in roughly the wall time of a 90
# rather than twice it, which matters because REVERSE_FREEZE is only 1.6x
# TURN_FREEZE -- a 180 that eased at the 90's rate would still be swinging well
# after the hold released.
#
# Measured in half-turns, so a 90 (0.5) contributes half of what a 180 (1.0)
# does. Tuned so a 180 completes inside its own freeze rather than past it.
# At 0.35 a 180 swings at 1.35x a 90's rate, so the reversal resolves in LESS
# wall time (159ms) than the 90 (186ms) despite covering twice the angle.
# That is the point: a reversal is the input the player most needs to see land,
# and REVERSE_FREEZE is only 1.6x TURN_FREEZE, so a 180 easing at the 90's rate
# would still be turning after the hold released.
#
# Not higher: at 0.6 the 180's first frame covered 86 of its 180 degrees, which
# is most of the way round in a single frame -- the swing collapsing back toward
# the snap it replaced.
const MARKER_YAW_LAG_GAIN := 0.35

# Below this, the swing is finished and the marker is snapped onto the exact
# facing. An ease approaches its target asymptotically and never arrives, which
# would leave the arrow permanently a fraction of a degree off the corridor it
# is driving down -- invisible, but it means the marker's yaw is never actually
# equal to the racer's facing, and anything that later compares the two would be
# reading a value that is always slightly wrong.
const MARKER_YAW_SNAP_EPSILON := 0.0015

# How fast the kick is applied, in lanes per second.
#
# The kick used to be a step: `lane += KICK` in the same frame the facing
# changed, so the marker jumped sideways instantly and the "arc with weight"
# this whole mechanic exists for was invisible -- it was a second snap stapled
# to the 90-degree snap. Easing it in over a few frames is what actually makes
# the corner read as an arc. Fast enough to complete well inside one cell even
# at high speed, so the lane has settled before the next junction.
const LANE_KICK_PER_SEC := 6.0

# Lanes per second the player drifts back toward centre. Slow enough that the
# kick is still visible a cell or two later, fast enough to recover before the
# next junction at ordinary speed.
const LANE_RECOVER_PER_SEC := 1.6


# --- Seeded runs (docs/plans/leaderboards.md) --------------------------------
#
# The daily and monthly boards need every player driving the SAME maze, so the
# seed is derived from the date itself rather than fetched. Every client
# computes it identically with no network call, which means a daily run starts
# instantly and still works offline -- only the board needs Firebase.
#
# Publishing seeds from Firestore was rejected: it puts a round trip in front of
# the PLAY button, and a failed fetch would mean no daily run at all.

# Which board a run counts toward. GENERAL keeps the ordinary wall-clock seed --
# that board is "any seed", so a random maze is correct there.
enum Board { GENERAL, DAILY, MONTHLY }

const BOARD_NAMES := ["general", "daily", "monthly"]

# Mixed into every derived seed so the daily maze for a date is not the same
# number as anything else that might hash the same string.
const SEED_SALT := 0x4D617A65   # "Maze"


# A stable 31-bit seed from any string.
#
# FNV-1a rather than String.hash(): the engine's hash is not contractually
# stable across Godot versions, and a seed that changed on an engine upgrade
# would silently redraw every past daily maze -- making old scores incomparable
# with new ones on a board whose whole premise is that the maze is fixed.
#
# Masked to 31 bits because the value is handed to RandomNumberGenerator.seed
# and used in `run_seed + index * 7919`; keeping it positive and well clear of
# 64-bit overflow keeps that arithmetic honest.
static func seed_from_string(text: String) -> int:
	var h := 0x811C9DC5
	for i in text.length():
		h = (h ^ text.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 0x01000193) & 0xFFFFFFFF
	return (h ^ SEED_SALT) & 0x7FFFFFFF


# "2026-09-02" -> the seed every player drives that day.
static func seed_for_date(date_text: String) -> int:
	return seed_from_string("daily:" + date_text)


# "2026-09" -> the seed every player drives that month.
static func seed_for_month(month_text: String) -> int:
	return seed_from_string("monthly:" + month_text)


# Today's date as the boards key them, in LOCAL time.
#
# Local rather than UTC deliberately: a player's "today" is the date on their own
# calendar, and a UTC rollover would change the daily maze mid-evening for
# anyone west of Greenwich.
static func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func this_month_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d" % [d["year"], d["month"]]


# The seed for a board right now. GENERAL is the wall clock, so every run draws
# a fresh maze; the other two are fixed for their period.
static func seed_for_board(board: int) -> int:
	match board:
		Board.DAILY:
			return seed_for_date(today_key())
		Board.MONTHLY:
			return seed_for_month(this_month_key())
		_:
			return int(Time.get_unix_time_from_system()) & 0x7FFFFFFF


static func board_name(board: int) -> String:
	if board < 0 or board >= BOARD_NAMES.size():
		return BOARD_NAMES[Board.GENERAL]
	return String(BOARD_NAMES[board])
