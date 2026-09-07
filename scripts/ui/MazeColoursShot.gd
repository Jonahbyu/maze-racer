# The picture half of the maze colours screen.
#
# Five rows of five chips is layout no assertion can judge, and the chips are
# drawn IN their palette's own colours -- so whether a locked chip reads as
# locked, and whether a dark palette's chip is visible at all against the card,
# are both rendered-frame questions.
#
# Two frames: a fresh profile (four palettes locked, which is what a new player
# sees) and everything unlocked with an assignment made.
extends SceneTree

const SHOT_DIR := "res://logs"
const SETTLE := 30

var _menu: MainMenu = null
var _screen: MazeColours = null
var _saved_earned := {}
var _saved_slots: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_remember()

	_menu = MainMenu.new()
	root.add_child(_menu)
	await process_frame

	# A genuinely FRESH profile, not this machine's saved one. The first
	# version shot whatever was already earned here and produced a nearly
	# complete board labelled "01_locked" -- a frame that cannot show the state
	# it is named for. The saved set is restored on the way out.
	var fresh := root.get_node_or_null("Unlocks")
	if fresh != null:
		fresh.earned = {}

	_screen = MazeColours.new()
	_menu.add_child(_screen)
	# Nothing is captured on the frame the screen is BUILT: process_frame fires
	# before the UI is drawn, so a shot here comes back as the bare menu.
	await process_frame
	await _shoot("01_locked")

	# Everything unlocked, and one maze reassigned -- the state a player reaches
	# rather than starts in.
	var unlocks := root.get_node_or_null("Unlocks")
	if unlocks != null:
		for id in unlocks.lockable_ids():
			unlocks.earned[id] = true
	var settings := root.get_node_or_null("Settings")
	if settings != null:
		settings.set_maze_palette(0, "violet")
		settings.set_maze_palette(2, "ember")
	_screen._refresh()
	await _shoot("02_assigned")

	_restore()
	print("RESULT: PASS")
	quit(0)


func _shoot(name: String) -> void:
	for _i in range(SETTLE):
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/maze_colours_%s.png" % [SHOT_DIR, name]
	if image.save_png(path) == OK:
		print("shot %s" % path)
	else:
		push_error("MazeColoursShot: could not write %s" % path)


# A tool must not write the state it is inspecting (section 12, TouchShot): this
# one changes BOTH the earned set and every maze assignment, so it puts both
# back.
func _remember() -> void:
	var unlocks := root.get_node_or_null("Unlocks")
	if unlocks != null:
		_saved_earned = unlocks.earned.duplicate()
	var settings := root.get_node_or_null("Settings")
	if settings != null:
		_saved_slots = settings.maze_palettes.duplicate()


func _restore() -> void:
	var unlocks := root.get_node_or_null("Unlocks")
	if unlocks != null:
		unlocks.earned = _saved_earned
	var settings := root.get_node_or_null("Settings")
	if settings != null:
		for i in _saved_slots.size():
			settings.set_maze_palette(i, _saved_slots[i])
