extends SceneTree
## 用出厂默认值抓三张：水下近景、中景、远景，确认焦散只落在水下物体上。
var main: Node
var out := "D:/projects/sea-work/caustics/final"
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 70: await process_frame
	main.hud.hide(); main.markers.hide(); main.ribbon.hide()
	main.cam.suspend_follow()
	main.water_node.set_process(false)
	main.set_process(false); main.set_physics_process(false)
	var mat: ShaderMaterial = main.water_node.current_material()
	print("[final] shader=", mat.shader.resource_path)
	# 两套水的参数名不同（原版 caustics_strength / 吸收式 caustic_strength），
	# 按当前方案取。
	var strength_key := "caustic_strength" if String(mat.shader.resource_path).contains("absorption") else "caustics_strength"
	print("[final] caustics_enabled=", mat.get_shader_parameter("caustics_enabled"),
		" ", strength_key, "=", mat.get_shader_parameter(strength_key))
	var views := [
		["v1-close", Vector3(-0.52, 0.30, 0.42), Vector3(0, -3.0, 6), 16.0],
		["v2-mid", Vector3(-0.44, 0.52, 0.48), Vector3(-3, 1.12, 5), 24.0],
		["v3-far", Vector3(-0.30, 0.90, 0.32), Vector3(-8, 1.12, 8), 34.0],
	]
	for v in views:
		main.cam.orbit_dir = v[1]
		main.cam.target = v[2]
		main.cam.distance = v[3]
		main.cam.refresh()
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + v[0] + ".png")
		print("[final] ", v[0])
	quit(0)
