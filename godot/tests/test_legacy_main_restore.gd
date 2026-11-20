extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var entry := str(ProjectSettings.get_setting("application/run/main_scene"))
	var checks := [
		entry == "res://scenes/main.tscn",
		root.has_node("Zones") and root.has_node("Economy") and root.has_node("GameState"),
		ProjectSettings.get_setting("application/config/custom_user_dir_name", "").begins_with("sea-verification/"),
	]
	if checks.has(false):
		printerr("FAIL [legacy-main-restore] entry/autoload/isolation: ", checks)
		quit(1)
		return
	var result := change_scene_to_file(entry)
	if result != OK:
		printerr("FAIL [legacy-main-restore] change scene: ", result)
		quit(1)
		return
	await scene_changed
	for i in 12:
		await process_frame
	checks.append(current_scene.scene_file_path == entry)
	checks.append(current_scene.has_node("World/Zones/Zone1HomeHarbor"))
	checks.append(current_scene.has_node("HUD"))
	checks.append(current_scene.has_node("Camera"))
	checks.append(current_scene.has_node("World/SeaStructures/water_building_001"))
	checks.append(not current_scene.has_node("Ramp"))
	var failures := checks.count(false)
	if failures:
		printerr("FAIL [legacy-main-restore] legacy node layout: ", checks)
	print("[legacy-main-restore] %d checks, %d failures" % [checks.size(), failures])
	quit(1 if failures else 0)
