# Captures a frame near a landmark in each maze, to check they actually render
# and read the way docs/specs/landmarks.md intends.
#
# Not a test -- there is no assertion that can tell you a spire looks like a
# spire, or that it is legible against the maze's own neon.
#
# It SEEKS a landmark rather than shooting on a timer, for the same reason
# PaletteShot seeks a junction: a shot taken at a fixed frame lands in a plain
# corridor and shows nothing of the thing being checked. The camera is capped
# below WALL_HEIGHT on purpose, so a skyline landmark is only in frame when the
# player is genuinely near it.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _last_cell := Vector2i(-999, -999)
var _target := Vector2i(-999, -999)
var _settle := 0
var _armed := false

const SETTLE := 45
const GIVE_UP := 2400

# How close, in cells, counts as "in frame". Skyline landmarks clear the wall
# line so they are visible further off, but a shot from across the maze shows a
# speck -- this is tuned for a frame where the shape is actually readable.
const NEAR_CELLS := 1.6

# Frames to let the renderer draw before reading the framebuffer.
const SETTLE_FRAMES := 12


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	# Once the seek has succeeded, STOP DRIVING and let the frame settle in
	# place. Continuing to autopilot through the settle window drove the racer
	# straight past the landmark it had just found, so the captured frame showed
	# the corridor beyond it -- or, at a maze edge, a wall and nothing else.
	if _armed:
		if _settle > 0:
			_settle -= 1
			return
		_shoot()
		return

	_autopilot()

	if _frame < SETTLE:
		return
	if not _near_landmark() and _frame < GIVE_UP:
		return

	# Face the landmark before shooting, so it is in frame rather than behind
	# the camera -- a dead-end landmark is BEHIND the racer the moment it has
	# driven in and reversed out.
	_armed = true
	_settle = SETTLE_FRAMES


func _shoot() -> void:

	# The renderer has had SETTLE_FRAMES to draw by now. Capturing on the same
	# frame the seek succeeded gave a flat blue image with only the HUD on it --
	# the 3D world had not been drawn into the viewport texture yet, which looks
	# exactly like "the maze failed to build" and is not.
	_capture(_maze_index)
	_armed = false
	_frame = 0
	_maze_index += 1

	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	_game._start_maze(_maze_index)
	_last_cell = Vector2i(-999, -999)
	_target = Vector2i(-999, -999)


# Drive TOWARD the nearest landmark rather than toward the exit.
#
# The solve-path autopilot every other tool uses is optimal, and landmarks are
# deliberately placed OFF the route -- in sealed pockets and dead ends -- so
# following the distance field is the one policy guaranteed never to arrive at
# one. Same trap as SceneTest's wall-indicator check, which could not reach a
# dead end while it steered by best_direction (CLAUDE.md section 12).
func _autopilot() -> void:
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

	if _target == Vector2i(-999, -999):
		_target = _nearest_landmark_cell(racer)

	# BFS toward the target rather than a greedy step toward it.
	#
	# Greedy stalls: it walks into the wall of the pocket it is aiming at and
	# then oscillates, because "closest in a straight line" is not "reachable".
	# That produced a blank first frame and a maze the tool never got near.
	var best_dir := _next_step_toward(racer.maze, racer.cell, _target)

	if best_dir == -1 or best_dir == racer.facing:
		return
	if best_dir == racer.left_direction():
		racer.request_turn(-1)
	elif best_dir == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


# The first step of a shortest path from `from` toward `goal`, or -1.
#
# BFS runs OUTWARD FROM THE GOAL so the result is a direction to walk, and it
# stops at whatever it can actually reach. A landmark in a sealed pocket is
# unreachable by construction -- that is why it is safe to put one there -- so
# the search accepts arriving ADJACENT to the goal, which is close enough to
# put it in frame.
func _next_step_toward(maze: Maze, from: Vector2i, goal: Vector2i) -> int:
	if goal == Vector2i(-999, -999):
		return -1

	var dist := {}
	var queue: Array[Vector2i] = []

	# Seed from the goal if it is drivable, otherwise from its open neighbours.
	if maze.open_directions(goal).size() > 0:
		dist[goal] = 0
		queue.append(goal)
	else:
		for dir in Maze.DIRS:
			var side: Vector2i = goal + Maze.DIR_VECTORS[dir]
			if side.x < 0 or side.x >= maze.width or side.y < 0 or side.y >= maze.height:
				continue
			dist[side] = 0
			queue.append(side)

	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == from:
			break
		for dir in maze.open_directions(cell):
			var next: Vector2i = cell + Maze.DIR_VECTORS[dir]
			if dist.has(next):
				continue
			dist[next] = int(dist[cell]) + 1
			queue.append(next)

	if not dist.has(from):
		return -1

	# Step to whichever open neighbour is one closer to the goal.
	var here: int = dist[from]
	for dir in maze.open_directions(from):
		var next: Vector2i = from + Maze.DIR_VECTORS[dir]
		if dist.has(next) and int(dist[next]) < here:
			return int(dir)
	return -1


func _nearest_landmark_cell(racer: Racer) -> Vector2i:
	var best := Vector2i(-999, -999)
	var best_gap := 1e20
	for landmark in racer.maze.landmarks:
		var cell: Vector2i = landmark["cell"]
		# Interior only. The exterior ring is outside the boundary wall and
		# cannot be driven to at all.
		if cell.x < 0 or cell.x >= racer.maze.width:
			continue
		if cell.y < 0 or cell.y >= racer.maze.height:
			continue
		# Prefer a DEAD END. Those are the ones the player can actually drive
		# into, so they frame the landmark from inside the cell rather than
		# across a wall -- and they are where the local tier lives, which a
		# nearest-first seek otherwise never shows.
		if racer.maze.open_directions(cell).size() != 1:
			continue
		var gap := Vector2(cell - racer.cell).length()
		if gap < best_gap:
			best_gap = gap
			best = cell
	return best


func _near_landmark() -> bool:
	var racer: Racer = _game.racer
	if racer == null or racer.maze == null:
		return false
	for landmark in racer.maze.landmarks:
		var cell: Vector2i = landmark["cell"]
		if Vector2(cell - racer.cell).length() <= NEAR_CELLS:
			return true
	return false


func _capture(index: int) -> void:
	var image := root.get_texture().get_image()
	var maze_name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var path := "res://logs/landmark_%d_%s.png" % [index + 1, maze_name]

	var racer: Racer = _game.racer
	var nearby: Array[String] = []
	if racer != null and racer.maze != null:
		for landmark in racer.maze.landmarks:
			var cell: Vector2i = landmark["cell"]
			var gap := Vector2(cell - racer.cell).length()
			if gap <= NEAR_CELLS + 2.0:
				nearby.append("%s@%.1f" % [
					Tuning.LANDMARK_TYPES[int(landmark["type"])]["name"], gap])

	if image.save_png(path) == OK:
		print("saved %s  (cell %s, near: %s)" % [
			path, racer.cell, "none" if nearby.is_empty() else ", ".join(nearby)])
	else:
		printerr("FAILED to save %s" % path)
