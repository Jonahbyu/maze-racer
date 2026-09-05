# Not a test -- an instrument. Drives the REST leaderboard backend against the
# REAL Firebase project and reports what came back.
#
# It exists for the same reason MusicProbe does: every harness runs --headless,
# and the REST backend is deliberately switched off there (no test may wait on a
# network), so the harnesses prove the wiring and say nothing whatever about
# whether desktop can actually reach Firebase. Only a windowed run does.
#
# Usage:
#   launch.ps1 -Script res://scripts/core/LeaderboardProbe.gd
extends SceneTree

const STEP_SECONDS := 1.5

var _lb: Node
var _elapsed := 0.0
var _stage := 0
var _posted := false
var _seed := 0


func _init() -> void:
	print("=== LeaderboardProbe ===")
	_setup.call_deferred()


func _setup() -> void:
	# Wait for a frame before looking the autoload up.
	#
	# call_deferred from _init fires BEFORE the autoloads have entered the tree,
	# so /root/Leaderboard does not exist yet and the probe reported it missing
	# from a project where it is correctly registered -- which reads exactly like
	# a broken autoload and is not one. process_frame is the first point at which
	# the tree is fully built.
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _lb == null:
		_lb = root.get_node_or_null("/root/Leaderboard")
		if _lb == null:
			printerr("no /root/Leaderboard autoload -- is it in project.godot?")
			quit(1)
			return
		print("backend        : ", _lb._backend, "  (0=NONE 1=BRIDGE 2=REST)")
		print("rest enabled   : ", _lb._rest_enabled())

	_elapsed += 1.0 / 60.0
	if _elapsed < STEP_SECONDS * float(_stage + 1):
		return
	_stage += 1

	match _stage:
		1:
			print("signed in      : ", _lb.signed_in)
			print("available      : ", _lb.available)
			print("uid            : ", _lb._uid.substr(0, 12), "...")
			print("last error     : '", _lb.last_error, "'")
			if not _lb.signed_in:
				printerr("SIGN-IN FAILED -- nothing further will work")
		2:
			# A name, so the row is identifiable on the board rather than "anon".
			_lb.set_player_name("desktop-probe")
			print("name set       : ", _lb.player_name)
		3:
			# Post a plausible run on the GENERAL board. General is any-seed, so
			# this cannot collide with a real daily entry.
			_seed = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
			_posted = _lb.post_run(123456.0, 271.0, _seed,
				Tuning.Board.GENERAL, 5, false)
			print("post accepted  : ", _posted)
		4:
			print("post state     : '", _lb._post_state, "'")
		5:
			print("post state +1s : '", _lb._post_state, "'")
		6:
			print("post state +2s : '", _lb._post_state, "'")
		7:
			_lb.board_loaded.connect(_on_board)
			_lb.request_board(Tuning.Board.GENERAL, "score")
			print("board requested")
		9:
			_lb.history_loaded.connect(_on_history)
			_lb.request_history()
			print("history requested")
		11:
			print("")
			print("RESULT: ", "PASS" if _lb.signed_in and _posted else "FAIL")
			quit(0)


func _on_board(_board: int, _sort: String, rows: Array) -> void:
	print("board rows     : ", rows.size())
	for r in rows:
		print("   ", String(r.get("name", "?")), "  ",
			int(r.get("score", 0)), "  ", int(r.get("time", 0)), "s")


func _on_history(rows: Array) -> void:
	print("history rows   : ", rows.size())
	for r in rows:
		print("   ", String(r.get("board", "?")), "  ", int(r.get("score", 0)))
