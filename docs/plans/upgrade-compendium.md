# Upgrade Compendium Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A browsable in-game screen listing every upgrade line with an animated
diagram demonstrating what the mechanic actually does, reached from an UPGRADES
button on the main menu.

**Architecture:** One new `Control` (`UpgradeCompendium`) built on the
`MarkerPicker` template — full-screen scrim, panel, `closed` signal, opened and
freed by `MainMenu`. The line list is read live from `Upgrades.DEFINITIONS` so it
can never drift from the cards. Each demo is a **2D `Control` that draws itself**
from a table entry naming a draw function, not a 3D scene and not 28 hand-written
widgets — the same "a table, never a parallel array" rule §6 states for landmark
density and §9c for music tracks.

**Tech Stack:** Godot 4.7, GDScript. No new assets, no new autoloads, no network.

---

## Why these decisions, before any code

Four constraints this plan is built around. An implementer who changes one of
these is changing the design, not the implementation.

**1. The list is read from `Upgrades.DEFINITIONS`, never restated.** §12 records
that a test restating a tuning number is a transcription check; a *screen*
restating one is worse, because the player reads it and picks on it. Names, rank
counts and per-rank text all come from `Upgrades`, including the derived
descriptions `next_rank_description()` builds for Fast Turnaround, both trails,
Trail Memory, Momentum, Deep Breath, Overclock and Extra Card. A line added to
`DEFINITIONS` appears here with no edit.

**2. Demos are 2D, drawn in code.** The alternative — a live `SubViewport` with a
real `Racer` per demo, the `MarkerPicker` approach — was rejected. That screen
previews **one** object and can afford a 3D turntable; this one has 28 entries,
and a real racer would need a real `Maze`, which drags the whole simulation into
a menu screen. §12's rule is that the simulation layer must never require a
rendered frame, and the inverse holds here: a cosmetic screen must not require
the simulation.

**3. A demo answers "what does this line change", not "what number does it set".**
Several lines have no visible on-screen effect at all — Cornering, Wall Armor,
Score Multiplier, Base Speed. Those get a **quantity diagram** (a labelled bar
comparing rank 0 against max) rather than a fake animation. Inventing motion for
a line that has none would be the HUD-chevron mistake of §7: a picture that draws
the eye somewhere the mechanic is not.

**4. Nothing in the simulation may read the compendium.** Same separation
landmarks (§6), music (§9c), touch controls (§9d) and the marker picker (§12)
have. It reads `Upgrades` and `Tuning`; nothing reads it.

---

## Demo kinds

Every line maps to exactly one of five draw kinds. This is the whole taxonomy —
an implementer adding a line picks one of these rather than writing a 29th
special case.

| Kind | What it draws | Lines using it |
|---|---|---|
| `CORRIDOR` | A top-down corridor with a marker travelling it, looping. Overlays vary per line. | Path Indicator, Buffer Window, Fast Turnaround, Snap Turn, Deep Breath, Golden Trail, Platinum Trail, Trail Memory, Gate Compass, Gate Size, Wall Smasher, Auto-Steer, Expiry Grace |
| `BAR` | Two labelled bars, rank 0 against max rank, with the units named. | Base Speed, Cornering, Score Multiplier, Wall Armor, Barrier Regen, Momentum, Overclock, Repair Field |
| `GAUGE` | A draining/refilling pool with a threshold marker. | Barrier Capacity, Second Wind |
| `PANEL` | A mock of the HUD element the line adds, at rank 0 and max. | Minimap, Quadrant, Compass, Extra Card |
| `STILL` | A single composed frame with callouts, no motion. | Flying Vision |

**`CORRIDOR` is one function with per-line parameters, not thirteen functions.**
The corridor, grid lines, walls and marker are drawn once; a line supplies what
to overlay on it (a strip, a ribbon, an armed-turn indicator) and how the marker
behaves. Thirteen copies of the corridor drawing is the parallel-array trap
wearing different clothes.

---

## File structure

- **Create `scripts/ui/UpgradeCompendium.gd`** — the screen. Scrim, panel, the
  scrolling line list, and the bubble that follows the focused row. Owns focus,
  keyboard navigation, bubble placement and the `closed` signal. Does no drawing
  of demos.
- **Create `scripts/ui/UpgradeDemo.gd`** — one `Control` that draws one demo. Owns
  the five draw kinds, the animation clock, and the `DEMOS` table mapping each
  `Upgrades.Line` to its kind and parameters. This is where every drawing decision
  lives.
- **Modify `scripts/ui/MainMenu.gd`** — an `UPGRADES` button, its open/close
  handlers, and its name added to `PHONE_HIDDEN`.
- **Modify `scripts/core/RulesTest.gd`** — assert the `DEMOS` table's shape:
  total coverage of `Upgrades.Line`, valid kinds, and that it reads nothing the
  rules depend on.
- **Modify `scripts/core/ShellTest.gd`** — assert the button opens and closes the
  screen, that the screen covers every line, and that the bubble stays inside the
  panel at **both ends** of the list.
- **Create `scripts/ui/CompendiumShot.gd`** — the picture half. Renders one frame
  per demo kind, plus the first and last rows, which is where bubble placement
  fails.

---

## Task 1: The demo table and its shape assertion

The table comes first, and its test comes before it, because everything else
reads it.

**Files:**
- Create: `scripts/ui/UpgradeDemo.gd`
- Modify: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

Add to `scripts/core/RulesTest.gd`. Register it in the list of `_test_*` calls at
the top of `_run()`, beside `_test_marker_shapes()`.

```gdscript
# The compendium's demo table (docs/plans/upgrade-compendium.md).
#
# Asserts the table's SHAPE, never its contents -- the same division
# _test_marker_shapes() draws. What matters is that every upgrade line has
# exactly one demo, that every demo names a kind the drawer implements, and that
# a line added to Upgrades.DEFINITIONS cannot silently arrive with no demo. What
# a given demo looks like is a rendered-frame question (CompendiumShot).
func _test_demo_table() -> void:
	var kinds := UpgradeDemo.KINDS

	# Every line in DEFINITIONS has a demo. This is the assertion that fails
	# when someone adds an upgrade line and forgets this screen -- which is the
	# whole reason the table is checked rather than trusted.
	for line in Upgrades.DEFINITIONS:
		check("demo table covers %s" % Upgrades.DEFINITIONS[line]["name"],
			UpgradeDemo.DEMOS.has(line))

	# And no demo describes a line that does not exist.
	for line in UpgradeDemo.DEMOS:
		check("demo %d names a real line" % line,
			Upgrades.DEFINITIONS.has(line))

	# Every demo names a kind the drawer actually implements. A typo'd kind
	# would draw an empty box, which reads as the demo being unwired rather
	# than as a bad table entry.
	for line in UpgradeDemo.DEMOS:
		var entry: Dictionary = UpgradeDemo.DEMOS[line]
		check("demo for %s names a kind" % Upgrades.DEFINITIONS[line]["name"],
			entry.has("kind"))
		check("demo for %s has a valid kind" % Upgrades.DEFINITIONS[line]["name"],
			int(entry.get("kind", -1)) in kinds)
		# Every demo carries a one-line summary of the mechanic, which is what
		# the bubble prints under the diagram. Derived text from
		# Upgrades covers the NUMBERS; this covers the idea.
		check("demo for %s has a caption" % Upgrades.DEFINITIONS[line]["name"],
			String(entry.get("caption", "")).strip_edges() != "")
```

