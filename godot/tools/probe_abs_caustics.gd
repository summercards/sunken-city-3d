extends SceneTree
## 只针对吸收式方案：开/关它自带的焦散，看现状。
var main: Node
var out := "D:/projects/sea-work/caustics/abs"
var mat: ShaderMaterial
const F := 4.0
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 60: await process_frame
	main.hud.hide(); main.markers.hide(); main.ribbon.hide()
	main.cam.suspend_follow()
	main.cam.orbit_dir = Vector3(-0.52, 0.30, 0.42)
	main.cam.target = Vector3(0, -3.0, 6)
	main.cam.distance = 16.0
	main.cam.refresh()
	for i in 12: await process_frame
	main.water_node.set_process(false)
	main.set_process(false); main.set_physics_process(false)
	mat = main.water_node.current_material()
	print("[abs] shader=", mat.shader.resource_path)
	for spec in [["a-off", false, 0.0, 2.0, 40.0],
				 ["a-15", true, 0.15, 2.0, 40.0],
				 ["a-35", true, 0.35, 2.0, 40.0],
				 ["a-60", true, 0.60, 2.0, 40.0]]:
		mat.set_shader_parameter("caustics_enabled", spec[1])
		mat.set_shader_parameter("caustic_strength", spec[2])
		mat.set_shader_parameter("caustic_size", spec[3])
		mat.set_shader_parameter("caustic_range", spec[4])
		for i in 8:
			mat.set_shader_parameter("u_time", F)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + spec[0] + ".png")
		print("[abs] ", spec[0])
	quit(0)
