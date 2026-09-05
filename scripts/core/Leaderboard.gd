# The leaderboard client: posts finished runs, fetches the three boards, and
# holds the player's display name.
#
# An autoload for the same reason Music and Settings are (CLAUDE.md 9c, 9d):
# Shell._swap frees the entire live child on every mode change, and this is
# WRITTEN by the game (posting a score) and READ by the menu (drawing a board) --
# the game is freed on the way back to the menu.
#
# Transport is JavaScriptBridge into the Firebase SDK loaded by tools/web/
# shell.html, the same shape as the audio unlock (section 12). Godot has no
# Firebase SDK, and the REST API would mean hand-rolling token refresh.
#
# Nothing in the simulation may read this. Movement, turn resolution, the buffer,
# the barrier and the penalties behave identically with the autoload absent,
# which is what every harness that instantiates Game.tscn bare gets. Every call
# here is guarded rather than assumed -- a blocked CDN, a dead network or a
# failed sign-in must never be what stops a run starting.
extends Node

# A board finished loading. Carries the rows so the menu never polls.
signal board_loaded(board: int, sort: String, rows: Array)
signal history_loaded(rows: Array)
signal post_state_changed(state: String)
signal ready_changed(is_ready: bool)

const NAME_KEY := "player_name"
const CONFIG_PATH := "user://settings.cfg"
const SECTION := "leaderboard"

const ROWS := 10

# How often the bridge is polled for an async result. The JS side cannot call
# back into Godot, so every result is parked in a slot and collected here.
const POLL_INTERVAL := 0.25

var available := false
var signed_in := false
var player_name := ""
var last_error := ""

# The most recent rows, so a menu rebuilt by a scene swap can draw immediately
# rather than flashing empty while a refetch lands.
var cached_boards := {}
var cached_history: Array = []

var _poll := 0.0
var _post_state := ""
var _want_board := -1
var _want_sort := "score"
var _awaiting_board := false
var _awaiting_history := false


func _ready() -> void:
	# PROCESS_MODE_ALWAYS plus set_process, both: process_mode says WHEN a node
	# may process, set_process says that it SHOULD. Music shipped silent for
	# want of the second one (section 12).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_load_name()
	available = _has_bridge()


# --- The bridge --------------------------------------------------------------
#
# Desktop has no JavaScriptBridge at all, so every one of these returns a benign
# empty value there and the boards are simply absent. That is deliberate: the
# desktop build is the one used for development and every harness, and it must
# not depend on a browser being present.

func _has_bridge() -> bool:
	if not OS.has_feature("web"):
		return false
	var v = JavaScriptBridge.eval("!!window.mazeRacerLB", true)
	return typeof(v) == TYPE_BOOL and v


func _call_js(expression: String) -> Variant:
	if not available:
		return null
	return JavaScriptBridge.eval(expression, true)


func _process(delta: float) -> void:
	if not available:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_INTERVAL

	_poll_status()
	_poll_post()
	_poll_board()
	_poll_history()


func _poll_status() -> void:
	var raw = _call_js("window.mazeRacerLB.status()")
	if typeof(raw) != TYPE_STRING or raw == "":
		return
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return

	last_error = String(data.get("error", ""))
	var now: bool = bool(data.get("ready", false))
	if now != signed_in:
		signed_in = now
		ready_changed.emit(signed_in)
		# A name already stored server-side wins over a local one: the server
		# copy is the one other players see on the board.
		var remote := String(data.get("name", ""))
		if remote != "":
			player_name = remote
			_save_name()
		elif player_name != "":
			# A name chosen before sign-in completed still has to reach the
			# server, or the board shows "anon" for a player who did name
			# themselves.
			set_player_name(player_name)


func _poll_post() -> void:
	var raw = _call_js("window.mazeRacerLB.postState()")
	if typeof(raw) != TYPE_STRING:
		return
	if raw != _post_state:
		_post_state = raw
		post_state_changed.emit(_post_state)


func _poll_board() -> void:
	if not _awaiting_board:
		return
	var raw = _call_js("window.mazeRacerLB.boardResult()")
	if typeof(raw) != TYPE_STRING or raw == "":
		return
	_awaiting_board = false
	var data = JSON.parse_string(raw)
	var rows: Array = []
	if typeof(data) == TYPE_DICTIONARY:
		rows = data.get("rows", [])
		if not bool(data.get("ok", false)):
			last_error = String(data.get("error", "fetch-failed"))
	cached_boards[_board_key(_want_board, _want_sort)] = rows
	board_loaded.emit(_want_board, _want_sort, rows)


func _poll_history() -> void:
	if not _awaiting_history:
		return
	var raw = _call_js("window.mazeRacerLB.historyResult()")
	if typeof(raw) != TYPE_STRING or raw == "":
		return
	_awaiting_history = false
	var data = JSON.parse_string(raw)
	var rows: Array = []
	if typeof(data) == TYPE_DICTIONARY:
		rows = data.get("rows", [])
	cached_history = rows
	history_loaded.emit(rows)


# --- Public API --------------------------------------------------------------

# Post a finished run. Called from the end-of-run summary, which is the only
# place a run is genuinely over and its score final.
func post_run(score_value: float, seconds: float, seed_value: int, board: int,
		mazes_cleared: int, died: bool) -> bool:
	if not available or not signed_in:
		return false

	var payload := JSON.stringify({
		"score": score_value,
		"time": seconds,
		"seed": seed_value,
		"board": Tuning.board_name(board),
		"mazes": mazes_cleared,
		"died": died,
	})
	# JSON.stringify escapes its own quotes, so the payload is passed as a JS
	# string literal built here rather than interpolated raw -- an unescaped
	# name would otherwise be able to close the string and inject.
	var call := "window.mazeRacerLB.postScore(%s)" % JSON.stringify(payload)
	_post_state = ""
	var ok = _call_js(call)
	return typeof(ok) == TYPE_BOOL and ok


func request_board(board: int, sort: String = "score") -> void:
	if not available or not signed_in:
		board_loaded.emit(board, sort, [])
		return
	_want_board = board
	_want_sort = sort
	_awaiting_board = true
	_call_js("window.mazeRacerLB.fetchBoard(%s, %s, %d)" % [
		JSON.stringify(Tuning.board_name(board)), JSON.stringify(sort), ROWS
	])


func request_history() -> void:
	if not available or not signed_in:
		history_loaded.emit([])
		return
	_awaiting_history = true
	_call_js("window.mazeRacerLB.fetchHistory(%d)" % ROWS)


func set_player_name(value: String) -> void:
	player_name = value.strip_edges().substr(0, 24)
	_save_name()
	if available and signed_in:
		_call_js("window.mazeRacerLB.setName(%s)" % JSON.stringify(player_name))


func has_name() -> bool:
	return player_name.strip_edges() != ""


func cached_board(board: int, sort: String) -> Array:
	return cached_boards.get(_board_key(board, sort), [])


func _board_key(board: int, sort: String) -> String:
	return "%d:%s" % [board, sort]


# --- Local persistence -------------------------------------------------------
#
# Shares settings.cfg with Settings rather than opening a second file: it is the
# same kind of per-player preference, and two config files would be two things to
# keep in step. Read and written directly rather than through Settings, so
# neither autoload has to know the other exists.

func _load_name() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	player_name = String(cfg.get_value(SECTION, NAME_KEY, ""))


func _save_name() -> void:
	var cfg := ConfigFile.new()
	# Load first: saving a bare ConfigFile would drop every other section,
	# taking the player's control and audio preferences with it.
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION, NAME_KEY, player_name)
	cfg.save(CONFIG_PATH)
