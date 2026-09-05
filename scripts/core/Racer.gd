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
signal scraped()           # barrier began draining, and 1 HP was charged
signal crashed()
signal unstuck()
# Carries the gate's index into `maze.gates` -- its POSITION in the maze, not
# a count of how many have been taken. Those are the same number only when the
# player collects gates in the order they were placed, which is true on a maze
# with few loops and false the moment braiding lets the player reach gate 3
# before gate 2. The mesh names its markers by the placement index, so emitting
# the count recoloured whichever marker happened to sit at that position -- a
# gate the player had never driven through, while the one they just took stayed
# lit. The minimap was right the whole time because it reads `gates_cleared`,
# which is a list of cells and cannot drift out of step with anything.
# A cell boundary was crossed.
#
# `repeat` is whether this cell has already been driven through in THIS maze. It
# is true on EVERY re-crossing, because it governs whether the cell earns
# anything (CLAUDE.md section 8b) -- ground already covered pays nothing however
# many times it is covered again.
#
# `first_repeat` is true only the FIRST time a given cell is re-entered, which is
# what the flat repeat penalty is charged on. The two differ deliberately: the
# penalty measures how much redundant ground a route covered, so it is a property
# of the cell, while the earning rule is a property of each crossing.
#
# Emitted for every cell including gates and the exit -- the rules layer records
# what happened and the score decides what it is worth, the same separation
# last_turn_scraped keeps.
signal cell_entered(cell: Vector2i, repeat: bool, first_repeat: bool)
signal gate_entered(index: int)
signal exit_reached()
signal died()              # HP reached 0 with Tuning.DEATH_ENABLED
signal wall_smashed(cell: Vector2i, direction: int)
signal legendary_ready()   # a legendary cooldown finished

enum State { RUNNING, PARKED }

var maze: Maze
var upgrades: Upgrades

var state: int = State.RUNNING

# Grid position. `cell` is the cell being travelled through; `progress` is how
# far across it we are, along `facing`.
#
# PROGRESS IS CENTRED ON THE CELL CENTRE: it runs -0.5 .. +0.5, where 0.0 is the
# centre and +/-0.5 are the two drawn grid lines bounding the cell. It used to
# run 0..1 between cell CENTRES, which put it half a cell out of phase with
# every line the player can see -- so for the whole upper half of a traversal
# the marker was drawn in the next cell while every rule still read the old one.
# Measured: 75.6% of immediate turns resolved against the cell behind the
# marker, at a flat 0.500-cell error. Centring makes "past the line" and "in the
# new cell" the same statement, which is what section 11.3 promises.
#
# The one exception is a scrape, where progress is pinned to the wall face to
# mean "hard against it" rather than to mean a position at all -- see
# world_position() and the section 12 trap.
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

# Where the lane is heading. A turn sets this; `lane` eases toward it over the
# following frames rather than jumping. Keeping the target separate from the
# position is what turns the kick from a sideways snap into an arc -- see
# _kick_lane() and _recover_lane().
var lane_target: float = 0.0

# Seconds left in the post-turn freeze. While positive the racer holds station:
# no travel, no buffer consumption, no barrier drain. The camera uses the same
# window to swing onto the new heading (CLAUDE.md section 2).
var freeze: float = 0.0

var pending_turn: int = -1
var pending_buffer: float = 0.0

# True while the player is pressed into a wall and the barrier is draining.
var scraping := false

# Whether the turn that just resolved came OUT of a scrape.
#
# The scrape-escape path clears `scraping` before pivoting, so a listener on
# `turned` cannot tell a clean corner from a wall escape by reading `scraping`
# -- it is already false by then. Recorded here at the moment of the turn so the
# score can price the two differently (CLAUDE.md section 8b) without the rules
# layer knowing anything about scoring.
var last_turn_scraped := false

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
# Wall contacts made, each of which cost Tuning.SCRAPE_DAMAGE. Counted
# separately from crashes because they are separate events -- a run with many
# scrapes and no crashes is a player brushing walls and paying for it, which
# reads nothing like a run that crashed the same number of times.
var scrape_count := 0
var slowdown_count := 0

