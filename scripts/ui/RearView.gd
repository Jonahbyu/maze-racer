# The rear-view mirror: a small box in the top-left corner showing the corridor
# BEHIND the player, live, at all times.
#
# WHY IT IS SAFE TO GIVE AWAY FREE. It answers "what did I just pass", never
# "which way should I go" -- which is the line landmarks (CLAUDE.md section 6)
# and spent gate markers (section 7) already sit on. Everything it can show is
# ground the player has ALREADY driven, so it cannot cannibalise Path Indicator,
# Gate Compass or Golden Trail, all three of which are paid lines sold on
# answering the route AHEAD. What it adds is memory, not routing: a corridor you
# are about to reverse into is one you can see before committing the 180, and a
# gate or landmark you have passed stays legible for a moment longer.
#
# It renders the real world through a second camera rather than being faked.
# Sharing `world_3d` with the main viewport is what makes it truthful -- the
# maze, the marker, the gates, the Path Indicator strips and the Golden Trail
# are all the same nodes, so nothing can drift out of step with what is on the
# main screen. A separate scene would be a second copy of the world to keep in
# sync, which is the same trap section 12 records for a parallel array.
#
# TOP-LEFT, below the speed/maze row. Every other corner is spoken for: the
# timer's width CHANGES past a minute so nothing may share its line (the
# section 9d collision), bottom-left is the barrier and integrity bars, and
# bottom-centre is the minimap. Top-left under the row is the one band with
# nothing in it on either platform -- the touch pads are bottom-anchored and the
# pause pad is top-RIGHT.
#
# NOTHING IN THE SIMULATION MAY READ THIS. Movement, turn resolution, the
# buffer, the barrier and the penalties behave identically with the mirror
# absent. Same separation landmarks, music and settings have.
class_name RearView
extends Control

# Size as a fraction of the SHORTER viewport edge, for the reason section 9d
# gives for the touch pads: a pixel is a count, not a size, and a phone reports
# a large pixel viewport at a small physical one. The short edge is the honest
# reference.
const SHORT_FRACTION := 0.20
# Wider than tall. A corridor is a horizontal thing, and what is useful behind
# you is what is beside and behind, not the sky above it.
const ASPECT := 1.6
# A floor, not a ceiling -- the mistake the pads made was capping at a pixel
# maximum, which handed the smallest screen the smallest box.
const MIN_SIZE := Vector2(150.0, 94.0)
# Never more than this share of the viewport, so a narrow window cannot let the
# mirror eat the corridor it exists to supplement.
const MAX_WIDTH_SHARE := 0.24

const MARGIN := 24.0
# Clears the speed / maze / timer row.
#
# The row's own band runs to y=70, and 86 was measured off that -- but the maze
# name and gate count are the row's SHORTEST labels, sitting on its baseline
# well below its nominal top, and the mirror's frame cut through them. Rendered
# frames are the only thing that shows this: the row's rect and the mirror's
# rect did not overlap, and the TEXT inside the row still did.
const TOP_BAND := 96.0

# A wider lens than the main camera. The mirror is small, so a normal FOV shows
# almost nothing in it; widening trades distortion -- which nobody steers by --
# for actually seeing the mouth of the corridor just left.
const FOV := 95.0
# Shorter than the main camera's 220. Nothing in a box this size is legible at
# 200m, and a shorter far plane keeps depth precision honest in a viewport that
# shares its near plane and its geometry with the main one.
const FAR := 90.0

const COL_FRAME := Color(0.35, 0.72, 1.0, 0.55)
const COL_LABEL := Color(0.55, 0.78, 1.0, 0.75)
const FRAME_WIDTH := 2.0

# Where the mirror camera sits relative to the marker, and how high.
#
# The eye is slightly AHEAD of the player looking backwards, not behind them
# looking further back. Behind-and-back would frame the corridor the player has
# not reached the far end of yet, which is not what a mirror is; ahead-and-back
# puts their own wake in frame with the marker at the near edge.
const AHEAD := 0.55
const HEIGHT := 1.35
# What it aims at, above the floor at the point it looks toward.
#
# Aimed ABOVE the eye, deliberately, so the view pitches very slightly UP rather
# than down. The first pass aimed below the eye and the frame came out roughly
# 40% empty black ceiling with the corridor crushed into the bottom half -- a
# 95-degree lens over a 3m-high corridor sees a lot of nothing above the wall
# line, and pitching down only adds more of it. Raising the aim trades ceiling
# the player cannot use for floor grid and wall bands, which is where every
# recognisable feature actually is.
const LOOK_HEIGHT := 1.5
# How far back the aim point sits. Far enough that the view is a corridor rather
# than a wall face, short enough that the pitch stays near level.
const LOOK_BACK := 5.0

