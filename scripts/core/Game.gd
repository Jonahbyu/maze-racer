# The run controller: owns the maze, the racer, the camera, and the phase
# machine that moves between racing, upgrade picks, and maze transitions.
#
# The simulation itself lives in Racer; this node drives it, renders it, and
# routes input to it. Keeping that split is what lets the whole rule set be
# tested headlessly (CLAUDE.md section 12).
extends Node3D

enum Phase { RACING, UPGRADING, TRANSITION, COMPLETE }

var maze: Maze
var racer: Racer
var upgrades: Upgrades

var phase: int = Phase.RACING
var maze_index := 0
var run_seed := 0

# The run timer. Pauses during upgrade picks -- it is the score, and the whole
# optimisation target, so it must never tick while the player is reading cards.
var elapsed := 0.0

var _camera: Camera3D
var _headlight: OmniLight3D
var _environment: Environment
var _marker: PlayerMarker
var _wall_indicator: WallIndicator
var _path_indicator: PathIndicator
var _golden_trail: GoldenTrail
var _mesh: MazeMesh
var _hud: HUD
var _minimap: Minimap
var _upgrade_screen: UpgradeScreen
var _world: Node3D
var _transition_time := 0.0

# Smoothed camera state, so the view does not snap on turns.
var _cam_yaw := 0.0

# 0 = normal view, 1 = fully in the crash view. Eased, never snapped.
var _crash_blend := 0.0
var _cam_target_yaw := 0.0
var _shake := 0.0


func _ready() -> void:
	run_seed = int(Time.get_unix_time_from_system())
	upgrades = Upgrades.new(run_seed)

	_build_world()
	_build_ui()
	_start_maze(0)


# --- Setup -------------------------------------------------------------------

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	_mesh = MazeMesh.new()
	_mesh.name = "MazeMesh"
	_world.add_child(_mesh)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = Tuning.FOV_BASE
	# Depth precision is dominated by the near/far RATIO, and at 0.05/220 (4400:1)
	# almost the whole depth buffer was spent on the first few centimetres --
	# which nothing ever occupies, since the anti-clip pass keeps the eye 0.45m
	# clear of any wall. Starving the far range that way made near-coplanar
	# surfaces shimmer down long corridors. 0.25 is still well inside the closest
	# the camera can legally get, and cuts the ratio by 5x.
	_camera.near = 0.25
	_camera.far = 220.0
	add_child(_camera)

	# The player's avatar. Third person needs something to BE.
	_marker = PlayerMarker.new()
	_marker.name = "PlayerMarker"
	_world.add_child(_marker)

	_wall_indicator = WallIndicator.new()
	_wall_indicator.name = "WallIndicator"
	_world.add_child(_wall_indicator)

	_path_indicator = PathIndicator.new()
	_path_indicator.name = "PathIndicator"
	_world.add_child(_path_indicator)

	_golden_trail = GoldenTrail.new()
	_golden_trail.name = "GoldenTrail"
	_world.add_child(_golden_trail)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.42, 0.62)
	env.ambient_light_energy = 1.1

	# Bloom is what sells the neon look, and it costs almost nothing here
	# because the emissive surfaces are already the brightest things on screen.
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.25
	env.glow_strength = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# Fog hides the far end of a 90x90 maze and adds a lot of depth cueing at
	# speed, which matters more than seeing distant corridors you cannot reach.
	#
	# It is also the single biggest BANDING risk in the scene, and it looked
	# exactly like a texture on the walls: dark fog over dark wall faces means
	# the blend spans very few 8-bit steps up close (~7 over the first 2m at
	# density 0.014), so each step showed as a flat plateau and the corridor
	# walls came out visibly mottled. Two things keep it smooth -- debanding
	# below, and starting the fog a little way out so the steepest part of the
	# curve is not sitting on the nearest wall.
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.06, 0.12)
	env.fog_density = 0.012
	# Nothing within a couple of cells gets fogged at all, which is where the
	# gradient was tightest and the banding worst.
	env.fog_depth_begin = Tuning.CELL_SIZE * 2.0
	env.fog_depth_end = Tuning.CELL_SIZE * 30.0
	env.fog_mode = Environment.FOG_MODE_DEPTH

	_environment = env

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Dither the output to break up gradient banding.
	#
	# This scene is close to the worst case for it: a dark, low-contrast, almost
	# monochrome blue palette, where every smooth gradient (fog over walls, the
	# headlight falloff, the ambient wash) traverses only a handful of 8-bit
	# values. Without debanding those steps read as blotchy PATCHES ON THE WALL
	# SURFACES -- it looks like a texture or a transparency bug, and sends you
	# hunting through the material for a problem that is not there. The walls
	# were always fully opaque; the banding was in the gradient over them.
	get_viewport().use_debanding = true

	var light := DirectionalLight3D.new()
	light.light_energy = 0.5
	light.light_color = Color(0.7, 0.85, 1.0)
	light.rotation_degrees = Vector3(-55, -40, 0)
	add_child(light)

	# A lamp riding with the camera. A directional light cannot reach down into
	# a corridor -- the walls that matter most are the ones right beside the
	# player, and those are exactly the ones it never touches. This is what gives
	# nearby walls shape and makes the corridor feel enclosed rather than drawn.
	_headlight = OmniLight3D.new()
	_headlight.name = "Headlight"
	# Deliberately dim with a wide range: the job is to give nearby walls SHAPE,
	# not to light them. Turned up, it blows the wall a metre away into a flat
	# field of colour and destroys exactly the depth it was added to create.
	_headlight.light_energy = 0.9
	_headlight.light_color = Color(0.62, 0.82, 1.0)
	_headlight.omni_range = Tuning.CELL_SIZE * 7.0
	_headlight.omni_attenuation = 0.7
	_headlight.shadow_enabled = false
	add_child(_headlight)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	# A Control parented straight to a CanvasLayer gets no rect from it, so any
	# anchor other than top-left resolves against 0x0 and lands off-screen. One
	# full-rect root under the layer gives every UI child a real screen to
	# anchor against.
	var ui_root := Control.new()
	ui_root.name = "UIRoot"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	_hud = HUD.new()
	_hud.name = "HUD"
	ui_root.add_child(_hud)

	# Bottom left, directly above the barrier/HP bars. It sits near the player
	# marker rather than in the far corner: the map and the corridor are read
	# together at speed, and a diagonal glance across the whole screen costs the
	# read it exists to give. The bars occupy the bottom 120px, so the map stacks
	# above them with a small gap.
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.anchor_left = 0.0
	_minimap.anchor_right = 0.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left = 24
	_minimap.offset_right = 24 + Minimap.SIZE
	_minimap.offset_top = -(140 + Minimap.SIZE)
	_minimap.offset_bottom = -140
	ui_root.add_child(_minimap)

	_upgrade_screen = UpgradeScreen.new()
	_upgrade_screen.name = "UpgradeScreen"
	_upgrade_screen.upgrade_chosen.connect(_on_upgrade_chosen)
	ui_root.add_child(_upgrade_screen)


