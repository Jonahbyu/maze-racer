# The music system: one autoload, two crossfading players, a table of tracks.
#
# Registered as an autoload in project.godot, which is the whole point. Shell
# frees its entire live child on every mode change (menu -> game -> trailer), so
# a player parented under any of those dies with it and restarts the track from
# zero on every button press. This node sits above the shell and is never freed.
#
# Nothing in the simulation may read this. The rules layer can reach it and must
# never use it -- every harness runs --headless with no audio driver.
#
# docs/specs/music.md
extends Node

# Crossfade length on a track change. Long enough not to read as a cut, short
# enough that pressing PLAY does not sit under two tracks at once.
const FADE_SECONDS := 0.9

# Where the mix sits while the game is paused. Ducked, not stopped: music
# continuing quietly is what says the game is held rather than gone, and a
# volume change keeps the track's position where a stop would lose it.
const DUCK_DB := -14.0

# How fast the duck moves, in dB per second. Faster than the crossfade -- a
# pause should feel immediate.
const DUCK_PER_SEC := 60.0

const BUS_NAME := "music"

# Neither of these is a maze, so they cannot live in Tuning.MAZES.
const MENU_TRACK := "find_the_way"
const TRAILER_TRACK := "find_the_way"

var _players: Array[AudioStreamPlayer] = []
# Index into _players of the one that should be audible.
var _active := 0

# The track name currently playing, or "" for silence. Compared against on
# play() so a shared track across a transition is not restarted.
var _current := ""

# The stream track selection draws on. Its own generator, never the maze's --
# see pick_for_maze. Randomized rather than seeded: two runs of the same maze
# should not open on the same track, which is the whole point of a pool.
var _rng := RandomNumberGenerator.new()

var _bus_index := 0
var _duck := 0.0
var _duck_target := 0.0

# Browsers refuse to start audio until the user has interacted with the page,
# so a track requested during boot -- which the menu's is -- starts against a
# suspended AudioContext and is silently discarded. Nothing errors, the player
# reports playing == true, and the game is mute until a reload.
#
# Desktop has no such policy, which is why every local check passed and only
# production was silent. `_unlocked` stays true off the web, so this whole path
# costs nothing there.
var _unlocked := true
var _pending := ""

# Track names already reported as broken. Warn once per name, not once per
# call -- a bad per-maze key would otherwise print every frame of a fade.
var _warned := {}


func _ready() -> void:
	# The fade has to keep running even if the tree is paused, or a crossfade
	# interrupted by a pause leaves the mix stuck between two tracks.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# process_mode says WHEN this node may process; it does not say that it
	# should. Without this the fade never ticks, so every player sits at the
	# -80dB it starts at and the music is inaudible while reporting playing=true
	# -- which is exactly what a headless harness cannot see.
	set_process(true)

	# RandomNumberGenerator is NOT random until seeded -- an unseeded one gives
	# the same sequence every launch, so every run would open on the same track.
	_rng.randomize()

	_bus_index = _ensure_bus()

	# Only the web has an autoplay policy to satisfy, so only the web starts
	# locked. The platform check picks WHETHER to wait; _poll_unlock decides
	# when the wait is over by reading the AudioContext itself.
	if OS.has_feature("web"):
		_unlocked = false

	_follow_settings()

	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % i
		player.bus = BUS_NAME
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


# A dedicated bus, so the master stays free for future SFX. Created at runtime
# rather than shipped as a .tres, because a bus layout resource is one more
# binary file to keep in sync with a name that only appears here.
func _ensure_bus() -> int:
	var existing := AudioServer.get_bus_index(BUS_NAME)
	if existing != -1:
		return existing
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, "Master")
	return index


# --- Transport ---------------------------------------------------------------

# Start `track`, crossfading from whatever is playing.
#
# Returns early if `track` is already playing, which is what makes menu -> game
# on a shared track seamless. Passing "" fades to silence.
func play(track: String) -> void:
	if track == _current:
		return
	if track != "" and not _resolve(track):
		return

	# Before the browser has unlocked audio, starting the stream would burn the
	# track against a suspended context: it advances, finishes its fade, and is
	# never heard, so the first thing the player hears is whatever plays SECOND.
	# Hold the request instead and start it for real on the first input.
	if not _unlocked:
		_pending = track
		_current = track
		return

	_current = track

	var incoming := 1 - _active
	var player := _players[incoming]

	if track == "":
		# Fade the outgoing player down and leave both idle.
		_active = incoming
		return

	var entry: Dictionary = Tuning.TRACKS[track]
	var stream := _load_stream(String(entry["path"]))
	if stream == null:
		_warn(track, "could not load %s" % entry["path"])
		_current = ""
		return

	player.stream = stream
	player.volume_db = -80.0
	player.play()
	_active = incoming


