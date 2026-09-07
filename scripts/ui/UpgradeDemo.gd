# One animated diagram demonstrating one upgrade line.
#
# A Control that DRAWS ITSELF in 2D. Deliberately not a SubViewport with a real
# Racer in it: MarkerPicker can afford a 3D preview because it previews one
# object, where this screen has an entry per upgrade line and a real racer would
# need a real Maze -- dragging the simulation into a menu screen. CLAUDE.md
# section 12 says the simulation must never require a rendered frame; the inverse
# holds here.
#
# The DEMOS table is a TABLE, never a parallel array indexed by line number --
# the failure section 6 records for landmark density and 9c for music tracks.
# Each entry names its line and carries its own parameters, so adding an upgrade
# is a table entry rather than an edit in several places, and RulesTest asserts
# that a line with no entry is a FAILURE rather than a blank box.
class_name UpgradeDemo
extends Control

# The ways a mechanic can be shown. Every line uses exactly one.
#
# A line with no visible on-screen effect -- Cornering, Wall Armor, Score
# Multiplier -- gets a BAR rather than an invented animation. Motion drawn for a
# mechanic that has none is the HUD-chevron mistake of section 7: a picture
# pulling the eye somewhere the mechanic is not.
enum Kind {
	CORRIDOR,   # a marker travelling a corridor, with per-line overlays
	BAR,        # rank 0 against max, labelled, with units
	GAUGE,      # a draining pool with a threshold
	PANEL,      # a mock of the HUD element the line adds
	STILL,      # one composed frame with callouts
}

const KINDS := [Kind.CORRIDOR, Kind.BAR, Kind.GAUGE, Kind.PANEL, Kind.STILL]

# What each corridor demo overlays on the shared corridor drawing. The corridor
# itself -- walls, grid lines, marker -- is drawn once by _draw_corridor_base();
# an overlay is the only thing that varies. A dozen copies of the corridor code
# would be the parallel-array trap in different clothes.
enum Overlay {
	NONE,
	ARMED_TURN,     # the press, the buffer window, where the turn lands
	STRIP,          # Path Indicator's green/yellow/red floor strips
	RIBBON,         # a trail running ahead of the marker
	FREEZE,         # the post-turn hold
	REVERSE,        # a 180 in place
	TRAIL_TINT,     # ground tinted by visit count
	COMPASS_ARROW,  # an arrow toward a gate
	GATE,           # a gate marker and its collection footprint
	SMASH,          # a wall breaking
	AUTOPILOT,      # the router steering
	EXPIRY,         # a press that finds no opening and expires
}

