# Builds the 3D geometry for a maze.
#
# A 90x90 maze is 8100 cells and up to ~16000 wall quads. That is far too many
# to make individual nodes out of, so every wall goes into ONE surface built with
# SurfaceTool, plus one floor and one grid-line overlay. Three draw calls for the
# whole maze.
#
# The grid lines are not decoration: they are the timing contract the whole
# control scheme rests on (CLAUDE.md section 11.3). They get their own emissive
# overlay so they stay readable at speed.
class_name MazeMesh
extends Node3D

# The live colourway, swapped per maze from Tuning.PALETTES so arriving in a new
# maze reads as arriving somewhere. Defaults to maze 1's so a mesh built without
# an explicit palette -- SceneTest does this -- still looks right.
#
# Gate and exit stay FIXED across every palette: they are navigation, not
# decoration, and a gate has to be identifiable as a gate on sight rather than
# re-learned once per maze.
var _palette: Dictionary = Tuning.PALETTES[0]

var _maze: Maze

# Collected while emitting wall quads, consumed by _build_wall_tops().
var _wall_edges: Array = []


func build(maze: Maze, palette_index: int = 0) -> void:
	_maze = maze
	_palette = Tuning.PALETTES[clampi(palette_index, 0, Tuning.PALETTES.size() - 1)]
	_wall_edges.clear()

	# Detached IMMEDIATELY, not merely queued. queue_free is DEFERRED to the end
	# of the frame, so without the remove_child the outgoing maze's markers are
	# still in the tree -- still holding "Gate0", "Gate1"... -- while the new
	# ones are added below, and Godot renames the NEW node to break the
	# collision. `clear_gate` finds its marker by name, so a renamed marker is
	# an unreachable one.
	#
	# Detaching first frees the name before it is reused. Cheap, and it removes
	# a whole class of order-dependence between a maze teardown and the build
	# that immediately follows it.
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_build_floor()
	_build_walls()
	_build_grid_lines()
	_build_landmarks()
	_build_gates()
	_build_exit()


# --- Floor -------------------------------------------------------------------

func _build_floor() -> void:
	var size_x := _maze.width * Tuning.CELL_SIZE
	var size_z := _maze.height * Tuning.CELL_SIZE

	var plane := PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _palette["floor"]
	mat.roughness = 0.65
	mat.metallic = 0.1
	plane.material = mat

	var instance := MeshInstance3D.new()
	instance.mesh = plane
	# PlaneMesh is centred on its origin; cell centres run from 0 to (n-1)*size,
	# so the centre of the grid sits half a cell short of half the full extent.
	instance.position = Vector3(
		size_x * 0.5 - Tuning.CELL_SIZE * 0.5,
		0.0,
		size_z * 0.5 - Tuning.CELL_SIZE * 0.5
	)
	add_child(instance)


# --- Walls -------------------------------------------------------------------

