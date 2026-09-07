# Marker Colour and Decals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player choose the marker's **colour** freely and pick a
**decal** that patterns it, with every decal working on every shape — present and
future — by construction.

**Architecture:** Colour becomes a saved preference alongside the existing shape
choice. Decals are **generated from whatever outline they are given** rather than
authored per shape, so the shapes × decals grid never has to be filled in. The
state read (scrape-amber, crash-red) is moved onto a surface the player cannot
recolour, which is what keeps a free colour picker from destroying it.

**Tech Stack:** Godot 4.7, GDScript. No new assets.

---

## The rule this overturns, stated plainly

**CLAUDE.md §12 says near-white is mandatory and a colour picker is not offered.**
It gives two reasons, and this plan is accepted knowing both:

> Near-white stays mandatory. The marker went white because maze 3's palette
> turned the walls green and the thing the player steers with matched the scenery
> it has to be picked out from. A colour picker would hand that failure straight
> back — and worse, it would hand it back *chosen*, so the player who picked deep
> violet would be the one who could not see themselves in The Vault.

> Amber and red must keep reading as STATE. The scrape and crash colours work
> precisely because the resting marker carries no hue of its own.

**Jonah asked for the free picker after both objections were put, so this is a
decision rather than an oversight.** It is written down here the same turn it was
made, which is what §"Self-instructions" requires of a rule settled in
conversation. Anything in CLAUDE.md reading "every shape draws in the same
near-white" predates it.

**What the decision costs, honestly:** a player who picks a colour close to a
maze's neon can make their own marker hard to pick out in that maze. That is now
theirs to do. It is a cosmetic screen with a live preview and a reset, not a
trap — and unlike the maze-3 failure, it is *chosen and reversible* rather than
imposed by a palette the player never asked for.

**What is NOT given away, and must not be.** The state read is load-bearing
(§5.1 calls the barrier the most important read on screen), and it is not a
cosmetic choice. Task 2 exists entirely to protect it.

---

## Why the state read survives a free picker

`PlayerMarker.update_state` currently writes **the ring material only**:

```gdscript
	_ring_material.albedo_color = colour
	_ring_material.emission = colour
```

§12 already records this as a live defect:

> The marker's state colour is on the RING, which the trailing camera barely
> sees. `update_state` recolours only the ring material, so a scrape leaves the
> inner mark pure white — measured, a frame with the barrier bar visibly
> half-drained is pixel-identical to a clean one.

That defect and this feature have the **same fix**, which is why they land
together rather than the colour picker being stacked on top of a broken read:

- **The player's colour goes on the INNER MARK.** It is the larger surface, it is
  what the trailing camera actually sees, and it is the part that carries
  identity.
- **The RING stays the state channel and is never player-coloured.** At rest it
  is near-white; it goes amber on a scrape and red on a crash, and now the inner
  mark goes with it.
- **State overrides everything.** While scraping or parked, both surfaces show
  state and the player's colour is suppressed entirely. A player who picks red
  therefore still sees a *change* on scrape — from their red to state amber and
  on to crash red — rather than a marker that already looked like it had crashed.

That last point is the one that makes the free picker safe rather than merely
allowed. The read is a **transition**, not a hue, so no chosen colour can delete
it.

---

## Why decals are generated, not authored

A decal must work on all six shapes in `Tuning.MARKER_SHAPES` and on every shape
added later. Authoring artwork per pairing is a **shapes × decals grid** — 6×5
today, and adding a seventh shape means authoring five more or shipping five
blanks. That is exactly the parallel-array failure §6 records for landmark
density and §9c for music tracks: it goes stale silently, and the stale cell is
the one nobody looks at.

**So a decal is a FUNCTION of an outline**, not a drawing. Each takes the shape's
own polygon and returns geometry derived from it — bands clipped to it, an inset
copy of it, a fraction of it. Adding a shape needs no decal work at all, and
`RulesTest` asserts that property directly rather than trusting it.

The five decals, each a rule that any closed polygon satisfies:

| Decal | The rule |
|---|---|
| `none` | Nothing. The plain shape, which stays the default. |
| `stripe` | Two bands across the facing axis, clipped to the outline. |
| `edge` | An inset copy of the outline, drawn as a rim. |
| `tip` | The forward third of the shape, in the accent colour. |
| `split` | The outline halved along its facing axis, one half accented. |

