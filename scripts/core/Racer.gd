# The player simulation: position, facing, speed, buffer, barrier, penalties.
#
# Deliberately node-free and renderer-free so the whole rule set stays headlessly
# testable (CLAUDE.md section 12). The 3D scene reads this state and draws it; it
# never owns any of it.
#
# CLAUDE.md sections 2, 3, 4, 5.
class_name Racer
extends RefCounted

signal turned(direction: int)
signal reversed()
signal slowdown()          # an expired turn input
signal scraped()           # barrier began draining
signal crashed()
signal unstuck()
signal gate_entered(index: int)
signal exit_reached()

enum State { RUNNING, PARKED }

var maze: Maze
var upgrades: Upgrades

var state: int = State.RUNNING

# Grid position. `cell` is the cell being travelled through; `progress` is how
# far across it we are, 0..1, along `facing`.
var cell: Vector2i
var facing: int = Maze.E
var progress: float = 0.0

var speed: float = Tuning.SPEED_FLOOR
var hp: int = Tuning.MAX_HP
var barrier: float = Tuning.BASE_BARRIER

# Pending turn: the direction requested and how much buffer (in cells) is left
# before it expires.
# Lateral position within the corridor, in lanes: -LANE_MAX..+LANE_MAX, 0 being
# the centre line. Negative is to the LEFT of the direction of travel.
#
# Display only. No rule reads it -- the maze graph, turn resolution, the buffer
# and the barrier all work in whole cells, which is what keeps the simulation
# headlessly testable (CLAUDE.md section 12). It exists so a corner reads as an
# arc with weight rather than an instant snap.
var lane: float = 0.0

var pending_turn: int = -1
var pending_buffer: float = 0.0

# True while the player is pressed into a wall and the barrier is draining.
var scraping := false

# Set when a turn resolved instantly inside the current cell, cleared on entering
# a new one. An immediate turn CONSUMES the cell: a second press before the next
# boundary must arm the buffer instead of firing again. Without this, two fast
# presses in an open junction both resolved on the spot and two lefts became a
# 180 -- a double-tap while rounding a corner spun the player back the way they
# came, which is the opposite of what they asked for.
var _turned_in_cell := false

# The direction the racer would travel to go BACK the way it just turned from.
# -1 when nothing is locked out.
#
# Turning does not clear the corridor you came out of, so at a crossroads a
# second press could immediately fold the racer back into the corridor it just
# left -- two lefts in quick succession being a 180 by another name. A turn
# should always take the NEXT available opening, never the one behind. So the
# entry corridor is locked out of turn resolution until the racer leaves the
# cell it turned in.
#
# A 180 is exempt: it is an explicit, expensive, always-legal input, and going
# back is precisely what the player asked for (CLAUDE.md section 2).
var _entry_lockout: int = -1

var distance_travelled := 0.0
var crash_count := 0
var slowdown_count := 0

var gates_taken := 0
var _gate_cells: Array[Vector2i] = []

var finished := false


func setup(p_maze: Maze, p_upgrades: Upgrades) -> void:
	maze = p_maze
	upgrades = p_upgrades

	cell = maze.start_cell
	progress = 0.0
	state = State.RUNNING
	finished = false

	# Face whichever way is actually open from the start cell, preferring the
	# route toward the exit so the player never begins staring at a wall.
	var best := maze.best_direction(cell)
	if best != -1:
		facing = best
	else:
		var open := maze.open_directions(cell)
		facing = open[0] if not open.is_empty() else Maze.E

	speed = upgrades.speed_floor()
	barrier = upgrades.barrier_capacity()
	pending_turn = -1
	pending_buffer = 0.0
	lane = 0.0
	scraping = false
	_turned_in_cell = false
	_entry_lockout = -1

	_gate_cells = maze.gates.duplicate()
	gates_taken = 0


# --- Input -------------------------------------------------------------------

func request_turn(direction_key: int) -> void:
	# direction_key is -1 for left, +1 for right, relative to current facing.
	if state == State.PARKED:
		return

	var direction := _relative_direction(direction_key)

	# If the requested side is open RIGHT HERE, take it immediately rather than
	# waiting for the next cell boundary. The opening out of the current cell is
	# available for as long as the racer is in that cell, so a press inside the
	# junction must take it -- deferring to the boundary would sail the player
	# straight past the opening they were aiming at.
	#
	# ONE such turn per cell, though. The second press in the same cell falls
	# through to the buffer below and resolves at the next boundary like any
	# other early input -- see _turned_in_cell.
	if _may_turn_into(direction) and not _turned_in_cell:
		_turn_into(direction)
		if scraping:
			scraping = false
		return

	pending_turn = direction
	pending_buffer = upgrades.buffer_cells()


