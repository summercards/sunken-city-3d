extends SceneTree
## 在「能看见切边」的机位下，逐层求「该层贡献」，再检测贡献里有没有直线。
##
##   SEA_SHOT_DIR=<目录> Godot --path godot --script res://tools/probe_seam_layers.gd
##
## 做法：先把水面压到只剩体色（全关），拍一张底；再逐层单开，拍一张。
## 两张之差就是这一层的贡献，跟波浪动画无关（时间已冻结）。

var main: Node
var mat: ShaderMaterial
var out := ""
const FROZEN := 3.0
## 全关状态：只剩体色（床面透射 + 深水色）。
const OFF := {
	"surface_normal_strength": 0.0,
	"refraction_strength": 0.0,
	"reflection_strength": 0.0,
	"relief_enabled": false,
	"glints_enabled": false,
	"ripples_enabled": false,
	"contact_foam_strength": 0.0,
	"sun_highlight_strength": 0.0,
	"dither_strength": 0.0,
}
## 每层单开时要恢复的值（与 water.tres 出厂一致）。
const LAYER := {
	"normal": {"surface_normal_strength": 0.56},
	"refraction": {"refraction_strength": 15.5},
	"reflection": {"reflection_strength": 1.0, "sun_highlight_strength": 0.19},
	"relief": {"relief_enabled": true},
	"glints": {"glints_enabled": true},
	"ripples": {"ripples_enabled": true},
	"contact": {"contact_foam_strength": 0.83},
	"dither": {"dither_strength": 1.0},
}


func _init() -> void:
	out = OS.get_environment("SEA_SHOT_DIR")
	if out == "":
		out = "user://"
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
	# 用户截图那个机位：贴水面斜视、建筑在右上、大片开阔水在左与下。
	main.cam.orbit_dir = Vector3(-0.30, 0.90, 0.32)
	main.cam.target = Vector3(-8, 1.12, 8)
	main.cam.distance = 34.0
	main.cam.refresh()
	for i in 12:
		await process_frame

	mat = main.water_node.current_material()
	# 时钟有两个写入者：水面自己的 `update_surface`，以及 `main.gd` 每帧写 `_t`。
	# 只停水面那一处不够 —— 主循环会把冻结值覆盖掉，两次抓图就落在不同相位上，
	# 差异里全是波浪位移，看不到静态接缝。
	main.water_node.set_process(false)
	main.set_process(false)
	main.set_physics_process(false)

	for key in OFF:
		mat.set_shader_parameter(key, OFF[key])
	await _shot("base")

	for layer in LAYER:
		for key in OFF:
			mat.set_shader_parameter(key, OFF[key])
		for key in LAYER[layer]:
			mat.set_shader_parameter(key, LAYER[layer][key])
		await _shot(layer)

	print("[seam] done dir=", out)
	main.queue_free()
	await process_frame
	quit(0)


func _shot(label: String) -> void:
	for i in 8:
		mat.set_shader_parameter("u_time", FROZEN)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + ".png"))
	print("[seam] ", label)
