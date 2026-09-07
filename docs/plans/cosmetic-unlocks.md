# Cosmetic Unlocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Marker shapes, colours and decals start locked and are earned by
achievements, Geometry Dash style — every one visible from the first run with its
requirement named, so the picker is a goal list rather than a menu.

**Architecture:** One new autoload (`Unlocks`) owning both the achievement
definitions and the earned set, persisted beside the existing preferences.
Achievements are evaluated at exactly one point — the end of a run, where the
full `Score` is in hand. Nothing in the simulation may read it.

**Tech Stack:** Godot 4.7, GDScript. No new assets, no network.

---

## The rule this narrows, stated plainly

**§10 defers meta-progression**, and this plan makes something persist across
runs. The section reads:

> **Meta-progression.** Persistent unlocks across runs — new upgrade lines,
> starting bonuses, maze modifiers. Out of scope for v1; v1 is a single
> self-contained run.

**Every example it names changes how a run PLAYS.** An unlocked upgrade line, a
starting bonus and a maze modifier all make a veteran's run different from a
newcomer's — which is what "v1 is a single self-contained run" is protecting.

**A cosmetic changes nothing.** §12 already establishes that the marker's shape
is chosen freely and that *"nothing in the simulation may read the choice"*,
asserted by driving two racers side by side. An unlocked shape is the same shape;
the only difference is whether the picker offers it.

So the rule is **narrowed, not broken**: cosmetics unlock, and gameplay does not.
Jonah confirmed that scope explicitly. §10's deferral stands for everything it
actually names, and Task 7 rewrites the section to say so rather than leaving it
contradicting the code.

**The line to hold, forever:** if an unlock would change a number the racer
reads, it does not belong in this system.

---

## Why an achievement per colour, and what that forces

Jonah asked for colours as presets, each tied to an achievement. Two consequences
worth stating before any code:

**The achievement list is now load-bearing content, not decoration.** A colour
with no achievement is unreachable, so the two tables must not drift apart.
`RulesTest` asserts the pairing in both directions — every unlockable item has an
achievement that grants it, and every achievement grants something real.

**Achievements must be measurable from data the game already keeps.** `Score`
tracks clean turns, scraped turns, crashes, repeat cells and per-maze results;
`Upgrades` holds the finishing build. Most achievements are written against those
directly. The one genuinely missing signal is **peak speed**, which nothing
records — Task 2 adds it, and that is the only change this feature makes to a
file the simulation reads.

**Everything is evaluated at the END of a run**, at `_post_run`, which its own
comment already calls *"the only point at which a run is genuinely over"*. Not
during play: a mid-run unlock popup over a corridor at 8x is a distraction placed
exactly where §11.3 says the player has no attention to spare.

---

## The starting loadout is bare

Arrow, white, plain — the current defaults, and nothing else. Jonah chose this
over a starter set.

**It means a first-time player has no cosmetic choice at all**, which is the
cost, and it buys the thing the feature exists for: every entry in the picker is
something to earn. The picker still opens and still previews; it simply shows one
unlocked row and a wall of named goals.

**The default must never be lockable.** `Tuning.MARKER_SHAPE_DEFAULT`,
near-white, and `MARKER_DECAL_DEFAULT` are what a player falls back to when a
saved name no longer resolves (§12), so a locked default would strand them with
no marker. `RulesTest` asserts all three are unlocked from the start.

---

## File structure

- **Create `scripts/core/Unlocks.gd`** — the autoload. The `ACHIEVEMENTS` table,
  the earned set, persistence, and `evaluate(score, upgrades, …)`. Pure logic
  apart from the file I/O, so it is headlessly testable.
- **Modify `project.godot`** — register the autoload. **This is the step that was
  skipped for `Leaderboard`** (§9b-2: it was missing from `project.godot`
  entirely, so the feature was inert in every shipped build while looking
  correct). `ShellTest` asserts registration.
- **Modify `scripts/core/Tuning.gd`** — an `unlock` id on each shape and decal
  entry, plus the colour table moved here from `MarkerPicker`.
- **Modify `scripts/core/Score.gd`** — track peak speed.
- **Modify `scripts/core/Game.gd`** — evaluate achievements at `_post_run`.
- **Modify `scripts/ui/MarkerPicker.gd`** — draw locked entries with their
  requirement, and refuse to select them.
