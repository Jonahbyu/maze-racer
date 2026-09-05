# The leaderboard client: posts finished runs, fetches the three boards, and
# holds the player's display name.
#
# An autoload for the same reason Music and Settings are (CLAUDE.md 9c, 9d):
# Shell._swap frees the entire live child on every mode change, and this is
# WRITTEN by the game (posting a score) and READ by the menu (drawing a board) --
# the game is freed on the way back to the menu.
#
# Two transports behind one surface (docs/plans/leaderboard-desktop.md):
#
#   BRIDGE -- JavaScriptBridge into the Firebase SDK loaded by tools/web/
#             shell.html, the same shape as the audio unlock (section 12).
#   REST   -- plain HTTPRequest against the same project, for desktop, which has
#             no JavaScriptBridge at all.
#
# Every public method below dispatches on the backend and behaves identically
# either way. Neither is reachable from a harness: the bridge needs a browser and
# REST is switched off headless, so `available` is false in both cases and the
# game is unaffected.
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

# --- REST backend (docs/plans/leaderboard-desktop.md) ------------------------
#
# Desktop has no JavaScriptBridge, so it talks to the same Firebase project over
# plain HTTP instead. The public surface below is identical either way; only the
# transport differs.
#
# The API key is a public client identifier, not a secret -- exactly as in
# shell.html. Access is controlled by the Firestore rules.
const API_KEY := "AIzaSyBMZoufa0sSfk6Dv_vgQ0xogB_16GgwMcI"
const PROJECT := "pistachio-kitchen"

const URL_SIGNUP := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + API_KEY
const URL_REFRESH := "https://securetoken.googleapis.com/v1/token?key=" + API_KEY
const URL_DOCS := "https://firestore.googleapis.com/v1/projects/" + PROJECT \
	+ "/databases/(default)/documents"
const SCORES_PATH := "mazeRacer/data/scores"
const PLAYERS_PATH := "mazeRacer/data/players"

# Refresh the ID token this many seconds before it actually expires. A run can
# last minutes, so a token that is merely "still valid now" is not good enough --
# it must survive the post at the end.
const TOKEN_REFRESH_MARGIN := 300.0

const TOKEN_KEY := "refresh_token"

enum Backend { NONE, BRIDGE, REST }

var _backend: int = Backend.NONE

# REST auth state.
var _uid := ""
var _id_token := ""
var _refresh_token := ""
var _token_expires := 0.0

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

	if _has_bridge():
		_backend = Backend.BRIDGE
		available = true
		return

	# Desktop, or a web build whose bridge failed to load. REST needs a network
	# round trip before it can claim to be available, so `available` stays false
	# until sign-in actually lands -- the panel reads that and shows "connecting"
	# rather than an empty board it cannot explain.
	if _rest_enabled():
		_backend = Backend.REST
		_load_refresh_token()
		_rest_authenticate()


# --- The bridge --------------------------------------------------------------
#
# Desktop has no JavaScriptBridge at all, so every one of these returns a benign
# empty value there and the boards are simply absent. That is deliberate: the
# desktop build is the one used for development and every harness, and it must
# not depend on a browser being present.

# Whether to attempt the REST backend at all.
#
# Off in headless runs, which is every harness: a test must never wait on a
# network, and a machine with no connection must not have its harness slowed by
# a DNS timeout. `DisplayServer` reporting the dummy driver is the honest test --
# it is exactly the condition `--headless` creates.
func _rest_enabled() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return true


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
	# Polling exists only for the bridge, whose JS side cannot call back into
	# Godot. REST results arrive on HTTPRequest completion handlers, so there is
	# nothing to poll for there.
	if not available or _backend != Backend.BRIDGE:
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

	if _backend == Backend.REST:
		return _rest_post_run(score_value, seconds, seed_value, board,
			mazes_cleared, died)

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
	if _backend == Backend.REST:
		_rest_request_board(board, sort)
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
	if _backend == Backend.REST:
		_rest_request_history()
		return

	_awaiting_history = true
	_call_js("window.mazeRacerLB.fetchHistory(%d)" % ROWS)


func set_player_name(value: String) -> void:
	player_name = value.strip_edges().substr(0, 24)
	_save_name()
	if not available or not signed_in:
		return
	if _backend == Backend.REST:
		_rest_set_name(player_name)
	else:
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


# --- The REST backend --------------------------------------------------------
#
# Desktop reaches the same Firebase project over plain HTTP. Everything here is
# fire-and-forget: a request is sent, its completion handler updates state and
# emits the same signal the bridge path emits, and nothing ever blocks. A dead
# network leaves the boards empty and the game entirely unaffected, which is the
# rule the bridge follows too.

