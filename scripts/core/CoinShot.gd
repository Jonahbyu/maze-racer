# The picture half of the coin work (CLAUDE.md section 5b).
#
# Not a test -- no assertion can say whether a spinning disc reads as a coin
# rather than as a glowing speck, and that is the only question worth asking
# here. What is checked in RulesTest is the economy; what is checked here is
# whether the player can SEE the thing the economy is about.
#
# It SEEKS a coin straight ahead with an open line of sight, walking the corridor
# cell by cell, rather than shooting on a timer. A timed shot lands in an empty
# corridor and produces a frame that cannot tell a working coin from one that
# never spawned -- the reason PaletteShot seeks a junction and GateShot seeks a
# gate. Alignment alone is not enough either: a coin sharing an axis may sit
# behind a wall, which is the fault AddedLinesShot records for its first two
# versions.
#
# Two frames per maze: one APPROACHING a coin, and one just after taking it, so
# the pair shows both that a coin reads at distance and that collection actually
# retires it. A coin that was never removed would look identical in a single
# approach shot.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _last_cell := Vector2i(-999, -999)
var _shot_approach := false
var _pending_take := Vector2i(-999, -999)

const SETTLE := 40
# How far ahead a coin may be and still be worth shooting. Close enough that the
# disc is legible, far enough that the shot answers "can I see it coming".
const MIN_AHEAD := 1
const MAX_AHEAD := 3
# Give up on a maze after this many frames and move on rather than hanging: a
# tool that waits forever for a fixture reports nothing at all.
const BUDGET := 4000


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	if _frame < SETTLE:
		return

	var racer: Racer = _game.racer
	if racer == null:
		return

	# The second frame of the pair: the coin just taken is now behind us, and
	# the world should no longer be drawing it.
	if _pending_take != Vector2i(-999, -999):
		# Wait until the coin is actually COLLECTED and the racer has driven on
		# past it. Shooting the moment it is reached produces a frame all but
		# identical to the approach, which says nothing about whether collection
		# retired the node -- the failure this pair exists to expose. The first
		# version did exactly that and saved two shots from the same cell.
		var gone: bool = not racer.maze.coins.has(_pending_take)
		if gone and racer.cell != _pending_take:
			_capture(_maze_index, "taken")
			_pending_take = Vector2i(-999, -999)
			_next_maze()
		elif _frame > BUDGET:
			print("maze %d: coin at %s never collected" % [
				_maze_index + 1, _pending_take])
			_next_maze()
		return

	if not _shot_approach:
		var ahead := _coin_ahead()
		if ahead == Vector2i(-999, -999):
			if _frame > BUDGET:
				print("maze %d: no coin found in budget" % (_maze_index + 1))
				_next_maze()
			return
		_capture(_maze_index, "approach")
		_shot_approach = true
		_pending_take = ahead
		return


func _next_maze() -> void:
	_frame = 0
	_shot_approach = false
	_pending_take = Vector2i(-999, -999)
	_last_cell = Vector2i(-999, -999)
	_maze_index += 1
	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return
	_game._start_maze(_maze_index)


# A coin dead ahead, with nothing but open corridor between here and it.
#
# Walked cell by cell rather than tested for alignment, because alignment is not
# visibility: a coin on the same axis with a wall in between photographs as an
# empty corridor, which is exactly the frame this tool exists not to produce.
func _coin_ahead() -> Vector2i:
	var racer: Racer = _game.racer
	if racer == null or racer.maze == null:
		return Vector2i(-999, -999)
	var maze: Maze = racer.maze
	var step: Vector2i = Maze.DIR_VECTORS[racer.facing]
	var at: Vector2i = racer.cell
	for i in MAX_AHEAD:
		if not maze.is_open(at, racer.facing):
			return Vector2i(-999, -999)
		at += step
		if i + 1 >= MIN_AHEAD and maze.coins.has(at):
			return at
	return Vector2i(-999, -999)


# Drive toward the exit, taking any card offered so the run does not stall on a
# modal. Instruments are not players.
func _autopilot() -> void:
	var racer: Racer = _game.racer
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

	# Once per CELL, never once per frame. The coin route below is a flood over
	# the whole grid, and running it every frame on a 100x100 maze is what made
	# the first version appear to hang outright -- the frame-versus-cell lesson
	# RepeatProbe and MomentumProbe both record (section 12).
	if racer.cell == _last_cell:
		return
	_last_cell = racer.cell

	# Steer toward the nearest COIN rather than toward the exit.
	#
	# An exit-seeking router takes the optimal route and coin placement
	# deliberately ignores that route (section 5b), so it meets a coin only by
	# accident -- measured, it found one in 1 maze of 5 and reported "no coin
	# found" for the rest, which is a tool that photographs nothing. Driving at
	# the fixture is the same rule PaletteShot follows in seeking a junction.
	var best := _toward_coin()
	if best == -1:
		best = racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


# The first step of a BFS route to the nearest uncollected coin, or -1.
#
# A plain flood rather than a read of the distance field: the field descends to
# the EXIT, and a coin is routinely in the opposite direction -- the same reason
# Golden Trail needs route_to() rather than route_from() (section 7).
func _toward_coin() -> int:
	var racer: Racer = _game.racer
	var maze: Maze = racer.maze
	if maze.coins.is_empty():
		return -1

	var targets := {}
	for c in maze.coins:
		targets[c] = true

	var came := {racer.cell: racer.cell}
	var queue: Array[Vector2i] = [racer.cell]
	var head := 0
	var found := Vector2i(-999, -999)
	# Bounded tightly: the tool wants a coin CLOSE BY, and flooding a
	# 100x100 grid per cell is what made the first version crawl.
	while head < queue.size() and head < 900:
		var at: Vector2i = queue[head]
		head += 1
		if targets.has(at) and at != racer.cell:
			found = at
			break
		for dir in maze.open_directions(at):
			var nxt: Vector2i = at + Maze.DIR_VECTORS[int(dir)]
			if came.has(nxt):
				continue
			came[nxt] = at
			queue.append(nxt)
	if found == Vector2i(-999, -999):
		return -1

	# Walk the parent chain back to the cell after the start.
	#
	# GUARDED. The start cell is its own parent, so a chain that reaches it
	# without matching spins forever -- a hang with no output, which reads as a
	# broken launcher rather than as a bad loop (the wait-loop trap section 12
	# records for the harnesses).
	var step: Vector2i = found
	var hops := 0
	while came.has(step) and came[step] != racer.cell and hops < 4000:
		step = came[step]
		hops += 1
	if hops >= 4000:
		return -1
	var delta: Vector2i = step - racer.cell
	for dir in Maze.DIRS:
		if Maze.DIR_VECTORS[dir] == delta:
			return int(dir)
	return -1


func _capture(index: int, tag: String) -> void:
	var image := root.get_texture().get_image()
	var name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var path := "res://logs/coin_%d_%s_%s.png" % [index + 1, name, tag]
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, coins %d/%d, banked %d)" % [
			path, _game.racer.cell, _game.racer.coins,
			_game.racer.coin_cap, _game.racer.coins_banked])
	else:
		printerr("FAILED to save %s" % path)
