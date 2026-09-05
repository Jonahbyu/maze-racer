# The picture half of the Quadrant box and the Compass (CLAUDE.md section 7).
# SceneTest proves the wiring and the clearances; only a rendered frame can say
# whether the grid, the lit region and the letter are legible together.
#
# It SEEKS A REGION CHANGE rather than shooting on a timer, for the reason
# RearViewShot seeks a corner and PaletteShot seeks a junction. A box that
# never updated would look IDENTICAL to a working one in any single frame --
# a lit square is a lit square. Shooting either side of a crossing is the only
# frame pair that shows the highlight actually moving, which is the whole
# behaviour the upgrade is bought for.
#
# Three frames per rank: the region just before a crossing, just after it, and
# one at 4x4 with a long way still to go, so the "N of 16" progress read is in
# the picture as well as the grid.
extends SceneTree

var _game: Node
var _frame := 0
var _rank := 1
var _shot := 0
var _last_cell := Vector2i(-999, -999)
var _last_region := Vector2i(-99, -99)
var _crossed := false

const SETTLE := 60
const GIVE_UP := SETTLE * 40


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	# The compass alongside, because the two lines share one widget and the
	# question a shot answers is whether they read together -- an element in
	# isolation is not the layout it ships in.
	_game.upgrades.take(Upgrades.Line.COMPASS)
	# The minimap up too, so the box is shown in the company it keeps.
	_game.upgrades.take(Upgrades.Line.MINIMAP)
	_apply_rank()

	process_frame.connect(_on_frame)


func _apply_rank() -> void:
	_game.upgrades.ranks[Upgrades.Line.QUADRANT] = _rank


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	if _frame < SETTLE:
		return

	var box = _game._quadrant_box
	if box == null:
		printerr("no quadrant box")
		quit(1)
		return

	# Shot 0 is the frame before a crossing, so it has to be taken while the
	# region is merely ABOUT to change -- which cannot be known in advance.
	# Taken instead as "settled in a region", and shot 1 fires the moment the
	# region actually moves, giving the pair either side of the boundary.
	var ready := false
	if _shot == 0:
		ready = box.here != Vector2i(-1, -1)
	elif _shot == 1:
		ready = _crossed
	else:
		ready = _crossed

	if not ready and _frame < GIVE_UP:
		return
	_frame = 0
	_crossed = false

	_capture(_rank, _shot)
	_shot += 1
	if _shot < 3:
		return

	_shot = 0
	_rank += 1
	if _rank >= Tuning.QUADRANT_DIVISIONS_BY_RANK.size():
		print("RESULT: PASS")
		quit(0)
		return
	_apply_rank()


func _autopilot() -> void:
	var racer: Racer = _game.racer
	# An instrument, not a player: a card screen up is a stall. Covers the
	# maze-start loadout pick as well as a gate pick.
	if int(_game.phase) == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(offered[0])
		# A pick can change the quadrant rank out from under the shot, so it is
		# re-asserted after every card taken.
		_apply_rank()
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

	# Watch the region rather than the cell: a crossing is the event this shot
	# is about, and it happens on one cell in every twenty-odd.
	var box = _game._quadrant_box
	if box != null and box.divisions > 0:
		var region: Vector2i = racer.maze.quadrant_coord(racer.cell, box.divisions)
		if _last_region != Vector2i(-99, -99) and region != _last_region:
			_crossed = true
		_last_region = region

	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


func _capture(rank: int, shot: int) -> void:
	var image := root.get_texture().get_image()
	var divisions: int = int(Tuning.QUADRANT_DIVISIONS_BY_RANK[rank])
	var kind: String = ["before", "after", "progress"][shot]
	var path := "res://logs/quadrant_r%d_%dx%d_%s.png" % [
		rank, divisions, divisions, kind]
	var box = _game._quadrant_box
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, region %s, %d of %d, facing %s)" % [
			path, _game.racer.cell, box.here,
			box.quadrant_number, box.quadrant_total, box.cardinal])
	else:
		printerr("FAILED to save %s" % path)
