# The picture half of the two trail lines (CLAUDE.md section 7).
#
# Not a test. No assertion can answer the question this change turns on: whether
# the silver ribbon reads as its own line rather than as gold lit oddly, and
# whether the floor ever ends up carrying two ribbons at once.
#
# It SEEKS a frame where PLATINUM is mid-firing, rather than shooting on a
# timer. Platinum says nothing until PLATINUM_MIN_GATES are banked, so an
# untimed shot lands in the first half of a maze and can only ever show Golden --
# which every other frame of the run already shows. The silver line appearing at
# all is the fixture.
#
# The first version of this tool held out for both trails visible together, and
# the frame it produced is why the interlock exists: gold drawn over silver down
# the same corridor, the silver reading as a white smear beneath it. "Both
# drawn" is now a FAILURE the shot reports, not the thing it waits for.
#
# Both lines are taken at rank 3 so the intervals are short and a firing is
# never far away; at rank 1 the tool would spend its budget on cooldowns.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _last_cell := Vector2i(-999, -999)
var _shot_this_maze := false

const SETTLE := 120
# Generous on purpose. Platinum is not eligible until 5 of 8 gates are banked,
# which in maze 5 is most of the maze -- a budget sized for "wait for a junction"
# expires long before the fixture can exist, and the tool then shoots a frame
# with no silver in it and reports success.
const GIVE_UP := SETTLE * 200


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	for _i in 3:
		_game.upgrades.take(Upgrades.Line.GOLDEN_TRAIL)
		_game.upgrades.take(Upgrades.Line.PLATINUM_TRAIL)
	_game.upgrades.take(Upgrades.Line.MINIMAP)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	if _frame < SETTLE:
		return

	# Wait for Platinum to be eligible at all -- it says nothing until the gate
	# tour is done (Tuning.PLATINUM_MIN_GATES), so a shot taken before then can
	# only ever show Golden and would prove nothing about the silver line.
	var racer: Racer = _game.racer
	if racer == null:
		return
	if racer.gates_taken < Tuning.PLATINUM_MIN_GATES and _frame < GIVE_UP:
		return

	# Then hold out for the silver ribbon actually being on screen. The two can
	# never draw together by design, so "both visible" is NOT the fixture --
	# catching Platinum mid-firing is, since Golden has already been shot in
	# every earlier frame of the run.
	if not _showing("PlatinumTrail") and _frame < GIVE_UP:
		return

	_frame = 0
	_capture(_maze_index)
	_maze_index += 1

	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	_game._start_maze(_maze_index)
	for _i in 3:
		_game.upgrades.take(Upgrades.Line.GOLDEN_TRAIL)
		_game.upgrades.take(Upgrades.Line.PLATINUM_TRAIL)
	_last_cell = Vector2i(-999, -999)


func _showing(node_name: String) -> bool:
	var n: Node = _game.get_node_or_null("World/" + node_name)
	return n != null and n.visible


# Are the two trails currently drawn at the same time? Must ALWAYS be false --
# the shot exists partly to confirm on a real frame what RulesTest asserts
# headlessly, since "one ribbon painted over another" is a rendering failure
# that a boolean pair cannot fully describe.
func _both_drawn() -> bool:
	return _showing("GoldenTrail") and _showing("PlatinumTrail")


func _autopilot() -> void:
	var racer: Racer = _game.racer
	if int(_game.phase) == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(int(offered[0]))
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

	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


func _capture(index: int) -> void:
	var image := root.get_texture().get_image()
	var name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var path := "res://logs/trails_%d_%s.png" % [index + 1, name]
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, gates %d, gold %s, plat %s, OVERLAP %s)" % [
			path, _game.racer.cell, _game.racer.gates_taken,
			_showing("GoldenTrail"), _showing("PlatinumTrail"), _both_drawn()])
	else:
		printerr("FAILED to save %s" % path)
