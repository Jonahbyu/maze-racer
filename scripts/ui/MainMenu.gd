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

# The button row's WIDTH, and its height at full size. The height is a maximum,
# not a fixed value -- see _build_buttons, which shrinks it when the count no
# longer fits the band below the logo.
const BUTTON_SIZE := Vector2(360, 62)
const SEPARATION := 18.0

# Below this a button stops being comfortably pressable, on a phone especially,
# so the row stops shrinking here and something else has to give. Same shape of
# rule as the minimap sliding clear of the barrier bars rather than shrinking
# into illegibility (section 12).
const BUTTON_HEIGHT_MIN := 48.0

# --- Sizing for the glass, not for the viewport -------------------------------
#
# THE VIEWPORT IS NOT THE SCREEN, and this is the third feature to be caught by
# it (section 9d). stretch/mode is canvas_items with aspect=expand, so the
# viewport height is pinned at 900 and the width stretches: a phone whose canvas
# measures 828x295 CSS pixels gets a ~2526x900 viewport and draws everything at
# 0.33x. Measured, the six-button stack came out at
#
#     360 x 55 viewport units  ->  118 x 18 CSS px on glass, with 7.9px text
#
# against the 44x44 both Apple and Google publish. That is a menu whose every
# button is under half the minimum tap height -- "the buttons below it need to
# be bigger", exactly.
#
# So the row is sized from the live viewport-to-screen scale, the same figure
# the upgrade cards are sized from, and the minimum is expressed in CSS pixels
# rather than in viewport units -- a viewport unit is a count, not a size.
const MIN_TAP_CSS_PX := 44.0

# What a button should measure ON GLASS. Comfortably above the 44px floor: this
# is the menu, read once at rest, where a generous target costs nothing.
const BUTTON_GLASS_PX := 56.0
const BUTTON_FONT_GLASS_PX := 19.0

# The hint below the stack, in CSS pixels. Smaller than a button label -- it is
# a legend, not a control -- but it still has to be readable on glass, where a
# flat 16 viewport units came out at 7px.
const HINT_FONT_GLASS_PX := 12.0

# Bounds on the derived values, so a degenerate scale before layout or a
# harness's dummy viewport cannot produce an absurd button.
const BUTTON_HEIGHT_MAX := 132.0
const FONT_MIN := 15
const FONT_MAX := 52

# The lowest the hint may end, relative to screen centre. The viewport is 900
# tall and pinned there by stretch/mode="canvas_items", so half of it is 450 and
# this leaves a 10px margin at the bottom edge.
const ROW_BOTTOM_LIMIT := 440.0

