# Maze generation and solving.
#
# Pure logic, no nodes, no rendering -- so it stays headlessly testable
# (CLAUDE.md section 12). Everything the renderer and the Path Indicator need is
# derived here and read back as plain data.
#
# Pipeline (CLAUDE.md section 6):
#   1. carve a perfect maze with iterative randomized DFS
#   2. braid in loops by knocking out walls
#   3. tune dead-end density
#   4. BFS from the exit to build a full distance field
#   5. place gates along the canonical solve path
class_name Maze
extends RefCounted

# Wall bitmask. A cell stores which of its four sides are solid.
const N := 1
const E := 2
const S := 4
const W := 8

const DIRS := [N, E, S, W]

# Direction vectors. +Y is south, matching row order in the flat cell array.
const DIR_VECTORS := {
	N: Vector2i(0, -1),
	E: Vector2i(1, 0),
	S: Vector2i(0, 1),
	W: Vector2i(-1, 0),
}

const OPPOSITE := {N: S, E: W, S: N, W: E}

# Longest run a player may travel without a junction appearing.
#
# The `straighten` carve bias lengthens corridors on AVERAGE but cannot bound
# them -- it is a per-step probability, so a long run is always possible and at
# 0.70 the measured longest passed 40 cells. A 40-cell straight is dead time in
# a game whose whole tension is reading junctions at speed: nothing to decide,
# nothing to read, just holding a lane while the ramp climbs.
#
# Enforced as a post-carve pass rather than by lowering `straighten`, because
# the two want opposite things: the bias sets the TYPICAL corridor length (still
# ~3 cells, which is what stops the maze feeling choppy) and this sets the
# CEILING. Lowering the bias to control the tail would shorten every corridor.
const MAX_STRAIGHT_CELLS := 8

var width: int
var height: int
var seed_value: int

# cells[y * width + x] -> wall bitmask. A set bit means that side is SOLID.
var cells: PackedInt32Array

# BFS distance from every cell to the exit. -1 means unreachable.
var distance_field: PackedInt32Array

# The canonical entrance-to-exit route.
var solve_path: Array[Vector2i] = []

# Gate cells, spaced along solve_path.
var gates: Array[Vector2i] = []

# Decorative landmarks (docs/specs/landmarks.md). Each entry is a Dictionary:
#
#   cell     Vector2i   the cell it occupies (may be OUTSIDE the grid, for the
#                       exterior ring -- so never index the maze with it)
#   type     int        an index into Tuning.LANDMARK_TYPES
#   yaw      float      rotation about Y, radians
#   scale    float      per-instance size variation
#   anchor   Vector2    offset from the cell centre in CELL units, so a dead-end
#                       landmark can sit against the far wall rather than on the
#                       point the player stops at
#
# This is DISPLAY DATA ONLY. Nothing in the simulation may read it: movement,
# turn resolution, the buffer, the barrier, penalties and the distance field all
# have to behave identically whether it is populated or empty. RulesTest asserts
# that directly, because this is the failure mode hardest to notice -- the data
# hangs off the maze, so it is reachable from the rules layer even though it must
# never be used there.
var landmarks: Array[Dictionary] = []

var start_cell: Vector2i
var exit_cell: Vector2i

var _rng := RandomNumberGenerator.new()

# Landmarks draw from their OWN stream, seeded from the maze seed but separate
# from the carve's generator.
#
# Sharing _rng would mean that changing the landmark density silently redraws
# every maze in the game, because each extra draw shifts the whole downstream
# sequence. A decoration knob must not be able to alter the maze it decorates.
var _decor_rng := RandomNumberGenerator.new()

# 0.0 = pure random DFS. Higher values bias the carve toward continuing in the
# direction it was already going, which lengthens straight corridors.
var _straighten := 0.0


