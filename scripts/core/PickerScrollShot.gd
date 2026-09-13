extends SceneTree

# Does the marker picker OPEN on the shape the player already holds?
#
# MarkerPickerShot cannot answer this. It opens the picker and then calls _pick()
# to move the highlight, so by the time the last entry is selected the screen has
# been open for many frames and the on-open scroll has long since fired -- its
# frame shows the top of the list whether the scroll works or not, which is
# exactly the "a lit button is a lit button" problem that tool's own comment
# records about a single frame.
#
# The question here is different and only has one frame in it: with a
# late-in-the-table shape ALREADY SAVED, does the screen come up showing it? That
# went from a minor annoyance at eight shapes to a real defect at forty-four,
# where the selected button can be fifteen rows below the fold and the screen
# opens looking like it forgot the choice.
#
# It writes the saved preference, so it RESTORES it on the way out -- the rule
# TouchShot, MarkerPickerShot and ShopShot all record: a tool must not leave the
# state it is inspecting changed.

const MarkerPickerScene = preload("res://scripts/ui/MarkerPicker.gd")

var _stage := 0
var _frame := 0
var _picker: Control = null
var _saved := ""

# Long enough for the card to build, the deferred scroll to run, and the result
# to be drawn. Nothing is captured on the frame the picker is built:
# process_frame fires before the UI is drawn.
const SETTLE := 40



func _initialize() -> void:
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	match _stage:
		0:
			if _frame < 4:
				return
			_open()
			_frame = 0
			_stage = 1
		1:
			if _frame < SETTLE:
				return
			_report()
			_restore()
			quit(0)


func _open() -> void:
	var settings := root.get_node_or_null("/root/Settings")
	# The LAST shape in the table, which is the worst case and the one the
	# defect is about. Read off the table rather than named, so this keeps
	# testing the bottom of the list as the list grows.
	var last := String(Tuning.MARKER_SHAPES[Tuning.MARKER_SHAPES.size() - 1]["id"])
	# Settings has no suppress_save (that is Unlocks); it persists on every
	# write. So the saved value is captured here and written BACK in _restore,
	# which is what keeps the player's own choice intact.
	if settings != null:
		_saved = String(settings.marker_shape)
		settings.set_marker_shape(last)
	_picker = MarkerPickerScene.new()
	root.add_child(_picker)
	print("opened with shape: %s (entry %d of %d)"
		% [last, Tuning.MARKER_SHAPES.size(), Tuning.MARKER_SHAPES.size()])


func _report() -> void:
	var scroll: ScrollContainer = _picker.get("_scroll")
	var buttons: Array = _picker.get("_buttons")
	var index: int = int(_picker.get("_index"))
	if scroll == null or buttons.is_empty():
		printerr("PickerScrollShot: no scroll or no buttons")
		quit(1)
		return

	var button: Button = buttons[index]
	var top: float = button.global_position.y - scroll.global_position.y
	var bottom: float = top + button.size.y
	var height: float = scroll.size.y
	var visible: bool = top >= -1.0 and bottom <= height + 1.0

	print("selected index %d (%s)" % [index, Tuning.MARKER_SHAPES[index]["id"]])
	print("button y %.1f..%.1f within viewport 0..%.1f" % [top, bottom, height])
	print("scroll_vertical %d of %d"
		% [scroll.scroll_vertical, int(scroll.get_v_scroll_bar().max_value)])
	print("RESULT: %s" % ("PASS" if visible else "FAIL -- opens off-screen"))
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png("res://logs/picker_scroll.png")
		print("saved res://logs/picker_scroll.png")


func _restore() -> void:
	var settings := root.get_node_or_null("/root/Settings")
	if settings != null and _saved != "":
		settings.set_marker_shape(_saved)
