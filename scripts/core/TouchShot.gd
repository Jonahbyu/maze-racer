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
var _want_minimap := false


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	# Shoot at PHONE dimensions, not the desktop default.
	#
	# A 1600x900 window cannot show the thing this instrument exists to check:
	# the pads are sized off the shorter screen edge, so a desktop shot says
	# nothing about whether a thumb can hit them on a handset. 844x390 is an
	# ordinary phone in landscape.
	var window := root.get_window()
	if window != null:
		window.size = Vector2i(844, 390)

	# Through the real shell, so the menu shot is the menu a player sees.
	_shell = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_shell)
	_want_minimap = true
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	match _stage:
		0:
			if _frame >= 30:
				_capture("touch_01_menu")
				_shell.start_game()
				var g = _shell._current
				# The minimap only draws once its line has a rank, and its
				# placement is one of the things these shots exist to check.
				if _want_minimap:
					g.upgrades.take(Upgrades.Line.MINIMAP)
				# Show the pads WITHOUT touching the saved preference.
				#
				# Going through Settings would persist to user://settings.cfg
				# and leave the player's own choice flipped -- a later desktop
				# Screenshot.gd run then came back full of thumb pads, which
				# reads exactly like a layout regression and is not one. An
				# instrument must not write the state it is inspecting.
				var pads = g.get_node_or_null("UI/UIRoot/TouchControls")
				if pads != null:
					pads.visible = true
					g._place_minimap()
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
	if game == null:
		return

	# An instrument, not a player: take whatever card is up rather than stalling
	# on it. The run opens on a maze-start loadout pick.
	if int(game.phase) == 1:
		var offered: Array = game._upgrade_screen._lines
		if offered.is_empty():
			game._on_upgrade_chosen(-1)
		else:
			game._on_upgrade_chosen(offered[0])
		return

	if game.get("racer") == null or int(game.phase) != 0:
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

