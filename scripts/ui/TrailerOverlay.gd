# The trailer's own layer: cut-to-black fades, per-segment captions, skip hint.
#
# Kept separate from HUD deliberately. The HUD is the player's instrument panel
# and its palette is fixed across every maze (CLAUDE.md section 7); the trailer
# needs captions and a full-screen fade, and neither belongs in the thing the
# player reads under pressure.
#
# docs/specs/trailer.md
class_name TrailerOverlay
extends CanvasLayer

const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.55, 0.62, 0.75)

# How long a caption stays at full opacity before fading out.
const CAPTION_HOLD := 3.0
const CAPTION_FADE := 0.6

# A short note (the gate call-out) is briefer than a segment caption.
const NOTE_HOLD := 1.8

var _fade: ColorRect
var _caption: Label
var _maze_label: Label
var _note: Label
var _skip: Label

# 1.0 is fully black. Cuts drive this to 1 and then ease it back to 0.
var _fade_amount := 0.0
var _fade_speed := 0.0
var _caption_time := 0.0
var _note_time := 0.0
var _finishing := false


func _ready() -> void:
	# Above the game's own UI layer, so the fade actually covers the HUD.
	layer = 10

	var root := Control.new()
	root.name = "OverlayRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

	# The caption block sits in the LOWER THIRD, not the centre.
	#
	# Centred, it lands exactly on the corridor vanishing point -- which is where
	# the Path Indicator panels and the Golden Trail both
	# draw. The reel would have been captioning its own subject matter, hiding
	# the upgrades the later segments exist to show. It also sat on top of the
	# HUD's own maze-name message, printing the maze twice.
	_maze_label = _make_label(38, COL_ACCENT, 1.0, -252, -200)
	_maze_label.add_theme_constant_override("outline_size", 8)
	_maze_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	root.add_child(_maze_label)

	_caption = _make_label(22, Color.WHITE, 1.0, -196, -160)
	root.add_child(_caption)

	# The gate call-out sits lower still, clear of the upgrade cards.
	_note = _make_label(24, Color(1.0, 0.85, 0.15), 1.0, -140, -104)
	root.add_child(_note)

	_skip = _make_label(15, COL_DIM, 1.0, -46, -22)
	_skip.text = "press any key to skip"
	root.add_child(_skip)


func _make_label(size: int, colour: Color, anchor_y: float,
		top: float, bottom: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.offset_top = top
	label.offset_bottom = bottom
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# Start a segment: cut to black and come back up with a new caption.
func cut(caption: String, maze_name: String, fade_seconds: float) -> void:
	_caption.text = caption
	_maze_label.text = maze_name
	_caption_time = CAPTION_HOLD + CAPTION_FADE
	_note.text = ""
	_note_time = 0.0
	_fade_amount = 1.0
	_fade_speed = 1.0 / maxf(fade_seconds, 0.01)


# A brief call-out, used for the gate moment.
func note(text: String) -> void:
	_note.text = text
	_note_time = NOTE_HOLD


# Fade to black and stay there.
func outro(fade_seconds: float) -> void:
	_finishing = true
	_caption.text = ""
	_maze_label.text = ""
	_note.text = ""
	_skip.visible = false
	_fade_speed = 1.0 / maxf(fade_seconds, 0.01)


func step(delta: float) -> void:
	if _finishing:
		_fade_amount = minf(1.0, _fade_amount + delta * _fade_speed)
	elif _fade_amount > 0.0:
		_fade_amount = maxf(0.0, _fade_amount - delta * _fade_speed)
	_fade.color = Color(0, 0, 0, _fade_amount)

	if _caption_time > 0.0:
		_caption_time -= delta
		# Hold, then fade the text rather than cutting it -- a caption that
		# vanished on a frame boundary reads as a glitch next to the eased fade.
		var alpha: float = clampf(_caption_time / CAPTION_FADE, 0.0, 1.0)
		_caption.modulate.a = alpha
		_maze_label.modulate.a = alpha

	if _note_time > 0.0:
		_note_time -= delta
		_note.modulate.a = clampf(_note_time / 0.5, 0.0, 1.0)
