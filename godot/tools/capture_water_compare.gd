extends SceneTree
## 截「面板放大图」和「出厂 vs 内置预设」的同一机位水面对比。
##
## 用法：
##   SEA_SHOT_DIR=F:/wxgame/sea-work/tmp Godot --path godot \
##     --script res://tools/capture_water_compare.gd
##
## **不走面板套预设**：面板套用会写 `user://water.cfg`，跑一次就把玩家存档改了。
## 这里直接照 `WaterParams.builtin()` 的差异项往材质上设，跑完再按开机快照复原，
## 对存档零影响。面板本身只用来截「控件长什么样」。
##
## 面板图会按面板的全局矩形裁下来再放大 2 倍——1280x800 下的面板文字太小，
## 不放大根本看不清滑杆标签。

const Params = preload("res://src/rendering/water_params.gd")

var main: Node
var out_dir := ""
var mat: ShaderMaterial
var factory: Dictionary = {}


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

	mat = main.water_node.material_override as ShaderMaterial
	if mat == null:
		print("[cmp] FAIL 水面没有 ShaderMaterial")
		quit(1)
		return
	factory = _snapshot()

	await _shot("sea-factory.png")

	main.grade.set_open(true)
	main.grade.set_tab("water")
	for i in 10:
		await process_frame
	await _zoomed("panel-top-zoom.png", 2.0)

	# 光点组在中段偏下，按组名滚过去再截一张放大的。
	# 写死像素位置会被新加的组挤偏，滚到标题上方一点，正好让整组落在视野里。
	_scroll_to_group("水面光点")
	for i in 6:
		await process_frame
	await _zoomed("panel-glints-zoom.png", 2.0)

	main.grade.set_open(false)
	for i in 4:
		await process_frame

	var preset: Dictionary = Params.builtin("参考包初版")
	if preset.is_empty():
		print("[cmp] FAIL 拿不到内置预设「参考包初版」")
		quit(1)
		return
	_apply_preset(preset)
	for i in 12:
		await process_frame
	await _shot("sea-preset-reference.png")

	_apply(factory)
	for i in 12:
		await process_frame
	await _shot("sea-factory-restored.png")

	print("[cmp] builtin=", Params.builtin_names())
	print("[cmp] 复原后与出厂一致=", _diff_from_factory().is_empty(), " diff=", _diff_from_factory())
	print("[cmp] done out_dir=", out_dir)
	main.queue_free()
	await process_frame
	quit(0)


## 抓当前材质 + 节点属性的一份全量值，用来复原和对比。
func _snapshot() -> Dictionary:
	var snap := {}
	for g in Params.GROUPS:
		for r in g.rows:
			if r.kind == "node":
				snap[r.key] = main.water_node.get(r.key)
			else:
				snap[r.key] = mat.get_shader_parameter(r.key)
	return snap


func _apply(values: Dictionary) -> void:
	for k in values:
		if k == "wave_scale":
			main.water_node.wave_scale = float(values[k])
		else:
			mat.set_shader_parameter(k, values[k])


## 内置预设只记差异项，所以先复归出厂再叠差异——不然会残留上一次套用的值。
func _apply_preset(preset: Dictionary) -> void:
	_apply(factory)
	_apply(preset.values)


func _diff_from_factory() -> Dictionary:
	var now := _snapshot()
	var diff := {}
	for k in factory:
		if not now.has(k) or str(now[k]) != str(factory[k]):
			diff[k] = [factory.get(k), now.get(k)]
	return diff


func _shot(name: String, img_arg: Image = null) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = img_arg if img_arg != null else root.get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("[cmp] ", name, " -> ", err, " ", path)


## 按分组标题的文字滚过去——同一个名字的组标题是唯一稳定锚点。
func _scroll_to_group(title: String) -> void:
	var y := 0
	for c in main.grade._water_body.get_children():
		if c is Button and String((c as Button).text).contains(title):
			y = int((c as Control).position.y)
			break
	main.grade._water_scroll.scroll_vertical = maxi(0, y - 10)


## 把面板本身裁出来放大，滑杆标签才看得清。
func _zoomed(name: String, factor: float) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	# 面板根是 CanvasLayer，全局矩形要从里面的 PanelContainer 拿。
	var panel: Control = main.grade._panel
	var vp := root.get_visible_rect().size
	var scale := float(img.get_width()) / vp.x
	var rect := panel.get_global_rect()
	# 外扩几像素：面板矩形不含投影，贴着边裁会把右侧数值和底部提示切掉半行。
	var pad := 10.0
	var x0 := maxi(0, int((rect.position.x - pad) * scale))
	var y0 := maxi(0, int((rect.position.y - pad) * scale))
	var x1 := mini(img.get_width(), int((rect.position.x + rect.size.x + pad) * scale))
	var y1 := mini(img.get_height(), int((rect.position.y + rect.size.y + pad) * scale))
	var region := Rect2i(Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0))
	if region.size.x <= 0 or region.size.y <= 0:
		print("[cmp] FAIL 面板矩形为空 ", rect)
		return
	var crop := img.get_region(region)
	crop.resize(int(crop.get_width() * factor), int(crop.get_height() * factor),
		Image.INTERPOLATE_LANCZOS)
	await _shot(name, crop)
