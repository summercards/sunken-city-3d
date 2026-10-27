extends SceneTree
## 统计开阔水面的亮度起伏，只算「整格都是水」的格子。
##
##   Godot --path godot --script res://tools/probe_water_stats.gd
##
## 为什么单独一个脚本：用整幅画面求均值会把建筑、白沫、阴影一起算进去，
## 量出来的标准差是水面的两倍以上（实测 9.5 对真实的 5.0），据此调参数
## 会一路调过头。这里按 32×32 网格只保留 100% 落在水体色域里的格子。

const CELL := 32
## 水体色域（8 bit）。与参考帧的开阔水面同域：红压到近 0，绿 95~160，蓝 140~190。
const LO := Vector3(0.0, 95.0, 140.0)
const HI := Vector3(60.0, 170.0, 200.0)

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 60:
		await process_frame
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()
	main.cam.orbit_dir = Vector3(-0.28, 0.86, 0.43)
	main.cam.target = Vector3(0, 1.12, 4)

	var tune := OS.get_environment("SEA_TUNE")
	if tune != "" and FileAccess.file_exists(tune):
		var data = JSON.parse_string(FileAccess.get_file_as_string(tune))
		if data is Dictionary:
			var mat: ShaderMaterial = main.water_node.current_material()
			for key in data.keys():
				var v = data[key]
				if v is Array and v.size() == 3:
					mat.set_shader_parameter(key, Vector3(float(v[0]), float(v[1]), float(v[2])))
				elif v is float or v is int or v is bool:
					mat.set_shader_parameter(key, v)

	var label := OS.get_environment("SEA_LABEL")
	if label == "":
		label = "current"
	for spec in [46.0, 78.0]:
		await _measure(int(spec), label)
	main.queue_free()
	await process_frame
	quit(0)


func _measure(distance: int, label: String) -> void:
	main.cam.distance = float(distance)
	main.cam.refresh()
	for i in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()

	var gs := PackedFloat32Array()
	var cells := 0
	for y in range(0, h - CELL, CELL):
		for x in range(0, w - CELL, CELL):
			var all := true
			for yy in range(y, y + CELL, 4):
				for xx in range(x, x + CELL, 4):
					var c := img.get_pixel(xx, yy)
					var v := Vector3(c.r * 255.0, c.g * 255.0, c.b * 255.0)
					if v.x < LO.x or v.y < LO.y or v.z < LO.z or v.x > HI.x or v.y > HI.y or v.z > HI.z:
						all = false
						break
				if not all:
					break
			if not all:
				continue
			cells += 1
			for yy in range(y, y + CELL):
				for xx in range(x, x + CELL):
					gs.append(img.get_pixel(xx, yy).g * 255.0)

	if gs.is_empty():
		print("[stats] %s d=%d  没有纯水格" % [label, distance])
		return
	var sum := 0.0
	for v in gs:
		sum += v
	var mean := sum / float(gs.size())
	var var_sum := 0.0
	for v in gs:
		var_sum += (v - mean) * (v - mean)
	var sd := sqrt(var_sum / float(gs.size()))
	var sorted := Array(gs)
	sorted.sort()
	var p5: float = sorted[int(sorted.size() * 0.05)]
	var p95: float = sorted[int(sorted.size() * 0.95)]
	print("[stats] %-10s d=%-3d cells=%-4d meanG=%6.2f std=%5.2f p5=%3.0f p95=%3.0f"
		% [label, distance, cells, mean, sd, p5, p95])
