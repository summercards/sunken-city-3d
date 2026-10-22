extends SceneTree
## 单栋楼剔除探针：把某个 glb 单独摆出来，用同一台相机分别按
## 「cull_back（单面）」和「cull_disabled（双面）」各截一张。
##
## 判读：如果单面那张里墙面消失、只剩楼板和内墙，说明这个 glb 的绕序
## 在 Godot 里是反的（正面朝内）；如果两张一样，说明绕序正常，
## 之前看到的「碎」来自别的东西（材质、深度、装饰件本身）。
##
## 用法：Godot --path . --script res://tools/unit_cull_probe.gd -- <glb 相对路径>

func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var rel: String = args[0] if args.size() > 0 else "assets/models/underwater/neighborhood/units/house_00.glb"

	var world := Node3D.new()
	root.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.30
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var packed: PackedScene = load("res://" + rel)
	var inst := packed.instantiate()
	world.add_child(inst)

	# 只框楼身：往下 42m 的基座会把取景拉得很远。
	var box := AABB()
	var first := true
	for mi in _meshes(inst):
		var b: AABB = mi.global_transform * mi.get_aabb()
		var bb := AABB(b.position, b.size)
		# 低于 -6m 的部分（基座）不参与取景
		if bb.position.y + bb.size.y < -6.0:
			continue
		box = bb if first else box.merge(bb)
		first = false
	if first:
		for mi in _meshes(inst):
			box = mi.get_aabb() if first else box.merge(mi.get_aabb())
			first = false
	# 取景只压楼身上半段（基座是一根 42m 的柱子，会把相机推得很远）。
	var top := box.position.y + box.size.y
	var center := Vector3(box.get_center().x, top - minf(box.size.y * 0.28, 9.0), box.get_center().z)
	var radius := maxf(maxf(box.size.x, box.size.z) * 0.62, 3.0)
	print("[unit] ", rel, " box=", box, " r=", "%.2f" % radius)

	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.current = true
	var dir := Vector3(0.45, 0.5, 1.0).normalized()
	cam.position = center + dir * radius * 2.0
	cam.look_at(center, Vector3.UP)

	# 三种画法：正面绿/背面红（定方向）、单面标准材质、双面标准材质。
	var facing := ShaderMaterial.new()
	facing.shader = load("res://shaders/uw_facing_debug.gdshader")

	var single := StandardMaterial3D.new()
	single.albedo_color = Color(0.62, 0.58, 0.52)
	single.roughness = 1.0
	single.cull_mode = BaseMaterial3D.CULL_BACK

	var dual := StandardMaterial3D.new()
	dual.albedo_color = Color(0.62, 0.58, 0.52)
	dual.roughness = 1.0
	dual.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 第四种：游戏里真正用的水下材质（单面变体）。用来分清
	# 「看起来发虚/透」是几何问题还是这个着色器算出来的。
	var uw := ShaderMaterial.new()
	uw.shader = load("res://shaders/underwater_culled.gdshader")
	uw.set_shader_parameter("albedo_color", Color(0.62, 0.58, 0.52))
	uw.set_shader_parameter("caustic_gain", 0.0)
	uw.set_shader_parameter("dive_depth", 20.0)

	var key := DirectionalLight3D.new()
	key.light_energy = 0.75
	key.rotation_degrees = Vector3(-38, 28, 0)
	world.add_child(key)

	var tag := rel.get_file().get_basename()
	for spec in [["facing", facing], ["single", single], ["double", dual], ["uw", uw]]:
		_apply(inst, spec[1])
		for t in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var out := ProjectSettings.globalize_path("res://outputs/probe-unit-%s-%s.png" % [tag, spec[0]])
		img.save_png(out)
		# 覆盖率对「单/双面」不敏感（剪影一样），所以 facing 那张必须分开数绿/红：
		# 绿 = 正面朝向相机，红 = 背面。红占多数 ⇒ 这个单元的绕序反了。
		var st := _facing_stats(img)
		print("[unit] %s %s cover=%.4f green=%.3f red=%.3f" % [
			tag, spec[0], st["cover"], st["green"], st["red"]])

	quit()


## 统计非背景像素比例，以及其中「绿（正面）/ 红（背面）」的占比。
func _facing_stats(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var step := maxi(1, int(float(w) / 240.0))
	var n := 0
	var hit := 0
	var green := 0
	var red := 0
	var bg := Color(0.04, 0.05, 0.07)
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			n += 1
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.08:
				hit += 1
				if c.g > c.r + 0.12:
					green += 1
				elif c.r > c.g + 0.12:
					red += 1
			x += step
		y += step
	var face_total := maxi(1, green + red)
	return {
		"cover": 0.0 if n == 0 else float(hit) / float(n),
		"green": float(green) / float(face_total),
		"red": float(red) / float(face_total),
	}


func _meshes(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


func _apply(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		# 必须用 material_override：glb 导入的实例把材质挂在 material_override 上，
		# set_surface_override_material 会被它盖掉，探针会「三种画法一模一样」。
		mi.material_override = mat
	for c in node.get_children():
		_apply(c, mat)
