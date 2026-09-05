# Headless harness for the pure rule set: generation, distance field, turn and
# buffer resolution, barrier, penalties, upgrades.
#
# Everything here runs with no rendered frame. If a rule needs the renderer to
# test, the rule is in the wrong place (CLAUDE.md section 12).
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== RulesTest ===")

	_test_generation()
	_test_distance_field()
	_test_braiding()
	_test_zigzag_cull()
	_test_seeding()
	_test_turn_resolution()
	_test_double_tap()
	_test_buffer_expiry()
	_test_barrier_grace()
	_test_crash_and_unstick()
	_test_reverse()
	_test_speed_ramp()
	_test_upgrades()
	_test_hp_regen_and_death()
	_test_score()
	_test_visited_cells()
	_test_trail_memory()
	_test_seeded_boards()
	_test_legendaries()
	_test_gates()
	_test_indicator()
	_test_branch_quality()
	_test_golden_trail()
	_test_wall_position()
	_test_lanes()
	_test_turn_keeps_progress()
	_test_last_cell_before_a_wall()
	_test_entry_corridor_lockout()
	_test_turn_freeze()
	_test_marker_heights()
	_test_landmarks()
	_test_landmarks_do_not_move_the_racer()
	_test_quadrants()
	_test_cardinal_compass()
	_test_quadrant_upgrades()

	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


# The quadrant box and the cardinal compass (CLAUDE.md section 7).
#
# Two properties matter far more than the arithmetic. First, the NUMBERING
# PROMISE: quadrant 1 holds the start and the highest holds the exit, which the
# card text states outright and the player reads their progress from. Second,
# the SEPARATION: a quadrant number is position, never direction, so it must be
# derivable with the distance field, the solve path and the openings all
# ignored -- that is what keeps this clear of the three paid route lines.
func _test_quadrants() -> void:
	var m := _make_maze(60, 60)

	# The promise, at every rank the line offers. Asserted across the whole
	# table rather than at one division count, because the numbering is derived
	# per-axis and an off-by-one in the flip would be correct at 2 and wrong at
	# 3 -- a single sample of a curve says nothing about the curve.
	for r in range(1, Tuning.QUADRANT_DIVISIONS_BY_RANK.size()):
		var d: int = Tuning.QUADRANT_DIVISIONS_BY_RANK[r]
		var total := m.quadrant_count(d)
		check_eq("rank %d gives %d regions" % [r, d * d], total, d * d)
		check_eq("rank %d: start is quadrant 1" % r,
			m.quadrant_of(m.start_cell, d), 1)
		check_eq("rank %d: exit is the highest quadrant" % r,
			m.quadrant_of(m.exit_cell, d), total)
		check_eq("rank %d: start sits at grid origin" % r,
			m.quadrant_coord(m.start_cell, d), Vector2i(0, 0))
		check_eq("rank %d: exit sits at the far corner" % r,
			m.quadrant_coord(m.exit_cell, d), Vector2i(d - 1, d - 1))

	# Every cell must land in a real region. A cell falling outside would draw
	# the highlight off the box, or nowhere at all.
	var out_of_range := 0
	var coord_out := 0
	for y in m.height:
		for x in m.width:
			var n := m.quadrant_of(Vector2i(x, y), 4)
			if n < 1 or n > 16:
				out_of_range += 1
			var c := m.quadrant_coord(Vector2i(x, y), 4)
			if c.x < 0 or c.x > 3 or c.y < 0 or c.y > 3:
				coord_out += 1
	check_eq("every cell has a quadrant", out_of_range, 0)
	check_eq("every cell has a grid coord", coord_out, 0)

	# The number and the coordinate are two views of one answer, so they must
	# agree everywhere -- the renderer lights the coord and the readout prints
	# the number, and a player seeing "6 of 16" beside a lit cell 7 would be
	# reading two accounts of the same fact.
	var disagreed := 0
	for y in m.height:
		for x in m.width:
			var c := m.quadrant_coord(Vector2i(x, y), 3)
			if c.y * 3 + c.x + 1 != m.quadrant_of(Vector2i(x, y), 3):
				disagreed += 1
	check_eq("number and coord agree", disagreed, 0)

	# Regions are contiguous bands: moving one cell can never skip a region.
	# A band computed by rounding rather than by integer division would jump.
	var jumped := 0
	for y in m.height:
		for x in range(m.width - 1):
			var a := m.quadrant_coord(Vector2i(x, y), 4)
			var b := m.quadrant_coord(Vector2i(x + 1, y), 4)
			if absi(b.x - a.x) > 1 or b.y != a.y:
				jumped += 1
	check_eq("bands are contiguous across x", jumped, 0)

	# Bad input is refused rather than clamped into a lie: 0 divisions is the
	# untaken line, and a caller that forgot to check has_quadrant() must get an
	# obvious zero rather than a plausible "quadrant 1".
	check_eq("zero divisions has no regions", m.quadrant_count(0), 0)
	check_eq("zero divisions has no quadrant", m.quadrant_of(m.start_cell, 0), 0)
	check_eq("out of bounds has no quadrant",
		m.quadrant_of(Vector2i(-1, -1), 4), 0)
	check_eq("out of bounds has no coord",
		m.quadrant_coord(Vector2i(999, 999), 4), Vector2i(-1, -1))

	# THE SEPARATION. A quadrant number is a statement about POSITION, so two
	# mazes that differ in every wall must still agree on it -- if the number
	# tracked the route at all, a different carve would move it. Same shape as
	# the landmark separation check: assert the thing that must NOT influence
	# the answer, since it is reachable and must never be used.
	var other := _make_maze(60, 60, 0.30)
	var differed := 0
	var walls_differ := false
	for y in m.height:
		for x in m.width:
			var cell := Vector2i(x, y)
			if m.quadrant_of(cell, 4) != other.quadrant_of(cell, 4):
				differed += 1
			if m.get_distance(cell) != other.get_distance(cell):
				walls_differ = true
	check("the two mazes really do differ", walls_differ)
	check_eq("quadrant ignores the maze routing", differed, 0)


# The Compass reports the direction the player FACES, in real cardinal terms.
#
# The exit is south-east, and the compass is not allowed to pretend otherwise --
# a relabelling that made the exit read north would turn an orientation readout
# into a second route hint. Asserted against the direction VECTORS rather than
# against a table of letters, so this checks the naming is consistent with the
# geometry rather than transcribing one constant into another.
func _test_cardinal_compass() -> void:
	check_eq("north is -Y", Maze.DIR_VECTORS[Maze.N], Vector2i(0, -1))
	check_eq("north is called N", Maze.cardinal_name(Maze.N), "N")
	check_eq("east is called E", Maze.cardinal_name(Maze.E), "E")
	check_eq("south is called S", Maze.cardinal_name(Maze.S), "S")
	check_eq("west is called W", Maze.cardinal_name(Maze.W), "W")

	# Opposite directions must never share a name.
	var clashes := 0
	for dir in Maze.DIRS:
		if Maze.cardinal_name(dir) == Maze.cardinal_name(Maze.OPPOSITE[dir]):
			clashes += 1
	check_eq("opposites have different names", clashes, 0)

	# The exit really is south and east of the start, which is the fact the card
	# text tells the player. Read off the two cells rather than restated, so a
	# generator that moved either one fails here instead of leaving the card
	# quietly wrong.
	var m := _make_maze(40, 40)
	check("exit is south of start", m.exit_cell.y > m.start_cell.y)
	check("exit is east of start", m.exit_cell.x > m.start_cell.x)


# Both lines are ordinary picks: they must be offerable, cap correctly, and
# never be mistaken for the rare tier.
func _test_quadrant_upgrades() -> void:
	var u := Upgrades.new(1)

	check_eq("quadrant starts untaken", u.rank(Upgrades.Line.QUADRANT), 0)
	check("no box without the line", not u.has_quadrant())
	check_eq("untaken quadrant has no divisions", u.quadrant_divisions(), 0)
	check("no compass without the line", not u.has_cardinal_compass())

	for i in 3:
		u.take(Upgrades.Line.QUADRANT)
	check_eq("quadrant caps at rank 3", u.rank(Upgrades.Line.QUADRANT), 3)
	check_eq("rank 3 divides by 4", u.quadrant_divisions(), 4)
	check("quadrant is not legendary", not u.is_legendary(Upgrades.Line.QUADRANT))

	# Divisions rise with rank and never repeat: a rank that bought the same
	# grid as the one before it would be a card offering nothing.
	var seen := {}
	var previous := 0
	var rises := true
	for r in range(1, Tuning.QUADRANT_DIVISIONS_BY_RANK.size()):
		var d: int = Tuning.QUADRANT_DIVISIONS_BY_RANK[r]
		if d <= previous:
			rises = false
		previous = d
		seen[d] = true
	check("divisions rise with every rank", rises)
	check_eq("every rank is a distinct grid", seen.size(),
		Tuning.QUADRANT_DIVISIONS_BY_RANK.size() - 1)

	u.take(Upgrades.Line.COMPASS)
	check("compass reads after one rank", u.has_cardinal_compass())
	check("compass maxes at one rank", u.is_maxed(Upgrades.Line.COMPASS))
	check("compass is distinct from gate compass",
		Upgrades.Line.COMPASS != Upgrades.Line.GATE_COMPASS)

	# Every rank must offer a card that says something. An empty description is
	# a blank card the player cannot evaluate.
	var blank := 0
	for line in [Upgrades.Line.QUADRANT, Upgrades.Line.COMPASS]:
		var fresh := Upgrades.new(2)
		for r in int(Upgrades.DEFINITIONS[line]["max_rank"]):
			if fresh.next_rank_description(line).strip_edges() == "":
				blank += 1
			fresh.take(line)
	check_eq("every rank has card text", blank, 0)


# Lanes are a DISPLAY offset and must never leak into the rules.
#
# The whole reason lanes are safe to add is that `cell`, `progress`, facing and
# every penalty stay on the corridor centre line -- that is what keeps the
# simulation headlessly testable (CLAUDE.md section 12). This asserts the
# separation directly, because a lane value that started influencing movement
# would be invisible in every other test.
func _test_lanes() -> void:
	var r := _make_racer(_make_room(9, 9))

	check_near("starts centred", r.lane, 0.0)

	var before_cell := r.cell
	var before_progress := r.progress
	r.request_turn(-1)

	# The kick sets lane_target; `lane` EASES toward it rather than snapping, so
	# the assertion has to let a little time pass before reading the position.
	# Reading `lane` in the same call as the turn tested the old instant step and
	# would now fail on a change that is working exactly as intended -- the kick
	# is an arc with weight, and an arc is not observable in zero time.
	check("a turn aims the lane off centre", absf(r.lane_target) > 0.5,
		"lane_target %.2f" % r.lane_target)

	# The turn itself is what must not touch cell or progress -- that is the
	# separation being asserted. Checked HERE, before any time is stepped,
	# because the frames needed to observe the lane easing legitimately advance
	# progress down the corridor; folding them in first would make this assert
	# that the racer does not move, which is not the claim.
	check_eq("the kick did not move the racer's cell", r.cell, before_cell)
	check_near("the kick did not move progress", r.progress, before_progress)

	for _i in range(12):
		r.step(1.0 / 60.0)
	check("a turn kicks the lane off centre", absf(r.lane) > 0.5,
		"lane %.2f" % r.lane)

	# Travel since the turn stays on the corridor centre line: lane moved, and
	# the RULES still did not notice.
	check_eq("easing the lane did not move the racer's cell", r.cell, before_cell)
	check("the kick is toward the OUTSIDE of the turn", r.lane > 0.0,
		"turning left should throw right of the new heading, got %.2f" % r.lane)
	# The offset shows up in the rendered position, perpendicular to travel.
	var centred := Vector3(
		float(r.cell.x) * Tuning.CELL_SIZE, Tuning.EYE_HEIGHT,
		float(r.cell.y) * Tuning.CELL_SIZE)
	var actual := r.world_position()
	var v: Vector2i = Maze.DIR_VECTORS[r.facing]
	var fwd := Vector3(float(v.x), 0.0, float(v.y))
	var lateral := (actual - centred).dot(Vector3(-fwd.z, 0.0, fwd.x))
	check("lane shifts the world position sideways", absf(lateral) > 0.1,
		"lateral offset %.3f" % lateral)

	# And it never leaves the corridor.
	var max_offset: float = float(Tuning.LANE_MAX) * Tuning.LANE_SPACING
	check("the outermost lane stays inside the corridor",
		max_offset + Tuning.MARKER_RADIUS < Tuning.CELL_SIZE * 0.5,
		"offset %.2f + radius %.2f vs half-cell %.2f"
			% [max_offset, Tuning.MARKER_RADIUS, Tuning.CELL_SIZE * 0.5])

	# Settle it, with no further input.
	for i in 300:
		r.step(0.02)
		if is_equal_approx(r.lane, roundf(r.lane)):
			break
	# The lane settles onto a whole lane LINE and holds there -- it no longer
	# drifts back to the centre. Pulling the racer back to the middle meant the
	# corridor was constantly moving them sideways out from under the player,
	# to a position they never chose.
	check_near("lane settles on a whole lane line", r.lane, roundf(r.lane))
	check("lane holds its line instead of returning to centre",
		absf(r.lane) > 0.5, "lane drifted to %.2f" % r.lane)


# Trail Memory: the per-cell record behind the floor tint and the map tint.
#
# Pure logic on purpose. The renderer reads this; it never computes it -- which
# is what keeps the rule headlessly testable (CLAUDE.md section 12) and what
# lets the floor and the minimap agree by construction rather than by two
# implementations happening to match.
func _test_trail_memory() -> void:
	var t := TrailMemory.new()

	# An untouched cell is not merely at zero visits, it is ABSENT. The
	# difference matters to the renderer: absent means "draw nothing", zero
	# would mean "draw the untrodden tint", and at maze 5 that is 10,000 cells
	# of nothing being drawn.
	check("an undriven cell is unknown", not t.has(Vector2i(3, 4)))
	check_eq("an undriven cell reads zero visits", t.visits(Vector2i(3, 4)), 0)

	t.visit(Vector2i(3, 4), 0.0)
	check("a driven cell is known", t.has(Vector2i(3, 4)))
	check_eq("one drive is one visit", t.visits(Vector2i(3, 4)), 1)

	# Re-crossing counts. This is the whole "darker with repeats" rule.
	t.visit(Vector2i(3, 4), 1.0)
	t.visit(Vector2i(3, 4), 2.0)
	check_eq("re-crossing accumulates", t.visits(Vector2i(3, 4)), 3)

	# Intensity: full while the window has time left, decaying to nothing across
	# the final TRAIL_FADE seconds. A cell that snapped off at its deadline
	# would blink out on its own, which reads as a rendering glitch rather than
	# as memory.
	var window := 60.0
	check_near("fresh ground is fully lit", t.intensity(Vector2i(3, 4), 2.0, window), 1.0)

	var mid := 2.0 + window - Tuning.TRAIL_FADE * 0.5
	check_near("half through the fade is half lit",
		t.intensity(Vector2i(3, 4), mid, window), 0.5, 0.01)

	check_near("past the window it is gone",
		t.intensity(Vector2i(3, 4), 2.0 + window + 1.0, window), 0.0)

	# The COUNT expires with the cell, not just the drawing. A cell looped four
	# times and then left alone reads as never driven -- the window is the whole
	# rule, which is what makes the infinite rank a difference in what is KNOWN
	# rather than only in what is shown.
	t.expire(2.0 + window + 1.0, window)
	check("a lapsed cell is forgotten", not t.has(Vector2i(3, 4)))
	check_eq("a lapsed cell's count resets", t.visits(Vector2i(3, 4)), 0)

	# An infinite window never expires. Passed as a negative, which is the
	# sentinel the rank table uses -- a huge float would work until someone ran
	# a long enough session, and 0.0 would be indistinguishable from "no memory".
	var inf_mem := TrailMemory.new()
	inf_mem.visit(Vector2i(1, 1), 0.0)
	inf_mem.expire(100000.0, Tuning.TRAIL_WINDOW_INFINITE)
	check("an infinite window never forgets", inf_mem.has(Vector2i(1, 1)))
	check_near("an infinite window stays fully lit",
		inf_mem.intensity(Vector2i(1, 1), 100000.0, Tuning.TRAIL_WINDOW_INFINITE), 1.0)

	# clear() is the per-maze reset. A trail carried into maze 2 would draw
	# maze 1's route onto a different grid -- the same stale-state trap section
	# 12 records for gates_cleared.
	inf_mem.clear()
	check_eq("clear empties the record", inf_mem.count(), 0)


