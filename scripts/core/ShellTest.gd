# Does the shell boot to a menu, and do both of its buttons lead somewhere?
#
# The shell is thin, but it is the only path a player has into the game now --
# a break here means the game does not start at all, which no other harness
# would notice because they all instantiate Game.tscn directly.
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== ShellTest ===")
	_go.call_deferred()


func check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _go() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	check("Main.tscn loads", scene != null)
	if scene == null:
		_finish()
		return

	var shell = scene.instantiate()
	check("Main.tscn instantiates a Shell", shell is Shell)
	root.add_child(shell)

	check("boots to the menu", int(shell.mode) == Shell.Mode.MENU,
		"mode %d" % int(shell.mode))

	var menu = shell._current
	check("the menu is a MainMenu", menu is MainMenu)
	# What the buttons SAY, not how many there are. A bare count is a
	# transcription check (CLAUDE.md section 12) -- it broke the moment a fourth
	# button was added and reported nothing except that two literals had
	# drifted. Naming the actions asserts the menu still offers a way in, a way
	# to watch, and a way out.
	var labels := PackedStringArray()
	if menu != null:
		for button in menu._buttons:
			labels.append(String(button.text))
	var joined := ", ".join(labels)
	# MOBILE CONTROLS is deliberately NOT here -- it moved into the settings
	# panel behind the cog, so that preferences live in one place.
	for wanted in ["PLAY", "TRAILER", "QUIT"]:
		check("the menu offers %s" % wanted, joined.contains(wanted), joined)
	check("the menu has a settings cog", menu != null and menu._cog != null)

	# PLAY must reach a real, running Game -- not just swap a node in.
	shell.start_game()
	check("PLAY starts a game", int(shell.mode) == Shell.Mode.GAME)
	var game = shell._current
	check("the game has a racer", game != null and game.get("racer") != null)
	# A game opens on the maze-1 loadout pick (CLAUDE.md section 7), so PLAY
	# lands in UPGRADING and racing starts once a card is taken. Every input
	# check below has to come AFTER that -- the pads and the keyboard are both
	# correctly inert during a pick, which is the behaviour section 9d requires.
	check("PLAY opens the loadout pick",
		game != null and int(game.get("phase")) == 1)
	_take_loadout(game)
	check("the game is racing", game != null and int(game.get("phase")) == 0)
	check("a normal run is NOT trailer-seeded",
		game != null and int(game.get("run_seed")) != TrailerDirector.TRAILER_SEED,
		"seed %d" % (int(game.get("run_seed")) if game != null else 0))

	# The mobile-controls toggle, which is the one preference that has to
	# survive a mode change -- it is set on the menu and read by the game, and
	# Shell frees the menu on the way there.
	shell.show_menu()
	var menu2 = shell._current
	var settings = shell.get_node_or_null("/root/Settings")
	check("the Settings autoload is registered", settings != null)
	if settings != null and menu2 != null:
		var music_volume_before: float = float(settings.music_volume)
		var music_muted_before: bool = bool(settings.music_muted)

		# The cog opens the panel, and the panel is what owns the toggle now.
		menu2._on_settings()
		var panel = menu2._panel
		check("the cog opens a settings panel", panel != null)

		var before: bool = bool(settings.touch_controls)
		if panel != null:
			panel._on_toggle_touch()
		check("the panel toggle flips the setting",
			bool(settings.touch_controls) != before)
		check("the panel label follows the setting",
			panel != null and String(panel._touch_button.text).contains(
				"ON" if bool(settings.touch_controls) else "OFF"),
			String(panel._touch_button.text) if panel != null else "no panel")

		# Music volume, the reason the panel exists. Written through Settings
		# so it persists, and read back off the panel's own readout.
		if panel != null:
			panel._on_volume_changed(0.42)
			check("the panel sets the music volume",
				is_equal_approx(float(settings.music_volume), 0.42),
				str(settings.music_volume))
			check("the volume readout follows the slider",
				String(panel._volume_label.text) == "42%",
				String(panel._volume_label.text))

			# Mute is a separate flag from a zero volume, so that unmuting
			# restores the level the player chose.
			panel._on_toggle_mute()
			check("the panel mutes", bool(settings.music_muted))
			check("muting leaves the volume alone",
				is_equal_approx(float(settings.music_volume), 0.42),
				str(settings.music_volume))
			panel._on_toggle_mute()
			check("the panel unmutes", not bool(settings.music_muted))

			# Moving the slider off zero while muted is a request to hear
			# something -- it must not leave the player with a slider that
			# climbs and does nothing.
			panel._on_toggle_mute()
			panel._on_volume_changed(0.6)
			check("raising the volume while muted unmutes",
				not bool(settings.music_muted))

		menu2._on_settings_closed()
		check("closing frees the panel", menu2._panel == null)

		# Put the player's own audio preference back. A harness that leaves the
		# state it inspected changed is the TouchShot trap (CLAUDE.md section
		# 9d) -- here it would quietly rewrite the volume someone had chosen.
		settings.set_music_volume(music_volume_before)
		settings.set_music_muted(music_muted_before)

		# Into a game, and the pads must agree with what the menu was left on.
		shell.start_game()
		var g = shell._current
		# Clear the loadout pick before driving any input: steering is gated off
		# during a pick, for both the pads and the keyboard.
		_take_loadout(g)
		var pads = g.get_node_or_null("UI/UIRoot/TouchControls")
		check("the game builds touch controls", pads != null)
		check("the pads honour the setting",
			pads != null and pads.visible == bool(settings.touch_controls),
			"visible %s, setting %s" % [
				pads.visible if pads != null else "?",
				settings.touch_controls])

		# A pad drives the racer through the SAME path the keyboard uses.
		#
		# request_turn either resolves on the spot -- changing facing -- or arms
		# the buffer, depending on whether the side is open right here. Either
		# outcome proves the call landed; asserting only one would make the
		# check depend on where the racer happened to spawn.
		if pads != null and g.get("racer") != null:
			var facing_before: int = int(g.racer.facing)
			var pending_before: int = int(g.racer.pending_turn)
			g._on_turn_input(-1)
			check("a pad request reaches the racer",
				int(g.racer.facing) != facing_before
					or int(g.racer.pending_turn) != pending_before,
				"facing %d->%d, pending %d->%d" % [
					facing_before, int(g.racer.facing),
					pending_before, int(g.racer.pending_turn)])

		# The 180 gesture: left and right together, with no pad of its own.
		#
		# Driven through _steer rather than the signal, because what is being
		# checked is the CHORD RESOLUTION -- that the second press turns into a
		# reverse instead of a second turn. Emitting reverse_requested directly
		# would assert nothing about it.
		if pads != null:
			check("the reverse pad is gone", not pads._pads.has("reverse"),
				str(pads._pads.keys()))

			var seen := {"turns": 0, "reverses": 0}
			pads.turn_requested.connect(func(_d: int) -> void:
				seen["turns"] = int(seen["turns"]) + 1)
			pads.reverse_requested.connect(func() -> void:
				seen["reverses"] = int(seen["reverses"]) + 1)

			pads.clear_held()
			pads._steer(-1)
			check("one pad alone is a turn",
				int(seen["turns"]) == 1 and int(seen["reverses"]) == 0,
				"turns %d reverses %d" % [seen["turns"], seen["reverses"]])

			pads._steer(1)
			check("both pads together is a reverse",
				int(seen["reverses"]) == 1,
				"turns %d reverses %d" % [seen["turns"], seen["reverses"]])

			# And the state must not latch: after releasing, a lone press is a
			# turn again. This is the bug that would make every later tap a
			# reverse, and it is invisible until the second gesture.
			pads.clear_held()
			pads._steer(1)
			check("the chord does not latch",
				int(seen["turns"]) == 2 and int(seen["reverses"]) == 1,
				"turns %d reverses %d" % [seen["turns"], seen["reverses"]])

		# Pads must SCALE with the screen, not sit at a fixed pixel size.
		#
		# They were a screen fraction capped at a pixel maximum, and the cap won
		# on a phone -- which reports a large pixel viewport -- so the smallest
		# screen got the same small pad as a desktop window. A pixel is a count,
		# not a size. Driving _layout at two viewport sizes is the only way to
		# catch that without a device.
		if pads != null:
			pads.size = Vector2(1600, 900)
			pads._layout()
			var big: Vector2 = pads._pads["left"].size

			pads.size = Vector2(844, 390)
			pads._layout()
			var small: Vector2 = pads._pads["left"].size

			check("pads scale with the screen", big.y > small.y,
				"900px screen -> %.0f, 390px screen -> %.0f" % [big.y, small.y])

			# And they must stay ON the screen at phone size, which the fixed
			# 120px HUD band broke: it is nearly a third of a 390px display.
			var pad_bottom: float = pads._pads["left"].position.y + small.y
			check("pads fit a phone screen", pad_bottom <= 390.0,
				"bottom edge at %.0f of 390" % pad_bottom)

			# The icons are drawn, never typed -- a font fallback on an unknown
			# device can render a glyph as blank or tofu, and these are the
			# controls the player steers with.
			check("the arrows are drawn, not lettered",
				pads._pads["left"].get_node_or_null("icon/arrow") != null)

		# The chord is MOBILE ONLY. The keyboard keeps its own reverse key and
		# must not acquire a left+right gesture along the way -- pressing both
		# arrows at once on a desktop is an ordinary thing to do by accident,
		# and it must stay two turns.
		#
		# Checked with the pads switched OFF, which is the desktop
		# configuration: the keyboard's reverse still has to work, and it must
		# reach the racer without going through TouchControls at all.
		settings.set_touch_controls(false)
		check("the pads hide when the setting is off", not pads.visible)
		if g.get("racer") != null:
			var f_before: int = int(g.racer.facing)
			g._on_turn_input(-1)
			g._on_turn_input(1)
			check("two arrow presses are not a reverse on desktop",
				int(g.racer.facing) != Maze.OPPOSITE[f_before],
				"facing %d -> %d" % [f_before, int(g.racer.facing)])

			var f2: int = int(g.racer.facing)
			g._on_reverse_input()
			check("the keyboard reverse still works",
				int(g.racer.facing) == int(Maze.OPPOSITE[f2]),
				"facing %d -> %d" % [f2, int(g.racer.facing)])

		# Put it back the way the player had it.
		settings.set_touch_controls(before)

	# And back out, then into the trailer.
	shell.show_menu()
	check("returns to the menu", int(shell.mode) == Shell.Mode.MENU)

	shell.start_trailer()
	check("TRAILER starts the reel", int(shell.mode) == Shell.Mode.TRAILER)
	var trailer = shell._current
	check("the trailer is a TrailerDirector", trailer is TrailerDirector)
	check("the trailer built its own game",
		trailer != null and trailer._game != null)
	check("the trailer IS seeded from the constant",
		trailer != null and trailer._game != null
			and int(trailer._game.run_seed) == TrailerDirector.TRAILER_SEED)

	# The reel hands the screen back when it finishes or is skipped. Driving the
	# signal directly rather than playing 30s of trailer -- what is being checked
	# is the wiring, and the reel itself has its own harness.
	trailer.emit_signal("finished")
	check("finishing the reel returns to the menu",
		int(shell.mode) == Shell.Mode.MENU, "mode %d" % int(shell.mode))

	_finish()


func _finish() -> void:
	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


# Dismiss a maze-start loadout pick by taking the first card offered.
#
# Harnesses that drive input have to clear this first: a game boots into the
# pick, and steering is deliberately gated off while it is up.
func _take_loadout(game) -> void:
	if game == null or int(game.get("phase")) != 1:
		return
	var offered: Array = game._upgrade_screen._lines
	if offered.is_empty():
		game._on_upgrade_chosen(-1)
	else:
		game._on_upgrade_chosen(offered[0])
