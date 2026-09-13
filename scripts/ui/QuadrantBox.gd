# The quadrant box: which region of the maze the player is in, and which way
# they face.
#
# Two upgrade lines share one widget (CLAUDE.md section 7). Quadrant draws the
# maze split 2x2 / 3x3 / 4x4 with the occupied region lit; Compass draws a
# physical compass -- a dial with a needle pointing at real north. They are
# drawn together because they are read together, SIDE BY SIDE rather than
# stacked, and either works alone.
#
# TOP-CENTRE. The pair used to hang under the rear-view mirror in the left
# column, which was where the empty space happened to be rather than where the
# reads belong. Both answer "where am I and which way am I pointing", which is
# a question the player asks about the corridor dead ahead -- so the widgets sit
# on the axis the eye already tracks, the same argument section 12 makes for
# moving the minimap to the bottom CENTRE, under the marker. A glance up the
# centre line is shorter than one into a corner and back.
#
# Laid out side by side because the top-centre band is WIDE and SHORT: the HUD's
# top row ends at y=70 and the corridor vanishing point must stay clear, so the
# space available is horizontal. Stacking them there would push the compass down
# into the corridor the player is reading.
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
# The start's region, outlined the same way. Quadrant 1 holds start_cell for the
# same derived reason the last one holds exit_cell, so this is the other end of
# the fact the numbering already states.
#
# It is drawn because the two ends together are what make the box a PROGRESS
# readout rather than a position one: a lit square at 6 of 16 says where you
# stand, and a lit square between a marked start and a marked finish says how
# far along you are. Marking only the exit gave the player one end of that
# measurement and left them to remember the other.
#
# Deliberately NOT a second amber. The exit is the destination and the start is
# behind you; two outlines in one hue would read as two goals, and the player
# would have to work out which corner was which at a glance.
#
# It separates by HUE, not by value, and the first attempt got that wrong. A
# cool blue-grey at 0.55/0.68/0.82 was the obvious "quieter than the exit"
# choice and it was measured INVISIBLE in a rendered frame: it sits in the same
# hue family as COL_GRID and COL_FRAME, so on the two sides where the start cell
# borders the outer frame it merged into it completely, and the top-left corner
# read as bare grid. Meanwhile the exit's amber was legible instantly -- because
# amber is a different hue from everything around it, not because it is
# brighter.
#
# So this is a violet: the one band left once amber is the exit, green is Path
# Indicator, white is the exit marker and the marker itself, red is the crash
# state (section 8), and blue is this widget's own frame and grid. It reads as a
# distinct mark at a glance while never being mistaken for a route hint.
#
# Still dimmer than COL_EXIT, which is the ranking that survived the retune:
# where the maze ENDS is worth more at a glance than where it began.
const COL_START := Color(0.78, 0.58, 0.98, 0.6)
# The cardinal letter, at full strength. Near-white so it carries no hue of its
# own -- the same reasoning the player marker rests on (section 8), and it keeps
# the letter clear of the amber the exit outline beside it uses.
const COL_CARDINAL := Color(0.92, 0.96, 1.0, 0.95)
# The compass needle's north half. Warm red is what a physical compass uses, and
# the convention is worth borrowing outright -- a player who has held a compass
# already knows which end is north, so the widget needs no legend.
#
# It is the one place a red is allowed on this widget. Red is the crash state
# (section 8), but that read is on the PLAYER MARKER, in the world; a needle in
# an instrument at the top of the screen is never mistaken for the racer going
# red, and the alternative -- inventing a non-red north for consistency's sake --
# would throw away the one piece of shared knowledge the whole shape relies on.
const COL_NEEDLE_N := Color(0.98, 0.42, 0.38, 0.95)
# The south half, deliberately plain. A two-tone needle is what makes the
# pointing END unambiguous; a single-colour bar would read as an axis rather
# than a direction.
const COL_NEEDLE_S := Color(0.78, 0.84, 0.92, 0.75)
# The dial's ring and its cardinal ticks.
const COL_DIAL := Color(0.35, 0.72, 1.0, 0.5)
const COL_TICK := Color(0.55, 0.78, 1.0, 0.6)

const FRAME_WIDTH := 2.0
const GRID_WIDTH := 1.0
const MARGIN := 24.0

# Sized off the SHORTER viewport edge with a floor and no ceiling, which is the
# section 9d lesson: a pixel is a count rather than a size, and a pixel CAP
# hands the smallest screen the smallest box.
const SHORT_FRACTION := 0.115
const MIN_SIZE := 76.0
const MAX_WIDTH_SHARE := 0.16

# The gap below whatever sits above it -- now the HUD's own top row rather than
# the rear-view mirror, since the pair moved to the top CENTRE. Game passes the
# measured band rather than this guessing at it.
const STACK_GAP := 10.0
# Room ABOVE the grid for the "N of 16" count. Part of this widget's own rect
# rather than text hung outside it -- a label placed at a negative offset
# reached up into the rear-view mirror when the box stacked under it, and only
# a rendered frame showed it: the RECTS did not overlap, and the TEXT did. The
# same trap the mirror hit against the maze name, and it is kept guarded here
# because the HUD's top row is now what sits above.
const HEADER_BAND := 16.0
# Wider than the letter's own font size: a band equal to the glyph height clips
# its descender and its outline against the rect edge.
const LABEL_BAND := 30.0

