# Reports the equilibrium speed a build actually settles at.
#
# NOT a test. Section 5.3 calls the ramp rate and the turn cost "the single most
# sensitive pair of numbers in the game" and says to RE-DERIVE rather than
# re-guess when either moves. Momentum moves the ramp directly, so this is the
# instrument that answers what it actually did.
#
# It exists because RunTest cannot answer it: RunTest's autopilot takes whatever
# cards it is offered, and a single run took Momentum only to rank 1 of 4 -- so
# its final speed says nothing about the line's ceiling, which is the number the
# section 5.3 formula is about. This drives an optimal router with the ranks
# FORCED, one configuration at a time.
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Momentum equilibrium (measured, not derived) ===")
	print("section 5.3: equilibrium = RAMP_PER_SEC / (turn_ratio * TURN_COST)")
	print("")
	print("%-28s %10s %10s %10s" % ["build", "final", "peak", "turns/s"])

	# Momentum alone, rank by rank -- the line's own contribution.
	for r in range(0, 5):
		_measure("Momentum %d" % r, {Upgrades.Line.MOMENTUM: r})

	# The pairing that section 7 flags as bringing the cap within reach: the
	# ramp raised and the turn cost cut at the same time, which are the two
	# halves of the equilibrium formula moving together.
	_measure("Momentum 4 + Cornering 3", {
		Upgrades.Line.MOMENTUM: 4,
		Upgrades.Line.CORNERING: 3,
	})
	_measure("Cornering 3 only", {Upgrades.Line.CORNERING: 3})

	# Maze 1 finishes in ~41s, which is BEFORE the ramp settles -- so the numbers
	# above are what a build reaches on maze 1, not the equilibrium itself. Maze 5
	# is the longest run in the game and is where the settling point is visible.
	print("")
	print("--- maze 5 (the longest run: where the ramp actually settles) ---")
	for r in range(0, 5):
		_measure("Momentum %d" % r, {Upgrades.Line.MOMENTUM: r}, 4)
	_measure("Momentum 4 + Cornering 3", {
		Upgrades.Line.MOMENTUM: 4,
		Upgrades.Line.CORNERING: 3,
	}, 4)

	print("")
	print("SPEED_CAP = %.1fx" % Tuning.SPEED_CAP)
	quit()


# Drive one maze on an optimal router with `build` forced, and report where the
# speed settles.
func _measure(label: String, build: Dictionary, maze_index: int = 0) -> void:
	var upgrades := Upgrades.new(1)
	for line in build:
		for i in int(build[line]):
			upgrades.take(line)

	var maze := Maze.new()
	# A fixed seed: a wall-clock seed makes this answer "did we get lucky"
	# rather than "what does this build settle at" (section 12). Maze 1's own
	# config is read from Tuning rather than restated, so the turn ratio measured
	# here is the one the game actually generates.
	var cfg: Dictionary = Tuning.MAZES[maze_index]
	maze.generate(
		int(cfg["width"]),
		int(cfg["height"]),
		20250905,
		float(cfg["braid"]),
		float(cfg["dead_ends"]),
		int(cfg["gates"]),
		float(cfg.get("straighten", 0.0)),
		float(cfg.get("shallow_keep", 1.0)),
		0.0,
		float(cfg.get("zigzag_keep", 1.0))
	)

	var racer := Racer.new()
	racer.setup(maze, upgrades, maze_index)

	var peak := 0.0
	var turns := 0
	var elapsed := 0.0
	var dt := 1.0 / 60.0
	var last_cell := Vector2i(-999, -999)

	# Long enough for the ramp to reach its settling point against the turn
	# cost, which is what "equilibrium" means here -- not the maze's solve time.
	for frame in 30000:
		if racer.finished or racer.dead:
			break
		# Steered ONCE PER CELL, exactly as RunTest's autopilot does. Re-requesting
		# every frame instead spams the buffer: the first version of this probe did
		# that and measured a racer that crashed 13 times and died after 122 cells,
		# which reads as an equilibrium of 1.0x and is in fact no equilibrium at all.
		if racer.state == Racer.State.PARKED:
			racer.request_reverse()
			last_cell = Vector2i(-999, -999)
		elif racer.cell != last_cell:
			last_cell = racer.cell
			var want := maze.best_direction(racer.cell)
			if want != -1 and want != racer.facing:
				# Requested, not forced, so every turn pays the ordinary cost --
				# that cost is one half of the formula being measured.
				if want == racer.left_direction():
					racer.request_turn(-1)
					turns += 1
				elif want == racer.right_direction():
					racer.request_turn(1)
					turns += 1
				else:
					racer.request_reverse()
					turns += 1
		racer.step(dt)
		elapsed += dt
		peak = maxf(peak, racer.speed)

	var rate := float(turns) / maxf(elapsed, 0.001)
	print("%-28s %9.2fx %9.2fx %10.2f  crashes=%d scrapes=%d cells=%.0f t=%.0fs fin=%s dead=%s" % [
		label, racer.speed, peak, rate, racer.crash_count, racer.scrape_count,
		racer.distance_travelled, elapsed, str(racer.finished), str(racer.dead)])
