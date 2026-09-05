# The run controller: owns the maze, the racer, the camera, and the phase
# machine that moves between racing, upgrade picks, and maze transitions.
#
# The simulation itself lives in Racer; this node drives it, renders it, and
# routes input to it. Keeping that split is what lets the whole rule set be
# tested headlessly (CLAUDE.md section 12).
extends Node3D

enum Phase { RACING, UPGRADING, TRANSITION, COMPLETE, PAUSED, DEAD, VISION }

# The player dismissed the end-of-run summary. Shell listens and returns to the
# menu; a harness that instantiates Game bare simply never connects it, which is
# why the run does not tear itself down here.
signal run_dismissed()

# Right edge of the HUD's barrier/integrity column, and the smallest map worth
# drawing. Both are needed by _place_minimap now that the map is centred rather
# than tucked in the opposite corner.
#
# Mirrored from HUD's own layout literals rather than measured off the live
# node, for the reason section 9d records about the touch pads: the HUD builds
# its layout from literals too, and a queried rect is only correct once a frame
# has been laid out -- which has not happened when this runs. If the bars move,
# this moves with them; they are one screen.
const HUD_BARS_RIGHT := 340.0
const MINIMAP_MIN := 96.0

# The pause-screen settings cog, top-right. Below the HUD's top row rather than
# beside it: the timer is right-aligned there and its width changes as the run
# passes a minute, so anything sharing that line eventually collides with it.
const COG_MARGIN := 24.0
const COG_TOP := 76.0

var maze: Maze
var racer: Racer
var upgrades: Upgrades
var score: Score

var phase: int = Phase.RACING
var maze_index := 0
var run_seed := 0

# Which leaderboard this run counts toward (docs/plans/leaderboards.md). Set by
# Shell before the scene is added, exactly as trailer_seed is -- _ready derives
# run_seed from it, so it has to be in place before then.
#
# GENERAL keeps the wall-clock seed, so that board still draws a fresh maze
# every run; DAILY and MONTHLY derive theirs from the date.
var board: int = Tuning.Board.GENERAL

# Set before the node enters the tree to force a specific seed, overriding the
# clock. The trailer needs this (docs/specs/trailer.md): it starts a maze during
# its own _ready, so pinning run_seed afterwards -- the way SceneTest does --
# would come one maze too late. 0 means "use the clock", which is every normal
# run.
var trailer_seed := 0

# The run timer. Pauses during upgrade picks -- it is the score, and the whole
# optimisation target, so it must never tick while the player is reading cards.
var elapsed := 0.0

var _camera: Camera3D
var _headlight: OmniLight3D
var _environment: Environment
var _marker: PlayerMarker
var _path_indicator: PathIndicator
var _golden_trail: GoldenTrail
var _platinum_trail: GoldenTrail
var _mesh: MazeMesh
var _hud: HUD
var _minimap: Minimap
var _rear_view: RearView
var _quadrant_box: QuadrantBox
var _upgrade_screen: UpgradeScreen
var _run_summary: RunSummary
var _touch: TouchControls

# The settings panel, built on demand from the pause screen and freed on close.
# Not built up front: it is a modal the player may never open, and one that
# exists all run is one more Control competing for input every frame.
var _settings_panel: SettingsPanel = null
var _settings_cog: Button = null
var _world: Node3D
var _transition_time := 0.0

# --- Legendaries (CLAUDE.md section 7) ---------------------------------------

# When the last reverse input arrived, for double-tap detection.
var _last_reverse_time := -999.0

# Flying Vision: seconds left of the held view, then of the countdown back in.
var _vision_time := 0.0
var _vision_countdown := 0.0

# Smoothed camera state, so the view does not snap on turns.
var _cam_yaw := 0.0

# 0 = normal view, 1 = fully in the crash view. Eased, never snapped.
var _crash_blend := 0.0
var _cam_target_yaw := 0.0
var _shake := 0.0


