# The picture half of the settings panel. Layout is exactly what no headless
# assertion can check -- the HUD collisions in section 9d were all found this
# way and none of them by a test.
#
# Shoots both mounts, because they sit over different backgrounds: the menu's
# flat card, and the pause screen's live corridor behind a scrim.
extends SceneTree

const OUT := "res://logs"


func _init() -> void:
	await process_frame
	var shell = load("res://scenes/Main.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame

	# --- The menu mount ---
	var menu = shell._current
	menu._on_settings()
	for _i in 4:
		await process_frame
	_shoot("shot_settings_menu.png")

	menu._on_settings_closed()
	await process_frame
	_shoot("shot_settings_cog.png")

	# --- The pause mount ---
	shell.start_game()
	var game = shell._current
	await process_frame
	# A run opens on the loadout pick; take a card so the corridor is live.
	if int(game.phase) == 1:
		game._on_upgrade_chosen(0)
	for _i in 30:
		await process_frame

	game._set_paused(true)
	await process_frame
	_shoot("shot_settings_paused_cog.png")

	game._open_settings()
	for _i in 4:
		await process_frame
	_shoot("shot_settings_paused.png")

	print("shots written to logs/")
	quit()


func _shoot(name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [OUT, name])
	print("  %s  %dx%d" % [name, image.get_width(), image.get_height()])