**Every one is defined by clipping or insetting the given polygon**, so none can
assume a vertex count, a symmetry, or a tail notch. `Geometry2D` provides the
clip and offset operations, and the project already uses
`Geometry2D.triangulate_polygon` for the marker's inner mark — including the
lesson that a *fan* silently fills concave notches (§12), which a chevron would
hit immediately.

---

## File structure

- **Modify `scripts/core/Tuning.gd`** — the `MARKER_DECALS` table and the palette
  of offered colours, beside the existing `MARKER_SHAPES`.
- **Modify `scripts/core/Settings.gd`** — `marker_colour` and `marker_decal`
  preferences, saved through setter methods like the existing shape choice.
- **Modify `scripts/core/PlayerMarker.gd`** — build the decal, apply the player's
  colour to the inner mark, and move the state read onto both surfaces.
- **Modify `scripts/ui/MarkerPicker.gd`** — colour swatches and a decal row, in
  the screen that already previews the shape.
- **Modify `scripts/core/RulesTest.gd`** — the decal table's shape, and that a
  decal generates valid geometry for **every** shape in the table.
- **Modify `scripts/core/SceneTest.gd`** — the marker builds for every
  shape × decal pairing, and the choice moves nothing about the racer.
- **Modify `scripts/ui/MarkerPickerShot.gd`** — shoot decals and colours, not
  only shapes.

---

## Task 1: The decal table, generated from outlines

**Files:**
- Modify: `scripts/core/Tuning.gd`
- Modify: `scripts/core/RulesTest.gd`

- [ ] **Step 1: Write the failing test**

Add to `scripts/core/RulesTest.gd`, registered beside `_test_marker_shapes()`.

The critical assertion is the **cross product**: every decal must produce valid
geometry for every shape. That is the property that makes generation worth doing,
and it is the one that would rot silently under per-shape artwork.

```gdscript
# The marker decal table (docs/plans/marker-colour-and-decals.md).
#
# Asserts the table's SHAPE and the property the whole design rests on: a decal
# is a FUNCTION of an outline, so every decal must work on every shape --
# including shapes added later. Authoring artwork per pairing would be a
# shapes x decals grid, which is the parallel-array trap section 6 records for
# landmark density.
func _test_marker_decals() -> void:
	check("there are at least two decals", Tuning.MARKER_DECALS.size() >= 2)

	var ids := {}
	for decal in Tuning.MARKER_DECALS:
		check("decal has an id", decal.has("id"))
		check("decal has a label", decal.has("label"))
		var id := String(decal.get("id", ""))
		check("decal id %s is unique" % id, not ids.has(id))
		ids[id] = true

	# The default must exist, or a fresh player gets nothing.
	check("the default decal exists", ids.has(Tuning.MARKER_DECAL_DEFAULT))

	# An unknown id falls back rather than crashing -- the same promise the
	# shape table makes, and for the same reason: a saved preference naming a
	# decal that has since been removed must not take the game down.
	check("an unknown decal falls back",
		String(Tuning.decal_by_id("no-such-decal")["id"])
			== Tuning.MARKER_DECAL_DEFAULT)

	# THE CROSS PRODUCT. Every decal, on every shape, must produce polygons that
	# are non-empty and closed. This is what "works on any chosen icon" means
	# operationally, and it is asserted rather than assumed.
	for shape in Tuning.MARKER_SHAPES:
		for decal in Tuning.MARKER_DECALS:
			var polys := Tuning.decal_polygons(
				String(decal["id"]), shape["outline"])
			var label := "%s on %s" % [decal["id"], shape["id"]]
			# `none` legitimately produces nothing; everything else must draw.
			if String(decal["id"]) == "none":
				check("%s draws nothing" % label, polys.is_empty())
				continue
			check("%s produces geometry" % label, not polys.is_empty())
			for poly in polys:
				check("%s polygon has 3+ points" % label, poly.size() >= 3)
				# Inside the shape it decorates. A decal spilling past the
				# outline would draw over the ring and the corridor floor.
				for point in poly:
					check("%s stays within bounds" % label,
						absf(point.x) <= 2.0 and absf(point.y) <= 2.0)
```

- [ ] **Step 2: Run the test and verify it fails**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: FAIL — `MARKER_DECALS` does not exist. It will surface as a parse
error naming the constant.

- [ ] **Step 3: Add the table and the generator**

