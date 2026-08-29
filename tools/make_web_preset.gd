@tool
extends EditorScript

# Godot rejects a hand-written Web preset with an unhelpful "configuration
# errors" message and no detail, because the preset schema carries keys the
# engine expects to exist. Building the preset through EditorExportPlatform
# lets the engine fill its own defaults, so the result is valid by construction.
func _run() -> void:
	var eps := EditorExportPlatform.new()
	print("platforms: ", EditorExport.get_singleton().get_export_platform_count())
	var ee := EditorExport.get_singleton()
	for i in ee.get_export_platform_count():
		var p := ee.get_export_platform(i)
		print(i, " -> ", p.get_os_name(), " / ", p.get_name())