# Gap between the last button and the hint, and the hint's own height. Named
# because _build_buttons has to subtract them to find the space the row may use.
const HINT_GAP := 30.0
const HINT_HEIGHT := 30.0

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
var _button_grid: GridContainer = null
var _board_button: Button = null
# Which menu is on screen, and the trail back to the root. A STACK rather than
# a parent pointer, so a menu reached from two places returns where it came
# from -- and so ui_cancel has one obvious meaning at every depth.
var _menu_id := MENU_ROOT
var _menu_stack: Array[String] = []
var _menu_title: Label = null
var _board_modal: Control = null
var _hint: Label = null
var _cog: Button = null
var _panel: SettingsPanel = null
var _marker_picker: MarkerPicker = null
var _compendium: UpgradeCompendium = null
var _maze_colours: MazeColours = null
var _shop: Shop = null


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
	# The cog is NOT built. SETTINGS is a labelled row in the OTHER menu now,
	# and two doors to one panel is two things to keep in step -- section 9d
	# already had to rescue this one on a phone, where a 17px glyph sat inside
	# the pause pad's rect and was unhittable.
	#
	# The builder and its drawn icon are kept rather than deleted: _place_cog
	# and _tint_cog are already null-guarded, so nothing needs unpicking, and
	# the in-GAME cog (TouchControls' own, section 9d) is a separate control
	# that still stands down off the pads. Deleting live code to express a
	# layout decision would make restoring it a rewrite.
	_layout_columns()
	# The viewport can resize under a running menu -- a browser window drag is
	# the common case -- and the two-column split is width-dependent, so it has
	# to be re-decided rather than fixed at build time.
	get_viewport().size_changed.connect(_layout_columns)
	# The button sizing reads the viewport-to-screen scale, which changes with
	# the window -- a browser drag is the ordinary case. Sized once at boot it
	# would be correct only at the size the menu happened to open on.
	get_viewport().size_changed.connect(_size_buttons)


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
	# A GRID, not a column.
	#
	# One column is right on a desktop and cannot work on a phone, and the
	# arithmetic is not close: six buttons at the 44px tap minimum need 895 of
	# the viewport's 900 units on a handset, so no separation tweak and no
	# dropped hint rescues it. The stack was fitting only by shrinking every
	# button to 18 CSS px, which is why the menu "needs bigger buttons".
	#
	# The screen a phone actually has is WIDE -- 2526 viewport units against
	# 900 tall -- and a single column spends none of it. Two columns of three
	# fit at 44px with room to spare (measured: the row ends at 399 against the
	# 440 limit), so the layout wraps rather than shrinking past the floor.
	#
	# On a desktop the scale is 1.0, one column holds everything comfortably,
	# and this reduces to exactly the stack the menu has always drawn.
	var grid := GridContainer.new()
	grid.name = "ButtonGrid"
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.anchor_top = 0.5
	grid.anchor_bottom = 0.5
	grid.add_theme_constant_override("v_separation", int(SEPARATION))
	grid.add_theme_constant_override("h_separation", int(SEPARATION))
	add_child(grid)

	_button_grid = grid

	# Which menu you are in, between the logo and the first row. Built BEFORE
	# the menu, because _build_menu writes to it.
	#
	# Hidden at the root, where the logo already answers the question -- a
	# label reading "ROOT" or repeating the game's name would be noise in the
	# one place the player is never lost.
	_menu_title = _centred_label("", TITLE_FONT, COL_ACCENT,
		TITLE_TOP, TITLE_TOP + TITLE_HEIGHT)
	_menu_title.visible = false
	add_child(_menu_title)

	_build_menu(MENU_ROOT)

	# Below the grid wherever _size_buttons left it. Built here rather than
	# there because _size_buttons runs on EVERY resize -- building the hint in
	# it would add a label per resize, and grabbing focus in it would yank the
	# player's focus back to PLAY every time a browser window moved.
	_hint = _centred_label(_hint_text(), 16, COL_DIM,
		_button_grid.offset_bottom + HINT_GAP,
		_button_grid.offset_bottom + HINT_GAP + HINT_HEIGHT)
	add_child(_hint)

	# Deferred: _build_buttons runs from _ready, so the grid is not in the tree
	# yet and grab_focus on a node outside it is an error rather than a no-op.
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()


# The buttons a phone does not show.
#
# Seven buttons at a tappable 44px do not fit a handset alongside the logo, and
# the arithmetic is not close -- measured, seven need four rows of 171 units on
# the 828px phone and the band holds two. Something has to give, and the three
# candidates were: shrink the buttons (which is the bug), shrink the logo (which
# Jonah explicitly likes where it is), or show fewer buttons.
#
# Fewer buttons, and not an arbitrary four. MARKER is a cosmetic choice made
# once, and its picker is a preview panel that wants a desktop screen; WATCH
# TRAILER is a thirty-second reel nobody opens on a phone they came to play on;
# QUIT does nothing meaningful in a browser tab, which is what a phone is
# running. What is left is the three ways to start a run and the way to the
# board -- exactly what the menu is for.
#
# They are named rather than counted, so adding a button later does not silently
# push a different one off the phone.
# UPGRADES is a list beside a diagram, which wants a desktop screen for the same
# reason MARKER's preview does.
# The menus, as a TABLE. The root and every submenu are the same construct, so
# adding a screen is a row rather than an edit in several places -- the failure
# section 6 records for landmark density and 9c for music tracks.
#
# WHY SUBMENUS AT ALL. The flat list reached nine buttons, and nine do not fit a
# phone: measured on the 844x390 MenuShot size, nine buttons wrap to 5 rows of 2
# and need 718 viewport units against a 440-unit band. The previous answer was
# PHONE_HIDDEN, which simply switched five entries off -- so MARKER, UPGRADES
# and MAZE COLOURS were UNREACHABLE on the one platform most likely to be
# someone's only device, and every cosmetic added to them was invisible there.
#
# Grouping fixes the count structurally rather than by shrinking buttons toward
# the tap floor, and it costs desktop nothing: four buttons at the top level is
# a shorter read than nine, and the things a player opens once a session are one
# press further away than the thing they open every time.
#
# "id" is what a submenu is addressed by; "label" is what the player reads.
# Every submenu ends with BACK, added by _build_menu rather than declared, so a
# menu cannot be entered with no way out.
const MENU_ROOT := "root"

