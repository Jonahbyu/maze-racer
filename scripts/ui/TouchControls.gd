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
# is systemic. The 180 has no pad of its own: it is LEFT AND RIGHT TOGETHER,
# which is why there are only two steering targets and the middle of the screen
# is clear. See _on_pad_input for why the chord costs the turn nothing.
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

# ...but never more than this share of a short screen.
#
# Those two are desktop pixel measurements, and on a 390px-tall phone the
# bottom band alone is nearly a third of the display -- reserving it whole
# pushed the pads clean off the bottom edge. The bars are drawn at a fixed
# pixel height whatever the screen, so on a small one the pads simply have to
# overlap the far left of that band; they are hard against the margins and the
# bars are only ~320px wide, so what they overlap is empty space beside them.
const MAX_BAND_SHARE := 0.18

# Steering pads, anchored to the bottom corners -- where thumbs are on a phone
# held in landscape, and nowhere else.
#
# Sized against the SHORTER screen dimension, never in pixels.
#
# They were a fraction capped at a pixel maximum, and the cap is what made them
# unusably small on a phone: a phone reports a large pixel viewport, so the cap
# won every time and handed the smallest screen the same 260px pad as a desktop
# window. A pixel is not a size -- it is a count, and how big it is depends
# entirely on the device. The short edge is the honest reference because it is
# the one a thumb has to span in landscape.
const PAD_SHORT_FRACTION := 0.42   # of the shorter viewport edge
const PAD_ASPECT := 1.15           # width / height, slightly wider than tall

# A floor in pixels, not a ceiling. On a very small window the fraction alone
# can produce a target too small to hit; nothing needs protecting at the top
# end, since a big screen genuinely wants a big thumb target.
const PAD_MIN := Vector2(120.0, 100.0)

# Pause is the one control that is NOT a driving input (section 2), so it stays
# deliberately smaller than the steering pads -- but it still scales, because a
# fixed 70px box is a smudge on a phone.
const PAUSE_SHORT_FRACTION := 0.13
const PAUSE_ASPECT := 1.35
const PAUSE_MIN := Vector2(70.0, 52.0)

# The pause bars, as a fraction of the pad that holds them, for the same reason
# the pad itself is not in pixels.
const PAUSE_BAR_W_FRAC := 0.11
const PAUSE_BAR_H_FRAC := 0.42
const PAUSE_BAR_GAP_FRAC := 0.14

# The steering triangles, as a fraction of the pad that holds them.
const ARROW_W_FRAC := 0.34
const ARROW_H_FRAC := 0.44

const MARGIN := 18.0

var _pads: Dictionary = {}

# Which steering pads are currently held, by direction (-1 left, +1 right).
# A chord is both of them down at once, so this has to be tracked across
# events rather than inferred from any single one.
var _held_dirs: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE, not STOP: this Control spans the whole screen so its children can
	# be placed against real corners, and a full-screen STOP would swallow every
	# click meant for the upgrade cards underneath it. Only the pads themselves
	# take input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Both icons are drawn, not lettered -- see _build_arrow_icon.
	_build_pad("left", "", func(): _steer(-1), -1)
	_build_pad("right", "", func(): _steer(1), 1)
	_build_arrow_icon(_pads["left"], -1)
	_build_arrow_icon(_pads["right"], 1)
	# Pause is drawn, not lettered -- see _build_pause_icon.
	_build_pad("pause", "", func(): emit_signal("pause_requested"))
	_build_pause_icon(_pads["pause"])

	_layout()
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)


# A finger that slides off a pad before lifting may never deliver its release
# to that pad, which would leave a direction latched and turn every later tap
# into a reverse. Hiding the overlay -- a gate, a pause, the setting going off
# -- is a clean point to drop any half-finished gesture.
func _on_visibility_changed() -> void:
	if not visible:
		_release_all()


# Forget every held pad and reset their styling. Public so the game can call it
# on a phase change: a gesture started while racing must not survive into the
# next thing the player does.
func clear_held() -> void:
	_release_all()


