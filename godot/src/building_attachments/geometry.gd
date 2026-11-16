extends RefCounted
## 原创原生低面几何。所有顶点烘入米制根空间，最终仅按材质角色合批。
## 实体凸件各自产生凸代理；中空件逐壁段代理，绝不以总包围盒跨洞。

const Catalog = preload("res://src/building_attachments/catalog.gd")
const ROLES := ["SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission"]
const SEGMENTS := 10
var buckets: Dictionary = {}
var parts: Array[Dictionary] = []
var proxies: Array[Dictionary] = []
var errors: Array[String] = []
var dimensions := Vector3.ONE
var colors: Dictionary = {}
var active_part: Dictionary = {}
var active_transform := Transform3D.IDENTITY
var all_bounds := AABB()
var has_bounds := false
var role: String = "SEA_Matte"
var cell: int = 0

func _init(recipe: Dictionary) -> void:
	dimensions = Vector3(float(recipe.dimensions.width), float(recipe.dimensions.height), float(recipe.dimensions.depth)) * float(recipe.scale)
	colors = recipe.colors.duplicate(true)
	for material_role: String in ROLES:
		buckets[material_role] = {"vertices": [], "normals": [], "uv": [], "indices": []}

func begin(name: String, material_role: String, center: Vector3, size: Vector3, rotation: Vector3, kind: String, taper: float, solid: bool) -> void:
	role = material_role
	cell = int(colors[role])
	active_transform = Transform3D(Basis.from_euler(rotation), center)
	active_part = {
		"name": name, "kind": kind, "material_role": role,
		"dimensions": vec(size), "center": vec(center), "rotation_euler": vec(rotation),
		"taper": taper, "rho": taper, "bevel_segments": 1,
		"bevel_width_m": minf(size[size.min_axis_index()] * 0.16, 0.02),
		"taper_along": size.max_axis_index(), "solid": solid,
		"bottom": vec(size), "top": vec(size * (1.0 - taper)),
		"contacts": [], "contact_verification": "pending_source_contact_audit",
		"triangle_start": buckets[role].indices.size() / 3, "triangle_count": 0,
		"source": "original_native_code", "no_volume": false
	}
	parts.append(active_part)

func contact(host: String, mode: String = "clearance", clearance_m: float = 0.008) -> void:
	active_part.contacts.append({"attached_to": host, "mode": mode, "clearance_m": clearance_m, "verification": "declared_pending_contact_audit"})

func require_connection(host: String, point: Vector3) -> void:
	active_part.required_connection = true
	active_part.contacts.append({"attached_to": host, "mode": "embedded_support", "clearance_m": 0.0,
		"witness": vec(point), "verification": "pending_mesh_witness"})

func _contains_point(part: Dictionary, point: Vector3) -> bool:
	var bucket: Dictionary = buckets[part.material_role]
	var direction := Vector3(0.8123, 0.3719, 0.4491).normalized()
	var hits: Array[float] = []
	for i: int in range(int(part.triangle_start) * 3, (int(part.triangle_start) + int(part.triangle_count)) * 3, 3):
		var a: Vector3 = from_vec(bucket.vertices[int(bucket.indices[i])])
		var b: Vector3 = from_vec(bucket.vertices[int(bucket.indices[i + 1])])
		var c: Vector3 = from_vec(bucket.vertices[int(bucket.indices[i + 2])])
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		var plane_distance: float = normal.dot(point - a)
		if absf(plane_distance) <= 0.00001:
			var ab: Vector3 = b - a
			var ac: Vector3 = c - a
			var ap: Vector3 = point - normal * plane_distance - a
			var denominator: float = ab.dot(ab) * ac.dot(ac) - ab.dot(ac) * ab.dot(ac)
			var v: float = (ac.dot(ac) * ap.dot(ab) - ab.dot(ac) * ap.dot(ac)) / denominator
			var w: float = (ab.dot(ab) * ap.dot(ac) - ab.dot(ac) * ap.dot(ab)) / denominator
			if minf(1.0 - v - w, minf(v, w)) >= -0.00001:
				return true
		var hit: Variant = Geometry3D.ray_intersects_triangle(point, direction, a, b, c)
		if hit != null:
			var distance: float = point.distance_to(hit)
			var duplicate: bool = false
			for previous: float in hits:
				if absf(previous - distance) <= 0.00001:
					duplicate = true
					break
			if not duplicate:
				hits.append(distance)
	return hits.size() % 2 == 1