# --- Assertions --------------------------------------------------------------

func check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func check_eq(label: String, actual, expected) -> void:
	check(label, actual == expected, "got %s, expected %s" % [actual, expected])


func check_near(label: String, actual: float, expected: float, tol: float = 0.001) -> void:
	check(label, absf(actual - expected) <= tol, "got %f, expected %f" % [actual, expected])


# --- Signal recording --------------------------------------------------------

# GDScript lambdas capture locals BY VALUE, so `var hit := false;
# sig.connect(func(): hit = true)` silently never updates `hit` -- the lambda
# mutates its own copy. Every signal assertion goes through this recorder
# instead, which holds state on an object and therefore actually observes it.
class SignalRecorder extends RefCounted:
	var count := 0
	var last_arg = null
	var last_two = null

	func on_signal() -> void:
		count += 1

	func on_signal_arg(arg) -> void:
		count += 1
		last_arg = arg

	# wall_smashed carries (cell, direction); a one-arg handler cannot bind it.
	func on_signal_two(a, b) -> void:
		count += 1
		last_arg = a
		last_two = b

	func fired() -> bool:
		return count > 0


func record(sig: Signal) -> SignalRecorder:
	var rec := SignalRecorder.new()
	sig.connect(rec.on_signal)
	return rec


func record_arg(sig: Signal) -> SignalRecorder:
	var rec := SignalRecorder.new()
	sig.connect(rec.on_signal_arg)
	return rec


# The cell in front of a wall must be DRIVEN THROUGH, not skipped.
#
# Entering a blocked cell used to press into the wall on the same frame, which
# pinned progress to the wall face and teleported the marker most of a cell in a
# single step -- then held it motionless there while the barrier drained into a
# crash. In play: "I get into the last cell before a wall, it freezes, jumps to
# the wall and I crash there, with no movement in the last cell."
#
# Two separate paths did it, and both are asserted here by simply driving: the
# boundary handler in _travel(), and step()'s own dispatch, which sent any racer
# in a blocked cell straight to _press_into_wall regardless of how far into the
# cell it had actually got.
#
# It was MASKED before progress was centred. The cell used to advance at the
# centre, so a racer entering a blocked cell was already half way across it and
# only half a cell of travel went missing. Crossing at the drawn line is correct
# and made the whole cell's worth visible -- so this is a regression test for the
# phase change as much as for the wall.
func _test_last_cell_before_a_wall() -> void:
	var m := _make_corridor(5)
	var r := _make_racer(m)
	r.cell = Vector2i(3, 0)
	r.facing = Maze.E
	r.progress = 0.0

	# Drive until the racer is pinned, recording the largest single-frame jump.
	var last_pos := r.world_position()
	var biggest := 0.0
	var frames_in_last := 0
	var entered := false
	var step := 1.0 / 60.0

	for i in 400:
		r.step(step)
		var pos := r.world_position()
		var moved: float = (pos - last_pos).length()
		last_pos = pos
		if r.cell == Vector2i(4, 0):
			if not entered:
				entered = true
			else:
				# Ignore the entry frame itself: it legitimately spans a
				# boundary. Every frame AFTER it is ordinary travel.
				biggest = maxf(biggest, moved)
				if not r.scraping and r.state == Racer.State.RUNNING:
					frames_in_last += 1
		if r.state == Racer.State.PARKED:
			break

	check("reached the cell in front of the wall", entered)

	# One frame of travel at the speed floor. Anything approaching a cell is a
	# teleport -- the bug moved the marker ~3.4m in a single frame.
	var per_frame: float = Tuning.BASE_CELL_RATE * Tuning.CELL_SIZE * step
	check("no frame jumps across the cell", biggest < per_frame * 3.0,
		"largest single-frame move %.3fm vs %.3fm expected" % [biggest, per_frame])

	# And the cell is actually crossed rather than skipped. At the speed floor a
	# cell is a second of travel, so this is dozens of frames, not one or two.
	check("the last cell is driven through, not skipped", frames_in_last > 20,
		"%d moving frames in the last cell" % frames_in_last)

	# The wall must still stop the racer, and still crash it.
	check("the wall still stops the racer", r.state == Racer.State.PARKED)


# A turn must PIVOT, not rewind.
#
# Turning used to reset progress to 0, which yanked the racer back to the centre
# of a cell it had already half-crossed -- read in play as "I reached the new
# grid line, turned, and it jumped me back to an old one and I missed my turn".
# The racer is at a real point in the corridor; turning is a rotation, and the
# distance already covered still counts toward the next boundary.
func _test_turn_keeps_progress() -> void:
	var r := _make_racer(_make_room(9, 9))

	# Get well into a cell without crossing its far boundary.
	#
	# Progress is centred on the cell centre and runs -0.5..+0.5, the two drawn
	# grid lines. So "inside the cell, not on a boundary" is |progress| < 0.5 --
	# it was `> 0.3 and < 1.0` when progress ran 0..1 between cell CENTRES. The
	# racer having moved at all is the separate half, and `_travel` is what would
	# break it.
	# Driven PAST the cell centre, so the distance covered is a real distance
	# along the corridor and the pivot must keep it. Progress is centred, so
	# "past the centre" is simply > 0.
	while r.progress <= 0.05 and r.cell == r.cell:
		r.step(0.05)
		if r.progress > 0.05:
			break
	var before := r.progress
	check("moved past the cell centre", before > 0.0 and before < 0.5,
		"progress %.3f" % before)

	var cell_before := r.cell
	r.request_turn(-1)

	check_near("a turn preserves progress", r.progress, before)
	check_eq("a turn does not change cell", r.cell, cell_before)

	# The other half of the rule, and it is NOT a rewind.
	#
	# Progress runs -0.5..+0.5 about the cell centre, so for the first half of
	# every cell it is NEGATIVE -- distance still to cover before the centre.
	# That number is measured along the OLD heading, and a pivot changes the
	# heading, so carrying it through would re-read it as that distance
	# BACKWARDS down the new corridor and draw the marker out through the side
	# wall. Measured: 1.949m off a cell centre whose corridor half-width is
	# 1.77m, which no camera position can see past -- it broke the "marker is
	# never hidden" rule on 20-40 of every 2000 autopilot frames.
	#
	# CLAUDE.md section 2 records the same trade for the scrape case and reaches
	# the same answer: the two distances are not the same point, and starting the
	# new corridor from the cell centre is the smaller, honest move.
	# The racer STARTS at a cell centre (progress 0), so it has to cross one
	# grid line before it is ever on the approach side of a cell.
	var r4 := _make_racer(_make_room(9, 9))
	var start4 := r4.cell
	var spin4 := 0
	while (r4.cell == start4 or r4.progress >= 0.0) and spin4 < 500:
		r4.step(0.01)
		spin4 += 1
	check("reached the approach side of a later cell", spin4 < 500)
	check("still short of the cell centre", r4.progress < 0.0,
		"progress %.3f" % r4.progress)
	r4.request_turn(-1)
	check("a turn on the way in starts the new corridor at the centre",
		is_equal_approx(r4.progress, 0.0), "progress %.3f" % r4.progress)


# After a turn, the corridor just left must not be immediately re-enterable.
#
# Otherwise a second press at a crossroads folds the racer straight back the way
# it came -- a 180 the player neither asked for nor paid for. A turn should
# always take the NEXT available opening.
#
# The 180 itself is exempt: going back IS what that input means.
# The post-turn freeze holds POSITION, not the speed ramp.
#
# Two separate claims, and getting either backwards breaks something real: a
# freeze that let travel continue would not buy the player the moment to read
# the new corridor that it exists for, and a freeze that stopped the ramp would
# make cornering a way to duck the game's central pressure (CLAUDE.md section 3).
func _test_turn_freeze() -> void:
	var r := _make_racer(_make_room(9, 9))

	r.step(0.2)
	r.request_turn(-1)
	check("a turn arms the freeze", r.freeze > 0.0, "freeze %.3f" % r.freeze)

	var cell_before := r.cell
	var progress_before := r.progress
	var speed_before := r.speed

	# Step less than the freeze window, so the whole step is spent frozen.
	var held := Tuning.TURN_FREEZE * 0.5
	r.step(held)

	check_eq("frozen: cell does not move", r.cell, cell_before)
	check_near("frozen: progress does not move", r.progress, progress_before)
	check("frozen: the speed ramp still runs", r.speed > speed_before,
		"%.4f -> %.4f" % [speed_before, r.speed])
	check_near("the freeze burns down with time", r.freeze,
		Tuning.TURN_FREEZE - held)

	# Past the window, travel resumes. The baseline is re-read HERE, not reused
	# from before the freeze: a turn preserves progress, so the pre-turn value is
	# still current and comparing against it asserts nothing about the freeze
	# having ended -- it just re-checks that the turn did not rewind.
	var frozen_cell := r.cell
	var frozen_progress := r.progress
	r.step(Tuning.TURN_FREEZE)
	check_near("the freeze expires", r.freeze, 0.0)
	check("travel resumes once the freeze ends",
		r.cell != frozen_cell or r.progress > frozen_progress,
		"progress %.3f -> %.3f" % [frozen_progress, r.progress])

	# Snap Turn shortens it but never removes it -- the freeze is what makes a
	# corner readable at speed, and a zero freeze hands the maxed build back the
	# unreadable pivot it exists to fix.
	var up := Upgrades.new(1)
	var base_freeze := up.turn_freeze()
	for _i in range(int(Upgrades.DEFINITIONS[Upgrades.Line.SNAP_TURN]["max_rank"])):
		up.take(Upgrades.Line.SNAP_TURN)
	check("Snap Turn shortens the freeze", up.turn_freeze() < base_freeze,
		"%.3f -> %.3f" % [base_freeze, up.turn_freeze()])
	check("Snap Turn never removes the freeze", up.turn_freeze() > 0.0,
		"freeze %.3f" % up.turn_freeze())

	# A crash must clear the freeze: PARKED already holds position, and a freeze
	# left running would silently eat the first frames after un-stick.
	var r2 := _make_racer(_make_room(9, 9))
	r2.request_turn(-1)
	r2._crash()
	check_near("a crash clears the freeze", r2.freeze, 0.0)


func _test_entry_corridor_lockout() -> void:
	var r := _make_racer(_make_room(9, 9))

	var start_facing := r.facing
	var came_from := int(Maze.OPPOSITE[start_facing])

	r.request_turn(-1)
	var after_turn := r.facing
	check("the first turn resolved", after_turn != start_facing)

	# The corridor the racer came out of is open in the maze -- the room is
	# fully open -- so only the lockout can keep a turn out of it.
	check("the entry corridor is open in the maze",
		r.maze.is_open(r.cell, came_from))

	# Turning back toward it must not resolve into it. In a room, the way back
	# is one of the two sides after a 90, so request that side.
	var key := 0
	if came_from == r.left_direction():
		key = -1
	elif came_from == r.right_direction():
		key = 1
	check("the way back is now a side turn", key != 0)

	if key != 0:
		r.request_turn(key)
		check("a turn does not fold back into the corridor just left",
			r.facing != came_from,
			"facing went back to %d" % r.facing)

	# A 180 is exempt -- it is explicit, expensive and always legal.
	var facing_before := r.facing
	r.request_reverse()
	check_eq("a 180 still reverses", r.facing, int(Maze.OPPOSITE[facing_before]))

	# And leaving the cell clears the lockout, so the corridor is available
	# again once it is genuinely behind the racer.
	var r2 := _make_racer(_make_room(9, 9))
	r2.request_turn(-1)
	# Travel far enough to cross into a new cell.
	for i in 200:
		r2.step(1.0 / 60.0)
		if r2.cell != r2.maze.start_cell:
			break
	check("left the starting cell", r2.cell != r2.maze.start_cell)
	check("the lockout clears on entering a new cell", r2._entry_lockout == -1,
		"still locked out of %d" % r2._entry_lockout)


# --- Fixtures ----------------------------------------------------------------

# A small maze with no braiding, so structure is predictable.
func _make_maze(w: int = 20, h: int = 20, braid: float = 0.0, seed_value: int = 1234) -> Maze:
	var m := Maze.new()
	m.generate(w, h, seed_value, braid, 1.0, 5)
	return m


# An open corridor of the given length running east, one cell tall. Built by
# hand so movement tests are not at the mercy of generation.
#
# The exit sits OFF the corridor by default (out of bounds, so unreachable),
# because reaching the exit sets `finished` and freezes the simulation -- which
# would stop a wall-contact test before it ever touched the wall. Tests that
# want a real exit pass `with_exit`.
func _make_corridor(length: int, with_exit: bool = false) -> Maze:
	var m := Maze.new()
	m.width = length
	m.height = 1
	m.cells = PackedInt32Array()
	m.cells.resize(length)
	m.cells.fill(Maze.N | Maze.E | Maze.S | Maze.W)
	m.start_cell = Vector2i(0, 0)
	m.exit_cell = Vector2i(length - 1, 0) if with_exit else Vector2i(-1, -1)
	for x in length - 1:
		m._knock_wall(Vector2i(x, 0), Maze.E)
	if with_exit:
		m._build_distance_field()
		m._build_solve_path()
	else:
		m._build_distance_field_for_tests()
	return m


# A corridor east along row 0 with a single opening south at `branch_x`, and the
# exit directly below that opening. The whole bottom row is NOT carved, so the
# only route to the exit is the branch -- which is exactly what makes this a
# clean fixture for turn resolution and the Path Indicator.
func _make_branch(length: int, branch_x: int) -> Maze:
	var m := Maze.new()
	m.width = length
	m.height = 2
	m.cells = PackedInt32Array()
	m.cells.resize(length * 2)
	m.cells.fill(Maze.N | Maze.E | Maze.S | Maze.W)
	m.start_cell = Vector2i(0, 0)
	m.exit_cell = Vector2i(branch_x, 1)
	for x in length - 1:
		m._knock_wall(Vector2i(x, 0), Maze.E)
	m._knock_wall(Vector2i(branch_x, 0), Maze.S)
	m._build_distance_field()
	m._build_solve_path()
	return m


