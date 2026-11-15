@tool
extends RefCounted
## 结构大洞只针对立面；纯同步几何，不依赖SceneTree或全局随机流。
const SHAPES := ["ellipse", "jagged", "arch", "breach"]
const FACADES := ["front", "back", "left", "right"]
const FIELDS := ["enabled", "shape", "facade", "center_u", "center_y", "width", "height", "roughness", "seed"]

static func defaults() -> Dictionary:
	return {"enabled": false, "shape": "jagged", "facade": "front", "center_u": 0.5, "center_y": 1.7, "width": 3.8, "height": 2.8, "roughness": 0.25, "seed": 11013}

static func settings(recipe: Dictionary) -> Dictionary:
	var result: Dictionary = defaults()
	result.merge(recipe.get("structural_damage", {}), true)
	return result

static func active(recipe: Dictionary) -> bool:
	var d: Dictionary = settings(recipe)
	return bool(d.enabled) and float(d.width) > 0.0 and float(d.height) > 0.0

static func validate(recipe: Dictionary) -> String:
	var raw: Variant = recipe.get("structural_damage", {})
	if not raw is Dictionary: return "structural_damage必须是对象"
	for field: String in raw:
		if field not in FIELDS: return "不支持的结构损毁字段（roof/slab不支持）: " + field
	var d: Dictionary = settings(recipe)
	if not d.enabled is bool: return "structural_damage.enabled必须是布尔值"
	if d.shape not in SHAPES: return "结构大洞形状只支持ellipse/jagged/arch/breach"
	if d.facade not in FACADES: return "结构大洞只支持front/back/left/right；roof/slab明确不支持"
	for field: String in ["center_u", "center_y", "width", "height", "roughness", "seed"]:
		if not (d[field] is float or d[field] is int) or not is_finite(float(d[field])): return "结构大洞字段必须是有限数值: " + field
	if float(d.center_u) < 0.0 or float(d.center_u) > 1.0 or float(d.roughness) < 0.0 or float(d.roughness) > 1.0: return "结构大洞中心比例/粗糙度必须在0..1"
	if float(d.center_y) < 0.0 or float(d.center_y) > 96.0 or float(d.width) < 0.0 or float(d.width) > 48.0 or float(d.height) < 0.0 or float(d.height) > 96.0: return "结构大洞中心/尺寸越界"
	if float(d.seed) < 0.0 or float(d.seed) > 9007199254740991.0 or floorf(float(d.seed)) != float(d.seed): return "结构大洞seed必须是非负JSON安全整数"
	if active(recipe) and str(recipe.get("construction_mode", "modular_v1")) != "shell_v2": return "结构大洞只支持shell_v2"
	return ""

static func profile(d: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	if str(d.shape) == "arch":
		points.append(Vector2(-0.5, -0.5))
		points.append(Vector2(0.5, -0.5))
		for i: int in 13:
			var angle: float = float(i) * PI / 12.0
			points.append(Vector2(cos(angle) * 0.5, sin(angle) * 0.65 - 0.15))
	elif str(d.shape) == "breach":
		points = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.45, -0.1), Vector2(0.5, 0.34), Vector2(0.22, 0.5), Vector2(-0.18, 0.43), Vector2(-0.44, 0.5), Vector2(-0.36, 0.02)])
		for i: int in points.size(): points[i] *= 1.0 - rng.randf() * float(d.roughness) * 0.25
	else:
		for i: int in 24:
			var angle: float = TAU * float(i) / 24.0
			var radius: float = 0.5
			if str(d.shape) == "jagged": radius *= 1.0 - rng.randf() * float(d.roughness) * 0.55
			points.append(Vector2(cos(angle), sin(angle)) * radius)
	for i: int in points.size(): points[i] *= Vector2(float(d.width), float(d.height))
	return points

