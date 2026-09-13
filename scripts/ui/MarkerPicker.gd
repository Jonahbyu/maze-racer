# The marker picker: choose which mark sits inside the player's ring.
#
# The one cosmetic choice in the game, and the reason it is a menu button rather
# than a settings-panel row (CLAUDE.md, "The marker's shape is the player's to
# pick"). Preferences are things you set once to make the game work on your
# hardware; this is closer to picking a character -- it wants to be seen rather
# than found, and it needs a preview, which is a panel row's worth of screen on
# its own.
#
# SHAPE ONLY. Colour is deliberately not offered: the marker is near-white
# because a saturated marker collides with a maze palette, and because
# scrape-amber and crash-red only read as STATE while the resting colour carries
# no hue of its own. Every option here draws in the same white.
#
# It owns no preference. The list is Tuning.MARKER_SHAPES and the choice is
# written through Settings' own setter, which is what keeps this screen from
# becoming a second copy of the state.
class_name MarkerPicker
extends Control

# Preloaded rather than reached through the autoload, because this screen is
# instantiated by harnesses that have none. The EARNED SET still comes from the
# autoload when there is one -- see _unlocked().
const UnlocksScript := preload("res://scripts/core/Unlocks.gd")

signal closed()

const COL_ACCENT := MainMenu.COL_ACCENT
const COL_DIM := MainMenu.COL_DIM
const COL_CARD := MainMenu.COL_CARD
const COL_CARD_HOVER := MainMenu.COL_CARD_HOVER

# The preview is REAL: a PlayerMarker in a small 3D scene, angled like the
# game's own trailing camera. A flat 2D icon per shape would be a second drawing
# of the same outline to keep in step with the table -- and worse, it would be
# the wrong question. What the player is choosing is how a silhouette reads from
# behind at a shallow angle, which a face-on icon cannot show.
# Shortened from 200 to 156. The turntable sat in visible dead space top and
# bottom -- the marker lies flat on the floor and the camera looks DOWN at it,
# so the box was taller than the silhouette ever filled. The height it gives up
# goes to the choice list, which is the part that was actually short of room.
# Width is unchanged: the shapes are longer along their facing axis than across
# it, so it is the HEIGHT that was surplus.
const PREVIEW_SIZE := Vector2i(320, 156)

# Close enough to the game's trailing camera that the preview answers the
# question actually being asked. Not derived from Tuning.CAM_*: those are tuned
# against a corridor the player is driving down, and this is a turntable with no
# maze around it.
# Tuned against rendered frames, not calculated. The first pass sat at (0, 1.35,
# 2.3) with a 45 degree lens, which drew the marker as a speck high in an
# otherwise empty box -- the arithmetic said it should fill 65% of the frame and
# it did not, because the aim point and the box's centre are not the same thing
# once the camera looks DOWN at a shape lying on the floor.
const PREVIEW_EYE := Vector3(0.0, 0.72, 1.15)
const PREVIEW_LOOK := Vector3(0.0, 0.0, -0.08)

# Narrower than the game's own lens. The corridor camera is wide because it has
# a corridor to show; this has one object, and a wide lens spends most of the
# box on the empty floor around it.
const PREVIEW_FOV := 38.0

# The panel's UPPER BOUND, never its height.
#
# A PanelContainer sizes to its CONTENTS and ignores an offset smaller than they
# need -- the section 8c overrun, which this screen hit for the fourth time in
# the codebase. Measured: three tables (8 shapes, 8 decals, 19 colours twice)
# stack to 1054px against the 830 declared here, so the card laid out at 1054
# whatever this said and ran 189px off the bottom of a 900-tall viewport. The
# PATTERN COLOUR swatches and CLOSE were simply not on screen.
#
# The fix is the compendium's: clamp the box to a share of the viewport, then
# derive the SCROLLING region's height from that box minus a measured fixed
# cost. Raising this number ALONE would be the same trap one step along --
# correct for today's three tables and overflowing on the next cosmetic added.
#
# It is raised here anyway, to the height the three tables actually need (1054
# measured), because as an upper BOUND it now costs nothing: the viewport clamp
# below is what keeps the card on screen, and capping at 830 only denied a tall
# display the chance to show every table at once. A short one still scrolls.
const PANEL_SIZE := Vector2(760, 1054)