func _release_all() -> void:
	_held_dirs.clear()
	for key in ["left", "right"]:
		var pad: Panel = _pads.get(key)
		if pad != null:
			pad.add_theme_stylebox_override("panel", _pad_style(false))


# One pad. A Panel with a Label centred in it rather than a Button, because a
# Button fires on RELEASE and steering wants the turn armed the instant the
# thumb lands -- at 8x a cell is 125ms and a press-to-release round trip is a
# meaningful part of the buffer (section 4).
func _build_pad(key: String, glyph: String, handler: Callable,
		direction: int = 0) -> void:
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
		_on_pad_input(pad, event, handler, direction))

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
	holder.name = "icon"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(holder)

	for i in 2:
		var bar := ColorRect.new()
		bar.color = COL_GLYPH
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.5
		bar.anchor_right = 0.5
		bar.anchor_top = 0.5
		bar.anchor_bottom = 0.5
		holder.add_child(bar)

	_size_pause_bars(PAUSE_MIN)


# The bars are re-offset whenever the pad resizes, since their size is a
# fraction OF THE PAD and the pad is a fraction of the screen.
func _size_pause_bars(pad_size: Vector2) -> void:
	var pause: Panel = _pads.get("pause")
	if pause == null:
		return
	var holder := pause.get_node_or_null("icon")
	if holder == null:
		return

	var bar_w: float = pad_size.x * PAUSE_BAR_W_FRAC
	var bar_h: float = pad_size.y * PAUSE_BAR_H_FRAC
	var gap: float = pad_size.x * PAUSE_BAR_GAP_FRAC

	var bars := holder.get_children()
	for i in bars.size():
		var bar: Control = bars[i]
		# Centred as a pair: each bar sits half a gap out from the middle.
		var dir := -1.0 if i == 0 else 1.0
		var near_edge := gap * 0.5 * dir
		var far_edge := near_edge + bar_w * dir
		bar.offset_left = min(near_edge, far_edge)
		bar.offset_right = max(near_edge, far_edge)
		bar.offset_top = -bar_h * 0.5
		bar.offset_bottom = bar_h * 0.5


# A steering arrow, drawn as a filled triangle rather than typed as a glyph.
#
# The pads used U+25C0 / U+25B6, and they broke on mobile for the same reason
# the pause glyph did: a character is only as reliable as the font behind it,
# and the web export on a phone falls back to whatever that device happens to
# ship. A missing glyph renders as a blank or a tofu box -- so the one control
# the player steers with can simply vanish, on a device we cannot test from
# here and cannot predict.
#
# A Polygon2D owes nothing to a font. It also scales exactly with the pad,
# which a font size cannot do without re-measuring text.
func _build_arrow_icon(pad: Panel, direction: int) -> void:
	var holder := Control.new()
	holder.name = "icon"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(holder)

	var arrow := Polygon2D.new()
	arrow.name = "arrow"
	arrow.color = COL_GLYPH
	arrow.set_meta("direction", direction)
	holder.add_child(arrow)


# Re-points the triangle for the current pad size, for the same reason the
# pause bars are re-offset.
func _size_arrow(key: String, pad_size: Vector2) -> void:
	var pad: Panel = _pads.get(key)
	if pad == null:
		return
	var arrow := pad.get_node_or_null("icon/arrow")
	if arrow == null:
		return

	var direction: int = int(arrow.get_meta("direction", -1))
	var half_w: float = pad_size.x * ARROW_W_FRAC * 0.5
	var half_h: float = pad_size.y * ARROW_H_FRAC * 0.5
	var centre := pad_size * 0.5
	var dir := float(direction)

	# Apex on the side it points to, flat base opposite.
	arrow.polygon = PackedVector2Array([
		centre + Vector2(half_w * dir, 0.0),
		centre + Vector2(-half_w * dir, -half_h),
		centre + Vector2(-half_w * dir, half_h),
	])


