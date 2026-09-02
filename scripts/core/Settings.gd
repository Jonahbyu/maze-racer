# Player preferences that outlive a scene swap and a restart.
#
# An autoload for the same reason Music is one (docs/specs/music.md): Shell
# frees its entire live child on every mode change, so a preference parented
# under the menu would die the moment the player pressed PLAY -- which is the
# one transition where "did they turn mobile controls on?" actually has to be
# remembered. This node sits above the shell and is never freed.
#
# Nothing in the simulation may read this. Movement, turn resolution, the
# buffer, the barrier and the penalties behave identically whether touch
# controls are on or off -- the touch overlay synthesises the SAME
# request_turn/request_reverse calls the keyboard makes, and adds no rules.
# Same separation landmarks and music have (CLAUDE.md sections 6 and 9c).
extends Node

signal touch_controls_changed(enabled: bool)
signal music_changed(volume: float, muted: bool)

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "controls"
const SECTION_AUDIO := "audio"

# Where the music sits on a fresh install. Deliberately low: the tracks are
# already trimmed per-entry in Tuning.TRACKS, and a first launch at full bus
# gain lands louder than anything else the player has open. This leaves a lot of
# headroom to turn UP, which a default near 1.0 does not.
#
# 0.25 linear is about -12dB. Loudness is not linear in amplitude, so this is a
# deeper cut than the number suggests -- which is the intent: quiet by default,
# with the slider right there for anyone who wants more.
const MUSIC_VOLUME_DEFAULT := 0.25

# Whether the on-screen driving pads are drawn.
#
# Read directly; written through set_touch_controls() so that persisting and
# announcing a change cannot be forgotten at a call site. A bare property setter
# was tried and is wrong here: loading from disk assigns this field too, and a
# setter cannot tell a restore from a choice -- it re-saved the file it had just
# read and fired the signal before the menu existed to hear it.
var touch_controls := false

# Music bus level, 0..1 linear. Read directly, written through set_music_volume().
var music_volume := MUSIC_VOLUME_DEFAULT

# Kept separate from a zero volume rather than folded into it, so unmuting
# restores the level the player chose instead of dumping them at silence and
# making them find it again.
var music_muted := false


func _ready() -> void:
	_load()


# True when the running device actually has a touchscreen.
#
# Checked as the DEFAULT rather than as the switch. Godot reports a touchscreen
# on desktop only when emulation is on, and the web export runs on both -- so a
# purely automatic decision would leave a phone player with no way to recover if
# the probe read wrong, and would give a desktop tester no way to see the pads
# at all. The menu toggle is the override; this is only what it starts at.
static func device_has_touch() -> bool:
	return DisplayServer.is_touchscreen_available()


# The only way the preference should ever change at runtime.
func set_touch_controls(value: bool) -> void:
	if value == touch_controls:
		return
	touch_controls = value
	_save()
	emit_signal("touch_controls_changed", value)


# The only way the music preference should ever change at runtime, for the same
# reason set_touch_controls exists: persisting and announcing a change must not
# be forgettable at a call site.
func set_music_volume(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	if is_equal_approx(v, music_volume):
		return
	music_volume = v
	_save()
	emit_signal("music_changed", music_volume, music_muted)


func set_music_muted(value: bool) -> void:
	if value == music_muted:
		return
	music_muted = value
	_save()
	emit_signal("music_changed", music_volume, music_muted)


func _load() -> void:
	var config := ConfigFile.new()
	# No file on first run is the normal case, not an error -- fall through to
	# the platform default rather than reporting anything.
	if config.load(CONFIG_PATH) != OK:
		touch_controls = device_has_touch()
		return
	touch_controls = bool(
		config.get_value(SECTION, "touch_controls", device_has_touch()))
	music_volume = clampf(float(config.get_value(
		SECTION_AUDIO, "music_volume", MUSIC_VOLUME_DEFAULT)), 0.0, 1.0)
	music_muted = bool(config.get_value(SECTION_AUDIO, "music_muted", false))


func _save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # keep any keys this build does not know about
	config.set_value(SECTION, "touch_controls", touch_controls)
	config.set_value(SECTION_AUDIO, "music_volume", music_volume)
	config.set_value(SECTION_AUDIO, "music_muted", music_muted)
	config.save(CONFIG_PATH)
