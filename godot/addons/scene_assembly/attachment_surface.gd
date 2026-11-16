@tool
extends RefCounted
## 只读宿主真实可见三角面；不查询物理空间，不用包围盒充当命中面。

const META := "sea_attachment"
const WALL_LIMIT := 0.35
const ROOF_LIMIT := 0.7

static func valid_transform(value: Transform3D) -> bool:
	return value.is_finite() and value.basis.determinant() > 0.00000001

static func excluded(node: Node, host: Node) -> bool:
	var current := node
	while current != null:
		if current.has_meta(META) or current.name == "Attachments": return true
		if current is NavigationRegion3D or current is NavigationLink3D or current is CollisionShape3D: return true
		var label := str(current.name).to_lower()
		if label.contains("glass") or label.contains("navigation") or label.contains("helper") or label.contains("blocker") or label.begins_with("walkarea"): return true
		if bool(current.get_meta("attachment_surface_excluded", false)): return true
		if current == host: break
		current = current.get_parent()
	return false

static func glass_material(material: Material) -> bool:
	if material == null: return false
	var label := (material.resource_name + " " + material.resource_path).to_lower()
	if label.contains("glass") or label.contains("sunny_gloss"): return true
	if material is BaseMaterial3D:
		return material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	return false

static func material_cull(material: Material) -> Dictionary:
	# 空材质遵循 Godot 默认背面剔除；shader只读代码，不执行或加载脚本。
	if material == null: return {"ok": true, "mode": "back"}
	if material is BaseMaterial3D:
		return {"ok": true, "mode": "disabled" if material.cull_mode == BaseMaterial3D.CULL_DISABLED else "front" if material.cull_mode == BaseMaterial3D.CULL_FRONT else "back"}
	if material is ShaderMaterial and material.shader != null:
		var code: String = material.shader.code
		var comments := RegEx.new()
		comments.compile("(?s)/\\*.*?\\*/|//[^\\n]*")
		code = comments.sub(code, "", true)
		if code.contains("#include"): return {"ok": false, "reason": "未知 shader include 的剔除规则，保守拒绝挂载"}
		var modes := RegEx.new()
		modes.compile("\\brender_mode\\s+([^;]+);")
		var found: Array[String] = []
		for declaration: RegExMatch in modes.search_all(code):
			for value: String in declaration.get_string(1).split(","):
				if value.strip_edges() in ["cull_back", "cull_front", "cull_disabled"]: found.append(value.strip_edges())
		if found.size() > 1: return {"ok": false, "reason": "shader剔除声明冲突，拒绝挂载"}
		if not code.contains("shader_type spatial"): return {"ok": false, "reason": "未知非空间shader材质，拒绝挂载"}
		return {"ok": true, "mode": found[0].trim_prefix("cull_") if not found.is_empty() else "back"}
	return {"ok": false, "reason": "未知有效材质剔除规则，保守拒绝挂载"}

static func meshes(host: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect(host, host, result)
	return result

static func _collect(node: Node, host: Node3D, result: Array[MeshInstance3D]) -> void:
	if excluded(node, host): return
	if node is Node3D and not node.is_visible_in_tree(): return
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): _collect(child, host, result)