# A steering press: a turn, or the second half of a 180.
#
# LEFT AND RIGHT TOGETHER is the reverse gesture. The 180 lost its own pad
# because that pad sat in the middle of the bottom edge -- directly under the
# player marker and the corridor vanishing point, which is where the Path
# Indicator panels, the Golden Trail and the wall indicator all draw. A control
# parked over the thing it is helping you read is the same mistake the HUD
# chevrons were (section 7).
#
# The FIRST press turns immediately and the SECOND completes the chord. The
# obvious alternative -- hold both presses briefly to see whether a chord is
# forming -- was rejected on the buffer maths: the buffer is 1.0 cells (section
# 4), which at the 10x cap is 100ms, so any hold long enough to detect a chord
# would spend a large fraction of the entire forgiveness window on EVERY turn,
# and worst exactly when the game is hardest. Turning first costs the common
# case nothing.
#
# The price is that a chord also fires one turn on the way in. That is the
# right way round: a 90 is nearly free at -0.03x (section 5.3) and the racer is
# pivoted, not moved, so the stray turn is cheap and immediately undone by the
# reversal that follows. Charging every ordinary turn a fraction of its buffer
# to avoid it would be a far larger, and constant, cost.
func _steer(direction: int) -> void:
	_held_dirs[direction] = true
	if _held_dirs.has(-direction):
		emit_signal("reverse_requested")
		return
	emit_signal("turn_requested", direction)


# Fires on press, for both a finger and a mouse, and never on release.
#
# Both device types are handled because the toggle is available on desktop --
# a tester with a mouse must be able to drive the same pads, or the setting
# cannot be checked without a phone in hand.
func _on_pad_input(pad: Panel, event: InputEvent, handler: Callable,
		direction: int = 0) -> void:
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
		# Must happen, or the first chord latches both directions forever and
		# every later tap reads as a reverse. A touch that leaves the pad still
		# delivers its release here, so this is not only the lift-in-place case.
		if direction != 0:
			_held_dirs.erase(direction)
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

	# The shorter edge is the reference: in landscape that is the height, and it
	# is what a thumb actually has to span.
	var short_edge: float = min(view.x, view.y)

	var pad_h: float = max(short_edge * PAD_SHORT_FRACTION, PAD_MIN.y)
	var pad := Vector2(max(pad_h * PAD_ASPECT, PAD_MIN.x), pad_h)

	# The steering pads stop short of the HUD's bottom band so the barrier and
	# integrity bars stay both visible and untappable -- clamped, because the
	# band is a desktop pixel figure and a phone screen cannot spare it whole.
	var bottom_band: float = min(HUD_BOTTOM_BAND, view.y * MAX_BAND_SHARE)
	var pad_top := view.y - bottom_band - pad.y

	_place(_pads.get("left"), Rect2(MARGIN, pad_top, pad.x, pad.y))
	_place(_pads.get("right"), Rect2(
		view.x - pad.x - MARGIN, pad_top, pad.x, pad.y))
	_size_arrow("left", pad)
	_size_arrow("right", pad)

	# Below the timer, not beside it. The timer is right-aligned in the HUD's
	# top row and its width changes as the run passes a minute, so anything
	# sharing that line eventually collides with it -- which the first rendered
	# frame showed happening.
	var top_band: float = min(HUD_TOP_BAND, view.y * MAX_BAND_SHARE)
	var pause_h: float = max(short_edge * PAUSE_SHORT_FRACTION, PAUSE_MIN.y)
	var pause := Vector2(max(pause_h * PAUSE_ASPECT, PAUSE_MIN.x), pause_h)
	_place(_pads.get("pause"), Rect2(
		view.x - pause.x - MARGIN, top_band + MARGIN, pause.x, pause.y))
	_size_pause_bars(pause)


func _place(node: Variant, rect: Rect2) -> void:
	if node == null:
		return
	var pad: Control = node
	pad.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pad.position = rect.position
	pad.size = rect.size
