# The on-screen driving pads: LEFT, RIGHT, REVERSE, and a pause corner.
#
# This is a VIEW, not a rule. Each pad emits the same signal the keyboard path
# in Game._unhandled_input already raises, so the racer cannot tell a tap from a
# key press and no harness has to know this file exists. If a pad ever needed to
# consult the maze, the buffer or the barrier to decide what to send, the rule
# would be in the wrong place (CLAUDE.md section 12).
#
# It mirrors the three-key contract in section 2 exactly -- left, right, 180 --
# and nothing else. There is no accelerator and no brake to add, because speed
# is systemic.
class_name TouchControls
extends Control

signal turn_requested(direction: int)
signal reverse_requested()
signal pause_requested()

const COL_PAD := Color(0.10, 0.16, 0.26, 0.42)
const COL_PAD_HELD := Color(0.16, 0.34, 0.52, 0.72)
const COL_EDGE := Color(0.12, 0.85, 1.0, 0.55)
const COL_GLYPH := Color(0.85, 0.95, 1.0, 0.92)

# The bands the HUD already owns, which the pads must not cover.
#
# Taken as constants rather than measured off the HUD at runtime, because the
# HUD builds its own layout from literals too and a pad that queried it would
# be reading a rect that is only correct after a frame has been laid out. If
# either moves, both move -- they are one screen.
#
# The barrier bar is the most important element on screen (CLAUDE.md section
# 5.1); a tap target sitting over it was the first thing the rendered frame
# caught, and it is exactly the sort of thing no headless assertion sees.
const HUD_BOTTOM_BAND := 120.0   # barrier + integrity, bottom-left
const HUD_TOP_BAND := 70.0       # speed / maze / timer row

# Steering pads, anchored to the bottom corners -- where thumbs are on a phone
# held in landscape, and nowhere else.
#
# Sized as a fraction of the screen, because a pixel size that suits a 1600x900
# desktop window is a third of the width of a small phone. Capped in pixels as
# well, so a big desktop window does not hand back a pad the size of a playing
# card for a mouse to hit.
const PAD_W_FRACTION := 0.20
const PAD_H_FRACTION := 0.26
const PAD_W_MAX := 260.0
const PAD_H_MAX := 200.0

# The 180 sits between the two steering pads, deliberately smaller and set low.
# It is the expensive input (section 5.3) and the un-stick, so it must be
# reachable without being easy to clip with the side of a thumb aimed at a turn.
const REVERSE_W_FRACTION := 0.16
const REVERSE_H_FRACTION := 0.14
const REVERSE_W_MAX := 200.0
const REVERSE_H_MAX := 110.0

const PAUSE_SIZE := Vector2(70.0, 52.0)

# The two bars of the pause icon. Weight is chosen for the pad rather than
# inherited from a font -- a text glyph drew them as hairlines.
const PAUSE_BAR_W := 5.0
const PAUSE_BAR_H := 20.0
const PAUSE_BAR_GAP := 7.0

const MARGIN := 18.0

var _pads: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE, not STOP: this Control spans the whole screen so its children can
	# be placed against real corners, and a full-screen STOP would swallow every
	# click meant for the upgrade cards underneath it. Only the pads themselves
	# take input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_pad("left", "◀", func(): emit_signal("turn_requested", -1))
	_build_pad("right", "▶", func(): emit_signal("turn_requested", 1))
	_build_pad("reverse", "↶", func(): emit_signal("reverse_requested"))
	# Pause is drawn, not lettered -- see _build_pause_icon.
	_build_pad("pause", "", func(): emit_signal("pause_requested"))
	_build_pause_icon(_pads["pause"])

	_layout()
	resized.connect(_layout)


# One pad. A Panel with a Label centred in it rather than a Button, because a
# Button fires on RELEASE and steering wants the turn armed the instant the
# thumb lands -- at 8x a cell is 125ms and a press-to-release round trip is a
# meaningful part of the buffer (section 4).
func _build_pad(key: String, glyph: String, handler: Callable) -> void:
	var pad := Panel.new()
	pad.name = key
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.add_theme_stylebox_override("panel", _pad_style(false))

	if glyph != "":
		var label := Label.new()
		label.text = glyph
		label.add_theme_font_size_override("font_size", 40)
		label.add_theme_color_override("font_color", COL_GLYPH)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(label)

	pad.gui_input.connect(func(event: InputEvent) -> void:
		_on_pad_input(pad, event, handler))

	add_child(pad)
	_pads[key] = pad


