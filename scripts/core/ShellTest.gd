# Does the shell boot to a menu, and do both of its buttons lead somewhere?
#
# The shell is thin, but it is the only path a player has into the game now --
# a break here means the game does not start at all, which no other harness
# would notice because they all instantiate Game.tscn directly.
extends SceneTree

# Preloaded rather than referenced by class_name: Unlocks is an autoload, so it
# deliberately has none (see the note in that file).
const UnlocksScript := preload("res://scripts/core/Unlocks.gd")

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
	check("PLAY counts toward the general board",
		game != null and int(game.get("board")) == Tuning.Board.GENERAL)

	# The daily and monthly buttons.
	#
	# Asserted through the MENU's own signal rather than by calling start_game
	# directly, because the wiring is the part that can rot: a button bound to
	# the wrong board, or a signal that drops its argument, both leave
	# start_game perfectly correct and the player on the wrong maze.
	#
	# The seed is checked against Tuning rather than a literal -- restating the
	# hash would be a transcription check (CLAUDE.md section 12), and it would
	# go stale the day after it was written.
	for spec in [[Tuning.Board.DAILY, "DAILY", Tuning.seed_for_date(Tuning.today_key())],
			[Tuning.Board.MONTHLY, "MONTHLY", Tuning.seed_for_month(Tuning.this_month_key())]]:
		var want_board: int = int(spec[0])
		var label: String = String(spec[1])
		var want_seed: int = int(spec[2])

		shell.show_menu()
		var m = shell._current
		var button: Button = null
		for b in m._buttons:
			if b.text == "PLAY " + label:
				button = b
		check("the menu has a PLAY %s button" % label, button != null)
		if button == null:
			continue

		button.pressed.emit()
		var run = shell._current
		check("PLAY %s starts a game" % label,
			int(shell.mode) == Shell.Mode.GAME and run != null)
		check("PLAY %s counts toward the %s board" % [label, label],
			run != null and int(run.get("board")) == want_board)
		# The whole point of the button: a shared maze, not a fresh one.
		check("PLAY %s uses the date-derived seed" % label,
			run != null and int(run.get("run_seed")) == want_seed,
			"seed %d, want %d" % [int(run.get("run_seed")) if run != null else 0, want_seed])
		_take_loadout(run)
		check("PLAY %s reaches a racing game" % label,
			run != null and int(run.get("phase")) == 0
				and run.get("racer") != null)

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

			# The pads must report HELD direction, not only presses.
			#
			# Deep Breath and Overclock (section 7) both need a key to still be
			# down, which the keyboard gets from release events. The pads already
			# tracked this internally for the chord above and simply did not expose
			# it, so both lines were inert on a phone while working on a desktop --
			# a divergence between tap and key press that no keyboard-driven test
			# would ever see, which is exactly what section 9d says must not rot.
			var held := {"last": -99}
			pads.held_direction_changed.connect(func(d: int) -> void:
				held["last"] = d)

			pads.clear_held()
			pads._steer(-1)
			check("a pad press reports the held direction",
				int(held["last"]) == -1, "reported %d" % held["last"])

			# Lifting one finger of a chord must report what is STILL held, never a
			# bare 0 -- that would cut an extension short mid-corner.
			#
			# The sentinel is reset AFTER the second press and before the release,
			# or the assertion reads the press's own emit and passes however the
			# release behaves. Verified by deleting the release emit: without this
			# reset the check still passed, which made it a false positive rather
			# than a test.
			pads._steer(1)
			held["last"] = -99
			pads._on_pad_input(pads._pads["left"], _release_event(),
				func() -> void: pass, -1)
			check("releasing one of a chord reports the other",
				int(held["last"]) == 1, "reported %d, held=%s" % [
					held["last"], str(pads._held_dirs)])

			# And hiding the overlay releases everything, or an extension bought on
			# the way out would last forever.
			pads.clear_held()
			check("hiding the pads releases the held direction",
				int(held["last"]) == 0, "reported %d" % held["last"])

			# ONE TAP IS ONE TURN, and the tap has to be driven as a real touch
			# event rather than through _steer.
			#
			# Godot's `emulate_mouse_from_touch` defaults to TRUE, so a phone
			# delivers every tap twice: the InputEventScreenTouch first, then a
			# synthesized InputEventMouseButton from the same finger. This handler
			# accepted both, so one thumb press turned the racer twice -- the
			# phantom second turn "a second later" that made the game unplayable on
			# a phone. On desktop there is no touch device, so the mouse branch
			# fires alone and nothing looks wrong.
			#
			# Every other pad check above calls _steer directly and so cannot see
			# this: the bug lives in the event DISPATCH, not in the chord logic.
			pads.clear_held()
			seen["turns"] = 0
			seen["reverses"] = 0
			pads._on_pad_input(pads._pads["left"], _touch_event(true),
				func() -> void: pads._steer(-1), -1)
			pads._on_pad_input(pads._pads["left"], _mouse_event(true),
				func() -> void: pads._steer(-1), -1)
			check("one tap is one turn",
				int(seen["turns"]) == 1 and int(seen["reverses"]) == 0,
				"turns %d reverses %d" % [seen["turns"], seen["reverses"]])

			# The release pair must not latch either: a touch release followed by
			# its emulated mouse release must leave nothing held, or the next tap
			# reads as a chord.
			pads._on_pad_input(pads._pads["left"], _touch_event(false),
				func() -> void: pass, -1)
			pads._on_pad_input(pads._pads["left"], _mouse_event(false),
				func() -> void: pass, -1)
			check("a tap release leaves nothing held",
				pads._held_dirs.is_empty(), str(pads._held_dirs))

			# And a mouse tap on its own still works, because the pads are
			# available on desktop for testing without a phone in hand.
			#
			# The echo window is checked GLOBALLY rather than per pad -- the
			# browser delivers the synthesized mousedown at the position the
			# finger lifted from, which is often a different pad (see the
			# cross-pad check below). So modelling a desktop means modelling a
			# machine that has sent no touch at all: the stamp is pushed back
			# by clearing the touch latch, which is what a real desktop is:
			# no InputEventScreenTouch is ever emitted there, so the latch
			# never closes and the mouse path stays live.
			pads.clear_held()
			pads._seen_touch = false
			seen["turns"] = 0
			pads._on_pad_input(pads._pads["right"], _mouse_event(true),
				func() -> void: pads._steer(1), 1)
			check("a mouse-only tap still turns", int(seen["turns"]) == 1,
				"turns %d" % seen["turns"])
			pads.clear_held()

			# A tap must emit exactly ONE held-direction change per edge.
			#
			# The press half is covered above, but the RELEASE half has its own
			# ordering trap: the touch release erases the pad's finger claim, so
			# the emulated mouse release that follows is no longer recognised as
			# an echo and runs the release branch a second time. _held_dirs makes
			# that harmless -- erase is idempotent -- but the signal is not, and
			# Deep Breath and Overclock both listen to it. A duplicate 0 there is
			# a held direction dropped twice, which is the phantom input again
			# wearing different clothes.
			pads.clear_held()
			var edges := {"n": 0}
			var counter := func(_d: int) -> void:
				edges["n"] = int(edges["n"]) + 1
			pads.held_direction_changed.connect(counter)

			pads._on_pad_input(pads._pads["left"], _touch_event(true),
				func() -> void: pads._steer(-1), -1)
			pads._on_pad_input(pads._pads["left"], _mouse_event(true),
				func() -> void: pads._steer(-1), -1)
			check("a tap press emits one held change", int(edges["n"]) == 1,
				"emitted %d" % edges["n"])

			edges["n"] = 0
			pads._on_pad_input(pads._pads["left"], _touch_event(false),
				func() -> void: pass, -1)
			pads._on_pad_input(pads._pads["left"], _mouse_event(false),
				func() -> void: pass, -1)
			check("a tap release emits one held change", int(edges["n"]) == 1,
				"emitted %d" % edges["n"])

			pads.held_direction_changed.disconnect(counter)
			pads.clear_held()

			# And a tap AFTER a gesture reset is still one turn.
			#
			# clear_held runs whenever the overlay hides -- a gate, a pause, the
			# setting going off -- so if that also forgot the pad was
			# touch-driven, the first tap after every upgrade pick would
			# double-fire again. Which pad is a finger's is a fact about the
			# DEVICE, not about the gesture, so it has to outlive the reset.
			pads.clear_held()
			seen["turns"] = 0
			seen["reverses"] = 0
			pads._on_pad_input(pads._pads["left"], _touch_event(true),
				func() -> void: pads._steer(-1), -1)
			pads._on_pad_input(pads._pads["left"], _mouse_event(true),
				func() -> void: pads._steer(-1), -1)
			check("a tap after a reset is still one turn",
				int(seen["turns"]) == 1 and int(seen["reverses"]) == 0,
				"turns %d reverses %d" % [seen["turns"], seen["reverses"]])
			pads.clear_held()

			# A RELEASE THIS PAD NEVER SAW A PRESS FOR MUST DO NOTHING.
			#
			# This is the "phantom turn while driving straight" report, and it
			# is a different bug from the double-tap one above. `released` is
			# just `not event.pressed`, so ANY release-shaped event runs the
			# release branch -- whether or not this pad was ever pressed. That
			# branch emits held_direction_changed, and Game routes that into
			# _set_held_direction, so an unmatched release reports a direction
			# change the player never made.
			#
			# A phone delivers exactly this. clear_held() runs on every phase
			# change (a gate, a pause), dropping _held_dirs while a finger is
			# still resting on the screen -- so the eventual lift arrives as a
			# release with no press behind it.
			# Reconnect the edge counter: it was disconnected above, and an
			# assertion counting a signal nothing listens to cannot fail.
			pads.held_direction_changed.connect(counter)
			pads.clear_held()
			edges["n"] = 0
			pads._on_pad_input(pads._pads["left"], _touch_event(false),
				func() -> void: pass, -1)
			check("an unmatched touch release emits no held change",
				int(edges["n"]) == 0, "edges %d" % edges["n"])

			# The same via the emulated mouse release, which is what actually
			# arrives second on a phone.
			pads.clear_held()
			edges["n"] = 0
			pads._on_pad_input(pads._pads["left"], _mouse_event(false),
				func() -> void: pass, -1)
			check("an unmatched mouse release emits no held change",
				int(edges["n"]) == 0, "edges %d" % edges["n"])

			# A DRAG IS NOT A TAP.
			#
			# A thumb resting on a pad is never perfectly still, so a phone
			# raises InputEventScreenDrag continuously -- and Godot emulates an
			# InputEventMouseMotion from each one. Neither is a press or a
			# release, so neither may move the racer or the held state.
			pads.clear_held()
			seen["turns"] = 0
			seen["reverses"] = 0
			edges["n"] = 0
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			pads._on_pad_input(pads._pads["left"], drag,
				func() -> void: pads._steer(-1), -1)
			var motion := InputEventMouseMotion.new()
			pads._on_pad_input(pads._pads["left"], motion,
				func() -> void: pads._steer(-1), -1)
			check("a drag across a pad is not a turn",
				int(seen["turns"]) == 0 and int(edges["n"]) == 0,
				"turns %d edges %d" % [seen["turns"], edges["n"]])

			# THE ECHO IS NOT ALWAYS DELIVERED TO THE PAD THAT WAS TOUCHED.
			#
			# Measured on production, one finger raises these in this order:
			#   touchstart@10963 touchend@11115 mousedown@11115 mouseup@11115
			# The browser synthesizes its mousedown AFTER touchend -- 152ms
			# later, at the position the finger LIFTED from. A thumb that
			# lands on one pad and lifts a little to the side therefore sends
			# the echo to a DIFFERENT pad, whose echo window no touch ever
			# opened, so the guard passes it through as a genuine click.
			#
			# On a straight corridor that arms a turn with no opening to take,
			# which expires into the -0.5x slowdown (section 5.2) a second or
			# so later: a phantom penalty for an input the player never made,
			# arriving well after the thumb left the glass.
			#
			# A per-pad stamp cannot see this, because the two events are on
			# two different pads by construction.
			pads.clear_held()
			seen["turns"] = 0
			seen["reverses"] = 0
			pads._on_pad_input(pads._pads["left"], _touch_event(true),
				func() -> void: pads._steer(-1), -1)
			pads._on_pad_input(pads._pads["left"], _touch_event(false),
				func() -> void: pass, -1)
			pads._on_pad_input(pads._pads["right"], _mouse_event(true),
				func() -> void: pads._steer(1), 1)
			pads._on_pad_input(pads._pads["right"], _mouse_event(false),
				func() -> void: pass, 1)
			check("an echo landing on another pad is still one turn",
				int(seen["turns"]) == 1 and int(seen["reverses"]) == 0,
				"turns %d reverses %d" % [seen["turns"], seen["reverses"]])

			# A HELD TAP, which is what a thumb actually does.
			#
			# This is the case every earlier assertion here missed, and the
			# miss shipped: they fire touchstart and the echo back to back, so
			# the echo always landed inside the window no matter how the window
			# was measured. A real press RESTS on the pad first.
			#
			# Measured on the live page with a realistic 450ms hold:
			#   touchstart@10388  touchend@10871  mousedown@10871
			# The echo arrives 483ms after the press, because the browser
			# generates it from the LIFT. A window measured from the press has
			# to cover the whole hold, and no window short enough to be safe
			# can -- so every press held longer than it escaped the guard and
			# was taken for a genuine click. That is the double turn, the
			# phantom slowdown behind it, and the pause that toggles straight
			# back off, all from one cause.
			#
			# The guard is now a latch on having seen a finger, so held time
			# is irrelevant by construction rather than by tuning -- which is
			# what this asserts.
			pads.clear_held()
			seen["turns"] = 0
			seen["reverses"] = 0
			pads._on_pad_input(pads._pads["left"], _touch_event(true),
				func() -> void: pads._steer(-1), -1)
			# The thumb RESTS, then lifts, and only then does the echo arrive.
			#
			# No clock is wound here any more, and that is the point: the guard
			# is a latch on having seen a finger, so HOW LONG the gesture takes
			# cannot affect it. Two timestamp schemes were beaten in play
			# before this -- the echo is synthesized inside the engine and
			# delivered on whatever frame it reaches, which is late exactly
			# when the phone is busiest.
			pads._on_pad_input(pads._pads["left"], _touch_event(false),
				func() -> void: pass, -1)
			# A DELAYED echo, which is what beat both timestamp schemes: the
			# emulated event is synthesized inside the engine and delivered on
			# whatever frame it reaches, so under load it can arrive long after
			# any window has shut. Modelled by simply letting real time pass.
			OS.delay_msec(900)
			pads._on_pad_input(pads._pads["left"], _mouse_event(true),
				func() -> void: pads._steer(-1), -1)
			pads._on_pad_input(pads._pads["left"], _mouse_event(false),
				func() -> void: pass, -1)
			check("a HELD tap with a DELAYED echo is still one turn",
				int(seen["turns"]) == 1 and int(seen["reverses"]) == 0,
				"turns %d reverses %d" % [seen["turns"], seen["reverses"]])
			pads.held_direction_changed.disconnect(counter)
			pads.clear_held()

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

			# THE PAUSE PAD MUST CLEAR THE SETTINGS COG.
			#
			# Both live in the top-right corner, and the cog is only visible
			# while paused -- which is exactly when the pause pad is the thing
			# the player is reaching for. Measured before this check existed,
			# the cog's whole 52x52 rect sat INSIDE the pause pad at every
			# viewport size, and the pads are added to UIRoot after the cog, so
			# the pad swallowed every tap and the cog was unreachable on the one
			# platform that has a pause pad at all.
			#
			# Checked at both sizes: the overlap was size-independent, so a
			# single viewport would not have proved the clearance holds.
			for vp in [Vector2(1600, 900), Vector2(2526, 900)]:
				pads.size = vp
				pads._layout()
				var pause_pad: Panel = pads._pads["pause"]
				var pause_r := Rect2(pause_pad.position, pause_pad.size)
				# Game has no class_name, so its cog constants cannot be read
				# from here. TouchControls.COG_BOTTOM is the shared statement of
				# where the cog ends; the margin and size come from MainMenu,
				# which does declare a class_name.
				var cog_top: float = TouchControls.COG_BOTTOM - MainMenu.COG_SIZE
				var cog_r := Rect2(
					vp.x - MainMenu.COG_SIZE - MainMenu.COG_MARGIN, cog_top,
					MainMenu.COG_SIZE, MainMenu.COG_SIZE)
				check("the pause pad clears the settings cog at %.0f" % vp.x,
					not pause_r.intersects(cog_r),
					"pause %s cog %s" % [str(pause_r), str(cog_r)])

			# And it has to be big enough to actually hit.
			#
			# The viewport is NOT the screen: stretch/mode is canvas_items with
			# aspect=expand, so a phone whose canvas is 828x295 CSS pixels gets
			# a ~2526x900 viewport and everything is drawn at 0.33x. At the old
			# 0.13 fraction the pause pad came out 52x38 ON GLASS, under the
			# 44x44 minimum Apple and Google both publish -- a button that is
			# perfectly wired and cannot be pressed.
			pads.size = Vector2(2526, 900)
			pads._layout()
			var phone_pause: Vector2 = pads._pads["pause"].size
			# 828x295 canvas against a 2526x900 viewport.
			var glass_scale := 295.0 / 900.0
			var glass := phone_pause * glass_scale
			check("the pause pad is big enough to tap on a phone",
				glass.x >= TouchControls.MIN_TAP_CSS_PX
					and glass.y >= TouchControls.MIN_TAP_CSS_PX,
				"%.0fx%.0f CSS px, minimum %.0f"
					% [glass.x, glass.y, TouchControls.MIN_TAP_CSS_PX])
			pads.size = Vector2(1600, 900)
			pads._layout()

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

	_check_leaderboard_panel(shell)
	_check_menu_buttons(shell)
	_check_name_prompt(shell)
	_check_unlocks_autoload()

	_finish()


