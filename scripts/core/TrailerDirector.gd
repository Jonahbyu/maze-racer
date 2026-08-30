# The attract-mode trailer: a seeded, self-playing showreel of all five mazes.
#
# Owns a real Game and drives it through its ordinary public surface -- the same
# distance-field autopilot RunTest uses, plus scripted cuts between segments. No
# movement rule lives here, and nothing in Racer knows this exists.
#
# docs/specs/trailer.md
class_name TrailerDirector
extends Node

signal finished()

# Fixed, checked in, never the clock.
#
# A trailer that generated a fresh maze each play is a demo that sometimes opens
# on a blank corridor and sometimes drives into a dead end on camera. This is
# the "did we get lucky" failure CLAUDE.md section 12 flags for tests, and it
# bites harder here because this is the first thing a new player sees.
const TRAILER_SEED := 20260829

# Seconds of driving per maze segment, before any gate hold.
const SEGMENT_SECONDS := 5.0

# How long the upgrade cards stay up on a gate segment. Long enough to read
# three cards; short enough that the reel does not stall on a static screen.
const GATE_HOLD_SECONDS := 2.2

# Cells back along the solve path to start, on a segment that shows a gate.
#
# Gates sit at even intervals along the solve path (CLAUDE.md section 6), so the
# first is far more than five seconds of driving from the start cell. Waiting
# for one would spend the whole reel in plain corridor, so a gate segment CUTS
# to just short of a real gate and drives into it.
const GATE_APPROACH_CELLS := 9

# Fade in/out at each cut, in seconds.
const FADE_SECONDS := 0.45

# The reel. One entry per maze, in order.
#
# `build` is applied before the maze starts and `speed` seeds the ramp, because
# the whole point of the reel is the escalation: maze 1 is the bare game, and by
# maze 5 the Path Indicator is lighting junctions, the minimap is wide, the
# Golden Trail is firing and the racer is moving fast. Showing maze 5 at 1.0x
# with a rank-0 HUD would advertise the wrong game.
#
# `gate` marks the three segments that cut to a gate. `pick` is the card index
# taken there -- scripted, not random, so the reel always lands on a card worth
# reading.
const SEGMENTS := [
	{
		"maze": 0,
		"speed": 1.6,
		"gate": false,
		"pick": 0,
		"caption": "auto-forward.  arrow keys commit turns.",
		"build": [],
	},
	{
		"maze": 1,
		"speed": 2.8,
		"gate": true,
		"pick": 0,
		"caption": "gates pause the clock.  pick an upgrade.",
		"build": [
			Upgrades.Line.MINIMAP,
			Upgrades.Line.BUFFER_WINDOW,
		],
	},
	{
		"maze": 2,
		"speed": 4.0,
		"gate": true,
		"pick": 1,
		"caption": "path indicator lights the way out.",
		"build": [
			Upgrades.Line.PATH_INDICATOR,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.BARRIER_CAPACITY,
			Upgrades.Line.SNAP_TURN,
		],
	},
	{
		"maze": 3,
		"speed": 5.2,
		"gate": false,
		"pick": 0,
		"caption": "the maze gets faster than you do.",
		"build": [
			Upgrades.Line.PATH_INDICATOR,
			Upgrades.Line.PATH_INDICATOR,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.GOLDEN_TRAIL,
			Upgrades.Line.BASE_SPEED,
			Upgrades.Line.SNAP_TURN,
			Upgrades.Line.BARRIER_CAPACITY,
		],
	},
	{
		"maze": 4,
		"speed": 6.4,
		"gate": true,
		"pick": 0,
		"caption": "survive five.  the timer is the score.",
		"build": [
			Upgrades.Line.PATH_INDICATOR,
			Upgrades.Line.PATH_INDICATOR,
			Upgrades.Line.PATH_INDICATOR,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.MINIMAP,
			Upgrades.Line.GOLDEN_TRAIL,
			Upgrades.Line.GOLDEN_TRAIL,
			Upgrades.Line.BASE_SPEED,
			Upgrades.Line.BASE_SPEED,
			Upgrades.Line.SNAP_TURN,
			Upgrades.Line.SNAP_TURN,
			Upgrades.Line.BARRIER_CAPACITY,
			Upgrades.Line.BARRIER_REGEN,
			Upgrades.Line.GATE_COMPASS,
			Upgrades.Line.FAST_TURNAROUND,
		],
	},
]

var _game: Node = null
var _overlay: TrailerOverlay = null

var _segment := -1
var _segment_time := 0.0
var _gate_hold := 0.0
var _shown_gate := false
var _done := false

# The autopilot decides once per cell, never per frame -- re-requesting the same
# turn every frame pays the per-turn speed cost repeatedly and pins the racer at
# the floor (the trap Screenshot.gd documents).
var _last_cell := Vector2i(-999, -999)


func _ready() -> void:
	_game = load("res://scenes/Game.tscn").instantiate()
	# Seed BEFORE the game runs its own _ready, so maze 1 is already the
	# trailer's maze rather than a clock-seeded one that gets thrown away.
	_game.set("trailer_seed", TRAILER_SEED)
	add_child(_game)

	_overlay = TrailerOverlay.new()
	_overlay.name = "TrailerOverlay"
	add_child(_overlay)

	_advance()