- **Modify `scripts/ui/RunSummary.gd`** — report what this run unlocked.
- **Modify `RulesTest.gd` / `ShellTest.gd`** — the table pairing, the evaluation,
  and the picker's refusal.
- **Modify `scripts/core/MarkerPickerShot.gd`** — shoot the locked state.

---

## Task 1: The unlock tables and their pairing assertion

The tables come first, and the assertion before them, because everything else
reads them.

**Files:**
- Create: `scripts/core/Unlocks.gd`
- Modify: `scripts/core/Tuning.gd`
- Modify: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

Add to `RulesTest.gd`, registered beside `_test_marker_decals()`.

The load-bearing assertion is the **pairing in both directions**. A cosmetic with
no achievement is permanently unreachable, and an achievement granting nothing is
a goal with no reward — both fail silently, and both are exactly the
parallel-array rot §6 records.

```gdscript
# The unlock tables (docs/plans/cosmetic-unlocks.md).
#
# Asserts the PAIRING, which is the property that rots. A cosmetic whose unlock
# id names no achievement is permanently unreachable; an achievement granting an
# id nothing offers is a goal with no reward. Both fail silently and neither is
# visible in any rendered frame -- the picker just shows a locked square forever.
func _test_unlocks() -> void:
	# Every achievement grants something that exists.
	for id in Unlocks.ACHIEVEMENTS:
		var entry: Dictionary = Unlocks.ACHIEVEMENTS[id]
		check("achievement %s has a label" % id,
			String(entry.get("label", "")) != "")
		check("achievement %s has a requirement line" % id,
			String(entry.get("requirement", "")) != "")
		check("achievement %s grants something" % id,
			not String(entry.get("grants", "")).is_empty())
		check("achievement %s grants a real cosmetic" % id,
			Unlocks.cosmetic_exists(String(entry["grants"])))

	# And every lockable cosmetic is granted by exactly one achievement.
	for id in Unlocks.lockable_ids():
		var granting := 0
		for aid in Unlocks.ACHIEVEMENTS:
			if String(Unlocks.ACHIEVEMENTS[aid]["grants"]) == id:
				granting += 1
		check("%s is unlockable" % id, granting >= 1)
		# More than one route to the same item makes the picker's requirement
		# line a lie: it can name only one of them.
		check("%s has exactly one achievement" % id, granting <= 1)

	# THE DEFAULTS ARE NEVER LOCKED. A saved name that no longer resolves falls
	# back to these (section 12), so a locked default strands the player with no
	# marker at all.
	var fresh := Unlocks.new()
	check("the default shape starts unlocked",
		fresh.is_unlocked(Tuning.MARKER_SHAPE_DEFAULT))
	check("the default decal starts unlocked",
		fresh.is_unlocked(Tuning.MARKER_DECAL_DEFAULT))
	check("the default colour starts unlocked",
		fresh.is_unlocked(Tuning.MARKER_COLOUR_DEFAULT))

	# And everything else starts LOCKED -- Jonah's choice of a bare starting
	# loadout. A default-unlocked table would make the whole feature invisible.
	var locked := 0
	for id in Unlocks.lockable_ids():
		if not fresh.is_unlocked(id):
			locked += 1
	check("most cosmetics start locked", locked >= Unlocks.lockable_ids().size() - 3)
```

- [ ] **Step 2: Run it and verify it fails**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: a parse error naming `Unlocks`. Correct at this step.

> §12: a new `class_name` is invisible until re-import. Re-run with `--import`
> once if the identifier is still unresolved after Step 3.

- [ ] **Step 3: Add the colour table to `Tuning`**

The swatches move out of `MarkerPicker` and into `Tuning`, because they are now
game content rather than a UI detail — `Unlocks` and `RulesTest` both need them,
and a table living in a screen would make the screen a dependency of the rules.

