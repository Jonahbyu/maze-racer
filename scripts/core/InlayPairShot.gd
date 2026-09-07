# Does a WHITE inlay read against a WHITE mark?
#
# Colour 2's default moved to white so a fresh profile starts with ONE colour
# unlocked rather than two. That reverses the reasoning recorded in section 12
# -- "the two defaults must differ, or a white pattern on a white mark reads as
# a broken decal" -- so the claim that has to survive it is the OTHER one that
# section makes: the seam guarantees the read AT ANY PAIR, because the inlay is
# a recessed, dimmer surface rather than a flat fill.
#
# An identical pair is the hardest case of that rule, which makes it the one
# worth photographing. Shot against COBALT as a control -- the pair that shipped
# before -- so the question asked is "is white legible" rather than "is white as
# loud as cobalt".
#
# Not a test. Whether a seam reads at the trailing camera's shallow angle is
# exactly what no headless assertion can judge, which is why MarkerShot exists
# at all; this is the same instrument aimed at the second colour.
extends SceneTree

# The pairs to shoot, as (name, colour 2). White FIRST, since it is the subject.
# A var rather than a const: the seeded entry is COMPUTED from the same
# constant Settings uses, and darkened() is not available at compile time.
# Deriving it here rather than typing the resulting colour is what stops this
# tool drifting from the code it photographs (section 12's transcription trap).
var _pairs := [
	# The SEEDED shade -- what Settings gives colour 2 the first time a decal
	# goes on while both colours still match. This is the subject.
	["seeded", Color(1.0, 1.0, 0.999).darkened(
		Tuning.MARKER_COLOUR_2_DARKEN)],
	# The pair that shipped before, as a control: it is known to read, so a
	# frame where the subject looks like this one is a pass.
	["cobalt", Color(0.25, 0.55, 1.0)],
	# And plain white, the FAILING case, kept so the comparison stays honest --
	# this is the frame that showed no pattern at all.
	["white", Color(1.0, 1.0, 1.0)],
]

# The decal to wear. STRIPE severs the mark into pieces, so it is the decal
# with the most seam to read -- if any pair works, it works here.
const DECAL := "stripe"

# Long enough for the maze to build and the camera to settle behind the racer,
# so the frame looks like play rather than like a spawn.
const SETTLE := 110

var _game: Node
var _frame := 0
var _index := 0
var _armed := false


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_game = load("res://scenes/Game.tscn").instantiate()
	root.add_child(_game)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	_take_any_card()

	# BUILD ON ONE FRAME, CAPTURE ON THE NEXT. process_frame fires before the
	# frame is drawn, so rebuilding and shooting in one callback photographs the
	# PREVIOUS pair -- every frame lands one behind and the last is never shot
	# at all (section 12, the trap MarkerShot and SummaryShot both record).
	if _armed:
		_armed = false
		_capture()
		_index += 1
		if _index >= _pairs.size():
			print("RESULT: PASS")
			quit(0)
			return
		_apply()
		return

	if _frame == SETTLE:
		_apply()


# A run now boots into UPGRADING, so steering is inert until a card is taken.
func _take_any_card() -> void:
	if _game.has_method("_on_card_chosen") and _game.get("phase") == 1:
		_game._on_card_chosen(0)


# Rebuild the live marker wearing this pair.
#
# Straight onto Game's own marker rather than through Settings: a tool must not
# write the state it is inspecting (section 12, TouchShot).
func _apply() -> void:
	var pair: Array = _pairs[_index]
	var old = _game._marker
	var world: Node = old.get_parent()
	var at: Vector3 = old.position
	var facing: Vector3 = old.rotation

	# remove_child BEFORE queue_free, so the name is free before it is reused --
	# otherwise the incoming node is silently renamed and every later lookup
	# finds the DYING original (section 12, the gate marker trap).
	world.remove_child(old)
	old.queue_free()

	var marker := PlayerMarker.new()
	# Set BEFORE add_child: _ready builds the mesh on entry to the tree, so
	# anything assigned afterwards photographs the previous pair.
	#
	# _resolve_colour's escape hatch is keyed on player_colour DIFFERING from
	# COL_ARROW, so setting the mark to white -- which IS COL_ARROW -- reads as
	# "nothing was set" and Settings overwrites BOTH colours with the saved
	# profile's. The first version of this tool did exactly that and shot the
	# saved profile twice: two byte-identical frames reported as a white/cobalt
	# comparison. An instrument that agrees with itself is measuring nothing.
	#
	# So the mark is nudged imperceptibly off COL_ARROW to hold the hatch open,
	# and colour 2 is what actually varies.
	marker.decal_id = DECAL
	marker.player_colour = Color(1.0, 1.0, 0.999)
	marker.player_colour_2 = pair[1]
	world.add_child(marker)
	marker.name = "PlayerMarker"
	marker.position = at
	marker.rotation = facing
	_game._marker = marker
	_armed = true


func _capture() -> void:
	var pair: Array = _pairs[_index]
	var path := "res://logs/inlay_%s.png" % String(pair[0])
	var image := root.get_texture().get_image()
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
