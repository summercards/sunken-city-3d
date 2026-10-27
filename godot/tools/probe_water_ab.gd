extends SceneTree
## 冻结时间做 A/B：同一帧，只改一个参数。
##
##   SEA_SHOT_DIR=<目录> Godot --path godot --script res://tools/probe_water_ab.gd
##
## 水面每帧都在动，两次截图若不在同一 `u_time`，差异里全是波浪位移，
## 定位不到静态的贴图接缝。这里把 `u_time` 钉死再比。

var main: Node
var out_dir := ""
var mat: ShaderMaterial
const FROZEN := 3.0


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
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
	# 近水面俯视：贴图密度最高，接缝最容易看出来。
	main.cam.orbit_dir = Vector3(-0.30, 0.90, 0.32)
	main.cam.target = Vector3(-8, 1.12, 8)
	main.cam.distance = 34.0
	main.cam.refresh()
	for i in 12:
		await process_frame

	mat = main.water_node.current_material()
	# 停掉水面自己的时钟，之后每帧都把它写回同一个值。
	main.water_node.set_process(false)
	_freeze()

	await _shot("a0-baseline")

	await _shot("a1-no-ripple", {"ripples_enabled": false})
	await _shot("a2-no-normal", {"ripples_enabled": true, "surface_normal_strength": 0.0})
	await _shot("a3-no-refraction", {"surface_normal_strength": 0.56, "refraction_strength": 0.0})
	await _shot("a4-ripple-only",
		{"refraction_strength": 15.5, "surface_normal_strength": 0.0,
		"reflection_strength": 0.0, "relief_enabled": false, "glints_enabled": false,
		"contact_foam_strength": 0.0, "ripple_color": Color(1, 1, 1, 1)})
	await _shot("a5-ripple-only-wide",
		{"ripple_scale": 1.0, "ripple_tile_metres": Vector2(24.0, 18.0)})

	main.queue_free()
	await process_frame
	quit(0)


func _freeze() -> void:
	mat.set_shader_parameter("u_time", FROZEN)


func _shot(label: String, params := {}) -> void:
	for key in params:
		mat.set_shader_parameter(key, params[key])
	for i in 8:
		_freeze()
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(label + ".png"))
	print("[ab] ", label)