func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := Tuning.CELL_SIZE * 0.5

	for y in _maze.height:
		for x in _maze.width:
			var cell := Vector2i(x, y)
			var cx := x * Tuning.CELL_SIZE
			var cz := y * Tuning.CELL_SIZE

			# Only emit the north and west faces of each cell, plus the outer
			# south/east boundary. Emitting all four would double every interior
			# wall into coincident quads that z-fight.
			if _maze._has_wall(cell, Maze.N):
				_add_wall_quad(st,
					Vector3(cx - half, 0, cz - half),
					Vector3(cx + half, 0, cz - half))
			if _maze._has_wall(cell, Maze.W):
				_add_wall_quad(st,
					Vector3(cx - half, 0, cz + half),
					Vector3(cx - half, 0, cz - half))
			if x == _maze.width - 1 and _maze._has_wall(cell, Maze.E):
				_add_wall_quad(st,
					Vector3(cx + half, 0, cz - half),
					Vector3(cx + half, 0, cz + half))
			if y == _maze.height - 1 and _maze._has_wall(cell, Maze.S):
				_add_wall_quad(st,
					Vector3(cx + half, 0, cz + half),
					Vector3(cx - half, 0, cz + half))

	st.generate_normals()

	# Wall faces sit in a narrow band between two failure modes, and both have
	# been hit:
	#
	#   too bright -> every wall washes out to flat cyan and all depth reading
	#                 dies, because the neon must come from the EDGES (wall-top
	#                 caps, the floor band at the wall base, and the grid),
	#                 never the faces
	#   too dark   -> with correct outward normals the corridor-facing sides
	#                 point away from the directional light and get ambient only,
	#                 so the maze becomes neon lines floating in a void
	#
	# A low albedo plus a trace of emission keeps the surfaces present without
	# competing with the edges. The headlight in Game.gd does the rest.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _palette["wall_albedo"]
	mat.emission_enabled = true
	mat.emission = _palette["wall_emission"]
	mat.emission_energy_multiplier = 0.40
	mat.roughness = 0.85
	mat.metallic = 0.0
	# Walls are single quads with no thickness, so each one is shared by the two
	# cells either side of it and must render from BOTH. Culling backfaces here
	# makes every wall invisible from one of the two corridors it bounds.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = mat
	add_child(instance)

	_build_wall_tops()


# A flat wall plane running from `a` to `b` along the ground, rising to
# WALL_HEIGHT.
#
# ZERO THICKNESS, deliberately. These were solid boxes, on the reasoning that a
# flat wall shows nothing edge-on so corridor mouths read as slits cut in paper.
# In practice the opposite was true: at 0.5-0.7m the slab's side faces and end
# caps were plainly visible as you passed an opening, every junction showed the
# wall's depth, and the maze read as a set of 3D blocks rather than a clean
# lightcycle grid. Thickness also created the artifacts it took three passes to
# kill -- the doubled-looking walls and the banded end caps both came from
# having a slab to decorate.
#
# Opacity does NOT come from thickness, it comes from the material: the wall
# surface is fully opaque either way. What thickness bought was a visible side
# face, and that was the thing that looked wrong.
func _add_wall_quad(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var h := Vector3(0, Tuning.WALL_HEIGHT, 0)

	# One quad. Both faces are drawn because the material is CULL_DISABLED --
	# with no thickness there is no "outside" to cull toward, and a plane culled
	# to one side would vanish when seen from the other corridor.
	_add_quad(st, a, b, b + h, a + h)

	_wall_edges.append([a, b])


# Emits the quad p1-p2-p3-p4 as two triangles.
#
# Winding no longer decides visibility: the wall material is CULL_DISABLED
# because a zero-thickness wall is shared by the corridors on both sides and has
# to draw from either. It still sets the normal direction, which is what the
# lighting reads, so the order is kept consistent.
func _add_quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> void:
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p3)

	st.add_vertex(p1)
	st.add_vertex(p3)
	st.add_vertex(p4)


