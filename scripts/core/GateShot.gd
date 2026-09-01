# Captures a frame APPROACHING A GATE, to check the gate marker clears the wall
# line and is visible from outside its own corridor.
#
# Not a test -- no assertion can tell you a gate is spottable at a glance. The
# whole reason gates are physical objects rather than a HUD readout is that you
# should see one coming from a couple of corridors away (CLAUDE.md section 7),
# and that is only true if the marker rises above WALL_HEIGHT.
#
# It SEEKS a gate rather than shooting on a timer, for the same reason
# PaletteShot seeks a junction: a timed shot lands in plain corridor.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _last_cell := Vector2i(-999, -999)
var _settle := 0
var _armed := false

const SETTLE := 30
const GIVE_UP := 3000
const SETTLE_FRAMES := 12

# How far from a gate to shoot from, in cells. The point is to see it BEFORE
# arriving, so this deliberately shoots from a distance rather than on top of it.
const NEAR_MIN := 2.5
const NEAR_MAX := 6.0


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	if _armed:
		if _settle > 0:
			_settle -= 1
			return
		_shoot()
		return

	_autopilot()

	if _frame < SETTLE:
		return
	if not _near_gate() and _frame < GIVE_UP:
		return

	_armed = true
	_settle = SETTLE_FRAMES


func _shoot() -> void:
	_capture(_maze_index)
	_armed = false
	_frame = 0
	_maze_index += 1

	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	_game._start_maze(_maze_index)
	_last_cell = Vector2i(-999, -999)


# Drive the solve path -- gates sit ON it, so the optimal router reaches them.
func _autopilot() -> void:
	var racer: Racer = _game.racer
	# These tools are INSTRUMENTS, not players: a card screen up is a stall, not
	# a decision. Take whatever is offered so the shot happens. Covers the
	# maze-start loadout as well as a gate pick.
	if int(_game.phase) == 1:
		var _offered: Array = _game._upgrade_screen._lines
		if _offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(_offered[0])
		return

	if racer == null or _game.phase != 0:
		return

	# Take the upgrade card immediately so the reel keeps driving rather than
	# parking on the card screen at the first gate.
	if _game.phase != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	if racer.cell == _last_cell:
		return
	_last_cell = racer.cell

	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


func _near_gate() -> bool:
	var racer: Racer = _game.racer
	if racer == null or racer.maze == null:
		return false
	for gate in racer.maze.gates:
		var gap := Vector2(gate - racer.cell).length()
		if gap >= NEAR_MIN and gap <= NEAR_MAX:
			return true
	return false


func _capture(index: int) -> void:
	var image := root.get_texture().get_image()
	var maze_name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var path := "res://logs/gate_%d_%s.png" % [index + 1, maze_name]

	var racer: Racer = _game.racer
	var nearest := 999.0
	for gate in racer.maze.gates:
		nearest = minf(nearest, Vector2(gate - racer.cell).length())

	if image.save_png(path) == OK:
		print("saved %s  (cell %s, nearest gate %.1f cells)" % [path, racer.cell, nearest])
	else:
		printerr("FAILED to save %s" % path)