func stop() -> void:
	play("")


# The tracks a maze names in its own config, rather than an array indexed by
# maze number -- that goes stale the moment a maze is added, and silently
# (CLAUDE.md section 6, the same rule landmarks follow).
#
# One is drawn per visit, so a maze is not note-for-note the same on a replay,
# and a maze may instead draw from Tuning.SHARED_TRACKS -- the tracks that
# belong to the game rather than to one palette.
func play_for_maze(index: int) -> void:
	if index < 0 or index >= Tuning.MAZES.size():
		return
	var track := pick_for_maze(index)
	if track == "":
		return
	play(track)


# Chosen separately from play() so a test can ask what a maze WOULD play
# without an audio device deciding the answer.
#
# Runs on its own RNG, for the reason landmark placement does (CLAUDE.md
# section 6): sharing the maze generator would mean adding a track silently
# redrew every maze, since each extra draw shifts the whole downstream
# sequence. Nothing in the simulation may read this either way.
func pick_for_maze(index: int) -> String:
	if index < 0 or index >= Tuning.MAZES.size():
		return ""

	var own := _track_list(Tuning.MAZES[index].get("music", ""))
	var shared := _track_list(Tuning.SHARED_TRACKS)

	# The roll only stands if the pool it chose has anything in it -- a maze
	# with no tracks of its own should still play a shared one rather than
	# falling silent, and vice versa.
	var pool := own
	if shared.size() > 0 and (own.size() == 0
			or _rng.randf() < Tuning.SHARED_TRACK_CHANCE):
		pool = shared
	if pool.size() == 0:
		return ""

	# Prefer not to redraw what is already playing: play() returns early on a
	# repeat, so arriving in a new maze on the same track would give no audible
	# transition at all. Only when there is something else to pick.
	var choice := String(pool[_rng.randi() % pool.size()])
	if choice == _current and pool.size() > 1:
		var others: Array = []
		for t in pool:
			if String(t) != _current:
				others.append(t)
		choice = String(others[_rng.randi() % others.size()])
	return choice


# Accepts either a bare name or a list of them, so a maze wanting exactly one
# track is not forced into list syntax. Unknown names are dropped here rather
# than at play() time, so a typo in a pool cannot make a maze silent -- it just
# stops being drawn, and MusicTest asserts the names resolve.
func _track_list(value: Variant) -> Array:
	var names: Array = []
	if value is String:
		if String(value) != "":
			names.append(String(value))
	elif value is Array:
		for v in value:
			names.append(String(v))
	var out: Array = []
	for n in names:
		if Tuning.TRACKS.has(n):
			out.append(n)
		else:
			_warn(String(n), "named in a pool but not in Tuning.TRACKS")
	return out


func current_track() -> String:
	return _current


# --- Browser autoplay unlock -------------------------------------------------

# The unlock has to watch the AudioContext, NOT Godot's input.
#
# It was an `_input` handler, and that misses the one gesture that matters. The
# player's first interaction is the shell's PLAY button -- an HTML element
# OUTSIDE the canvas -- so Godot never sees it, `_unlocked` stayed false, and
# the menu's track sat in `_pending` forever. Measured over CDP against the live
# site: the context was `running` with its clock advancing in real time while
# the game was still holding the track unplayed. The browser half was working;
# this half never fired.
#
# Reaching a canvas click is not enough either. The menu is fully playable with
# the keyboard, and a keypress on the canvas is only seen once the canvas has
# focus -- which it acquires from that same out-of-canvas PLAY click.
#
# So ask the context directly. `shell.html` already collects every context the
# engine creates, for its own resume() call, and its state is the exact fact
# this needs: `running` means the browser has accepted a gesture and audio will
# be heard. Polled in _process rather than pushed from JS, so nothing depends on
# the shell calling into GDScript -- a custom shell that someone later replaces
# takes the audio with it, silently, and that is how this broke the first time.
func _poll_unlock() -> void:
	if _unlocked:
		return

	var state := ""
	if OS.has_feature("web"):
		# Falls back to the engine's own context if the shell hook is absent,
		# so a default shell still unlocks.
		var v = JavaScriptBridge.eval("""
			(function () {
				var l = window.__godotAudioContexts || [];
				if (l.length && l[0]) { return l[0].state; }
				return (window.GodotAudio && window.GodotAudio.ctx)
					? window.GodotAudio.ctx.state : "";
			})();
		""", true)
		if typeof(v) == TYPE_STRING:
			state = v

	if state != "running":
		return

	_unlock()