# A fully open w x h room: every internal wall knocked out. Left is open before
# AND after a left turn, which is precisely the geometry where two fast presses
# used to resolve instantly into a 180.
func _make_room(w: int, h: int) -> Maze:
	var m := Maze.new()
	m.width = w
	m.height = h
	m.cells = PackedInt32Array()
	m.cells.resize(w * h)
	m.cells.fill(Maze.N | Maze.E | Maze.S | Maze.W)
	m.start_cell = Vector2i(w / 2, h / 2)
	m.exit_cell = Vector2i(-1, -1)
	for y in h:
		for x in w:
			if x < w - 1:
				m._knock_wall(Vector2i(x, y), Maze.E)
			if y < h - 1:
				m._knock_wall(Vector2i(x, y), Maze.S)
	m._build_distance_field_for_tests()
	return m


func _make_racer(m: Maze, u: Upgrades = null) -> Racer:
	var r := Racer.new()
	r.setup(m, u if u != null else Upgrades.new(1))
	return r


# --- Generation --------------------------------------------------------------

func _test_generation() -> void:
	var m := _make_maze(30, 30)

	check_eq("maze dimensions", m.cells.size(), 900)
	check("start != exit", m.start_cell != m.exit_cell)

	# Every cell must be reachable, or the maze can strand the player.
	var unreachable := 0
	for i in m.distance_field.size():
		if m.distance_field[i] == -1:
			unreachable += 1
	check_eq("all cells reachable", unreachable, 0)

	check("solve path exists", m.solve_path.size() > 0)
	check_eq("solve starts at start", m.solve_path[0], m.start_cell)
	check_eq("solve ends at exit", m.solve_path[-1], m.exit_cell)

	# Consecutive path cells must be genuinely adjacent and connected.
	var broken := 0
	for i in range(m.solve_path.size() - 1):
		var a: Vector2i = m.solve_path[i]
		var b: Vector2i = m.solve_path[i + 1]
		var delta: Vector2i = b - a
		var connected := false
		for dir in Maze.DIRS:
			if Maze.DIR_VECTORS[dir] == delta and m.is_open(a, dir):
				connected = true
		if not connected:
			broken += 1
	check_eq("solve path is contiguous", broken, 0)


func _test_distance_field() -> void:
	var m := _make_corridor(10, true)

	check_eq("exit distance is zero", m.get_distance(Vector2i(9, 0)), 0)
	check_eq("start distance is length-1", m.get_distance(Vector2i(0, 0)), 9)
	check_eq("mid distance", m.get_distance(Vector2i(4, 0)), 5)
	check_eq("out of bounds is -1", m.get_distance(Vector2i(99, 99)), -1)

	# best_direction should point down the corridor, toward the exit.
	check_eq("best direction points east", m.best_direction(Vector2i(3, 0)), Maze.E)
	check_eq("no improving move at exit", m.best_direction(Vector2i(9, 0)), -1)


func _test_braiding() -> void:
	var perfect := _make_maze(30, 30, 0.0)
	var braided := _make_maze(30, 30, 0.20)

	# A perfect maze has exactly W*H-1 openings, so zero loops. Dead-end tuning
	# is disabled here (ratio 1.0) so it cannot add any.
	check("perfect maze has no loops", perfect.loop_count() == 0,
		"got %d" % perfect.loop_count())
	check("braided maze has loops", braided.loop_count() > 0,
		"got %d" % braided.loop_count())
	check("braiding adds many loops", braided.loop_count() > 50,
		"got %d" % braided.loop_count())



# The zigzag cull thins CORNER-INTO-CORNER pairs: a forced 90 whose exit leads
# straight into another forced 90, with no cell between them to read the second
# from (CLAUDE.md section 6).
#
# Asserts the RELATIONSHIP rather than a count. A check against a literal number
# of zigzags would be a transcription of whatever the tuning happens to be, and
# would fail the moment the knob moved without telling you anything (section 12,
# the transcription-check trap). What has to hold is that the knob is monotonic,
# that it removes obligations rather than corners, and that opening walls never
# breaks the maze.
func _test_zigzag_cull() -> void:
	var loose := Maze.new()
	loose.generate(40, 40, 5150, 0.10, 1.0, 0, 0.0, 1.0, 0.0, 1.0)
	var tight := Maze.new()
	tight.generate(40, 40, 5150, 0.10, 1.0, 0, 0.0, 1.0, 0.0, 0.4)

	var loose_zig := _count_zigzags(loose)
	var tight_zig := _count_zigzags(tight)

	check("zigzag cull removes zigzags", tight_zig < loose_zig,
		"kept 1.0 -> %d, kept 0.4 -> %d" % [loose_zig, tight_zig])

	# It must relieve the FORCED turn, not delete the corner. A pass that simply
	# straightened corridors would score well here and would be flattening the
	# maze instead of opening it up, so assert openings went UP.
	check("zigzag cull opens walls rather than removing corners",
		tight.loop_count() > loose.loop_count(),
		"loops %d -> %d" % [loose.loop_count(), tight.loop_count()])

	# Every stage that knocks walls has to leave the maze solvable.
	check("zigzag cull leaves the exit reachable",
		tight.get_distance(tight.start_cell) != -1)
	check("zigzag cull leaves a solve path", tight.solve_path.size() > 0)

	# keep >= 1.0 is the off switch, and must be byte-identical to not running.
	var off := Maze.new()
	off.generate(40, 40, 5150, 0.10, 1.0, 0, 0.0, 1.0, 0.0, 1.0)
	check("zigzag_keep 1.0 is a no-op", off.cells == loose.cells)


# A corner is a cell with exactly two PERPENDICULAR openings: the only way on is
# a turn. A junction offers a choice and is deliberately not counted.
func _count_zigzags(m: Maze) -> int:
	var total := 0
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m._is_corner(c) and m._leads_into_corner(c):
				total += 1
	return total


func _test_seeding() -> void:
	var a := _make_maze(25, 25, 0.15, 999)
	var b := _make_maze(25, 25, 0.15, 999)
	var c := _make_maze(25, 25, 0.15, 1000)

	check("same seed gives same maze", a.cells == b.cells)
	check("different seed gives different maze", a.cells != c.cells)


# --- Movement ----------------------------------------------------------------

func _test_turn_resolution() -> void:
	var m := _make_branch(10, 3)
	var r := _make_racer(m)

	check_eq("starts facing east", r.facing, Maze.E)
	check_eq("right of east is south", r.right_direction(), Maze.S)
	check_eq("left of east is north", r.left_direction(), Maze.N)

	# The branch opens south out of cell 3. The turn is requested while crossing
	# cell 3 itself, so the pending input is live when the racer reaches the
	# cell-3/cell-4 boundary and the south opening is available there.
	#
	# Note the geometry the buffer implies: an input fired a full cell early
	# EXPIRES by design, because the buffer measures how far an input may be
	# carried. That is tested separately in _test_buffer_expiry.
	var rec := record_arg(r.turned)

	while r.cell.x < 3:
		r.step(0.02)
	r.request_turn(1)

	var guard := 0
	while not rec.fired() and guard < 2000:
		r.step(0.02)
		guard += 1

	check_eq("pending right turn resolved south", rec.last_arg, Maze.S)
	check_eq("turn happened at the branch cell", r.cell.x, 3)
	check_eq("racer is now heading south", r.facing, Maze.S)


# Two directional presses inside one cell must never resolve as two turns.
#
# request_turn() takes an opening immediately when the requested side is open
# right here, which is correct: deferring to the boundary would sail the player
# past the junction they aimed at. But it also reset progress to 0, so a second
# press landing a few milliseconds later saw a still-open side and fired again --
# and two lefts is a 180. At speed, rounding a corner with a quick double-tap
# spun the player back the way they came.
#
# The rule: an immediate turn consumes the cell. A further press in the same cell
# arms the buffer and waits for the next boundary, which is what a second turn
# request has always meant everywhere else.
func _test_double_tap() -> void:
	var m := _make_room(9, 9)
	var r := _make_racer(m)

	var start_facing := r.facing
	var start_cell := r.cell
	var expected_left := r.left_direction()

	r.request_turn(-1)
	check_eq("first press turns immediately", r.facing, expected_left)

	# The second press lands in the SAME cell, before any boundary is crossed.
	r.request_turn(-1)
	check("second press does not turn again", r.facing == expected_left)
	check("second press is not a reversal",
		r.facing != int(Maze.OPPOSITE[start_facing]))
	var armed := r.pending_turn
	check_eq("second press armed the buffer", armed,
		int(Maze.OPPOSITE[start_facing]))

	# From there it is an ordinary early input. With a ONE-CELL buffer it has
	# exactly enough room to reach the next boundary, so it RESOLVES there
	# rather than expiring -- a press made anywhere inside a cell stays live
	# until the far side of it (section 4).
	#
	# This used to assert the opposite, back when the base buffer was 0.4 cells
	# and the same press expired into a slowdown. The deferral is what the
	# lockout is for; the slowdown was a side effect of a buffer too short to
	# span the cell it was armed in.
	var expired := record(r.slowdown)
	var guard := 0
	while r.pending_turn != -1 and guard < 500:
		r.step(0.02)
		guard += 1
	check("second tap resolves rather than expiring", not expired.fired())
	check("second tap did resolve", r.pending_turn == -1)
	# It resolves as a second 90 at the NEXT boundary, one cell along -- not as
	# an instant spin in place. In an open room two lefts do add up to a
	# reversed heading, and that is correct: they are two deliberate turns a
	# cell apart, each paying the 90 cost. What the lockout prevents is both
	# landing in the same cell, which is what `r.cell != start_cell` proves.
	check("second turn happened in a later cell", r.cell != start_cell)
	check_eq("both turns cost a 90, not a 180", r.slowdown_count, 0)

	# A second press late in the cell resolves at the boundary too -- the
	# lockout defers the input, it never discards it. Kept alongside the case
	# above because it exercises a DIFFERENT path: armed most of the way across
	# the cell rather than immediately after a turn.
	var r3 := _make_racer(_make_room(9, 9))
	r3.request_turn(-1)
	# "Late in the cell" is 0.2 of a cell short of the far grid line. Progress is
	# centred on the cell centre and runs -0.5..+0.5 (the two drawn lines), so
	# that is +0.3 -- it was 0.7 when progress ran 0..1 between cell CENTRES and
	# the boundary sat at 1.0. Guarded, because an unbounded wait on a progress
	# value that can no longer be reached is an infinite loop rather than a
	# failing assertion: this one hung the whole harness with no output at all.
	var spin3 := 0
	while r3.progress < 0.3 and spin3 < 500:
		r3.step(0.01)
		spin3 += 1
	check("r3 reached the late-cell position", spin3 < 500)
	var want3 := r3.left_direction()
	r3.request_turn(-1)
	check_eq("late second press is buffered, not immediate", r3.pending_turn, want3)
	var cell3 := r3.cell
	var guard3 := 0
	while r3.pending_turn != -1 and guard3 < 500:
		r3.step(0.01)
		guard3 += 1
	check_eq("buffered turn resolves to the armed direction", r3.facing, want3)
	check("buffered turn waited for a cell boundary", r3.cell != cell3)
	check_eq("a carried turn costs no slowdown", r3.slowdown_count, 0)

	# A press after genuinely entering a new cell must still turn immediately --
	# the lockout is per-cell, not a global cooldown.
	var r2 := _make_racer(_make_room(9, 9))
	var first_want := r2.left_direction()
	r2.request_turn(-1)
	check_eq("fresh racer turns immediately", r2.facing, first_want)
	var before := r2.cell
	var guard2 := 0
	while r2.cell == before and guard2 < 500:
		r2.step(0.02)
		guard2 += 1
	var want := r2.left_direction()
	r2.request_turn(-1)
	check_eq("press in a NEW cell turns immediately again", r2.facing, want)


func _test_buffer_expiry() -> void:
	var m := _make_corridor(20)
	var r := _make_racer(m)

	var expired := record(r.slowdown)

	var speed_before := r.speed
	r.request_turn(1)      # nothing is open to the south anywhere

	# Drive until the buffer must have run out. Derived from the constant rather
	# than hard-coded: the base buffer went 0.2 -> 0.4 -> 1.0 cells, and a
	# fixed 0.6s loop silently stopped reaching expiry each time, turning this
	# into a test that asserted nothing. Travel is ~1 cell/sec at base speed and
	# the ramp only makes it faster, so buffer-cells worth of seconds plus a
	# margin always overshoots.
	var seconds: float = Tuning.BASE_BUFFER_CELLS + 0.5
	for i in int(seconds / 0.02):
		r.step(0.02)

	check("expired input fires slowdown", expired.fired())
	check_eq("pending turn cleared", r.pending_turn, -1)
	check_eq("slowdown counted", r.slowdown_count, 1)
	check("slowdown is not a crash", r.state == Racer.State.RUNNING)
	check_eq("slowdown costs no hp", r.hp, Tuning.MAX_HP)
	check_near("barrier untouched by slowdown", r.barrier, r.upgrades.barrier_capacity())
	# Compare against what the ramp ALONE would have produced over the same
	# stretch, not against the starting speed: the drive now lasts long enough
	# (buffer-cells + margin, ~1.5s) that the ramp out-gains the 0.5x penalty
	# and a naive `speed < speed_before` check fails while the penalty is
	# working perfectly. What matters is that the slowdown left the racer
	# measurably below an unpenalised run.
	# The floor clamps how much of the penalty can actually show: starting at
	# 1.0x with a 1.0x floor, a 0.5x hit cannot drive speed below 1.0, so only
	# the ramp accrued BEFORE the slowdown is lost. Assert the racer ended up
	# meaningfully below an unpenalised run, not that the full 0.5 landed.
	var unpenalised: float = speed_before + Tuning.SPEED_RAMP_PER_SEC * seconds
	check("slowdown reduced speed", r.speed < unpenalised - 0.05,
		"speed %.3f vs unpenalised ~%.3f" % [r.speed, unpenalised])


