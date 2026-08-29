# The Path Indicator upgrade, drawn ON THE CORRIDOR WALLS at a junction.
#
# This used to be three chevrons pinned to the middle of the HUD. That put the
# answer to "which way" in screen space, floating in the air over a corridor it
# had no fixed relationship to -- the player had to map a flat overlay back onto
# the 3D junction rushing toward them, at exactly the moment they had least time
# to do it. Worse, it trained them to watch the centre of the screen instead of
# the maze, which is the opposite of what the upgrade is for.
#
# Painted on the walls, the answer is already in the place it applies to. A lit
# panel at the mouth of the left corridor IS "go left" -- there is nothing to
# translate, and the player's eyes stay on the geometry they are steering
# through.
#
# Green means "this way to the exit", red means "not this way"
# (CLAUDE.md section 7). It reads the live distance field, so it stays correct
# in a looped maze where the player has stepped off the canonical path.
class_name PathIndicator
extends Node3D

const COL_GOOD := Color(0.15, 1.0, 0.45)
const COL_BAD := Color(1.0, 0.22, 0.22)

# One panel per relative direction. Index matches _SLOTS below.
var _panels: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _pulse := 0.0
var _built := false

# left, ahead, right -- as relative keys matching Racer.correct_relative_turn().
const _SLOTS := [-1, 0, 1]


func _ready() -> void:
	_build()
	visible = false


# Built lazily as well as in _ready(), because a harness that adds this node and
# drives it in the same frame gets here before _ready() has run -- the same trap
# GoldenTrail hit (CLAUDE.md section 12).
func _build() -> void:
	if _built:
		return
	_built = true

	for i in _SLOTS.size():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COL_GOOD
		mat.emission_enabled = true
		mat.emission = COL_GOOD
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Double-sided for the same reason the walls are: a zero-thickness wall
		# is shared by the corridors either side, so a panel laid against one
		# has no single correct facing.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		var mesh := MeshInstance3D.new()
		mesh.name = "Panel%d" % i
		mesh.mesh = _make_panel()
		mesh.material_override = mat
		mesh.visible = false
		add_child(mesh)

		_panels.append(mesh)
		_materials.append(mat)


# A tall bar in the XY plane, sized to sit inside a corridor mouth.
#
# Deliberately NOT a chevron or an arrow. The panel's POSITION already says
# which way it points -- it is on the left wall, or the right one -- so an
# arrowhead would be repeating in symbols what the geometry states directly, and
# arrow shapes read poorly at a glancing angle, which is exactly how a side wall
# is seen when approaching a junction at speed. A plain lit slab holds its shape
# from any angle.
func _make_panel() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w := Tuning.CELL_SIZE * 0.30
	var bottom := Tuning.WALL_HEIGHT * 0.12
	var top := Tuning.WALL_HEIGHT * 0.78

	var p1 := Vector3(-half_w, bottom, 0.0)
	var p2 := Vector3(half_w, bottom, 0.0)
	var p3 := Vector3(half_w, top, 0.0)
	var p4 := Vector3(-half_w, top, 0.0)

	st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(p3)
	st.add_vertex(p1); st.add_vertex(p3); st.add_vertex(p4)
	st.generate_normals()

	return st.commit()


