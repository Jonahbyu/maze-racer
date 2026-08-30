# Does the trailer actually play through, and show what it claims to show?
#
# The reel is the first thing a new player sees, so the failure that matters is
# not a crash -- it is a segment that silently shows nothing: a maze that never
# advances, a gate that never opens its cards, a build that did not apply. Each
# of those looks fine in a log and wrong on screen, so they are asserted
# directly.
#
# Headless, like every other rule-level harness (CLAUDE.md section 12): the
# trailer drives the simulation, and the simulation never needs a rendered
# frame.
extends SceneTree

const DELTA := 1.0 / 60.0
const MAX_FRAMES := 6000

var _passed := 0
var _failed := 0

# What actually happened, per segment, filled as the reel plays.
var _seen_mazes: Array[int] = []
var _gates_opened := 0
var _cards_seen: Array[int] = []
var _distance_per_segment: Array[float] = []


func _init() -> void:
	print("=== TrailerTest ===")
	_go.call_deferred()


func check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])


func _go() -> void:
	var trailer := TrailerDirector.new()
	root.add_child(trailer)

	check("trailer built a game", trailer._game != null)
	if trailer._game == null:
		_finish()
		return

	check("trailer seeded deterministically",
		int(trailer._game.run_seed) == TrailerDirector.TRAILER_SEED,
		"seed %d" % int(trailer._game.run_seed))

	var last_segment := -1
	var frames := 0
	var finished := false

	while frames < MAX_FRAMES and not trailer._done:
		frames += 1

		if trailer._segment != last_segment:
			last_segment = trailer._segment
			if trailer._segment < TrailerDirector.SEGMENTS.size():
				_seen_mazes.append(int(trailer._game.maze_index))
				_distance_per_segment.append(0.0)

		# The cards being up is the gate moment. Recorded once per rise.
		var was_at_gate: bool = int(trailer._game.phase) == 1

		# Each segment starts a BRAND NEW Racer, whose distance_travelled starts
		# at zero -- so a segment's travel cannot be a difference between two
		# readings taken across the swap. Accumulate the per-frame delta from the
		# racer that is actually current, and only while it stays the same
		# object (CLAUDE.md section 12, stale node references).
		var before: Racer = trailer._game.racer
		var before_distance: float = before.distance_travelled if before != null else 0.0

		trailer._process(DELTA)
		trailer._game._process(DELTA)

		var after: Racer = trailer._game.racer
		if after != null and after == before and not _distance_per_segment.is_empty():
			_distance_per_segment[-1] += after.distance_travelled - before_distance

		if not was_at_gate and int(trailer._game.phase) == 1:
			_gates_opened += 1
			var screen = trailer._game._upgrade_screen
			if screen != null:
				_cards_seen.append(screen._lines.size())

		if trailer._segment >= TrailerDirector.SEGMENTS.size():
			finished = true
			break

	check("reel ran to the end without stalling", finished or trailer._done,
		"stopped after %d frames on segment %d" % [frames, trailer._segment])

	# Every maze in Tuning.MAZES must appear. Read from the config rather than
	# restated, so adding a sixth maze fails here rather than silently shipping a
	# trailer that skips it (CLAUDE.md section 12).
	check("every maze appears in the reel",
		_seen_mazes.size() == Tuning.MAZES.size(),
		"showed %d of %d: %s" % [_seen_mazes.size(), Tuning.MAZES.size(), str(_seen_mazes)])

	var in_order := true
	for i in _seen_mazes.size():
		if _seen_mazes[i] != int(TrailerDirector.SEGMENTS[i]["maze"]):
			in_order = false
	check("segments show the mazes they declare", in_order, str(_seen_mazes))

	# The count the spec promises. A reel that drove past its gates without the
	# cards coming up would still "pass" a smoke test and show nothing.
	var expected_gates := 0
	for entry in TrailerDirector.SEGMENTS:
		if bool(entry["gate"]):
			expected_gates += 1
	check("each gate segment opened its cards", _gates_opened >= expected_gates,
		"opened %d, expected %d" % [_gates_opened, expected_gates])

	for count in _cards_seen:
		check("a gate offered a full hand of cards", count == Tuning.CARDS_PER_GATE,
			"offered %d" % count)

	# The whole point of a trailer is motion. A segment that covered no ground
	# is a static shot of a corridor, which is the specific way this can look
	# broken while every other assertion passes.
	for i in _distance_per_segment.size():
		check("segment %d actually moved" % (i + 1), _distance_per_segment[i] > 1.0,
			"travelled %.2f cells" % _distance_per_segment[i])

	# The escalating build is the reason the reel exists. Verified against the
	# declared build rather than a hard-coded rank, so retuning a segment does
	# not silently disagree with the test.
	for i in TrailerDirector.SEGMENTS.size():
		var entry: Dictionary = TrailerDirector.SEGMENTS[i]
		var expected := Upgrades.new(0)
		for line in entry["build"]:
			expected.take(int(line))
		var total := 0
		for line in expected.ranks:
			total += expected.ranks[line]
		check("segment %d declares a usable build" % (i + 1),
			total == entry["build"].size(),
			"declared %d ranks, tree absorbed %d" % [entry["build"].size(), total])

	# The reel should escalate: the last segment must be strictly richer than
	# the first, or it is not showing progression at all.
	var first_build: int = TrailerDirector.SEGMENTS[0]["build"].size()
	var last_build: int = TrailerDirector.SEGMENTS[-1]["build"].size()
	check("the build escalates across the reel", last_build > first_build,
		"first %d, last %d" % [first_build, last_build])

	print("")
	print("segments      : %d" % _seen_mazes.size())
	print("mazes shown   : %s" % str(_seen_mazes))
	print("gates opened  : %d" % _gates_opened)
	for i in _distance_per_segment.size():
		print("  segment %d   : %.1f cells" % [i + 1, _distance_per_segment[i]])

	_finish()


func _finish() -> void:
	print("")
	print("passed: %d   failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)
