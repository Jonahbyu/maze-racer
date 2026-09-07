# The picture half of the upgrade compendium.
#
# Shoots one frame per DEMO KIND rather than one per line: five kinds is what the
# drawing code actually has, and 28 frames of which a dozen are the same corridor
# function is a slower read for no more coverage.
#
# Plus the FIRST and LAST rows, which is where bubble placement fails. ShellTest
# asserts the bubble's rect stays inside the panel, and a rect assertion cannot
# see the failure that actually matters here: a bubble correctly inside the panel
# but sitting on top of the list text it is meant to sit beside. Rect clearance
# is not text clearance (section 12).
#
# Every shot is taken MID-ANIMATION. A demo that never advances looks identical
# to a working one in a frame taken at t=0 -- the reason QuadrantShot seeks a
# region change rather than shooting on a timer.
extends SceneTree

const SHOT_DIR := "res://logs"

# Long enough for the panel to lay out and for the animation to be visibly
# under way.
const SETTLE := 40

var _menu: MainMenu = null
var _screen: UpgradeCompendium = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)
	await process_frame

	_screen = UpgradeCompendium.new()
	_menu.add_child(_screen)
	# Nothing is captured on the frame the screen is BUILT: process_frame fires
	# before the UI is drawn, so a shot here comes back as the bare menu. The
	# trap SummaryShot records, whose own two shots came out identical for
	# exactly this reason.
	await process_frame
	await process_frame

	var wanted := {
		Upgrades.Line.BUFFER_WINDOW: "01_corridor_buffer",
		Upgrades.Line.PATH_INDICATOR: "02_corridor_strip",
		Upgrades.Line.CORNERING: "03_bar",
		Upgrades.Line.BARRIER_CAPACITY: "04_gauge",
		Upgrades.Line.QUADRANT: "05_panel",
		Upgrades.Line.FLYING_VISION: "06_still",
		Upgrades.Line.WALL_SMASHER: "07_legendary_smash",
	}

	for line in wanted:
		var index := _screen._lines.find(int(line))
		if index == -1:
			push_error("CompendiumShot: no row for line %d" % line)
			continue
		await _shoot(index, String(wanted[line]))

	# The extremes, where the clamp binds hardest.
	await _shoot(0, "08_row_first")
	await _shoot(_screen._lines.size() - 1, "09_row_last")

	print("RESULT: PASS")
	quit(0)


func _shoot(index: int, name: String) -> void:
	_screen._select(index)
	for _i in range(SETTLE):
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/compendium_%s.png" % [SHOT_DIR, name]
	if image.save_png(path) == OK:
		print("shot %s" % path)
	else:
		push_error("CompendiumShot: could not write %s" % path)