# The submenu title, between the logo's baseline (-75) and the first row
# (ROW_TOP, -40). A tight band, which is why the label is short and the font is
# sized to it rather than to the buttons.
# Sized in CSS pixels like every other text on this screen, then converted
# through the live scale -- a viewport unit is a count, not a size. Between a
# button label (19) and the hint (12): it names where you are, which is read
# once on arrival rather than scanned.
const TITLE_GLASS_PX := 16.0
const TITLE_GAP := 12.0
const TITLE_TOP := -78.0
const TITLE_HEIGHT := 34.0
const TITLE_FONT := 22

const MENUS := {
	"root": {
		"title": "",
		"items": [
			{"label": "PLAY", "menu": "play"},
			{"label": "CUSTOMIZATION", "menu": "custom"},
			{"label": "LEADERBOARD", "action": "leaderboard"},
			{"label": "OTHER", "menu": "other"},
		],
	},
	# One button per board rather than a selector: a toggle would need the lit
	# board legible at a glance, where a labelled button says which maze it
	# starts by being pressed.
	"play": {
		"title": "PLAY",
		"items": [
			{"label": "QUICK RACE", "action": "play_general"},
			{"label": "DAILY RUN", "action": "play_daily"},
			{"label": "MONTHLY RUN", "action": "play_monthly"},
		],
	},
	# The cosmetic CHOICES, which are not preferences. Section 12 records why
	# these were never behind the cog: a preference is set once to make the game
	# work on your hardware, where these are closer to picking a character --
	# they want to be seen, and each needs a preview.
	"custom": {
		"title": "CUSTOMIZATION",
		"items": [
			{"label": "MARKER", "action": "marker"},
			{"label": "MAZE COLOURS", "action": "maze_colours"},
			# The shop sells exactly what the two rows above wear, so it belongs
			# beside them rather than in OTHER: a player who opens
			# CUSTOMIZATION to change their marker and finds it locked is one
			# press from the screen that sells it.
			{"label": "SHOP", "action": "shop"},
		],
	},
	# Everything that is neither a run nor a cosmetic. SETTINGS lives here, and
	# that is what retires the cog from the main menu: a labelled row in a
	# labelled menu is a better door than a 17px glyph in a corner, which
	# section 9d already had to rescue once on a phone.
	"other": {
		"title": "OTHER",
		"items": [
			{"label": "SETTINGS", "action": "settings"},
			{"label": "UPGRADES", "action": "upgrades"},
			{"label": "WATCH TRAILER", "action": "trailer"},
			{"label": "QUIT", "action": "quit"},
		],
	},
}

# Rows that do not apply on every platform. QUIT does nothing meaningful in a
# browser tab, and LEADERBOARD opens the panel only on screens too narrow to
# show it beside the menu -- on a desktop the board is already on screen, and a
# button to open it would be a second door to a room the player is standing in.
const PHONE_HIDDEN := ["QUIT"]


# Size the buttons for the glass and wrap them into as many columns as it takes.
#
# Re-run on every resize, because the scale it reads changes with the window --
# a browser drag is the ordinary case, and a menu that sized itself once at boot
# would be correct only at the size it happened to start on.
# Build one menu into the grid, replacing whatever was there.
#
# Every submenu gets a BACK row, appended here rather than declared in MENUS:
# a menu that could be entered with no way out is a dead end, and relying on
# each table row to remember its own escape is exactly the kind of per-entry
# duty that goes stale on the one row nobody looks at.
func _build_menu(id: String) -> void:
	if not MENUS.has(id):
		id = MENU_ROOT
	_menu_id = id
	var menu: Dictionary = MENUS[id]

	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	_board_button = null
	for child in _button_grid.get_children():
		_button_grid.remove_child(child)

	for item in menu["items"]:
		var label := String(item["label"])
		var button: Button
		if item.has("menu"):
			button = _make_button(label, _enter_menu.bind(String(item["menu"])))
		else:
			button = _make_button(label, _do_action.bind(String(item["action"])))
		# The board button keeps its own visibility rule, which _layout_columns
		# owns: it appears only on screens that cannot show the panel.
		if String(item.get("action", "")) == "leaderboard":
			_board_button = button
		_button_grid.add_child(button)

	if id != MENU_ROOT:
		_button_grid.add_child(_make_button("BACK", _leave_menu))

	if _menu_title != null:
		_menu_title.text = String(menu.get("title", ""))
		_menu_title.visible = _menu_title.text != ""

	_size_buttons()
	_layout_columns()