func generate(p_width: int, p_height: int, p_seed: int, braid_factor: float,
		dead_end_target: float, gate_count: int, straighten: float = 0.0,
		shallow_keep: float = 1.0, landmark_density: float = 0.0,
		zigzag_keep: float = 1.0) -> void:
	width = p_width
	height = p_height
	seed_value = p_seed
	_straighten = straighten
	_rng.seed = p_seed
	# Offset so the two streams never run in lockstep on the same seed.
	_decor_rng.seed = p_seed ^ 0x5EED_DEC0

	# Start every cell fully walled; the carve knocks walls down.
	cells = PackedInt32Array()
	cells.resize(width * height)
	cells.fill(N | E | S | W)

	start_cell = Vector2i(0, 0)
	exit_cell = Vector2i(width - 1, height - 1)

	_carve()
	_braid(braid_factor)
	_cull_shallow_dead_ends(shallow_keep)
	_tune_dead_ends(dead_end_target)
	# After both dead-end stages, because those open walls and so create new
	# corners; before the straight-run cap, because this one opens walls too and
	# the cap has to be the last word on corridor length.
	_cull_zigzags(zigzag_keep)
	# LAST of the wall-knocking stages. Both dead-end passes open walls, which
	# can merge corridors into a new over-long run, so capping before them
	# leaves runs over the limit in the finished maze (measured: no effect at
	# all when run earlier).
	_cap_straight_runs(MAX_STRAIGHT_CELLS)
	_build_distance_field()
	_build_solve_path()
	_place_gates(gate_count)
	# LAST, after every wall-knocking stage, for the same reason the straight-run
	# cap is: the dead-end passes open walls, so a cell that was a sealed pocket
	# or a dead end mid-pipeline may well not be one in the finished maze.
	_place_landmarks(landmark_density)


# --- Generation stages -------------------------------------------------------

# Iterative randomized DFS (recursive backtracker). Chosen over Prim's/Kruskal's
# because it produces long winding corridors, which suit a speed game far better
# than the short choppy ones those give (CLAUDE.md section 6).
#
# Iterative rather than recursive: a 90x90 maze is 8100 cells deep enough to
# blow GDScript's call stack.
func _carve() -> void:
	var visited := {}
	var stack: Array[Vector2i] = []

	# The direction used to arrive at each cell, so the carve can prefer to keep
	# going that way. A plain random DFS turns at nearly every cell -- measured
	# average straight run is ~1.6 cells -- which gives the player no room to
	# build speed or read a junction before reaching it.
	var arrival := {}

	stack.push_back(start_cell)
	visited[start_cell] = true

	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var unvisited: Array = []

		for dir in DIRS:
			var next: Vector2i = current + DIR_VECTORS[dir]
			if _in_bounds(next) and not visited.has(next):
				unvisited.append(dir)

		if unvisited.is_empty():
			stack.pop_back()
			continue

		var dir: int = -1

		# Bias toward continuing straight. Rolling against `_straighten` rather
		# than always going straight keeps the maze from degenerating into long
		# axis-aligned combs -- it lengthens runs without making them uniform.
		if _straighten > 0.0 and arrival.has(current):
			var forward: int = arrival[current]
			if unvisited.has(forward) and _rng.randf() < _straighten:
				dir = forward

		if dir == -1:
			dir = unvisited[_rng.randi_range(0, unvisited.size() - 1)]

		var neighbour: Vector2i = current + DIR_VECTORS[dir]

		_knock_wall(current, dir)
		visited[neighbour] = true
		arrival[neighbour] = dir
		stack.push_back(neighbour)


