# The heads-up display: speed, barrier, HP, timer, path indicator, compass.
#
# Everything is drawn in code rather than authored as a scene, so the whole UI
# lives in one readable file and there is no .tscn to keep in sync by hand.
#
# The barrier bar is the most important element on screen (CLAUDE.md section
# 5.1) -- it is the difference between "cutting it fine" and "about to lose
# several seconds", so it gets the most visual weight after speed.
class_name HUD
extends Control

# The HUD keeps a FIXED palette across every maze.
#
# The world recolours per maze (Tuning.PALETTES); the readouts deliberately do
# not. Speed, barrier and integrity are the numbers the player checks under
# pressure, and a bar that changed colour per maze would mean re-learning what
# "barrier is low" looks like twice a run. The barrier bar already uses colour
# to mean something -- it goes red when low -- and that signal only works if the
# resting colour is constant.
const COL_SPEED := Color(0.12, 0.85, 1.0)
const COL_BARRIER := Color(1.0, 0.75, 0.15)
const COL_BARRIER_LOW := Color(1.0, 0.25, 0.2)
const COL_HP := Color(0.35, 1.0, 0.45)
const COL_DIM := Color(0.55, 0.62, 0.75)
const COL_GOOD := Color(0.2, 1.0, 0.4)
const COL_BAD := Color(1.0, 0.25, 0.25)

# The score's own colour. Kept clear of the reserved set in CLAUDE.md section 8:
# amber-yellow is gates, amber-to-red is the wall indicator, white is the exit
# and the player marker, green/red is Path Indicator. A pale near-white gold
# reads as "value" without colliding with any of them, and like the rest of the
# HUD it is FIXED across every maze (section 7) -- a score that changed hue per
# palette would be re-learned five times a run.
const COL_SCORE := Color(0.98, 0.92, 0.62)

var _speed_label: Label
var _timer_label: Label
var _maze_label: Label
var _score_label: Label
var _budget_label: Label
var _barrier_bar: ProgressBar
var _hp_bar: ProgressBar
var _compass: Label
var _flash: ColorRect
var _message: Label

var _flash_time := 0.0
var _message_time := 0.0
var _held := false


func _ready() -> void:
	# A Control added directly to a CanvasLayer does not inherit the viewport
	# rect, so anchors resolve against a 0x0 parent and every bottom- or
	# right-anchored child lands off-screen. Filling explicitly fixes the whole
	# layout at once.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	set_anchors_preset(Control.PRESET_FULL_RECT, false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_flash()
	_build_top_bar()
	_build_stat_bars()
	_build_compass()
	_build_message()


# --- Construction ------------------------------------------------------------

func _build_flash() -> void:
	# Full-screen tint used for crash and slowdown feedback.
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func _build_top_bar() -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 0.0
	row.anchor_bottom = 0.0
	row.offset_left = 24
	# The minimap used to sit in the top-right corner and this stopped short to
	# clear it. The map now lives bottom-left, so the timer gets the full width.
	row.offset_right = -24
	row.offset_top = 16
	row.offset_bottom = 70
	row.add_theme_constant_override("separation", 32)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_speed_label = _make_label("1.00x", 42, COL_SPEED)
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_speed_label)

	_maze_label = _make_label("", 20, COL_DIM)
	_maze_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_maze_label)

	# The spacer goes BETWEEN the maze label and the timer, so speed and maze
	# info group at the left and only the timer is pushed to the right. With the
	# spacer immediately after speed, everything else piles up on the far edge
	# under the minimap.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# The score sits with the timer rather than beside speed, because the two are
	# read together: the countdown is what the score is about to be multiplied
	# by. Both are in the row's flow, so neither can collide with the other as
	# the timer's width changes past a minute (the trap section 9d records).
	_score_label = _make_label("0", 30, COL_SCORE)
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_score_label)

	_budget_label = _make_label("", 20, COL_DIM)
	_budget_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_budget_label)

	_timer_label = _make_label("0:00.0", 34, Color.WHITE)
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_timer_label)