# The gap between the grid and the compass dial sitting beside it.
const PAIR_GAP := 14.0
# The dial is a touch smaller than the grid. The grid carries 16 regions and a
# count; the compass carries one needle, so it needs less room to be read and
# taking the same width would make the pair look like two grids.
const DIAL_FRACTION := 0.82
# How far the cardinal ticks sit in from the ring, as a share of the radius.
const TICK_INNER := 0.78
# The needle's half-length and half-width, as shares of the radius. Short of the
# ring so the tip is never confused with a tick.
const NEEDLE_REACH := 0.68
const NEEDLE_WIDE := 0.17

# Set by Game each frame. divisions of 0 means the Quadrant line is untaken and
# only the compass letter is drawn.
var divisions := 0
var here := Vector2i(-1, -1)
var start_at := Vector2i(-1, -1)
var exit_at := Vector2i(-1, -1)
var quadrant_number := 0
var quadrant_total := 0
var cardinal := ""
# The direction the racer faces, as a Maze.N/E/S/W bit. The needle needs an
# ANGLE, which the letter cannot give -- so the facing is carried rather than
# re-derived from the string, which would be a second mapping to keep in step
# with Maze.CARDINAL_NAMES.
var facing := 0

var _label: Label
var _count: Label

# Measured in place() and read by _draw(). Held rather than recomputed, so the
# two cannot disagree about where the halves are -- the drawing and the label
# placement have to land on the same columns.
var _grid_side := 0.0
var _dial_size := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# "N of 16" sits above the grid, the cardinal letter below it. The number is
	# the progress statement and the letter is the orientation one; stacking
	# them keeps both a single glance from the grid they describe.
	_count = _make_label(11, COL_LABEL)
	_count.position = Vector2(0.0, 0.0)
	add_child(_count)

	# The letter is kept alongside the needle rather than replaced by it. The
	# needle answers "which way is north" at a glance and the letter names the
	# heading exactly -- at 8x a needle a few degrees off is ambiguous where a
	# letter never is, so the two are not redundant.
	#
	# Sized and coloured well above the count. Measured in a rendered frame at
	# 15px in the label blue, it was a smudge -- and a readout the player has to
	# squint at is not one they check at speed.
	_label = _make_label(22, COL_CARDINAL)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _make_label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# `top` is the y this box hangs from -- the bottom of the HUD's top row, passed
# in rather than measured here.
#
# CENTRED horizontally, so the pair sits on the same vertical axis as the
# corridor vanishing point, the player marker and the minimap. The widget is as
# wide as the grid plus the dial beside it, and that total is what gets centred
# -- centring the grid alone would push the dial off-axis by half its own width.
func place(view: Vector2, top: float) -> void:
	var short_edge: float = min(view.x, view.y)
	var side: float = max(short_edge * SHORT_FRACTION, MIN_SIZE)
	side = min(side, view.x * MAX_WIDTH_SHARE)

	# The dial's own diameter, and the width of the whole cluster.
	var dial: float = side * DIAL_FRACTION
	var total: float = side + PAIR_GAP + dial
	# Never wider than the viewport allows, which matters on a phone where the
	# short edge is the height and `side` is a large share of a narrow screen.
	if total > view.x - MARGIN * 2.0:
		var shrink: float = (view.x - MARGIN * 2.0) / total
		side *= shrink
		dial *= shrink
		total = side + PAIR_GAP + dial

	# The grid's own height is the taller of the two columns, since it carries
	# the count band above it. The dial carries the letter band below it, so the
	# rect has to cover both or one of them is clipped -- rect clearance is not
	# text clearance, which is the trap this widget has already hit twice.
	var height: float = HEADER_BAND + side + LABEL_BAND

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = (view.x - total) * 0.5
	offset_right = offset_left + total
	offset_top = top + STACK_GAP
	offset_bottom = offset_top + height
	size = Vector2(total, height)

	_grid_side = side
	_dial_size = dial

	if _label:
		# Under the dial, centred on it. The letter belongs to the compass now
		# rather than to the widget as a whole, so it tracks the dial's column.
		_label.size = Vector2(dial, LABEL_BAND)
		_label.position = Vector2(total - dial, HEADER_BAND + side + 1.0)
	if _count:
		# Over the GRID column, not the whole rect. The count describes the grid
		# and nothing else, so hanging it off the widget's left edge keeps it on
		# the thing it counts rather than drifting toward the dial.
		_count.size = Vector2(side, HEADER_BAND)
	queue_redraw()


# Everything the box shows, in one call, so the widget never reaches back into
# the racer or the maze itself -- it is a readout, and a readout that queried
# the simulation could disagree with the frame it is drawn in.
func show_state(p_divisions: int, p_here: Vector2i, p_start: Vector2i,
		p_exit: Vector2i, p_number: int, p_total: int,
		p_cardinal: String, p_facing: int = 0) -> void:
	divisions = p_divisions
	here = p_here
	start_at = p_start
	exit_at = p_exit
	quadrant_number = p_number
	quadrant_total = p_total
	cardinal = p_cardinal
	facing = p_facing

	if _count:
		_count.text = "" if p_total <= 0 else "%d of %d" % [p_number, p_total]
	if _label:
		_label.text = p_cardinal
	queue_redraw()


