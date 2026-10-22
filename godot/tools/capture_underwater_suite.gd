extends SceneTree
## 同机位验收：网页版相机 JSON + 固定水下时间，关闭网页版没有的头灯。
## Godot --path godot --resolution 1440x900 --script res://tools/capture_underwater_suite.gd
const Materials = preload("res://scripts/world/uw_materials.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not FileAccess.file_exists(
			"res://outputs/uw-standard-web-cameras.json"):
		printerr("[uw-suite] requires a real renderer and web camera baseline")
		quit(2)
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("_autosave_on", false)
	for i in 5:
		await process_frame
	var uw: Node3D = main.get("dive")
	var original_env: Environment = main.get("world_env").environment
	main.call("_on_dive")
	uw.call("freeze_time", 3.0)
	var cameras: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://outputs/uw-standard-web-cameras.json"))
	var poses := {
		"overview": Vector3(0, -10, 12),
		"neighborhood": Vector3(-14, -6, 20),
		"reef": Vector3(8, -14, -22),
		"trench": Vector3(-2, -200, -120),
	}
	var failures := 0
	for tag in poses:
		uw.set_process(true)
		uw.call("debug_teleport", poses[tag])
		uw.get("air").lamp = false
		for i in 15:
			await process_frame
		uw.set_process(false)
		var cam: Camera3D = uw.get("camera")
		if cameras.has(tag):
			var row: Dictionary = cameras[tag]
			var p: Array = row.position
			var q: Array = row.quaternion
			cam.global_transform = Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])),
				Vector3(p[0], p[1], p[2]))
		uw.call("_update_sky", 1.12 - poses[tag].y)
		uw.call("_update_lamp")
		uw.get("deco").call("update", 0.0, 3.0, poses[tag], cam)
		await _save("uw-standard-godot-" + tag)
		# 静态相机 A/B：冻结模型和焦散，暂时隐藏动态装饰及人物/HUD。
		var deco: Node3D = uw.get("deco")
		# 保留灯光：不能隐藏 Deco 根节点，灯也在其中。
		var hidden: Array = []
		for n in deco.get_children():
			if n is GeometryInstance3D and n.visible:
				n.hide()
				hidden.append(n)
		var diver: Node3D = uw.get("_diver")
		diver.hide()
		uw.get("_marker_layer").hide()
		main.get("hud").hide()
		var a := await _save("uw-stability-%s-a" % tag)
		var b := await _save("uw-stability-%s-b" % tag)
		var diff := 0
		# 裁掉海面 HUD 的其它控件，只检查 3D 主画面。
		for y in range(120, a.get_height() - 150, 3):
			for x in range(40, a.get_width() - 40, 3):
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) > 0.04:
					diff += 1
		print("[uw-suite] ", tag, " static_changed_samples=", diff)
		if diff > 0:
			failures += 1
		for n in hidden:
			n.show()
		diver.show()
		main.get("hud").show()
		uw.get("_marker_layer").show()
	# 单独验头灯：深沟的开灯效果不能丢失。
	uw.get("air").lamp = true
	uw.call("_update_lamp")
	await _save("uw-standard-godot-trench-lamp")
	uw.call("_finish_exit")
	var restored: bool = main.get("world_env").environment == original_env
	print("[uw-suite] surface_environment_restored=", restored)
	main.queue_free()
	await process_frame
	Materials.clear_cache()
	for i in 3:
		await process_frame
	quit(0 if restored and failures == 0 else 1)

func _save(name: String) -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://outputs/%s.png" % name))
	return img
