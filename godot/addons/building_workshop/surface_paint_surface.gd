@tool
extends RefCounted
## 只读 GeneratedVisual 的有界 CPU 表面缓存。没有逐三角节点、物理碰撞或世界平面回退。

const Data = preload("res://addons/building_workshop/surface_paint_data.gd")
const Surface = preload("res://addons/scene_assembly/attachment_surface.gd")
# The editor cache keeps a bounded source-instance budget separately from its
# parser-class budget. Every source path/transform and every triangle remains
# in the exact cache for stamps; parser classes only bound the shared traversal
# bookkeeping and never collapse geometry or alter ray identities.
const MAX_SOURCE_INSTANCES := 192
const MAX_PARSER_CLASSES := 128
const MAX_SURFACES := 256
const MAX_TRIANGLES := 65536
const MAX_VERTICES := 262144
const MAX_NODES := 2048
const MAX_PATCH_LEAVES := 2048
const MAX_SAMPLES := 128
const MAX_COMPARISONS := 2000000
const LEAF_SIZE := 64

var _host: WeakRef
var _host_world := Transform3D.IDENTITY
var _triangles: Array[Dictionary] = []
var _leaves: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _lookup := {}
var _batch_keys := {}
var _geometry_fingerprint := ""
var _source_signature := ""
var _comparisons := 0

func invalidate_cache() -> void:
	_geometry_fingerprint = ""
	_source_signature = ""