# The leaderboard panel and the two-column menu
# (docs/plans/leaderboards.md).
#
# Everything here runs with the Leaderboard autoload reporting UNAVAILABLE,
# because a harness has no browser and no network -- which is exactly the state
# a desktop player is in. The panel must draw its empty state and the menu must
# be completely usable, or the desktop build breaks for want of a feature it was
# never meant to have.
# The one-time leaderboard name prompt (docs/plans/leaderboards.md).
#
# The interesting case here is the one a harness gets for free: with no
# Leaderboard autoload available, PLAY must start a run with NO prompt at all.
# A gate that fired without a board to post to would make the desktop build
# unplayable for a feature it does not have -- and it would fire in every
# harness, so this is asserted rather than assumed.
# The menu's buttons must be reachable with a THUMB, not merely present.
#
# The viewport is not the screen (section 9d), and this is the third feature
# caught by it. Measured before the fix, the six-button stack rendered
# 118 x 18 CSS px with 7.9px labels on an 828x295 phone -- under half the 44px
# both Apple and Google publish, on the one platform the menu is hardest to use.
#
# Driven through _size_buttons at two viewport sizes, because the wide case
# passes trivially: on a desktop the scale is 1.0 and every derived number
# reduces to the constant it always was, so a broken derivation would be
# invisible if only one size were tested. Same reason the minimap and the
# mirror are both asserted at two sizes.
func _check_menu_buttons(shell) -> void:
	shell.show_menu()
	var menu = shell._current
	if menu == null:
		check("the menu exists for the button-size check", false)
		return

	# A desktop window: one column, the sizes this menu has always drawn.
	#
	# Note this reads the HEADLESS viewport, whose stretch scale is meaningless
	# -- a 64x64 dummy reporting 0.04. _view_scale is guarded against exactly
	# that and returns 1.0, so what this asserts is that the guard HOLDS: a
	# harness must get desktop numbers, not numbers inflated 25x. That guard is
	# not a detail. Without it every size on this screen is derived from a
	# fiction, and the assertions would still look plausible.
	menu.size = Vector2(1600, 900)
	menu._size_buttons()
	var wide: Vector2 = menu._buttons[0].custom_minimum_size
	# At scale 1.0 a button is BUTTON_GLASS_PX tall, since a viewport unit and a
	# screen pixel are the same thing there. It must still clear the tap
	# minimum, which is the property that actually matters on every platform.
	check("a desktop button clears the tap minimum",
		wide.y >= MainMenu.MIN_TAP_CSS_PX,
		"%.1f, minimum %.1f" % [wide.y, MainMenu.MIN_TAP_CSS_PX])
	check("a dummy viewport does not inflate the buttons",
		wide.y <= MainMenu.BUTTON_HEIGHT_MAX,
		"%.1f, max %.1f" % [wide.y, MainMenu.BUTTON_HEIGHT_MAX])

	# Every button that is SHOWN has to clear the tap minimum once the viewport
	# scale is applied. The grid is what the player presses; a button hidden on
	# a phone is not a target and is excluded rather than being sized for one.
	var grid: GridContainer = menu._button_grid
	check("the menu lays its buttons out in a grid", grid != null)

	var shown := 0
	for button in menu._buttons:
		if button.visible:
			shown += 1
	check("the menu shows buttons at all", shown > 0, "shown %d" % shown)

	# THE PHONE CASE, which is the one that broke.
	#
	# Driven through the menu's OWN sizing path with the scale forced, never by
	# recomputing the numbers here. A recomputation asserts the arithmetic
	# against itself: zeroing MIN_TAP_CSS_PX moves both sides of the comparison
	# together and the check still passes, which is exactly what it did before
	# this was rewritten. Reading back what the menu actually produced is the
	# only version that fails when the sizing is wrong.
	#
	# The desktop case above passes trivially -- at scale 1.0 every derived
	# number equals the constant it came from -- so this is the half that has to
	# be driven at a real phone's scale.
	var phone_scale := 0.328   # measured: an 828x295 canvas
	menu.scale_override = phone_scale
	menu._size_buttons()
	var tall: Vector2 = menu._buttons[0].custom_minimum_size
	check("a phone button clears the tap minimum ON GLASS",
		tall.y * phone_scale >= MainMenu.MIN_TAP_CSS_PX - 0.01,
		"%.1f CSS px, minimum %.1f" % [tall.y * phone_scale,
			MainMenu.MIN_TAP_CSS_PX])

	# ...and the label with it: 24 units was 7.9 CSS px on that same screen.
	var label_px: float = float(menu._buttons[0].get_theme_font_size("font_size"))
	check("a phone button label is readable ON GLASS",
		label_px * phone_scale >= 12.0,
		"%.1f CSS px" % (label_px * phone_scale))

	# NOT asserted here: that a phone shows the reduced button set. That rule
	# keys off the WINDOW's width, which a headless harness cannot change --
	# window_set_size is ignored by the dummy DisplayServer (section 12) -- so
	# any check of it would compare a number against itself and pass whatever
	# the code did. MenuShot's phone frame is what covers it, and it is a
	# rendered frame precisely because this is not reachable from here.

	menu.scale_override = -1.0
	menu._size_buttons()

	# The grid must not run off the bottom of the viewport, which is the failure
	# the summary panel already records: the best-looking layout in the game
	# with its last row past the screen edge.
	#
	# Bounded against the height the buttons ACTUALLY got rather than against
	# ROW_BOTTOM_LIMIT, which is a desktop band: on a real phone the tap floor
	# deliberately wins over the band, because a stack that runs slightly long
	# is recoverable where a row of 18px targets is not pressable at all. What
	# must always hold is that the grid fits the rows it chose.
	if grid != null:
		var rows_fit: float = MainMenu.ROW_TOP + wide.y * float(shown) 			+ MainMenu.SEPARATION * float(max(shown - 1, 0))
		check("the menu button grid is no taller than its rows",
			grid.offset_bottom <= rows_fit + 1.0,
			"ends %.0f, rows need %.0f" % [grid.offset_bottom, rows_fit])