# The neon: a cap along the top of every wall, and a band on the floor at its
# base. Both are EDGES -- a glowing line where two surfaces meet reads as depth,
# where an emissive wall face just becomes a flat colour field.
func _build_wall_tops() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# The neon lives on ONE surface per wall side: a band lying flat on the
	# FLOOR, tight against the base of the wall, plus the cap along the top.
	#
	# The band used to be a vertical strip on the wall face, and that is what
	# produced both artifacts at once:
	#
	#   - Pushed 0.06 OUTSIDE the face it floated in open air, drove through
	#     perpendicular walls at every corner, and hung in space beyond them.
	#   - Pulled 0.06 INSIDE the face it was buried in solid geometry and only
	#     rendered by winning a depth fight it should lose -- which is the
	#     ribbed "panel" striping that showed up on every wall end.
	#
	# There is no offset that works, because a coplanar decal on a thick slab is
	# the wrong construction. A floor band has neither problem: it sits on the
	# floor plane, well clear of every wall surface in depth, and it is bounded
	# by the corridor rather than the slab. It also reads BETTER at speed -- it
	# runs alongside the grid lines the player is already tracking (section
	# 11.3) rather than competing with them from up on the wall.
	# The cap is a separate quad floating over the slab's own top face, so the
	# two are parallel and close -- the classic z-fight setup. At 0.05 they
	# still interleaved at grazing angles and every distant wall top grew a
	# sawtooth fringe. 0.16 is far enough to resolve cleanly at the far end of a
	# 90-cell maze and still reads as sitting ON the wall.
	var top := Vector3(0, Tuning.WALL_HEIGHT + 0.16, 0)
	# Walls have no thickness now, so the cap needs its own width or it would be
	# a zero-area strip. This is the one place a wall gets visible breadth, and
	# it reads as a glowing rail along the top edge rather than as slab depth.
	var half_t := 0.07

	# Well above the floor strips (y = 0.02) so the two never fight for depth.
	var floor_y := 0.05
	# How far the glow reaches out from the wall base into the corridor.
	var band_width := 0.30

	for edge in _wall_edges:
		var base_a: Vector3 = edge[0]
		var base_b: Vector3 = edge[1]

		var a: Vector3 = base_a + top
		var b: Vector3 = base_b + top
		var along := (b - a).normalized()
		var side := Vector3(-along.z, 0.0, along.x) * half_t

		# Cap along the top of the slab, flush with its sides.
		st.add_vertex(a - side)
		st.add_vertex(b - side)
		st.add_vertex(b + side)

		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(a + side)

		# A floor band on each side, running from the wall outward. It starts a
		# few centimetres clear of the wall plane rather than exactly on it, so
		# the band and the wall's own base never fight for depth.
		var unit := side.normalized()
		var inner := unit * 0.03
		var outer := unit * (0.03 + band_width)
		var lift := Vector3(0, floor_y, 0)

		for sign in [1.0, -1.0]:
			var i0: Vector3 = base_a + inner * sign + lift
			var i1: Vector3 = base_b + inner * sign + lift
			var o0: Vector3 = base_a + outer * sign + lift
			var o1: Vector3 = base_b + outer * sign + lift

			st.add_vertex(i0)
			st.add_vertex(i1)
			st.add_vertex(o1)

			st.add_vertex(i0)
			st.add_vertex(o1)
			st.add_vertex(o0)

	st.generate_normals()

	# Unshaded and double-sided: the caps are flat horizontal strips at wall
	# height, and the camera eye sits below them, so a single-sided cap would be
	# backface-culled and invisible from inside the corridor -- exactly where it
	# needs to be seen.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _palette["wall"]
	mat.emission_enabled = true
	mat.emission = _palette["wall"]
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = mat
	add_child(instance)

	_wall_edges.clear()


# --- Grid lines --------------------------------------------------------------

# The timing reference. Every cell boundary gets a bright line on the floor so
# the player can see exactly when they cross into a new cell -- which is what
# makes a 0.2-cell buffer fair rather than cruel.
func _build_grid_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := Tuning.CELL_SIZE * 0.5
	var line_half := 0.06
	var y := 0.02   # just above the floor, to avoid z-fighting

	for i in range(_maze.width + 1):
		var x := i * Tuning.CELL_SIZE - half
		_add_floor_strip(st,
			Vector3(x - line_half, y, -half),
			Vector3(x + line_half, y, _maze.height * Tuning.CELL_SIZE - half))

	for i in range(_maze.height + 1):
		var z := i * Tuning.CELL_SIZE - half
		_add_floor_strip(st,
			Vector3(-half, y, z - line_half),
			Vector3(_maze.width * Tuning.CELL_SIZE - half, y, z + line_half))

	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _palette["grid"]
	mat.emission_enabled = true
	mat.emission = _palette["grid"]
	mat.emission_energy_multiplier = 1.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = mat
	add_child(instance)

	_build_lane_lines()


