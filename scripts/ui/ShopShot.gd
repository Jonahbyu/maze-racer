# The picture half of the shop (CLAUDE.md section 7b).
#
# Not a test. Whether a locked chip reads as locked, whether an affordable one is
# distinguishable from one out of reach, and whether four sections of chips fit
# the panel at all are rendered-frame questions -- and the last is the section 8c
# overrun, which no assertion has ever caught.
#
# Two frames, because the interesting states are about MONEY: an empty wallet,
# where nothing is affordable and the screen is a goal list, and a full one,
# where most chips light. A single shot shows one half of the mechanic.
#
# It RESTORES the wallet and the earned set on the way out. The shop writes
# through Unlocks, which persists to settings.cfg, so without this the tool would
# leave the player rich and holding cosmetics they never earned -- the rule
# section 12 records for TouchShot and MarkerPickerShot.
extends SceneTree

var _menu: Node
var _shop: Node
var _frame := 0
var _stage := 0

# What the wallet held before the tool touched it.
var _saved_coins := 0
var _saved_earned := {}

const SETTLE := 12
# Enough to light most chips but not all, so both lit and unlit states are in
# the same frame.
const RICH := 30


func _init() -> void:
	_setup.call_deferred()


func _setup() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)

	var unlocks := root.get_node_or_null("Unlocks")
	if unlocks != null:
		_saved_coins = int(unlocks.coins)
		_saved_earned = unlocks.earned.duplicate()
		# Nothing written from here may reach the player's profile.
		unlocks.suppress_save = true
		unlocks.coins = 0

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame += 1
	if _frame < SETTLE:
		return
	_frame = 0

	# BUILD ON ONE FRAME, CAPTURE ON THE NEXT.
	#
	# process_frame fires BEFORE the UI is drawn, so a shot taken in the same
	# frame that built the screen catches whatever was on screen before it --
	# the first run of this tool photographed "0 COINS" against a wallet of 30
	# and an empty shop that was really the previous frame. That reads exactly
	# like a stale label and is not: it is the trap section 8c records for
	# SummaryShot, whose own two shots came out identical for this reason.
	match _stage:
		0:
			_open()
			_stage = 1
		1:
			_capture("empty")
			_stage = 2
		2:
			var unlocks := root.get_node_or_null("Unlocks")
			if unlocks != null:
				unlocks.coins = RICH
			# Rebuilt rather than refreshed in place, so the frame is of a shop
			# OPENED with money rather than of one that changed under the player.
			# The wallet is set BEFORE the build, since the shop reads it in
			# _ready -- which fires on add_child.
			_close()
			_open()
			_stage = 3
		3:
			_capture("funded")
			_stage = 4
		4:
			_restore()
			print("RESULT: PASS")
			quit(0)


func _open() -> void:
	_shop = Shop.new()
	_menu.add_child(_shop)


func _close() -> void:
	if _shop != null:
		_menu.remove_child(_shop)
		_shop.queue_free()
		_shop = null


# Put the wallet and the earned set back exactly as they were.
func _restore() -> void:
	_close()
	var unlocks := root.get_node_or_null("Unlocks")
	if unlocks == null:
		return
	unlocks.coins = _saved_coins
	unlocks.earned = _saved_earned
	unlocks.suppress_save = false


func _capture(tag: String) -> void:
	var image := root.get_texture().get_image()
	var path := "res://logs/shop_%s.png" % tag
	if image.save_png(path) == OK:
		var unlocks := root.get_node_or_null("Unlocks")
		print("saved %s  (wallet %d)" % [
			path, 0 if unlocks == null else int(unlocks.coins)])
	else:
		printerr("FAILED to save %s" % path)
