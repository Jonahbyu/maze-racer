# Music

Looping background tracks, owned by one autoload that outlives every scene
swap. Adding a track is meant to be a one-line edit to a table, never a code
change.

---

## 1. Why an autoload, and not a node in each scene

`Shell._swap` frees the entire live child on every mode change (menu → game →
trailer → menu). An `AudioStreamPlayer` parented anywhere under that child dies
with it, which produces two failures the moment a player touches a button:

- **The track restarts from zero** on every transition. Menu music that resumes
  from the top each time the player backs out of the trailer reads as a bug, not
  as a loop.
- **A hard audio cut** at the swap frame, because the old player is freed before
  the new one begins.

The autoload sits above the shell and is never freed, so a track that should
continue across a swap simply is not told to change. That is also what makes
the "same track on both sides of a transition does not restart" rule below
expressible at all — it needs one player that remembers what it is playing.

`Music` is registered in `project.godot` under `[autoload]`. It is a plain
`Node`; it needs no scene.

---

## 2. The track table

Tracks are declared in `Tuning.TRACKS`, keyed by a short name:

```gdscript
const TRACKS := {
    "find_the_way": {
        "path": "res://audio/music/find-the-way.mp3",
        "volume_db": -8.0,
    },
}
```

`path` is the resource. `volume_db` is per-track trim, because two tracks
mastered at different levels need to be evened out somewhere, and doing it at
the mixer would move them together. Both keys are required; a missing or
misspelled `path` is reported once and then ignored — see §6.

**Assignment is a key on the thing that plays it, never a parallel array.**
A maze names its track in its own `Tuning.MAZES` entry:

```gdscript
{ "name": "The Grid", ..., "music": "find_the_way" }
```

This is the rule CLAUDE.md §6 already sets for `landmarks`, for the same
reason: an array indexed by maze number goes stale the moment a maze is added,
and the failure is silent — maze 6 gets index 5 of a 5-entry array and plays
nothing, with no error. Reading the key off the maze config means a maze that
forgets to name a track is a visible `""`, not an off-by-one.

The menu and the trailer name their tracks the same way, as constants on
`Music` itself (`MENU_TRACK`, `TRAILER_TRACK`), since neither is a maze.

---

## 3. What plays where

| Context | Track |
|---|---|
| Main menu | `MENU_TRACK` |
| A run | whatever `Tuning.MAZES[index]["music"]` names |
| Trailer | `TRAILER_TRACK` |

**With two tracks in hand, all five mazes share one.** That is a placement
decision, not a design limit — the table takes a different track per maze the
moment there are more. `find_the_way` is the menu and trailer track;
`ah_eh_oh` is the run track.

The trailer gets its own entry rather than continuing the menu's, because the
reel is a cut showreel with its own pacing and it opens on a hard cut already.

---

## 4. Rules

**Looping is set in code, not in the `.import` file.** Godot's mp3 importer
defaults `loop=false`, so every track added would need its import file edited
by hand to loop — a per-file step that is easy to forget and produces music
that simply stops one minute in, with no error anywhere. `Music` sets `loop`
on the stream resource at load, so any file dropped into the table loops
because it is music, not because someone remembered.

**The same track across a transition does not restart.** `play()` compares
against what is already playing and returns early if it matches. Menu → game
on a shared track is then seamless; the alternative is a restart-from-zero on
every button press.

**Crossfades on a change, cuts on nothing.** A track change fades the old out
and the new in over `FADE_SECONDS`, using two players and swapping between
them. A hard cut between two pieces of music is the single most noticeable
audio flaw in a game, and it would land on the two most-seen transitions in
the product — pressing PLAY, and the trailer's return to the menu.

**Pause ducks; it does not stop.** Pausing drops the music to `DUCK_DB` rather
than silencing it, and unpausing brings it back. Music continuing quietly is
what tells the player the game is still there and merely held. It is a volume
change, not a transport change, so the track does not lose its position.

The autoload sets `process_mode = PROCESS_MODE_ALWAYS` so the fade keeps
running if the tree is ever paused — the game's own pause is a phase, not
`SceneTree.paused`, but a future real pause must not freeze a crossfade
half-way and leave the mix stuck between two tracks.

**Nothing in the simulation may read `Music`.** Movement, turn resolution, the
buffer, the barrier and the penalties behave identically with the audio server
absent, which is what `--headless` gives every harness. This is the same
separation landmarks have (CLAUDE.md §6): the rules layer can *reach* the
autoload, and must never *use* it.

---

## 5. Volume

One `music` bus, created at runtime if the project has no custom bus layout, so
the master bus stays free for future SFX. `Music.set_volume(linear)` moves that
bus; `Music.set_muted(bool)` toggles it.

Per-track `volume_db` trims the *player*, not the bus, so evening out two
differently-mastered tracks does not move the player's own volume setting.

---

## 6. Failure is quiet but not silent

A missing file, a bad key, or a headless run with no audio driver must never
take the game down — music is the least essential thing on screen, and a crash
in it costs the whole run. Every entry point checks and returns.

A bad track name or unloadable file prints **once per name** (`push_warning`),
not once per call, so a per-maze mistake does not fill the log across a run
while still reaching `logs/errors.log`, which is the only feedback channel
this project has (CLAUDE.md §12).

---

## 7. Adding a track

1. Drop the file in `audio/music/`.
2. Add an entry to `Tuning.TRACKS`.
3. Point something at it — a maze's `music` key, or one of the `Music`
   constants.

No code change. `MusicTest.gd` asserts every declared track resolves to a real
file and that every maze names a track that exists, so a typo fails a harness
rather than going silent in play.
