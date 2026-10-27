extends SceneTree
## 复现「水面出现直线切边」的机位，用于改前/改后的 A/B。
##
##   SEA_TAG=before SEA_SHOT_DIR=<目录> Godot --path godot \
##     --script res://tools/probe_seam_shot.gd
##
## 机位按用户截图还原：等距斜视、贴着建筑侧面、水面占大半画面。
## 时间冻结，保证两次抓的是同一帧。

var main: Node
var out_dir := ""
var mat: ShaderMaterial
var tag := "shot"
const FROZEN := 3.0


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	tag = OS.get_environment("SEA_TAG")
	if tag == "":
		tag = "shot"
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
	# 低俯角、近距：屏幕上会出现大面积的 44 m 等厚度线。
	main.cam.orbit_dir = Vector3(-0.44, 0.46, 0.52)
	main.cam.target = Vector3(-4, 1.12, 4)
	main.cam.distance = 30.0
	main.cam.refresh()
	for i in 12:
		await process_frame
	mat = main.water_node.current_material()
	main.water_node.set_process(false)

	await _shot("seam-a")
	main.cam.orbit_dir = Vector3(-0.30, 0.90, 0.32)
	main.cam.target = Vector3(-8, 1.12, 8)
	main.cam.distance = 34.0
	main.cam.refresh()
	await _shot("seam-b")

	main.queue_free()
	await process_frame
	quit(0)


func _shot(label: String) -> void:
	for i in 10:
		mat.set_shader_parameter("u_time", FROZEN)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("%s-%s.png" % [label, tag]))
	print("[seam] ", label, " ", tag)