func request_reverse() -> void:
	if state == State.PARKED:
		# The un-stick input. Same key as the 180, deliberately: the crash
		# recovery IS a turnaround (CLAUDE.md section 2).
		_unstick()
		return

	facing = int(Maze.OPPOSITE[facing])
	# Reversing mid-cell means the distance already covered is now behind us.
	progress = 1.0 - progress
	_apply_speed_cost(upgrades.reverse_cost())
	pending_turn = -1
	# A 180 is an explicit, expensive, always-legal input -- it is never the
	# accidental second tap these lockouts guard against, and the racer is now
	# facing the other way, so the cell is fresh again. Going back down the
	# corridor it came from is exactly what the player asked for, so the entry
	# lockout lifts too.
	_turned_in_cell = false
	_entry_lockout = -1
	reversed.emit()


# --- Simulation --------------------------------------------------------------

func step(delta: float) -> void:
	if finished:
		return

	if state == State.PARKED:
		# Parked: no ramp, no movement. The barrier holds until un-stick so the
		# player is not punished twice for sitting where the game put them.
		return

	_advance_speed(delta)
	_recover_lane(delta)

	var moved := speed * Tuning.BASE_CELL_RATE * delta

	if maze.is_open(cell, facing):
		_travel(moved, delta)
	else:
		_press_into_wall(moved, delta)


# Speed accrues with time-not-crashing. Recovery from a crash climbs at 2.5x
# until it reaches the floor (CLAUDE.md section 3).
func _advance_speed(delta: float) -> void:
	var floor_speed := upgrades.speed_floor()
	var rate := Tuning.SPEED_RAMP_PER_SEC

	if speed < floor_speed:
		rate *= Tuning.RECOVERY_RAMP_MULTIPLIER

	speed = minf(speed + rate * delta, Tuning.SPEED_CAP)


func _travel(moved: float, delta: float) -> void:
	if scraping:
		scraping = false

	# Barrier regenerates whenever not in contact.
	barrier = minf(barrier + upgrades.barrier_regen() * delta, upgrades.barrier_capacity())

	var remaining := moved

	# A single frame at high speed can cross more than one cell boundary, so
	# resolve boundaries in a loop rather than once.
	while remaining > 0.0:
		var to_boundary := 1.0 - progress

		if remaining < to_boundary:
			progress += remaining
			_consume_buffer(remaining)
			distance_travelled += remaining
			remaining = 0.0
			break

		# Reached the next cell boundary.
		progress = 0.0
		remaining -= to_boundary
		distance_travelled += to_boundary

		cell = cell + Maze.DIR_VECTORS[facing]
		# A new cell means a new immediate turn is allowed, and the corridor the
		# racer turned out of is now a cell behind -- no longer the thing a
		# press could fold back into. Cleared here rather than in
		# _on_enter_cell(), which returns early on gate and exit cells and would
		# leave both flags stuck on.
		_turned_in_cell = false
		_entry_lockout = -1

		_on_enter_cell()

		if finished:
			return

		# A pending turn resolves at the boundary, if the requested side is open.
		#
		# This is checked BEFORE the buffer is charged for crossing the boundary.
		# Charging first would expire an input that arrives exactly at the
		# junction it was aimed at -- the player presses in time, reaches the
		# opening, and eats a slowdown anyway. The buffer says "how far may I
		# carry this input", and arriving at the opening on the last fraction of
		# it is a hit, not a miss.
		if pending_turn != -1 and _may_turn_into(pending_turn):
			_turn_into(pending_turn)
		else:
			_consume_buffer(to_boundary)

		# If the way ahead is now solid, stop here and start scraping. Without
		# this the loop would keep consuming `remaining` through a wall.
		if not maze.is_open(cell, facing):
			_press_into_wall(remaining, 0.0)
			return


