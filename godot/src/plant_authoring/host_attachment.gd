@tool
extends RefCounted
## 宿主只读适配层。所有几何、洞口与 plant_to_host 均在宿主根局部空间。

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const TrunkPath = preload("res://src/plant_authoring/trunk_path.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const ROOT_GAP := 0.002
const CONTACT_LIMIT := 0.02
const EPSILON := 0.000001
const SAFE_NODES = ["Node", "Node3D", "MeshInstance3D", "StaticBody3D", "CollisionShape3D", "Marker3D"]

var host: Node3D
var openings: Array[Dictionary] = []
var surfaces: Array[Dictionary] = []

static func audit_scene(packed: PackedScene, seen: Dictionary = {}) -> String:
	if packed == null:
		return "宿主不是 PackedScene"
	if seen.has(packed):
		return "宿主含循环场景引用"
	seen[packed] = true
	var state := packed.get_state()
	if state.get_connection_count() > 0:
		return "只读宿主不接受信号连接"
	var base := state.get_base_scene_state()
	if base != null:
		return "请使用已保存的独立 building.tscn，不接受继承场景"
	for index in state.get_node_count():
		var type := str(state.get_node_type(index))
		var instance := state.get_node_instance(index)
		if instance != null:
			var reason := audit_scene(instance, seen)
			if not reason.is_empty(): return reason
		elif not SAFE_NODES.has(type):
			return "宿主节点类型不在只读白名单：" + type
		for property in state.get_node_property_count(index):
			var key := str(state.get_node_property_name(index, property))
			var value: Variant = state.get_node_property_value(index, property)
			if key == "top_level" and value == true:
				return "宿主不接受 top_level 节点"
			if key == "transform" and (not value is Transform3D or not _valid_transform(value)):
				return "宿主节点变换非法"
			if key == "script" and value != null:
				return "禁止带脚本的宿主：" + str(state.get_node_name(index))
			if not _safe_value(value, {}):
				return "宿主属性含脚本或可执行资源：" + key
	seen.erase(packed)
	return ""

static func _safe_value(value: Variant, seen: Dictionary) -> bool:
	if value is Script or value is Callable or value is Signal: return false
	if value is Resource:
		if seen.has(value): return true
		seen[value] = true
		if value.get_script() != null or value is PackedScene: return false
		for property in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				if not _safe_value(value.get(property.name), seen): return false
	elif value is Dictionary:
		for key in value.keys():
			if not _safe_value(key, seen) or not _safe_value(value[key], seen): return false
	elif value is Array:
		for item in value:
			if not _safe_value(item, seen): return false
	return not (value is Object and not value is Resource)

func bind_host(node: Node3D) -> Dictionary:
	# 已实例化节点入口仅供可信调用者；文件入口必须先 audit_scene，不能事后去脚本。
	var records: Array[Dictionary] = []
	if node == null or not _valid_transform(node.transform): return _fail("宿主根变换非法")
	var reason := _collect(node, node.transform.affine_inverse(), records)
	if not reason.is_empty(): return _fail(reason)
	if records.is_empty(): return _fail("宿主没有可检查的 Mesh / Collision 三角形")
	var holes: Array[Dictionary] = []
	for key in ["damage_openings", "openings"]:
		var values: Variant = node.get_meta(key, [])
		if not values is Array: return _fail(key + " 必须是数组")
		for entry in values:
			if not entry is Dictionary: continue
			var normal: Variant = entry.get("normal", entry.get("outward"))
			if not entry.get("center") is Vector3 or not normal is Vector3: continue
			if not entry.center.is_finite() or not normal.is_finite() or normal.length() < 0.001: continue
			var hole: Dictionary = entry.duplicate(true)
			hole["normal"] = normal
			hole["height"] = entry.get("height", entry.get("clear_height", 1.0))
			hole["depth"] = entry.get("wall_thickness", entry.get("depth", 0.5))
			hole["source"] = key
			hole["label"] = str(hole.get("id", "洞口")) + (" · 破墙候选" if key == "damage_openings" else " · 门窗候选（须检测玻璃/门扇）")
			holes.append(hole)
	host = node
	surfaces = records
	openings = holes
	return {"ok": true, "reason": "只读宿主已加载；洞口元数据不等于可穿，须执行粗干检测", "openings": openings.duplicate(true), "surface_count": surfaces.size()}

func _collect(node: Node, parent_transform: Transform3D, records: Array[Dictionary]) -> String:
	if node.get_script() != null: return "宿主包含脚本节点"
	if not SAFE_NODES.has(node.get_class()): return "不支持的宿主节点：" + node.get_class()
	var transform := parent_transform
	if node is Node3D:
		if node.top_level: return "宿主不接受 top_level 节点：" + str(node.name)
		if not _valid_transform(node.transform): return "宿主节点变换非法：" + str(node.name)
		transform = parent_transform * node.transform
		if not _valid_transform(transform): return "宿主累计变换非法：" + str(node.name)
	# bind 时传入的根不计其 transform；递归由调用者传入根的逆矩阵抵消。
	var faces := PackedVector3Array()
	var solid: Shape3D
	if node is MeshInstance3D and node.mesh != null:
		faces = node.mesh.get_faces()
	elif node is CollisionShape3D and node.shape != null and not node.disabled:
		solid = node.shape if not node.shape is ConcavePolygonShape3D else null
		if node.shape is ConcavePolygonShape3D:
			faces = node.shape.get_faces()
		else:
			var mesh: PrimitiveMesh
			if node.shape is BoxShape3D:
				mesh = BoxMesh.new()
				mesh.size = node.shape.size
			elif node.shape is SphereShape3D:
				mesh = SphereMesh.new()
				mesh.radius = node.shape.radius
				mesh.height = node.shape.radius * 2.0
			elif node.shape is CylinderShape3D:
				mesh = CylinderMesh.new()
				mesh.top_radius = node.shape.radius
				mesh.bottom_radius = node.shape.radius
				mesh.height = node.shape.height
			elif node.shape is CapsuleShape3D:
				mesh = CapsuleMesh.new()
				mesh.radius = node.shape.radius
				mesh.height = node.shape.height
			if mesh != null:
				faces = mesh.get_faces()
				solid = node.shape
		if faces.is_empty(): return "无法三角化宿主碰撞体（请保存三角网格碰撞）：" + str(node.name)
	if not faces.is_empty():
		var bounds := AABB(transform * faces[0], Vector3.ZERO)
		for index in faces.size():
			faces[index] = transform * faces[index]
			if not faces[index].is_finite(): return "宿主含非法几何：" + str(node.name)
			bounds = bounds.expand(faces[index])
		records.append({"name": str(node.name), "faces": faces, "bounds": bounds, "shape": solid, "inverse": transform.affine_inverse()})
	for child in node.get_children():
		var reason := _collect(child, transform, records)
		if not reason.is_empty(): return reason
	return ""

func propose_path(recipe: Dictionary, opening_index: int) -> Dictionary:
	var reason := Recipe.validate(recipe)
	if not reason.is_empty(): return _fail(reason)
	if opening_index < 0 or opening_index >= openings.size(): return _fail("请先选择洞口")
	var hole: Dictionary = openings[opening_index]
	var center: Vector3 = hole.center
	var normal: Vector3 = hole.normal.normalized()
	var outward := Vector3(normal.x, 0, normal.z).normalized()
	if outward.length() < 0.9: return _fail("洞口不是可用的侧墙开口")
	var radius := float(recipe.trunk_radius)
	var depth := float(hole.get("wall_depth", hole.get("depth", 0.5)))
	var reach := maxf(0.8, depth + radius + 0.25)
	var origin := center - outward * (reach + radius + 0.35)
	var support := _support_below(origin)
	if support.is_empty(): return _fail("树根下方未找到真实水平支撑面，请选择有楼板的洞口")
	origin.y = float(support.height) + ROOT_GAP
	var rise := maxf(0.12, minf(float(hole.get("height", 1.0)) * 0.18, 0.45))
	# 保持洞心为第 3 个控制点；第一段竖直，实际根环不因倾斜切进楼板。
	var inside := Vector3(origin.x, center.y - rise, origin.z)
	var outside := center + outward * reach + Vector3.UP * rise
	var crown := center + outward * (reach + float(recipe.crown_radius) + 0.5)
	crown.y = origin.y + float(recipe.height)
	var path: Array = []
	for point: Vector3 in [origin, inside, center, outside, crown]:
		var local := point - origin
		path.append({"x": local.x, "y": local.y, "z": local.z})
	path[0] = {"x": 0.0, "y": 0.0, "z": 0.0}
	path[-1].y = float(recipe.height)
	reason = TrunkPath.validate(path, float(recipe.height))
	if not reason.is_empty(): return _fail("洞口路径跨度不足；请调整树高或选择较低洞口，不会削树：" + reason)
	return {"ok": true, "trunk_path": path, "plant_to_host": Transform3D(Basis.IDENTITY, origin), "opening_id": str(hole.get("id", ""))}

func check_clearance(recipe: Dictionary, plant_to_host: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var reason := Recipe.validate(recipe)
	if not reason.is_empty(): return _fail(reason)
	if surfaces.is_empty(): return _fail("未载入可检查宿主")
	if not _valid_transform(plant_to_host) or not plant_to_host.basis.is_equal_approx(plant_to_host.basis.orthonormalized()) or plant_to_host.basis.determinant() < 0.99: return _fail("宿主相对变换仅接受有限、无缩放镜像的刚体变换")
	var points := TrunkPath.points(recipe)
	var frames := Geometry.tube_frames(points)
	var rings: Array[PackedVector3Array] = []
	for index in points.size():
		var ring := PackedVector3Array()
		var radius := float(recipe.trunk_radius) * lerpf(1.0, 0.065, pow(points[index].y / float(recipe.height), 0.82))
		for side in 12:
			var angle := TAU * float(side) / 12.0
			ring.append(plant_to_host * (points[index] + (frames[index].x * cos(angle) + frames[index].y * sin(angle)) * radius))
		rings.append(ring)
	var support_heights: Array[float] = []
	for surface in surfaces:
		support_heights.append(_root_support_height(surface, plant_to_host.origin, rings[0]))
	# 胶囊保守筛查仍覆盖每一段；仅真实支撑面接触以带端面管的顶点半空间复核。
	var scale := 1.0
	var checked := 0
	for index in range(points.size() - 1):
		var a := plant_to_host * points[index]
		var b := plant_to_host * points[index + 1]
		var t := points[index].y / float(recipe.height)
		var radius := float(recipe.trunk_radius) * lerpf(1.0, 0.065, pow(t, 0.82)) * scale + 0.005
		var capsule_bounds := AABB(a, Vector3.ZERO).expand(b).grow(radius)
		for surface_index in surfaces.size():
			var surface: Dictionary = surfaces[surface_index]
			# 实体包含判断不能依赖到外壳的距离；凹三角网格只表示表面，不参与 inside。
			if surface.shape != null:
				var probes := PackedVector3Array([a, b])
				probes.append_array(rings[index])
				probes.append_array(rings[index + 1])
				for probe in probes:
					if _inside_shape(surface.shape, surface.inverse * probe):
						return {"ok": false, "reason": "主干位于实体碰撞体内部：" + str(surface.name), "node": surface.name, "segment": index, "radius": radius, "triangles_checked": checked}
			if not capsule_bounds.intersects(surface.bounds): continue
			var faces: PackedVector3Array = surface.faces
			for face in range(0, faces.size(), 3):
				var p := faces[face]
				var q := faces[face + 1]
				var r := faces[face + 2]
				if not capsule_bounds.intersects(AABB(p, Vector3.ZERO).expand(q).expand(r).grow(0.00001)): continue
				checked += 1
				if _segment_triangle_distance(a, b, p, q, r) <= radius:
					var support_y := support_heights[surface_index]
					var face_normal := (q - p).cross(r - p).normalized()
					if is_finite(support_y) and absf(face_normal.y) > 0.99999 and maxf(p.y, maxf(q.y, r.y)) <= support_y + EPSILON and _tube_above_support(rings[index], rings[index + 1], a, b, support_y):
						continue
					var glass := "玻璃/门扇阻挡；元数据洞口不代表实际可穿" if "glass" in str(surface.name).to_lower() or "door" in str(surface.name).to_lower() else "墙体/窗框/楼板或碰撞体阻挡"
					return {"ok": false, "reason": "%s：%s；主干段 %d，检测半径 %.3fm（含 5mm 余量）。请改路径/相对位置或宿主洞口，不会自动削树。" % [glass, surface.name, index, radius], "node": surface.name, "segment": index, "radius": radius, "triangles_checked": checked}
	return {"ok": true, "reason": "粗干与宿主 Mesh/Collision 三角形间隙预检通过（不含枝叶、不代替视觉验收）", "triangles_checked": checked}

static func _valid_transform(value: Transform3D) -> bool:
	return value.is_finite() and is_finite(value.basis.determinant()) and absf(value.basis.determinant()) >= EPSILON and value.affine_inverse().is_finite()

func _support_below(origin: Vector3) -> Dictionary:
	var height := -INF
	for surface in surfaces:
		height = maxf(height, _surface_below(surface, origin))
	return {"height": height} if is_finite(height) else {}

static func _surface_below(surface: Dictionary, origin: Vector3) -> float:
	var height := -INF
	var faces: PackedVector3Array = surface.faces
	var bottom := Vector3(origin.x, minf(surface.bounds.position.y - 1.0, origin.y - 1.0), origin.z)
	for face in range(0, faces.size(), 3):
		var a := faces[face]
		var b := faces[face + 1]
		var c := faces[face + 2]
		# 水平楼板才可作为平根端面的支撑；不把墙或斜屋面当作地板。
		if absf((b - a).cross(c - a).normalized().y) < 0.99999: continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(origin, bottom, a, b, c)
		if hit is Vector3: height = maxf(height, hit.y)
	return height

static func _root_support_height(surface: Dictionary, root: Vector3, ring: PackedVector3Array) -> float:
	var height := _surface_below(surface, root + Vector3.UP * CONTACT_LIMIT)
	if not is_finite(height) or root.y < height - EPSILON: return -INF
	# 根截面每个顶点都须在同一真实支撑面的上方；不能只让中心线站在板边或孔上。
	for point in ring:
		if point.y < height - EPSILON: return -INF
		var below := _surface_below(surface, Vector3(point.x, height + CONTACT_LIMIT, point.z))
		if not is_finite(below) or absf(below - height) > EPSILON: return -INF
	return height

static func _tube_above_support(first: PackedVector3Array, second: PackedVector3Array, a: Vector3, b: Vector3, height: float) -> bool:
	# 实际十二边形管侧面及两端面均是这些顶点的凸组合。
	# 整个有端面管在板顶半空间内，才可消除胶囊端球穿板的假阳性。
	if minf(a.y, b.y) < height - EPSILON: return false
	for ring in [first, second]:
		for point: Vector3 in ring:
			if point.y < height - EPSILON: return false
	return true

static func _inside_shape(shape: Shape3D, point: Vector3) -> bool:
	if shape is BoxShape3D:
		var half: Vector3 = shape.size * 0.5
		return absf(point.x) < half.x - EPSILON and absf(point.y) < half.y - EPSILON and absf(point.z) < half.z - EPSILON
	if shape is SphereShape3D:
		return point.length() < shape.radius - EPSILON
	if shape is CylinderShape3D:
		return Vector2(point.x, point.z).length() < shape.radius - EPSILON and absf(point.y) < shape.height * 0.5 - EPSILON
	if shape is CapsuleShape3D:
		var half_axis := maxf(0.0, shape.height * 0.5 - shape.radius)
		var axis_point := Vector3(0.0, clampf(point.y, -half_axis, half_axis), 0.0)
		return point.distance_to(axis_point) < shape.radius - EPSILON
	return false

static func _segment_triangle_distance(a: Vector3, b: Vector3, p: Vector3, q: Vector3, r: Vector3) -> float:
	if Geometry3D.segment_intersects_triangle(a, b, p, q, r) != null: return 0.0
	var distance := minf(_point_triangle_distance(a, p, q, r), _point_triangle_distance(b, p, q, r))
	for edge in [[p, q], [q, r], [r, p]]:
		var closest := Geometry3D.get_closest_points_between_segments(a, b, edge[0], edge[1])
		distance = minf(distance, closest[0].distance_to(closest[1]))
	return distance

static func _point_triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() > 1.0e-16:
		normal = normal.normalized()
		var projected := point - normal * (point - a).dot(normal)
		if (b - a).cross(projected - a).dot(normal) >= -0.000001 and (c - b).cross(projected - b).dot(normal) >= -0.000001 and (a - c).cross(projected - c).dot(normal) >= -0.000001:
			return point.distance_to(projected)
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))

