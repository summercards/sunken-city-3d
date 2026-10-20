extends SceneTree
## 校验区块场景里的实体建筑与 manifest 对得上：
##   1. 每个 unit 的节点位置 == manifest.origin - 区块根位移（与旧运行时装配同一公式）
##   2. 场景所有网格的世界包围盒尺寸 == manifest.bounds.size
##   3. 每张面的材质与 manifest.slots 的 (贴图/深染/unlit/透明) 一一对应
## 失败时退出码 1，可接进 CI。

const ZONES := [
	["zone1", "zone1_home_harbor"], ["zone2", "zone2_yokohama_station"],
	["zone3", "zone3_arc_farm"], ["zone4", "zone4_far_shore"],
	["zone5", "zone5_aqua_platform"],
]
const WATER_LEVEL := 1.12
const TOL := 0.02

var fails := 0


func _init() -> void:
	for pair in ZONES:
		_check(pair[0], pair[1])
	print("[verify] %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)


func _check(zone_id: String, key: String) -> void:
	var scene_path := "res://scenes/zones/%s.tscn" % key
	var packed: Variant = load(scene_path)
	if packed == null:
		_fail(zone_id, "场景加载失败 " + scene_path); return
	var zone: Node = packed.instantiate()
	var models: Node = zone.get_node_or_null("Models")
	if models == null:
		_fail(zone_id, "缺 Models"); zone.free(); return

	var manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/models/zones/%s/manifest.json" % key))
	if manifest == null:
		_fail(zone_id, "manifest 读不到"); zone.free(); return

	var base: Vector3 = (zone as Node3D).position
	var bad_pos := 0
	var bad_mat := 0
	var faces := 0
	var bad_size := 0

	for u in manifest.units:
		var uid := str(u.id)
		var node: Node3D = models.get_node_or_null(uid)
		if node == null:
			_fail(zone_id, "缺 unit 节点 " + uid); bad_pos += 1; continue
		var origin: Array = u.origin
		var want := Vector3(float(origin[0]), float(origin[1]), float(origin[2])) - base
		if (node.position - want).length() > TOL:
			bad_pos += 1
			print("     %s 位置 %.3f != %.3f" % [uid, node.position.length(), want.length()])

		var slots: Array = u.get("slots", [])
		var unit_box := AABB()
		var first := true
		var meshes := _mesh_list(node)
		for mi in meshes:
			for i in mi.mesh.get_surface_count():
				faces += 1
				var s: Dictionary = slots[i] if i < slots.size() else {}
				if not _mat_ok(mi.get_surface_override_material(i), s):
					bad_mat += 1
			var box := _xform_aabb(mi.global_transform, mi.mesh.get_aabb())
			unit_box = box if first else unit_box.merge(box)
			first = false
		var want_box: Dictionary = u.get("bounds", {})
		if want_box.has("size"):
			var ws: Array = want_box.size
			var d := (unit_box.size - Vector3(float(ws[0]), float(ws[1]), float(ws[2]))).length()
			if d > 0.5:
				bad_size += 1
				print("     %s 尺寸差 %.3f (%s)" % [uid, d, _fmt(unit_box.size)])

	var ok := bad_pos == 0 and bad_mat == 0 and bad_size == 0 and faces > 0
	print("%s %s  units=%d faces=%d 位置错=%d 材质错=%d 尺寸错=%d" % [
		"OK  " if ok else "FAIL", zone_id, manifest.units.size(), faces, bad_pos, bad_mat, bad_size])
	if not ok:
		fails += 1
	zone.free()


func _mesh_list(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _mat_ok(raw: Variant, s: Dictionary) -> bool:
	if not (raw is ShaderMaterial):
		return false
	var m: ShaderMaterial = raw
	if m.shader == null:
		return false
	var path := m.shader.resource_path.get_file()
	var want_unlit := bool(s.get("unlit", false))
	var want_alpha := bool(s.get("alpha", false))
	var is_unlit := path.begins_with("unlit")
	var is_alpha := path.contains("_alpha")
	if is_unlit != want_unlit or is_alpha != want_alpha:
		return false
	var tex := int(s.get("tex", -1))
	var use: Variant = m.get_shader_parameter("use_texture")
	if bool(use) != (tex >= 0):
		return false
	var tint: Variant = m.get_shader_parameter("depth_tint")
	if bool(tint) != bool(s.get("tint", false)):
		return false
	var wl: Variant = m.get_shader_parameter("water_level")
	if absf(float(wl) - WATER_LEVEL) > 0.001:
		return false
	return true


func _xform_aabb(xf: Transform3D, box: AABB) -> AABB:
	var out := AABB()
	var first := true
	for i in 8:
		var corner := box.position + Vector3(
			box.size.x if (i & 1) else 0.0,
			box.size.y if (i & 2) else 0.0,
			box.size.z if (i & 4) else 0.0)
		var p := xf * corner
		if first:
			out = AABB(p, Vector3.ZERO); first = false
		else:
			out = out.expand(p)
	return out


func _fail(zone_id: String, msg: String) -> void:
	print("FAIL %s %s" % [zone_id, msg])
	fails += 1


func _fmt(v: Vector3) -> String:
	return "%.2fx%.2fx%.2f" % [v.x, v.y, v.z]