func _test_barrier_grace() -> void:
	# A short corridor with no exit, so the racer runs east into the dead end
	# instead of finishing the maze.
	var m := _make_corridor(3)
	var r := _make_racer(m)

	var scrape_rec := record(r.scraped)
	var crash_rec := record(r.crashed)

	# Drive into the far wall. Two cells at ~1 cell/sec is ~2s of travel before
	# contact even begins, so the loop has to outlast that.
	for i in 400:
		r.step(0.01)
		if r.scraping:
			break

	check("scrape fires on wall contact", scrape_rec.fired())

	# Hold against the wall for HALF the barrier, derived rather than written
	# out. A literal 0.2s was chosen as "well inside" a 0.5s pool and would have
	# silently become 80% of it when the base was halved -- a margin that shrinks
	# with a tuning change is the transcription trap (CLAUDE.md section 12) in
	# its quieter form: the assertion still passes, but it stops testing grace
	# and starts testing arithmetic.
	var hold_steps := int(Tuning.BASE_BARRIER * 0.5 / 0.01)
	for i in hold_steps:
		r.step(0.01)

	check("no crash yet -- barrier is holding", not crash_rec.fired())
	check("barrier is draining", r.barrier < r.upgrades.barrier_capacity())
	check("still running while scraping", r.state == Racer.State.RUNNING)

	# Contact costs a flat point, and the barrier no longer buys it back. Read
	# off Tuning rather than written as a literal, for the reason the crash
	# damage below is (CLAUDE.md section 12).
	check_eq("contact costs hp", r.hp, Tuning.MAX_HP - Tuning.SCRAPE_DAMAGE)
	check_eq("contact is counted", r.scrape_count, 1)

	# Charged ONCE per contact, not per second: holding the wall longer must not
	# cost more. This is the assertion that would catch a per-frame or per-second
	# charge, which is the shape the rule was explicitly NOT given.
	var held := r.hp
	for i in int(Tuning.BASE_BARRIER * 0.25 / 0.01):
		r.step(0.01)
	check_eq("holding the wall costs no more", r.hp, held)
	check_eq("still one contact", r.scrape_count, 1)

	# Contact is NOT a crash. It moves HP and nothing else -- the racer keeps
	# driving, at the speed it had, un-parked. This is the whole distinction the
	# rule rests on, so it is asserted directly rather than implied.
	check("contact does not crash", not crash_rec.fired())
	check_eq("contact does not park", r.state, Racer.State.RUNNING)
	check_eq("contact leaves crash count alone", r.crash_count, 0)

	var clean := _make_racer(_make_corridor(3))
	var speed_before := 0.0
	for i in 400:
		clean.step(0.01)
		if clean.scraping:
			speed_before = clean.speed
			break
	for i in hold_steps:
		clean.step(0.01)
	var hp_before := clean.hp
	clean.request_reverse()
	# Escaping still avoids the CRASH -- the barrier's remaining job -- but no
	# longer refunds the contact charge already paid.
	check_eq("escaping the wall causes no crash", clean.crash_count, 0)
	check_eq("escaping does not re-charge hp", clean.hp, hp_before)
	check_eq("escaping cost exactly one contact", clean.scrape_count, 1)
	check("contact does not touch speed", speed_before > 0.0)

	# Leaving the wall and touching it again is a SECOND contact, and charges
	# again. Without this, "once per contact" could be silently implemented as
	# "once ever" and every assertion above would still pass.
	var again := _make_racer(_make_corridor(4))
	var reached_first := false
	for i in 900:
		again.step(0.01)
		if again.scraping:
			reached_first = true
			break
	check("the second-contact fixture reached the wall", reached_first)
	var after_first := again.hp

	# Reverse OFF the wall and wait for contact to actually clear before looking
	# for the next one. Without this wait the loop below breaks instantly on the
	# contact still in progress, so `scrape_count` never moves and the check
	# reports the rule broken when the fixture simply never left the wall. That
	# is the CLAUDE.md section 12 wait-loop trap: guard the wait and name the
	# failure rather than asserting against a state that never changed.
	again.request_reverse()
	var left_wall := false
	for i in 900:
		again.step(0.01)
		if not again.scraping:
			left_wall = true
			break
	check("the racer left the wall before the second run", left_wall)

	var reached_second := false
	for i in 1200:
		again.step(0.01)
		if again.scraping:
			reached_second = true
			break
	check("the second-contact fixture reached a wall again", reached_second)
	check_eq("a second contact charges again", again.hp,
		after_first - Tuning.SCRAPE_DAMAGE)
	check_eq("two contacts counted", again.scrape_count, 2)


func _test_crash_and_unstick() -> void:
	var m := _make_corridor(3)
	var r := _make_racer(m)

	var crash_rec := record(r.crashed)

	# ~2s of travel to reach the wall, then the barrier's worth before the crash.
	for i in 600:
		r.step(0.01)
		if crash_rec.fired():
			break

	check("barrier depletion causes a crash", crash_rec.fired())
	check_eq("crash parks the racer", r.state, Racer.State.PARKED)
	# Read the damage off the build rather than restating a literal. A hard-coded
	# "MAX_HP - 1" was a transcription check, and it broke the moment wall damage
	# became a per-maze curve -- while telling us nothing about whether the crash
	# actually applied the damage the rules say it should (CLAUDE.md section 12).
	# The crash damage lands ON TOP of the contact charge already paid when the
	# racer first touched the wall -- a crash is always preceded by a contact,
	# since the barrier has to drain before it can empty.
	check_eq("crash deals damage", r.hp,
		Tuning.MAX_HP - Tuning.SCRAPE_DAMAGE
			- r.upgrades.wall_damage(r.maze_index))
	check_eq("the crash was preceded by one contact", r.scrape_count, 1)
	check_near("speed reset to floor", r.speed, r.upgrades.speed_floor())

	# Parked means parked: stepping does nothing.
	var cell_before := r.cell
	var hp_before := r.hp
	for i in 50:
		r.step(0.02)
	check_eq("parked racer does not move", r.cell, cell_before)
	check_eq("parked racer takes no further damage", r.hp, hp_before)

	var facing_before := r.facing
	r.request_reverse()
	check_eq("unstick resumes running", r.state, Racer.State.RUNNING)
	check_eq("unstick reverses facing", r.facing, int(Maze.OPPOSITE[facing_before]))
	check("unstick restores barrier", r.barrier > 0.0)
	check("recovery starts below the floor", r.speed < r.upgrades.speed_floor())

	# The recovery ramp is 2.5x, so the climb back to the floor is quick:
	# 0.5x to regain at 0.1667x/sec is about 3 seconds. Measured on a long
	# corridor, because a short one would just crash into the far wall again
	# before the ramp finished.
	var long_maze := _make_corridor(200)
	var recovering := _make_racer(long_maze)
	recovering.speed = recovering.upgrades.speed_floor() * 0.5
	var floor_speed := recovering.upgrades.speed_floor()

	for i in 200:
		recovering.step(0.02)
	check("recovery reaches the floor", recovering.speed >= floor_speed,
		"got %f, floor %f" % [recovering.speed, floor_speed])


func _test_reverse() -> void:
	var m := _make_corridor(400)
	var r := _make_racer(m)

	# Build up real speed first, so the reverse cost has room to land without
	# being clamped by the speed floor. 45s of clean travel is ~4x.
	for i in 2250:
		r.step(0.02)

	var speed_before := r.speed
	var facing_before := r.facing
	check("speed ramped up", speed_before > 3.5, "got %f" % speed_before)

	r.request_reverse()

	check_eq("reverse flips facing", r.facing, int(Maze.OPPOSITE[facing_before]))
	check_near("reverse costs the base amount at rank 0",
		speed_before - r.speed, Tuning.REVERSE_COST)

	# The 180 must stay well above a 90, or committing to a route and rounding a
	# loop stops being a real decision against just reversing (section 5.3).
	check("reverse costs meaningfully more than a 90",
		Tuning.REVERSE_COST > Tuning.TURN_COST * 4.0,
		"reverse %.2f against turn %.2f" % [Tuning.REVERSE_COST, Tuning.TURN_COST])

	# Fast Turnaround refunds part of the cost, and must actually bite at every
	# rank -- a line that flattens out is a dead card in the pool.
	var u := Upgrades.new(1)
	u.ranks[Upgrades.Line.FAST_TURNAROUND] = 3
	check_near("fast turnaround rank 3 reverse cost", u.reverse_cost(),
		float(Tuning.REVERSE_COST_BY_RANK[3]))
	check("fast turnaround roughly halves the 180 by top rank",
		u.reverse_cost() <= Tuning.REVERSE_COST * 0.6,
		"rank 3 costs %.2f against base %.2f" % [u.reverse_cost(), Tuning.REVERSE_COST])

	var previous := Tuning.REVERSE_COST + 1.0
	for step in Tuning.REVERSE_COST_BY_RANK.size():
		var cost: float = float(Tuning.REVERSE_COST_BY_RANK[step])
		check("fast turnaround rank %d improves on the last" % step, cost < previous,
			"rank %d costs %.2f, previous %.2f" % [step, cost, previous])
		previous = cost


func _test_speed_ramp() -> void:
	var m := _make_corridor(500)
	var r := _make_racer(m)

	# One ramp interval of clean travel should be worth exactly +1.0x. Derived
	# from the constant rather than hardcoded, so retuning the ramp does not
	# leave this assertion silently encoding the old value.
	var interval := 1.0 / Tuning.SPEED_RAMP_PER_SEC
	for i in int(interval / 0.02):
		r.step(0.02)

	check_near("one ramp interval gives +1.0x over the floor",
		r.speed, Tuning.SPEED_FLOOR + 1.0, 0.05)
	check_eq("no crashes on a straight run", r.crash_count, 0)

	# And it must never exceed the cap.
	for i in 10000:
		r.step(0.02)
	check("speed never exceeds cap", r.speed <= Tuning.SPEED_CAP + 0.001,
		"got %f" % r.speed)


# --- Upgrades ----------------------------------------------------------------

func _test_upgrades() -> void:
	var u := Upgrades.new(42)

	check_near("base buffer", u.buffer_cells(), Tuning.BASE_BUFFER_CELLS)
	u.take(Upgrades.Line.BUFFER_WINDOW)
	# Derived, not hardcoded -- this assertion is about the +1 rank arithmetic,
	# not about whatever the base happens to be tuned to this week.
	check_near("buffer after one rank", u.buffer_cells(),
		Tuning.BASE_BUFFER_CELLS + Tuning.BUFFER_PER_RANK)

	check_near("base speed floor", u.speed_floor(), Tuning.SPEED_FLOOR)
	u.take(Upgrades.Line.BASE_SPEED)
	check_near("floor after one rank", u.speed_floor(),
		Tuning.SPEED_FLOOR + Tuning.BASE_SPEED_PER_RANK)

	check_near("base barrier", u.barrier_capacity(), Tuning.BASE_BARRIER)
	u.take(Upgrades.Line.BARRIER_CAPACITY)
	check_near("barrier after one rank", u.barrier_capacity(),
		Tuning.BASE_BARRIER + Tuning.BARRIER_PER_RANK)

	# Ranks must cap.
	for i in 20:
		u.take(Upgrades.Line.GATE_COMPASS)
	check_eq("rank caps at max", u.rank(Upgrades.Line.GATE_COMPASS), 1)
	check("maxed line reports maxed", u.is_maxed(Upgrades.Line.GATE_COMPASS))

	# Wall armor must never heal, on any maze.
	var armored := Upgrades.new(1)
	for i in 3:
		armored.take(Upgrades.Line.WALL_ARMOR)
	for mi in Tuning.MAZES.size():
		check("wall damage floors at zero (maze %d)" % (mi + 1),
			armored.wall_damage(mi) >= 0)

	# Wall damage scales per maze (CLAUDE.md section 5.5). Derived from the
	# tuning pair rather than restated, so the assertion is about the curve
	# holding, not about two literals agreeing.
	var bare_dmg := Upgrades.new(3)
	check_eq("maze 1 wall damage", bare_dmg.wall_damage(0), Tuning.WALL_DAMAGE)
	check_eq("wall damage climbs per maze", bare_dmg.wall_damage(4),
		Tuning.WALL_DAMAGE + 4 * Tuning.WALL_DAMAGE_PER_MAZE)
	check("later mazes hurt more", bare_dmg.wall_damage(4) > bare_dmg.wall_damage(0))
	# Armor subtracts AFTER the scaling, so a rank is worth the same flat point
	# everywhere rather than being multiplied up in the late mazes.
	check_eq("armor subtracts after scaling", armored.wall_damage(4),
		bare_dmg.wall_damage(4) - 3 * Tuning.WALL_ARMOR_PER_RANK)

	# Cornering and Expiry Grace both reduce a cost without ever reaching zero:
	# a free turn or a free expiry would remove the decision the cost exists to
	# create (CLAUDE.md sections 5.2, 5.3).
	var corner := Upgrades.new(5)
	check_near("base turn cost", corner.turn_cost(), Tuning.TURN_COST)
	check_near("base slowdown", corner.slowdown_penalty(), Tuning.SLOWDOWN_PENALTY)
	var prev_turn := corner.turn_cost()
	var prev_slow := corner.slowdown_penalty()
	for i in 3:
		corner.take(Upgrades.Line.CORNERING)
		corner.take(Upgrades.Line.EXPIRY_GRACE)
		check("cornering rank %d cuts the turn cost" % (i + 1),
			corner.turn_cost() < prev_turn)
		check("expiry grace rank %d cuts the slowdown" % (i + 1),
			corner.slowdown_penalty() < prev_slow)
		prev_turn = corner.turn_cost()
		prev_slow = corner.slowdown_penalty()
	check("turn cost never reaches zero", corner.turn_cost() > 0.0)
	check("slowdown never reaches zero", corner.slowdown_penalty() > 0.0)

	# Card offers: three distinct, never maxed.
	var cards := u.roll_cards(3)
	check_eq("three cards offered", cards.size(), 3)
	check("cards are distinct", cards[0] != cards[1] and cards[1] != cards[2] and cards[0] != cards[2])
	var offered_maxed := false
	for line in cards:
		if u.is_maxed(line):
			offered_maxed = true
	check("no maxed line offered", not offered_maxed)

	# Early on, at least one card must open a new line.
	var fresh := Upgrades.new(7)
	var fresh_cards := fresh.roll_cards(3)
	var has_new := false
	for line in fresh_cards:
		if fresh.rank(line) == 0:
			has_new = true
	check("early offer includes a new line", has_new)


# Repair Field restores HP on CLEAN travel only, and death fires when HP runs
# out (CLAUDE.md sections 5.5, 7).
func _test_hp_regen_and_death() -> void:
	var m := Maze.new()
	m.generate(40, 40, 999, 0.25, 0.02, 3, 0.5, 0.2, 0.0, 0.6)

	# Start well below the cap, DERIVED from it rather than written out. A literal
	# was fine when the pool was 100 and silently broke the test when it came down
	# to 50: the racer started already full, healed nothing, and the failure read
	# as Repair Field being inert. That is the section 12 transcription trap -- a
	# fixture that restates a tuning number tests the number, not the rule.
	var start_hp := Tuning.MAX_HP / 2

	# Untaken, the line is completely inert: HP only ever falls.
	var bare := Upgrades.new(1)
	var r_bare := Racer.new()
	r_bare.setup(m, bare, 0)
	r_bare.hp = start_hp
	_run_clean(m, r_bare, 500)
	check_eq("no regen without Repair Field", r_bare.hp, start_hp)

	var u := Upgrades.new(1)
	for i in 3:
		u.take(Upgrades.Line.HP_REGEN)
	var r := Racer.new()
	r.setup(m, u, 0)
	r.hp = start_hp
	_run_clean(m, r, 500)
	# 10s at the rank-3 rate, less the fraction still accumulating. Asserting a
	# band rather than an exact value, since the last whole point lands whenever
	# the accumulator happens to cross 1.0. Capped at the pool, or the assertion
	# would demand a racer heal past full the moment the rate outruns the room.
	var want := minf(float(start_hp) + u.hp_regen() * 10.0, float(Tuning.MAX_HP))
	check("Repair Field restores on clean travel",
		float(r.hp) >= want - 2.0 and float(r.hp) <= want,
		"%d -> %d, expected about %.0f" % [start_hp, r.hp, want])
	check_eq("regen never exceeds max hp", mini(r.hp, Tuning.MAX_HP), r.hp)

	# It must not pay out while parked -- a crash would otherwise heal itself.
	var parked := Racer.new()
	parked.setup(m, u, 0)
	parked.hp = start_hp
	parked.state = Racer.State.PARKED
	for i in 300:
		parked.step(0.02)
	check_eq("no regen while parked", parked.hp, start_hp)

	# Death: drive into walls until HP is gone.
	var dying := Racer.new()
	dying.setup(m, Upgrades.new(1), 4)
	var rec := SignalRecorder.new()
	dying.died.connect(rec.on_signal)

	for i in 40000:
		if dying.dead:
			break
		if dying.state == Racer.State.PARKED:
			dying.request_reverse()
		dying.step(0.02)

	check("death fires when hp runs out", dying.dead)
	check("died signal emitted", rec.fired())
	check_eq("death leaves hp at zero", dying.hp, 0)
	# A dead racer is finished: stepping must not move it.
	var cell_at_death := dying.cell
	for i in 100:
		dying.step(0.02)
	check_eq("dead racer does not move", dying.cell, cell_at_death)


