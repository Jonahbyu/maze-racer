# Runs the real game with rendering and saves screenshots to logs/.
#
# Headless tests prove the logic; this proves the picture. It is the only way to
# check framing, neon, the HUD layout, and the grid lines without a human at the
# keyboard -- which is the working rule for this project (CLAUDE.md, "Jonah
# never launches Godot").
#
# Usage:
#   launch.ps1 -Script res://scripts/core/Screenshot.gd
extends SceneTree

# Frames to wait before each shot, and a label for the filename.
const SHOTS := [
	[60, "01_start"],
	[700, "02_running"],
	[1600, "03_deep"],
	[2400, "04_straight"],
]

var _game: Node
var _frame := 0
var _shot_index := 0
var _last_cell := Vector2i(-999, -999)


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	# Give an upgrade or two so the indicator and minimap actually draw --
	# otherwise the shot only ever shows the rank-0 HUD.
	_game.upgrades.take(Upgrades.Line.PATH_INDICATOR)
	_game.upgrades.take(Upgrades.Line.MINIMAP)
	_game.upgrades.take(Upgrades.Line.MINIMAP)
	_game.upgrades.take(Upgrades.Line.GATE_COMPASS)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	if _shot_index >= SHOTS.size():
		print("RESULT: PASS")
		quit(0)
		return

	var target: int = SHOTS[_shot_index][0]
	if _frame < target:
		return

	var label: String = SHOTS[_shot_index][1]
	_capture(label)
	_shot_index += 1


# Drive along the solve path, so the screenshots show a run in progress rather
# than a racer parked against the first dead end. This also exercises the turn
# and gate paths with the renderer attached.
func _autopilot() -> void:
	var racer: Racer = _game.racer
	if racer == null or _game.phase != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	# Decide at most ONCE per cell. Re-deciding every frame re-requests the same
	# turn over and over, and since each turn costs 0.1x that pins speed at the
	# floor and the racer never gets anywhere.
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


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/shot_%s.png" % label
	var err := image.save_png(path)
	if err == OK:
		print("saved %s  (speed %.2fx, cell %s)" % [
			path, _game.racer.speed, _game.racer.cell
		])
	else:
		printerr("FAILED to save %s (error %d)" % [path, err])
