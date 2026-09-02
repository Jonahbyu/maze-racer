# Shoots a gate before and after it is taken, plus the minimap showing both.
#
# The picture half of the spent-gate work. `SceneTest` proves the material
# changes and `RulesTest` proves the racer records the cell, but neither can
# answer the question that actually matters: does a spent gate read as "been
# there" rather than as a live gate seen dimly through fog, and is it still
# distinguishable from the exit?
#
# It SEEKS a gate rather than shooting on a timer, for the reason GateShot and
# PaletteShot do: gates sit at even intervals along the solve path, so a shot
# taken on a frame count lands in plain corridor and shows nothing of the thing
# it exists to check.
#
# Two shots per gate. The "before" is what makes the "after" legible -- a dim
# amber-blue pillar in isolation says nothing; the pair says the colour moved.
#
# Usage:
#   launch.ps1 -Script res://scripts/core/GateSpentShot.gd
extends SceneTree

# How many gates to document. Two is enough to show a spent gate and a live one
# in the same run, which is the comparison the change is about.
const GATES := 2

# Frames to hold after a gate is taken before the "after" shot. The racer drives
# THROUGH a gate, so shooting on the same frame puts the camera inside the
# marker; a beat later it is behind and looking at it.
const AFTER_FRAMES := 26

# A second "after" shot from further back, with the camera swung around to face
# the gate just taken. The close after-shot proves the wash is gone; only a look
# BACK proves the marker still reads as a gate -- which is the whole point of
# keeping it. Facing away from something says nothing about how it looks.
const LOOKBACK_FRAMES := 150

# Give up rather than spin forever if the autopilot never reaches a gate.
const FRAME_BUDGET := 6000

var _game: Node
var _frame := 0
var _last_cell := Vector2i(-999, -999)
var _seen := 0
var _armed := false
var _after_at := -1
var _lookback_at := -1
var _aimed := false
var _lookback_cell := Vector2i.ZERO


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	# Pinned so the shot is reproducible: an unseeded run draws a different maze
	# every time, which makes "did this look right last time" unanswerable.
	_game.trailer_seed = 20250901
	root.add_child(_game)

	# The minimap has to be up, since half the change is on it. Rank 2 zooms out
	# far enough to hold a taken gate and the player at once, which is the whole
	# point of marking them there.
	_game.upgrades.take(Upgrades.Line.MINIMAP)
	_game.upgrades.take(Upgrades.Line.MINIMAP)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1

	if _frame > FRAME_BUDGET:
		printerr("gave up after %d frames with %d gates shot" % [_frame, _seen])
		quit(1)
		return

	# The "after" shot, once the racer is clear of the arch it just drove
	# through.
	if _after_at > 0 and _frame >= _after_at:
		_capture("gate%d_after" % _seen)
		_after_at = -1
		_lookback_at = _frame + LOOKBACK_FRAMES
		_lookback_cell = _game.racer.gates_cleared[-1]
		_seen += 1
		if _seen >= GATES:
			print("RESULT: PASS")
			quit(0)
			return

	# Two frames: aim, then shoot. process_frame fires BEFORE the game's own
	# _process, so aiming and capturing in one frame means Game._update_camera
	# runs in between and puts the camera straight back -- which is exactly what
	# the first attempt at this shot did, producing a forward-facing frame that
	# looked like the recolour had failed. The game is stopped as well as aimed,
	# so nothing re-aims it while the shot is set up.
	if _lookback_at > 0 and _frame >= _lookback_at:
		if not _aimed:
			_game.set_process(false)
			_look_back_at_cell(_lookback_cell)
			_aimed = true
			return
		_capture("gate%d_lookback" % (_seen - 1))
		_game.set_process(true)
		_aimed = false
		_lookback_at = -1
		return

	_autopilot()

	# Shoot just SHORT of the gate, not on top of it: the question is what a
	# live gate looks like from the corridor, which is where the comparison
	# happens.
	if not _armed and _after_at < 0:
		var racer: Racer = _game.racer
		if racer != null and _distance_to_next_gate(racer) <= 2.5:
			_capture("gate%d_before" % _seen)
			_armed = true


func _distance_to_next_gate(racer: Racer) -> float:
	var best := 9999.0
	for gate in racer.maze.gates:
		if racer.gates_cleared.has(gate):
			continue
		var d := Vector2(gate - racer.cell).length()
		best = minf(best, d)
	return best


func _autopilot() -> void:
	var racer: Racer = _game.racer

	# A gate opens the card screen, and taking the card is what fires the
	# recolour -- so this is also the trigger for the "after" shot.
	if _game.phase == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(offered[0])
		# Only a real gate arms the after-shot. The run OPENS on a loadout pick
		# (CLAUDE.md section 7), which takes the same screen and takes no gate.
		if _armed:
			_after_at = _frame + AFTER_FRAMES
			_armed = false
		return

	if racer == null or _game.phase != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	# At most one decision per cell: re-requesting the same turn every frame
	# pays the turn cost every frame and pins the racer at the speed floor.
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


# Aim the camera at a cell for one frame, overriding Game's own framing.
#
# Game re-aims the camera every _process, so this has to be the last thing done
# before the capture -- anything that ticks the game afterwards puts it back.
func _look_back_at_cell(cell: Vector2i) -> void:
	var cam: Camera3D = _game._camera
	if cam == null:
		return
	var target := Vector3(
		cell.x * Tuning.CELL_SIZE,
		Tuning.WALL_HEIGHT * 1.2,
		cell.y * Tuning.CELL_SIZE
	)
	# Backed off along the line from the gate to the racer, so the shot is taken
	# from where a player who drove on would actually be looking from.
	var racer: Racer = _game.racer
	var from := Vector3(
		racer.cell.x * Tuning.CELL_SIZE,
		Tuning.CAM_HEIGHT,
		racer.cell.y * Tuning.CELL_SIZE
	)
	cam.position = from
	cam.look_at(target, Vector3.UP)


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/shot_%s.png" % label
	var err := image.save_png(path)
	if err == OK:
		print("saved %s  (speed %.2fx, cell %s, cleared %d)" % [
			path, _game.racer.speed, _game.racer.cell,
			_game.racer.gates_cleared.size()
		])
	else:
		printerr("FAILED to save %s (error %d)" % [path, err])