# Step a racer without ever letting it touch a wall, so "clean travel" means
# what it says. An unsteered racer parks against the first wall it meets
# (CLAUDE.md section 12), which is exactly what regen excludes -- so a regen
# test that did not steer would measure the parking, not the regen.
func _run_clean(m: Maze, r: Racer, frames: int) -> void:
	for i in frames:
		if not m.is_open(r.cell, r.facing):
			var best := m.best_direction(r.cell)
			if best != -1:
				r.facing = best
		r.step(0.02)


# The score (CLAUDE.md section 8b).
#
# The property that matters most here is MONOTONICITY: a faster run must always
# beat a slower one, even though the slower one covers more ground and so makes
# more turns and earns more per-second income. That is not a property of the
# award sizes being sensible -- it broke in every naive configuration tried, and
# it is the multiplier that has to carry it. Asserted directly below.
func _test_score() -> void:
	var sc := Score.new()
	check_near("fresh score is zero", sc.total(), 0.0)

	# Travel pays per second, scaled by speed.
	sc.add_travel(1.0, 2.0)
	check_near("travel pays rate x speed", sc.maze_subtotal,
		Tuning.SCORE_PER_SECOND * 2.0)

	# A parked racer earns nothing -- Game gates this, but a zero delta must be
	# inert regardless.
	var before := sc.maze_subtotal
	sc.add_travel(0.0, 5.0)
	check_near("zero delta earns nothing", sc.maze_subtotal, before)

	# A scraped turn is worth less than a clean one, and both beat nothing.
	var clean_score := Score.new()
	clean_score.add_turn(3.0, false)
	var scrape_score := Score.new()
	scrape_score.add_turn(3.0, true)
	check("clean turn beats scraped turn",
		clean_score.maze_subtotal > scrape_score.maze_subtotal)
	check("scraped turn still pays", scrape_score.maze_subtotal > 0.0)
	check_near("scraped turn is 40% of clean",
		scrape_score.maze_subtotal / clean_score.maze_subtotal, 0.4)
	check_eq("clean turns are counted", clean_score.clean_turns, 1)
	check_eq("scraped turns are counted", scrape_score.scraped_turns, 1)

	# Crashes are a flat cost, NOT speed-scaled.
	var crash_a := Score.new()
	crash_a.add_crash()
	var crash_b := Score.new()
	crash_b.add_crash()
	check_near("crash cost does not vary", crash_a.maze_subtotal, crash_b.maze_subtotal)
	check_near("crash costs the flat penalty", crash_a.maze_subtotal,
		-Tuning.SCORE_CRASH_PENALTY)

	# A maze can bank zero but never a negative -- a run of crashes must not eat
	# the scores of mazes already completed.
	var sunk := Score.new()
	for i in 50:
		sunk.add_crash()
	sunk.bank_maze(0, "test")
	check("a wrecked maze banks zero, never negative", sunk.total() >= 0.0)

	# The multiplier: steep under budget, gentle over, floored.
	var m := Score.new()
	check_near("multiplier at exactly budget is 1.0",
		m.time_multiplier(Tuning.SCORE_TIME_BUDGET), 1.0)
	check("finishing early beats finishing at budget",
		m.time_multiplier(Tuning.SCORE_TIME_BUDGET - 60.0)
			> m.time_multiplier(Tuning.SCORE_TIME_BUDGET))
	check("overtime drops below 1.0",
		m.time_multiplier(Tuning.SCORE_TIME_BUDGET + 30.0) < 1.0)
	check("overtime never goes below the floor",
		m.time_multiplier(Tuning.SCORE_TIME_BUDGET * 100.0)
			>= Tuning.SCORE_MULT_FLOOR)
	check("overtime decays more gently than early time rewards",
		(m.time_multiplier(Tuning.SCORE_TIME_BUDGET - 60.0) - 1.0)
			> (1.0 - m.time_multiplier(Tuning.SCORE_TIME_BUDGET + 60.0)))

	# Banking clears the maze and accumulates the run.
	var bank := Score.new()
	bank.add_travel(10.0, 4.0)
	bank.advance_time(120.0)
	var expected_mult := bank.time_multiplier()
	var earned := bank.bank_maze(0, "The Grid")
	check("banking returns what was earned", earned > 0.0)
	check_near("banked equals subtotal x multiplier", earned,
		Tuning.SCORE_PER_SECOND * 4.0 * 10.0 * expected_mult)
	check_near("maze subtotal resets after banking", bank.maze_subtotal, 0.0)
	check_near("maze clock resets after banking", bank.maze_time, 0.0)
	check_eq("a banked maze is recorded", bank.maze_results.size(), 1)

	# Partial banking on death scales by progress.
	var partial := Score.new()
	partial.add_travel(10.0, 4.0)
	partial.advance_time(120.0)
	var half := partial.bank_maze(0, "The Grid", 0.5)
	check_near("half progress banks half the score", half, earned * 0.5)

	# --- The repeat-cell penalty ---
	var rep := Score.new()
	rep.add_repeat()
	check_near("a repeat costs the flat penalty", rep.maze_subtotal,
		-Tuning.SCORE_REPEAT_CELL_PENALTY)
	check_eq("repeats are counted", rep.repeat_cells, 1)

	# Charged once per DISTINCT cell -- Racer decides which crossings qualify via
	# `first_repeat`, and Score simply charges what it is told. What stops a
	# farming loop is no longer this penalty but the suppressed earning below.
	rep.add_repeat()
	rep.add_repeat()
	check_near("each charged cell costs the penalty", rep.maze_subtotal,
		-3.0 * Tuning.SCORE_REPEAT_CELL_PENALTY)
	check_eq("charged cells are counted", rep.repeat_cells, 3)

	# --- No earning on repeat ground ---
	#
	# This is the actual anti-farming rule. A turn pays 60 x speed on fresh
	# ground and nothing at all on ground already driven, which is what removes
	# the income a farming lap runs on (CLAUDE.md section 8b).
	var fresh := Score.new()
	fresh.add_turn(6.0, false)
	fresh.add_travel(1.0, 6.0)
	check("fresh ground earns", fresh.maze_subtotal > 0.0)

	var stale := Score.new()
	stale.on_repeat_ground = true
	stale.add_turn(6.0, false)
	stale.add_travel(1.0, 6.0)
	check_near("repeat ground earns the scaled share", stale.maze_subtotal,
		fresh.maze_subtotal * Tuning.SCORE_EARN_ON_REPEAT)

	# The turn is still TALLIED, only unpaid: the summary reports what the player
	# did, and withholding the points must not also erase the record.
	check_eq("an unpaid turn is still counted", stale.clean_turns, 1)

	# Banking clears it: a new maze is fresh ground by definition.
	stale.bank_maze(0, "The Grid")
	check("banking clears repeat ground", not stale.on_repeat_ground)

	# Flat, like the crash penalty: Score Multiplier is a bonus on points EARNED,
	# so scaling the penalty by it would make backtracking more expensive the
	# more of that line the player holds.
	var boosted := Score.new()
	boosted.earn_multiplier = 1.6
	boosted.add_repeat()
	check_near("the repeat penalty ignores earn_multiplier",
		boosted.maze_subtotal, -Tuning.SCORE_REPEAT_CELL_PENALTY)

	_check_score_monotonic()
	_check_farming_loses()


# A player who refuses to finish, driving a loop to farm turn income, must score
# WORSE than one who simply drives the maze -- at EVERY lap count, not merely at
# one chosen in advance.
#
# This is the case the monotonicity check cannot see: every run it models
# finishes its maze, so all of them are disciplined by the time multiplier at
# bank time. A farming run is defined by never banking until the subtotal has
# been pumped high, and the multiplier floors at 0.20x.
#
# The sweep matters more than the model. An earlier version of this check
# modelled ONE fixed lap count (60) and passed, while the exploit was live: a
# farmer's score peaks early and then decays as the time multiplier bites, and
# 60 laps sat past the peak. Measured at the time, 20 laps beat an honest run
# even at the old 250 penalty. A single sample of a curve says nothing about its
# maximum -- sweep it.
func _check_farming_loses() -> void:
	const LOOP_CELLS := 10.0
	const FARM_SPEED := 6.0

	# The honest run: 300 cells of fresh ground, turning on 55% of them.
	var honest := Score.new()
	honest.add_travel(55.0, 5.5)
	for i in int(300.0 * 0.55):
		honest.add_turn(5.5, false)
	honest.advance_time(55.0)
	var honest_score := honest.bank_maze(0, "honest")

	# The worst case for the rule is a farmer who turns on EVERY cell -- a small
	# braided ring circled at speed, which is the most lucrative loop the maze
	# can offer. A pacing farmer reverses instead, which costs 0.75x a time and
	# never reaches these speeds, so it is strictly weaker.
	var worst := 0.0
	var worst_laps := 0
	var lap_counts: Array[int] = [1, 2, 5, 10, 20, 30, 60, 120, 240, 400]
	for laps: int in lap_counts:
		var farm := Score.new()
		farm.add_travel(55.0, 5.5)
		for i in int(300.0 * 0.55):
			farm.add_turn(5.5, false)

		var cells: int = int(LOOP_CELLS * laps)
		var farm_seconds: float = LOOP_CELLS * laps / FARM_SPEED

		# Every cell of the loop is charged once; the loop is fully marked after
		# the first lap, which is why the penalty alone cannot bound this.
		for i in int(LOOP_CELLS):
			farm.add_repeat()

		# And every lap of it earns at the repeat rate rather than the fresh one.
		# This is the rule under test.
		farm.on_repeat_ground = true
		farm.add_travel(farm_seconds, FARM_SPEED)
		for i in cells:
			farm.add_turn(FARM_SPEED, false)

		farm.advance_time(55.0 + farm_seconds)
		var farm_score := farm.bank_maze(0, "farm")
		if farm_score > worst:
			worst = farm_score
			worst_laps = laps

	check("farming a loop scores worse than driving the maze, at every lap count",
		worst < honest_score,
		"best farm %.0f at %d laps vs honest %.0f" % [worst, worst_laps, honest_score])


# Faster must always score higher, across a realistic spread of runs.
#
# This is the assertion the whole section 8b design exists to satisfy. A worse
# player covers MORE ground, so they make more turns and collect more per-second
# income -- the naive scoring built the obvious way pays them more. Only the
# time multiplier reverses that, and only if it is strong enough.
func _check_score_monotonic() -> void:
	# time, speed, detour (route length vs optimal), scrape fraction
	var runs := [
		[55.0, 5.5, 1.00, 0.00],
		[90.0, 5.0, 1.30, 0.10],
		[120.0, 4.0, 1.60, 0.25],
		[150.0, 3.0, 1.90, 0.40],
		[200.0, 2.0, 2.20, 0.50],
		[260.0, 1.5, 2.60, 0.60],
	]
	const OPTIMAL_CELLS := 300.0

	var scores: Array[float] = []
	for run in runs:
		var t: float = run[0]
		var sp: float = run[1]
		var cells: float = OPTIMAL_CELLS * float(run[2])
		var scrape_frac: float = run[3]
		var turns := int(cells * 0.55)

		var sc := Score.new()
		sc.add_travel(t, sp)
		for i in turns:
			sc.add_turn(sp, i < int(float(turns) * scrape_frac))
		sc.advance_time(t)
		scores.append(sc.bank_maze(0, "test"))

	for i in range(scores.size() - 1):
		check("run %d outscores run %d (faster is better)" % [i, i + 1],
			scores[i] > scores[i + 1],
			"%.0f vs %.0f" % [scores[i], scores[i + 1]])

	check("best run far outscores worst", scores[0] / maxf(scores[-1], 1.0) > 10.0,
		"ratio %.1fx" % (scores[0] / maxf(scores[-1], 1.0)))


# Legendaries: rarity, the one-per-run cap, and each ability's mechanics
# (CLAUDE.md section 7).
# Seed derivation for the daily and monthly boards
# (docs/plans/leaderboards.md). Pure functions of a date string, which is what
# lets them be asserted without a clock.
func _test_seeded_boards() -> void:
	# The same date must always give the same maze -- that is the entire premise
	# of a shared board.
	check_eq("a date always derives the same seed",
		Tuning.seed_for_date("2026-09-02"), Tuning.seed_for_date("2026-09-02"))
	check("different dates derive different seeds",
		Tuning.seed_for_date("2026-09-02") != Tuning.seed_for_date("2026-09-03"))
	check("different months derive different seeds",
		Tuning.seed_for_month("2026-09") != Tuning.seed_for_month("2026-10"))

	# The daily and monthly streams are namespaced apart, so the first of a month
	# does not hand the monthly board the same maze as that day's daily.
	check("daily and monthly never collide on the same key",
		Tuning.seed_for_date("2026-09") != Tuning.seed_for_month("2026-09"))

	# Positive and inside 31 bits: the value is handed to RandomNumberGenerator
	# and then used in `run_seed + index * 7919`, so a negative or near-overflow
	# seed would break maze generation rather than merely looking odd.
	for key in ["2026-01-01", "2026-09-02", "1999-12-31", "2100-06-15"]:
		var v := Tuning.seed_for_date(key)
		check("%s derives a usable seed" % key, v > 0 and v <= 0x7FFFFFFF,
			"got %d" % v)

	# A derived seed must actually generate. This is the assertion that matters:
	# the others only check arithmetic, this checks the maze exists.
	var m := Maze.new()
	var daily := Tuning.seed_for_date("2026-09-02")
	m.generate(20, 20, daily, 0.1, 0.03, 3)
	check("a derived seed generates a solvable maze", m.solve_path.size() > 0)

	# And generates the SAME maze twice, which is what makes two players'
	# scores comparable at all.
	var again := Maze.new()
	again.generate(20, 20, daily, 0.1, 0.03, 3)
	check("the same seed regenerates an identical maze",
		again.solve_path == m.solve_path)

	# Board names round-trip, and an out-of-range board falls back rather than
	# crashing -- this string is written into every posted score.
	check_eq("general board name", Tuning.board_name(Tuning.Board.GENERAL), "general")
	check_eq("daily board name", Tuning.board_name(Tuning.Board.DAILY), "daily")
	check_eq("monthly board name", Tuning.board_name(Tuning.Board.MONTHLY), "monthly")
	check_eq("an unknown board falls back to general", Tuning.board_name(99), "general")

	# The date keys are the shape the boards are keyed by; a drift here would
	# silently split one day's board into two.
	check("today_key is YYYY-MM-DD", Tuning.today_key().length() == 10,
		Tuning.today_key())
	check("this_month_key is YYYY-MM", Tuning.this_month_key().length() == 7,
		Tuning.this_month_key())
	check("the month key prefixes the day key",
		Tuning.today_key().begins_with(Tuning.this_month_key()))

	# GENERAL stays random: that board is "any seed", so a fixed maze would be
	# wrong there.
	check("the general board is not date-derived",
		Tuning.seed_for_board(Tuning.Board.GENERAL)
			!= Tuning.seed_for_date(Tuning.today_key()))
	check_eq("the daily board uses today's seed",
		Tuning.seed_for_board(Tuning.Board.DAILY),
		Tuning.seed_for_date(Tuning.today_key()))