static func encode_transform(value: Transform3D) -> Array:
	# 列主序 4×4，plant 局部 -> host 根局部；与宿主自身世界变换无关。
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z, 0.0, value.basis.y.x, value.basis.y.y, value.basis.y.z, 0.0, value.basis.z.x, value.basis.z.y, value.basis.z.z, 0.0, value.origin.x, value.origin.y, value.origin.z, 1.0]

static func decode_transform(data: Variant) -> Dictionary:
	if not data is Array or data.size() != 16: return _fail("相对变换必须是列主序 4×4 matrix")
	for value in data:
		if not (value is int or value is float) or not is_finite(float(value)): return _fail("matrix 必须为有限数")
	if data[3] != 0.0 or data[7] != 0.0 or data[11] != 0.0 or data[15] != 1.0: return _fail("matrix 非仿射变换")
	var value := Transform3D(Basis(Vector3(data[0], data[1], data[2]), Vector3(data[4], data[5], data[6]), Vector3(data[8], data[9], data[10])), Vector3(data[12], data[13], data[14]))
	if not value.basis.is_equal_approx(value.basis.orthonormalized()) or value.basis.determinant() < 0.99: return _fail("仅接受不缩放、不镜像的刚体相对变换")
	return {"ok": true, "transform": value}

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
