extends SceneTree
## 量 emission_gain 用的探针：在某个后端上扫一遍增益并逐档出图。
##
## 用法（同一个机位跑两遍，再比开阔水面像素均值）：
##   SEA_SHOT_DIR=<dir> Godot --path godot --resolution 1440x900 \
##     --script res://tools/capture_water_gain_probe.gd
##   SEA_SHOT_DIR=<dir-gl> Godot --path godot --rendering-driver opengl3 \
##     --resolution 1440x900 --script res://tools/capture_water_gain_probe.gd
##
## 图里只有世界、没有面板，机位与帧数固定，两份可以直接逐像素比。
## `RenderFlagsLib.water_emission_gain()` 的系数就是这么拟合出来的，
## 着色器发光量级一变就得重跑一遍（过程见
## docs/development/2026-10-24_water_backend_parity.md）。
##
## SEA_GAINS 可覆盖扫描档位，逗号分隔，例如 SEA_GAINS=1.2,1.26,1.32；
## 逐通道写 "r/g/b"，例如 SEA_GAINS=2.6/2.8/2.0。
## SEA_SCHEME 选水面方案（original / absorption），两套的发光量级不同，各拟合各的。

var main: Node
var mat: ShaderMaterial
var out_dir := ""
var scheme := "original"
var gains := [1.0, 0.6, 0.9, 1.2, 1.26, 1.32, 1.6, 2.2, 3.8]


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var custom := OS.get_environment("SEA_GAINS")
	if custom != "":
		gains = []
		for part in custom.split(","):
			var item := part.strip_edges()
			if item == "":
				continue
			# "2.6/2.8/2.0" 逐通道；单个数字三通道同值。
			if item.contains("/"):
				var xyz := item.split("/")
				if xyz.size() != 3:
					print("[gain-probe] 跳过非法三通道写法：", item)
					continue
				gains.append(Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])))
			else:
				gains.append(float(item))
	# 两套水面各拟合各的：吸收式的发光量级和原版不同，系数不能互借。
	var wanted := OS.get_environment("SEA_SCHEME")
	if wanted != "":
		scheme = wanted
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# 岸线图建完、波场稳定后再开始，两遍的时序才一致。
	for i in 90:
		await process_frame

	# 走 use_scheme() 而不是面板：面板切方案会写 user://water.cfg。
	if scheme != "original":
		if not main.water_node.use_scheme(scheme):
			print("[gain-probe] FAIL 没有方案 ", scheme)
			quit(1)
			return
		for i in 6:
			await process_frame
	mat = main.water_node.current_material()
	if mat == null:
		print("[gain-probe] FAIL 水面没有 ShaderMaterial")
		quit(1)
		return

	var method: String = RenderingServer.get_current_rendering_method()
	print("[gain-probe] method=", method, " scheme=", scheme, " size=", root.get_visible_rect().size)
	for g in gains:
		var v: Vector3 = _as_gain(g)
		mat.set_shader_parameter("emission_gain", v)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/gain-%s.png" % [out_dir, _label(v)]
		root.get_texture().get_image().save_png(path)
		print("[gain-probe] ", path)
	quit(0)


## 单个标量按三通道同值；"r/g/b" 形式的字符串按逐通道。
func _as_gain(g: Variant) -> Vector3:
	if g is Vector3:
		return g
	var v: float = float(g)
	return Vector3(v, v, v)


func _label(v: Vector3) -> String:
	if is_equal_approx(v.x, v.y) and is_equal_approx(v.y, v.z):
		return str(v.x)
	return "%s_%s_%s" % [str(v.x), str(v.y), str(v.z)]
