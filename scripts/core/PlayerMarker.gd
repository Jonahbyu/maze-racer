# The player's avatar: a glowing ring with an arrow inside it.
#
# Third-person needs an unambiguous read on two things at a glance -- where the
# player IS and which way they FACE -- at speeds where there is no time to
# study the screen. The ring answers position and wall clearance; the arrow
# answers facing. Neither alone is enough: a bare arrow is hard to locate
# against a neon maze, and a bare ring says nothing about direction.
#
# Both are unshaded and emissive so they stay legible against any wall, and
# they sit low to the floor so they never occlude the corridor ahead.
class_name PlayerMarker
extends Node3D

# NEAR-WHITE, deliberately, and it must stay that way.
#
# The marker used to be green. That was fine while every maze was cyan, then
# maze 3's palette turned the walls green too and the one thing the player
# steers with went the same hue as the scenery it has to be picked out from.
#
# White is the only colour that cannot collide with a palette, because the
# palettes are all saturated hues and white is none of them. Any future maze
# colourway is safe against it. The marker still turns amber while scraping and
# red on a crash -- those are STATE, and they read as state precisely because
# the resting colour carries no hue of its own.
const COL_RING := Color(0.92, 0.98, 1.0)
const COL_ARROW := Color(1.0, 1.0, 1.0)
const COL_CRASH := Color(1.0, 0.25, 0.20)
const COL_SCRAPE := Color(1.0, 0.72, 0.15)

var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _ring_material: StandardMaterial3D
var _arrow_material: StandardMaterial3D

# Bobs gently so the marker reads as alive rather than pasted on the floor.
var _bob := 0.0


func _ready() -> void:
	_build_ring()
	_build_arrow()


# A flat annulus on the floor. Drawn as a triangle strip between an inner and
# outer radius rather than a torus: a torus reads as a doughnut in perspective,
# where a flat band reads cleanly as a footprint.
func _build_ring() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 48
	var outer := Tuning.MARKER_RADIUS
	# A wide band, not a hairline. Seen from a trailing camera at a shallow
	# angle the ring foreshortens hard, and a thin one disappears entirely.
	var inner := Tuning.MARKER_RADIUS * 0.60

	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)

		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)

		# Wound so the visible side faces up.
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(o0)

		st.add_vertex(i0)
		st.add_vertex(i1)
		st.add_vertex(o1)

	st.generate_normals()

	_ring_material = _make_material(COL_RING, 2.4)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = st.commit()
	_ring.material_override = _ring_material
	_ring.position.y = 0.04
	add_child(_ring)


# A solid chevron pointing along -Z, which is the marker's forward axis. Built
# as a low prism so it catches the eye from the trailing camera without being
# tall enough to hide the corridor.
func _build_arrow() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sized to sit INSIDE the ring with clearance, so both shapes stay readable
	# as separate marks rather than merging into one blob.
	var r := Tuning.MARKER_RADIUS * 0.46
	var h := Tuning.MARKER_HEIGHT

	# Ground outline: a tip ahead, two barbs behind, and a notched tail so the
	# shape reads as an arrow rather than a triangle at a glance.
	var tip := Vector3(0.0, 0.0, -r * 1.15)
	var left := Vector3(-r * 0.85, 0.0, r * 0.75)
	var right := Vector3(r * 0.85, 0.0, r * 0.75)
	var tail := Vector3(0.0, 0.0, r * 0.32)

	var top := Vector3(0.0, h, 0.0)

	# Top faces, drawn from an apex so the arrow has a raised spine.
	var apex := Vector3(0.0, h, -r * 0.15)
	_tri(st, tip, left, apex)
	_tri(st, left, tail, apex)
	_tri(st, tail, right, apex)
	_tri(st, right, tip, apex)

	# Underside, wound the other way so it is visible from below.
	_tri(st, left, tip, tail)
	_tri(st, tip, right, tail)

	st.generate_normals()

	_arrow_material = _make_material(COL_ARROW, 3.0)

	_arrow = MeshInstance3D.new()
	_arrow.name = "Arrow"
	_arrow.mesh = st.commit()
	_arrow.material_override = _arrow_material
	_arrow.position.y = 0.06
	add_child(_arrow)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _make_material(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Never hidden by the floor or a wall it is standing against -- losing track
	# of your own marker at speed is far worse than a little clipping.
	mat.no_depth_test = false
	return mat


# Drives colour from racer state, so the marker itself reports danger. This is
# the same information the barrier bar carries, but placed where the player is
# already looking.
func update_state(racer: Racer, delta: float) -> void:
	_bob = fmod(_bob + delta * 3.0, TAU)
	if _arrow:
		_arrow.position.y = 0.06 + sin(_bob) * 0.04

	if _ring_material == null:
		return

	var colour := COL_RING
	if racer.state == Racer.State.PARKED:
		colour = COL_CRASH
	elif racer.scraping:
		# Warms toward red as the barrier drains, so the marker shows how close
		# the scrape is to becoming a crash.
		colour = COL_SCRAPE.lerp(COL_CRASH, 1.0 - racer.barrier_fraction())

	_ring_material.albedo_color = colour
	_ring_material.emission = colour