## center_u沿选中立面最长外侧run；返回root-local真实轮廓及贯穿体。
static func prepare(recipe: Dictionary, contours: Array, context: Dictionary, geometry: Script) -> Dictionary:
	if not active(recipe): return {"ok": true, "opening": {}, "mesh": null}
	var d: Dictionary = settings(recipe)
	var base: float = 0.0
	var floor_index: int = -1
	for floor: int in int(recipe.floors):
		var height: float = geometry._floor_value(recipe, floor, "floor_height")
		if float(d.center_y) >= base and float(d.center_y) < base + height:
			floor_index = floor
			break
		base += height
	if floor_index < 0: return {"ok": false, "reason": "结构洞中心不在立面内；roof/slab不支持"}
	var normal2: Vector2 = {"front": Vector2(0, -1), "back": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}[str(d.facade)]
	var polygon: Array = contours[floor_index]
	var start := Vector2.ZERO
	var axis := Vector2.ZERO
	var length: float = 0.0
	var outermost: float = -INF
	for i: int in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var direction: Vector2 = (b - a).normalized()
		if Vector2(direction.y, -direction.x).dot(normal2) < 0.99: continue
		var distance: float = a.dot(normal2)
		if distance > outermost + 0.0001 or (is_equal_approx(distance, outermost) and a.distance_to(b) > length):
			outermost = distance
			start = a
			axis = direction
			length = a.distance_to(b)
	if length <= 0.0: return {"ok": false, "reason": "选中立面无可用墙run"}
	var center2: Vector2 = start + axis * length * float(d.center_u)
	var center := Vector3(center2.x, float(d.center_y), center2.y)
	var outline: PackedVector2Array = profile(d)
	var depth: float = float(recipe.wall_thickness) + 0.85
	var normal := Vector3(normal2.x, 0, normal2.y)
	var tangent := Vector3(axis.x, 0, axis.y)
	var rings: Array = []
	var public_profile: Array = []
	for offset: float in [-depth, 1.2]:
		var ring: Array[Vector3] = []
		for p: Vector2 in outline:
			ring.append(geometry._map(center + tangent * p.x + Vector3.UP * p.y + normal * offset, context))
		rings.append(ring)
	for p: Vector2 in outline: public_profile.append(geometry._map(center + tangent * p.x + Vector3.UP * p.y, context))
	var buffer: Dictionary = geometry._buffer()
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	if indices.is_empty(): return {"ok": false, "reason": "结构洞轮廓无法三角化"}
	for side: int in 2:
		for i: int in range(0, indices.size(), 3):
			geometry._tri(buffer, rings[side][indices[i]], rings[side][indices[i + 1]], rings[side][indices[i + 2]], normal if side == 1 else -normal)
	for i: int in outline.size():
		var next: int = (i + 1) % outline.size()
		var delta: Vector2 = outline[next] - outline[i]
		geometry._quad(buffer, rings[0][i], rings[0][next], rings[1][next], rings[1][i], tangent * delta.y - Vector3.UP * delta.x)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer.v
	arrays[Mesh.ARRAY_NORMAL] = buffer.n
	arrays[Mesh.ARRAY_INDEX] = buffer.i
	var uv := PackedVector2Array()
	for p: Vector2 in buffer.uv: uv.append(Vector2(0.035, 0.035) + p * 0.055)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, geometry.MeshBuilder.shared_materials()["SEA_Matte"])
	var scale: float = geometry._scale_at(center.y, context)
	var actual_normal: Vector3 = Vector3(normal.x / scale, float(context.taper) * center.dot(normal) / (float(context.height) * scale), normal.z / scale).normalized()
	return {"ok": true, "mesh": mesh, "opening": {"id": "structural_damage_0", "facade": d.facade, "shape": d.shape, "center": geometry._map(center, context), "normal": actual_normal, "axis": tangent, "width": float(d.width) * scale, "height": float(d.height), "profile": public_profile, "coordinate_space": "root_local", "profile_space": "root_local", "protected": ["roof", "slab"], "seed": int(d.seed)}}

## 门窗组件与贯穿体实际投影相交时整套移除，避免残框悬浮；不是删除墙面。
static func overlaps(faces: PackedVector3Array, cutter: Mesh) -> bool:
	if faces.is_empty(): return false
	var bounds := AABB(faces[0], Vector3.ZERO)
	for point: Vector3 in faces: bounds = bounds.expand(point)
	if not bounds.intersects(cutter.get_aabb()): return false
	var bvh := TriangleMesh.new()
	bvh.create_from_faces(cutter.get_faces())
	for i: int in range(0, faces.size(), 3):
		for edge: int in 3:
			if not bvh.intersect_segment(faces[i + edge], faces[i + (edge + 1) % 3]).is_empty(): return true
		var center: Vector3 = (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		var hit: Dictionary = bvh.intersect_ray(center, Vector3(0.61391, 0.33173, 0.71629).normalized())
		if not hit.is_empty() and Vector3(hit.normal).dot(Vector3(0.61391, 0.33173, 0.71629)) > 0.0: return true
	return false
