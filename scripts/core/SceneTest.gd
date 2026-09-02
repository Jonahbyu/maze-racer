# Boots the real Main scene headlessly and drives it, to catch the runtime
# errors that a pure-logic harness cannot see: bad node setup, missing theme
# properties, signal wiring, null derefs in _process, UI construction.
#
# RulesTest proves the rules are right. This proves the game actually runs.
extends SceneTree

# Seed for the dead-end decoration check's maze. Any seed whose maze 1 puts a
# dead end within reach of the seeker inside the frame budget will do; this one
# is checked in because the check must not depend on the wall clock.
const DEAD_END_SEED := 20250829

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
	# The run now OPENS on a loadout pick rather than straight into motion
	# (CLAUDE.md section 7): every maze begins by asking what you want to be for
	# it. So the boot state is UPGRADING, and racing starts once a card is taken.
	check("starts on the loadout pick", game.phase == 1)
	check("loadout blurs the minimap", game._minimap.blurred)
	var loadout: Array = game._upgrade_screen._lines
	check("loadout offered cards", loadout.size() > 0, "got %d" % loadout.size())
	if loadout.size() > 0:
		game._on_upgrade_chosen(loadout[0])
	check("racing begins after the loadout pick", game.phase == 0)

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

	# Colour of the gate marker about to be taken, read BEFORE the gate fires so
	# the comparison below is against what was actually on screen rather than
	# against a constant restated here (the transcription trap, section 12).
	var gate_node := game._mesh.get_node_or_null("Gate0") as MeshInstance3D
	check("the gate marker exists before it is taken", gate_node != null)
	var live_colour := Color.BLACK
	if gate_node != null:
		live_colour = (gate_node.material_override as StandardMaterial3D).emission

	# The argument is the gate's PLACEMENT in `maze.gates`, so gate 0's marker
	# is cleared by passing 0. This read `_on_gate_entered(1)` against a handler
	# that subtracted one, which meant the harness was asserting the off-by-one
	# rather than the contract -- and so could not see the mismatch that left
	# out-of-order gates recolouring the wrong marker.
	game._on_gate_entered(0)
	check("gate pauses the run", game.phase == 1)
	check("minimap blurs at a gate", game._minimap.blurred)

	# A taken gate DIMS; it does not disappear. It used to be queue_free'd, which
	# threw away the most recognisable landmark the maze has -- and one that is
	# tall enough to clear the wall line, so it is visible from several corridors
	# away. Deleting it made ground the player had demonstrably driven look
	# exactly like ground they had never seen (section 6).
	#
	# queue_free is deferred, so a check for the node still being there would
	# pass for a frame either way. Processing frames first is what makes this an
	# assertion rather than a race.
	for i in 5:
		game._process(0.016)

	var spent := game._mesh.get_node_or_null("Gate0") as MeshInstance3D
	check("a taken gate keeps its marker", spent != null)
	if spent != null:
		var mat := spent.material_override as StandardMaterial3D
		check("the spent marker still has a material", mat != null)
		if mat != null:
			check("a taken gate changes colour", mat.emission != live_colour,
				"still %s" % mat.emission)
			# Separated by HUE, not only by brightness: the wall indicator
			# already ramps amber-to-red on distance (section 5.6), so a spent
			# gate that was merely a dimmer amber would read as a live one seen
			# far off through fog.
			check("the spent colour is cool where the live one is warm",
				mat.emission.b > mat.emission.r,
				"spent %s vs live %s" % [mat.emission, live_colour])
			check("a taken gate stops shouting",
				mat.emission_energy_multiplier < 2.0,
				"energy %.2f" % mat.emission_energy_multiplier)

		# The spent marker must sit ABOVE the camera, and this is the assertion
		# that would have caught the bug a rendered frame found: the marker is
		# transparent and CULL_DISABLED, so one still running to the floor puts
		# the eye inside it whenever the player re-crosses the cell and washes
		# the entire screen its colour. Deleting the marker used to hide this;
		# keeping it made it permanent.
		#
		# Measured off the mesh's own AABB rather than off the tuning constant,
		# so this asserts the geometry actually MOVED rather than restating a
		# number (section 12).
		var box: AABB = spent.mesh.get_aabb()
		check("a spent gate clears the camera",
			box.position.y > Tuning.CAM_HEIGHT,
			"base %.2f vs camera %.2f" % [box.position.y, Tuning.CAM_HEIGHT])

		# And it must still clear the wall line, which is the entire reason the
		# marker is worth keeping: only the part above the walls is visible from
		# another corridor, and that visibility is what makes a spent gate a
		# landmark rather than clutter in one cell.
		check("a spent gate still clears the wall line",
			box.end.y > Tuning.WALL_HEIGHT,
			"top %.2f vs wall %.2f" % [box.end.y, Tuning.WALL_HEIGHT])

	# The gates NOT yet taken must be untouched. _make_marker builds one material
	# per marker, but a recolour that reached through a shared resource would dim
	# every gate in the maze at the first one taken -- and nothing about the look
	# of a single frame would reveal it.
	var next_gate := game._mesh.get_node_or_null("Gate1") as MeshInstance3D
	if next_gate != null:
		var next_mat := next_gate.material_override as StandardMaterial3D
		check("taking one gate leaves the others live",
			next_mat != null and next_mat.emission == live_colour)

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

	_check_flying_vision(game)
	_check_wall_winding()
	_check_path_indicator(game)
	_check_dead_end_decoration(game)
	_check_camera_never_clips(game)
	_check_crash_camera(game)
	_check_pause(game)
	_check_landmark_meshes(game)
	_check_minimap_placement(game)
	_check_gate_names_survive_a_rebuild()

	_finish()


