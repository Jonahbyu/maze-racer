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

# Leave the run and go back to the title screen.
#
# The panel does NOT act on this itself. It is mounted in two places, and only
# one of them has a run to leave -- so the mount decides what quitting means and
# the panel only reports the press, the same division `closed` already uses.
signal quit_to_menu()

# Height is derived from the rows the panel actually builds, not a band picked
# to fit the ones it had -- the section 12 hard-coded-layout trap, which the
# menu's button stack and the summary panel have both already paid for. QUIT TO
# MENU is a conditional row, so the height genuinely varies by mount.
const PANEL_WIDTH := 520.0
const PANEL_BASE_HEIGHT := 330.0
const ROW_HEIGHT := 44.0

# The heading and the padding the card puts around and between its rows. Named
# because _row_height has to subtract them to find the space the rows may use.
# MEASURED, not estimated: a card of 5 rows at 101.5 units laid out 783 tall,
# so everything that is not a row -- the heading, the card's content margins and
# the separations between rows -- comes to 275. A guess at this number is what
# let the panel overrun the screen while the arithmetic said it fitted.
# MEASURED, not estimated. A card of 5 rows at 101.5 units laid out 783 tall,
# broken down as: heading 95, three spacers 14, the rows themselves, and 164 of
# card margins. So everything that is not a row comes to 273.
#
# Guessing this number is what let the panel overrun the screen while the
# arithmetic said it fitted -- the offset asked for 676 and the card laid out at
# 783, because a PanelContainer sizes to its CONTENTS and simply ignores an
# offset smaller than they need.
const CARD_FIXED := 273.0

# How far above screen centre the card sits. See _build_panel.
const PANEL_RISE := 20.0

# Breathing room between the card and the screen edge, so a full-height panel
# does not sit flush against it.
const EDGE_MARGIN := 12.0

const COL_ACCENT := MainMenu.COL_ACCENT
const COL_DIM := MainMenu.COL_DIM
const COL_CARD := MainMenu.COL_CARD
const COL_CARD_HOVER := MainMenu.COL_CARD_HOVER

# Whether this mount has a run to leave. Set by the mount BEFORE add_child,
# because _ready builds the rows -- the same ordering Game.board needs, and for
# the same reason: a flag set afterwards arrives one build too late.
var allow_quit: bool = false

var _slider: HSlider = null
var _mute_button: Button = null
var _touch_button: Button = null
var _volume_label: Label = null
var _cam_slider: HSlider = null
var _cam_label: Label = null


# The viewport-to-screen scale, guarded exactly as MainMenu's is.
#
# The panel is the pause screen on a phone now, so its rows are tap targets
# rather than merely readable -- and at a flat 44 units a row is 14 CSS px on a
# handset. Below a viewport size no real display has, 1.0 is the honest answer:
# a headless run reports a 0.04 scale on a 64x64 dummy, which is finite,
# meaningless, and would inflate every row 25x.
func _view_scale() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.0
	var view := vp.get_visible_rect().size
	if view.x < 320.0 or view.y < 240.0:
		return 1.0
	var sx: float = vp.get_stretch_transform().get_scale().x
	# A LOWER BOUND ON THE SCALE ITSELF, not only on the viewport.
	#
	# Guarding the viewport size is not enough, and trusting it produced 1100
	# unit buttons in the harness: a Window reports a plausible 1600x900 visible
	# rect while its stretch transform is still the dummy's, so the size check
	# passes and the scale is fiction. 0.15 is below any real device -- the
	# tightest measured phone is 0.328 -- and far above the 0.04 a headless run
	# reports, so it separates the two without touching anything real.
	if sx < 0.15 or sx > 8.0:
		return 1.0
	return sx


