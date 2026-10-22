extends SceneTree
## 绕序探针：拿两个已知绕序的四边面，问 Godot 到底认哪边是正面。
##
## 左块 = glTF 规范的逆时针（three.js 正面）；右块 = 索引对调（顺时针）。
## 两个块的法线都朝 +Z（朝向相机）。三种画法各截一张：
##   cull_back（默认剔除）、cull_disabled（两面都画）、facing（正面绿/背面红）。
##
## 结论只看"哪一块在 cull_back 下还看得见" —— 那一块就是 Godot 的正面。
##
## 用法：Godot --path . --script res://tools/winding_probe.gd

func _init() -> void:
	_run()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4.2)
	cam.fov = 50
	world.add_child(cam)
	cam.current = true

	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.05, 0.06, 0.08)
	# 环境光必须给：underwater_culled 只写 ALBEDO，没有灯就是纯黑，
	# 黑块贴在近黑背景上根本看不出「可见/消失」，探针会失去意义。
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(1, 1, 1)
	sky.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = sky
	world.add_child(we)

	var packed: PackedScene = load("res://assets/models/debug/quad_test.glb")
	print("[probe] packed=", packed)
	var inst := packed.instantiate()
	world.add_child(inst)
	_dump(inst, 0)

	var solid := ShaderMaterial.new()
	solid.shader = load("res://shaders/underwater_culled.gdshader")
	solid.set_shader_parameter("albedo_color", Color(0.95, 0.95, 0.9))
	solid.set_shader_parameter("caustic_gain", 0.0)
	solid.set_shader_parameter("water_level", -1000.0)  # 关掉深度衰减，别把方块压黑

	var facing := ShaderMaterial.new()
	facing.shader = load("res://shaders/uw_facing_debug.gdshader")

	for spec in [["cull_back", solid], ["facing", facing]]:
		var tag: String = spec[0]
		_apply(inst, spec[1])
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var out := ProjectSettings.globalize_path("res://outputs/probe-winding-%s.png" % tag)
		img.save_png(out)
		print("[probe] ", tag, " → ", out)

	quit()


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		print("[probe] ", pad, node.name, " surfaces=", mi.mesh.get_surface_count(), " aabb=", mi.get_aabb(), " vis=", mi.visible)
	else:
		print("[probe] ", pad, node.name, " <", node.get_class(), ">")
	for c in node.get_children():
		_dump(c, depth + 1)


func _apply(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
	for c in node.get_children():
		_apply(c, mat)