func _check_name_prompt(shell) -> void:
	shell.show_menu()
	var menu = shell._current
	if menu == null:
		check("the menu exists for the name-prompt check", false)
		return

	var started := SignalCounter.new()
	menu.play_pressed.connect(started.on_play)

	# Offline: PLAY goes straight through, and no modal is built.
	menu._on_play(Tuning.Board.GENERAL)
	check("PLAY starts a run with no board available", started.count == 1)
	check("no name prompt is built when there is no board",
		menu._name_modal == null)

	# The prompt itself, driven directly. It cannot be reached through _on_play
	# here (there is no autoload to report a missing name), but the modal must
	# still build, take a name and hand the run on -- otherwise the web build
	# would be the only place this code ever ran, untested.
	menu._ask_name(Tuning.Board.DAILY)
	check("the prompt builds when asked directly", menu._name_modal != null)
	if menu._name_modal == null:
		return

	# SKIP must still start the run. A player who will not name themselves is
	# not a player who should be prevented from playing.
	var skip: Button = _find_button(menu._name_modal, "SKIP")
	check("the prompt offers SKIP", skip != null)
	if skip != null:
		skip.pressed.emit()
		check("SKIP starts the run anyway", started.count == 2)
		check("SKIP closes the prompt", menu._name_modal == null)

	# And the board it was asked for must survive the prompt -- a daily run that
	# came back as a general one would post to the wrong board silently.
	check("the prompt preserves the board it was opened for",
		int(started.last_board) == int(Tuning.Board.DAILY),
		"got %d" % int(started.last_board))