# The lane sub-grid: LANE_COUNT lines per cell in each axis, matching the
# lateral positions the marker can occupy (Tuning, "Lanes").
#
# A SEPARATE, dimmer, thinner surface rather than more lines in the grid above,
# and that separation is the whole point. The cell-boundary lines are the timing
# contract -- the player reads them to know when a turn resolves (CLAUDE.md
# section 11.3) -- so they must stay the dominant marking on the floor. Drawing
# lane lines at the same weight would give five equally-loud lines per cell and
# destroy the one reference the control scheme depends on.
func _build_lane_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := Tuning.CELL_SIZE * 0.5
	# Much thinner than the cell lines (0.06) so it reads as a subdivision.
	var line_half := 0.012
	# Just under the cell lines, so where the two coincide the boundary wins.
	var y := 0.018
	var step := Tuning.CELL_SIZE / float(Tuning.LANE_COUNT)

	for i in range(_maze.width * Tuning.LANE_COUNT + 1):
		# Skip positions that land on a cell boundary -- the bright line is
		# already there and a dim one under it would only z-fight.
		if i % Tuning.LANE_COUNT == 0:
			continue
		var x := i * step - half
		_add_floor_strip(st,
			Vector3(x - line_half, y, -half),
			Vector3(x + line_half, y, _maze.height * Tuning.CELL_SIZE - half))

	for i in range(_maze.height * Tuning.LANE_COUNT + 1):
		if i % Tuning.LANE_COUNT == 0:
			continue
		var z := i * step - half
		_add_floor_strip(st,
			Vector3(-half, y, z - line_half),
			Vector3(_maze.width * Tuning.CELL_SIZE - half, y, z + line_half))

	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _palette["grid"]
	mat.emission_enabled = true
	mat.emission = _palette["grid"]
	# A small fraction of the cell lines' energy, and dimmed in albedo too.
	#
	# Tuned DOWN hard from 0.30: at that strength the sub-grid read as loud as
	# the cell boundaries and the floor became an undifferentiated graph-paper
	# mesh, which is precisely the failure this surface was split out to avoid.
	# The lane lines are texture and a speed cue; the boundary is the contract.
	mat.albedo_color = (_palette["grid"] * 0.5)
	mat.emission = (_palette["grid"] * 0.5)
	mat.emission_energy_multiplier = 0.10
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = mat
	add_child(instance)


func _add_floor_strip(st: SurfaceTool, from: Vector3, to: Vector3) -> void:
	var a := Vector3(from.x, from.y, from.z)
	var b := Vector3(to.x, from.y, from.z)
	var c := Vector3(to.x, from.y, to.z)
	var d := Vector3(from.x, from.y, to.z)

	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


# --- Gates and exit ----------------------------------------------------------

func _build_gates() -> void:
	for i in _maze.gates.size():
		var gate: Vector2i = _maze.gates[i]
		var marker := _make_marker(gate, Tuning.NEON_GATE, Tuning.GATE_MARKER_HEIGHT)
		# Named AFTER add_child, never before. Godot assigns a generated name on
		# entry to the tree, so a name set beforehand is overwritten -- the trap
		# CLAUDE.md section 12 already records for the Music autoload, arriving
		# here through the marker that clear_gate then has to look up by name.
		#
		# It also has to happen after the previous maze's markers are detached,
		# or the assignment collides with a node that is queued for deletion but
		# still in the tree, and Godot renames THIS node to resolve it. Measured
		# directly: adding a second "Gate0" beside a queue_freed one yields a
		# node called "Gate1", and get_node("Gate0") returns the dying original.
		add_child(marker)
		marker.name = "Gate%d" % i


func _build_exit() -> void:
	var marker := _make_marker(_maze.exit_cell, Tuning.NEON_EXIT, Tuning.EXIT_MARKER_HEIGHT)
	# After add_child, for the reason given in _build_gates.
	add_child(marker)
	marker.name = "Exit"