func _build_stat_bars() -> void:
	# Anchors set explicitly rather than via set_anchors_preset(): the preset
	# rewrites offsets as a side effect, silently discarding the ones set after
	# it and leaving the whole box collapsed off-screen.
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 0.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 24
	box.offset_top = -120
	box.offset_right = 340
	box.offset_bottom = -24
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	box.add_child(_make_label("BARRIER", 13, COL_DIM))
	_barrier_bar = _make_bar(COL_BARRIER, 18)
	box.add_child(_barrier_bar)

	box.add_child(_make_label("INTEGRITY", 13, COL_DIM))
	_hp_bar = _make_bar(COL_HP, 10)
	box.add_child(_hp_bar)


# The Path Indicator no longer lives here.
#
# It used to be three chevrons pinned to the middle of the screen. Those floated
# in the air over a junction they had no fixed relationship to, so the player
# had to map a flat overlay back onto the 3D corridor rushing at them -- and it
# trained them to watch the centre of the HUD instead of the maze. The upgrade
# is now painted on the corridor walls themselves (PathIndicator.gd), where the
# answer is already in the place it applies to.
#
# The compass keeps its slot: it is a soft bearing to the next gate, not a
# per-junction answer, so it has no single wall to belong to.
func _build_compass() -> void:
	var centre := Control.new()
	centre.anchor_left = 0.5
	centre.anchor_right = 0.5
	centre.anchor_top = 0.5
	centre.anchor_bottom = 0.5
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	# Placed well below centre: at centre it lands directly on the player marker
	# in third person and the two fight for the same pixels.
	_compass = _make_label("", 16, COL_DIM)
	_compass.position = Vector2(-40, 250)
	centre.add_child(_compass)


func _build_message() -> void:
	_message = _make_label("", 30, Color.WHITE)
	_message.anchor_left = 0.5
	_message.anchor_right = 0.5
	_message.anchor_top = 0.0
	_message.anchor_bottom = 0.0
	_message.offset_top = 140
	_message.offset_bottom = 190
	_message.offset_left = -400
	_message.offset_right = 400
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.modulate.a = 0.0
	add_child(_message)


func _make_label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_bar(colour: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, height)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.13, 0.85)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)

	return bar
func update_hud(racer: Racer, upgrades: Upgrades, elapsed: float, maze_name: String, maze_index: int, score: Score = null) -> void:
	_speed_label.text = "%.2fx" % racer.speed
	# The speed readout warms toward white as it climbs, so the number itself
	# signals how exposed the player is.
	_speed_label.add_theme_color_override("font_color",
		COL_SPEED.lerp(Color.WHITE, racer.speed_fraction()))

	_timer_label.text = _format_time(elapsed)

	if score != null:
		# The projected total, not just the banked one: the number on screen
		# should always be the score the player actually has, including the maze
		# in progress at its current multiplier.
		_score_label.text = _format_score(score.projected_total())

		# The countdown drives the multiplier, so it is shown as the multiplier
		# the player is currently earning rather than as a bare clock -- "x3.40"
		# is the decision-relevant number, and the raw seconds are not.
		var mult := score.time_multiplier()
		var left := score.time_remaining()
		_budget_label.text = "x%.2f  (%s)" % [mult, _format_budget(left)]
		# Over budget the multiplier is below 1.0 and actively shrinking the
		# score, which has to read as a warning rather than as neutral trim.
		_budget_label.add_theme_color_override("font_color",
			COL_BAD if left < 0.0 else (COL_DIM if left > 30.0 else COL_BARRIER))
	# Gate count comes from the maze, not a literal: the per-maze gate count is
	# a tuning knob (Tuning.MAZES) and a hard-coded denominator here would quietly
	# lie the moment it moved.
	# maze.gates is the full placed set; the racer tracks the remaining ones on
	# its own duplicate, so this stays the total rather than the leftovers.
	var gate_total: int = racer.maze.gates.size() if racer.maze else 0
	# The maze-count denominator comes from Tuning.MAZES for the same reason the
	# gate one comes from the maze: it is a knob, and a literal "3" here quietly
	# lied to the player about how much run was left the moment two more mazes
	# were added.
	_maze_label.text = "%s   %d/%d   GATES %d/%d" % [
		maze_name, maze_index + 1, Tuning.MAZES.size(), racer.gates_taken, gate_total
	]

	var barrier_fraction := racer.barrier_fraction()
	_barrier_bar.value = barrier_fraction
	var barrier_style := _barrier_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if barrier_style:
		barrier_style.bg_color = COL_BARRIER_LOW if barrier_fraction < 0.35 else COL_BARRIER

	_hp_bar.value = float(racer.hp) / float(Tuning.MAX_HP)

	_update_compass(racer, upgrades)
