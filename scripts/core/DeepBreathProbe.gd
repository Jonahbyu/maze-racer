# Reports what Deep Breath actually costs and pays, per rank.
#
# NOT a test. The line now lets the ramp RUN through the extension, which
# reverses the rule that held before the cooldown existed -- so the question
# section 5.3 insists on asking is live again: what does this do to the speed
# the racer settles at, and to the maze budget it spends getting there.
#
# It exists because neither RunTest nor RulesTest can answer it. RunTest's
# autopilot never HOLDS a direction, so it never triggers an extension at all --
# its final speed is the same with the line maxed and untaken. RulesTest asserts
# one extension in isolation, which says nothing about ~6 of them a minute
# compounding across a whole maze.
#
# The pair of columns that matters is `final` against `t`: the ramp gain is only
# a problem if it arrives without a matching cost in the section 8b currency.
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Deep Breath: what the held extension costs and pays ===")
	print("extension by rank : %s" % str(Tuning.DEEP_BREATH_BY_RANK))
	print("cooldown          : %.1fs" % Tuning.DEEP_BREATH_COOLDOWN)
	print("ramp              : RUNS through the extension (Jonah's call)")
	print("")
	print("%-22s %8s %8s %8s %8s %8s" % [
		"build", "final", "peak", "time", "uses", "turns/s"])

	# Maze 5 is the longest run in the game and so the one where the ramp
	# actually settles -- maze 1 finishes in ~41s, before the settling point,
	# which is the trap MomentumProbe records for its own maze-1 column.
	print("--- maze 5 (where the ramp settles), direction HELD throughout ---")
	for r in range(0, Tuning.DEEP_BREATH_BY_RANK.size()):
		_measure("Deep Breath %d" % r, r, true, 4)

	# The control: the same build NOT holding. The difference between the two is
	# the whole of what the line does, and it is the number that says whether
	# "the ramp runs" is a pump or merely a relief.
	print("")
	print("--- maze 5, control: same build, direction NOT held ---")
	for r in range(0, Tuning.DEEP_BREATH_BY_RANK.size()):
		_measure("Deep Breath %d" % r, r, false, 4)

	print("")
	print("SPEED_CAP = %.1fx" % Tuning.SPEED_CAP)
	print("maze budget = %.0fs (section 8b)" % Tuning.SCORE_TIME_BUDGET)
	quit()


# Drive one maze on an optimal router at a forced Deep Breath rank.
#
# `hold` decides whether the turn key stays down after each request, which is
# the entire gesture: the racer reads `held_direction`, never input.
func _measure(label: String, rank: int, hold: bool, maze_index: int = 0) -> void:
	var upgrades := Upgrades.new(1)
	for i in rank:
		upgrades.take(Upgrades.Line.DEEP_BREATH)

	var maze := Maze.new()
	# A fixed seed, and maze config read from Tuning rather than restated, so the
	# turn ratio measured here is the one the game actually generates.
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

	# Counts extensions by watching the freeze exceed what an ordinary turn can
	# produce. Derived from the upgrade's own numbers rather than a literal, so a
	# retune cannot leave this counting the wrong thing.
	var ordinary := maxf(upgrades.turn_freeze(), upgrades.reverse_freeze())
	var uses := 0
	var was_extended := false

	for frame in 30000:
		if racer.finished or racer.dead:
			break

		# Steered ONCE PER CELL, never once per frame: re-requesting every frame
		# spams the buffer, which is the failure MomentumProbe and RepeatProbe
		# both record -- it measures a dying racer rather than a settling one.
		if racer.state == Racer.State.PARKED:
			racer.request_reverse()
			racer.held_direction = 0
			last_cell = Vector2i(-999, -999)
		elif racer.cell != last_cell:
			last_cell = racer.cell
			var want := maze.best_direction(racer.cell)
			if want != -1 and want != racer.facing:
				if want == racer.left_direction():
					racer.request_turn(-1)
					if hold:
						racer.held_direction = -1
					turns += 1
				elif want == racer.right_direction():
					racer.request_turn(1)
					if hold:
						racer.held_direction = 1
					turns += 1
				else:
					racer.request_reverse()
					turns += 1

		racer.step(dt)
		elapsed += dt
		peak = maxf(peak, racer.speed)

		# One use per freeze that runs longer than any ordinary turn could.
		var extended := racer.freeze > ordinary + 0.001
		if extended and not was_extended:
			uses += 1
		was_extended = extended

	var rate := float(turns) / maxf(elapsed, 0.001)
	print("%-22s %7.2fx %7.2fx %7.0fs %8d %8.2f" % [
		label, racer.speed, peak, elapsed, uses, rate])
