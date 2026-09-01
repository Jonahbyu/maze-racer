# Headless probe: landmark placement per maze (docs/specs/landmarks.md).
#
# Not a test -- a measuring instrument for the `landmarks` knob in Tuning.MAZES.
# Reports how many landmarks each maze gets, how they split across the two
# tiers, and the type mix, so the density can be tuned without guessing and
# without anyone opening the editor.
#
# It also reports the two numbers that decide whether the feature is doing its
# job at all:
#
#   PER CORRIDOR   landmarks per 100 cells. Too low and a player crosses the
#                  maze without meeting one; too high and they are wallpaper,
#                  which is the failure mode one-cell stubs already hit
#                  (CLAUDE.md section 6) -- frequency was what was wrong there.
#
#   DEAD ENDS      the share of dead ends that got one. This is the placement
#                  that matters most: a dead end with a statue in it is a
#                  punishment the player REMEMBERS, so turning around at the
#                  same broken pillar twice is unambiguous evidence of a
#                  re-tried route.
extends SceneTree

const SEEDS := 6


func _init() -> void:
	for i in Tuning.MAZES.size():
		var cfg: Dictionary = Tuning.MAZES[i]
		var density := float(cfg.get("landmarks", Tuning.LANDMARK_DENSITY))

		var total := 0
		var skyline := 0
		var interior := 0
		var in_dead_end := 0
		var dead_ends := 0
		var cells := 0
		var by_type := {}

		for s in SEEDS:
			var maze := Maze.new()
			maze.generate(cfg["width"], cfg["height"], 1000 + s,
				cfg["braid"], cfg["dead_ends"], cfg["gates"],
				cfg.get("straighten", 0.0), cfg.get("shallow_keep", 1.0),
				density, cfg.get("zigzag_keep", 1.0))

			cells += maze.width * maze.height
			for y in maze.height:
				for x in maze.width:
					var c := Vector2i(x, y)
					if c == maze.start_cell or c == maze.exit_cell:
						continue
					if maze.open_directions(c).size() == 1:
						dead_ends += 1

			for landmark in maze.landmarks:
				total += 1
				var type_index := int(landmark["type"])
				var config: Dictionary = Tuning.LANDMARK_TYPES[type_index]
				if bool(config["skyline"]):
					skyline += 1
				by_type[config["name"]] = int(by_type.get(config["name"], 0)) + 1

				var cell: Vector2i = landmark["cell"]
				var inside := (cell.x >= 0 and cell.x < maze.width
					and cell.y >= 0 and cell.y < maze.height)
				if inside:
					interior += 1
					if maze.open_directions(cell).size() == 1:
						in_dead_end += 1

		var n := float(SEEDS)
		print("%-14s density %.2f   total %6.1f   skyline %4.0f%%   per 100 cells %.2f" % [
			cfg["name"], density, total / n,
			0.0 if total == 0 else 100.0 * float(skyline) / float(total),
			100.0 * float(interior) / float(cells),
		])
		print("%-14s   dead ends %5.1f, with a landmark %5.1f (%.0f%%)   exterior %.1f" % [
			"", dead_ends / n, in_dead_end / n,
			0.0 if dead_ends == 0 else 100.0 * float(in_dead_end) / float(dead_ends),
			(total - interior) / n,
		])

		var mix: Array[String] = []
		for key in by_type:
			mix.append("%s %.0f" % [key, float(by_type[key]) / n])
		mix.sort()
		print("%-14s   %s" % ["", " | ".join(mix)])

	quit()