- [ ] **Step 2: Run the test and verify it fails**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: a parse error naming `UpgradeDemo` as an undeclared identifier, because
the class does not exist yet. That is the correct failure at this step.

> Note the §12 trap: a new `class_name` is invisible until the project is
> re-imported. If the identifier is still unresolved after Task 1 Step 3, re-run
> with `--import` once before assuming the code is wrong.

- [ ] **Step 3: Create the table**

Create `scripts/ui/UpgradeDemo.gd` with the class, the kind enum and the full
table. Draw functions are stubs at this step — Task 2 fills them in.

```gdscript
# One animated diagram demonstrating one upgrade line.
#
# A Control that DRAWS ITSELF in 2D. Deliberately not a SubViewport with a real
# Racer in it: MarkerPicker can afford a 3D preview because it previews one
# object, where this screen has 28 entries and a real racer would need a real
# Maze -- dragging the simulation into a menu screen. CLAUDE.md section 12 says
# the simulation must never require a rendered frame; the inverse holds here.
#
# The DEMOS table is a TABLE, never a parallel array indexed by line number --
# the failure section 6 records for landmark density and section 9c for music
# tracks. Each entry names itself and carries its own parameters, so adding an
# upgrade line is a table entry rather than an edit in several places, and
# RulesTest asserts that a line with no entry is a failure rather than a blank
# box.
class_name UpgradeDemo
extends Control

# The five ways a mechanic can be shown. Every line uses exactly one.
#
# A line with no visible on-screen effect -- Cornering, Wall Armor, Score
# Multiplier -- gets a BAR rather than an invented animation. Motion drawn for
# a mechanic that has none is the HUD-chevron mistake of section 7: a picture
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
# itself -- walls, grid lines, marker -- is drawn once by _draw_corridor(); an
# overlay is the only thing that varies. Thirteen copies of the corridor code is
# the parallel-array trap in different clothes.
enum Overlay {
	NONE,
	ARMED_TURN,     # the press, the buffer window, where the turn lands
	STRIP,          # Path Indicator's green/yellow/red floor strips
	RIBBON,         # a trail running ahead of the marker
	FREEZE,         # the post-turn hold, shown as a pause with a clock
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
		"caption": "A circular map around you, rotated so the way you are facing is always up. Each rank widens it.",
	},
	Upgrades.Line.BUFFER_WINDOW: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.ARMED_TURN,
		"caption": "Press early and the turn stays armed until an opening arrives. Measured in cells, so forgiveness does not shrink as you speed up.",
	},
	Upgrades.Line.FAST_TURNAROUND: {
		"kind": Kind.CORRIDOR,
		"overlay": Overlay.REVERSE,
		"caption": "A 180 costs speed. This line makes backtracking out of a misread cheap enough to be a real option.",
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
		"caption": "Cuts what each turn costs you in speed, so a turn-heavy route stops bleeding you dry.",
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
		"caption": "LEGENDARY. Crash through the wall instead of stopping, keeping your speed. The wall is destroyed and the route is rebuilt around the hole.",
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


# The line this demo draws. Set by the compendium before the node is shown.
var line: int = -1

# Seconds since the demo started, driven by _process. Every animation is a
# function of this, so a demo has no state of its own to get out of step.
var _clock := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	if line == -1 or not DEMOS.has(line):
		return
	# Task 2 fills these in.
	pass
```

- [ ] **Step 4: Run the test and verify it passes**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS. The count rises by 28 lines × 4 checks plus the reverse-coverage
checks. Read `logs/errors.log` after the run.

- [ ] **Step 5: Verify the test can actually fail**

A test that cannot fail is not evidence (§9d records two of these). Temporarily
delete the `Upgrades.Line.COMPASS` entry from `DEMOS` and re-run.

Expected: FAIL at `demo table covers Compass`. Restore the entry and confirm the
run is green again before committing.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/UpgradeDemo.gd scripts/core/RulesTest.gd docs/plans/upgrade-compendium.md
git commit -m "Add the upgrade demo table, asserted for total coverage

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: The five draw kinds

Fill in the drawing. Each kind is one function; `CORRIDOR` dispatches to an
overlay drawer after drawing the shared corridor.

**Files:**
- Modify: `scripts/ui/UpgradeDemo.gd`

- [ ] **Step 1: Draw the shared corridor**

Add to `UpgradeDemo.gd`. Colours are taken from `MainMenu` so the screen matches
the menu it opens from rather than introducing a third palette.

```gdscript
const COL_ACCENT := MainMenu.COL_ACCENT
const COL_DIM := MainMenu.COL_DIM

# The demo's own palette. Deliberately cyan-family rather than per-maze: this is
# a reference screen, not a maze, and a demo that recoloured itself would imply
# the mechanic differs by maze when it does not.
const COL_WALL := Color(0.16, 0.55, 0.75)
const COL_GRID := Color(0.20, 0.42, 0.55)
const COL_MARKER := Color(0.95, 0.97, 1.0)
const COL_GHOST := Color(0.45, 0.55, 0.68, 0.5)

# The demo corridor, in cells. Small enough that a cell is large on screen --
# the point is to show one mechanic clearly, not to show a maze.
const DEMO_CELLS := 6

# One loop of every animation. Every demo shares it so a player scrolling the
# list is not watching things at unrelated tempos.
const LOOP_SECONDS := 4.0


# Phase through the loop, 0..1. Every animation is a function of this, so
# nothing accumulates drift.
func _phase() -> float:
	return fmod(_clock, LOOP_SECONDS) / LOOP_SECONDS


# The corridor's cell size in pixels, derived from the box rather than fixed --
# the panel resizes with the screen, and a fixed cell size would be correct at
# one window size only. This is the same lesson section 9d records for the pads:
# a pixel is a count, not a size.
func _cell_px() -> float:
	return minf(size.x / float(DEMO_CELLS + 1), size.y * 0.28)


func _draw_corridor_base(rows: int = 1) -> void:
	var cell := _cell_px()
	var origin := Vector2((size.x - cell * DEMO_CELLS) * 0.5,
		(size.y - cell * rows) * 0.5)

	# The corridor floor.
	draw_rect(Rect2(origin, Vector2(cell * DEMO_CELLS, cell * rows)),
		Color(0.04, 0.06, 0.10), true)

	# Cell boundaries. These are the timing contract (section 11.3) and must
	# stay the most legible marking on the floor -- the same rule the game's own
	# floor obeys, for the same reason: every demo about timing is read against
	# them.
	for i in range(DEMO_CELLS + 1):
		var x := origin.x + cell * i
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + cell * rows),
			COL_GRID, 2.0)

	# The walls, top and bottom.
	draw_line(origin, origin + Vector2(cell * DEMO_CELLS, 0.0), COL_WALL, 3.0)
	draw_line(origin + Vector2(0.0, cell * rows),
		origin + Vector2(cell * DEMO_CELLS, cell * rows), COL_WALL, 3.0)


# Where the marker sits at a given cell offset, on the corridor's centre line.
func _marker_pos(cells_along: float, rows: int = 1) -> Vector2:
	var cell := _cell_px()
	var origin := Vector2((size.x - cell * DEMO_CELLS) * 0.5,
		(size.y - cell * rows) * 0.5)
	return origin + Vector2(cell * cells_along, cell * rows * 0.5)


# The marker: a ring with a pointer, the same two-part shape the game draws, so
# a player recognises it. Colour carries state exactly as it does in play.
func _draw_marker(at: Vector2, facing: Vector2,
		colour: Color = COL_MARKER) -> void:
	var r := _cell_px() * 0.22
	draw_arc(at, r, 0.0, TAU, 24, colour, 2.5)
	var tip := at + facing.normalized() * r * 0.9
	var back := at - facing.normalized() * r * 0.4
	var side := Vector2(-facing.y, facing.x).normalized() * r * 0.5
	draw_colored_polygon([tip, back + side, back - side], colour)
```

- [ ] **Step 2: Draw the BAR, GAUGE, PANEL and STILL kinds**

```gdscript
# Two bars, rank 0 against max, with the units named.
#
# This is what a line with no on-screen effect gets. Cornering, Wall Armor and
# Score Multiplier change a number and nothing else, and an animation invented
# for them would claim a visible mechanic that does not exist.
#
# Both values are DERIVED from an Upgrades built at each rank, never written
# here -- the transcription trap of section 12. A bar that restated a tuning
# number would go stale the moment the number moved, and the player reads it.
func _draw_bar(which: String) -> void:
	var lo := _stat_at_rank(which, 0)
	var hi := _stat_at_rank(which, _max_rank())
	var peak := maxf(maxf(lo.value, hi.value), 0.0001)

	var bar_h := size.y * 0.16
	var gap := size.y * 0.12
	var left := size.x * 0.22
	var span := size.x * 0.62
	var top := (size.y - bar_h * 2.0 - gap) * 0.5

	# Animate the max bar filling, so the screen has motion where the mechanic
	# does not -- but the motion is the COMPARISON being drawn, not a fake
	# corridor.
	var grow := clampf(_phase() * 2.0, 0.0, 1.0)

	_draw_labelled_bar(Rect2(left, top, span * (lo.value / peak), bar_h),
		"no ranks", lo.text, COL_GHOST)
	_draw_labelled_bar(
		Rect2(left, top + bar_h + gap, span * (hi.value / peak) * grow, bar_h),
		"max rank", hi.text, COL_ACCENT)


func _draw_labelled_bar(rect: Rect2, label: String, value: String,
		colour: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y)),
		colour, true)
	var font := ThemeDB.fallback_font
	var fs := int(maxf(12.0, size.y * 0.09))
	draw_string(font, rect.position + Vector2(-8.0, rect.size.y * 0.72),
		label, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, fs, COL_DIM)
	draw_string(font,
		rect.position + Vector2(rect.size.x + 10.0, rect.size.y * 0.72),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, colour)


# A pool that drains and refills, with the crash threshold marked.
func _draw_gauge(which: String) -> void:
	var p := _phase()
	# Drain over the first 40% of the loop, hold, then refill -- the shape a
	# barrier actually has in play.
	var fill := 1.0 - clampf(p / 0.4, 0.0, 1.0)
	if p > 0.6:
		fill = clampf((p - 0.6) / 0.4, 0.0, 1.0)

	var w := size.x * 0.6
	var h := size.y * 0.22
	var at := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)
	draw_rect(Rect2(at, Vector2(w, h)), Color(0.10, 0.13, 0.18), true)
	var colour := COL_ACCENT if fill > 0.35 else Color(0.95, 0.35, 0.30)
	draw_rect(Rect2(at, Vector2(w * fill, h)), colour, true)
	draw_rect(Rect2(at, Vector2(w, h)), COL_DIM, false, 2.0)

	var font := ThemeDB.fallback_font
	var fs := int(maxf(12.0, size.y * 0.09))
	var caption := "barrier empty -- you crash" if fill <= 0.001 \
		else "wall contact drains it"
	if which == "second_wind":
		caption = "a banked charge is spent instead" if fill <= 0.001 \
			else "one charge per rank"
	draw_string(font, at + Vector2(0.0, h + fs * 1.6), caption,
		HORIZONTAL_ALIGNMENT_LEFT, w, fs, COL_DIM)


# A mock of the HUD element the line adds, at rank 0 beside max rank.
func _draw_panel(which: String) -> void:
	var box := Vector2(size.x * 0.32, size.y * 0.62)
	var y := (size.y - box.y) * 0.5
	_draw_panel_box(Rect2(Vector2(size.x * 0.10, y), box), which, 0)
	_draw_panel_box(Rect2(Vector2(size.x * 0.58, y), box), which, _max_rank())


func _draw_panel_box(rect: Rect2, which: String, rank: int) -> void:
	draw_rect(rect, Color(0.05, 0.07, 0.11), true)
	draw_rect(rect, COL_DIM if rank == 0 else COL_ACCENT, false, 2.0)
	var font := ThemeDB.fallback_font
	var fs := int(maxf(11.0, size.y * 0.08))
	var label := "without it" if rank == 0 else "at max rank"
	draw_string(font, rect.position + Vector2(0.0, rect.size.y + fs * 1.4),
		label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs,
		COL_DIM if rank == 0 else COL_ACCENT)

	match which:
		"minimap":
			if rank == 0:
				return
			var c := rect.position + rect.size * 0.5
			var radius := minf(rect.size.x, rect.size.y) * 0.38
			draw_arc(c, radius, 0.0, TAU, 32, COL_ACCENT, 2.0)
			# A few wall strokes, so it reads as a map rather than a circle.
			for i in range(6):
				var a := TAU * float(i) / 6.0 + _phase() * 0.4
				draw_line(c + Vector2(cos(a), sin(a)) * radius * 0.35,
					c + Vector2(cos(a), sin(a)) * radius * 0.8,
					COL_WALL, 2.0)
			_draw_marker(c, Vector2.UP)
		"quadrant":
			var n := 2 if rank <= 1 else (3 if rank == 2 else 4)
			var lit := int(_phase() * float(n * n))
			var cw := rect.size.x / float(n)
			var ch := rect.size.y / float(n)
			for i in range(n * n):
				var cell := Rect2(
					rect.position + Vector2(cw * (i % n), ch * (i / n)),
					Vector2(cw, ch))
				draw_rect(cell, COL_ACCENT if i == lit \
					else Color(0.12, 0.16, 0.22), true)
				draw_rect(cell, Color(0.05, 0.07, 0.11), false, 1.0)
			if rank == 0:
				draw_rect(rect, Color(0.05, 0.07, 0.11), true)
				draw_rect(rect, COL_DIM, false, 2.0)
		"compass":
			if rank == 0:
				return
			var dirs := ["N", "E", "S", "W"]
			var idx := int(_phase() * 4.0) % 4
			draw_string(ThemeDB.fallback_font,
				rect.position + Vector2(0.0, rect.size.y * 0.6),
				dirs[idx], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x,
				int(rect.size.y * 0.42), COL_MARKER)
		"cards":
			var count := Tuning.CARDS_PER_GATE if rank == 0 \
				else int(Tuning.CARDS_BY_EXTRA_RANK[
					mini(rank, Tuning.CARDS_BY_EXTRA_RANK.size() - 1)])
			var pad := rect.size.x * 0.06
			var cw2 := (rect.size.x - pad * float(count + 1)) / float(count)
			for i in range(count):
				draw_rect(Rect2(
					rect.position + Vector2(pad + (cw2 + pad) * i,
						rect.size.y * 0.2),
					Vector2(cw2, rect.size.y * 0.6)),
					COL_ACCENT if rank > 0 else COL_GHOST, false, 2.0)


# One composed frame with callouts. Flying Vision only: the ability is a static
# overhead view, so animating it would misrepresent it.
func _draw_still(_which: String) -> void:
	var cell := _cell_px() * 0.6
	var origin := Vector2((size.x - cell * 6.0) * 0.5,
		(size.y - cell * 4.0) * 0.5)
	# A small maze seen from above -- which is the whole point of the ability,
	# and the one place the camera is allowed above the wall line.
	for gx in range(7):
		draw_line(origin + Vector2(cell * gx, 0.0),
			origin + Vector2(cell * gx, cell * 4.0), COL_GRID, 1.5)
	for gy in range(5):
		draw_line(origin + Vector2(0.0, cell * gy),
			origin + Vector2(cell * 6.0, cell * gy), COL_GRID, 1.5)
	_draw_marker(origin + Vector2(cell * 1.5, cell * 2.5), Vector2.RIGHT)
	var font := ThemeDB.fallback_font
	var fs := int(maxf(12.0, size.y * 0.09))
	draw_string(font, origin + Vector2(0.0, cell * 4.0 + fs * 1.8),
		"the clock is stopped while you look",
		HORIZONTAL_ALIGNMENT_CENTER, cell * 6.0, fs, COL_DIM)
```

- [ ] **Step 3: Derive the bar values from `Upgrades`**

This is the function that keeps the screen honest. It builds a real `Upgrades`,
takes the line to a rank, and asks it — so a bar can never quote a number the
game does not use.

```gdscript
# The value a stat takes at a given rank, with the text to print beside it.
#
# Built by taking a REAL Upgrades to that rank and asking it, never by reading a
# tuning table directly and never by writing the number here. Fast Turnaround's
# card text had already drifted a whole retune before anyone noticed (section
# 7); this screen must not repeat that.
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
				"text": "%.2f/sec" % up.barrier_regen()}
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
				"text": "%.1f HP/sec" % up.hp_regen()}
		"score_mult":
			return {"value": up.score_multiplier(),
				"text": "%.2fx points" % up.score_multiplier()}
		"momentum":
			return {"value": up.momentum_ramp_scale(),
				"text": "%.2fx ramp" % up.momentum_ramp_scale()}
		"overclock":
			var burn := up.overclock_hp_per_sec()
			return {"value": burn if burn > 0.0 else 0.0,
				"text": "not held" if burn <= 0.0 else "%.1f HP/sec" % burn}
	return {"value": 0.0, "text": ""}


func _max_rank() -> int:
	return int(Upgrades.DEFINITIONS[line]["max_rank"])
```

- [ ] **Step 4: Draw the corridor overlays and dispatch**

```gdscript
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


func _draw_overlay(overlay: int, entry: Dictionary) -> void:
	var p := _phase()
	var font := ThemeDB.fallback_font
	var fs := int(maxf(12.0, size.y * 0.09))
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
				draw_rect(Rect2(_marker_pos(press_at) - Vector2(0.0, cell * 0.5),
					Vector2(cell * (opening - press_at), cell)),
					Color(COL_ACCENT, 0.15), true)
				draw_string(font, _marker_pos(press_at)
					+ Vector2(0.0, -cell * 0.7), "press -- armed",
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, COL_ACCENT)
			draw_line(_marker_pos(opening) - Vector2(0.0, cell * 0.5),
				_marker_pos(opening) + Vector2(0.0, -cell * 0.5) * -1.0,
				Color(0.10, 0.12, 0.16), 4.0)
			var facing := Vector2.RIGHT if travel < opening else Vector2.UP
			_draw_marker(_marker_pos(minf(travel, opening)), facing)
		Overlay.STRIP:
			# Green, yellow and red across three openings.
			var cols := [Color(0.2, 0.95, 0.4), Color(0.95, 0.85, 0.25),
				Color(0.95, 0.3, 0.25)]
			for i in range(3):
				var x := 1.5 + float(i) * 1.6
				var pulse := 1.0 if i > 0 else 0.6 + 0.4 * sin(_clock * 4.0)
				draw_rect(Rect2(
					_marker_pos(x) - Vector2(cell * 0.06, cell * 0.5),
					Vector2(cell * 0.12, cell)),
					Color(cols[i], pulse), true)
			_draw_marker(_marker_pos(p * 1.4), Vector2.RIGHT)
		Overlay.RIBBON:
			var col: Color = entry.get("ribbon_color", COL_ACCENT)
			var head := clampf(p * 2.2, 0.0, 1.0) * float(DEMO_CELLS)
			draw_line(_marker_pos(0.4), _marker_pos(maxf(head, 0.4)),
				col, cell * 0.18)
			_draw_marker(_marker_pos(0.4), Vector2.RIGHT)
		Overlay.FREEZE:
			# The marker reaches the corner, holds, then continues. Deep Breath
			# holds longer, which is the whole difference between the two lines.
			var hold := 0.45 if bool(entry.get("extends_freeze", false)) else 0.2
			var t := p
			var pos := 0.0
			var facing2 := Vector2.RIGHT
			if t < 0.4:
				pos = t / 0.4 * 3.0
			elif t < 0.4 + hold:
				pos = 3.0
				facing2 = Vector2.UP
			else:
				pos = 3.0
				facing2 = Vector2.UP
			if t >= 0.4 and t < 0.4 + hold:
				draw_string(font, _marker_pos(3.0) + Vector2(0.0, -cell * 0.8),
					"held -- read the new corridor",
					HORIZONTAL_ALIGNMENT_CENTER, cell * 4.0, fs, COL_ACCENT)
			_draw_marker(_marker_pos(pos), facing2)
		Overlay.REVERSE:
			var facing3 := Vector2.RIGHT if p < 0.5 else Vector2.LEFT
			var pos2 := p * 4.0 if p < 0.5 else (1.0 - p) * 4.0
			_draw_marker(_marker_pos(maxf(pos2, 0.3)), facing3)
			if p >= 0.45 and p < 0.6:
				draw_string(font, _marker_pos(2.0) + Vector2(0.0, -cell * 0.8),
					"180 -- costs speed", HORIZONTAL_ALIGNMENT_CENTER,
					cell * 3.0, fs, Color(0.95, 0.6, 0.3))
		Overlay.TRAIL_TINT:
			# Lit on the first pass, darker with every re-crossing.
			for i in range(DEMO_CELLS):
				var visits := 1 if i < 3 else (3 if i < 5 else 0)
				if visits == 0:
					continue
				var tint := Color(0.35, 0.75, 0.95, 0.55) if visits == 1 \
					else Color(0.10, 0.14, 0.22, 0.85)
				draw_rect(Rect2(_marker_pos(float(i))
					- Vector2(0.0, cell * 0.5), Vector2(cell, cell)),
					tint, true)
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT)
		Overlay.COMPASS_ARROW:
			var at := _marker_pos(2.0)
			_draw_marker(at, Vector2.RIGHT)
			var a := sin(_clock) * 0.5 - 0.6
			draw_line(at, at + Vector2(cos(a), sin(a)) * cell * 0.9,
				Color(0.95, 0.75, 0.2), 3.0)
		Overlay.GATE:
			# The footprint is the mechanic: a wide gate straddles a wall, so a
			# parallel corridor can bank the pick.
			var gate_at := 3.0
			var wide := p > 0.5
			if wide:
				for dx in [-1.0, 0.0, 1.0]:
					draw_rect(Rect2(_marker_pos(gate_at + dx)
						- Vector2(cell * 0.5, cell * 0.5), Vector2(cell, cell)),
						Color(0.95, 0.8, 0.25, 0.22), true)
			draw_rect(Rect2(_marker_pos(gate_at)
				- Vector2(cell * 0.08, cell * 0.5),
				Vector2(cell * 0.16, cell)), Color(0.95, 0.8, 0.25), true)
			draw_string(font, _marker_pos(gate_at) + Vector2(0.0, -cell * 0.75),
				"wider footprint" if wide else "one cell",
				HORIZONTAL_ALIGNMENT_CENTER, cell * 2.0, fs, COL_DIM)
			_draw_marker(_marker_pos(1.0), Vector2.RIGHT)
		Overlay.SMASH:
			var broken := p > 0.5
			var wall_at := 3.5
			if not broken:
				draw_line(_marker_pos(wall_at) - Vector2(0.0, cell * 0.5),
					_marker_pos(wall_at) + Vector2(0.0, cell * 0.5),
					COL_WALL, 5.0)
			else:
				draw_line(_marker_pos(wall_at) - Vector2(0.0, cell * 0.5),
					_marker_pos(wall_at) - Vector2(0.0, cell * 0.2),
					COL_WALL, 5.0)
				draw_line(_marker_pos(wall_at) + Vector2(0.0, cell * 0.2),
					_marker_pos(wall_at) + Vector2(0.0, cell * 0.5),
					COL_WALL, 5.0)
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT)
		Overlay.AUTOPILOT:
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT,
				Color(0.5, 0.9, 1.0))
			draw_string(font, _marker_pos(0.0) + Vector2(0.0, -cell * 0.8),
				"driven for you, untouchable",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, COL_ACCENT)
		Overlay.EXPIRY:
			var t2 := p
			draw_string(font, _marker_pos(1.0) + Vector2(0.0, -cell * 0.8),
				"press", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, COL_ACCENT)
			if t2 > 0.55:
				draw_string(font, _marker_pos(3.2) + Vector2(0.0, -cell * 0.8),
					"expired -- slowdown", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
					Color(0.95, 0.5, 0.3))
			_draw_marker(_marker_pos(t2 * float(DEMO_CELLS)), Vector2.RIGHT)
		_:
			_draw_marker(_marker_pos(p * float(DEMO_CELLS)), Vector2.RIGHT)
```

- [ ] **Step 5: Verify it parses and the rules test still passes**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS, same count as Task 1. A parse error here is most likely the
§12 leading-operator trap — GDScript has no leading-operator line continuation,
and it surfaces as "Could not resolve class" in some *other* file.

Read `logs/errors.log`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/UpgradeDemo.gd
git commit -m "Draw the five upgrade demo kinds

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: The compendium screen, with the demo in a bubble

The list is the screen. The demo appears in a **bubble beside the row the player
is on**, and follows the selection up and down the list.

**Files:**
- Create: `scripts/ui/UpgradeCompendium.gd`

### Why a bubble rather than a fixed pane

Recorded because the two layouts look interchangeable and are not:

- **The list is the subject.** A fixed detail pane splits the screen in half and
  gives permanent real estate to one line at a time, which is backwards for a
  reference screen whose job is *comparison* — a player deciding between
  Cornering and Snap Turn wants both names in view. A bubble spends screen only
  on the line being asked about.
- **It is transient, so it may be large.** A pane has to fit beside the list
  forever; a bubble overlaps it and can be big enough to read a diagram in. The
  demo gets more room this way, not less.
- **The affordance is the row itself, not an (i) glyph.** §9d records the settings
  cog rendering as a tofu box because a *character* was used for a control, and
  the fix was to draw it. A dedicated (i) target would be that problem plus a
  second focus stop per row — 28 extra tab stops on a keyboard-navigable list.
  The row already has hover and focus; the bubble hangs off those.

### The two failure modes it must be built against

Both are §12 lessons arriving in a new place, and both are why the shot tool in
Task 5 matters more for this layout than it did for a pane:

- **A bubble near the bottom of a list runs off the screen.** Its position is
  derived from the row's measured rect and then **clamped into the panel**, never
  placed at a fixed offset. This is the hard-coded-band trap (§12) — a constant
  offset is correct for the row it was tuned against and wrong for the last one.
- **A bubble drawn under the list is invisible; drawn over the row it explains,
  it hides it.** It is added last so it draws on top, and offset to the side of
  the list rather than over it.

- [ ] **Step 1: Build the screen**

```gdscript
# The upgrade compendium: every line in the game, with a diagram of what it does.
#
# Built on MarkerPicker's shape -- a full-screen Control the menu adds and frees,
# reporting through `closed`. It owns no state: the list is read live from
# Upgrades.DEFINITIONS and the numbers from a real Upgrades taken to each rank,
# so this screen can never advertise a mechanic the game does not have. That is
# the same rule that made Fast Turnaround's card text derived rather than
# written (CLAUDE.md section 7).
#
# The demo lives in a BUBBLE beside the focused row rather than in a fixed pane.
# The list is the subject of this screen -- a player deciding between two lines
# wants both names in view -- and a pane would spend half the screen permanently
# on one of them. The bubble is transient, so it can be larger than a pane could
# afford to be.
#
# Nothing in the simulation may read this. Same separation landmarks (section 6),
# music (9c), touch controls (9d) and the marker picker (section 12) have.
class_name UpgradeCompendium
extends Control

signal closed()

const COL_ACCENT := MainMenu.COL_ACCENT
const COL_DIM := MainMenu.COL_DIM
const COL_SCRIM := Color(0.02, 0.02, 0.05, 0.86)
const COL_LEGENDARY := Color(0.95, 0.75, 0.25)

const PANEL_SIZE := Vector2(1180, 700)
const LIST_WIDTH := 340.0
const ROW_HEIGHT := 40.0

# The bubble. Wide enough for a corridor demo to read at six cells, tall enough
# for the diagram plus its caption and the per-rank list.
const BUBBLE_SIZE := Vector2(560, 340)
# How far the bubble sits from the list. A gap rather than an overlap: a bubble
# drawn over the row it explains hides the thing being asked about.
const BUBBLE_GAP := 18.0

var _rows: Array[Button] = []
var _bubble: PanelContainer = null
var _demo: UpgradeDemo = null
var _title: Label = null
var _ranks: Label = null
var _caption: Label = null
var _detail: RichTextLabel = null
var _list: VBoxContainer = null
var _panel: PanelContainer = null
var _selected := -1
# Sorted once in _ready. Legendaries last, since they are the rare tier and a
# player reading top to bottom should meet the ordinary tree first.
var _lines: Array[int] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = COL_SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	_build_line_order()
	_build_panel()
	# Built AFTER the panel so it draws on top of the list rather than under it.
	_build_bubble()
	if not _rows.is_empty():
		_select(0)


# Ordinary lines in declaration order, then the legendaries. Read from
# DEFINITIONS rather than listed here, so a new line needs no edit.
func _build_line_order() -> void:
	var ordinary: Array[int] = []
	var legendary: Array[int] = []
	var probe := Upgrades.new(1)
	for line in Upgrades.DEFINITIONS:
		if probe.is_legendary(line):
			legendary.append(int(line))
		else:
			ordinary.append(int(line))
	_lines = ordinary
	_lines.append_array(legendary)


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	# Sized against the viewport with the same reasoning section 9d gives for
	# the pads: a pixel is a count, not a size, so a panel fixed in viewport
	# units is a different physical size on every screen.
	var box := Vector2(
		minf(PANEL_SIZE.x, get_viewport_rect().size.x * 0.94),
		minf(PANEL_SIZE.y, get_viewport_rect().size.y * 0.92))
	panel.offset_left = -box.x * 0.5
	panel.offset_right = box.x * 0.5
	panel.offset_top = -box.y * 0.5
	panel.offset_bottom = box.y * 0.5
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	_panel = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var heading := Label.new()
	heading.text = "UPGRADES"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", COL_ACCENT)
	col.add_child(heading)

	var sub := Label.new()
	sub.text = "Browse with UP and DOWN. ESC to close."
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", COL_DIM)
	col.add_child(sub)

	# The list keeps its own narrow column on the left; the bubble uses the
	# space beside it.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	scroll.add_child(_list)

	var probe := Upgrades.new(1)
	for i in range(_lines.size()):
		var line := _lines[i]
		var row := Button.new()
		var max_rank := int(Upgrades.DEFINITIONS[line]["max_rank"])
		# The rank count sits on the row itself, so the list is worth reading
		# before any bubble opens -- otherwise the screen says nothing at all
		# until something is hovered.
		row.text = "%s      %d" % [
			String(Upgrades.DEFINITIONS[line]["name"]), max_rank]
		row.custom_minimum_size = Vector2(LIST_WIDTH, ROW_HEIGHT)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_ALL
		var accent := COL_LEGENDARY if probe.is_legendary(line) else COL_ACCENT
		row.add_theme_color_override("font_color", COL_DIM)
		row.add_theme_color_override("font_hover_color", accent)
		row.add_theme_color_override("font_focus_color", accent)
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.10, 0.16, 0.24) \
				if state in ["hover", "focus", "pressed"] \
				else Color(0.06, 0.08, 0.13)
			style.set_corner_radius_all(5)
			style.set_content_margin_all(8)
			row.add_theme_stylebox_override(state, style)
		# Hover and focus both open the bubble, so a mouse and a keyboard reach
		# it the same way. No dedicated (i) target: that would be a second focus
		# stop on every one of 28 rows.
		row.pressed.connect(_select.bind(i))
		row.focus_entered.connect(_select.bind(i))
		row.mouse_entered.connect(_select.bind(i))
		_list.add_child(row)
		_rows.append(row)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11, 0.97)
	style.border_color = COL_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	return style


func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.custom_minimum_size = BUBBLE_SIZE
	# Never a mouse target. The bubble follows the pointer's row, so a bubble
	# that ate hover events would fight the list it is describing.
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _panel_style()
	style.bg_color = Color(0.07, 0.10, 0.16, 0.99)
	_bubble.add_theme_stylebox_override("panel", style)
	add_child(_bubble)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_bubble.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", COL_ACCENT)
	col.add_child(_title)

	_ranks = Label.new()
	_ranks.add_theme_font_size_override("font_size", 13)
	_ranks.add_theme_color_override("font_color", COL_DIM)
	col.add_child(_ranks)

	_demo = UpgradeDemo.new()
	_demo.name = "Demo"
	_demo.custom_minimum_size = Vector2(0.0, BUBBLE_SIZE.y * 0.42)
	_demo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_demo)

	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 15)
	_caption.add_theme_color_override("font_color", Color(0.85, 0.9, 0.96))
	col.add_child(_caption)

	# Per-rank text, straight from Upgrades. This is the part that must never be
	# restated here: it is what the CARD says, and a compendium disagreeing with
	# a card is worse than no compendium.
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 13)
	col.add_child(_detail)


func _select(index: int) -> void:
	if index < 0 or index >= _lines.size() or index == _selected:
		return
	_selected = index
	var line := _lines[index]
	_demo.line = line
	_title.text = String(Upgrades.DEFINITIONS[line]["name"])

	var max_rank := int(Upgrades.DEFINITIONS[line]["max_rank"])
	var probe := Upgrades.new(1)
	_ranks.text = "%d rank%s%s" % [max_rank, "" if max_rank == 1 else "s",
		"     LEGENDARY" if probe.is_legendary(line) else ""]

	_caption.text = String(UpgradeDemo.DEMOS[line].get("caption", ""))

	# Walk a real Upgrades up the line, asking it what each rank offers. This is
	# exactly what the card screen shows, from exactly the same call -- so the
	# two can never disagree.
	var up := Upgrades.new(1)
	var texts: Array[String] = []
	for r in range(max_rank):
		var text := up.next_rank_description(line)
		if text != "":
			texts.append("[color=#7f8c9d]%d.[/color]  %s" % [r + 1, text])
		up.take(line)
	_detail.text = "\n".join(texts)

	_place_bubble(index)


# Put the bubble beside its row, CLAMPED into the panel.
#
# Derived from the row's measured rect rather than placed at a fixed offset per
# row: a constant is correct for the row it was tuned against and runs off the
# bottom for the last one -- the hard-coded-band trap section 12 records for the
# card row and the summary panel. Clamping is what makes the bottom of a
# 28-entry list behave like the top.
func _place_bubble(index: int) -> void:
	if _bubble == null or _panel == null or index >= _rows.size():
		return
	var row := _rows[index]
	var panel_rect := _panel.get_global_rect()
	var row_rect := row.get_global_rect()
	# A row not yet laid out has a zero rect, and anchoring to it would put the
	# bubble in the corner. Defer to the next frame, where the rect is real.
	if row_rect.size.y <= 0.0 or panel_rect.size.y <= 0.0:
		_place_bubble.call_deferred(index)
		return

	var bubble_size := _bubble.size
	if bubble_size.y <= 0.0:
		bubble_size = BUBBLE_SIZE

	# Beside the list, vertically centred on the row.
	var x := panel_rect.position.x + LIST_WIDTH + BUBBLE_GAP * 2.0
	var y := row_rect.position.y + row_rect.size.y * 0.5 - bubble_size.y * 0.5

	# Clamped inside the panel, so the last rows do not push it off the screen.
	var top_limit := panel_rect.position.y + BUBBLE_GAP
	var bottom_limit := panel_rect.position.y + panel_rect.size.y \
		- bubble_size.y - BUBBLE_GAP
	y = clampf(y, top_limit, maxf(top_limit, bottom_limit))
	var right_limit := panel_rect.position.x + panel_rect.size.x \
		- bubble_size.x - BUBBLE_GAP
	x = clampf(x, panel_rect.position.x + BUBBLE_GAP,
		maxf(panel_rect.position.x + BUBBLE_GAP, right_limit))

	_bubble.global_position = Vector2(x, y)


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		closed.emit()
```

- [ ] **Step 2: Verify it parses**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS at the same count as Task 2. This step only checks that the new
class parses and its `class_name` resolves — re-run with `--import` first if the
identifier is reported undeclared (§12).

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/UpgradeCompendium.gd
git commit -m "Add the upgrade compendium, with the demo in a bubble

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3b: Assert the bubble stays inside the panel

The clamp is the part of this screen most likely to be wrong, and it is wrong
*invisibly* — a bubble half off the bottom edge still renders, still animates, and
still reads correctly for every row except the ones nobody tests. Worth its own
assertion rather than trusting Task 5's frames, because the shot tool photographs
a handful of rows and the failure lives at the extremes.

**Files:**
- Modify: `scripts/core/ShellTest.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# The bubble stays inside the panel, at the TOP and BOTTOM of the list.
#
# Both ends, because the top passes trivially -- a bubble placed at a fixed
# offset is correct there and runs off the screen at the last row, which is
# exactly the hard-coded-band failure this clamp exists to prevent. Testing one
# end would pass against the broken version.
func _test_compendium_bubble_stays_in_panel() -> void:
	var screen := UpgradeCompendium.new()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	var panel: PanelContainer = screen.get_node_or_null("Panel")
	var bubble: PanelContainer = screen.get_node_or_null("Bubble")
	check("compendium builds its panel", panel != null)
	check("compendium builds its bubble", bubble != null)

	if panel != null and bubble != null:
		for index in [0, screen._lines.size() - 1]:
			screen._select(index)
			await get_tree().process_frame
			await get_tree().process_frame
			var p := panel.get_global_rect()
			var b := bubble.get_global_rect()
			check("bubble top inside panel at row %d" % index,
				b.position.y >= p.position.y - 1.0)
			check("bubble bottom inside panel at row %d" % index,
				b.position.y + b.size.y <= p.position.y + p.size.y + 1.0)
			check("bubble right inside panel at row %d" % index,
				b.position.x + b.size.x <= p.position.x + p.size.x + 1.0)

	screen.queue_free()
	await get_tree().process_frame
```

- [ ] **Step 2: Run it and verify it passes**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
```
Expected: PASS.

- [ ] **Step 3: Verify the test can actually fail**

A test that cannot fail is not evidence — §9d records two of these in this
codebase, both false positives that stayed green against the bug they were named
for. Temporarily replace the clamped `y` in `_place_bubble` with the unclamped
value:

```gdscript
	# TEMPORARY -- verifying the assertion can fail.
	y = row_rect.position.y + row_rect.size.y * 0.5 - bubble_size.y * 0.5
```

Re-run. Expected: FAIL at `bubble bottom inside panel at row 27`, and a PASS at
row 0 — which is the proof that testing only the top would have been worthless.
Restore the clamp and confirm green.

- [ ] **Step 4: Commit**

```bash
git add scripts/core/ShellTest.gd
git commit -m "Assert the compendium bubble stays inside its panel

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
## Task 4: Wire it to the menu

**Files:**
- Modify: `scripts/ui/MainMenu.gd`
- Modify: `scripts/core/ShellTest.gd`

- [ ] **Step 1: Write the failing test**

Add to `scripts/core/ShellTest.gd`, registered beside the other menu checks.

```gdscript
# The UPGRADES button opens the compendium and closing it comes back.
#
# Driven through the menu's own button rather than by constructing the screen
# directly, because that is the half that rots: a button wired to nothing leaves
# UpgradeCompendium perfectly correct and the player unable to reach it. The
# same reasoning the daily/monthly buttons are asserted through their signal.
func _test_upgrade_compendium() -> void:
	var menu := MainMenu.new()
	add_child(menu)
	await get_tree().process_frame

	var button: Button = null
	for child in _all_buttons(menu):
		if child.text == "UPGRADES":
			button = child
			break
	check("menu has an UPGRADES button", button != null)
	if button == null:
		menu.queue_free()
		return

	button.pressed.emit()
	await get_tree().process_frame

	var screen: UpgradeCompendium = null
	for child in menu.get_children():
		if child is UpgradeCompendium:
			screen = child
			break
	check("UPGRADES opens the compendium", screen != null)

	if screen != null:
		# Every line in the game is listed. This is the assertion that fails
		# when a line is added and this screen is forgotten -- the menu-side
		# half of RulesTest's table coverage check.
		check("compendium lists every line",
			screen._lines.size() == Upgrades.DEFINITIONS.size())
		screen.closed.emit()
		await get_tree().process_frame
		var still_open := false
		for child in menu.get_children():
			if child is UpgradeCompendium:
				still_open = true
		check("closing the compendium frees it", not still_open)

	menu.queue_free()
	await get_tree().process_frame
```

If `_all_buttons` does not already exist in `ShellTest.gd`, add it — the file
already walks the menu's grid for other checks, so reuse whatever helper is
there rather than adding a second one.

- [ ] **Step 2: Run the test and verify it fails**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
```
Expected: FAIL at `menu has an UPGRADES button`.

- [ ] **Step 3: Add the button and its handlers**

In `scripts/ui/MainMenu.gd`, add the button to the grid in `_build_buttons()`,
directly after the `MARKER` line:

```gdscript
	# UPGRADES sits beside MARKER for the same reason MARKER is not behind the
	# cog: it is not a preference. It is a reference screen a player opens to
	# decide what to take, which wants to be seen rather than found.
	grid.add_child(_make_button("UPGRADES", _on_upgrades))
```

Add the field beside `_marker_picker`:

```gdscript
var _compendium: UpgradeCompendium = null
```

Add the handlers beside `_on_marker` / `_on_marker_closed`:

```gdscript
func _on_upgrades() -> void:
	if _compendium != null:
		return
	var screen := UpgradeCompendium.new()
	screen.closed.connect(_on_upgrades_closed)
	_compendium = screen
	add_child(screen)
	screen.focus_first()


func _on_upgrades_closed() -> void:
	if _compendium != null:
		_compendium.queue_free()
		_compendium = null
	# Land back on the button that opened it, the courtesy MARKER and the cog
	# both get.
	for button in _buttons:
		if button.text == "UPGRADES":
			button.grab_focus()
			break
```

Add it to the phone-hidden list, extending the existing comment:

```gdscript
# UPGRADES is a reference screen with a list and a diagram side by side, which
# wants a desktop screen for the same reason MARKER's preview does.
const PHONE_HIDDEN := ["MARKER", "UPGRADES", "WATCH TRAILER", "QUIT"]
```

- [ ] **Step 4: Run the test and verify it passes**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
```
Expected: PASS, count up by 4.

- [ ] **Step 5: Run every harness**

The menu's button count changed, and `_size_buttons` derives its layout from it —
so the menu sizing assertions are the ones at risk.

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SceneTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/TrailerTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/MusicTest.gd
```
Expected: all green. Read `logs/errors.log` after each.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/MainMenu.gd scripts/core/ShellTest.gd
git commit -m "Reach the compendium from an UPGRADES menu button

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: The picture half

No headless assertion can see a demo that draws an empty box, a caption clipped
by its rect, or a diagram that is unreadable at the panel's real size. §12 records
that failure repeatedly — the marker picker's mis-aimed camera rendered a
plausible dark panel rather than an error.

**Files:**
- Create: `scripts/ui/CompendiumShot.gd`

- [ ] **Step 1: Write the tool**

```gdscript
# The picture half of the upgrade compendium.
#
# It shoots one frame per DEMO KIND rather than one per line, plus every
# legendary -- five kinds is what the drawing code actually has, and 28 frames of
# which 13 are the same corridor function is a slower read for no more coverage.
# It also shoots mid-animation rather than on the first frame: a demo that never
# advances looks identical to a working one in a frame taken at t=0, which is the
# reason QuadrantShot seeks a region change.
extends SceneTree

const SHOT_DIR := "user://../logs"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	await process_frame

	var screen := UpgradeCompendium.new()
	menu.add_child(screen)
	await process_frame

	# One line per kind, plus the legendaries.
	var wanted := {
		Upgrades.Line.BUFFER_WINDOW: "corridor-buffer",
		Upgrades.Line.PATH_INDICATOR: "corridor-strip",
		Upgrades.Line.CORNERING: "bar",
		Upgrades.Line.BARRIER_CAPACITY: "gauge",
		Upgrades.Line.QUADRANT: "panel",
		Upgrades.Line.FLYING_VISION: "still",
		Upgrades.Line.WALL_SMASHER: "legendary-smash",
		Upgrades.Line.AUTO_STEER: "legendary-autosteer",
	}

	for line in wanted:
		var index := screen._lines.find(int(line))
		if index == -1:
			print("MISSING line %d" % line)
			continue
		await _shoot(screen, index, "compendium-%s" % wanted[line])

	# The FIRST and LAST rows, which is where bubble placement fails.
	#
	# ShellTest asserts the bubble's rect stays inside the panel, and a rect
	# assertion cannot see the failure that actually matters here: a bubble
	# correctly inside the panel but sitting on top of the list text it is
	# meant to sit beside. Rect clearance is not text clearance (section 12),
	# and the last row is where the clamp pushes hardest.
	await _shoot(screen, 0, "compendium-row-first")
	await _shoot(screen, screen._lines.size() - 1, "compendium-row-last")

	quit()


func _shoot(screen: UpgradeCompendium, index: int, name: String) -> void:
	screen._select(index)
	# Let the animation advance before capturing. A frame at t=0 cannot tell a
	# moving demo from a frozen one -- the reason QuadrantShot seeks a region
	# change rather than shooting on a timer.
	for _i in range(45):
		await process_frame
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(path)
	print("shot %s" % path)
```

- [ ] **Step 2: Run it**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Script res://scripts/ui/CompendiumShot.gd -Quit 40
```

Expected: ten PNGs in `logs/`. Not `-Headless` — this needs the renderer.

- [ ] **Step 3: Look at every frame**

Read each PNG. Check specifically for the failures §12 says only a frame catches:

- A demo box that is empty or flat — the mis-aimed-preview failure, which renders
  as a plausible dark panel rather than as an error.
- A caption or label clipped by the bubble edge, or overlapping the diagram.
  Rect clearance is not text clearance.
- A demo unreadable at the bubble's real size, rather than at the size it was
  designed against.
- **The bubble sitting on the list text** in `compendium-row-first` and
  `compendium-row-last`. This is the one the `ShellTest` rect assertion cannot
  see: a bubble fully inside the panel and still covering the names it is meant
  to sit beside is a pass by rect and a failure by eye.
- The bubble jumping somewhere unexpected at the **last** row, where the clamp
  binds hardest and the row is furthest from the bubble's centre.

Fix what the frames show, re-run, and look again.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/CompendiumShot.gd
git commit -m "Add the compendium's picture half

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Record it in CLAUDE.md

Per the working practices: update the docs only once the change lands and is
confirmed working. This task runs **last**, after the frames are checked.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the section**

Add after the marker-picker section in §12, since that screen is this one's
structural template. Record the reasoning, not the file inventory:

- Why demos are 2D drawings rather than live `SubViewport` racers — the
  simulation must not be dragged into a menu screen.
- Why lines with no visible effect get a quantity bar rather than an invented
  animation — the HUD-chevron mistake.
- Why every number is derived from a real `Upgrades` taken to each rank, never
  written — Fast Turnaround's drifted card text.
- That `DEMOS` is a table asserted for **total coverage**, so adding an upgrade
  line fails a test rather than silently producing a blank box.
- Why the demo is a **bubble off the focused row** rather than a fixed pane: the
  list is the subject of a reference screen, comparison needs two names in view,
  and a transient bubble can be larger than a permanent pane could afford.
- Why the affordance is the row rather than an (i) glyph — a drawn-versus-typed
  icon problem (§9d's tofu cog) plus 28 extra focus stops.
- That the bubble's position is **derived from the row's measured rect and
  clamped into the panel**, and that the assertion covers both ends of the list
  because the top passes trivially.
- The harness counts, updated.

- [ ] **Step 2: Update the harness table**

`RulesTest` and `ShellTest` assertion counts in §12's table both change. Read the
new totals off an actual run rather than adding them up by hand.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Record the upgrade compendium's design decisions

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-review notes

Checked against the request and the project's own rules:

- **Every line covered.** The `DEMOS` table has an entry for all 28 members of
  `Upgrades.Line`, and Task 1's test asserts coverage in both directions rather
  than trusting it.
- **No parallel arrays.** The table is keyed by line, and the line order is read
  from `DEFINITIONS`. Nothing is indexed by position.
- **No transcribed numbers.** Every value shown comes from a real `Upgrades` or
  from `next_rank_description()`. The one place tuning constants are named
  directly is `Tuning.CARDS_BY_EXTRA_RANK` in the cards panel, read from `Tuning`
  rather than written.
- **Tests can fail.** Task 1 Step 5 and Task 3b Step 3 both verify this
  explicitly by breaking the code and watching the assertion go red — §9d records
  two false positives in this codebase that stayed green against the bug they
  were named for.
- **A rendered frame is part of the plan**, not an afterthought — Task 5 exists
  because the failures this screen is most likely to have are invisible headlessly.
- **The bubble is covered from both sides.** Task 3b asserts its rect stays in
  the panel at both ends of the list; Task 5 photographs the same two rows,
  because a bubble can satisfy the rect check and still sit on the list text.
  Neither check subsumes the other.
