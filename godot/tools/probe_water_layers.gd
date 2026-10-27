extends SceneTree
## 逐层关掉水面图层，定位「贴图切边」来自哪一层。
##
##   SEA_SHOT_DIR=<目录> Godot --path godot --script res://tools/probe_water_layers.gd
##
## 每张图只改一个参数，机位固定，差异就是那一层造成的。

var main: Node
var out_dir := ""
var mat: ShaderMaterial


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 60:
		await process_frame
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()
	# 平视偏俯、近距：截图里那种能看到建筑侧面与水下轮廓的机位。
	main.cam.orbit_dir = Vector3(-0.42, 0.52, 0.50)
	main.cam.target = Vector3(-6, 1.12, 6)
	main.cam.distance = 44.0
	main.cam.refresh()
	for i in 14:
		await process_frame

	mat = main.water_node.current_material()
	print("[layers] shader=", mat.shader.resource_path.get_file(),
		" ripples=", mat.get_shader_parameter("ripples_enabled"),
		" normal=", mat.get_shader_parameter("surface_normal_strength"))

	await _shot("00-all")

	# 逐个关。
	await _only("01-no-ripple-texture", {"ripples_enabled": false})
	mat.set_shader_parameter("ripples_enabled", true)
	await _only("02-no-normal-map", {"surface_normal_strength": 0.0})
	mat.set_shader_parameter("surface_normal_strength", 0.56)
	await _only("03-no-refraction", {"refraction_strength": 0.0})
	mat.set_shader_parameter("refraction_strength", 15.5)
	await _only("04-no-reflection", {"reflection_strength": 0.0})
	mat.set_shader_parameter("reflection_strength", 1.0)
	await _only("05-no-relief", {"relief_enabled": false})
	mat.set_shader_parameter("relief_enabled", true)
	await _only("06-no-glints", {"glints_enabled": false})
	mat.set_shader_parameter("glints_enabled", true)
	await _only("07-no-contact-foam", {"contact_foam_strength": 0.0})
	mat.set_shader_parameter("contact_foam_strength", 0.83)

	# 只留波纹纹理：其他全关，看它单独长什么样。
	mat.set_shader_parameter("surface_normal_strength", 0.0)
	mat.set_shader_parameter("refraction_strength", 0.0)
	mat.set_shader_parameter("reflection_strength", 0.0)
	mat.set_shader_parameter("relief_enabled", false)
	mat.set_shader_parameter("glints_enabled", false)
	mat.set_shader_parameter("contact_foam_strength", 0.0)
	mat.set_shader_parameter("ripple_color", Color(1, 1, 1, 1))
	await _shot("08-ripple-only")

	main.queue_free()
	await process_frame
	quit(0)


func _only(label: String, params: Dictionary) -> void:
	for key in params:
		mat.set_shader_parameter(key, params[key])
	for i in 10:
		await process_frame
	await _shot(label)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(label + ".png")
	img.save_png(path)
	print("[layers] ", label)