# The Path Indicator must light real wall panels at a junction, and go dark
# everywhere else.
#
# This is the assertion that stops it silently reverting to "floating in the
# air": every lit strip is checked to lie on the boundary between the player's
# cell and a genuinely open neighbour -- the gap it is marking. A strip laid
# over a wall, or adrift mid-cell, would still LOOK lit from most angles and
# would never be caught by a smoke test that only asks whether the node is
# visible.
#
# Note this is the INVERSE of the check it replaces. The panels had to be flush
# against a wall face; a strip marks an opening, so a wall under it is now the
# failure rather than the requirement.
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
	var misplaced := 0
	var lit_at_corner := 0

	# Walk the maze and drive the indicator through real cells rather than
	# waiting for an autopilot to wander into a junction -- the same reason the
	# dead-end decoration check seeks its own fixture.
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
					if not _strip_is_in_a_gap(maze, cell, panel):
						misplaced += 1

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
	check("path indicator strips lie across an opening, not in the air",
		misplaced == 0,
		"%d strips were off the boundary or turned the wrong way" % misplaced)
	check("path indicator stays dark where there is no choice", lit_at_corner == 0,
		"%d corners were lit" % lit_at_corner)


# Is this strip lying across a real opening out of `cell`?
#
# It has to sit on a cell boundary -- half a cell out from the centre along one
# axis, dead centre on the other -- and the side it names must actually be open.
# That covers both ways the placement can go wrong: a strip drawn over a solid
# wall (marking a route that does not exist) and one adrift inside a cell
# (marking nothing at all, the floating-in-air failure).
func _strip_is_in_a_gap(maze: Maze, cell: Vector2i, strip: Node3D) -> bool:
	var pos: Vector3 = strip.position
	var offset := Vector3(
		pos.x - float(cell.x) * Tuning.CELL_SIZE,
		0.0,
		pos.z - float(cell.y) * Tuning.CELL_SIZE)

	var half: float = Tuning.CELL_SIZE * 0.5
	var dir := -1
	var across := 0.0

	if is_equal_approx(absf(offset.x), half):
		dir = Maze.E if offset.x > 0.0 else Maze.W
		across = offset.z
	elif is_equal_approx(absf(offset.z), half):
		dir = Maze.S if offset.z > 0.0 else Maze.N
		across = offset.x
	else:
		# Not on any boundary of this cell.
		return false

	# Centred in the corridor it spans, not shunted to one side of it.
	if absf(across) > 0.001:
		return false

	if not maze.is_open(cell, dir):
		return false

	# It must lie ACROSS the gap, not lengthwise down the corridor.
	#
	# Orientation needs asserting separately from position because the two fail
	# independently, and a mis-yawed strip sits in exactly the right place: it
	# passed every positional check here while rendering as a bar running down
	# the corridor instead of over its mouth. Worse, the branch straight ahead
	# looks correct under a flipped sign, so half the strips on screen agree
	# with the bug.
	#
	# The mesh spans local X, so the world span is the basis X column. Against
	# the direction it marks it must be perpendicular -- dot product zero.
	var v: Vector2i = Maze.DIR_VECTORS[dir]
	var span: Vector3 = strip.transform.basis.x.normalized()
	var along := Vector3(float(v.x), 0.0, float(v.y)).normalized()
	return absf(span.dot(along)) < 0.01


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