func _ready() -> void:
	run_seed = trailer_seed if trailer_seed != 0 \
		else Tuning.seed_for_board(board)
	upgrades = Upgrades.new(run_seed)
	score = Score.new()

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

	_path_indicator = PathIndicator.new()
	_path_indicator.name = "PathIndicator"
	_world.add_child(_path_indicator)

	_golden_trail = GoldenTrail.new()
	_golden_trail.name = "GoldenTrail"
	_world.add_child(_golden_trail)
	# mode is set AFTER add_child, which is when _ready builds the material.
	# GoldenTrail.mode is a setter for exactly that reason -- see its comment.
	_golden_trail.mode = GoldenTrail.Mode.GOLDEN

	_platinum_trail = GoldenTrail.new()
	_platinum_trail.name = "PlatinumTrail"
	_world.add_child(_platinum_trail)
	_platinum_trail.mode = GoldenTrail.Mode.PLATINUM

	# The two ribbons are the same shape on the same floor, and gates sit on the
	# solve path -- so left alone they draw on top of each other and the player
	# sees one muddled line instead of two that disagree. Pairing them means
	# whichever fires second waits rather than overlapping.
	_golden_trail.set_partner(_platinum_trail)
	_platinum_trail.set_partner(_golden_trail)

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

	# Positioned by _place_minimap, which is called once the touch pads exist --
	# the map's corner depends on whether they are up.
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	ui_root.add_child(_minimap)

	# The rear-view mirror. Top-left under the speed row, and it renders the
	# SAME World3D the main camera does -- see RearView.gd for why a second copy
	# of the world would be the wrong construction.
	#
	# Added after the minimap and before the upgrade screen, so the cards and
	# the summary both draw over it.
	_rear_view = RearView.new()
	_rear_view.name = "RearView"
	ui_root.add_child(_rear_view)
	_rear_view.attach_world(get_viewport().world_3d)

	# The quadrant box hangs under the mirror in the same left column. It is
	# given the mirror's bottom edge rather than measuring it, so the two cannot
	# drift apart -- see QuadrantBox.place().
	_quadrant_box = QuadrantBox.new()
	_quadrant_box.name = "QuadrantBox"
	ui_root.add_child(_quadrant_box)

	_upgrade_screen = UpgradeScreen.new()
	_upgrade_screen.name = "UpgradeScreen"
	_upgrade_screen.upgrade_chosen.connect(_on_upgrade_chosen)
	ui_root.add_child(_upgrade_screen)

	# Added after the upgrade screen so it draws over it: a run that ends during
	# an upgrade pick must not leave cards on top of the summary.
	_run_summary = RunSummary.new()
	_run_summary.name = "RunSummary"
	_run_summary.dismissed.connect(_on_summary_dismissed)
	# The player named themselves after the run had already gone up as "anon".
	# Best-of keying means this overwrites that entry rather than adding one.
	_run_summary.repost.connect(func(): _post_run(phase == Phase.DEAD))
	ui_root.add_child(_run_summary)

	# Only visible while paused -- see _set_paused. A cog on a live corridor
	# would be a mouse target over the thing the player is steering through.
	_settings_cog = _make_settings_cog()
	ui_root.add_child(_settings_cog)

	# Added LAST so the pads sit above the HUD and the upgrade cards in draw
	# order. They are transparent panels over a corner each, so what matters is
	# not what they cover but that a tap reaches them rather than the card
	# behind -- and the topmost STOP control wins that.
	_touch = TouchControls.new()
	_touch.name = "TouchControls"
	_touch.turn_requested.connect(_on_turn_input)
	_touch.reverse_requested.connect(_on_reverse_input)
	_touch.pause_requested.connect(_on_pause_input)
	ui_root.add_child(_touch)
	_apply_touch_setting()

	# Settings is an autoload and so is absent from a harness that instantiates
	# this scene directly rather than booting the project. Guarded for the same
	# reason Shell guards Music: a missing preference must never be what stops
	# the game starting.
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.touch_controls_changed.connect(
			func(_enabled: bool) -> void: _apply_touch_setting())

	# The mirror derives its whole size from the viewport's shorter edge, so it
	# has to be re-placed whenever that changes -- otherwise a window resized
	# after boot leaves a box sized for the old screen, and on a phone that is
	# the difference between a usable mirror and a postage stamp. The minimap
	# gets the same call for the same reason.
	ui_root.resized.connect(_place_ui)
	_place_ui()


# Positions everything whose layout is derived from the viewport size rather
# than fixed by anchors. Called at build and on every resize.
func _place_ui() -> void:
	_place_minimap()
	_place_rear_view()
	_place_quadrant_box()


func _place_rear_view() -> void:
	if _rear_view == null:
		return
	var parent := _rear_view.get_parent()
	if parent == null:
		return
	var view: Vector2 = parent.size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	_rear_view.place(view)


# Hung off the MIRROR's bottom edge rather than off a constant of its own. Both
# widgets size themselves from the viewport's shorter edge, so a literal here
# would be correct at one screen size and overlap at every other -- the same
# hard-coded-band trap CLAUDE.md section 12 records for the upgrade card row.
func _place_quadrant_box() -> void:
	if _quadrant_box == null:
		return
	var parent := _quadrant_box.get_parent()
	if parent == null:
		return
	var view: Vector2 = parent.size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var top: float = _rear_view.offset_bottom if _rear_view != null else 96.0
	_quadrant_box.place(view, top)


# The minimap sits DIRECTLY BELOW THE PLAYER MARKER, on desktop and mobile
# alike.
#
# It was bottom-left on desktop, which was already an argument about distance:
# section 12 moved it out of the top-right corner because the map and the
# corridor are read together at speed, and a diagonal glance across the whole
# screen costs the read the map exists to give. Centring finishes that move
# rather than reversing it -- the marker sits on the centre line slightly below
# the middle of the screen, so the shortest possible glance is straight down
# from it, not down and away to a corner.
#
# It also puts the map on the axis the player is already looking along. The
# corridor vanishing point, the marker and the map now stack vertically, so
# checking the map is a flick of the eye down the same line rather than a
# saccade to a different part of the screen and back.
#
# Mobile reached this position first and for an additional reason: with pads up,
# the bottom-left corner IS a thumb, so the map would have sat under the hand
# holding the phone. The centre strip is the one part of the bottom edge no
# thumb occupies, since the pads are hard against the left and right margins.
# Both platforms now want the same answer, so the branch below is only about
# SIZE and clearance, not about which corner.
func _place_minimap() -> void:
	if _minimap == null:
		return

	var touch: bool = _touch != null and _touch.visible

	# Minimap.SIZE is a desktop pixel figure, and on a small phone a fixed
	# 210px square is over half the screen height. Shrink it to fit rather than
	# let it run off the bottom -- same failure the pads' pixel caps had, and
	# the same fix.
	var view: Vector2 = _minimap.get_parent().size
	var span: float = Minimap.SIZE
	if touch and view.y > 0.0:
		span = min(span, view.y * 0.5)

	# Centred, the map runs into the barrier/integrity bars on a narrow window:
	# the bars occupy the left 340px of the same bottom band, so anything below
	# roughly 890px wide overlaps them. Shrink to the gap rather than cover them
	# -- the barrier bar is the most important element on screen (CLAUDE.md
	# section 5.1), so it wins any contest for these pixels.
	#
	# Measured against the HUD's own literals rather than a queried rect, for
	# the reason section 9d records: the HUD builds its layout from literals
	# too, and a queried rect is only correct after a frame has been laid out.
	var gap_left := 0.0
	if view.x > 0.0:
		var free_half: float = view.x * 0.5 - HUD_BARS_RIGHT - 16.0
		span = min(span, maxf(free_half * 2.0, MINIMAP_MIN))
		gap_left = HUD_BARS_RIGHT + 16.0

	_minimap.custom_minimum_size = Vector2(span, span)

	# Centred horizontally under the marker, which is the whole point of the
	# placement -- but NUDGED RIGHT if centring would still put the map over the
	# bars. Below roughly 890px wide the two demands cannot both be met, and
	# clearing the bars wins: MINIMAP_MIN floors the shrink above, so on a very
	# narrow window the map would otherwise be sitting on the barrier readout
	# with nothing left to give.
	#
	# Off-centre by a few pixels costs almost nothing, because the marker is
	# large and the glance is vertical. The alternative -- shrinking past the
	# floor -- costs the map its legibility, and an unreadable map centred
	# perfectly is worse than a readable one slightly to the right.
	var left := -span * 0.5
	if view.x > 0.0:
		left = maxf(left, gap_left - view.x * 0.5)

	_minimap.anchor_left = 0.5
	_minimap.anchor_right = 0.5
	_minimap.offset_left = left
	_minimap.offset_right = left + span

	# Bottom-anchored, and it can sit low now that it is centred: the barrier
	# and integrity bars are hard against the LEFT margin, so the map no longer
	# has to stack above them the way the old corner placement did. Clearing
	# them by height was the only reason the desktop gap was 140.
	_minimap.anchor_top = 1.0
	_minimap.anchor_bottom = 1.0
	var bottom_gap := 24.0
	_minimap.offset_top = -(bottom_gap + span)
	_minimap.offset_bottom = -bottom_gap