# Split from the poll so a test can drive it without a browser.
func _unlock() -> void:
	if _unlocked:
		return
	_unlocked = true

	# Restart what was asked for while locked, from the top. _current is already
	# set to it, so clear that first or play() returns early as a no-op.
	var track := _pending
	_pending = ""
	if track != "":
		_current = ""
		play(track)


# --- Ducking -----------------------------------------------------------------

# Drop the mix while paused, restore it on resume. Not a transport call: the
# track keeps playing and keeps its position.
func set_ducked(on: bool) -> void:
	_duck_target = DUCK_DB if on else 0.0


# --- Volume ------------------------------------------------------------------

# Player-facing volume, 0..1 linear, on the music bus. Per-track trim is applied
# to the players instead, so evening out two masters does not move this.
func set_volume(linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(_bus_index,
		-80.0 if v <= 0.0 else linear_to_db(v))


func set_muted(on: bool) -> void:
	AudioServer.set_bus_mute(_bus_index, on)


# Apply the stored preference, and keep applying it as the player changes it.
#
# Music reads Settings and never the other way round: the preference is what the
# player asked for, this is the thing that obeys it. Guarded rather than assumed,
# for the reason MainMenu guards the same lookup -- a harness that instantiates
# Music bare has no autoloads, and a missing preference must never be what stops
# the audio starting.
func _follow_settings() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	_apply_settings(float(settings.music_volume), bool(settings.music_muted))
	if settings.has_signal("music_changed"):
		settings.music_changed.connect(_apply_settings)


func _apply_settings(volume: float, muted: bool) -> void:
	set_volume(volume)
	set_muted(muted)


func is_muted() -> bool:
	return AudioServer.is_bus_mute(_bus_index)


# --- Fade --------------------------------------------------------------------

func _process(delta: float) -> void:
	# Cheap once unlocked -- it returns on the first line -- and off the web
	# `_unlocked` starts true, so this never evaluates anything at all.
	_poll_unlock()

	if _players.is_empty():
		return

	_duck = move_toward(_duck, _duck_target, DUCK_PER_SEC * delta)

	var step := (80.0 / FADE_SECONDS) * delta

	for i in _players.size():
		var player := _players[i]
		var wants_sound := (i == _active and _current != "")
		var target := (_track_db(_current) + _duck) if wants_sound else -80.0
		player.volume_db = move_toward(player.volume_db, target, step)

		# Only stop once it is genuinely inaudible, or the fade-out is a cut.
		if not wants_sound and player.playing and player.volume_db <= -79.9:
			player.stop()


func _track_db(track: String) -> float:
	if track == "" or not Tuning.TRACKS.has(track):
		return 0.0
	return float(Tuning.TRACKS[track].get("volume_db", 0.0))


# --- Loading -----------------------------------------------------------------

func _resolve(track: String) -> bool:
	if not Tuning.TRACKS.has(track):
		_warn(track, "no such track in Tuning.TRACKS")
		return false
	return true


# Load a stream and force it to loop.
#
# Godot's mp3/ogg importers default loop=false, so a track added without editing
# its .import file by hand just stops a minute in, with no error. Setting it
# here means anything dropped into the table loops because it is music.
func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	# Duplicated before mutating: load() returns a cached, shared resource, so
	# setting loop on it would reach through to every other user of the same
	# file -- and both players can hold the same stream mid-crossfade.
	stream = stream.duplicate() as AudioStream
	if "loop" in stream:
		stream.set("loop", true)
	return stream


func _warn(track: String, detail: String) -> void:
	if _warned.has(track):
		return
	_warned[track] = true
	push_warning("Music: track '%s' -- %s" % [track, detail])
