# Boots the real Main scene headlessly and drives it, to catch the runtime
# errors that a pure-logic harness cannot see: bad node setup, missing theme
# properties, signal wiring, null derefs in _process, UI construction.
#
# RulesTest proves the rules are right. This proves the game actually runs.
extends SceneTree

# Seed for the wall-indicator check's maze. Any seed whose maze 1 puts a dead
# end within reach of the seeker inside the frame budget will do; this one is
# checked in because the check must not depend on the wall clock.
const INDICATOR_SEED := 20250829

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== SceneTest ===")
	# Deferred so the scene tree is up before the scene is instantiated.
	_run.call_deferred()


func check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _run() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	check("Game.tscn loads", scene != null)
	if scene == null:
		_finish()
		return

	var game = scene.instantiate()
	check("Game.tscn instantiates", game != null)
	if game == null:
		_finish()
		return

	root.add_child(game)

	# _ready runs on add_child, so the maze and racer must exist now.
	check("maze generated", game.maze != null)
	check("racer created", game.racer != null)
	check("upgrades created", game.upgrades != null)
	check("starts racing", game.phase == 0)

	if game.maze != null:
		check("maze is maze 1 size", game.maze.width == 60 and game.maze.height == 60,
			"got %dx%d" % [game.maze.width, game.maze.height])
		# Read the count from the tuning table rather than restating it. The
		# per-maze gate count is a knob (Tuning.MAZES); a literal here just
		# means the test has to be edited every time it moves, which makes it a
		# transcription check rather than a real assertion.
		var want_gates := int(Tuning.MAZES[0]["gates"])
		check("gate count matches tuning", game.maze.gates.size() == want_gates,
			"got %d, tuning says %d" % [game.maze.gates.size(), want_gates])
		check("solve path found", game.maze.solve_path.size() > 0,
			"got %d" % game.maze.solve_path.size())

	# Drive real frames. This is what exercises _process, the camera, and the
	# whole HUD update path -- where a missing theme override or a null would
	# otherwise only show up in front of a player.
	for i in 120:
		game._process(0.016)

	check("survived 120 frames", true)
	check("racer moved", game.racer.distance_travelled > 0.0,
		"travelled %f" % game.racer.distance_travelled)
	check("timer advanced", game.elapsed > 0.0)

	# Input routing.
	game.racer.request_turn(-1)
	game.racer.request_turn(1)
	game.racer.request_reverse()
	for i in 30:
		game._process(0.016)
	check("survived input", true)

	# Force a gate to confirm the upgrade screen builds and resolves. Building
	# that UI is the most node-heavy thing in the game and the most likely to
	# break silently.
	var before: int = game.upgrades.started_line_count()
	game._on_gate_entered(1)
	check("gate pauses the run", game.phase == 1)
	check("minimap blurs at a gate", game._minimap.blurred)

	var offered: Array = game._upgrade_screen._lines
	check("cards were offered", offered.size() > 0, "got %d" % offered.size())

	if offered.size() > 0:
		game._on_upgrade_chosen(offered[0])
		check("choosing resumes racing", game.phase == 0)
		check("minimap unblurs after the pick", not game._minimap.blurred)
		check("upgrade was applied", game.upgrades.started_line_count() > before)

	# Run on with an upgrade in hand, which turns on the indicator/minimap draw
	# paths that were inert before.
	for i in 120:
		game._process(0.016)
	check("survived post-upgrade frames", true)

	# Every upgrade line must survive being applied and rendered -- a bad
	# derived stat or a bad draw call would surface here.
	for line in Upgrades.Line.values():
		game.upgrades.take(line)
	for i in 60:
		game._process(0.016)
	check("survived with every upgrade line taken", true)

	# And the maze-complete path.
	game._on_exit_reached()
	check("exit advances phase", game.phase == 2 or game.phase == 3)

	_check_wall_winding()
	_check_path_indicator(game)
	_check_wall_indicator(game)
	_check_camera_never_clips(game)
	_check_crash_camera(game)
	_check_pause(game)
	_check_landmark_meshes(game)

	_finish()