const DEMOS := {
	Upgrades.Line.PATH_INDICATOR: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.STRIP,
		"caption": "A lit strip across the mouth of each opening: green is the best route, yellow is longer but works, red leads nowhere.",
	},
	Upgrades.Line.MINIMAP: {
		"kind": Kind.PANEL,
		"panel": "minimap",
		"caption": "A circular map around you, rotated so the way you face is always up. Each rank widens it.",
	},
	Upgrades.Line.BUFFER_WINDOW: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.ARMED_TURN,
		"caption": "Press early and the turn stays armed until an opening arrives. Measured in cells, so forgiveness does not shrink as you speed up.",
	},
	Upgrades.Line.FAST_TURNAROUND: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.REVERSE,
		"caption": "A 180 costs speed. This makes backtracking out of a misread cheap enough to be a real option.",
	},
	Upgrades.Line.BASE_SPEED: {
		"kind": Kind.BAR,
		"bar": "speed_floor",
		"caption": "Raises the speed you can never drop below, so a crash costs you less of the climb back.",
	},
	Upgrades.Line.BARRIER_CAPACITY: {
		"kind": Kind.GAUGE,
		"gauge": "barrier",
		"caption": "How long you may hold a wall before it becomes a crash. The base is an eighth of a second; one rank triples it.",
	},
	Upgrades.Line.BARRIER_REGEN: {
		"kind": Kind.BAR,
		"bar": "barrier_regen",
		"caption": "How fast the barrier refills between scrapes. Without it, consecutive brushes compound.",
	},
	Upgrades.Line.GATE_COMPASS: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.COMPASS_ARROW,
		"caption": "An arrow pointing at the next gate, relative to the way you face. Always on.",
	},
	Upgrades.Line.WALL_ARMOR: {
		"kind": Kind.BAR,
		"bar": "wall_damage",
		"caption": "Each rank takes a flat point off every crash, on every maze -- it subtracts after the per-maze scaling.",
	},
	Upgrades.Line.GOLDEN_TRAIL: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.RIBBON,
		"ribbon_color": Color(1.0, 0.78, 0.25),
		"caption": "On a timer, a gold streak runs the whole route to the nearest gate you have not taken.",
	},
	Upgrades.Line.PLATINUM_TRAIL: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.RIBBON,
		"ribbon_color": Color(0.85, 0.89, 0.96),
		"caption": "The same in silver, running the shortest way OUT -- but only once five gates are banked.",
	},
	Upgrades.Line.SNAP_TURN: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.FREEZE,
		"caption": "Corners hold you still for a beat so you can read the new corridor. This shortens the hold, never removing it.",
	},
	Upgrades.Line.CORNERING: {
		"kind": Kind.BAR,
		"bar": "turn_cost",
		"caption": "Cuts what each turn costs in speed, so a turn-heavy route stops bleeding you dry.",
	},
	Upgrades.Line.EXPIRY_GRACE: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.EXPIRY,
		"caption": "A press that never finds its opening expires into a slowdown. This shrinks that penalty, never to nothing.",
	},
	Upgrades.Line.HP_REGEN: {
		"kind": Kind.BAR,
		"bar": "hp_regen",
		"caption": "Restores health for every second of clean travel. It cannot be farmed: nothing regenerates while parked or scraping.",
	},
	Upgrades.Line.SCORE_BONUS: {
		"kind": Kind.BAR,
		"bar": "score_mult",
		"caption": "More points for everything you earn, applied before the time bonus -- so it compounds with routing well.",
	},
	Upgrades.Line.QUADRANT: {
		"kind": Kind.PANEL,
		"panel": "quadrant",
		"caption": "Splits the maze into regions and lights the one you are in. Quadrant 1 holds the start; the highest holds the exit.",
	},
	Upgrades.Line.COMPASS: {
		"kind": Kind.PANEL,
		"panel": "compass",
		"caption": "The direction you face, as N/E/S/W. North is really north -- the exit lies south-east.",
	},
	Upgrades.Line.TRAIL_MEMORY: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.TRAIL_TINT,
		"caption": "Ground you have driven is tinted: lit on the first pass, darker with every re-crossing. It answers where you have been, never which way to go.",
	},
	Upgrades.Line.MOMENTUM: {
		"kind": Kind.BAR,
		"bar": "momentum",
		"caption": "Speed climbs faster -- but any wall contact loses the bonus, and it rebuilds over a few seconds of clean driving.",
	},
	Upgrades.Line.SECOND_WIND: {
		"kind": Kind.GAUGE,
		"gauge": "second_wind",
		"caption": "Bank a crash. The barrier emptying spends a charge instead of stopping you, and clearing a gate refills it.",
	},
	Upgrades.Line.DEEP_BREATH: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.FREEZE,
		"extends_freeze": true,
		"caption": "Hold the turn key through a corner to stay still longer and read ahead. The speed ramp pauses, so what you spend is the clock.",
	},
	Upgrades.Line.OVERCLOCK: {
		"kind": Kind.BAR,
		"bar": "overclock",
		"caption": "Hold a direction, then DOWN: burn health for a burst of speed. It floors at 1 HP, so it can never kill you.",
	},
	Upgrades.Line.GATE_SIZE: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.GATE,
		"caption": "Taller gates you can see coming, then a wider collection footprint -- so a parallel corridor can bank the pick.",
	},
	Upgrades.Line.EXTRA_CARD: {
		"kind": Kind.PANEL,
		"panel": "cards",
		"caption": "More cards at every pick from now on. The cost is the pick itself, so it is only worth taking early.",
	},
	Upgrades.Line.WALL_SMASHER: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.SMASH,
		"caption": "LEGENDARY. Crash through the wall instead of stopping, keeping your speed. The wall is destroyed and the route rebuilt around the hole.",
	},
	Upgrades.Line.FLYING_VISION: {
		"kind": Kind.STILL,
		"still": "flying_vision",
		"caption": "LEGENDARY. Double-tap DOWN to stop the clock and rise above the maze for five seconds, then a countdown back in.",
	},
	Upgrades.Line.AUTO_STEER: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.AUTOPILOT,
		"caption": "LEGENDARY. Double-tap DOWN to be driven down the best route at double speed, untouchable while it runs.",
	},
}