# A glowing pillar marking a cell. Deliberately tall: at speed the player needs
# to see a gate coming from several corridors away.
#
# TWO CROSSED SLABS, not one. A single flat slab is nearly invisible edge-on, so
# a gate approached down a perpendicular corridor showed as a thin vertical
# sliver -- which is exactly the approach a player most needs the warning on,
# since a gate straight ahead is already obvious. Crossing them means there is
# always a broad face turned toward the camera whatever direction it is seen
# from, at a cost of one extra quad-set per marker.
#
# The whole marker rises ABOVE the wall line (see GATE_MARKER_HEIGHT). The part
# below the walls is what the player drives through; the part above is the only
# part visible from anywhere else, so it has to be tall enough to clear and wide
# enough to read once it does.
func _make_marker(cell: Vector2i, colour: Color, height_scale: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	# Seen from both sides: the player passes THROUGH a gate, so the far face has
	# to draw on the way in and the near face on the way out.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var instance := MeshInstance3D.new()
	instance.mesh = _marker_mesh(height_scale, 0.0)
	instance.material_override = mat
	instance.position = Vector3(
		cell.x * Tuning.CELL_SIZE,
		0.0,
		cell.y * Tuning.CELL_SIZE
	)
	return instance


# The crossed-slab mesh, running from `base_scale` up to `height_scale` (both
# multiples of WALL_HEIGHT).
#
# The base is a parameter because a SPENT gate starts above the camera rather
# than on the floor (Tuning.GATE_SPENT_BASE) -- it keeps the part that clears
# the wall line and loses the part the eye would otherwise pass through.
func _marker_mesh(height_scale: float, base_scale: float) -> ArrayMesh:
	var top := Tuning.WALL_HEIGHT * height_scale
	var base := Tuning.WALL_HEIGHT * base_scale
	var wide := Tuning.CELL_SIZE * 0.75
	var thin := Tuning.CELL_SIZE * 0.14

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_marker_slab(st, Vector3(wide, top, thin), base)
	_add_marker_slab(st, Vector3(thin, top, wide), base)

	st.generate_normals()
	return st.commit()


# One box of the crossed pair, running from `base` up to `size.y`.
func _add_marker_slab(st: SurfaceTool, size: Vector3, base: float = 0.0) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var lo := Vector3(-hx, base, -hz)
	var hi := Vector3(hx, size.y, hz)

	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]

	# Outward-wound, same convention as the landmark boxes.
	_add_quad(st, p[7], p[6], p[5], p[4])
	_add_quad(st, p[0], p[1], p[2], p[3])
	_add_quad(st, p[0], p[4], p[5], p[1])
	_add_quad(st, p[2], p[6], p[7], p[3])
	_add_quad(st, p[3], p[7], p[4], p[0])
	_add_quad(st, p[1], p[5], p[6], p[2])


# Recolour a gate marker once its gate is taken, rather than removing it.
#
# It used to queue_free the node, and that was throwing away a landmark. The
# marker is tall enough to clear the wall line (Tuning.GATE_MARKER_HEIGHT), so
# it is visible from several corridors away -- which makes a spent gate the most
# recognisable object the maze has, and recognising re-crossed ground is the
# exact problem landmarks exist to solve in a looped maze (CLAUDE.md section 6).
# Deleting it meant a corridor the player had demonstrably driven looked like
# one they had never seen.
#
# It does NOT answer "which way", so it does not tread on the paid navigation
# lines: it marks somewhere the player has BEEN, which is knowledge they already
# had and merely could not see. That is the same line landmarks sit on.
#
# The mesh is left alone and only the material changes, so the marker keeps its
# silhouette -- a spent gate is still a gate, dimmed, rather than a different
# kind of object.
func clear_gate(index: int) -> void:
	# A negative index means the caller could not resolve the cell to a gate at
	# all. Nothing to recolour, and "Gate-1" would silently find no node anyway
	# -- returning here says so on purpose rather than by accident.
	if index < 0:
		return
	var node := get_node_or_null("Gate%d" % index)
	if node == null:
		return
	var instance := node as MeshInstance3D
	if instance == null:
		return

	# Duplicated because _make_marker builds one material per marker and this
	# must not reach through a shared resource into the gates still standing.
	var mat := instance.material_override.duplicate() as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = Tuning.NEON_GATE_SPENT
	mat.albedo_color.a = Tuning.GATE_SPENT_ALPHA
	mat.emission = Tuning.NEON_GATE_SPENT
	mat.emission_energy_multiplier = 2.0 * Tuning.GATE_SPENT_ENERGY
	instance.material_override = mat

	# And it is lifted clear of the camera. The marker is transparent and drawn
	# double-sided, so a marker still running to the floor puts the eye INSIDE
	# it every time the player re-crosses the cell -- washing the entire screen
	# its colour. A live gate does that too, but only in the instant of passing
	# through, and it is the thing being aimed at. A cleared one is just in the
	# way, and it stays in the way for the rest of the maze.
	instance.mesh = _marker_mesh(Tuning.GATE_MARKER_HEIGHT, Tuning.GATE_SPENT_BASE)