# Remove walls to create loops. A perfect maze has exactly one route between any
# two cells, which makes every wrong turn a mandatory backtrack; loops are what
# make "commit and route around" a real decision (CLAUDE.md section 6).
#
# Candidates are shuffled and taken in order rather than sampled at random, so
# the braid factor lands accurately instead of approximately.
func _braid(factor: float) -> void:
	if factor <= 0.0:
		return

	var candidates: Array = []
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			# Only look N and E: checking all four would visit each shared wall
			# twice and double-count the candidate pool.
			for dir in [N, E]:
				var neighbour: Vector2i = cell + DIR_VECTORS[dir]
				if _in_bounds(neighbour) and _has_wall(cell, dir):
					candidates.append([cell, dir])

	_shuffle(candidates)

	var target := int(candidates.size() * factor)
	for i in mini(target, candidates.size()):
		_knock_wall(candidates[i][0], candidates[i][1])


# Break up any corridor longer than `limit` cells by opening a side exit.
#
# A "straight run" here means what it means to the PLAYER: consecutive cells you
# travel through with no opening to either side, so there is nothing to read and
# no decision to make. A long corridor that has junctions along it is not a
# straight run -- it is a series of short ones -- so the walk below breaks a run
# at any cell that already offers a turn, not merely at a wall ahead.
#
# Runs both axes. Uses a fixed-point loop because opening a side exit can merge
# two previously separate corridors into one longer run in the OTHER axis, so a
# single pass is not enough to guarantee the bound.
func _cap_straight_runs(limit: int) -> void:
	if limit <= 0:
		return

	# Bounded rather than `while true`. Opening a side exit can MERGE two
	# corridors into a longer run in the other axis, so one pass does not
	# guarantee the bound and the loop has to re-check -- but it also means
	# "something changed" is not the same as "we got closer", and an unbounded
	# loop can spin. Four passes takes 60x60 to zero over-long runs in practice;
	# the bound is what keeps generation from stalling if one ever does not.
	for _pass in 4:
		if not _break_long_runs(limit):
			return


# One pass. Returns true if it opened anything.
#
# Tracks the run as a START INDEX plus a length rather than accumulating an
# array of cells. Building and clearing a typed array per run inside the inner
# loop is both slower and the thing that hung generation outright when this was
# first written -- the cell list is not needed anyway, since a run is contiguous
# and any position in it can be computed from the start index.
func _break_long_runs(limit: int) -> bool:
	var changed := false

	for axis in [true, false]:
		var run_dir: int = E if axis else S
		var sides: Array = [N, S] if axis else [E, W]
		var outer: int = height if axis else width
		var inner: int = width if axis else height

		for a in outer:
			var run_start := 0
			for b in inner:
				var cell := Vector2i(b, a) if axis else Vector2i(a, b)

				# The run ends where the player would stop going straight: a
				# wall ahead, or a side opening that makes this a junction.
				var has_side := false
				for d in sides:
					if is_open(cell, d):
						has_side = true
						break
				if not (has_side or not is_open(cell, run_dir)):
					continue

				var length := b - run_start + 1
				if length > limit and _punch_side(a, run_start, length, axis, sides, limit):
					changed = true
				run_start = b + 1

	return changed


# Open a side somewhere in the middle of an over-long run.
#
# Aims for the midpoint and walks outward, so the new junction lands where the
# corridor is dullest rather than immediately next to an existing one. Returns
# false when the run is boxed in on both sides for its whole length -- rare, but
# possible at the maze boundary, and the caller must not treat that as progress.
func _punch_side(lane: int, run_start: int, length: int, axis: bool,
		sides: Array, limit: int) -> bool:
	var mid := int(length / 2)
	var reach := int(limit / 2)

	for step in range(reach + 1):
		var deltas: Array = [0] if step == 0 else [-step, step]
		for delta in deltas:
			var i: int = mid + delta
			if i < 0 or i >= length:
				continue
			var b: int = run_start + i
			var cell := Vector2i(b, lane) if axis else Vector2i(lane, b)
			for dir in sides:
				var neighbour: Vector2i = cell + DIR_VECTORS[dir]
				if _in_bounds(neighbour) and _has_wall(cell, dir):
					_knock_wall(cell, dir)
					return true

	return false


