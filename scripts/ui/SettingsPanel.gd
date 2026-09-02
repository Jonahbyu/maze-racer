# The settings panel: music volume, mute, and the mobile-controls toggle.
#
# One panel, mounted in two places -- the title screen and the in-game pause
# screen. A player who finds the music too loud mid-run should not have to quit
# to fix it, and pause is already the moment the game is held (CLAUDE.md
# section 2), so it is where a settings door belongs.
#
# It owns no preference of its own. Every control reads Settings on open and
# writes back through Settings' own setters, which is what makes the same panel
# correct in both mounts: there is no second copy of the state to keep in step.
#
# Colours come from the maze-1 palette via MainMenu's constants rather than
# being restated, for the reason the menu takes them from Tuning -- a title
# screen and its settings door drifting apart in colour is exactly the kind of
# drift a shared constant prevents.
class_name SettingsPanel
extends Control

signal closed()

const PANEL_SIZE := Vector2(520, 330)
const ROW_HEIGHT := 44.0

# How far above screen centre the card sits. See _build_panel.
const PANEL_RISE := 20.0

const COL_ACCENT := MainMenu.COL_ACCENT
const COL_DIM := MainMenu.COL_DIM
const COL_CARD := MainMenu.COL_CARD
const COL_CARD_HOVER := MainMenu.COL_CARD_HOVER

var _slider: HSlider = null
var _mute_button: Button = null
var _touch_button: Button = null
var _volume_label: Label = null


func _ready() -> void:
	# Anchors and offsets together -- set_anchors_preset() alone leaves a
	# degenerate rect and every centred child lands on the origin (section 12).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the scrim has to swallow clicks aimed at whatever is
	# behind it, or a press meant for this panel reaches the menu button under
	# it as well.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_scrim()
	_build_panel()
	_refresh()


# Dim what is behind rather than hiding it. The pause mount sits over a live
# corridor, and blacking it out would make settings read as a mode change
# instead of a panel over a held game.
func _build_scrim() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Deep enough that a lit corridor behind it stops competing with the panel,
	# short of hiding it -- the pause mount is over live gameplay and blacking
	# it out would read as a mode change rather than a panel over a held game.
	scrim.color = Color(0.0, 0.0, 0.0, 0.86)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)


func _build_panel() -> void:
	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -PANEL_SIZE.x * 0.5
	card.offset_right = PANEL_SIZE.x * 0.5
	# Lifted slightly above dead centre: the title sits above and the menu hint
	# below, and a panel centred exactly split the difference badly, overlapping
	# both. Only a rendered frame shows this.
	card.offset_top = -PANEL_SIZE.y * 0.5 + PANEL_RISE
	card.offset_bottom = PANEL_SIZE.y * 0.5 + PANEL_RISE

	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = COL_ACCENT
	style.set_content_margin_all(26)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	card.add_child(rows)

	rows.add_child(_heading("SETTINGS"))
	rows.add_child(_spacer(6))

	# --- Music volume ---
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 14)
	music_row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	rows.add_child(music_row)

	music_row.add_child(_row_label("MUSIC"))

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.custom_minimum_size = Vector2(220, ROW_HEIGHT)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_ALL
	_style_slider(_slider)
	# value_changed, not drag_ended: the point of a volume slider is that you
	# hear the level while moving it, so the change has to land continuously.
	_slider.value_changed.connect(_on_volume_changed)
	music_row.add_child(_slider)

	# The number is the readout, so the slider does not have to be eyeballed
	# against its own track. Fixed width, or the row reflows as digits change.
	_volume_label = _row_label("100%")
	_volume_label.custom_minimum_size = Vector2(64, ROW_HEIGHT)
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_row.add_child(_volume_label)

	# --- Mute ---
	_mute_button = _make_button("", _on_toggle_mute)
	rows.add_child(_mute_button)

	# --- Mobile controls ---
	#
	# Lives here rather than in the menu's button stack: this is the one place
	# preferences are, and a toggle sitting outside it would be a second home
	# for the same category of thing.
	_touch_button = _make_button("", _on_toggle_touch)
	rows.add_child(_touch_button)

	rows.add_child(_spacer(4))
	rows.add_child(_make_button("CLOSE", _on_close))


