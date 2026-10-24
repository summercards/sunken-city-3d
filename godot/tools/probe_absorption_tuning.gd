extends SceneTree
## 吸收式的出厂值扫描：同一机位、只改吸收参数，拍一组图回来挑。
##
## 用法：
##   SEA_SHOT_DIR=F:/wxgame/sea-work/tmp Godot --path godot \
##     --script res://tools/probe_absorption_tuning.gd [轮次]
##
## 存在的理由：吸收式把屏幕色当作体色来源，`depth_distance` 一开就吃掉水下的
## 沉没城市。这个探针一次跑完几档，肉眼对比「有纵深」和「看得见废墟」。

## 每档只写列出的参数，其余保持资源里的出厂值。
const ROUND_1 := [
	{"tag": "a-current", "p": {
		"depth_distance": 3.5, "beers_law": 5.5, "deep_darkness": 0.6,
		"absorption_color": Color(1.0, 0.55, 0.3)}},
	{"tag": "b-8-3", "p": {
		"depth_distance": 8.0, "beers_law": 3.0, "deep_darkness": 0.75,
		"absorption_color": Color(1.0, 0.55, 0.3)}},
	{"tag": "c-14-22", "p": {
		"depth_distance": 14.0, "beers_law": 2.2, "deep_darkness": 0.8,
		"absorption_color": Color(1.0, 0.5, 0.25)}},
	{"tag": "d-22-15", "p": {
		"depth_distance": 22.0, "beers_law": 1.5, "deep_darkness": 0.85,
		"absorption_color": Color(1.0, 0.45, 0.2)}},
]

## 第二轮：在 c 附近调远景亮度与菲涅尔。
const ROUND_2 := [
	{"tag": "c1-dark07", "p": {
		"depth_distance": 14.0, "beers_law": 2.2, "deep_darkness": 0.7,
		"absorption_color": Color(1.0, 0.5, 0.25), "screen_gain": 0.85,
		"fresnel_strength": 0.35}},
	{"tag": "c2-fresnel", "p": {
		"depth_distance": 14.0, "beers_law": 2.2, "deep_darkness": 0.7,
		"absorption_color": Color(1.0, 0.5, 0.25), "screen_gain": 0.85,
		"fresnel_strength": 0.22, "fresnel_radius": 6.0}},
	{"tag": "c3-dark065", "p": {
		"depth_distance": 14.0, "beers_law": 2.2, "deep_darkness": 0.65,
		"absorption_color": Color(1.0, 0.45, 0.2), "screen_gain": 0.9,
		"fresnel_strength": 0.25, "fresnel_radius": 6.0}},
	{"tag": "c4-dd18", "p": {
		"depth_distance": 18.0, "beers_law": 2.0, "deep_darkness": 0.65,
		"absorption_color": Color(1.0, 0.45, 0.2), "screen_gain": 0.9,
		"fresnel_strength": 0.25, "fresnel_radius": 6.0}},
]

var main: Node
var out_dir := ""
var combos: Array = ROUND_1


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var which := OS.get_environment("SEA_TUNE_ROUND")
	if which == "2":
		combos = ROUND_2
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 90:
		await process_frame

	await _shot("tune-original.png")

	main.grade.set_water_scheme("absorption")
	main.grade.set_open(false)
	for i in 20:
		await process_frame

	var mat: ShaderMaterial = main.water_node.current_material()
	for combo in combos:
		for key in combo["p"]:
			mat.set_shader_parameter(key, combo["p"][key])
		for i in 12:
			await process_frame
		await _shot("tune-%s.png" % combo["tag"])
		print("[tune] ", combo["tag"], " done")

	main.queue_free()
	await process_frame
	quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	print("[tune] ", name, " -> ", img.save_png(out_dir.path_join(name)))
