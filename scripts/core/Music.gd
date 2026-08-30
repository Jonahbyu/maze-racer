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

var _bus_index := 0
var _duck := 0.0
var _duck_target := 0.0

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

	_bus_index = _ensure_bus()

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


# The track a maze names in its own config, rather than an array indexed by
# maze number -- that goes stale the moment a maze is added, and silently
# (CLAUDE.md section 6, the same rule landmarks follow).
func play_for_maze(index: int) -> void:
	if index < 0 or index >= Tuning.MAZES.size():
		return
	var name := String(Tuning.MAZES[index].get("music", ""))
	if name == "":
		return
	play(name)


func current_track() -> String:
	return _current


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


func is_muted() -> bool:
	return AudioServer.is_bus_mute(_bus_index)


# --- Fade --------------------------------------------------------------------

func _process(delta: float) -> void:
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
