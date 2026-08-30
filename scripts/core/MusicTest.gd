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
		var name := String(config.get("music", ""))
		check("maze %d names a track" % (i + 1), name != "",
			String(config["name"]))
		if name != "":
			check("maze %d track '%s' is declared" % [i + 1, name],
				Tuning.TRACKS.has(name))

	check("the menu track is declared",
		Tuning.TRACKS.has(Music.MENU_TRACK), Music.MENU_TRACK)
	check("the trailer track is declared",
		Tuning.TRACKS.has(Music.TRAILER_TRACK), Music.TRAILER_TRACK)


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


func _finish() -> void:
	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)