# The pads exist whether or not they are shown, and visibility is the only
# thing the setting changes. A hidden Control takes no input in Godot, so this
# is also what stops an invisible pad swallowing a click on the upgrade cards.
func _apply_touch_setting() -> void:
	if _touch == null:
		return
	var settings := get_node_or_null("/root/Settings")
	_touch.visible = settings != null and bool(settings.touch_controls)
	# The map moves out from under the thumb pads with the setting.
	_place_minimap()


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
		float(config.get("shallow_keep", 1.0)),
		_landmark_density(index),
		float(config.get("zigzag_keep", 1.0))
	)

	if _golden_trail:
		_golden_trail.reset()
	if _platinum_trail:
		_platinum_trail.reset()

	racer = Racer.new()
	racer.setup(maze, upgrades, index)

	racer.crashed.connect(_on_crashed)
	racer.unstuck.connect(_on_unstuck)
	racer.slowdown.connect(_on_slowdown)
	racer.gate_entered.connect(_on_gate_entered)
	racer.exit_reached.connect(_on_exit_reached)
	racer.turned.connect(_on_turned)
	racer.reversed.connect(_on_turned.bind(-1))
	racer.died.connect(_on_died)
	racer.cell_entered.connect(_on_cell_entered)

	# The track is named on the maze config, so a maze changes its own music the
	# same way it changes its own palette (docs/specs/music.md). Shared across all
	# five today; this call does not care.
	_music_for_maze(index)

	var palette_index := int(config.get("palette", 0))
	_mesh.build(maze, palette_index)
	_apply_palette(palette_index)
	_minimap.racer = racer
	_minimap.upgrades = upgrades

	_cam_target_yaw = _yaw_for(racer.facing)
	_cam_yaw = _cam_target_yaw

	phase = Phase.RACING

	# The loadout card screen already names the maze in its title, and it opens
	# on this same frame -- so announcing it on the HUD as well drew the name
	# twice, overlapping, in two different sizes. The banner is what gives way:
	# it is the decoration, the title is load-bearing.
	#
	# The trailer prints the name itself, larger and clear of the corridor
	# (docs/specs/trailer.md), which is the same reason it is suppressed there.
	_offer_loadout(index)
	if trailer_seed == 0 and phase != Phase.UPGRADING:
		_hud.show_message("%s" % String(config["name"]).to_upper(),
			Tuning.PALETTES[palette_index]["wall"])


# The loadout pick: one upgrade at the START of every maze, before the racer has
# covered any ground.
#
# It is the same card screen a gate uses, deliberately. The player already knows
# how to read it, and a second UI saying the same thing in a different shape
# would be two things to keep in sync for no gain. Only the title changes, so
# the MOMENT still reads as distinct from a gate.
#
# Why it exists: a maze used to open with whatever build the previous one ended
# on, so arriving somewhere new -- which section 8 wants to read as ARRIVING --
# came with no decision attached. A pick on entry means every maze starts by
# asking what you want to be for it.
#
# The trailer is excluded for the same reason it suppresses the HUD maze banner:
# it calls _start_maze five times in thirty seconds and drives a pre-built
# upgrade set per segment (docs/specs/trailer.md), so a card screen on every cut
# would cover the reel in modal UI the reel never asked for.
func _offer_loadout(index: int) -> void:
	if trailer_seed != 0:
		return

	phase = Phase.UPGRADING
	_minimap.blurred = true
	_upgrade_screen.present_loadout(upgrades, index)


# Landmark density for a maze, from its own config (docs/specs/landmarks.md).
#
# Read off the maze entry rather than a parallel per-maze array, so adding a
# sixth maze cannot leave the array short and silently hand it a density of
# zero -- the same reason the gate count is read from MAZES rather than being
# restated (CLAUDE.md section 12).
func _landmark_density(index: int) -> float:
	if index < 0 or index >= Tuning.MAZES.size():
		return Tuning.LANDMARK_DENSITY
	return float(Tuning.MAZES[index].get("landmarks", Tuning.LANDMARK_DENSITY))


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
		# own colour across every maze.
		_environment.ambient_light_color = palette["grid"].lerp(Color(0.62, 0.66, 0.76), 0.8)

	if _headlight:
		_headlight.light_color = palette["wall"].lerp(Color(0.85, 0.9, 1.0), 0.45)


# --- Loop --------------------------------------------------------------------

