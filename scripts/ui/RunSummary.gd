# The end-of-run breakdown: what the player scored, and where it came from.
#
# Shown on BOTH run-end paths -- a cleared run and a death. Dying is when a
# player most wants to know what went wrong, so sending the breakdown only to
# winners would withhold it from the run that most needs explaining.
#
# Unlike UpgradeScreen this is a FULL modal. A gate pick deliberately leaves the
# corridor visible because the player is going straight back to it (CLAUDE.md
# section 7); a finished run is not going back, and this is the one screen in the
# game meant to be read slowly rather than glanced at under time pressure.
#
# Everything here is read from Score.maze_results and Upgrades.ranks. It
# recomputes nothing: a summary that derived its own totals could disagree with
# the HUD the player was watching a second earlier.
class_name RunSummary
extends Control

signal dismissed()

# The player named themselves after the run was already posted, so it needs
# posting again under the new name. Game owns the actual send.
signal repost()

const COL_BG := Color(0.01, 0.02, 0.04, 1.0)
const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.55, 0.64, 0.76)
const COL_TEXT := Color(0.86, 0.92, 1.0)
const COL_GOOD := Color(0.35, 1.0, 0.45)
const COL_BAD := Color(1.0, 0.38, 0.32)
const COL_LEGENDARY := Color(1.0, 0.82, 0.35)
const COL_RULE := Color(0.16, 0.26, 0.38)

# Width only. The HEIGHT is deliberately not fixed: the panel grows with its
# contents and is centred by a container rather than by a hard-coded band.
#
# A fixed 660 was tried and is exactly the section 12 hard-coded-layout trap. It
# fitted the death screen -- three maze rows and a nine-line build -- purely by
# luck, and a cleared run with five rows and a fifteen-line build overran it: the
# last build row was cut off at the screen edge and "press SPACE or ESC to
# continue" was pushed off entirely, so the best run in the game ended on a
# screen with no visible way out. Only a rendered frame at full height shows it.
const PANEL_WIDTH := 940.0

# Margin kept clear at the top and bottom, so a tall panel never runs to the
# screen edge.
const PANEL_MARGIN := 24.0

# HUD elements hidden for the duration, restored on dismiss.
var _hidden: Array = []

# The leaderboard name prompt and post-status line, present only when the
# Leaderboard autoload is available (so: web builds, never a harness).
var _name_field: LineEdit = null
var _post_line: Label = null


func _ready() -> void:
	# Anchors and offsets together: set_anchors_preset() leaves the offsets at
	# zero, which gives a degenerate rect and hangs every centred child off the
	# top-left corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