# The racer's record of where it has been, which the repeat-cell penalty is
# charged from (CLAUDE.md section 8b).
func _test_visited_cells() -> void:
	var u := Upgrades.new(1)
	var m := _make_corridor(12)
	var r := Racer.new()
	r.setup(m, u, 0)

	# The start cell counts as visited from the outset: the racer is demonstrably
	# there, so coming back to it later is a return like any other.
	check("the start cell is marked visited", r.visited.has(m.start_cell))

	var seen: Array[Vector2i] = []
	var repeats: Array[Vector2i] = []
	var first_repeats: Array[Vector2i] = []
	r.cell_entered.connect(func(cell: Vector2i, repeat: bool, first: bool) -> void:
		seen.append(cell)
		if repeat:
			repeats.append(cell)
		if first:
			first_repeats.append(cell))

	# Drive east four cells of fresh ground.
	while r.cell.x < 4:
		r.step(0.02)
	check("fresh cells are entered", seen.size() >= 4)
	check_eq("fresh ground charges no repeat", repeats.size(), 0)

	# Reverse and drive back over them.
	var turn_around := r.cell
	r.request_reverse()
	while r.cell.x > 0:
		r.step(0.02)
	check("driving back over old ground is a repeat", repeats.size() > 0)
	check("the repeats are cells already driven",
		r.visited.has(turn_around) and repeats.has(Vector2i(0, 0)))

	check("the first re-entry of a cell is flagged", first_repeats.size() > 0)

	# A THIRD pass still reads as repeat GROUND -- which is what suppresses the
	# earning, and so is what actually makes farming unprofitable -- but it does
	# NOT charge the flat penalty again, which is levied once per cell.
	var before := repeats.size()
	var before_first := first_repeats.size()
	r.request_reverse()
	while r.cell.x < 3:
		r.step(0.02)
	check("a third pass is still repeat ground",
		repeats.size() > before,
		"%d then %d" % [before, repeats.size()])
	check_eq("a third pass charges no further penalty",
		first_repeats.size(), before_first)

	# Gate and exit cells are tracked too. _on_enter_cell returns early on both,
	# so tracking placed after those returns would leave the solve path -- which
	# is exactly the ground a looping player re-covers -- free to farm.
	var gm := _make_corridor(12, true)
	gm.gates = [Vector2i(4, 0)] as Array[Vector2i]
	var gr := Racer.new()
	gr.setup(gm, u, 0)
	while gr.cell.x < 5 and not gr.finished:
		gr.step(0.02)
	check("a gate cell is recorded as visited", gr.visited.has(Vector2i(4, 0)))

	var er := Racer.new()
	er.setup(gm, u, 0)
	while not er.finished:
		er.step(0.02)
	check("the exit cell is recorded as visited", er.visited.has(gm.exit_cell))

	# The record is per maze, not per run: a new maze is new ground by
	# definition, so carrying it forward would charge the player for a
	# coincidence of grid coordinates between two unrelated mazes.
	var fresh := _make_corridor(12)
	r.setup(fresh, u, 1)
	check_eq("setup clears the visited record", r.visited.size(), 1)
	check("only the new start cell is marked", r.visited.has(fresh.start_cell))


func _test_legendaries() -> void:
	var u := Upgrades.new(11)

	# The tier is identifiable, and the ordinary lines are not in it.
	check("wall smasher is legendary", u.is_legendary(Upgrades.Line.WALL_SMASHER))
	check("flying vision is legendary", u.is_legendary(Upgrades.Line.FLYING_VISION))
	check("auto steer is legendary", u.is_legendary(Upgrades.Line.AUTO_STEER))
	check("buffer window is not legendary",
		not u.is_legendary(Upgrades.Line.BUFFER_WINDOW))
	check("score bonus is not legendary",
		not u.is_legendary(Upgrades.Line.SCORE_BONUS))

	check("a fresh build holds no legendary", not u.has_legendary())
	u.take(Upgrades.Line.WALL_SMASHER)
	check("taking one is detected", u.has_legendary())
	check_eq("the held legendary is reported",
		u.legendary_line(), Upgrades.Line.WALL_SMASHER)

	# ONE PER RUN: no other legendary may ever be offered again. This is the
	# rule the whole tier rests on, so it is checked exhaustively rather than
	# on a sample.
	var leaked := false
	for i in 400:
		for line in u.roll_cards(3):
			if u.is_legendary(line) and line != Upgrades.Line.WALL_SMASHER:
				leaked = true
	check("a second legendary is never offered", not leaked)

	# The one already held stays upgradeable.
	var upgradeable := false
	for i in 400:
		if Upgrades.Line.WALL_SMASHER in u.roll_cards(3):
			upgradeable = true
	check("the held legendary is still offered", upgradeable)

	# Cooldown scales by rank, and Auto-Steer scales duration instead.
	var cd := Upgrades.new(3)
	cd.take(Upgrades.Line.WALL_SMASHER)
	var cd1 := cd.legendary_cooldown()
	cd.take(Upgrades.Line.WALL_SMASHER)
	check("rank 2 cools down faster", cd.legendary_cooldown() < cd1)

	var au := Upgrades.new(3)
	au.take(Upgrades.Line.AUTO_STEER)
	var dur1 := au.auto_steer_duration()
	au.take(Upgrades.Line.AUTO_STEER)
	check("auto-steer rank 2 runs longer", au.auto_steer_duration() > dur1)

	# Rarity: an unstarted legendary must be genuinely rare in the draw.
	var seen := 0
	var draws := 3000
	for i in draws:
		var fresh := Upgrades.new(i + 1)
		for line in fresh.roll_cards(3):
			if fresh.is_legendary(line):
				seen += 1
	var rate := float(seen) / float(draws * 3)
	check("legendaries are rare in the draw", rate < 0.10,
		"%.1f%% of offered cards" % (rate * 100.0))
	check("legendaries do appear at all", seen > 0)

	_test_wall_smasher()
	_test_auto_steer()


func _test_wall_smasher() -> void:
	var m := Maze.new()
	m.generate(30, 30, 4242, 0.15, 0.02, 3, 0.5, 0.2, 0.0, 0.6)

	var u := Upgrades.new(1)
	u.take(Upgrades.Line.WALL_SMASHER)

	var r := Racer.new()
	r.setup(m, u, 0)

	# Find an interior cell with a wall ahead that is NOT the boundary.
	var found := false
	for y in range(1, m.height - 1):
		for x in range(1, m.width - 1):
			var c := Vector2i(x, y)
			for dir in Maze.DIRS:
				if m._has_wall(c, dir) and m._in_bounds(c + Maze.DIR_VECTORS[dir]):
					r.cell = c
					r.facing = dir
					r.progress = 0.0
					found = true
					break
			if found: break
		if found: break
	check("found an interior wall to smash", found)
	if not found:
		return

	var smash_rec := SignalRecorder.new()
	r.wall_smashed.connect(smash_rec.on_signal_two)
	var target := r.cell
	var dir_hit := r.facing
	var speed_before := r.speed

	for i in 400:
		r.step(0.01)
		if smash_rec.fired():
			break

	check("driving a wall down smashes it", smash_rec.fired())
	check("the racer did not crash", r.state == Racer.State.RUNNING)
	check("the wall is really gone", not m._has_wall(target, dir_hit))
	check("speed was kept", r.speed >= speed_before * 0.5,
		"%.2f from %.2f" % [r.speed, speed_before])
	check("the cooldown started", r.legendary_cooldown > 0.0)

	# The distance field must agree the hole exists, or the indicator points
	# players around a wall that is not there.
	check("distance field was rebuilt",
		m.get_distance(target) >= 0)

	# On cooldown it crashes normally again.
	var r2 := Racer.new()
	r2.setup(m, u, 0)
	r2.legendary_cooldown = 999.0
	var blocked := -1
	for y in range(1, m.height - 1):
		for x in range(1, m.width - 1):
			var c2 := Vector2i(x, y)
			for d in Maze.DIRS:
				if m._has_wall(c2, d) and m._in_bounds(c2 + Maze.DIR_VECTORS[d]):
					r2.cell = c2
					r2.facing = d
					blocked = d
					break
			if blocked != -1: break
		if blocked != -1: break
	if blocked != -1:
		for i in 600:
			r2.step(0.01)
			if r2.state == Racer.State.PARKED:
				break
		check("on cooldown it crashes normally", r2.state == Racer.State.PARKED)

	# The maze BOUNDARY must never break -- it turns the player around instead.
	var edge := Racer.new()
	edge.setup(m, u, 0)
	edge.cell = Vector2i(0, 5)
	edge.facing = Maze.W
	edge.progress = 0.0
	edge.legendary_cooldown = 0.0
	var facing_before := edge.facing
	for i in 400:
		edge.step(0.01)
		if edge.facing != facing_before:
			break
	check("the boundary turns you around instead of breaking",
		edge.facing == int(Maze.OPPOSITE[facing_before]))
	check("the racer is still inside the maze",
		edge.cell.x >= 0 and edge.cell.x < m.width)


func _test_auto_steer() -> void:
	var m := Maze.new()
	m.generate(30, 30, 77, 0.15, 0.02, 3, 0.5, 0.2, 0.0, 0.6)

	var u := Upgrades.new(1)
	u.take(Upgrades.Line.AUTO_STEER)

	var r := Racer.new()
	r.setup(m, u, 0)

	check("auto-steer starts when held and ready", r.start_auto_steer())
	check("the burst is running", r.auto_steer > 0.0)
	check("starting it puts it on cooldown", r.legendary_cooldown > 0.0)
	check("it cannot be restarted while cooling", not r.start_auto_steer())

	# It covers ground faster than an ordinary racer over the same window.
	var plain := Racer.new()
	plain.setup(m, Upgrades.new(1), 0)
	plain.speed = r.speed
	for i in 100:
		r.step(0.01)
		plain.step(0.01)
	check("auto-steer covers more ground",
		r.distance_travelled > plain.distance_travelled,
		"%.2f vs %.2f" % [r.distance_travelled, plain.distance_travelled])

	# Invulnerable: it can never crash while running.
	var safe := Racer.new()
	safe.setup(m, u, 0)
	safe.start_auto_steer()
	safe.barrier = 0.001
	for i in 200:
		safe.step(0.01)
		if safe.auto_steer <= 0.0:
			break
	check("auto-steer never crashes", safe.state == Racer.State.RUNNING)
	check("auto-steer takes no damage", safe.hp == Tuning.MAX_HP)

	# It expires on its own.
	var timed := Racer.new()
	timed.setup(m, u, 0)
	timed.start_auto_steer()
	for i in 2000:
		timed.step(0.01)
		if timed.auto_steer <= 0.0:
			break
	check("the burst ends by itself", timed.auto_steer <= 0.0)

	# A racer without the line cannot start one.
	var bare := Racer.new()
	bare.setup(m, Upgrades.new(1), 0)
	check("no auto-steer without the legendary", not bare.start_auto_steer())


func _test_gates() -> void:
	var m := _make_maze(40, 40, 0.15)

	check_eq("five gates placed", m.gates.size(), 5)

	# Gates must sit on the solve path -- that is what makes collecting them
	# engagement with the maze rather than a detour.
	var off_path := 0
	for gate in m.gates:
		if not m.solve_path.has(gate):
			off_path += 1
	check_eq("all gates on the solve path", off_path, 0)

	# And never on the start or exit.
	var on_endpoints := 0
	for gate in m.gates:
		if gate == m.start_cell or gate == m.exit_cell:
			on_endpoints += 1
	check_eq("no gate on start or exit", on_endpoints, 0)

	# Gates should be distinct and ordered along the path.
	var indices: Array[int] = []
	for gate in m.gates:
		indices.append(m.solve_path.find(gate))
	var ordered := true
	for i in range(indices.size() - 1):
		if indices[i] >= indices[i + 1]:
			ordered = false
	check("gates are spaced in order", ordered)

	_test_gates_cleared()


# A gate the player has already taken must stay KNOWN, not merely be dropped.
#
# The racer used to remove a gate from its pending list and forget it, so
# nothing downstream could tell a cleared gate from plain corridor -- the world
# marker was deleted and the minimap painted the cell as floor. In a looped maze
# "have I been here?" is the question the player is actually asking (CLAUDE.md
# section 6), and a gate is the single most recognisable answer to it.
#
# Asserted at the rules layer because `gates_cleared` is what both the mesh and
# the minimap read. It is a RECORD, not a rule: nothing about movement, turn
# resolution or the distance field may consult it, which is why the check below
# also confirms the pending list and the record stay disjoint -- a cell in both
# would let a gate be taken twice.
func _test_gates_cleared() -> void:
	var m := _make_corridor(12)
	# Two gates in the corridor's path. Placed by hand rather than by generation
	# so the test knows exactly which cells should end up recorded.
	m.gates = [Vector2i(3, 0), Vector2i(7, 0)] as Array[Vector2i]

	var r := _make_racer(m)
	check_eq("no gates cleared at the start", r.gates_cleared.size(), 0)

	# Drive east down the corridor, past both gates.
	for i in 600:
		r.step(1.0 / 60.0)

	check_eq("both gates recorded as cleared", r.gates_cleared.size(), 2)
	check_eq("cleared gates match gates_taken",
		r.gates_cleared.size(), r.gates_taken)
	check("the first gate is recorded by cell",
		r.gates_cleared.has(Vector2i(3, 0)))
	check("the second gate is recorded by cell",
		r.gates_cleared.has(Vector2i(7, 0)))

	# Order matters: the minimap does not care, but a cleared list that did not
	# follow the driving order would make any future "most recent gate" read
	# wrong, and it costs nothing to guarantee here.
	check_eq("cleared in the order taken", r.gates_cleared[0], Vector2i(3, 0))

	# A gate may never be both pending and cleared -- that would let it be taken
	# a second time and hand out a duplicate upgrade pick.
	var both := 0
	for cell in r.gates_cleared:
		if r._gate_cells.has(cell):
			both += 1
	check_eq("no gate is both pending and cleared", both, 0)

	# setup() must clear the record, or a gate taken in maze 1 would still be
	# drawn as visited in maze 2 -- the stale-reference trap section 12 records,
	# arriving through state rather than through a node handle.
	r.setup(m, Upgrades.new(1))
	check_eq("a new maze starts with nothing cleared", r.gates_cleared.size(), 0)

	_test_gate_index_is_placement()