func build_cache(host: Node3D) -> Dictionary:
	if not is_instance_valid(host) or not host.is_inside_tree(): return _fail("宿主必须在场景树内")
	host.force_update_transform()
	if not Data.valid_transform(host.global_transform): return _fail("宿主变换无效")
	var visual := host.get_node_or_null("GeneratedVisual") as Node3D
	if visual == null: return _fail("宿主缺少真实 GeneratedVisual")
	var source_signature := _source_tree_signature(host, visual)
	if _geometry_fingerprint != "" and _host != null and is_instance_valid(_host.get_ref()):
		var cached_host := _host.get_ref() as Node3D
		if cached_host == host and cached_host.global_transform == _host_world and source_signature == _source_signature:
			return {"ok": true, "reason": "", "fingerprint": _geometry_fingerprint, "triangles": _triangles.size(), "surfaces": _records.size(), "meshes": _records.size(), "cached": true}
	_triangles.clear(); _leaves.clear(); _records.clear(); _lookup.clear(); _batch_keys.clear()
	_host = null
	_geometry_fingerprint = ""
	_source_signature = source_signature
	var pending: Array[Node] = [visual]
	var meshes := 0
	var mesh_batches := 0
	var surfaces := 0
	var vertices_count := 0
	var input_triangles := 0
	var nodes := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		nodes += 1
		if nodes > MAX_NODES: return _fail("表面树超过2048节点预算")
		if _excluded(node, host): continue
		if node is Node3D and not node.is_visible_in_tree(): continue
		pending.append_array(node.get_children())
		if not node is MeshInstance3D or node.mesh == null: continue
		meshes += 1
		if meshes > MAX_SOURCE_INSTANCES: return _fail("建筑表面源网格实例超过192预算")
		var instance := node as MeshInstance3D
		instance.force_update_transform()
		var world := instance.global_transform
		if not Data.valid_transform(world): return _fail("建筑网格变换无效")
		var path := str(host.get_path_to(instance))
		if not Data.relative_mesh_path(path): return _fail("建筑表面路径不是 GeneratedVisual 相对路径")
		var relative := _host_relative_transform(instance, host)
		if not relative.ok: return _fail(str(relative.reason))
		var hash_state := HashingContext.new()
		hash_state.start(HashingContext.HASH_SHA256)
		# 只规范化指纹中的局部变换到1e-9；真实世界顶点、索引与贴面阈值完全不量化。
		var local_transform: Transform3D = relative.transform
		hash_state.update(("host_local_transform_v1:" + Data.canonical(Data.encode_transform(local_transform))).to_utf8_buffer())
		var first := _triangles.size()
		for surface: int in instance.mesh.get_surface_count():
			surfaces += 1
			if surfaces > MAX_SURFACES: return _fail("建筑表面超过256 surfaces预算")
			if instance.mesh is ArrayMesh and instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				return _fail("建筑表面只支持三角网格")
			var arrays := instance.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return _fail("建筑表面没有可读顶点")
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			vertices_count += vertices.size()
			if vertices_count > MAX_VERTICES: return _fail("建筑表面超过262144顶点预算")
			var count := indices.size() if not indices.is_empty() else vertices.size()
			input_triangles += int(count / 3)
			if count % 3 != 0 or input_triangles > MAX_TRIANGLES: return _fail("建筑表面超过65536三角或索引不完整")
			var material: Material = instance.get_active_material(surface)
			var label := (path + " " + instance.mesh.resource_name).to_lower()
			var allowed := _opaque_material(material) and not label.contains("glass") and not label.contains("玻璃") and instance.transparency <= 0.0 and instance.material_overlay == null
			var cull := Surface.material_cull(material)
			# Parser class is only a bounded bookkeeping class. It must not use
			# vertex bytes as a fake merge key: each source path and triangle below
			# remains independent for exact occlusion, stamping and persistence.
			var batch_key := "%s|%s" % [str(allowed), str(cull.get("mode", "unknown"))]
			if not _batch_keys.has(batch_key):
				_batch_keys[batch_key] = true
				mesh_batches += 1
				if mesh_batches > MAX_PARSER_CLASSES:
					return _fail("建筑表面解析类别超过128预算 (source=%d,classes=%d)" % [meshes, mesh_batches])
			hash_state.update(var_to_bytes([surface, vertices, indices, allowed, cull]))
			for offset: int in range(0, count, 3):
				var points: Array[Vector3] = []
				for corner: int in 3:
					var index := indices[offset + corner] if not indices.is_empty() else offset + corner
					if index < 0 or index >= vertices.size() or not vertices[index].is_finite(): return _fail("建筑三角面索引或顶点无效")
					var world_point: Vector3 = world * vertices[index]
					if not world_point.is_finite() or world_point.length() > 1000000.0: return _fail("建筑世界顶点非有限或超米制范围")
					points.append(world_point)
				var normal := (points[2] - points[0]).cross(points[1] - points[0])
				if normal.length_squared() < 0.000000000001: continue
				var triangle := {"a": points[0], "b": points[1], "c": points[2], "normal": normal.normalized(),
					"box": AABB(points[0], Vector3.ZERO).expand(points[1]).expand(points[2]).grow(0.000001),
					"mesh_path": path, "surface": surface, "triangle": int(offset / 3),
					"paintable": allowed and cull.get("ok", false) and cull.get("mode", "") != "front"}
				_lookup[_key(path, surface, int(offset / 3))] = _triangles.size()
				_triangles.append(triangle)
		var mesh_hash := hash_state.finish().hex_encode()
		for index: int in range(first, _triangles.size()): _triangles[index].mesh_fingerprint = mesh_hash
		_records.append({"path": path, "fingerprint": mesh_hash})
	for start: int in range(0, _triangles.size(), LEAF_SIZE):
		var end := mini(start + LEAF_SIZE, _triangles.size())
		var box: AABB = _triangles[start].box
		for index: int in range(start + 1, end): box = box.merge(_triangles[index].box)
		_leaves.append({"start": start, "end": end, "box": box})
	_host_world = host.global_transform
	_host = weakref(host)
	_source_signature = source_signature
	_geometry_fingerprint = Data.canonical(_records).sha256_text()
	return {"ok": true, "reason": "", "fingerprint": _geometry_fingerprint, "triangles": _triangles.size(), "surfaces": surfaces, "meshes": meshes}