# --- Landmarks (docs/specs/landmarks.md) -------------------------------------

# Decorative structures that give a corridor an identity beyond "corridor".
#
# ONE MERGED SURFACE PER TYPE, not one node per landmark. A 90x90 maze can carry
# a few hundred of these, and the whole reason walls, grid lines and lane lines
# are built with SurfaceTool is that per-object nodes at that count are not
# affordable. Six types means at most six extra draw calls for the entire maze.
#
# They emit through material emission only, never as real lights. The corridor
# is lit by exactly one dim OmniLight3D headlight, kept dim on purpose because
# turning it up flattens the near wall into a colour field (CLAUDE.md section
# 12) -- scattering light sources through the maze would undo that tuning
# everywhere at once.
func _build_landmarks() -> void:
	if _maze.landmarks.is_empty():
		return

	# One SurfaceTool per type, since each type has its own colour and they
	# cannot share a material.
	var tools: Array[SurfaceTool] = []
	var used: Array[bool] = []
	for i in Tuning.LANDMARK_TYPES.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
		used.append(false)

	for landmark in _maze.landmarks:
		var type_index := int(landmark["type"])
		if type_index < 0 or type_index >= tools.size():
			continue

		var cell: Vector2i = landmark["cell"]
		var anchor: Vector2 = landmark["anchor"]
		var origin := Vector3(
			(cell.x + anchor.x) * Tuning.CELL_SIZE,
			0.0,
			(cell.y + anchor.y) * Tuning.CELL_SIZE
		)

		# Free rotation about Y. Every shape below is built axis-aligned, so
		# without this a field of them lines up like a parade and stops reading
		# as scenery.
		var basis := Basis(Vector3.UP, float(landmark["yaw"]))
		var scaled := basis.scaled(Vector3.ONE * float(landmark["scale"]))

		_emit_landmark(tools[type_index], type_index, Transform3D(scaled, origin))
		used[type_index] = true

	for i in tools.size():
		if not used[i]:
			continue

		var config: Dictionary = Tuning.LANDMARK_TYPES[i]
		var colour: Color = config["colour"]

		tools[i].generate_normals()

		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.emission_enabled = true
		mat.emission = colour
		# Well under the neon's 2.2. A landmark must be visible but never
		# brighter than a gate: gates and the exit stay the most eye-catching
		# things in the maze because they are navigation and landmarks are not.
		mat.emission_energy_multiplier = Tuning.LANDMARK_EMISSION
		mat.roughness = 0.75

		var instance := MeshInstance3D.new()
		instance.mesh = tools[i].commit()
		instance.material_override = mat
		instance.name = "Landmarks_%s" % String(config["name"])
		add_child(instance)


func _emit_landmark(st: SurfaceTool, type_index: int, xf: Transform3D) -> void:
	match type_index:
		Tuning.LANDMARK_SPIRE:
			_emit_spire(st, xf)
		Tuning.LANDMARK_MONOLITH:
			_emit_monolith(st, xf)
		Tuning.LANDMARK_TREE:
			_emit_tree(st, xf)
		Tuning.LANDMARK_ARCH:
			_emit_arch(st, xf)
		Tuning.LANDMARK_RINGS:
			_emit_rings(st, xf)
		Tuning.LANDMARK_RUBBLE:
			_emit_rubble(st, xf)