func _enter_menu(id: String) -> void:
	_menu_stack.append(_menu_id)
	_build_menu(id)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _leave_menu() -> void:
	if _menu_stack.is_empty():
		return
	var came_from := _menu_id
	var back: String = _menu_stack.pop_back()
	_build_menu(back)
	# Land on the row that opened the menu just left, rather than at the top of
	# the list -- the same courtesy every screen's close handler gives.
	for button in _buttons:
		if String(button.text) != "" and MENUS.has(came_from) 				and _opens_menu(button.text, came_from):
			button.grab_focus()
			return
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


# Does this label, in the CURRENT menu, lead to the given submenu?
func _opens_menu(label: String, target: String) -> bool:
	for item in MENUS[_menu_id]["items"]:
		if String(item["label"]) == label:
			return String(item.get("menu", "")) == target
	return false


# One place every menu action is dispatched, so a row in MENUS names a string
# rather than binding a Callable the table would have to keep in step.
func _do_action(action: String) -> void:
	match action:
		"play_general": _on_play(Tuning.Board.GENERAL)
		"play_daily": _on_play(Tuning.Board.DAILY)
		"play_monthly": _on_play(Tuning.Board.MONTHLY)
		"marker": _on_marker()
		"maze_colours": _on_maze_colours()
		"shop": _on_shop()
		"upgrades": _on_upgrades()
		"settings": _on_settings()
		"trailer": _on_trailer()
		"leaderboard": _on_leaderboard()
		"quit": _on_quit()