func _start_maze(index: int) -> void:
	maze_index = index
	var config: Dictionary = Tuning.MAZES[index]

	maze = Maze.new()
	maze.generate(
		int(config["width"]),
		int(config["height"]),
		run_seed + index * 7919,   # a prime stride, so mazes do not correlate
		float(config["braid"]),
		float(config["dead_ends"]),
		int(config["gates"]),
		float(config.get("straighten", 0.0)),
		float(config.get("shallow_keep", 1.0))
	)

	if _golden_trail:
		_golden_trail.reset()

	racer = Racer.new()
	racer.setup(maze, upgrades)

	racer.crashed.connect(_on_crashed)
	racer.unstuck.connect(_on_unstuck)
	racer.slowdown.connect(_on_slowdown)
	racer.gate_entered.connect(_on_gate_entered)
	racer.exit_reached.connect(_on_exit_reached)
	racer.turned.connect(_on_turned)
	racer.reversed.connect(_on_turned.bind(-1))

	var palette_index := int(config.get("palette", 0))
	_mesh.build(maze, palette_index)
	_apply_palette(palette_index)
	_minimap.racer = racer
	_minimap.upgrades = upgrades

	_cam_target_yaw = _yaw_for(racer.facing)
	_cam_yaw = _cam_target_yaw

	phase = Phase.RACING
	_hud.show_message("%s" % String(config["name"]).to_upper(),
		Tuning.PALETTES[palette_index]["wall"])