# `died_on` is the maze index the run ended on, or -1 for a completed run.
#
# `hide_while_shown` are the live HUD elements this screen covers -- the speed
# readout, the timer, the barrier and integrity bars, the minimap. A rendered
# frame is the only thing that shows why they must go: the run is over, so every
# one of them is a frozen number from a run that has ended, drawn on top of the
# screen that reports what those numbers finally came to. Two contradictory
# accounts of the same run, one of them stale.
func present(score: Score, upgrades: Upgrades, elapsed: float,
		died_on: int = -1, hide_while_shown: Array = []) -> void:
	_clear()

	_hidden = []
	for node in hide_while_shown:
		if node != null and node is CanvasItem and node.visible:
			node.visible = false
			_hidden.append(node)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = COL_BG
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# A CenterContainer sizes the panel to its contents and centres it, instead
	# of the panel being pinned to a band guessed in advance. Full-rect with a
	# margin, so a tall build list is centred in what is left rather than
	# overrunning the bottom edge.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.offset_top = PANEL_MARGIN
	centre.offset_bottom = -PANEL_MARGIN
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_constant_override("separation", 8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(panel)

	var cleared := died_on < 0
	panel.add_child(_line("RUN COMPLETE" if cleared else "RUN OVER", 30,
		COL_GOOD if cleared else COL_BAD, HORIZONTAL_ALIGNMENT_CENTER))

	if not cleared and died_on < Tuning.MAZES.size():
		var where := String(Tuning.MAZES[died_on]["name"]).to_upper()
		panel.add_child(_line("died on %s  -  maze %d of %d" % [
			where, died_on + 1, Tuning.MAZES.size()
		], 17, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	panel.add_child(_line(format_score(score.total()), 54, COL_ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER))
	panel.add_child(_spacer(12))

	# --- Per-maze table ---
	panel.add_child(_row_of([
		["MAZE", 260], ["SUBTOTAL", 150], ["TIME", 110],
		["MULT", 110], ["SCORE", 170],
	], 15, COL_DIM))
	panel.add_child(_rule())

	for result in score.maze_results:
		var mult := float(result["multiplier"])
		var name_text := String(result["name"]).to_upper()
		# A partially-completed maze is marked, because its subtotal was scaled
		# by gates taken (CLAUDE.md section 8b) and an unmarked row would look
		# like it merely scored badly.
		var progress := float(result["progress"])
		if progress < 1.0:
			name_text += "  (%d%%)" % int(round(progress * 100.0))
		panel.add_child(_row_of([
			[name_text, 260],
			[format_score(float(result["subtotal"])), 150],
			[format_time(float(result["time"])), 110],
			["x%.2f" % mult, 110],
			[format_score(float(result["score"])), 170],
		], 16, COL_TEXT, _mult_colour(mult, float(result["score"])), 3))

	if score.maze_results.is_empty():
		panel.add_child(_line("no mazes completed", 16, COL_DIM))

	panel.add_child(_spacer(14))

	# --- Run tallies ---
	panel.add_child(_line("RUN", 15, COL_DIM))
	panel.add_child(_rule())

	var repeat_cost := float(score.repeat_cells) * Tuning.SCORE_REPEAT_CELL_PENALTY
	var crash_cost := float(score.crashes) * Tuning.SCORE_CRASH_PENALTY

	panel.add_child(_stat("Total time", format_time(elapsed)))
	panel.add_child(_stat("Clean turns", str(score.clean_turns)))
	panel.add_child(_stat("Scraped turns", str(score.scraped_turns)))
	panel.add_child(_stat("Crashes", "%d      -%s" % [
		score.crashes, format_score(crash_cost)
	], COL_BAD if score.crashes > 0 else COL_TEXT))
	panel.add_child(_stat("Repeated cells", "%d      -%s" % [
		score.repeat_cells, format_score(repeat_cost)
	], COL_BAD if score.repeat_cells > 0 else COL_TEXT))

	panel.add_child(_spacer(14))

	# --- The build ---
	panel.add_child(_line("BUILD", 15, COL_DIM))
	panel.add_child(_rule())
	panel.add_child(_build_grid(upgrades))

	panel.add_child(_spacer(14))
	panel.add_child(_build_leaderboard_block())

	panel.add_child(_spacer(10))
	panel.add_child(_line("press SPACE or ESC to continue", 15, COL_DIM,
		HORIZONTAL_ALIGNMENT_CENTER))

	visible = true


# The posting line, and on a first post the name prompt.
#
# This is the right moment to ask for a name and the only one: the run is over,
# the score is in front of the player, and they now have a reason to care what it
# is filed under. Asking on the menu, before anyone has played, is asking for a
# commitment to a game they have not tried.
func _build_leaderboard_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lb := get_node_or_null("/root/Leaderboard")
	# Absent on desktop and in every harness. The summary is the run's own
	# report and must render completely without it.
	if lb == null or not lb.available:
		return box

	if not lb.has_name():
		box.add_child(_line("NAME FOR THE LEADERBOARD", 13, COL_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))

		var entry_row := HBoxContainer.new()
		entry_row.alignment = BoxContainer.ALIGNMENT_CENTER
		entry_row.add_theme_constant_override("separation", 8)

		_name_field = LineEdit.new()
		_name_field.placeholder_text = "your name"
		_name_field.max_length = 24
		_name_field.custom_minimum_size = Vector2(240, 34)
		_name_field.text_submitted.connect(func(_t): _submit_name())
		entry_row.add_child(_name_field)

		var save := Button.new()
		save.text = "POST"
		save.custom_minimum_size = Vector2(90, 34)
		save.pressed.connect(_submit_name)
		entry_row.add_child(save)

		box.add_child(entry_row)
		# Focus so the player can simply type. Deferred because the node is not
		# in the tree until this frame finishes building.
		_name_field.grab_focus.call_deferred()
	else:
		_post_line = _line("", 14, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		box.add_child(_post_line)
		_sync_post_state(String(lb._post_state))
		if not lb.post_state_changed.is_connected(_sync_post_state):
			lb.post_state_changed.connect(_sync_post_state)

	return box


func _submit_name() -> void:
	if _name_field == null:
		return
	var chosen := _name_field.text.strip_edges()
	if chosen == "":
		return
	var lb := get_node_or_null("/root/Leaderboard")
	if lb == null:
		return
	lb.set_player_name(chosen)
	# Re-post now that the run has a name to file under. The first post already
	# went out as "anon" -- best-of keying means this overwrites it rather than
	# adding a second entry.
	repost.emit()


# The post state, in the player's terms rather than the transport's.
func _sync_post_state(state: String) -> void:
	if _post_line == null or not is_instance_valid(_post_line):
		return
	if state.begins_with("error"):
		_post_line.text = "could not reach the leaderboard"
		_post_line.add_theme_color_override("font_color", COL_BAD)
	elif state == "ok":
		_post_line.text = "posted to the leaderboard"
		_post_line.add_theme_color_override("font_color", COL_GOOD)
	elif state == "kept":
		# Not a failure: a replay that went worse leaves the better run standing.
		_post_line.text = "your best run on this maze still stands"
		_post_line.add_theme_color_override("font_color", COL_DIM)
	elif state == "pending":
		_post_line.text = "posting..."
		_post_line.add_theme_color_override("font_color", COL_DIM)
	else:
		_post_line.text = ""


# A multiplier reads green only when it actually earned something.
#
# Colouring on the multiplier alone put a bright green x5.53 beside a maze whose
# subtotal was -13,060 and which banked ZERO -- the row congratulating the player
# on the worst maze of the run. The multiplier was right on its own terms (the
# maze was quick); it just says nothing about the outcome when there is nothing
# to multiply. A maze that banked nothing is dimmed instead: neither good nor a
# penalty, simply spent.
func _mult_colour(mult: float, banked: float) -> Color:
	if banked <= 0.0:
		return COL_DIM
	return COL_GOOD if mult >= 1.0 else COL_BAD


func dismiss() -> void:
	visible = false
	_clear()
	# Restore whatever was hidden, so a Game that keeps running behind this --
	# a harness driving frames, or a future retry-in-place -- gets its HUD back
	# rather than a permanently blank screen.
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden = []
	_name_field = null
	_post_line = null


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Not while the player is typing their name: SPACE is a character there, and
	# dismissing the screen mid-word would throw the name away along with it.
	if _name_field != null and is_instance_valid(_name_field) 			and _name_field.has_focus():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismissed.emit()


# --- Formatting --------------------------------------------------------------
#
# Static so a harness can assert the formatting without building a Control, and
# so Game can call the same implementation rather than keeping a second copy of
# the thousands separator in step with this one.

# Thousands-separated: a maze banks six figures and a bare run of digits is
# unreadable at a glance.
static func format_score(value: float) -> String:
	var n := int(round(value))
	var sign_text := "-" if n < 0 else ""
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return sign_text + out


static func format_time(seconds: float) -> String:
	var total := int(round(maxf(0.0, seconds)))
	return "%d:%02d" % [total / 60, total % 60]


# --- Widgets -----------------------------------------------------------------

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _line(text: String, size: int, colour: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = COL_RULE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# A row of fixed-width cells. Widths are explicit so the columns line up down
# the table -- Labels sized to their text leave every row ragged.
#
# `accent` recolours the cell at `accent_index`, which is how the multiplier
# reads green or red without needing a second row type.
func _row_of(cells: Array, size: int, colour: Color,
		accent: Color = Color(0, 0, 0, 0), accent_index: int = -1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in cells.size():
		var spec: Array = cells[i]
		var use := accent if i == accent_index and accent.a > 0.0 else colour
		var label := _line(String(spec[0]), size, use)
		label.custom_minimum_size = Vector2(float(spec[1]), 0)
		# Numbers right-align so the digits stack; the maze name stays left.
		if i > 0:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
	return row


func _stat(label_text: String, value: String,
		value_colour: Color = COL_TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _line(label_text, 16, COL_DIM)
	name_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(name_label)
	var value_label := _line(value, 16, value_colour)
	value_label.custom_minimum_size = Vector2(280, 0)
	row.add_child(value_label)
	return row


# Every line the player actually took, with its rank. Three columns, because a
# late-run build runs to a dozen-plus lines and one column would overrun the
# panel.
func _build_grid(upgrades: Upgrades) -> Control:
	var held: Array[int] = []
	for line in upgrades.ranks.keys():
		if upgrades.rank(int(line)) > 0:
			held.append(int(line))
	held.sort()

	if held.is_empty():
		return _line("no upgrades taken", 16, COL_DIM)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for line in held:
		var max_rank := int(Upgrades.DEFINITIONS[line]["max_rank"])
		# A legendary is called out: it is one per run and it changed how the
		# run was driven, so it should not read as one stat among many.
		var colour := COL_LEGENDARY if upgrades.is_legendary(line) else COL_TEXT
		var text := "%s  %d/%d" % [
			upgrades.line_name(line), upgrades.rank(line), max_rank
		]
		var cell := _line(text, 15, colour)
		cell.custom_minimum_size = Vector2(290, 0)
		grid.add_child(cell)

	return grid
