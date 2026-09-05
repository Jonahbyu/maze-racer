# Not a test -- an instrument. Reports how many repeat cells each of three
# driving styles accumulates on a real maze, which is how the repeat penalty gets
# sanity-checked against play rather than against a model.
#
# The question it answers: does the penalty stay off an honest player's back?
# An optimal router should pay nothing, a wandering one should pay steadily, and
# a deliberate farmer should pay catastrophically.
extends SceneTree


func _init() -> void:
	print("=== RepeatProbe ===")
	var config: Dictionary = Tuning.MAZES[0]
	var m := Maze.new()
	m.generate(
		int(config["width"]),
		int(config["height"]),
		4242,
		float(config["braid"]),
		float(config["dead_ends"]),
		int(config["gates"]),
		float(config.get("straighten", 0.0)),
		float(config.get("shallow_keep", 1.0)),
		0.0,
		float(config.get("zigzag_keep", 1.0)))

	_drive("optimal router", m, 0)
	_drive("wanderer (turns at random)", m, 1)
	_drive("farmer (paces one corridor)", m, 2)
	quit()


func _drive(label: String, m: Maze, style: int) -> void:
	var u := Upgrades.new(7)
	var r := Racer.new()
	r.setup(m, u, 0)

	var sc := Score.new()
	r.turned.connect(func(_d): sc.add_turn(r.speed, r.last_turn_scraped))
	r.crashed.connect(func(): sc.add_crash())
	r.cell_entered.connect(func(_c, repeat, first_repeat):
		sc.on_repeat_ground = repeat
		if first_repeat:
			sc.add_repeat())

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var anchor := r.cell

	for frame in 12000:
		if r.finished or r.dead:
			break
		var d := 0.016
		match style:
			0:
				var best := m.best_direction(r.cell)
				if best != -1 and best != r.facing:
					r.request_turn(_key_for(r.facing, best))
			1:
				if rng.randf() < 0.10:
					r.request_turn(1 if rng.randf() < 0.5 else -1)
			2:
				# Pace back and forth along whatever corridor the racer is in.
				# Driven by CELLS COVERED, not by frame count: the racer starts
				# at 1x and accelerates, so a fixed frame interval reverses
				# before it has left the first cell and the "farmer" never
				# moves at all -- which reads as the penalty failing to fire
				# when in fact nothing was ever farmed.
				if absi(r.cell.x - anchor.x) + absi(r.cell.y - anchor.y) >= 8:
					r.request_reverse()
					anchor = r.cell
		if r.state == Racer.State.PARKED:
			r.request_reverse()
		r.step(d)
		sc.add_travel(d, r.speed)
		sc.advance_time(d)

	var repeat_cost := float(sc.repeat_cells) * Tuning.SCORE_REPEAT_CELL_PENALTY
	print("%-30s cells %4d  repeats %5d  cost %9.0f  subtotal %9.0f  finished %s" % [
		label, r.visited.size(), sc.repeat_cells, repeat_cost,
		sc.maze_subtotal, str(r.finished)
	])


func _key_for(facing: int, want: int) -> int:
	var order := [Maze.N, Maze.E, Maze.S, Maze.W]
	var i := order.find(facing)
	var j := order.find(want)
	return 1 if (i + 1) % 4 == j else -1