var gates_taken := 0
var _gate_cells: Array[Vector2i] = []

# Gates already passed through, in the order they were taken.
#
# The racer used to simply drop a gate out of _gate_cells and forget it, which
# left nothing able to answer "have I been here?" -- the mesh deleted the marker
# and the minimap painted the cell as plain corridor, so a cleared gate and a
# stretch of empty floor looked identical. In a looped maze that is exactly the
# question the player is asking (CLAUDE.md section 6), and it is the same job
# landmarks do for corridors: recognising re-crossed ground.
#
# Kept as cells rather than as indices so a listener can ask about a POSITION
# without knowing the gate order -- which is what the minimap needs, since it
# draws cells and knows nothing about gate numbering.
var gates_cleared: Array[Vector2i] = []

# Every cell driven through this maze, as a set. Drives the repeat-cell penalty
# (CLAUDE.md section 8b) and is the raw material for a "where have I been" trail
# should one ever be drawn.
#
# The value is whether the cell has been RE-entered since it was first driven,
# so the flat penalty can be charged once per cell rather than once per crossing.
# The count of re-entries lives on Score with the other tallies.
var visited := {}

var finished := false

# True once HP has hit 0 with death enabled. The run is over; Game reads this
# and stops the simulation.
var dead := false

# Which maze of the run this racer is driving, 0-based. Wall damage scales with
# it (Tuning.WALL_DAMAGE_PER_MAZE), so the racer has to know -- but nothing else
# reads it, and it is NOT part of the build (see Upgrades.wall_damage).
var maze_index := 0

# Fractional HP carried between frames. HP is an integer to the player and on
# the HUD, but Repair Field restores well under one point per frame, so
# truncating every frame would regenerate exactly nothing.
var _hp_fraction := 0.0

# --- Legendaries (CLAUDE.md section 7) ---------------------------------------

# Seconds until the held legendary can fire again. Counts down on clean travel
# the same way everything else does.
var legendary_cooldown := 0.0

# Seconds left of an Auto-Steer burst; 0.0 when not running. While positive the
# racer drives itself down the distance field at doubled speed and is immune to
# wall contact.
var auto_steer := 0.0


func setup(p_maze: Maze, p_upgrades: Upgrades, p_maze_index: int = 0) -> void:
	maze = p_maze
	upgrades = p_upgrades
	maze_index = p_maze_index

	cell = maze.start_cell
	progress = 0.0
	state = State.RUNNING
	finished = false
	dead = false
	_hp_fraction = 0.0
	# A legendary starts ready: the cooldown is a limit on repeat use, not an
	# entry fee on the maze.
	legendary_cooldown = 0.0
	auto_steer = 0.0

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
	lane_target = 0.0
	freeze = 0.0
	scraping = false
	_turned_in_cell = false
	_entry_lockout = -1

	# Cells driven through this maze, for the repeat-cell penalty. Reset per
	# maze rather than per run: a new maze is new ground by definition, so
	# carrying this forward would charge the player for a coincidence of grid
	# coordinates between two unrelated mazes.
	#
	# The start cell is pre-marked, so returning to it is a repeat like any
	# other -- the racer has demonstrably been there.
	visited.clear()
	# false = seen once, not yet re-entered. The start cell is pre-marked, so
	# returning to it is a repeat like any other.
	visited[cell] = false

	_gate_cells = maze.gates.duplicate()
	gates_cleared.clear()
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
		# Escaping a scrape resets progress, for the same reason the boundary
		# path in _press_into_wall() does: while scraping, progress is pinned at
		# 1.0 to mean "hard against the wall", which is NOT a position. Pivoting
		# out of it and then interpolating that 1.0 down the newly-opened
		# corridor threw the marker a full cell forward in a single frame -- the
		# player turned out of a wall and was teleported to the front of the next
		# cell. The racer is at the cell centre when it turns out of a scrape,
		# so that is where the new corridor starts.
		if scraping:
			progress = 0.0
			scraping = false
		_turn_into(direction)
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
	# Progress is centred on the cell centre (-0.5..+0.5), so the reflection is
	# about 0.0: a racer a third of the way past the centre ends a third of the
	# way back toward the line it came in through. It was `1.0 - progress` when
	# progress ran centre-to-centre.
	progress = -progress
	_apply_speed_cost(upgrades.reverse_cost())
	pending_turn = -1
	# A 180 is an explicit, expensive, always-legal input -- it is never the
	# accidental second tap these lockouts guard against, and the racer is now
	# facing the other way, so the cell is fresh again. Going back down the
	# corridor it came from is exactly what the player asked for, so the entry
	# lockout lifts too.
	_turned_in_cell = false
	_entry_lockout = -1
	freeze = upgrades.reverse_freeze()
	reversed.emit()