# One HTTPRequest per call, freed on completion.
#
# Reusing a single node would serialise every request behind whichever is in
# flight -- and the board fetch, the history fetch and a score post can all be
# live at once when a run ends on the menu's first frame.
func _http(handler: Callable) -> HTTPRequest:
	var req := HTTPRequest.new()
	# ALWAYS, matching this node: a request must complete while the tree is
	# paused, since the summary that posts a score is drawn over a paused game.
	req.process_mode = Node.PROCESS_MODE_ALWAYS
	req.timeout = 15.0
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			handler.call(result, code, body)
			req.queue_free())
	return req


func _post_json(url: String, payload: Dictionary, handler: Callable,
		bearer: String = "") -> void:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if bearer != "":
		headers.append("Authorization: Bearer " + bearer)
	var req := _http(handler)
	var err := req.request(url, headers, HTTPClient.METHOD_POST,
		JSON.stringify(payload))
	if err != OK:
		req.queue_free()
		last_error = "request-failed"


func _parse_body(body: PackedByteArray) -> Dictionary:
	var data = JSON.parse_string(body.get_string_from_utf8())
	return data if typeof(data) == TYPE_DICTIONARY else {}


# --- Auth --------------------------------------------------------------------

# Sign in, reusing the stored refresh token if there is one.
#
# A fresh anonymous sign-up on every launch would mint a NEW uid each time, so
# every desktop run would post as a different player and the run history would
# always be empty. Persisting the refresh token is what makes desktop one stable
# identity across launches.
func _rest_authenticate() -> void:
	if _refresh_token != "":
		_rest_refresh()
	else:
		_rest_signup()


func _rest_signup() -> void:
	_post_json(URL_SIGNUP, {"returnSecureToken": true},
		func(result: int, code: int, body: PackedByteArray) -> void:
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				last_error = "auth-failed"
				return
			var d := _parse_body(body)
			_uid = String(d.get("localId", ""))
			_id_token = String(d.get("idToken", ""))
			_refresh_token = String(d.get("refreshToken", ""))
			_token_expires = _now() + float(String(d.get("expiresIn", "3600")).to_float())
			_save_refresh_token()
			_rest_on_signed_in())


func _rest_refresh() -> void:
	_post_json(URL_REFRESH,
		{"grant_type": "refresh_token", "refresh_token": _refresh_token},
		func(result: int, code: int, body: PackedByteArray) -> void:
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				# A refresh token can be revoked or simply invalid -- fall back to
				# a fresh anonymous account rather than leaving the player with a
				# permanently dead leaderboard. The identity changes, which is
				# worse than keeping it and better than losing the feature.
				_refresh_token = ""
				_save_refresh_token()
				_rest_signup()
				return
			var d := _parse_body(body)
			_uid = String(d.get("user_id", ""))
			_id_token = String(d.get("id_token", ""))
			var rt := String(d.get("refresh_token", ""))
			if rt != "":
				_refresh_token = rt
				_save_refresh_token()
			_token_expires = _now() + float(String(d.get("expires_in", "3600")).to_float())
			_rest_on_signed_in())


func _rest_on_signed_in() -> void:
	if _uid == "" or _id_token == "":
		return
	available = true
	signed_in = true
	ready_changed.emit(true)
	# Fetch the stored display name: the server copy is what other players see,
	# so it wins over a local one.
	_rest_fetch_name()


