# Toolchain smoke test.
#
# Proves the headless harness path works end to end: Godot launches with no
# window, runs a script, prints to captured stdout, and exits cleanly. If this
# stops passing, every other harness result is untrustworthy.
extends SceneTree


func _init() -> void:
	print("=== SmokeTest ===")
	print("godot version : %s" % Engine.get_version_info().string)
	print("project name  : %s" % ProjectSettings.get_setting("application/config/name"))

	var failures := 0

	# The three inputs from CLAUDE.md section 2 must exist, or Phase 1 cannot
	# be built at all.
	for action in ["turn_left", "turn_right", "turn_around"]:
		if InputMap.has_action(action):
			print("input ok      : %s" % action)
		else:
			printerr("MISSING INPUT : %s" % action)
			failures += 1

	if failures == 0:
		print("RESULT: PASS")
	else:
		print("RESULT: FAIL (%d)" % failures)

	quit(failures)
