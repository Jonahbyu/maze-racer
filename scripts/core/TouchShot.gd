# The picture half of the mobile-controls work.
#
# ShellTest proves the toggle flips and the pads honour it; only a rendered
# frame shows whether the pads land where a thumb can reach them and whether
# the fourth menu button still fits its row. Layout is exactly the part no
# headless harness can check (CLAUDE.md section 12).
#
# Usage:
#   launch.ps1 -Script res://scripts/core/TouchShot.gd
extends SceneTree

var _shell: Node
var _frame := 0
var _stage := 0
var _last_cell := Vector2i(-999, -999)


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var settings := root.get_node_or_null("/root/Settings")
	if settings != null:
		settings.set_touch_controls(true)

	# Through the real shell, so the menu shot is the menu a player sees.
	_shell = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_shell)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	match _stage:
		0:
			if _frame >= 30:
				_capture("touch_01_menu")
				_shell.start_game()
				_frame = 0
				_stage = 1
		1:
			_autopilot()
			if _frame >= 90:
				_capture("touch_02_pads")
				_frame = 0
				_stage = 2
		2:
			_autopilot()
			if _frame >= 400:
				_capture("touch_03_running")
				print("RESULT: PASS")
				quit(0)


func _autopilot() -> void:
	var game = _shell._current
	if game == null or game.get("racer") == null or int(game.phase) != 0:
		return
	var racer: Racer = game.racer

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	# Once per cell, for the reason Screenshot.gd gives: re-deciding every frame
	# re-requests the same turn and pins speed at the floor.
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
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s (error %d)" % [path, err])
