extends SceneTree
## 绞盘打捞台旋转后的实景对照：同一机位拍全景 + 近景。
##
##   godot --path godot --resolution 1280x800 --script res://tools/capture_salvage_angle.gd -- --skip-title --nosave

var main: Node

func _init() -> void:
	call_deferred("run")


func _shot(name: String, target: Vector3, distance: float, fov := 34.0) -> void:
	if main.cam.has_method("suspend_follow"):
		main.cam.suspend_follow()
	else:
		main.cam.set_process(false)
	main.cam.target = target
	main.cam.dir = Vector3(-54, 76.37, 54).normalized()
	main.cam.distance = distance
	main.cam.cam_fov = fov
	main.cam.apply_pose()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/" + name)
	print("[salvage-shot] ", name)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 10:
		await process_frame
	var zone: Node3D = main._zone_nodes.get("zone1", null)
	if zone == null:
		print("[salvage-shot] FAIL zone1 未加载")
		quit(1)
		return
	var station: Node3D = zone.get_node_or_null("Models/绞盘打捞台")
	var area: Node3D = zone.get_node_or_null("WalkAreas/Walk_zone1_salvage")
	var pole: Node3D = station.get_node_or_null("salvage_station/PoleAndFlowers")
	print("[salvage-shot] station=", station.global_transform.origin,
		" rot_y_deg=", snappedf(rad_to_deg(station.global_rotation.y), 0.1))
	print("[salvage-shot] pole=", pole.global_position,
		" area_origin=", area.global_transform.origin)
	var landing: Node3D = area.get_node_or_null("Landing_salvage")
	if landing != null:
		print("[salvage-shot] landing=", landing.global_position)
	# 全景：以甲板为中心，用玩家截图那个方位
	await _shot("final_salvage.png", Vector3(-13.4, 1.6, 12.2), 20.0, 38.0)
	var roof: Vector3 = Vector3(110.6, 15.2, 72.9)
	await _shot("neon_roof.png", roof, 22.0, 40.0)
	await _shot("neon_roof_wide.png", roof, 30.0, 44.0)
	quit(0)