# Every dead end the player can actually drive into must carry a landmark.
#
# This replaced the wall indicator, and it inherits its job. The indicator was a
# free no-entry mark on the end wall; removing it means the landmark is now the
# ONLY thing that tells the end of a corridor apart from a corridor that merely
# turns. A bare dead end is a reversal with nothing to remember it by -- the
# "punishment without the lesson" case in CLAUDE.md section 6.
#
# Asserted over real PLAY rather than over the grid, because the placement pass
# and the mesh builder can disagree: Maze._place_landmarks can list a cell that
# MazeMesh never emits. Driving into dead ends is what catches that.
func _check_dead_end_decoration(game) -> void:
	# Pin the maze. Game seeds itself from the wall clock, so this drew a
	# different maze every run and whether the autopilot met a dead end inside
	# the frame budget was luck. A fixed seed makes it answer "does the rule
	# hold" rather than "did we get a lucky maze".
	game.run_seed = DEAD_END_SEED
	game._start_maze(0)

	var decorated := {}
	for landmark in game.maze.landmarks:
		decorated[landmark["cell"]] = true

	# The whole-grid claim first: no dead end may be left bare, whether or not
	# this run's autopilot happens to reach it.
	var maze: Maze = game.maze
	var total_dead_ends := 0
	var bare := 0
	for y in maze.height:
		for x in maze.width:
			var cell := Vector2i(x, y)
			if maze.open_directions(cell).size() != 1:
				continue
			# The start, the exit and the gate cells are deliberately excluded
			# from placement -- each already carries its own marker, and a
			# landmark on top of one would be scenery competing with navigation.
			if cell == maze.start_cell or cell == maze.exit_cell or maze.gates.has(cell):
				continue
			total_dead_ends += 1
			if not decorated.has(cell):
				bare += 1

	check("the maze has dead ends to decorate", total_dead_ends > 0,
		"found none, so the check below asserts nothing")
	check("every dead end carries a landmark", bare == 0,
		"%d of %d dead ends were left bare" % [bare, total_dead_ends])

	# And now the same claim over play. Re-read racer and maze from `game` every
	# frame, never cached: _start_maze builds a NEW Racer and a NEW Maze per
	# maze, so a reference captured up front goes stale the moment maze 1 ends.
	var racer: Racer = null
	var visited_dead_ends := {}
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
				# dead end and this would assert nothing. Hunt for the case under
				# test instead.
				var want := _dead_end_seeking_turn(maze, racer)
				if want != 0:
					racer.request_turn(want)

		game._process(1.0 / 60.0)

		racer = game.racer
		maze = racer.maze
		if game.phase != 0:
			continue
		if maze.open_directions(racer.cell).size() == 1:
			visited_dead_ends[racer.cell] = true

	var driven := visited_dead_ends.size()
	var driven_bare := 0
	for cell in visited_dead_ends:
		if maze.gates.has(cell) or cell == maze.start_cell or cell == maze.exit_cell:
			continue
		if not decorated.has(cell):
			driven_bare += 1

	check("the autopilot reached a dead end", driven > 0,
		"entered none in %d frames, so nothing was exercised" % frames)
	check("every dead end driven into was decorated", driven_bare == 0,
		"%d of %d dead ends reached were bare" % [driven_bare, driven])


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

	# The settings cog is a PAUSE-screen control: on a live corridor it would be
	# a mouse target sitting over the thing the player is steering through.
	check("paused: the settings cog is shown",
		game._settings_cog != null and game._settings_cog.visible)

	_check_pause_settings(game)

	game._set_paused(false)
	check("unpause returns to racing", game.phase == game.Phase.RACING)
	check("unpause unblurs the minimap", not game._minimap.blurred)
	check("unpause hides the settings cog",
		game._settings_cog != null and not game._settings_cog.visible)

	for _i in range(30):
		game._process(1.0 / 60.0)
	check("unpaused: the run timer resumes", game.elapsed > elapsed_before,
		"%.3f -> %.3f" % [elapsed_before, game.elapsed])


