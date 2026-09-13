# Spend coins on cosmetics.
#
# A SECOND path to a cosmetic, never a replacement for the achievement that
# grants it (CLAUDE.md section 10). Achievements still award for free; the shop
# lets a player buy what they have not earned. Both routes write the same
# `earned` set on Unlocks, so nothing downstream -- the pickers, the paired-table
# assertions -- has to know which way an item arrived.
#
# WHAT THE SHOP MAY SELL IS THE WHOLE SAFETY ARGUMENT. Cosmetics only, exactly
# as section 10 narrows meta-progression: a shape, a colour, a decal, a palette.
# If a purchase would change a number the racer reads, it does not belong here --
# and coins the player has BANKED buy nothing in a run, since every run starts
# with an empty purse whatever the wallet holds.
#
# Nothing in the simulation may read any of this. Same separation the marker
# picker and the maze-colour screen have.
class_name Shop
extends Control

signal closed()

const UnlocksScript := preload("res://scripts/core/Unlocks.gd")

const COL_ACCENT := MainMenu.COL_ACCENT
const COL_DIM := MainMenu.COL_DIM
const COL_CARD := MainMenu.COL_CARD
const COL_CARD_HOVER := MainMenu.COL_CARD_HOVER

const PANEL_SIZE := Vector2(1420, 900)
const CHIP_SIZE := Vector2(150, 40)

# How many chips fit across before the row wraps.
#
# The grid WRAPS rather than assuming a row fits, because these tables grow: 25
# palettes and 19 colours already ran one screen off its edge once, which is
# section 12's hard-coded-band trap arriving through a table that got longer.
const CHIP_COLUMNS := 8

var _wallet_label: Label = null
var _hint: Label = null
var _hint_hold := 0.0

# Every chip built, as {button, id}. Walked on refresh rather than rebuilt: a
# purchase changes only the paint and the wallet, and rebuilding would drop
# keyboard focus on every buy.
var _chips: Array = []


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

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	card.add_child(outer)

	outer.add_child(_heading("SHOP", 26, COL_ACCENT))

	# The wallet is the first thing read, because every price below is only
	# meaningful against it.
	_wallet_label = _heading("", 20, Tuning.NEON_COIN)
	outer.add_child(_wallet_label)

	outer.add_child(_heading(
		"Coins are banked by FINISHING a maze. Achievements still unlock these for free.",
		13, COL_DIM))

	_hint = _heading("", 14, Color(1.0, 0.72, 0.25))
	outer.add_child(_hint)

	# The rows SCROLL. Four kinds against tables already running to 25 palettes
	# and 19 colours is far more than a panel holds, and the alternative is the
	# overrun section 8c records -- a panel sized to a band it outgrows, with the
	# CLOSE button pushed off the screen edge.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	# One section per kind, in ascending price: a player with a few coins sees
	# what they can afford first rather than scrolling past what they cannot.
	_build_section(rows, "COLOURS", UnlocksScript.KIND_COLOUR)
	_build_section(rows, "PATTERNS", UnlocksScript.KIND_DECAL)
	_build_section(rows, "MAZE COLOURWAYS", UnlocksScript.KIND_PALETTE)
	_build_section(rows, "MARKER SHAPES", UnlocksScript.KIND_SHAPE)

	outer.add_child(_make_button("CLOSE", _on_close))


# Every lockable cosmetic of one kind, as a wrapping grid of chips.
#
# Read off Unlocks.lockable_ids() rather than off the four Tuning tables
# directly, so the shop stocks exactly what CAN be locked. Listing from the
# tables would put the defaults on the shelf -- items every player already owns
# and none can buy, which is a row that can only ever be refused.
func _build_section(parent: VBoxContainer, title: String, kind: String) -> void:
	var ids: Array = []
	for id in UnlocksScript.lockable_ids():
		if String(id).begins_with(kind + ":"):
			ids.append(String(id))
	if ids.is_empty():
		return

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var price: int = UnlocksScript.price_of(String(ids[0]))
	var label := _heading("%s   -   %d coins each" % [title, price], 15, COL_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(label)

	var grid := GridContainer.new()
	grid.columns = CHIP_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)

	for id in ids:
		var chip := Button.new()
		chip.custom_minimum_size = CHIP_SIZE
		chip.focus_mode = Control.FOCUS_ALL
		chip.add_theme_font_size_override("font_size", 13)
		chip.pressed.connect(_on_buy.bind(String(id)))
		grid.add_child(chip)
		_chips.append({"button": chip, "id": String(id)})

	parent.add_child(col)


# The readable half of a namespaced id: "colour:cobalt" -> "COBALT".
func _short_name(id: String) -> String:
	var parts := String(id).split(":")
	if parts.size() != 2:
		return String(id).to_upper()
	return String(parts[1]).replace("_", " ").to_upper()


func _wallet() -> Node:
	return get_node_or_null("/root/Unlocks")


# Paint every chip against the wallet: owned, affordable, or out of reach.
#
# THREE states rather than two, and the third is the one that matters. A chip
# the player cannot yet afford has to read differently from one they can, or the
# shop gives no sense of what to save for -- it would be a wall of identical
# buttons that refuse most presses.
func _refresh() -> void:
	var wallet := _wallet()
	var coins := 0 if wallet == null else int(wallet.coins)

	if _wallet_label != null:
		_wallet_label.text = "%d COINS" % coins

	for entry in _chips:
		var chip: Button = entry["button"]
		var id: String = entry["id"]
		var owned: bool = wallet != null and bool(wallet.is_unlocked(id))
		var price: int = UnlocksScript.price_of(id)
		var affordable: bool = not owned and coins >= price

		chip.text = "%s\n%s" % [_short_name(id),
			"OWNED" if owned else str(price)]

		var face := Color(0.06, 0.08, 0.12)
		var edge := Color(0.20, 0.26, 0.36)
		var text := Color(0.42, 0.47, 0.56)
		if owned:
			# Owned reads as SPENT rather than as available: clearly not a thing
			# to press again.
			edge = Color(0.22, 0.44, 0.30)
			text = Color(0.55, 0.80, 0.62)
		elif affordable:
			face = Color(0.10, 0.13, 0.18)
			edge = Tuning.NEON_COIN
			text = Color.WHITE

		chip.add_theme_color_override("font_color", text)
		chip.add_theme_color_override("font_hover_color", Color.WHITE)
		chip.add_theme_color_override("font_focus_color", Color.WHITE)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = face
			style.border_color = edge
			style.set_corner_radius_all(6)
			style.set_border_width_all(2)
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


# A chip was pressed.
#
# Every refusal SAYS WHY. A button that silently ignores a press reads as broken,
# which is worse than one that reads as unaffordable -- the same reason a locked
# palette chip states its requirement rather than doing nothing.
func _on_buy(id: String) -> void:
	var wallet := _wallet()
	if wallet == null:
		_say("SHOP UNAVAILABLE")
		return

	if bool(wallet.is_unlocked(id)):
		# Already owned, by either route. Worth saying rather than refusing
		# silently: the player may have earned it since they last looked.
		_say("%s -- ALREADY YOURS" % _short_name(id))
		return

	var price: int = UnlocksScript.price_of(id)
	if int(wallet.coins) < price:
		_say("%s COSTS %d  -  YOU HAVE %d" % [
			_short_name(id), price, int(wallet.coins)])
		return

	if bool(wallet.buy(id)):
		_say("BOUGHT %s" % _short_name(id))
		_refresh()
	else:
		_say("COULD NOT BUY %s" % _short_name(id))


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
	if not _chips.is_empty():
		var chip: Button = _chips[0]["button"]
		chip.grab_focus()