Add to `scripts/core/Tuning.gd`, directly after `MARKER_SHAPES` and its lookup.

```gdscript
# --- Marker decals -----------------------------------------------------------
#
# A pattern laid over whatever inner mark the player has chosen.
#
# A decal is a FUNCTION OF AN OUTLINE, never authored artwork. Authoring one
# drawing per shape-and-decal pairing is a shapes x decals grid: six by five
# today, and a seventh shape means five more drawings or five silent blanks.
# That is the parallel-array failure section 6 records for landmark density and
# 9c for music tracks, and the stale cell is always the one nobody looks at.
#
# Generating instead means a shape added later is decorated correctly by
# construction, and RulesTest asserts the whole cross product rather than
# trusting it.
const MARKER_DECAL_DEFAULT := "none"

const MARKER_DECALS := [
	{
		"id": "none",
		"label": "PLAIN",
		# The shape as drawn. Stays the default: a marker with no pattern is
		# the most legible one, and the pattern is a choice rather than an
		# upgrade to it.
	},
	{
		"id": "stripe",
		"label": "STRIPE",
		# Two bands across the facing axis. Racing stripes, and the clearest
		# read of the five at the trailing camera's shallow angle.
	},
	{
		"id": "edge",
		"label": "EDGE",
		# An inset copy of the outline. Reads as a rim light, and it is the one
		# decal whose shape is literally the marker's own silhouette -- so it
		# flatters every shape equally.
	},
	{
		"id": "tip",
		"label": "TIP",
		# The forward third, accented. It is the only decal that REINFORCES
		# facing, which is the one thing every shape in the table must say
		# (section 12, "Every shape has to point").
	},
	{
		"id": "split",
		"label": "SPLIT",
		# One half of the shape along its facing axis. The boldest of the five.
	},
]


func decal_by_id(id: String) -> Dictionary:
	for decal in MARKER_DECALS:
		if decal["id"] == id:
			return decal
	for decal in MARKER_DECALS:
		if decal["id"] == MARKER_DECAL_DEFAULT:
			return decal
	return MARKER_DECALS[0]


# The polygons a decal contributes, given the outline it is decorating.
#
# Every branch CLIPS or INSETS the outline it was handed, so none may assume a
# vertex count, a symmetry or a tail notch -- a chevron is concave and a delta
# has three points, and both must come out right without special-casing.
#
# Returns polygons in the same space as the outline. Empty for "none".
static func decal_polygons(id: String, outline: Array) -> Array:
	var poly := PackedVector2Array(outline)
	if poly.size() < 3:
		return []

	# The shape's own extent, so every decal is proportional to the shape it
	# decorates rather than to a constant. A fixed band width would be right for
	# the delta and wrong for the dart.
	var min_y := poly[0].y
	var max_y := poly[0].y
	var max_x := absf(poly[0].x)
	for p in poly:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		max_x = maxf(max_x, absf(p.x))
	var height := max_y - min_y
	var width := maxf(max_x * 2.0, 0.001)

	match id:
		"none":
			return []
		"stripe":
			# Two bands across the facing axis, clipped to the outline. Clipping
			# is what makes this work on a concave chevron: the band is a plain
			# rectangle and the intersection does the shaping.
			var out: Array = []
			for i in [0.30, 0.58]:
				var y := min_y + height * i
				var band := PackedVector2Array([
					Vector2(-width, y),
					Vector2(width, y),
					Vector2(width, y + height * 0.13),
					Vector2(-width, y + height * 0.13),
				])
				for piece in Geometry2D.intersect_polygons(band, poly):
					if piece.size() >= 3:
						out.append(piece)
			return out
		"edge":
			# An inset copy. offset_polygon with a negative delta shrinks the
			# outline along its own normals, so the result follows whatever
			# silhouette it was given.
			var out2: Array = []
			for piece in Geometry2D.offset_polygon(poly,
					-minf(width, height) * 0.16):
				if piece.size() >= 3:
					out2.append(piece)
			return out2
		"tip":
			# The forward third. Facing is -Y in this space, so "forward" is the
			# low end of the range.
			var cut := min_y + height * 0.34
			var nose := PackedVector2Array([
				Vector2(-width, min_y - height),
				Vector2(width, min_y - height),
				Vector2(width, cut),
				Vector2(-width, cut),
			])
			var out3: Array = []
			for piece in Geometry2D.intersect_polygons(nose, poly):
				if piece.size() >= 3:
					out3.append(piece)
			return out3
		"split":
			# One half along the facing axis.
			var half := PackedVector2Array([
				Vector2(0.0, min_y - height),
				Vector2(width, min_y - height),
				Vector2(width, max_y + height),
				Vector2(0.0, max_y + height),
			])
			var out4: Array = []
			for piece in Geometry2D.intersect_polygons(half, poly):
				if piece.size() >= 3:
					out4.append(piece)
			return out4
	return []
```

