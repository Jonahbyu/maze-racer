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
	for wanted in ["PLAY", "TRAILER", "MOBILE CONTROLS", "QUIT"]:
		check("the menu offers %s" % wanted, joined.contains(wanted), joined)

	# PLAY must reach a real, running Game -- not just swap a node in.
	shell.start_game()
	check("PLAY starts a game", int(shell.mode) == Shell.Mode.GAME)
	var game = shell._current
	check("the game has a racer", game != null and game.get("racer") != null)
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
		var before: bool = bool(settings.touch_controls)
		menu2._on_toggle_touch()
		check("the toggle flips the setting",
			bool(settings.touch_controls) != before)
		check("the button label follows the setting",
			String(menu2._touch_button.text).contains(
				"ON" if bool(settings.touch_controls) else "OFF"),
			String(menu2._touch_button.text))

		# Into a game, and the pads must agree with what the menu was left on.
		shell.start_game()
		var g = shell._current
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
