# The picture half of Trail Memory. SceneTest proves the floor is wired to the
# record; only a rendered frame says whether the tint reads.
#
# It DRIVES A LOOP on purpose rather than shooting on a timer. The whole subject
# is how re-crossed ground reads against ground driven once -- and an optimal
# router never re-crosses anything, so a timed shot would show a uniform trail
# and could not tell the darkening rule from no darkening rule at all. Same
# reasoning as PaletteShot seeking a junction and RearViewShot seeking a corner.
#
# Two frames per maze: one down a stretch driven once, and one after pacing the
# same corridor several times.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _shot := 0
var _last_cell := Vector2i(-999, -999)
# Laps paced once the first frame is taken. The second shot waits on this, since
# the darkening is what it exists to show.
var _laps := 0
var _lap_cells := 0

const SETTLE := 200
const LAPS_WANTED := 4
const LAP_CELLS := 5
const GIVE_UP := SETTLE * 12


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	# Maxed, so nothing expires mid-shot -- the fade is a separate question and
	# a cell lapsing between the two frames would confound the comparison.
	for i in 6:
		_game.upgrades.take(Upgrades.Line.TRAIL_MEMORY)
	# The map up, so the shot shows both renderings of the same record together.
	_game.upgrades.take(Upgrades.Line.MINIMAP)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	var ready := false
	if _shot == 0:
		ready = _frame >= SETTLE
	else:
		ready = _laps >= LAPS_WANTED

	if not ready and _frame < GIVE_UP:
		return
	_frame = 0

	_capture(_maze_index, _shot)
	_shot += 1
	if _shot < 2:
		return

	_shot = 0
	_laps = 0
	_lap_cells = 0
	_maze_index += 1
	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	_game._start_maze(_maze_index)
	_last_cell = Vector2i(-999, -999)


func _autopilot() -> void:
	var racer: Racer = _game.racer
	# An instrument, not a player: a card screen up is a stall. Covers the
	# maze-start loadout as well as a gate pick.
	#
	# Compared as ints, not as Game.Phase.UPGRADING: Game.gd declares no
	# class_name, so its enum is unreachable from a script that only holds the
	# node. Every other shot tool does the same for the same reason.
	if int(_game.phase) == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(offered[0])
		return

	if racer == null or _game.phase != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	if racer.cell == _last_cell:
		return
	_last_cell = racer.cell

	# After the first frame, pace back and forth over the SAME cells rather than
	# routing onward -- that is what produces ground with four crossings on it.
	#
	# Paced by CELLS COVERED, never on a frame count. RepeatProbe records what
	# that costs: its farming driver reversed on a frame interval, which at the
	# 1x start speed never left the opening cell and reported zero repeats --
	# reading exactly like the feature failing when nothing had been driven.
	if _shot >= 1:
		_lap_cells += 1
		if _lap_cells >= LAP_CELLS:
			_lap_cells = 0
			_laps += 1
			racer.request_reverse()
		return

	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


func _capture(index: int, shot: int) -> void:
	var image := root.get_texture().get_image()
	var maze_name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var kind := "fresh" if shot == 0 else "worn"
	var path := "res://logs/trail_%d_%s_%s.png" % [index + 1, maze_name, kind]
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, %d cells remembered, %d laps)" % [
			path, _game.racer.cell, _game.racer.trail.count(), _laps])
	else:
		printerr("FAILED to save %s" % path)