# Remove a share of the SHALLOW dead ends -- one-cell stubs hanging directly off
# a junction, where the player turns in, travels a single cell, and must
# immediately 180 back out.
#
# This runs as its OWN stage, before density tuning, because the two are
# genuinely different knobs and making them share one budget does not work. The
# density target on maze 3 (324 cells) sits just under what carve-plus-braid
# leaves (337), so a shallow-first ordering inside _tune_dead_ends had only 13
# removals to spend and drained almost none of the 229 stubs. Culling first
# spends removals on the stubs specifically and lets density tuning take
# whatever is still over target afterwards.
#
# `keep` is the fraction of shallow dead ends left alone. Keeping some matters:
# at zero the maze reads as uniformly safe, and the occasional stub is what
# stops the player trusting every opening blindly. It is the FREQUENCY that was
# wrong, not the existence.
func _cull_shallow_dead_ends(keep: float) -> void:
	if keep >= 1.0:
		return

	var shallow: Array[Vector2i] = []
	for cell in _find_dead_ends():
		if _is_shallow_dead_end(cell):
			shallow.append(cell)

	_shuffle(shallow)

	var to_remove := int(shallow.size() * (1.0 - clampf(keep, 0.0, 1.0)))
	for i in to_remove:
		var cell: Vector2i = shallow[i]
		# Re-check: an earlier removal may have opened a neighbour and changed
		# this cell's status already.
		if open_directions(cell).size() != 1:
			continue
		var options: Array = []
		for dir in DIRS:
			var neighbour: Vector2i = cell + DIR_VECTORS[dir]
			if _in_bounds(neighbour) and _has_wall(cell, dir):
				options.append(dir)
		if not options.is_empty():
			_knock_wall(cell, options[_rng.randi_range(0, options.size() - 1)])


# Thin out CORNER-INTO-CORNER zigzags: a forced 90 whose exit leads straight
# into another forced 90, with no cell in between to read the second one.
#
# A corner is a cell with exactly two perpendicular openings -- you come in one
# side and the only way on is a turn. It is not a junction: a junction offers a
# CHOICE, which is the decision the game is built on, while a corner offers only
# an obligation. Chaining two obligations is the shape being thinned here.
#
# It is a timing problem, not a routing one, and it gets worse exactly as the
# ramp climbs. At 6x a cell passes in 167ms, so a zigzag demands two commits
# inside a third of a second with nothing straight between them to read the
# second from. That is the one thing CLAUDE.md section 11.3 forbids: the turn IS
# visible on the grid, but the player is still inside the freeze from the first
# turn when the second arrives. Long staircases are worse still -- measured, the
# unbiased mazes carried 300-500 chains of three or more per maze.
#
# The fix OPENS a wall rather than closing one, like every other stage in this
# pipeline: knocking the wall ahead of the second corner turns the forced turn
# into an optional one. The player may still take it; they are no longer made
# to. That is the important distinction -- this pass removes obligations, not
# corners, so the maze keeps its shape and loses only the coercion.
#
# `keep` is the fraction of zigzags left alone, and like `shallow_keep` it is
# NOT the share that survives: opening one wall can resolve a neighbouring
# zigzag at the same time, and it can create a fresh corner elsewhere. Measure
# with ZigzagProbe, never assume the number is the outcome.
func _cull_zigzags(keep: float) -> void:
	if keep >= 1.0:
		return

	var zigzags: Array[Vector2i] = []
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if _is_corner(cell) and _leads_into_corner(cell):
				zigzags.append(cell)

	_shuffle(zigzags)

	var to_remove := int(zigzags.size() * (1.0 - clampf(keep, 0.0, 1.0)))
	var removed := 0
	for cell in zigzags:
		if removed >= to_remove:
			break
		# Re-check: an earlier removal may have opened this cell or its
		# neighbour already, in which case there is nothing left to fix here.
		if not (_is_corner(cell) and _leads_into_corner(cell)):
			continue
		if _relieve_corner(cell):
			removed += 1


