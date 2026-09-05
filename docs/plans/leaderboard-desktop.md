# Desktop leaderboards over REST

The web build reaches Firebase through `JavaScriptBridge` into the SDK loaded by
`shell.html`. Desktop has no bridge, so `Leaderboard.available` is false there
and the boards are empty — which makes the desktop shortcut a practice mode that
posts nothing and shows no history.

This adds a second backend behind the *same* public surface, so nothing that
calls `Leaderboard` changes.

## Transport: HTTPRequest against the REST APIs

Godot has no Firebase SDK, but both services this needs are plain REST:

- **Auth** — `identitytoolkit.googleapis.com/v1/accounts:signUp` for an anonymous
  account, and `securetoken.googleapis.com/v1/token` to refresh the ID token.
- **Firestore** — `firestore.googleapis.com/v1/projects/.../documents/...`,
  with the ID token as a bearer credential.

Both are already verified working against this project: the same endpoints were
driven by hand while proving the rules, including a rejected worse-score update
and a rejected foreign-uid write.

## The ID token expires after an hour, and that is the whole complication

The web SDK refreshes silently. Over REST it has to be done here:

- The **refresh token** is long-lived and is what gets persisted.
- The **ID token** lasts ~3600s and is what Firestore actually accepts.
- Refresh is attempted when the token is within `TOKEN_REFRESH_MARGIN` of expiry,
  and *always* before a post — a run that ends 59 minutes in must not fail
  because the token went stale while the player was driving.

A refresh that fails leaves the client unauthenticated rather than crashing: the
boards go empty, the game is unaffected. This is the same rule the bridge follows.

## Identity: a stable desktop account, not the browser's

Signing in anonymously on every launch would mint a **new uid each time**, so
every desktop run would post as a different player and the run history would
always be empty. The refresh token is therefore persisted to `user://` beside the
player name.

**Desktop and browser remain different players, and that is inherent.** Anonymous
auth has no cross-device identity — the browser's uid lives in browser storage
and there is no way to reach it from a desktop process. Linking them needs a real
sign-in (email or a provider), which was explicitly rejected for this game: a
score that needs a signup to count is a score that gets thrown away.

So a player who plays in both places holds two entries under one display name.
Recorded as a known cost, not hidden. The display name is shared (it is stored
per-uid server-side but set from the same local config), so the board reads
sensibly even though the rows are technically two players.

## Firestore REST differs from the SDK in two ways that matter

- **Typed values.** REST wants `{"doubleValue": 123}` rather than `123`, and
  reads come back the same way, so both directions need conversion. Numbers are
  written as `doubleValue` deliberately: `integerValue` is a *string* in JSON and
  round-trips as one.
- **Queries are POSTed to `:runQuery`**, not expressed as URL parameters. A board
  is a `structuredQuery` with a `where` on `board`, an `orderBy`, and a `limit`.
  The response is an array of `{document: ...}` wrappers, and entries with no
  `document` key are skipped — the API emits those as progress markers.

## Structure

`Leaderboard` keeps its public surface exactly: `post_run`, `request_board`,
`request_history`, `set_player_name`, `has_name`, `cached_board`, and all four
signals. Internally it gains a backend switch:

```
_backend = BRIDGE   when OS.has_feature("web") and window.mazeRacerLB exists
           REST     otherwise, once anonymous sign-in succeeds
           NONE     if neither is reachable
```

The bridge path is untouched. Nothing in the simulation reads any of it, and
every harness still gets `available == false` — a harness has no network and must
never wait on one, which is why REST sign-in is not attempted under
`OS.has_feature("template")`-less headless runs unless explicitly enabled.

## Tests

`ShellTest` already asserts the offline behaviour, and that must keep passing
unchanged: no autoload reachable means no prompt, empty boards, and a playable
game. The new coverage is for the pure logic, which is the part worth testing
without a network:

- Firestore typed-value conversion round-trips (`_to_fields` / `_from_fields`).
- A document ID is built as `uid_board_seed` for the shared boards and
  `uid_timestamp` for general — the shape the deployed rules require.
- Token expiry arithmetic: a token inside the margin is stale, one outside is not.

Live verification is by driving the real desktop build and reading the board back,
which is the only thing that proves the REST path end to end.
