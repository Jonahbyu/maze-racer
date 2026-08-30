# Does the music actually reach a real audio device?
#
# Not a test. MusicTest covers the table and the wiring, but it runs headless
# with no audio driver, so it can only prove nothing crashes -- a file that
# fails to decode, or an import that produced a zero-length stream, passes it
# and is silent in play. This runs WITH sound and reports whether the playback
# head is genuinely advancing.
#
# Builds the shell the way the project boots it, plus the Music autoload by
# hand, because --script replaces the main scene and so skips both.
#
# Usage:
#   launch.ps1 -Script res://scripts/core/MusicProbe.gd -Quit 25
extends SceneTree

var _music: Node
var _shell: Node
var _t := 0.0
var _step := 0

# Each entry: seconds to wait, a label, and what to do on arrival.
const SCRIPT := [
	[1.5, "menu", "none"],
	[3.0, "menu, still playing", "play"],
	[4.5, "after PLAY (maze track)", "none"],
	[6.5, "in game", "pause"],
	[7.5, "paused -- should be ducked", "unpause"],
	[9.0, "resumed", "none"],
]


func _init() -> void:
	print("=== MusicProbe ===")
	_setup.call_deferred()


func _setup() -> void:
	# The REAL autoload, not a second copy. --script replaces the main scene but
	# autoloads still load, so /root/Music already exists here -- and adding
	# another one is invisible, because a name set before add_child does not
	# stick: the node lands at /root/@Node@N and every lookup of /root/Music
	# quietly finds the autoload instead. That is what made this probe report
	# silence while the game was working.
	_music = root.get_node_or_null("/root/Music")
	if _music == null:
		printerr("no /root/Music autoload -- is it registered in project.godot?")
		quit(1)
		return

	_shell = load("res://scenes/Main.tscn").instantiate()
	_shell.name = "Main"
	root.add_child(_shell)


func _process(delta: float) -> bool:
	if _music == null or _step >= SCRIPT.size():
		return false

	_t += delta
	var entry: Array = SCRIPT[_step]
	if _t < float(entry[0]):
		return false

	_report(String(entry[1]))

	match String(entry[2]):
		"play":
			_shell.start_game()
		"pause":
			var game = _shell._current
			if game != null and game.has_method("_set_paused"):
				game._set_paused(true)
		"unpause":
			var game = _shell._current
			if game != null and game.has_method("_set_paused"):
				game._set_paused(false)

	_step += 1
	if _step >= SCRIPT.size():
		print("")
		print("driver: %s   latency: %.1f ms" % [
			AudioServer.get_driver_name(),
			AudioServer.get_output_latency() * 1000.0,
		])
		print("=== done ===")
		quit(0)
	return false


func _report(label: String) -> void:
	var parts := []
	for i in _music._players.size():
		var p: AudioStreamPlayer = _music._players[i]
		parts.append("p%d[%s %.1fdB %.2fs]" % [
			i,
			"ON " if p.playing else "off",
			p.volume_db,
			p.get_playback_position() if p.playing else 0.0,
		])
	print("%-28s track='%s'  %s" % [
		label, _music.current_track(), " ".join(parts)])