# A row's height in viewport units, so it measures at least the published tap
# minimum on the glass.
func _row_height() -> float:
	var want: float = maxf(ROW_HEIGHT, 44.0 / _view_scale())
	# ...but never more than the rows can actually fit into.
	#
	# A PanelContainer grows to its CONTENTS, so a row height that does not fit
	# does not clip -- it pushes the card off the bottom of the screen, taking
	# CLOSE with it. That is the summary panel's hard-coded-band failure exactly
	# (section 8c): the best-looking rows in the game, with no visible way out.
	#
	# So the height is bounded by the space there is. The row count is read from
	# what this panel actually builds rather than restated, since allow_quit
	# changes it -- restating it is the section 12 trap one step along.
	var rows: float = float(_row_count())
	var view_h: float = float(get_viewport_rect().size.y)
	# A PanelContainer sizes itself to its CONTENTS and ignores any offset
	# smaller than they need, so panel_h below is a request the card is free to
	# refuse -- which is exactly what it did: the computed height said 676 and
	# the card laid out at 783, running 15 units off the bottom of the screen
	# with CLOSE on the far side of the edge.
	#
	# So the ROWS have to fit, because they are what the card is measuring. The
	# card is centred and then lifted by PANEL_RISE, which costs it twice at the
	# bottom, and CARD_OVERHEAD is everything in the card that is not a row.
	var usable: float = view_h - EDGE_MARGIN * 2.0 - CARD_FIXED
	var room: float = usable / maxf(rows, 1.0)
	return clampf(want, ROW_HEIGHT, maxf(room, ROW_HEIGHT))


# The rows this panel builds: music, camera, mute, mobile controls, close, and
# the quit row when the mount has a run to leave.
#
# Read by _row_height rather than restated there, so adding a row here shrinks
# the rows to fit instead of pushing CLOSE off the bottom edge -- the section 8c
# overrun, which this panel has already paid for once.
func _row_count() -> int:
	return 6 if allow_quit else 5