func _size_buttons() -> void:
	if _button_grid == null:
		return

	# A phone shows a reduced set -- see PHONE_HIDDEN. Decided on the same
	# window width the two-column split uses, so the menu has exactly one idea
	# of what a small screen is.
	var window := get_window()
	var win_width := float(window.size.x) if window != null 		else float(get_viewport_rect().size.x)
	var phone := win_width < TWO_COLUMN_MIN_WINDOW_WIDTH
	for button in _buttons:
		# The board button has its own rule -- it appears only on the screens
		# that cannot show the panel -- and _layout_columns owns it.
		if button == _board_button:
			continue
		button.visible = not (phone and button.text in PHONE_HIDDEN)

	var count := 0
	for button in _buttons:
		if button.visible:
			count += 1
	if count == 0:
		return

	# What one viewport unit is worth on the glass. On a desktop this is 1.0 and
	# everything below reduces to the numbers this menu always used.
	var scale := _view_scale()

	# The height a button WANTS so it measures BUTTON_GLASS_PX on screen, and
	# the floor it may never go under, so it always clears the published tap
	# minimum. Both are converted from CSS pixels into viewport units, which is
	# the space these Controls actually live in.
	var want: float = BUTTON_GLASS_PX / scale
	var floor_h: float = maxf(MIN_TAP_CSS_PX / scale, BUTTON_HEIGHT_MIN)
	# The floor is applied AFTER the ceiling, deliberately. BUTTON_HEIGHT_MAX
	# exists to stop a huge window growing absurd buttons; it must never pull a
	# button back under the tap minimum, which is what it did on the 828px phone
	# -- 43.3 CSS px, failing by a whisker for no reason the player could see.
	# A cap that violates the floor is the wrong constraint, so the floor is
	# reasserted last.
	var height: float = maxf(
		clampf(maxf(want, floor_h), BUTTON_HEIGHT_MIN, BUTTON_HEIGHT_MAX),
		floor_h)

	# Width follows the height, so the buttons keep their proportions instead of
	# becoming squat bars -- and never narrower than the desktop width, which is
	# already comfortable to read.
	var width: float = maxf(BUTTON_SIZE.x,
		height * (BUTTON_SIZE.x / BUTTON_SIZE.y))
	var font: int = clampi(int(round(BUTTON_FONT_GLASS_PX / scale)),
		FONT_MIN, FONT_MAX)

	# How many rows fit the band at that height, and therefore how many columns
	# the buttons have to wrap into. The band is the same one the stack always
	# used; what changed is that overflowing it is no longer answered by
	# shrinking past the tap floor.
	var band: float = ROW_BOTTOM_LIMIT - HINT_GAP - HINT_HEIGHT - ROW_TOP
	var per_col: int = max(int(floor((band + SEPARATION)
		/ (height + SEPARATION))), 1)
	# Never more columns than the viewport can actually hold side by side.
	var view_w: float = float(get_viewport_rect().size.x)
	var max_cols: int = max(int((view_w - LEFT_MARGIN * 2.0)
		/ (width + SEPARATION)), 1)
	# Enough columns that the rows FIT the band -- not merely enough that the
	# count divides. Taking ceil(count / per_col) picks the fewest columns that
	# hold the buttons at all, which is a different question and overflowed by
	# 160 units at seven buttons: it answers "how few columns can contain
	# these" rather than "how few keep the stack on screen".
	var cols := 1
	while cols < max_cols and int(ceil(float(count) / float(cols))) > per_col:
		cols += 1
	var rows_n: int = int(ceil(float(count) / float(cols)))

	_button_grid.columns = cols
	for button in _buttons:
		button.custom_minimum_size = Vector2(width, height)
		button.add_theme_font_size_override("font_size", font)

	var grid_w: float = width * float(cols) + SEPARATION * float(cols - 1)
	var stack: float = height * float(rows_n) + SEPARATION * float(rows_n - 1)
	_button_grid.offset_left = -grid_w * 0.5
	_button_grid.offset_right = grid_w * 0.5
	# The first row starts below the title when there is one, so a submenu's
	# heading never sits on the buttons. Derived from the title's measured
	# bottom rather than from a second constant -- one number moving is one
	# number to keep right.
	var row_top := ROW_TOP
	if _menu_title != null and _menu_title.visible:
		row_top = maxf(ROW_TOP, _menu_title.offset_bottom + TITLE_GAP)
	_button_grid.offset_top = row_top
	_button_grid.offset_bottom = row_top + stack

	if _hint != null:
		# The hint scales too. At a flat 16 units it measured 7 CSS px on the
		# phone -- unreadable, and drawn across the buttons because its band was
		# sized for a row height the grid no longer uses.
		var hint_font: int = clampi(int(round(HINT_FONT_GLASS_PX / scale)),
			FONT_MIN, FONT_MAX)
		_hint.add_theme_font_size_override("font_size", hint_font)
		# The submenu title scales the same way, and for the same reason: a
		# flat font size in viewport units is a COUNT, not a size, so at 22 it
		# measured ~9 CSS px on the phone -- the failure section 9d records for
		# the hint, reappearing on the label added above it. Sized from the
		# live scale, and its band grows with it so the glyphs are not clipped
		# by a fixed-height rect.
		if _menu_title != null:
			var title_font: int = clampi(
				int(round(TITLE_GLASS_PX / scale)), FONT_MIN, FONT_MAX)
			_menu_title.add_theme_font_size_override("font_size", title_font)
			var title_h: float = maxf(TITLE_HEIGHT, float(title_font) * 1.5)
			# BELOW the logo's own rect, never in the gap above the first row.
			#
			# Hanging it off ROW_TOP put it at -86..-52, which is INSIDE the
			# logo box (-286..-75) -- and the wordmark's drawn glyphs reach the
			# bottom of that box, so the title landed across "RACER". The two
			# rects overlapping is the whole failure; section 12 records the
			# same thing twice, for the mirror cutting through the maze name
			# and the quadrant's count label reaching into the mirror. Rect
			# clearance is not text clearance, and here even the rects did not
			# clear.
			_menu_title.offset_top = LOGO_TOP + LOGO_SIZE.y + TITLE_GAP
			_menu_title.offset_bottom = _menu_title.offset_top + title_h
		var hint_h: float = maxf(HINT_HEIGHT, float(hint_font) * 1.6)
		_hint.offset_top = row_top + stack + HINT_GAP
		_hint.offset_bottom = row_top + stack + HINT_GAP + hint_h


# The viewport-to-screen scale, guarded.
#
# get_stretch_transform() is that factor exactly -- the same figure UpgradeScreen
# sizes its card text from. It is degenerate before the tree has laid out, and a
# harness's dummy viewport reports a tiny scale, so neither may reach the
# arithmetic above.
# Overrides the measured scale. -1.0 means "measure it".
#
# Exists for the harness: a headless viewport cannot report a phone's stretch
# scale, so without this the only way to check the phone case is to recompute
# the sizes in the test -- which asserts the arithmetic against itself and
# passes even when the constants it reads are wrong. Verified: with the sizing
# reverted to a flat desktop height, the phone assertions fail through this and
# do not through a recomputation.
var scale_override: float = -1.0


