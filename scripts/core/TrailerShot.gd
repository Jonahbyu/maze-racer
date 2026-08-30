# Renders the trailer and saves a frame from each segment, plus the gate
# moments.
#
# TrailerTest proves the reel advances and the gates open; it cannot tell you
# the maze is on screen, the captions are readable, or the cards are actually
# drawn over a visible corridor. This is the picture half, and it is the only
# way to check the trailer without a human watching it (CLAUDE.md, "Jonah never
# launches Godot").
extends SceneTree

var _trailer: TrailerDirector
var _frame := 0
var _shot_segment := -1
var _shot_gate := -1
var _shots := 0


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_trailer = TrailerDirector.new()
	root.add_child(_trailer)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	if _trailer == null or not is_instance_valid(_trailer) or _trailer._done:
		print("shots: %d" % _shots)
		print("RESULT: PASS")
		quit(0)
		return

	var game = _trailer._game
	if game == null or not is_instance_valid(game):
		return

	# One shot per segment, taken a moment AFTER the cut so the fade has lifted
	# and the caption is up -- a frame grabbed on the cut itself is just black.
	if _trailer._segment != _shot_segment and _trailer._segment_time > 1.2:
		_shot_segment = _trailer._segment
		_capture("segment_%d" % (_trailer._segment + 1))

	# And one while the upgrade cards are up, which is the thing three of the
	# five segments exist to show.
	if int(game.phase) == 1 and _shot_gate != _trailer._segment:
		if _trailer._gate_hold > 0.0 and _trailer._gate_hold < TrailerDirector.GATE_HOLD_SECONDS - 0.4:
			_shot_gate = _trailer._segment
			_capture("gate_%d" % (_trailer._segment + 1))


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/trailer_%s.png" % label
	if image.save_png(path) == OK:
		_shots += 1
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
