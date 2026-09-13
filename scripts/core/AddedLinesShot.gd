# The picture half of the six added lines (CLAUDE.md section 7).
#
# Two of the six change what is on screen, and neither is visible to any
# headless assertion:
#
#   - Extra Card raises the card count to 4 and then 5, and the cards NARROW to
#     fit. RulesTest can assert the count and SceneTest can assert the screen
#     opens; neither can see a row overrunning the viewport or description text
#     clipped out of a slimmer card. This is section 12's hard-coded-layout trap,
#     and the only instrument for it is a rendered frame.
#   - Gate Size raises the marker and widens its footprint. Height is exactly the
#     property GateShot exists to check for the base marker -- "can I see it
#     coming" -- so the upgraded one needs the same question asked of it.
#
# The gate shots SEEK a gate rather than firing on a timer, for the reason
# GateShot and PaletteShot do: a frame taken on a schedule lands in plain
# corridor and shows nothing of the thing it is meant to check.
#
# Usage:
#   launch.ps1 -Script res://scripts/core/AddedLinesShot.gd
extends SceneTree

var _game: Node
var _frame := 0
var _stage := 0
var _last_cell := Vector2i(-999, -999)


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_game = load("res://scenes/Game.tscn").instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	match _stage:
		0:
			# The card row at each count, which is the case that overruns.
			_open_cards(0)
			_stage = 1
		1:
			# Captured a frame LATER than the build: process_frame fires before
			# the UI is drawn, so shooting in the same frame grabs the previous
			# screen -- the trap SummaryShot records, which produced two
			# identical files there.
			_capture("cards_3")
			_open_cards(1)
			_stage = 2
		2:
			_capture("cards_4")
			_open_cards(2)
			_stage = 3
		3:
			_capture("cards_5")
			_stage = 4
		4:
			# A bare gate marker, for the comparison the height shot needs.
			_restart(0)
			_stage = 5
		5:
			if _seek_gate():
				_report()
				_capture("gate_height_0")
				_restart(3)
				_stage = 6
			elif _frame > 3000:
				printerr("FAILED: never reached a gate at rank 0")
				quit(1)
		6:
			if _seek_gate():
				_report()
				_capture("gate_height_3")
				_stage = 7
			elif _frame > 6000:
				printerr("FAILED: never reached a gate at rank 3")
				quit(1)
		7:
			print("RESULT: PASS")
			quit(0)


# Open the card screen with Extra Card at `rank`, so the row is drawn at 3, 4
# and 5 cards.
func _open_cards(rank: int) -> void:
	for i in rank:
		_game.upgrades.take(Upgrades.Line.EXTRA_CARD)
	# A spread of other ranks too, so the cards carry real "RANK n" text and
	# real descriptions rather than a screen of identical first-rank cards.
	var taken := 0
	for line in Upgrades.DEFINITIONS.keys():
		if taken >= 6:
			break
		if _game.upgrades.is_legendary(int(line)):
			continue
		if int(line) != Upgrades.Line.EXTRA_CARD:
			_game.upgrades.take(int(line))
		taken += 1
	_game._upgrade_screen.present(_game.upgrades, 3)


# Rebuild the run with Gate Size at `rank`. The marker's height is applied at
# mesh build time, so the rank has to be held BEFORE the maze is built.
func _restart(rank: int) -> void:
	root.remove_child(_game)
	_game.free()
	_game = load("res://scenes/Game.tscn").instantiate()
	root.add_child(_game)
	for i in rank:
		_game.upgrades.take(Upgrades.Line.GATE_SIZE)
	# Rebuilt rather than merely rescaled, so the shot exercises the ordinary
	# build path a real run takes rather than the mid-maze rescale.
	_game._mesh.build(_game.maze, 0, _game.upgrades.gate_height_scale(),
		_game.upgrades.gate_girth_scale())
	_last_cell = Vector2i(-999, -999)


# Drive until a gate is a few cells STRAIGHT AHEAD -- the distance and the
# bearing the question is about. "Can I see it coming" is not answered by a gate
# level with the camera or behind it, and the first version of this accepted any
# gate within 4 cells on either axis: it shot one sitting beside the marker,
# which shows the marker's colour and nothing whatever about its height.
func _seek_gate() -> bool:
	_autopilot()
	var racer: Racer = _game.racer
	if racer == null or _game.phase != 0:
		return false
	for gate in racer.maze.gates:
		if _sees(racer, gate):
			return true
	return false


# Is `gate` actually VISIBLE from where the racer stands -- straight ahead, 2-5
# cells out, with open corridor the whole way?
#
# Alignment alone is not visibility, and that is the bug this replaced: the
# earlier version checked only that the gate shared an axis and was in range, so
# it fired on a gate sitting behind a wall. The rank 0 control frame came out
# showing a dead end, which makes the before/after pair useless for the one
# question the shots exist to answer.
func _sees(racer: Racer, gate: Vector2i) -> bool:
	var ahead: Vector2i = Maze.DIR_VECTORS[racer.facing]
	var cell: Vector2i = racer.cell
	for stepped in 5:
		# Walk the corridor a cell at a time, stopping the moment a wall closes
		# the line -- which is precisely what "can I see it coming" means.
		if not racer.maze.is_open(cell, racer.facing):
			return false
		cell += ahead
		if cell == gate:
			return stepped >= 1
	return false


func _autopilot() -> void:
	# Any pick is taken IMMEDIATELY, so a card screen can never be up on the frame
	# a gate shot is captured. The first version let one open over the gate and
	# produced a frame of the card row where the marker's height should have been.
	if _game.phase == 1:
		var offered: Array = _game._upgrade_screen._lines
		_game._on_upgrade_chosen(-1 if offered.is_empty() else offered[0])
		return
	var racer: Racer = _game.racer
	if racer == null or _game.phase != 0:
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


# What the shot actually caught, so a frame with no marker in it can be told
# from a frame where the marker is merely dim.
func _report() -> void:
	var racer: Racer = _game.racer
	print("  cell=%s facing=%d gates=%s height=%.2f girth=%.2f" % [
		str(racer.cell), racer.facing, str(racer.maze.gates),
		_game.upgrades.gate_height_scale(), _game.upgrades.gate_girth_scale()])
	for gate in racer.maze.gates:
		if _sees(racer, gate):
			print("  SEES gate at %s, delta %s" % [str(gate), str(gate - racer.cell)])


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/shot_%s.png" % label
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