func _update_compass(racer: Racer, upgrades: Upgrades) -> void:
	if not upgrades.has_compass():
		_compass.text = ""
		return

	var target := racer.maze.exit_cell
	for gate in racer.maze.gates:
		if racer.maze.solve_path.find(gate) > racer.maze.solve_path.find(racer.cell):
			target = gate
			break

	var delta := target - racer.cell
	var arrow := _bearing_arrow(delta, racer.facing)
	_compass.text = "GATE %s" % arrow


# Convert a world-space offset into an arrow relative to the way the player is
# facing, so the compass reads as "turn that way" rather than "north".
func _bearing_arrow(delta: Vector2i, facing: int) -> String:
	var world_angle := atan2(float(delta.y), float(delta.x))
	var facing_vector: Vector2i = Maze.DIR_VECTORS[facing]
	var facing_angle := atan2(float(facing_vector.y), float(facing_vector.x))
	var relative := wrapf(world_angle - facing_angle, -PI, PI)

	if absf(relative) < PI * 0.25:
		return "^"
	if relative > 0.0:
		return ">"
	if absf(relative) > PI * 0.75:
		return "v"
	return "<"


# --- Feedback ----------------------------------------------------------------

func flash(colour: Color, strength: float = 0.4) -> void:
	_flash.color = Color(colour.r, colour.g, colour.b, strength)
	_flash_time = 0.35


# `hold` keeps the message up until something clears it, rather than fading.
# The crash prompt needs this: the player stays parked until they press DOWN,
# which can be far longer than the 1.6s fade, and a prompt that vanishes while
# the state it describes is still active leaves them stopped with no
# explanation on screen.
func show_message(text: String, colour: Color = Color.WHITE, hold: bool = false) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", colour)
	_message.modulate.a = 1.0
	_held = hold
	_message_time = 1.6


func clear_held_message() -> void:
	if _held:
		_held = false
		_message_time = 0.35


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		_flash.color.a = _flash.color.a * (_flash_time / 0.35) if _flash_time > 0.0 else 0.0

	if _held:
		_message.modulate.a = 1.0
	elif _message_time > 0.0:
		_message_time = maxf(0.0, _message_time - delta)
		_message.modulate.a = minf(1.0, _message_time / 0.6)


# Thousands-separated: a maze banks six figures, and a bare run of digits is
# unreadable at the glance-speed everything else on this HUD is designed for.
func _format_score(value: float) -> String:
	var n := int(round(value))
	var sign_text := "-" if n < 0 else ""
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return sign_text + out


# The maze budget countdown. Goes NEGATIVE rather than stopping at zero, because
# a countdown that floors at 0:00 hides how far over the player is -- and how
# far over is exactly what the shrinking multiplier depends on.
func _format_budget(seconds: float) -> String:
	var over := seconds < 0.0
	var t := absf(seconds)
	var m := int(t) / 60
	var sec := int(t) % 60
	return "%s%d:%02d" % ["-" if over else "", m, sec]


func _format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var rest := fmod(seconds, 60.0)
	return "%d:%04.1f" % [minutes, rest]