# --- Simulation --------------------------------------------------------------

func step(delta: float) -> void:
	if finished or dead:
		return

	if state == State.PARKED:
		# Parked: no ramp, no movement. The barrier holds until un-stick so the
		# player is not punished twice for sitting where the game put them.
		#
		# No HP regen either: Repair Field pays for CLEAN TRAVEL, and a parked
		# racer is doing the opposite. Regenerating here would let a player farm
		# HP by sitting in the crash they just caused.
		return

	_advance_speed(delta)
	_recover_lane(delta)
	_regen_hp(delta)
	_tick_legendary(delta)

	# Held on a turn. The speed ramp above still runs -- the freeze is a pause in
	# POSITION, not in the systemic pressure section 3 describes, and stopping
	# the ramp would make cornering a way to duck the game's central mechanic.
	# Travel, the buffer and the barrier are all suspended: the racer is not
	# moving, so it is not covering buffer distance and it cannot be grinding
	# against anything.
	#
	# The freeze consumes only as much of the frame as it NEEDS, and travel gets
	# the rest. Swallowing the whole delta and returning was wrong twice over: a
	# 0.10s freeze ended somewhere inside the frame that crossed it but still ate
	# that frame entirely, so every corner leaked up to a frame of travel; and
	# any frame longer than the freeze -- a hitch, or a low-framerate machine --
	# was discarded whole, which turns a stutter into a much longer stop on a
	# slow machine than on a fast one. Frame-rate independence is the point.
	if freeze > 0.0:
		var spent := minf(freeze, delta)
		freeze -= spent
		delta -= spent
		if delta <= 0.0:
			return

	# Auto-Steer drives at a multiple of the player's own speed, so it stays
	# legible: a fixed rate would feel slow to a 6x racer and violent to a 1x one.
	var rate := speed
	if auto_steer > 0.0:
		rate *= Tuning.AUTOSTEER_SPEED_MULTIPLIER
	var moved := rate * Tuning.BASE_CELL_RATE * delta

	# Blocked ahead, but not yet AT the wall: there is still corridor to cover
	# between here and the face, so travel it.
	#
	# Dispatching on `is_open` alone sent a racer that had merely ENTERED a
	# blocked cell straight to _press_into_wall, which pins it to the wall face
	# -- teleporting the marker most of a cell in one frame and freezing it
	# there. Progress is centred now, so a racer entering a cell is at its
	# LEADING edge with a full cell still to cross, and that missing travel is
	# the whole of "no movement in the last cell". It was hidden while the cell
	# advanced at the centre, where only half a cell went missing.
	# Travel while there is corridor left: either the way ahead is open, or it is
	# blocked but the racer has not yet reached the wall face.
	var open_ahead := maze.is_open(cell, facing)
	if open_ahead or (not scraping and progress < _wall_face_progress()):
		_travel(moved, delta)
	elif auto_steer > 0.0:
		# Invulnerable while the burst runs: the router takes the optimal turn
		# every time so this should be unreachable, but at doubled speed a single
		# mistimed frame would be brutal, and an escape button that can kill you
		# is not one (CLAUDE.md section 7). Re-aim rather than grind.
		var out := maze.best_direction(cell)
		if out != -1 and out != facing:
			facing = out
	else:
		_press_into_wall(moved, delta)


