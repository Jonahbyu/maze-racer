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
const PREVIEW_SIZE := Vector2i(320, 200)

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

const PANEL_SIZE := Vector2(720, 620)

# How fast the preview turns. Slow enough to read the silhouette at every angle,
# fast enough that a player deciding between two shapes does not have to wait.
const SPIN_RATE := 0.7

var _viewport: SubViewport = null
var _marker: PlayerMarker = null
var _pivot: Node3D = null
var _name_label: Label = null
var _index := 0
var _buttons: Array[Button] = []


func _ready() -> void:
	# Anchors and offsets together -- set_anchors_preset() alone leaves a
	# degenerate rect and every centred child lands on the origin (section 12).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the scrim has to swallow clicks aimed at the menu
	# buttons behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_index = _current_index()
	_build_scrim()
	_build_panel()
	_show_shape()
	set_process(true)


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
	card.offset_left = -PANEL_SIZE.x * 0.5
	card.offset_right = PANEL_SIZE.x * 0.5
	card.offset_top = -PANEL_SIZE.y * 0.5
	card.offset_bottom = PANEL_SIZE.y * 0.5

	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = COL_ACCENT
	style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)

	rows.add_child(_heading("MARKER", 30, COL_ACCENT))
	rows.add_child(_build_preview())

	_name_label = _heading("", 24, Color.WHITE)
	rows.add_child(_name_label)

	rows.add_child(_build_grid())
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


func _process(delta: float) -> void:
	# Turning the preview is what makes a silhouette decision possible: several
	# of these shapes are told apart by their outline from behind and to the
	# side, which one fixed angle cannot show.
	if _pivot != null:
		_pivot.rotate_y(delta * SPIN_RATE)


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
	_pivot.add_child(_marker)

	if _name_label != null:
		_name_label.text = String(shape["label"])

	_refresh_buttons()


# The chosen shape's button carries the accent, so the grid says which one is
# live rather than leaving that to the label above it alone.
func _refresh_buttons() -> void:
	for i in _buttons.size():
		var lit: bool = i == _index
		var button: Button = _buttons[i]
		var style := button.get_theme_stylebox("normal") as StyleBoxFlat
		if style == null:
			continue
		style.border_color = COL_ACCENT if lit else Color(0.2, 0.3, 0.45)
		style.bg_color = COL_CARD_HOVER if lit else COL_CARD


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


# --- Handlers ----------------------------------------------------------------

# Picking writes immediately rather than on close. There is nothing destructive
# to confirm and nothing to lose, and an unsaved state would need an APPLY
# button plus a discard path for a purely cosmetic choice.
func _on_pick(index: int) -> void:
	if index < 0 or index >= Tuning.MARKER_SHAPES.size():
		return
	_index = index
	_show_shape()
	var settings := _settings()
	if settings != null:
		settings.set_marker_shape(String(Tuning.MARKER_SHAPES[index]["id"]))


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
