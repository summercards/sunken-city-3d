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
## SEA_GAINS 可覆盖扫描档位，逗号分隔，例如 SEA_GAINS=1.2,1.26,1.32。

var main: Node
var mat: ShaderMaterial
var out_dir := ""
var gains := [1.0, 0.6, 0.9, 1.2, 1.26, 1.32, 1.6, 2.2, 3.8]


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var custom := OS.get_environment("SEA_GAINS")
	if custom != "":
		gains = []
		for part in custom.split(","):
			if part.strip_edges() != "":
				gains.append(float(part))
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# 岸线图建完、波场稳定后再开始，两遍的时序才一致。
	for i in 90:
		await process_frame

	mat = main.water_node.material_override as ShaderMaterial
	if mat == null:
		print("[gain-probe] FAIL 水面没有 ShaderMaterial")
		quit(1)
		return

	var method: String = RenderingServer.get_current_rendering_method()
	print("[gain-probe] method=", method, " size=", root.get_visible_rect().size)
	for g in gains:
		var v: float = float(g)
		mat.set_shader_parameter("emission_gain", Vector3(v, v, v))
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/gain-%s.png" % [out_dir, str(v)]
		root.get_texture().get_image().save_png(path)
		print("[gain-probe] ", path)
	quit(0)
