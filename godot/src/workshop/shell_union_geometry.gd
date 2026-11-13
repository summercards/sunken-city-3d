@tool
extends RefCounted
## 只在生成期存在的布尔内核；不挂SceneTree，不把CSG或源壳写入静态场景。

const MeshBuilder = preload("res://src/workshop/mesh_builder.gd")
const WELD: float = 0.00001
# CSG内部绝对容差不能表达毫米级咬合；在放大坐标中求交，再恢复米制。
const BOOLEAN_SCALE: float = 100.0

static func owns(id: String) -> bool:
	return id == "roof_main" or id.begins_with("wall_shell_") or id.begins_with("slab_") or id.begins_with("pilaster_") or id.begins_with("band_") or id.begins_with("belt_") or id.begins_with("plinth_")

static func combine(parts: Array) -> Dictionary:
	var root := CSGCombiner3D.new()
	root.calculate_tangents = false
	if root.has_method("set_snap"): root.call("set_snap", 0.000001)
	if not root.has_method("_update_shape"):
		root.free()
		return {"ok": false, "reason": "当前引擎缺少同步CSG更新接口；拒绝以join替代布尔"}
	var source_ids: Array[String] = []
	for part: Dictionary in parts:
		if not owns(str(part.id)): continue
		source_ids.append(str(part.id))
		for record: Dictionary in part.mesh_records:
			var operand := CSGMesh3D.new()
			operand.mesh = record.mesh
			operand.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * BOOLEAN_SCALE), part.position * BOOLEAN_SCALE) * record.transform
			operand.calculate_tangents = false
			if operand.has_method("set_snap"): operand.call("set_snap", 0.000001)
			operand.operation = CSGShape3D.OPERATION_UNION
			root.add_child(operand)
	root.call("_update_shape")
	var baked: ArrayMesh = root.bake_static_mesh()
	root.free()
	if baked == null or baked.get_surface_count() == 0:
		return {"ok": false, "reason": "结构布尔返回空边界；不保留源壳伪装成功"}
	# 布尔切割可能把插值UV压成线。保留原Palette格与共享材质，逐三角重建格内非零面积UV。
	var mesh := ArrayMesh.new()
	var surfaces: Array = []
	for surface: int in baked.get_surface_count():
		var arrays: Array = baked.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array()
		var input_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var clean := PackedVector3Array()
		var uvs := PackedVector2Array()
		for start: int in range(0, vertices.size(), 3):
			for corner: int in 3:
				vertices[start + corner] = Vector3(key(vertices[start + corner] / BOOLEAN_SCALE)) * WELD
			if key(vertices[start]) == key(vertices[start + 1]) or key(vertices[start]) == key(vertices[start + 2]) or key(vertices[start + 1]) == key(vertices[start + 2]): continue
			if MeshBuilder._degenerate_triangle(vertices[start], vertices[start + 1], vertices[start + 2]): continue
			for corner: int in 3:
				clean.append(vertices[start + corner])
				uvs.append(input_uvs[start + corner])
		vertices = clean
		for index: int in vertices.size():
			# TriangleMesh/get_faces本身按0.1mm吸附，上传前先采用同一精度并移除塌缩三角。
			vertices[index] = vertices[index].snappedf(0.0001)
		clean = PackedVector3Array()
		var clean_uvs := PackedVector2Array()
		for start: int in range(0, vertices.size(), 3):
			if key(vertices[start]) == key(vertices[start + 1]) or key(vertices[start]) == key(vertices[start + 2]) or key(vertices[start + 1]) == key(vertices[start + 2]): continue
			if (vertices[start + 1] - vertices[start]).cross(vertices[start + 2] - vertices[start]).length_squared() <= 1.0e-18: continue
			for corner: int in 3:
				clean.append(vertices[start + corner])
				clean_uvs.append(uvs[start + corner])
		vertices = clean
		uvs = clean_uvs
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if not indices.is_empty():
			return {"ok": false, "reason": "CSG返回未知索引格式；需显式适配"}
		for start: int in range(0, vertices.size(), 3):
			var normal: Vector3 = -(vertices[start + 1] - vertices[start]).cross(vertices[start + 2] - vertices[start]).normalized()
			var center: Vector2 = (uvs[start] + uvs[start + 1] + uvs[start + 2]) / 3.0
			var cell := Vector2(floorf(center.x * 8.0), floorf(center.y * 8.0)) / 8.0
			for corner: int in 3:
				normals.append(normal)
				uvs[start + corner] = cell + [Vector2(0.035, 0.035), Vector2(0.090, 0.035), Vector2(0.0625, 0.090)][corner]
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uvs
		arrays[Mesh.ARRAY_TANGENT] = null
		surfaces.append({"arrays": arrays, "material": baked.surface_get_material(surface)})
	_remove_canceling_faces(surfaces)
	_conform_boundaries(surfaces)
	# 拆分T接后，原先不同剖分的零厚度反向面才可能完全重合。
	_remove_canceling_faces(surfaces)
	_collapse_quantization_slivers(surfaces)
	for surface: Dictionary in surfaces:
		if surface.arrays[Mesh.ARRAY_VERTEX].is_empty(): continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, surface.material)
	var audit: Dictionary = audit_faces(mesh.get_faces())
	if not bool(audit.valid):
		return {"ok": false, "reason": "结构union边界校核失败: " + str(audit), "audit": audit}
	var boundary_audit: Dictionary = _audit_source_boundary(mesh.get_faces(), parts)
	if not bool(boundary_audit.valid):
		return {"ok": false, "reason": "结构union实体边界校核失败: " + str(boundary_audit), "audit": audit, "boundary_audit": boundary_audit}
	return {"ok": true, "mesh": mesh, "audit": audit, "boundary_audit": boundary_audit, "source_slots": source_ids, "backend": "Godot4.7.2_CSG_sync_boolean"}