- [ ] **Step 4: Run the test and verify it passes**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/RulesTest.gd
```
Expected: PASS. Read `logs/errors.log`.

- [ ] **Step 5: Verify the cross-product check can fail**

A test that cannot fail is not evidence — §9d records two false positives in this
codebase that stayed green against the bug they were named for.

Temporarily add a shape to `MARKER_SHAPES` whose outline is a **concave notch**
that a naive decal would mishandle:

```gdscript
	{
		"id": "_probe",
		"label": "PROBE",
		"outline": [
			Vector2(0.0, -1.2), Vector2(0.9, 0.8),
			Vector2(0.0, -0.1), Vector2(-0.9, 0.8),
		],
	},
```

Re-run. Expected: still PASS, because clipping handles concavity — that is the
property being claimed. Then temporarily change `stripe` to return the raw
`band` without intersecting, and re-run.

Expected: FAIL at `stripe stays within bounds`, because an unclipped band runs to
the full width. Restore both and confirm green.

- [ ] **Step 6: Commit**

```bash
git add scripts/core/Tuning.gd scripts/core/RulesTest.gd docs/plans/marker-colour-and-decals.md
git commit -m "Generate marker decals from the outline, asserted on every shape

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: Move the state read onto both surfaces

**This task comes before the colour picker, deliberately.** It is what makes a
free colour choice survivable, and doing it afterwards would mean shipping an
interval where a player could pick red and lose the crash read entirely.

It also fixes the defect §12 already records — the inner mark staying white
through a scrape — so the two land together.

**Files:**
- Modify: `scripts/core/PlayerMarker.gd`
- Modify: `scripts/core/SceneTest.gd`

- [ ] **Step 1: Write the failing test**

Add to `scripts/core/SceneTest.gd`.

```gdscript
# The state read survives a player-chosen colour.
#
# This is the assertion the free colour picker rests on. CLAUDE.md section 12
# made near-white mandatory precisely because amber and red only read as STATE
# while the resting marker carries no hue -- so with colour now choosable, what
# has to be true is that state OVERRIDES the choice on both surfaces.
#
# Checked with the worst possible choice: a player whose colour IS crash red. If
# the read survives that, it survives anything.
func _check_state_overrides_player_colour() -> void:
	var marker := PlayerMarker.new()
	marker.player_colour = PlayerMarker.COL_CRASH
	add_child(marker)
	await get_tree().process_frame

	var racer := Racer.new(_maze(), Upgrades.new(1))

	# At rest, the mark carries the player's colour.
	racer.state = Racer.State.RUNNING
	racer.scraping = false
	marker.update_state(racer, 0.016)
	var resting_ring: Color = marker._ring_material.albedo_color
	check("at rest the ring is not state-coloured",
		not resting_ring.is_equal_approx(PlayerMarker.COL_CRASH))

	# Parked, BOTH surfaces must read crash -- including the inner mark, which
	# section 12 records as currently staying white through a scrape.
	racer.state = Racer.State.PARKED
	marker.update_state(racer, 0.016)
	check("a crash colours the ring",
		marker._ring_material.albedo_color.is_equal_approx(
			PlayerMarker.COL_CRASH))
	check("a crash colours the inner mark too",
		marker._arrow_material.albedo_color.is_equal_approx(
			PlayerMarker.COL_CRASH))

	# And the READ is a transition, not a hue: resting and crashed must differ
	# on the ring even when the player picked the crash colour itself.
	check("the state read survives the worst colour choice",
		not resting_ring.is_equal_approx(marker._ring_material.albedo_color))

	marker.queue_free()
	await get_tree().process_frame
```

Use whatever helper `SceneTest` already has for building a maze rather than
adding a second one; `_maze()` above is a placeholder for that existing call.

