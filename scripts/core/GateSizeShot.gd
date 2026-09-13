# The CONTROLLED picture of Gate Size (CLAUDE.md section 7).
#
# AddedLinesShot already shoots this line, and its two frames cannot answer the
# question: it restarts the run per rank, so they land at different distances on
# different mazes. That shows a marker is there. It cannot show one is BIGGER,
# which is exactly the fault reported -- "the gate size upgrade isn't visually
# making the gates bigger" -- and exactly what a pair of uncontrolled frames is
# unable to settle either way.
#
# So this holds EVERYTHING fixed -- one seed, one gate, one camera pose -- and
# varies only the rank. Two distances, because the two halves of the marker fail
# differently: FAR is the "can I see it coming" question GateShot asks, and NEAR
# is where the fault actually lived. The camera is capped below WALL_HEIGHT
# (section 12), so a taller marker adds only to the strip above the wall line --
# at 5 cells that strip is most of what is visible, and at 1.5 cells it is off
# the top of the frame entirely, leaving the width to do all the work.
#
# Usage:
#   launch.ps1 -Script res://scripts/core/GateSizeShot.gd
extends SceneTree

# One seed, so every frame is the same maze and the same gate.
const SEED := 12345

# Cells back from the gate. Far is the warning distance; near is collection
# range, where height contributes nothing and only girth can read.
const DISTANCES := {"far": 5.0, "near": 1.5}

var _game: Node
var _stage := 0
var _rank := 0
var _shot := 0
var _gate: Vector2i
var _approach := Vector2i(0, 1)
var _keys: Array


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_keys = DISTANCES.keys()
	_game = load("res://scenes/Game.tscn").instantiate()
	_game.run_seed = SEED
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	match _stage:
		0:
			# A run BOOTS into UPGRADING (section 7): steering is inert and the
			# cards are drawn over the frame until a pick is taken. Declined
			# rather than taken, so no other line can alter what is on screen.
			_game._on_upgrade_chosen(-1)
			if not _pick_gate():
				printerr("FAILED: no gate with a clear approach on seed %d" % SEED)
				quit(1)
				return
			_stage = 1
		1:
			_aim(float(DISTANCES[_keys[_shot]]))
			_stage = 2
		2:
			# Captured a frame LATER than the aim. Game._process re-frames the
			# camera every tick and process_frame fires before it, so aiming and
			# capturing in one frame gets the aim overwritten in between -- the
			# trap GateSpentShot records, which produces a forward-facing frame
			# that looks exactly like the feature having failed.
			_capture()
			_advance()


func _advance() -> void:
	_shot += 1
	if _shot < _keys.size():
		_stage = 1
		return

	_shot = 0
	_rank += 1
	if _rank > _max_rank():
		print("RESULT: PASS")
		quit(0)
		return

	var u: Upgrades = _game.upgrades
	while u.rank(Upgrades.Line.GATE_SIZE) < _rank:
		u.take(Upgrades.Line.GATE_SIZE)
	# Rescaled rather than rebuilt, so the shot exercises the mid-maze path a
	# real pick takes -- and so the markers keep their names (section 12).
	_game._mesh.rescale_gates(u.gate_height_scale(), u.gate_girth_scale())
	_stage = 1


func _max_rank() -> int:
	return int(Upgrades.DEFINITIONS[Upgrades.Line.GATE_SIZE]["max_rank"])


# A gate with CLEAR CORRIDOR behind it, along the axis the camera backs down.
#
# Taking gates[0] is not good enough and produced a frame with no marker in it
# at all: gates sit wherever the solve path puts them, and the first one on this
# seed is hard against the maze's west edge -- so a camera parked 5 cells south
# of it sits inside the boundary wall, looking at solid geometry. That reads
# exactly like the upgrade having failed, which is the one thing this instrument
# must never be able to say by accident. It is the same reason GateShot and
# AddedLinesShot seek an approach rather than trusting an axis and a range.
func _pick_gate() -> bool:
	var maze: Maze = _game.maze
	var need := int(ceil(float(DISTANCES.values().max()))) + 1
	# All four approaches, not just one: a gate sits wherever the solve path put
	# it, and demanding a particular heading rejects most of them for no reason.
	var dirs := {
		Maze.S: Vector2i(0, 1), Maze.N: Vector2i(0, -1),
		Maze.E: Vector2i(1, 0), Maze.W: Vector2i(-1, 0),
	}
	for gate in maze.gates:
		for dir in dirs:
			var step: Vector2i = dirs[dir]
			var clear := true
			var at: Vector2i = gate
			for _i in need:
				if not maze.is_open(at, int(dir)):
					clear = false
					break
				at += step
			if clear:
				_gate = gate
				_approach = step
				return true
	return false


# Park the camera a fixed distance from the gate, looking straight at it, and
# stop the game so _process cannot re-frame it.
func _aim(cells: float) -> void:
	_game.set_process(false)
	var cam: Camera3D = _game._camera
	var gx := _gate.x * Tuning.CELL_SIZE
	var gz := _gate.y * Tuning.CELL_SIZE
	var back := Vector3(_approach.x, 0.0, _approach.y) * cells * Tuning.CELL_SIZE
	cam.position = Vector3(gx, Tuning.CAM_HEIGHT, gz) + back
	cam.look_at(Vector3(gx, Tuning.CAM_HEIGHT, gz), Vector3.UP)


func _capture() -> void:
	var u: Upgrades = _game.upgrades
	var image := root.get_texture().get_image()
	var path := "res://logs/shot_gatesize_%s_rank%d.png" % [_keys[_shot], _rank]
	if image.save_png(path) == OK:
		print("saved %s  (height %.2f, girth %.2f)" % [
			path, u.gate_height_scale(), u.gate_girth_scale()])
	else:
		printerr("FAILED to save %s" % path)