# The Path Indicator must light real wall panels at a junction, and go dark
# everywhere else.
#
# This is the assertion that stops it silently reverting to "floating in the
# air": every lit panel is checked to be flush against an actual wall face. A
# panel positioned in open space would still LOOK lit from most angles and would
# never be caught by a smoke test that only asks whether the node is visible.
func _check_path_indicator(game) -> void:
	var indicator: PathIndicator = game._path_indicator
	check("path indicator exists", indicator != null)
	if indicator == null:
		return

	var maze: Maze = game.maze
	var racer: Racer = game.racer
	if maze == null or racer == null:
		return

	# The upgrade is already taken by this point in _run(); assert that rather
	# than assume it, since the whole check is inert without it.
	check("path indicator upgrade is active", game.upgrades.has_indicator())

	var junctions := 0
	var lit_somewhere := false
	var off_wall := 0
	var lit_at_corner := 0

	# Walk the maze and drive the indicator through real cells rather than
	# waiting for an autopilot to wander into a junction -- the same reason the
	# wall-indicator check seeks its own fixture.
	for y in maze.height:
		for x in maze.width:
			if junctions >= 40:
				break
			var cell := Vector2i(x, y)
			for dir in Maze.DIRS:
				var d := int(dir)
				if not maze.is_open(cell, d):
					continue

				var behind := int(Maze.OPPOSITE[d])
				var onward := 0
				for o in maze.open_directions(cell):
					if int(o) != behind:
						onward += 1

				racer.cell = cell
				racer.facing = d
				racer.progress = 0.0
				indicator.update_state(racer, game.upgrades, 0.016)

				var lit := 0
				for panel in indicator.get_children():
					if not panel.visible:
						continue
					lit += 1
					if not _panel_is_on_a_wall(maze, panel):
						off_wall += 1

				if onward >= 2:
					junctions += 1
					if lit > 0:
						lit_somewhere = true
				elif lit > 0:
					# A corner is not a decision. Lighting one is the noise this
					# was narrowed to avoid.
					lit_at_corner += 1
				break
		if junctions >= 40:
			break

	check("path indicator found junctions to test", junctions > 0,
		"checked %d" % junctions)
	check("path indicator lights at a junction", lit_somewhere)
	check("path indicator panels sit on a wall, not in the air", off_wall == 0,
		"%d panels were not against any wall face" % off_wall)
	check("path indicator stays dark where there is no choice", lit_at_corner == 0,
		"%d corners were lit" % lit_at_corner)


# Is this panel flush against a real wall face?
#
# A panel is placed half a cell out from some cell centre along one axis. So the
# cell it belongs to is the one it rounds to, the axis it is offset along names
# the wall, and that wall must actually be solid.
func _panel_is_on_a_wall(maze: Maze, panel: Node3D) -> bool:
	var pos: Vector3 = panel.position
	var cell := Vector2i(
		int(round(pos.x / Tuning.CELL_SIZE)),
		int(round(pos.z / Tuning.CELL_SIZE)))
	if not maze._in_bounds(cell):
		return false

	var offset := Vector3(
		pos.x - float(cell.x) * Tuning.CELL_SIZE,
		0.0,
		pos.z - float(cell.y) * Tuning.CELL_SIZE)

	var dir := -1
	if absf(offset.x) > absf(offset.z):
		dir = Maze.E if offset.x > 0.0 else Maze.W
	else:
		dir = Maze.S if offset.z > 0.0 else Maze.N

	# It has to be pushed out to (near) the face, not sitting mid-cell.
	var reach: float = maxf(absf(offset.x), absf(offset.z))
	if reach < Tuning.CELL_SIZE * 0.4:
		return false

	return not maze.is_open(cell, dir)


