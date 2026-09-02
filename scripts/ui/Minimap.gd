# The circular minimap, drawn with _draw() rather than a viewport.
#
# Radius comes from the Minimap upgrade rank; rank 0 draws nothing at all.
#
# The blur during upgrade picks is a real mechanic, not a transition effect: a
# paused, static, zoomed-out map would otherwise let the player solve the whole
# maze at leisure at every gate (CLAUDE.md section 7). "Blur" here is a heavy
# cell-level scramble plus a fog overlay -- enough that shapes are unreadable,
# which is the requirement.
#
# THE MAP ROTATES WITH THE PLAYER: the direction of travel is always toward the
# top of the map. A north-up map would demand a mental rotation at exactly the
# moment there is no time for one -- at 8x a cell passes in 125ms, and "the
# corridor on my left is the one drawn on the map's right" is not a translation
# anyone performs at that speed. Rotating means a left turn on screen is a left
# turn on the map, so the map can be read the way the corridor is.
#
# The cost is that the maze's absolute orientation is no longer legible, which
# is what landmarks are for (CLAUDE.md section 6) -- recognising WHERE you are
# was never the map's job at this radius.
class_name Minimap
extends Control

const SIZE := 210.0

const COL_WALL := Color(0.35, 0.62, 0.9, 0.9)
const COL_OPEN := Color(0.06, 0.09, 0.15, 0.75)
const COL_PLAYER := Color(0.2, 1.0, 0.5)
const COL_GATE := Color(1.0, 0.85, 0.15)
# A gate already taken. Cool against the live gate's amber, so the two separate
# by hue and not only by brightness -- at this scale a gate is a handful of
# pixels, and a dimmer amber square would read as the same square drawn faintly.
#
# BRIGHTER than the world marker's spent colour, deliberately, rather than the
# same value. The two are read against opposite backgrounds: the marker sits
# against a near-black sky where a dark blue still reads, while this sits on a
# map whose walls are ALREADY blue (COL_WALL), so a dark blue cell disappears
# into the strokes drawn around it. Matching the hue is what makes the two read
# as the same thing; matching the value would make one of them invisible.
const COL_GATE_SPENT := Color(0.30, 0.55, 0.95)
const COL_EXIT := Color(0.35, 1.0, 0.45)
const COL_RING := Color(0.4, 0.7, 1.0, 0.35)

var racer: Racer
var upgrades: Upgrades
var blurred := false

var _noise := FastNoiseLite.new()


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_noise.seed = 12345
	_noise.frequency = 0.35


func _process(_delta: float) -> void:
	# Cheap enough at this scale, and it has to track the player every frame.
	queue_redraw()


func _draw() -> void:
	if racer == null or upgrades == null or not upgrades.has_minimap():
		return

	var radius_cells := upgrades.minimap_radius()
	if radius_cells <= 0.0:
		return

	# Centre on the control's ACTUAL size, not the nominal constant -- a
	# container or anchor can resize it, and drawing to a stale constant puts
	# the map off-centre inside its own ring.
	var actual := size
	if actual.x <= 0.0 or actual.y <= 0.0:
		actual = Vector2(SIZE, SIZE)

	var centre := actual * 0.5
	var map_radius := minf(actual.x, actual.y) * 0.5 - 6.0
	var scale := map_radius / radius_cells

	draw_circle(centre, map_radius, Color(0.02, 0.03, 0.06, 0.85))

	var origin := racer.cell
	var span := int(ceil(radius_cells)) + 1

	# The rotation that carries the player's heading to screen-up. Every cell
	# offset and every wall stroke goes through it, so the whole map turns as one
	# rather than the contents rotating inside a fixed frame.
	var spin := _map_rotation()

	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var cell := origin + Vector2i(dx, dy)
			if not _in_maze(cell):
				continue

			var offset := Vector2(float(dx), float(dy)).rotated(spin) * scale
			# Clip to the ring, leaving room for the cell's own footprint so a
			# half-drawn square does not poke outside the circle.
			if offset.length() > map_radius - scale * 0.5:
				continue

			_draw_cell(cell, centre + offset, scale, spin)

	# Player marker, always dead centre and always pointing UP -- the map turns
	# under it, so the arrow itself never needs to.
	if not blurred:
		_draw_player(centre, scale)

	if blurred:
		# Fog over the top. Combined with the scrambled cell positions below,
		# the map becomes genuinely unreadable rather than merely soft.
		draw_circle(centre, map_radius, Color(0.05, 0.07, 0.12, 0.82))

	draw_arc(centre, map_radius, 0.0, TAU, 64, COL_RING, 2.0, true)