# Depth-first search for a button by its label.
# The Unlocks autoload is REGISTERED and reachable.
#
# Leaderboard shipped INERT in every build for weeks because it was never added
# to project.godot -- `git log -S "Leaderboard="` found it in no commit -- and
# nothing looked broken, because the panel drew its offline state correctly
# (section 9b-2).
#
# Unlocks fails the same silent way and worse: unlocks would simply never save,
# which is indistinguishable from not having earned anything. A player could
# grind for a colour forever.
func _check_unlocks_autoload() -> void:
	# Through the ROOT: this harness extends SceneTree, which has no node
	# lookups of its own.
	var node: Node = root.get_node_or_null("Unlocks")
	check("Unlocks is registered as an autoload", node != null)
	if node != null:
		check("Unlocks carries its table",
			node.ACHIEVEMENTS.size() > 0)


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		var b := child as Button
		if b != null and b.text == text:
			return b
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _check_leaderboard_panel(shell) -> void:
	shell.show_menu()
	var menu = shell._current
	check("the menu builds a leaderboard panel",
		menu != null and menu._leaderboard != null)
	if menu == null or menu._leaderboard == null:
		return

	var panel = menu._leaderboard
	check("the panel starts on the general board",
		int(panel._view) == LeaderboardPanel.View.GENERAL)
	check("the panel starts sorted by score", String(panel._sort) == "score")

	# All four views must switch without the autoload being reachable. This is
	# the case that would break silently: the panel asking an absent service for
	# rows and taking the error path on every click.
	for view in [LeaderboardPanel.View.DAILY, LeaderboardPanel.View.MONTHLY,
			LeaderboardPanel.View.HISTORY, LeaderboardPanel.View.GENERAL]:
		panel._set_view(view)
		check("switching to view %d works offline" % view,
			int(panel._view) == view)

	# The sort toggle changes the QUERY, not just the display -- so what is
	# asserted is the state the next fetch will use.
	panel._set_view(LeaderboardPanel.View.GENERAL)
	panel._set_sort("time")
	check("the sort toggle switches to time", String(panel._sort) == "time")
	panel._set_sort("score")
	check("the sort toggle switches back to score", String(panel._sort) == "score")

	# History is always newest-first, so its sort buttons are disabled rather
	# than present and inert.
	panel._set_view(LeaderboardPanel.View.HISTORY)
	var disabled := true
	for b in panel._sort_buttons:
		if not b.disabled:
			disabled = false
	check("history disables the sort toggle", disabled)
	panel._set_view(LeaderboardPanel.View.GENERAL)

	# Rows drawn from data, including the shapes a bad payload could take. The
	# rows come from Firestore, so they are untrusted input as far as this panel
	# is concerned -- a missing field must not be able to stop the menu drawing.
	panel._draw_rows([
		{"name": "Fav", "score": 452947.0, "time": 271.0},
		{"name": "TheSmallNut", "score": 1000000.0, "time": 300.0},
		{},
		"not a dictionary",
	])
	check("rows are drawn, malformed entries skipped",
		panel._rows_box.get_child_count() == 4,
		"got %d" % panel._rows_box.get_child_count())

	# An empty board draws its header and nothing else, rather than erroring.
	panel._draw_rows([])
	check("an empty board still draws a header",
		panel._rows_box.get_child_count() == 1)

	# --- The two-column split ---
	#
	# Driven directly rather than by resizing the window: headless ignores
	# window_set_size entirely (the dummy DisplayServer), which is the same
	# reason SceneTest drives UIRoot for the minimap check.
	menu._layout_columns()
	check("the layout runs without a viewport resize", true)

	# BOTH branches of the split, asserted by their actual condition rather than
	# by assuming the wide one.
	#
	# This check first read "the panel is anchored to the right edge"
	# unconditionally and failed once the split started working: the harness
	# window is narrower than TWO_COLUMN_MIN_WINDOW_WIDTH, so the single-column
	# branch is the correct one there and the right-edge anchors are never set.
	# The test was wrong, not the layout -- the same "did we actually vary
	# anything" trap SceneTest records for the minimap, arriving from the other
	# side.
	var win: Window = shell.get_window()
	var win_width := 0.0 if win == null else float(win.size.x)
	var expect_two := win_width >= MainMenu.TWO_COLUMN_MIN_WINDOW_WIDTH
	check("the panel is shown only when there is room for it",
		panel.visible == expect_two,
		"window %.0f wide, visible %s" % [win_width, str(panel.visible)])
	if expect_two:
		check("a two-column panel is anchored to the right edge",
			panel.anchor_left == 1.0 and panel.anchor_right == 1.0)
	else:
		# The fallback must genuinely return the menu to centre, or a narrow
		# window would leave the buttons shifted left with nothing beside them.
		var centred := true
		for node in menu.get_children():
			var c = node as Control
			# Skip full-rect backdrops by GROUP, not by type. This read
			# "c is ColorRect", which was the same type-standing-in-for-intent
			# mistake _place_left made: the background art is a TextureRect, so
			# the test demanded a full-rect backdrop be centred at 0.5 and
			# failed the moment the menu got real art -- reporting a layout
			# regression that did not exist.
			if c == null or c == panel or c == menu._cog:
				continue
			if c.is_in_group(MainMenu.GROUP_BACKDROP):
				continue
			if c.anchor_left != 0.5:
				centred = false
		check("the single-column fallback re-centres the menu", centred)

	# The autoload itself, when present.
	var lb = shell.get_node_or_null("/root/Leaderboard")
	if lb != null:
		check("the leaderboard autoload processes", lb.is_processing())
		check("no bridge outside a browser", not lb.available)
		check("posting without a bridge fails safely",
			not lb.post_run(1000.0, 60.0, 123, Tuning.Board.GENERAL, 1, false))
		# A board request with no bridge must still answer, or a caller waiting
		# on the signal hangs forever.
		var answered := SignalCounter.new()
		lb.board_loaded.connect(answered.on_board)
		lb.request_board(Tuning.Board.DAILY, "score")
		check("an offline board request still emits", answered.count == 1)
		lb.board_loaded.disconnect(answered.on_board)


class SignalCounter extends RefCounted:
	var count := 0
	var last_board := -1

	func on_play(board: int) -> void:
		count += 1
		last_board = board

	func on_board(_b, _s, _rows) -> void:
		count += 1


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


# A release event, for driving the pads' own input path rather than reaching
# past it into _held_dirs -- the release branch is where the latch bug lived.
func _release_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	return ev


# A real finger. Godot synthesizes a mouse event from each of these when
# `emulate_mouse_from_touch` is on, which is the default -- so a phone sends
# BOTH, and a handler that accepts both fires twice per tap.
func _touch_event(pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = 0
	return ev


# The emulated mouse event that follows a touch, and also a genuine desktop
# click -- the two are indistinguishable to a handler, which is the whole
# reason the touch branch has to claim the tap first.
func _mouse_event(pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	return ev