# Pressed into a wall. The barrier drains; turning out before it empties costs
# nothing at all, which is the skill expression (CLAUDE.md section 5.1).
func _press_into_wall(_moved: float, delta: float) -> void:
	progress = 1.0

	if not scraping:
		scraping = true
		scraped.emit()

	# A pending turn still resolves while scraping -- that is exactly how a good
	# player escapes without paying.
	if pending_turn != -1 and _may_turn_into(pending_turn):
		# A scrape is the one place progress SHOULD reset: the racer is pinned
		# at 1.0 against the wall, which is not a real position (see
		# world_position()). Pivoting out starts the new corridor from the cell
		# centre because that is where the racer actually is.
		progress = 0.0
		_turn_into(pending_turn)
		scraping = false
		return

	if delta <= 0.0:
		return

	barrier -= delta
	if barrier <= 0.0:
		_crash()


func _crash() -> void:
	barrier = 0.0
	scraping = false
	state = State.PARKED
	crash_count += 1

	hp = maxi(0, hp - upgrades.wall_damage())
	speed = upgrades.speed_floor()
	pending_turn = -1
	pending_buffer = 0.0
	# A crash is a hard stop: recentre in the corridor rather than leaving the
	# marker parked against a wall from whatever turn preceded it.
	lane = 0.0

	crashed.emit()


func _unstick() -> void:
	facing = int(Maze.OPPOSITE[facing])
	progress = 0.0
	state = State.RUNNING

	# Start the climb back from below the floor so the 2.5x recovery ramp has
	# something to do -- otherwise un-sticking would restore full base speed
	# instantly and the crash would cost only the parked time.
	speed = upgrades.speed_floor() * 0.5
	barrier = upgrades.barrier_capacity()

	unstuck.emit()


# The buffer is consumed by DISTANCE, not time. That keeps forgiveness constant
# at every speed instead of growing as the player gets faster
# (CLAUDE.md section 4).
func _consume_buffer(distance: float) -> void:
	if pending_turn == -1:
		return

	pending_buffer -= distance
	if pending_buffer <= 0.0:
		# Expired. A slowdown, not a crash: no HP, no barrier. The input is
		# cleared and must be pressed again (CLAUDE.md section 5.2).
		pending_turn = -1
		pending_buffer = 0.0
		slowdown_count += 1
		_apply_speed_cost(Tuning.SLOWDOWN_PENALTY)
		slowdown.emit()


func _on_enter_cell() -> void:
	if cell == maze.exit_cell:
		finished = true
		exit_reached.emit()
		return

	for i in _gate_cells.size():
		if _gate_cells[i] == cell:
			_gate_cells.remove_at(i)
			gates_taken += 1
			gate_entered.emit(gates_taken)
			return


func _apply_speed_cost(cost: float) -> void:
	speed = maxf(speed - cost, upgrades.speed_floor())


# --- Helpers -----------------------------------------------------------------

# Convert a left/right key into an absolute compass direction given facing.
func _relative_direction(key: int) -> int:
	var order := [Maze.N, Maze.E, Maze.S, Maze.W]
	var index := order.find(facing)
	if index == -1:
		return facing
	# +1 in this order is a right turn (N -> E -> S -> W).
	var shifted := (index + key + order.size()) % order.size()
	return int(order[shifted])


# May a turn resolve into `direction` right now?
#
# Open in the maze, and not the corridor the racer just turned out of. The
# second half is what makes "always turn into the NEXT available opening" true:
# without it a crossroads lets a press fold the racer straight back into the
# corridor it left, which is a 180 the player did not ask for and did not pay
# for.
func _may_turn_into(direction: int) -> bool:
	if direction == _entry_lockout:
		return false
	return maze.is_open(cell, direction)


# Commit a turn into `direction`. The one place facing changes for a 90.
#
# PROGRESS IS PRESERVED. It used to reset to 0, which reads as the racer being
# yanked back to the centre of the cell it had already half-crossed -- the
# "jumped me to an old grid line and I missed my turn" bug. The racer is at a
# real point in the corridor; pivoting there is a rotation, not a teleport, so
# the distance already covered in this cell still counts against the next
# boundary.
func _turn_into(direction: int) -> void:
	_kick_lane(direction)
	# Lock out the corridor being left, so the next press cannot fold straight
	# back into it. `facing` still points the old way here, so the way back is
	# simply the reverse of the current heading.
	_entry_lockout = int(Maze.OPPOSITE[facing])
	facing = direction
	_turned_in_cell = true
	pending_turn = -1
	pending_buffer = 0.0
	_apply_speed_cost(Tuning.TURN_COST)
	turned.emit(facing)