```gdscript
# --- Marker colours ----------------------------------------------------------
#
# PRESETS, not a wheel. Each one is unlocked by an achievement, so the set has to
# be enumerable and stable -- a free RGB picker cannot be earned.
#
# Stored by NAME like the shapes and decals, so reordering cannot re-point a
# saved choice or an earned unlock.
const MARKER_COLOUR_DEFAULT := "white"

const MARKER_COLOURS := [
	{"id": "white", "label": "WHITE", "colour": Color(1.0, 1.0, 1.0)},
	{"id": "ice", "label": "ICE", "colour": Color(0.30, 0.85, 1.0)},
	{"id": "cobalt", "label": "COBALT", "colour": Color(0.25, 0.55, 1.0)},
	{"id": "violet", "label": "VIOLET", "colour": Color(0.65, 0.45, 1.0)},
	{"id": "magenta", "label": "MAGENTA", "colour": Color(1.0, 0.40, 0.85)},
	{"id": "coral", "label": "CORAL", "colour": Color(1.0, 0.45, 0.35)},
	{"id": "gold", "label": "GOLD", "colour": Color(1.0, 0.80, 0.30)},
	{"id": "lime", "label": "LIME", "colour": Color(0.55, 0.95, 0.45)},
	{"id": "jade", "label": "JADE", "colour": Color(0.20, 0.85, 0.65)},
	{"id": "steel", "label": "STEEL", "colour": Color(0.75, 0.78, 0.85)},
]


static func marker_colour(id: String) -> Dictionary:
	for entry in MARKER_COLOURS:
		if entry["id"] == id:
			return entry
	for entry in MARKER_COLOURS:
		if entry["id"] == MARKER_COLOUR_DEFAULT:
			return entry
	return MARKER_COLOURS[0]
```

- [ ] **Step 4: Write `Unlocks.gd`**

Ids are namespaced (`shape:dart`, `colour:gold`, `decal:stripe`) so one earned
set covers all three kinds without three parallel dictionaries.