- [ ] **Step 2: Run the test and verify it fails**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SceneTest.gd
```
Expected: FAIL at `a crash colours the inner mark too` — `update_state` writes
only the ring today.

- [ ] **Step 3: Apply colour to the mark and state to both**

In `scripts/core/PlayerMarker.gd`, add the field and rewrite `update_state`:

```gdscript
# The player's chosen colour, applied to the INNER MARK only.
#
# The ring is deliberately excluded: it is the state channel (see update_state),
# and a player-coloured ring would put the scrape and crash read on a surface
# the player can set to any colour they like -- including the state colours
# themselves.
var player_colour := COL_ARROW
```

```gdscript
# Drives colour from racer state, so the marker itself reports danger. This is
# the same information the barrier bar carries, but placed where the player is
# already looking.
#
# STATE OVERRIDES THE PLAYER'S COLOUR, on both surfaces. That is what makes the
# free colour picker safe: the read is a TRANSITION rather than a hue, so a
# player who picks crash red still sees their marker change on a scrape. The
# alternative -- leaving the resting colour showing through -- is what CLAUDE.md
# section 12 refused a colour picker over.
#
# It writes the inner mark as well as the ring, which also fixes the defect that
# section records: the mark stayed pure white through a scrape, so a frame with
# the barrier visibly half-drained was pixel-identical to a clean one, on the
# larger of the two surfaces and the one the trailing camera actually sees.
func update_state(racer: Racer, delta: float) -> void:
	_bob = fmod(_bob + delta * 3.0, TAU)
	if _arrow:
		_arrow.position.y = 0.06 + sin(_bob) * 0.04

	if _ring_material == null:
		return

	var ring_colour := COL_RING
	var mark_colour := player_colour
	if racer.state == Racer.State.PARKED:
		ring_colour = COL_CRASH
		mark_colour = COL_CRASH
	elif racer.scraping:
		# Warms toward red as the barrier drains, so the marker shows how close
		# the scrape is to becoming a crash.
		var warm := COL_SCRAPE.lerp(COL_CRASH, 1.0 - racer.barrier_fraction())
		ring_colour = warm
		mark_colour = warm

	_ring_material.albedo_color = ring_colour
	_ring_material.emission = ring_colour
	if _arrow_material != null:
		_arrow_material.albedo_color = mark_colour
		_arrow_material.emission = mark_colour
```

- [ ] **Step 4: Run the test and verify it passes**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SceneTest.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/PlayerMarker.gd scripts/core/SceneTest.gd
git commit -m "Put the state read on both marker surfaces, overriding player colour

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: Build the decal geometry into the marker

**Files:**
- Modify: `scripts/core/PlayerMarker.gd`
- Modify: `scripts/core/SceneTest.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# Every shape builds with every decal.
#
# The cross product again, this time through the real mesh builder rather than
# the polygon generator -- RulesTest asserts the geometry is valid, and this
# asserts the marker actually BUILDS it. A decal that produced good polygons and
# then failed to triangulate would pass there and fail here.
func _check_every_shape_builds_with_every_decal() -> void:
	for shape in Tuning.MARKER_SHAPES:
		for decal in Tuning.MARKER_DECALS:
			var marker := PlayerMarker.new()
			marker.shape_id = String(shape["id"])
			marker.decal_id = String(decal["id"])
			add_child(marker)
			await get_tree().process_frame
			var label := "%s + %s" % [shape["id"], decal["id"]]
			check("%s builds an inner mark" % label, marker._arrow != null)
			# A decal must never replace the shape it decorates.
			check("%s keeps its ring" % label, marker._ring != null)
			marker.queue_free()
			await get_tree().process_frame
```

- [ ] **Step 2: Run it and verify it fails**

Expected: FAIL — `decal_id` does not exist on `PlayerMarker`.

- [ ] **Step 3: Build the decal**

Add the field beside `shape_id`, and extend the inner-mark builder to emit the
decal's polygons as a second surface, raised very slightly so it does not
z-fight the mark beneath it.

```gdscript
# The chosen decal's id. Read once at build time and never again -- the same
# treatment shape_id gets, and for the same reason: nothing in the simulation
# may read a cosmetic choice.
var decal_id := Tuning.MARKER_DECAL_DEFAULT
```

In the function that builds the inner mark, after the mark itself is built:

```gdscript
	# The decal, generated from THIS shape's outline rather than looked up per
	# pairing (Tuning.decal_polygons). A shape added later is decorated by
	# construction.
	var decal_polys := Tuning.decal_polygons(decal_id, outline)
	if not decal_polys.is_empty():
		var decal_mesh := _build_polygons_mesh(decal_polys, DECAL_LIFT)
		if decal_mesh != null:
			var node := MeshInstance3D.new()
			node.mesh = decal_mesh
			# Built with add_child FIRST, then named -- a name set before entry
			# to the tree is overwritten (CLAUDE.md section 12).
			_arrow.add_child(node)
			node.name = "Decal"
			_decal_material = _make_material(COL_ARROW, 3.4)
			node.material_override = _decal_material
			_decal = node