var _viewport: SubViewport
var _camera: Camera3D
var _display: TextureRect
var _label: Label

# Set by the pause and gate paths, for the same anti-abuse reason the minimap
# blurs (CLAUDE.md sections 2 and 7). A frozen rear view is a far weaker free
# solve than a frozen map -- it shows only ground already driven -- but it is
# still a free look at a static world on a stopped clock, and the cheapest
# answer is to stop rendering it.
var frozen := false:
	set(value):
		frozen = value
		_apply_frozen()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.name = "RearViewport"
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.audio_listener_enable_3d = false
	_viewport.size = Vector2i(int(MIN_SIZE.x), int(MIN_SIZE.y))
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "RearCamera"
	_camera.fov = FOV
	# Matches the main camera's near plane. Both viewports render the same
	# geometry, so a different near/far ratio here would z-fight differently in
	# the mirror than on screen -- the same surfaces shimmering in one view and
	# not the other, which reads as a mirror bug rather than a depth one.
	_camera.near = 0.25
	_camera.far = FAR
	_camera.current = true
	_viewport.add_child(_camera)

	_display = TextureRect.new()
	_display.name = "RearDisplay"
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.texture = _viewport.get_texture()
	add_child(_display)

	_label = Label.new()
	_label.name = "RearLabel"
	_label.text = "REAR"
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", COL_LABEL)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(6.0, 2.0)
	add_child(_label)


# Shares the main scene's World3D, which is what makes the mirror show the real
# maze rather than an empty room. Called by Game once its world exists -- a
# SubViewport builds its own World3D otherwise, and would render nothing but
# background colour.
func attach_world(world: World3D) -> void:
	if _viewport and world:
		_viewport.world_3d = world


func place(view: Vector2) -> void:
	var short_edge: float = min(view.x, view.y)
	var w: float = max(short_edge * SHORT_FRACTION * ASPECT, MIN_SIZE.x)
	w = min(w, view.x * MAX_WIDTH_SHARE)
	var h: float = max(w / ASPECT, MIN_SIZE.y)

	# The top band is a desktop measurement, so it gets the same clamp the touch
	# pads' HUD bands do: 86px of a 390px-tall phone is over a fifth of the
	# screen, and reserving it whole would push the mirror down over the world.
	var top: float = min(TOP_BAND, view.y * 0.22)

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = MARGIN
	offset_right = MARGIN + w
	offset_top = top
	offset_bottom = top + h
	size = Vector2(w, h)

	if _viewport:
		# The render target is sized in whole pixels, and a zero on either axis
		# is a viewport that renders nothing at all.
		_viewport.size = Vector2i(max(1, int(w)), max(1, int(h)))

	queue_redraw()


# Aims the mirror camera, given the same `ground` the main view is built from so
# the two can never disagree about where the player is.
func aim(ground: Vector3, facing: Vector3) -> void:
	if _camera == null:
		return

	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()

	var eye := ground + flat * AHEAD + Vector3(0.0, HEIGHT, 0.0)
	var target := ground - flat * LOOK_BACK + Vector3(0.0, LOOK_HEIGHT, 0.0)

	_camera.position = eye
	_camera.look_at(target, Vector3.UP)


func _apply_frozen() -> void:
	if _viewport == null:
		return
	_viewport.render_target_update_mode = \
		SubViewport.UPDATE_DISABLED if frozen else SubViewport.UPDATE_ALWAYS
	if _display:
		_display.visible = not frozen
	if _label:
		_label.visible = not frozen
	queue_redraw()


func _draw() -> void:
	if frozen:
		return
	# A thin frame, so the mirror reads as a surface of its own rather than a
	# hole punched in the corridor. Same hue family as the minimap's ring.
	draw_rect(Rect2(Vector2.ZERO, size), COL_FRAME, false, FRAME_WIDTH)