```gdscript
# What the player has earned, and what earns it.
#
# COSMETICS ONLY. CLAUDE.md section 10 defers meta-progression, and every example
# it names -- upgrade lines, starting bonuses, maze modifiers -- changes how a run
# PLAYS. That is what "v1 is a single self-contained run" protects. A marker
# shape changes nothing: section 12 already asserts that nothing in the
# simulation may read the choice, by driving two racers side by side.
#
# So the rule is narrowed rather than broken, and the line to hold is simple:
# if an unlock would change a number the racer reads, it does not belong here.
#
# Nothing in the simulation may read this autoload. Same separation landmarks
# (section 6), music (9c), touch controls (9d) and the marker picker have.
class_name Unlocks
extends Node

signal unlocked(ids: Array)

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "unlocks"

# Ids are NAMESPACED so one earned set covers shapes, colours and decals without
# three parallel dictionaries to keep in step.
const KIND_SHAPE := "shape"
const KIND_COLOUR := "colour"
const KIND_DECAL := "decal"


static func id_for(kind: String, name: String) -> String:
	return "%s:%s" % [kind, name]


# What each achievement asks for, and what it grants.
#
# Every requirement is measurable from data the game ALREADY keeps -- Score's
# tallies and per-maze results, and the finishing Upgrades. The one exception is
# peak speed, which Score gains in Task 2; that is the only change this feature
# makes to a file the simulation touches.
#
# "requirement" is shown verbatim in the picker under a locked entry, so it is
# written for a player rather than as a rule name.
const ACHIEVEMENTS := {
	# --- Shapes: earned by getting through the game -----------------------
	"first_blood": {
		"label": "FIRST BLOOD",
		"requirement": "Finish a run",
		"grants": "shape:dart",
	},
	"the_tangle": {
		"label": "INTO THE TANGLE",
		"requirement": "Reach maze 3",
		"grants": "shape:delta",
	},
	"the_vault": {
		"label": "THE VAULT",
		"requirement": "Reach maze 5",
		"grants": "shape:kite",
	},
	"clear_run": {
		"label": "ALL FIVE",
		"requirement": "Clear all five mazes",
		"grants": "shape:chevron",
	},
	"flawless": {
		"label": "FLAWLESS",
		"requirement": "Clear a maze without crashing",
		"grants": "shape:cycle",
	},

	# --- Colours: earned by HOW you drive ---------------------------------
	"ton_up": {
		"label": "TON UP",
		"requirement": "Reach 6x speed",
		"grants": "colour:ice",
	},
	"redline": {
		"label": "REDLINE",
		"requirement": "Reach 8x speed",
		"grants": "colour:coral",
	},
	"clean_hands": {
		"label": "CLEAN HANDS",
		"requirement": "Finish a maze without touching a wall",
		"grants": "colour:jade",
	},
	"wall_dancer": {
		"label": "WALL DANCER",
		"requirement": "Escape 50 scrapes in one run",
		"grants": "colour:gold",
	},
	"no_looking_back": {
		"label": "NO LOOKING BACK",
		"requirement": "Clear a maze without re-crossing a cell",
		"grants": "colour:cobalt",
	},
	"century": {
		"label": "CENTURY",
		"requirement": "Bank 100,000 points in a run",
		"grants": "colour:magenta",
	},
	"half_million": {
		"label": "HALF A MILLION",
		"requirement": "Bank 500,000 points in a run",
		"grants": "colour:violet",
	},
	"survivor": {
		"label": "SURVIVOR",
		"requirement": "Finish a run with HP in single figures",
		"grants": "colour:steel",
	},
	"cornerer": {
		"label": "CORNERER",
		"requirement": "Take 500 clean turns in one run",
		"grants": "colour:lime",
	},

	# --- Decals: earned by what you BUILD ---------------------------------
	"legend": {
		"label": "LEGEND",
		"requirement": "Hold a legendary upgrade",
		"grants": "decal:stripe",
	},
	"maxed": {
		"label": "MAXED",
		"requirement": "Take a line to its highest rank",
		"grants": "decal:notch",
	},
	"specialist": {
		"label": "SPECIALIST",
		"requirement": "Finish a run holding 12 upgrade lines",
		"grants": "decal:tip",
	},
	"the_long_way": {
		"label": "THE LONG WAY",
		"requirement": "Collect all 8 gates in a maze",
		"grants": "decal:split",
	},
}


var earned := {}


func _ready() -> void:
	_load()


func is_unlocked(id: String) -> bool:
	# A bare name (no namespace) is a default id -- the shape, colour and decal
	# defaults are never lockable and never appear in the granted set.
	if _is_default(id):
		return true
	return bool(earned.get(id, false))


func _is_default(id: String) -> bool:
	return id == Tuning.MARKER_SHAPE_DEFAULT \
		or id == Tuning.MARKER_DECAL_DEFAULT \
		or id == Tuning.MARKER_COLOUR_DEFAULT \
		or id == id_for(KIND_SHAPE, Tuning.MARKER_SHAPE_DEFAULT) \
		or id == id_for(KIND_DECAL, Tuning.MARKER_DECAL_DEFAULT) \
		or id == id_for(KIND_COLOUR, Tuning.MARKER_COLOUR_DEFAULT)


# Every cosmetic that CAN be locked -- i.e. everything but the three defaults.
static func lockable_ids() -> Array:
	var out: Array = []
	for shape in Tuning.MARKER_SHAPES:
		if String(shape["id"]) != Tuning.MARKER_SHAPE_DEFAULT:
			out.append(id_for(KIND_SHAPE, String(shape["id"])))
	for entry in Tuning.MARKER_COLOURS:
		if String(entry["id"]) != Tuning.MARKER_COLOUR_DEFAULT:
			out.append(id_for(KIND_COLOUR, String(entry["id"])))
	for decal in Tuning.MARKER_DECALS:
		if String(decal["id"]) != Tuning.MARKER_DECAL_DEFAULT:
			out.append(id_for(KIND_DECAL, String(decal["id"])))
	return out


# Does a namespaced id name something that actually exists? This is what stops
# an achievement granting a typo forever.
static func cosmetic_exists(id: String) -> bool:
	var parts := id.split(":")
	if parts.size() != 2:
		return false
	match parts[0]:
		KIND_SHAPE:
			return String(Tuning.marker_shape(parts[1])["id"]) == parts[1]
		KIND_COLOUR:
			return String(Tuning.marker_colour(parts[1])["id"]) == parts[1]
		KIND_DECAL:
			return String(Tuning.marker_decal(parts[1])["id"]) == parts[1]
	return false


# The achievement granting an id, or an empty dictionary. This is what the
# picker prints under a locked entry.
static func achievement_for(id: String) -> Dictionary:
	for aid in ACHIEVEMENTS:
		if String(ACHIEVEMENTS[aid]["grants"]) == id:
			return ACHIEVEMENTS[aid]
	return {}


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	for id in config.get_section_keys(SECTION) if \
			config.has_section(SECTION) else []:
		earned[id] = bool(config.get_value(SECTION, id, false))


func _save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # keep the other sections
	for id in earned:
		config.set_value(SECTION, String(id), true)
	config.save(CONFIG_PATH)
```

