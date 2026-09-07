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
signal marker_shape_changed(id: String)
signal marker_decal_changed(id: String)
signal marker_colour_changed(colour: Color)
signal marker_colour_2_changed(colour: Color)
signal maze_palettes_changed()

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "controls"
const SECTION_AUDIO := "audio"
const SECTION_LOOK := "look"

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

# Which inner mark the player marker draws, by Tuning.MARKER_SHAPES id.
#
# Stored by NAME, never by index. An index would silently re-point every
# existing player's choice at a different shape the moment that table is
# reordered -- and reordering a cosmetic table is exactly the sort of change
# nobody expects to alter anyone's settings. An id that no longer exists falls
# back to the arrow (Tuning.marker_shape), rather than failing.
var marker_shape := Tuning.MARKER_SHAPE_DEFAULT

# Which decal patterns the inner mark, by Tuning.MARKER_DECALS id. Stored by
# NAME for the same reason the shape is, and normalised through Tuning on the
# way in and out.
var marker_decal := Tuning.MARKER_DECAL_DEFAULT

# The marker's colour.
#
# FREE, deliberately, and this reverses a rule CLAUDE.md section 12 stated as
# hard: near-white was mandatory because maze 3 turned the walls green and the
# thing the player steers with matched the scenery. Jonah asked for the picker
# after that objection was put, so it is a decision rather than an oversight,
# and the cost is real -- a colour close to a maze's neon is harder to see in
# that maze.
#
# What is NOT given away is the state read. PlayerMarker applies this to the
# inner mark only and lets scrape-amber and crash-red override both surfaces,
# so the read is a TRANSITION rather than a hue (see PlayerMarker.player_colour).
#
# Near-white by default: a player who never opens the picker gets exactly the
# marker the game had before it existed.
var marker_colour := PlayerMarker.COL_ARROW

# The second marker colour: what fills the decal's cuts. Only visible when a
# decal other than PLAIN is chosen, since a plain mark has nothing to fill.
var marker_colour_2: Color = Tuning.marker_colour(
	Tuning.MARKER_COLOUR_2_DEFAULT)["colour"]

# Which palette each maze slot draws in, by palette id.
#
# WHOLE PALETTES, never a single hue. A palette is six interlocking colours --
# wall, grid, floor, ambient, fog, emission -- and section 8 records two separate
# bugs from getting that mix wrong: maze 3's green ambient lighting every wall
# face in its own neon, and ember's yellow grid driving ambient warm until every
# wall turned milky brown. Both came from DERIVING the rest from one colour,
# which is exactly what a per-hue picker would have to do. Each entry here is a
# palette authored and tuned as a set, so no assignment a player can make
# reproduces either failure.
#
# Empty means "this slot uses its own default", which is what keeps a fresh
# profile identical to the game as authored.
var maze_palettes: Array[String] = []


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


# The only way the marker preference should ever change at runtime, for the
# reason set_touch_controls exists: persisting and announcing a change must not
# be forgettable at a call site.
func set_marker_shape(id: String) -> void:
	# Normalised through Tuning rather than stored raw, so an unknown id can
	# never be written to the file and come back to haunt a later build.
	var resolved: String = String(Tuning.marker_shape(id)["id"])
	if resolved == marker_shape:
		return
	marker_shape = resolved
	_save()
	emit_signal("marker_shape_changed", marker_shape)


# Same shape as set_marker_shape, and separate rather than one combined setter:
# the two are chosen independently and a combined one would force a caller to
# restate the value it is not changing.
func set_marker_decal(id: String) -> void:
	var resolved: String = String(Tuning.marker_decal(id)["id"])
	if resolved == marker_decal:
		return
	marker_decal = resolved
	# Taking a decal while both colours still match separates them, ONCE.
	#
	# Colour 2 defaults to the same white as the mark so a fresh profile has a
	# single colour unlocked. That is safe only while PLAIN is worn, because a
	# plain mark has no cuts to fill -- the moment a real decal goes on, an
	# untouched profile would show white on white.
	#
	# And that genuinely does not read. Measured against a cobalt control in a
	# rendered frame: cobalt draws two unmistakable bands, white draws a plain
	# grey arrow with no pattern visible at all. CLAUDE.md's claim that the seam
	# "guarantees the read AT ANY PAIR" is wrong, and is corrected there -- the
	# seam separates two colours, it does not manufacture a second one.
	#
	# Separating here rather than at the picker's swatch row means every route
	# to a decal is covered, including a future one. It fires only while the two
	# are equal, so a player who has deliberately chosen matching colours after
	# this point keeps them.
	if marker_decal != Tuning.MARKER_DECAL_DEFAULT 			and marker_colour_2.is_equal_approx(marker_colour):
		marker_colour_2 = marker_colour.darkened(
			Tuning.MARKER_COLOUR_2_DARKEN)
		emit_signal("marker_colour_2_changed", marker_colour_2)
	_save()
	emit_signal("marker_decal_changed", marker_decal)


