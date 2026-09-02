# Landmarks

Randomly generated decorative structures placed in the maze so that a corridor
has an identity beyond "corridor". Their entire job is to answer **"have I been
here before?"** — and never **"which way should I go?"**

---

## 1. Why the game needs them

The maze is procedurally uniform by construction. Every cell is the same size,
every wall the same height, every corridor the same colour as every other
corridor in that maze. That uniformity is deliberate — it is what makes the grid
lines readable as a timing contract (CLAUDE.md §11.3) — but it has a cost the
design has not addressed until now: **a player who loops back onto their own path
cannot tell that they have.**

That matters most in exactly the mazes the design leans on hardest. §8 makes loop
density "the most interesting knob", and §11.2 says bad routing should be punished
by distance and time. Both assume the player can *notice* they have wasted
distance. In a 25%-braided 90×90 maze with no visual anchors, they cannot — a
re-crossed junction is indistinguishable from a fresh one, so the punishment
lands without the lesson.

Landmarks are the memory anchor that makes the loop legible. Passing the same
lone spire twice is unambiguous information that you have gone in a circle.

---

## 2. What they are not

**Landmarks carry no navigational information.** They are placed with no
relationship to the solve path, the distance field, the gates, or the exit, and
nothing about a landmark's type, height, or colour correlates with any of them.

This line is the whole reason the feature is safe to add. Three upgrade lines are
sold on answering "which way" — Path Indicator, Gate Compass, Golden Trail — and
Path Indicator in particular is described in §7 as "the headline upgrade". Free
scenery that hinted at the route would cannibalise all three at once. This is the
line the wall indicator held too, before it was removed in favour of the landmark
itself (§5.6).

So the contract is: **a landmark tells you where you *are*, never where to go.**
Recognising one is worth something only because you remember what you did last
time you saw it. That is player-supplied knowledge, not a given answer, and it is
therefore not a substitute for any upgrade.

A useful test for any future change here: if a first-time player entering a maze
gains anything at all from a landmark before they have passed it once, the
placement rule is wrong.

---

## 3. Two tiers: local and skyline

Landmarks come in two tiers, and they answer different questions.

### Local landmarks — under the wall line

Shorter than `WALL_HEIGHT`, so they are visible only from inside the corridor
they occupy or through an opening into it. They make one *specific junction*
recognisable. This is the fine-grained tier: it distinguishes two adjacent
T-junctions from each other.

### Skyline landmarks — over the wall line

Tall enough to clear the walls and be seen from several corridors away. They make
a *region* recognisable — "I am back in the north-east part of the maze" — which
is a coarser and slower read, but survives being seen from anywhere nearby.

**Skyline landmarks are seen as spires poking up past the wall tops, never from
above.** The camera is deliberately capped below `WALL_HEIGHT` (`CAM_HEIGHT`, and
again for the crash view) because above it "the maze flattens into a floor plan
and corridors stop feeling enclosed". That cap is not negotiable, so a skyline
landmark earns its visibility by being tall itself, seen from a low eye. The
practical consequence is that only the **upper** portion of a skyline landmark is
ever seen at distance, which is why every skyline type is shaped to be
identifiable from its top alone.

That constraint is a feature: a distant spire tip over a wall is a far more
evocative image than a bird's-eye view of the maze, and it preserves the
enclosure the camera rules exist to protect.

---

## 4. Placement

Landmarks occupy a **whole cell** and the player drives *around* them, never
through them — collision is not modelled, and must not be, because the barrier
and crash rules are defined against maze walls only (§5) and adding a second
class of solid thing would mean two collision systems disagreeing at speed.

Consequently landmarks are placed **only in cells the player cannot enter**, plus
one case where they can:

| Kind | Where | Rationale |
|---|---|---|
| **Sealed pocket** | A fully-walled cell left over from the carve | Free space; seen only through a neighbouring corridor, so it reads as glimpsed |
| **Dead end** | The terminal cell of a dead end | The player *can* enter. The landmark sits at the far end as the thing you turned around at — exactly the memory anchor a dead end should leave |
| **Outside the boundary** | Beyond the maze's outer wall | Skyline tier only. Nothing to collide with at all, and it gives the maze an exterior |

The dead-end case is the most valuable of the three and much of the reason the
feature is worth building. §6 says dead ends are the punishment for a misread, and
a dead end with a statue in it is a punishment the player *remembers*. Turning
around at the same broken pillar twice is the clearest possible signal that a
route was re-tried.

**A landmark in a dead end sits against the far wall, not on the cell centre.**
The player drives into that cell and stops against the end wall; a landmark on
the centre point would be geometry the marker visibly drives through. Pushed to
the back it is the thing beyond the stopping point, which is both correct and the
better image.

**Every dead end is decorated; the density knob thins only sealed pockets.**

This reverses an earlier call, recorded plainly because the reasoning changed
rather than the taste. The knob used to thin both pools together on the argument
that *"a landmark in every dead end is wallpaper; the memorability comes from
scarcity"* — reasoning borrowed from the one-cell stubs in §6, where frequency
was the problem and not existence.