- [ ] **Step 5: Run and verify it passes**

Expected: PASS. Read `logs/errors.log`.

- [ ] **Step 6: Verify the pairing check can fail**

A test that cannot fail is not evidence — §9d records two false positives in this
codebase. Temporarily change one achievement's `grants` to `"colour:puce"`.

Expected: FAIL at `achievement century grants a real cosmetic` **and** at
`colour:magenta is unlockable`, since nothing now grants it. Two failures from
one typo is the pairing working in both directions. Restore and confirm green.

- [ ] **Step 7: Commit**

```bash
git add scripts/core/Unlocks.gd scripts/core/Tuning.gd scripts/core/RulesTest.gd docs/plans/cosmetic-unlocks.md
git commit -m "Add the cosmetic unlock tables, paired in both directions

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: Track peak speed

The one signal the achievements need that nothing records.

**Files:**
- Modify: `scripts/core/Score.gd`
- Modify: `scripts/core/Game.gd`
- Modify: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# Peak speed is remembered across a whole run.
#
# Per RUN, not per maze: "reach 8x" is a thing the player did, and resetting it
# at a maze boundary would make the achievement depend on WHERE the speed was
# reached rather than whether it was.
func _test_peak_speed() -> void:
	var s := Score.new()
	check("peak speed starts at zero", s.peak_speed == 0.0)
	s.note_speed(3.0)
	s.note_speed(6.5)
	s.note_speed(2.0)
	check_eq("peak speed keeps the maximum", s.peak_speed, 6.5)
	s.bank_maze(0, "The Grid")
	s.note_speed(1.0)
	check_eq("peak speed survives banking a maze", s.peak_speed, 6.5)
```

- [ ] **Step 2: Run it and verify it fails**

Expected: FAIL — `peak_speed` does not exist.

- [ ] **Step 3: Add it**

In `Score.gd`, beside the other tallies:

```gdscript
# The fastest the racer went this RUN.
#
# Per run rather than per maze: "reach 8x" describes something the player did,
# and resetting at a maze boundary would make it depend on where the speed
# happened rather than whether it did. Not banked with a maze for the same
# reason.
var peak_speed := 0.0


func note_speed(speed: float) -> void:
	peak_speed = maxf(peak_speed, speed)
```

In `Game.gd`, call it where speed is already read each frame — beside the
existing HUD update, so there is exactly one place per frame that reads
`racer.speed` for reporting.

- [ ] **Step 4: Run and verify it passes**

- [ ] **Step 5: Commit**

```bash
git add scripts/core/Score.gd scripts/core/Game.gd scripts/core/RulesTest.gd
git commit -m "Track peak speed across a run

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: Evaluate achievements at the end of a run

**Files:**
- Modify: `scripts/core/Unlocks.gd`
- Modify: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

Drive real `Score` and `Upgrades` objects rather than a stub, so the evaluation
is tested against the shapes it will actually receive.

```gdscript
# Achievements are awarded from a finished run, and only from a finished run.
func _test_achievement_evaluation() -> void:
	var u := Unlocks.new()

	# A weak run unlocks the entry-level achievement and little else.
	var weak := Score.new()
	weak.bank_maze(0, "The Grid")
	var got: Array = u.evaluate(weak, Upgrades.new(1), 0, 50, false)
	check("finishing a run grants the first shape",
		u.is_unlocked("shape:dart"))

	# Speed achievements read the peak.
	var fast := Score.new()
	fast.note_speed(8.2)
	u.evaluate(fast, Upgrades.new(1), 0, 50, false)
	check("6x unlocks ice", u.is_unlocked("colour:ice"))
	check("8x unlocks coral", u.is_unlocked("colour:coral"))

	# ALREADY-EARNED items are not re-reported. The summary lists what THIS run
	# unlocked, so a re-award would show the same achievement every run forever.
	var again: Array = u.evaluate(fast, Upgrades.new(1), 0, 50, false)
	check("an already-earned achievement is not re-reported",
		not again.has("ton_up"))

	# A locked item is genuinely locked before it is earned.
	var fresh := Unlocks.new()
	check("violet starts locked", not fresh.is_unlocked("colour:violet"))
	var rich := Score.new()
	rich.banked = 600000.0
	fresh.evaluate(rich, Upgrades.new(1), 4, 50, true)
	check("half a million unlocks violet", fresh.is_unlocked("colour:violet"))