# Retint the fog and the headlight to match the maze's palette.
#
# The mesh carries most of the colourway, but fog and the headlight wash sit
# BETWEEN the camera and every surface, so leaving them blue would push a cyan
# haze over a magenta maze and grey the whole thing out. They have to move with
# the palette or the recolour only half lands.
#
# The headlight keeps its energy and range -- only its hue moves. It is dim on
# purpose: turned up it flattens the near wall into a colour field and destroys
# the depth it exists to create.
func _apply_palette(index: int) -> void:
	var palette: Dictionary = Tuning.PALETTES[clampi(index, 0, Tuning.PALETTES.size() - 1)]

	if _environment:
		_environment.fog_light_color = palette["fog"]
		# Ambient barely leans toward the maze's hue, and stays mostly neutral.
		#
		# Tuned down hard from a 50/50 blend: at that strength maze 3's green
		# ambient lit every wall face in the SAME hue as its neon edges, and the
		# corridor washed flat -- the walls, the caps and the grid all became one
		# colour field with no depth left in it. That is the exact failure the
		# wall-face brightness is tuned to avoid (MazeMesh, "too bright"), just
		# arriving through the light instead of the material.
		#
		# It also has to stay desaturated so the gate and exit markers keep their
		# own colour across all three mazes.
		_environment.ambient_light_color = palette["grid"].lerp(Color(0.62, 0.66, 0.76), 0.8)

	if _headlight:
		_headlight.light_color = palette["wall"].lerp(Color(0.85, 0.9, 1.0), 0.45)


# --- Loop --------------------------------------------------------------------

func _process(delta: float) -> void:
	match phase:
		Phase.RACING:
			elapsed += delta
			racer.step(delta)
		Phase.TRANSITION:
			_transition_time -= delta
			if _transition_time <= 0.0:
				_start_maze(maze_index + 1)
		Phase.UPGRADING, Phase.COMPLETE:
			pass

	_update_camera(delta)

	if racer:
		_hud.update_hud(racer, upgrades, elapsed,
			String(Tuning.MAZES[maze_index]["name"]), maze_index)


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.RACING:
		return
	if not event.is_pressed() or event.is_echo():
		return

	if event.is_action("turn_left"):
		racer.request_turn(-1)
	elif event.is_action("turn_right"):
		racer.request_turn(1)
	elif event.is_action("turn_around"):
		racer.request_reverse()


# --- Camera ------------------------------------------------------------------

