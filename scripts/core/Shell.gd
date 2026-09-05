# The application root: owns exactly one of { menu, game, trailer } at a time.
#
# Main.tscn used to boot Game.gd directly, so there was nowhere to put a menu
# and nowhere for the trailer to be launched from. This node is that place, and
# it is deliberately thin -- Game.gd is still the run controller and is
# instantiated here exactly as the scene used to instantiate it, so a normal run
# behaves identically to before.
#
# docs/specs/trailer.md
class_name Shell
extends Node

enum Mode { MENU, GAME, TRAILER }

var mode: int = Mode.MENU

# The single live child. Freed and replaced on every mode change.
var _current: Node = null


func _ready() -> void:
	show_menu()


# --- Mode switching ----------------------------------------------------------

func show_menu() -> void:
	_swap(Mode.MENU, _build_menu())


func start_game() -> void:
	_swap(Mode.GAME, _build_game())


func start_trailer() -> void:
	_swap(Mode.TRAILER, _build_trailer())


# Replace the live child.
#
# The old node is removed from the tree BEFORE being freed, so its _process
# cannot run again against half-torn-down state. queue_free alone leaves it in
# the tree for the rest of the frame, and Game._process dereferences a racer and
# a HUD every frame -- a trailer teardown that let one more frame through was an
# easy null crash.
func _swap(new_mode: int, node: Node) -> void:
	if _current != null and is_instance_valid(_current):
		remove_child(_current)
		_current.queue_free()
	_current = node
	mode = new_mode
	if node != null:
		add_child(node)


func _build_menu() -> Node:
	_music(Music.MENU_TRACK)
	var menu := MainMenu.new()
	menu.name = "MainMenu"
	menu.play_pressed.connect(start_game)
	menu.trailer_pressed.connect(start_trailer)
	return menu


# No music call here on purpose: the track is a property of the MAZE, so Game
# starts it in _start_maze. Setting a run-wide track here would fight that, and
# a game instantiated bare by a harness would behave differently from one
# reached through the menu.
func _build_game() -> Node:
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	# Back to the menu when the player dismisses the end-of-run summary, the
	# same shape as the trailer's finished signal. Game does not free itself:
	# owning the mode swap is this node's whole job, and a harness that loads
	# Game.tscn bare simply never connects this.
	game.run_dismissed.connect(show_menu)
	return game


func _build_trailer() -> Node:
	_music(Music.TRAILER_TRACK)
	var trailer := TrailerDirector.new()
	trailer.name = "TrailerDirector"
	trailer.finished.connect(show_menu)
	return trailer


# Music is an autoload and so is absent from a harness that instantiates this
# node directly rather than booting the project. Guarded rather than assumed,
# because a missing soundtrack must never be what stops the game starting.
func _music(track: String) -> void:
	var music := get_node_or_null("/root/Music")
	if music != null:
		music.play(track)