func _process(delta: float) -> void:
	match phase:
		Phase.RACING:
			elapsed += delta
			# The maze clock drives the time multiplier and runs alongside the
			# run timer, which measures the whole run (CLAUDE.md section 8b).
			score.advance_time(delta)
			racer.step(delta)
			# Clean travel only: a parked racer earns nothing, which is what
			# stops a crash paying for the time it costs.
			if racer.state == Racer.State.RUNNING and not racer.dead:
				# Kept in step every frame rather than on each pick, so a rank
				# taken mid-maze applies immediately and nothing has to remember
				# to push it.
				score.earn_multiplier = upgrades.score_multiplier()
				score.add_travel(delta, racer.speed)
		Phase.TRANSITION:
			_transition_time -= delta
			if _transition_time <= 0.0:
				_start_maze(maze_index + 1)
		Phase.VISION:
			# Neither clock advances: elapsed and the maze budget are both held,
			# which is what makes this a genuine reprieve (CLAUDE.md section 7).
			if _vision_time > 0.0:
				_vision_time -= delta
				if _vision_time <= 0.0:
					_vision_countdown = Tuning.VISION_COUNTDOWN
			elif _vision_countdown > 0.0:
				var before := ceili(_vision_countdown)
				_vision_countdown -= delta
				var after := ceili(_vision_countdown)
				# One message per whole second, not per frame.
				if after != before and after > 0:
					_hud.show_message(str(after), Color(0.7, 0.9, 1.0))
				if _vision_countdown <= 0.0:
					_end_vision()
		Phase.UPGRADING, Phase.COMPLETE, Phase.PAUSED, Phase.DEAD:
			# PAUSED stops `elapsed` along with the simulation. The timer IS the
			# score (CLAUDE.md section 8), so a pause that let it run would be a
			# penalty for stepping away, and one that let the sim run would be
			# no pause at all.
			pass

	_update_camera(delta)

	if racer:
		_hud.update_hud(racer, upgrades, elapsed,
			String(Tuning.MAZES[maze_index]["name"]), maze_index, score)
		_update_quadrant_box()


# Feeds the quadrant box everything it draws.
#
# It is NOT frozen with the phase the way the mirror is. The mirror shows live
# corridor, so a stopped clock would hand the player a free look at the world;
# this shows which sixteenth of the maze they occupy, which does not change
# while they are parked and gives nothing away when it is read at leisure. The
# same reasoning that makes it safe as a free-standing readout makes it safe
# during a pick.
func _update_quadrant_box() -> void:
	if _quadrant_box == null or racer == null or racer.maze == null:
		return

	var divisions := 0
	var here := Vector2i(-1, -1)
	var exit_at := Vector2i(-1, -1)
	var number := 0
	var total := 0

	if upgrades.has_quadrant():
		divisions = upgrades.quadrant_divisions()
		here = racer.maze.quadrant_coord(racer.cell, divisions)
		exit_at = racer.maze.quadrant_coord(racer.maze.exit_cell, divisions)
		number = racer.maze.quadrant_of(racer.cell, divisions)
		total = racer.maze.quadrant_count(divisions)

	var cardinal := ""
	if upgrades.has_cardinal_compass():
		cardinal = Maze.cardinal_name(racer.facing)

	_quadrant_box.show_state(divisions, here, exit_at, number, total, cardinal)
	# Hidden outright when neither line is held, so an untaken pair costs no
	# pixels rather than leaving an empty frame in the corner.
	_quadrant_box.visible = divisions > 0 or cardinal != ""


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	# Every branch here just forwards to the shared handler below, which owns
	# the phase gating. The touch pads call the same methods.
	if event.is_action("pause_game"):
		_on_pause_input()
		return

	if event.is_action("turn_left"):
		_on_turn_input(-1)
	elif event.is_action("turn_right"):
		_on_turn_input(1)
	elif event.is_action("turn_around"):
		_on_reverse_input()


# The three driving inputs and pause, as methods rather than inline branches.
#
# The touch pads raise these too, so a tap and a key press cannot diverge --
# including on the phase gating, which is the part that would rot silently if it
# were duplicated. A pad that turned during an upgrade pick would be driving the
# racer while the timer is stopped.

func _on_turn_input(direction: int) -> void:
	if phase != Phase.RACING:
		return
	racer.request_turn(direction)


func _on_reverse_input() -> void:
	if phase != Phase.RACING:
		return

	# A double-tap reaches the held legendary. Guarded so it can never steal the
	# crash un-stick: a parked player mashing DOWN to recover would otherwise
	# burn the ability at exactly the moment they did not want it
	# (CLAUDE.md section 7).
	var now := elapsed
	var is_double := (now - _last_reverse_time) <= Tuning.DOUBLE_TAP_WINDOW
	_last_reverse_time = now

	# A press that UN-STICKS is not part of a gesture. Without this the guard
	# only half-works: the first tap on a parked racer recovers it to RUNNING,
	# so the second tap sees a running racer and fires the ability -- which is
	# precisely the recovery mash the guard exists to stop. Clearing the tap
	# here means the player must press again, deliberately, after they are
	# actually moving.
	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_reverse_time = -999.0
		return

	if is_double and racer.state == Racer.State.RUNNING and not racer.dead:
		if _try_legendary_gesture():
			# Consumed: do not also reverse, and clear the tap so a third press
			# does not immediately read as another double.
			_last_reverse_time = -999.0
			return

	racer.request_reverse()


# The double-tap abilities. Wall Smasher is not here -- it fires on contact, not
# on input. Returns true if an ability actually started.
func _try_legendary_gesture() -> bool:
	if upgrades.has_flying_vision():
		return _start_vision()
	if upgrades.has_auto_steer():
		if racer.start_auto_steer():
			_hud.show_message("AUTO-STEER", Color(0.5, 0.85, 1.0))
			return true
	return false


