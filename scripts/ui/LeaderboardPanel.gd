# The leaderboard panel: three boards, a score/time toggle, and the player's own
# run history.
#
# Lives on the RIGHT of the menu; the title and buttons take the left
# (docs/plans/leaderboards.md). It draws its own scrim rather than relying on the
# background being dark, because a background art piece sits behind it and this
# has to stay legible over an image nobody has seen yet.
#
# It reads the Leaderboard autoload and never Firebase directly. On desktop -- and
# in every harness -- that autoload reports unavailable, so the panel draws its
# empty state and nothing errors.
class_name LeaderboardPanel
extends Control

const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.55, 0.62, 0.75)
const COL_TEXT := Color(0.86, 0.92, 1.0)
# 0.88 was chosen when the menu behind it was a flat near-black fill, where an
# opaque panel cost nothing. Against the corridor art it read as a black slab
# with a hard vertical seam down the screen -- the panel stopped looking like
# part of the menu and started looking like a hole cut in it. Opened up so the
# art carries through, which is enough to keep a 13pt row legible because the
# whole image is already dimmed by MainMenu's own scrim before this lands.
const COL_SCRIM := Color(0.02, 0.035, 0.06, 0.62)
const COL_RULE := Color(0.16, 0.26, 0.38)
const COL_TAB_ON := Color(0.12, 0.85, 1.0)
const COL_TAB_OFF := Color(0.35, 0.42, 0.54)
const COL_ME := Color(1.0, 0.82, 0.35)

const PANEL_WIDTH := 460.0
const ROW_HEIGHT := 26.0

# The three boards plus the player's own runs. History is a FOURTH view rather
# than a separate widget: it answers "how am I doing" against the same rows in
# the same shape, and a second panel would be a second thing to lay out and keep
# clear of the art behind it.
enum View { GENERAL, DAILY, MONTHLY, HISTORY }

const VIEW_TITLES := ["GENERAL", "DAILY", "MONTHLY", "YOUR RUNS"]
const VIEW_BLURB := [
	"any seed",
	"today's maze, same for everyone",
	"this month's maze, same for everyone",
	"your most recent runs",
]

var _view: int = View.GENERAL
var _sort := "score"

var _title: Label
var _blurb: Label
var _rows_box: VBoxContainer
var _status: Label
var _tabs: Array[Button] = []
var _sort_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_connect_board()
	refresh()


func _build() -> void:
	# A rounded, bordered card rather than a bare ColorRect.
	#
	# A flat rect has four hard edges, and against the corridor art the left one
	# read as a seam splitting the screen in half -- the panel looked stamped ON
	# the menu instead of being part of it. The radius and a faint accent border
	# say "this is a panel" deliberately, which is what stops the eye reading the
	# edge as damage. Same reasoning as the buttons, which have carried a radius
	# and a border since they were built.
	var scrim := PanelContainer.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COL_SCRIM
	style.set_corner_radius_all(14)
	style.set_border_width_all(1)
	style.border_color = Color(0.22, 0.34, 0.48, 0.55)
	scrim.add_theme_stylebox_override("panel", style)
	add_child(scrim)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 28.0
	column.offset_right = -28.0
	column.offset_top = 28.0
	column.offset_bottom = -28.0
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# --- Board switcher ---
	#
	# A row of four, not a cycling button: with the boards visible at once the
	# player can see the daily exists without discovering it by clicking. Four
	# short labels fit the panel width, which is what makes this affordable --
	# the menu-row lesson (section 9d) is about deriving the band, not about
	# avoiding rows.
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	column.add_child(tab_row)
	for i in VIEW_TITLES.size():
		var tab := _make_small_button(_tab_label(i), func(): _set_view(i))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.append(tab)
		tab_row.add_child(tab)

	_title = _label(VIEW_TITLES[_view], 22, COL_ACCENT)
	column.add_child(_title)

	_blurb = _label(VIEW_BLURB[_view], 13, COL_DIM)
	column.add_child(_blurb)

	# --- Sort toggle ---
	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 6)
	column.add_child(sort_row)
	sort_row.add_child(_label("SORT", 12, COL_DIM))
	for mode in ["score", "time"]:
		var b := _make_small_button(mode.to_upper(), func(): _set_sort(mode))
		_sort_buttons.append(b)
		sort_row.add_child(b)

	var rule := ColorRect.new()
	rule.color = COL_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_rows_box)

	_status = _label("", 12, COL_DIM)
	column.add_child(_status)

	_sync_buttons()


func _connect_board() -> void:
	var lb := _board()
	if lb == null:
		return
	lb.board_loaded.connect(_on_board_loaded)
	lb.history_loaded.connect(_on_history_loaded)
	# A board fetched before sign-in lands returns nothing, so refetch when the
	# connection actually comes up rather than leaving the panel empty until the
	# player clicks something.
	lb.ready_changed.connect(func(_r): refresh())