# --- Widgets -----------------------------------------------------------------

# The stock slider draws a near-white track and grabber, which reads louder
# than the panel heading and pulls the eye to the control rather than the value.
# Nothing asserts colour -- this is a rendered-frame fix.
func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.16, 0.22, 0.32)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)

	# The filled portion carries the accent, so the value is what is bright.
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_ACCENT
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", COL_ACCENT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", COL_DIM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(110, ROW_HEIGHT)
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", COL_ACCENT)
	button.add_theme_color_override("font_focus_color", COL_ACCENT)

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var lit: bool = state in ["hover", "focus", "pressed"]
		style.bg_color = COL_CARD_HOVER if lit else COL_CARD
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = COL_ACCENT if lit else Color(0.2, 0.3, 0.45)
		style.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, style)

	button.pressed.connect(handler)
	return button


# --- State -------------------------------------------------------------------

# The live preference, or null outside the real project -- a harness that
# instantiates this panel bare has no autoloads. Guarded rather than assumed,
# for the reason MainMenu guards the same lookup.
func _settings() -> Node:
	return get_node_or_null("/root/Settings")


# Push every control to what Settings currently holds. Called on open rather
# than trusting the widgets' own defaults, so the panel cannot show one value
# while the game plays another.
func _refresh() -> void:
	var settings := _settings()
	if _slider != null:
		var volume: float = (
			float(settings.music_volume) if settings != null else 1.0)
		# Without this the assignment re-enters _on_volume_changed and writes
		# the value straight back to Settings -- harmless here, but it turns a
		# refresh into a save, and on the pause mount that means opening the
		# panel rewrites the config file.
		_slider.set_block_signals(true)
		_slider.value = volume
		_slider.set_block_signals(false)
	_refresh_labels()


func _refresh_labels() -> void:
	var settings := _settings()
	var volume: float = float(settings.music_volume) if settings != null else 1.0
	var muted: bool = bool(settings.music_muted) if settings != null else false
	var touch: bool = bool(settings.touch_controls) if settings != null else false

	if _volume_label != null:
		_volume_label.text = "%d%%" % int(round(volume * 100.0))
	# The label carries the state, so each button reads as a switch rather than
	# an action -- the same choice the menu's toggle already makes. A separate
	# indicator beside it would be a second thing to keep in sync.
	# "SOUND", not "MUSIC" -- a button reading MUSIC: ON directly beneath a row
	# labelled MUSIC reads as a second control for the same thing. Only a
	# rendered frame shows that; the strings are individually fine.
	if _mute_button != null:
		_mute_button.text = "SOUND:  %s" % ("MUTED" if muted else "ON")
	if _touch_button != null:
		_touch_button.text = "MOBILE CONTROLS:  %s" % ("ON" if touch else "OFF")


# --- Handlers ----------------------------------------------------------------

func _on_volume_changed(value: float) -> void:
	var settings := _settings()
	if settings != null:
		settings.set_music_volume(value)
		# Moving the slider off zero while muted is a clear request to hear
		# something. Leaving it muted would look like a broken slider: the
		# number climbs and nothing happens.
		if value > 0.0 and bool(settings.music_muted):
			settings.set_music_muted(false)
	_refresh_labels()


func _on_toggle_mute() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_music_muted(not bool(settings.music_muted))
	_refresh_labels()


func _on_toggle_touch() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_touch_controls(not bool(settings.touch_controls))
	_refresh_labels()


func _on_close() -> void:
	emit_signal("closed")


# ESC closes the panel, matching what ESC does everywhere else in the game.
#
# Handled here and marked handled, so the same press cannot also reach the
# pause handler underneath and resume a game the player was still configuring.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		_on_close()


# Focus the slider when the panel opens, so a keyboard or gamepad player can
# reach the controls without a mouse.
func focus_first() -> void:
	if _slider != null:
		_slider.grab_focus()