# Assign a palette to one maze slot. An empty id restores that slot's default.
func set_maze_palette(slot: int, id: String) -> void:
	if slot < 0 or slot >= Tuning.MAZES.size():
		return
	while maze_palettes.size() < Tuning.MAZES.size():
		maze_palettes.append("")
	var resolved := ""
	if id != "":
		resolved = String(Tuning.palette_by_id(id).get("id", ""))
	if maze_palettes[slot] == resolved:
		return
	maze_palettes[slot] = resolved
	_save()
	emit_signal("maze_palettes_changed")


# The palette id a maze slot should draw in: the player's assignment, or the
# maze's own default.
func palette_for_maze(slot: int) -> String:
	if slot >= 0 and slot < maze_palettes.size() and maze_palettes[slot] != "":
		return maze_palettes[slot]
	return Tuning.default_palette_id(slot)


func set_marker_colour_2(colour: Color) -> void:
	var opaque2 := Color(colour.r, colour.g, colour.b, 1.0)
	if opaque2.is_equal_approx(marker_colour_2):
		return
	marker_colour_2 = opaque2
	_save()
	emit_signal("marker_colour_2_changed", marker_colour_2)


func set_marker_colour(colour: Color) -> void:
	# Alpha is not offered: a translucent marker is a marker that is harder to
	# see, which is the one thing this file must never let a player choose.
	var opaque := Color(colour.r, colour.g, colour.b, 1.0)
	if opaque.is_equal_approx(marker_colour):
		return
	marker_colour = opaque
	_save()
	emit_signal("marker_colour_changed", marker_colour)


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
	# Through Tuning, so a shape dropped or renamed since this file was written
	# lands the player on the arrow instead of on nothing.
	marker_shape = String(Tuning.marker_shape(String(config.get_value(
		SECTION_LOOK, "marker_shape", Tuning.MARKER_SHAPE_DEFAULT)))["id"])
	marker_decal = String(Tuning.marker_decal(String(config.get_value(
		SECTION_LOOK, "marker_decal", Tuning.MARKER_DECAL_DEFAULT)))["id"])
	# Stored as a hex string rather than four floats, so the config file stays
	# readable and a hand-edited value is obvious. An unparseable one falls back
	# rather than leaving the player with an invisible marker.
	var hex := String(config.get_value(SECTION_LOOK, "marker_colour",
		PlayerMarker.COL_ARROW.to_html(false)))
	marker_colour = Color.from_string(hex, PlayerMarker.COL_ARROW)
	marker_colour.a = 1.0
	var fallback2: Color = Tuning.marker_colour(
		Tuning.MARKER_COLOUR_2_DEFAULT)["colour"]
	marker_colour_2 = Color.from_string(String(config.get_value(
		SECTION_LOOK, "marker_colour_2", fallback2.to_html(false))), fallback2)
	marker_colour_2.a = 1.0
	maze_palettes.clear()
	for i in Tuning.MAZES.size():
		maze_palettes.append(String(config.get_value(
			SECTION_LOOK, "maze_palette_%d" % i, "")))


func _save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # keep any keys this build does not know about
	config.set_value(SECTION, "touch_controls", touch_controls)
	config.set_value(SECTION_AUDIO, "music_volume", music_volume)
	config.set_value(SECTION_AUDIO, "music_muted", music_muted)
	config.set_value(SECTION_LOOK, "marker_shape", marker_shape)
	config.set_value(SECTION_LOOK, "marker_decal", marker_decal)
	config.set_value(SECTION_LOOK, "marker_colour", marker_colour.to_html(false))
	config.set_value(SECTION_LOOK, "marker_colour_2",
		marker_colour_2.to_html(false))
	for i in maze_palettes.size():
		config.set_value(SECTION_LOOK, "maze_palette_%d" % i,
			maze_palettes[i])
	config.save(CONFIG_PATH)