func fingerprint() -> String:
	return _geometry_fingerprint

func _source_tree_signature(host: Node3D, visual: Node3D) -> String:
	var rows: Array = []
	var pending: Array[Node] = [visual]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if _excluded(node, host): continue
		pending.append_array(node.get_children())
		if not node is MeshInstance3D: continue
		var instance := node as MeshInstance3D
		var mesh: Mesh = instance.mesh
		if mesh == null: continue
		var materials: Array = []
		for surface: int in mesh.get_surface_count():
			var material: Material = instance.get_active_material(surface)
			var material_row: Array = [str(material.get_class()) if material != null else "null", str(material.resource_path) if material != null else "", str(material.resource_name) if material != null else ""]
			if material is BaseMaterial3D:
				material_row.append(float((material as BaseMaterial3D).transparency))
				material_row.append((material as BaseMaterial3D).albedo_color.a)
			elif material is ShaderMaterial and (material as ShaderMaterial).shader != null:
				material_row.append(str((material as ShaderMaterial).shader.resource_path))
			materials.append(material_row)
		var relative: Dictionary = _host_relative_transform(instance, host)
		var relative_transform: Transform3D = relative.get("transform", Transform3D.IDENTITY)
		rows.append([str(host.get_path_to(instance)), Data.canonical(Data.encode_transform(relative_transform)), str(mesh.resource_path), str(mesh.resource_name), mesh.get_surface_count(), mesh.get_aabb(), materials, instance.transparency])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	return Data.canonical(rows).sha256_text()

func _host_relative_transform(instance: Node3D, host: Node3D) -> Dictionary:
	# 从叶到宿主逐级左乘作者局部变换，完全不求世界矩阵逆；宿主及其祖先不进入指纹。
	var relative := Transform3D.IDENTITY
	var current: Node = instance
	var depth := 0
	while current != host:
		if current == null or depth >= MAX_NODES: return _fail("网格不在有界宿主子树内")
		if current is Node3D:
			var spatial := current as Node3D
			# 这些节点不遵循普通父子矩阵乘法，不能伪造稳定的宿主局部变换。
			if spatial.top_level or spatial.is_scale_disabled(): return _fail("表面局部链含 top_level 或禁用缩放节点")
			if not Data.valid_transform(spatial.transform): return _fail("表面局部链变换无效")
			relative = spatial.transform * relative
		current = current.get_parent()
		depth += 1
	if not Data.valid_transform(relative): return _fail("表面宿主局部组合变换无效")
	return {"ok": true, "reason": "", "transform": relative}

func _excluded(node: Node, host: Node) -> bool:
	# 玻璃保留在遮挡缓存中，只禁止受涂；不能沿用 Surface.excluded 跳过玻璃。
	var current := node
	while current != null:
		if current is NavigationRegion3D or current is NavigationLink3D or current is CollisionShape3D: return true
		if current.has_meta("sea_attachment") or bool(current.get_meta("attachment_surface_excluded", false)): return true
		var label := str(current.name).to_lower()
		for forbidden: String in ["vegetation", "attachment", "surfacepaint", "surface_paint", "ghost", "highlight", "temporary", "overlay", "navigation", "helper", "blocker", "walkarea"]:
			if label.contains(forbidden): return true
		if current.has_meta(Data.META) or bool(current.get_meta("surface_paint_excluded", false)): return true
		if current == host: break
		current = current.get_parent()
	return false

func _opaque_material(material: Material) -> bool:
	if Surface.glass_material(material): return false
	if material == null: return true
	if material.next_pass != null: return false
	if material is BaseMaterial3D: return material.albedo_color.a >= 0.99999
	if not material is ShaderMaterial or material.shader == null: return false
	var code: String = material.shader.code
	var comments := RegEx.new()
	comments.compile("(?s)/\\*.*?\\*/|//[^\\n]*")
	code = comments.sub(code, "", true)
	var alpha := RegEx.new()
	alpha.compile("\\b(ALPHA|ALPHA_SCISSOR_THRESHOLD|ALPHA_HASH_SCALE|discard)\\b|#include")
	# 未知 include/透明 shader 保守拒绝，不能靠资源名字冒充不透明。
	return alpha.search(code) == null