# Flying Vision: stop the world and rise above the maze.
#
# The run timer and the maze budget BOTH stop, which makes using it on cooldown
# strictly optimal -- a known and accepted cost, recorded in section 7 so it is
# not mistaken later for an oversight.
func _start_vision() -> bool:
	if racer.legendary_cooldown > 0.0:
		return false
	racer.legendary_cooldown = upgrades.legendary_cooldown()
	_vision_time = Tuning.VISION_DURATION
	_vision_countdown = 0.0
	phase = Phase.VISION
	# The minimap is redundant under a real overhead view, and leaving it up
	# would be a second, worse map competing with the one the ability exists to
	# give.
	_minimap.blurred = true
	_hud.show_message("FLYING VISION", Color(0.7, 0.9, 1.0))
	return true


# Not gated on RACING, unlike the three above: the whole point of pause is that
# it works when the game is not racing, since an unpause has to be reachable
# from the paused phase itself.
func _on_pause_input() -> void:
	# The panel is modal over a paused game: a pause press while it is open is
	# aimed at the panel, and resuming underneath it would hand the player a
	# running corridor with a settings card still on screen. The panel closes
	# itself on ESC; this covers the pause PAD, which does not go through
	# _unhandled_input at all (CLAUDE.md section 9d).
	if _settings_panel != null:
		_close_settings()
		return
	if phase == Phase.RACING:
		_set_paused(true)
	elif phase == Phase.PAUSED:
		_set_paused(false)


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

	# Aimed off the RACER's facing, not the camera's trailing yaw. The chase
	# camera deliberately lags through a pivot so the swing reads smoothly
	# (the turn freeze exists to pay for exactly that), but a mirror that lagged
	# would spend every corner showing the wall it was in the middle of leaving.
	# The mirror is an instrument: it should be pointing behind you the moment
	# you are facing the new way.
	if _rear_view:
		_rear_view.aim(ground, racer.facing_vector())
		# Frozen off the PHASE, in one place, rather than a line beside each of
		# the seven sites that blur the minimap. Those sites blur because each
		# knows it is opening a modal; the mirror only cares whether the clock
		# is stopped, and deriving that from the phase means a phase added later
		# cannot forget to freeze it. It stops rendering rather than blurring:
		# it only ever shows ground already driven, so there is nothing to
		# scramble -- the cost being paid is a free look at a static world on a
		# stopped clock, and not drawing it is the cheapest way to refuse that.
		_rear_view.frozen = phase != Phase.RACING

	# Flying Vision lifts the camera clear of the maze and looks straight down.
	#
	# This is the ONE place the section 12 rule "camera height stays below
	# WALL_HEIGHT" is suspended. That rule exists so corridors feel enclosed
	# while DRIVING; this is explicitly not driving, and the reprieve from the
	# enclosure is the whole ability. It bypasses the anti-clip passes too --
	# there is nothing up there to clip against.
	if phase == Phase.VISION:
		var eye := ground + Vector3(0.0, Tuning.VISION_CAMERA_HEIGHT, 0.01)
		_camera.position = _camera.position.lerp(eye, minf(1.0, delta * 6.0))
		_camera.look_at(ground, Vector3(0.0, 0.0, -1.0))
		return

	# Driven during a gate pause as well as while racing, deliberately: the
	# panels are part of the corridor now, so blanking them while the cards are
	# up would make the junction geometry change under the player as they read.
	#
	# Not driven between mazes: the racer still sits on the OLD maze's exit cell
	# for a frame after the new maze is swapped in, so anything drawn then lands
	# on whatever happens to occupy that coordinate in the new grid.
	if _path_indicator:
		if phase == Phase.RACING or phase == Phase.UPGRADING:
			_path_indicator.update_state(racer, upgrades, delta)
		else:
			_path_indicator.visible = false

	# RACING only, deliberately unlike the Path Indicator. A trail firing during
	# the gate pause would draw the optimal route while the timer is stopped --
	# exactly the free scouting the minimap blur exists to prevent (section 7).
	if _golden_trail:
		if phase == Phase.RACING:
			_golden_trail.update_state(racer, upgrades, delta)
		else:
			_golden_trail.visible = false
	if _platinum_trail:
		if phase == Phase.RACING:
			_platinum_trail.update_state(racer, upgrades, delta)
		else:
			_platinum_trail.visible = false

	_cam_target_yaw = _yaw_for(racer.facing)
	# Rotate the short way round, so a west-to-north turn does not spin 270.
	var difference := wrapf(_cam_target_yaw - _cam_yaw, -PI, PI)
	# The turn freeze exists so the view can catch up to a pivot the world made
	# instantly -- so the camera swings FASTER while it runs, not at its usual
	# trailing rate. A freeze the camera does not spend is just a stutter: the
	# player would be held still and still be looking the old way when released.
	var yaw_rate := 12.0
	if racer.freeze > 0.0:
		yaw_rate *= Tuning.TURN_FREEZE_CAM_MULTIPLIER
	_cam_yaw += difference * minf(1.0, delta * yaw_rate)

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

	# THIRD pass, and the only one that asks about the marker at all. The two
	# above keep the EYE out of walls; this one keeps the LINE from the eye to
	# the marker clear, which is a different question -- swinging through a
	# corner, the camera sits in open space while the segment to the marker cuts
	# the inside corner, and the wall just passed wipes across the marker for a
	# few frames. The marker must never be obscured (CLAUDE.md section 12).
	eye = _clear_sight_to(eye, ground)

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
		# The shake is applied AFTER the three anti-clip passes, so it can throw
		# the eye straight back into the geometry they just cleared -- including
		# behind the wall between the camera and the marker, which section 12
		# makes a hard rule. Re-run the two passes that own that rule.
		#
		# It has to be re-run rather than clamped because the offset is random:
		# the failure is intermittent by construction, and it showed up as a
		# sight check that failed with a DIFFERENT count every run (28, 37, 44
		# of 2000 frames) long after the deterministic causes were fixed.
		eye = _push_out_of_walls(eye)
		eye = _clear_sight_to(eye, ground)

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
# Pull the eye in until nothing stands between it and the marker.
#
# The camera is capped below WALL_HEIGHT, so it can never see over a wall and
# sight is a pure floor-plane problem: if the segment crosses a solid wall band,
# the marker is hidden, full stop.
#
# Pulling IN rather than pushing sideways is deliberate. Sliding the eye around
# an obstruction changes the viewing angle mid-corner, which reads as the camera
# lurching sideways on its own -- and the corridor the player is about to enter
# swings out of frame just as they need it. Closing the distance keeps the
# camera on the axis it already holds and shortens the segment until it fits in
# the open space; the view tightens through a corner and opens again after,
# which reads as the camera hugging the turn rather than fighting it.
func _clear_sight_to(eye: Vector3, target: Vector3) -> Vector3:
	var aim := target
	aim.y = eye.y

	if not _sight_blocked(eye, aim):
		return eye

	# Binary search the fraction of the way in that first clears. Bisection
	# rather than fixed steps so a deep intrusion costs no more work than a
	# shallow one, and the camera never gets pulled further in than it must --
	# an over-eager pull-in is its own artifact.
	var span := eye - aim
	if span.length() < 0.001:
		return eye

	# Fractions along the segment from the marker (0.0) to the eye (1.0). The
	# eye is known blocked -- that is why we are here -- and the marker end is
	# taken as clear, since a camera sitting on the marker has nothing between
	# them by definition.
	var blocked := 1.0
	var clear := 0.0

	for _i in range(12):
		var mid := (blocked + clear) * 0.5
		if _sight_blocked(aim + span * mid, aim):
			blocked = mid
		else:
			clear = mid

	var distance: float = maxf(Tuning.CAM_SIGHT_MIN_DISTANCE, span.length() * clear)
	var settled := aim + span.normalized() * distance

	if not _sight_blocked(settled, aim):
		return settled

	# Pulling in along this axis bottomed out and sight is still blocked.
	#
	# LIFTING DOES NOT HELP HERE, which is worth writing down because it is the
	# obvious next move and it is wrong: walls run floor to WALL_HEIGHT with no
	# gap and the camera is capped below that, so a level sight line is blocked
	# at every height the camera can legally hold. Raising the eye only tilts the
	# view; it never clears the wall. (The crash camera lifts to show the player
	# WHAT they hit, which is a different goal from seeing past it.)
	#
	# So the last resort is to close the remaining gap entirely and sit on the
	# marker. A very tight camera for a frame or two is a far smaller failure
	# than the marker disappearing -- section 12 makes that a hard rule, and this
	# is the branch that keeps it true when the geometry allows nothing better.
	#
	# CAM_SIGHT_HARD_MIN is not itself guaranteed to clear, and returning it
	# blind is how this branch used to leave the marker hidden anyway: measured,
	# 44 of 2000 autopilot frames sat at exactly the hard minimum and were STILL
	# blocked, every one of them within a few hundredths of a grid line just
	# after a turn -- the marker is closest to the corner it has just rounded,
	# and _sight_blocked() holds CAM_SIGHT_MARGIN of clearance off every wall
	# face on top of that.
	#
	# So close the rest of the way rather than stopping at a number. The loop
	# walks in toward the marker and returns the first distance that genuinely
	# clears; sitting ON the marker is clear by definition (zero-length segments
	# report unblocked), so this always terminates with the rule satisfied.
	var hard := aim + span.normalized() * Tuning.CAM_SIGHT_HARD_MIN
	if not _sight_blocked(hard, aim):
		return hard

	# Walk from the hard minimum down to CAM_SIGHT_FLOOR, taking the first
	# distance that genuinely clears. Interpolating between the two rather than
	# scaling the hard minimum, so the steps keep shrinking all the way down --
	# a max() against the floor stalls the walk partway and hands back a
	# position that is still blocked, which is the bug this loop exists to fix.
	var dir := span.normalized()
	for i in range(1, 9):
		var f := float(i) / 8.0
		var d: float = lerpf(Tuning.CAM_SIGHT_HARD_MIN, Tuning.CAM_SIGHT_FLOOR, f)
		var shrunk := aim + dir * d
		if not _sight_blocked(shrunk, aim):
			return shrunk

	# Nothing along the axis clears, so sit at the floor: effectively on the
	# marker, which is what the hard rule asks for when geometry allows nothing
	# better. Never at zero -- eye and target would coincide on the floor plane
	# and look_at() would warn about colinear vectors every frame.
	return aim + dir * Tuning.CAM_SIGHT_FLOOR