## 折叠量化产生的细长三角；link条件保持流形，可靠邻面须在0.1mm误差内且不翻转。
static func _collapse_quantization_slivers(surfaces: Array) -> void:
	var points: Array[Vector3] = []
	var lookup: Dictionary = {}
	var triangles: Array = []
	for surface_index: int in surfaces.size():
		var arrays: Array = surfaces[surface_index].arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for start: int in range(0, vertices.size(), 3):
			var ids: Array[int] = []
			for corner: int in 3:
				var k: Vector3i = key(vertices[start + corner])
				if not lookup.has(k):
					lookup[k] = points.size()
					points.append(vertices[start + corner])
				ids.append(int(lookup[k]))
			triangles.append({"ids": ids, "surface": surface_index, "uv": uvs[start]})
	for iteration: int in 256:
		var neighbors: Dictionary = {}
		var incidents: Dictionary = {}
		var edge_faces: Dictionary = {}
		var slivers: Array[int] = []
		var candidates: Dictionary = {}
		for index: int in triangles.size():
			var ids: Array = triangles[index].ids
			for a: int in ids:
				if not neighbors.has(a):
					neighbors[a] = {}
					incidents[a] = []
				incidents[a].append(index)
			for edge: int in 3:
				var a: int = ids[edge]
				var b: int = ids[(edge + 1) % 3]
				neighbors[a][b] = true
				neighbors[b][a] = true
				var ek := Vector2i(mini(a, b), maxi(a, b))
				if not edge_faces.has(ek): edge_faces[ek] = []
				edge_faces[ek].append(index)
			var ab: float = points[ids[0]].distance_to(points[ids[1]])
			var bc: float = points[ids[1]].distance_to(points[ids[2]])
			var ca: float = points[ids[2]].distance_to(points[ids[0]])
			var area2: float = (points[ids[1]] - points[ids[0]]).cross(points[ids[2]] - points[ids[0]]).length()
			if area2 / maxf(ab, maxf(bc, ca)) > 0.0002: continue
			slivers.append(index)
			var shortest: int = 0 if ab <= bc and ab <= ca else (1 if bc <= ca else 2)
			for offset: int in 3:
				var edge: int = (shortest + offset) % 3
				var a: int = ids[edge]
				var b: int = ids[(edge + 1) % 3]
				candidates[Vector2i(a, b)] = true
				candidates[Vector2i(b, a)] = true
		var changed: bool = false
		for candidate: Vector2i in candidates:
			var a: int = candidate.x
			var b: int = candidate.y
			var common: int = 0
			for neighbor: int in neighbors[a]:
				if neighbors[b].has(neighbor): common += 1
			if common != 2: continue
			var replacement: Vector3 = points[a]
			var safe: bool = true
			var touched: Array = incidents[a].duplicate()
			for index: int in incidents[b]:
				if not touched.has(index): touched.append(index)
			for index: int in touched:
				var ids: Array = triangles[index].ids
				if ids.has(a) and ids.has(b): continue
				var before: Vector3 = (points[ids[1]] - points[ids[0]]).cross(points[ids[2]] - points[ids[0]])
				var longest: float = maxf(points[ids[0]].distance_to(points[ids[1]]), maxf(points[ids[1]].distance_to(points[ids[2]]), points[ids[2]].distance_to(points[ids[0]])))
				var resolved_plane: bool = before.length() / longest > 0.0001
				if resolved_plane and ids.has(b) and absf(before.normalized().dot(replacement - points[ids[0]])) > 0.0001:
					safe = false
					break
				var p: Array[Vector3] = []
				for id: int in ids: p.append(replacement if id == b else points[id])
				var after: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
				if after.length_squared() <= 1.0e-18 or (resolved_plane and after.dot(before) <= 0.0):
					safe = false
					break
			if not safe: continue
			var remaining: Array = []
			for triangle: Dictionary in triangles:
				var ids: Array = triangle.ids
				if ids.has(a) and ids.has(b): continue
				for corner: int in 3:
					if ids[corner] == b: ids[corner] = a
				remaining.append(triangle)
			triangles = remaining
			changed = true
			break
		if changed: continue
		# 短边折叠被邻面约束挡住时，翻转薄三角的最长边；不移动任何顶点。
		for index: int in slivers:
			var ids: Array = triangles[index].ids
			var longest_edge: int = 0
			for edge: int in 3:
				if points[ids[edge]].distance_squared_to(points[ids[(edge + 1) % 3]]) > points[ids[longest_edge]].distance_squared_to(points[ids[(longest_edge + 1) % 3]]): longest_edge = edge
			var a: int = ids[longest_edge]
			var b: int = ids[(longest_edge + 1) % 3]
			var c: int = ids[(longest_edge + 2) % 3]
			var incident: Array = edge_faces[Vector2i(mini(a, b), maxi(a, b))]
			if incident.size() != 2: continue
			var other: int = incident[0] if incident[1] == index else incident[1]
			if triangles[index].surface != triangles[other].surface or Vector2i(triangles[index].uv * 8.0) != Vector2i(triangles[other].uv * 8.0): continue
			var d: int = -1
			for id: int in triangles[other].ids:
				if id != a and id != b: d = id
			if d == -1 or d == c or neighbors[c].has(d): continue
			var normal: Vector3 = (points[triangles[other].ids[1]] - points[triangles[other].ids[0]]).cross(points[triangles[other].ids[2]] - points[triangles[other].ids[0]])
			if absf(normal.normalized().dot(points[c] - points[a])) > 0.0001: continue
			var first: Vector3 = (points[a] - points[c]).cross(points[d] - points[c])
			var second: Vector3 = (points[d] - points[c]).cross(points[b] - points[c])
			if first.dot(normal) <= 0.0 or second.dot(normal) <= 0.0: continue
			var first_height: float = first.length() / maxf(points[c].distance_to(points[a]), maxf(points[a].distance_to(points[d]), points[d].distance_to(points[c])))
			var second_height: float = second.length() / maxf(points[c].distance_to(points[d]), maxf(points[d].distance_to(points[b]), points[b].distance_to(points[c])))
			if minf(first_height, second_height) <= 0.0002: continue
			triangles[index].ids = [c, a, d]
			triangles[other].ids = [c, d, b]
			changed = true
			break
		if not changed: break
	for surface_index: int in surfaces.size():
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var uv := PackedVector2Array()
		for triangle: Dictionary in triangles:
			if int(triangle.surface) != surface_index: continue
			var ids: Array = triangle.ids
			var normal: Vector3 = -(points[ids[1]] - points[ids[0]]).cross(points[ids[2]] - points[ids[0]]).normalized()
			var cell: Vector2 = Vector2(floorf(triangle.uv.x * 8.0), floorf(triangle.uv.y * 8.0)) / 8.0
			for corner: int in 3:
				v.append(points[ids[corner]])
				n.append(normal)
				uv.append(cell + [Vector2(0.035, 0.035), Vector2(0.090, 0.035), Vector2(0.0625, 0.090)][corner])
		var arrays: Array = surfaces[surface_index].arrays
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv

## 量化后的反向重合三角为零厚度内隔片，只删除成对反向面；同向重复仍交给门禁拒绝。
static func _remove_canceling_faces(surfaces: Array) -> void:
	var faces: Dictionary = {}
	var removed: Dictionary = {}
	for surface_index: int in surfaces.size():
		var vertices: PackedVector3Array = surfaces[surface_index].arrays[Mesh.ARRAY_VERTEX]
		for start: int in range(0, vertices.size(), 3):
			var keys: Array[String] = [str(key(vertices[start])), str(key(vertices[start + 1])), str(key(vertices[start + 2]))]
			keys.sort()
			var tk: String = "|".join(keys)
			var normal: Vector3 = (vertices[start + 1] - vertices[start]).cross(vertices[start + 2] - vertices[start]).normalized()
			if faces.has(tk) and normal.dot(faces[tk].normal) < -0.99:
				removed[Vector2i(surface_index, start)] = true
				removed[faces[tk].index] = true
				faces.erase(tk)
			else: faces[tk] = {"normal": normal, "index": Vector2i(surface_index, start)}
	for surface_index: int in surfaces.size():
		var arrays: Array = surfaces[surface_index].arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var uv := PackedVector2Array()
		for start: int in range(0, vertices.size(), 3):
			if removed.has(Vector2i(surface_index, start)): continue
			for corner: int in 3:
				v.append(vertices[start + corner]); n.append(normals[start + corner]); uv.append(uvs[start + corner])
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv

## 只拆分真实边界长边上的同线顶点，不补洞、不重叠封盖。
static func _conform_boundaries(surfaces: Array) -> void:
	var edges: Dictionary = {}
	var points: Dictionary = {}
	for surface: Dictionary in surfaces:
		var vertices: PackedVector3Array = surface.arrays[Mesh.ARRAY_VERTEX]
		for start: int in range(0, vertices.size(), 3):
			for edge: int in 3:
				var a: Vector3 = vertices[start + edge]
				var b: Vector3 = vertices[start + (edge + 1) % 3]
				var sa: String = str(key(a))
				var sb: String = str(key(b))
				var ek: String = sa + ":" + sb if sa < sb else sb + ":" + sa
				if not edges.has(ek): edges[ek] = {"a": a, "b": b, "count": 0}
				edges[ek].count += 1
	for edge: Dictionary in edges.values():
		if int(edge.count) == 1:
			points[key(edge.a)] = edge.a
			points[key(edge.b)] = edge.b
	if points.is_empty(): return
	for surface: Dictionary in surfaces:
		var arrays: Array = surface.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var old_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var output := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for start: int in range(0, vertices.size(), 3):
			var boundary: Array[Vector3] = []
			for edge: int in 3:
				var a: Vector3 = vertices[start + edge]
				var b: Vector3 = vertices[start + (edge + 1) % 3]
				var delta: Vector3 = b - a
				var candidates: Array = [{"t": 0.0, "p": a}]
				for point: Vector3 in points.values():
					var t: float = (point - a).dot(delta) / delta.length_squared()
					if t > 0.00001 and t < 0.99999 and point.distance_squared_to(a + delta * t) <= 1.0e-10:
						candidates.append({"t": t, "p": point})
				candidates.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.t) < float(y.t))
				for candidate: Dictionary in candidates: boundary.append(candidate.p)
			var normal: Vector3 = -(vertices[start + 1] - vertices[start]).cross(vertices[start + 2] - vertices[start]).normalized()
			var cell: Vector2 = Vector2(floorf(old_uvs[start].x * 8.0), floorf(old_uvs[start].y * 8.0)) / 8.0
			# 仅沿已有边插点；吸附后的新扇心会使窄斜面偏折，双侧探针可能越入邻接实体。
			var triangles: Array = [[vertices[start], vertices[start + 1], vertices[start + 2]]]
			for point: Vector3 in boundary:
				if point == vertices[start] or point == vertices[start + 1] or point == vertices[start + 2]: continue
				var inserted: bool = false
				for index: int in triangles.size():
					var triangle: Array = triangles[index]
					for edge: int in 3:
						var a: Vector3 = triangle[edge]
						var b: Vector3 = triangle[(edge + 1) % 3]
						var c: Vector3 = triangle[(edge + 2) % 3]
						var delta: Vector3 = b - a
						var t: float = (point - a).dot(delta) / delta.length_squared()
						if t <= 0.00001 or t >= 0.99999 or point.distance_squared_to(a + delta * t) > 1.0e-10: continue
						triangles[index] = [a, point, c]
						triangles.append([point, b, c])
						inserted = true
						break
					if inserted: break
			for triangle: Array in triangles:
				if MeshBuilder._degenerate_triangle(triangle[0], triangle[1], triangle[2]): continue
				for corner: int in 3:
					output.append(triangle[corner])
					normals.append(normal)
					uvs.append(cell + [Vector2(0.035, 0.035), Vector2(0.090, 0.035), Vector2(0.0625, 0.090)][corner])
		arrays[Mesh.ARRAY_VERTEX] = output
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uvs