# A tapering column. The taper is the identity: at distance only the top clears
# the wall line, and a narrowing point reads as a spire where a constant-width
# column would read as a monolith.
func _emit_spire(st: SurfaceTool, xf: Transform3D) -> void:
	var h: float = float(Tuning.LANDMARK_TYPES[Tuning.LANDMARK_SPIRE]["height"])
	# Squared off rather than round, so it silhouettes as built rather than grown
	# -- the tree is the round one and the two must not converge at distance.
	_emit_drum(st, xf, 0.0, h * 0.70, 1.15, 0.55, 4)
	_emit_drum(st, xf, h * 0.70, h, 0.55, 0.05, 4)


# A fat slab with a flat top -- the deliberate opposite of the spire, so the two
# cannot be confused from their tops alone, which is all that is visible of
# either at distance.
func _emit_monolith(st: SurfaceTool, xf: Transform3D) -> void:
	var h: float = float(Tuning.LANDMARK_TYPES[Tuning.LANDMARK_MONOLITH]["height"])
	_emit_box(st, xf, Vector3(-1.15, 0.0, -0.75), Vector3(1.15, h, 0.75))
	# A slight overhanging cap, so the flat top reads as deliberate rather than
	# as a spire that was cut off.
	_emit_box(st, xf, Vector3(-1.35, h, -0.95), Vector3(1.35, h + 0.4, 0.95))


# A thin trunk under a wide canopy. The canopy is faceted rather than a sphere:
# flat facets catch the headlight in bands, which reads as foliage mass at a
# glance, and it costs a fraction of the triangles.
func _emit_tree(st: SurfaceTool, xf: Transform3D) -> void:
	var h: float = float(Tuning.LANDMARK_TYPES[Tuning.LANDMARK_TREE]["height"])
	var trunk_top := h * 0.5

	_emit_drum(st, xf, 0.0, trunk_top, 0.45, 0.28, 5)

	# Two stacked drums, wider below, so it silhouettes as a rounded mass rather
	# than as a cylinder on a stick.
	var mid := trunk_top + (h - trunk_top) * 0.5
	_emit_drum(st, xf, trunk_top - 0.3, mid, 2.0, 2.35)
	_emit_drum(st, xf, mid, h, 2.35, 0.45)


# Two legs and a lintel. The GAP is the silhouette -- it is the only landmark
# you can see through, which is what makes it recognisable in a corridor where
# everything else is solid.
func _emit_arch(st: SurfaceTool, xf: Transform3D) -> void:
	var h: float = float(Tuning.LANDMARK_TYPES[Tuning.LANDMARK_ARCH]["height"])
	var leg := 0.22
	var span := 0.95
	var lintel := h * 0.24

	_emit_box(st, xf, Vector3(-span, 0.0, -leg), Vector3(-span + leg * 2.0, h - lintel, leg))
	_emit_box(st, xf, Vector3(span - leg * 2.0, 0.0, -leg), Vector3(span, h - lintel, leg))
	_emit_box(st, xf, Vector3(-span, h - lintel, -leg), Vector3(span, h, leg))


# Stacked concentric rings, widest at the base. Built as thin drums rather than
# real torii: at this size the difference is invisible and a torus is an order
# of magnitude more triangles.
func _emit_rings(st: SurfaceTool, xf: Transform3D) -> void:
	var h: float = float(Tuning.LANDMARK_TYPES[Tuning.LANDMARK_RINGS]["height"])
	var count := 3

	for i in count:
		var t := float(i) / float(count)
		var y0 := h * t
		var radius := lerpf(1.05, 0.4, t)
		_emit_drum(st, xf, y0, y0 + h * 0.2, radius, radius * 0.8, 7)