```

- [ ] **Step 2: Run it and verify it fails**

Expected: FAIL — `evaluate` does not exist.

- [ ] **Step 3: Implement `evaluate`**

```gdscript
# Award everything this run earned, and return only what was NEWLY earned.
#
# Called from exactly one place -- Game._post_run, whose own comment already
# calls it "the only point at which a run is genuinely over". Not evaluated
# during play: an unlock popup over a corridor at 8x is a distraction placed
# exactly where section 11.3 says the player has no attention to spare.
#
# Returns the new achievement ids so the summary can report them. Already-earned
# ones are excluded, or the same achievement would be announced every run.
func evaluate(score: Score, upgrades: Upgrades, maze_index: int,
		hp: int, cleared: bool) -> Array:
	var won: Array = []

	for aid in ACHIEVEMENTS:
		var granted := String(ACHIEVEMENTS[aid]["grants"])
		if is_unlocked(granted):
			continue
		if not _met(aid, score, upgrades, maze_index, hp, cleared):
			continue
		earned[granted] = true
		won.append(aid)

	if not won.is_empty():
		_save()
		unlocked.emit(won)
	return won


# Whether one achievement's requirement is met.
#
# Every branch reads data the game already keeps. Kept as one match rather than
# a callable per entry: a table of lambdas would put the requirement text and
# the test it describes in two places, which is the drift the card-text rule
# guards against (section 7).
func _met(aid: String, score: Score, upgrades: Upgrades, maze_index: int,
		hp: int, cleared: bool) -> bool:
	match aid:
		"first_blood": return true
		"the_tangle": return maze_index >= 2 or cleared
		"the_vault": return maze_index >= 4 or cleared
		"clear_run": return cleared
		"flawless": return score.crashes == 0 and not score.maze_results.is_empty()
		"ton_up": return score.peak_speed >= 6.0
		"redline": return score.peak_speed >= 8.0
		"clean_hands": return score.scraped_turns == 0 \
			and not score.maze_results.is_empty()
		"wall_dancer": return score.scraped_turns >= 50
		"no_looking_back": return score.repeat_cells == 0 \
			and not score.maze_results.is_empty()
		"century": return score.banked >= 100000.0
		"half_million": return score.banked >= 500000.0
		"survivor": return cleared and hp > 0 and hp < 10
		"cornerer": return score.clean_turns >= 500
		"legend": return upgrades.has_legendary()
		"maxed": return _has_a_maxed_line(upgrades)
		"specialist": return upgrades.started_line_count() >= 12
		"the_long_way": return _took_every_gate(score)
	return false


func _has_a_maxed_line(upgrades: Upgrades) -> bool:
	for line in Upgrades.DEFINITIONS:
		if upgrades.rank(line) > 0 and upgrades.is_maxed(line):
			return true
	return false


# Every gate in a maze taken.
#
# Read off `progress`, which a banked maze already carries: section 8b defines
# it as gates_taken / gates_in_maze, so 1.0 IS "took every gate". A death banks
# a partial maze at its real fraction, which is exactly the distinction wanted.
func _took_every_gate(score: Score) -> bool:
	for result in score.maze_results:
		if float(result.get("progress", 0.0)) >= 1.0:
			return true
	return false
```

> **Verified against the real structures before writing.** `Score.maze_results`
> carries `index`, `name`, `subtotal`, `time`, `multiplier`, `progress` and
> `score` — there is no `gates_taken` field, and no `Tuning.GATES_PER_MAZE`
> constant either (gates live per-maze in `Tuning.MAZES`). An earlier draft of
> this function used both and would not have parsed.
>
> **Do not add a field to `Score` to satisfy an achievement.** Pick a
> requirement the existing data supports, the way `progress` was picked here.
> `racer.hp` is real and is used directly.

- [ ] **Step 4: Run and verify it passes**

- [ ] **Step 5: Commit**

```bash
git add scripts/core/Unlocks.gd scripts/core/RulesTest.gd
git commit -m "Evaluate achievements from a finished run

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Register the autoload and wire it to the run

**Files:**
- Modify: `project.godot`
- Modify: `scripts/core/Game.gd`
- Modify: `scripts/core/ShellTest.gd`