func _view_scale() -> float:
	if scale_override > 0.0:
		return scale_override
	var vp := get_viewport()
	if vp == null:
		return 1.0
	# A 0.01 floor is NOT enough, and trusting it shipped 25x buttons past a
	# green harness. Headless runs on a 64x64 dummy viewport and reports a
	# stretch scale of 0.04 -- a perfectly finite number, comfortably above any
	# near-zero guard, and meaningless. Every size derived from it inflated by
	# 25x while the assertions still read as plausible.
	#
	# So the guard is on the VIEWPORT, not on the scale: below a size no real
	# display has, there is nothing to scale against and 1.0 is the honest
	# answer. Desktop and phone both sit far above it.
	var view := vp.get_visible_rect().size
	if view.x < 320.0 or view.y < 240.0:
		return 1.0
	var sx: float = vp.get_stretch_transform().get_scale().x
	# A LOWER BOUND ON THE SCALE ITSELF, not only on the viewport.
	#
	# Guarding the viewport size is not enough, and trusting it produced 1100
	# unit buttons in the harness: a Window reports a plausible 1600x900 visible
	# rect while its stretch transform is still the dummy's, so the size check
	# passes and the scale is fiction. 0.15 is below any real device -- the
	# tightest measured phone is 0.328 -- and far above the 0.04 a headless run
	# reports, so it separates the two without touching anything real.
	if sx < 0.15 or sx > 8.0:
		return 1.0
	return sx


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
	# While the board is open as a modal it stays visible and stays put -- the
	# column layout must not drag it back into the corner underneath its own
	# scrim.
	if _board_modal != null and is_instance_valid(_board_modal):
		return
	_leaderboard.visible = two
	# The button is the way IN to the board on a screen that cannot show it
	# beside the menu, so it appears exactly when the panel does not. On a
	# desktop the board is already on screen and a button opening it would be a
	# second door into a room the player is standing in.
	if _board_button != null:
		_board_button.visible = not two

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


# The marker picker, mounted the same way the settings panel is -- a modal
# child of the menu, closed by its own signal. It writes through Settings, so
# nothing has to be read back out of it here.
# Open the leaderboard as a modal.
#
# Only reachable on a screen too narrow for the two-column layout, where the
# panel is hidden. It is the SAME LeaderboardPanel, re-parented into a scrim
# rather than a second board built for phones -- two panels showing one set of
# scores is the parallel-array trap in different clothes (section 6), and the
# one that is not on screen is the one that would rot.
func _on_leaderboard() -> void:
	if _board_modal != null and is_instance_valid(_board_modal):
		return
	if _leaderboard == null:
		return

	var modal := Control.new()
	modal.name = "BoardModal"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_to_group(GROUP_BACKDROP)
	add_child(modal)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Deeper than the name prompt's scrim. The board is a dense grid of small
	# numbers, and the logo sits directly behind it -- at 0.88 the wordmark read
	# straight through the rows, which is the "dimmed menu is still a menu"
	# failure the name prompt already records, with more to compete against.
	scrim.color = Color(0.01, 0.015, 0.03, 0.96)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(scrim)

	# The panel itself, moved rather than copied. It goes back to the menu on
	# close, so nothing about its state is rebuilt or lost.
	_leaderboard.get_parent().remove_child(_leaderboard)
	_leaderboard.visible = true
	_leaderboard.anchor_left = 0.5
	_leaderboard.anchor_right = 0.5
	_leaderboard.anchor_top = 0.0
	_leaderboard.anchor_bottom = 1.0
	# Widened for the glass, like everything else on this screen. At its desktop
	# 460 units the panel is a narrow strip in a 1948-unit phone viewport, with
	# text at a third of its intended size -- the board would be reachable and
	# still unreadable, which is only half the fix.
	var board_scale := _view_scale()
	var board_w: float = clampf(LeaderboardPanel.PANEL_WIDTH / board_scale,
		LeaderboardPanel.PANEL_WIDTH,
		maxf(float(get_viewport_rect().size.x) - PANEL_MARGIN * 4.0,
			LeaderboardPanel.PANEL_WIDTH))
	_leaderboard.offset_left = -board_w * 0.5
	_leaderboard.offset_right = board_w * 0.5
	_leaderboard.offset_top = PANEL_MARGIN
	var close_h: float = maxf(MIN_TAP_CSS_PX / board_scale, BUTTON_SIZE.y)
	_leaderboard.offset_bottom = -PANEL_MARGIN - close_h - PANEL_MARGIN
	modal.add_child(_leaderboard)
	# Rescaled AFTER the re-parent, never before it: the rebuild refreshes the
	# rows, which reads the Leaderboard autoload through get_node_or_null -- and
	# that is an error on a node sitting outside the tree, not a null. It would
	# have put a red line in logs/errors.log on every open, which is the channel
	# this project reads first.
	#
	# The panel's own text is sized for the desktop mount, where it sits beside
	# the menu. On glass that is ~4 CSS px, so the board would be reachable and
	# still unreadable -- half a fix.
	_leaderboard.rescale(1.0 / maxf(_view_scale(), 0.05))

	var close := _make_button("CLOSE", _close_board_modal)
	# Not part of the menu's own stack -- it belongs to this modal, and leaving
	# it in _buttons would have _size_buttons resize a button that is not in the
	# grid and grab_focus land on it after the modal is gone.
	_buttons.erase(close)
	close.anchor_left = 0.5
	close.anchor_right = 0.5
	close.anchor_top = 1.0
	close.anchor_bottom = 1.0
	var cw: float = maxf(BUTTON_SIZE.x, board_w * 0.4)
	var ch: float = close_h
	close.offset_left = -cw * 0.5
	close.offset_right = cw * 0.5
	close.offset_top = -ch - PANEL_MARGIN
	close.offset_bottom = -PANEL_MARGIN
	close.custom_minimum_size = Vector2(cw, ch)
	modal.add_child(close)

	_board_modal = modal