# Legendary cooldowns and any Auto-Steer burst in flight.
#
# The cooldown runs on the same clean-travel clock as everything else, so a
# parked racer is not quietly recharging its ability while it sits.
func _tick_legendary(delta: float) -> void:
	if legendary_cooldown > 0.0:
		var was_cooling := legendary_cooldown > 0.0
		legendary_cooldown = maxf(0.0, legendary_cooldown - delta)
		if was_cooling and legendary_cooldown <= 0.0:
			legendary_ready.emit()

	if auto_steer > 0.0:
		auto_steer = maxf(0.0, auto_steer - delta)
		# Steer down the distance field. Requested rather than forced, so the
		# turn goes through the ordinary resolution path and pays the ordinary
		# turn cost -- the burst is an autopilot, not a separate movement mode.
		var want := maze.best_direction(cell)
		if want != -1 and want != facing and pending_turn == -1:
			var rel := (want - facing + 4) % 4
			if rel == 1:
				request_turn(1)
			elif rel == 3:
				request_turn(-1)


# Start an Auto-Steer burst. Returns false if the legendary is not held or is
# still cooling.
func start_auto_steer() -> bool:
	if not upgrades.has_auto_steer() or legendary_cooldown > 0.0:
		return false
	if state == State.PARKED or dead:
		return false
	auto_steer = upgrades.auto_steer_duration()
	legendary_cooldown = upgrades.legendary_cooldown()
	return true


# Repair Field: HP back on clean travel only.
#
# Accumulated as a float and spent in whole points, because the regen rates are
# well under one HP per frame -- truncating each frame would restore precisely
# nothing at every rank. Scraping does not count as clean: the barrier is
# draining, which is the moment the player is closest to taking the damage this
# would be undoing.
func _regen_hp(delta: float) -> void:
	if hp >= Tuning.MAX_HP or scraping:
		return
	var rate := upgrades.hp_regen()
	if rate <= 0.0:
		return

	_hp_fraction += rate * delta
	if _hp_fraction >= 1.0:
		var whole := int(_hp_fraction)
		_hp_fraction -= float(whole)
		hp = mini(Tuning.MAX_HP, hp + whole)


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
		# The boundary is the drawn grid line, at progress 0.5 -- NOT progress
		# 1.0, which is the next cell's centre, half a cell further on.
		#
		# These used to be the same step, and that was the "turns put you in
		# early" bug: `cell` advanced at the centre, so for the whole upper half
		# of every traversal the marker was drawn inside the next cell while
		# every rule still read the old one. Crossing where the line is drawn
		# makes "past the line" and "in the new cell" one statement, which is
		# what section 11.3 promises the line means.
		#
		# Past the line, the next one is a full cell away; short of it, half a
		# cell. Both are just "distance to progress 0.5, modulo one cell".
		var to_boundary := 0.5 - progress if progress < 0.5 else 1.5 - progress

		if remaining < to_boundary:
			progress += remaining
			_consume_buffer(remaining)
			distance_travelled += remaining
			remaining = 0.0
			break

		# Reached the grid line. Progress rephases to just past the new cell's
		# trailing line -- the marker keeps moving forward, but it is now
		# measured from the centre of the cell it just entered.
		progress = progress + to_boundary - 1.0
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

		# If the way ahead is now solid, the racer still has to CROSS this cell
		# before it reaches the wall at the far side of it.
		#
		# This used to press into the wall the instant the cell was entered,
		# which teleported the marker from the entry line straight to the far
		# wall face -- nearly a whole cell in a single frame -- and then held it
		# there, motionless, while the barrier drained into a crash. In play:
		# "I get into the last cell before a wall, it freezes, jumps to the wall
		# and I crash there, with no movement in the last cell."
		#
		# It was masked before progress was centred: the cell advanced at the
		# CENTRE, so a racer entering a blocked cell was already half way across
		# it and the jump to the wall face was small. Crossing at the line is
		# correct, and it made the missing half-cell of travel visible.
		#
		# So travel the rest of the way normally and let the wall stop the racer
		# when it is actually reached. The wall face is the far side of this
		# cell, so that is simply the distance still to cover.
		if not maze.is_open(cell, facing):
			var to_wall := _wall_face_progress() - progress
			if remaining < to_wall:
				progress += remaining
				_consume_buffer(remaining)
				distance_travelled += remaining
				return
			progress += to_wall
			distance_travelled += to_wall
			_consume_buffer(to_wall)
			_press_into_wall(remaining - to_wall, 0.0)
			return


