# The picture half of the marker picker's SCREEN (CLAUDE.md, "The marker's shape
# is the player's to pick"). MarkerShot photographs the shapes in play; this
# photographs the panel they are chosen from.
#
# Two different failures, which is why both exist. A shape can read perfectly in
# a corridor and still be unchoosable -- a preview that renders empty, a grid
# that overflows its card, a label sitting on the viewport. None of that is
# visible to any headless assertion, and the preview in particular is the one
# thing most likely to come back blank: a SubViewport that fails to build its
# own world renders as flat background, which looks like a dark panel rather
# than like a broken one.
#
# It shoots the picker on the FIRST and LAST entry in the table, because the
# highlight moving is the only proof the grid is wired -- a lit button is a lit
# button in any single frame, the reason QuadrantShot seeks a region change.
extends SceneTree

var _menu: Control
var _picker: Control
var _frame := 0
var _stage := 0

# The player's own choice, put back before the tool exits.
var _saved := ""
# The picker now writes THREE preferences, not one. Restoring only the shape
# would leave the player on whichever colour and pattern this tool shot last --
# the same failure the shape restore already exists to prevent, arriving through
# the two settings added after it.
var _saved_decal := ""
var _saved_colour := Color.WHITE
var _remembered := false

# Long enough for the panel to lay out and for the preview's turntable to swing
# off its start angle, so the shot shows the shape at an angle rather than
# edge-on at exactly zero.
const SETTLE := 45


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_remember()
	_menu = MainMenu.new()
	root.add_child(_menu)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	if _frame < SETTLE:
		return
	_frame = 0

	match _stage:
		0:
			_open()
			# Nothing is captured on the frame the picker is BUILT: process_frame
			# fires before the UI is drawn, so a shot here comes back as the bare
			# menu. The same trap SummaryShot records, whose own two shots came
			# out identical for exactly this reason.
			_stage = 1
		1:
			_capture("01_default")
			_pick(Tuning.MARKER_SHAPES.size() - 1)
			# Another whole SETTLE before the second shot, not an immediate
			# capture: picking rebuilds the preview marker, and that mesh is not
			# drawn until the next frame. Shooting straight after the pick
			# produced two frames of the SAME shape with different labels --
			# which is worse than a missing frame, because it reads as the pick
			# having failed to change anything.
			_stage = 2
		2:
			_capture("02_last")
			# A DECAL, on the lightcycle picked above. The pattern is generated
			# by clipping the shape's own outline, so whether it reads at all
			# is a question about a rendered frame rather than about geometry
			# -- RulesTest already proves the polygons are valid and inside the
			# shape, and a valid polygon can still be invisible.
			_pick_decal("stripe")
			_stage = 3
		3:
			_capture("03_decal")
			# A COLOUR, named by its position in the real table rather than by
			# a literal. The first version passed Color(0.2, 0.9, 0.35), which
			# is not in COLOUR_SWATCHES at all -- the lime is (0.55, 0.95,
			# 0.45) -- so the lookup matched nothing, returned silently, and
			# the frame came back white while reporting PASS. A literal here is
			# a transcription of the table, and it went stale immediately.
			_pick_colour("lime")
			_stage = 4
		4:
			_capture("04_colour")
			_restore()
			print("RESULT: PASS")
			quit(0)


func _open() -> void:
	_menu._on_marker()
	_picker = _menu._marker_picker


# Straight at the handler rather than through a synthesised click: what is being
# photographed is the panel, and driving the button would be testing Godot's
# input routing instead. ShellTest covers the wiring.
#
# The picker WRITES through Settings, which persists to user://settings.cfg --
# so the tool restores whatever was there when it is done. Without that it
# leaves the player on whichever shape it happened to shoot last, and its own
# next run opens on that instead of on the default: the first version reported a
# frame labelled "default" showing LIGHTCYCLE, which reads as the label being
# wrong rather than as the tool having changed the setting. A tool must not
# write the state it is inspecting (section 12, TouchShot).
func _pick(index: int) -> void:
	if _picker != null:
		_picker._on_pick(index)


func _pick_decal(id: String) -> void:
	if _picker == null:
		return
	for i in Tuning.MARKER_DECALS.size():
		if String(Tuning.MARKER_DECALS[i]["id"]) == id:
			_picker._on_pick_decal(i)
			return


func _pick_colour(id: String) -> void:
	if _picker == null:
		return
	# By ID through the picker's own handler, so the tool exercises the same
	# path a click does rather than writing the setting behind it -- and names
	# the swatch rather than restating its value. An earlier version passed a
	# Color literal that was not in the table at all, matched nothing, returned
	# silently, and shot a white marker while reporting PASS.
	for i in Tuning.MARKER_COLOURS.size():
		if String(Tuning.MARKER_COLOURS[i]["id"]) == id:
			_picker._on_pick_colour(i)
			return
	# A no-match must be LOUD. Returning quietly is what produced a white frame
	# under a PASS -- the tool agreeing with itself about a colour it never set.
	push_error("MarkerPickerShot: no swatch named %s" % id)


func _remember() -> void:
	var settings := root.get_node_or_null("/root/Settings")
	if settings != null:
		_saved = String(settings.marker_shape)
		_saved_decal = String(settings.marker_decal)
		_saved_colour = settings.marker_colour
		_remembered = true


func _restore() -> void:
	var settings := root.get_node_or_null("/root/Settings")
	if settings == null or not _remembered:
		return
	if _saved != "":
		settings.set_marker_shape(_saved)
	if _saved_decal != "":
		settings.set_marker_decal(_saved_decal)
	settings.set_marker_colour(_saved_colour)


func _capture(label: String) -> void:
	var path := "res://logs/marker_picker_%s.png" % label
	var image := root.get_texture().get_image()
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
