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
	_test_seeding()
	_test_turn_resolution()
	_test_double_tap()
	_test_buffer_expiry()
	_test_barrier_grace()
	_test_crash_and_unstick()
	_test_reverse()
	_test_speed_ramp()
	_test_upgrades()
	_test_gates()
	_test_indicator()
	_test_golden_trail()
	_test_wall_position()
	_test_lanes()
	_test_turn_keeps_progress()
	_test_entry_corridor_lockout()

	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


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
	check("a turn kicks the lane off centre", absf(r.lane) > 0.5,
		"lane %.2f" % r.lane)
	check("the kick is toward the OUTSIDE of the turn", r.lane > 0.0,
		"turning left should throw right of the new heading, got %.2f" % r.lane)
	check_eq("the kick did not move the racer's cell", r.cell, before_cell)
	check_near("the kick did not move progress", r.progress, before_progress)

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

	func on_signal() -> void:
		count += 1

	func on_signal_arg(arg) -> void:
		count += 1
		last_arg = arg

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
	r.step(0.6)
	var before := r.progress
	check("moved partway into the cell", before > 0.3 and before < 1.0,
		"progress %.3f" % before)

	var cell_before := r.cell
	r.request_turn(-1)

	check_near("a turn preserves progress", r.progress, before)
	check_eq("a turn does not change cell", r.cell, cell_before)


# After a turn, the corridor just left must not be immediately re-enterable.
#
# Otherwise a second press at a crossroads folds the racer straight back the way
# it came -- a 180 the player neither asked for nor paid for. A turn should
# always take the NEXT available opening.
#
# The 180 itself is exempt: going back IS what that input means.
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
	while r3.progress < 0.7:
		r3.step(0.01)
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

	# Hold against the wall for 0.2s -- well inside the 0.5s base barrier.
	for i in 20:
		r.step(0.01)

	check("no crash yet -- barrier is holding", not crash_rec.fired())
	check("barrier is draining", r.barrier < r.upgrades.barrier_capacity())
	check_eq("scraping costs no hp", r.hp, Tuning.MAX_HP)
	check("still running while scraping", r.state == Racer.State.RUNNING)

	# The payoff: turning out before the barrier empties costs NOTHING. This is
	# the skill expression the whole design rests on (CLAUDE.md section 5.1).
	var clean := _make_racer(_make_corridor(3))
	for i in 400:
		clean.step(0.01)
		if clean.scraping:
			break
	for i in 20:
		clean.step(0.01)
	var hp_before := clean.hp
	clean.request_reverse()
	check_eq("escaping the wall costs no hp", clean.hp, hp_before)
	check_eq("escaping the wall causes no crash", clean.crash_count, 0)


func _test_crash_and_unstick() -> void:
	var m := _make_corridor(3)
	var r := _make_racer(m)

	var crash_rec := record(r.crashed)

	# ~2s of travel to reach the wall, then 0.5s of barrier before the crash.
	for i in 600:
		r.step(0.01)
		if crash_rec.fired():
			break

	check("barrier depletion causes a crash", crash_rec.fired())
	check_eq("crash parks the racer", r.state, Racer.State.PARKED)
	check_eq("crash deals damage", r.hp, Tuning.MAX_HP - 1)
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

	# Wall armor must never heal.
	var armored := Upgrades.new(1)
	for i in 3:
		armored.take(Upgrades.Line.WALL_ARMOR)
	check("wall damage floors at zero", armored.wall_damage() >= 0)

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


# Pressed into a wall, the rendered position must stay INSIDE the cell.
#
# `_press_into_wall` pins progress at 1.0 to mean "hard against it", but that
# value also drives world_position, where 1.0 literally means one whole cell
# forward -- so the player rendered inside the wall, or a full cell outside the
# maze when the wall was a boundary. First person hid it entirely; third person
# put the marker in the middle of the wall it was stopped at.
#
# The clamp is display-only, so this also checks the simulation value is
# untouched: the rules depend on progress reaching 1.0.
# Golden Trail: the ROUTE is the rule, the streak is just how it is drawn.
# Everything asserted here is pure logic and needs no rendered frame.
func _test_golden_trail() -> void:
	var u := Upgrades.new(1)
	check("no trail at rank 0", not u.has_trail())

	u.take(Upgrades.Line.GOLDEN_TRAIL)
	check("rank 1 enables the trail", u.has_trail())
	check_near("rank 1 interval", u.trail_interval(), 12.0)
	check_near("rank 1 length", u.trail_cells(), 10.0)

	u.take(Upgrades.Line.GOLDEN_TRAIL)
	u.take(Upgrades.Line.GOLDEN_TRAIL)
	check_near("rank 3 interval", u.trail_interval(), 5.0)
	check_near("rank 3 length", u.trail_cells(), 20.0)
	check("trail line caps at rank 3", u.is_maxed(Upgrades.Line.GOLDEN_TRAIL))

	# Both scale together, and both in the direction that makes the upgrade
	# stronger: shorter interval, longer trail.
	var u2 := Upgrades.new(1)
	u2.take(Upgrades.Line.GOLDEN_TRAIL)
	var i1 := u2.trail_interval()
	var c1 := u2.trail_cells()
	u2.take(Upgrades.Line.GOLDEN_TRAIL)
	check("interval shortens with rank", u2.trail_interval() < i1)
	check("length grows with rank", u2.trail_cells() > c1)

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
	for i in 5:
		r.step(0.02)

	check_eq("progress still pins at 1.0 for the rules", r.progress, 1.0)

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
