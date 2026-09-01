# Headless probe: forced immediate turns -- corner-into-corner zigzags.
#
# Not a test -- a measuring instrument for the `zigzag_keep` knob in
# Tuning.MAZES, the same way DeadEndProbe measures `shallow_keep`.
#
# A CORNER is a cell with exactly two openings that are perpendicular: you come
# in one side and the only way on is a 90. It forces an input, with no option to
# hold the line. A ZIGZAG is a corner whose exit leads straight into another
# corner, so the player pays two commits back to back with no straight cell in
# between to read the second one -- at 6x that is ~330ms for two decisions.
#
# Reported both over the whole grid and ALONG THE CANONICAL SOLVE PATH, because
# the second is what the player actually drives through. A maze can carry plenty
# of zigzags in its backwaters and still feel clean on the route.
extends SceneTree

const SEEDS := 8


func _init() -> void:
	_report()
	quit()


func _report() -> void:
	for i in Tuning.MAZES.size():
		var cfg: Dictionary = Tuning.MAZES[i]
		var corners := 0
		var zig := 0
		var chains := 0
		var route_cells := 0
		var route_zig := 0
		var cells := 0

		for s in SEEDS:
			var maze := Maze.new()
			maze.generate(cfg["width"], cfg["height"], 1000 + s,
				cfg["braid"], cfg["dead_ends"], cfg["gates"],
				cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0), 0.0,
				cfg.get("zigzag_keep", 1.0))

			cells += maze.width * maze.height
			for y in maze.height:
				for x in maze.width:
					var c := Vector2i(x, y)
					if not _is_corner(maze, c):
						continue
					corners += 1
					if _zigzag_at(maze, c):
						zig += 1
					if _chain_len(maze, c) >= 3:
						chains += 1

			# Along the route the player actually drives.
			var path := maze.solve_path
			route_cells += path.size()
			for j in range(1, path.size() - 2):
				if _turn_at(path, j) != 0 and _turn_at(path, j + 1) != 0:
					route_zig += 1

		var n := float(SEEDS)
		print("%-14s corners %6.1f (%.1f%%)  zigzags %6.1f (%.0f%% of corners)  3+chains %5.1f  |  route %5.1f turns-in-a-row per run (%.1f%% of route)" % [
			cfg["name"], corners / n, 100.0 * float(corners) / float(cells),
			zig / n, 0.0 if corners == 0 else 100.0 * float(zig) / float(corners),
			chains / n, route_zig / n,
			0.0 if route_cells == 0 else 100.0 * float(route_zig) / float(route_cells),
		])



# Exactly two openings, perpendicular to each other. Straight-through corridors
# and junctions are both excluded: a junction offers a CHOICE, which is the
# thing the game is about, while a corner offers only an obligation.
static func _is_corner(maze: Maze, c: Vector2i) -> bool:
	var dirs := maze.open_directions(c)
	if dirs.size() != 2:
		return false
	return int(dirs[0]) != int(Maze.OPPOSITE[dirs[1]])


# Does either exit of this corner lead directly into another corner?
static func _zigzag_at(maze: Maze, c: Vector2i) -> bool:
	for dir in maze.open_directions(c):
		if _is_corner(maze, c + Maze.DIR_VECTORS[dir]):
			return true
	return false


# Longest chain of adjacent corners running through this cell.
static func _chain_len(maze: Maze, c: Vector2i) -> int:
	var best := 1
	for dir in maze.open_directions(c):
		var n := 1
		var at := c
		var d: int = dir
		while true:
			var next: Vector2i = at + Maze.DIR_VECTORS[d]
			if not _is_corner(maze, next):
				break
			n += 1
			at = next
			var onward := -1
			for e in maze.open_directions(at):
				if int(e) != int(Maze.OPPOSITE[d]):
					onward = e
					break
			if onward == -1:
				break
			d = onward
		best = maxi(best, n)
	return best


# Does the route turn at path[i]? Returns 0 for straight.
static func _turn_at(path: Array[Vector2i], i: int) -> int:
	var a: Vector2i = path[i] - path[i - 1]
	var b: Vector2i = path[i + 1] - path[i]
	if a == b:
		return 0
	return 1