# Exactly two openings, perpendicular. A straight-through corridor and a
# junction are both excluded.
func _is_corner(cell: Vector2i) -> bool:
	var dirs := open_directions(cell)
	if dirs.size() != 2:
		return false
	return int(dirs[0]) != int(OPPOSITE[dirs[1]])


func _leads_into_corner(cell: Vector2i) -> bool:
	for dir in open_directions(cell):
		if _is_corner(cell + DIR_VECTORS[dir]):
			return true
	return false


# Give a corner a third opening, so arriving from either side leaves a straight
# option instead of a mandatory turn.
#
# Prefers the wall OPPOSITE an existing opening, since that is what actually
# relieves the obligation -- opening the fourth side of a corner adds a route
# but still leaves both approaches forced to turn. Falls back to any available
# wall, and returns false when the cell is boxed in by the boundary, which the
# caller must not count as progress.
func _relieve_corner(cell: Vector2i) -> bool:
	var straight: Array = []
	var other: Array = []

	for dir in DIRS:
		var neighbour: Vector2i = cell + DIR_VECTORS[dir]
		if not _in_bounds(neighbour) or not _has_wall(cell, dir):
			continue
		if is_open(cell, OPPOSITE[dir]):
			straight.append(dir)
		else:
			other.append(dir)

	var options: Array = straight if not straight.is_empty() else other
	if options.is_empty():
		return false

	_knock_wall(cell, options[_rng.randi_range(0, options.size() - 1)])
	return true


# Nudge dead-end density toward a target. Dead ends are the punishment for a
# misread -- each costs a 180 -- so their count is a difficulty knob independent
# of size and loop density.
#
# Only removal is implemented: carve-plus-braid always overshoots the targets in
# CLAUDE.md section 8, so there is never a shortfall to fill.
#
# SHALLOW dead ends are removed first. A shallow dead end is one whose single
# opening leads straight back to a junction -- so the player turns in, travels
# one cell, and must immediately 180 back out. That is the least interesting
# punishment the maze can deliver: there is no route to misread and no decision
# to get wrong, just a one-cell stub that costs a reversal. Measured on the
# stock parameters, they were the MAJORITY of dead ends in mazes 2 and 3 (212 of
# 316, and 247 of 348), which made the reverse the most common thing a player
# did. A deeper dead end at least represents a wrong route commitment, which is
# the decision section 11.2 wants the maze punishing.
func _tune_dead_ends(target_ratio: float) -> void:
	var dead_ends := _find_dead_ends()
	var target := int(width * height * target_ratio)

	if dead_ends.size() <= target:
		return

	_shuffle(dead_ends)

	# Stable partition: shuffled within each group, so removal stays seeded and
	# reproducible while still draining the shallow ones first.
	var shallow: Array[Vector2i] = []
	var deep: Array[Vector2i] = []
	for cell in dead_ends:
		if _is_shallow_dead_end(cell):
			shallow.append(cell)
		else:
			deep.append(cell)

	var ordered: Array[Vector2i] = shallow
	ordered.append_array(deep)

	var to_remove := ordered.size() - target
	for i in to_remove:
		var cell: Vector2i = ordered[i]
		# Open a second side so the cell stops being a dead end.
		var options: Array = []
		for dir in DIRS:
			var neighbour: Vector2i = cell + DIR_VECTORS[dir]
			if _in_bounds(neighbour) and _has_wall(cell, dir):
				options.append(dir)
		if not options.is_empty():
			_knock_wall(cell, options[_rng.randi_range(0, options.size() - 1)])


# A dead end whose only exit leads directly to a junction: one cell in, 180 out,
# with no route decision in between.
func _is_shallow_dead_end(cell: Vector2i) -> bool:
	var dirs := open_directions(cell)
	if dirs.size() != 1:
		return false
	var back: Vector2i = cell + DIR_VECTORS[dirs[0]]
	return open_directions(back).size() >= 3