const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.55, 0.62, 0.75)

# The demo's own palette. Deliberately cyan-family rather than per-maze: this is
# a reference screen, not a maze, and a demo that recoloured itself would imply
# the mechanic differs by maze when it does not.
const COL_WALL := Color(0.16, 0.55, 0.75)
const COL_GRID := Color(0.20, 0.42, 0.55)
const COL_MARKER := Color(0.95, 0.97, 1.0)
const COL_GHOST := Color(0.45, 0.55, 0.68, 0.6)

# The demo corridor, in cells. Small enough that a cell is large on screen -- the
# point is to show one mechanic clearly, not to show a maze.
const DEMO_CELLS := 6

# One loop of every animation. Shared so a player moving down the list is not
# watching things at unrelated tempos.
const LOOP_SECONDS := 4.0

# The line this demo draws. Set by the compendium before the node is shown.
var line: int = -1

# Seconds since the demo started. Every animation is a function of this, so a
# demo has no state of its own to get out of step.
var _clock := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func set_line(value: int) -> void:
	if value == line:
		return
	line = value
	# Restarted so a demo always begins at the top of its loop. Landing
	# mid-animation makes a one-shot demo -- the smash, the expiry -- look like
	# it is missing its first half.
	_clock = 0.0
	queue_redraw()


# Phase through the loop, 0..1.
func _phase() -> float:
	return fmod(_clock, LOOP_SECONDS) / LOOP_SECONDS


# The corridor's cell size in pixels, DERIVED from the box rather than fixed --
# the bubble resizes with the screen, and a fixed cell size would be correct at
# one window size only. Section 9d's lesson: a pixel is a count, not a size.
func _cell_px() -> float:
	return minf(size.x / float(DEMO_CELLS + 1), size.y * 0.34)


func _font() -> Font:
	return ThemeDB.fallback_font


func _font_px() -> int:
	return int(maxf(11.0, size.y * 0.095))


func _draw() -> void:
	if line == -1 or not DEMOS.has(line):
		return
	var entry: Dictionary = DEMOS[line]
	match int(entry["kind"]):
		Kind.CORRIDOR:
			_draw_corridor_base()
			_draw_overlay(int(entry.get("overlay", Overlay.NONE)), entry)
		Kind.BAR:
			_draw_bar(String(entry.get("bar", "")))
		Kind.GAUGE:
			_draw_gauge(String(entry.get("gauge", "")))
		Kind.PANEL:
			_draw_panel(String(entry.get("panel", "")))
		Kind.STILL:
			_draw_still(String(entry.get("still", "")))


func _origin(rows: int = 1) -> Vector2:
	var cell := _cell_px()
	return Vector2((size.x - cell * DEMO_CELLS) * 0.5,
		(size.y - cell * rows) * 0.5)