# `gate_entered` must carry the gate's PLACEMENT in `maze.gates`, never a count
# of gates taken.
#
# The mesh names each marker "Gate<placement>", so the two numbers have to be
# the same thing or the wrong marker gets recoloured. They agree by accident on
# any maze driven in placement order, which is why this went unnoticed on maze 1
# -- 6% braid leaves few enough loops that the player meets the gates in the
# order they were laid down. In the loopier later mazes a player can reach a
# further gate first, and from that moment every recolour lands on a gate they
# have never driven through, while the one they just took stays lit.
#
# The minimap was correct throughout because it reads `gates_cleared`, a list of
# CELLS -- which is the lesson worth keeping: an index into a second array is a
# claim that two orderings agree, and this one did not.
func _test_gate_index_is_placement() -> void:
	var m := _make_corridor(12)
	m.gates = [Vector2i(7, 0), Vector2i(3, 0)] as Array[Vector2i]

	var r := _make_racer(m)
	var seen: Array[int] = []
	r.gate_entered.connect(func(i: int) -> void: seen.append(i))

	for i in 600:
		r.step(1.0 / 60.0)

	check_eq("both gates emitted", seen.size(), 2)
	if seen.size() == 2:
		# Driving east, cell (3,0) is met FIRST but is placed SECOND. A count
		# would emit 1 then 2; the placement emits 1 then 0.
		check_eq("the first gate driven emits its placement, not its ordinal",
			seen[0], 1)
		check_eq("the second gate driven emits its placement", seen[1], 0)

	# And the emitted index must actually name the cell that was driven through,
	# which is the property the mesh depends on.
	for i in mini(seen.size(), r.gates_cleared.size()):
		# Range-checked rather than indexed straight in. A wrong emission is
		# exactly what this test exists to catch, and an out-of-range index is
		# one of its shapes -- indexing blind turns that failure into a crashed
		# harness, which reports nothing about the other assertions after it.
		var placement: int = seen[i]
		check("emitted index is a real gate placement",
			placement >= 0 and placement < m.gates.size(),
			"got %d against %d gates" % [placement, m.gates.size()])
		if placement >= 0 and placement < m.gates.size():
			check_eq("emitted index resolves to the cell taken",
				m.gates[placement], r.gates_cleared[i])


# Pressed into a wall, the rendered position must stay INSIDE the cell.
#
# `_press_into_wall` pins progress to mean "hard against it" rather than to mean
# a position, and that same value drives world_position(). It used to pin at
# 1.0, which under the old centre-to-centre phase literally meant one whole cell
# forward -- so the player rendered inside the wall, or a full cell outside the
# maze when the wall was a boundary. First person hid it entirely; third person
# put the marker in the middle of the wall it was stopped at.
#
# Progress is now centred (-0.5..+0.5 about the cell centre) and the pin is the
# wall FACE, just under +0.5, so the pinned value is already a sane position and
# the clamp in world_position() is belt-and-braces. What must still hold is the
# thing this test was always really about: the marker never renders past the
# wall it is stopped at.
# Golden Trail: the ROUTE is the rule, the streak is just how it is drawn.
# Everything asserted here is pure logic and needs no rendered frame.
func _test_golden_trail() -> void:
	var u := Upgrades.new(1)
	check("no trail at rank 0", not u.has_trail())

	u.take(Upgrades.Line.GOLDEN_TRAIL)
	check("rank 1 enables the trail", u.has_trail())
	check_near("rank 1 interval", u.trail_interval(), 12.0)

	u.take(Upgrades.Line.GOLDEN_TRAIL)
	u.take(Upgrades.Line.GOLDEN_TRAIL)
	check_near("rank 3 interval", u.trail_interval(), 5.0)
	check("trail line caps at rank 3", u.is_maxed(Upgrades.Line.GOLDEN_TRAIL))

	# Rank drives the INTERVAL only. Length is no longer a rank table at all --
	# the trail runs the whole route and how far it is seen comes from the
	# racer's speed (section 7), so a test asserting a cell count per rank would
	# now be asserting a number the game does not have.
	var u2 := Upgrades.new(1)
	u2.take(Upgrades.Line.GOLDEN_TRAIL)
	var i1 := u2.trail_interval()
	u2.take(Upgrades.Line.GOLDEN_TRAIL)
	check("interval shortens with rank", u2.trail_interval() < i1)

	# Platinum is a separate line: taking one must not enable the other, or the
	# two would be one upgrade sold twice.
	var up := Upgrades.new(1)
	check("no platinum at rank 0", not up.has_platinum_trail())
	up.take(Upgrades.Line.GOLDEN_TRAIL)
	check("golden does not grant platinum", not up.has_platinum_trail())
	up.take(Upgrades.Line.PLATINUM_TRAIL)
	check("platinum rank 1 enables it", up.has_platinum_trail())
	check("platinum does not disturb golden", up.has_trail())
	check_near("platinum rank 1 interval", up.platinum_interval(), 15.0)
	up.take(Upgrades.Line.PLATINUM_TRAIL)
	check("platinum interval shortens with rank", up.platinum_interval() < 15.0)

	# Platinum fires less often than Golden at equal rank -- it answers the
	# bigger question, and a continuous readout of the whole solve would flatten
	# the maze. Read from Tuning rather than restated, so this checks the shape
	# of the two tables rather than transcribing them (section 12).
	var slower := true
	for r in range(1, Tuning.TRAIL_INTERVAL_BY_RANK.size()):
		if float(Tuning.PLATINUM_INTERVAL_BY_RANK[r]) <= float(Tuning.TRAIL_INTERVAL_BY_RANK[r]):
			slower = false
	check("platinum fires less often than golden at equal rank", slower)

	# The route must follow the live distance field, so it is correct even when
	# the player has stepped off the canonical path (section 6).
	var m := _make_branch(10, 3)
	var route := m.route_from(Vector2i(0, 0), 10)
	check("route starts at the given cell", route[0] == Vector2i(0, 0))
	check("route is more than one cell", route.size() > 1)
	check("route ends at the exit", route[route.size() - 1] == m.exit_cell)

	# Every step must be a legal move through an open wall -- a route that
	# jumps through geometry would draw a streak straight through a wall.
	var legal := true
	for i in route.size() - 1:
		var step: Vector2i = route[i + 1] - route[i]
		var found := false
		for dir in Maze.DIRS:
			if Maze.DIR_VECTORS[dir] == step and m.is_open(route[i], dir):
				found = true
		if not found:
			legal = false
	check("every route step passes through an opening", legal)

	# And each step must strictly approach the exit, never wander or loop.
	var descends := true
	for i in route.size() - 1:
		if m.get_distance(route[i + 1]) >= m.get_distance(route[i]):
			descends = false
	check("route strictly approaches the exit", descends)

	# Length is respected, and the +1 is the starting cell itself.
	var big := _make_maze(20, 20)
	var short_route := big.route_from(big.start_cell, 4)
	check("route honours the cell budget", short_route.size() <= 5)

	# A dead end with nowhere better to go yields no drawable route rather than
	# a zero-length streak that would flicker once per interval.
	var corridor := _make_corridor(6)
	var stuck := corridor.route_from(Vector2i(0, 0), 10)
	check("unreachable exit yields no route to draw", stuck.size() < 2)

	# --- The two trails never draw at once -----------------------------------
	#
	# They are the same ribbon shape on the same floor, and gates sit on the
	# solve path -- so most of the time both routes coincide and the near one
	# simply paints over the far one. A rendered frame showed exactly that:
	# gold over silver, the silver reading as a white smear beneath it.
	var maze_l := _make_maze(20, 20)
	var ur := Upgrades.new(1)
	for _i in 3:
		ur.take(Upgrades.Line.GOLDEN_TRAIL)
		ur.take(Upgrades.Line.PLATINUM_TRAIL)

	var rl := Racer.new()
	rl.setup(maze_l, ur, 0)

	var gold := GoldenTrail.new()
	var plat := GoldenTrail.new()
	gold.mode = GoldenTrail.Mode.GOLDEN
	plat.mode = GoldenTrail.Mode.PLATINUM
	gold.set_partner(plat)
	plat.set_partner(gold)

	# Past the gate threshold, so both lines are genuinely eligible -- otherwise
	# this would pass on the gate rule alone and assert nothing about the lock.
	rl.gates_taken = Tuning.PLATINUM_MIN_GATES

	var overlapped := false
	var plat_fired := false
	for _f in 3000:
		gold.update_state(rl, ur, 1.0 / 60.0)
		plat.update_state(rl, ur, 1.0 / 60.0)
		if gold.is_showing() and plat.is_showing():
			overlapped = true
		if plat.is_showing():
			plat_fired = true
	check("the two trails never draw simultaneously", not overlapped)
	# Guard against the assertion passing because platinum simply never fired:
	# "never overlaps" is trivially true of a line that never appears.
	check("platinum does fire past the gate threshold", plat_fired)

	gold.free()
	plat.free()

	# --- Platinum stays silent until the gate tour is done --------------------
	var early := Racer.new()
	early.setup(_make_maze(20, 20), ur, 0)
	early.gates_taken = Tuning.PLATINUM_MIN_GATES - 1

	var solo := GoldenTrail.new()
	solo.mode = GoldenTrail.Mode.PLATINUM
	var showed_early := false
	for _f in 3000:
		solo.update_state(early, ur, 1.0 / 60.0)
		if solo.is_showing():
			showed_early = true
	check("platinum never fires below the gate threshold", not showed_early)

	# And the very next gate switches it on, so the threshold is a real edge
	# rather than a line that simply never runs.
	early.gates_taken = Tuning.PLATINUM_MIN_GATES
	var showed_after := false
	for _f in 3000:
		solo.update_state(early, ur, 1.0 / 60.0)
		if solo.is_showing():
			showed_after = true
	check("platinum fires once the threshold is reached", showed_after)
	solo.free()

	# Golden is NOT gated -- it is the line that answers the gate tour, so
	# gating it on gates taken would silence it exactly when it is wanted.
	var g0 := Racer.new()
	g0.setup(_make_maze(20, 20), ur, 0)
	var gsolo := GoldenTrail.new()
	gsolo.mode = GoldenTrail.Mode.GOLDEN
	var gold_early := false
	for _f in 3000:
		gsolo.update_state(g0, ur, 1.0 / 60.0)
		if gsolo.is_showing():
			gold_early = true
	check("golden fires with no gates taken", gold_early)
	gsolo.free()

	# --- route_to: the Golden Trail's gate routing ---------------------------
	#
	# route_from descends the distance field, which knows exactly one
	# destination. A gate is not on that gradient, so this is the rule that
	# makes "the trail goes through the gates" expressible at all.
	var line := _make_corridor(8, true)
	var to_mid := line.route_to(Vector2i(0, 0), Vector2i(5, 0))
	check("route_to starts at the given cell", to_mid.size() > 0 and to_mid[0] == Vector2i(0, 0))
	check("route_to ends at the target", to_mid[to_mid.size() - 1] == Vector2i(5, 0))
	check_eq("route_to is the shortest path", to_mid.size(), 6)

	# Every step legal, same requirement route_from has: a route that jumped
	# through geometry would draw a ribbon straight through a wall.
	var to_legal := true
	for i in to_mid.size() - 1:
		var st: Vector2i = to_mid[i + 1] - to_mid[i]
		var ok := false
		for dir in Maze.DIRS:
			if Maze.DIR_VECTORS[dir] == st and line.is_open(to_mid[i], dir):
				ok = true
		if not ok:
			to_legal = false
	check("every route_to step passes through an opening", to_legal)

	# Standing on the target is "nowhere to go", which _fire skips rather than
	# drawing a zero-length streak.
	check_eq("route_to onto own cell is a single cell",
		line.route_to(Vector2i(3, 0), Vector2i(3, 0)).size(), 1)

	# An unreachable target yields NO route rather than a wrong one. A trail
	# that quietly pointed at the closest thing it could reach would be
	# advice, and false advice is worse than none (section 7).
	var split := _make_corridor(4)
	check("unreachable target yields no route",
		split.route_to(Vector2i(0, 0), Vector2i(99, 99)).size() == 0)

	# The trail must aim at a gate that is genuinely NOT down the exit
	# gradient, which is the whole reason route_to exists. On a real maze,
	# routing to a gate and routing to the exit must be able to disagree.
	var real := _make_maze(20, 20)
	if not real.gates.is_empty():
		var gate: Vector2i = real.gates[0]
		var to_gate := real.route_to(real.start_cell, gate)
		check("route to a real gate reaches it",
			to_gate.size() > 1 and to_gate[to_gate.size() - 1] == gate)
		# And it is the SHORTEST such route: no step may be skippable. BFS
		# guarantees this by construction, so the check is that the
		# construction was not quietly broken -- a parent map walked back
		# wrongly still terminates and still yields a connected path.
		check_eq("route to a gate is shortest",
			to_gate.size(), _bfs_length(real, real.start_cell, gate))


