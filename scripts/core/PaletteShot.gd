# Captures one frame in each maze in Tuning.MAZES, to check the per-maze
# palettes and the wall-mounted Path Indicator actually render.
#
# Not a test -- there is no assertion that can tell you a maze looks magenta.
# It jumps straight to each maze rather than playing through, because the normal
# autopilot pauses at every gate and a palette check has no interest in the
# upgrade screen.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _last_cell := Vector2i(-999, -999)

const SETTLE := 90


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	# Path Indicator on, so the wall panels are in shot -- the whole point of
	# one of the two things being checked here.
	_game.upgrades.take(Upgrades.Line.PATH_INDICATOR)
	_game.upgrades.take(Upgrades.Line.MINIMAP)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	# Shoot at a JUNCTION, not at a fixed frame. The Path Indicator only lights
	# where there is a genuine choice of onward routes, so a shot taken on a
	# timer lands in a plain corridor and shows nothing of the thing being
	# checked.
	if _frame < SETTLE:
		return
	if not _at_junction() and _frame < SETTLE * 12:
		return
	_frame = 0

	_capture(_maze_index)
	_maze_index += 1

	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	# Straight to the next maze: no gates, no upgrade screen.
	_game._start_maze(_maze_index)
	_last_cell = Vector2i(-999, -999)


# Drive toward the exit so the shot shows a corridor, not a racer parked at the
# start facing a wall.
func _autopilot() -> void:
	var racer: Racer = _game.racer
	if racer == null or _game.phase != 0:
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


func _capture(index: int) -> void:
	var image := root.get_texture().get_image()
	var name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var path := "res://logs/palette_%d_%s.png" % [index + 1, name]
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, speed %.2fx)" % [path, _game.racer.cell, _game.racer.speed])
	else:
		printerr("FAILED to save %s" % path)


# A cell offering two or more ways ONWARD -- the condition PathIndicator lights
# on. Same rule as the node itself, deliberately: a shot taken anywhere else is
# not testing the indicator.
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