# The third-person camera must never end up inside a wall or outside the maze.
#
# It trails the player by more than a metre, so a dead end, a fresh corner, or
# the maze boundary can all put it in geometry -- and a camera inside a wall box
# fills the screen with one flat face. Screenshots only sample a few moments;
# this drives thousands of frames including every turn.
func _check_camera_never_clips(game) -> void:
	var to_face: float = Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5
	var last := Vector2i(-999, -999)
	var bad := 0
	var blind := 0
	var frames := 2000

	for i in frames:
		var racer: Racer = game.racer

		if game.phase == 1:
			var offered: Array = game._upgrade_screen._lines
			game._on_upgrade_chosen(offered[0] if offered.size() > 0 else -1)
		elif game.phase == 0:
			if racer.state == Racer.State.PARKED:
				racer.request_reverse()
				last = Vector2i(-999, -999)
			elif racer.cell != last:
				last = racer.cell
				var best := racer.maze.best_direction(racer.cell)
				if best != -1 and best != racer.facing:
					if best == racer.left_direction():
						racer.request_turn(-1)
					elif best == racer.right_direction():
						racer.request_turn(1)
					else:
						racer.request_reverse()

		game._process(1.0 / 60.0)

		var p: Vector3 = game._camera.position
		var cell := Vector2i(
			int(round(p.x / Tuning.CELL_SIZE)),
			int(round(p.z / Tuning.CELL_SIZE))
		)

		if not game.maze._in_bounds(cell):
			bad += 1
			continue

		var centre := Vector3(cell.x * Tuning.CELL_SIZE, 0.0, cell.y * Tuning.CELL_SIZE)
		var offset := Vector3(p.x, 0.0, p.z) - centre

		if absf(offset.x) > to_face:
			var dir := Maze.E if offset.x > 0.0 else Maze.W
			if not game.maze.is_open(cell, dir):
				bad += 1
				continue
		if absf(offset.z) > to_face:
			var dir := Maze.S if offset.z > 0.0 else Maze.N
			if not game.maze.is_open(cell, dir):
				bad += 1
				continue

		# The marker must never be hidden behind a wall (CLAUDE.md section 12).
		# A separate question from the clip check above: the eye can sit in
		# perfectly open space while the LINE to the marker cuts a corner, which
		# is exactly what happens swinging through a turn -- the wall just passed
		# wipes across the marker for a few frames.
		#
		# Checked in this loop rather than its own, because a second 2000-frame
		# autopilot doubles the harness runtime to assert over the same play.
		var marker := racer.world_position()
		marker.y = p.y
		if game._sight_blocked(p, marker):
			blind += 1

	check("camera never clips into a wall", bad == 0,
		"%d of %d frames inside geometry" % [bad, frames])
	check("the player marker is never hidden by a wall", blind == 0,
		"%d of %d frames with sight blocked" % [blind, frames])