func _draw_corridor_base(rows: int = 1) -> void:
	var cell := _cell_px()
	var origin := _origin(rows)

	draw_rect(Rect2(origin, Vector2(cell * DEMO_CELLS, cell * rows)),
		Color(0.04, 0.06, 0.10), true)

	# Cell boundaries. These are the timing contract (section 11.3) and stay the
	# most legible marking on the floor -- the same rule the game's own floor
	# obeys, for the same reason: every demo about timing is read against them.
	for i in range(DEMO_CELLS + 1):
		var x := origin.x + cell * i
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + cell * rows),
			COL_GRID, 2.0)

	draw_line(origin, origin + Vector2(cell * DEMO_CELLS, 0.0), COL_WALL, 3.0)
	draw_line(origin + Vector2(0.0, cell * rows),
		origin + Vector2(cell * DEMO_CELLS, cell * rows), COL_WALL, 3.0)


func _marker_pos(cells_along: float, rows: int = 1) -> Vector2:
	var cell := _cell_px()
	return _origin(rows) + Vector2(cell * cells_along, cell * rows * 0.5)


# The marker: a ring with a pointer, the same two-part shape the game draws, so
# a player recognises it.
func _draw_marker(at: Vector2, facing: Vector2,
		colour: Color = COL_MARKER) -> void:
	var r := _cell_px() * 0.22
	draw_arc(at, r, 0.0, TAU, 24, colour, 2.5)
	var dir := facing.normalized()
	var tip := at + dir * r * 0.95
	var back := at - dir * r * 0.45
	var side := Vector2(-dir.y, dir.x) * r * 0.55
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]),
		colour)


# --- BAR ---------------------------------------------------------------------

# Two bars, rank 0 against max, with the units named.
#
# This is what a line with no on-screen effect gets. Cornering, Wall Armor and
# Score Multiplier change a number and nothing else, and an animation invented
# for them would claim a visible mechanic that does not exist.
func _draw_bar(which: String) -> void:
	var lo := _stat_at_rank(which, 0)
	var hi := _stat_at_rank(which, _max_rank())
	var peak: float = maxf(maxf(float(lo["value"]), float(hi["value"])), 0.0001)

	# The bars sit in the MIDDLE THIRD, with the label to their left and the
	# value to their right -- both outside the bar rather than over it. Drawn
	# inside, the labels overlapped the fill and read as part of it, which only
	# a rendered frame showed.
	var bar_h := size.y * 0.17
	var gap := size.y * 0.16
	var left := size.x * 0.30
	var span := size.x * 0.38
	var top := (size.y - bar_h * 2.0 - gap) * 0.5

	# Animate the max bar filling, so the panel has motion where the mechanic
	# does not -- but the motion IS the comparison, not a fake corridor.
	var grow := clampf(_phase() * 2.4, 0.0, 1.0)

	_draw_labelled_bar(
		Rect2(left, top, span * (float(lo["value"]) / peak), bar_h),
		"no ranks", String(lo["text"]), COL_GHOST)
	_draw_labelled_bar(
		Rect2(left, top + bar_h + gap,
			span * (float(hi["value"]) / peak) * grow, bar_h),
		"max rank", String(hi["text"]), COL_ACCENT)


func _draw_labelled_bar(rect: Rect2, label: String, value: String,
		colour: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(maxf(rect.size.x, 2.0),
		rect.size.y)), colour, true)
	var fs := _font_px()
	var baseline := rect.position.y + rect.size.y * 0.72
	# Right-aligned into the space BEFORE the bar starts, so a longer label
	# grows away from the fill rather than over it.
	draw_string(_font(), Vector2(0.0, baseline), label,
		HORIZONTAL_ALIGNMENT_RIGHT, size.x * 0.30 - 12.0, fs, COL_DIM)
	draw_string(_font(), Vector2(size.x * 0.70, baseline), value,
		HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.30, fs, colour)


