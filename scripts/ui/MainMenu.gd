# The title screen: the logo, PLAY, WATCH TRAILER, QUIT, and a settings cog,
# over a painted corridor.
#
# Still no 3D behind it, and the reason is unchanged: the trailer is the moving
# shop window (docs/specs/trailer.md), and a menu that also rendered a live maze
# would be paying the cost of both and diluting the one that is actually built
# to sell the game. A still image is not a live maze -- it costs one texture and
# no simulation, so it buys the first impression without taking that trade.
#
# The art earns its place by being the game: a one-point-perspective neon
# corridor, cyan on the left and magenta on the right, which is what the player
# is about to drive down. A generic backdrop would not have been worth the
# legibility cost the scrim now pays for.
#
# Colours are taken from the maze-1 palette in Tuning rather than restated, so
# the title screen cannot drift away from the game's own cyan.
class_name MainMenu
extends Control

# Carries the board the run counts toward (Tuning.Board). Shell hands it
# straight to Game.board, which is what derives the seed -- so DAILY and MONTHLY
# are not a separate mode, they are the ordinary game with a date-derived seed.
signal play_pressed(board: int)
signal trailer_pressed()

const COL_ACCENT := Color(0.12, 0.85, 1.0)
const COL_DIM := Color(0.55, 0.62, 0.75)
# Near-opaque when the menu was a flat fill; against the corridor art that read
# as three heavy slabs pasted over a photograph. Let down so the art carries
# through the button faces -- they still hold white 24pt text because the whole
# image is dimmed by COL_SCRIM first, and the lit states stay clearly brighter
# than the resting ones, which is what actually communicates focus.
const COL_CARD := Color(0.07, 0.10, 0.16, 0.72)
const COL_CARD_HOVER := Color(0.12, 0.22, 0.36, 0.86)

# How hard the art is dimmed before any UI is drawn over it. Tuned against the
# brightest thing in the image -- the yellow pillars at the vanishing point,
# which sit squarely behind the button stack. Bright enough to leave the neon
# lines and the skyline reading as art; dark enough that white 24pt button text
# holds against the pillars rather than only against the walls beside them.
const COL_SCRIM := Color(0.02, 0.02, 0.05, 0.55)

# --- Art ---------------------------------------------------------------------
#
# Paths rather than preload()s. preload resolves at PARSE time, so a missing
# file is a hard parse error that takes the whole class down -- and this class
# is instantiated by ShellTest and MenuShot, so a missing texture would fail
# harnesses that have nothing to do with the art. Loaded at run time and guarded
# instead, exactly as Settings and Music are (sections 9c, 9d).
const ART_BACKGROUND := "res://art/menu_background.png"
const ART_LOGO := "res://art/logo.png"

# The logo's drawn size and its top edge relative to screen centre. The box is a
# BOUND, not a claim about the image's dimensions -- KEEP_ASPECT_CENTERED fits
# the art inside it, so the two only need to be close enough that the fit does
# not leave the logo small. art/logo.png is 2072x606 (3.42:1) and this box is
# 3.42:1, so it fills it almost exactly. The asset is padded so the SOLID
# wordmark sits at the centre of its own image, not merely the glow -- the menu
# centres the box, so an off-centre wordmark inside a centred box lands on
# screen as a title that does not share a centre line with the button stack.
const LOGO_SIZE := Vector2(720, 211)
const LOGO_TOP := -286.0

# Full-rect nodes that must NOT be moved into the left column when the menu
# splits in two. _place_left used to identify them as "is ColorRect", which was
# a type standing in for an intent, and it broke the moment the backdrop stopped
# being a plain fill: a TextureRect is not a ColorRect, so the background art
# was dragged into the left column and cropped to it. A group states the
# property directly -- this node spans the screen -- so anything added later
# says so for itself rather than needing the filter widened again.
const GROUP_BACKDROP := "menu_backdrop"

const BUTTON_SIZE := Vector2(360, 62)
const SEPARATION := 18.0

# Angular offsets of the four points that make one gear tooth, as a fraction
# of one tooth's arc: rise, flat top, fall, flat gap. Named rather than inlined
# because the four numbers are meaningless out of order.
const _COG_STEP: Array[float] = [0.06, 0.20, 0.30, 0.44]

const COG_SIZE := 52.0
const COG_MARGIN := 24.0

