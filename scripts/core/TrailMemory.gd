# The per-cell record behind the Trail Memory upgrade: how often the player has
# driven each cell, and when they were last there.
#
# PURE LOGIC. No nodes, no renderer, no time source of its own -- every method
# that cares about time takes `now` as an argument. That is what makes it
# headlessly testable (CLAUDE.md section 12), and it is also what lets the floor
# shader and the minimap agree: both read this one record rather than each
# computing its own answer from the racer's history.
#
# Deliberately SEPARATE from Racer.visited, which looks like it covers the same
# ground and does not. That dictionary holds a bool -- "has this cell been
# re-entered" -- and exists to charge the section 8b repeat-ground penalty once
# per cell. Widening it to carry counts and timestamps would put a display
# feature inside a load-bearing scoring rule, so this is a parallel record that
# the scoring rules never read.
class_name TrailMemory
extends RefCounted

# cell -> [visit count, time of last visit]
var _cells := {}

const _COUNT := 0
const _SEEN := 1


func clear() -> void:
	_cells.clear()


func count() -> int:
	return _cells.size()


func has(cell: Vector2i) -> bool:
	return _cells.has(cell)


func visits(cell: Vector2i) -> int:
	if not _cells.has(cell):
		return 0
	return int(_cells[cell][_COUNT])


func last_seen(cell: Vector2i) -> float:
	if not _cells.has(cell):
		return 0.0
	return float(_cells[cell][_SEEN])


# Record one crossing of `cell` at time `now`.
func visit(cell: Vector2i, now: float) -> void:
	if _cells.has(cell):
		_cells[cell][_COUNT] = int(_cells[cell][_COUNT]) + 1
		_cells[cell][_SEEN] = now
	else:
		_cells[cell] = [1, now]


# How brightly `cell` should draw: 1.0 while its window has time left, decaying
# to 0.0 across the final Tuning.TRAIL_FADE seconds, and 0.0 once lapsed.
func intensity(cell: Vector2i, now: float, window: float) -> float:
	if not _cells.has(cell):
		return 0.0
	if window == Tuning.TRAIL_WINDOW_INFINITE:
		return 1.0
	if window <= 0.0:
		return 0.0

	var age := now - last_seen(cell)
	if age >= window:
		return 0.0

	var remaining := window - age
	if remaining >= Tuning.TRAIL_FADE:
		return 1.0
	return clampf(remaining / Tuning.TRAIL_FADE, 0.0, 1.0)


# Drop every cell whose window has lapsed. The COUNT goes with it, so a cell
# looped four times and then left alone comes back as never driven -- the window
# is the whole rule.
#
# Returns the cells removed, so a caller driving a texture knows exactly which
# texels to clear rather than rewriting the whole image.
func expire(now: float, window: float) -> Array:
	if window == Tuning.TRAIL_WINDOW_INFINITE or window <= 0.0:
		return []

	var dropped := []
	for cell in _cells.keys():
		if now - float(_cells[cell][_SEEN]) >= window:
			dropped.append(cell)
	for cell in dropped:
		_cells.erase(cell)
	return dropped


# Every remembered cell. The renderer iterates this rather than the grid, which
# is what keeps the cost proportional to the trail rather than to the maze.
func cells() -> Array:
	return _cells.keys()
