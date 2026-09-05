# The picture half of the two-column menu (docs/plans/leaderboards.md).
#
# ShellTest proves the panel switches boards, toggles sort and survives being
# offline. None of that can see whether the leaderboard overlaps the button
# stack, whether a long name pushes the score column off the panel, or whether
# the fallback single column actually looks like a menu. Layout is exactly the
# part no headless harness can check (CLAUDE.md section 12).
#
# Three shots, because the split is WIDTH-dependent and a single size would
# prove nothing about the branch it does not take:
#   wide   -- two columns, the normal desktop case
#   narrow -- below TWO_COLUMN_MIN_WINDOW_WIDTH, the panel drops and it centres
#   phone  -- the mobile case, where the fallback has to hold up at 844x390
#
# Usage:
#   launch.ps1 -Script res://scripts/core/MenuShot.gd
extends SceneTree

# Rows stuffed into the panel before shooting. Real Firebase is not reachable
# from a shot tool -- and must not be, since an instrument that needed the
# network would fail whenever Jonah is offline -- so the panel is fed directly.
#
# The names are deliberately awkward: the longest one is at the 24-character
# limit the rules enforce, which is the case that would push the score column
# off the panel if the column widths were wrong.
const FAKE_ROWS := [
	{"name": "Fav", "score": 627483.0, "time": 271.0},
	{"name": "TheSmallNut", "score": 452947.0, "time": 288.0},
	{"name": "ABCDEFGHIJKLMNOPQRSTUVWX", "score": 318002.0, "time": 305.0},
	{"name": "jonah", "score": 204118.0, "time": 331.0},
	{"name": "anon", "score": 96550.0, "time": 402.0},
	{"name": "racer_09", "score": 41200.0, "time": 455.0},
]

const SIZES := [
	[Vector2i(1600, 900), "menu_01_wide"],
	[Vector2i(1000, 760), "menu_02_narrow"],
	[Vector2i(844, 390), "menu_03_phone"],
]

var _shell: Node
var _frame := 0
var _index := 0
var _stage := 0


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_shell = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_shell)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	if _frame < 20:
		return

	if _index >= SIZES.size():
		print("RESULT: PASS")
		quit(0)
		return

	match _stage:
		0:
			_resize(SIZES[_index][0])
			_stage = 1
		1:
			# A frame between the resize and the fill so the layout has
			# re-decided its columns before anything is drawn into them.
			_fill_panel()
			_stage = 2
		2:
			# And another before capturing: process_frame fires BEFORE the UI is
			# drawn, so capturing in the frame that built it grabs the previous
			# screen. Same trap SummaryShot hit -- build on one frame, shoot on
			# the next.
			_capture(String(SIZES[_index][1]))
			_index += 1
			_stage = 0


func _resize(size: Vector2i) -> void:
	var window := root.get_window()
	if window != null:
		window.size = size
	var menu = _shell._current
	if menu != null and menu.has_method("_layout_columns"):
		menu._layout_columns()


# Feed the panel rows directly rather than through Firebase.
func _fill_panel() -> void:
	var menu = _shell._current
	if menu == null or menu._leaderboard == null:
		return
	var panel = menu._leaderboard
	panel._status.text = ""
	panel._draw_rows(FAKE_ROWS)


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/shot_%s.png" % label
	if image.save_png(path) == OK:
		print("saved %s" % path)
	else:
		printerr("FAILED to save %s" % path)