# What the card spends on everything that is NOT the scrolling choice list:
# the MARKER heading, the preview, the state and name labels, the CLOSE button,
# the row separations between them and the card's own content margins.
#
# MEASURED off the live layout, not estimated -- the settings card's note records
# an estimated fixed cost laying out 107px over its computed height. Broken down:
# heading 42, preview 156, state 20, name 34, CLOSE 46, five separations 60,
# card margins 48.
const PANEL_FIXED_COST := 406.0

# The floor on the scrolling region. Below about this the list shows under two
# rows of shape buttons and scrolling stops being navigation and starts being a
# keyhole -- at which point the screen is worse than one that merely overflows.
const LIST_MIN_HEIGHT := 220.0

# How much of a short viewport's height the card may take.
#
# 0.94 rather than a tighter number because this screen is a full-screen modal
# over a scrim -- there is nothing behind it that needs to stay legible, unlike
# the settings card, which is lifted off centre so the menu title still reads.
# What the margin is for is the scrim reading as a border rather than the card
# meeting the screen edge.
const PANEL_VIEW_SHARE := 0.94

# Blank space after the last swatch row, so it can scroll fully clear of the
# boundary instead of being sliced by it.
const LIST_TAIL_PAD := 14.0

# The colours offered as swatches.
#
# A PALETTE rather than a full RGB wheel, and that is a usability choice rather
# than a restriction: the wheel's useful answers are a dozen saturated hues, and
# a grid of them is one press where a wheel is a drag. NEAR-WHITE leads, because
# it is what the marker was before this choice existed and a player must be able
# to get back to it in one press (section 12 refused a colour picker over
# exactly the visibility this row can cost).
#
# The maze palettes are deliberately NOT excluded. Section 12's objection is
# real -- green in maze 3 is hard to see -- but the free choice is what was
# asked for, and hiding the colours that make it visible would be pretending to
# offer a choice while quietly removing its consequences. The preview shows the
# state colours instead, so the cost is visible before it is paid.
# The palette itself lives in Tuning.MARKER_COLOURS.
#
# It moved there when colours became UNLOCKABLE: Unlocks and RulesTest both read
# it, and a table living inside a screen would make the rules depend on the UI.
# It was duplicated here as a bare Array[Color] with no ids, which a tool then
# had to address by restating a literal -- MarkerPickerShot did exactly that,
# got the value wrong, and shot a white marker while reporting success.

const SWATCH_SIZE := Vector2(52, 40)

# How long the preview holds each state before moving on.
#
# The preview CYCLES resting -> scrape -> crash rather than only showing the
# resting colour. A player choosing a colour near amber or red needs to see what
# a scrape looks like BEFORE committing to it -- otherwise the picker hides the
# exact interaction the free choice put at risk, and the first time they learn
# it is mid-run with the barrier draining.
const STATE_CYCLE_SECONDS := 1.6

# How fast the preview turns. Slow enough to read the silhouette at every angle,
# fast enough that a player deciding between two shapes does not have to wait.
const SPIN_RATE := 0.7

var _viewport: SubViewport = null
var _marker: PlayerMarker = null
var _pivot: Node3D = null
var _name_label: Label = null
var _index := 0
var _buttons: Array[Button] = []
var _decal_buttons: Array[Button] = []
var _swatches: Array[Button] = []
var _swatches_2: Array[Button] = []
var _decal_index := 0
var _colour: Color = PlayerMarker.COL_ARROW
var _colour_2: Color = PlayerMarker.COL_ARROW
var _state_clock := 0.0
var _state_label: Label = null
var _preview_state: Racer = null
# Seconds left showing a locked entry's requirement. While this is running the
# state label is given over to it, because a player who just pressed a locked
# button wants to know why far more than they want the scrape demo.
var _locked_hold := 0.0
var _colour_2_label: Label = null
var _colour_2_row: Control = null

# The card's actual laid-out box, clamped to the viewport in _build_panel. Kept
# because the scrolling region's height is derived from it, and a second call to
# get_viewport_rect() could disagree with the box the card was actually built at.
var _panel_box: Vector2 = PANEL_SIZE

# The scrolling choice region, kept so _fit can re-derive its height. The card is
# built once but the viewport can change under it -- a height computed only at
# build time is correct for the window the screen happened to open on and wrong
# for every resize after, which is the stale half of the hard-coded-band trap.
var _scroll: ScrollContainer = null
var _card: PanelContainer = null
var _choices: VBoxContainer = null