# Does a solid wall stand between these two points on the floor plane?
#
# Asks the maze grid rather than physics, for the same reason _camera_clearance
# does: the walls are pure geometry with no collision bodies, and the grid
# answers the same question for free.
func _sight_blocked(from: Vector3, to: Vector3) -> bool:
	var to_face: float = Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5 - Tuning.CAM_SIGHT_MARGIN
	var span := to - from
	var length := span.length()
	if length < 0.001:
		return false

	# Step well under the cell size so the walk cannot straddle a wall band and
	# report clear -- the same failure the 0.1m step in _camera_clearance avoids.
	var steps := int(ceil(length / 0.12))

	for i in range(steps + 1):
		var p := from + span * (float(i) / float(steps))
		var cell := Vector2i(
			int(round(p.x / Tuning.CELL_SIZE)),
			int(round(p.z / Tuning.CELL_SIZE))
		)
		if not maze._in_bounds(cell):
			return true

		var ox: float = p.x - float(cell.x) * Tuning.CELL_SIZE
		var oz: float = p.z - float(cell.y) * Tuning.CELL_SIZE

		# In the wall band on one side of this cell? Only legal if that side is
		# an actual opening.
		var dir := 0
		if absf(ox) > to_face:
			dir = Maze.E if ox > 0.0 else Maze.W
		elif absf(oz) > to_face:
			dir = Maze.S if oz > 0.0 else Maze.N

		if dir != 0 and not maze.is_open(cell, dir):
			return true

	return false


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


