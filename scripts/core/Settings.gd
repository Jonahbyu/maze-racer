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

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "controls"

# Whether the on-screen driving pads are drawn.
#
# Read directly; written through set_touch_controls() so that persisting and
# announcing a change cannot be forgotten at a call site. A bare property setter
# was tried and is wrong here: loading from disk assigns this field too, and a
# setter cannot tell a restore from a choice -- it re-saved the file it had just
# read and fired the signal before the menu existed to hear it.
var touch_controls := false


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


func _load() -> void:
	var config := ConfigFile.new()
	# No file on first run is the normal case, not an error -- fall through to
	# the platform default rather than reporting anything.
	if config.load(CONFIG_PATH) != OK:
		touch_controls = device_has_touch()
		return
	touch_controls = bool(
		config.get_value(SECTION, "touch_controls", device_has_touch()))


func _save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # keep any keys this build does not know about
	config.set_value(SECTION, "touch_controls", touch_controls)
	config.save(CONFIG_PATH)
