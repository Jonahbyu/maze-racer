# The player's avatar: a glowing ring with a pointing mark inside it.
#
# Third-person needs an unambiguous read on two things at a glance -- where the
# player IS and which way they FACE -- at speeds where there is no time to
# study the screen. The ring answers position and wall clearance; the inner mark
# answers facing. Neither alone is enough: a bare mark is hard to locate
# against a neon maze, and a bare ring says nothing about direction.
#
# The inner mark is the player's pick, from Tuning.MARKER_SHAPES. Only its
# OUTLINE varies -- the ring, the colour and the height do not. That split is
# the whole design: every rule this file records is about colour and visibility,
# and shape is the one axis that leaves all of them intact. Which is also why
# every shape in the table must point: the ring already says "here", so a
# symmetric mark would leave nothing saying "this way".
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

# The inlay's emission, well under the mark's 3.0.
#
# The mark is SHADING_MODE_UNSHADED, so what renders is albedo + emission x
# energy and anything at the mark's own energy saturates to white -- which is
# exactly why a decal drawn ON the mark was invisible and had to become a hole.
# A fill has to sit under that ceiling to read as a second colour rather than as
# more of the first.
const INLAY_ENERGY := 1.5

# How far the inlay sits below the mark's top face, and how far its edge is
# inset from the cut.
#
# Both leave a DARK SEAM around every inlay piece. The seam is what makes the
# pattern legible at any pair of colours -- without it, two bright choices merge
# into one shape and the decal disappears for the same reason the original patch
# did. Cheaper and more reliable than trying to guarantee contrast between two
# colours the player picked independently.
const INLAY_DROP := 0.012
const INLAY_INSET := 0.008

# Which shape the inner mark is drawn as, by Tuning.MARKER_SHAPES id.
#
# Empty means "ask Settings" -- which is what the game does. It is settable so
# that a preview or a harness can build a specific shape without touching the
# player's saved preference: a tool must not write the state it is inspecting
# (CLAUDE.md section 12, TouchShot).
#
# Read ONLY here. Nothing in the simulation may read it: movement, turn
# resolution, the buffer, the barrier and the penalties behave identically
# whichever shape is drawn.
var shape_id := ""

# Which decal patterns the inner mark, by Tuning.MARKER_DECALS id. Same
# treatment as shape_id: empty means "ask Settings", settable so a preview or a
# harness can build one without writing the player's saved choice, and read
# ONLY here.
var decal_id := ""

# The player's chosen colour, applied to the INNER MARK only.
#
# The ring is deliberately excluded, and that split is what makes a free colour
# picker safe. The ring is the STATE channel (see update_state): it carries
# scrape-amber and crash-red, which section 5.1 calls the most important read on
# screen. A player-coloured ring would put that read on a surface the player can
# set to any colour they like -- including the state colours themselves.
#
# CLAUDE.md section 12 refused a colour picker outright on this reasoning. The
# picker was asked for anyway, after the objection was put, so what changed is
# the answer and not the argument: state OVERRIDES this on both surfaces, which
# makes the read a TRANSITION rather than a hue. A player who picks crash red
# still sees their marker change on a scrape.
#
# Near-white by default, which is what every marker was before the choice
# existed.
var player_colour := COL_ARROW

# The SECOND colour: what fills the decal's cuts.
#
# The decal used to be a bare hole showing the floor, which is why it could not
# be washed out by the mark's saturation. Filling it puts that problem back --
# an inlay at the mark's own emission would blow out to the same white -- so the
# inlay is drawn DIMMER (INLAY_ENERGY) and the cut is kept slightly wider than
# the fill, leaving a dark seam between the two. The seam is what guarantees the
# pattern reads at any pair of colours, including two bright ones.
#
# Ignored while the plain decal is selected, since there is nothing to fill.
var player_colour_2 := Color(0.25, 0.55, 1.0)

var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _ring_material: StandardMaterial3D
var _arrow_material: StandardMaterial3D
var _inlay: MeshInstance3D
var _inlay_material: StandardMaterial3D

# Bobs gently so the marker reads as alive rather than pasted on the floor.
var _bob := 0.0


func _ready() -> void:
	_resolve_colour()
	_build_ring()
	_build_shape()


# Take the saved colour, unless one was set explicitly before entry to the tree.
#
# Guarded rather than assumed: Settings is absent in every harness that
# instantiates Game.tscn bare, and a missing preference must never be what stops
# the game starting -- the same treatment the shape and the decal get.
#
# An explicit assignment WINS, so a preview or a shot can build a specific
# colour without writing the player's saved choice. A tool must not write the
# state it is inspecting (section 12, TouchShot).
func _resolve_colour() -> void:
	if not player_colour.is_equal_approx(COL_ARROW):
		return
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		player_colour = settings.marker_colour
		player_colour_2 = settings.marker_colour_2


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