static func raycast(host: Node3D, origin: Vector3, direction: Vector3, mode: String = "wall") -> Dictionary:
	if not is_instance_valid(host) or not host.is_inside_tree(): return _fail("宿主已失效，请重新锁定")
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.00000001: return _fail("射线必须是有限非零向量")
	if not valid_transform(host.global_transform): return _fail("宿主为奇异、镜像或非有限变换，拒绝贴面")
	if not ["wall", "roof"].has(mode): return _fail("请选择显式挂载面 wall 或 roof")
	var ray := direction.normalized()
	var nearest := INF
	var best: Dictionary = {}
	for node: MeshInstance3D in meshes(host):
		var world := node.global_transform
		if not valid_transform(world): return _fail("宿主可见网格含奇异、镜像或非有限变换：" + str(node.name))
		var inverse := world.affine_inverse()
		var local_origin := inverse * origin
		var local_ray := inverse.basis * ray
		if node.get_aabb().intersects_ray(local_origin, local_ray) == null: continue
		var normal_matrix := world.basis.inverse().transposed()
		for surface: int in node.mesh.get_surface_count():
			if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var material: Material = node.get_active_material(surface)
			if glass_material(material): continue
			var cull := material_cull(material)
			var arrays := node.mesh.surface_get_arrays(surface)
			if arrays.is_empty(): continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index: int in range(0, count - 2, 3):
				var ia := indices[index] if not indices.is_empty() else index
				var ib := indices[index + 1] if not indices.is_empty() else index + 1
				var ic := indices[index + 2] if not indices.is_empty() else index + 2
				var a := vertices[ia]
				var b := vertices[ib]
				var c := vertices[ic]
				if not a.is_finite() or not b.is_finite() or not c.is_finite(): return _fail("宿主三角面含非有限顶点")
				var local_normal := (c - a).cross(b - a)
				if local_normal.length_squared() < 0.000000000001: continue
				var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_ray, a, b, c)
				if hit == null: continue
				var point: Vector3 = world * hit
				var distance := (point - origin).dot(ray)
				if distance < 0.00001 or distance >= nearest: continue
				var normal := (normal_matrix * local_normal).normalized()
				# Godot 顺时针正面；逆转置结果与真实世界三角形的外法线核对。
				var triangle_normal := ((world * c) - (world * a)).cross((world * b) - (world * a)).normalized()
				if not normal.is_finite() or normal.dot(triangle_normal) < 0.999: return _fail("三角面法向变换无效")
				if not cull.ok:
					nearest = distance
					best = _fail(str(cull.reason))
					continue
				var facing := normal.dot(ray)
				if (cull.mode == "back" and facing >= -0.000001) or (cull.mode == "front" and facing <= 0.000001): continue
				if cull.mode == "front" or (cull.mode == "disabled" and facing > 0.0): normal = -normal
				nearest = distance
				best = {"ok": true, "reason": "", "position": point, "normal": normal, "mesh_path": host.get_path_to(node), "surface": surface, "triangle": index / 3, "triangle_local": [a, b, c], "distance": distance, "mode": mode}
	if best.is_empty(): return _fail("未命中宿主真实可见实体面；不会回落到世界 Y 平面")
	if not best.ok: return best
	var up: float = best.normal.dot(Vector3.UP)
	if (mode == "wall" and absf(up) > WALL_LIMIT) or (mode == "roof" and up < ROOF_LIMIT):
		return _fail("最近命中面不满足 %s 法向门限，请调整挂载面或视角" % mode)
	return best

static func installation_profile(built: Dictionary, mode: String) -> Dictionary:
	var snapshot: Dictionary = built.snapshot
	var triangles: Array = []
	var parts: Array = []
	for source: Dictionary in snapshot.meshes:
		for index: int in range(0, source.indices.size(), 3):
			triangles.append([_vec(source.vertices[source.indices[index]]), _vec(source.vertices[source.indices[index + 1]]), _vec(source.vertices[source.indices[index + 2]])])
	for part: Dictionary in snapshot.source_parts:
		var faces: Array = []
		var extreme := INF if mode == "roof" else -INF
		for source: Dictionary in snapshot.meshes:
			if source.material_role != part.material_role: continue
			for index: int in range(int(part.triangle_start) * 3, (int(part.triangle_start) + int(part.triangle_count)) * 3, 3):
				var face := [_vec(source.vertices[source.indices[index]]), _vec(source.vertices[source.indices[index + 1]]), _vec(source.vertices[source.indices[index + 2]])]
				faces.append(face)
				for point: Vector3 in face: extreme = minf(extreme, point.y) if mode == "roof" else maxf(extreme, point.z)
		parts.append({"name": str(part.name), "faces": faces, "extreme": extreme})
	var global_extreme := INF if mode == "roof" else -INF
	for part: Dictionary in parts: global_extreme = minf(global_extreme, part.extreme) if mode == "roof" else maxf(global_extreme, part.extreme)
	var has_pads := false
	if mode == "roof":
		for part: Dictionary in parts:
			if str(part.name).contains("_pad_"): has_pads = true
	var points: Array[Vector3] = []
	var names: Array[String] = []
	for part: Dictionary in parts:
		var required_pad: bool = mode == "roof" and has_pads and str(part.name).contains("_pad_")
		if mode == "roof" and has_pads and not required_pad: continue
		if absf(float(part.extreme) - global_extreme) > 0.002:
			if required_pad: return _fail("独立底脚不在真实底部接触薄带内，缺少稳定支撑：" + str(part.name))
			continue
		var candidates: Array[Vector3] = []
		for face: Array in part.faces:
			var a: Vector3 = face[0]
			var b: Vector3 = face[1]
			var c: Vector3 = face[2]
			var normal := (c - a).cross(b - a).normalized()
			var outward := -normal.y if mode == "roof" else normal.z
			if outward <= 0.000001: continue
			# 极值坐标来自真实网格顶点；裁切保留原三角上的2mm接触薄带，兼容倾斜/收分/圆弧边接触。
			var contact := _clip_contact(face, global_extreme, mode)
			if contact.size() < 3: continue
			var center := Vector3.ZERO
			for point: Vector3 in contact: center += point
			center /= float(contact.size())
			candidates.append(center)
			for point: Vector3 in contact: candidates.append(center.lerp(point, 0.7))
		if candidates.is_empty():
			if required_pad: return _fail("独立底脚没有真实朝外接触面：" + str(part.name))
			continue
		var samples: Array[Vector3] = [candidates[0]]
		for sample_index: int in 2:
			var best := candidates[0]
			var farthest := -1.0
			for point: Vector3 in candidates:
				var distance := INF
				for sample: Vector3 in samples: distance = minf(distance, sample.distance_squared_to(point))
				if distance > farthest:
					farthest = distance
					best = point
			samples.append(best)
		points.append_array(samples)
		names.append(part.name)
	if points.is_empty(): return _fail("没有可识别的真实底面/背挂支点，保守拒绝安装")
	if points.size() > 96: return _fail("安装支点超过有界核验预算，拒绝强制放置")
	return {"ok": true, "reason": "", "points": points, "parts": names, "triangles": triangles}