## 拓扑闭合并不证明是实体并集的边界；每个实际面还必须内实外空。
static func _audit_source_boundary(faces: PackedVector3Array, parts: Array) -> Dictionary:
	var sources: Array = []
	for part: Dictionary in parts:
		if not owns(str(part.id)): continue
		for record: Dictionary in part.mesh_records:
			var points := PackedVector3Array()
			var bounds := AABB()
			var initialized: bool = false
			var transform: Transform3D = Transform3D(Basis.IDENTITY, part.position) * record.transform
			for surface: int in record.mesh.get_surface_count():
				var arrays: Array = record.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				for index: int in indices.size() if not indices.is_empty() else vertices.size():
					var point: Vector3 = transform * vertices[indices[index] if not indices.is_empty() else index]
					bounds = bounds.expand(point) if initialized else AABB(point, Vector3.ZERO)
					initialized = true
					points.append(point * BOOLEAN_SCALE)
			var bvh := TriangleMesh.new()
			bvh.create_from_faces(points)
			sources.append({"bvh": bvh, "bounds": bounds})
	var errors: Array = []
	var count: int = 0
	for start: int in range(0, faces.size(), 3):
		var a: Vector3 = faces[start]
		var b: Vector3 = faces[start + 1]
		var c: Vector3 = faces[start + 2]
		var normal: Vector3 = -(b - a).cross(c - a).normalized()
		for weights: Vector3 in [Vector3.ONE / 3.0, Vector3(0.23, 0.31, 0.46)]:
			var center: Vector3 = a * weights.x + b * weights.y + c * weights.z
			var inner: bool = _inside_source_union(center - normal * 0.0001, sources)
			var outer: bool = _inside_source_union(center + normal * 0.0001, sources)
			if not inner or outer:
				count += 1
				if errors.size() < 12: errors.append({"triangle": start / 3, "point": str(center), "inner": inner, "outer": outer})
	return {"valid": count == 0, "samples": faces.size() / 3 * 2, "errors": count, "examples": errors, "probe_distance_m": 0.0001}