# The wall indicator must only ever mark a REAL DEAD END.
#
# This is the design constraint, not an implementation detail: the mark says
# "not through here" and never "go left". If it ever lit up an open direction it
# would be answering routing, which is Path Indicator's job and the headline
# paid upgrade (CLAUDE.md section 7). And a cell with a turn available is not a
# dead end -- marking those fired the sign on roughly half the cells in a DFS
# maze, which is frequent enough to stop reading as a warning. A scan-loop tweak
# could break either half silently, so both are asserted over real play rather
# than eyeballed.
func _check_wall_indicator(game) -> void:
	var indicator = game._wall_indicator
	check("wall indicator exists", indicator != null)
	if indicator == null:
		return

	# Pin the maze. Game seeds itself from the wall clock, so this check drew a
	# different maze on every run and whether the autopilot met a dead end
	# inside the frame budget was luck -- it failed roughly two runs in three
	# once the one-cell stubs were culled. A fixed seed makes the check answer
	# "does the indicator obey its rule" rather than "did we get a lucky maze".
	# Verified to contain reachable dead ends within the frame budget.
	game.run_seed = INDICATOR_SEED
	game._start_maze(0)

	# Re-read racer and maze from `game` every frame, never cached: _start_maze
	# builds a NEW Racer and a NEW Maze for each maze in the run, so a
	# reference captured up front goes stale the moment maze 1 is cleared and
	# leaves the test inspecting an orphaned racer.
	var racer: Racer = null
	var maze: Maze = null
	var marked_open := 0
	var marked_turnable := 0
	var marked_sideways := 0
	var marked_too_far := 0
	var missed_blocked := 0
	var shown := 0
	var frames := 900
	var last := Vector2i(-999, -999)

	for i in frames:
		racer = game.racer
		maze = racer.maze

		if game.phase == 1:
			var offered: Array = game._upgrade_screen._lines
			game._on_upgrade_chosen(offered[0] if offered.size() > 0 else -1)
		elif game.phase == 0:
			if racer.state == Racer.State.PARKED:
				racer.request_reverse()
				last = Vector2i(-999, -999)
			elif racer.cell != last:
				last = racer.cell
				# Steer TOWARD dead ends, not toward the exit. The solve-path
				# autopilot the other checks use is optimal, so it never enters a
				# dead end and the mark never fires -- which left this whole
				# block asserting nothing. Hunt for the case under test instead.
				var want := _dead_end_seeking_turn(maze, racer)
				if want != 0:
					racer.request_turn(want)

		game._process(1.0 / 60.0)

		# Recover which wall the mark landed on from its world transform, so the
		# test reads the rendered result rather than trusting internal state.
		racer = game.racer
		maze = racer.maze

		if not indicator.visible:
			# A wall inside the window must always be marked WHILE RACING, or the
			# player gets no warning at exactly the moment the mark exists for.
			# Between mazes it is deliberately hidden: the racer still sits on the
			# old exit cell for a frame after the new maze is swapped in.
			if game.phase != 0:
				continue

			var cell := racer.cell
			var ahead := 1.0 - racer.progress
			while ahead <= WallIndicator.SHOW_WITHIN_CELLS:
				if not maze.is_open(cell, racer.facing):
					# Only a dead end is a miss now. A corner inside the window
					# is correctly left unmarked -- the player has a turn.
					if _dead_end_ahead(maze, cell, racer.facing):
						missed_blocked += 1
					break
				cell += Maze.DIR_VECTORS[racer.facing]
				ahead += 1.0
			continue

		shown += 1
		var p: Vector3 = indicator.position
		var marked_cell := Vector2i(
			int(round(p.x / Tuning.CELL_SIZE)),
			int(round(p.z / Tuning.CELL_SIZE))
		)
		var offset := Vector3(p.x, 0.0, p.z) - Vector3(
			marked_cell.x * Tuning.CELL_SIZE, 0.0, marked_cell.y * Tuning.CELL_SIZE)

		var dir := -1
		if absf(offset.x) > absf(offset.z):
			dir = Maze.E if offset.x > 0.0 else Maze.W
		else:
			dir = Maze.S if offset.z > 0.0 else Maze.N

		if maze.is_open(marked_cell, dir):
			marked_open += 1

		# The new rule: a marked cell must offer no way out but a 180. If a turn
		# exists there, the sign is firing on an ordinary corner.
		if not _dead_end_ahead(maze, marked_cell, dir):
			marked_turnable += 1

		# And it must be the wall AHEAD, not one off to the side.
		if dir != racer.facing:
			marked_sideways += 1

		var gap := (Vector2(marked_cell) - Vector2(racer.cell)).length()
		if gap > WallIndicator.SHOW_WITHIN_CELLS + 1.0:
			marked_too_far += 1

	check("indicator was exercised", shown > 0, "never shown in %d frames" % frames)
	check("indicator never marks an open direction", marked_open == 0,
		"%d frames marked a passable side -- it would be acting as a free Path Indicator"
			% marked_open)
	check("indicator only marks real dead ends", marked_turnable == 0,
		"%d frames marked a cell with a turn available" % marked_turnable)
	check("indicator marks the wall straight ahead", marked_sideways == 0,
		"%d frames marked a side wall" % marked_sideways)
	check("indicator never marks a distant wall", marked_too_far == 0,
		"%d frames marked past the window" % marked_too_far)
	check("indicator never misses a dead end in the window", missed_blocked == 0,
		"%d frames hid a dead end the player was driving into" % missed_blocked)


# Pick a turn that heads for a dead end when one is adjacent, so the indicator
# actually gets exercised. Falls back to whichever side is open, which keeps the
# racer moving through the maze rather than grinding against a wall.
func _dead_end_seeking_turn(maze: Maze, racer: Racer) -> int:
	var left := racer.left_direction()
	var right := racer.right_direction()

	# Prefer a side that leads into a dead end. Searched several cells deep, not
	# one: culling the one-cell stubs (Maze._cull_shallow_dead_ends) left maze 1
	# with only DEEP dead ends, and a single-cell lookahead cannot see those at
	# all -- the seeker then wandered the whole 900 frames without ever entering
	# one and the "was exercised" guard fired. The guard was right; the search
	# was too shallow for the maze the generator now produces.
	if maze.is_open(racer.cell, left) and _leads_to_dead_end(maze, racer.cell, left):
		return -1
	if maze.is_open(racer.cell, right) and _leads_to_dead_end(maze, racer.cell, right):
		return 1

	# Otherwise keep going forward where possible; turn only when blocked.
	if maze.is_open(racer.cell, racer.facing):
		return 0
	if maze.is_open(racer.cell, left):
		return -1
	if maze.is_open(racer.cell, right):
		return 1
	return 0