func _draw() -> void:
	# Either half may be absent: the two lines are taken independently, and a
	# player holding only the Compass gets a dial with no grid beside it.
	if divisions >= 1:
		_draw_grid()
	if facing != 0:
		_draw_compass()


func _draw_grid() -> void:
	var side: float = _grid_side
	if side <= 0.0:
		return
	var step: float = side / float(divisions)
	# Everything below draws in grid space; this shifts it under the header.
	draw_set_transform(Vector2(0.0, HEADER_BAND))

	# The lit region first, so the grid lines are drawn ON TOP of the fill and
	# the highlighted cell keeps its borders. Filling over the lines instead
	# makes the lit region look like it has swallowed its own edges, which reads
	# as a rendering fault rather than a highlight.
	# Both ends are suppressed when the player is STANDING in them, because the
	# fill would sit under the outline and the two would read as one muddled
	# square -- and the occupied region is the more urgent of the two facts. The
	# count above the grid still says "1 of 16", so nothing is lost.
	if start_at.x >= 0 and start_at != here:
		draw_rect(_cell_rect(start_at, step), COL_START, false, FRAME_WIDTH)
	if exit_at.x >= 0 and exit_at != here:
		draw_rect(_cell_rect(exit_at, step), COL_EXIT, false, FRAME_WIDTH)
	if here.x >= 0:
		draw_rect(_cell_rect(here, step), COL_HERE, true)

	for i in range(1, divisions):
		var at: float = step * float(i)
		draw_line(Vector2(at, 0.0), Vector2(at, side), COL_GRID, GRID_WIDTH)
		draw_line(Vector2(0.0, at), Vector2(side, at), COL_GRID, GRID_WIDTH)

	draw_rect(Rect2(Vector2.ZERO, Vector2(side, side)), COL_FRAME, false, FRAME_WIDTH)
	draw_set_transform(Vector2.ZERO)


# A physical compass: a dial with cardinal ticks and a two-tone needle pointing
# at real north.
#
# The DIAL is fixed and the NEEDLE rotates, which is the way a hand compass
# works and the opposite of the minimap. That difference is deliberate and the
# two are answering different questions: the minimap rotates because it shows
# the corridor, and a corridor on your left must be drawn on the map's left at
# 8x (section 12). A compass shows the WORLD's orientation, so its whole value
# is that north stays where north is. A dial that rotated with the player would
# just be the letter again, drawn larger.
func _draw_compass() -> void:
	var dia: float = _dial_size
	if dia <= 0.0:
		return
	var radius: float = dia * 0.5
	# The dial's column is the right-hand one, vertically centred on the grid
	# beside it so the two read as one instrument rather than two stuck together.
	var centre := Vector2(
		size.x - radius,
		HEADER_BAND + _grid_side * 0.5)

	draw_arc(centre, radius, 0.0, TAU, 48, COL_DIAL, FRAME_WIDTH)

	# Cardinal ticks at the four compass points, in SCREEN space -- north is up,
	# always, because the dial does not move.
	for i in 4:
		var a: float = -PI * 0.5 + TAU * float(i) / 4.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(centre + dir * radius * TICK_INNER, centre + dir * radius,
			COL_TICK, GRID_WIDTH)

	# The needle. `facing` is a grid direction and north is -Y on the grid
	# (Maze.N), which is also up on screen, so the two frames agree and the
	# angle needs no correction -- the needle points where the racer points.
	#
	# Drawn as two triangles meeting at the centre so the north half can be
	# coloured differently: a single bar reads as an axis rather than a
	# direction, and which END is north is the entire question.
	var ang: float = _facing_angle()
	var tip := Vector2(cos(ang), sin(ang))
	var side_v := Vector2(-tip.y, tip.x) * radius * NEEDLE_WIDE

	draw_colored_polygon(PackedVector2Array([
		centre + tip * radius * NEEDLE_REACH,
		centre + side_v,
		centre - side_v]), COL_NEEDLE_N)
	draw_colored_polygon(PackedVector2Array([
		centre - tip * radius * NEEDLE_REACH,
		centre + side_v,
		centre - side_v]), COL_NEEDLE_S)


# The screen angle the racer faces, in radians, with -Y (north) as zero.
#
# Read from the Maze direction bit rather than from the cardinal STRING, which
# would be a second copy of Maze.CARDINAL_NAMES to keep in step.
func _facing_angle() -> float:
	match facing:
		Maze.N:
			return -PI * 0.5
		Maze.E:
			return 0.0
		Maze.S:
			return PI * 0.5
		Maze.W:
			return PI
	return -PI * 0.5


func _cell_rect(coord: Vector2i, step: float) -> Rect2:
	return Rect2(
		Vector2(float(coord.x) * step, float(coord.y) * step),
		Vector2(step, step))
