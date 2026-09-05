# The picture half of the rear-view mirror. SceneTest proves the wiring; only a
# rendered frame can say whether the box shows a legible corridor.
#
# It SEEKS A CORNER rather than shooting on a timer, for the reason PaletteShot
# seeks a junction and GateShot shoots from short of a gate: the question is not
# "does the mirror render" -- a straight corridor would answer that while
# showing two identical walls receding, which is exactly the frame that cannot
# distinguish a working mirror from one aimed forward. A shot taken a cell or
# two AFTER a turn has the corner just rounded in it, which is the thing the
# mirror exists to show and the only frame where "behind" is visibly different
# from "ahead".
#
# Two frames per maze: one just after a turn, and one at a junction, so both the
# corner read and the palette are covered.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _shot := 0
var _last_cell := Vector2i(-999, -999)
# Cells covered since the last turn resolved, so the shot lands with the corner
# behind rather than in the middle of the pivot -- during the turn freeze the
# camera is still swinging and the frame says nothing.
var _since_turn := 99
var _last_facing := -1

const SETTLE := 70
const GIVE_UP := SETTLE * 14


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	# The minimap up, so the shot shows the mirror in the company it actually
	# keeps -- the point of a layout check is the whole screen, not the element
	# in isolation.
	_game.upgrades.take(Upgrades.Line.MINIMAP)
	_game.upgrades.take(Upgrades.Line.PATH_INDICATOR)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	if _frame < SETTLE:
		return

	var ready := false
	if _shot == 0:
		# One or two cells past a turn: the corner is behind and in frame, and
		# the camera has finished its swing.
		ready = _since_turn >= 1 and _since_turn <= 2
	else:
		ready = _at_junction()

	if not ready and _frame < GIVE_UP:
		return
	_frame = 0

	_capture(_maze_index, _shot)
	_shot += 1
	if _shot < 2:
		return

	_shot = 0
	_maze_index += 1
	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	_game._start_maze(_maze_index)
	_last_cell = Vector2i(-999, -999)
	_since_turn = 99
	_last_facing = -1


func _autopilot() -> void:
	var racer: Racer = _game.racer
	# An instrument, not a player: a card screen up is a stall. Covers the
	# maze-start loadout as well as a gate pick.
	if int(_game.phase) == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(offered[0])
		return

	if racer == null or _game.phase != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	if racer.cell == _last_cell:
		return
	_last_cell = racer.cell

	# Count cells since the heading last changed. Measured on entering a cell
	# rather than off the turn signal, because what the shot needs is DISTANCE
	# past the corner, not the moment of the pivot.
	if racer.facing != _last_facing:
		_since_turn = 0
		_last_facing = racer.facing
	else:
		_since_turn += 1

	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


func _capture(index: int, shot: int) -> void:
	var image := root.get_texture().get_image()
	var maze_name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var kind := "corner" if shot == 0 else "junction"
	var path := "res://logs/rearview_%d_%s_%s.png" % [index + 1, maze_name, kind]
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, %d past a turn, speed %.2fx)" % [
			path, _game.racer.cell, _since_turn, _game.racer.speed])
	else:
		printerr("FAILED to save %s" % path)


func _at_junction() -> bool:
	var racer: Racer = _game.racer
	if racer == null or racer.maze == null:
		return false
	var behind := int(Maze.OPPOSITE[racer.facing])
	var onward := 0
	for dir in racer.maze.open_directions(racer.cell):
		if int(dir) != behind:
			onward += 1
	return onward >= 2
