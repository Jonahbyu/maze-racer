# The Path Indicator upgrade, drawn as a LIT STRIP ACROSS THE FLOOR of each
# opening at a junction.
#
# Two moves got it here. It began as three chevrons pinned to the middle of the
# HUD, which put the answer to "which way" in screen space, floating over a
# corridor it had no fixed relationship to -- the player had to map a flat
# overlay back onto the 3D junction rushing toward them, at exactly the moment
# they had least time to do it, and it trained them to watch the centre of the
# screen instead of the maze.
#
# Moving it into the world fixed that but put it on the WALLS, one cell down
# each branch. That is a surface the player reads by looking INTO a corridor,
# and it is the far wall of the neighbouring cell -- so the answer sat past the
# decision rather than on it, and where a branch continued straight there was no
# far wall at all and the panel fell back to whatever side wall existed.
#
# A strip laid across the mouth of each opening has neither problem. It marks
# the GAP -- the thing the player is choosing between -- it lies on the cell
# boundary, which is already the timing contract the whole control scheme runs
# on (section 11.3), and every opening has a floor by definition, so there is no
# fallback case and nothing ever floats.
#
# Three colours, from Maze.branch_quality():
#
#   GREEN  -- the optimal route, the way the Golden Trail would go
#   YELLOW -- a longer way that still reaches the exit
#   RED    -- leads nowhere: a dead end, or a pocket that only drains back here
#
# The middle colour is the point of the change. A braided maze (up to 30% at
# maze 5) is full of routes that work and are not best, and calling those wrong
# tells the player to reverse out of a corridor they should commit to -- which
# collapses the routing decision section 11.2 exists to protect.
class_name PathIndicator
extends Node3D

const COL_BEST := Color(0.15, 1.0, 0.45)
const COL_VIABLE := Color(1.0, 0.80, 0.15)
const COL_BAD := Color(1.0, 0.22, 0.22)

# One strip per relative direction. Index matches _SLOTS below.
var _strips: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _pulse := 0.0
var _built := false

# left, ahead, right -- as relative keys matching Racer.correct_relative_turn().
const _SLOTS := [-1, 0, 1]

# Clear of everything else already on the floor: the cell grid lines sit at
# 0.02, the lane sub-grid at 0.018 and the walls' own neon band at 0.05. A
# marking that fought any of those for depth would strobe at distance, and the
# cell lines in particular must never be disturbed -- they are the timing
# reference (section 11.3).
const STRIP_Y := 0.09


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
		mat.albedo_color = COL_BEST
		mat.emission_enabled = true
		mat.emission = COL_BEST
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Seen from both sides for the same reason the walls are: the player can
		# cross a junction from either approach, and a strip that vanished when
		# looked at from the far side would be missing exactly when re-reading a
		# junction on a second pass.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		var mesh := MeshInstance3D.new()
		mesh.name = "Strip%d" % i
		mesh.mesh = _make_strip()
		mesh.material_override = mat
		mesh.visible = false
		add_child(mesh)

		_strips.append(mesh)
		_materials.append(mat)


# A flat quad in the XZ plane, spanning the corridor and laid along the
# boundary. Local +X runs across the gap, local +Z is the depth of the band.
#
# It stops just short of the full cell width so it reads as a strip laid IN the
# gap rather than a patch running into the walls either side -- the wall bases
# already carry their own neon band (section 12), and butting one marking into
# another loses both edges.
func _make_strip() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w := Tuning.CELL_SIZE * 0.42
	var half_d := Tuning.CELL_SIZE * 0.085

	var p1 := Vector3(-half_w, 0.0, -half_d)
	var p2 := Vector3(half_w, 0.0, -half_d)
	var p3 := Vector3(half_w, 0.0, half_d)
	var p4 := Vector3(-half_w, 0.0, half_d)

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
	# strips dark until the answer actually matters.
	var behind := int(Maze.OPPOSITE[racer.facing])
	var onward := 0
	for dir in maze.open_directions(racer.cell):
		if int(dir) != behind:
			onward += 1

	if onward < 2:
		_hide_all()
		return

	visible = true

	for i in _SLOTS.size():
		var key: int = _SLOTS[i]
		var direction := _absolute(racer, key)
		var is_open := maze.is_open(racer.cell, direction)

		_strips[i].visible = is_open
		if not is_open:
			continue

		_place(_strips[i], racer.cell, direction)

		var quality := maze.branch_quality(racer.cell, direction)
		var colour := COL_BAD
		if quality == Maze.Branch.BEST:
			colour = COL_BEST
		elif quality == Maze.Branch.VIABLE:
			colour = COL_VIABLE

		_materials[i].albedo_color = colour
		_materials[i].emission = colour

		# Only the best route pulses; viable and wrong both hold steady. Motion
		# is the strongest thing in peripheral vision, so spending it on the ONE
		# answer means the right gap is findable without being looked at
		# directly -- which is the whole point of putting this in the world
		# instead of on the HUD. Yellow already separates from green by hue;
		# giving it motion too would put two things moving and leave the player
		# picking between them.
		var lit := 3.0
		if quality == Maze.Branch.BEST:
			lit += maxf(sin(_pulse * 7.0), 0.0) * 3.0
		_materials[i].emission_energy_multiplier = lit
		_materials[i].albedo_color.a = 0.85


func _hide_all() -> void:
	visible = false
	for strip in _strips:
		strip.visible = false


func _absolute(racer: Racer, key: int) -> int:
	if key == -1:
		return racer.left_direction()
	if key == 1:
		return racer.right_direction()
	return racer.facing


# Lay the strip flat on the cell boundary the opening sits on -- the line
# between the player's cell and the branch, which is the gap itself.
#
# On the boundary rather than a little way down the corridor because that line
# is already the reference the player times every input against (section 11.3),
# so the answer lands on a mark they are watching anyway. It is also the last
# place the choice is still live: past it, the turn has been taken.
func _place(strip: MeshInstance3D, cell: Vector2i, direction: int) -> void:
	var v: Vector2i = Maze.DIR_VECTORS[direction]
	var reach := Tuning.CELL_SIZE * 0.5

	var origin := Vector3(
		float(cell.x) * Tuning.CELL_SIZE + float(v.x) * reach,
		STRIP_Y,
		float(cell.y) * Tuning.CELL_SIZE + float(v.y) * reach
	)

	# Build the basis outright rather than solving for a yaw angle.
	#
	# The mesh spans local X and must come out ACROSS the opening, so the span
	# is just the perpendicular of `v` -- which is directly writable, with no
	# sign to get backwards. Going via atan2 was wrong twice in a row here, and
	# each wrong sign still rendered the branch STRAIGHT AHEAD correctly (there
	# the span and the corridor axis already disagree), so half the strips on
	# screen agreed with the bug and only the side branches showed it, as a bar
	# lying lengthwise down the corridor instead of over its mouth.
	var along := Vector3(float(v.x), 0.0, float(v.y))
	var span := Vector3(-along.z, 0.0, along.x)
	strip.transform = Transform3D(Basis(span, Vector3.UP, along), origin)