# The value a stat takes at a given rank, with the text to print beside it.
#
# Built by taking a REAL Upgrades to that rank and asking it, never by reading a
# tuning table directly and never by writing the number here. Fast Turnaround's
# card text had already drifted a whole retune before anyone noticed (section 7);
# this screen must not repeat that.
func _stat_at_rank(which: String, rank: int) -> Dictionary:
	var up := Upgrades.new(1)
	for _i in range(rank):
		up.take(line)

	match which:
		"speed_floor":
			return {"value": up.speed_floor(),
				"text": "%.2fx floor" % up.speed_floor()}
		"barrier_regen":
			return {"value": up.barrier_regen(),
				"text": "%.2f / sec" % up.barrier_regen()}
		"wall_damage":
			# Shown on maze 5, where armor matters most and the curve is
			# steepest. The maze is a parameter rather than state, exactly as
			# Upgrades.wall_damage documents.
			var dmg := up.wall_damage(4)
			return {"value": float(dmg), "text": "%d damage" % dmg}
		"turn_cost":
			return {"value": up.turn_cost(),
				"text": "%.3fx per turn" % up.turn_cost()}
		"hp_regen":
			return {"value": up.hp_regen(),
				"text": "%.1f HP / sec" % up.hp_regen()}
		"score_mult":
			return {"value": up.score_multiplier(),
				"text": "%.2fx points" % up.score_multiplier()}
		"momentum":
			return {"value": up.momentum_ramp_scale(),
				"text": "%.2fx ramp" % up.momentum_ramp_scale()}
		"overclock":
			var burn := up.overclock_hp_per_sec()
			return {"value": burn,
				"text": "not held" if burn <= 0.0 else "%.1f HP / sec" % burn}
	return {"value": 0.0, "text": ""}


func _max_rank() -> int:
	return int(Upgrades.DEFINITIONS[line]["max_rank"])


# --- GAUGE -------------------------------------------------------------------

func _draw_gauge(which: String) -> void:
	var p := _phase()
	# Drain over the first 40% of the loop, hold, then refill -- the shape a
	# barrier actually has in play.
	var fill := 1.0 - clampf(p / 0.4, 0.0, 1.0)
	if p > 0.6:
		fill = clampf((p - 0.6) / 0.4, 0.0, 1.0)

	var w := size.x * 0.58
	var h := size.y * 0.22
	var at := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5 - size.y * 0.08)
	draw_rect(Rect2(at, Vector2(w, h)), Color(0.10, 0.13, 0.18), true)
	var colour := COL_ACCENT if fill > 0.35 else Color(0.95, 0.35, 0.30)
	draw_rect(Rect2(at, Vector2(w * fill, h)), colour, true)
	draw_rect(Rect2(at, Vector2(w, h)), COL_DIM, false, 2.0)

	var fs := _font_px()
	var caption := "wall contact drains it"
	if fill <= 0.001:
		caption = "empty -- you crash"
		if which == "second_wind":
			caption = "empty -- a banked charge is spent instead"
	elif which == "second_wind":
		caption = "one charge per rank"
	draw_string(_font(), at + Vector2(0.0, h + fs * 1.8), caption,
		HORIZONTAL_ALIGNMENT_CENTER, w, fs, COL_DIM)


# --- PANEL -------------------------------------------------------------------

func _draw_panel(which: String) -> void:
	var box := Vector2(size.x * 0.30, size.y * 0.56)
	var y := (size.y - box.y) * 0.5 - size.y * 0.05
	_draw_panel_box(Rect2(Vector2(size.x * 0.12, y), box), which, 0)
	_draw_panel_box(Rect2(Vector2(size.x * 0.58, y), box), which, _max_rank())


