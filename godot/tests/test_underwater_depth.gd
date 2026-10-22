extends SceneTree
const Materials = preload("res://scripts/world/uw_materials.gd")
## GPU 回归：同一网格先提交近处红面，再提交远处蓝面，近面必须遮住远面。
## 需真实渲染器运行（不能用 --headless）。
## Godot --path godot --script res://tests/test_underwater_depth.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[uw-depth] requires a real renderer")
		quit(2)
		return
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 0, 5)
	cam.current = true

	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	for z in [0.0, -2.0]:
		for p in [Vector2(-2, -2), Vector2(2, 2), Vector2(2, -2),
				Vector2(-2, -2), Vector2(-2, 2), Vector2(2, 2)]:
			vertices.append(Vector3(p.x, p.y, z))
			colors.append(Color.RED if z == 0.0 else Color.BLUE)
			normals.append(Vector3(0, 0, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	world.add_child(mi)
	var failures := 0
	# 缓存不能合并不同透明度；晚创建材质必须继承当前深度和冻结时间。
	Materials.set_depth(200.0)
	Materials.freeze_time(3.0)
	var faint := Materials.get_material({"alpha": true, "opacity": 0.2})
	var dense := Materials.get_material({"alpha": true, "opacity": 0.8})
	var cache_ok: bool = faint != dense and is_equal_approx(
		float(faint.get_shader_parameter("alpha")), 0.2)
	cache_ok = cache_ok and dense.get_shader_parameter("dive_depth") == 200.0
	cache_ok = cache_ok and dense.get_shader_parameter("time_override") == 3.0
	print("[uw-depth] opacity_cache_and_late_state ", "PASS" if cache_ok else "FAIL")
	if not cache_ok:
		failures += 1
	Materials.set_depth(10.0)
	for shader_name in ["underwater", "underwater_culled"]:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/%s.gdshader" % shader_name)
		mat.set_shader_parameter("use_vertex_color", true)
		mat.set_shader_parameter("caustic_gain", 0.0)
		mat.set_shader_parameter("time_override", 3.0)
		mi.material_override = mat
		for x in [-0.5, 0.0, 0.5]:
			cam.position.x = x
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			var ok := c.r > c.b + 0.2
			print("[uw-depth] %s camera_x=%.1f color=%s %s" % [
				shader_name, x, c, "PASS" if ok else "FAIL"])
			if not ok:
				failures += 1
	# 真透明物体在实体后面时仍须被遮挡；两个透明变体都必须成功编译。
	for shader_name in ["underwater_alpha", "underwater_alpha_culled"]:
		var behind := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(4, 4)
		behind.mesh = quad
		behind.position.z = -1.0
		var transparent := ShaderMaterial.new()
		transparent.shader = load("res://shaders/%s.gdshader" % shader_name)
		transparent.set_shader_parameter("albedo_color", Color.BLUE)
		transparent.set_shader_parameter("alpha", 0.8)
		behind.material_override = transparent
		world.add_child(behind)
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		var ok := c.r > c.b + 0.2
		print("[uw-depth] transparent_behind_%s %s" % [shader_name, "PASS" if ok else "FAIL"])
		if not ok:
			failures += 1
		behind.queue_free()
		await process_frame
	# 双面薄片在同样的正面照明下，两侧应一样亮。引擎会翻转背面 NORMAL。
	mi.mesh = QuadMesh.new()
	mi.mesh.size = Vector2(4, 4)
	var dual := ShaderMaterial.new()
	dual.shader = load("res://shaders/underwater.gdshader")
	dual.set_shader_parameter("caustic_gain", 0.0)
	mi.material_override = dual
	env.ambient_light_energy = 0.0
	var light := DirectionalLight3D.new()
	world.add_child(light)
	var brightness: Array[float] = []
	for side in [1.0, -1.0]:
		cam.position = Vector3(0, 0, 5 * side)
		cam.look_at(Vector3.ZERO)
		light.basis = cam.basis
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		brightness.append(c.r)
	var two_sides_ok := brightness[0] > 0.2 and absf(brightness[0] - brightness[1]) < 0.05
	print("[uw-depth] double_sided_lighting ", brightness, " ", "PASS" if two_sides_ok else "FAIL")
	if not two_sides_ok:
		failures += 1
	world.queue_free()
	await process_frame
	Materials.clear_cache()
	quit(1 if failures else 0)
