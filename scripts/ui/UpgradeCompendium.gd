# The upgrade compendium: every line in the game, with a diagram of what it does.
#
# Built on MarkerPicker's shape -- a full-screen Control the menu adds and frees,
# reporting through `closed`. It owns no state: the list is read live from
# Upgrades.DEFINITIONS and the numbers from a real Upgrades taken to each rank,
# so this screen can never advertise a mechanic the game does not have. That is
# the rule that made Fast Turnaround's card text derived rather than written
# (CLAUDE.md section 7), applied to a screen the player browses at leisure.
#
# The demo lives in a BUBBLE beside the focused row rather than in a fixed pane.
# The list is the subject here -- a player deciding between Cornering and Snap
# Turn wants both names in view -- and a pane would spend half the screen
# permanently on one of them. Being transient, the bubble can also be LARGER
# than a pane could afford, so the diagram gets more room rather than less.
#
# Nothing in the simulation may read this. Same separation landmarks (section 6),
# music (9c), touch controls (9d) and the marker picker have.
class_name UpgradeCompendium
extends Control

signal closed()

const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.55, 0.62, 0.75)
const COL_SCRIM := Color(0.02, 0.02, 0.05, 0.88)
const COL_LEGENDARY := Color(0.95, 0.75, 0.25)

const PANEL_SIZE := Vector2(1240, 720)
const LIST_WIDTH := 330.0
const ROW_HEIGHT := 38.0

# What the panel spends above the list: the heading, the hint, the separations
# and the panel's own content margins. Measured against the built panel rather
# than estimated -- the same discipline section 9d records for the settings
# card's fixed cost.
const HEADER_HEIGHT := 120.0

# The bubble. Wide enough for a six-cell corridor demo to read, tall enough for
# the diagram plus its caption and the per-rank list.
const BUBBLE_SIZE := Vector2(620, 460)

# The demo's share of the bubble.
#
# Measured rather than guessed: at 0.40 the box came out 152px tall against a
# 438px bubble, because the caption and a seven-rank list take the rest and a
# VBox gives a minimum-sized child exactly its minimum. A 6-cell corridor in
# 152px draws a 52px cell, which is a strip rather than a diagram.
const DEMO_HEIGHT := 210.0

# A gap rather than an overlap: a bubble drawn over the row it explains hides
# the thing being asked about.
const BUBBLE_GAP := 20.0

var _rows: Array[Button] = []
var _bubble: PanelContainer = null
var _demo: UpgradeDemo = null
var _title: Label = null
var _ranks: Label = null
var _caption: Label = null
var _detail: RichTextLabel = null
var _panel: PanelContainer = null
var _selected := -1
# Ordinary lines first, legendaries last. Read from DEFINITIONS rather than
# listed here, so a new line needs no edit.
var _lines: Array[int] = []


func _ready() -> void:
	# Anchors and offsets together -- set_anchors_preset() alone leaves a
	# degenerate rect and every centred child lands on the origin (section 12).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the scrim has to swallow clicks aimed at the menu
	# buttons behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = COL_SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_build_line_order()
	_build_panel()
	# Built AFTER the panel so it draws on top of the list rather than under it.
	_build_bubble()
	if not _rows.is_empty():
		_select(0)


func _build_line_order() -> void:
	var ordinary: Array[int] = []
	var legendary: Array[int] = []
	var probe := Upgrades.new(1)
	for line in Upgrades.DEFINITIONS:
		if probe.is_legendary(line):
			legendary.append(int(line))
		else:
			ordinary.append(int(line))
	_lines = ordinary
	_lines.append_array(legendary)