func _draw_panel_box(rect: Rect2, which: String, rank: int) -> void:
	draw_rect(rect, Color(0.05, 0.07, 0.11), true)
	draw_rect(rect, COL_DIM if rank == 0 else COL_ACCENT, false, 2.0)
	var fs := _font_px()
	draw_string(_font(), rect.position + Vector2(0.0, rect.size.y + fs * 1.5),
		"without it" if rank == 0 else "at max rank",
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs,
		COL_DIM if rank == 0 else COL_ACCENT)

	if rank == 0 and which != "cards" and which != "quadrant":
		return

	match which:
		"minimap":
			var c := rect.position + rect.size * 0.5
			var radius := minf(rect.size.x, rect.size.y) * 0.38
			draw_arc(c, radius, 0.0, TAU, 32, COL_ACCENT, 2.0)
			for i in range(6):
				var a := TAU * float(i) / 6.0 + _phase() * 0.6
				draw_line(c + Vector2(cos(a), sin(a)) * radius * 0.35,
					c + Vector2(cos(a), sin(a)) * radius * 0.82,
					COL_WALL, 2.0)
			_draw_marker(c, Vector2.UP)
		"quadrant":
			if rank == 0:
				return
			var n := 4 if rank >= 3 else (3 if rank == 2 else 2)
			var lit := int(_phase() * float(n * n))
			var cw := rect.size.x / float(n)
			var ch := rect.size.y / float(n)
			for i in range(n * n):
				var cell := Rect2(
					rect.position + Vector2(cw * float(i % n),
						ch * float(i / n)),
					Vector2(cw, ch))
				draw_rect(cell, COL_ACCENT if i == lit \
					else Color(0.12, 0.16, 0.22), true)
				draw_rect(cell, Color(0.05, 0.07, 0.11), false, 1.0)
		"compass":
			var dirs := ["N", "E", "S", "W"]
			var idx := int(_phase() * 4.0) % 4
			draw_string(_font(),
				rect.position + Vector2(0.0, rect.size.y * 0.64),
				dirs[idx], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x,
				int(rect.size.y * 0.40), COL_MARKER)
		"cards":
			var count := Tuning.CARDS_PER_GATE if rank == 0 \
				else int(Tuning.CARDS_BY_EXTRA_RANK[
					mini(rank, Tuning.CARDS_BY_EXTRA_RANK.size() - 1)])
			var pad := rect.size.x * 0.07
			var cw2 := (rect.size.x - pad * float(count + 1)) / float(count)
			for i in range(count):
				draw_rect(Rect2(
					rect.position + Vector2(pad + (cw2 + pad) * float(i),
						rect.size.y * 0.22),
					Vector2(cw2, rect.size.y * 0.56)),
					COL_ACCENT if rank > 0 else COL_GHOST, false, 2.0)


# --- STILL -------------------------------------------------------------------

# One composed frame with a callout. Flying Vision only: the ability IS a static
# overhead view, so animating it would misrepresent it.
func _draw_still(_which: String) -> void:
	var cell := _cell_px() * 0.62
	var origin := Vector2((size.x - cell * 6.0) * 0.5,
		(size.y - cell * 4.0) * 0.5 - size.y * 0.06)
	for gx in range(7):
		draw_line(origin + Vector2(cell * float(gx), 0.0),
			origin + Vector2(cell * float(gx), cell * 4.0), COL_GRID, 1.5)
	for gy in range(5):
		draw_line(origin + Vector2(0.0, cell * float(gy)),
			origin + Vector2(cell * 6.0, cell * float(gy)), COL_GRID, 1.5)
	_draw_marker(origin + Vector2(cell * 1.5, cell * 2.5), Vector2.RIGHT)
	var fs := _font_px()
	draw_string(_font(), origin + Vector2(0.0, cell * 4.0 + fs * 1.8),
		"the clock is stopped while you look",
		HORIZONTAL_ALIGNMENT_CENTER, cell * 6.0, fs, COL_DIM)


# --- CORRIDOR OVERLAYS -------------------------------------------------------

