extends SceneTree
## 抓「世界浮层纯文字」：资源行、上岸点名称、潜水状态，用来人眼核对
## 字号是否够大、有没有勾边。
##
## 用法：
##   SEA_SHOT_DIR=<dir> Godot --path godot --script res://tools/capture_world_text.gd

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
	var economy: Node = root.get_node("Economy")
	economy.give({"fish": 6, "vegetable": 8, "shell": 8})
	for i in 90:
		await process_frame

	var font: Font = main.hud._font
	for entry in [["资源常驻行", main.hud._res_label], ["潜水状态", main.hud._dive_status], ["视野提示", main.hud._zoom]]:
		var l: Label = entry[1]
		print("[world-text] %s fs=%d text='%s'" % [entry[0], l.get_theme_font_size("font_size"), l.text])
	print("[world-text] 上岸点名称 fs=%d" % (22 * 2 * 0.60))

	# 保持默认镜头：资源行平时就在下方的水面上。
	main.hud._dive_status.text = "氧气 86% · 水深 12m · 头灯开 · 发现 2/5"
	main.hud._dive_status.show()
	main.hud.note_zoom(1.25)
	for i in 30:
		await process_frame

	await _shot("world-text-surface")

	# 换个朝向，让资源行落在开阔水面上：字形细节（圆润、字重、无勾边）
	# 在白灯塔前面看不出来。
	var cam: Node = main.get_node_or_null("Camera")
	if cam == null:
		for c in main.get_children():
			if c is Camera3D:
				cam = c
				break
	if cam is Camera3D:
		cam.global_position = cam.global_position + Vector3(-18, 0, -18)
		cam.look_at(Vector3(0, 2, 6), Vector3.UP)
		main.hud.note_zoom(1.25)
		for i in 30:
			await process_frame
		await _shot("world-text-surface-clear")

	# 上岸点标签：走到最近的上岸点附近，让标签进画面。
	var marker: Node = main.landing_markers if main.get("landing_markers") != null else main.get_node_or_null("LandingMarkers")
	for i in 20:
		await process_frame
	await _shot("world-text-markers")
	print("[world-text] done out_dir=", out_dir)
	quit(0)


func _shot(tag: String) -> void:
	await create_timer(0.4, true).timeout
	RenderingServer.force_draw(false)
	var img: Image = root.get_texture().get_image()
	var path := out_dir.path_join(tag + ".png")
	img.save_png(path)
	print("[world-text] saved ", path)