# Does heading `dir` from `cell` run into a dead end within a few cells?
#
# Follows the corridor while it has no choices. Any branch means the route is
# not a committed dead end and the walk stops -- so this finds the deep stubs a
# one-cell probe misses, without wandering the whole maze.
func _leads_to_dead_end(maze: Maze, cell: Vector2i, dir: int, depth: int = 6) -> bool:
	var current := cell
	var facing := dir

	for _i in depth:
		if not maze.is_open(current, facing):
			return false
		current = current + Maze.DIR_VECTORS[facing]

		var exits := maze.open_directions(current)
		if exits.size() == 1:
			return true   # nothing but the way we came in
		if exits.size() > 2:
			return false  # a junction: a real choice exists here

		# A plain corridor or corner -- keep following it.
		var back: int = Maze.OPPOSITE[facing]
		var moved := false
		for d in exits:
			if d != back:
				facing = d
				moved = true
				break
		if not moved:
			return false

	return false


# Mirrors WallIndicator's own rule, written out independently so the test does
# not simply restate the implementation it is checking.
func _dead_end_ahead(maze: Maze, cell: Vector2i, facing: int) -> bool:
	for dir in Maze.DIRS:
		if dir == Maze.OPPOSITE[facing]:
			continue
		if maze.is_open(cell, dir):
			return false
	return true


# A crash must visibly change the view, and must still never clip.
#
# The autopilot in the other harnesses never crashes, so every part of the crash
# path -- the camera retreat, the held prompt, the recovery -- was previously
# unexercised by any test. This drives a real crash by steering INTO a wall.
# Pause stops the clock AND the simulation, and blurs the minimap.
#
# All three matter and each fails differently: a pause that let `elapsed` run
# would penalise stepping away in the one currency the player is fighting
# (CLAUDE.md section 8); one that let the racer step would not be a pause; and
# one that left the minimap sharp would be a strictly better gate screen --
# free, unlimited, and available any time -- which is the scouting the gate blur
# exists to prevent (section 7).
func _check_pause(game) -> void:
	# Leave whatever the earlier checks did behind: this test needs a live,
	# racing game, and the crash check before it parks the racer.
	game.phase = game.Phase.RACING
	game.racer.state = Racer.State.RUNNING
	game.racer.freeze = 0.0

	game._set_paused(true)
	check("pause enters the paused phase", game.phase == game.Phase.PAUSED)
	check("pause blurs the minimap", game._minimap.blurred)

	var elapsed_before: float = game.elapsed
	var cell_before: Vector2i = game.racer.cell
	var progress_before: float = game.racer.progress

	for _i in range(30):
		game._process(1.0 / 60.0)

	check("paused: the run timer is stopped",
		is_equal_approx(game.elapsed, elapsed_before),
		"%.3f -> %.3f" % [elapsed_before, game.elapsed])
	check("paused: the racer does not move",
		game.racer.cell == cell_before and is_equal_approx(game.racer.progress, progress_before),
		"cell %s progress %.3f" % [str(game.racer.cell), game.racer.progress])

	game._set_paused(false)
	check("unpause returns to racing", game.phase == game.Phase.RACING)
	check("unpause unblurs the minimap", not game._minimap.blurred)

	for _i in range(30):
		game._process(1.0 / 60.0)
	check("unpaused: the run timer resumes", game.elapsed > elapsed_before,
		"%.3f -> %.3f" % [elapsed_before, game.elapsed])