# --- Settings ----------------------------------------------------------------

# Top-right, matching the title screen's cog so the same affordance sits in the
# same corner in both places.
func _make_settings_cog() -> Button:
	var cog := Button.new()
	cog.name = "SettingsCog"
	cog.text = "⚙"
	cog.tooltip_text = "Settings"
	cog.visible = false
	cog.focus_mode = Control.FOCUS_NONE
	cog.custom_minimum_size = Vector2(MainMenu.COG_SIZE, MainMenu.COG_SIZE)
	cog.add_theme_font_size_override("font_size", 30)
	cog.add_theme_color_override("font_color", MainMenu.COL_DIM)
	cog.add_theme_color_override("font_hover_color", MainMenu.COL_ACCENT)

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var lit: bool = state in ["hover", "focus", "pressed"]
		style.bg_color = MainMenu.COL_CARD_HOVER if lit else MainMenu.COL_CARD
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = (MainMenu.COL_ACCENT if lit
			else Color(0.2, 0.3, 0.45))
		cog.add_theme_stylebox_override(state, style)

	# The HUD timer is right-aligned in the top row, and its width CHANGES as
	# the run passes a minute -- so anything sharing that line collides with it
	# eventually (the mistake the pause pad made, CLAUDE.md section 9d). The cog
	# sits below the row, not beside it.
	cog.anchor_left = 1.0
	cog.anchor_right = 1.0
	cog.anchor_top = 0.0
	cog.anchor_bottom = 0.0
	cog.offset_left = -MainMenu.COG_SIZE - COG_MARGIN
	cog.offset_right = -COG_MARGIN
	cog.offset_top = COG_TOP
	cog.offset_bottom = COG_TOP + MainMenu.COG_SIZE

	cog.pressed.connect(_open_settings)
	return cog


func _open_settings() -> void:
	if _settings_panel != null:
		return
	var ui_root := get_node_or_null("UI/UIRoot")
	if ui_root == null:
		return
	var panel := SettingsPanel.new()
	panel.name = "SettingsPanel"
	panel.closed.connect(_close_settings)
	_settings_panel = panel
	ui_root.add_child(panel)
	panel.focus_first()


func _close_settings() -> void:
	if _settings_panel == null:
		return
	_settings_panel.queue_free()
	_settings_panel = null


func settings_open() -> bool:
	return _settings_panel != null


# --- Pause -------------------------------------------------------------------

# Enter or leave the paused phase.
#
# The minimap blurs, for exactly the reason it blurs at a gate (CLAUDE.md
# section 7): a paused, static, zoomed-out map is a free solve of the whole
# maze, and pause would otherwise be a strictly better version of the gate
# screen -- available any time, at no cost, for as long as you like.
func _set_paused(on: bool) -> void:
	if on:
		phase = Phase.PAUSED
		_minimap.blurred = true
		if _settings_cog != null:
			_settings_cog.visible = true
		# Ducked, not stopped. Music continuing quietly is what says the game is
		# held rather than gone, and a volume change keeps the track's position.
		_music_duck(true)
		_hud.show_message("PAUSED  -  press ESC or P to resume", Color(0.7, 0.85, 1.0), true)
	else:
		phase = Phase.RACING
		_minimap.blurred = false
		# Resuming with the panel still up would leave a modal over a live
		# corridor, swallowing the steering inputs the player just went back to.
		_close_settings()
		if _settings_cog != null:
			_settings_cog.visible = false
		_music_duck(false)
		_hud.clear_held_message()
		# Pausing while parked overwrote the crash prompt with the pause prompt,
		# and clearing it here would leave the player stopped with nothing on
		# screen telling them why -- the exact failure the held message exists to
		# prevent. Put it back if the crash it describes is still current.
		if racer and racer.state == Racer.State.PARKED:
			_hud.show_message("CRASH  -  press DOWN to recover", Color(1.0, 0.35, 0.3), true)


# --- Events ------------------------------------------------------------------

func _on_turned(_direction: int) -> void:
	# A turn out of a scrape is worth 40% of a clean one -- see the note on
	# Tuning.SCORE_TURN_SCRAPED. The racer records which it was, because
	# `scraping` is already cleared by the time this fires.
	score.add_turn(racer.speed, racer.last_turn_scraped)


# A cell boundary was crossed. Fresh ground is what the player is supposed to be
# covering; repeat ground both costs and, more importantly, stops paying.
#
# Two separate things happen here, and they are charged on different flags
# (CLAUDE.md section 8b):
#
#   `repeat`       -- true on EVERY re-crossing, so it gates whether the cell
#                     earns travel and turn points at all. This is the rule that
#                     makes farming unprofitable.
#   `first_repeat` -- true only the first time a cell is re-entered, so the flat
#                     penalty is charged once per cell rather than per lap.
#
# Charged in RACING only. The trailer drives the real Game through this same
# surface (docs/specs/trailer.md) and a reel segment that re-crosses its own
# path must not accumulate a penalty nobody is scoring.
func _on_cell_entered(_cell: Vector2i, repeat: bool, first_repeat: bool) -> void:
	if phase != Phase.RACING:
		return
	score.on_repeat_ground = repeat
	if first_repeat:
		score.add_repeat()


func _on_crashed() -> void:
	score.add_crash()
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


# `index` is the gate's PLACEMENT in `maze.gates`, which is what names its
# marker node -- so it goes to the mesh unmodified.
#
# The card title wants a different number: how many gates the player has taken,
# which is `gates_taken`. The two were one parameter, and reading the placement
# as a count is what made the header say "GATE 5" on the second gate of a loopy
# maze. They are only the same on a maze driven in placement order.
func _on_gate_entered(index: int) -> void:
	_mesh.clear_gate(index)
	phase = Phase.UPGRADING
	_minimap.blurred = true
	_upgrade_screen.present(upgrades, racer.gates_taken)


