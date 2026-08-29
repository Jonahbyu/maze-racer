# Marks the wall the player is about to drive into.
#
# See docs/specs/wall-indicator.md. The short version: at 4x a wall arrives in
# 250ms, and perspective alone compresses the "how long have I got" read exactly
# when speed makes it matter. Section 11.3 says a timing demand must be visible
# before it is demanded; a corridor that ends IS a timing demand.
#
# Critically this marks a DEAD END, never a correct turn. A T-junction or a
# corner gets nothing -- the player still solves the routing themselves, which
# is what keeps this from cannibalising Path Indicator, the headline paid
# upgrade. It only fires where continuing is unsurvivable and no turn exists to
# save it, which is the one case the player cannot read out of the corridor.
class_name WallIndicator
extends Node3D

# Only show a wall this close. Further out it stops being an imminent demand and
# starts being a map of the maze.
const SHOW_WITHIN_CELLS := 2.5

const COL_FAR := Color(1.0, 0.62, 0.10)
const COL_NEAR := Color(1.0, 0.16, 0.12)

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _pulse := 0.0


func _ready() -> void:
	_build()
	visible = false


# A ring with a slash through it, drawn flat against the wall face. A plain disc
# reads as a light or a pickup; the barred ring reads as "no" with no legend.
func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var outer := Tuning.CELL_SIZE * 0.24
	var inner := outer * 0.74
	var segments := 40

	# The ring, drawn in the XY plane so it lies flat on a wall face once the
	# node is rotated to match the wall's normal.
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)

		var o0 := Vector3(cos(a0) * outer, sin(a0) * outer, 0.0)
		var o1 := Vector3(cos(a1) * outer, sin(a1) * outer, 0.0)
		var i0 := Vector3(cos(a0) * inner, sin(a0) * inner, 0.0)
		var i1 := Vector3(cos(a1) * inner, sin(a1) * inner, 0.0)

		st.add_vertex(i0); st.add_vertex(o1); st.add_vertex(o0)
		st.add_vertex(i0); st.add_vertex(i1); st.add_vertex(o1)

	# The bar, a rotated quad across the middle.
	var bar_half := outer * 0.92
	var bar_thick := (outer - inner) * 0.5
	var ang := deg_to_rad(45.0)
	var along := Vector3(cos(ang), sin(ang), 0.0) * bar_half
	var across := Vector3(-sin(ang), cos(ang), 0.0) * bar_thick

	var b1 := -along - across
	var b2 := along - across
	var b3 := along + across
	var b4 := -along + across

	st.add_vertex(b1); st.add_vertex(b2); st.add_vertex(b3)
	st.add_vertex(b1); st.add_vertex(b3); st.add_vertex(b4)

	st.generate_normals()

	_material = StandardMaterial3D.new()
	_material.albedo_color = COL_FAR
	_material.emission_enabled = true
	_material.emission = COL_FAR
	_material.emission_energy_multiplier = 3.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Double-sided so a wall approached from either side still shows the mark --
	# the same wall face is shared by two cells.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mesh = MeshInstance3D.new()
	_mesh.name = "Mark"
	_mesh.mesh = st.commit()
	_mesh.material_override = _material
	add_child(_mesh)


func update_state(racer: Racer, delta: float) -> void:
	_pulse += delta

	var maze: Maze = racer.maze
	if maze == null:
		visible = false
		return

	# Scan forward for the first blocked facing, tracking the distance to the
	# blocking FACE rather than to the cell that owns it. Those differ by up to a
	# full cell, and confusing them let the mark land three cells out -- well past
	# the window -- whenever the racer was deep into its current cell.
	#
	# The face at the far side of the current cell is (1 - progress) away; each
	# further cell adds one.
	var cell := racer.cell
	var step: Vector2i = Maze.DIR_VECTORS[racer.facing]
	var distance := 1.0 - racer.progress
	var found := false

	while distance <= SHOW_WITHIN_CELLS:
		if not maze.is_open(cell, racer.facing):
			# Only a REAL dead end earns the mark. A corridor that merely turns
			# has a blocked facing too, and marking those lit the sign on roughly
			# half the cells in a DFS maze -- constant enough that it stopped
			# reading as a warning at all, and it sat over junctions the player
			# was about to turn through cleanly. If either side is open, the
			# player has somewhere to go and needs no no-entry sign.
			found = _is_dead_end(maze, cell, racer.facing)
			break
		cell += step
		distance += 1.0

	if not found:
		visible = false
		return

	visible = true
	_place_on_wall(cell, racer.facing)

	# Colour IS the distance read -- cheaper to parse than the wall's size in
	# perspective, which is the thing that fails at speed.
	var t := clampf(1.0 - distance / SHOW_WITHIN_CELLS, 0.0, 1.0)
	var colour := COL_FAR.lerp(COL_NEAR, t)

	_material.albedo_color = colour
	_material.emission = colour

	# Reach full opacity by the time the wall is one cell out, and hold it there.
	# A linear ramp across the whole window peaked at ~0.8 alpha even while the
	# racer was scraping the wall, which on a dark blue surface read as a faint
	# smudge at exactly the moment the warning matters most.
	var fade := clampf((SHOW_WITHIN_CELLS - distance) / (SHOW_WITHIN_CELLS - 1.0), 0.0, 1.0)
	_material.albedo_color.a = fade

	# Emission carries the urgency, not alpha. A pulse that dips below solid puts
	# a trough at the peak of the warning, so this only ever brightens: the mark
	# is always at least fully lit and flashes UP from there, faster as the wall
	# closes.
	var flash: float = maxf(sin(_pulse * (5.0 + t * 9.0)), 0.0)
	_material.emission_energy_multiplier = 3.0 + t * 6.0 + flash * (1.0 + t * 3.0)


# A cell entered heading `facing` is a dead end when forward, left and right are
# all walls: the only exit is a 180 back the way you came. Reversal-only is the
# definition that matters here, because it is exactly the case where continuing
# costs the player a crash with no turn available to save it.
func _is_dead_end(maze: Maze, cell: Vector2i, facing: int) -> bool:
	for dir in Maze.DIRS:
		if dir == Maze.OPPOSITE[facing]:
			continue
		if maze.is_open(cell, dir):
			return false
	return true


# Lay the mark flat against the given side of the given cell, just proud of the
# wall face so it never z-fights with the wall it is drawn on.
func _place_on_wall(cell: Vector2i, dir: int) -> void:
	var v: Vector2i = Maze.DIR_VECTORS[dir]
	var to_face := Tuning.CELL_SIZE * 0.5 - Tuning.WALL_THICKNESS * 0.5 - 0.03

	position = Vector3(
		cell.x * Tuning.CELL_SIZE + v.x * to_face,
		Tuning.WALL_HEIGHT * 0.42,
		cell.y * Tuning.CELL_SIZE + v.y * to_face
	)

	# Face back down the corridor toward the player.
	rotation = Vector3(0.0, atan2(-float(v.x), -float(v.y)), 0.0)