# Scattered low blocks at irregular angles.
#
# Deterministic despite looking random: the offsets are a FIXED table, not RNG
# draws. Pulling from a generator here would make the mesh differ between two
# builds of the same seed, which breaks the reproducibility the whole generator
# rests on -- and it would be invisible until someone compared two runs.
func _emit_rubble(st: SurfaceTool, xf: Transform3D) -> void:
	var blocks := [
		[Vector3(-0.55, 0.0, -0.35), Vector3(0.05, 0.55, 0.25), 0.4],
		[Vector3(0.10, 0.0, -0.60), Vector3(0.70, 0.34, 0.05), -0.7],
		[Vector3(-0.30, 0.0, 0.15), Vector3(0.35, 0.80, 0.62), 0.15],
		[Vector3(0.30, 0.0, 0.30), Vector3(0.75, 0.28, 0.70), 1.1],
	]

	for block in blocks:
		var spin := Transform3D(Basis(Vector3.UP, float(block[2])), Vector3.ZERO)
		_emit_box(st, xf * spin, block[0], block[1])


# --- Landmark primitives -----------------------------------------------------

# An axis-aligned box between two corners, transformed into place.
func _emit_box(st: SurfaceTool, xf: Transform3D, lo: Vector3, hi: Vector3) -> void:
	var p := [
		xf * Vector3(lo.x, lo.y, lo.z),
		xf * Vector3(hi.x, lo.y, lo.z),
		xf * Vector3(hi.x, lo.y, hi.z),
		xf * Vector3(lo.x, lo.y, hi.z),
		xf * Vector3(lo.x, hi.y, lo.z),
		xf * Vector3(hi.x, hi.y, lo.z),
		xf * Vector3(hi.x, hi.y, hi.z),
		xf * Vector3(lo.x, hi.y, hi.z),
	]

	# Wound counter-clockwise seen from OUTSIDE, so normals face outward and the
	# faces light correctly. Inverted winding is invisible until culling is on --
	# the wall boxes shipped that way once and every wall went see-through the
	# moment CULL_BACK was enabled (CLAUDE.md section 12). SceneTest asserts the
	# signed volume of this mesh is positive for the same reason.
	_add_quad(st, p[7], p[6], p[5], p[4])   # top
	_add_quad(st, p[0], p[1], p[2], p[3])   # bottom
	_add_quad(st, p[0], p[4], p[5], p[1])   # -Z
	_add_quad(st, p[2], p[6], p[7], p[3])   # +Z
	_add_quad(st, p[3], p[7], p[4], p[0])   # -X
	_add_quad(st, p[1], p[5], p[6], p[2])   # +X


# A prism between two heights with independent lower and upper radii. Every
# rounded landmark shape reduces to this plus boxes.
func _emit_drum(st: SurfaceTool, xf: Transform3D, y0: float, y1: float,
		r0: float, r1: float, sides: int = 8) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)

		var lo0 := xf * Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var lo1 := xf * Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var hi0 := xf * Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var hi1 := xf * Vector3(cos(a1) * r1, y1, sin(a1) * r1)

		# Side face, wound so the normal points AWAY from the axis.
		#
		# The order matters and is easy to get backwards: with +Y up and the
		# angle sweeping from +X toward +Z, going lo0 -> lo1 -> hi1 -> hi0 winds
		# CLOCKWISE seen from outside, i.e. inward. Reversing to lo1 -> lo0 is
		# what puts the normal outward. SceneTest asserts the signed volume of
		# the finished landmark meshes is positive, which is what caught this --
		# inverted winding renders identically until backface culling is on.
		_add_quad(st, lo1, lo0, hi0, hi1)

		# Cap the top when the shape closes to a non-zero radius, so a drum seen
		# from above is not hollow. A tip that tapers to nothing needs no cap.
		if r1 > 0.02:
			var top_centre := xf * Vector3(0.0, y1, 0.0)
			st.add_vertex(top_centre)
			st.add_vertex(hi1)
			st.add_vertex(hi0)

		# And the bottom, so a landmark seen through an opening below its base
		# -- the exterior ring, viewed from inside the maze -- is not open.
		if r0 > 0.02:
			var base_centre := xf * Vector3(0.0, y0, 0.0)
			st.add_vertex(base_centre)
			st.add_vertex(lo0)
			st.add_vertex(lo1)