# Pressed into a wall. Contact itself costs a flat Tuning.SCRAPE_DAMAGE, once,
# at the moment it begins. The barrier then decides whether that stays the whole
# price or escalates into a crash (CLAUDE.md section 5.1).
#
# A contact charge is NOT a crash: no park, no speed reset, no `crashed` signal
# and none of the crash framing that hangs off it. The player keeps driving,
# one point down. Only the barrier emptying crashes.
func _press_into_wall(_moved: float, delta: float) -> void:
	# Auto-Steer is invulnerable, so wall contact cannot even begin to drain.
	# Reached only if the router had nowhere better to aim.
	if auto_steer > 0.0:
		return

	# Pinned against the wall ahead. This is the one place progress does NOT
	# mean a position -- it means "hard against it" -- so it is set to the wall
	# FACE rather than to some value past the boundary. With progress centred on
	# the cell centre, the face is just under +0.5 (half a cell out, less the
	# wall's half-thickness and the marker's radius), which keeps the value in
	# range and keeps world_position()'s clamp a no-op rather than a rescue.
	progress = _wall_face_progress()

	if not scraping:
		scraping = true
		# Charged HERE, where contact BEGINS, which is what makes it once per
		# contact rather than per second or per frame: `scraping` stays true for
		# the whole touch, so this branch cannot run again until the player has
		# left the wall and come back to it.
		_take_contact_damage()
		scraped.emit()

	# A pending turn still resolves while scraping -- that is exactly how a good
	# player escapes without paying.
	if pending_turn != -1 and _may_turn_into(pending_turn):
		# A scrape is the one place progress must be REWRITTEN before pivoting:
		# it is pinned to the wall face to mean "hard against the wall", which
		# is not a position along the NEW heading at all. Carrying that value
		# through the pivot sends the marker the same distance down the new
		# corridor -- measured at 1.95m, worse than the 1.4m reposition below,
		# because the wall face is that far along the OLD heading and the two
		# are not the same point (CLAUDE.md section 2).
		#
		# So the pivot starts from the cell centre, which is where the racer
		# actually is. The turn freeze is what makes that reposition readable
		# rather than something to hide.
		progress = 0.0
		last_turn_scraped = true
		_turn_into(pending_turn)
		scraping = false
		return

	if delta <= 0.0:
		return

	barrier -= delta
	if barrier <= 0.0:
		# Wall Smasher fires at the moment a crash WOULD have happened, so it is
		# a save rather than a bypass: the barrier still drained, the player
		# still felt the scrape, and the ability turns the ending into a
		# breakthrough (CLAUDE.md section 7).
		if _try_smash():
			return
		_crash()


# The flat cost of touching a wall at all. Deliberately narrow: it moves HP and
# nothing else -- speed, state, the barrier and the lane are all untouched,
# because this is contact, not a crash.
#
# Death is still checked, since a player already at 1 HP has to be able to die to
# a scrape; otherwise a run could survive indefinitely on wall contact alone and
# HP would stop meaning anything at exactly the moment it matters most. It reads
# as its own event rather than as a crash: `died` fires without `crashed`, so the
# crash framing never appears for a death the player did not crash into.
func _take_contact_damage() -> void:
	if dead or Tuning.SCRAPE_DAMAGE <= 0:
		return

	hp = maxi(0, hp - Tuning.SCRAPE_DAMAGE)
	scrape_count += 1

	if Tuning.DEATH_ENABLED and hp <= 0:
		dead = true
		died.emit()


