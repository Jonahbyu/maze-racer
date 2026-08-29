# The Golden Trail upgrade: a periodic scout that runs the optimal route ahead.
#
# See CLAUDE.md section 7. The design point is that it is PERIODIC, not
# continuous. Path Indicator answers "this junction, right now" at every
# junction forever; this answers "where does this corridor actually go" a few
# times a minute and says nothing in between. That is what keeps the two lines
# from collapsing into each other.
#
# Rendering only. Every number it reads comes from Upgrades/Tuning, and the
# route itself is Maze.route_from() -- so the rule is testable headlessly and
# this node is just the picture.
class_name GoldenTrail
extends Node3D

const COL_HEAD := Color(1.0, 0.92, 0.45)
const COL_TAIL := Color(1.0, 0.66, 0.10)

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
	_material.set_shader_parameter("col_head", Vector3(COL_HEAD.r, COL_HEAD.g, COL_HEAD.b))
	_material.set_shader_parameter("col_tail", Vector3(COL_TAIL.r, COL_TAIL.g, COL_TAIL.b))
	_material.set_shader_parameter("head", 0.0)
	_material.set_shader_parameter("fade", 1.0)

	_mesh = MeshInstance3D.new()
	_mesh.name = "Streak"
	_mesh.material_override = _material
	add_child(_mesh)

	visible = false


# Called every frame while racing. `delta` is real time; the trail's own speed is
# derived from the racer's current speed so it always pulls ahead.
func update_state(racer: Racer, upgrades: Upgrades, delta: float) -> void:
	_ensure_built()

	if not upgrades.has_trail() or racer == null or racer.maze == null:
		_active = false
		visible = false
		return

	if _active:
		_advance(racer, delta)
	else:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_fire(racer, upgrades)


# Snapshot the route from where the player is standing RIGHT NOW. Recomputing
# mid-flight would make the streak swerve as the player turns, which reads as a
# bug; a trail is a photograph of the route at the moment it fired.
func _fire(racer: Racer, upgrades: Upgrades) -> void:
	var cells := racer.maze.route_from(racer.cell, int(upgrades.trail_cells()))

	_cooldown = upgrades.trail_interval()

	# A route of one cell is "nowhere to go" -- at the exit, or boxed in. Drawing
	# a zero-length streak would just flicker, so skip this cycle entirely.
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
	_active = true
	visible = true
	_build_ribbon()
	_material.set_shader_parameter("head", 0.0)
	_material.set_shader_parameter("fade", 1.0)


func _advance(racer: Racer, delta: float) -> void:
	var segments := float(_points.size() - 1)

	if _head < segments:
		# Cells per second: the racer's own cell rate, doubled. Tying this to
		# live speed rather than a fixed rate is what keeps it legible -- at 5x a
		# fixed-rate streak would trail BEHIND the player, inverting the point.
		var rate := racer.speed * Tuning.BASE_CELL_RATE * Tuning.TRAIL_SPEED_MULTIPLIER
		_head = minf(_head + rate * delta, segments)
		_material.set_shader_parameter("head", _head)
		return

	# Fully drawn: hold, then fade out over the linger.
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
	_cooldown = 0.0
	_points = PackedVector3Array()
	visible = false
	if _mesh:
		_mesh.mesh = null
