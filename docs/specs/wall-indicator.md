# Wall Indicator

## The problem

At 4x a wall arrives in 250ms. The corridor geometry already says where it is --
the wall is right there, lit, with a neon cap -- but "there is a wall 1.5 cells
ahead" and "I must turn NOW" are different reads, and only the first is fast.

Section 11.3: every timing demand made of the player must be visible on screen
before it is demanded. A wall that ends a corridor IS a timing demand, and it is
currently communicated only by perspective, which compresses exactly when speed
makes it matter most.

## What it marks

**A real dead end.** The first cell ahead where forward, left and right are all
walls -- the only way out is a 180 back the way you came.

This started as "any blocked facing", on the reasoning that a dead end and a
corridor that merely turns are the same event for the player: keep going and you
scrape. In play that was wrong. A DFS carve blocks the facing on roughly **55%**
of cells (the same ratio that drives the turn-cost equilibrium in section 5.3),
so the sign was lit about half the time -- frequent enough that it stopped
reading as a warning and became scenery, and it sat over junctions the player was
about to turn through cleanly.

The dead end is the case the player genuinely cannot recover from with a turn,
and it is the case perspective hides worst. Restricting the mark to it is what
gives the sign its meaning back: when it appears, the only answer is `down`.

## What it must never mark

**Which way to go.** The marker says "not through here". It never says "left is
correct". That distinction is what keeps it from cannibalising Path Indicator
(section 7), which is the headline paid upgrade and the only thing in the game
that answers routing.

Concretely: a T-junction and a plain corner get **nothing at all**. The player
still has to solve which way is right -- and now also has to notice the corner
themselves, which is the read the grid lines and corridor geometry already
support.

## Behaviour

- The marker sits flat on the blocking wall face, centred, at eye height.
- It appears when the wall is within **2.5 cells** of the player, so it is never
  a distant map of the maze -- only an imminent demand.
- It **grows in urgency as the wall approaches**: amber far, red close. The
  colour is the distance read, which is cheaper to parse than the size of the
  wall in perspective.
- **One marker at a time.** Lighting every wall in view would turn the maze into
  a christmas tree and stop reading as urgent.
- It is **free and always on**. Not an upgrade. It restores information the 3D
  view already technically shows -- it is a legibility fix, not a power.

## Why on the wall and not the HUD

A HUD arrow asks the player to look away from the corridor and then map a screen
direction back onto the world. The marker is ON the thing it is about, at the
distance it is about, so no mapping is needed. Same reason the player marker
carries the barrier colour (section 12).