That argument does not survive the removal of the wall indicator (§5.6). While
the sign existed, a bare dead end still announced itself and the landmark was
pure bonus, so thinning cost little. With the sign gone the landmark is the
**only** thing distinguishing the end of a corridor from a corridor that merely
turns, and a bare dead end is a reversal with nothing to remember it by — the
"punishment without the lesson" failure in §1 that this whole feature exists to
fix, reappearing in the exact cells it was aimed at.

The scarcity argument was also weaker than it looked: what makes a landmark
memorable is that it is *different from the others*, which is carried by type,
hue, scale and yaw, not by whether the neighbouring dead end happens to be empty.
Measured after the split: **0 bare dead ends** across all five mazes on 4 seeds
each (2,187 dead ends).

Sealed pockets stay on the knob. They are glimpsed from outside, are never driven
into, and so make no promise to the player that a bare one would break.

---

## 5. Types

Each type is a distinct **silhouette**, because silhouette is what survives the
two conditions landmarks are actually read under: heavy fog at distance, and a
glance at speed. Colour distinguishes them at close range; shape distinguishes
them at the range that matters.

| Type | Tier | Silhouette | Hue |
|---|---|---|---|
| **Spire** | Skyline | Tall narrow tapering column | Deep blue |
| **Monolith** | Skyline | Fat rectangular slab, flat top | Pale bone |
| **Tree** | Skyline | Thin trunk, wide round canopy | Dusty teal |
| **Arch** | Local | Two legs and a lintel, gap beneath | Rose |
| **Rings** | Local | Stacked concentric rings | Pale violet |
| **Rubble** | Local | Scattered low blocks, irregular | Slate grey |

### The hues are held clear of every reserved colour

Colour in this game is close to fully committed, and a landmark palette that
collides with any of it damages a signal the player reads under pressure:

| Reserved | Owner |
|---|---|
| amber → orange-red | Wall indicator, ramping by distance (§5.6) |
| amber-yellow | Gate markers (`NEON_GATE`) |
| white | Exit marker, player marker |
| green / red | Path Indicator panels (§7) |
| red | Barrier bar when low; player marker under scrape |
| per-maze hue | Walls, grid, fog — cyan / magenta / green / ember / violet |

Landmark hues therefore sit in the gaps: **deep blue, bone, teal, rose, violet,
slate**. All six are low-saturation and low-emission relative to the neon, which
is the second half of the safety argument — a landmark should be *visible*, never
*brighter than a gate*. Gates and the exit must stay the most eye-catching things
in the maze, because they are navigation and landmarks are not.

**Landmarks do not recolour per maze.** They join the short list of things that
hold a fixed colour across all three (gates, exit, player marker, HUD — §8). A
landmark you saw in maze 1 and again in maze 2 should be recognisably the same
kind of object, and per-maze tinting would mean re-learning the vocabulary three
times a run for no gain.

**Guard against the palette colliding with them instead.** The maze palettes may
grow; a future colourway in deep blue would put the spire's hue on every wall.
The reserved list above runs in both directions.

---

## 6. Rendering

Landmarks are **static decorative geometry with no per-frame cost**. They are
built once per maze into one merged surface per material, the same way walls,
grid lines and lane lines already are — a 90×90 maze must not gain a few hundred
individually-processed nodes for scenery.

They are built from the same primitive vocabulary the rest of the mesh uses
(boxes and quads via `SurfaceTool`) rather than imported models, so they inherit
the flat-shaded neon look and add no assets to the project.

They emit light only as material emission, never as real lights. The corridor is
lit by exactly one `OmniLight3D` headlight, kept deliberately dim because turning
it up "flattens the near wall into a colour field" (§12) — adding light sources
scattered through the maze would undo that tuning everywhere at once.

---

## 7. What stays out of the simulation

Landmark placement is generated from the maze seed, so it is **reproducible** and
part of the same determinism guarantee as the maze itself (§6, seeding). A given
run seed produces the same landmarks in the same cells every time, which keeps
bugs reproducible and keeps a future daily-run mode free.

It runs on its **own RNG stream**, seeded from the maze seed but separate from the
carve's generator. Sharing the carve RNG would mean that changing the landmark
density silently redraws every maze in the game, because each extra draw shifts
the whole downstream sequence — a decoration knob must not be able to alter the
maze it decorates.

Placement runs **last**, after every wall-knocking stage, for the same reason the
straight-run cap does (§6): the dead-end passes open walls, so a cell that was a
sealed pocket or a dead end mid-pipeline may not be one in the finished maze.

But **nothing in the simulation may read a landmark.** Movement, turn resolution,
the buffer, the barrier, penalties and the distance field must all behave
identically whether landmarks exist or not. The rule is the same one §12 states
for lanes: the simulation layer must never require a rendered frame, and a
decorative system that started influencing movement would be invisible in every
existing test.

This is worth asserting directly rather than trusting, because it is the failure
mode that would be hardest to notice: landmark data lives on the maze (it is
seeded from it), so it is *reachable* from the rules layer even though it must
never be *used* there.