func _update_camera(delta: float) -> void:
	if racer == null:
		return

	# The marker sits exactly where the simulation says the player is; the
	# camera then trails IT. Keeping the marker unsmoothed means the thing the
	# player aims with is always truthful, and only the view lags.
	var ground := racer.world_position()
	ground.y = 0.0

	if _marker:
		_marker.position = ground
		_marker.rotation = Vector3(0.0, _yaw_for(racer.facing), 0.0)
		_marker.update_state(racer, delta)

	# Only while actually racing. Between mazes the racer still sits on the OLD
	# maze's exit cell for a frame after the new maze is swapped in, so a mark
	# drawn then lands on whatever happens to occupy that coordinate in the new
	# grid -- usually an open corridor, which is exactly what this must never
	# mark. It is also just noise on the completion screen.
	if _wall_indicator:
		if phase == Phase.RACING or phase == Phase.UPGRADING:
			_wall_indicator.update_state(racer, delta)
		else:
			_wall_indicator.visible = false

	# Driven in every phase the wall indicator is, deliberately: the panels are
	# part of the corridor now, so blanking them during a gate pause would make
	# the junction geometry change under the player while they read cards.
	if _path_indicator:
		if phase == Phase.RACING or phase == Phase.UPGRADING:
			_path_indicator.update_state(racer, upgrades, delta)
		else:
			_path_indicator.visible = false

	# RACING only, deliberately unlike the wall indicator. A trail firing during
	# the gate pause would draw the optimal route while the timer is stopped --
	# exactly the free scouting the minimap blur exists to prevent (section 7).
	if _golden_trail:
		if phase == Phase.RACING:
			_golden_trail.update_state(racer, upgrades, delta)
		else:
			_golden_trail.visible = false

	_cam_target_yaw = _yaw_for(racer.facing)
	# Rotate the short way round, so a west-to-north turn does not spin 270.
	var difference := wrapf(_cam_target_yaw - _cam_yaw, -PI, PI)
	_cam_yaw += difference * minf(1.0, delta * 12.0)

	# Ease toward the crash view rather than snapping, both in and out.
	var crash_target := 1.0 if racer.state == Racer.State.PARKED else 0.0
	_crash_blend = move_toward(_crash_blend, crash_target, delta * Tuning.CAM_CRASH_EASE)

	# Pull back as speed rises, so the view widens exactly when reaction time
	# gets shortest.
	var distance: float = Tuning.CAM_DISTANCE + Tuning.CAM_DISTANCE_AT_CAP * racer.speed_fraction()

	# Crashed: retreat and lift, so being stopped at a wall reads as a state
	# change and the player can see WHAT they are against.
	distance += Tuning.CAM_CRASH_DISTANCE * _crash_blend

	# Behind is the opposite of where the CAMERA faces, not where the racer
	# faces -- during a turn those differ, and following the camera's own yaw is
	# what keeps the swing smooth instead of snapping.
	var back := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))

	# Do not let the camera back into a wall. The cell behind is solid whenever
	# the player just turned a corner, sits in a dead end, or hugs the maze
	# boundary -- and a camera inside a wall box fills the screen with one flat
	# face. Clamp the pull-back to whatever clearance actually exists.
	distance = minf(distance, _camera_clearance(back))

	# Height is applied AFTER the clearance clamp, deliberately. A crash happens
	# with a wall ahead and often in a dead end, so the clamp regularly eats the
	# whole pull-back -- leaving the camera exactly where it was and the crash
	# reading as nothing at all. Lifting is the axis that stays available.
	var height: float = minf(
		Tuning.CAM_HEIGHT + Tuning.CAM_CRASH_HEIGHT * _crash_blend,
		Tuning.CAM_CRASH_HEIGHT_MAX)

	var eye := ground + back * distance + Vector3(0.0, height, 0.0)

	# Ray-marching along `back` catches walls the camera reverses into, but a
	# camera swinging through a turn also moves SIDEWAYS, and can clip a corner
	# it never pointed at. Nudging the eye back toward the nearest corridor
	# centre line covers that: it is a no-op in open corridor and only bites
	# when the camera has drifted into a wall band.
	eye = _push_out_of_walls(eye)

	# Crashed, the aim drops toward the player's own level. Lifting the eye while
	# still aiming at normal look height points the view straight INTO the wall
	# that was just hit, filling the frame with one flat face and hiding the
	# marker, the corridor, and every bit of context the pull-back existed to
	# reveal. Looking down at the player is what makes the stop legible.
	var look_height: float = lerpf(
		Tuning.CAM_LOOK_HEIGHT, Tuning.CAM_CRASH_LOOK_HEIGHT, _crash_blend)
	var look_at := ground + Vector3(0.0, look_height, 0.0)

	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		eye += Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.6, 0.6),
			randf_range(-1.0, 1.0)
		) * _shake * 0.35

	_camera.position = eye
	_camera.look_at(look_at, Vector3.UP)

	# The headlight rides ahead of the MARKER, not the camera -- the wall the
	# player is about to reach is what needs lighting.
	if _headlight:
		_headlight.position = ground + Vector3(0.0, Tuning.EYE_HEIGHT, 0.0) \
			+ racer.facing_vector() * (Tuning.CELL_SIZE * 0.4)

	# FOV widens with speed. The single strongest and cheapest speed cue there
	# is -- the corridor visibly stretches as the ramp climbs.
	var target_fov: float = lerpf(Tuning.FOV_BASE, Tuning.FOV_AT_CAP, racer.speed_fraction())
	_camera.fov = lerpf(_camera.fov, target_fov, minf(1.0, delta * 4.0))


# Clamps a camera position out of any wall slab it has drifted into.
#
# Works per-axis against the cell the point sits in: if the point has crossed
# that cell's wall band on a side that is closed, pull it back to the band edge.
# Cheap, and unlike the ray march it does not care HOW the camera got there.
func _push_out_of_walls(eye: Vector3) -> Vector3:
	var to_face: float = Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5
	var margin := 0.25
	var limit := to_face - margin

	var cell := Vector2i(
		int(round(eye.x / Tuning.CELL_SIZE)),
		int(round(eye.z / Tuning.CELL_SIZE))
	)

	# Off the grid entirely -- clamp into the nearest valid cell.
	if not maze._in_bounds(cell):
		cell.x = clampi(cell.x, 0, maze.width - 1)
		cell.y = clampi(cell.y, 0, maze.height - 1)

	var centre := Vector3(cell.x * Tuning.CELL_SIZE, eye.y, cell.y * Tuning.CELL_SIZE)
	var offset := eye - centre

	if offset.x > limit and not maze.is_open(cell, Maze.E):
		offset.x = limit
	elif offset.x < -limit and not maze.is_open(cell, Maze.W):
		offset.x = -limit

	if offset.z > limit and not maze.is_open(cell, Maze.S):
		offset.z = limit
	elif offset.z < -limit and not maze.is_open(cell, Maze.N):
		offset.z = -limit

	return centre + offset


