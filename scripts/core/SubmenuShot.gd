# The picture half of the grouped menus.
#
# MenuShot shoots the ROOT at three widths; this walks into every submenu and
# shoots each one, at phone dimensions -- which is where the grouping is FOR.
# Nine flat buttons did not fit an 844x390 screen (measured: 5 rows of 2 needing
# 718 viewport units against a 440-unit band), and the previous answer switched
# five of them off, so MARKER, UPGRADES and MAZE COLOURS were unreachable there.
#
# What no assertion can judge: whether a submenu reads as a submenu. ShellTest
# proves every row exists and every menu has a BACK; only a frame shows whether
# the title lands clear of the logo, whether BACK reads as an escape rather than
# as another option, and whether the stack still clears the hint.
extends SceneTree

const SHOT_DIR := "res://logs"
const SETTLE := 24

# The phone TouchShot and MenuShot both use, so all three tools describe the
# same device.
const PHONE := Vector2i(844, 390)

var _menu: MainMenu = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_window().size = PHONE
	_menu = MainMenu.new()
	root.add_child(_menu)
	await process_frame
	await process_frame

	for id in MainMenu.MENUS:
		_menu._build_menu(String(id))
		# BUILD ON ONE FRAME, CAPTURE ON THE NEXT -- process_frame fires before
		# the UI is drawn, so shooting here catches the PREVIOUS menu (the trap
		# SummaryShot and MarkerShot both record).
		await _shoot(String(id))

	print("RESULT: PASS")
	quit(0)


func _shoot(name: String) -> void:
	for _i in range(SETTLE):
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/submenu_%s.png" % [SHOT_DIR, name]
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		push_error("SubmenuShot: could not write %s" % path)
