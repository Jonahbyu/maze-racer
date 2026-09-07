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

# Which direction is HELD, -1 / 0 / +1, whenever that changes.
#
# Deep Breath and Overclock (section 7) both need a key to still be down rather
# than merely to have been pressed, and the keyboard path gets that from key
# release events. The pads already track exactly this in `_held_dirs` for the
# reverse chord -- it simply was not exposed, so both lines were inert on a
# phone while working on a desktop. A view, still: this reports what the thumbs
# are doing and decides nothing.
signal held_direction_changed(direction: int)

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

# The settings cog's bottom edge: Game.COG_TOP (76) + MainMenu.COG_SIZE (52).
# Stated here for the same reason the HUD bands are -- the cog builds its own
# layout from literals, and a queried rect is only correct after a frame has
# been laid out. If the cog moves, this moves. They are one screen.
const COG_BOTTOM := 128.0

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
#
# 0.13 was too small to hit, and the reason is that the VIEWPORT IS NOT THE
# SCREEN. stretch/mode is canvas_items with aspect=expand, so a phone whose
# canvas measures 828x295 CSS pixels gets a 2526x900 viewport -- everything is
# then drawn at 0.33x. Measured on the live page, 0.13 of the short edge came
# out as a 52x38 tap target ON GLASS, under the 44x44 minimum both Apple and
# Google publish, and hard against the screen edge where the browser's own
# gestures compete. That is a pause button that "does not work" on a phone
# while being perfectly wired: every signal fires, nothing lands on it.
#
# At 0.18 the same phone gets 72x53, which clears the minimum with margin.
# _min_tap_px is what keeps this honest as screens change.
const PAUSE_SHORT_FRACTION := 0.18
const PAUSE_ASPECT := 1.35
const PAUSE_MIN := Vector2(70.0, 52.0)

# The smallest a tap target may be ON THE GLASS, in CSS pixels -- the figure
# Apple and Google both publish. Checked against the live scale rather than
# against viewport units, because a viewport pixel is not a screen pixel and
# the gap between them is 3x on a phone.
const MIN_TAP_CSS_PX := 44.0

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

# When a real finger last touched ANY pad, in milliseconds.
#
# Godot synthesizes a mouse event from every touch
# (input_devices/pointing/emulate_mouse_from_touch defaults to TRUE), and the
# browser does the same on top of it, so a phone delivers each tap twice. This
# is how the echo is told from a genuine click.
#
# Whether this overlay has ever seen a real finger.
#
# It replaces a TIMESTAMP, and the difference is the difference between a bet
# and a fact. Godot's emulate_mouse_from_touch synthesizes a mouse event from
# every touch inside the engine, so one tap arrives twice and the second must
# be dropped -- but it is delivered on whatever frame the engine reaches it,
# which is prompt when idle and late under load. Every timestamp scheme is
# therefore racing the frame rate, and the phone at 8x is the loaded case: the
# window was beaten in play at 250ms and again at 600ms, each time letting one
# tap turn the racer twice.
#
# A latch cannot be beaten by a slow frame. Once a finger has landed, this is a
# touch device and every mouse button event it delivers is a synthesized twin.
#
# It is deliberately never cleared. A player does not stop having a touchscreen
# part-way through a run, and clearing it on any phase change is what would let
# the first tap after a gate double-fire again.
var _seen_touch := false


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
	# _seen_touch is deliberately NOT cleared here. It records what KIND of
	# device this is, not a gesture in progress -- and the device does not
	# change when a gate opens. Clearing it would re-open the mouse path for
	# the next tap, which is the double turn coming straight back.
	# Hiding the overlay must release the held direction too, or a Deep Breath
	# extension bought on the way out lasts forever -- the same latch the chord
	# comment below is about, reaching a second consumer.
	emit_signal("held_direction_changed", 0)
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
# Indicator panels and the Golden Trail both draw. A control parked over the
# thing it is helping you read is the same mistake the HUD chevrons were
# (section 7).
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
	emit_signal("held_direction_changed", direction)
	if _held_dirs.has(-direction):
		emit_signal("reverse_requested")
		return
	emit_signal("turn_requested", direction)


