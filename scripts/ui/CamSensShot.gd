# The picture half of the camera sensitivity dial.
#
# The dial's whole subject is what the camera does DURING a turn, so a frame
# taken at rest shows nothing at all -- both ends of the dial look identical the
# moment the swing has finished. It seeks a pivot and shoots a fixed number of
# frames INTO it, at each end of the dial, on the same seed and the same corner.
# That is the only pair of frames where "snap" and "lag" are distinguishable.
#
# For the reason PaletteShot seeks a junction rather than shooting on a timer.
extends SceneTree

const OUT := "res://logs"
const SEED := 20260907
# Frames after the pivot to shoot. Inside the turn freeze, which is where a
# lagged camera is most visibly behind and a snapped one is already round.
const AFTER := 3


func _init() -> void:
	await process_frame
	# The three positions are DERIVED from the dial's own ends, never written
	# out. A literal [0, 5, 10] was correct while the dial ended at 10 and went
	# quietly half-blind the moment it was lengthened -- it would have shot the
	# fast half three times and never photographed the new slow end at all,
	# which is the one frame this tool exists to produce. The transcription trap
	# section 12 records for tests, in an instrument.
	var lo: float = Tuning.CAM_SENSITIVITY_MIN
	var hi: float = Tuning.CAM_SENSITIVITY_MAX

	# The dial is a PERSISTED preference, so the tool has to put it back: the
	# setting is written to user://settings.cfg, and without this the player is
	# left on whichever dial position this shot happened to end on. A tool must
	# not write the state it is inspecting (CLAUDE.md section 9d, where TouchShot
	# and MarkerPickerShot record the same trap). This one did exactly that for
	# as long as it existed, and was caught leaving the saved dial at its own
	# last position.
	var settings := root.get_node_or_null("/root/Settings")
	var restore: float = (float(settings.cam_sensitivity) if settings != null
		else Tuning.cam_sensitivity_default())

	for dial in [lo, Tuning.cam_sensitivity_default(), hi]:
		await _shoot_dial(float(dial))

	if settings != null:
		settings.set_cam_sensitivity(restore)
	quit()


func _shoot_dial(dial: float) -> void:
	var settings := root.get_node_or_null("/root/Settings")
	if settings != null:
		settings.set_cam_sensitivity(dial)

	var game = load("res://scenes/Game.tscn").instantiate()
	game.run_seed = SEED
	root.add_child(game)
	await process_frame
	# A run opens on the loadout pick (CLAUDE.md section 7), so steering is
	# inert until a card is taken.
	if int(game.phase) == 1:
		game._on_upgrade_chosen(0)
	await process_frame

	# Seek a real pivot rather than shooting on a timer.
	var fired := false
	for i in 1200:
		var r = game.racer
		# A parked racer takes no turn input at all, so a seeker that does not
		# un-stick simply sits against a wall for its whole budget and shoots a
		# frame with no pivot in it -- which is indistinguishable from the
		# feature doing nothing.
		if r != null and int(r.state) == 1:
			r.request_reverse()
		if not fired and r != null and int(r.state) == 0:
			var best: int = game.maze.best_direction(r.cell)
			if best != -1 and best != r.facing:
				# Compared against the racer's OWN left/right, never by indexing
				# a [0,1,2,3] table. Maze directions are BIT FLAGS (N=1, E=2,
				# S=4, W=8), so `[0,1,2,3].find(facing)` returns -1 for every
				# real heading -- the turn was never requested at all, and the
				# tool only ever caught pivots the autopilot happened to make on
				# its own. That is why "pivot found: false" moved between runs
				# on the same seed: it was luck, not the dial.
				if best == r.right_direction():
					r.request_turn(1)
				elif best == r.left_direction():
					r.request_turn(-1)
		await process_frame
		if game.racer != null and game.racer.freeze > 0.0 and not fired:
			fired = true
			for _j in AFTER:
				await process_frame
			break

	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/shot_cam_sens_%d.png" % [OUT, int(dial)])
	# A frame with no pivot in it is indistinguishable from the dial doing
	# nothing, which is the one thing this instrument must never say by
	# accident. Loud rather than a quiet `false` beside a saved file.
	if fired:
		print("dial %d: shot (pivot found: true)" % int(dial))
	else:
		var r = game.racer
		printerr("dial %d: NO PIVOT FOUND -- frame is not evidence (phase=%s state=%s cell=%s)"
			% [int(dial), str(game.phase),
				str(r.state) if r != null else "no racer",
				str(r.cell) if r != null else "-"])
	game.queue_free()
	await process_frame