# A solid mark pointing along -Z, which is the marker's forward axis. Built as a
# low prism so it catches the eye from the trailing camera without being tall
# enough to hide the corridor.
#
# The OUTLINE comes from Tuning.MARKER_SHAPES, so which mark is drawn is the
# player's pick (CLAUDE.md, "The marker's shape is the player's to pick"). Only
# the outline varies: every shape is built by this one function, in the same
# near-white, at the same height, inside the same ring. A second builder per
# shape would be a second copy of the extrusion to keep in step -- the
# parallel-array trap in different clothes.
func _build_shape() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sized to sit INSIDE the ring with clearance, so both marks stay readable
	# as separate shapes rather than merging into one blob.
	var r := Tuning.MARKER_RADIUS * 0.46
	var h := Tuning.MARKER_HEIGHT

	var outline: Array = _shape_outline()

	# TRIANGULATED, not fanned from an apex. A fan fills any concave outline --
	# it draws a triangle from the centre to every edge, so a notch is covered
	# over rather than left open. That is not a cosmetic loss: the chevron IS
	# its notch, and fanned it rendered as a plain solid triangle identical to
	# the delta. Only a rendered frame showed it; every headless assertion about
	# the outline passed, because the OUTLINE was correct and the mesh built
	# from it was not.
	var flat := PackedVector2Array()
	for v in outline:
		flat.append(Vector2(v.x * r, v.y * r))

	# The decal is CUT OUT of the mark, not drawn on top of it.
	#
	# Drawing a patch over the mark cannot work, and the reason is the material
	# rather than the geometry: this surface is SHADING_MODE_UNSHADED with an
	# emission energy of 3.0, so what renders is albedo + emission x energy and
	# the mark SATURATES TO WHITE. A patch on it is invisible at every colour,
	# every height and every energy -- measured in a real-game frame, where the
	# marker is a flat white silhouette with even its own ring lost.
	#
	# Five fixes were spent on that surface before the frame was read: raising
	# the lift, lowering the energy, clearing the mark's volume, reparenting the
	# node, and finally a bright red plane floating half a unit above it, which
	# also did not appear. That last one is what proved the problem was never a
	# property of the decal.
	#
	# A HOLE cannot be washed out. The dark corridor floor shows through it, so
	# the pattern reads as dark bands however bright the mark becomes -- and it
	# holds at every state colour for free, since the gap has no colour of its
	# own to keep in step.
	var pieces := _cut_decal(flat)
	# Every piece is extruded into ONE surface.
	#
	# The mark is a single loop UNTIL a decal is cut from it: a stripe severs it
	# into bands and an inset rim leaves a ring plus its hole, so both return
	# more than one polygon (measured: 2 pieces on every shape in the table).
	# Extruding only the first would draw a marker missing most of itself.
	#
	# Depth is measured across the WHOLE mark rather than per piece, so the
	# pieces keep one shared slope and still read as one object cut apart -- per
	# piece, each band would rise to full height on its own and the shape would
	# read as a staircase.
	var min_z := INF
	var max_z := -INF
	for piece in pieces:
		for v in piece:
			min_z = minf(min_z, v.y)
			max_z = maxf(max_z, v.y)
	var span: float = maxf(max_z - min_z, 0.0001)

	for piece in pieces:
		_extrude(st, piece, min_z, span, h)

	st.generate_normals()

	# Built in the PLAYER'S colour rather than the constant. update_state
	# overwrites this every frame in play, but a marker built for a preview
	# or a shot is never stepped -- so building white here would make every
	# still frame of a coloured marker come out white.
	_arrow_material = _make_material(player_colour, 3.0)

	_arrow = MeshInstance3D.new()
	# Named "Arrow" whatever shape is drawn. The name is what the scene and its
	# assertions address this node by, and renaming it per shape would make the
	# lookup depend on a cosmetic preference.
	_arrow.name = "Arrow"
	_arrow.mesh = st.commit()
	_arrow.material_override = _arrow_material
	_arrow.position.y = 0.06
	add_child(_arrow)

	_build_inlay(flat, min_z, span, h)


