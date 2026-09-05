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
	1.2,    # 3
	0.6,    # 4
	0.3,    # 5+ -- burnt out
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
		# Maze 1 -- cyan. The stock lightcycle blue.
		"wall": Color(0.12, 0.85, 1.0),
		"grid": Color(0.30, 0.55, 0.85),
		"floor": Color(0.03, 0.04, 0.07),
		"wall_albedo": Color(0.13, 0.17, 0.25),
		"wall_emission": Color(0.07, 0.12, 0.20),
		"fog": Color(0.02, 0.05, 0.10),
	},
	{
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
]

# Gate and exit markers keep a FIXED colour across every maze. They are
# navigation, not decoration: a gate must be identifiable as a gate the instant
# it comes into view, and recolouring it per maze would mean re-learning what
# the bright thing in the corridor once per maze.
const NEON_GATE := Color(1.0, 0.85, 0.15)
const NEON_EXIT := Color(1.0, 1.0, 1.0)

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

# The camera slews toward the new heading this many times faster while frozen.
# The whole point is that the view CATCHES UP during the hold rather than
# trailing out of it -- a freeze the camera does not use is just a stutter.
const TURN_FREEZE_CAM_MULTIPLIER := 3.5

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