func _font_px(base: float) -> int:
	return clampi(int(round(base / _view_scale())), int(base), 96)


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
	# Sized BEFORE the card is laid out, because both offsets read them. The
	# height is derived from the rows this panel actually builds, at the height
	# those rows actually get -- a band sized for desktop rows clips every one
	# of them once the rows grow for a phone.
	var row_h: float = _row_height()
	# Built from what the card actually contains, measured rather than guessed:
	# CARD_FIXED is the heading, the spacers and the card's own margins, and the
	# rest is one row per control. An estimate here is what let the offset and
	# the laid-out card disagree by 100 units.
	var panel_h: float = CARD_FIXED + row_h * float(_row_count())
	var panel_w: float = clampf(PANEL_WIDTH / _view_scale(), PANEL_WIDTH,
		maxf(float(get_viewport_rect().size.x) - 80.0, PANEL_WIDTH))

	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -panel_w * 0.5
	card.offset_right = panel_w * 0.5
	# Lifted slightly above dead centre: the title sits above and the menu hint
	# below, and a panel centred exactly split the difference badly, overlapping
	# both. Only a rendered frame shows this.
	# The RISE gives way before the screen edge does.
	#
	# PANEL_RISE lifts the card off dead centre so the menu's title and hint are
	# not split by it, which is a desktop nicety. On a phone the card is nearly
	# as tall as the viewport, and the same lift pushes CLOSE off the bottom --
	# measured, the card ran to 915 against a 900-tall viewport, which is the
	# summary panel's overrun (section 8c) in a second place. A control the
	# player cannot reach beats a slightly off-centre card every time, so the
	# rise is taken back exactly as far as the overflow requires and no further.
	var view_h: float = float(get_viewport_rect().size.y)
	var half: float = panel_h * 0.5
	var rise: float = PANEL_RISE
	var overflow: float = (view_h * 0.5 + half + rise) - (view_h - EDGE_MARGIN)
	if overflow > 0.0:
		rise = maxf(rise - overflow, 0.0)
	card.offset_top = -half + rise
	card.offset_bottom = half + rise

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
	music_row.custom_minimum_size = Vector2(0, _row_height())
	rows.add_child(music_row)

	music_row.add_child(_row_label("MUSIC"))

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.custom_minimum_size = Vector2(220, _row_height())
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
	_volume_label.custom_minimum_size = Vector2(64, _row_height())
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_row.add_child(_volume_label)

	# --- Camera sensitivity ---
	#
	# Directly under MUSIC and built the same way, because it is the same kind
	# of control: a continuous value with a number beside it. A dial that looked
	# different from the slider above it would imply it behaved differently.
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 14)
	cam_row.custom_minimum_size = Vector2(0, _row_height())
	rows.add_child(cam_row)

	cam_row.add_child(_row_label("CAMERA"))

	_cam_slider = HSlider.new()
	_cam_slider.min_value = Tuning.CAM_SENSITIVITY_MIN
	_cam_slider.max_value = Tuning.CAM_SENSITIVITY_MAX
	# Whole notches. A camera lag is not something anyone tunes to a decimal
	# place, and a 0..10 dial that lands on 6.37 reads as a bug rather than a
	# choice.
	_cam_slider.step = 1.0
	_cam_slider.custom_minimum_size = Vector2(220, _row_height())
	_cam_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cam_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cam_slider.focus_mode = Control.FOCUS_ALL
	_style_slider(_cam_slider)
	# value_changed, not drag_ended, for the reason the volume slider uses it:
	# the panel is mounted over a live game on pause, so the camera can be seen
	# responding while the slider moves. Adjusting a view setting blind, then
	# closing the panel to find out what you picked, is the thing this avoids.
	_cam_slider.value_changed.connect(_on_cam_changed)
	cam_row.add_child(_cam_slider)

	# The ends are named rather than numbered, because "0" and "10" say nothing
	# about which end is which -- and the dial's whole subject is a direction of
	# travel, not a magnitude. The number is still shown, so a player can
	# describe or return to a setting.
	_cam_label = _row_label("SNAP")
	_cam_label.custom_minimum_size = Vector2(64, _row_height())
	_cam_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cam_row.add_child(_cam_label)

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

	# --- Quit to menu ---
	#
	# Only on the mount that has a run to leave. On the title screen there is
	# nothing to quit TO, so the row would be a button that either does nothing
	# or re-enters the screen the player is already looking at.
	#
	# It sits above CLOSE rather than below because CLOSE is the way out of the
	# panel and wants to stay the last thing in the stack -- and because a
	# destructive action directly under the thumb's resting position, where
	# CLOSE is expected, is the one place it should not be.
	if allow_quit:
		rows.add_child(_spacer(4))
		var quit_button := _make_button("QUIT TO MENU", _on_quit_to_menu)
		quit_button.add_theme_color_override("font_color",
			Color(1.0, 0.72, 0.60))
		rows.add_child(quit_button)

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
	label.add_theme_font_size_override("font_size", _font_px(30.0))
	label.add_theme_color_override("font_color", COL_ACCENT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


# Reported, never acted on -- the mount owns what leaving a run means.
func _on_quit_to_menu() -> void:
	emit_signal("quit_to_menu")


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _font_px(20.0))
	label.add_theme_color_override("font_color", COL_DIM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(110, _row_height())
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, _row_height())
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", _font_px(20.0))
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
	if _cam_slider != null:
		var dial: float = (float(settings.cam_sensitivity) if settings != null
			else Tuning.cam_sensitivity_default())
		# Blocked for the reason the volume slider is: without it the assignment
		# re-enters the handler and writes straight back to Settings, so merely
		# opening the panel rewrites the config file.
		_cam_slider.set_block_signals(true)
		_cam_slider.value = dial
		_cam_slider.set_block_signals(false)
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
	if _cam_label != null:
		var dial: float = (float(settings.cam_sensitivity) if settings != null
			else Tuning.cam_sensitivity_default())
		_cam_label.text = _cam_text(dial)


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


func _on_cam_changed(value: float) -> void:
	var settings := _settings()
	if settings != null:
		settings.set_cam_sensitivity(value)
	_refresh_labels()


# The readout beside the camera slider.
#
# The ends are NAMED, because a bare 0 and 10 do not say which way the dial
# runs -- and the two ends are opposite behaviours rather than more and less of
# one thing. The number rides along so a setting can be described or returned
# to. Thresholds are derived from the dial's own bounds rather than written as
# literals, so a future re-scale cannot leave the labels pointing at the wrong
# end of the range.
func _cam_text(dial: float) -> String:
	var lo: float = Tuning.CAM_SENSITIVITY_MIN
	var hi: float = Tuning.CAM_SENSITIVITY_MAX
	if dial <= lo:
		return "SNAP"
	if dial >= hi:
		return "%d LAG" % int(round(dial))
	return "%d" % int(round(dial))


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
