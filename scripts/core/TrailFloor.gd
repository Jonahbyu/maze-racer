# Drives the floor's trail texture from the racer's TrailMemory.
#
# The whole reason the floor is a shader reading a texture rather than a mesh of
# per-cell quads is here: lighting a cell is one pixel write, so the cost is
# proportional to the cells that CHANGED this frame, not to the maze. At maze 5
# with the top rank the trail can cover thousands of cells, and CLAUDE.md
# section 12 already records what rebuilding geometry per frame costs -- the
# GoldenTrail ribbon was 23ms a frame before it became a shader uniform.
#
# It owns no state of its own beyond the last values written. The record lives
# on the Racer; this only paints it.
class_name TrailFloor
extends Node

# 0.5 is untrodden -- the signed packing the shader unpacks. Kept here as well
# as in the shader because both ends have to agree on it.
const NEUTRAL := 0.5

var _mesh: MazeMesh
var _painted := {}
var _dirty := false


func set_mesh(mesh: MazeMesh) -> void:
	_mesh = mesh
	_painted.clear()
	_dirty = false


# Called every frame while the racer is driving.
func update_state(racer: Racer, upgrades: Upgrades) -> void:
	if _mesh == null or _mesh.trail_image == null or racer == null:
		return

	# The line decides what is DRAWN. The record is kept regardless (see
	# Racer.trail), so taking the line at gate 4 lights the ground already
	# driven rather than starting blank.
	if not upgrades.has_trail_memory():
		if not _painted.is_empty():
			_clear_all()
		return

	var window := upgrades.trail_memory_window()
	var now := racer.trail_clock

	# Drop lapsed cells first, so a cell that expired this frame is repainted to
	# neutral rather than left at its last brightness.
	for cell in racer.trail.expire(now, window):
		_paint(cell, NEUTRAL)

	for cell in racer.trail.cells():
		var lit := racer.trail.intensity(cell, now, window)
		var visits := mini(racer.trail.visits(cell),
			Tuning.TRAIL_TINT_BY_VISITS.size() - 1)
		var tint := float(Tuning.TRAIL_TINT_BY_VISITS[visits])

		# TRAIL_TINT_BY_VISITS is a multiplier on the floor (1.0 = untrodden),
		# and the texture stores a signed value around NEUTRAL. Map one to the
		# other, and scale by the fade so a lapsing cell walks back to neutral
		# rather than snapping.
		# Normalised against the table's OWN brightest entry rather than a
		# literal. The divisor is what maps the lit rank onto the texture's
		# +1.0 ceiling, so a hand-written copy of it goes silently wrong the
		# moment TRAIL_TINT_BY_VISITS is retuned -- the transcription trap
		# CLAUDE.md section 12 records for tests, in tuning clothes.
		var span: float = float(Tuning.TRAIL_TINT_BY_VISITS[1]) - 1.0
		var signed := clampf((tint - 1.0) / span, -1.0, 1.0) * lit
		_paint(cell, clampf(NEUTRAL + signed * 0.5, 0.0, 1.0))

	if _dirty:
		# One upload per frame, not one per cell. update() re-sends the image to
		# the GPU, and doing that per changed cell would be hundreds of uploads
		# a frame on a busy trail.
		_mesh.trail_texture.update(_mesh.trail_image)
		_dirty = false


func _paint(cell: Vector2i, value: float) -> void:
	if _mesh.trail_image == null:
		return
	if cell.x < 0 or cell.y < 0 \
			or cell.x >= _mesh.trail_image.get_width() \
			or cell.y >= _mesh.trail_image.get_height():
		return
	# Skip a write that changes nothing. On a static trail this makes the whole
	# update free, which matters because the loop above walks every remembered
	# cell every frame.
	if _painted.has(cell) and absf(float(_painted[cell]) - value) < 0.002:
		return
	_painted[cell] = value
	_mesh.trail_image.set_pixel(cell.x, cell.y, Color(value, value, value))
	_dirty = true


func _clear_all() -> void:
	for cell in _painted.keys():
		_mesh.trail_image.set_pixel(cell.x, cell.y,
			Color(NEUTRAL, NEUTRAL, NEUTRAL))
	_painted.clear()
	_mesh.trail_texture.update(_mesh.trail_image)
	_dirty = false