# Wall Smasher. Returns true if the wall gave way (or the boundary turned the
# player around), meaning no crash happens.
func _try_smash() -> bool:
	if not upgrades.has_wall_smasher() or legendary_cooldown > 0.0:
		return false

	legendary_cooldown = upgrades.legendary_cooldown()

	if maze.smash_wall(cell, facing):
		# Through the hole with speed intact. The barrier refills because the
		# scrape that led here is over and the player is back in open corridor;
		# leaving it empty would drop them straight into a second crash.
		barrier = upgrades.barrier_capacity()
		scraping = false
		progress = 0.0
		wall_smashed.emit(cell, facing)
		return true

	# The maze boundary: nothing to break, so turn around instead. Still costs
	# the cooldown -- the ability fired, it simply met the one wall that cannot
	# go (CLAUDE.md section 7).
	scraping = false
	barrier = upgrades.barrier_capacity()
	request_reverse()
	return true


func _crash() -> void:
	barrier = 0.0
	scraping = false
	state = State.PARKED
	crash_count += 1

	hp = maxi(0, hp - upgrades.wall_damage(maze_index))
	speed = upgrades.speed_floor()
	pending_turn = -1
	pending_buffer = 0.0
	# A crash is a hard stop: recentre in the corridor rather than leaving the
	# marker parked against a wall from whatever turn preceded it.
	lane = 0.0
	lane_target = 0.0
	# PARKED already holds position, and a freeze left running would silently
	# eat the first frames after un-stick.
	freeze = 0.0

	crashed.emit()

	# Death is checked AFTER crashed.emit(), so the crash still reads as a crash
	# -- the HUD message, the camera pull-back and the sound all fire normally,
	# and the death lands on top of it. Emitting death first would leave the
	# player looking at a stopped racer with no explanation of what hit them.
	if Tuning.DEATH_ENABLED and hp <= 0:
		dead = true
		died.emit()


func _unstick() -> void:
	facing = int(Maze.OPPOSITE[facing])
	progress = 0.0
	state = State.RUNNING
	# No freeze here. Un-sticking is a 180, but the player has already been sat
	# still for as long as it took them to press the key -- charging a freeze on
	# top would hold them motionless again the instant they asked to move.
	freeze = 0.0

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
		_apply_speed_cost(upgrades.slowdown_penalty())
		slowdown.emit()