func _ready() -> void:
	# Anchors and offsets together -- set_anchors_preset() alone leaves a
	# degenerate rect and every centred child lands on the origin (section 12).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the scrim has to swallow clicks aimed at the menu
	# buttons behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_index = _current_index()
	_decal_index = _current_decal_index()
	_colour = _current_colour()
	_colour_2 = _current_colour_2()
	_build_scrim()
	_build_panel()
	_show_shape()
	_fit()
	# Re-fit on resize. The card is built once, so a height derived only at build
	# time is correct for the window the screen opened on and stale for every one
	# after it -- and this screen is reachable from a menu the player may have
	# resized since launch.
	get_viewport().size_changed.connect(_fit)
	# SCROLL TO WHAT IS ALREADY CHOSEN, once the layout has resolved.
	#
	# The list opens at the top, which was invisible while the tables were short
	# and is a real defect now that the shape grid alone runs to fifteen rows: a
	# player whose marker is the last entry opened this screen with NO lit button
	# anywhere in view, which reads as the picker having forgotten their choice.
	#
	# Deferred because ensure_control_visible measures rects, and nothing has a
	# rect until the frame after the card is built -- the same "build on one
	# frame, act on the next" rule the shot tools record, arriving in the screen
	# itself rather than in an instrument.
	_scroll_to_selection.call_deferred()
	set_process(true)


# Bring the selected shape button into view, so the screen opens on the choice
# the player actually holds rather than on the top of the table.
func _scroll_to_selection() -> void:
	if _scroll == null or _index < 0 or _index >= _buttons.size():
		return
	var button: Button = _buttons[_index]
	if button == null or not is_instance_valid(button):
		return
	_scroll.ensure_control_visible(button)


# Size the card to the viewport and the scrolling region to what is left.
#
# Both halves are DERIVED. The card is clamped to a share of the viewport (a
# pixel is a count, not a size -- section 9d), and the list then takes the box
# minus the measured fixed cost, so a shorter screen shortens the LIST rather
# than pushing CLOSE off the bottom edge. Raising a literal instead would be the
# same trap one cosmetic later.
func _fit() -> void:
	if _card == null or _scroll == null:
		return
	var view := get_viewport_rect().size
	# Guarded exactly as SettingsPanel's scale is: a headless dummy reports a
	# degenerate viewport, and sizing against it produces plausible-looking
	# nonsense rather than an error.
	if view.x < 1.0 or view.y < 1.0:
		return
	var box := Vector2(minf(PANEL_SIZE.x, view.x * 0.94),
		minf(PANEL_SIZE.y, view.y * PANEL_VIEW_SHARE))
	_panel_box = box
	_card.offset_left = -box.x * 0.5
	_card.offset_right = box.x * 0.5
	_card.offset_top = -box.y * 0.5
	_card.offset_bottom = box.y * 0.5
	# The floor is applied to the LIST, and the card is then allowed to exceed
	# the box rather than the list becoming a keyhole. On a viewport too short
	# for even that, scrolling the whole card is a worse answer than a list two
	# rows deep -- but neither is reachable on any real display, so the floor is
	# a guard rather than a layout anyone sees.
	_scroll.custom_minimum_size = Vector2(0.0,
		maxf(box.y - PANEL_FIXED_COST, LIST_MIN_HEIGHT))


func _build_scrim() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.0, 0.0, 0.0, 0.86)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)