func _on_upgrade_chosen(line: int) -> void:
	# Idempotent: the screen hides itself on a card press, but this is also
	# reached directly (harnesses, and any future non-card exit from a pick),
	# and a pick that ends without hiding the cards leaves them drawn over live
	# gameplay.
	_upgrade_screen.dismiss()

	if line >= 0:
		upgrades.take(line)
		_hud.show_message("%s  RANK %d" % [
			upgrades.line_name(line).to_upper(), upgrades.rank(line)
		], Color(0.2, 1.0, 0.5))

	_minimap.blurred = false
	phase = Phase.RACING


# HP reached 0 with death enabled (Tuning.DEATH_ENABLED).
#
# The run ends where it stands. Unlike a crash there is no un-stick: the racer
# is already PARKED from the crash that killed it, and DEAD stops the timer and
# the simulation the same way COMPLETE does.
func _end_vision() -> void:
	_vision_time = 0.0
	_vision_countdown = 0.0
	phase = Phase.RACING
	_minimap.blurred = false
	_hud.show_message("GO", Color(0.35, 1.0, 0.45))


func _on_died() -> void:
	phase = Phase.DEAD

	# Bank what was actually achieved in the maze being driven, measured by
	# gates taken (CLAUDE.md section 8b). Gates are already the maze's own
	# milestones, evenly spaced along the solve path, so "5 of 8" is a real
	# statement about progress and needs no extra tracking -- and unlike
	# distance travelled it cannot be farmed by wandering.
	var config: Dictionary = Tuning.MAZES[maze_index]
	var gate_total := maxi(1, int(config["gates"]))
	var progress := float(racer.gates_taken) / float(gate_total)
	score.bank_maze(maze_index, String(config["name"]), progress)

	# The summary carries the outcome, so the HUD message would be a second,
	# smaller copy of the headline behind a full-screen modal. Cleared instead:
	# a held crash prompt is still on screen at this point and would otherwise
	# sit under the summary waiting to reappear.
	_hud.clear_message()
	_upgrade_screen.dismiss()
	_post_run(true)
	_run_summary.present(score, upgrades, elapsed, maze_index, _covered_hud())


func _on_exit_reached() -> void:
	var config: Dictionary = Tuning.MAZES[maze_index]
	var mult := score.time_multiplier()
	var earned := score.bank_maze(maze_index, String(config["name"]))

	if maze_index + 1 < Tuning.MAZES.size():
		phase = Phase.TRANSITION
		_transition_time = 2.0
		_hud.show_message("MAZE CLEARED  -  %s  x%.2f" % [
			RunSummary.format_score(earned), mult
		], Color(0.35, 1.0, 0.45))
	else:
		phase = Phase.COMPLETE
		_hud.clear_message()
		_upgrade_screen.dismiss()
		_post_run(false)
		_run_summary.present(score, upgrades, elapsed, -1, _covered_hud())


# Send the finished run to the leaderboard.
#
# Called from both terminal paths and nowhere else: this is the only point at
# which a run is genuinely over and its score final. A run abandoned by closing
# the tab never reaches here, which is correct -- there is no partial submission.
#
# Guarded on the autoload's presence, like every other Music/Settings call: a
# harness instantiates Game.tscn bare with no autoloads at all, and the desktop
# build has no JavaScriptBridge. Neither may be what stops a run ending.
#
# The trailer is excluded on trailer_seed, the same flag that already suppresses
# the HUD maze banner and the loadout pick -- the reel drives real runs through
# this controller and must never post a score for one.
func _post_run(died: bool) -> void:
	if trailer_seed != 0:
		return
	var lb := get_node_or_null("/root/Leaderboard")
	if lb == null:
		return
	# maze_results holds one entry per BANKED maze, and the maze that just ended
	# is already among them -- both callers bank before posting. A death banks a
	# partial maze, so cleared counts only the ones actually finished.
	var cleared := 0
	for result in score.maze_results:
		if float(result.get("progress", 1.0)) >= 1.0:
			cleared += 1
	lb.post_run(score.total(), elapsed, run_seed, board, cleared, died)


# The live readouts the summary covers, hidden while it is up.
#
# Every one of them is a frozen number from a run that has ENDED, drawn on top of
# the screen that reports what those numbers finally came to -- two accounts of
# the same run, one of them stale. Only a rendered frame shows this; no headless
# assertion can see one Control drawn over another.
func _covered_hud() -> Array:
	var nodes: Array = []
	if _hud != null:
		nodes.append(_hud)
	if _minimap != null:
		nodes.append(_minimap)
	if _touch != null:
		nodes.append(_touch)
	return nodes


# The player dismissed the summary. Game does not tear itself down -- Shell owns
# the mode swap, exactly as it does when the trailer finishes.
func _on_summary_dismissed() -> void:
	_run_summary.dismiss()
	run_dismissed.emit()


# --- Music -------------------------------------------------------------------
#
# Both guarded: Music is an autoload, so it is absent whenever a harness loads
# Game.tscn directly instead of booting the project, and every harness runs
# --headless with no audio driver. Nothing in the simulation reads these
# (docs/specs/music.md) -- they are called from phase changes only.

func _music_for_maze(index: int) -> void:
	# The trailer cuts between all five mazes in thirty seconds and owns its own
	# track. Letting each cut re-request that maze's music would restart the
	# soundtrack five times across one reel -- and crossfade through four of
	# them. trailer_seed is already the "am I the trailer" test here; it is what
	# suppresses the HUD maze banner for the same reason.
	if trailer_seed != 0:
		return
	var music := get_node_or_null("/root/Music")
	if music != null:
		music.play_for_maze(index)


func _music_duck(on: bool) -> void:
	var music := get_node_or_null("/root/Music")
	if music != null:
		music.set_ducked(on)