func _panel_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = COL_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	return style


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	# Sized against the viewport with the reasoning section 9d gives for the
	# pads: a pixel is a count, not a size, so a panel fixed in viewport units
	# is a different physical size on every screen.
	var view := get_viewport_rect().size
	var box := Vector2(minf(PANEL_SIZE.x, view.x * 0.94),
		minf(PANEL_SIZE.y, view.y * 0.92))
	panel.offset_left = -box.x * 0.5
	panel.offset_right = box.x * 0.5
	panel.offset_top = -box.y * 0.5
	panel.offset_bottom = box.y * 0.5
	panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.05, 0.07, 0.11, 0.97)))
	add_child(panel)
	_panel = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	col.add_child(_label("UPGRADES", 28, COL_ACCENT))
	col.add_child(_label("Browse with UP and DOWN.    ESC to close.", 13,
		COL_DIM))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The list gets a FIXED height, not merely a minimum width.
	#
	# A PanelContainer sizes to its CONTENTS and ignores an offset smaller than
	# they need (the section 8c overrun). With an unbounded scroll list of 28
	# rows the VBox grew past the panel and pushed the heading clean off the top
	# -- a rendered frame showed a panel with a list in it and no title at all.
	#
	# Derived from the panel box rather than a literal: the heading, the hint and
	# the margins are what is left over, so a shorter panel shortens the list
	# instead of losing the title.
	scroll.custom_minimum_size = Vector2(LIST_WIDTH,
		maxf(box.y - HEADER_HEIGHT, ROW_HEIGHT * 4.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	scroll.add_child(list)

	var probe := Upgrades.new(1)
	for i in range(_lines.size()):
		var line := _lines[i]
		var row := Button.new()
		var max_rank := int(Upgrades.DEFINITIONS[line]["max_rank"])
		# The rank count sits on the row, so the list is worth reading before
		# any bubble opens -- otherwise the screen says nothing until hovered.
		row.text = "%s      %d" % [
			String(Upgrades.DEFINITIONS[line]["name"]), max_rank]
		row.custom_minimum_size = Vector2(LIST_WIDTH, ROW_HEIGHT)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_ALL
		row.add_theme_font_size_override("font_size", 15)
		var accent := COL_LEGENDARY if probe.is_legendary(line) else COL_ACCENT
		row.add_theme_color_override("font_color", COL_DIM)
		row.add_theme_color_override("font_hover_color", accent)
		row.add_theme_color_override("font_focus_color", accent)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			var lit: bool = state in ["hover", "focus", "pressed"]
			style.bg_color = Color(0.10, 0.16, 0.24) if lit \
				else Color(0.06, 0.08, 0.13)
			style.set_corner_radius_all(5)
			style.set_content_margin_all(7)
			row.add_theme_stylebox_override(state, style)
		# Hover AND focus both open the bubble, so a mouse and a keyboard reach
		# it the same way. No dedicated (i) target: that would be a second focus
		# stop on every row, and a glyph control is the tofu-box failure section
		# 9d records for the settings cog.
		row.pressed.connect(_select.bind(i))
		row.focus_entered.connect(_select.bind(i))
		row.mouse_entered.connect(_select.bind(i))
		list.add_child(row)
		_rows.append(row)


func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.custom_minimum_size = BUBBLE_SIZE
	# Never a mouse target: the bubble follows the pointer's row, so one that
	# ate hover events would fight the list it is describing.
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_theme_stylebox_override("panel",
		_panel_style(Color(0.07, 0.10, 0.16, 0.99)))
	add_child(_bubble)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	_bubble.add_child(col)

	_title = _label("", 22, COL_ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_title)

	_ranks = _label("", 13, COL_DIM)
	_ranks.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_ranks)

	_demo = UpgradeDemo.new()
	_demo.name = "Demo"
	_demo.custom_minimum_size = Vector2(0.0, DEMO_HEIGHT)
	_demo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_demo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_demo)

	_caption = _label("", 14, Color(0.85, 0.9, 0.96))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(BUBBLE_SIZE.x - 40.0, 0.0)
	col.add_child(_caption)

	# Per-rank text, straight from Upgrades. This is the part that must never be
	# restated here: it is what the CARD says, and a compendium disagreeing with
	# a card is worse than no compendium at all.
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 13)
	col.add_child(_detail)


func _label(text: String, size_px: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _select(index: int) -> void:
	if index < 0 or index >= _lines.size() or index == _selected:
		return
	_selected = index
	var line := _lines[index]
	_demo.set_line(line)
	_title.text = String(Upgrades.DEFINITIONS[line]["name"])

	var max_rank := int(Upgrades.DEFINITIONS[line]["max_rank"])
	var probe := Upgrades.new(1)
	_ranks.text = "%d rank%s%s" % [max_rank, "" if max_rank == 1 else "s",
		"      LEGENDARY" if probe.is_legendary(line) else ""]

	_caption.text = String(UpgradeDemo.DEMOS[line].get("caption", ""))

	# Walk a real Upgrades up the line, asking what each rank offers. This is
	# exactly what the card screen shows, from exactly the same call -- so the
	# two can never disagree.
	var up := Upgrades.new(1)
	var texts: Array[String] = []
	for r in range(max_rank):
		var text := up.next_rank_description(line)
		if text != "":
			texts.append("[color=#7f8c9d]%d.[/color]  %s" % [r + 1, text])
		up.take(line)
	_detail.text = "\n".join(texts)

	_place_bubble(index)


# Put the bubble beside its row, CLAMPED into the panel.
#
# Derived from the row's measured rect rather than placed at a fixed offset per
# row: a constant is correct for the row it was tuned against and runs off the
# bottom for the last one -- the hard-coded-band trap section 12 records for the
# card row and the summary panel. Clamping is what makes the bottom of a long
# list behave like the top.
func _place_bubble(index: int) -> void:
	if _bubble == null or _panel == null or index >= _rows.size():
		return
	var row := _rows[index]
	var panel_rect := _panel.get_global_rect()
	var row_rect := row.get_global_rect()
	# A row not yet laid out has a zero rect, and anchoring to it would put the
	# bubble in the corner. Defer to the next frame, where the rect is real.
	if row_rect.size.y <= 0.0 or panel_rect.size.y <= 0.0:
		_place_bubble.call_deferred(index)
		return

	var bubble_size := _bubble.size
	if bubble_size.y <= 0.0:
		bubble_size = BUBBLE_SIZE

	# Beside the list, vertically centred on the row.
	var x := panel_rect.position.x + LIST_WIDTH + BUBBLE_GAP * 2.0
	var y := row_rect.position.y + row_rect.size.y * 0.5 - bubble_size.y * 0.5

	# Below the HEADER, not merely inside the panel.
	#
	# Clamping to the panel alone let the bubble ride up over the heading and
	# the hint at the top rows, and a rendered frame showed a screen with no
	# title -- which reads as the title never being built. Both labels were
	# present, visible and correctly placed the whole time; the bubble was
	# simply on top of them. Rect containment is not the same as clearance.
	var top_limit := panel_rect.position.y + HEADER_HEIGHT
	var bottom_limit := panel_rect.position.y + panel_rect.size.y \
		- bubble_size.y - BUBBLE_GAP
	y = clampf(y, top_limit, maxf(top_limit, bottom_limit))

	var right_limit := panel_rect.position.x + panel_rect.size.x \
		- bubble_size.x - BUBBLE_GAP
	x = clampf(x, panel_rect.position.x + BUBBLE_GAP,
		maxf(panel_rect.position.x + BUBBLE_GAP, right_limit))

	_bubble.global_position = Vector2(x, y)


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


# ESC closes, matching what ESC does everywhere else in the game.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		closed.emit()
