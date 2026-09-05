# The trail upgrades: a periodic scout that runs a whole route ahead.
#
# See CLAUDE.md section 7. The design point is that it is PERIODIC, not
# continuous. Path Indicator answers "this junction, right now" at every
# junction forever; this answers "where does this corridor actually go" a few
# times a minute and says nothing in between. That is what keeps the two lines
# from collapsing into each other.
#
# ONE node class serves both trail lines, differing only in the target it routes
# to and the colours it draws in. They are the same mechanism aimed at two
# different questions:
#
#   GOLDEN   -- the next gate the player has not taken yet. The "collect your
#               upgrades" line. A gate is deliberately NOT on the distance-field
#               gradient, so this frequently points away from the exit.
#   PLATINUM -- the exit. The "finish fast" line, and the shortest way home.
#
# Holding both is meant to be strong and to show the player something neither
# gives alone: the two ribbons diverge exactly where a gate costs a detour, which
# is the routing decision section 11.2 exists to protect. A second class would
# have been a second copy of the ribbon, the shader and the timing to keep in
# step -- the parallel-array trap of sections 6 and 9c wearing different clothes.
#
# Rendering only. Every number it reads comes from Upgrades/Tuning, and the
# routes themselves are Maze.route_to()/route_from() -- so the rule is testable
# headlessly and this node is just the picture.
class_name GoldenTrail
extends Node3D

enum Mode { GOLDEN, PLATINUM }

const COL_HEAD := Color(1.0, 0.92, 0.45)
const COL_TAIL := Color(1.0, 0.66, 0.10)

# Platinum reads as cool silver-white against gold's warm amber, which is what
# lets the two be told apart at a glance when both are on screen. It stays clear
# of the reserved colours in section 8: the exit marker is white but is a tall
# vertical object rather than a line on the floor, and the palettes own cyan,
# magenta, green, ember and violet -- none of which a desaturated steel sits in.
const COL_PLAT_HEAD := Color(0.95, 0.98, 1.0)
const COL_PLAT_TAIL := Color(0.55, 0.68, 0.82)

# Height above the floor. Low enough to read as a line painted on the ground
# rather than a wire strung through the corridor, high enough to clear the grid
# lines it crosses.
const TRAIL_HEIGHT := 0.10
# Narrow on purpose. At 0.55 the ribbon filled most of the corridor floor and
# read as a painted road rather than a streak shooting ahead -- and a road is a
# permanent feature, which is exactly the wrong impression for something that
# fires for a couple of seconds. CELL_SIZE is 4.0, so this is under a tenth of
# the corridor width.
const TRAIL_WIDTH := 0.32

# Which question this instance answers. GOLDEN is the default so an
# unconfigured instance behaves as the original line did rather than silently
# drawing nothing.
#
# Written through a SETTER because the colours depend on it and `_ready` may
# already have run: Game sets `mode` after `add_child`, which is when _ready
# fires and builds the material. A plain field would have left a platinum trail
# wearing gold -- the failure would be a screenshot-only one, since nothing
# headless can see a colour. Assigning re-applies rather than rebuilding, so the
# order the caller happens to use cannot matter.
var mode: int = Mode.GOLDEN:
	set(value):
		mode = value
		_apply_colours()

var _mesh: MeshInstance3D
var _material: ShaderMaterial

# The route being drawn, in world-space points along cell centres.
var _points: PackedVector3Array = PackedVector3Array()

# Seconds until the next firing. Counted down rather than accumulated so a rank
# change mid-run takes effect on the next cycle instead of retroactively.
var _cooldown := 0.0

# How far the head has travelled along the route, in cells. Once it reaches the
# end the trail holds for TRAIL_LINGER before clearing.
var _head := 0.0
var _linger := 0.0
# Seconds spent drawing this firing, bounding the draw phase -- see _advance.
var _draw_time := 0.0
var _active := false