func refresh() -> void:
	var lb := _board()
	if lb == null:
		_draw_rows([])
		_status.text = "leaderboards are online only"
		return

	if not lb.available:
		_draw_rows([])
		_status.text = "leaderboards are online only"
		return

	if not lb.signed_in:
		_draw_rows([])
		_status.text = "connecting..."
		return

	if _view == View.HISTORY:
		var cached: Array = lb.cached_history
		_draw_rows(cached)
		_status.text = "loading..." if cached.is_empty() else ""
		lb.request_history()
		return

	var rows: Array = lb.cached_board(_view, _sort)
	_draw_rows(rows)
	_status.text = "loading..." if rows.is_empty() else ""
	lb.request_board(_view, _sort)


func _on_board_loaded(board: int, sort: String, rows: Array) -> void:
	# Ignore a result for a board the player has already clicked away from --
	# two fetches in flight would otherwise race and the slower one would win.
	if _view == View.HISTORY or board != _view or sort != _sort:
		return
	_draw_rows(rows)
	_status.text = "no scores yet" if rows.is_empty() else ""


func _on_history_loaded(rows: Array) -> void:
	if _view != View.HISTORY:
		return
	_draw_rows(rows)
	_status.text = "no runs yet" if rows.is_empty() else ""


func _draw_rows(rows: Array) -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()

	_rows_box.add_child(_header_row())

	var lb := _board()
	var me := "" if lb == null else String(lb.player_name)

	var shown := 0
	for entry in rows:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		shown += 1
		_rows_box.add_child(_score_row(shown, entry, me))


# History has no rank and no name -- both would be the same on every line. It
# shows WHEN instead, which is the column that actually varies.
func _header_row() -> Control:
	if _view == View.HISTORY:
		return _row(["", "BOARD", "SCORE", "TIME"], 12, COL_DIM)
	return _row(["#", "NAME", "SCORE", "TIME"], 12, COL_DIM)


func _score_row(rank: int, entry: Dictionary, me: String) -> Control:
	var score_text := _thousands(float(entry.get("score", 0)))
	var time_text := _mmss(float(entry.get("time", 0)))

	if _view == View.HISTORY:
		return _row([
			"", String(entry.get("board", "")), score_text, time_text
		], 13, COL_TEXT)

	var name_text := String(entry.get("name", "anon"))
	# The player's own entry is picked out, which is the first thing anyone
	# looks for on a board.
	var colour := COL_ME if (me != "" and name_text == me) else COL_TEXT
	return _row([str(rank), name_text, score_text, time_text], 13, colour)


func _set_view(view: int) -> void:
	if _view == view:
		return
	_view = view
	_title.text = VIEW_TITLES[view]
	_blurb.text = VIEW_BLURB[view]
	_sync_buttons()
	refresh()


func _set_sort(mode: String) -> void:
	if _sort == mode:
		return
	_sort = mode
	_sync_buttons()
	refresh()


func _sync_buttons() -> void:
	for i in _tabs.size():
		_tabs[i].add_theme_color_override("font_color",
			COL_TAB_ON if i == _view else COL_TAB_OFF)
	for i in _sort_buttons.size():
		var mode := "score" if i == 0 else "time"
		_sort_buttons[i].add_theme_color_override("font_color",
			COL_TAB_ON if mode == _sort else COL_TAB_OFF)
	# History is always newest-first, so a sort toggle there would be a control
	# that does nothing -- worse than one that is absent.
	var sortable := _view != View.HISTORY
	for b in _sort_buttons:
		b.disabled = not sortable
		b.modulate.a = 1.0 if sortable else 0.4


# --- Widgets -----------------------------------------------------------------

func _tab_label(view: int) -> String:
	match view:
		View.GENERAL: return "ALL"
		View.DAILY: return "DAY"
		View.MONTHLY: return "MONTH"
		_: return "MINE"


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Fixed column widths so the numbers stack down the panel; Labels sized to their
# own text leave every row ragged.
func _row(cells: Array, size: int, colour: Color) -> HBoxContainer:
	var widths := [34.0, 170.0, 118.0, 70.0]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	for i in cells.size():
		var l := _label(String(cells[i]), size, colour)
		l.custom_minimum_size = Vector2(float(widths[i]), 0)
		if i >= 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# A long name must not push the score column off the panel.
		if i == 1:
			l.clip_text = true
		row.add_child(l)
	return row


func _make_small_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, 26)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.06, 0.09, 0.14, 0.9)
	flat.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", flat)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.11, 0.18, 0.28, 0.95)
	hover.set_corner_radius_all(4)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", flat)
	b.pressed.connect(handler)
	return b


# Shared with RunSummary's formatting rather than reimplemented: two copies of a
# thousands separator is two things to keep in step.
func _thousands(value: float) -> String:
	return RunSummary.format_score(value)


func _mmss(seconds: float) -> String:
	return RunSummary.format_time(seconds)


func _board() -> Node:
	return get_node_or_null("/root/Leaderboard")