# The panel mounted over a paused game, which is where the interactions that
# can actually go wrong live: a modal that outlives the pause would swallow the
# steering inputs the player just went back to.
func _check_pause_settings(game) -> void:
	game._open_settings()
	check("the cog opens the settings panel", game.settings_open())

	var panel = game._settings_panel
	check("the panel is a SettingsPanel", panel is SettingsPanel)
	check("the panel is under the UI root",
		panel != null and panel.get_parent() != null
			and String(panel.get_parent().name) == "UIRoot")

	# Opening must not itself write a preference -- the slider is assigned from
	# the stored value on open, and an unblocked assignment would echo straight
	# back into Settings and re-save the config on every open.
	# Explicitly typed, not inferred: `game` is untyped here, so the return of
	# get_node_or_null through it carries no static type and `:=` is a parse
	# error -- which fails the whole FILE to load, so the harness reports a
	# bare "Parse error" and none of its assertions run at all.
	var settings: Node = game.get_node_or_null("/root/Settings")
	if settings != null and panel != null:
		var volume_before: float = float(settings.music_volume)
		game._close_settings()
		game._open_settings()
		check("opening the panel does not change the volume",
			is_equal_approx(float(settings.music_volume), volume_before),
			"%.3f -> %.3f" % [volume_before, float(settings.music_volume)])

	# A pause press with the panel up is aimed at the panel. Resuming
	# underneath it would hand back a running corridor with a modal on screen.
	game._on_pause_input()
	check("a pause press closes the panel first", not game.settings_open())
	check("...and does NOT resume the game",
		game.phase == game.Phase.PAUSED, str(game.phase))

	# Still paused, so the next press is the ordinary resume.
	game._open_settings()
	check("the panel reopens", game.settings_open())
	game._set_paused(false)
	check("resuming frees the panel", not game.settings_open())
	game._set_paused(true)


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
	# Clear whatever the earlier checks left armed. A pending turn survives a
	# bare cell/facing assignment, so the racer would resolve it at the next
	# boundary and steer AROUND the wall this check just went to the trouble of
	# finding -- failing as "driving into a wall crashes", which points at the
	# crash rules rather than at the stale input that actually caused it.
	#
	# The same trap CLAUDE.md section 12 records for shared-scene harnesses:
	# state the test needs must be established, never inherited. It stayed
	# hidden while the checks ahead of this one happened to leave nothing armed.
	racer.pending_turn = -1
	racer.pending_buffer = 0.0
	racer.scraping = false
	racer.state = Racer.State.RUNNING
	# This check is about the CRASH path, and by now the harness has taken every
	# upgrade line -- including Wall Smasher, which correctly breaks through a
	# wall instead of crashing into it. Hold it on cooldown so the racer is
	# actually testing what this check is named for.
	racer.legendary_cooldown = 999.0

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