> **This is the step that was skipped for `Leaderboard`.** §9b-2 records it
> plainly: the autoload was missing from `project.godot` entirely, so the feature
> was **inert in every build shipped**, and nothing looked broken because the
> panel drew its offline state correctly. The assertion below exists so that
> cannot happen twice.

- [ ] **Step 1: Write the failing test**

```gdscript
# The autoload is REGISTERED and processing.
#
# Leaderboard shipped inert for weeks because it was never added to
# project.godot, and every screen it fed looked correct while doing nothing
# (section 9b-2). A feature that persists across runs fails the same silent way:
# unlocks would simply never save, which is indistinguishable from not having
# earned anything.
func _test_unlocks_autoload() -> void:
	var node := get_node_or_null("/root/Unlocks")
	check("Unlocks is registered as an autoload", node != null)
	if node != null:
		check("Unlocks is the right class", node is Unlocks)
```

- [ ] **Step 2: Run it and verify it fails**

Expected: FAIL at `Unlocks is registered as an autoload`.

- [ ] **Step 3: Register it and evaluate at run end**

In `project.godot`, under `[autoload]`, beside the existing entries.

In `Game.gd`, at `_post_run` — the single point both terminal paths reach:

```gdscript
	# Achievements are evaluated HERE and nowhere else, for the reason this
	# function already exists: it is the only point at which a run is genuinely
	# over and its figures final. The result is handed to the summary rather
	# than announced separately, so a player reads what they earned in the same
	# place they read how they did.
	var unlocks := get_node_or_null("/root/Unlocks")
	var won: Array = []
	if unlocks != null:
		won = unlocks.evaluate(score, upgrades, maze_index,
			racer.hp if racer != null else 0, not died)
```

Guarded with `get_node_or_null`, because every harness that instantiates
`Game.tscn` bare has no autoloads — the same treatment `Settings`, `Music` and
`Leaderboard` get, and for the same reason: a missing autoload must never be what
stops a run finishing.

- [ ] **Step 4: Run every harness**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SceneTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RunTest.gd
```

`RunTest` matters here: it plays a complete run, so it is the first thing to
actually trigger an evaluation.

- [ ] **Step 5: Commit**

```bash
git add project.godot scripts/core/Game.gd scripts/core/ShellTest.gd
git commit -m "Register the Unlocks autoload and evaluate at run end

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: The picker shows locked items with their requirement

**Files:**
- Modify: `scripts/ui/MarkerPicker.gd`
- Modify: `scripts/core/ShellTest.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# A locked cosmetic cannot be selected, and the refusal is in the PICKER rather
# than left to the buttons being disabled.
#
# Disabling alone is not enough: the picker also restores a SAVED choice on open,
# and a player whose save names a since-locked item (a wiped settings file, a
# renamed table) must land on the default rather than on something they have not
# earned.
func _test_locked_cosmetics_are_refused() -> void:
	var picker := MarkerPicker.new()
	add_child(picker)
	await get_tree().process_frame

	# Find a shape that is locked on a fresh profile.
	var locked_index := -1
	for i in Tuning.MARKER_SHAPES.size():
		var id := Unlocks.id_for(Unlocks.KIND_SHAPE,
			String(Tuning.MARKER_SHAPES[i]["id"]))
		if not picker._unlocked(id):
			locked_index = i
			break

	check("something is locked on a fresh profile", locked_index != -1)
	if locked_index != -1:
		var before := picker._index
		picker._on_pick(locked_index)
		check("picking a locked shape does nothing",
			picker._index == before)

	picker.queue_free()
	await get_tree().process_frame
```

- [ ] **Step 2: Run it and verify it fails**

- [ ] **Step 3: Draw the locked state**

Three changes, each with a reason:

- **Locked entries are shown, not hidden.** Jonah chose this: the picker is a
  goal list, which is most of why the Geometry Dash version works. A hidden
  entry gives the player nothing to aim at.
- **The requirement is printed under the selected locked entry**, in the row the
  state label already occupies. Printing it on every locked button at once would
  need eighteen requirement lines on one card.
- **A locked entry is refused in `_on_pick`**, not merely `disabled` on the
  button — see the test's comment. It must also be refused on restore.

Swatches show locked colours as a dim outline of the colour rather than the
colour itself, so the player can see what they are working toward without it
reading as available.