func _build_panel() -> void:
	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	# Clamped to a share of the viewport rather than taking PANEL_SIZE outright,
	# with the reasoning section 9d gives for the pads: a pixel is a count, not
	# a size, so a card fixed in viewport units is a different physical size on
	# every screen -- and on a short one it simply runs off the bottom.
	var view := get_viewport_rect().size
	var box := Vector2(minf(PANEL_SIZE.x, view.x * 0.94),
		minf(PANEL_SIZE.y, view.y * 0.92))
	_panel_box = box
	card.offset_left = -box.x * 0.5
	card.offset_right = box.x * 0.5
	card.offset_top = -box.y * 0.5
	card.offset_bottom = box.y * 0.5

	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = COL_ACCENT
	style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	_card = card

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)

	rows.add_child(_heading("MARKER", 30, COL_ACCENT))
	rows.add_child(_build_preview())

	# What the preview is currently showing. Directly under the preview and
	# ABOVE the shape name, because it describes the picture rather than the
	# grid -- placed below the name it read as a heading for the shape buttons
	# ("DRIVING" over a row of shapes), which only a rendered frame showed.
	_state_label = _heading("", 14, COL_DIM)
	rows.add_child(_state_label)

	_name_label = _heading("", 24, Color.WHITE)
	rows.add_child(_name_label)

	# The three choice tables SCROLL; everything above and CLOSE below do not.
	#
	# The heading, preview and name answer "what am I looking at" and the button
	# answers "how do I leave" -- both must stay put, which is precisely the
	# failure being fixed: CLOSE was the row that went off the bottom edge, so
	# the screen offered no visible way out. The compendium's note records the
	# mirror of this, a list that grew until it pushed its own title off the top.
	var scroll := ScrollContainer.new()
	scroll.name = "Choices"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# DERIVED from the panel box, never a literal: a shorter viewport shortens
	# the list instead of losing the rows off the end of it.
	_scroll = scroll
	rows.add_child(scroll)

	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(choices)
	_choices = choices

	choices.add_child(_label_row("SHAPE"))
	choices.add_child(_build_grid())
	choices.add_child(_label_row("PATTERN"))
	choices.add_child(_build_decal_grid())
	choices.add_child(_label_row("COLOUR"))
	choices.add_child(_build_swatches(1))
	# The second row is built always but SHOWN only when a decal is chosen: a
	# plain mark has no cuts to fill, so offering a fill colour for it would be
	# a control that changes nothing.
	_colour_2_label = _label_row("PATTERN COLOUR")
	choices.add_child(_colour_2_label)
	choices.add_child(_build_swatches(2))
	# A tail spacer, so the last swatch row can scroll clear of the edge.
	#
	# Without it the list ends exactly on its final row, and a row sliced by the
	# scroll boundary reads as a CLIPPED control rather than as more content
	# below -- which is the same misread this whole screen was reported for. The
	# spacer is what turns a cut-off row into a visible bottom of the list.
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0.0, LIST_TAIL_PAD)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices.add_child(tail)

	rows.add_child(_make_button("CLOSE", _on_close))


# The live 3D preview. It shares NO world with the game -- the menu has no maze
# running -- so this SubViewport builds its own, which is the one place that
# default is what is wanted. Contrast RearView, which must be handed the main
# world or it renders nothing but background colour.
func _build_preview() -> Control:
	_viewport = SubViewport.new()
	_viewport.name = "MarkerPreview"
	_viewport.size = PREVIEW_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.audio_listener_enable_3d = false
	# An OWN world, set explicitly. A SubViewport nested under a Control inherits
	# the parent viewport's world unless told otherwise, and the menu's world is
	# empty -- which renders as a blank panel rather than as an error. This is
	# RearView's note read in the opposite direction: that view must be HANDED
	# the game's world or it shows nothing, and this one must be denied it for
	# the same reason. Only a rendered frame showed the empty box.
	_viewport.own_world_3d = true
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.fov = PREVIEW_FOV
	camera.position = PREVIEW_EYE
	camera.current = true
	_viewport.add_child(camera)
	# look_at AFTER add_child. It works in GLOBAL space, so on a node that is not
	# yet in a tree it has no global transform to work from and silently does
	# nothing -- leaving the camera pointing down -Z from above the marker, at
	# empty space. The panel then renders as a blank box, which reads as the
	# preview being unwired rather than as the camera being aimed wrong.
	camera.look_at(PREVIEW_LOOK, Vector3.UP)

	# No light. The marker's materials are UNSHADED, so one would change nothing
	# -- and a light here would be misleading anyway, since it would make the
	# preview read differently from the marker in play.
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_viewport.add_child(_pivot)

	var display := TextureRect.new()
	display.texture = _viewport.get_texture()
	display.custom_minimum_size = Vector2(PREVIEW_SIZE)
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return display