# How far the camera may sit behind the player before it enters a wall.
#
# Queried against the maze grid rather than physics: the walls are pure
# geometry with no collision bodies, and the grid answers exactly the same
# question for free.
func _camera_clearance(back: Vector3) -> float:
	var max_distance: float = Tuning.CAM_DISTANCE + Tuning.CAM_DISTANCE_AT_CAP

	# March along `back` in small steps and stop at the first blocked cell.
	#
	# `back` is derived from the CAMERA's yaw, which lags the racer's facing
	# through a turn -- so mid-turn it can point at a wall that is neither
	# ahead of nor behind the racer. Checking only the racer's opposite
	# direction misses exactly that case, and the camera swings through the
	# corner. Stepping the actual ray is what covers every angle it can hold.
	var to_face: float = Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5
	var origin := racer.world_position()
	origin.y = 0.0

	# Fine steps: a coarse march can straddle a wall slab entirely and report
	# clear. 0.1m is well under the 0.5m wall thickness.
	var step := 0.1
	var travelled := 0.0

	while travelled < max_distance:
		travelled += step
		var probe := origin + back * travelled
		var cell := Vector2i(
			int(round(probe.x / Tuning.CELL_SIZE)),
			int(round(probe.z / Tuning.CELL_SIZE))
		)

		# Outside the maze entirely, or inside a wall slab between two cells.
		if not maze._in_bounds(cell):
			return maxf(0.8, travelled - step - 0.45)

		var centre := Vector3(cell.x * Tuning.CELL_SIZE, 0.0, cell.y * Tuning.CELL_SIZE)
		var offset := probe - centre
		if absf(offset.x) > to_face or absf(offset.z) > to_face:
			# In the wall band around this cell -- only legal if that side is
			# actually an opening.
			var dir := Maze.E if offset.x > to_face else (Maze.W if offset.x < -to_face else 0)
			if dir == 0:
				dir = Maze.S if offset.z > to_face else Maze.N
			if not maze.is_open(cell, int(dir)):
				return maxf(0.8, travelled - step - 0.45)

	return max_distance


# Maze +Y is south, which in world space is +Z. Camera looks down -Z at yaw 0,
# so each compass direction maps to the yaw that points the camera along it.
func _yaw_for(direction: int) -> float:
	match direction:
		Maze.N: return 0.0
		Maze.S: return PI
		Maze.E: return -PI * 0.5
		Maze.W: return PI * 0.5
	return 0.0


# --- Events ------------------------------------------------------------------

func _on_turned(_direction: int) -> void:
	pass


func _on_crashed() -> void:
	_shake = 1.0
	_hud.flash(Color(1.0, 0.2, 0.15), 0.5)
	# Held, not faded: the player stays parked until they press DOWN, so the
	# prompt has to outlast a 1.6s fade or they are left stopped with nothing on
	# screen telling them why.
	_hud.show_message("CRASH  -  press DOWN to recover", Color(1.0, 0.35, 0.3), true)


func _on_unstuck() -> void:
	_hud.clear_held_message()


func _on_slowdown() -> void:
	_hud.flash(Color(1.0, 0.65, 0.1), 0.22)
	_hud.show_message("TOO EARLY", Color(1.0, 0.75, 0.2))


func _on_gate_entered(index: int) -> void:
	_mesh.clear_gate(index - 1)
	phase = Phase.UPGRADING
	_minimap.blurred = true
	_upgrade_screen.present(upgrades, index)


func _on_upgrade_chosen(line: int) -> void:
	if line >= 0:
		upgrades.take(line)
		_hud.show_message("%s  RANK %d" % [
			upgrades.line_name(line).to_upper(), upgrades.rank(line)
		], Color(0.2, 1.0, 0.5))

	_minimap.blurred = false
	phase = Phase.RACING


func _on_exit_reached() -> void:
	if maze_index + 1 < Tuning.MAZES.size():
		phase = Phase.TRANSITION
		_transition_time = 2.0
		_hud.show_message("MAZE CLEARED", Color(0.35, 1.0, 0.45))
	else:
		phase = Phase.COMPLETE
		_hud.show_message("RUN COMPLETE  -  %s" % _hud._format_time(elapsed),
			Color(0.35, 1.0, 0.45))
