# Assign a colourway to each maze.
#
# WHOLE PALETTES, never a single hue. A palette is six interlocking colours --
# wall, grid, floor, ambient, fog, emission -- and CLAUDE.md section 8 records
# two separate bugs from getting that mix wrong: maze 3's green ambient lighting
# every wall face in its own neon, and ember's yellow grid driving ambient warm
# until every wall turned milky brown with the floor grid washed out against it.
#
# Both came from DERIVING the rest of the palette from one colour, which is
# exactly what a per-hue picker would have to do. Every entry offered here is a
# palette authored and tuned as a set, so no assignment a player can make can
# reproduce either failure. That is the whole reason this screen assigns rather
# than mixes.
#
# Nothing in the simulation may read the choice: Game resolves it once when a
# maze is built and the rules never see it. Same separation landmarks (section
# 6), music (9c) and the marker picker have.
class_name MazeColours
extends Control

signal closed()

const UnlocksScript := preload("res://scripts/core/Unlocks.gd")

const COL_ACCENT := MainMenu.COL_ACCENT
const COL_DIM := MainMenu.COL_DIM
const COL_CARD := MainMenu.COL_CARD
const COL_CARD_HOVER := MainMenu.COL_CARD_HOVER

const PANEL_SIZE := Vector2(1420, 900)
# A swatch strip per maze, showing the palette rather than naming it: a colour
# name is a worse answer to "what will this look like" than the colour itself.
const CHIP_SIZE := Vector2(92, 27)

# How many chips fit across before the row wraps.
#
# DERIVED from the panel width rather than fixed, because the count is not: the
# table grew from 5 palettes to 25, and a single row that fitted five ran the
# panel clean off the screen edge -- taking the heading and both buttons with
# it. That is the hard-coded-band trap section 12 records for the card row and
# the summary panel, arriving through a table that got longer.
#
# A maze's own five come FIRST in the table, so the first row of every strip is
# always the authored colourways.
const CHIP_COLUMNS := 13

var _rows: Array = []
var _hint: Label = null
var _hint_hold := 0.0


func _ready() -> void:
	# Anchors and offsets together -- set_anchors_preset() alone leaves a
	# degenerate rect and every centred child lands on the origin (section 12).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.0, 0.0, 0.0, 0.86)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_build_panel()
	set_process(true)
	_refresh()


func _build_panel() -> void:
	var card := PanelContainer.new()
	card.name = "Panel"
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	var view := get_viewport_rect().size
	var box := Vector2(minf(PANEL_SIZE.x, view.x * 0.94),
		minf(PANEL_SIZE.y, view.y * 0.92))
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

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	card.add_child(rows)

	rows.add_child(_heading("MAZE COLOURS", 26, COL_ACCENT))
	# "by reaching them" was true when every palette was a maze-progress
	# reward. Most are not: they are spread across score, speed, cornering,
	# scraping, build width and failure, so a line naming one route would send
	# the player at the wrong one. A locked chip states its OWN requirement when
	# pressed, which is the only place that can be accurate.
	rows.add_child(_heading(
		"Pick a colourway for each maze. Press a locked one to see what earns it.",
		13, COL_DIM))

	_hint = _heading("", 14, Color(1.0, 0.72, 0.25))
	rows.add_child(_hint)

	for slot in Tuning.MAZES.size():
		rows.add_child(_build_row(slot))

		# Side by side rather than stacked: two full-width buttons cost two rows of
	# height, and the chip grid has already spent nearly all of it. The panel
	# overran the screen edge and clipped CLOSE outright when they were stacked
	# -- the section 8c overrun, arriving through a table that grew.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var reset := _make_button("RESET TO DEFAULTS", _on_reset)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := _make_button("CLOSE", _on_close)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(reset)
	buttons.add_child(close)
	rows.add_child(buttons)