static func _inside_source_union(point: Vector3, sources: Array) -> bool:
	for source: Dictionary in sources:
		if not source.bounds.grow(0.000001).has_point(point): continue
		var votes: int = 0
		for direction: Vector3 in [Vector3(0.61391, 0.33173, 0.71629).normalized(), Vector3(-0.43719, 0.81113, -0.38971).normalized(), Vector3(0.29131, -0.53917, -0.79031).normalized()]:
			var origin: Vector3 = point * BOOLEAN_SCALE
			var crossings: int = 0
			for step: int in 128:
				var hit: Dictionary = source.bvh.intersect_ray(origin, direction)
				if hit.is_empty(): break
				crossings += 1
				origin = hit.position + direction * 0.001
			if crossings % 2 == 1: votes += 1
		if votes >= 2: return true
	return false

static func key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x / WELD), roundi(point.y / WELD), roundi(point.z / WELD))

static func audit_faces(faces: PackedVector3Array) -> Dictionary:
	var edges: Dictionary = {}
	var triangles: Dictionary = {}
	var adjacency: Dictionary = {}
	var volume: float = 0.0
	var duplicate: int = 0
	var degenerate: int = 0
	var nonfinite: int = 0
	for start: int in range(0, faces.size(), 3):
		var triangle: int = start / 3
		adjacency[triangle] = []
		var keys: Array[String] = []
		for corner: int in 3:
			var point: Vector3 = faces[start + corner]
			if not point.is_finite(): nonfinite += 1
			keys.append(str(key(point)))
		var cross: Vector3 = (faces[start + 1] - faces[start]).cross(faces[start + 2] - faces[start])
		if cross.length_squared() <= 1.0e-18 or keys[0] == keys[1] or keys[1] == keys[2] or keys[2] == keys[0]: degenerate += 1
		volume -= faces[start].dot(faces[start + 1].cross(faces[start + 2])) / 6.0
		var sorted: Array[String] = keys.duplicate()
		sorted.sort()
		var tk: String = "|".join(sorted)
		if triangles.has(tk): duplicate += 1
		triangles[tk] = true
		for edge: int in 3:
			var a: String = keys[edge]
			var b: String = keys[(edge + 1) % 3]
			var ek: String = a + ":" + b if a < b else b + ":" + a
			if not edges.has(ek): edges[ek] = {"triangles": [], "balance": 0}
			edges[ek].triangles.append(triangle)
			edges[ek].balance += 1 if a < b else -1
	var boundary: int = 0
	var nonmanifold: int = 0
	var reversed: int = 0
	for entry: Dictionary in edges.values():
		var incident: Array = entry.triangles
		if incident.size() == 1: boundary += 1
		elif incident.size() != 2: nonmanifold += 1
		if int(entry.balance) != 0: reversed += 1
		if incident.size() == 2:
			adjacency[incident[0]].append(incident[1])
			adjacency[incident[1]].append(incident[0])
	var components: int = 0
	var visited: Dictionary = {}
	for triangle: int in adjacency:
		if visited.has(triangle): continue
		components += 1
		var pending: Array = [triangle]
		visited[triangle] = true
		while not pending.is_empty():
			var current: int = pending.pop_back()
			for neighbor: int in adjacency[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)
	var valid: bool = not faces.is_empty() and boundary == 0 and nonmanifold == 0 and reversed == 0 and duplicate == 0 and degenerate == 0 and nonfinite == 0 and components == 1 and volume > 1.0e-8
	return {"valid": valid, "closed": boundary == 0 and nonmanifold == 0, "oriented": reversed == 0, "components": components, "boundary_edges": boundary, "nonmanifold_edges": nonmanifold, "orientation_errors": reversed, "duplicate_triangles": duplicate, "degenerate_triangles": degenerate, "nonfinite_vertices": nonfinite, "signed_volume": volume, "triangles": faces.size() / 3}