```

`_build_polygons_mesh` triangulates with `Geometry2D.triangulate_polygon`, not a
fan — §12 records that a fan silently fills concave notches, which is exactly
what a chevron's decal would hit. Reuse the existing triangulation path the inner
mark already uses rather than writing a second one.

`DECAL_LIFT` is a small constant (0.004) raising the decal above the mark. §12
records two separate depth-fighting failures from coplanar surfaces — the wall
band and the wall-top cap — and both were fixed by real geometric separation
rather than by a bias property, which `StandardMaterial3D` does not have in 4.7.

- [ ] **Step 4: Run it and verify it passes**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/SceneTest.gd
```
Expected: PASS, 30 pairings × 2 checks.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/PlayerMarker.gd scripts/core/SceneTest.gd
git commit -m "Build the decal into the marker, on every shape

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Save the two preferences

**Files:**
- Modify: `scripts/core/Settings.gd`
- Modify: `scripts/core/ShellTest.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# The two new preferences round-trip, and an unknown decal falls back.
#
# Written through SETTER METHODS rather than bare properties, which CLAUDE.md
# section 9d records as a real bug: loading from disk assigns the same field, and
# a setter cannot tell a restore from a choice -- it re-saved the file it had
# just read and fired the change signal before the menu existed to hear it.
func _test_marker_preferences() -> void:
	var settings := Settings.new()
	add_child(settings)

	settings.set_marker_colour(Color(0.9, 0.2, 0.4))
	check("marker colour round-trips",
		settings.marker_colour.is_equal_approx(Color(0.9, 0.2, 0.4)))

	settings.set_marker_decal("stripe")
	check("marker decal round-trips", settings.marker_decal == "stripe")

	# Stored by NAME, so a reordered table cannot silently re-point an existing
	# player's choice -- the rule the shape table already follows.
	settings.set_marker_decal("no-such-decal")
	check("an unknown decal resolves to the default",
		String(Tuning.decal_by_id(settings.marker_decal)["id"])
			== Tuning.MARKER_DECAL_DEFAULT)

	settings.queue_free()
	await get_tree().process_frame
```

- [ ] **Step 2: Run it and verify it fails**

Expected: FAIL — `set_marker_colour` does not exist.

- [ ] **Step 3: Add the preferences**

Follow the existing shape preference exactly — same file, same section, same
setter shape, and saved to `user://settings.cfg` alongside it. The colour is
stored as a hex string rather than four floats, so the config file stays
readable and a hand-edited value is obvious.

- [ ] **Step 4: Run it and verify it passes**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/Settings.gd scripts/core/ShellTest.gd
git commit -m "Save the marker colour and decal preferences

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: The picker gains colour swatches and a decal row

**Files:**
- Modify: `scripts/ui/MarkerPicker.gd`

- [ ] **Step 1: Add the two rows**

The screen already previews a shape in a live 3D viewport. Both new choices feed
the **same preview**, which is the whole reason they belong here rather than in
a second screen: colour and decal are only judgeable *on the shape*, at the
trailing camera's shallow angle.

- A row of colour swatches, plus a **RESET** that returns to near-white. §12's
  objection is real even though the picker is now free — the reset is what makes
  a bad choice recoverable in one press rather than requiring the player to
  remember what the default looked like.
- A row of decal buttons, labelled from `Tuning.MARKER_DECALS`.
- Both write through `Settings`' setters, never a bare field.

**The preview must show the state colours too.** A player picking a colour close
to amber needs to see what a scrape looks like *before* committing, so the
preview cycles resting → scrape → crash on a slow loop, or offers a held
"preview damage" control. Without it the picker hides exactly the interaction the
free choice put at risk.