# BFS from the exit across the whole grid. Storing distance for EVERY cell (not
# just the solve path) is what lets the Path Indicator stay correct when the
# player is off the canonical route -- which in a braided maze is constant, and
# often correct play (CLAUDE.md section 6).
func _build_distance_field() -> void:
	distance_field = PackedInt32Array()
	distance_field.resize(width * height)
	distance_field.fill(-1)

	var queue: Array[Vector2i] = [exit_cell]
	_set_distance(exit_cell, 0)
	var head := 0

	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var d := get_distance(current)

		for dir in DIRS:
			if _has_wall(current, dir):
				continue
			var neighbour: Vector2i = current + DIR_VECTORS[dir]
			if not _in_bounds(neighbour):
				continue
			if get_distance(neighbour) != -1:
				continue
			_set_distance(neighbour, d + 1)
			queue.push_back(neighbour)


# Walk the distance field downhill from the start. This is the canonical route
# and the shortest one, since the field is a BFS result.
func _build_solve_path() -> void:
	solve_path.clear()

	if get_distance(start_cell) == -1:
		push_error("Maze: exit unreachable from start -- generation is broken")
		return

	var current := start_cell
	solve_path.append(current)

	while current != exit_cell:
		var best := current
		var best_distance := get_distance(current)

		for dir in DIRS:
			if _has_wall(current, dir):
				continue
			var neighbour: Vector2i = current + DIR_VECTORS[dir]
			if not _in_bounds(neighbour):
				continue
			var d := get_distance(neighbour)
			if d != -1 and d < best_distance:
				best_distance = d
				best = neighbour

		if best == current:
			push_error("Maze: solve path stalled at %s" % current)
			return

		current = best
		solve_path.append(current)


# Gates sit on the canonical solve path so that collecting them IS engagement
# with the maze (CLAUDE.md section 7). Spaced evenly, never on start or exit.
func _place_gates(count: int) -> void:
	gates.clear()
	if count <= 0 or solve_path.size() < count + 2:
		return

	var step := float(solve_path.size()) / float(count + 1)
	for i in range(1, count + 1):
		var index := int(step * i)
		index = clampi(index, 1, solve_path.size() - 2)
		gates.append(solve_path[index])


# --- Landmarks (docs/specs/landmarks.md) -------------------------------------

# Decorative structures that make a corridor recognisable.
#
# PLACEMENT IGNORES THE SOLVE PATH, THE DISTANCE FIELD, THE GATES AND THE EXIT.
# That is the whole safety argument for the feature: a landmark says "you have
# been here", never "go this way", so it cannot substitute for Path Indicator,
# Gate Compass or Golden Trail. Nothing here may start consulting
# `distance_field` or `solve_path` -- if a first-time player gains anything from
# a landmark before passing it once, this function is wrong.
#
# Landmarks occupy a whole cell and are never collided with -- the barrier and
# crash rules are defined against maze WALLS only (section 5), and a second
# class of solid thing would mean two collision systems disagreeing at speed. So
# they go only where the player cannot drive through them:
#
#   - sealed pockets: fully-walled leftover cells, glimpsed from outside
#   - dead ends: pushed against the far wall, past where the player stops
#   - outside the boundary: skyline tier only, giving the maze an exterior
func _place_landmarks(density: float) -> void:
	landmarks.clear()
	if density <= 0.0:
		return

	var interior: Array[Vector2i] = []
	var anchors := {}

	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if cell == start_cell or cell == exit_cell:
				continue
			if gates.has(cell):
				continue

			var open: Array = open_directions(cell)
			if open.is_empty():
				# A sealed pocket. Centred, since it is seen from outside.
				interior.append(cell)
				anchors[cell] = Vector2.ZERO
			elif open.size() == 1:
				# A dead end. The player drives in and stops against the end
				# wall, so a landmark on the cell centre is geometry the marker
				# visibly drives through. Push it to the back -- it becomes the
				# thing BEYOND the stopping point, which is both correct and the
				# better image.
				var back: Vector2i = -DIR_VECTORS[open[0]]
				interior.append(cell)
				anchors[cell] = Vector2(back.x, back.y) * 0.28

	_shuffle_decor(interior)

	var count := int(interior.size() * clampf(density, 0.0, 1.0))
	for i in count:
		var cell: Vector2i = interior[i]
		landmarks.append(_make_landmark(cell, anchors[cell], _pick_interior_type()))

	_place_exterior_landmarks()