func _on_enter_cell() -> void:
	# Recorded BEFORE the exit and gate early-returns below. Those return before
	# the end of this function, so tracking placed after them would leave gate
	# cells and the exit free to re-cross -- and gates sit on the solve path,
	# which is precisely the ground a looping player covers twice.
	var repeat: bool = visited.has(cell)
	# Charged once per cell: true only on the first re-crossing, false on every
	# one after it. `visited` holds that flag rather than a bare marker.
	var first_repeat: bool = repeat and not visited[cell]
	visited[cell] = repeat
	cell_entered.emit(cell, repeat, first_repeat)

	if cell == maze.exit_cell:
		finished = true
		exit_reached.emit()
		return

	for i in _gate_cells.size():
		if _gate_cells[i] == cell:
			# Resolved against `maze.gates` rather than against `i`: this list
			# is a working copy that shrinks as gates are taken, so its indices
			# slide the moment one is removed.
			var placement := maze.gates.find(cell)
			_gate_cells.remove_at(i)
			gates_cleared.append(cell)
			gates_taken += 1
			gate_entered.emit(placement)
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
#
# `cell` is trustworthy here because progress is centred: _travel() advances the
# cell at the drawn grid line, so the cell named is always the one the player is
# standing in. When progress ran 0..1 between centres that was false for the
# upper half of every traversal, and this function was the place it hurt --
# measured, 75.6% of immediate turns asked about the cell BEHIND the marker.
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
	# Anything reaching here that did NOT come from the scrape-escape path above
	# is a clean corner. The escape path sets the flag immediately before
	# calling, so this default runs for every ordinary turn.
	if not scraping:
		last_turn_scraped = false

	# A turn taken on the way IN to a cell must not keep its inbound distance.
	#
	# Progress is measured along `facing`, and the pivot changes `facing` --
	# so a negative progress (still short of this cell's centre, which is where
	# the racer is for the whole first half of a cell) would be re-interpreted
	# as that same distance BACKWARDS along the new heading, drawing the marker
	# out through the side wall. Measured: the marker sat 1.949m off its cell
	# centre where the corridor half-width is 1.77m, so the camera could never
	# find a clear line to it and the "marker is never hidden" rule (section 12)
	# failed on 20-40 of every 2000 autopilot frames.
	#
	# Clamped to 0 rather than reflected, because the racer turning at the mouth
	# of a cell is, for the new corridor, at that corridor's start. Progress
	# already past the centre is a real distance down the new heading and is
	# kept, which is what makes a turn a pivot rather than a rewind (section 2).
	if progress < 0.0:
		progress = 0.0

	_kick_lane(direction)
	# Lock out the corridor being left, so the next press cannot fold straight
	# back into it. `facing` still points the old way here, so the way back is
	# simply the reverse of the current heading.
	_entry_lockout = int(Maze.OPPOSITE[facing])
	facing = direction
	_turned_in_cell = true
	pending_turn = -1
	pending_buffer = 0.0
	_apply_speed_cost(upgrades.turn_cost())
	freeze = upgrades.turn_freeze()
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
	# Sets the TARGET, not the position. `lane` eases toward it in _recover_lane()
	# over the following frames, which is what makes the corner read as an arc
	# instead of a sideways teleport stapled to the 90-degree pivot.
	lane_target = clampf(lane_target + kick, -float(Tuning.LANE_MAX), float(Tuning.LANE_MAX))


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
	# The target is a whole lane line -- the kick moves it in whole lanes and a
	# crash zeroes it, so it is already integral. Rounding here is belt-and-braces
	# against float drift, and it is what pins the racer ON a line rather than
	# between two.
	var target := roundf(clampf(lane_target, -float(Tuning.LANE_MAX), float(Tuning.LANE_MAX)))
	lane_target = target

	if is_equal_approx(lane, target):
		lane = target
		return

	# Approaching a fresh kick is fast (the throw); settling the last of it is
	# slow (the weight). Same direction, two rates, so the corner has a shape.
	var rate := Tuning.LANE_KICK_PER_SEC if absf(target - lane) > 0.5 else Tuning.LANE_RECOVER_PER_SEC
	var step := rate * delta
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
# Travel runs -0.5..+0.5 about this cell's centre, so the marker is drawn at the
# cell centre plus `progress` cells along the facing -- and +/-0.5 lands it
# exactly on a drawn grid line, which is the whole point of the centred phase.
#
# The clamp below is belt-and-braces rather than the rescue it used to be. When
# progress ran 0..1 a scrape pinned it at 1.0 to mean "hard against the wall",
# and interpolating that literally put the player a FULL CELL forward, standing
# inside the wall or outside the maze entirely at a boundary. First person hid
# it completely (inside a wall looking out just reads as "close to it"); third
# person showed the marker buried in the wall it was stopped at. _press_into_wall
# now pins to the wall FACE directly, so the clamp holds the line for anything
# that drives progress past it by another route.
# How far across the cell the wall FACE sits, in progress units.
#
# The single source of truth for "pinned against the wall ahead": world_position()
# clamps the drawn position to it during a scrape, and a turn out of a scrape
# resets progress to it so the pivot does not jump. Half a cell out, less the
# wall's own half-thickness and clearance for the marker's radius.
func _wall_face_progress() -> float:
	# Progress is measured from the cell CENTRE, so this is already the distance
	# from centre to face: half a cell out, less the wall's own half-thickness
	# and clearance for the marker's radius. Just under +0.5.
	return (Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5
		- Tuning.MARKER_RADIUS) / Tuning.CELL_SIZE


func world_position() -> Vector3:
	var v: Vector2i = Maze.DIR_VECTORS[facing]
	var travel := progress

	if not maze.is_open(cell, facing):
		travel = minf(progress, _wall_face_progress())

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
