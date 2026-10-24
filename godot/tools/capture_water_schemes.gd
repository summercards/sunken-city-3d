extends SceneTree
## 两套水的同机位对比，以及吸收式那套的面板。
##
## 用法：
##   SEA_SHOT_DIR=F:/wxgame/sea-work/tmp Godot --path godot \
##     --script res://tools/capture_water_schemes.gd
##
## 走面板的 `set_water_scheme()` 而不是直接换材质，这样顺带验证「切换后控件
## 重建、值跟着换」这条链路。跑完切回原版，`water.cfg` 里的方案字段也回到原样。

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
	for i in 90:
		await process_frame

	if main.grade == null or main.water_node == null:
		print("[schemes] FAIL 场景里没有面板或水面节点")
		quit(1)
		return

	await _shot("scheme-original.png")

	main.grade.set_open(true)
	main.grade.set_tab("water")
	for i in 8:
		await process_frame
	await _shot("scheme-original-panel.png")

	main.grade.set_water_scheme("absorption")
	for i in 20:
		await process_frame
	print("[schemes] 当前方案=", main.water_node.scheme,
		" 材质=", main.water_node.current_material().shader.resource_path.get_file(),
		" 控件数=", main.grade._order.size())
	await _shot("scheme-absorption-panel.png")
	await _zoomed("scheme-absorption-panel-zoom.png", 2.0)

	main.grade.set_open(false)
	for i in 20:
		await process_frame
	await _shot("scheme-absorption.png")

	main.grade.set_water_scheme("original")
	for i in 20:
		await process_frame
	await _shot("scheme-original-restored.png")
	print("[schemes] 复原后方案=", main.water_node.scheme,
		" 控件数=", main.grade._order.size())

	print("[schemes] done out_dir=", out_dir)
	main.queue_free()
	await process_frame
	quit(0)


func _shot(name: String, img_arg: Image = null) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = img_arg if img_arg != null else root.get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("[schemes] ", name, " -> ", err, " ", path)


## 面板按 `_panel` 的全局矩形裁下来放大，8 px 的标签才看得清。
func _zoomed(name: String, factor: float) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var panel: Control = main.grade._panel
	var vp := root.get_visible_rect().size
	var scale := float(img.get_width()) / vp.x
	var rect := panel.get_global_rect()
	var pad := 10.0
	var x0 := maxi(0, int((rect.position.x - pad) * scale))
	var y0 := maxi(0, int((rect.position.y - pad) * scale))
	var x1 := mini(img.get_width(), int((rect.position.x + rect.size.x + pad) * scale))
	var y1 := mini(img.get_height(), int((rect.position.y + rect.size.y + pad) * scale))
	var crop := img.get_region(Rect2i(Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0)))
	crop.resize(int(crop.get_width() * factor), int(crop.get_height() * factor),
		Image.INTERPOLATE_LANCZOS)
	await _shot(name, crop)