# The pause icon: two solid bars, drawn as geometry rather than typed as a
# character.
#
# It was the glyph U+2016, which is a TYPOGRAPHIC mark -- a double vertical
# line meant to sit in running text -- so the font drew it at text stroke
# weight and it read as two hairlines rattling around inside a 70px pad. No
# font size fixes that: scaling a hairline scales its height, not its weight,
# and the pause symbol in most UI fonts is not a text character at all. Two
# ColorRects give the bars a weight chosen for the pad instead of inherited
# from a typeface, and they stay crisp at any resolution -- which matters here
# because this is the one pad the web build shows on a phone at whatever DPI
# the device happens to have.
func _build_pause_icon(pad: Panel) -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(holder)

	for i in 2:
		var bar := ColorRect.new()
		bar.color = COL_GLYPH
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Centred as a pair: each bar sits half a gap out from the middle.
		bar.anchor_left = 0.5
		bar.anchor_right = 0.5
		bar.anchor_top = 0.5
		bar.anchor_bottom = 0.5
		var dir := -1.0 if i == 0 else 1.0
		var near_edge := PAUSE_BAR_GAP * 0.5 * dir
		var far_edge := near_edge + PAUSE_BAR_W * dir
		bar.offset_left = min(near_edge, far_edge)
		bar.offset_right = max(near_edge, far_edge)
		bar.offset_top = -PAUSE_BAR_H * 0.5
		bar.offset_bottom = PAUSE_BAR_H * 0.5
		holder.add_child(bar)


# Fires on press, for both a finger and a mouse, and never on release.
#
# Both device types are handled because the toggle is available on desktop --
# a tester with a mouse must be able to drive the same pads, or the setting
# cannot be checked without a phone in hand.
func _on_pad_input(pad: Panel, event: InputEvent, handler: Callable) -> void:
	var pressed := false
	var released := false

	if event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed

	if pressed:
		pad.add_theme_stylebox_override("panel", _pad_style(true))
		handler.call()
		accept_event()
	elif released:
		pad.add_theme_stylebox_override("panel", _pad_style(false))
		accept_event()


func _pad_style(held: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PAD_HELD if held else COL_PAD
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = COL_EDGE
	return style


# Placed in code against the live viewport rather than by anchors alone: the
# pads are sized as a fraction of the screen, the reverse pad has to be centred
# between the other two whatever that resolves to, and every one of them has to
# clear a band the HUD already occupies.
func _layout() -> void:
	var view := size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	var pad := Vector2(
		min(view.x * PAD_W_FRACTION, PAD_W_MAX),
		min(view.y * PAD_H_FRACTION, PAD_H_MAX))
	var rev := Vector2(
		min(view.x * REVERSE_W_FRACTION, REVERSE_W_MAX),
		min(view.y * REVERSE_H_FRACTION, REVERSE_H_MAX))

	# The steering pads stop short of the HUD's bottom band so the barrier and
	# integrity bars stay both visible and untappable.
	var floor_y := view.y - HUD_BOTTOM_BAND
	var pad_top := floor_y - pad.y
	var rev_top := floor_y - rev.y

	_place(_pads.get("left"), Rect2(MARGIN, pad_top, pad.x, pad.y))
	_place(_pads.get("right"), Rect2(
		view.x - pad.x - MARGIN, pad_top, pad.x, pad.y))
	_place(_pads.get("reverse"), Rect2(
		(view.x - rev.x) * 0.5, rev_top, rev.x, rev.y))

	# Below the timer, not beside it. The timer is right-aligned in the HUD's
	# top row and its width changes as the run passes a minute, so anything
	# sharing that line eventually collides with it -- which the first rendered
	# frame showed happening.
	_place(_pads.get("pause"), Rect2(
		view.x - PAUSE_SIZE.x - MARGIN, HUD_TOP_BAND + MARGIN,
		PAUSE_SIZE.x, PAUSE_SIZE.y))


func _place(node: Variant, rect: Rect2) -> void:
	if node == null:
		return
	var pad: Control = node
	pad.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pad.position = rect.position
	pad.size = rect.size