func _rest_fetch_name() -> void:
	var req := _http(func(result: int, code: int, body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			# No stored name is the ordinary case for a new player (404), not an
			# error worth reporting. A local name still stands.
			if player_name != "":
				set_player_name(player_name)
			return
		var d := _parse_body(body)
		var fields: Dictionary = d.get("fields", {})
		var remote := String(_field_value(fields.get("name", {})))
		if remote != "":
			player_name = remote
			_save_name()
		elif player_name != "":
			set_player_name(player_name))
	var err := req.request("%s/%s/%s" % [URL_DOCS, PLAYERS_PATH, _uid],
		PackedStringArray(["Authorization: Bearer " + _id_token]))
	if err != OK:
		req.queue_free()


# True when the ID token is close enough to expiry that it should be renewed.
#
# Static and pure so a harness can assert the arithmetic without a network -- the
# expiry logic is the part most likely to be wrong and the least likely to be
# noticed, since a stale token only fails an hour into a session.
static func token_is_stale(expires_at: float, now: float,
		margin: float = TOKEN_REFRESH_MARGIN) -> bool:
	return now >= expires_at - margin


func _rest_token_ok() -> bool:
	return _id_token != "" and not token_is_stale(_token_expires, _now())


func _now() -> float:
	return Time.get_unix_time_from_system()


# --- Firestore value conversion ----------------------------------------------
#
# REST speaks typed values -- {"doubleValue": 123} rather than 123 -- in both
# directions, so both need converting.
#
# Numbers go out as doubleValue deliberately: integerValue is a STRING in JSON
# and round-trips as one, which would put "12345" on a board that sorts
# numerically.

static func to_fields(data: Dictionary) -> Dictionary:
	var out := {}
	for key in data:
		var v = data[key]
		match typeof(v):
			TYPE_BOOL:
				out[key] = {"booleanValue": v}
			TYPE_INT, TYPE_FLOAT:
				out[key] = {"doubleValue": float(v)}
			_:
				out[key] = {"stringValue": String(v)}
	return {"fields": out}


static func _field_value(field) -> Variant:
	if typeof(field) != TYPE_DICTIONARY:
		return null
	if field.has("stringValue"):
		return String(field["stringValue"])
	if field.has("doubleValue"):
		return float(field["doubleValue"])
	if field.has("integerValue"):
		return float(String(field["integerValue"]))
	if field.has("booleanValue"):
		return bool(field["booleanValue"])
	return null


static func from_fields(doc: Dictionary) -> Dictionary:
	var out := {}
	var fields = doc.get("fields", {})
	if typeof(fields) != TYPE_DICTIONARY:
		return out
	for key in fields:
		out[key] = _field_value(fields[key])
	return out


# The document id the deployed rules require.
#
# Shared boards are keyed uid_board_seed, so one player holds one entry per
# shared maze and a replay overwrites rather than adding a second row. The
# general board is any-seed, so each run is its own document.
#
# Static and pure for the same reason token_is_stale is: this shape is a contract
# with the security rules, and a harness can hold it to that without a network.
static func score_doc_id(uid: String, board_name: String, seed_value: int,
		created_at: int) -> String:
	if board_name == "general":
		return "%s_%d" % [uid, created_at]
	return "%s_%s_%d" % [uid, board_name, seed_value]


# --- REST operations ---------------------------------------------------------

func _rest_post_run(score_value: float, seconds: float, seed_value: int,
		board: int, mazes_cleared: int, died: bool) -> bool:
	if not signed_in:
		return false

	# A run lasts minutes, so the token may have gone stale while it was driven.
	# Refresh first and re-enter, rather than posting with a dead credential and
	# reporting a failure the player cannot act on.
	if not _rest_token_ok():
		_set_post_state("pending")
		_post_json(URL_REFRESH,
			{"grant_type": "refresh_token", "refresh_token": _refresh_token},
			func(result: int, code: int, body: PackedByteArray) -> void:
				if result == HTTPRequest.RESULT_SUCCESS and code == 200:
					var d := _parse_body(body)
					_id_token = String(d.get("id_token", ""))
					_token_expires = _now() \
						+ float(String(d.get("expires_in", "3600")).to_float())
					_rest_post_run(score_value, seconds, seed_value, board,
						mazes_cleared, died)
				else:
					_set_post_state("error:token"))
		return true

	var created := int(_now() * 1000.0)
	var board_text := Tuning.board_name(board)
	var doc_id := score_doc_id(_uid, board_text, seed_value, created)

	var payload := to_fields({
		"uid": _uid,
		"name": player_name if player_name != "" else "anon",
		"score": round(score_value),
		"timeSeconds": seconds,
		"seed": seed_value,
		"board": board_text,
		"mazesCleared": mazes_cleared,
		"died": died,
		"createdAt": created,
	})

	_set_post_state("pending")

	# Read the standing entry first: a replay that went worse must not lower what
	# is already on the board. The rules enforce this too (an update must be an
	# improvement), but checking here is what turns a rejection into the honest
	# "your best run still stands" rather than an error.
	var check := _http(func(result: int, code: int, body: PackedByteArray) -> void:
		var standing := -1.0
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var existing := from_fields(_parse_body(body))
			standing = float(existing.get("score", -1.0))
		if standing >= round(score_value):
			_set_post_state("kept")
			return
		_rest_write_score(doc_id, payload))

	var err := check.request("%s/%s/%s" % [URL_DOCS, SCORES_PATH, doc_id],
		PackedStringArray(["Authorization: Bearer " + _id_token]))
	if err != OK:
		check.queue_free()
		_set_post_state("error:request")
	return true


func _rest_write_score(doc_id: String, payload: Dictionary) -> void:
	var req := _http(func(result: int, code: int, body: PackedByteArray) -> void:
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_set_post_state("ok")
		else:
			var d := _parse_body(body)
			var msg := String(d.get("error", {}).get("status", "unknown"))
			_set_post_state("error:" + msg.to_lower()))
	var err := req.request("%s/%s/%s" % [URL_DOCS, SCORES_PATH, doc_id],
		PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + _id_token,
		]), HTTPClient.METHOD_PATCH, JSON.stringify(payload))
	if err != OK:
		req.queue_free()
		_set_post_state("error:request")