func triangle_for_stamp(stamp: Dictionary) -> Dictionary:
	var index: int = _lookup.get(_key(stamp.mesh_path, int(stamp.surface), int(stamp.triangle)), -1)
	if index < 0: return {}
	var triangle: Dictionary = _triangles[index]
	return triangle if triangle.mesh_fingerprint == stamp.mesh_fingerprint and triangle.paintable else {}

func validate_snapshot_surface(snapshot: Dictionary) -> String:
	var reason := Data.validate(snapshot)
	if not reason.is_empty(): return reason
	if _host == null or not is_instance_valid(_host.get_ref()): return "表面缓存宿主已失效"
	var host := _host.get_ref() as Node3D
	if not host.is_inside_tree() or host.global_transform != _host_world: return "表面缓存变换已过期"
	for stamp: Dictionary in snapshot.stamps:
		var triangle := triangle_for_stamp(stamp)
		if triangle.is_empty(): return "印记宿主网格指纹/路径已过期，请显式处理，不自动重投：" + stamp.id
		var world: Vector3 = _host_world * Data.vec(stamp.center_local)
		if not world.is_finite(): return "印记世界变换非有限"
		if not _on_triangle(world, triangle): return "印记不在原真实三角面内：" + stamp.id
		var normal: Vector3 = (_host_world.basis.inverse().transposed() * Data.vec(stamp.normal)).normalized()
		if normal.dot(triangle.normal) < 0.999 or (stamp.kind == "grass" and normal.y < 0.7): return "印记法线与原表面不一致"
		for raw: Array in stamp.path_points:
			if not _on_triangle(_host_world * Data.vec(raw), triangle): return "藤路径离开原真实表面"
	return ""