# One button per shape, in a grid whose column count reads the table's length
# rather than assuming a row width -- the hard-coded-band trap (section 12). A
# longer table wraps instead of running off the card.
func _build_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = min(3, max(Tuning.MARKER_SHAPES.size(), 1))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)

	for i in Tuning.MARKER_SHAPES.size():
		var shape: Dictionary = Tuning.MARKER_SHAPES[i]
		var button := _make_button(String(shape["label"]), _on_pick.bind(i))
		button.custom_minimum_size = Vector2(200, 46)
		_buttons.append(button)
		grid.add_child(button)

	return grid


# One button per decal, in a grid whose column count reads the table rather than
# assuming a row width -- the same hard-coded-band reasoning _build_grid uses.
func _build_decal_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = min(5, max(Tuning.MARKER_DECALS.size(), 1))
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)

	for i in Tuning.MARKER_DECALS.size():
		var decal: Dictionary = Tuning.MARKER_DECALS[i]
		var button := _make_button(String(decal["label"]), _on_pick_decal.bind(i))
		button.custom_minimum_size = Vector2(118, 42)
		button.add_theme_font_size_override("font_size", 15)
		_decal_buttons.append(button)
		grid.add_child(button)

	return grid


# The colour swatches. Each draws its own colour as its face rather than naming
# it, because a colour name is a worse answer to "what will this look like" than
# the colour itself.
func _build_swatches(which: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = min(10, max(Tuning.MARKER_COLOURS.size(), 1))
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)

	for i in Tuning.MARKER_COLOURS.size():
		var button := Button.new()
		button.custom_minimum_size = SWATCH_SIZE
		button.focus_mode = Control.FOCUS_ALL
		button.tooltip_text = "Marker colour"
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = _swatch(i)
			style.set_corner_radius_all(6)
			style.set_border_width_all(3)
			style.border_color = Color(0.2, 0.3, 0.45)
			button.add_theme_stylebox_override(state, style)
		if which == 2:
			button.pressed.connect(_on_pick_colour_2.bind(i))
			_swatches_2.append(button)
		else:
			button.pressed.connect(_on_pick_colour.bind(i))
			_swatches.append(button)
		grid.add_child(button)

	if which == 2:
		_colour_2_row = grid
	return grid


func _label_row(text: String) -> Label:
	return _heading(text, 15, COL_DIM)


func _process(delta: float) -> void:
	# Turning the preview is what makes a silhouette decision possible: several
	# of these shapes are told apart by their outline from behind and to the
	# side, which one fixed angle cannot show.
	if _pivot != null:
		_pivot.rotate_y(delta * SPIN_RATE)

	_advance_state_preview(delta)


# Cycle the preview through resting, scraping and crashed.
#
# This is the half of the picker that answers the objection section 12 raised
# against offering colour at all. The marker turns amber on a scrape and red on
# a crash, and those only read as STATE against a resting colour that is not
# already amber or red -- so a player picking gold or coral needs to see the
# collision here rather than discover it mid-run.
#
# It drives PlayerMarker.update_state directly with a stub rather than
# duplicating the colour rules, so the preview cannot drift from what the game
# actually draws.
func _advance_state_preview(delta: float) -> void:
	if _marker == null:
		return

	# A locked message owns the label while it lasts.
	if _locked_hold > 0.0:
		_locked_hold -= delta
		return
	_state_clock = fmod(_state_clock + delta, STATE_CYCLE_SECONDS * 3.0)
	var phase := int(_state_clock / STATE_CYCLE_SECONDS)

	var racer := _preview_racer(phase)
	if racer == null:
		return
	_marker.update_state(racer, delta)

	if _state_label != null:
		match phase:
			1: _state_label.text = "SCRAPING  -  the barrier is draining"
			2: _state_label.text = "CRASHED"
			_: _state_label.text = "DRIVING"


# A racer for the preview.
#
# The picker runs on the MENU, where there is no maze and no run. A bare
# Racer.new() is not enough either: update_state reads barrier_fraction(), which
# divides by upgrades.barrier_capacity() -- so an un-setup racer takes the
# preview down on a null. It is given a real maze and a real build for that one
# reason, and is never stepped.
func _preview_racer(phase: int) -> Racer:
	# Built ONCE and mutated, not rebuilt per frame. Generating a maze every
	# frame to set three fields is the failure section 12 records for
	# GoldenTrail's ribbon: 23ms a frame for something whose inputs never
	# changed.
	if _preview_state == null:
		var racer := Racer.new()
		var maze := Maze.new()
		maze.generate(8, 8, 1, 0.0, 0.0, 4)
		racer.setup(maze, Upgrades.new(1))
		_preview_state = racer
	var r := _preview_state
	match phase:
		1:
			r.state = Racer.State.RUNNING
			r.scraping = true
			# Part-drained, so the scrape colour is mid-way between amber and
			# red -- which is what a player actually sees for most of a scrape,
			# rather than either endpoint.
			r.barrier = r.upgrades.barrier_capacity() * 0.45
		2:
			r.state = Racer.State.PARKED
			r.scraping = false
		_:
			r.state = Racer.State.RUNNING
			r.scraping = false
	return r