# The decal's cuts, filled in the SECOND colour.
#
# Built from the same cutters _cut_decal subtracts, intersected with the outline
# instead -- so the fill is exactly the shape of the hole by construction, and
# the two can never disagree about where the pattern is.
#
# Inset and dropped, leaving a dark seam around every piece. The seam is not
# decoration: the mark is unshaded and saturates, so two bright colours meeting
# edge to edge merge into one shape and the pattern vanishes -- the failure that
# forced the decal to become a hole in the first place. A seam guarantees the
# read at any pair of colours the player picks, which no contrast rule between
# two independent choices can.
func _build_inlay(flat: PackedVector2Array, min_z: float, span: float,
		h: float) -> void:
	var id := _decal_id()
	if id == Tuning.MARKER_DECAL_DEFAULT:
		return

	var outline: Array = []
	for v in flat:
		outline.append(v)
	var cuts: Array = Tuning.decal_polygons(id, outline)
	if cuts.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0

	for cut in cuts:
		# The part of the cutter that actually lies INSIDE the mark. A cutter
		# spans the shape (it has to, to cut through it), so using it raw would
		# draw a bar sticking out both sides.
		for piece in Geometry2D.intersect_polygons(PackedVector2Array(cut),
				flat):
			if piece.size() < 3:
				continue
			# Shrunk, to leave the seam. A piece too thin to survive the inset
			# is dropped rather than drawn as a sliver.
			for inner in Geometry2D.offset_polygon(piece, -INLAY_INSET):
				if inner.size() < 3:
					continue
				_extrude(st, inner, min_z, span, h - INLAY_DROP)
				emitted += 1

	if emitted == 0:
		return

	st.generate_normals()
	_inlay_material = _make_material(player_colour_2, INLAY_ENERGY)

	_inlay = MeshInstance3D.new()
	_arrow.add_child(_inlay)
	# Named AFTER add_child: a name set before entry to the tree is overwritten
	# by a generated one (section 12, the gate markers).
	_inlay.name = "Inlay"
	_inlay.mesh = st.commit()
	_inlay.material_override = _inlay_material




# Extrude one closed loop into a solid: sloped top, flat base, and a rim joining
# them.
#
# Split out of _build_shape so a decal that cuts the mark into several pieces
# can extrude each one. It was inline while the mark was always a single loop.
func _extrude(st: SurfaceTool, loop: PackedVector2Array, min_z: float,
		span: float, h: float) -> void:
	if loop.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(loop)

	# A degenerate loop triangulates to nothing. Falling back to a fan keeps a
	# marker on screen -- losing track of your own marker is the one failure
	# this whole file exists to prevent, so a piece that cannot be triangulated
	# must still draw something.
	#
	# A fan FILLS a concave loop, which is wrong for a chevron and is why the
	# mark is triangulated properly in the first place (section 12). It is
	# acceptable only here, as the alternative to drawing nothing at all.
	if indices.is_empty():
		for k in loop.size():
			indices.append_array([k, (k + 1) % loop.size(), 0])

	# Top face.
	var i := 0
	while i < indices.size():
		var a: Vector2 = loop[indices[i]]
		var b: Vector2 = loop[indices[i + 1]]
		var c: Vector2 = loop[indices[i + 2]]
		# Reversed against the triangulator's own order. Geometry2D winds in
		# 2D screen convention, which maps to INWARD once y becomes +Z with +Y
		# up -- the same sign flip the landmark drums hit (section 12). Asserted
		# by signed volume rather than trusted, because an unshaded material
		# looks identical either way.
		_tri(st, _lift(c, min_z, span, h), _lift(b, min_z, span, h),
			_lift(a, min_z, span, h))
		i += 3

	# Flat underside, wound the other way so it is visible from below. The
	# marker sits a few centimetres off the floor and the camera dips toward it
	# through a corner, so an open bottom shows as a hole in the mark.
	i = 0
	while i < indices.size():
		var a2: Vector2 = loop[indices[i]]
		var b2: Vector2 = loop[indices[i + 1]]
		var c2: Vector2 = loop[indices[i + 2]]
		_tri(st, Vector3(a2.x, 0.0, a2.y), Vector3(b2.x, 0.0, b2.y),
			Vector3(c2.x, 0.0, c2.y))
		i += 3

	# The rim, joining the lifted top to the flat base around the whole outline.
	# Without it the two faces float apart at every edge and the mark reads as
	# two stacked cut-outs rather than one solid object.
	for j in loop.size():
		var p0: Vector2 = loop[j]
		var p1: Vector2 = loop[(j + 1) % loop.size()]
		var t0 := _lift(p0, min_z, span, h)
		var t1 := _lift(p1, min_z, span, h)
		var b0 := Vector3(p0.x, 0.0, p0.y)
		var b1 := Vector3(p1.x, 0.0, p1.y)
		_tri(st, b0, t0, t1)
		_tri(st, b0, t1, b1)


# The chosen decal's id.
#
# Settings is absent in every harness that instantiates Game.tscn bare, so the
# lookup is guarded rather than assumed -- the same treatment _shape_outline
# gives, and for the same reason: a missing preference must never be what stops
# the game starting.
func _decal_id() -> String:
	var id := decal_id
	if id == "":
		var settings := get_node_or_null("/root/Settings")
		if settings != null:
			id = String(settings.marker_decal)
	return String(Tuning.marker_decal(id)["id"])