## 每次命令只用一次 Surface.raycast 作中心提示；真实最近阻挡与任意法向由缓存精筛。
## command={brush,origin:Vector3,direction:Vector3,stroke_id,sequence,seed,elapsed,previous_world?}。
## elapsed 是距上次成功采样的秒数；首击无 previous_world，立即生效。失败从不修改输入。
func apply_brush_command(snapshot: Dictionary, command: Dictionary) -> Dictionary:
	var reason := Data.validate(snapshot)
	if not reason.is_empty(): return _fail(reason)
	var required := ["brush", "origin", "direction", "stroke_id", "sequence", "seed", "elapsed"]
	if not command.has_all(required): return _fail("笔刷命令缺少必填字段")
	for key: Variant in command:
		if key not in required and key != "previous_world": return _fail("笔刷命令含未知字段")
	if not command.brush is Dictionary: return _fail("brush 必须为对象")
	reason = Data.validate_brush(command.brush)
	if not reason.is_empty(): return _fail(reason)
	if not command.origin is Vector3 or not command.direction is Vector3: return _fail("射线须为 Vector3")
	var origin: Vector3 = command.origin
	var direction: Vector3 = command.direction
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.00000001: return _fail("射线非有限或为零")
	if not Data.safe_id(command.stroke_id) or str(command.stroke_id).length() > 64 or not Data.integer(command.sequence, 0, 2147483647) or not Data.integer(command.seed, 0, 2147483647): return _fail("笔划 ID/序号/seed 无效")
	if not Data.bounded(command.elapsed, 0.0, 3600.0): return _fail("elapsed 必须为0..3600秒")
	if command.has("previous_world") and (not command.previous_world is Vector3 or not command.previous_world.is_finite()): return _fail("上一采样点无效")
	if _host == null or not is_instance_valid(_host.get_ref()): return _fail("请先建立表面缓存")
	# 重新读同一有界源，检测原位编辑网格、材质和变换；不信任实例 ID 或旧缓存。
	var host := _host.get_ref() as Node3D
	var old_fingerprint := _geometry_fingerprint
	var old_world := _host_world
	var rebuilt := build_cache(host)
	if not rebuilt.ok: return rebuilt
	if old_fingerprint != _geometry_fingerprint or old_world != _host_world: return _fail("宿主已变化，请重新开始笔划")
	reason = validate_snapshot_surface(snapshot)
	if not reason.is_empty(): return _fail(reason)
	var brush: Dictionary = command.brush
	var ray := direction.normalized()
	# _nearest 使用已建立的真实三角缓存，是唯一权威命中；不再额外
	# 调用 Surface.raycast 全量重扫 GeneratedVisual。
	_comparisons = 0
	var hit := _nearest(origin, ray)
	if not hit.get("ok", false): return hit
	var triangle: Dictionary = hit.face
	if not triangle.paintable or triangle.normal.dot(ray) >= -0.000001: return _fail("最近面透明、玻璃、未知材质或背面，拒绝穿透刷涂")
	if brush.kind == "grass" and triangle.normal.y < 0.7: return _fail("草只允许世界向上 dot>=0.7 的建筑真实表面")
	var center: Vector3 = hit.position
	if command.has("previous_world"):
		if center.distance_to(command.previous_world) < float(brush.spacing) or float(command.elapsed) < 1.0 / float(brush.rate):
			return {"ok": true, "reason": "", "changed": false, "snapshot": snapshot.duplicate(true), "center_world": center, "added": 0, "removed": 0}
	var result: Dictionary = snapshot.duplicate(true)
	var removed := 0
	if brush.kind == "erase":
		var kept: Array = []
		for stamp: Dictionary in result.stamps:
			var point: Vector3 = _host_world * Data.vec(stamp.center_local)
			var touches: bool = point.distance_to(center) <= float(brush.radius)
			var erase_point := point
			for index: int in range(1, stamp.path_points.size()):
				var a: Vector3 = _host_world * Data.vec(stamp.path_points[index - 1])
				var b: Vector3 = _host_world * Data.vec(stamp.path_points[index])
				var closest: Vector3 = Geometry3D.get_closest_point_to_segment(center, a, b)
				if closest.distance_to(center) <= float(brush.radius):
					touches = true
					erase_point = closest
			if touches and _visible(origin, erase_point, triangle_for_stamp(stamp)):
				removed += 1
			else: kept.append(stamp)
		if _comparisons > MAX_COMPARISONS: return _fail("擦除遮挡检查超过预算，未提交")
		result.stamps = kept
	else:
		var patches := _sphere_patches(center, float(brush.radius), origin, str(brush.kind))
		if not patches.ok: return patches
		var rng := RandomNumberGenerator.new()
		rng.seed = int(command.seed) ^ int((str(command.stroke_id) + ":" + str(command.sequence)).sha256_text().substr(0, 8).hex_to_int())
		var target := mini(MAX_SAMPLES, maxi(1, ceili(PI * pow(float(brush.radius), 2.0) * float(brush.density))))
		var existing := {}
		for stamp: Dictionary in result.stamps: existing[stamp.id] = true
		var added := 0
		for attempt: int in range(target * 8):
			if added >= target: break
			var sample := _sample_patch(patches.patches, float(patches.area), rng)
			var point: Vector3 = sample.position
			var face: Dictionary = sample.face
			if point.distance_to(center) > float(brush.radius) or not _visible(origin, point, face): continue
			var too_close := false
			for stamp: Dictionary in result.stamps:
				if stamp.kind == brush.kind and (_host_world * Data.vec(stamp.center_local)).distance_squared_to(point) < pow(float(brush.spacing), 2.0):
					too_close = true
					break
			if too_close: continue
			var id := "%s_%d_%d" % [command.stroke_id, command.sequence, added]
			if existing.has(id): return _fail("笔划序号重复，不能覆盖稳定印记 ID")
			if result.stamps.size() >= Data.MAX_STAMPS: return _fail("表面印记已达4096上限，本次未提交")
			result.stamps.append(_make_stamp(id, brush, point, face, rng))
			existing[id] = true
			added += 1
		if _comparisons > MAX_COMPARISONS: return _fail("表面遮挡检查超过预算，未提交")
	reason = Data.validate(result)
	if not reason.is_empty(): return _fail(reason)
	return {"ok": true, "reason": "", "changed": result != snapshot, "snapshot": result,
		"center_world": center, "normal_world": triangle.normal, "radius_m": brush.radius,
		"added": result.stamps.size() - snapshot.stamps.size() + removed, "removed": removed,
		"center_surface_hint_ok": true, "comparisons": _comparisons}

