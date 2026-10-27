extends SceneTree
## 调色用的机位与取色探针（不是验收用例）。
##
## 用法：
##   SEA_SHOT_DIR=<目录> Godot --path godot --script res://tools/probe_water_look.gd
##   SEA_TUNE=<json 文件>  覆盖 water.tres 的一组参数（可选）
##   SEA_VIEW=top|default  机位（默认 top，模拟俯视）
##
## 输出：每个机位一张 png，外加开阔水域取样点的像素均值，便于对着目标色拟合。

var main: Node
var out_dir := ""


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	for i in 60:
		await process_frame
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()

	var tune := OS.get_environment("SEA_TUNE")
	if tune != "" and FileAccess.file_exists(tune):
		_apply(FileAccess.get_file_as_string(tune))

	var view := OS.get_environment("SEA_VIEW")
	if view == "":
		view = "top"
	if view == "top":
		# 接近参考截图的俯视：俯角约 55°，距离 46 m。
		main.cam.orbit_dir = Vector3(-0.28, 0.86, 0.43)
		await shot("look-top", Vector3(0, 1.12, 4), 46.0)
		main.cam.orbit_dir = Vector3(-0.28, 0.86, 0.43)
		await shot("look-top-far", Vector3(0, 1.12, 4), 78.0)
		main.cam.orbit_dir = Vector3(-0.5, 0.62, 0.5)
		await shot("look-mid", Vector3(0, 1.12, 4), 46.0)
	else:
		main.cam.orbit_dir = Vector3(-0.5, 0.7, 0.5)
		await shot("look-default", Vector3(0.45, 1.75, -0.65), 54.25)

	main.grade.set_open(true)
	for i in 10:
		await process_frame
	await shot("look-panel", Vector3(0, 1.12, 4), 46.0)

	main.queue_free()
	await process_frame
	quit(0)


func _apply(text: String) -> void:
	var data = JSON.parse_string(text)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		print("[look] tune file not a dict")
		return
	var mat: ShaderMaterial = main.water_node.current_material()
	for key in data.keys():
		var v = data[key]
		if v is Array:
			if v.size() == 3:
				mat.set_shader_parameter(key, Vector3(float(v[0]), float(v[1]), float(v[2])))
			elif v.size() == 4:
				mat.set_shader_parameter(key, Color(float(v[0]), float(v[1]), float(v[2]), float(v[3])))
		elif v is String and v.begins_with("#"):
			mat.set_shader_parameter(key, Color(v))
		elif v is float or v is int or v is bool:
			mat.set_shader_parameter(key, v)
	print("[look] applied ", data.size(), " params")


func shot(label: String, target: Vector3, distance: float) -> void:
	main.cam.target = target
	main.cam.distance = distance
	main.cam.refresh()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(label + ".png")
	img.save_png(path)
	print("[look] ", label, " ", path, " open_water=", _sample(img))


## 开阔水域取样：左上与右下两块空白海面（避开建筑与 HUD），各取 9x9 均值。
func _sample(img: Image) -> String:
	var spots := [Vector2i(120, 120), Vector2i(img.get_width() - 140, 150),
		Vector2i(img.get_width() / 2, img.get_height() - 120)]
	var parts := PackedStringArray()
	for s in spots:
		var sum := Vector3.ZERO
		var n := 0
		for y in range(-5, 6):
			for x in range(-5, 6):
				var p: Vector2i = s + Vector2i(x, y)
				if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
					continue
				var c := img.get_pixel(p.x, p.y)
				sum += Vector3(c.r, c.g, c.b)
				n += 1
		var avg := sum / float(max(n, 1))
		parts.append("%d/%d/%d" % [roundi(avg.x * 255.0), roundi(avg.y * 255.0), roundi(avg.z * 255.0)])
	return " ".join(parts)
