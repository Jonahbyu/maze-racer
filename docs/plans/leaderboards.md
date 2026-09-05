# Leaderboards, seeded runs, and the new menu

Three boards (general / daily / monthly), each toggling between score and time,
plus a personal run history — served from the existing `pistachio-kitchen`
Firebase project, and surfaced in a menu rebuilt as two columns.

## 1. The seeds

**Derived from the date, never fetched.** `daily` is a hash of `YYYY-MM-DD`,
`monthly` a hash of `YYYY-MM`, computed identically by every client with no
network call — so a daily run starts instantly and works offline, and the board
is the only thing that needs Firebase.

Publishing seeds from Firestore was rejected: it puts a network round trip in
front of the PLAY button, and a failed fetch would mean no daily run at all.

**The seed is what makes scores comparable, and it is the reason the daily and
monthly boards exist at all.** §10 already calls this "nearly free" off the
Phase 3 seeding work, and it is — `Game.run_seed` is already the single source
every maze derives from (`run_seed + index * 7919`). The only change is where
that number comes from.

`Tuning.seed_for_date()` / `seed_for_month()` are pure functions of a date
string, so `RulesTest` can assert them without a clock: same date in, same seed
out; different dates, different seeds; and the rollover happens at local
midnight.

**A general-board run keeps the existing wall-clock seed.** That board is "any
seed", so it is the one place a random maze is still correct.

## 2. Firebase

Reuses the cookbook's project (`pistachio-kitchen`), which already has Firestore
and rules deployed. A second app in one project is normal; the collections are
namespaced under `mazeRacer/` so nothing can collide with recipes.

### Auth: anonymous, not email/password

The cookbook signs in with email and password. That is wrong here — nobody makes
an account before their first two-minute run, and a score that asks for a signup
to count is a score that gets thrown away.

`signInAnonymously()` gives a stable UID with no prompt at all. The player is
asked for a **display name** only when they first post, and it is stored against
the UID in Firestore plus locally in `settings.cfg`.

**Known cost, recorded rather than hidden:** clearing browser storage loses the
identity, and there is no recovery. That is the price of no signup, and it is the
right trade for a leaderboard nobody has to enrol in.

### Collections

```
mazeRacer/scores/{scoreId}        one run
  uid, name, score, timeSeconds, seed, board, mazesCleared, died, createdAt
mazeRacer/players/{uid}           display name
```

`board` is `general` | `daily` | `monthly`, denormalised onto the score so a
board query is a single indexed `where`, and `seed` is stored alongside it so a
suspicious run can be checked later against the maze it claims to have driven.

### Cheating: rules plus a stored seed, and no pretence beyond that

A static site cannot stop a determined cheater — anyone can open devtools and
POST a number. What the rules CAN do is reject the impossible, which is what
stops the casual case:

- `score` within a plausible ceiling, `timeSeconds` positive and under 30 min
- `seed` equal to the seed that board's date actually derives to
- one score per uid per seed, so a board cannot be flooded by one player
- `uid` equal to the caller, so nobody posts as someone else

Full server-side validation (replaying an input log in a Cloud Function) was
considered and rejected as out of scale: it needs the simulation running
server-side, which is weeks of work for a board played by a handful of friends.

**This is written down because it is a limit, not a solution.** If the board ever
matters more than it does now, the replay approach is the upgrade path, and
storing the seed on every score today is what keeps that door open.

## 3. The Godot side

**`Leaderboard.gd`, an autoload**, for the same reason `Music` and `Settings` are
(§9c, §9d): `Shell._swap` frees the entire live child on every mode change, and
this is written from the game and read by the menu.

**Transport is `JavaScriptBridge` into `shell.html`**, the pattern the audio
unlock already established (§12): the Firebase JS SDK loads in the shell, and
GDScript calls a small set of `window.mazeRacerLB.*` functions. Godot has no
Firebase SDK, and the REST API would mean hand-rolling auth token refresh.

**Every call is guarded and asynchronous, and the game never waits on one.** A
missing bridge, a failed sign-in, or no network must never be what stops a run
starting — the same rule §9d states for `Settings`. Desktop builds have no
`JavaScriptBridge` at all, so on desktop the boards are simply empty and the game
is otherwise identical.

**Nothing in the simulation may read `Leaderboard`.** Movement, turn resolution,
the buffer, the barrier and the penalties behave identically with the autoload
absent, which is what every harness gets. Same separation as landmarks, music and
settings.

## 4. The menu, rebuilt as two columns

Left: title and buttons, as now but left-aligned rather than centred.
Right: the leaderboard panel.
Behind: a background art piece (Jonah is making it) — so both columns must stay
legible over an unknown image, which means every panel needs its own scrim rather
than relying on the background being dark.

**Board switching is click-through**, one control cycling general → daily →
monthly, rather than three tabs. Three boards is few enough that a cycle is
faster to build and cannot overflow the panel width the way a tab row would (the
§9d menu-row lesson).

**Score / time toggle** per board. Time sorts ascending, score descending — the
toggle changes the query's order, not just the display, or the "top 10" would be
the top 10 by the wrong measure.

**Run history** is the player's own runs, newest first, from the same collection
filtered by uid.

## 5. Where a score gets posted

`RunSummary` (§8c) is the moment: the run is over, the score is final, and the
player is already reading it. It gets a POSTING / POSTED / FAILED line and, on a
first post, the name prompt.

A run is only posted if it **finished or died** — there is no partial submission,
because a run abandoned by closing the tab never reaches the summary anyway.

## 6. Tests

`RulesTest`: seed derivation is pure and date-stable; the board a run belongs to.
`SceneTest`: the summary shows post state; the autoload's absence changes nothing.
`ShellTest`: the menu builds both columns, cycles boards, and toggles sort.
`LeaderboardTest`: a new harness for the payload shape and the local fallbacks,
with no network — the JS bridge is stubbed, since a harness that needed Firebase
would be a harness that fails when Jonah is offline.

**A rendered frame is required** for the two-column menu, per §9d: no headless
assertion can see one panel overlapping another. `MenuShot.gd` extends the
existing shot tooling.