- [ ] **Step 4: Run and verify it passes**

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/MarkerPicker.gd scripts/core/ShellTest.gd
git commit -m "Show locked cosmetics with the achievement that grants them

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: The summary reports what the run unlocked

**Files:**
- Modify: `scripts/ui/RunSummary.gd`
- Modify: `scripts/core/Game.gd`

- [ ] **Step 1: Add an unlocks block**

The summary already reports what the run *did* (§8c). What it earned belongs in
the same place, for the reason §8c gives for showing the repeat-cell cost: **a
rule the player cannot see the effect of is a mystery, not a rule.** An unlock
announced nowhere is one the player finds by accident later.

Shown only when the run unlocked something, so an ordinary run's summary is
unchanged.

- [ ] **Step 2: Shoot it**

`SummaryShot` builds the tallest case deliberately (§8c). Add unlocks to that
case, since it is the one that overruns — §8c records the panel running off the
screen edge and taking *"press SPACE or ESC to continue"* with it.

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Script res://scripts/ui/SummaryShot.gd -Quit 30
```

Read both frames. The panel is a `CenterContainer` sizing to its contents, so it
should absorb the extra rows — confirm rather than assume.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/RunSummary.gd scripts/core/Game.gd scripts/ui/SummaryShot.gd
git commit -m "Report new unlocks on the run summary

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: The picture half, then the docs

**Files:**
- Modify: `scripts/core/MarkerPickerShot.gd`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Shoot the locked picker**

The locked state is what a new player sees, so it is the frame that matters most
and the one no assertion can judge. Shoot a **fresh profile** — every requirement
line visible, one unlocked entry per row.

The tool must restore the earned set as well as the three preferences (§12: a
tool must not write the state it is inspecting). It already restores three; this
adds a fourth.

- [ ] **Step 2: Look at the frames**

- Are eighteen locked entries legible, or does the card overflow? The row width
  is derived rather than hard-coded (§12), but eighteen requirement strings is
  new content the layout has never carried.
- Does a locked swatch read as *locked* rather than as an ugly colour?
- Is the requirement line readable at the size it lands, or a smudge — the
  failure §7 records for the compass letter?

- [ ] **Step 3: Rewrite §10's meta-progression entry**

It currently forbids what this ships. Rewrite rather than delete, keeping the
reasoning:

- Cosmetic unlocks are IN, and why the rule was narrowed rather than broken:
  every example §10 names changes how a run plays, and a marker shape changes
  nothing — §12 already asserts the simulation cannot read the choice.
- The line to hold: if an unlock would change a number the racer reads, it does
  not belong in this system.
- Gameplay meta-progression stays deferred.
- That the achievement table and the cosmetic tables are asserted paired **in
  both directions**, since an unreachable cosmetic and a reward-less achievement
  both fail silently.
- That evaluation happens at `_post_run` only, and why.
- Updated harness counts, read off an actual run.

- [ ] **Step 4: Commit**

```bash
git add scripts/core/MarkerPickerShot.gd CLAUDE.md
git commit -m "Record the cosmetic unlock system and narrow the meta-progression rule

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **The §10 reversal is recorded, not hidden** — Task 7 lands it in CLAUDE.md,
  and this plan is the record until then.
- **The pairing is asserted in both directions**, because an unreachable cosmetic
  and a reward-less achievement are both invisible failures.
- **The autoload registration has its own assertion**, because `Leaderboard`
  shipped inert for weeks in exactly this way.
- **Tests can fail** — Task 1 Step 6 breaks a `grants` id and expects two
  failures from the one typo.
- **No new field is invented to satisfy an achievement.** Peak speed is the one
  addition, and Task 3 explicitly says to pick a different requirement rather
  than grow `Score` to fit `the_long_way`.
- **Defaults can never be locked**, asserted, because a locked default strands a
  player whose saved name no longer resolves.

## Open question for Jonah, before Task 5

**The decal system is currently unresolved** (see
`docs/plans/marker-colour-and-decals.md`): the pattern does not render, because
the mark is unshaded at emission 3.0 and saturates to white. Four decals are
therefore *unlockable but invisible*.

Two options: hold the four decal achievements until decals render, or ship them
and let the unlock land silently. **Shipping an achievement that grants something
invisible is worse than not shipping it**, so this plan assumes decals get fixed
first — Task 1's table can drop the four decal entries with no other change if
that slips.