# Screen-space rotation putting the player's facing at the top of the map.
#
# Grid +X is drawn to the right and +Y downward, so a racer facing +X must be
# rotated a quarter turn anticlockwise to point up, +Y a half turn, and so on.
# atan2 on the facing vector gives its screen angle directly; subtracting it
# from -PI/2 (screen "up") is the rotation that lands it there.
func _map_rotation() -> float:
	var v: Vector2i = Maze.DIR_VECTORS[racer.facing]
	return -PI * 0.5 - atan2(float(v.y), float(v.x))


func _draw_cell(cell: Vector2i, at: Vector2, scale: float, spin: float) -> void:
	var pos := at
	if blurred:
		# Scramble each cell by up to a full cell in a stable, seeded way. The
		# map still looks like a map; it just no longer says anything true.
		var n1 := _noise.get_noise_2d(float(cell.x) * 3.1, float(cell.y) * 3.1)
		var n2 := _noise.get_noise_2d(float(cell.y) * 5.7, float(cell.x) * 5.7)
		pos += Vector2(n1, n2) * scale * 1.6

	var cell_size := scale * 0.82

	var colour := COL_OPEN
	if cell == racer.maze.exit_cell:
		colour = COL_EXIT
	elif racer.gates_cleared.has(cell):
		# Checked BEFORE the live-gate test: maze.gates is the full placement
		# list and never shrinks, so a taken gate is still in it and would
		# otherwise keep painting itself as one still worth driving to.
		colour = COL_GATE_SPENT
	elif racer.maze.gates.has(cell):
		colour = COL_GATE

	draw_rect(Rect2(pos - Vector2(cell_size, cell_size) * 0.5,
		Vector2(cell_size, cell_size)), colour, true)

	# Walls as short strokes on the cell edge. The stroke direction rotates with
	# the map -- drawing them unrotated would leave every wall axis-aligned while
	# the cells around them turned, which reads as the walls sliding off the
	# cells they belong to.
	var half := scale * 0.5
	for dir in Maze.DIRS:
		if not racer.maze._has_wall(cell, dir):
			continue
		var v: Vector2i = Maze.DIR_VECTORS[dir]
		var normal := Vector2(float(v.x), float(v.y)).rotated(spin)
		var along := Vector2(-normal.y, normal.x)
		var mid := pos + normal * half
		draw_line(mid - along * half, mid + along * half, COL_WALL, 1.5)


func _draw_player(centre: Vector2, scale: float) -> void:
	# Fixed pointing up. The map rotates instead, so reading the arrow's heading
	# off the racer here would rotate it twice and leave it permanently wrong.
	var forward := Vector2(0.0, -1.0)
	var side := Vector2(-forward.y, forward.x)
	var r := maxf(scale * 0.45, 4.0)

	var points := PackedVector2Array([
		centre + forward * r * 1.4,
		centre - forward * r * 0.8 + side * r * 0.9,
		centre - forward * r * 0.8 - side * r * 0.9,
	])
	draw_colored_polygon(points, COL_PLAYER)


func _in_maze(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < racer.maze.width \
		and cell.y >= 0 and cell.y < racer.maze.height