# Where the button stack starts, relative to screen centre.
#
# The stack hangs BELOW the logo and grows downward -- it is deliberately not
# centred on its own height. Centring was tried and the two constraints fight:
# any centre that keeps the hint clear of the bottom edge at five buttons puts
# the stack's top above the logo's baseline (-75), so the title and the first
# button overlap. Hanging from a fixed top is what keeps both ends honest.
#
# The number that actually needed deriving is the stack's HEIGHT, which reads
# the button count (see _build_buttons) -- that is the section 12 trap, and it
# was already avoided. This offset is a gap below the logo, which does not
# change with the count.
const ROW_TOP := -40.0

# --- Two columns (docs/plans/leaderboards.md) --------------------------------
#
# Left: title and buttons. Right: the leaderboard. The background art sits behind
# both. Each column still paints its own scrim on top of the one over the art,
# for the reason it always did -- neither column may be at the mercy of what the
# image happens to be bright behind. The art exists now, and that is an argument
# for keeping the belt and braces rather than against it: the brightest part of
# the image is the vanishing point, dead centre, between the two columns.
const LEFT_MARGIN := 90.0
const PANEL_MARGIN := 28.0

# Below this WINDOW width the two columns are dropped and the menu falls back to
# the single centred column it has always been -- when there is not room for
# both, the one the player came for wins. Same reasoning as the minimap sliding
# clear of the barrier bars rather than overlapping them (section 12).
#
# Measured against the window, NOT the viewport: stretch/mode="canvas_items"
# pins the viewport at 1600x900 whatever the window does, so a viewport test can
# never fail. See _layout_columns.
#
# Aspect ratio was tried first and is simply the wrong signal -- a handset in
# landscape (844x390 = 2.16) is WIDER than a desktop 16:9 (1.78), so no
# threshold on aspect separates them at all. Physical width does: 844 against
# 1600.
const TWO_COLUMN_MIN_WINDOW_WIDTH := 1100.0

var _leaderboard: LeaderboardPanel = null

# The one-time name prompt, built on the first PLAY when no name is stored.
var _name_modal: Control = null

var _buttons: Array[Button] = []
var _hint: Label = null
var _cog: Button = null
var _panel: SettingsPanel = null


func _ready() -> void:
	# Anchors and offsets together. set_anchors_preset() leaves the offsets at
	# zero and yields a degenerate rect, which is what hung UpgradeScreen's cards
	# off the top-left corner (CLAUDE.md section 12).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_background()
	_build_title()
	_build_buttons()
	_build_leaderboard()
	_build_cog()
	_layout_columns()
	# The viewport can resize under a running menu -- a browser window drag is
	# the common case -- and the two-column split is width-dependent, so it has
	# to be re-decided rather than fixed at build time.
	get_viewport().size_changed.connect(_layout_columns)


func _build_background() -> void:
	# The flat fill stays, underneath the art, and is not redundant. The art is
	# 16:9 and the window is not always -- KEEP_ASPECT_COVERED crops rather than
	# letterboxes, but a texture that fails to load leaves nothing at all, and a
	# menu drawn over an undefined buffer is the failure this guards. It is also
	# what every harness that runs without the art file present sees.
	var back := ColorRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.01, 0.015, 0.03)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_to_group(GROUP_BACKDROP)
	add_child(back)

	var art := _load_art(ART_BACKGROUND)
	if art == null:
		return

	var rect := TextureRect.new()
	rect.name = "BackgroundArt"
	rect.texture = art
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# COVERED, never SCALED: the art is a corridor in one-point perspective, so
	# stretching it off-ratio skews the vanishing point and the whole image reads
	# as a mistake. Cropping the edges of a symmetrical corridor costs nothing.
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.add_to_group(GROUP_BACKDROP)
	add_child(rect)

	# A scrim over the art, not over each column.
	#
	# The two columns used to paint their own scrims precisely because the art
	# "is not written yet and must not be able to make either column
	# unreadable". It is written now, and it is bright in the middle -- the
	# yellow pillars at the vanishing point sit directly behind the button
	# stack. One dimming pass over the whole image is what keeps white button
	# text legible without boxing the art off into panels.
	var scrim := ColorRect.new()
	scrim.name = "BackgroundScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = COL_SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.add_to_group(GROUP_BACKDROP)
	add_child(scrim)