func _check_crash_camera(game) -> void:
	var racer: Racer = game.racer
	var maze: Maze = racer.maze

	# Find a cell WITH a wall and move the racer there. The earlier tests leave
	# the racer wherever they finished, and an open cell has nothing to crash
	# into -- assuming the current cell has a wall made this test fail depending
	# on what ran before it.
	var blocked := -1
	var target := racer.cell

	for radius in 30:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := racer.cell + Vector2i(dx, dy)
				if not maze._in_bounds(c):
					continue
				for dir in Maze.DIRS:
					if not maze.is_open(c, dir):
						target = c
						blocked = dir
						break
				if blocked != -1:
					break
			if blocked != -1:
				break
		if blocked != -1:
			break

	check("found a wall to crash into", blocked != -1)
	if blocked == -1:
		return

	racer.cell = target
	racer.facing = blocked
	racer.progress = 0.0

	var before_height: float = game._camera.position.y
	var crashed := false

	for i in 400:
		game._process(1.0 / 60.0)
		if game.racer.state == Racer.State.PARKED:
			crashed = true
			break

	check("driving into a wall crashes", crashed)
	if not crashed:
		return

	# Let the eased crash view settle.
	for i in 60:
		game._process(1.0 / 60.0)

	var eye: Vector3 = game._camera.position
	check("crash camera lifts", eye.y > before_height + 0.3,
		"height %.2f vs %.2f before" % [eye.y, before_height])
	check("crash camera stays below wall height", eye.y < Tuning.WALL_HEIGHT,
		"height %.2f would see over the maze" % eye.y)

	# The retreat must not push the eye into geometry -- the crash view is
	# exactly the case where the cell behind is most likely to be solid.
	var to_face: float = Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5
	var cell := Vector2i(
		int(round(eye.x / Tuning.CELL_SIZE)),
		int(round(eye.z / Tuning.CELL_SIZE)))
	var clipped := false
	if not game.maze._in_bounds(cell):
		clipped = true
	else:
		var centre := Vector3(cell.x * Tuning.CELL_SIZE, 0.0, cell.y * Tuning.CELL_SIZE)
		var offset := Vector3(eye.x, 0.0, eye.z) - centre
		if absf(offset.x) > to_face:
			var d := Maze.E if offset.x > 0.0 else Maze.W
			if not game.maze.is_open(cell, d):
				clipped = true
		if absf(offset.z) > to_face:
			var d2 := Maze.S if offset.z > 0.0 else Maze.N
			if not game.maze.is_open(cell, d2):
				clipped = true
	check("crash camera does not clip", not clipped)

	# And recovery must restore the normal view.
	# Un-stick, then actually DRIVE. An unsteered racer just reverses down the
	# corridor and parks against the next wall, so the camera is correctly still
	# raised when the frames run out -- the assertion would be reading a second
	# crash and blaming the first one's recovery.
	#
	# This is the "a solve-path autopilot cannot exercise failure states" trap in
	# reverse (CLAUDE.md section 12): here the test has to steer to AVOID the
	# failure, not to seek it.
	game.racer.request_reverse()
	for i in 90:
		game._process(1.0 / 60.0)
		var r: Racer = game.racer
		if r.state == Racer.State.PARKED:
			r.request_reverse()
		elif not r.maze.is_open(r.cell, r.facing):
			# About to run out of corridor -- take whichever side is open.
			if r.maze.is_open(r.cell, r.left_direction()):
				r.request_turn(-1)
			elif r.maze.is_open(r.cell, r.right_direction()):
				r.request_turn(1)

	check("recovery leaves the racer running", game.racer.state == Racer.State.RUNNING,
		"still parked")
	check("camera returns after recovery",
		game._camera.position.y < before_height + 0.35,
		"height %.2f did not settle back" % game._camera.position.y)