# The minimap sits centred under the player marker and must not cover the
# barrier and integrity bars.
#
# It moved out of the bottom-left corner so it would sit directly below the
# marker -- the shortest possible glance, on the axis the player is already
# looking along. The cost of centring is a collision the corner placement could
# never have: the bars are hard against the left margin in the SAME bottom
# band, so on a narrow window the map runs straight over them. The barrier bar
# is the most important element on screen (CLAUDE.md section 5.1), so the map
# has to give way, and the clamp that makes it give way is exactly the sort of
# layout arithmetic that is right by luck until a number moves.
#
# Checked at two widths because the wide case passes trivially -- the clamp is
# not even binding there -- so a broken clamp would show up at neither size if
# only one were tested.
func _check_minimap_placement(game) -> void:
	# UIRoot is driven directly rather than by resizing the window: --headless
	# runs a dummy DisplayServer that ignores window_set_size entirely, so the
	# viewport stays at the project's 1600x900 and every size below would be
	# tested against the same rect. This is the "did we actually vary anything"
	# trap -- the checks passed at one size and silently never saw the other.
	#
	# Its full-rect anchors have to be released first, or the assignment is
	# overridden on the next layout (the engine warns about exactly that).
	var ui: Control = game._minimap.get_parent()
	ui.anchor_right = 0.0
	ui.anchor_bottom = 0.0

	for width in [1280.0, 760.0]:
		ui.size = Vector2(width, 720.0)
		game._place_minimap()
		# Anchors and offsets resolve into a rect on layout, not on assignment.
		for i in 3:
			game._process(0.016)

		var box: Rect2 = game._minimap.get_rect()
		var label := "at %dpx" % int(width)

		# Centred where there is room for it. On a window too narrow to both
		# centre the map and clear the bars, the map gives ground to the right
		# -- the bars win those pixels -- so this asserts "centred, or pushed
		# right", never "pushed left", which would put it back over them.
		var centred: bool = absf(box.get_center().x - width * 0.5) <= 1.0
		var nudged_right: bool = box.get_center().x > width * 0.5
		check("the map is centred or nudged right %s" % label,
			centred or nudged_right,
			"centre %.1f vs %.1f" % [box.get_center().x, width * 0.5])

		# At a normal desktop width the clamp must not be binding at all -- the
		# map is exactly centred and full size. Without this the checks above
		# would be satisfied by a clamp that fired at every width and quietly
		# pushed the map off-centre on every screen.
		if width >= 1280.0:
			check("a desktop window centres the map exactly %s" % label, centred,
				"centre %.1f" % box.get_center().x)
			check("a desktop window draws the map full size %s" % label,
				box.size.x >= Minimap.SIZE - 1.0, "span %.1f" % box.size.x)

		# Clear of the bars, which run from the left margin to HUD_BARS_RIGHT.
		check("the map clears the barrier bars %s" % label,
			box.position.x >= game.HUD_BARS_RIGHT,
			"left edge %.1f vs bars ending %.1f" % [
				box.position.x, game.HUD_BARS_RIGHT])

		# And still large enough to read: a clamp that satisfied the line above
		# by collapsing the map to nothing would be worse than the overlap.
		check("the map stays legible %s" % label,
			box.size.x >= game.MINIMAP_MIN,
			"span %.1f" % box.size.x)

		# On screen. A bottom anchor with the wrong sign puts it off the edge,
		# which is the failure the touch pads had (section 9d).
		check("the map stays on screen %s" % label,
			box.position.y >= 0.0 and box.end.y <= 720.0,
			"y %.1f..%.1f" % [box.position.y, box.end.y])

	# Left as it was found: a tool must not write the state it is inspecting
	# (section 9d), and later checks in this harness share the same scene.
	ui.anchor_right = 1.0
	ui.anchor_bottom = 1.0
	ui.offset_right = 0.0
	ui.offset_bottom = 0.0
	game._place_minimap()


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


# Flying Vision: the double-tap gesture, the held world, the raised camera, and
# the return to racing (CLAUDE.md section 7).
#
# The camera lift is the part no headless rule check can see, so what is
# asserted here is the CONTRACT: the eye goes above the wall line, which is the
# one place section 12's height cap is deliberately suspended.
func _check_flying_vision(game) -> void:
	game.upgrades.take(Upgrades.Line.FLYING_VISION)
	game.phase = 0
	game.racer.state = Racer.State.RUNNING
	game.racer.legendary_cooldown = 0.0
	game._vision_time = 0.0
	game._vision_countdown = 0.0
	game._last_reverse_time = -999.0

	var elapsed_before: float = game.elapsed
	var maze_time_before: float = game.score.maze_time

	# A single tap must NOT trigger it -- that is an ordinary 180.
	game._on_reverse_input()
	check("a single reverse does not trigger the vision", game.phase == 0)

	# Two in quick succession do. elapsed does not advance between these calls,
	# so they fall inside the double-tap window by construction.
	game._on_reverse_input()
	check("a double-tap starts flying vision", game.phase == 6,
		"phase %d" % game.phase)
	check("the vision blurs the minimap", game._minimap.blurred)

	var height_before: float = game._camera.position.y
	for i in 30:
		game._process(1.0 / 60.0)
	check("the camera rises above the wall line",
		game._camera.position.y > Tuning.WALL_HEIGHT,
		"%.1f vs wall %.1f" % [game._camera.position.y, Tuning.WALL_HEIGHT])
	check("the camera rose from where it was",
		game._camera.position.y > height_before)

	# Both clocks are held: this is a genuine reprieve, deliberately free.
	check("the run timer is held", absf(game.elapsed - elapsed_before) < 0.001,
		"%.4f vs %.4f" % [game.elapsed, elapsed_before])
	check("the maze budget is held",
		absf(game.score.maze_time - maze_time_before) < 0.001,
		"%.4f vs %.4f" % [game.score.maze_time, maze_time_before])

	# It ends on its own and hands control back.
	for i in 1200:
		game._process(1.0 / 60.0)
		if game.phase == 0:
			break
	check("the vision ends and racing resumes", game.phase == 0,
		"phase %d" % game.phase)
	check("the minimap unblurs afterwards", not game._minimap.blurred)

	# A parked racer must never lose the ability to a recovery mash.
	game.racer.state = Racer.State.PARKED
	game.racer.legendary_cooldown = 0.0
	game._last_reverse_time = -999.0
	game._on_reverse_input()
	game._on_reverse_input()
	check("a parked racer cannot trigger the vision", game.phase == 0)
	game.racer.state = Racer.State.RUNNING


