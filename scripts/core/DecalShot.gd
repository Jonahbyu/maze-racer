# Does each decal actually read as a PATTERN in play?
#
# Every decal, on one shape, from the ordinary trailing camera. That angle is
# the whole question: it foreshortens the length axis hard, which has already
# eaten a shallow taper once (section 12, the lightcycle nose) and turned two
# decals into scratches -- so a cut that measures fine in outline space can
# still show nothing on screen.
#
# Not a test. DecalProbe reports the AREA each decal removes and RulesTest now
# asserts it, but neither can judge whether a 7% bite reads as shoulders or as
# a chipped edge. That is what this photographs.
#
# Shot on LIGHTCYCLE deliberately: it is the shape the fault was reported on,
# and its long parallel flanks are the least forgiving body in the table -- a
# band that reads here reads anywhere.
extends SceneTree

# The mark and its inlay, held FIXED across every frame so the only thing that
# varies is the decal. Cobalt is the known-legible control from InlayPairShot,
# so a frame where the pattern is invisible is the decal's fault rather than
# the colour pair's.
const MARK := Color(1.0, 1.0, 0.999)
const INLAY := Color(0.25, 0.55, 1.0)

const SHAPE := "cycle"

# Long enough for the maze to build and the camera to settle behind the racer,
# so the frame looks like play rather than like a spawn.
const SETTLE := 110

var _decals: Array = []
var _game: Node
var _frame := 0
var _index := 0
var _armed := false


func _init() -> void:
	# Read from the table rather than listed, so a decal added later is
	# photographed by construction -- the parallel-array trap this whole
	# feature is built to avoid (section 6).
	for entry in Tuning.MARKER_DECALS:
		_decals.append(String(entry["id"]))
	_setup.call_deferred()


func _setup() -> void:
	_game = load("res://scenes/Game.tscn").instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_take_any_card()

	# BUILD ON ONE FRAME, CAPTURE ON THE NEXT. process_frame fires before the
	# frame is drawn, so rebuilding and shooting in one callback photographs
	# the PREVIOUS decal -- every frame lands one behind and the last is never
	# shot at all (section 12, the trap MarkerShot and SummaryShot record).
	if _armed:
		_armed = false
		_capture()
		_index += 1
		if _index >= _decals.size():
			print("RESULT: PASS")
			quit(0)
			return
		_apply()
		return

	if _frame == SETTLE:
		_apply()


# A run boots into UPGRADING, so steering is inert until a card is taken.
func _take_any_card() -> void:
	if _game.has_method("_on_card_chosen") and _game.get("phase") == 1:
		_game._on_card_chosen(0)


# Rebuild the live marker wearing this decal.
#
# Straight onto Game's own marker rather than through Settings: a tool must not
# write the state it is inspecting (section 12, TouchShot).
func _apply() -> void:
	var id: String = _decals[_index]
	var old = _game._marker
	var world: Node = old.get_parent()
	var at: Vector3 = old.position
	var facing: Vector3 = old.rotation

	# remove_child BEFORE queue_free, so the name is free before it is reused
	# -- otherwise the incoming node is silently renamed and every later lookup
	# finds the DYING original (section 12, the gate marker trap).
	world.remove_child(old)
	old.queue_free()

	var marker := PlayerMarker.new()
	# Set BEFORE add_child: _ready builds the mesh on entry to the tree, so
	# anything assigned afterwards photographs the previous decal.
	#
	# _resolve_colour's escape hatch is keyed on player_colour DIFFERING from
	# COL_ARROW, so a mark of pure white reads as "nothing was set" and
	# Settings overwrites both colours from the saved profile. MARK is nudged
	# imperceptibly off it to hold the hatch open.
	marker.shape_id = SHAPE
	marker.decal_id = id
	marker.player_colour = MARK
	marker.player_colour_2 = INLAY
	world.add_child(marker)
	marker.name = "PlayerMarker"
	marker.position = at
	marker.rotation = facing
	_game._marker = marker
	_armed = true


func _capture() -> void:
	var id: String = _decals[_index]
	var path := "res://logs/decal_%s.png" % id
	var image := root.get_texture().get_image()
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