# Wall boxes must be wound so their normals point OUTWARD.
#
# Inverted winding is invisible while the material is double-sided, then turns
# every wall see-through the moment backface culling is enabled -- which is
# exactly how it shipped once. A geometric assertion catches it regardless of
# what the material happens to be set to.
func _check_wall_winding() -> void:
	var maze := Maze.new()
	maze.generate(8, 8, 4321, 0.0, 1.0, 0)

	var mesh := MazeMesh.new()
	mesh.build(maze)

	var walls: MeshInstance3D = null
	for child in mesh.get_children():
		# The wall surface is the first MeshInstance3D built from an ArrayMesh;
		# the floor is a PlaneMesh and the markers are BoxMeshes.
		if child is MeshInstance3D and child.mesh is ArrayMesh:
			walls = child
			break

	check("wall mesh was built", walls != null)
	if walls == null:
		return

	var arrays: Array = walls.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	check("wall mesh has geometry", verts.size() > 0, "got %d verts" % verts.size())
	if verts.size() == 0:
		return

	# Each wall is a closed box, so its faces must point away from their own
	# box's centre. Rather than reconstruct which box a triangle belongs to --
	# walls are emitted per-cell as N/W faces plus outer boundaries, so the
	# mapping is not local -- use the whole-mesh invariant that follows from
	# every box being closed and outward-wound:
	#
	#   sum over triangles of (centroid · normal · area) = +6V for outward
	#   winding, and -6V for inward.
	#
	# This is the divergence theorem applied to F = position: it needs no
	# knowledge of where any individual wall sits, and it flips sign precisely
	# when the winding does, which is the thing that has actually broken.
	var signed_volume := 0.0

	for i in range(0, verts.size(), 3):
		var p1: Vector3 = verts[i]
		var p2: Vector3 = verts[i + 1]
		var p3: Vector3 = verts[i + 2]
		signed_volume += p1.dot(p2.cross(p3))

	signed_volume /= 6.0

	check("wall mesh is outward-wound", signed_volume > 0.0,
		"signed volume %.1f -- negative means inverted normals and see-through walls"
			% signed_volume)
	check("wall mesh encloses real volume", absf(signed_volume) > 1.0,
		"got %.3f" % signed_volume)


func _finish() -> void:
	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


# Landmark geometry actually reaches the scene, and is built solid.
#
# The rules-level guarantees live in RulesTest; this checks the half that only
# exists once there is a rendered world: that the meshes are built, that they
# are wound the right way out, and that a skyline landmark genuinely rises above
# the wall line rather than merely being declared tall in the table.
func _check_landmark_meshes(game) -> void:
	var mesh_root: Node = game._mesh
	var found: Array[MeshInstance3D] = []
	for child in mesh_root.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Landmarks_"):
			found.append(child)

	check("landmark meshes are built", found.size() > 0,
		"got %d surfaces" % found.size())
	if found.is_empty():
		return

	var tallest := 0.0
	var total_volume := 0.0
	var inverted: Array[String] = []

	for instance in found:
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.size() == 0:
			continue

		# Same whole-mesh invariant the wall check uses: for closed,
		# outward-wound solids the signed volume is positive. It needs no
		# knowledge of where any individual landmark sits, and it flips sign
		# exactly when the winding does -- which is the failure that stays
		# invisible until backface culling is switched on.
		var volume := 0.0
		for i in range(0, verts.size(), 3):
			volume += verts[i].dot(verts[i + 1].cross(verts[i + 2]))
		volume /= 6.0

		if volume <= 0.0:
			inverted.append(String(instance.name))
		total_volume += volume

		for v in verts:
			tallest = maxf(tallest, v.y)

	check("landmark meshes are outward-wound", inverted.is_empty(),
		"inverted: %s" % ", ".join(inverted))
	check("landmark meshes enclose real volume", total_volume > 1.0,
		"got %.3f" % total_volume)

	# The whole justification for the skyline tier is that the camera is capped
	# BELOW WALL_HEIGHT (CLAUDE.md section 12), so the only way anything is
	# visible from the next corridor over is by towering above the walls. If the
	# built geometry never gets above the wall line, the tier does nothing --
	# and the table alone cannot prove it, since the shapes are what decide the
	# real height.
	check("a landmark rises above the wall line", tallest > Tuning.WALL_HEIGHT,
		"tallest vertex %.2f, wall is %.2f" % [tallest, Tuning.WALL_HEIGHT])
	check("skyline landmarks tower, not merely clear",
		tallest >= Tuning.WALL_HEIGHT * 2.0,
		"tallest %.2f, want >= %.2f" % [tallest, Tuning.WALL_HEIGHT * 2.0])

	# They must not reach so high they read as a ceiling over the corridor.
	check("landmarks stay under a sane ceiling", tallest < Tuning.WALL_HEIGHT * 8.0,
		"tallest %.2f" % tallest)