# The mark's outline with the chosen decal subtracted, as one or more pieces.
#
# Returns the ORIGINAL outline as a single piece when the cut would leave
# nothing usable. Losing the pattern is cosmetic; losing the mark is the failure
# this whole file exists to prevent, so anything ambiguous falls back to the
# plain shape rather than risking a marker with holes where its body should be.
#
# Godot returns a HOLE as a clockwise-wound polygon from clip_polygons. Those
# are dropped rather than modelled: the extrusion builds a solid per loop, so a
# hole extruded as a solid would fill the gap it is supposed to be. Dropping it
# leaves the outer ring, which is exactly what an inset rim should look like.
func _cut_decal(flat: PackedVector2Array) -> Array:
	var id := _decal_id()
	if id == Tuning.MARKER_DECAL_DEFAULT:
		return [flat]

	var outline_array: Array = []
	for v in flat:
		outline_array.append(v)
	var cuts: Array = Tuning.decal_polygons(id, outline_array)
	if cuts.is_empty():
		return [flat]

	var result: Array = [flat]
	for cut in cuts:
		var next: Array = []
		for loop in result:
			for piece in Geometry2D.clip_polygons(loop,
					PackedVector2Array(cut)):
				if piece.size() < 3:
					continue
				# Clockwise is a hole -- see above.
				if Geometry2D.is_polygon_clockwise(piece):
					continue
				next.append(piece)
		if next.is_empty():
			# The cut removed everything. Keep the plain mark.
			return [flat]
		result = next

	return result


# The outline for the shape this marker was built with.
#
# Settings is absent in every harness that instantiates Game.tscn bare, so the
# lookup is guarded rather than assumed -- a missing preference must never be
# what stops the game starting. Same separation landmarks, music and touch
# controls have.
func _shape_outline() -> Array:
	var id := shape_id
	if id == "":
		var settings := get_node_or_null("/root/Settings")
		if settings != null:
			id = String(settings.marker_shape)
	return Tuning.marker_shape(id)["outline"]


# A footprint vertex raised by how far FORWARD it sits: the tip is at full
# height, the trailing edge on the floor. This is what gives every shape a
# raised spine without needing a per-shape apex, and it is why a shape reads as
# pointing from above as well as in outline.
func _lift(v: Vector2, min_z: float, span: float, h: float) -> Vector3:
	var forward: float = 1.0 - (v.y - min_z) / span
	return Vector3(v.x, h * forward, v.y)


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

	# STATE OVERRIDES THE PLAYER'S COLOUR, on both surfaces.
	#
	# That is what makes the free colour picker safe: the read is a TRANSITION
	# rather than a hue, so a player who picked crash red still sees their
	# marker change on a scrape. Leaving the resting colour showing through is
	# what section 12 refused a colour picker over.
	#
	# Writing the MARK as well as the ring also fixes the defect section 12
	# records: update_state used to recolour only the ring, so a scrape left the
	# inner mark pure white and a frame with the barrier visibly half-drained
	# was pixel-identical to a clean one -- on the larger of the two surfaces,
	# and the one the trailing camera actually sees.
	var ring_colour := COL_RING
	var mark_colour := player_colour
	if racer.state == Racer.State.PARKED:
		ring_colour = COL_CRASH
		mark_colour = COL_CRASH
	elif racer.scraping:
		# Warms toward red as the barrier drains, so the marker shows how close
		# the scrape is to becoming a crash.
		var warm := COL_SCRAPE.lerp(COL_CRASH, 1.0 - racer.barrier_fraction())
		ring_colour = warm
		mark_colour = warm

	_ring_material.albedo_color = ring_colour
	_ring_material.emission = ring_colour
	if _arrow_material != null:
		_arrow_material.albedo_color = mark_colour
		_arrow_material.emission = mark_colour
	# The INLAY follows the state too. It is a real surface now rather than a
	# hole, so leaving it alone would keep the pattern in its resting colour on a
	# marker that has gone crash-red -- reading as a stuck patch rather than as
	# one object changing state. It keeps its own dimmer energy, so the seam
	# survives.
	if _inlay_material != null:
		var inlay_colour := player_colour_2
		if racer.state == Racer.State.PARKED or racer.scraping:
			# Deliberately DARKER than the mark rather than the same: two
			# surfaces at one colour merge, and the shape would lose its pattern
			# exactly when the player most needs to recognise their own marker.
			inlay_colour = mark_colour.darkened(0.45)
		_inlay_material.albedo_color = inlay_colour
		_inlay_material.emission = inlay_colour
