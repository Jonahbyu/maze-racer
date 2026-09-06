# The picture half of the marker picker (CLAUDE.md, "The marker's shape is the
# player's to pick"): one frame per shape, from the game's own trailing camera.
#
# Not a test. RulesTest asserts that every outline points and SceneTest asserts
# that every one builds a mesh, and neither can answer the question that
# actually matters -- whether the silhouette READS as pointing from behind and
# slightly above, at the shallow angle the player sees it from. That is the only
# angle any of this is for, and it is why the shot is taken in a real corridor
# rather than from a preview camera: the marker has to hold up against lit wall
# bands and the floor grid, not against an empty background.
#
# It also shoots the SCRAPING state once, because the amber is the reason colour
# is not on the menu -- a shape that swallows its own state colour would defeat
# the split the whole feature rests on.
extends SceneTree

var _game: Node
var _frame := 0
var _shape_index := 0
var _last_cell := Vector2i(-999, -999)
var _scrape_shot := false
# True when a shape has been built and is waiting for the NEXT frame to draw it.
var _armed := false

# Long enough for the maze to build, the camera to settle behind the racer and
# the speed to come off the floor, so the frame looks like play rather than like
# a spawn.
const SETTLE := 100

# Give up seeking a corridor after this and shoot anyway. A shape must not go
# unphotographed because the autopilot happened not to find a clean stretch --
# a missing frame reads as the tool failing rather than as the shape being fine.
const PATIENCE := SETTLE * 8


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_autopilot()

	# BUILD ON ONE FRAME, CAPTURE ON THE NEXT. process_frame fires BEFORE the
	# frame is drawn, so swapping the marker and shooting in the same callback
	# photographs the PREVIOUS shape -- every frame lands one index behind, and
	# the last shape is never photographed at all. The tool looks like it worked
	# and each file is mislabelled, which is worse than an outright failure.
	# Same trap SummaryShot and GateSpentShot both record (section 12).
	if _armed:
		_armed = false
		_capture()
		_shape_index += 1
		if _shape_index >= Tuning.MARKER_SHAPES.size():
			# awaited, so the quit cannot fire before the frame the scrape
			# colour is drawn on -- an un-awaited call here left the file
			# unwritten and the tool still reporting PASS.
			await _capture_scrape()
			print("RESULT: PASS")
			quit(0)
		return

	if _frame < SETTLE:
		return
	# Shoot down a corridor rather than at a junction: what is being judged is
	# the silhouette against the floor and walls, and a junction puts openings
	# on both sides that break up exactly the background the mark has to read
	# against.
	if not _in_corridor() and _frame < PATIENCE:
		return
	# Never over a card screen. The autopilot dismisses a pick the frame it
	# opens, but the screen is still DRAWN that frame -- so a shot taken here
	# without this check comes back as a picture of the upgrade row with the
	# marker behind it. AddedLinesShot records the same failure.
	if int(_game.phase) != 0:
		return
	_frame = 0

	_apply_shape()
	_armed = true


# Rebuild the live marker with the shape being shot.
#
# Straight onto Game's own marker rather than through Settings, deliberately: a
# tool must not write the state it is inspecting (section 12, TouchShot -- which
# persisted the touch preference and left a later desktop shot full of thumb
# pads). Nothing here touches the player's saved choice.
func _apply_shape() -> void:
	var shape: Dictionary = Tuning.MARKER_SHAPES[_shape_index]
	var old: PlayerMarker = _game._marker
	var world: Node = old.get_parent()
	var at: Vector3 = old.position
	var facing: Vector3 = old.rotation

	# remove_child BEFORE queue_free, so the name is free before it is reused --
	# otherwise the incoming node is silently renamed and every later lookup
	# finds the DYING original (section 12, the gate marker trap).
	world.remove_child(old)
	old.queue_free()

	var marker := PlayerMarker.new()
	# Before add_child: _ready builds the mesh on entry to the tree, so a shape
	# set afterwards would photograph the previous pick.
	marker.shape_id = String(shape["id"])
	world.add_child(marker)
	marker.name = "PlayerMarker"
	marker.position = at
	marker.rotation = facing
	_game._marker = marker


func _capture() -> void:
	var shape: Dictionary = Tuning.MARKER_SHAPES[_shape_index]
	var id: String = String(shape["id"])
	var path := "res://logs/marker_%d_%s.png" % [_shape_index + 1, id]
	var image := root.get_texture().get_image()
	if image.save_png(path) == OK:
		print("saved %s  (cell %s, speed %.2fx)" % [
			path, _game.racer.cell, _game.racer.speed])
	else:
		printerr("FAILED to save %s" % path)


# One frame of the default shape mid-scrape.
#
# The amber is the whole reason colour is not on the menu: it reads as STATE
# only because the resting marker carries no hue. A shape that lost that read
# would defeat the split -- so it gets a frame, once, rather than being assumed.
func _capture_scrape() -> void:
	if _scrape_shot:
		return
	_scrape_shot = true
	var racer: Racer = _game.racer
	if racer == null or _game._marker == null:
		return
	racer.scraping = true
	# Half-drained, so the colour is mid-lerp between amber and red rather than
	# sitting at either end -- the end points are the easy cases.
	racer.barrier = racer.upgrades.barrier_capacity() * 0.5
	_game._marker.update_state(racer, 0.0)
	# update_state changes a MATERIAL, which is not visible until the next
	# frame is drawn -- the same build-on-one-frame trap the shape swap has.
	# The first version shot in this same callback and produced a frame
	# identical to the previous white one, which reads as the state colour
	# failing to apply when it had simply not been drawn yet.
	await process_frame
	var image := root.get_texture().get_image()
	var path := "res://logs/marker_scraping.png"
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)


# A cell with walls on both sides, so the marker is seen against unbroken
# corridor rather than against gaps.
func _in_corridor() -> bool:
	var racer: Racer = _game.racer
	if racer == null or racer.maze == null:
		return false
	if racer.state != Racer.State.RUNNING:
		return false
	var open: Array = racer.maze.open_directions(racer.cell)
	var behind := int(Maze.OPPOSITE[racer.facing])
	var onward := 0
	for dir in open:
		if int(dir) != behind:
			onward += 1
	return onward == 1


func _autopilot() -> void:
	var racer: Racer = _game.racer
	# An instrument, not a player: a card screen is a stall, so take whatever is
	# offered. Covers the maze-start loadout as well as a gate pick.
	if int(_game.phase) == 1:
		var offered: Array = _game._upgrade_screen._lines
		if offered.is_empty():
			_game._on_upgrade_chosen(-1)
		else:
			_game._on_upgrade_chosen(offered[0])
		return

	if racer == null or _game.phase != 0:
		return

	if racer.state == Racer.State.PARKED:
		racer.request_reverse()
		_last_cell = Vector2i(-999, -999)
		return

	# Once per CELL, never once per frame. Steering every frame spams the buffer
	# and drives the racer into walls -- the lesson RepeatProbe and MomentumProbe
	# both record (section 12).
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