static func _clip_contact(face: Array, extreme: float, mode: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var axis := 1 if mode == "roof" else 2
	var boundary := extreme + 0.002 if mode == "roof" else extreme - 0.002
	for index: int in face.size():
		var start: Vector3 = face[index]
		var end: Vector3 = face[(index + 1) % face.size()]
		var start_inside := start[axis] <= boundary if mode == "roof" else start[axis] >= boundary
		var end_inside := end[axis] <= boundary if mode == "roof" else end[axis] >= boundary
		if start_inside: result.append(start)
		if start_inside != end_inside:
			result.append(start.lerp(end, (boundary - start[axis]) / (end[axis] - start[axis])))
	return result

static func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func validate_installation(host: Node3D, profile: Dictionary, pose: Transform3D, normal: Vector3, mode: String, clearance: float) -> Dictionary:
	if not profile.ok: return profile
	var checks := 0
	for point: Vector3 in profile.points:
		var world := pose * point
		var support := raycast(host, world + normal * 0.003, -normal, mode)
		if not support.ok or absf(float(support.get("distance", INF)) - (clearance + 0.003)) > 0.004 or support.normal.dot(normal) < 0.98:
			return _fail("中心命中但支承不足：底脚/背挂支点未在4毫米容差内获得真实支撑")
		checks += 1
	var overlap := _intersections(host, profile.triangles, pose)
	if not overlap.ok: return overlap
	return {"ok": true, "reason": "", "support_checks": checks, "support_parts": profile.parts}

static func _triangle_box(face: Array) -> AABB:
	return AABB(face[0], Vector3.ZERO).expand(face[1]).expand(face[2])

static func _crossing(a: Array, b: Array) -> bool:
	var normal: Vector3 = (b[1] - b[0]).cross(b[2] - b[0]).normalized()
	var low := INF
	var high := -INF
	for point: Vector3 in a:
		var distance: float = normal.dot(point - b[0])
		low = minf(low, distance)
		high = maxf(high, distance)
	if low >= -0.001 or high <= 0.001: return false
	for index: int in 3:
		var start: Vector3 = a[index]
		var end: Vector3 = a[(index + 1) % 3]
		var hit: Variant = Geometry3D.segment_intersects_triangle(start, end, b[0], b[1], b[2])
		if hit != null and start.distance_to(hit) > 0.001 and end.distance_to(hit) > 0.001: return true
	return false

static func _intersections(host: Node3D, local_faces: Array, pose: Transform3D) -> Dictionary:
	var faces: Array = []
	var bounds := AABB()
	var first := true
	for face: Array in local_faces:
		var world := [pose * face[0], pose * face[1], pose * face[2]]
		var box := _triangle_box(world)
		faces.append({"points": world, "box": box})
		bounds = box if first else bounds.merge(box)
		first = false
	var comparisons := 0
	for mesh: MeshInstance3D in meshes(host):
		if not valid_transform(mesh.global_transform): return _fail("宿主网格变换无效")
		if not bounds.intersects(mesh.global_transform * mesh.get_aabb()): continue
		for surface: int in mesh.mesh.get_surface_count():
			if mesh.mesh is ArrayMesh and mesh.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			if glass_material(mesh.get_active_material(surface)): continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays.is_empty(): continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index: int in range(0, count - 2, 3):
				var triangle: Array = []
				for offset: int in 3: triangle.append(mesh.global_transform * vertices[indices[index + offset] if not indices.is_empty() else index + offset])
				var box := _triangle_box(triangle)
				if not bounds.intersects(box): continue
				for candidate: Dictionary in faces:
					if not candidate.box.intersects(box): continue
					comparisons += 1
					if comparisons > 200000: return _fail("相交检查超过有界预算，保守拒绝安装")
					if _crossing(candidate.points, triangle) or _crossing(triangle, candidate.points): return _fail("中心命中但外挂实体与宿主墙面/屋面相交，拒绝安装")
	return {"ok": true, "reason": ""}

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