func _make_stamp(id: String, brush: Dictionary, point: Vector3, face: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var normal: Vector3 = (_host_world.basis.transposed() * face.normal).normalized()
	var rotation := (Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, rng.randf() * TAU)).get_rotation_quaternion().normalized()
	var params := brush.duplicate(true)
	params.erase("kind")
	var local: Vector3 = _host_world.affine_inverse() * point
	var stamp := {"id": id, "kind": brush.kind, "source": Data.SOURCES[brush.kind],
		"center_world": Data.array_vec(point), "center_local": Data.array_vec(local),
		"normal": Data.array_vec(normal), "orientation": [rotation.x, rotation.y, rotation.z, rotation.w],
		"scale": [1.0, 1.0, 1.0], "seed": int(rng.randi() % 2147483648), "params": params,
		"mesh_fingerprint": face.mesh_fingerprint, "mesh_path": face.mesh_path,
		"surface": face.surface, "triangle": face.triangle, "path_points": []}
	if brush.kind == "vine":
		# 最小藤段严格位于同一真实三角内；不猜跨墙路径或让路径悬在空中。
		var farthest: Vector3 = face.a
		for corner: Vector3 in [face.b, face.c]:
			if point.distance_squared_to(corner) > point.distance_squared_to(farthest): farthest = corner
		var end: Vector3 = point.lerp(farthest, 0.6)
		if end.distance_to(point) > float(brush.size): end = point + (end - point).normalized() * float(brush.size)
		stamp.path_points = [Data.array_vec(local), Data.array_vec(_host_world.affine_inverse() * end)]
	return stamp

func _sphere_patches(center: Vector3, radius: float, origin: Vector3, kind: String) -> Dictionary:
	var patches: Array[Dictionary] = []
	var queue: Array[Dictionary] = []
	for leaf: Dictionary in _leaves:
		if not _box_sphere(leaf.box, center, radius): continue
		for index: int in range(leaf.start, leaf.end):
			var face: Dictionary = _triangles[index]
			if not face.paintable or (kind == "grass" and face.normal.y < 0.7): continue
			if face.normal.dot(origin - face.a) <= 0.000001 or not _box_sphere(face.box, center, radius): continue
			queue.append({"a": face.a, "b": face.b, "c": face.c, "face": face})
			if queue.size() > MAX_PATCH_LEAVES: return _fail("球范围候选面超过2048预算")
	var area := 0.0
	var visited := 0
	while not queue.is_empty():
		var patch: Dictionary = queue.pop_back()
		visited += 1
		if visited > MAX_PATCH_LEAVES * 8: return _fail("球笔刷细分超过预算")
		var box: AABB = AABB(patch.a, Vector3.ZERO).expand(patch.b).expand(patch.c)
		if not _box_sphere(box, center, radius): continue
		var lengths := Vector3((patch.a as Vector3).distance_squared_to(patch.b), (patch.b as Vector3).distance_squared_to(patch.c), (patch.c as Vector3).distance_squared_to(patch.a))
		if lengths[lengths.max_axis_index()] > radius * radius * 0.25:
			var a: Vector3 = patch.a
			var b: Vector3 = patch.b
			var c: Vector3 = patch.c
			match lengths.max_axis_index():
				0: queue.append({"a": a, "b": (a+b)*0.5, "c": c, "face": patch.face}); queue.append({"a": (a+b)*0.5, "b": b, "c": c, "face": patch.face})
				1: queue.append({"a": a, "b": b, "c": (b+c)*0.5, "face": patch.face}); queue.append({"a": a, "b": (b+c)*0.5, "c": c, "face": patch.face})
				2: queue.append({"a": a, "b": b, "c": (c+a)*0.5, "face": patch.face}); queue.append({"a": (c+a)*0.5, "b": b, "c": c, "face": patch.face})
			if queue.size() + patches.size() > MAX_PATCH_LEAVES: return _fail("球笔刷叶片超过2048预算")
		else:
			patch.area = ((patch.b - patch.a) as Vector3).cross(patch.c - patch.a).length() * 0.5
			area += float(patch.area)
			patches.append(patch)
	if patches.is_empty() or area <= 0.0: return _fail("球范围没有合格真实表面")
	return {"ok": true, "reason": "", "patches": patches, "area": area}