func _draw_overlay(overlay: int, entry: Dictionary) -> void:
	var p := _phase()
	var fs := _font_px()
	var cell := _cell_px()

	match overlay:
		Overlay.ARMED_TURN:
			# The press happens early; the buffer keeps it live; the turn lands
			# at the opening. Showing the WINDOW is the whole point -- the
			# buffer is invisible in play and this is the only place it can be
			# seen.
			var travel := p * float(DEMO_CELLS)
			var press_at := 1.5
			var opening := 4.0
			if travel >= press_at:
				draw_rect(Rect2(
					_marker_pos(press_at) - Vector2(0.0, cell * 0.5),
					Vector2(cell * (opening - press_at), cell)),
					Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.16),
					true)
				draw_string(_font(),
					_marker_pos(press_at) + Vector2(0.0, -cell * 0.66),
					"pressed -- still armed", HORIZONTAL_ALIGNMENT_LEFT,
					-1.0, fs, COL_ACCENT)
			var facing := Vector2.RIGHT if travel < opening else Vector2.UP
			_draw_marker(_marker_pos(minf(travel, opening)), facing)
		Overlay.STRIP:
			var cols := [Color(0.2, 0.95, 0.4), Color(0.95, 0.85, 0.25),
				Color(0.95, 0.3, 0.25)]
			var names := ["best", "works", "dead end"]
			for i in range(3):
				var x := 1.6 + float(i) * 1.5
				# Only GREEN pulses. Motion is the strongest signal in
				# peripheral vision, so spending it on the one best answer is
				# what makes that gap findable without being looked at (7).
				var pulse: float = 0.55 + 0.45 * sin(_clock * 4.0) \
					if i == 0 else 1.0
				var c: Color = cols[i]
				draw_rect(Rect2(
					_marker_pos(x) - Vector2(cell * 0.07, cell * 0.5),
					Vector2(cell * 0.14, cell)),
					Color(c.r, c.g, c.b, pulse), true)
				# A box wider than one cell: "dead end" is wider than the cell
				# it labels and came back clipped to "dead e".
				draw_string(_font(),
					_marker_pos(x) + Vector2(-cell * 0.8, -cell * 0.62),
					names[i], HORIZONTAL_ALIGNMENT_CENTER, cell * 1.6, fs, c)
			_draw_marker(_marker_pos(0.7), Vector2.RIGHT)
		Overlay.RIBBON:
			var col: Color = entry.get("ribbon_color", COL_ACCENT)
			var head: float = clampf(p * 2.2, 0.0, 1.0) * float(DEMO_CELLS - 1)
			draw_line(_marker_pos(0.5), _marker_pos(maxf(head, 0.5)),
				col, cell * 0.16)
			_draw_marker(_marker_pos(0.5), Vector2.RIGHT)
		Overlay.FREEZE:
			# The marker reaches the corner, holds, then turns. Deep Breath
			# holds longer, which is the whole difference between the two lines.
			var hold: float = 0.45 if bool(entry.get("extends_freeze", false)) \
				else 0.20
			var pos := 3.0
			var facing2 := Vector2.UP
			if p < 0.4:
				pos = p / 0.4 * 3.0
				facing2 = Vector2.RIGHT
			elif p < 0.4 + hold:
				draw_string(_font(),
					_marker_pos(3.0) + Vector2(-cell * 1.5, -cell * 0.66),
					"held -- read the new corridor",
					HORIZONTAL_ALIGNMENT_CENTER, cell * 3.0, fs, COL_ACCENT)
			_draw_marker(_marker_pos(pos), facing2)
		Overlay.REVERSE:
			var facing3 := Vector2.RIGHT if p < 0.5 else Vector2.LEFT
			var pos2: float = p * 6.0 if p < 0.5 else (1.0 - p) * 6.0
			_draw_marker(_marker_pos(clampf(pos2, 0.4, float(DEMO_CELLS) - 0.4)),
				facing3)
			if p >= 0.45 and p < 0.62:
				draw_string(_font(),
					_marker_pos(3.0) + Vector2(-cell * 1.5, -cell * 0.66),
					"180 -- costs speed", HORIZONTAL_ALIGNMENT_CENTER,
					cell * 3.0, fs, Color(0.95, 0.6, 0.3))
		Overlay.TRAIL_TINT:
			# Lit on the first pass, darker with every re-crossing.
			for i in range(DEMO_CELLS):
				var visits := 1 if i < 3 else (3 if i < 5 else 0)
				if visits == 0:
					continue
				var tint := Color(0.35, 0.75, 0.95, 0.5) if visits == 1 \
					else Color(0.09, 0.12, 0.18, 0.9)
				draw_rect(Rect2(
					_origin() + Vector2(cell * float(i), 0.0),
					Vector2(cell, cell)), tint, true)
			draw_string(_font(), _origin() + Vector2(0.0, -cell * 0.18),
				"driven once", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
				Color(0.35, 0.75, 0.95))
			draw_string(_font(),
				_origin() + Vector2(cell * 3.1, -cell * 0.18),
				"re-crossed", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, COL_DIM)
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT)
		Overlay.COMPASS_ARROW:
			var at := _marker_pos(2.0)
			_draw_marker(at, Vector2.RIGHT)
			var a := sin(_clock * 0.9) * 0.5 - 0.7
			draw_line(at, at + Vector2(cos(a), sin(a)) * cell * 0.95,
				Color(0.95, 0.75, 0.2), 3.0)
			draw_string(_font(), _marker_pos(4.2) + Vector2(0.0, -cell * 0.2),
				"next gate", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
				Color(0.95, 0.75, 0.2))
		Overlay.GATE:
			# The footprint is the mechanic: a wide gate straddles a wall, so a
			# parallel corridor can bank the pick.
			var gate_at := 3.5
			var wide := p > 0.5
			if wide:
				for dx in [-1.0, 0.0, 1.0]:
					draw_rect(Rect2(
						_origin() + Vector2(cell * (gate_at + dx - 0.5), 0.0),
						Vector2(cell, cell)),
						Color(0.95, 0.8, 0.25, 0.20), true)
			draw_rect(Rect2(
				_marker_pos(gate_at) - Vector2(cell * 0.07, cell * 0.5),
				Vector2(cell * 0.14, cell)), Color(0.95, 0.8, 0.25), true)
			draw_string(_font(),
				_marker_pos(gate_at) + Vector2(-cell * 1.0, -cell * 0.66),
				"wider footprint" if wide else "one cell",
				HORIZONTAL_ALIGNMENT_CENTER, cell * 2.0, fs, COL_DIM)
			_draw_marker(_marker_pos(1.0), Vector2.RIGHT)
		Overlay.SMASH:
			var wall_at := 3.5
			var broken := p > 0.5
			if not broken:
				draw_line(_marker_pos(wall_at) - Vector2(0.0, cell * 0.5),
					_marker_pos(wall_at) + Vector2(0.0, cell * 0.5),
					COL_WALL, 5.0)
			else:
				draw_line(_marker_pos(wall_at) - Vector2(0.0, cell * 0.5),
					_marker_pos(wall_at) - Vector2(0.0, cell * 0.22),
					COL_WALL, 5.0)
				draw_line(_marker_pos(wall_at) + Vector2(0.0, cell * 0.22),
					_marker_pos(wall_at) + Vector2(0.0, cell * 0.5),
					COL_WALL, 5.0)
				draw_string(_font(),
					_marker_pos(wall_at) + Vector2(-cell, -cell * 0.66),
					"through, at speed", HORIZONTAL_ALIGNMENT_CENTER,
					cell * 2.0, fs, Color(0.95, 0.6, 0.3))
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT)
		Overlay.AUTOPILOT:
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT,
				Color(0.5, 0.9, 1.0))
			draw_string(_font(), _origin() + Vector2(0.0, -cell * 0.18),
				"driven for you, untouchable", HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, fs, COL_ACCENT)
		Overlay.EXPIRY:
			draw_string(_font(),
				_marker_pos(1.0) + Vector2(-cell * 0.5, -cell * 0.66),
				"pressed", HORIZONTAL_ALIGNMENT_CENTER, cell, fs, COL_ACCENT)
			if p > 0.55:
				draw_string(_font(),
					_marker_pos(4.0) + Vector2(-cell, -cell * 0.66),
					"no opening -- slowdown", HORIZONTAL_ALIGNMENT_CENTER,
					cell * 2.0, fs, Color(0.95, 0.5, 0.3))
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT)
		_:
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT)