func _build_title() -> void:
	var logo := _load_art(ART_LOGO)
	if logo == null:
		# The text title is the fallback, not dead code: it is what a harness
		# without the art sees, and what ships if the file is ever missing. A
		# menu with no title at all reads as a broken build.
		var title := _centred_label("MAZE RACER", 78, COL_ACCENT, -250, -150)
		title.add_theme_constant_override("outline_size", 8)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		add_child(title)
		return

	var rect := TextureRect.new()
	rect.name = "TitleLogo"
	rect.texture = logo
	# The logo already carries its own glow and its own transparency, so it
	# needs no outline and no scrim -- adding either would put a box around
	# artwork drawn to sit on darkness.
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 0.5
	rect.anchor_bottom = 0.5
	# Spans the same width the text title did, so _place_left moves it by the
	# same anchor arithmetic and the two-column split needs to know nothing
	# about which of the two is on screen.
	rect.offset_left = -LOGO_SIZE.x * 0.5
	rect.offset_right = LOGO_SIZE.x * 0.5
	rect.offset_top = LOGO_TOP
	rect.offset_bottom = LOGO_TOP + LOGO_SIZE.y
	add_child(rect)


# Load a texture that may legitimately not be there.
#
# ResourceLoader.exists() first, because load() on a missing path pushes an
# error into logs/errors.log -- and that log is the primary feedback channel
# here (CLAUDE.md, "Jonah never launches Godot"). An expected absence must not
# put a red line in it, or the log stops being worth reading.
func _load_art(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _build_buttons() -> void:
	var row := VBoxContainer.new()
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 0.5
	row.anchor_bottom = 0.5
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", SEPARATION)
	row.offset_left = -BUTTON_SIZE.x * 0.5
	row.offset_right = BUTTON_SIZE.x * 0.5
	add_child(row)

	# One button per board rather than a selector beside PLAY: a toggle would
	# make starting a daily run two presses and would need the lit board to be
	# legible at a glance, where a labelled button says which maze it starts by
	# being pressed. The stack height is derived from the count below, so
	# growing it from three to five costs nothing but the space it takes.
	row.add_child(_make_button("PLAY", _on_play.bind(Tuning.Board.GENERAL)))
	row.add_child(_make_button("PLAY DAILY", _on_play.bind(Tuning.Board.DAILY)))
	row.add_child(_make_button("PLAY MONTHLY",
		_on_play.bind(Tuning.Board.MONTHLY)))
	row.add_child(_make_button("WATCH TRAILER", _on_trailer))
	# MOBILE CONTROLS used to sit here. It moved into the settings panel so
	# that preferences live in exactly one place -- a toggle in the button
	# stack and a panel behind a cog would be two homes for the same category.
	row.add_child(_make_button("QUIT", _on_quit))

	# Derived from what the row actually holds, never a fixed band. The previous
	# literal 180 fitted three buttons by luck and already clipped the third
	# slightly; a fourth overflowed it outright. Same trap as the upgrade card
	# row (CLAUDE.md section 12) -- read the count, do not restate the total.
	var count: int = _buttons.size()
	var gaps: float = float(max(count - 1, 0))
	var stack: float = BUTTON_SIZE.y * float(count) + SEPARATION * gaps
	row.offset_top = ROW_TOP
	row.offset_bottom = ROW_TOP + stack

	if not _buttons.is_empty():
		_buttons[0].grab_focus()

	# Below the row wherever the row now ends, for the same reason.
	_hint = _centred_label(_hint_text(), 16, COL_DIM,
		row.offset_bottom + 30.0, row.offset_bottom + 60.0)
	add_child(_hint)


func _build_leaderboard() -> void:
	_leaderboard = LeaderboardPanel.new()
	_leaderboard.name = "LeaderboardPanel"
	add_child(_leaderboard)


# Decide between one centred column and two, and place them.
#
# Everything here is anchored rather than positioned: a fixed pixel band is the
# section 12 trap, and this layout has to survive a browser window at any size.
func _layout_columns() -> void:
	if _leaderboard == null:
		return

	# The WINDOW's width, not the viewport's.
	#
	# project.godot sets stretch/mode="canvas_items", so the viewport stays at
	# the project's 1600x900 whatever the window does -- the canvas is scaled to
	# fit instead. get_viewport_rect().size.x is therefore ALWAYS 1600, and a
	# test against it can never fail: the phone shot came back showing a
	# scaled-down desktop layout rather than the fallback, which reads exactly
	# like the fallback being broken when it was in fact never reachable.
	var window := get_window()
	var win_width := float(window.size.x) if window != null \
		else float(get_viewport_rect().size.x)
	# The layout itself is still measured in VIEWPORT units, because that is the
	# space the Controls live in -- only the decision reads the window.
	var width := float(get_viewport_rect().size.x)
	var two := win_width >= TWO_COLUMN_MIN_WINDOW_WIDTH
	_leaderboard.visible = two

	if not two:
		# Single column: everything returns to centre, which is exactly the
		# layout this menu had before the panel existed -- cog included.
		_place_left(0.5)
		_place_cog(0.0)
		return

	var panel_w := LeaderboardPanel.PANEL_WIDTH
	_leaderboard.anchor_left = 1.0
	_leaderboard.anchor_right = 1.0
	_leaderboard.anchor_top = 0.0
	_leaderboard.anchor_bottom = 1.0
	_leaderboard.offset_left = -panel_w - PANEL_MARGIN
	_leaderboard.offset_right = -PANEL_MARGIN

	# The cog moves clear of the panel, which now owns the top-right corner it
	# used to sit in -- it was drawn UNDER the board's fourth tab, which only a
	# rendered frame shows. It follows the left column instead, where the rest
	# of the menu's own controls live.
	_place_cog(-panel_w - PANEL_MARGIN * 2.0)
	# Full height, not inset top and bottom. A scrim that stops short of both
	# edges reads as a floating card that failed to size itself, and the rows
	# have nowhere to grow into as a board fills up.
	_leaderboard.offset_top = 0.0
	_leaderboard.offset_bottom = 0.0

	# The left column centres itself in the space the panel does NOT occupy,
	# rather than in the screen -- centring on the screen would push it under the
	# board.
	var free_w := width - panel_w - PANEL_MARGIN * 2.0
	_place_left(clampf((free_w * 0.5) / maxf(width, 1.0), 0.15, 0.5))


# Shift the cog left of the panel. `shift` is 0 for the ordinary corner.
func _place_cog(shift: float) -> void:
	if _cog == null:
		return
	_cog.offset_left = -COG_SIZE - COG_MARGIN + shift
	_cog.offset_right = -COG_MARGIN + shift


# Move the title, buttons and hint to a horizontal anchor.
func _place_left(anchor_x: float) -> void:
	for node in get_children():
		if node == _leaderboard or node == _cog:
			continue
		var c := node as Control
		if c == null or c.is_in_group(GROUP_BACKDROP):
			continue
		c.anchor_left = anchor_x
		c.anchor_right = anchor_x


# Top-right, clear of the title and the button stack. A corner rather than a
# row entry because settings is not a peer of PLAY -- it is the door beside the
# room, and putting it in the stack is what crowded the stack in the first place.
func _build_cog() -> void:
	var cog := Button.new()
	# NO TEXT. This was "⚙" (U+2699 GEAR) and it rendered as a tofu box in
	# the web build -- the exact failure section 9d records for the touch pads,
	# arriving by the same route: a character is only as reliable as the font
	# behind it, and the web export falls back to whatever the device ships.
	# A missing glyph renders as a box, so the door to every setting looked
	# broken on the one platform that cannot be checked from here.
	#
	# Drawn from polygons instead, which owe nothing to a font and scale with
	# the button. Same fix the steering arrows and the pause bars already got.
	cog.tooltip_text = "Settings"
	cog.custom_minimum_size = Vector2(COG_SIZE, COG_SIZE)
	cog.focus_mode = Control.FOCUS_ALL

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var lit: bool = state in ["hover", "focus", "pressed"]
		style.bg_color = COL_CARD_HOVER if lit else COL_CARD
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = COL_ACCENT if lit else Color(0.2, 0.3, 0.45)
		cog.add_theme_stylebox_override(state, style)

	# Anchored to the top-right corner, so it stays put at any window size.
	cog.anchor_left = 1.0
	cog.anchor_right = 1.0
	cog.anchor_top = 0.0
	cog.anchor_bottom = 0.0
	cog.offset_left = -COG_SIZE - COG_MARGIN
	cog.offset_right = -COG_MARGIN
	cog.offset_top = COG_MARGIN
	cog.offset_bottom = COG_MARGIN + COG_SIZE

	cog.pressed.connect(_on_settings)
	_cog = cog
	add_child(cog)

	# Added after add_child so the icon inherits the button's final rect.
	_build_cog_icon(cog)

	# The glyph used to take its colour from font_color overrides, which a
	# polygon does not read. Hover and focus are re-tinted by hand instead.
	cog.mouse_entered.connect(_tint_cog.bind(true))
	cog.mouse_exited.connect(_tint_cog.bind(false))
	cog.focus_entered.connect(_tint_cog.bind(true))
	cog.focus_exited.connect(_tint_cog.bind(false))


# A gear: a toothed ring plus a hub hole, built from two polygons.
#
# Drawn rather than typed, for the reason in _build_cog. Geometry is derived
# from COG_SIZE so the icon tracks the button at any size -- a hard-coded span
# is the section 12 layout-band trap, which only looks right by coincidence.
func _build_cog_icon(cog: Button) -> void:
	var icon := Control.new()
	icon.name = "CogIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cog.add_child(icon)

	var mid := COG_SIZE * 0.5
	var r_out := COG_SIZE * 0.30
	var r_in := COG_SIZE * 0.21
	var teeth := 8

	# The toothed ring. Two radii alternating around the circle, four points
	# per tooth, gives square teeth rather than a star.
	var ring := PackedVector2Array()
	for i in teeth * 4:
		var seg := i % 4
		var r: float = r_out if (seg == 1 or seg == 2) else r_in
		var a: float = TAU * (float(i / 4) + _COG_STEP[seg]) / float(teeth)
		ring.append(Vector2(mid + cos(a) * r, mid + sin(a) * r))

	var body := Polygon2D.new()
	body.name = "CogBody"
	body.polygon = ring
	body.color = COL_DIM
	icon.add_child(body)

	# The hub, in the card colour, so the ring reads as a gear and not a blob.
	var hub := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		hub.append(Vector2(mid + cos(a) * COG_SIZE * 0.105,
			mid + sin(a) * COG_SIZE * 0.105))

	var hole := Polygon2D.new()
	hole.name = "CogHub"
	hole.polygon = hub
	hole.color = COL_CARD
	icon.add_child(hole)


func _tint_cog(lit: bool) -> void:
	if _cog == null:
		return
	var body := _cog.get_node_or_null("CogIcon/CogBody")
	if body != null:
		body.color = COL_ACCENT if lit else COL_DIM
	var hub := _cog.get_node_or_null("CogIcon/CogHub")
	if hub != null:
		hub.color = COL_CARD_HOVER if lit else COL_CARD


func _on_settings() -> void:
	if _panel != null:
		return
	var panel := SettingsPanel.new()
	panel.closed.connect(_on_settings_closed)
	_panel = panel
	add_child(panel)
	panel.focus_first()


func _on_settings_closed() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	# The hint describes whichever control scheme is active, and the panel is
	# now where that gets changed -- so it has to be re-read on the way out.
	if _hint != null:
		_hint.text = _hint_text()
	if _cog != null:
		_cog.grab_focus()


func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", COL_ACCENT)
	button.add_theme_color_override("font_focus_color", COL_ACCENT)

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		var lit: bool = state in ["hover", "focus", "pressed"]
		style.bg_color = COL_CARD_HOVER if lit else COL_CARD
		style.set_corner_radius_all(10)
		style.set_border_width_all(2)
		style.border_color = COL_ACCENT if lit else Color(0.2, 0.3, 0.45)
		style.set_content_margin_all(12)
		button.add_theme_stylebox_override(state, style)

	button.pressed.connect(handler)
	_buttons.append(button)
	return button


func _centred_label(text: String, size: int, colour: Color,
		top: float, bottom: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -520
	label.offset_right = 520
	label.offset_top = top
	label.offset_bottom = bottom
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# The live preference, or null when this menu is running outside the real
# project -- a harness that instantiates MainMenu directly has no autoloads.
# Every read is guarded rather than assumed, for the reason Shell guards Music:
# a missing setting must never be what stops the menu drawing.
func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _touch_enabled() -> bool:
	var settings := _settings()
	return settings != null and bool(settings.touch_controls)


# The keyboard line is wrong on a phone, where there are no arrow keys to press
# -- so the hint describes whichever scheme is actually active.
func _hint_text() -> String:
	if _touch_enabled():
		return "tap the pads to steer  -  both together reverses"
	return "arrow keys steer  -  DOWN reverses  -  ESC pauses"


# Kept after the button moved into the settings panel: this is still the one
# place the menu flips the preference, and the hint below the stack has to
# follow it. The panel calls Settings directly and the menu re-reads the hint
# when the panel closes.
func _on_toggle_touch() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_touch_controls(not bool(settings.touch_controls))
	if _hint != null:
		_hint.text = _hint_text()


# PLAY, with the leaderboard name asked for once before the first run.
#
# The name is picked BEFORE driving rather than on the end-of-run summary, and
# the reason is a real flaw in doing it after: a first run posts immediately, so
# it lands on the board as "anon" and is only renamed if the player then fills
# the field in. That leaves a genuine score filed under the wrong name for as
# long as it takes them to notice -- and a score good enough to reach a board is
# exactly the one that must not be anonymous.
#
# It gates only the FIRST run. Once a name is stored, PLAY starts a run with no
# interruption, because a prompt on every launch would be a toll on the button
# the whole menu exists to press.
func _on_play(board: int) -> void:
	var lb := _board()
	# Absent on desktop and in every harness, and unavailable when the service
	# cannot be reached. Either way there is no board to be named on, so the
	# prompt would be asking for something nothing will use.
	if lb == null or not lb.available or lb.has_name():
		emit_signal("play_pressed", board)
		return
	_ask_name(board)


# The one-time name prompt.
#
# Deliberately not a blocker: SKIP starts the run and the score posts as "anon",
# which is still better than refusing to let someone play until they have named
# themselves. The name can be set later from the summary, which already has the
# field.
func _ask_name(board: int) -> void:
	if _name_modal != null and is_instance_valid(_name_modal):
		return

	_name_modal = Control.new()
	_name_modal.name = "NamePrompt"
	_name_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_modal.add_to_group(GROUP_BACKDROP)
	add_child(_name_modal)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.01, 0.015, 0.03, 0.88)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_modal.add_child(scrim)

	# A real card behind the text, not just a scrim over the menu.
	#
	# The first version had only the full-screen scrim, and a rendered frame
	# showed why that is not enough: the title landed on the RACER wordmark and
	# the PLAY button showed straight through the name field. A dimmed menu is
	# still a menu -- the prompt needs its own surface to sit on, or it reads as
	# text scattered over the screen rather than as something to answer.
	var plate := PanelContainer.new()
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.anchor_top = 0.5
	plate.anchor_bottom = 0.5
	plate.offset_left = -250.0
	plate.offset_right = 250.0
	plate.offset_top = -108.0
	plate.offset_bottom = 108.0
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.04, 0.06, 0.10, 0.97)
	plate_style.set_corner_radius_all(14)
	plate_style.set_border_width_all(1)
	plate_style.border_color = Color(0.22, 0.40, 0.56, 0.7)
	plate_style.content_margin_left = 26.0
	plate_style.content_margin_right = 26.0
	plate_style.content_margin_top = 22.0
	plate_style.content_margin_bottom = 22.0
	plate.add_theme_stylebox_override("panel", plate_style)
	_name_modal.add_child(plate)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 12)
	plate.add_child(card)

	card.add_child(_centred_line("NAME FOR THE LEADERBOARD", 20, COL_ACCENT))
	card.add_child(_centred_line("shown beside your scores", 13, COL_DIM))

	var field := LineEdit.new()
	field.placeholder_text = "your name"
	field.max_length = 24
	field.custom_minimum_size = Vector2(0, 38)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(field)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var start := Button.new()
	start.text = "START RUN"
	start.custom_minimum_size = Vector2(160, 40)
	row.add_child(start)

	var skip := Button.new()
	skip.text = "SKIP"
	skip.custom_minimum_size = Vector2(100, 40)
	row.add_child(skip)

	var go := func(save: bool) -> void:
		if save:
			var chosen := field.text.strip_edges()
			if chosen != "":
				var b := _board()
				if b != null:
					b.set_player_name(chosen)
		_close_name_modal()
		emit_signal("play_pressed", board)

	start.pressed.connect(go.bind(true))
	skip.pressed.connect(go.bind(false))
	# Enter submits, so the whole thing is type-and-go without reaching for the
	# mouse -- the same reason the upgrade cards take 1/2/3.
	field.text_submitted.connect(func(_t): go.call(true))
	field.grab_focus.call_deferred()


func _close_name_modal() -> void:
	if _name_modal != null and is_instance_valid(_name_modal):
		_name_modal.queue_free()
	_name_modal = null


func _centred_line(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _board() -> Node:
	return get_node_or_null("/root/Leaderboard")


func _on_trailer() -> void:
	emit_signal("trailer_pressed")


func _on_quit() -> void:
	get_tree().quit()