# One maze, with a chip per palette.
func _build_row(slot: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var name := String(Tuning.MAZES[slot].get("name", "MAZE %d" % (slot + 1)))
	var label := _heading("%d.  %s" % [slot + 1, name.to_upper()], 15, COL_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(label)

	# A GRID, not a row: 25 chips do not fit a screen in one line.
	var strip := GridContainer.new()
	strip.columns = CHIP_COLUMNS
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 4)
	col.add_child(strip)

	var chips: Array = []
	for i in Tuning.PALETTES.size():
		var chip := Button.new()
		chip.custom_minimum_size = CHIP_SIZE
		chip.focus_mode = Control.FOCUS_ALL
		chip.text = String(Tuning.PALETTES[i].get("label", ""))
		chip.add_theme_font_size_override("font_size", 10)
		chip.pressed.connect(_on_pick.bind(slot, i))
		strip.add_child(chip)
		chips.append(chip)

	_rows.append({"slot": slot, "chips": chips})
	return col


func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _unlocked(id: String) -> bool:
	var node := get_node_or_null("/root/Unlocks")
	if node == null:
		return true
	return node.is_unlocked(id)


func _palette_locked(index: int) -> bool:
	return not _unlocked(UnlocksScript.id_for(UnlocksScript.KIND_PALETTE,
		String(Tuning.PALETTES[index].get("id", ""))))


# Paint every chip: its palette's own colours, dimmed when locked, outlined when
# it is the one this maze is using.
func _refresh() -> void:
	var settings := _settings()
	for row in _rows:
		var slot: int = row["slot"]
		var live := Tuning.default_palette_id(slot)
		if settings != null:
			live = String(settings.palette_for_maze(slot))
		var chips: Array = row["chips"]
		for i in chips.size():
			var chip: Button = chips[i]
			var entry: Dictionary = Tuning.PALETTES[i]
			var locked := _palette_locked(i)
			var lit: bool = String(entry.get("id", "")) == live
			chip.add_theme_color_override("font_color",
				Color(0.30, 0.34, 0.42) if locked else Color.WHITE)
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				var style := StyleBoxFlat.new()
				# The chip IS the palette: its wall colour as the face and its
				# floor as the ground, so the strip previews the maze rather
				# than naming it.
				if locked:
					style.bg_color = Color(0.05, 0.06, 0.09)
					style.border_color = Color(entry["wall"]).darkened(0.55)
				else:
					style.bg_color = Color(entry["floor"]).lightened(0.10)
					style.border_color = Color.WHITE if lit \
						else Color(entry["wall"]).darkened(0.25)
				style.set_corner_radius_all(6)
				style.set_border_width_all(3 if lit else 2)
				style.set_content_margin_all(4)
				chip.add_theme_stylebox_override(state, style)


func _process(delta: float) -> void:
	if _hint_hold > 0.0:
		_hint_hold -= delta
		if _hint_hold <= 0.0 and _hint != null:
			_hint.text = ""


func _say(text: String) -> void:
	if _hint == null:
		return
	_hint.text = text
	_hint_hold = 2.5


func _on_pick(slot: int, index: int) -> void:
	if _palette_locked(index):
		# A locked chip that silently ignores the press reads as a broken
		# button, which is worse than one that reads as locked.
		var entry: Dictionary = UnlocksScript.achievement_for(
			UnlocksScript.id_for(UnlocksScript.KIND_PALETTE,
				String(Tuning.PALETTES[index].get("id", ""))))
		_say("LOCKED  -  %s" % String(entry.get("requirement", "")))
		return
	var settings := _settings()
	if settings != null:
		settings.set_maze_palette(slot,
			String(Tuning.PALETTES[index].get("id", "")))
	_refresh()


func _on_reset() -> void:
	var settings := _settings()
	if settings != null:
		for slot in Tuning.MAZES.size():
			settings.set_maze_palette(slot, "")
	_refresh()
	_say("Restored every maze to its own colourway.")


func _on_close() -> void:
	closed.emit()


func _heading(text: String, size_px: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 18)
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
		style.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(handler)
	return button


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		_on_close()


func focus_first() -> void:
	if not _rows.is_empty():
		var chips: Array = _rows[0]["chips"]
		if not chips.is_empty():
			chips[0].grab_focus()