# --- State -------------------------------------------------------------------

# The live preference, or null outside the real project -- a harness that
# instantiates this screen bare has no autoloads. Guarded rather than assumed,
# for the reason MainMenu guards the same lookup.
func _settings() -> Node:
	return get_node_or_null("/root/Settings")


# Where the saved choice sits in the table, or the default's position when the
# stored name is unknown. Resolved through Tuning rather than compared raw, so
# a shape dropped since the file was written lands on the arrow.
func _current_index() -> int:
	var settings := _settings()
	var id: String = Tuning.MARKER_SHAPE_DEFAULT
	if settings != null:
		id = String(settings.marker_shape)
	var resolved: String = String(Tuning.marker_shape(id)["id"])
	for i in Tuning.MARKER_SHAPES.size():
		if String(Tuning.MARKER_SHAPES[i]["id"]) == resolved:
			return i
	return 0


# Where the saved decal sits in the table, resolved through Tuning so a decal
# dropped since the file was written lands on the default.
func _current_decal_index() -> int:
	var settings := _settings()
	var id: String = Tuning.MARKER_DECAL_DEFAULT
	if settings != null:
		id = String(settings.marker_decal)
	var resolved: String = String(Tuning.marker_decal(id)["id"])
	for i in Tuning.MARKER_DECALS.size():
		if String(Tuning.MARKER_DECALS[i]["id"]) == resolved:
			return i
	return 0


func _current_colour_2() -> Color:
	var settings := _settings()
	if settings != null:
		return settings.marker_colour_2
	return Tuning.marker_colour(Tuning.MARKER_COLOUR_2_DEFAULT)["colour"]


func _current_colour() -> Color:
	var settings := _settings()
	if settings != null:
		return settings.marker_colour
	return PlayerMarker.COL_ARROW


# Rebuild the preview marker for the current index.
#
# A fresh PlayerMarker rather than mutating the old one: the outline is baked
# into a mesh at build time, so changing shape means rebuilding that mesh either
# way, and a rebuilt node cannot leave a stale surface behind.
func _show_shape() -> void:
	if _pivot == null:
		return

	if _marker != null:
		# remove_child BEFORE queue_free, so the outgoing node is out of the
		# tree immediately rather than lingering until the deferred free lands
		# -- the same ordering the gate markers need (section 12).
		_pivot.remove_child(_marker)
		_marker.queue_free()
		_marker = null

	var shape: Dictionary = Tuning.MARKER_SHAPES[_index]

	_marker = PlayerMarker.new()
	# Set BEFORE add_child, deliberately: _ready builds the mesh on entry to the
	# tree, so a shape assigned afterwards arrives one build too late and the
	# preview shows the previous pick. This is also why the field is public --
	# the preview must not have to write the player's saved preference in order
	# to show them a shape (section 12: a tool must not write the state it is
	# inspecting).
	_marker.shape_id = String(shape["id"])
	_marker.decal_id = String(Tuning.MARKER_DECALS[_decal_index]["id"])
	_marker.player_colour = _colour
	_marker.player_colour_2 = _colour_2
	_pivot.add_child(_marker)

	if _name_label != null:
		_name_label.text = String(shape["label"])

	_refresh_buttons()


