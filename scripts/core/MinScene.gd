# DIAGNOSTIC: minimal main scene -- no Shell, no Game, no HUD. Just an mp3.
extends Node

func _ready() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://audio/music/ah-eh-oh.mp3")
	p.volume_db = -12.0
	add_child(p)
	p.play()
