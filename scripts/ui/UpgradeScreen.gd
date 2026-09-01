# The gate upgrade picker: three cards, timer paused, world still visible.
#
# The world stays rendered behind the cards deliberately (CLAUDE.md section 7):
# the player sees exactly as much of the corridor as they did when they passed
# the gate. It is not scouting, it is just not blacking out the screen. The
# minimap, by contrast, gets blurred -- that one WOULD be scouting.
class_name UpgradeScreen
extends Control

signal upgrade_chosen(line: int)

const COL_CARD := Color(0.07, 0.10, 0.16, 0.96)
const COL_CARD_HOVER := Color(0.12, 0.20, 0.32, 0.98)
const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.6, 0.68, 0.8)

const CARD_SIZE := Vector2(320, 250)
const CARD_SEPARATION := 26.0

var _cards: Array[Button] = []
var _lines: Array[int] = []


func _ready() -> void:
	# set_anchors_preset() rewrites the anchors but leaves the offsets at zero,
	# which gave this Control a degenerate rect and hung the whole card block off
	# the top-left corner. Set anchors and offsets together.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	# Only the cards should eat clicks; the rest of the screen stays inert so
	# the world behind reads as a live scene rather than a modal blocker.
	mouse_filter = Control.MOUSE_FILTER_STOP


func present(upgrades: Upgrades, gate_index: int) -> void:
	_present("GATE %d  -  CHOOSE AN UPGRADE" % gate_index, upgrades)


# The maze-start loadout pick (CLAUDE.md section 7). Identical machinery to a
# gate pick -- same cards, same keys, same signal -- with a title that names the
# maze instead of a gate number, so the player can tell the two moments apart
# without having to learn a second interface.
func present_loadout(upgrades: Upgrades, maze_index: int) -> void:
	var maze_name := String(Tuning.MAZES[maze_index]["name"]).to_upper()
	_present("%s  -  CHOOSE YOUR LOADOUT" % maze_name, upgrades)


func _present(title_text: String, upgrades: Upgrades) -> void:
	_clear()

	_lines = upgrades.roll_cards()
	if _lines.is_empty():
		# Everything is maxed -- nothing to offer, so do not stall the run.
		emit_signal("upgrade_chosen", -1)
		return

	# Dim only the lower part of the screen, leaving the corridor ahead visible.
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.01, 0.02, 0.04, 0.55)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.5
	title.anchor_bottom = 0.5
	title.offset_top = -CARD_SIZE.y * 0.5 - 96
	title.offset_bottom = -CARD_SIZE.y * 0.5 - 56
	title.offset_left = -450
	title.offset_right = 450
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var hint := Label.new()
	hint.text = "press 1, 2 or 3"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", COL_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 0.5
	hint.anchor_bottom = 0.5
	hint.offset_top = -CARD_SIZE.y * 0.5 - 50
	hint.offset_bottom = -CARD_SIZE.y * 0.5 - 24
	hint.offset_left = -450
	hint.offset_right = 450
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	# Centre the row on the screen centre in both axes. The card width is known
	# (CARD_SIZE.x each, plus separation), so the band is derived rather than
	# hard-coded -- a hard-coded 1020px band centred three 320px cards only by
	# coincidence, and drifted the moment the count or the card size changed.
	var count := _lines.size()
	var row_width := count * CARD_SIZE.x + maxf(count - 1, 0) * CARD_SEPARATION

	var row := HBoxContainer.new()
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 0.5
	row.anchor_bottom = 0.5
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(CARD_SEPARATION))
	row.offset_left = -row_width * 0.5
	row.offset_right = row_width * 0.5
	row.offset_top = -CARD_SIZE.y * 0.5
	row.offset_bottom = CARD_SIZE.y * 0.5
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	for i in count:
		var card := _make_card(upgrades, _lines[i], i)
		_cards.append(card)
		row.add_child(card)

	visible = true
	if not _cards.is_empty():
		_cards[0].grab_focus()


func _make_card(upgrades: Upgrades, line: int, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_ALL

	var current := upgrades.rank(line)
	var max_rank := int(Upgrades.DEFINITIONS[line]["max_rank"])

	button.text = "%d.  %s\n\nRANK %d / %d\n\n%s" % [
		index + 1,
		upgrades.line_name(line).to_upper(),
		current + 1,
		max_rank,
		upgrades.next_rank_description(line),
	]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", COL_ACCENT)
	button.add_theme_color_override("font_focus_color", COL_ACCENT)

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = COL_CARD_HOVER if state in ["hover", "focus", "pressed"] else COL_CARD
		style.set_corner_radius_all(10)
		style.set_border_width_all(2)
		style.border_color = COL_ACCENT if state in ["hover", "focus", "pressed"] \
			else Color(0.2, 0.3, 0.45)
		style.set_content_margin_all(18)
		button.add_theme_stylebox_override(state, style)

	button.pressed.connect(_on_card_pressed.bind(line))
	return button


func _on_card_pressed(line: int) -> void:
	dismiss()
	emit_signal("upgrade_chosen", line)


# Take the cards down without choosing.
#
# Visibility used to be cleared ONLY on a card press, so any other route out of
# the pick left the screen rendering over live gameplay -- the cards are a
# Control that knows nothing about the phase machine, so nothing else was going
# to hide them. Anything that ends a pick calls this.
func dismiss() -> void:
	visible = false
	_clear()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var key := (event as InputEventKey).keycode
	var index := -1
	match key:
		KEY_1, KEY_KP_1: index = 0
		KEY_2, KEY_KP_2: index = 1
		KEY_3, KEY_KP_3: index = 2

	if index >= 0 and index < _lines.size():
		get_viewport().set_input_as_handled()
		_on_card_pressed(_lines[index])


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()
