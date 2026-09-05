# The quadrant box: which region of the maze the player is in, and which way
# they face.
#
# Two upgrade lines share one widget (CLAUDE.md section 7). Quadrant draws the
# maze split 2x2 / 3x3 / 4x4 with the occupied region lit; Compass writes the
# cardinal letter the player is pointing. They are drawn together because they
# are read together -- but either works alone, and a player holding only the
# Compass gets the letter with no grid under it.
#
# POSITION ONLY. Nothing here reads the distance field, the solve path, the
# gates or the openings -- the box says which sixteenth of the maze you stand
# in and never which way to turn. That is what keeps it on the "have I been
# here" side of the line landmarks, spent gates and the rear-view mirror hold,
# and clear of the three PAID lines sold on answering the route ahead.
class_name QuadrantBox
extends Control

# Same hue family as the rear-view frame and the minimap ring: this is another
# instrument, not another world colour, so it stays fixed across every palette
# for the reason section 8 gives for the whole HUD.
const COL_FRAME := Color(0.35, 0.72, 1.0, 0.55)
const COL_GRID := Color(0.35, 0.72, 1.0, 0.28)
const COL_LABEL := Color(0.55, 0.78, 1.0, 0.75)
# The lit region. Bright enough to find without a look, and deliberately NOT
# green, amber or white -- those are Path Indicator, gates and the exit
# (section 8), and a region highlight that borrowed one would read as a route
# hint, which is exactly what this must never be.
const COL_HERE := Color(0.45, 0.82, 1.0, 0.85)
# The exit's region, outlined but never filled. It marks the corner the maze
# ends in, which the numbering already promises is the highest quadrant -- so
# this states a fact the player has been told rather than adding a new one.
const COL_EXIT := Color(0.98, 0.92, 0.62, 0.5)
# The cardinal letter, at full strength. Near-white so it carries no hue of its
# own -- the same reasoning the player marker rests on (section 8), and it keeps
# the letter clear of the amber the exit outline beside it uses.
const COL_CARDINAL := Color(0.92, 0.96, 1.0, 0.95)

const FRAME_WIDTH := 2.0
const GRID_WIDTH := 1.0
const MARGIN := 24.0

# Sized off the SHORTER viewport edge with a floor and no ceiling, which is the
# section 9d lesson: a pixel is a count rather than a size, and a pixel CAP
# hands the smallest screen the smallest box.
const SHORT_FRACTION := 0.115
const MIN_SIZE := 76.0
const MAX_WIDTH_SHARE := 0.16

# The gap below whatever sits above it. The box shares the left margin with the
# rear-view mirror and stacks under it, so Game passes the mirror's bottom edge
# rather than this guessing at it -- two widgets in one column that each
# measured the other independently is how they drift apart.
const STACK_GAP := 10.0
# Room ABOVE the grid for the "N of 16" count, and BELOW it for the compass
# letter. Both bands are part of this widget's own rect rather than text hung
# outside it -- a label placed at a negative offset reached up into the rear-view
# mirror stacked above, and a letter written at the rect's exact bottom edge was
# clipped by it. Only a rendered frame shows either: the RECTS did not overlap,
# and the TEXT did, which is the same trap the mirror hit against the maze name.
const HEADER_BAND := 16.0
# Wider than the letter's own font size: a band equal to the glyph height clips
# its descender and its outline against the rect edge.
const LABEL_BAND := 30.0

# Set by Game each frame. divisions of 0 means the Quadrant line is untaken and
# only the compass letter is drawn.
var divisions := 0
var here := Vector2i(-1, -1)
var exit_at := Vector2i(-1, -1)
var quadrant_number := 0
var quadrant_total := 0
var cardinal := ""

var _label: Label
var _count: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# "N of 16" sits above the grid, the cardinal letter below it. The number is
	# the progress statement and the letter is the orientation one; stacking
	# them keeps both a single glance from the grid they describe.
	_count = _make_label(11, COL_LABEL)
	_count.position = Vector2(0.0, 0.0)
	add_child(_count)

	# The letter is sized and coloured well above the count above it. Measured
	# in a rendered frame at 15px in the label blue, it was a smudge under the
	# grid -- and a readout the player has to squint at is not one they check at
	# 8x. It is the only orientation cue on screen, so it gets the weight of the
	# thing it replaces looking around for.
	_label = _make_label(22, COL_CARDINAL)
	add_child(_label)


func _make_label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# `top` is the y this box hangs from -- the bottom of whatever is above it in
# the same column, passed in rather than measured here.
func place(view: Vector2, top: float) -> void:
	var short_edge: float = min(view.x, view.y)
	var side: float = max(short_edge * SHORT_FRACTION, MIN_SIZE)
	side = min(side, view.x * MAX_WIDTH_SHARE)

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = MARGIN
	offset_right = MARGIN + side
	offset_top = top + STACK_GAP
	offset_bottom = top + STACK_GAP + HEADER_BAND + side + LABEL_BAND
	size = Vector2(side, HEADER_BAND + side + LABEL_BAND)

	if _label:
		_label.position = Vector2(0.0, HEADER_BAND + side + 1.0)
	queue_redraw()


# Everything the box shows, in one call, so the widget never reaches back into
# the racer or the maze itself -- it is a readout, and a readout that queried
# the simulation could disagree with the frame it is drawn in.
func show_state(p_divisions: int, p_here: Vector2i, p_exit: Vector2i,
		p_number: int, p_total: int, p_cardinal: String) -> void:
	divisions = p_divisions
	here = p_here
	exit_at = p_exit
	quadrant_number = p_number
	quadrant_total = p_total
	cardinal = p_cardinal

	if _count:
		_count.text = "" if p_total <= 0 else "%d of %d" % [p_number, p_total]
	if _label:
		_label.text = p_cardinal
	queue_redraw()


func _draw() -> void:
	if divisions < 1:
		return

	# The grid is the square between the two text bands, not the whole rect.
	var side: float = size.y - HEADER_BAND - LABEL_BAND
	if side <= 0.0:
		return
	var step: float = side / float(divisions)
	# Everything below draws in grid space; this shifts it under the header.
	draw_set_transform(Vector2(0.0, HEADER_BAND))

	# The lit region first, so the grid lines are drawn ON TOP of the fill and
	# the highlighted cell keeps its borders. Filling over the lines instead
	# makes the lit region look like it has swallowed its own edges, which reads
	# as a rendering fault rather than a highlight.
	if exit_at.x >= 0 and exit_at != here:
		draw_rect(_cell_rect(exit_at, step), COL_EXIT, false, FRAME_WIDTH)
	if here.x >= 0:
		draw_rect(_cell_rect(here, step), COL_HERE, true)

	for i in range(1, divisions):
		var at: float = step * float(i)
		draw_line(Vector2(at, 0.0), Vector2(at, side), COL_GRID, GRID_WIDTH)
		draw_line(Vector2(0.0, at), Vector2(side, at), COL_GRID, GRID_WIDTH)

	draw_rect(Rect2(Vector2.ZERO, Vector2(side, side)), COL_FRAME, false, FRAME_WIDTH)


func _cell_rect(coord: Vector2i, step: float) -> Rect2:
	return Rect2(
		Vector2(float(coord.x) * step, float(coord.y) * step),
		Vector2(step, step))


