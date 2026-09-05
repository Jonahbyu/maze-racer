# The picture half of the one-time name prompt.
#
# ShellTest proves it builds, takes a name and hands the run on; only a frame
# shows whether the card sits over the art legibly and whether the field and
# buttons line up. Layout is the part no headless harness can check.
#
# Usage:
#   launch.ps1 -Script res://scripts/core/NameShot.gd
extends SceneTree

var _shell: Node
var _frame := 0
var _stage := 0


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_shell = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_shell)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	if _frame < 25:
		return
	match _stage:
		0:
			# Driven directly: with no Leaderboard autoload on desktop, _on_play
			# correctly declines to prompt, so the modal has to be asked for.
			var menu = _shell._current
			if menu != null and menu.has_method("_ask_name"):
				menu._ask_name(Tuning.Board.DAILY)
			_stage = 1
		1:
			# Build on one frame, capture on the next -- process_frame fires
			# before the UI is drawn.
			_capture("name_prompt")
			_stage = 2
		2:
			print("RESULT: PASS")
			quit(0)


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/shot_%s.png" % label
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
