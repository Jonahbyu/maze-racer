# Does the music table hold together, and is it wired to the right places?
#
# The whole point of the design is that adding a track is a table edit
# (docs/specs/music.md), which means a typo in that table is the most likely
# failure by far -- and its symptom in play is silence, which reads as "the
# audio system is broken" rather than "that key is misspelled". These checks
# turn that into a harness failure instead.
#
# Runs headless with no audio driver, which is also the point: nothing here may
# require a rendered frame or a working AudioServer output.
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== MusicTest ===")
	_go.call_deferred()


func check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _go() -> void:
	_check_table()
	_check_assignments()
	_check_autoload()
	_check_transport()
	_check_autoplay_lock()
	_finish()


# --- The table ---------------------------------------------------------------

func _check_table() -> void:
	check("TRACKS is not empty", Tuning.TRACKS.size() > 0)

	for name in Tuning.TRACKS:
		var entry: Dictionary = Tuning.TRACKS[name]

		check("track '%s' declares a path" % name, entry.has("path"))
		if not entry.has("path"):
			continue

		var path := String(entry["path"])

		# The check that actually matters. A path that does not resolve is
		# silence in play and nothing in the log.
		check("track '%s' file exists" % name,
			ResourceLoader.exists(path), path)

		check("track '%s' declares volume_db" % name, entry.has("volume_db"))

		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			check("track '%s' loads as an AudioStream" % name, stream != null, path)


# --- Who plays what ----------------------------------------------------------

func _check_assignments() -> void:
	# Every maze must name a track that exists. This is the failure the
	# per-maze key exists to prevent -- an array indexed by maze number would
	# hand a sixth maze silence with no error at all.
	for i in Tuning.MAZES.size():
		var config: Dictionary = Tuning.MAZES[i]
		var names := _names_of(config.get("music", ""))
		check("maze %d names a track" % (i + 1), names.size() > 0,
			String(config["name"]))
		# Every name in the pool, not just the first -- a typo in a later entry
		# is invisible until the draw happens to land on it.
		for name in names:
			check("maze %d track '%s' is declared" % [i + 1, name],
				Tuning.TRACKS.has(name), String(config["name"]))

	# The sprinkle-anywhere tier. Same rule: a name here that is not in TRACKS
	# fails only on the run that rolls it.
	check("the shared pool is not empty", Tuning.SHARED_TRACKS.size() > 0)
	for name in Tuning.SHARED_TRACKS:
		check("shared track '%s' is declared" % name,
			Tuning.TRACKS.has(String(name)))

	check("the shared-track chance is a probability",
		Tuning.SHARED_TRACK_CHANCE >= 0.0 and Tuning.SHARED_TRACK_CHANCE <= 1.0,
		str(Tuning.SHARED_TRACK_CHANCE))

	check("the menu track is declared",
		Tuning.TRACKS.has(Music.MENU_TRACK), Music.MENU_TRACK)
	check("the trailer track is declared",
		Tuning.TRACKS.has(Music.TRAILER_TRACK), Music.TRAILER_TRACK)

	_check_pool_draw()
	_check_volume()