# An INDEPENDENT shortest-path length, so the route_to assertion is checked
# against a second implementation rather than against itself. A distance-only
# flood cannot share route_to's parent-map bug, which is the class of error
# most likely to survive a test written from the same code.
func _bfs_length(m: Maze, from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 1
	var dist := {}
	dist[from] = 1
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for dir in Maze.DIRS:
			if not m.is_open(current, dir):
				continue
			var next: Vector2i = current + Maze.DIR_VECTORS[dir]
			if dist.has(next):
				continue
			dist[next] = int(dist[current]) + 1
			if next == to:
				return int(dist[next])
			queue.append(next)
	return 0


func _test_wall_position() -> void:
	var m := _make_corridor(4)
	var r := _make_racer(m)

	# Drive east to the far end and press into the closing wall.
	for i in 400:
		r.step(0.05)
		if not m.is_open(r.cell, r.facing):
			break

	check("racer reached the end wall", not m.is_open(r.cell, r.facing))

	# Press until pinned.
	#
	# Entering the blocked cell is no longer the same event as being pinned
	# against its far wall -- the racer drives ACROSS that cell first, which is
	# what stops the marker teleporting to the wall face on entry (see
	# _test_last_cell_before_a_wall). So this waits for the scrape rather than
	# assuming a couple of frames is enough; five frames of 0.02s covers a tenth
	# of a cell, and the racer has most of a cell still to cover.
	var spin := 0
	while not r.scraping and r.state == Racer.State.RUNNING and spin < 500:
		r.step(0.02)
		spin += 1
	check("racer became pinned against the wall", r.scraping or r.state == Racer.State.PARKED,
		"after %d frames" % spin)

	# Pinned at the wall face -- hard against the wall, and still inside the
	# cell. Asserted against _wall_face_progress()'s own inputs rather than a
	# transcribed literal, so this stays an assertion about the rule rather than
	# a check that two numbers were typed the same (section 12).
	var face: float = (Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5
		- Tuning.MARKER_RADIUS) / Tuning.CELL_SIZE
	check_near("progress pins at the wall face for the rules", r.progress, face)
	check("the pin stays inside the cell", r.progress < 0.5)

	var pos := r.world_position()
	var centre := Vector3(r.cell.x * Tuning.CELL_SIZE, pos.y, r.cell.y * Tuning.CELL_SIZE)
	var out := Vector2(pos.x - centre.x, pos.z - centre.z).length()
	var limit: float = Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5

	check("rendered position stays inside the cell", out < limit,
		"%.2f from centre, wall face is at %.2f" % [out, limit])
	check("rendered position does not sit in the wall", out <= limit - Tuning.MARKER_RADIUS + 0.01,
		"%.2f leaves the marker inside the wall" % out)


func _test_indicator() -> void:
	var m := _make_branch(10, 3)
	var r := _make_racer(m)

	# In the branch corridor the exit is south-east, so from cell 3 the correct
	# move is the southward branch -- a right turn from east.
	while r.cell.x < 3:
		r.step(0.05)

	check_eq("indicator points right at the branch", r.correct_relative_turn(), 1)

	# In a plain corridor the answer is straight ahead.
	var straight := _make_racer(_make_corridor(10, true))
	check_eq("indicator says straight in a corridor", straight.correct_relative_turn(), 0)


# The three-way branch classification the Path Indicator paints (section 7).
#
# This is the rule behind a COLOUR the player reads and routes on, so it belongs
# in the rules layer and gets asserted here rather than being trusted to look
# right in a screenshot. The case worth protecting is the middle one: a branch
# that is not optimal but genuinely reaches the exit must come back VIABLE, not
# BAD. Collapsing it into "wrong" would tell the player to reverse out of a
# corridor that works, which is the misread the third colour exists to prevent.
func _test_branch_quality() -> void:
	# A corridor east with a southward branch at x=3 that holds the exit.
	var m := _make_branch(10, 3)
	var j := Vector2i(3, 0)

	check_eq("branch onto the exit is BEST",
		m.branch_quality(j, Maze.S), Maze.Branch.BEST)
	check_eq("corridor past the exit branch is BAD",
		m.branch_quality(j, Maze.E), Maze.Branch.BAD)
	check_eq("a solid side is BAD",
		m.branch_quality(j, Maze.N), Maze.Branch.BAD)

	# A loop: both ways round reach the exit, one of them longer.
	var loop := _make_loop()
	var top := Vector2i(0, 0)
	check_eq("the short way round a loop is BEST",
		loop.branch_quality(top, Maze.S), Maze.Branch.BEST)
	check_eq("the long way round a loop is VIABLE",
		loop.branch_quality(top, Maze.E), Maze.Branch.VIABLE)

	# Across a real generated maze, every BEST branch must be as short as the
	# one best_direction() picks -- the green strip and the Golden Trail read
	# the same field and can never be allowed to disagree about the way out.
	#
	# Matched on DISTANCE, not on direction. A braided maze has ties, where two
	# openings both cut the distance by one and are genuinely equally optimal;
	# best_direction() returns whichever it scanned first, which is an
	# implementation detail and not a statement that the other way is worse.
	# Green on both is the honest answer -- painting one of them yellow would
	# send the player down a route that is not slower, teaching them the colours
	# lie.
	var big := _make_maze(20, 20, 0.15, 99)
	var worse := 0
	var bests := 0
	var ties := 0
	for y in big.height:
		for x in big.width:
			var cell := Vector2i(x, y)
			var best := big.best_direction(cell)
			if best == -1:
				continue
			var best_dist := big.get_distance(cell + Maze.DIR_VECTORS[best])
			var here := 0
			for dir in Maze.DIRS:
				var d := int(dir)
				if big.branch_quality(cell, d) != Maze.Branch.BEST:
					continue
				bests += 1
				here += 1
				if big.get_distance(cell + Maze.DIR_VECTORS[d]) != best_dist:
					worse += 1
			if here > 1:
				ties += 1
	check("BEST branches exist to check", bests > 0, "found %d" % bests)
	check("every BEST branch is as short as best_direction", worse == 0,
		"%d were longer" % worse)
	# Not a requirement, just proof the tie case above is real and being
	# exercised rather than reasoned about in the abstract.
	check("ties are actually present in a braided maze", ties > 0,
		"%d cells had two equally-best ways on" % ties)


# A 2x2 ring: every cell connects to two neighbours, so from the top-left both
# ways round arrive at the exit and exactly one of them is shorter.
func _make_loop() -> Maze:
	var m := Maze.new()
	m.width = 2
	m.height = 2
	m.cells = PackedInt32Array()
	m.cells.resize(4)
	m.cells.fill(Maze.N | Maze.E | Maze.S | Maze.W)
	m.start_cell = Vector2i(0, 0)
	m.exit_cell = Vector2i(0, 1)
	m._knock_wall(Vector2i(0, 0), Maze.E)
	m._knock_wall(Vector2i(1, 0), Maze.S)
	m._knock_wall(Vector2i(0, 1), Maze.E)
	m._knock_wall(Vector2i(0, 0), Maze.S)
	m._build_distance_field()
	m._build_solve_path()
	return m


# --- Landmarks (docs/specs/landmarks.md) -------------------------------------

# Landmarks are DECORATION and must never touch the rules.
#
# The safety argument for the whole feature has two halves and this covers both:
#
#   1. They carry no navigational information. Placement ignores the solve path,
#      the distance field, the gates and the exit -- otherwise free scenery
#      would cannibalise Path Indicator, Gate Compass and Golden Trail, all
#      three of which are PAID lines sold on answering "which way".
#
#   2. They do not influence movement. This is the failure mode hardest to
#      notice, because landmark data hangs off the Maze and so is REACHABLE from
#      the rules layer even though it must never be used there -- the same trap
#      lanes have (CLAUDE.md section 12), asserted the same way.
func _test_landmarks() -> void:
	var cfg: Dictionary = Tuning.MAZES[0]

	var decorated := Maze.new()
	decorated.generate(24, 24, 4242, cfg["braid"], cfg["dead_ends"], 4,
		cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0), 0.5)

	check("landmarks are placed", decorated.landmarks.size() > 0,
		"got %d" % decorated.landmarks.size())

	# --- The maze itself must be identical with and without them --------------
	#
	# Landmarks run on their OWN RNG stream for this reason: sharing the carve
	# generator would mean the density knob silently redraws every maze in the
	# game, because each extra draw shifts the whole downstream sequence.
	var bare := Maze.new()
	bare.generate(24, 24, 4242, cfg["braid"], cfg["dead_ends"], 4,
		cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0), 0.0)

	check("landmarks do not perturb the carve", bare.cells == decorated.cells)
	check("landmarks do not perturb the distance field",
		bare.distance_field == decorated.distance_field)
	check_eq("landmarks do not perturb the gates", bare.gates, decorated.gates)
	check_eq("a density of zero places none", bare.landmarks.size(), 0)

	# --- Reproducible from the seed ------------------------------------------
	var again := Maze.new()
	again.generate(24, 24, 4242, cfg["braid"], cfg["dead_ends"], 4,
		cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0), 0.5)
	check_eq("landmark placement is reproducible from the seed",
		again.landmarks.size(), decorated.landmarks.size())

	var identical := true
	for i in decorated.landmarks.size():
		if (again.landmarks[i]["cell"] != decorated.landmarks[i]["cell"]
				or again.landmarks[i]["type"] != decorated.landmarks[i]["type"]):
			identical = false
			break
	check("the same seed places the same landmarks", identical)

	# --- Never in a cell the player drives through ---------------------------
	#
	# Collision is deliberately not modelled: the barrier and crash rules are
	# defined against maze WALLS only (section 5), and a second class of solid
	# thing would mean two collision systems disagreeing at speed. That is only
	# safe because landmarks sit where the player cannot pass through them.
	var on_route := {}
	for c in decorated.solve_path:
		on_route[c] = true

	var blocking := 0
	var on_solve := 0
	var on_gate := 0
	for landmark in decorated.landmarks:
		var cell: Vector2i = landmark["cell"]
		var inside := (cell.x >= 0 and cell.x < decorated.width
			and cell.y >= 0 and cell.y < decorated.height)
		if not inside:
			continue
		# A through-corridor has two or more exits, so the player can drive
		# straight across it. Only sealed pockets (0) and dead ends (1) qualify.
		if decorated.open_directions(cell).size() >= 2:
			blocking += 1
		if on_route.has(cell):
			on_solve += 1
		if decorated.gates.has(cell):
			on_gate += 1

	check_eq("no landmark sits in a through-corridor", blocking, 0)
	check_eq("no landmark sits on the solve path", on_solve, 0)
	check_eq("no landmark sits on a gate", on_gate, 0)

	var on_ends := 0
	for landmark in decorated.landmarks:
		var cell: Vector2i = landmark["cell"]
		if cell == decorated.start_cell or cell == decorated.exit_cell:
			on_ends += 1
	check_eq("no landmark sits on the start or exit", on_ends, 0)

	# --- Placement carries no directional information ------------------------
	#
	# If a landmark correlated with distance-to-exit, spotting one over the wall
	# line would be a free Gate Compass. Compare the mean distance-to-exit of
	# landmark cells against the maze as a whole: uncorrelated placement should
	# land near the middle of the range, not clustered at either end.
	var landmark_total := 0.0
	var landmark_n := 0
	for landmark in decorated.landmarks:
		var cell: Vector2i = landmark["cell"]
		if cell.x < 0 or cell.x >= decorated.width or cell.y < 0 or cell.y >= decorated.height:
			continue
		var d := decorated.get_distance(cell)
		if d >= 0:
			landmark_total += float(d)
			landmark_n += 1

	var maze_total := 0.0
	var maze_n := 0
	var furthest := 0
	for y in decorated.height:
		for x in decorated.width:
			var d := decorated.get_distance(Vector2i(x, y))
			if d >= 0:
				maze_total += float(d)
				maze_n += 1
				furthest = maxi(furthest, d)

	if landmark_n > 0 and maze_n > 0:
		var landmark_mean := landmark_total / float(landmark_n)
		var maze_mean := maze_total / float(maze_n)
		# Generous tolerance: this is asserting the ABSENCE of a signal, and
		# with a few dozen samples ordinary scatter is wide. A real correlation
		# -- landmarks placed near gates, say -- would move the mean far more
		# than a fifth of the maze's depth.
		check("landmark placement does not correlate with distance to exit",
			absf(landmark_mean - maze_mean) < float(furthest) * 0.2,
			"landmarks mean %.1f vs maze mean %.1f, depth %d" % [
				landmark_mean, maze_mean, furthest])

	# --- Types and tiers ------------------------------------------------------
	for i in Tuning.LANDMARK_TYPES.size():
		var config: Dictionary = Tuning.LANDMARK_TYPES[i]
		if bool(config["skyline"]):
			# A skyline landmark that does not clear the wall line is not a
			# skyline landmark -- the tier exists precisely so that something
			# is visible from the next corridor over. The camera is capped
			# BELOW WALL_HEIGHT on purpose, so height is the only way a
			# landmark becomes visible at distance.
			check("skyline type '%s' clears the wall line" % config["name"],
				float(config["height"]) >= Tuning.LANDMARK_SKYLINE_MIN,
				"%.1f, needs %.1f" % [config["height"], Tuning.LANDMARK_SKYLINE_MIN])
		else:
			check("local type '%s' stays under the wall line" % config["name"],
				float(config["height"]) < Tuning.WALL_HEIGHT,
				"%.1f, wall is %.1f" % [config["height"], Tuning.WALL_HEIGHT])

	# Landmarks must never out-glow the navigation markers. Gates and the exit
	# have to stay the most eye-catching things in the maze, because they are
	# navigation and landmarks explicitly are not.
	#
	# Compared against the GATE marker's own emission rather than a literal, so
	# this stays a real assertion instead of a transcription of a number that
	# drifts (CLAUDE.md section 12). A first version hard-coded "< 1.0" and went
	# red the moment the landmark glow was raised to be visible through fog --
	# telling us only that two constants had diverged, not that anything was
	# wrong.
	var gate_emission := 2.0
	check("landmarks never out-glow the gate markers",
		Tuning.LANDMARK_EMISSION < gate_emission,
		"%.2f vs gate %.2f" % [Tuning.LANDMARK_EMISSION, gate_emission])
	# But bright enough to survive the fog -- at 0.55 a skyline landmark four
	# cells out was a dim grey speck.
	check("landmarks glow enough to read through fog",
		Tuning.LANDMARK_EMISSION > 0.8, "%.2f" % Tuning.LANDMARK_EMISSION)

	# Every maze must actually get some, or the feature silently switches off in
	# exactly the big braided mazes that need it most.
	for i in Tuning.MAZES.size():
		var density := float(Tuning.MAZES[i].get("landmarks", Tuning.LANDMARK_DENSITY))
		check("maze %d has a landmark density" % i, density > 0.0,
			"%s is %.2f" % [Tuning.MAZES[i]["name"], density])


# Movement must be bit-identical whether landmarks exist or not.
#
# Driven side by side rather than checked structurally, because the failure this
# guards against is a rule QUIETLY starting to read `landmarks` -- which a
# structural check would not see. Two racers on the same maze, one decorated and
# one not, must trace the same path forever.
func _test_landmarks_do_not_move_the_racer() -> void:
	var cfg: Dictionary = Tuning.MAZES[0]

	var bare := Maze.new()
	bare.generate(20, 20, 77, cfg["braid"], cfg["dead_ends"], 3,
		cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0), 0.0)

	var decorated := Maze.new()
	decorated.generate(20, 20, 77, cfg["braid"], cfg["dead_ends"], 3,
		cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0), 0.6)

	var a := _make_racer(bare)
	var b := _make_racer(decorated)

	var diverged := false
	for i in 400:
		# Same inputs to both, including turns, so the comparison exercises turn
		# resolution and the buffer rather than just straight-line travel.
		if i % 37 == 0:
			a.request_turn(1)
			b.request_turn(1)
		elif i % 53 == 0:
			a.request_turn(-1)
			b.request_turn(-1)

		a.step(0.02)
		b.step(0.02)

		if a.cell != b.cell or absf(a.progress - b.progress) > 0.0001 or a.facing != b.facing:
			diverged = true
			break

	check("landmarks do not change how the racer moves", not diverged)
	check("landmarks do not change speed", absf(a.speed - b.speed) < 0.0001,
		"%.4f vs %.4f" % [a.speed, b.speed])
	check("landmarks do not change the barrier", absf(a.barrier - b.barrier) < 0.0001)


# Gate and exit markers must rise ABOVE the wall line.
#
# This is the whole reason they are physical objects in the world rather than a
# HUD readout: a gate sits on the solve path and pauses the timer, so the player
# is routing TOWARD it and needs to see it coming from a couple of corridors
# away. At 0.9x WALL_HEIGHT it sat just UNDER the walls and was invisible until
# the player was already in its corridor -- no warning at all at a speed where a
# cell passes in 125ms.
#
# The camera is capped below WALL_HEIGHT on purpose (CLAUDE.md section 12), so
# height is the ONLY way anything becomes visible from the next corridor over --
# the same argument the skyline landmark tier rests on.
func _test_marker_heights() -> void:
	check("gate markers clear the wall line",
		Tuning.GATE_MARKER_HEIGHT > 1.0,
		"%.2f x WALL_HEIGHT" % Tuning.GATE_MARKER_HEIGHT)
	check("exit markers clear the wall line",
		Tuning.EXIT_MARKER_HEIGHT > 1.0,
		"%.2f x WALL_HEIGHT" % Tuning.EXIT_MARKER_HEIGHT)

	# The exit stays taller than a gate. Now that BOTH clear the walls, height is
	# what separates them at distance -- a gate is a waypoint, the exit ends the
	# maze, and mistaking one for the other at speed is a real routing error.
	check("the exit stands taller than a gate",
		Tuning.EXIT_MARKER_HEIGHT > Tuning.GATE_MARKER_HEIGHT,
		"exit %.2f vs gate %.2f" % [Tuning.EXIT_MARKER_HEIGHT, Tuning.GATE_MARKER_HEIGHT])

	# But not so tall they read as part of the skyline rather than as a marker
	# inside the maze.
	check("markers stay under a sane ceiling",
		Tuning.EXIT_MARKER_HEIGHT < 5.0,
		"%.2f x WALL_HEIGHT" % Tuning.EXIT_MARKER_HEIGHT)


