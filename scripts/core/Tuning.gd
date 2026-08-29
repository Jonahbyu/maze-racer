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
const BASE_BARRIER := 0.5
const BARRIER_PER_RANK := 0.25

# Full refill in 2s of clean travel at base.
const BASE_BARRIER_REGEN := 0.25
const BARRIER_REGEN_PER_RANK := 0.15

const MAX_HP := 100
const WALL_DAMAGE := 1

# An expired turn input. Cheap, frequent, and teaching -- it says "you were
# early" without derailing the run. Not a crash: no HP, no barrier drain.
const SLOWDOWN_PENALTY := 0.5

# v1 has no death. The path exists; the flag is off (CLAUDE.md section 5.5).
const DEATH_ENABLED := false

# --- Upgrades (CLAUDE.md section 7) ------------------------------------------

const BASE_SPEED_PER_RANK := 0.25
const WALL_ARMOR_PER_RANK := 1

# Path Indicator: how many cells ahead the junction warning appears, by rank.
const INDICATOR_LOOKAHEAD_BY_RANK := [0.0, 1.0, 2.0, 3.5]

# Minimap radius in cells, by rank. Rank 0 means no minimap at all.
const MINIMAP_RADIUS_BY_RANK := [0.0, 6.0, 10.0, 16.0, 24.0]

# Golden Trail: seconds between firings and trail length in cells, by rank.
# Index 0 is rank 0 -- no trail. Both scale together (CLAUDE.md section 7).
const TRAIL_INTERVAL_BY_RANK := [0.0, 12.0, 8.0, 5.0]
const TRAIL_CELLS_BY_RANK := [0.0, 10.0, 15.0, 20.0]

# The streak runs at this multiple of the player's CURRENT speed, so it always
# pulls ahead. A fixed rate would trail behind a player at 5x, which inverts the
# whole point of a forward scout.
const TRAIL_SPEED_MULTIPLIER := 2.0

# How long the fully-drawn trail holds before fading, in seconds. Long enough
# that a trail fired just before a junction is still there when it arrives.
const TRAIL_LINGER := 2.0

const CARDS_PER_GATE := 3

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
# They need separate knobs because they compete for the same removals: maze 3's
# density target sits barely under what carve-plus-braid leaves, so a
# shallow-first ordering inside the density pass had almost no budget and
# drained nearly none of them. Maze.gd culls stubs in their own stage first.
const MAZES := [
	{
		"name": "The Grid",
		"palette": 0,
		"width": 60,
		"height": 60,
		"braid": 0.06,
		"dead_ends": 0.025,
		# Fraction of one-cell stubs kept. Maze 1 is the introduction: a
		# turnaround here teaches nothing the player has the speed to act on.
		"shallow_keep": 0.15,
		"gates": 8,
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
		"name": "The Tangle",
		"palette": 1,
		"width": 75,
		"height": 75,
		"braid": 0.18,
		"dead_ends": 0.030,
		"shallow_keep": 0.25,
		"gates": 8,
	},
	{
		"name": "The Labyrinth",
		"palette": 2,
		"width": 90,
		"height": 90,
		"braid": 0.25,
		"dead_ends": 0.040,
		# Maze 3 keeps the most: by here the player has upgrades and the speed
		# to be punished by a stub they misread, which is the point of it.
		"shallow_keep": 0.35,
		"gates": 8,
	},
]

# --- Per-maze palettes (CLAUDE.md section 8) ---------------------------------
#
# Each maze gets its own neon colourway, so arriving in a new maze reads as
# arriving somewhere -- not just as the same corridor with a bigger grid.
#
# The palette is the ONLY thing that changes; wall, grid and marker geometry are
# identical across all three. That matters because the grid lines are the timing
# contract (section 11.3): recolouring them is safe, restyling or reweighting
# them is not.
#
# Hue is the whole signal, and the three are spaced far apart on the wheel so
# they are never confusable at a glance. Value and saturation stay in the same
# band across all three, because brightness is already doing a job -- the wall
# indicator ramps amber-to-red by distance, the barrier bar goes red when low --
# and a dim maze would make those reads land differently maze to maze.
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
		# Maze 3 -- acid green. The furthest from both of the others, and the
		# most alien, for the maze the player should least want to be in.
		"wall": Color(0.35, 1.0, 0.45),
		"grid": Color(0.45, 0.80, 0.45),
		"floor": Color(0.02, 0.06, 0.04),
		"wall_albedo": Color(0.13, 0.24, 0.16),
		"wall_emission": Color(0.06, 0.18, 0.09),
		"fog": Color(0.02, 0.08, 0.04),
	},
]

# Gate and exit markers keep a FIXED colour across all three mazes. They are
# navigation, not decoration: a gate must be identifiable as a gate the instant
# it comes into view, and recolouring it per maze would mean re-learning what
# the bright thing in the corridor is three times a run.
const NEON_GATE := Color(1.0, 0.85, 0.15)
const NEON_EXIT := Color(1.0, 1.0, 1.0)


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
const LANE_TURN_KICK := 2.0

# Lanes per second the player drifts back toward centre. Slow enough that the
# kick is still visible a cell or two later, fast enough to recover before the
# next junction at ordinary speed.
const LANE_RECOVER_PER_SEC := 1.6
