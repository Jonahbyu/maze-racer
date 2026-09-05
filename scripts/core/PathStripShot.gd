# The picture half of the floor-strip Path Indicator (section 7).
#
# Not a test -- no assertion can tell you whether three colours on the floor
# read as three answers at speed, or whether a strip is lying the right way
# across a gap.
#
# It also guards against a misread that has already happened: the Golden Trail
# is a long gold ribbon drawn ALONG the route, and at a junction it looks
# exactly like a strip laid lengthwise down the corridor. It was diagnosed as a
# rotation bug and "fixed" twice against geometry that measured correct the
# whole time. See _pick() -- the trail is kept out of these frames on purpose.
#
# It SEEKS a junction that shows more than one colour rather than shooting on a
# timer, for the reason PaletteShot and GateShot seek theirs: a frame taken at a
# fixed moment lands in a plain corridor or on a corner, where the indicator is
# correctly dark and the shot shows nothing of what it exists to check. A
# two-colour junction is the fixture -- a T where one way is better than the
# other is what the whole three-colour scheme is for.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _last_cell := Vector2i(-999, -999)

const SETTLE := 90
const GIVE_UP := SETTLE * 20


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	_game.upgrades.take(Upgrades.Line.PATH_INDICATOR)
	_game.upgrades.take(Upgrades.Line.MINIMAP)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	if _frame < SETTLE:
		return
	# Hold out for a junction showing at least two different colours, then fall
	# back to any junction so a maze can never stall the whole run.
	if _colours_on_screen() < 2 and _frame < GIVE_UP:
		return
	if not _at_junction() and _frame < GIVE_UP:
		return
	_frame = 0

	_capture(_maze_index)
	_maze_index += 1

	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	_game._start_maze(_maze_index)
	_last_cell = Vector2i(-999, -999)


func _autopilot() -> void:
	var racer: Racer = _game.racer
	# An instrument, not a player: a card screen is a stall, not a decision.
	if int(_game.phase) == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(_pick(offered))
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


# Anything but a trail line -- either of them.
#
# A trail is a long ribbon drawn ALONG the route, and it is the one thing on
# screen that can be mistaken for a strip laid the wrong way -- it reads as a bar
# running lengthwise down a corridor, which is exactly the failure this tool
# exists to catch. It cost a wrong diagnosis and two "fixes" to correct geometry
# before the ribbon was identified. Keeping it out of the frame means anything
# long and lying down the corridor in these shots is a real bug.
#
# Platinum is excluded for the same reason and not merely by association: it is
# the SAME ribbon in silver, and silver against a lit floor strip is if anything
# the easier of the two to misread.
const TRAIL_LINES := [Upgrades.Line.GOLDEN_TRAIL, Upgrades.Line.PLATINUM_TRAIL]


func _pick(offered: Array) -> int:
	for line in offered:
		if not TRAIL_LINES.has(int(line)):
			return int(line)
	return int(offered[0])


# How many DISTINCT branch qualities are visible from where the racer stands.
# Two or more means the frame actually demonstrates the colour scheme rather
# than showing three strips that all say the same thing.
func _colours_on_screen() -> int:
	var racer: Racer = _game.racer
	if racer == null or racer.maze == null:
		return 0
	if not _at_junction():
		return 0

	var seen := {}
	for key in [-1, 0, 1]:
		var direction := racer.facing
		if key == -1:
			direction = racer.left_direction()
		elif key == 1:
			direction = racer.right_direction()
		if not racer.maze.is_open(racer.cell, direction):
			continue
		seen[racer.maze.branch_quality(racer.cell, direction)] = true
	return seen.size()


func _capture(index: int) -> void:
	var image := root.get_texture().get_image()
	var name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var path := "res://logs/pathstrip_%d_%s.png" % [index + 1, name]
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, colours %d, speed %.2fx)" % [
			path, _game.racer.cell, _colours_on_screen(), _game.racer.speed])
	else:
		printerr("FAILED to save %s" % path)


# Same rule the indicator itself lights on: two or more ways ONWARD.
func _at_junction() -> bool:
	var racer: Racer = _game.racer
	if racer == null or racer.maze == null:
		return false
	var behind := int(Maze.OPPOSITE[racer.facing])
	var onward := 0
	for dir in racer.maze.open_directions(racer.cell):
		if int(dir) != behind:
			onward += 1
	return onward >= 2