# Fires on press, for both a finger and a mouse, and never on release.
#
# ONE TAP MUST BE ONE TURN, and that needs saying because a phone does not
# send one event per tap. `input_devices/pointing/emulate_mouse_from_touch`
# defaults to TRUE, so every finger press arrives TWICE: the
# InputEventScreenTouch, then a synthesized InputEventMouseButton from the
# same finger. Accepting both fired the handler twice, which on a phone read
# as the racer turning when the thumb landed and AGAIN a moment later -- a
# phantom input that made the game unplayable on the one platform these pads
# exist for.
#
# `accept_event()` does not prevent it: the emulated event is GENERATED from
# the touch rather than propagated from it, so it arrives regardless of what
# this handler does with the first one.
#
# So a pad remembers whether a finger is on it and ignores mouse events while
# one is. It cannot just ignore mouse events outright -- the pads must stay
# clickable on desktop -- and it must not switch on is_touchscreen_available()
# either, since a laptop with a touchscreen would then lose the mouse. The
# STATE decides, not the device.
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
		# Latch the device as a TOUCH device on the first real finger.
		#
		# Set on press and release alike, because either may be the first event
		# this overlay sees -- a finger already down when the pads appear
		# delivers only its release here.
		_seen_touch = true
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# A DEVICE THAT DELIVERS TOUCH IS NEVER ALSO CLICKED.
		#
		# This was a time window, and a time window cannot be made correct --
		# it is racing the frame rate. Godot synthesizes the mouse event INSIDE
		# the engine from the touch, so it arrives on whatever frame the engine
		# gets to it: prompt when idle, late under load. A phone at 8x is
		# precisely the loaded case, so the window failed exactly where the
		# game is hardest, and it failed by letting one real tap turn TWICE.
		#
		# Measured: an echo delayed past the window produces 2 turns from one
		# tap. Widening the window only moves the threshold -- no value is both
		# long enough never to be beaten by a slow frame and short enough to
		# keep a desktop's genuine clicks responsive. Two earlier fixes tuned
		# this number (250, then 600) and both were beaten in play.
		#
		# So the guard is a LATCH on a fact rather than a bet on a clock. Once
		# this overlay has seen a real InputEventScreenTouch, the device steers
		# by finger, and every mouse button event it will ever deliver here is
		# a synthesized twin of one. Dropping them all is correct and costs
		# nothing -- a touchscreen player has no mouse to lose.
		#
		# Desktop is untouched: no touch ever arrives, so the latch never
		# closes. A laptop with both still works -- it takes the mouse until a
		# finger lands, and steers by finger from then on, which is the input
		# the player just chose.
		if _seen_touch:
			accept_event()
			return
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
		#
		# A release is only meaningful if this direction is actually held.
		# `released` is just `not event.pressed`, so ANY release-shaped event
		# reaches here -- including one whose press was never seen, which is
		# routine: clear_held() runs on every phase change (a gate, a pause)
		# and drops _held_dirs while a finger is still on the glass, so the
		# eventual lift arrives with nothing behind it. Emitting there reports
		# a direction change the player never made, and Game feeds that
		# straight into _set_held_direction -- which cancels an Overclock.
		if direction != 0 and _held_dirs.has(direction):
			_held_dirs.erase(direction)
			# Report whatever is STILL held rather than a bare 0: lifting one
			# finger of a chord leaves the other down, and saying "nothing held"
			# there would cut a Deep Breath extension short mid-corner.
			var remaining := 0
			for d in _held_dirs:
				remaining = int(d)
			emit_signal("held_direction_changed", remaining)
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
	#
	# And below the SETTINGS COG, which lives in this same corner. The cog is
	# only visible while paused, so it is easy to miss: measured, its whole
	# 52x52 rect sat INSIDE the pause pad at every viewport size. The pads are
	# added to UIRoot after the cog, so the pad won every tap and the cog was
	# unreachable on a phone -- the only platform where the pause pad exists.
	# Clearing it costs nothing, since the corner below is empty.
	var top_band: float = min(HUD_TOP_BAND, view.y * MAX_BAND_SHARE)
	var pause_h: float = max(short_edge * PAUSE_SHORT_FRACTION, PAUSE_MIN.y)
	var pause := Vector2(max(pause_h * PAUSE_ASPECT, PAUSE_MIN.x), pause_h)
	var pause_top: float = maxf(top_band, COG_BOTTOM) + MARGIN
	_place(_pads.get("pause"), Rect2(
		view.x - pause.x - MARGIN, pause_top, pause.x, pause.y))
	_size_pause_bars(pause)


func _place(node: Variant, rect: Rect2) -> void:
	if node == null:
		return
	var pad: Control = node
	pad.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pad.position = rect.position
	pad.size = rect.size