# Throw the player toward the OUTSIDE of a turn.
#
# Turning left exits toward the right of the new heading, and vice versa -- the
# same way a vehicle's momentum carries it wide through a corner. Called with
# the direction being turned INTO, before `facing` is updated.
func _kick_lane(direction: int) -> void:
	var turning_left: bool = direction == left_direction()
	# Outside of a left turn is +lane (right of the new heading).
	var kick: float = Tuning.LANE_TURN_KICK if turning_left else -Tuning.LANE_TURN_KICK
	lane = clampf(lane + kick, -float(Tuning.LANE_MAX), float(Tuning.LANE_MAX))


# Settle the lane onto the nearest whole lane line and HOLD it there.
#
# It used to drift all the way back to the centre line, which meant the corridor
# was constantly pulling the racer sideways out from under the player -- a
# position they never chose and could not stop. A turn threw them wide and then
# the game quietly reeled them back in, so the lateral position was never
# theirs.
#
# Now the kick still throws the racer wide, but it settles on whichever lane it
# landed nearest and STAYS on it until the next turn moves it. The lane a turn
# leaves you in is where you ride, so the floor lines mean something: you are on
# one of them, not sliding between them.
func _recover_lane(delta: float) -> void:
	var target := roundf(clampf(lane, -float(Tuning.LANE_MAX), float(Tuning.LANE_MAX)))
	if is_equal_approx(lane, target):
		lane = target
		return
	var step := Tuning.LANE_RECOVER_PER_SEC * delta
	if absf(target - lane) <= step:
		lane = target
	else:
		lane += signf(target - lane) * step


func left_direction() -> int:
	return _relative_direction(-1)


func right_direction() -> int:
	return _relative_direction(1)


# World position in metres, interpolated across the current cell.
#
# Travel runs 0..1 from this cell's centre to the next cell's centre. But when
# pressed into a wall, progress is pinned at 1.0 to mean "hard against it" --
# and interpolating that literally puts the player a FULL CELL forward, standing
# inside the wall, or outside the maze entirely at a boundary. First person hid
# this completely (inside a wall looking out just reads as "close to it"); third
# person shows the marker buried in the wall it is supposedly stopped at.
#
# So a blocked facing clamps to the wall FACE instead: half a cell out, less the
# wall's own half-thickness and a little clearance for the marker's radius.
func world_position() -> Vector3:
	var v: Vector2i = Maze.DIR_VECTORS[facing]
	var travel := progress

	if not maze.is_open(cell, facing):
		var face_distance := (Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5
			- Tuning.MARKER_RADIUS) / Tuning.CELL_SIZE
		travel = minf(progress, face_distance)

	var fx := float(cell.x) + float(v.x) * travel
	var fy := float(cell.y) + float(v.y) * travel

	var pos := Vector3(fx * Tuning.CELL_SIZE, Tuning.EYE_HEIGHT, fy * Tuning.CELL_SIZE)

	# Lateral lane offset, perpendicular to the direction of travel. Purely
	# positional -- `cell` and `progress` are untouched, so every rule still
	# sees a player on the corridor centre line.
	if not is_zero_approx(lane):
		var fwd := Vector3(float(v.x), 0.0, float(v.y))
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		pos += right * (lane * Tuning.LANE_SPACING)

	return pos


func facing_vector() -> Vector3:
	var v: Vector2i = Maze.DIR_VECTORS[facing]
	return Vector3(float(v.x), 0.0, float(v.y))


func barrier_fraction() -> float:
	var cap := upgrades.barrier_capacity()
	return 0.0 if cap <= 0.0 else clampf(barrier / cap, 0.0, 1.0)


func speed_fraction() -> float:
	return clampf(speed / Tuning.SPEED_CAP, 0.0, 1.0)


# Which relative key (-1 left, +1 right, 0 straight) heads toward the exit.
# Used by the Path Indicator. Returns 2 for "reverse".
func correct_relative_turn() -> int:
	var best := maze.best_direction(cell)
	if best == -1:
		return 0
	if best == facing:
		return 0
	if best == left_direction():
		return -1
	if best == right_direction():
		return 1
	return 2