# The whole ribbon is built ONCE per firing and revealed by moving a shader
# uniform, never by rebuilding geometry.
#
# The first version rebuilt the SurfaceTool mesh every frame to animate the
# head. Measured: 23ms per frame for a single trail -- on its own more than a
# whole 60fps budget, and enough to make a headless test loop look like an
# infinite hang. Vertex data does not change as the streak advances; only how
# much of it is visible does, which is exactly what a shader uniform is for.
const SHADER_SOURCE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform float head = 0.0;
uniform float fade = 1.0;
uniform vec3 col_head : source_color = vec3(1.0, 0.92, 0.45);
uniform vec3 col_tail : source_color = vec3(1.0, 0.66, 0.10);

varying float along;

void vertex() {
	along = UV.x;
}

void fragment() {
	// UV.x carries each vertex's distance along the route, in cells. Anything
	// past the head has not been drawn yet.
	if (along > head) {
		discard;
	}
	float t = clamp(along / max(head, 0.001), 0.0, 1.0);
	vec3 c = mix(col_tail, col_head, t);
	// Brighten the leading edge so the direction of travel reads from a still.
	float tip = smoothstep(head - 1.2, head, along);
	ALBEDO = c * (1.0 + tip * 1.6);
	ALPHA = fade;
}
"""


func _ready() -> void:
	_ensure_built()


# Build lazily rather than relying on _ready having run.
#
# A caller can reach update_state() before the node's _ready fires -- a harness
# that adds the node and drives it synchronously in the same frame does exactly
# that -- and every set_shader_parameter() then hit a null material. Doing the
# work on first use makes the node correct whatever the call order.
func _ensure_built() -> void:
	if _material != null:
		return

	var shader := Shader.new()
	shader.code = SHADER_SOURCE

	_material = ShaderMaterial.new()
	_material.shader = shader
	_apply_colours()
	_material.set_shader_parameter("head", 0.0)
	_material.set_shader_parameter("fade", 1.0)

	_mesh = MeshInstance3D.new()
	_mesh.name = "Streak"
	_mesh.material_override = _material
	add_child(_mesh)

	visible = false


# Safe to call before the material exists -- the build calls it again.
func _apply_colours() -> void:
	if _material == null:
		return
	var head_col := COL_PLAT_HEAD if mode == Mode.PLATINUM else COL_HEAD
	var tail_col := COL_PLAT_TAIL if mode == Mode.PLATINUM else COL_TAIL
	_material.set_shader_parameter("col_head", Vector3(head_col.r, head_col.g, head_col.b))
	_material.set_shader_parameter("col_tail", Vector3(tail_col.r, tail_col.g, tail_col.b))


# Called every frame while racing. `delta` is real time; the trail's own speed is
# derived from the racer's current speed so it always pulls ahead.
func update_state(racer: Racer, upgrades: Upgrades, delta: float) -> void:
	_ensure_built()

	if not _line_held(upgrades) or racer == null or racer.maze == null:
		_active = false
		visible = false
		return

	# Platinum says nothing until the gate tour is most of the way done.
	#
	# The two lines answer questions that belong to different halves of a maze:
	# for the first five gates the live question is "where are my upgrades", and
	# a silver ribbon pointing at the exit during that stretch is an invitation
	# to skip picks the player has already paid for. Once PLATINUM_MIN_GATES are
	# banked the question genuinely changes to "get me out", and Platinum is the
	# answer to that one.
	#
	# It also does most of the work of keeping the two apart. Before gate 5 only
	# Golden can fire at all, so the overlap window shrinks to the back third of
	# a maze -- the interlock below covers what is left rather than carrying the
	# whole burden.
	if mode == Mode.PLATINUM and racer.gates_taken < Tuning.PLATINUM_MIN_GATES:
		_active = false
		visible = false
		return

	if _active:
		_advance(racer, delta)
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return

	# Never fire on top of the other trail. Deferred rather than skipped: the
	# cooldown is NOT reset, so this trail fires the moment the other clears
	# instead of losing its whole cycle. Losing the cycle would make a rank of
	# Platinum quietly worth less than its card claims whenever Golden happened
	# to be busy.
	if _partner != null and _partner.is_showing():
		return

	_fire(racer, upgrades)


# The other trail, when both lines are held. Set by Game on both instances.
#
# THE TWO MUST NEVER BE ON SCREEN TOGETHER. They are ribbons of the same shape
# on the same floor, and gates sit on the solve path (section 7) -- so most of
# the time the route to the next gate IS the route to the exit and the two lie
# exactly on top of each other. Drawn together the near one simply paints over
# the far one, and what the player sees is one ribbon in a muddled colour: worse
# than either alone, and it destroys the one thing the split is for, which is
# seeing the two DISAGREE.
#
# Measured before this rule existed: at rank 3 the intervals are 5s and 6s
# against a draw phase of up to 2.5s plus a 2s linger, so an overlap is not an
# edge case -- it is most of the time. The first rendered frame of both lines
# together showed gold drawn over silver with the silver reading as a white
# smear beneath it.
var _partner: GoldenTrail = null


func set_partner(other: GoldenTrail) -> void:
	_partner = other


# Is the other trail currently drawing or lingering?
func is_showing() -> bool:
	return _active


func _line_held(upgrades: Upgrades) -> bool:
	if upgrades == null:
		return false
	return upgrades.has_platinum_trail() if mode == Mode.PLATINUM else upgrades.has_trail()


func _interval(upgrades: Upgrades) -> float:
	return upgrades.platinum_interval() if mode == Mode.PLATINUM else upgrades.trail_interval()


# The cell this trail is aimed at, or the player's own cell when there is
# nothing to aim at -- which _fire reads as "nowhere to go" and skips.
#
# GOLDEN takes the NEAREST gate not yet cleared, by route length rather than by
# placement order. Gate order is a property of the canonical solve path, and a
# braided maze (section 8) routinely puts a later gate closer than an earlier
# one; sending the streak to gate 2 while gate 5 is round the corner would be
# advice the player is right to ignore, which is worse than no advice.
#
# Falling back to the exit once every gate is taken is what keeps the line from
# going dead for the rest of the maze. It is not stepping on Platinum's toes --
# Platinum answers the exit for the WHOLE maze, which is the part worth paying
# for; Golden reaching it only after its own job is finished is the tail end of
# a line the player already spent picks on.
func _target(racer: Racer) -> Vector2i:
	if mode == Mode.PLATINUM:
		return racer.maze.exit_cell

	var best := racer.cell
	var best_len := -1
	for gate in racer.maze.gates:
		if racer.gates_cleared.has(gate):
			continue
		var route := racer.maze.route_to(racer.cell, gate)
		if route.size() < 2:
			continue
		if best_len == -1 or route.size() < best_len:
			best_len = route.size()
			best = gate

	if best_len == -1:
		return racer.maze.exit_cell
	return best


# Snapshot the route from where the player is standing RIGHT NOW. Recomputing
# mid-flight would make the streak swerve as the player turns, which reads as a
# bug; a trail is a photograph of the route at the moment it fired.
#
# The route runs the WHOLE way to the target -- there is no length cap. How far
# the player actually SEES is set by their speed, since the head advances at a
# multiple of the racer's own cell rate and the trail clears when it completes:
# at 8x a ribbon reaches several times as far in the same wall-clock moment as
# it does at 1x. That is deliberately the opposite of the old fixed cell count,
# which handed the fast player -- who has the least time to read a junction --
# exactly as much lookahead as the slow one.
func _fire(racer: Racer, upgrades: Upgrades) -> void:
	_cooldown = _interval(upgrades)

	var target := _target(racer)
	var cells: Array[Vector2i]
	if mode == Mode.PLATINUM:
		# route_to would give the same answer, but the distance field already
		# holds it and descending it is free. A huge max keeps it uncapped.
		cells = racer.maze.route_from(racer.cell, racer.maze.width * racer.maze.height)
	else:
		cells = racer.maze.route_to(racer.cell, target)

	# A route of one cell is "nowhere to go" -- standing on the target, boxed in,
	# or a target the bounded search could not reach. Drawing a zero-length
	# streak would just flicker, so skip this cycle entirely.
	if cells.size() < 2:
		_active = false
		visible = false
		return

	_points = PackedVector3Array()
	for c in cells:
		_points.append(Vector3(
			c.x * Tuning.CELL_SIZE,
			TRAIL_HEIGHT,
			c.y * Tuning.CELL_SIZE
		))

	_head = 0.0
	_linger = 0.0
	_draw_time = 0.0
	_active = true
	visible = true
	_build_ribbon()
	_material.set_shader_parameter("head", 0.0)
	_material.set_shader_parameter("fade", 1.0)


# The head advances until it reaches the end of the route, then holds and fades.
#
# With the route uncapped, "the end" can be hundreds of cells away, and a slow
# racer would still be drawing when the next firing was due -- so a trail could
# monopolise the line and never re-fire from the player's CURRENT cell, which is
# the one thing that keeps the snapshot honest. TRAIL_MAX_DRAW bounds the drawing
# phase in SECONDS: whatever the head has reached by then is what the player
# gets, and the linger starts from there. That is the duration rule doing its
# job -- reach is the racer's speed times a fixed moment, so it is the fast
# player who is shown further, and nobody is shown a ribbon that outlives its own
# cycle.
func _advance(racer: Racer, delta: float) -> void:
	var segments := float(_points.size() - 1)

	_draw_time += delta

	if _head < segments and _draw_time < Tuning.TRAIL_MAX_DRAW:
		# Cells per second: the racer's own cell rate, doubled. Tying this to
		# live speed rather than a fixed rate is what keeps it legible -- at 5x a
		# fixed-rate streak would trail BEHIND the player, inverting the point.
		# It is also what makes REACH scale with speed now that length does not.
		var rate := racer.speed * Tuning.BASE_CELL_RATE * Tuning.TRAIL_SPEED_MULTIPLIER
		_head = minf(_head + rate * delta, segments)
		_material.set_shader_parameter("head", _head)
		return

	# Fully drawn, or out of drawing time: hold, then fade out over the linger.
	_linger += delta
	if _linger >= Tuning.TRAIL_LINGER:
		_active = false
		visible = false
		return

	_material.set_shader_parameter("fade", 1.0 - _linger / Tuning.TRAIL_LINGER)


# Build the full ribbon once. UV.x carries distance along the route in cells,
# which is what the shader compares against `head` to reveal it progressively.
#
# Drawn as quads on the floor plane rather than a line primitive: line width is
# not portable across renderers in Godot 4 and a 1px line is invisible at speed.
func _build_ribbon() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := TRAIL_WIDTH * 0.5

	for i in _points.size() - 1:
		var a: Vector3 = _points[i]
		var b: Vector3 = _points[i + 1]

		var dir := b - a
		if dir.length() < 0.0001:
			continue
		dir = dir.normalized()
		# Perpendicular in the floor plane.
		var side := Vector3(-dir.z, 0.0, dir.x) * half

		var u0 := float(i)
		var u1 := float(i + 1)

		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(a - side)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(b + side)
		st.set_uv(Vector2(u1, 0.0)); st.add_vertex(b - side)

		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(a - side)
		st.set_uv(Vector2(u0, 1.0)); st.add_vertex(a + side)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(b + side)

	st.generate_normals()
	_mesh.mesh = st.commit()


# A new maze means the old route is meaningless. Game calls this on maze change.
func reset() -> void:
	_ensure_built()
	_active = false
	_head = 0.0
	_linger = 0.0
	_draw_time = 0.0
	_cooldown = 0.0
	_points = PackedVector3Array()
	visible = false
	if _mesh:
		_mesh.mesh = null