func _close_board_modal() -> void:
	if _board_modal == null or not is_instance_valid(_board_modal):
		return
	# Hand the panel back to the menu before the modal is freed, or it is freed
	# with it and the board is gone for the rest of the session.
	if _leaderboard != null and _leaderboard.get_parent() == _board_modal:
		_board_modal.remove_child(_leaderboard)
		add_child(_leaderboard)
		# Back to its desktop text size, and again only once it is back in the
		# tree -- or a later resize into the two-column layout would leave the
		# side panel drawn at phone scale.
		_leaderboard.rescale(1.0)
	_board_modal.queue_free()
	_board_modal = null
	_layout_columns()


func _on_marker() -> void:
	if _marker_picker != null:
		return
	var picker := MarkerPicker.new()
	picker.closed.connect(_on_marker_closed)
	_marker_picker = picker
	add_child(picker)
	picker.focus_first()


func _on_marker_closed() -> void:
	if _marker_picker != null:
		_marker_picker.queue_free()
		_marker_picker = null
	_focus_button("MARKER")


func _on_upgrades() -> void:
	if _compendium != null:
		return
	var screen := UpgradeCompendium.new()
	screen.closed.connect(_on_upgrades_closed)
	_compendium = screen
	add_child(screen)
	screen.focus_first()


func _on_upgrades_closed() -> void:
	if _compendium != null:
		_compendium.queue_free()
		_compendium = null
	_focus_button("UPGRADES")


func _on_maze_colours() -> void:
	if _maze_colours != null:
		return
	var screen := MazeColours.new()
	screen.closed.connect(_on_maze_colours_closed)
	_maze_colours = screen
	add_child(screen)
	screen.focus_first()


func _on_maze_colours_closed() -> void:
	if _maze_colours != null:
		_maze_colours.queue_free()
		_maze_colours = null
	_focus_button("MAZE COLOURS")


func _on_shop() -> void:
	if _shop != null:
		return
	var screen := Shop.new()
	screen.closed.connect(_on_shop_closed)
	_shop = screen
	add_child(screen)
	screen.focus_first()


func _on_shop_closed() -> void:
	if _shop != null:
		_shop.queue_free()
		_shop = null
	_focus_button("SHOP")


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
	_focus_button("SETTINGS")


# Land focus on a named row of the LIVE menu, falling back to the first row.
#
# Every screen closes back onto the button that opened it, and with submenus
# that button may no longer be on screen -- a player can close a screen after
# the menu has moved on. A miss must leave focus somewhere real rather than
# nowhere, or the keyboard stops working with nothing to show why.
func _focus_button(label: String) -> void:
	for button in _buttons:
		if button.text == label:
			button.grab_focus()
			return
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


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