- [ ] **Step 2: Verify it parses and the harnesses stay green**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Headless -Script res://scripts/core/ShellTest.gd
```

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/MarkerPicker.gd
git commit -m "Offer colour and decal in the marker picker

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: The picture half

No headless assertion can see a decal that reads as mud at the trailing camera's
angle, a colour that vanishes into a palette, or a stripe that lands off-centre
on an asymmetric shape.

**Files:**
- Modify: `scripts/ui/MarkerPickerShot.gd`
- Modify: `scripts/core/MarkerShot.gd`

- [ ] **Step 1: Extend the shot tools**

`MarkerShot` shoots one frame per shape from the ordinary trailing camera. Extend
it to shoot:

- **Every decal on ONE shape**, to judge the decals against each other.
- **One decal on EVERY shape**, to catch a decal that only works on the symmetric
  ones — the `stripe` on a chevron is the case most likely to fail.
- **A chosen colour in maze 3 and maze 5**, the green and deep-violet palettes.
  This is the §12 objection made visible: it does not block the feature, but the
  frame is what tells Jonah whether a given colour is a bad idea in a given maze.
- **A scrape frame and a crash frame with a red player colour**, which is the
  worst case Task 2 is built against.

`MarkerPickerShot` must keep its existing courtesy of **restoring the saved
preferences on the way out** — it now writes three of them rather than one, and
§12 records that a tool writing the state it inspects left a later `Screenshot`
run full of thumb pads that read as a layout regression.

- [ ] **Step 2: Run them**

```
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Script res://scripts/core/MarkerShot.gd -Quit 40
powershell -ExecutionPolicy Bypass -File tools\launch.ps1 -Script res://scripts/ui/MarkerPickerShot.gd -Quit 30
```

Not `-Headless` — these need the renderer.

- [ ] **Step 3: Look at every frame**

Specifically:

- Does each decal still read as **pointing**? §12 makes that the acceptance test
  for a shape, and a decal that obscures the taper breaks it — the shallow angle
  already ate a gentle taper once and drew a symmetric diamond.
- Is the decal visible at all at the trailing camera's distance, or is it mud?
- Does the scrape/crash frame read as a **change** with a red player colour?
- Does the chosen colour disappear in maze 3 or 5?

- [ ] **Step 4: Commit**

```bash
git add scripts/core/MarkerShot.gd scripts/ui/MarkerPickerShot.gd
git commit -m "Shoot decals, colours and the state read

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: Record the reversal in CLAUDE.md

Runs **last**, once the frames confirm it works.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite the marker-colour rule**

§12's "The marker's shape is the player's to pick — its colour is not" is now
wrong in its title and in two of its three bullets. It must be **rewritten, not
deleted**: the reasoning explains why maze 3 forced the white marker, and that
history is what a future reader needs to understand the constraint the new design
works within.

Record:

- That the free colour picker **reverses** the near-white rule, that it was asked
  for after both objections were put, and what it costs — a player can make their
  own marker hard to see in a given maze.
- That the state read is preserved by **override**, on both surfaces, so the read
  is a transition rather than a hue and no colour choice can delete it.
- That this also fixes the defect §12 already recorded — the inner mark staying
  white through a scrape, on the larger surface and the one the camera sees.
- That decals are **generated from the outline**, so a shape added later is
  decorated by construction, and that `RulesTest` asserts the full cross product.
- That `MARKER_DECALS` is a table stored **by name**, like the shapes, so a
  reordering cannot re-point a saved choice.
- The updated harness counts, read off an actual run.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Record the marker colour reversal and the decal system

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **The reversal is recorded, not hidden.** §"Self-instructions" requires a rule
  settled in conversation to be written down the same turn, and this plan is that
  record until Task 7 lands it in CLAUDE.md.
- **The state read is protected by an assertion, not by care.** Task 2 tests the
  worst possible choice — a player whose colour *is* crash red — because that is
  the case where a weaker design silently fails.
- **Ordering is deliberate.** Task 2 precedes the picker so there is never a
  build where a free colour can destroy the read.
- **No parallel arrays.** Decals are generated from outlines; the cross product
  is asserted rather than authored.
- **Tests can fail.** Task 1 Step 5 breaks the clipping deliberately and confirms
  the bounds check goes red.
- **A rendered frame is in the plan.** Task 6 exists because "does this decal
  still read as pointing at a shallow angle" is exactly the question §12 says no
  headless assertion can answer.
