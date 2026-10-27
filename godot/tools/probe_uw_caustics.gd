extends SceneTree
## 直接调水下材质自带的焦散：caustic_gain。
var main: Node
var out := "D:/projects/sea-work/caustics/uw"
var mats: Array = []
const F := 4.0
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 60: await process_frame
	main.hud.hide(); main.markers.hide(); main.ribbon.hide()
	main.cam.suspend_follow()
	main.cam.orbit_dir = Vector3(-0.52, 0.30, 0.42)
	main.cam.target = Vector3(0, -3.0, 6)
	main.cam.distance = 16.0
	main.cam.refresh()
	for i in 12: await process_frame
	main.water_node.set_process(false)
	main.set_process(false); main.set_physics_process(false)
	_walk(main)
	print("[uw] 水下材质数量 = ", mats.size())
	# 只保留 solid（有焦散的）
	var solid := []
	for m in mats:
		if m.shader.resource_path.ends_with("underwater_culled.gdshader"):
			solid.append(m)
	print("[uw] solid 材质 = ", solid.size())
	if solid.size() == 0:
		quit(0); return
	# 水下材质里 `water_level` 没人写，保持的是着色器默认值。先显式写一遍，
	# 验证「以水面高度为判据」能不能把焦散限制在水下。
	for m in solid:
		m.set_shader_parameter("water_level", 1.12)
	var m0: ShaderMaterial = solid[0]
	print("[uw] 参数: caustic_gain=", m0.get_shader_parameter("caustic_gain"),
		" emissive_strength=", m0.get_shader_parameter("emissive_strength"),
		" dive_depth=", m0.get_shader_parameter("dive_depth"))
	for spec in [["u-c0", 0.0], ["u-c025", 0.25], ["u-c055", 0.55], ["u-c090", 0.90]]:
		for m in solid:
			m.set_shader_parameter("caustic_surface", spec[1])
			m.set_shader_parameter("time_override", F)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + spec[0] + ".png")
		print("[uw] ", spec[0], " gain=", spec[1])
	quit(0)
func _walk(n: Node) -> void:
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		var m = gi.material_override
		if m == null and gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				m = mi.mesh.surface_get_material(0)
		if m is ShaderMaterial and m.shader.resource_path.contains("underwater") and not mats.has(m):
			mats.append(m)
	for ch in n.get_children():
		_walk(ch)
