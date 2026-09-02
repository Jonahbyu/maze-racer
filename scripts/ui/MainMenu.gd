# The title screen: PLAY, WATCH TRAILER, QUIT, and a settings cog.
#
# Deliberately flat -- no 3D behind it. The trailer is the moving shop window
# (docs/specs/trailer.md); a menu that also rendered a live maze would be paying
# the cost of both and diluting the one that is actually built to sell the game.
#
# Colours are taken from the maze-1 palette in Tuning rather than restated, so
# the title screen cannot drift away from the game's own cyan.
class_name MainMenu
extends Control

signal play_pressed()
signal trailer_pressed()

const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.55, 0.62, 0.75)
const COL_CARD := Color(0.07, 0.10, 0.16, 0.96)
const COL_CARD_HOVER := Color(0.12, 0.20, 0.32, 0.98)

const BUTTON_SIZE := Vector2(360, 62)
const SEPARATION := 18.0

const COG_SIZE := 52.0
const COG_MARGIN := 24.0

# Where the button stack starts, relative to screen centre. The stack grows
# downward from here and the hint follows it.
const ROW_TOP := -40.0

var _buttons: Array[Button] = []
var _hint: Label = null
var _cog: Button = null
var _panel: SettingsPanel = null


func _ready() -> void:
	# Anchors and offsets together. set_anchors_preset() leaves the offsets at
	# zero and yields a degenerate rect, which is what hung UpgradeScreen's cards
	# off the top-left corner (CLAUDE.md section 12).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_background()
	_build_title()
	_build_buttons()
	_build_cog()


func _build_background() -> void:
	var back := ColorRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.01, 0.015, 0.03)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)


func _build_title() -> void:
	var title := _centred_label("MAZE RACER", 78, COL_ACCENT, -250, -150)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(title)


func _build_buttons() -> void:
	var row := VBoxContainer.new()
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 0.5
	row.anchor_bottom = 0.5
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", SEPARATION)
	row.offset_left = -BUTTON_SIZE.x * 0.5
	row.offset_right = BUTTON_SIZE.x * 0.5
	add_child(row)

	row.add_child(_make_button("PLAY", _on_play))
	row.add_child(_make_button("WATCH TRAILER", _on_trailer))
	# MOBILE CONTROLS used to sit here. It moved into the settings panel so
	# that preferences live in exactly one place -- a toggle in the button
	# stack and a panel behind a cog would be two homes for the same category.
	row.add_child(_make_button("QUIT", _on_quit))

	# Derived from what the row actually holds, never a fixed band. The previous
	# literal 180 fitted three buttons by luck and already clipped the third
	# slightly; a fourth overflowed it outright. Same trap as the upgrade card
	# row (CLAUDE.md section 12) -- read the count, do not restate the total.
	var count: int = _buttons.size()
	var gaps: float = float(max(count - 1, 0))
	var stack: float = BUTTON_SIZE.y * float(count) + SEPARATION * gaps
	row.offset_top = ROW_TOP
	row.offset_bottom = ROW_TOP + stack

	if not _buttons.is_empty():
		_buttons[0].grab_focus()

	# Below the row wherever the row now ends, for the same reason.
	_hint = _centred_label(_hint_text(), 16, COL_DIM,
		row.offset_bottom + 30.0, row.offset_bottom + 60.0)
	add_child(_hint)


# Top-right, clear of the title and the button stack. A corner rather than a
# row entry because settings is not a peer of PLAY -- it is the door beside the
# room, and putting it in the stack is what crowded the stack in the first place.
func _build_cog() -> void:
	var cog := Button.new()
	cog.text = "⚙"
	cog.tooltip_text = "Settings"
	cog.custom_minimum_size = Vector2(COG_SIZE, COG_SIZE)
	cog.focus_mode = Control.FOCUS_ALL
	cog.add_theme_font_size_override("font_size", 30)
	cog.add_theme_color_override("font_color", COL_DIM)
	cog.add_theme_color_override("font_hover_color", COL_ACCENT)
	cog.add_theme_color_override("font_focus_color", COL_ACCENT)

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var lit: bool = state in ["hover", "focus", "pressed"]
		style.bg_color = COL_CARD_HOVER if lit else COL_CARD
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = COL_ACCENT if lit else Color(0.2, 0.3, 0.45)
		cog.add_theme_stylebox_override(state, style)

	# Anchored to the top-right corner, so it stays put at any window size.
	cog.anchor_left = 1.0
	cog.anchor_right = 1.0
	cog.anchor_top = 0.0
	cog.anchor_bottom = 0.0
	cog.offset_left = -COG_SIZE - COG_MARGIN
	cog.offset_right = -COG_MARGIN
	cog.offset_top = COG_MARGIN
	cog.offset_bottom = COG_MARGIN + COG_SIZE

	cog.pressed.connect(_on_settings)
	_cog = cog
	add_child(cog)


func _on_settings() -> void:
	if _panel != null:
		return
	var panel := SettingsPanel.new()
	panel.closed.connect(_on_settings_closed)
	_panel = panel
	add_child(panel)
	panel.focus_first()


func _on_settings_closed() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	# The hint describes whichever control scheme is active, and the panel is
	# now where that gets changed -- so it has to be re-read on the way out.
	if _hint != null:
		_hint.text = _hint_text()
	if _cog != null:
		_cog.grab_focus()


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", COL_ACCENT)
	button.add_theme_color_override("font_focus_color", COL_ACCENT)

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var lit: bool = state in ["hover", "focus", "pressed"]
		style.bg_color = COL_CARD_HOVER if lit else COL_CARD
		style.set_corner_radius_all(10)
		style.set_border_width_all(2)
		style.border_color = COL_ACCENT if lit else Color(0.2, 0.3, 0.45)
		style.set_content_margin_all(12)
		button.add_theme_stylebox_override(state, style)

	button.pressed.connect(handler)
	_buttons.append(button)
	return button


func _centred_label(text: String, size: int, colour: Color,
		top: float, bottom: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -520
	label.offset_right = 520
	label.offset_top = top
	label.offset_bottom = bottom
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# The live preference, or null when this menu is running outside the real
# project -- a harness that instantiates MainMenu directly has no autoloads.
# Every read is guarded rather than assumed, for the reason Shell guards Music:
# a missing setting must never be what stops the menu drawing.
func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _touch_enabled() -> bool:
	var settings := _settings()
	return settings != null and bool(settings.touch_controls)


# The keyboard line is wrong on a phone, where there are no arrow keys to press
# -- so the hint describes whichever scheme is actually active.
func _hint_text() -> String:
	if _touch_enabled():
		return "tap the pads to steer  -  both together reverses"
	return "arrow keys steer  -  DOWN reverses  -  ESC pauses"


# Kept after the button moved into the settings panel: this is still the one
# place the menu flips the preference, and the hint below the stack has to
# follow it. The panel calls Settings directly and the menu re-reads the hint
# when the panel closes.
func _on_toggle_touch() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_touch_controls(not bool(settings.touch_controls))
	if _hint != null:
		_hint.text = _hint_text()


func _on_play() -> void:
	emit_signal("play_pressed")


func _on_trailer() -> void:
	emit_signal("trailer_pressed")


func _on_quit() -> void:
	get_tree().quit()
