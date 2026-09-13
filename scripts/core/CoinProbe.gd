extends SceneTree

func _init() -> void:
	print("=== CoinProbe ===\n")
	for i in Tuning.MAZES.size():
		var cfg: Dictionary = Tuning.MAZES[i]
		var m := Maze.new()
		var d: float = Tuning.COIN_DENSITY_BY_MAZE[i] if i < Tuning.COIN_DENSITY_BY_MAZE.size() else Tuning.COIN_DENSITY
		m.generate(int(cfg["width"]), int(cfg["height"]), 1000 + i * 7919,
			float(cfg["braid"]), float(cfg["dead_ends"]), int(cfg["gates"]),
			float(cfg.get("straighten", 0.0)), float(cfg.get("shallow_keep", 1.0)),
			0.0, float(cfg.get("zigzag_keep", 1.0)), d)
		# How many coins sit ON the canonical solve path -- the routing-leak check.
		var path := {}
		for c in m.solve_path:
			path[c] = true
		var on_path := 0
		var dupes := {}
		var bad := 0
		for c in m.coins:
			if path.has(c):
				on_path += 1
			if dupes.has(c):
				bad += 1
			dupes[c] = true
			if c == m.start_cell or c == m.exit_cell:
				bad += 1
			if m.open_directions(c).is_empty():
				bad += 1
		var cells := m.width * m.height
		printf_row(i, cfg, m.coins.size(), cells, on_path, m.solve_path.size(), bad)
	quit(0)

func printf_row(i: int, cfg: Dictionary, n: int, cells: int, on_path: int, path_len: int, bad: int) -> void:
	var share := 100.0 * float(on_path) / maxf(1.0, float(n))
	var path_share := 100.0 * float(path_len) / float(cells)
	print("maze %d %-14s coins %4d  of %5d cells (%.2f%%)  on solve path %3d (%.1f%%, path is %.1f%% of grid)  invalid %d" % [
		i + 1, cfg["name"], n, cells, 100.0 * n / cells, on_path, share, path_share, bad])