func _sample_patch(patches: Array, area: float, rng: RandomNumberGenerator) -> Dictionary:
	var chosen: Dictionary = patches.back()
	var distance := rng.randf() * area
	for patch: Dictionary in patches:
		distance -= float(patch.area)
		if distance <= 0.0:
			chosen = patch
			break
	var u := sqrt(rng.randf())
	var v := rng.randf()
	return {"position": chosen.a * (1.0-u) + chosen.b * (u*(1.0-v)) + chosen.c * (u*v), "face": chosen.face}

func _nearest(origin: Vector3, direction: Vector3, limit: float = INF) -> Dictionary:
	var nearest := limit
	var best := {}
	for leaf: Dictionary in _leaves:
		if leaf.box.intersects_ray(origin, direction) == null: continue
		for index: int in range(leaf.start, leaf.end):
			_comparisons += 1
			if _comparisons > MAX_COMPARISONS: return _fail("射线检查超过预算")
			var face: Dictionary = _triangles[index]
			var point: Variant = Geometry3D.ray_intersects_triangle(origin, direction, face.a, face.b, face.c)
			if point == null: continue
			var distance: float = (point - origin).dot(direction)
			# 遮挡使用双面几何：不因背面/透明拒涂而穿到后墙。
			if distance > 0.000001 and distance < nearest:
				nearest = distance
				best = {"ok": true, "reason": "", "position": point, "face": face, "distance": distance}
	return best if not best.is_empty() else _fail("未命中真实建筑三角面")

func _visible(origin: Vector3, point: Vector3, face: Dictionary) -> bool:
	if face.is_empty() or face.normal.dot(origin - point) <= 0.000001: return false
	var ray := point - origin
	var hit := _nearest(origin, ray.normalized(), ray.length() + 0.001)
	return hit.get("ok", false) and hit.position.distance_to(point) <= 0.0001

func _on_triangle(point: Vector3, face: Dictionary) -> bool:
	if absf(face.normal.dot(point - face.a)) > 0.0001: return false
	var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(point, face.a, face.b)
	if point.distance_to(nearest) < 0.0001: return true
	var projected: Variant = Geometry3D.ray_intersects_triangle(point + face.normal * 0.01, -face.normal, face.a, face.b, face.c)
	return projected != null and point.distance_to(projected) < 0.0001

func _box_sphere(box: AABB, center: Vector3, radius: float) -> bool:
	return center.distance_squared_to(center.clamp(box.position, box.end)) <= radius * radius

func _key(path: String, surface: int, triangle: int) -> String:
	return "%s|%d|%d" % [path, surface, triangle]

func host_transform() -> Transform3D:
	return _host_world

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "changed": false}
