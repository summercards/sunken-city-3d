extends SceneTree
## 决定性验证：那条斜线是「网格密度突变」还是「颜色计算」造成的。
##
##   SEA_SHOT_DIR=<目录> Godot --path godot --script res://tools/probe_seam_cause.gd
##
## 水面网格是正方形同心环（0.5 m 间距到 48 m 处骤增），等距投影后方框的四条边
## 就是斜线。若线由顶点位移在疏密不同的网格上插值而成，那么把位移归零后线会消失。

var main: Node
var out := ""
const FROZEN := 3.0


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
	main.cam.orbit_dir = Vector3(-0.30, 0.90, 0.32)
	main.cam.target = Vector3(-8, 1.12, 8)
	main.cam.distance = 34.0
	main.cam.refresh()
	for i in 12:
		await process_frame
	main.water_node.set_process(false)
	main.set_process(false)
	main.set_physics_process(false)

	var mat: ShaderMaterial = main.water_node.current_material()
	mat.set_shader_parameter("u_time", FROZEN)

	# 1) 原样
	await _shot("c1-normal")

	# 2) 顶点位移归零（波高 = 0）：网格曲率不连续就不存在了
	main.water_node.wave_scale = 0.0
	main.water_node._sync(mat)
	await _shot("c2-no-displacement")

	# 3) 位移归零 + 关掉所有贴图/反射：只剩纯体色
	main.water_node.wave_scale = 1.2
	main.water_node._sync(mat)
	var off := {
		"surface_normal_strength": 0.0, "refraction_strength": 0.0,
		"reflection_strength": 0.0, "relief_enabled": false,
		"glints_enabled": false, "ripples_enabled": false,
		"contact_foam_strength": 0.0, "sun_highlight_strength": 0.0,
	}
	for k in off:
		mat.set_shader_parameter(k, off[k])
	await _shot("c3-body-only")

	# 4) 只有位移，没有贴图：如果网格密度是元凶，这一张就还有线
	mat.set_shader_parameter("relief_enabled", true)
	await _shot("c4-displacement-relief-only")

	print("[cause] done")
	main.queue_free()
	await process_frame
	quit(0)


func _shot(label: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + ".png"))
	print("[cause] ", label)