func update_state(racer: Racer, upgrades: Upgrades, delta: float) -> void:
	_build()
	_pulse += delta

	if racer == null or racer.maze == null or not upgrades.has_indicator():
		_hide_all()
		return

	var maze: Maze = racer.maze

	# Only mark a genuine CHOICE of onward routes -- a T or a crossroads.
	#
	# A corner has exactly one way on, so the player has no decision to inform
	# and lighting it is pure noise on the most common cell shape in a DFS maze.
	# Counting only the ways ONWARD (every opening but the one behind) keeps the
	# panels dark until the answer actually matters.
	var behind := int(Maze.OPPOSITE[racer.facing])
	var onward := 0
	for dir in maze.open_directions(racer.cell):
		if int(dir) != behind:
			onward += 1

	if onward < 2:
		_hide_all()
		return

	visible = true

	var correct := racer.correct_relative_turn()

	for i in _SLOTS.size():
		var key: int = _SLOTS[i]
		var direction := _absolute(racer, key)
		var is_open := maze.is_open(racer.cell, direction)

		_panels[i].visible = is_open
		if not is_open:
			continue

		_place(_panels[i], maze, racer.cell, direction)

		var colour := COL_GOOD if key == correct else COL_BAD
		_materials[i].albedo_color = colour
		_materials[i].emission = colour

		# The correct route pulses; the wrong ones hold steady. Motion is the
		# strongest thing in peripheral vision, so spending it on the ONE answer
		# means the right panel is findable without being looked at directly --
		# which is the whole point of putting this in the world instead of on
		# the HUD.
		var lit := 3.0
		if key == correct:
			lit += maxf(sin(_pulse * 7.0), 0.0) * 3.0
		_materials[i].emission_energy_multiplier = lit
		_materials[i].albedo_color.a = 0.85


func _hide_all() -> void:
	visible = false
	for panel in _panels:
		panel.visible = false


func _absolute(racer: Racer, key: int) -> int:
	if key == -1:
		return racer.left_direction()
	if key == 1:
		return racer.right_direction()
	return racer.facing


# Lay a panel flat against the FAR wall of the corridor it marks -- one cell
# along the opening, on the wall the player would face after taking it.
#
# Not on the near wall beside the opening: that surface is edge-on to a player
# approaching down the corridor, so the panel would compress to a line exactly
# when it is being read. The far wall of the neighbouring cell is square-on to
# the approach and stays legible the whole way in.
func _place(panel: MeshInstance3D, maze: Maze, cell: Vector2i, direction: int) -> void:
	var v: Vector2i = Maze.DIR_VECTORS[direction]

	# Just proud of the wall face so it never z-fights with the wall it sits on.
	var to_face := Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5 - 0.04

	var target := cell + v

	# The far wall only exists if that corridor actually ENDS there. A branch
	# that continues straight on has open air where the panel would go, and a
	# panel with no wall behind it is the floating-in-space problem this whole
	# node exists to fix. When there is nothing to paint on, fall back to a side
	# wall of the neighbouring cell -- still inside the corridor being marked,
	# still square to nothing, but attached to real geometry.
	if maze.is_open(target, direction):
		var side := _side_wall(maze, target, direction)
		if side == -1:
			# Fully open on every side: no surface anywhere in that cell. Rare,
			# and there is nothing honest to draw, so draw nothing.
			panel.visible = false
			return
		var sv: Vector2i = Maze.DIR_VECTORS[side]
		panel.position = Vector3(
			float(target.x) * Tuning.CELL_SIZE + float(sv.x) * to_face,
			0.0,
			float(target.y) * Tuning.CELL_SIZE + float(sv.y) * to_face
		)
		panel.rotation = Vector3(0.0, atan2(-float(sv.x), -float(sv.y)), 0.0)
		return

	panel.position = Vector3(
		float(target.x) * Tuning.CELL_SIZE + float(v.x) * to_face,
		0.0,
		float(target.y) * Tuning.CELL_SIZE + float(v.y) * to_face
	)
	# Face back down the corridor, toward the player.
	panel.rotation = Vector3(0.0, atan2(-float(v.x), -float(v.y)), 0.0)


# Pick a wall perpendicular to `direction` in `cell`, preferring whichever side
# is solid. Returns -1 when both are open.
func _side_wall(maze: Maze, cell: Vector2i, direction: int) -> int:
	for dir in Maze.DIRS:
		var d := int(dir)
		if d == direction or d == int(Maze.OPPOSITE[direction]):
			continue
		if not maze.is_open(cell, d):
			return d
	return -1
