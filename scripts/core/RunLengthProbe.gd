# Headless probe: straight-run length distribution per maze.
#
# Not a test -- a measuring instrument for Maze.MAX_STRAIGHT_CELLS. A "straight
# run" is what the player experiences: consecutive cells with no opening to
# either side, so there is nothing to read and nothing to decide. The cap pass
# is supposed to bound this; "over cap" must always be 0.
extends SceneTree

const SEEDS := 6


func _init() -> void:
	for i in Tuning.MAZES.size():
		var cfg: Dictionary = Tuning.MAZES[i]
		var longest := 0
		var total := 0
		var count := 0
		var over := 0

		for s in SEEDS:
			var maze := Maze.new()
			maze.generate(cfg["width"], cfg["height"], 1000 + s,
				cfg["braid"], cfg["dead_ends"], cfg["gates"],
				cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0))

			for r in _runs(maze):
				total += r
				count += 1
				longest = maxi(longest, r)
				if r > Maze.MAX_STRAIGHT_CELLS:
					over += 1

		print("%-14s avg %.2f   longest %2d   over cap: %d" % [
			cfg["name"], float(total) / float(count), longest, over])
	quit()


func _runs(maze: Maze) -> Array:
	var out: Array = []
	for axis in [true, false]:
		var run_dir: int = Maze.E if axis else Maze.S
		var sides: Array = [Maze.N, Maze.S] if axis else [Maze.E, Maze.W]
		var outer: int = maze.height if axis else maze.width
		var inner: int = maze.width if axis else maze.height

		for a in outer:
			var n := 0
			for b in inner:
				var cell := Vector2i(b, a) if axis else Vector2i(a, b)
				n += 1
				var has_side := false
				for d in sides:
					if maze.is_open(cell, d):
						has_side = true
						break
				if has_side or not maze.is_open(cell, run_dir):
					out.append(n)
					n = 0
			if n > 0:
				out.append(n)
	return out