# Which type an INTERIOR landmark gets, biased toward the local tier.
#
# A uniform draw over the type table looks balanced and is not, because the
# exterior ring is skyline-only and lands on top of it -- measured, that pushed
# the finished maze to ~2/3 skyline. Skyline landmarks answer "which REGION am I
# in", which is the coarse read; the local tier is what distinguishes two
# adjacent T-junctions from each other, and that is the finer and more useful
# half of the feature (docs/specs/landmarks.md section 3).
#
# Biasing here rather than by adding local types keeps the vocabulary small.
# Six shapes is already near the limit of what a player can learn to tell apart
# at speed through fog.
func _pick_interior_type() -> int:
	var want_skyline := _decor_rng.randf() < 0.35

	var candidates: Array[int] = []
	for i in Tuning.LANDMARK_TYPES.size():
		if bool(Tuning.LANDMARK_TYPES[i]["skyline"]) == want_skyline:
			candidates.append(i)

	if candidates.is_empty():
		return _decor_rng.randi_range(0, Tuning.LANDMARK_TYPES.size() - 1)
	return candidates[_decor_rng.randi_range(0, candidates.size() - 1)]


# A ring of skyline landmarks beyond the outer wall, so the maze has an exterior
# rather than ending in fog at the boundary.
#
# Skyline tier ONLY: a local landmark out here sits below the boundary wall and
# would never be seen at all.
func _place_exterior_landmarks() -> void:
	var skyline: Array[int] = []
	for i in Tuning.LANDMARK_TYPES.size():
		if bool(Tuning.LANDMARK_TYPES[i]["skyline"]):
			skyline.append(i)
	if skyline.is_empty():
		return

	var centre := Vector2(width - 1, height - 1) * 0.5
	# Half the diagonal, so the ring clears a rectangular maze on every side.
	var radius := centre.length()

	for i in Tuning.LANDMARK_EXTERIOR_COUNT:
		# Even angular spacing with a jitter, so the ring does not read as a
		# clock face while still never clumping.
		var slice := TAU / float(Tuning.LANDMARK_EXTERIOR_COUNT)
		var angle := slice * i + _decor_rng.randf_range(-slice * 0.35, slice * 0.35)
		var out := radius + _decor_rng.randf_range(
			Tuning.LANDMARK_EXTERIOR_MIN_CELLS, Tuning.LANDMARK_EXTERIOR_MAX_CELLS)

		var at := centre + Vector2(cos(angle), sin(angle)) * out
		var type_index: int = skyline[_decor_rng.randi_range(0, skyline.size() - 1)]
		# Rounded to a cell so exterior entries look like every other landmark;
		# the fractional part rides in `anchor`, which the mesh adds back.
		var cell := Vector2i(roundi(at.x), roundi(at.y))
		landmarks.append(_make_landmark(
			cell, at - Vector2(cell.x, cell.y), type_index, 1.35))


func _make_landmark(cell: Vector2i, anchor: Vector2, type_index: int,
		scale_bias: float = 1.0) -> Dictionary:
	return {
		"cell": cell,
		"type": type_index,
		# Free rotation. Every type is built axis-aligned, so without this a
		# field of them lines up like a parade and stops reading as scenery.
		"yaw": _decor_rng.randf_range(0.0, TAU),
		"scale": scale_bias * _decor_rng.randf_range(0.85, 1.2),
		"anchor": anchor,
	}