# The player-facing volume, which had a setter and no caller at all until the
# settings panel existed -- the bus stayed at unity however the preference read.
func _check_volume() -> void:
	var music := root.get_node_or_null("/root/Music")
	var settings := root.get_node_or_null("/root/Settings")
	if music == null or settings == null:
		check("Music and Settings present for the volume check", false)
		return

	var volume_before: float = float(settings.music_volume)
	var muted_before: bool = bool(settings.music_muted)

	var bus := AudioServer.get_bus_index("music")
	check("the music bus exists", bus >= 0)
	if bus < 0:
		return

	# Music follows Settings, not the other way round: the preference is what
	# the player asked for and the autoload is the thing that obeys it.
	settings.set_music_muted(false)
	settings.set_music_volume(0.5)
	check("a volume change reaches the bus",
		is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5)),
		"%.2f dB" % AudioServer.get_bus_volume_db(bus))

	settings.set_music_volume(1.0)
	check("full volume is 0 dB",
		is_equal_approx(AudioServer.get_bus_volume_db(bus), 0.0),
		"%.2f dB" % AudioServer.get_bus_volume_db(bus))

	# Zero is silence, not linear_to_db(0) -- which is -inf and poisons the bus.
	settings.set_music_volume(0.0)
	check("zero volume is finite silence",
		AudioServer.get_bus_volume_db(bus) <= -80.0
			and not is_inf(AudioServer.get_bus_volume_db(bus)),
		"%.2f dB" % AudioServer.get_bus_volume_db(bus))

	settings.set_music_muted(true)
	check("mute reaches the bus", AudioServer.is_bus_mute(bus))
	settings.set_music_muted(false)
	check("unmute reaches the bus", not AudioServer.is_bus_mute(bus))

	# The default is deliberately quiet, with headroom to turn up.
	check("the default volume leaves headroom",
		Settings.MUSIC_VOLUME_DEFAULT > 0.0
			and Settings.MUSIC_VOLUME_DEFAULT < 1.0,
		str(Settings.MUSIC_VOLUME_DEFAULT))

	# Leave the player's own preference exactly as it was found. A harness that
	# writes the state it inspects is the TouchShot trap (CLAUDE.md section 9d).
	settings.set_music_volume(volume_before)
	settings.set_music_muted(muted_before)


# A maze must only ever play a track from its own pool or the shared one, and
# must never fall silent. Drawn many times because the choice is random: a
# single draw would pass on a pool whose second entry is broken.
func _check_pool_draw() -> void:
	var music := root.get_node_or_null("/root/Music")
	if music == null:
		check("Music autoload present for pool draws", false)
		return

	for i in Tuning.MAZES.size():
		var config: Dictionary = Tuning.MAZES[i]
		var legal := _names_of(config.get("music", ""))
		for name in Tuning.SHARED_TRACKS:
			legal.append(String(name))

		var seen := {}
		var bad := ""
		for _n in 200:
			var got := String(music.pick_for_maze(i))
			seen[got] = true
			if not legal.has(got):
				bad = got
		check("maze %d only draws from its pools" % (i + 1), bad == "", bad)
		check("maze %d never draws silence" % (i + 1), not seen.has(""))
		# The pools together hold more than one track for every maze, so a
		# selector stuck on one name is a real failure rather than luck.
		check("maze %d draws more than one track" % (i + 1), seen.size() > 1,
			"drew %d distinct" % seen.size())

	# Out-of-range indices must be inert, not crash or return a track.
	check("an out-of-range maze draws nothing",
		String(music.pick_for_maze(-1)) == ""
			and String(music.pick_for_maze(Tuning.MAZES.size())) == "")


# Accepts a bare name or a list, mirroring what Music._track_list accepts.
func _names_of(value: Variant) -> Array:
	var out: Array = []
	if value is String:
		if String(value) != "":
			out.append(String(value))
	elif value is Array:
		for v in value:
			out.append(String(v))
	return out


# --- The autoload ------------------------------------------------------------

func _check_autoload() -> void:
	var music := root.get_node_or_null("/root/Music")
	check("Music is registered as an autoload", music != null)
	if music == null:
		return

	# It must outlive scene swaps, which means it must not be under the shell.
	check("Music sits directly under root",
		music.get_parent() == root)

	# A crossfade interrupted by a real tree pause must not stall half-way and
	# leave the mix stuck between two tracks.
	check("Music processes while paused",
		music.process_mode == Node.PROCESS_MODE_ALWAYS)

	check("Music built its bus",
		AudioServer.get_bus_index(Music.BUS_NAME) != -1)

	check("Music built two players", music._players.size() == 2)

	# process_mode says WHEN a node may process, not that it should. Without
	# set_process the fade never ticks and every player stays at the -80dB it
	# starts at -- playing, and completely inaudible. Headless cannot hear that,
	# so it is asserted here instead.
	check("Music is actually processing", music.is_processing())


# --- Transport ---------------------------------------------------------------