# A gate marker must still be called "Gate<n>" after the mesh is rebuilt.
#
# `clear_gate` finds its marker with get_node("Gate<n>"), so these names are
# load-bearing rather than cosmetic -- and they were being lost silently. Godot
# assigns a node's name on ENTRY TO THE TREE, so a name set before add_child is
# overwritten (the trap CLAUDE.md section 12 records for the Music autoload);
# and a name colliding with a node still in the tree -- one queue_freed earlier
# in the same frame -- is resolved by renaming the NEW node.
#
# Measured: on the old code the second build left 6 renamed markers and the
# third left 12, accumulating per maze, while the gate lookups still "succeeded"
# by resolving to the DYING originals. That is why no existing check saw it, and
# why the report was that gates stop recolouring in the later zones but not in
# maze 1 -- maze 1 has nothing to collide with.
#
# Driven against MazeMesh directly on a small maze, not through Game: the rule
# belongs to the mesh, and a real _start_maze on the shipped grids costs minutes
# per maze while telling us nothing more about naming. Three builds, because the
# first is always clean -- the failure needs a previous set of markers present.
#
# No frames are processed between builds, which is the whole point: that is what
# Game._start_maze does, and ticking the tree in between would let the deferred
# frees land and pass against the broken code.
func _check_gate_names_survive_a_rebuild() -> void:
	var mesh := MazeMesh.new()
	get_root().add_child(mesh)

	for pass_index in 3:
		var maze := Maze.new()
		maze.generate(12, 12, 1234 + pass_index * 7919, 0.15, 0.03, 5)
		mesh.build(maze, 0)

		var expected: int = maze.gates.size()
		var reachable := 0
		for i in expected:
			if mesh.get_node_or_null("Gate%d" % i) != null:
				reachable += 1

		check("every gate marker is reachable by name on build %d" % (pass_index + 1),
			reachable == expected and expected > 0,
			"found %d of %d" % [reachable, expected])

		check("the exit marker is reachable by name on build %d" % (pass_index + 1),
			mesh.get_node_or_null("Exit") != null)

		# A renamed marker still EXISTS, just unreachable, so counting strays is
		# what tells a rename apart from a missing node -- and it is the half
		# that actually caught this, since the lookups above kept "passing"
		# against the dying originals.
		#
		# The "@" prefix alone is NOT the signal: the floor, walls, grid lines
		# and wall tops are added unnamed and correctly carry generated names on
		# every build. Only a marker is meant to hold a name, so a stray is
		# identified by shape -- a mesh rising clear of the wall line that is
		# not called Gate<n> or Exit.
		var strays := 0
		for child in mesh.get_children():
			var n := String(child.name)
			if n.begins_with("Gate") or n == "Exit":
				continue
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if mi.mesh.get_aabb().end.y > Tuning.WALL_HEIGHT * 1.2:
				strays += 1

		check("no renamed markers left behind on build %d" % (pass_index + 1),
			strays == 0, "%d strays" % strays)

	mesh.queue_free()