func triangle(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if not errors.is_empty():
		return
	if not a.is_finite() or not b.is_finite() or not c.is_finite() or not outward.is_finite():
		errors.append("非有限三角面：" + str(active_part.get("name", "")))
		return
	var cross: Vector3 = (b - a).cross(c - a)
	if not cross.is_finite() or cross.length() < 0.000000001:
		errors.append("退化三角面：" + str(active_part.get("name", "")))
		return
	# 输入先按数学外法线定向，再转成Godot正面顺时针绕序。
	var normal: Vector3 = cross.normalized()
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	var transformed_normal: Vector3 = (active_transform.basis * normal).normalized()
	var bucket: Dictionary = buckets[role]
	var start: int = bucket.vertices.size()
	var column: int = cell % 8
	var row: int = cell / 8
	var uv_base := Vector2(float(column * 64 + 16) / 512.0, float(row * 64 + 16) / 512.0)
	var uv_size: float = 32.0 / 512.0
	var uv_points := [uv_base, uv_base + Vector2(uv_size, 0), uv_base + Vector2(0, uv_size)]
	var points := [a, c, b]
	for i: int in range(3):
		var point: Vector3 = active_transform * points[i]
		bucket.vertices.append(vec(point))
		bucket.normals.append(vec(transformed_normal))
		bucket.uv.append([uv_points[i].x, uv_points[i].y])
		bucket.indices.append(start + i)
		if not has_bounds:
			all_bounds = AABB(point, Vector3.ZERO)
			has_bounds = true
		else:
			all_bounds = all_bounds.expand(point)
	active_part.triangle_count += 1

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	triangle(a, b, c, outward)
	triangle(a, c, d, outward)

func proxy(points: Array) -> void:
	if not errors.is_empty():
		return
	if points.size() < 4 or not bool(active_part.get("solid", false)):
		errors.append("凸代理须属于实体且至少包含4个顶点：" + str(active_part.get("name", "")))
		return
	var transformed: Array = []
	for value: Variant in points:
		if not value is Vector3:
			errors.append("凸代理顶点必须为Vector3：" + str(active_part.name))
			return
		var point: Vector3 = value
		var world_point: Vector3 = active_transform * point
		if not point.is_finite() or not world_point.is_finite():
			errors.append("凸代理顶点必须为有限坐标：" + str(active_part.name))
			return
		transformed.append(vec(world_point))
	proxies.append({"part": active_part.name, "kind": "convex", "points": transformed})

func box(name: String, center: Vector3, size: Vector3, material_role: String = "SEA_Matte", rotation: Vector3 = Vector3.ZERO, solid: bool = true, taper: float = 0.035, beveled: bool = true, taper_axis: int = -1) -> void:
	begin(name, material_role, center, size, rotation, "beveled_tapered_prism" if beveled else "glyph_stroke_prism", taper, solid)
	var axis: int = size.max_axis_index() if taper_axis < 0 else taper_axis
	active_part.taper_along = axis
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var top_dimensions: Vector3 = size
	top_dimensions[u] *= 1.0 - taper
	top_dimensions[v] *= 1.0 - taper
	active_part.top = vec(top_dimensions)
	var half_u: float = size[u] * 0.5
	var half_v: float = size[v] * 0.5
	var bevel: float = minf(half_u, half_v) * 0.22
	active_part.bevel_width_m = bevel if beveled else 0.0
	active_part.bevel_segments = 1 if beveled else 0
	if not beveled:
		active_part.bevel_exception = "原创字形实体笔画保留直角轮廓，单字128面预算内不伪报倒角"
	var outline: Array[Vector2] = []
	if beveled:
		outline = [Vector2(-half_u + bevel, -half_v), Vector2(half_u - bevel, -half_v), Vector2(half_u, -half_v + bevel), Vector2(half_u, half_v - bevel), Vector2(half_u - bevel, half_v), Vector2(-half_u + bevel, half_v), Vector2(-half_u, half_v - bevel), Vector2(-half_u, -half_v + bevel)]
	else:
		outline = [Vector2(-half_u, -half_v), Vector2(half_u, -half_v), Vector2(half_u, half_v), Vector2(-half_u, half_v)]
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for point: Vector2 in outline:
		var bottom := Vector3.ZERO
		bottom[axis] = -size[axis] * 0.5
		bottom[u] = point.x
		bottom[v] = point.y
		var top: Vector3 = bottom
		top[axis] = size[axis] * 0.5
		top[u] *= 1.0 - taper
		top[v] *= 1.0 - taper
		lower.append(bottom)
		upper.append(top)
	for i: int in range(outline.size()):
		var j: int = (i + 1) % outline.size()
		var outward: Vector3 = (lower[i] + lower[j] + upper[i] + upper[j]) * 0.25
		outward[axis] = 0.0
		quad(lower[i], lower[j], upper[j], upper[i], outward)
	for i: int in range(1, outline.size() - 1):
		var normal := Vector3.ZERO
		normal[axis] = -1.0
		triangle(lower[0], lower[i], lower[i + 1], normal)
		triangle(upper[0], upper[i], upper[i + 1], -normal)
	if solid:
		var points: Array[Vector3] = lower.duplicate()
		points.append_array(upper)
		proxy(points)

func beam(name: String, a: Vector3, b: Vector3, thickness: float, material_role: String = "SEA_Metal", solid: bool = true) -> void:
	var direction: Vector3 = b - a
	var basis: Basis = Basis.looking_at(direction.normalized(), Vector3.RIGHT if absf(direction.normalized().y) > 0.95 else Vector3.UP)
	box(name, (a + b) * 0.5, Vector3(thickness, thickness, direction.length()), material_role, basis.get_euler(), solid, 0.048, true, 2)
	active_part.form_role = "rod_bar"
	active_part.taper_along = 2
	active_part.bottom = [thickness, thickness, direction.length()]
	active_part.top = [thickness * 0.952, thickness * 0.952, direction.length()]

func round_part(name: String, center: Vector3, bottom_radius: float, top_radius: float, length: float, material_role: String = "SEA_Metal", rotation: Vector3 = Vector3.ZERO, hollow: bool = false, missing: int = 0, solid: bool = true) -> void:
	begin(name, material_role, center, Vector3(bottom_radius * 2.0, length, bottom_radius * 2.0), rotation, "open_tapered_tube" if hollow else "tapered_drum", 1.0 - top_radius / bottom_radius, solid)
	active_part.taper_along = 1
	active_part.top = [top_radius * 2.0, length, top_radius * 2.0]
	active_part.d_bottom = bottom_radius * 2.0
	active_part.d_top = top_radius * 2.0
	active_part.radial_segments = SEGMENTS
	active_part.missing_sectors = missing
	active_part.bevel_segments = 0
	active_part.bevel_exception = "十段圆截面低面曲面，不伪造圆筒倒角"
	var count: int = SEGMENTS - missing
	var wall: float = minf(bottom_radius * 0.17, 0.045)
	var all_points: Array[Vector3] = []
	for i: int in range(count):
		var angle_a: float = TAU * float(i) / float(SEGMENTS)
		var angle_b: float = TAU * float(i + 1) / float(SEGMENTS)
		var va := Vector3(cos(angle_a), 0, sin(angle_a))
		var vb := Vector3(cos(angle_b), 0, sin(angle_b))
		var a: Vector3 = va * bottom_radius + Vector3.DOWN * length * 0.5
		var b: Vector3 = vb * bottom_radius + Vector3.DOWN * length * 0.5
		var c: Vector3 = vb * top_radius + Vector3.UP * length * 0.5
		var d: Vector3 = va * top_radius + Vector3.UP * length * 0.5
		quad(a, b, c, d, va + vb)
		if hollow or missing > 0:
			var ia: Vector3 = va * (bottom_radius - wall) + Vector3.DOWN * length * 0.5
			var ib: Vector3 = vb * (bottom_radius - wall) + Vector3.DOWN * length * 0.5
			var ic: Vector3 = vb * maxf(0.001, top_radius - wall) + Vector3.UP * length * 0.5
			var id: Vector3 = va * maxf(0.001, top_radius - wall) + Vector3.UP * length * 0.5
			quad(ia, id, ic, ib, -va - vb)
			quad(a, ia, ib, b, Vector3.DOWN)
			quad(d, c, ic, id, Vector3.UP)
			if missing > 0 and i == 0:
				quad(a, d, id, ia, -Vector3(-va.z, 0, va.x))
			if missing > 0 and i == count - 1:
				quad(b, ib, ic, c, Vector3(-vb.z, 0, vb.x))
			if solid:
				proxy([a, b, c, d, ia, ib, ic, id])
		else:
			all_points.append_array([a, b, c, d])
	# 实体端面仅一次扇形三角化，圆心不会变成碰撞洞。
	if not hollow and missing == 0:
		for i: int in range(1, SEGMENTS - 1):
			var a0 := Vector3(bottom_radius, -length * 0.5, 0)
			var ai := Vector3(cos(TAU * i / SEGMENTS) * bottom_radius, -length * 0.5, sin(TAU * i / SEGMENTS) * bottom_radius)
			var aj := Vector3(cos(TAU * (i + 1) / SEGMENTS) * bottom_radius, -length * 0.5, sin(TAU * (i + 1) / SEGMENTS) * bottom_radius)
			triangle(a0, ai, aj, Vector3.DOWN)
			var t0 := Vector3(top_radius, length * 0.5, 0)
			var ti := Vector3(cos(TAU * i / SEGMENTS) * top_radius, length * 0.5, sin(TAU * i / SEGMENTS) * top_radius)
			var tj := Vector3(cos(TAU * (i + 1) / SEGMENTS) * top_radius, length * 0.5, sin(TAU * (i + 1) / SEGMENTS) * top_radius)
			triangle(t0, ti, tj, Vector3.UP)
		if solid:
			proxy(all_points)

func pipe_segment(name: String, a: Vector3, b: Vector3, radius: float, missing: int = 0) -> void:
	var direction: Vector3 = (b - a).normalized()
	var basis: Basis = Basis.IDENTITY
	if direction.dot(Vector3.UP) < -0.999:
		basis = Basis(Vector3.RIGHT, PI)
	elif direction.dot(Vector3.UP) < 0.999:
		basis = Basis(Vector3.UP.cross(direction).normalized(), acos(clampf(Vector3.UP.dot(direction), -1.0, 1.0)))
	round_part(name, (a + b) * 0.5, radius, radius * 0.95, a.distance_to(b), "SEA_Metal", basis.get_euler(), true, missing)

func panel(name: String, polygon: Array[Vector2], z_center: float, thickness: float, material_role: String = "SEA_Matte", solid: bool = true) -> void:
	begin(name, material_role, Vector3(0, 0, z_center), Vector3(dimensions.x, dimensions.y, thickness), Vector3.ZERO, "original_extruded_polygon", 0.025, solid)
	active_part.bevel_segments = 0
	active_part.bevel_exception = "自定义箭头/拱牌轮廓使用实体薄挤出；外围框有单段倒角"
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(PackedVector2Array(polygon))
	var points: Array[Vector3] = []
	for i: int in range(0, triangles.size(), 3):
		var pa: Vector2 = polygon[triangles[i]]
		var pb: Vector2 = polygon[triangles[i + 1]]
		var pc: Vector2 = polygon[triangles[i + 2]]
		triangle(Vector3(pa.x, pa.y, -thickness * 0.5), Vector3(pb.x, pb.y, -thickness * 0.5), Vector3(pc.x, pc.y, -thickness * 0.5), Vector3.FORWARD)
		triangle(Vector3(pa.x * 0.975, pa.y, thickness * 0.5), Vector3(pb.x * 0.975, pb.y, thickness * 0.5), Vector3(pc.x * 0.975, pc.y, thickness * 0.5), Vector3.BACK)
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var fa := Vector3(a.x, a.y, -thickness * 0.5)
		var fb := Vector3(b.x, b.y, -thickness * 0.5)
		var ba := Vector3(a.x * 0.975, a.y, thickness * 0.5)
		var bb := Vector3(b.x * 0.975, b.y, thickness * 0.5)
		quad(fa, ba, bb, fb, Vector3(b.y - a.y, a.x - b.x, 0))
		points.append_array([fa, fb, ba, bb])
	if solid:
		# 非凸轮廓逐三角挤出代理，避免箭头凹角被凸包封死。
		for i: int in range(0, triangles.size(), 3):
			var prism: Array[Vector3] = []
			for j: int in range(3):
				var p: Vector2 = polygon[triangles[i + j]]
				prism.append(Vector3(p.x, p.y, -thickness * 0.5))
				prism.append(Vector3(p.x * 0.975, p.y, thickness * 0.5))
			proxy(prism)

func validate() -> bool:
	if not errors.is_empty():
		return false
	if not has_bounds or parts.is_empty() or not all_bounds.position.is_finite() or not all_bounds.size.is_finite() or all_bounds.size[all_bounds.size.min_axis_index()] <= 0.0:
		errors.append("几何为空或包围范围无效")
		return false
	var proxy_parts: Dictionary = {}
	for item: Dictionary in proxies:
		proxy_parts[item.part] = true
	for part: Dictionary in parts:
		if int(part.triangle_count) <= 0 or (bool(part.solid) and not proxy_parts.has(part.name)):
			errors.append("部件未完成或实体缺少凸代理：" + str(part.name))
			continue
		var bucket: Dictionary = buckets[part.material_role]
		var edges: Dictionary = {}
		for i: int in range(int(part.triangle_start) * 3, (int(part.triangle_start) + int(part.triangle_count)) * 3, 3):
			var keys: Array[String] = []
			for j: int in range(3):
				var point: Vector3 = from_vec(bucket.vertices[int(bucket.indices[i + j])])
				keys.append("%d,%d,%d" % [roundi(point.x * 10000), roundi(point.y * 10000), roundi(point.z * 10000)])
			for j: int in range(3):
				var pair: Array[String] = [keys[j], keys[(j + 1) % 3]]
				pair.sort()
				var key: String = "|".join(pair)
				edges[key] = int(edges.get(key, 0)) + 1
		for count: int in edges.values():
			if count != 2:
				errors.append("部件存在开放或非流形边：" + str(part.name))
				break
	var named: Dictionary = {}
	for part: Dictionary in parts:
		named[part.name] = part
	for part: Dictionary in parts:
		var verified: int = 0
		for item: Dictionary in part.contacts:
			if item.get("verification") != "pending_mesh_witness":
				continue
			var host: Dictionary = named.get(item.attached_to, {})
			var point: Vector3 = from_vec(item.witness)
			if host.is_empty() or not _contains_point(part, point) or not _contains_point(host, point):
				errors.append("装配支持点未同时位于双方实际网格：%s -> %s" % [part.name, item.attached_to])
				continue
			item.verification = "verified_mesh_containment_witness"
			verified += 1
		if verified > 0:
			part.contact_verification = "partial_verified_mesh_witness_not_whole_assembly"
	return errors.is_empty()

func recenter() -> Vector3:
	var offset := Vector3(all_bounds.get_center().x, all_bounds.position.y, all_bounds.get_center().z)
	for material_role: String in ROLES:
		var bucket: Dictionary = buckets[material_role]
		for i: int in range(bucket.vertices.size()):
			bucket.vertices[i] = vec(from_vec(bucket.vertices[i]) - offset)
	for part: Dictionary in parts:
		part.center = vec(from_vec(part.center) - offset)
		for item: Dictionary in part.contacts:
			if item.has("witness"):
				item.witness = vec(from_vec(item.witness) - offset)
	for item: Dictionary in proxies:
		for i: int in range(item.points.size()):
			item.points[i] = vec(from_vec(item.points[i]) - offset)
	all_bounds.position -= offset
	return offset

func snapshot() -> Dictionary:
	var meshes: Array[Dictionary] = []
	for material_role: String in ROLES:
		if buckets[material_role].indices.is_empty():
			continue
		var mesh: Dictionary = buckets[material_role].duplicate(true)
		mesh.material_role = material_role
		mesh.uv_layer = "PaletteUV"
		meshes.append(mesh)
	return {"schema": "sea.building_attachments.native_geometry", "schema_version": 1,
		"coordinate_system": {"up": "+Y", "front": "-Z", "origin": "bottom_center", "units": "meter", "winding": "godot_clockwise"},
		"meshes": meshes, "source_parts": parts.duplicate(true), "collision_proxies": proxies.duplicate(true),
		"bounds": {"position": vec(all_bounds.position), "size": vec(all_bounds.size)}}

static func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func from_vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