func _check_transport() -> void:
	var music := root.get_node_or_null("/root/Music")
	if music == null:
		return

	music.play(Music.MENU_TRACK)
	check("play() sets the current track",
		music.current_track() == Music.MENU_TRACK, music.current_track())

	# The rule that makes menu -> game seamless on a shared track. Re-requesting
	# what is already playing must not restart it, so the active player must not
	# change.
	var active_before: int = music._active
	music.play(Music.MENU_TRACK)
	check("replaying the same track does not restart it",
		music._active == active_before,
		"active %d -> %d" % [active_before, music._active])

	# A different track swaps players, which is what crossfades.
	var other := ""
	for name in Tuning.TRACKS:
		if String(name) != Music.MENU_TRACK:
			other = String(name)
			break
	if other != "":
		music.play(other)
		check("a different track crossfades to the other player",
			music._active != active_before)
		check("current track follows", music.current_track() == other)

	# A bad name must be survivable, and must not change what is playing.
	var before: String = music.current_track()
	music.play("no_such_track_at_all")
	check("an unknown track is ignored, not fatal",
		music.current_track() == before, music.current_track())

	# Ducking is a volume change, never a transport one -- the track keeps
	# playing and keeps its position.
	var playing_before: String = music.current_track()
	music.set_ducked(true)
	check("ducking does not stop the track",
		music.current_track() == playing_before)
	check("ducking moves the target", music._duck_target < 0.0)
	music.set_ducked(false)
	check("unducking restores the target", music._duck_target == 0.0)

	# Looping is set in code, because the mp3 importer defaults it to false and
	# a track that does not loop just stops a minute in with no error anywhere.
	music.play(Music.MENU_TRACK)
	var player: AudioStreamPlayer = music._players[music._active]
	check("the playing stream exists", player.stream != null)
	if player.stream != null:
		check("the playing stream loops", bool(player.stream.get("loop")))

		# Mutating the loop flag must not reach through to the shared cache --
		# both players can hold the same file mid-crossfade.
		var cached := load(String(Tuning.TRACKS[Music.MENU_TRACK]["path"]))
		check("the cached resource was not mutated",
			cached != null and bool(cached.get("loop")) == false)

	music.stop()
	check("stop() clears the current track", music.current_track() == "")


# --- The browser autoplay lock -----------------------------------------------
#
# This is the bug that shipped: on the web the AudioContext starts suspended,
# so the menu track -- requested during boot, before any click -- played
# against a dead context and the game was silent in production while every
# desktop check passed. The lock cannot be reproduced headlessly, so what is
# asserted is the STATE MACHINE that handles it, driven by hand.
func _check_autoplay_lock() -> void:
	var music := root.get_node_or_null("/root/Music")
	if music == null:
		return

	music.stop()

	# Force the locked state the web starts in.
	music._unlocked = false
	music._pending = ""
	music._current = ""

	# Which player is live, and what it holds, before the locked request. stop()
	# only FADES the previous player out, so it stays `playing` until the fade
	# reaches -80dB -- asserting on `playing` alone would read that leftover as
	# a new start.
	var active_before: int = music._active

	music.play(Music.MENU_TRACK)

	# Held, not started. Starting it would burn the track against a suspended
	# context: it advances, fades in, is never heard, and the first thing the
	# player actually hears is whatever plays second.
	check("a track requested while locked is held",
		String(music._pending) == Music.MENU_TRACK, String(music._pending))
	check("no player is switched to while locked",
		music._active == active_before,
		"active %d -> %d" % [active_before, music._active])
	# Note this deliberately does NOT assert "no player is playing": stop()
	# leaves the previous player fading, so it is still playing here and that
	# is correct. What must not happen is a NEW start, which is what the
	# _active check above catches.

	# A key press is a real gesture and must release it.
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	music._input(key)

	check("input unlocks audio", bool(music._unlocked))
	check("the held track is started on unlock",
		music.current_track() == Music.MENU_TRACK, music.current_track())
	var player: AudioStreamPlayer = music._players[music._active]
	check("the stream is actually playing after unlock", player.playing)
	check("unlock switched to the other player",
		music._active != active_before)
	check("nothing is left pending", String(music._pending) == "")

	music.stop()


func _finish() -> void:
	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)