# The chosen shape's button carries the accent, so the grid says which one is
# live rather than leaving that to the label above it alone.
func _refresh_buttons() -> void:
	for i in _buttons.size():
		_mark_selected(_buttons[i], i == _index, _shape_locked(i))

	for i in _decal_buttons.size():
		_mark_selected(_decal_buttons[i], i == _decal_index, _decal_locked(i))

	# The pattern row is only meaningful once there are cuts to fill.
	var has_decal: bool = String(Tuning.MARKER_DECALS[_decal_index]["id"]) 		!= Tuning.MARKER_DECAL_DEFAULT
	if _colour_2_label != null:
		_colour_2_label.visible = has_decal
	if _colour_2_row != null:
		_colour_2_row.visible = has_decal

	for i in _swatches_2.size():
		var lit2: bool = _swatch(i).is_equal_approx(_colour_2)
		var locked2: bool = _colour_locked(i)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var st2 := _swatches_2[i].get_theme_stylebox(state) as StyleBoxFlat
			if st2 == null:
				continue
			if locked2:
				st2.bg_color = Color(0.05, 0.06, 0.09)
				st2.border_color = _swatch(i).darkened(0.45)
			else:
				st2.bg_color = _swatch(i)
				st2.border_color = Color.WHITE if lit2 					else Color(0.2, 0.3, 0.45)

	# The live swatch is marked by its BORDER, never by its fill -- the fill is
	# the colour being offered, so changing it would misreport the choice.
	for i in _swatches.size():
		var slit: bool = _swatch(i).is_equal_approx(_colour)
		var slocked: bool = _colour_locked(i)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sstyle := _swatches[i].get_theme_stylebox(state) as StyleBoxFlat
			if sstyle == null:
				continue
			if slocked:
				# A dark face with the colour as its OUTLINE: the goal is
				# visible without the swatch reading as available.
				sstyle.bg_color = Color(0.05, 0.06, 0.09)
				sstyle.border_color = _swatch(i).darkened(0.45)
			else:
				sstyle.bg_color = _swatch(i)
				sstyle.border_color = Color.WHITE if slit 					else Color(0.2, 0.3, 0.45)


# Mark a button as the live choice, across EVERY state.
#
# Refreshing only the "normal" stylebox is not enough, and a rendered frame is
# what showed it: focus_first() grabs focus on the saved choice, and a focused
# button draws its FOCUS stylebox -- so after picking a different shape, two
# buttons were lit at once and the panel reported two selections. Selection and
# focus are different things and must not share one signal.
#
# Selected keeps the accent border in every state; unselected is dim in its
# resting states and still brightens on hover and focus, so keyboard navigation
# stays visible without claiming to be a choice.
func _mark_selected(button: Button, selected: bool,
		locked: bool = false) -> void:
	# Locked entries are SHOWN, dimmed, rather than hidden -- the picker is a
	# goal list, and a hidden entry gives the player nothing to aim at. The
	# label stays legible because it names the thing being worked toward.
	button.add_theme_color_override("font_color",
		Color(0.42, 0.47, 0.58) if locked else COL_DIM)
	if locked:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var s2 := button.get_theme_stylebox(state) as StyleBoxFlat
			if s2 != null:
				s2.border_color = Color(0.18, 0.22, 0.30)
				s2.bg_color = Color(0.04, 0.05, 0.08)
		return

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		if style == null:
			continue
		var interactive: bool = state in ["hover", "focus", "pressed"]
		if selected:
			style.border_color = COL_ACCENT
			style.bg_color = COL_CARD_HOVER
		else:
			# A NEUTRAL focus ring, not a dimmer accent. Darkening the accent
			# was measured against a rendered frame and still read as a second
			# selection -- the eye separates hues far more readily than it
			# separates two values of one hue, so a focused-but-unchosen button
			# in dim cyan beside a chosen one in bright cyan reports two
			# choices. Focus says "you are here"; the accent says "this is your
			# marker", and they must not share a colour.
			style.border_color = Color(0.55, 0.62, 0.75) if interactive 				else Color(0.2, 0.3, 0.45)
			style.bg_color = COL_CARD_HOVER if interactive else COL_CARD


# --- Widgets -----------------------------------------------------------------

