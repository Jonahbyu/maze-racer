# Headless probe: dead-end density and one-cell-stub frequency per maze.
#
# Not a test -- a measuring instrument for the two knobs in Tuning.MAZES
# (`dead_ends` and `shallow_keep`). Reports overall dead ends, how many are
# shallow stubs forcing an immediate 180, and how many sit directly off the
# canonical solve path where the player actually meets them.
extends SceneTree

const SEEDS := 8


func _init() -> void:
	for i in Tuning.MAZES.size():
		var cfg: Dictionary = Tuning.MAZES[i]
		var de := 0
		var sh := 0
		var adj := 0
		var cells := 0

		for s in SEEDS:
			var maze := Maze.new()
			maze.generate(cfg["width"], cfg["height"], 1000 + s,
				cfg["braid"], cfg["dead_ends"], cfg["gates"],
				cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0))

			var on_route := {}
			for c in maze.solve_path:
				on_route[c] = true

			cells += maze.width * maze.height
			for y in maze.height:
				for x in maze.width:
					var c := Vector2i(x, y)
					if c == maze.start_cell or c == maze.exit_cell:
						continue
					var dirs := maze.open_directions(c)
					if dirs.size() != 1:
						continue
					de += 1
					if maze._is_shallow_dead_end(c):
						sh += 1
					if on_route.has(c + Maze.DIR_VECTORS[dirs[0]]):
						adj += 1

		var n := float(SEEDS)
		print("%-14s dead ends %6.1f (%.2f%%)   stubs %6.1f (%.0f%% of them)   beside route %5.1f" % [
			cfg["name"], de / n, 100.0 * float(de) / float(cells),
			sh / n, 0.0 if de == 0 else 100.0 * float(sh) / float(de), adj / n,
		])

	quit()