func _process(delta: float) -> void:
	if _done or _game == null or not is_instance_valid(_game):
		return

	_overlay.step(delta)

	# Hold on the upgrade cards, then pick one. The Game is in its UPGRADING
	# phase here, which stops the racer and the timer on its own -- the trailer
	# just has to wait and then press a card, exactly as a player would.
	if _gate_hold > 0.0:
		_gate_hold -= delta
		if _gate_hold <= 0.0:
			_choose_card()
		return

	_autopilot()

	_segment_time += delta
	if _segment_time >= SEGMENT_SECONDS:
		_advance()


# --- Segments ----------------------------------------------------------------

func _advance() -> void:
	_segment += 1
	if _segment >= SEGMENTS.size():
		_finish()
		return

	var entry: Dictionary = SEGMENTS[_segment]
	var maze_index := int(entry["maze"])

	# Rebuild the upgrade set from scratch for each segment rather than adding to
	# the last one. The reel is CUT, not continuous, so a segment's build is a
	# statement about what that maze looks like with that build -- carrying ranks
	# forward would make the later entries depend on the order the earlier ones
	# happened to be written in.
	var upgrades := Upgrades.new(TRAILER_SEED + _segment)
	for line in entry["build"]:
		upgrades.take(int(line))
	_game.set("upgrades", upgrades)

	_game._start_maze(maze_index)

	# _start_maze builds a fresh Racer, so anything set on the racer has to come
	# after it (CLAUDE.md section 12, "node references captured before a maze
	# change go stale").
	var racer: Racer = _game.get("racer")
	if racer != null:
		if bool(entry["gate"]):
			_place_before_gate(racer)
		racer.speed = float(entry["speed"])

	_segment_time = 0.0
	_shown_gate = false
	_last_cell = Vector2i(-999, -999)

	_overlay.cut(String(entry["caption"]),
		"%d / %d   %s" % [
			maze_index + 1,
			Tuning.MAZES.size(),
			String(Tuning.MAZES[maze_index]["name"]).to_upper(),
		],
		FADE_SECONDS)


# Move the racer to a point on the solve path a short way before a real gate.
#
# Uses the maze's own gate list and solve path, so the racer arrives at a
# genuine gate cell and Racer emits gate_entered the ordinary way. Nothing about
# the gate is faked -- only where the segment starts from.
func _place_before_gate(racer: Racer) -> void:
	var maze: Maze = racer.maze
	if maze == null or maze.gates.is_empty() or maze.solve_path.is_empty():
		return

	var gate: Vector2i = maze.gates[0]
	var gate_index := maze.solve_path.find(gate)
	if gate_index == -1:
		return

	var start_index := maxi(0, gate_index - GATE_APPROACH_CELLS)
	var cell: Vector2i = maze.solve_path[start_index]

	racer.cell = cell
	racer.progress = 0.0
	racer.lane = 0.0
	racer.lane_target = 0.0
	racer.freeze = 0.0
	racer.scraping = false

	# Face along the route, so the segment opens driving forward rather than
	# into the wall behind.
	var best := maze.best_direction(cell)
	if best != -1:
		racer.facing = best

	# The camera is built for the OLD position and would otherwise sweep across
	# the maze on the first frame of the cut. Snap it onto the new heading.
	var yaw: float = _game._yaw_for(racer.facing)
	_game.set("_cam_yaw", yaw)
	_game.set("_cam_target_yaw", yaw)


func _finish() -> void:
	if _done:
		return
	_done = true
	_overlay.outro(FADE_SECONDS)
	# Let the outro play before handing the screen back to the menu.
	await get_tree().create_timer(1.5).timeout
	emit_signal("finished")


# --- Gate handling -----------------------------------------------------------

# Phase 1 is Game.Phase.UPGRADING -- the cards are up and the sim is stopped.
func _at_gate() -> bool:
	return int(_game.get("phase")) == 1


func _choose_card() -> void:
	var screen = _game.get("_upgrade_screen")
	if screen == null:
		return

	var offered: Array = screen._lines
	if offered.is_empty():
		_game._on_upgrade_chosen(-1)
		return

	var pick: int = SEGMENTS[_segment]["pick"]
	pick = clampi(pick, 0, offered.size() - 1)

	# Dismiss the cards through the screen's own path, so the visible state and
	# the Game phase come back in step exactly as a click would leave them.
	screen._on_card_pressed(offered[pick])


# --- Autopilot ---------------------------------------------------------------

# The same live distance-field router RunTest uses: correct through loops, so it
# never strands itself on camera.
func _autopilot() -> void:
	var racer: Racer = _game.get("racer")
	if racer == null:
		return

	if _at_gate():
		# Arrived at a gate. Hold on the cards rather than picking instantly.
		if not _shown_gate:
			_shown_gate = true
			_gate_hold = GATE_HOLD_SECONDS
			_overlay.note("GATE  -  timer paused")
		return

	# Phase 0 is RACING. Anything else (transition, complete) is not ours to
	# steer -- the trailer cuts on its own clock and never plays a maze out.
	if int(_game.get("phase")) != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	if racer.cell == _last_cell:
		return
	_last_cell = racer.cell

	var best := racer.maze.best_direction(racer.cell)
	if best == -1 or best == racer.facing:
		return

	if best == racer.left_direction():
		racer.request_turn(-1)
	elif best == racer.right_direction():
		racer.request_turn(1)
	else:
		racer.request_reverse()


# --- Skipping ----------------------------------------------------------------

# Any key or click ends the reel. An attract mode that cannot be escaped is a
# hostage situation, and a player pressing a key during a trailer wants to play.
func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.is_echo()) \
		or (event is InputEventMouseButton and event.pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_done = true
	emit_signal("finished")