func _heading(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
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


# The colour a swatch offers.
func _swatch(index: int) -> Color:
	return Tuning.MARKER_COLOURS[index]["colour"]


# Has the player earned this cosmetic?
#
# Guarded on the autoload, like every Settings read here: a harness that builds
# this screen bare has none, and everything must be OFFERED in that case rather
# than locked -- a missing autoload must never be what stops a tool or a test
# selecting a shape.
func _unlocked(id: String) -> bool:
	var node := get_node_or_null("/root/Unlocks")
	if node == null:
		return true
	return node.is_unlocked(id)


func _shape_locked(index: int) -> bool:
	return not _unlocked(UnlocksScript.id_for(UnlocksScript.KIND_SHAPE,
		String(Tuning.MARKER_SHAPES[index]["id"])))


func _decal_locked(index: int) -> bool:
	return not _unlocked(UnlocksScript.id_for(UnlocksScript.KIND_DECAL,
		String(Tuning.MARKER_DECALS[index]["id"])))


func _colour_locked(index: int) -> bool:
	return not _unlocked(UnlocksScript.id_for(UnlocksScript.KIND_COLOUR,
		String(Tuning.MARKER_COLOURS[index]["id"])))


# What a locked entry asks for, printed under the preview.
#
# Only for the entry the player is ON, not on every locked button at once:
# eighteen requirement lines would not fit the card, and the one being
# considered is the one worth reading.
func _requirement_for(id: String) -> String:
	var entry: Dictionary = UnlocksScript.achievement_for(id)
	if entry.is_empty():
		return ""
	return "LOCKED  -  %s" % String(entry.get("requirement", ""))


# --- Handlers ----------------------------------------------------------------

# Picking writes immediately rather than on close. There is nothing destructive
# to confirm and nothing to lose, and an unsaved state would need an APPLY
# button plus a discard path for a purely cosmetic choice.
func _on_pick(index: int) -> void:
	if index < 0 or index >= Tuning.MARKER_SHAPES.size():
		return
	# Refused HERE rather than by disabling the button, because a disabled
	# button is not the only route in: the picker also restores a SAVED choice
	# on open, and a save naming a since-locked item must land on the default
	# rather than on something unearned.
	if _shape_locked(index):
		_show_locked(UnlocksScript.id_for(UnlocksScript.KIND_SHAPE,
			String(Tuning.MARKER_SHAPES[index]["id"])))
		return
	_index = index
	_show_shape()
	var settings := _settings()
	if settings != null:
		settings.set_marker_shape(String(Tuning.MARKER_SHAPES[index]["id"]))


func _on_pick_decal(index: int) -> void:
	if index < 0 or index >= Tuning.MARKER_DECALS.size():
		return
	if _decal_locked(index):
		_show_locked(UnlocksScript.id_for(UnlocksScript.KIND_DECAL,
			String(Tuning.MARKER_DECALS[index]["id"])))
		return
	_decal_index = index
	# Rebuilt rather than mutated, for the reason a shape change is: the decal
	# is baked into a mesh at build time.
	_show_shape()
	var settings := _settings()
	if settings != null:
		settings.set_marker_decal(String(Tuning.MARKER_DECALS[index]["id"]))


func _on_pick_colour_2(index: int) -> void:
	if index < 0 or index >= Tuning.MARKER_COLOURS.size():
		return
	if _colour_locked(index):
		_show_locked(UnlocksScript.id_for(UnlocksScript.KIND_COLOUR,
			String(Tuning.MARKER_COLOURS[index]["id"])))
		return
	_colour_2 = _swatch(index)
	_show_shape()
	var settings := _settings()
	if settings != null:
		settings.set_marker_colour_2(_colour_2)


func _on_pick_colour(index: int) -> void:
	if index < 0 or index >= Tuning.MARKER_COLOURS.size():
		return
	if _colour_locked(index):
		_show_locked(UnlocksScript.id_for(UnlocksScript.KIND_COLOUR,
			String(Tuning.MARKER_COLOURS[index]["id"])))
		return
	_colour = _swatch(index)
	_show_shape()
	var settings := _settings()
	if settings != null:
		settings.set_marker_colour(_colour)


# Tell the player why a press did nothing.
#
# A locked button that simply ignores the press reads as a broken button, which
# is worse than a locked one -- the whole point of showing locked entries is
# that they are goals rather than absences.
func _show_locked(id: String) -> void:
	if _state_label == null:
		return
	_state_label.text = _requirement_for(id)
	_state_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	_locked_hold = 2.5


func _on_close() -> void:
	emit_signal("closed")


# ESC closes the picker, matching what ESC does everywhere else in the game.
# Marked handled so the same press cannot also reach whatever is underneath.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		_on_close()


# Focus the live shape's button, so a keyboard or gamepad player lands on the
# one they already have rather than at the top of the grid.
func focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[_index].grab_focus()
