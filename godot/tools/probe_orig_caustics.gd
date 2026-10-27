extends SceneTree
## 原版方案下焦散开关的 A/B。默认存档是吸收式，这里显式切回原版再测。
var main: Node
var out := "D:/projects/sea-work/caustics/orig"
var mat: ShaderMaterial
const F := 4.0
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 70: await process_frame
	main.grade.set_water_scheme("original")
	for i in 15: await process_frame
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
	print("[orig] shader=", mat.shader.resource_path)
	for spec in [["o-off", 0.0], ["o-on", 0.35]]:
		mat.set_shader_parameter("caustics_strength", spec[1])
		for i in 10:
			mat.set_shader_parameter("u_time", F)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + spec[0] + ".png")
		print("[orig] ", spec[0])
	quit(0)