# Fisher-Yates against the DECOR stream, so shuffling the candidate list cannot
# perturb the carve. Mirrors _shuffle, deliberately rather than sharing it.
func _shuffle_decor(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _decor_rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp


# --- Queries -----------------------------------------------------------------

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func _has_wall(cell: Vector2i, dir: int) -> bool:
	return (cells[_index(cell)] & dir) != 0


# Is the given side of this cell open to walk through?
func is_open(cell: Vector2i, dir: int) -> bool:
	if not _in_bounds(cell):
		return false
	if _has_wall(cell, dir):
		return false
	return _in_bounds(cell + DIR_VECTORS[dir])


func get_distance(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return -1
	return distance_field[_index(cell)]


# The direction from this cell that moves closest to the exit. Recomputed live
# from the distance field, so it stays correct well off the canonical path.
# Returns -1 if there is no improving move.
func best_direction(cell: Vector2i) -> int:
	var current_distance := get_distance(cell)
	if current_distance <= 0:
		return -1

	var best_dir := -1
	var best_distance := current_distance

	for dir in DIRS:
		if not is_open(cell, dir):
			continue
		var d := get_distance(cell + DIR_VECTORS[dir])
		if d != -1 and d < best_distance:
			best_distance = d
			best_dir = dir

	return best_dir


# The next `max_cells` cells along the distance-descending route from `cell`.
#
# Follows best_direction() repeatedly, which is the same live read the Path
# Indicator uses -- so in a looped maze it tracks whatever is actually optimal
# from where the player is standing, not a baked canonical path they may have
# left three junctions ago (CLAUDE.md section 6).
#
# Stops early at the exit or wherever no improving move exists. The returned
# array starts with `cell` itself, so a route of length 1 means "nowhere to go".
func route_from(cell: Vector2i, max_cells: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if max_cells <= 0 or not _in_bounds(cell):
		return path

	var current := cell
	path.append(current)

	for _i in max_cells:
		if current == exit_cell:
			break
		var dir := best_direction(current)
		if dir == -1:
			break
		current = current + DIR_VECTORS[dir]
		path.append(current)

	return path


func open_directions(cell: Vector2i) -> Array:
	var result: Array = []
	for dir in DIRS:
		if is_open(cell, dir):
			result.append(dir)
	return result


func is_junction(cell: Vector2i) -> bool:
	return open_directions(cell).size() > 2


func _find_dead_ends() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if cell == start_cell or cell == exit_cell:
				continue
			if open_directions(cell).size() == 1:
				result.append(cell)
	return result


func dead_end_count() -> int:
	return _find_dead_ends().size()


# Openings beyond a perfect maze. A perfect maze on W*H cells has exactly
# W*H-1 openings; every one above that closes a loop.
func loop_count() -> int:
	var openings := 0
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			for dir in [N, E]:
				if is_open(cell, dir):
					openings += 1
	return openings - (width * height - 1)


# --- Mutation ----------------------------------------------------------------

func _knock_wall(cell: Vector2i, dir: int) -> void:
	var neighbour: Vector2i = cell + DIR_VECTORS[dir]
	if not _in_bounds(neighbour):
		return
	cells[_index(cell)] &= ~dir
	cells[_index(neighbour)] &= ~int(OPPOSITE[dir])


func _set_distance(cell: Vector2i, value: int) -> void:
	distance_field[_index(cell)] = value


# Allocate an empty distance field for a hand-built fixture whose exit is
# deliberately out of bounds. Only the test harness uses this -- generation
# always goes through _build_distance_field().
func _build_distance_field_for_tests() -> void:
	distance_field = PackedInt32Array()
	distance_field.resize(width * height)
	distance_field.fill(-1)
	solve_path.clear()


# Fisher-Yates against the seeded RNG. Array.shuffle() uses the global RNG and
# would break reproducibility.
func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp
