# Trail Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a **Trail Memory** upgrade line that tints cells the player has driven — on the maze floor and on the minimap — lighting a cell on its first visit and darkening it with each repeat, remembered for a per-rank window of 1:00 / 1:30 / 2:00 / 2:30 / 3:00 / infinite.

**Architecture:** A per-cell visit record lives on `Racer` (rules layer, headlessly testable) as a new `TrailMemory` object holding a visit count and a last-seen timestamp per cell. The floor renders it through a `ShaderMaterial` on the existing floor plane, reading an `ImageTexture` with one texel per cell — so lighting a cell is a single pixel write rather than a mesh rebuild. The minimap reads the same record directly and tints its cell rects. Cells fade out over `TRAIL_FADE` seconds as their window lapses, and a lapsed cell's count resets to zero.

**Tech Stack:** Godot 4.7, GDScript. Shader written in-code via `Shader.new()` (the `GoldenTrail` idiom), kept WebGL2-safe because the web build runs `gl_compatibility`.

---

## Design decisions this plan encodes

These were settled in conversation before any code. They are the *why*; CLAUDE.md gets them in Task 11.

1. **Both the ground and the minimap**, gated on holding the line.
2. **Lit once, then darkens with repeats.** A cell driven once lifts *above* the base floor; each further visit takes it down, past base into shadow. Fresh ground is dark, ground you know glows, ground you have flogged is burnt out.
3. **Memory is a window, and it fades.** A cell dims back toward untrodden over the last `TRAIL_FADE` seconds of its window, so the tail visibly retreats — and ranking up is visibly a longer tail.
4. **The count expires with the cell.** A lapsed cell reads as never driven. The window is the whole rule, so the infinite rank differs from rank 5 in what is *known*, not only in what is drawn.
5. **It answers "have I been here", never "which way"** — the §6 line that landmarks, spent gates and the rear-view mirror sit on. That is what keeps it clear of Path Indicator, Gate Compass and Golden Trail. This one is *paid*, which makes it a stronger version of that position, not a different one.

## Why not the obvious renderings

- **Not a rebuilt trail mesh.** CLAUDE.md §12 already records this exact trap: `GoldenTrail` rebuilt its ribbon per frame at 23ms and looked like a hang. At maze 5 with the infinite rank the trail can cover thousands of cells.
- **Not a pooled set of quads near the player** (the `PathIndicator` pattern). That works for three strips at one junction; a trail is unbounded, so a pool caps how much can show and pops as it re-assigns.
- **A data texture is O(1) per cell entered** and costs no extra draw call. At 100×100 the texture is 10,000 texels.

## File structure

| File | Responsibility | New? |
|---|---|---|
| `scripts/core/TrailMemory.gd` | The per-cell visit record: counts, timestamps, expiry. Pure logic, node-free. | **create** |
| `scripts/core/Tuning.gd` | The rank window table and the trail's colour/fade constants. | modify |
| `scripts/core/Upgrades.gd` | The `TRAIL_MEMORY` line, its definition, `has_trail_memory()` / `trail_memory_window()`. | modify |
| `scripts/core/Racer.gd` | Owns a `TrailMemory`, records each cell entered, clears it per maze. | modify |
| `scripts/core/MazeMesh.gd` | Floor becomes a `ShaderMaterial` reading a visit texture; exposes `trail_texture`. | modify |
| `scripts/core/TrailFloor.gd` | Drives the floor texture from the racer's `TrailMemory` each frame. | **create** |
| `scripts/core/Game.gd` | Builds and drives `TrailFloor`; wires it per maze. | modify |
| `scripts/ui/Minimap.gd` | Tints cell rects from the same record. | modify |
| `scripts/core/RulesTest.gd` | Asserts the record: counting, expiry, reset, rank windows, rules separation. | modify |
| `scripts/core/SceneTest.gd` | Asserts the floor wiring: shader present, texture sized to the maze, updates on driving. | modify |
| `scripts/core/TrailMemoryShot.gd` | Picture half — seeks re-crossed ground and shoots it. | **create** |
| `CLAUDE.md` | The design record. | modify |

**Ordering matters:** `TrailMemory` (Task 1) has no dependencies and is where the rules live, so it is first and fully tested before anything renders it.

---

### Task 1: The visit record

`TrailMemory` is pure logic — no nodes, no renderer — so it is headlessly testable, which CLAUDE.md §12 requires of anything the simulation layer touches.

**Files:**
- Create: `scripts/core/TrailMemory.gd`
- Test: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

Add to `scripts/core/RulesTest.gd`, before the `check()` helper definitions (around line 125, after the last `_test_*` function):

```gdscript
# Trail Memory: the per-cell record behind the floor tint and the map tint.
#
# Pure logic on purpose. The renderer reads this; it never computes it -- which
# is what keeps the rule headlessly testable (CLAUDE.md section 12) and what
# lets the floor and the minimap agree by construction rather than by two
# implementations happening to match.
func _test_trail_memory() -> void:
	var t := TrailMemory.new()

	# An untouched cell is not merely at zero visits, it is ABSENT. The
	# difference matters to the renderer: absent means "draw nothing", zero
	# would mean "draw the untrodden tint", and at maze 5 that is 10,000 cells
	# of nothing being drawn.
	check("an undriven cell is unknown", not t.has(Vector2i(3, 4)))
	check_eq("an undriven cell reads zero visits", t.visits(Vector2i(3, 4)), 0)

	t.visit(Vector2i(3, 4), 0.0)
	check("a driven cell is known", t.has(Vector2i(3, 4)))
	check_eq("one drive is one visit", t.visits(Vector2i(3, 4)), 1)

	# Re-crossing counts. This is the whole "darker with repeats" rule.
	t.visit(Vector2i(3, 4), 1.0)
	t.visit(Vector2i(3, 4), 2.0)
	check_eq("re-crossing accumulates", t.visits(Vector2i(3, 4)), 3)

	# Intensity: full while the window has time left, decaying to nothing across
	# the final TRAIL_FADE seconds. A cell that snapped off at its deadline
	# would blink out on its own, which reads as a rendering glitch rather than
	# as memory.
	var window := 60.0
	check_near("fresh ground is fully lit", t.intensity(Vector2i(3, 4), 2.0, window), 1.0)

	var mid := 2.0 + window - Tuning.TRAIL_FADE * 0.5
	check_near("half through the fade is half lit",
		t.intensity(Vector2i(3, 4), mid, window), 0.5, 0.01)

	check_near("past the window it is gone",
		t.intensity(Vector2i(3, 4), 2.0 + window + 1.0, window), 0.0)

	# The COUNT expires with the cell, not just the drawing. A cell looped four
	# times and then left alone reads as never driven -- the window is the whole
	# rule, which is what makes the infinite rank a difference in what is KNOWN
	# rather than only in what is shown.
	t.expire(2.0 + window + 1.0, window)
	check("a lapsed cell is forgotten", not t.has(Vector2i(3, 4)))
	check_eq("a lapsed cell's count resets", t.visits(Vector2i(3, 4)), 0)

	# An infinite window never expires. Passed as a negative, which is the
	# sentinel the rank table uses -- a huge float would work until someone ran
	# a long enough session, and 0.0 would be indistinguishable from "no memory".
	var inf_mem := TrailMemory.new()
	inf_mem.visit(Vector2i(1, 1), 0.0)
	inf_mem.expire(100000.0, Tuning.TRAIL_WINDOW_INFINITE)
	check("an infinite window never forgets", inf_mem.has(Vector2i(1, 1)))
	check_near("an infinite window stays fully lit",
		inf_mem.intensity(Vector2i(1, 1), 100000.0, Tuning.TRAIL_WINDOW_INFINITE), 1.0)

	# clear() is the per-maze reset. A trail carried into maze 2 would draw
	# maze 1's route onto a different grid -- the same stale-state trap section
	# 12 records for gates_cleared.
	inf_mem.clear()
	check_eq("clear empties the record", inf_mem.count(), 0)
```

Register it in `_init()` — add the call immediately after `_test_visited_cells()` (line 30):

```gdscript
	_test_visited_cells()
	_test_trail_memory()
```

- [ ] **Step 2: Run the test and verify it fails**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: FAIL — parse error naming `TrailMemory` as an undeclared identifier, because the class does not exist yet.

- [ ] **Step 3: Add the tuning constants**

In `scripts/core/Tuning.gd`, add after the `MINIMAP_RADIUS_BY_RANK` line (around line 223):

```gdscript
# --- Trail Memory ------------------------------------------------------------
# How long a driven cell is remembered, by rank, in SECONDS.
#
# A memory DURATION rather than a cell count, which is the one place this line
# deliberately departs from section 4's "measure forgiveness in cells, not
# seconds" rule. That rule exists so forgiveness does not grow with speed; this
# is not forgiveness, it is memory, and memory of "the last minute of driving"
# is the thing a player actually wants to hold. It does mean the trail covers
# more ground at 8x than at 1x -- which is correct: at 8x you have genuinely
# driven more ground in that minute.
#
# Sized against the 180s maze budget (section 8b). Rank 1 at 60s is a third of
# a maze, which is enough to recognise a loop you just closed and not enough to
# map the maze. The final rank is the whole maze, which is why it is the last.
const TRAIL_WINDOW_INFINITE := -1.0
const TRAIL_WINDOW_BY_RANK := [
	0.0,                     # untaken -- callers must check has_trail_memory()
	60.0,                    # 1:00
	90.0,                    # 1:30
	120.0,                   # 2:00
	150.0,                   # 2:30
	180.0,                   # 3:00
	TRAIL_WINDOW_INFINITE,   # the whole maze
]

# How long a cell spends fading out at the end of its window. The tail of the
# trail visibly retreats rather than individual cells blinking off -- a cell
# that snapped off at its own deadline would read as a rendering fault, and
# ranking up would be invisible except by counting. With a fade, ranking up is
# watching the tail stretch.
const TRAIL_FADE := 3.0

# The tint applied to remembered ground, as a multiplier on the palette's floor
# colour, indexed by visit count.
#
# Index 1 (a single visit) LIFTS the floor: ground you have driven once glows
# faintly, which is the "have I been here" answer. Every further visit takes it
# DOWN, past the base floor into shadow, so heavily re-crossed ground burns out.
# Fresh ground is dark, known ground glows, flogged ground is black.
#
# That shape is deliberate and is not the same as "darker with every visit". A
# strictly monotonic dimming has nowhere to go on a floor that is already near
# black (every palette's floor sits under 0.08), so the first few visits would
# be indistinguishable from each other and from untrodden ground.
const TRAIL_TINT_BY_VISITS := [
	1.0,    # 0 -- untrodden, the palette's own floor
	3.4,    # 1 -- lit
	2.1,    # 2
	1.2,    # 3
	0.6,    # 4
	0.3,    # 5+ -- burnt out
]

# Colour the lit trail is pushed toward, mixed with the palette floor rather
# than replacing it, so the trail reads as the same floor lit rather than as a
# different surface painted on top. Neutral-cool on purpose: it must not collide
# with the three route colours the Path Indicator owns (green/yellow/red), with
# gate amber, or with exit white (section 8's reserved list).
const TRAIL_COL := Color(0.30, 0.62, 0.85)

# How far the tint pushes toward TRAIL_COL at full intensity. Well under 1.0 --
# the grid lines are the timing contract (section 11.3) and must stay the
# dominant marking on the floor, so the trail is a wash beneath them and never
# a surface that competes with them.
const TRAIL_COL_MIX := 0.45
```

- [ ] **Step 4: Write the minimal implementation**

Create `scripts/core/TrailMemory.gd`:

```gdscript
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
```

- [ ] **Step 5: Re-import, then run the test**

A new `class_name` is invisible until the project is re-imported — CLAUDE.md §12 records this exact trap, and the symptom is "Identifier not declared" on an otherwise correct file.

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS, with the assertion count risen by 13.

- [ ] **Step 6: Commit**

```bash
git add scripts/core/TrailMemory.gd scripts/core/Tuning.gd scripts/core/RulesTest.gd
git commit -m "Add the Trail Memory visit record"
```

---

### Task 2: The upgrade line

**Files:**
- Modify: `scripts/core/Upgrades.gd`
- Test: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

Append to `_test_trail_memory()` in `scripts/core/RulesTest.gd`, before its closing:

```gdscript
	# The line itself. Six ranks, the last of them infinite.
	var u := Upgrades.new(1)
	check("the line starts untaken", not u.has_trail_memory())
	check_near("an untaken line has no window", u.trail_memory_window(), 0.0)

	u.take(Upgrades.Line.TRAIL_MEMORY)
	check("one rank holds the line", u.has_trail_memory())
	check_near("rank 1 remembers a minute", u.trail_memory_window(), 60.0)

	for i in 4:
		u.take(Upgrades.Line.TRAIL_MEMORY)
	check_near("rank 5 remembers three minutes", u.trail_memory_window(), 180.0)
	check("rank 5 is not yet maxed", not u.is_maxed(Upgrades.Line.TRAIL_MEMORY))

	u.take(Upgrades.Line.TRAIL_MEMORY)
	check("the line caps at rank 6", u.is_maxed(Upgrades.Line.TRAIL_MEMORY))
	check_near("the last rank is infinite",
		u.trail_memory_window(), Tuning.TRAIL_WINDOW_INFINITE)

	# The card text is DERIVED from the rank table, never written out. A
	# hand-written description that restates a tuning value is the transcription
	# trap section 12 flags for tests, and it is worse on a card because the
	# player reads it and picks on it -- Fast Turnaround's strings drifted to
	# advertising a 2.0x cost long after the 180 was retuned to 0.75x.
	var fresh := Upgrades.new(1)
	var first := fresh.next_rank_description(Upgrades.Line.TRAIL_MEMORY)
	check("the first card names its window", first.contains("1:00"))
	for i in 5:
		fresh.take(Upgrades.Line.TRAIL_MEMORY)
	var last := fresh.next_rank_description(Upgrades.Line.TRAIL_MEMORY)
	check("the last card names it as permanent", last.to_lower().contains("rest of the maze"))
```

- [ ] **Step 2: Run the test and verify it fails**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: FAIL — parse error on `Upgrades.Line.TRAIL_MEMORY`, an undeclared enum member.

- [ ] **Step 3: Add the enum member**

In `scripts/core/Upgrades.gd`, add `TRAIL_MEMORY` to the `Line` enum after `COMPASS` (line 28), leaving the legendaries last:

```gdscript
	QUADRANT,
	COMPASS,
	TRAIL_MEMORY,
	# Legendaries. Rare, active, one per run -- see is_legendary() and the
	# rarity rule in roll_cards().
	WALL_SMASHER,
```

- [ ] **Step 4: Add the definition**

In `scripts/core/Upgrades.gd`, add to `DEFINITIONS` immediately before the `Line.WALL_SMASHER` entry:

```gdscript
	Line.TRAIL_MEMORY: {
		"name": "Trail Memory",
		"max_rank": 6,
		# Descriptions are generated from the rank table in
		# next_rank_description(), so this list is only the flavour of the FIRST
		# rank -- see the comment there.
		"desc": [],
	},
```

- [ ] **Step 5: Add the helpers**

In `scripts/core/Upgrades.gd`, add after `has_cardinal_compass()` (around line 494):

```gdscript
# --- Trail Memory ------------------------------------------------------------
# Ground the player has driven, tinted on the floor and on the minimap. It sits
# on the "have I been here" side of the line landmarks, spent gates and the
# rear-view mirror hold (CLAUDE.md sections 6 and 7) -- it says nothing whatever
# about the route ahead, which is what keeps it clear of Path Indicator, Gate
# Compass and Golden Trail. Being PAID makes it the strongest statement of that
# position in the tree, not a departure from it.

func has_trail_memory() -> bool:
	return rank(Line.TRAIL_MEMORY) > 0


# How long a driven cell stays remembered, in seconds. Returns
# Tuning.TRAIL_WINDOW_INFINITE (a negative sentinel) at the top rank, and 0.0
# when the line is untaken -- callers must check has_trail_memory() rather than
# treating 0.0 as a duration.
func trail_memory_window() -> float:
	var r := mini(rank(Line.TRAIL_MEMORY), Tuning.TRAIL_WINDOW_BY_RANK.size() - 1)
	return float(Tuning.TRAIL_WINDOW_BY_RANK[r])
```

- [ ] **Step 6: Derive the card text**

In `scripts/core/Upgrades.gd`, inside `next_rank_description()`, add immediately after the `FAST_TURNAROUND` branch and before the `var descs: Array` line:

```gdscript
	# Trail Memory's cards are generated from the window table for the same
	# reason Fast Turnaround's are: a hand-written string that restates a tuning
	# number drifts silently, and the player picks a card on what it says.
	if line == Line.TRAIL_MEMORY:
		var windows: Array = Tuning.TRAIL_WINDOW_BY_RANK
		if r + 1 >= windows.size():
			return ""
		var next_w := float(windows[r + 1])
		if next_w == Tuning.TRAIL_WINDOW_INFINITE:
			return "Ground you have driven stays lit for the REST OF THE MAZE."
		var text := "%d:%02d" % [int(next_w) / 60, int(next_w) % 60]
		if r == 0:
			return "Ground you have driven lights up, dimming as you re-cross it. Remembered for %s." % text
		return "Remembered for %s." % text
```

- [ ] **Step 7: Run the test**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/core/Upgrades.gd scripts/core/RulesTest.gd
git commit -m "Add the Trail Memory upgrade line"
```

---

### Task 3: The racer records its trail

**Files:**
- Modify: `scripts/core/Racer.gd`
- Test: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

Append to `_test_trail_memory()` in `scripts/core/RulesTest.gd`:

```gdscript
	# The racer keeps the record. It is written on every cell entered, whether
	# or not the line is held -- holding the line decides what is DRAWN, not
	# what is remembered. Gating the recording on the upgrade would mean a
	# player who takes the line mid-maze starts with a blank trail through
	# ground they demonstrably drove, which is the opposite of memory.
	var m := _make_corridor(8)
	var r := Racer.new()
	r.setup(m, Upgrades.new(1))

	check("a fresh racer has one cell remembered", r.trail.count() == 1)
	check("the start cell is remembered", r.trail.has(m.start_cell))

	# Drive forward a few cells.
	var guard := 0
	while r.cell.x < 3 and guard < 2000:
		r.step(1.0 / 60.0)
		guard += 1
	check("the drive did not hang", guard < 2000)
	check("driven ground is remembered", r.trail.has(Vector2i(2, 0)))
	check_eq("a single crossing is one visit", r.trail.visits(Vector2i(2, 0)), 1)

	# Reverse back over it. A re-crossing has to count, or "darker with repeats"
	# has nothing to darken.
	r.request_reverse()
	guard = 0
	while r.cell.x > 1 and guard < 2000:
		r.step(1.0 / 60.0)
		guard += 1
	check("the reverse did not hang", guard < 2000)
	check_eq("re-crossing counts twice", r.trail.visits(Vector2i(2, 0)), 2)

	# setup() clears it, exactly as it clears `visited` and `gates_cleared`. A
	# trail carried into maze 2 would paint maze 1's route onto a different grid.
	r.setup(_make_corridor(8), Upgrades.new(1))
	check_eq("a new maze starts with a fresh trail", r.trail.count(), 1)
```

- [ ] **Step 2: Run the test and verify it fails**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: FAIL — `Invalid access to property or key 'trail'` on a `Racer`.

- [ ] **Step 3: Add the record to the racer**

In `scripts/core/Racer.gd`, add immediately after the `var visited := {}` declaration (line 170):

```gdscript
# Ground driven this maze, for the Trail Memory upgrade: a visit count and a
# last-seen time per cell.
#
# Deliberately NOT folded into `visited` above. That dictionary is a scoring
# rule -- it holds "has this cell been re-entered" so the section 8b penalty can
# be charged once per cell -- and widening it to carry counts and timestamps
# would put a display feature inside a load-bearing rule. This record is written
# alongside it and read by nothing in the simulation.
#
# Written whether or not the upgrade is held. The line decides what is DRAWN,
# not what is remembered: a player who takes it at gate 4 should see the ground
# they have already covered, not start from blank.
var trail := TrailMemory.new()

# Seconds of driving on this maze, the clock the trail's expiry runs on.
#
# The racer's own accumulated time rather than a wall clock, so the trail stops
# ageing while the game is paused or a card screen is open -- a memory that
# lapsed during an upgrade pick would punish the player for reading their cards.
var trail_clock := 0.0
```

- [ ] **Step 4: Clear it per maze**

In `scripts/core/Racer.gd`, find the `visited.clear()` call in `setup()` (line 243) and the `visited[cell] = false` that follows it (line 246). Add the trail reset alongside:

```gdscript
	visited.clear()
```
becomes
```gdscript
	visited.clear()
	trail.clear()
	trail_clock = 0.0
```

and after the `visited[cell] = false` line, add:

```gdscript
	trail.visit(cell, trail_clock)
```

- [ ] **Step 5: Record each cell entered**

In `scripts/core/Racer.gd`, in `_on_enter_cell()`, add the trail write immediately after the `visited[cell] = repeat` line and *before* `cell_entered.emit(...)`:

```gdscript
	visited[cell] = repeat
	# Recorded here, beside `visited`, and for the same reason it is placed
	# before the gate and exit early-returns below: those return before the end
	# of this function, so a write placed after them would leave gate cells and
	# the exit permanently untrodden -- and gates sit on the solve path, which is
	# exactly the ground a looping player re-covers.
	trail.visit(cell, trail_clock)
	cell_entered.emit(cell, repeat, first_repeat)
```

- [ ] **Step 6: Advance the clock**

In `scripts/core/Racer.gd`, find `func step(` and add the clock advance as the first statement after its existing `finished` / `dead` early-returns. Locate the guard with:

```bash
grep -n "func step" -A 12 scripts/core/Racer.gd
```

Add, immediately after those early returns:

```gdscript
	# The trail's clock. Advanced here rather than from a wall clock so it stops
	# with the simulation -- Game does not call step() while paused or during an
	# upgrade pick, and a trail that aged through a card screen would forget
	# ground while the player was reading.
	trail_clock += delta
```

- [ ] **Step 7: Run the test**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/core/Racer.gd scripts/core/RulesTest.gd
git commit -m "Record driven ground on the racer"
```

---

### Task 4: The trail must not move the racer

The separation assertion. CLAUDE.md §6 records exactly this trap for landmarks: the data hangs off a structure the rules layer can *reach*, so it must be proven the rules never *use* it. `_test_landmarks_do_not_move_the_racer` is the existing precedent and this mirrors it.

**Files:**
- Test: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the test**

Add to `scripts/core/RulesTest.gd`, after `_test_trail_memory()`:

```gdscript
# The trail is a DISPLAY record and must never leak into the rules.
#
# Same shape as _test_landmarks_do_not_move_the_racer, and for the same reason:
# `trail` hangs off the Racer, so it is REACHABLE from every movement rule even
# though none may read it. That is the failure hardest to notice by eye -- a
# rule that started consulting the trail would still pass every other test in
# this file, because every other test drives a racer whose trail happens to
# match its history.
#
# Driven as two racers on the same seed, one with the line maxed and one with it
# untaken. The upgrade changes what is remembered and drawn; it must change
# nothing about where the racer goes or what it costs.
func _test_trail_memory_does_not_move_the_racer() -> void:
	var m1 := _make_corridor(40)
	var m2 := _make_corridor(40)

	var plain := Upgrades.new(1)
	var lit := Upgrades.new(1)
	for i in 6:
		lit.take(Upgrades.Line.TRAIL_MEMORY)

	var a := Racer.new()
	a.setup(m1, plain)
	var b := Racer.new()
	b.setup(m2, lit)

	var diverged := 0
	for i in 1200:
		a.step(1.0 / 60.0)
		b.step(1.0 / 60.0)
		if a.cell != b.cell \
				or absf(a.progress - b.progress) > 0.0001 \
				or absf(a.speed - b.speed) > 0.0001 \
				or a.facing != b.facing \
				or a.hp != b.hp:
			diverged += 1

	check_eq("the trail line never moves the racer", diverged, 0)
	check("the lit racer did record a trail", b.trail.count() > 1)
	check("the plain racer records one too", a.trail.count() > 1)
```

Register it in `_init()` after `_test_trail_memory()`:

```gdscript
	_test_trail_memory()
	_test_trail_memory_does_not_move_the_racer()
```

- [ ] **Step 2: Run the test**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS. If it fails, a movement rule is reading `trail` or `trail_clock` — fix the rule, not the test.

- [ ] **Step 3: Commit**

```bash
git add scripts/core/RulesTest.gd
git commit -m "Assert the trail never reaches the movement rules"
```

---

### Task 5: The minimap tint

The map is the cheaper of the two renderings and needs no shader, so it lands first and gives a visible feature before the floor work begins.

**Files:**
- Modify: `scripts/ui/Minimap.gd`

- [ ] **Step 1: Add the trail colours**

In `scripts/ui/Minimap.gd`, add after the `COL_RING` constant:

```gdscript
# Trail Memory. Ground driven once lifts ABOVE the untrodden cell colour; every
# re-crossing takes it down, past COL_OPEN into near-black. Fresh ground is
# dark, ground you know glows, ground you have flogged is burnt out.
#
# The hue matches the world floor's TRAIL_COL so the two readings of the same
# record read as the same thing, but the VALUES are brighter here -- the same
# argument COL_GATE_SPENT records a few lines up. A map cell is a handful of
# pixels against an already-dark disc, where the floor is a large surface seen
# under fog and a headlight.
const COL_TRAIL_BY_VISITS := [
	Color(0.06, 0.09, 0.15, 0.75),   # 0 -- unused; untrodden draws COL_OPEN
	Color(0.20, 0.42, 0.62, 0.90),   # 1 -- lit
	Color(0.14, 0.29, 0.44, 0.88),   # 2
	Color(0.10, 0.19, 0.30, 0.85),   # 3
	Color(0.07, 0.12, 0.19, 0.82),   # 4
	Color(0.04, 0.06, 0.10, 0.80),   # 5+ -- burnt out
]
```

- [ ] **Step 2: Tint the cell**

In `scripts/ui/Minimap.gd`, in `_draw_cell()`, replace this block:

```gdscript
	var colour := COL_OPEN
	if cell == racer.maze.exit_cell:
```

with:

```gdscript
	var colour := COL_OPEN

	# Trail Memory, drawn BENEATH every other cell state. The exit, gates and
	# spent gates all override it: those answer "where am I going" and "what have
	# I opened", which are worth more at a glance than "have I been here", and a
	# gate whose square went grey with re-crossings would be a gate the player
	# could no longer find.
	if upgrades.has_trail_memory():
		var lit := racer.trail.intensity(
			cell, racer.trail_clock, upgrades.trail_memory_window())
		if lit > 0.0:
			var v := mini(racer.trail.visits(cell), COL_TRAIL_BY_VISITS.size() - 1)
			colour = COL_OPEN.lerp(COL_TRAIL_BY_VISITS[v], lit)

	if cell == racer.maze.exit_cell:
```

- [ ] **Step 3: Verify it draws**

Run the shot tool and look at the map:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/Screenshot.gd
```

Then read `logs/errors.log` and confirm it is clean:
```bash
cat logs/errors.log
```
Expected: no errors. (The saved frames land in `logs/`; the minimap tint is checked properly by `TrailMemoryShot` in Task 10, which drives re-crossed ground on purpose.)

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/Minimap.gd
git commit -m "Tint remembered ground on the minimap"
```

---

### Task 6: The floor shader

The floor plane becomes a `ShaderMaterial` reading a per-cell texture. One draw call, unchanged; lighting a cell becomes a single pixel write.

**Files:**
- Modify: `scripts/core/MazeMesh.gd`

- [ ] **Step 1: Add the shader source and the texture**

In `scripts/core/MazeMesh.gd`, add near the other constants at the top of the file (after the `class_name MazeMesh` / `extends` lines and any existing consts):

```gdscript
# The floor's trail shader. One texel per cell holds how brightly that cell is
# remembered; the shader mixes it over the palette floor.
#
# Written in-code via Shader.new() rather than as a .gdshader resource, matching
# GoldenTrail -- and kept to plain GLSL ES 3.0 features, because the web build
# runs gl_compatibility (WebGL2) while the desktop build runs Forward+, and the
# same source has to compile on both.
#
# The texture is sampled with NEAREST filtering and no mipmaps: a cell is a hard
# square of memory, not a smooth field, and linear filtering would bleed the
# tint a half cell past the walls it stops at.
const FLOOR_SHADER_SOURCE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_col : source_color;
uniform vec3 trail_col : source_color;
uniform float trail_mix;
uniform sampler2D trail_tex : filter_nearest, repeat_disable, hint_default_black;
uniform vec2 grid_size;
uniform float cell_size;
uniform float origin_offset;
uniform float roughness_v;
uniform float metallic_v;

varying vec2 cell_uv;

void vertex() {
	// The cell coordinate is computed HERE, in the vertex stage, where model
	// space is actually available. In a fragment shader Godot 4's VERTEX is
	// VIEW space, not model space, so deriving a world position there needs
	// INV_VIEW_MATRIX and is easy to get subtly wrong -- and the floor is a
	// flat, axis-aligned plane, so there is nothing a per-fragment derivation
	// would buy. The rasteriser interpolates this exactly.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cell_uv = (world.xz + vec2(origin_offset)) / cell_size;
}

void fragment() {
	// Cell coordinate to the centre of that cell's texel. Sampling the centre
	// rather than the corner is what keeps a cell a hard square under NEAREST
	// filtering -- a corner sample sits exactly on the boundary between two
	// texels and picks whichever way the rounding falls.
	vec2 uv = (floor(cell_uv) + 0.5) / grid_size;

	float lit = 0.5;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		lit = texture(trail_tex, uv).r;
	}

	// The stored value is a signed tint packed into 0..1: 0.5 is untrodden,
	// above lifts the floor, below darkens it. Packing it that way keeps the
	// texture single-channel and 8-bit, which is what makes a per-cell write
	// cheap at 100x100.
	float signed_lit = (lit - 0.5) * 2.0;

	vec3 col = base_col;
	if (signed_lit > 0.0) {
		col = mix(base_col, trail_col, trail_mix * signed_lit);
		col *= 1.0 + signed_lit * 2.4;
	} else {
		col = base_col * (1.0 + signed_lit * 0.85);
	}

	ALBEDO = col;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
}
"""

# The floor's trail texture, one texel per cell. Held here because the floor
# material owns it; TrailFloor writes to it each frame.
var trail_texture: ImageTexture
var trail_image: Image
var _floor_material: ShaderMaterial
```

- [ ] **Step 2: Build the floor with it**

In `scripts/core/MazeMesh.gd`, replace the body of `_build_floor()` (lines 58-81) with:

```gdscript
func _build_floor() -> void:
	var size_x := _maze.width * Tuning.CELL_SIZE
	var size_z := _maze.height * Tuning.CELL_SIZE

	var plane := PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)

	# One texel per cell, single-channel. 0.5 is untrodden -- see the shader's
	# note on the signed packing. Rebuilt per maze because the grid changes size.
	trail_image = Image.create(_maze.width, _maze.height, false, Image.FORMAT_R8)
	trail_image.fill(Color(0.5, 0.5, 0.5))
	trail_texture = ImageTexture.create_from_image(trail_image)

	var shader := Shader.new()
	shader.code = FLOOR_SHADER_SOURCE

	_floor_material = ShaderMaterial.new()
	_floor_material.shader = shader
	var floor_col: Color = _palette["floor"]
	_floor_material.set_shader_parameter("base_col",
		Vector3(floor_col.r, floor_col.g, floor_col.b))
	_floor_material.set_shader_parameter("trail_col",
		Vector3(Tuning.TRAIL_COL.r, Tuning.TRAIL_COL.g, Tuning.TRAIL_COL.b))
	_floor_material.set_shader_parameter("trail_mix", Tuning.TRAIL_COL_MIX)
	_floor_material.set_shader_parameter("trail_tex", trail_texture)
	_floor_material.set_shader_parameter("grid_size",
		Vector2(float(_maze.width), float(_maze.height)))
	_floor_material.set_shader_parameter("cell_size", Tuning.CELL_SIZE)
	_floor_material.set_shader_parameter("origin_offset", Tuning.CELL_SIZE * 0.5)
	_floor_material.set_shader_parameter("roughness_v", 0.65)
	_floor_material.set_shader_parameter("metallic_v", 0.1)

	plane.material = _floor_material

	var instance := MeshInstance3D.new()
	instance.mesh = plane
	# PlaneMesh is centred on its origin; cell centres run from 0 to (n-1)*size,
	# so the centre of the grid sits half a cell short of half the full extent.
	instance.position = Vector3(
		size_x * 0.5 - Tuning.CELL_SIZE * 0.5,
		0.0,
		size_z * 0.5 - Tuning.CELL_SIZE * 0.5
	)
	add_child(instance)
```

> **If the trail never appears, suspect the image format before the shader.**
> `FORMAT_R8` is the right storage — one byte per cell — but `Image.set_pixel`
> takes a `Color` and writes through a format conversion, and a single-channel
> format keeps only `.r`. If a per-cell write reads back as zero, switch the
> image to `FORMAT_RGBA8` and confirm the value lands before touching the
> shader. The cost is four bytes a cell instead of one, which at 100x100 is
> 40KB — irrelevant. Diagnose it with a direct read-back
> (`trail_image.get_pixel(x, y).r` immediately after a `set_pixel`), not by
> looking at the floor: a floor that renders correctly at neutral is exactly
> what a failed write looks like.

- [ ] **Step 3: Verify the shader compiles**

A shader that fails to compile writes to the error log and renders the floor as a flat fallback — which looks like a palette bug rather than a shader one, so check the log rather than the picture.

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Quit 8
```
Then:
```bash
cat logs/errors.log
```
Expected: no shader compilation errors. If the log names a line in the shader, fix it there — the most likely cause is a `gl_compatibility` restriction, since that renderer is stricter than Forward+.

- [ ] **Step 4: Commit**

```bash
git add scripts/core/MazeMesh.gd
git commit -m "Give the floor a trail shader and per-cell texture"
```

---

### Task 7: Driving the floor texture

**Files:**
- Create: `scripts/core/TrailFloor.gd`
- Modify: `scripts/core/Game.gd`

- [ ] **Step 1: Write the driver**

Create `scripts/core/TrailFloor.gd`:

```gdscript
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
		var signed := clampf((tint - 1.0) / 2.4, -1.0, 1.0) * lit
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
```

- [ ] **Step 2: Add the node to Game**

In `scripts/core/Game.gd`, add the field beside the other world-node fields (after `var _mesh: MazeMesh` on line 69):

```gdscript
var _trail_floor: TrailFloor
```

And construct it in `_ready`, immediately after the `_mesh` block (after line 123, `_world.add_child(_mesh)`):

```gdscript
	_trail_floor = TrailFloor.new()
	_trail_floor.name = "TrailFloor"
	add_child(_trail_floor)
```

- [ ] **Step 3: Wire it per maze**

In `scripts/core/Game.gd`, in `_start_maze()`, add immediately after the `_mesh.build(maze, palette_index)` line:

```gdscript
	_mesh.build(maze, palette_index)
	# After build(), which is what creates the maze's trail image and texture --
	# they are sized to the grid, so a handle taken before the build is a handle
	# to the previous maze's texture.
	_trail_floor.set_mesh(_mesh)
	_apply_palette(palette_index)
```

- [ ] **Step 4: Drive it each frame**

In `scripts/core/Game.gd`, in `_process()`, add after the `_path_indicator` block (after line 802):

```gdscript
	# RACING only. During a card screen the clock is stopped and the trail is
	# static, so there is nothing to update -- and unlike the Path Indicator
	# there are no panels whose geometry would change under the player.
	if _trail_floor and phase == Phase.RACING:
		_trail_floor.update_state(racer, upgrades)
```

- [ ] **Step 5: Re-import and run**

`TrailFloor` is a new `class_name`, so the project needs re-importing before it resolves.

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Quit 12
```
Then:
```bash
cat logs/errors.log
```
Expected: clean log.

- [ ] **Step 6: Commit**

```bash
git add scripts/core/TrailFloor.gd scripts/core/Game.gd
git commit -m "Paint the trail onto the floor texture"
```

---

### Task 8: Scene-level assertions

`SceneTest` answers what `RulesTest` structurally cannot: that the floor is actually wired to the record. A shader that never receives its texture renders a perfectly plausible plain floor.

**Files:**
- Modify: `scripts/core/SceneTest.gd`

- [ ] **Step 1: Write the test**

`SceneTest` holds `game` as a LOCAL in `_run()`, not as a member, and every check
takes it as a parameter — `_check_path_indicator(game)`, `_check_rear_view(game)`
and so on. It also has **no `check_near`**; only `check(label, condition, detail)`.
Follow both, or the file will not parse.

Add to `scripts/core/SceneTest.gd`, alongside the other `_check_*` functions:

```gdscript
# The trail floor's wiring.
#
# RulesTest owns whether the RECORD is right; this owns whether anything is
# connected to it. The failure it catches is a floor whose shader never receives
# its texture -- which renders as an ordinary floor, looks entirely correct, and
# is indistinguishable by eye from a player who simply has not driven anywhere.
func _check_trail_floor(game) -> void:
	var mesh: MazeMesh = game._mesh
	check("the floor has a trail image", mesh.trail_image != null)
	check("the floor has a trail texture", mesh.trail_texture != null)
	if mesh.trail_image == null:
		return

	# Sized to the GRID, not to a constant. A texture sized off a literal would
	# be right for maze 1 and wrong for every maze after it -- the same failure
	# a test that restates a tuning number has (CLAUDE.md section 12).
	check("the trail image is grid-width",
		mesh.trail_image.get_width() == game.maze.width,
		"got %d, expected %d" % [mesh.trail_image.get_width(), game.maze.width])
	check("the trail image is grid-height",
		mesh.trail_image.get_height() == game.maze.height,
		"got %d, expected %d" % [mesh.trail_image.get_height(), game.maze.height])

	# With the line untaken, driving must leave the floor untouched. The record
	# fills up regardless, so this is what proves the upgrade gates the DRAWING
	# rather than the recording.
	game.upgrades.ranks[Upgrades.Line.TRAIL_MEMORY] = 0
	var cell_before: Vector2i = game.racer.cell
	var before: float = mesh.trail_image.get_pixel(cell_before.x, cell_before.y).r
	for i in 30:
		game._process(1.0 / 60.0)
	# Re-read the mesh and racer AFTER the loop: _process can finish a maze and
	# build a new Racer on a new grid with a new trail image, and a handle taken
	# before it is then an orphan (CLAUDE.md section 12, the stale-reference
	# trap -- it fired on ~1 run in 5 on exactly one frame).
	var mesh2: MazeMesh = game._mesh
	var after := before
	if mesh2 == mesh and mesh2.trail_image != null:
		after = mesh2.trail_image.get_pixel(cell_before.x, cell_before.y).r
	check("an untaken line paints nothing", absf(after - before) < 0.01,
		"got %f, expected %f" % [after, before])

	# Take the line and ground already driven lights up, WITHOUT the racer
	# having to cover it again -- the record was kept all along.
	game.upgrades.ranks[Upgrades.Line.TRAIL_MEMORY] = 1
	game._process(1.0 / 60.0)

	var mesh3: MazeMesh = game._mesh
	var cell: Vector2i = game.racer.cell
	var lit: float = mesh3.trail_image.get_pixel(cell.x, cell.y).r
	check("holding the line lights driven ground", lit > TrailFloor.NEUTRAL + 0.01,
		"got %f" % lit)

	# Leave the line where the rest of the harness expects it. A check that
	# hands the next one an unexpected build is the inherited-state trap section
	# 12 records -- SceneTest runs its checks in sequence against one Game.
	game.upgrades.ranks[Upgrades.Line.TRAIL_MEMORY] = 0
```

Register it in `_run()` beside the other `_check_*(game)` calls — put it after
`_check_path_indicator(game)`, since both read the floor:

```gdscript
	_check_trail_floor(game)
```

- [ ] **Step 2: Run the test**

Run:
```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SceneTest.gd
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/core/SceneTest.gd
git commit -m "Assert the trail floor is wired to the record"
```

---

### Task 9: Check the whole suite still passes

Adding an upgrade line changes the card pool and the picks-versus-ranks ledger CLAUDE.md §7 tracks, so `RunTest` needs reading, not just running.

**Files:** none modified unless a harness fails.

- [ ] **Step 1: Run every harness**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SceneTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/TrailerTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/MusicTest.gd
```
Expected: `RESULT: PASS` on all five.

- [ ] **Step 2: Run a full autopilot run and read the ledger**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RunTest.gd
```

Read the output for two things:
- the run completes all five mazes
- the `note:` line about the picks-versus-ranks ledger. The tree was 48 ranks against 45 picks; this adds 6, making it 54 against 45. The gap widens, which is the safe direction — the failure §7 cares about is a tree *smaller* than the pick count, where the last picks have nothing to take.

- [ ] **Step 3: Commit only if a harness needed fixing**

```bash
git add -A
git commit -m "Keep the harnesses green with the new upgrade line"
```

---

### Task 10: The picture half

Every visual feature in this project has a shot tool, because a rendered frame is the only thing that catches what a headless assertion cannot. This one has a specific requirement: it must shoot **re-crossed** ground, since a trail of all-single-visit cells shows one tint and proves nothing about the darkening.

**Files:**
- Create: `scripts/core/TrailMemoryShot.gd`

- [ ] **Step 1: Write the tool**

Create `scripts/core/TrailMemoryShot.gd`:

```gdscript
# The picture half of Trail Memory. SceneTest proves the floor is wired to the
# record; only a rendered frame says whether the tint reads.
#
# It DRIVES A LOOP on purpose rather than shooting on a timer. The whole subject
# is how re-crossed ground reads against ground driven once -- and an optimal
# router never re-crosses anything, so a timed shot would show a uniform trail
# and could not tell the darkening rule from no darkening rule at all. Same
# reasoning as PaletteShot seeking a junction and RearViewShot seeking a corner.
#
# Two frames per maze: one down a stretch driven once, and one after pacing the
# same corridor several times.
extends SceneTree

var _game: Node
var _frame := 0
var _maze_index := 0
var _shot := 0
var _last_cell := Vector2i(-999, -999)
# Laps paced once the first frame is taken. The second shot waits on this, since
# the darkening is what it exists to show.
var _laps := 0
var _lap_cells := 0

const SETTLE := 200
const LAPS_WANTED := 4
const LAP_CELLS := 5
const GIVE_UP := SETTLE * 12


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)

	# Maxed, so nothing expires mid-shot -- the fade is a separate question and
	# a cell lapsing between the two frames would confound the comparison.
	for i in 6:
		_game.upgrades.take(Upgrades.Line.TRAIL_MEMORY)
	# The map up, so the shot shows both renderings of the same record together.
	_game.upgrades.take(Upgrades.Line.MINIMAP)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	var ready := false
	if _shot == 0:
		ready = _frame >= SETTLE
	else:
		ready = _laps >= LAPS_WANTED

	if not ready and _frame < GIVE_UP:
		return
	_frame = 0

	_capture(_maze_index, _shot)
	_shot += 1
	if _shot < 2:
		return

	_shot = 0
	_laps = 0
	_lap_cells = 0
	_maze_index += 1
	if _maze_index >= Tuning.MAZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	_game._start_maze(_maze_index)
	_last_cell = Vector2i(-999, -999)


func _autopilot() -> void:
	var racer: Racer = _game.racer
	# An instrument, not a player: a card screen up is a stall. Covers the
	# maze-start loadout as well as a gate pick.
	if int(_game.phase) == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(offered[0])
		return

	if racer == null or _game.phase != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	if racer.cell == _last_cell:
		return
	_last_cell = racer.cell

	# After the first frame, pace back and forth over the SAME cells rather than
	# routing onward -- that is what produces ground with four crossings on it.
	#
	# Paced by CELLS COVERED, never on a frame count. RepeatProbe records what
	# that costs: its farming driver reversed on a frame interval, which at the
	# 1x start speed never left the opening cell and reported zero repeats --
	# reading exactly like the feature failing when nothing had been driven.
	if _shot >= 1:
		_lap_cells += 1
		if _lap_cells >= LAP_CELLS:
			_lap_cells = 0
			_laps += 1
			racer.request_reverse()
		return

	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return
	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


func _capture(index: int, shot: int) -> void:
	var image := root.get_texture().get_image()
	var maze_name := String(Tuning.MAZES[index]["name"]).to_lower().replace(" ", "_")
	var kind := "fresh" if shot == 0 else "worn"
	var path := "res://logs/trail_%d_%s_%s.png" % [index + 1, maze_name, kind]
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, %d cells remembered, %d laps)" % [
			path, _game.racer.cell, _game.racer.trail.count(), _laps])
	else:
		printerr("FAILED to save %s" % path)
```

- [ ] **Step 2: Run it**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/TrailMemoryShot.gd
```

Note: this needs a rendered frame, so it must run **without** `-Headless` if the headless run produces blank images:

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Script res://scripts/core/TrailMemoryShot.gd
```

- [ ] **Step 3: Look at the frames**

Read the saved images from `logs/` and check three things:
1. Driven ground is visibly lit against untrodden floor.
2. The `_worn` frames are visibly **darker** on the paced corridor than the `_fresh` frames.
3. The grid lines are still the dominant marking on the floor — CLAUDE.md §11.3 makes them the timing contract, and a trail wash that swamps them is a regression, however good it looks. If it does, lower `Tuning.TRAIL_COL_MIX`.

- [ ] **Step 4: Commit**

```bash
git add scripts/core/TrailMemoryShot.gd
git commit -m "Add the Trail Memory shot tool"
```

---

### Task 11: The design record

CLAUDE.md is the source of truth for the design, and this change lands a new upgrade line plus a rendering technique the project has not used before. Per the working practices, this happens **once the change is confirmed working**, which is why it is last.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the line to the upgrade table**

In `CLAUDE.md` §7, add a row to the "Upgrade lines" table, after **Wall Armor**:

```markdown
| **Trail Memory** | Ground you have driven is tinted on the floor and the minimap — lit on the first pass, darker with every re-crossing. Remembered for 1:00 / 1:30 / 2:00 / 2:30 / 3:00 / the rest of the maze | Six ranks. Answers "have I been here", never "which way" — the §6 line, and the only *paid* line on that side of it |
```

- [ ] **Step 2: Write the section**

Add to `CLAUDE.md` §7, after the "Path Indicator is a strip on the floor" section:

```markdown
### Trail Memory paints where you have been

**Ground the player has driven is tinted, on the maze floor and on the minimap.**
A cell driven once lifts *above* the palette floor; every re-crossing takes it down,
past the base floor into shadow. Fresh ground is dark, ground you know glows, ground
you have flogged is burnt out.

**It answers "have I been here", never "which way"** — the same line landmarks (§6),
spent gate markers (§7) and the rear-view mirror (§12) sit on. Everything it shows is
ground the player has already covered, so it adds **memory**, not routing, and cannot
cannibalise Path Indicator, Gate Compass or Golden Trail. It is the only *paid* line on
that side of the divide, which makes it the strongest statement of the position rather
than a departure from it.

**The lit-then-darkening shape is not the same as "darker every visit"**, and the
difference is forced by the palettes. Every maze's floor sits under 0.08 — a strictly
monotonic dimming has nowhere to go, so the first few visits would be indistinguishable
from each other and from untrodden ground. Lifting on the first visit gives the scale
somewhere to start, and it puts the brightest reading on the most useful fact: *this is
ground you have seen once*.

**The ranks are a memory DURATION, which is the one place this deliberately departs from
§4.** The buffer is measured in cells precisely so forgiveness does not grow with speed.
This is not forgiveness, it is memory — and "the last minute of driving" is the thing a
player actually wants to hold. It does mean the trail covers more ground at 8x, which is
correct: at 8x you have genuinely driven more ground in that minute.

Sized against the 180s maze budget (§8b): rank 1 at 60s is a third of a maze, enough to
recognise a loop you just closed and not enough to map the maze.

**A lapsing cell fades over 3s rather than snapping off.** Cells reach their deadlines
individually, so a hard cutoff would blink them out one at a time — which reads as a
rendering fault, not as memory. With a fade the tail of the trail visibly retreats, and
ranking up is *watching the tail stretch* rather than something you could only verify by
counting.

**The count expires with the cell**, so a lapsed cell reads as never driven. That is what
makes the top rank a difference in what is **known** rather than only in what is drawn.

**The record is kept whether or not the line is held.** The upgrade gates the *drawing*.
A player who takes it at gate 4 lights up the ground they have demonstrably already
covered, where gating the recording would hand them a blank trail through a maze they
have half-driven — the opposite of memory.

**It is a separate record from `Racer.visited`**, which looks like it covers the same
ground and does not. That dictionary holds a bool — "has this cell been re-entered" — and
exists to charge the §8b repeat-ground penalty once per cell. Widening it to carry counts
and timestamps would put a display feature inside a load-bearing scoring rule.

**The clock is the racer's own accumulated driving time, not a wall clock**, so the trail
stops ageing while the game is paused or a card screen is open. A memory that lapsed
during an upgrade pick would punish the player for reading their cards.

#### The floor is a shader over a per-cell texture

The floor is one `PlaneMesh`, and per-cell shading needs machinery it did not have. It
reads an `ImageTexture` holding **one texel per cell**, so lighting a cell is a single
pixel write — O(1), at any maze size, with no extra draw call.

**The two obvious alternatives are both traps this project has already paid for.**
Rebuilding a trail mesh when it changes is the `GoldenTrail` failure in §12 exactly — that
ribbon cost 23ms a frame and looked like a hang, and a maxed trail at maze 5 covers
thousands of cells. A pooled set of quads near the player (the `PathIndicator` pattern)
works for three strips at one junction and caps how much trail can exist, popping as the
pool re-assigns.

**The texture stores a signed value packed around 0.5** — above lifts, below darkens —
which is what keeps it single-channel and 8-bit.

**The upload is once per frame, not once per cell.** `ImageTexture.update` re-sends the
image to the GPU; doing that per changed cell would be hundreds of uploads a frame on a
busy trail.

**The shader is written in code and kept WebGL2-safe.** The web build runs
`gl_compatibility` while desktop runs Forward+ (§12), so the same source has to compile on
both. Sampled `filter_nearest`: a cell is a hard square of memory, and linear filtering
would bleed the tint half a cell past the walls it stops at.

**The tint stays a wash beneath the grid lines.** They are the timing contract (§11.3) and
must remain the dominant marking on the floor — `TRAIL_COL_MIX` is well under 1.0 for that
reason, and it is the number to lower if a future palette makes the trail compete.

**On the minimap the trail draws beneath every other cell state.** The exit, live gates and
spent gates all override it: those answer "where am I going" and "what have I opened",
which are worth more at a glance than "have I been here" — and a gate whose square went
grey with re-crossings would be a gate the player could no longer find.

**The map's trail colours are brighter than the floor's**, deliberately, exactly as
`COL_GATE_SPENT` is. A map cell is a handful of pixels on an already-dark disc; the floor
is a large surface seen under fog and a headlight. Matching the hue is what makes them read
as the same thing.

`RulesTest` asserts the record — counting, the fade, expiry resetting the count, the rank
windows — and asserts the **separation** directly, driving two racers on the same seed with
the line maxed and untaken and requiring they never diverge. That is the failure hardest to
notice: the trail hangs off the `Racer`, so it is *reachable* from every movement rule even
though none may read it, the same trap landmarks have (§6). `SceneTest` asserts the floor is
actually wired to the record, since a shader that never receives its texture renders a
perfectly plausible plain floor. `TrailMemoryShot.gd` is the picture half, and it **drives a loop**
rather than shooting on a timer — an optimal router never re-crosses anything, so a timed
shot would show a uniform trail and demonstrate nothing about the darkening that is the
whole point.
```

- [ ] **Step 3: Update the harness table**

In `CLAUDE.md` §12, extend the `RulesTest.gd` row's question list with:

```
the Trail Memory record -- visit counting, the expiry fade, the count resetting with the cell, the per-rank windows, and that none of it moves the racer
```

Extend the `SceneTest.gd` row with:

```
the trail floor's shader, its per-cell texture sized to the grid, and the upgrade gating the drawing rather than the recording
```

Add to the tools list, after the `RearViewShot.gd` paragraph:

```markdown
`TrailMemoryShot.gd` is the picture half of Trail Memory (§7): two frames per maze, one down a
stretch driven once and one looking back over ground crossed four times. It **drives a
loop** rather than shooting on a timer, for the reason `PaletteShot` seeks a junction — an
optimal router never re-crosses anything, so a timed shot shows a uniform trail and cannot
tell the darkening rule from a trail that has no darkening rule at all.
```

- [ ] **Step 4: Update the assertion counts**

The counts in the §12 harness table are stated exactly. Read the real numbers from the last runs and update `RulesTest`'s "358 assertions" and `SceneTest`'s "145 assertions" to match.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "Record the Trail Memory design"
```

---

## Verification checklist

Before calling this done, per `verification-before-completion` — every one of these must have been **run this session**, not assumed:

- [ ] `RulesTest` — `RESULT: PASS`
- [ ] `SceneTest` — `RESULT: PASS`
- [ ] `ShellTest` — `RESULT: PASS`
- [ ] `TrailerTest` — `RESULT: PASS`
- [ ] `MusicTest` — `RESULT: PASS`
- [ ] `RunTest` — completes five mazes; the picks-versus-ranks `note:` reads sanely
- [ ] `logs/errors.log` clean after a real launch (check its timestamp against the clock — §12 records three diagnoses made against a stale log)
- [ ] `TrailMemoryShot` frames: the trail is visible, re-crossed ground is visibly darker, and the grid lines still dominate the floor
