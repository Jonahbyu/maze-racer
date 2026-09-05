# The picture half of the end-of-run summary (CLAUDE.md section 8c).
#
# Every assertion SceneTest makes about this screen is about node counts and
# signals; none of them can see whether the columns line up, whether the table
# overruns the panel, or whether a long build list runs off the bottom. Layout
# is precisely what no headless harness can check -- which is why the touch pads
# needed TouchShot and this needs its own tool.
#
# Two shots, because the two paths differ in what they draw: a death carries the
# outcome line and a partial-progress row, a completed run carries neither and
# has five maze rows instead of one.
#
# Usage:
#   launch.ps1 -Script res://scripts/core/SummaryShot.gd
extends SceneTree

var _game: Node
var _frame := 0
var _stage := 0
var _last_cell := Vector2i(-999, -999)


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_game = load("res://scenes/Game.tscn").instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	match _stage:
		0:
			# Drive real frames first, so the tallies on the summary are from
			# actual play rather than from numbers poked in. A summary shot
			# built on synthetic values would not show the column widths a real
			# six-figure score needs.
			_autopilot()
			if _frame > 420:
				_stage = 1
		1:
			_build_death()
			_stage = 2
		2:
			# Capture on a LATER frame than the build. process_frame fires before
			# the new UI has been drawn, so capturing in the same frame grabs the
			# PREVIOUS screen -- which silently produced two identical files and
			# read as the completion path having failed. Same trap GateSpentShot
			# records for camera aiming.
			_capture("summary_death")
			_stage = 3
		3:
			_build_complete()
			_stage = 4
		4:
			_capture("summary_complete")
			_stage = 5
		5:
			print("RESULT: PASS")
			quit(0)


func _build_death() -> void:
	# Bank a couple of mazes first so the table has more than one row -- a
	# single-row table would not show whether the columns hold up down a list.
	var score = _game.score
	score.add_travel(6.0, 4.5)
	score.advance_time(52.0)
	score.bank_maze(0, "The Grid")
	score.add_travel(9.0, 5.2)
	score.advance_time(61.0)
	score.bank_maze(1, "The Ember")

	# A run that died carries damage, so the tallies are not all zero.
	for i in 4:
		score.add_crash()
	for i in 37:
		score.add_repeat()

	_take_upgrades(9)
	_game.maze_index = 2
	_game.racer.gates_taken = 5
	_game.score.add_travel(5.0, 3.8)
	_game.score.advance_time(44.0)
	_game._on_died()


func _build_complete() -> void:
	# A fresh Game: the death shot left its own summary up and its score banked.
	root.remove_child(_game)
	_game.free()
	_game = load("res://scenes/Game.tscn").instantiate()
	root.add_child(_game)

	var score = _game.score
	# All five mazes, so the table is at its tallest -- the case most likely to
	# overrun the panel.
	# All but the last: _on_exit_reached banks the final maze itself, so banking
	# every one here duplicated The Vault as a second, empty row.
	for i in Tuning.MAZES.size() - 1:
		score.add_travel(8.0 + float(i), 4.4 + float(i) * 0.3)
		score.advance_time(48.0 + float(i) * 4.0)
		score.bank_maze(i, String(Tuning.MAZES[i]["name"]))
	score.add_travel(12.0, 5.6)
	score.advance_time(64.0)
	score.clean_turns = 341
	score.scraped_turns = 27
	for i in 2:
		score.add_crash()
	for i in 14:
		score.add_repeat()

	# A full build, including a legendary, so the grid is at its widest.
	_take_upgrades(15)
	_game.upgrades.take(Upgrades.Line.WALL_SMASHER)

	_game.maze_index = Tuning.MAZES.size() - 1
	_game._on_exit_reached()


# Take a spread of ranks so the BUILD grid is populated the way a real late run
# would leave it, rather than showing one line at rank 1.
func _take_upgrades(count: int) -> void:
	var taken := 0
	for line in Upgrades.DEFINITIONS.keys():
		if taken >= count:
			break
		if _game.upgrades.is_legendary(int(line)):
			continue
		var ranks := 1 + (taken % 3)
		for i in ranks:
			if not _game.upgrades.is_maxed(int(line)):
				_game.upgrades.take(int(line))
		taken += 1


func _autopilot() -> void:
	if _game.phase == 1:
		var offered: Array = _game._upgrade_screen._lines
		_game._on_upgrade_chosen(-1 if offered.is_empty() else offered[0])
		return
	var racer: Racer = _game.racer
	if racer == null or _game.phase != 0:
		return
	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return
	if racer.cell == _last_cell:
		return
	_last_cell = racer.cell
	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/shot_%s.png" % label
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