func _set_post_state(state: String) -> void:
	if state == _post_state:
		return
	_post_state = state
	post_state_changed.emit(state)


# A board, as a structured query. REST has no URL form for filtered ordering, so
# this is POSTed to :runQuery.
func _rest_request_board(board: int, sort: String) -> void:
	var order_field := "timeSeconds" if sort == "time" else "score"
	var direction := "ASCENDING" if sort == "time" else "DESCENDING"

	var query := {
		"structuredQuery": {
			"from": [{"collectionId": "scores"}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "board"},
					"op": "EQUAL",
					"value": {"stringValue": Tuning.board_name(board)},
				}
			},
			"orderBy": [{
				"field": {"fieldPath": order_field},
				"direction": direction,
			}],
			"limit": ROWS,
		}
	}

	_run_query(query, func(rows: Array) -> void:
		var out: Array = []
		for r in rows:
			out.append({
				"name": String(r.get("name", "anon")),
				"score": float(r.get("score", 0.0)),
				"time": float(r.get("timeSeconds", 0.0)),
				"mazes": float(r.get("mazesCleared", 0.0)),
				"died": bool(r.get("died", false)),
			})
		cached_boards[_board_key(board, sort)] = out
		board_loaded.emit(board, sort, out))


func _rest_request_history() -> void:
	var query := {
		"structuredQuery": {
			"from": [{"collectionId": "scores"}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "uid"},
					"op": "EQUAL",
					"value": {"stringValue": _uid},
				}
			},
			"orderBy": [{
				"field": {"fieldPath": "createdAt"},
				"direction": "DESCENDING",
			}],
			"limit": ROWS,
		}
	}

	_run_query(query, func(rows: Array) -> void:
		var out: Array = []
		for r in rows:
			out.append({
				"score": float(r.get("score", 0.0)),
				"time": float(r.get("timeSeconds", 0.0)),
				"board": String(r.get("board", "general")),
				"mazes": float(r.get("mazesCleared", 0.0)),
				"died": bool(r.get("died", false)),
				"at": float(r.get("createdAt", 0.0)),
			})
		cached_history = out
		history_loaded.emit(out))


func _run_query(query: Dictionary, on_rows: Callable) -> void:
	var url := "%s/%s:runQuery" % [URL_DOCS, "mazeRacer/data"]
	_post_json(url, query,
		func(result: int, code: int, body: PackedByteArray) -> void:
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				last_error = "query-failed"
				on_rows.call([])
				return
			var parsed = JSON.parse_string(body.get_string_from_utf8())
			var rows: Array = []
			if typeof(parsed) == TYPE_ARRAY:
				for entry in parsed:
					# Entries without a `document` are progress markers the API
					# emits between results, not rows.
					if typeof(entry) == TYPE_DICTIONARY and entry.has("document"):
						rows.append(from_fields(entry["document"]))
			on_rows.call(rows),
		_id_token)


func _rest_set_name(value: String) -> void:
	if not signed_in:
		return
	var payload := to_fields({"name": value, "updatedAt": int(_now() * 1000.0)})
	var req := _http(func(_r: int, _c: int, _b: PackedByteArray) -> void:
		pass)
	var err := req.request("%s/%s/%s" % [URL_DOCS, PLAYERS_PATH, _uid],
		PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + _id_token,
		]), HTTPClient.METHOD_PATCH, JSON.stringify(payload))
	if err != OK:
		req.queue_free()


# --- Refresh token persistence -----------------------------------------------
#
# Beside the player name in settings.cfg. It is a credential, but an anonymous
# one with no personal data behind it and no value to anyone else -- it names a
# throwaway account that can only write that account's own scores.

func _load_refresh_token() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_refresh_token = String(cfg.get_value(SECTION, TOKEN_KEY, ""))


func _save_refresh_token() -> void:
	var cfg := ConfigFile.new()
	# Load first, or saving drops every other section and takes the player's
	# control and audio preferences with it.
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION, TOKEN_KEY, _refresh_token)
	cfg.save(CONFIG_PATH)
