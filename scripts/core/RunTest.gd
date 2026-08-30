# Plays a complete run start to finish, headlessly, with an autopilot.
#
# RulesTest proves individual rules; SceneTest proves the game boots. This
# proves the whole thing is FINISHABLE: every maze in Tuning.MAZES chained, the
# gates taken, upgrades carried across, and a completion state reached. That is
# the one property no unit test can establish.
extends SceneTree

const MAX_FRAMES := 300000
const DELTA := 1.0 / 60.0

var _game: Node
var _last_cell := Vector2i(-999, -999)
var _passed := 0
var _failed := 0

# Per-maze records, filled as each is cleared.
var _maze_log: Array = []


func _init() -> void:
	print("=== RunTest ===")
	_go.call_deferred()


func check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _go() -> void:
	_game = load("res://scenes/Game.tscn").instantiate()
	root.add_child(_game)

	var frames := 0
	var last_maze := 0
	var maze_start_time := 0.0
	var gates_this_maze := 0

	while frames < MAX_FRAMES:
		frames += 1

		# Phase 3 is COMPLETE.
		if _game.phase == 3:
			break

		# Sampled BEFORE _process, not after. _start_maze builds a whole new
		# Racer, and it does so DURING _process -- so a sample taken afterwards
		# is already reading the next maze's racer at zero gates, and every maze
		# but the last logged 0 (CLAUDE.md section 12, "node references captured
		# before a maze change go stale"). Reading it before the step is the only
		# point at which the finished maze's racer is still the current one.
		if _game.racer:
			gates_this_maze = _game.racer.gates_taken

		_autopilot()
		_game._process(DELTA)

		if _game.maze_index != last_maze:
			_maze_log.append({
				"index": last_maze,
				"time": _game.elapsed - maze_start_time,
				"gates": gates_this_maze,
			})
			maze_start_time = _game.elapsed
			last_maze = _game.maze_index
			_last_cell = Vector2i(-999, -999)

	check("run completed within frame budget", frames < MAX_FRAMES,
		"used %d frames" % frames)
	check("reached the final phase", _game.phase == 3,
		"phase %d" % _game.phase)
	# Read the count from the config rather than restating it: a literal here
	# checks that two numbers match, not that the game chains every maze it is
	# configured with (CLAUDE.md section 12, "a test that restates a tuning
	# number").
	check("cleared every maze", _game.maze_index == Tuning.MAZES.size() - 1,
		"stopped on maze %d of %d" % [_game.maze_index + 1, Tuning.MAZES.size()])

	_maze_log.append({
		"index": last_maze,
		"time": _game.elapsed - maze_start_time,
		"gates": _game.racer.gates_taken,
	})

	print("")
	print("run seed      : %d" % _game.run_seed)
	print("total time    : %.1fs" % _game.elapsed)
	print("frames        : %d" % frames)
	for entry in _maze_log:
		print("  maze %d      : %.1fs  (%d gates)" % [
			int(entry["index"]) + 1, float(entry["time"]), int(entry["gates"])
		])
	print("crashes       : %d" % _game.racer.crash_count)
	print("slowdowns     : %d" % _game.racer.slowdown_count)
	print("final speed   : %.2fx" % _game.racer.speed)
	print("hp remaining  : %d" % _game.racer.hp)
	print("upgrades      : %s" % str(_game.upgrades.snapshot()))

	# An autopilot that always takes the optimal turn should collect every gate
	# on every maze -- gates sit ON the solve path, so a perfect router cannot
	# miss one.
	#
	# But picks and gates are NOT one-to-one at five mazes: 40 gates against a
	# tree holding only `tree_capacity` total ranks means a perfect run maxes
	# everything and the surplus gates have nothing left to give. So the bound is
	# the smaller of the two -- what the gates offer, and what the tree can hold.
	# Asserting against the gate count alone would fail on a run that did nothing
	# wrong, which is the "restates a tuning number" trap in CLAUDE.md section 12
	# wearing a different hat.
	var gate_total_all := 0
	for cfg in Tuning.MAZES:
		gate_total_all += int(cfg["gates"])

	var tree_capacity := 0
	for line in Upgrades.DEFINITIONS:
		tree_capacity += int(Upgrades.DEFINITIONS[line]["max_rank"])

	var total_upgrades := 0
	for line in _game.upgrades.ranks:
		total_upgrades += _game.upgrades.ranks[line]

	var expected: int = mini(gate_total_all, tree_capacity)
	check("collected upgrades from gates", total_upgrades >= expected,
		"got %d, expected %d (%d gates, tree holds %d)"
			% [total_upgrades, expected, gate_total_all, tree_capacity])

	# A run that hands out more gates than the tree can absorb is a real design
	# signal, not a failure: the last few picks are inert. Reported rather than
	# asserted, because whether that is acceptable is a tuning call.
	if gate_total_all > tree_capacity:
		print("note          : %d gates vs %d total ranks -- the last %d picks have nothing left to take"
			% [gate_total_all, tree_capacity, gate_total_all - tree_capacity])

	check("timer advanced", _game.elapsed > 0.0)
	check("hp never went negative", _game.racer.hp >= 0)

	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


# Follows the live distance field, so it routes correctly even through loops.
# Decides once per cell -- re-deciding every frame would re-request the same
# turn and pin speed at the floor via the per-turn cost.
func _autopilot() -> void:
	var racer: Racer = _game.racer
	if racer == null:
		return

	# Auto-pick the first offered card so the run does not stall at a gate.
	if _game.phase == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(offered[0])
		return

	if _game.phase != 0:
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
	else:
		racer.request_reverse()
