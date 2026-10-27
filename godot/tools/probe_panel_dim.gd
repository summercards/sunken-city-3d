extends SceneTree
## 量 P 面板打开时画面是否真的被压暗。
##
##   Godot --path godot --script res://tools/probe_panel_dim.gd
##
## 输出同一机位下面板关闭 / 打开两次的同一批像素，以及 HUD 背板的可见性与强度。

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 60:
		await process_frame
	# 不能 hide HUD：背板就在 HUD 这个 CanvasLayer 下面，隐藏 HUD 等于把要测的东西
	# 一起藏掉，量出来永远是「没有变化」。只藏标注与航线，采样点选在 HUD 空白处。
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()
	main.cam.orbit_dir = Vector3(-0.28, 0.86, 0.43)
	main.cam.target = Vector3(6, 1.12, 10)
	main.cam.distance = 46.0
	main.cam.refresh()
	for i in 12:
		await process_frame

	print("[dim] backdrop node=", main.hud._backdrop != null,
		" visible=", main.hud._backdrop.visible)
	await _report("closed")

	main.grade.set_open(true)
	for i in 20:
		await process_frame
	print("[dim] backdrop visible=", main.hud._backdrop.visible,
		" strength=", _strength(),
		" external_modal=", main.hud._external_modal,
		" grade_layer=", main.grade.layer, " hud_layer=", main.hud.layer)
	await _report("open")

	main.grade.set_open(false)
	for i in 20:
		await process_frame
	await _report("closed2")

	# 回归：普通卡片（背包）必须仍然压暗。把调色面板排除掉，不能让所有面板一起失去遮罩。
	main.hud.open_tab("bag")
	for i in 20:
		await process_frame
	print("[dim] bag backdrop visible=", main.hud._backdrop.visible,
		" strength=", _strength())
	await _report("bag")
	main.hud.close_card()
	for i in 10:
		await process_frame

	quit(0)


func _strength() -> Variant:
	var mat: ShaderMaterial = main.hud._backdrop.material
	if mat == null:
		return -1.0
	return mat.get_shader_parameter("strength")


## 取四块开阔水面的均值，全部避开左侧面板区域（面板在 x<400、y>92）。
func _report(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var spots := [Vector2i(1250, 120), Vector2i(1250, 700), Vector2i(700, 900), Vector2i(100, 900)]
	var parts := PackedStringArray()
	for s in spots:
		var sum := Vector3.ZERO
		var n := 0
		for y in range(-4, 5):
			for x in range(-4, 5):
				var p: Vector2i = s + Vector2i(x, y)
				var c := img.get_pixel(p.x, p.y)
				sum += Vector3(c.r, c.g, c.b)
				n += 1
		var avg := sum / float(n)
		parts.append("%d/%d/%d" % [roundi(avg.x * 255.0), roundi(avg.y * 255.0), roundi(avg.z * 255.0)])
	print("[dim] ", label, " ", "  ".join(parts))
