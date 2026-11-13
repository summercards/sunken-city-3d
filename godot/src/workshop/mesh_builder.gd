@tool
extends RefCounted
## 原生参数网格源：闭合倒角、外向自定义法线与共享 8x8 色板。
## 这是 Native 参数源，不冒称 Blender 或其他 DCC 产物。

const Config = preload("res://src/workshop/architecture_config.gd")

## 只移动UV色格，保留有面积小岛及16px安全内缩；绝不复制或改写材质。
static func encode_cell_uv(source: PackedVector2Array, cell: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for uv: Vector2 in source:
		result.append(_palette_uv_with_mapping(uv, "selected", {"selected": {"row": cell[0], "column": cell[1]}}))
	return result

static func recolor_mesh(mesh: Mesh, settings: Dictionary, identity: String, role: String) -> ArrayMesh:
	var result := ArrayMesh.new()
	var cell: Array = Config.palette_cell(settings, identity, role)
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var local_uv := PackedVector2Array()
		for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
			var pixel: Vector2 = uv * 512.0
			local_uv.append((pixel - Vector2(floorf(pixel.x / CELL_PX), floorf(pixel.y / CELL_PX)) * CELL_PX - Vector2.ONE * SAFE_INSET_PX) / CELL_AREA_PX)
		arrays[Mesh.ARRAY_TEX_UV] = encode_cell_uv(local_uv, cell)
		arrays[Mesh.ARRAY_TEX_UV2] = arrays[Mesh.ARRAY_TEX_UV]
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, mesh.surface_get_material(surface))
	return result

## 共享材质的实例级着色参数只写入生成树的GeometryInstance3D；不修改四个公共ShaderMaterial。
static func apply_build_shading(build: Dictionary, recipe: Dictionary, _catalog: Dictionary) -> Dictionary:
	if not bool(build.get("ok", false)):
		return build
	var shared: Dictionary = shared_materials()
	var roles: Array[String] = ["SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission"]
	var root: Node = build.get("root") as Node
	if root == null:
		return build
	var shading: Dictionary = recipe.get("architecture", {}).get("shading", {}) as Dictionary
	var materials: Dictionary = shading.get("materials", {}) as Dictionary
	for raw_node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var node: MeshInstance3D = raw_node as MeshInstance3D
		if node == null or node.mesh == null:
			continue
		var node_roles: Dictionary = {}
		for surface: int in node.mesh.get_surface_count():
			var active: Material = node.get_active_material(surface)
			for role: String in roles:
				if active == shared.get(role):
					node_roles[role] = true
		if node_roles.size() != 1:
			# structure_union may contain multiple material surfaces. A single GeometryInstance3D
			# cannot carry different instance values per surface; keep shared shader defaults rather
			# than applying one role to the whole union.
			continue
		var role: String = str(node_roles.keys()[0])
		_apply_shading_instance(node, role, materials.get(role, {}) as Dictionary)
	return build

static func _apply_shading_instance(node: MeshInstance3D, role: String, settings: Dictionary) -> void:
	var prefix: String = role.trim_prefix("SEA_").to_lower()
	var role_index: int = ["SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission"].find(role)
	node.set_instance_shader_parameter("sea_material_role", role_index)
	var controls := Vector4(
		float(settings.get("roughness", -1.0)),
		float(settings.get("metallic", -1.0)),
		float(settings.get("specular", -1.0)),
		float(settings.get("transparency", -1.0)))
	node.set_instance_shader_parameter("sea_" + prefix + "_controls", controls)
	node.set_instance_shader_parameter("sea_" + prefix + "_emission_energy", float(settings.get("emission_energy", -1.0)))

## 会话与保存共用的作者构建边界：仅原生植物，外部prefab及其共享Mesh不改。
static func apply_build_palette(build: Dictionary, recipe: Dictionary, catalog: Dictionary) -> Dictionary:
	if not bool(build.get("ok", false)): return build
	for slot: Dictionary in build.slots:
		if str(slot.kind) != "plant": continue
		var definition: Dictionary = catalog.get("components", {}).get(str(slot.component_id), {})
		if str(definition.get("kind", "")) != "parametric": continue
		var role: String = str(definition.get("material_role", "SEA_Matte"))
		var settings: Dictionary = Config.palette_settings(recipe, "plant", role)
		if settings.is_empty(): continue
		var node: MeshInstance3D = build.root.get_node(str(slot.node_path)) as MeshInstance3D
		if node != null:
			node.mesh = recolor_mesh(node.mesh, settings, str(slot.id), role)
	return build

const TEXTURE_PATH := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const PALETTE_JSON_PATH := "res://data/workshop/palette_cells_v1.json"
const PALETTE_MAPPING_PATH := "res://data/workshop/palette_cells_v1.json"
const CELL_PX := 64.0
const SAFE_INSET_PX := 16.0
const CELL_AREA_PX := 32.0
const GEOMETRY_EPSILON := 1.0e-8
const GEOMETRY_EPSILON_SQ := 1.0e-16
const POSITION_WELD_EPSILON := 2.0e-6

static func rounded_box(size: Vector3, bevel: float, segments: int, palette: String = "timber", aging: float = 0.0, material_cache: Dictionary = {}, taper: float = 0.0) -> Dictionary:
	var extent := size * 0.5
	var min_half := minf(extent.x, minf(extent.y, extent.z))
	var b := clampf(bevel, 0.0, min_half * 0.9)
	var steps := clampi(segments, 1, 8)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# 六个平面面片；边界与 12 条真实圆角条带共用同一位置边界。
	_append_quad(vertices, normals, uvs, indices, Vector3(extent.x, -extent.y + b, -extent.z + b), Vector3(extent.x, extent.y - b, -extent.z + b), Vector3(extent.x, extent.y - b, extent.z - b), Vector3(extent.x, -extent.y + b, extent.z - b), Vector3.RIGHT)
	_append_quad(vertices, normals, uvs, indices, Vector3(-extent.x, -extent.y + b, extent.z - b), Vector3(-extent.x, extent.y - b, extent.z - b), Vector3(-extent.x, extent.y - b, -extent.z + b), Vector3(-extent.x, -extent.y + b, -extent.z + b), Vector3.LEFT)
	_append_quad(vertices, normals, uvs, indices, Vector3(-extent.x + b, extent.y, -extent.z + b), Vector3(-extent.x + b, extent.y, extent.z - b), Vector3(extent.x - b, extent.y, extent.z - b), Vector3(extent.x - b, extent.y, -extent.z + b), Vector3.UP)
	_append_quad(vertices, normals, uvs, indices, Vector3(-extent.x + b, -extent.y, extent.z - b), Vector3(-extent.x + b, -extent.y, -extent.z + b), Vector3(extent.x - b, -extent.y, -extent.z + b), Vector3(extent.x - b, -extent.y, extent.z - b), Vector3.DOWN)
	_append_quad(vertices, normals, uvs, indices, Vector3(-extent.x + b, -extent.y + b, extent.z), Vector3(extent.x - b, -extent.y + b, extent.z), Vector3(extent.x - b, extent.y - b, extent.z), Vector3(-extent.x + b, extent.y - b, extent.z), Vector3.BACK)
	_append_quad(vertices, normals, uvs, indices, Vector3(extent.x - b, -extent.y + b, -extent.z), Vector3(-extent.x + b, -extent.y + b, -extent.z), Vector3(-extent.x + b, extent.y - b, -extent.z), Vector3(extent.x - b, extent.y - b, -extent.z), Vector3.FORWARD)

	# 12 条边只沿角向细分；长轴保持一个长度区间，不作无效加面。
	for sign_y in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			_append_x_edge(vertices, normals, uvs, indices, extent, b, sign_y, sign_z, steps)
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			_append_y_edge(vertices, normals, uvs, indices, extent, b, sign_x, sign_z, steps)
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			_append_z_edge(vertices, normals, uvs, indices, extent, b, sign_x, sign_y, steps)

	# 八个球面角块：u=0 的极点用三角扇封口，避免原实现 u0=0 的整块剔除洞。
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			for sign_z in [-1.0, 1.0]:
				_append_corner(vertices, normals, uvs, indices, extent, b, sign_x, sign_y, sign_z, steps)

	# taper 先变换位置，再由实际 CW 三角重算外向法线。
	if absf(taper) > GEOMETRY_EPSILON:
		var taper_amount := clampf(taper, 0.0, 0.1)
		var height := size.y
		for index in vertices.size():
			var y_ratio := clampf((vertices[index].y + extent.y) / height, 0.0, 1.0)
			var xz_scale := 1.0 - taper_amount * y_ratio
			var point := vertices[index]
			var normal := normals[index]
			normals[index] = Vector3(normal.x / xz_scale, normal.y + taper_amount * (point.x * normal.x + point.z * normal.z) / (height * xz_scale), normal.z / xz_scale).normalized()
			vertices[index].x = point.x * xz_scale
			vertices[index].z = point.z * xz_scale
	# 位置焊接不合并UV/法线接缝，主体平面保持平、圆角保持平滑。
	_weld_vertices(vertices, normals, uvs, indices)
	_weld_vertices(vertices, normals, uvs, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = _encode_palette_uv(uvs, palette, aging)
	arrays[Mesh.ARRAY_TEX_UV2] = _encode_palette_uv(uvs, palette, aging)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material(palette, aging, material_cache))
	return {"mesh": mesh, "triangles": indices.size() / 3}

static func _append_x_edge(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, extent: Vector3, b: float, sign_y: float, sign_z: float, steps: int) -> void:
	for arc_step in range(steps):
		var a0 := float(arc_step) / float(steps) * PI * 0.5
		var a1 := float(arc_step + 1) / float(steps) * PI * 0.5
		var c_y := sign_y * (extent.y - b)
		var c_z := sign_z * (extent.z - b)
		var p0 := Vector3(-extent.x + b, c_y + sign_y * b * cos(a0), c_z + sign_z * b * sin(a0))
		var p1 := Vector3(extent.x - b, c_y + sign_y * b * cos(a0), c_z + sign_z * b * sin(a0))
		var p2 := Vector3(extent.x - b, c_y + sign_y * b * cos(a1), c_z + sign_z * b * sin(a1))
		var p3 := Vector3(-extent.x + b, c_y + sign_y * b * cos(a1), c_z + sign_z * b * sin(a1))
		var n0 := Vector3(0.0, sign_y * cos(a0), sign_z * sin(a0)).normalized()
		var n1 := Vector3(0.0, sign_y * cos(a1), sign_z * sin(a1)).normalized()
		_append_quad_normals(vertices, normals, uvs, indices, p0, p1, p2, p3, n0, n0, n1, n1)

static func _append_y_edge(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, extent: Vector3, b: float, sign_x: float, sign_z: float, steps: int) -> void:
	for arc_step in range(steps):
		var a0 := float(arc_step) / float(steps) * PI * 0.5
		var a1 := float(arc_step + 1) / float(steps) * PI * 0.5
		var c_x := sign_x * (extent.x - b)
		var c_z := sign_z * (extent.z - b)
		var p0 := Vector3(c_x + sign_x * b * cos(a0), -extent.y + b, c_z + sign_z * b * sin(a0))
		var p1 := Vector3(c_x + sign_x * b * cos(a0), extent.y - b, c_z + sign_z * b * sin(a0))
		var p2 := Vector3(c_x + sign_x * b * cos(a1), extent.y - b, c_z + sign_z * b * sin(a1))
		var p3 := Vector3(c_x + sign_x * b * cos(a1), -extent.y + b, c_z + sign_z * b * sin(a1))
		var n0 := Vector3(sign_x * cos(a0), 0.0, sign_z * sin(a0)).normalized()
		var n1 := Vector3(sign_x * cos(a1), 0.0, sign_z * sin(a1)).normalized()
		_append_quad_normals(vertices, normals, uvs, indices, p0, p1, p2, p3, n0, n0, n1, n1)

static func _append_z_edge(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, extent: Vector3, b: float, sign_x: float, sign_y: float, steps: int) -> void:
	for arc_step in range(steps):
		var a0 := float(arc_step) / float(steps) * PI * 0.5
		var a1 := float(arc_step + 1) / float(steps) * PI * 0.5
		var c_x := sign_x * (extent.x - b)
		var c_y := sign_y * (extent.y - b)
		var p0 := Vector3(c_x + sign_x * b * cos(a0), c_y + sign_y * b * sin(a0), -extent.z + b)
		var p1 := Vector3(c_x + sign_x * b * cos(a0), c_y + sign_y * b * sin(a0), extent.z - b)
		var p2 := Vector3(c_x + sign_x * b * cos(a1), c_y + sign_y * b * sin(a1), extent.z - b)
		var p3 := Vector3(c_x + sign_x * b * cos(a1), c_y + sign_y * b * sin(a1), -extent.z + b)
		var n0 := Vector3(sign_x * cos(a0), sign_y * sin(a0), 0.0).normalized()
		var n1 := Vector3(sign_x * cos(a1), sign_y * sin(a1), 0.0).normalized()
		_append_quad_normals(vertices, normals, uvs, indices, p0, p1, p2, p3, n0, n0, n1, n1)

static func _append_corner(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, extent: Vector3, b: float, sign_x: float, sign_y: float, sign_z: float, steps: int) -> void:
	if b <= GEOMETRY_EPSILON:
		return
	var center := Vector3(sign_x * (extent.x - b), sign_y * (extent.y - b), sign_z * (extent.z - b))
	var pole := center + Vector3(0.0, 0.0, sign_z * b)
	for v_step in range(steps):
		var v0 := float(v_step) / float(steps) * PI * 0.5
		var v1 := float(v_step + 1) / float(steps) * PI * 0.5
		var points0: Array[Vector3] = []
		var points1: Array[Vector3] = []
		var normals0: Array[Vector3] = []
		var normals1: Array[Vector3] = []
		for u_step in range(1, steps + 1):
			var u := float(u_step) / float(steps) * PI * 0.5
			var local0 := Vector3(sin(u) * cos(v0), sin(u) * sin(v0), cos(u))
			var local1 := Vector3(sin(u) * cos(v1), sin(u) * sin(v1), cos(u))
			var n0 := Vector3(sign_x * local0.x, sign_y * local0.y, sign_z * local0.z).normalized()
			var n1 := Vector3(sign_x * local1.x, sign_y * local1.y, sign_z * local1.z).normalized()
			points0.append(center + n0 * b)
			points1.append(center + n1 * b)
			normals0.append(n0)
			normals1.append(n1)
		# 每个 v 条带从极点起一枚三角扇面，再沿 u 方向补两个四边形。
		var pole_normal := Vector3(0.0, 0.0, sign_z)
		_append_triangle_normals(vertices, normals, uvs, indices, pole, points1[0], points0[0], pole_normal, normals1[0], normals0[0])
		for u_index in range(steps - 1):
			_append_quad_normals(vertices, normals, uvs, indices, points0[u_index], points0[u_index + 1], points1[u_index + 1], points1[u_index], normals0[u_index], normals0[u_index + 1], normals1[u_index + 1], normals1[u_index])

static func _degenerate_triangle(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var ab := b - a
	var ac := c - a
	var scale_sq := maxf(ab.length_squared(), ac.length_squared())
	return scale_sq == 0.0 or ab.cross(ac).length_squared() <= GEOMETRY_EPSILON_SQ * scale_sq * scale_sq

static func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, expected: Vector3) -> void:
	_append_quad_normals(vertices, normals, uvs, indices, a, b, c, d, expected, expected, expected, expected)

static func _append_quad_normals(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	if _degenerate_triangle(a, b, c) or _degenerate_triangle(a, c, d):
		return
	var cross := (b - a).cross(c - a)
	# Godot 前面按 CW；cross 与外法线同向时是 CCW，交换 b/d。
	if cross.dot((na + nb + nc + nd).normalized()) > 0.0:
		var point := b; b = d; d = point
		var normal := nb; nb = nd; nd = normal
	var base := vertices.size()
	vertices.append(a); vertices.append(b); vertices.append(c); vertices.append(d)
	normals.append(na.normalized()); normals.append(nb.normalized()); normals.append(nc.normalized()); normals.append(nd.normalized())
	uvs.append(Vector2(0.0, 0.0)); uvs.append(Vector2(1.0, 0.0)); uvs.append(Vector2(1.0, 1.0)); uvs.append(Vector2(0.0, 1.0))
	indices.append(base); indices.append(base + 1); indices.append(base + 2)
	indices.append(base); indices.append(base + 2); indices.append(base + 3)

static func _append_triangle_normals(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if _degenerate_triangle(a, b, c):
		return
	var expected := (na + nb + nc).normalized()
	if (b - a).cross(c - a).dot(expected) > 0.0:
		var point := b; b = c; c = point
		var normal := nb; nb = nc; nc = normal
	var base := vertices.size()
	vertices.append(a); vertices.append(b); vertices.append(c)
	normals.append(na.normalized()); normals.append(nb.normalized()); normals.append(nc.normalized())
	uvs.append(Vector2(0.0, 0.0)); uvs.append(Vector2(1.0, 0.0)); uvs.append(Vector2(0.5, 1.0))
	indices.append(base); indices.append(base + 1); indices.append(base + 2)

static func _rebuild_normals(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var accumulated: Array[Vector3] = []
	for index in vertices.size():
		accumulated.append(Vector3.ZERO)
	for triangle_start in range(0, indices.size(), 3):
		var ia := indices[triangle_start]
		var ib := indices[triangle_start + 1]
		var ic := indices[triangle_start + 2]
		var face := -(vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia]).normalized()
		accumulated[ia] += face; accumulated[ib] += face; accumulated[ic] += face
	normals.clear()
	for value in accumulated:
		normals.append(value.normalized())

static func plant_mesh(profile: String, growth_key: String, palette: String = "cozy", aging: float = 0.0, material_cache: Dictionary = {}) -> Dictionary:
	var size := _plant_size(profile, growth_key)
	var mapping := _load_palette_mapping()
	mapping = _mapping_for_aging(mapping, aging)
	var leaf_palette := "plant_leaf"
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var leaf_count := 6 if growth_key == "medium" else (3 if growth_key == "small" else 10)

	if profile == "moss":
		_append_moss(vertices, normals, uvs, indices, size, leaf_palette, mapping, leaf_count * 2 + 2)
	elif profile == "vine":
		_append_vine(vertices, normals, uvs, indices, size, leaf_palette, mapping, leaf_count)
	elif profile == "tree":
		_append_tree(vertices, normals, uvs, indices, size, leaf_palette, mapping, leaf_count)
	else:
		_append_shrub(vertices, normals, uvs, indices, size, leaf_palette, mapping, leaf_count)
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for point in vertices:
		bounds = bounds.expand(point)
	var anchor := Vector3(bounds.get_center().x, bounds.end.y if profile == "vine" else bounds.position.y, bounds.get_center().z)
	for index in vertices.size():
		vertices[index] -= anchor
	_weld_vertices(vertices, normals, uvs, indices)
	_weld_vertices(vertices, normals, uvs, indices)
	_rebuild_normals(vertices, normals, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs.duplicate()
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material(palette, aging, material_cache))
	return {"mesh": mesh, "triangles": indices.size() / 3}

static func _plant_size(profile: String, growth_key: String) -> Vector3:
	var base := Vector3(0.9, 1.25, 0.9)
	if profile == "vine":
		base = Vector3(0.22, 2.4, 0.22)
	elif profile == "tree":
		base = Vector3(1.8, 4.8, 1.8)
	elif profile == "moss":
		base = Vector3(1.6, 0.25, 1.6)
	var scale := 1.0
	if growth_key == "small":
		scale = 0.72
	elif growth_key == "large":
		scale = 1.28
	return base * scale

static func _weld_vertices(vertices: PackedVector3Array, _normals: PackedVector3Array, _uvs: PackedVector2Array, _indices: PackedInt32Array) -> void:
	var buckets: Dictionary = {}
	for index in vertices.size():
		var point := vertices[index]
		var key := Vector3i(floori(point.x / POSITION_WELD_EPSILON), floori(point.y / POSITION_WELD_EPSILON), floori(point.z / POSITION_WELD_EPSILON))
		var found := false
		for x in range(-1, 2):
			if found: break
			for y in range(-1, 2):
				if found: break
				for z in range(-1, 2):
					for candidate in buckets.get(key + Vector3i(x, y, z), []):
						if point.distance_squared_to(candidate) <= POSITION_WELD_EPSILON * POSITION_WELD_EPSILON:
							vertices[index] = candidate
							found = true
							break
					if found: break
		if not found:
			if not buckets.has(key): buckets[key] = []
			buckets[key].append(point)

static func _append_shrub(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, size: Vector3, palette: String, mapping: Dictionary, leaf_count: int) -> void:
	var stem_top := size.y * 0.48
	_append_tube(vertices, normals, uvs, indices, Vector3(0.0, 0.0, 0.0), Vector3(0.0, stem_top, 0.0), size.x * 0.075, size.x * 0.055, 6, "plant_stem", mapping)
	for leaf_index in leaf_count:
		var angle := float(leaf_index) / float(leaf_count) * TAU
		var branch_end := Vector3(cos(angle) * size.x * 0.30, size.y * (0.40 + float(leaf_index % 3) * 0.07), sin(angle) * size.z * 0.30)
		_append_tube(vertices, normals, uvs, indices, Vector3(0.0, size.y * 0.25, 0.0), branch_end, size.x * 0.038, size.x * 0.018, 5, "plant_stem", mapping)
		var direction := Vector3(cos(angle) * 0.72, 0.34 + float(leaf_index % 2) * 0.06, sin(angle) * 0.72).normalized()
		_append_leaf(vertices, normals, uvs, indices, branch_end, direction, size.x * 0.34, size.y * 0.28, size.x * 0.045, "plant_leaf", mapping)

static func _append_tree(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, size: Vector3, palette: String, mapping: Dictionary, leaf_count: int) -> void:
	var trunk_top := size.y * 0.60
	_append_tube(vertices, normals, uvs, indices, Vector3(0.0, 0.0, 0.0), Vector3(0.0, trunk_top, 0.0), size.x * 0.13, size.x * 0.07, 7, "plant_stem", mapping)
	for branch_index in leaf_count:
		var angle := float(branch_index) / float(leaf_count) * TAU
		var start := Vector3(0.0, size.y * (0.38 + float(branch_index % 2) * 0.08), 0.0)
		var end := Vector3(cos(angle) * size.x * 0.40, size.y * (0.58 + float(branch_index % 3) * 0.06), sin(angle) * size.z * 0.40)
		_append_tube(vertices, normals, uvs, indices, start, end, size.x * 0.065, size.x * 0.025, 6, "plant_stem", mapping)
	for leaf_index in leaf_count:
		var angle := float(leaf_index) / float(leaf_count) * TAU
		var base := Vector3(cos(angle) * size.x * 0.40, size.y * (0.58 + float(leaf_index % 3) * 0.06), sin(angle) * size.z * 0.40)
		var direction := Vector3(cos(angle) * 0.60, 0.45 + float(leaf_index % 2) * 0.1, sin(angle) * 0.60).normalized()
		_append_leaf(vertices, normals, uvs, indices, base, direction, size.x * 0.40, size.y * 0.22, size.x * 0.05, "plant_leaf", mapping)

static func _append_vine(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, size: Vector3, palette: String, mapping: Dictionary, leaf_count: int) -> void:
	var points: Array[Vector3] = []
	for segment in 5:
		var t := float(segment) / 4.0
		points.append(Vector3(sin(t * PI * 1.25) * size.x * 0.55, -t * size.y, cos(t * PI * 1.1) * size.z * 0.55))
	for segment in 4:
		var radius := size.x * lerpf(0.10, 0.045, float(segment) / 4.0)
		_append_tube(vertices, normals, uvs, indices, points[segment], points[segment + 1], radius, radius * 0.88, 5, "plant_stem", mapping)
	for leaf_index in leaf_count:
		var point_index := mini(4, 1 + leaf_index % 4)
		var base := points[point_index]
		var side := -1.0 if leaf_index % 2 == 0 else 1.0
		var direction := Vector3(side * 0.72, -0.18, 0.35 * side).normalized()
		_append_leaf(vertices, normals, uvs, indices, base, direction, size.x * 0.85, size.y * 0.095, size.x * 0.035, "plant_leaf", mapping)

static func _append_moss(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, size: Vector3, palette: String, mapping: Dictionary, lobes: int) -> void:
	var center_bottom := Vector3(0.0, 0.0, 0.0)
	var center_top := Vector3(0.0, size.y * 0.72, 0.0)
	for lobe in lobes:
		var a0 := float(lobe) / lobes * TAU
		var a1 := float(lobe + 1) / lobes * TAU
		var r0 := 0.46 + 0.08 * float(lobe % 2)
		var r1 := 0.46 + 0.08 * float((lobe + 1) % 2)
		var p0 := Vector3(cos(a0) * size.x * r0, 0.025, sin(a0) * size.z * r0)
		var p1 := Vector3(cos(a1) * size.x * r1, 0.025, sin(a1) * size.z * r1)
		var q0 := Vector3(cos(a0) * size.x * r0, size.y * (0.42 + 0.08 * float(lobe % 3)), sin(a0) * size.z * r0)
		var q1 := Vector3(cos(a1) * size.x * r1, size.y * (0.42 + 0.08 * float(((lobe + 1) % lobes) % 3)), sin(a1) * size.z * r1)
		var radial := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5)).normalized()
		_append_quad_palette(vertices, normals, uvs, indices, p0, p1, q1, q0, radial, palette, mapping)
		_append_triangle_palette(vertices, normals, uvs, indices, center_top, q0, q1, Vector3.UP, palette, mapping)
		_append_triangle_palette(vertices, normals, uvs, indices, center_bottom, p1, p0, Vector3.DOWN, palette, mapping)

static func _append_tube(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, from: Vector3, to: Vector3, radius_from: float, radius_to: float, sides: int, palette: String, mapping: Dictionary) -> void:
	var axis := (to - from).normalized()
	if axis.length_squared() < GEOMETRY_EPSILON:
		return
	var basis_u := axis.cross(Vector3.UP)
	if basis_u.length_squared() < GEOMETRY_EPSILON:
		basis_u = axis.cross(Vector3.RIGHT)
	basis_u = basis_u.normalized()
	var basis_v := basis_u.cross(axis).normalized()
	var from_ring: Array[Vector3] = []
	var to_ring: Array[Vector3] = []
	for side in sides:
		var angle := float(side) / float(sides) * TAU
		var radial := basis_u * cos(angle) + basis_v * sin(angle)
		from_ring.append(from + radial * radius_from)
		to_ring.append(to + radial * radius_to)
	for side in sides:
		var next := (side + 1) % sides
		_append_quad_palette(vertices, normals, uvs, indices, from_ring[side], from_ring[next], to_ring[next], to_ring[side], (from_ring[side] - from).normalized(), palette, mapping)
	_append_cap(vertices, normals, uvs, indices, from, from_ring, -axis, palette, mapping)
	_append_cap(vertices, normals, uvs, indices, to, to_ring, axis, palette, mapping)

static func _append_cap(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, center: Vector3, ring: Array[Vector3], expected: Vector3, palette: String, mapping: Dictionary) -> void:
	for side in ring.size():
		var next := (side + 1) % ring.size()
		_append_triangle_palette(vertices, normals, uvs, indices, center, ring[next], ring[side], expected, palette, mapping)

static func _append_leaf(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, base: Vector3, direction: Vector3, width: float, length: float, thickness: float, palette: String, mapping: Dictionary) -> void:
	var axis := direction.normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < GEOMETRY_EPSILON:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var normal := side.cross(axis).normalized()
	var outline: Array[Vector3] = [base, base + axis * length * 0.30 + side * width * 0.50, base + axis * length * 0.72 + side * width * 0.34, base + axis * length, base + axis * length * 0.72 - side * width * 0.34, base + axis * length * 0.30 - side * width * 0.50]
	var top_center := base + axis * length * 0.47 + normal * thickness
	var bottom_center := base + axis * length * 0.47 - normal * thickness
	for index in 6:
		var next := (index + 1) % 6
		_append_triangle_palette(vertices, normals, uvs, indices, top_center, outline[index] + normal * thickness, outline[next] + normal * thickness, normal, palette, mapping)
		_append_triangle_palette(vertices, normals, uvs, indices, bottom_center, outline[next] - normal * thickness, outline[index] - normal * thickness, -normal, palette, mapping)
		_append_quad_palette(vertices, normals, uvs, indices, outline[index] + normal * thickness, outline[next] + normal * thickness, outline[next] - normal * thickness, outline[index] - normal * thickness, (outline[next] - outline[index]).cross(normal).normalized(), palette, mapping)

static func _append_quad_palette(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, expected: Vector3, palette: String, mapping: Dictionary) -> void:
	var start := vertices.size()
	_append_quad_normals(vertices, normals, uvs, indices, a, b, c, d, expected, expected, expected, expected)
	for index in range(start, vertices.size()):
		uvs[index] = _palette_uv_with_mapping(uvs[index], palette, mapping)

static func _append_triangle_palette(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, expected: Vector3, palette: String, mapping: Dictionary) -> void:
	var start := vertices.size()
	_append_triangle_normals(vertices, normals, uvs, indices, a, b, c, expected, expected, expected)
	for index in range(start, vertices.size()):
		uvs[index] = _palette_uv_with_mapping(uvs[index], palette, mapping)

static func _load_palette_mapping() -> Dictionary:
	var paths := [PALETTE_JSON_PATH, PALETTE_MAPPING_PATH]
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			if parsed.get("semantics", null) is Dictionary:
				return parsed.semantics.duplicate(true)
			if parsed.get("cells", null) is Array:
				var by_name := {}
				for cell in parsed.cells:
					if cell is Dictionary:
						by_name[str(cell.get("name", ""))] = cell
				var result := {}
				for semantic in ["timber", "timber_dark", "timber_aged", "slab", "slab_aged", "cozy", "plant_leaf", "plant_leaf_aged", "plant_stem", "glass", "white"]:
					var name: String = str({"timber": "wood", "timber_dark": "wood_dark", "timber_aged": "darkwood", "slab": "wood_mid", "slab_aged": "stone", "cozy": "cream", "plant_leaf": "leaf_mid", "plant_leaf_aged": "leaf_dark", "plant_stem": "bark", "glass": "ice", "white": "white"}.get(semantic, "cream"))
					if by_name.has(name): result[semantic] = by_name[name]
				return result
	return {}

static func _mapping_for_aging(mapping: Dictionary, aging: float) -> Dictionary:
	var result := mapping.duplicate(true)
	if aging >= 0.35:
		for pair in [["timber", "timber_aged"], ["timber_dark", "timber_aged"], ["slab", "slab_aged"], ["plant_leaf", "plant_leaf_aged"]]:
			if result.has(pair[1]): result[pair[0]] = result[pair[1]]
	return result

static func _encode_palette_uv(source: PackedVector2Array, palette: String, aging: float = 0.0) -> PackedVector2Array:
	var mapping := _mapping_for_aging(_load_palette_mapping(), aging)
	var result := PackedVector2Array()
	for uv in source:
		result.append(_palette_uv_with_mapping(uv, palette, mapping))
	return result

## 连续壳专用分级老化，旧modular与植物的映射保持原样；只选公共PNG已有色格。
## 主线程可在semantics覆盖这些键，不需要新增/复制材质或改PNG。
static func _shell_aging_mapping(mapping: Dictionary, aging: float) -> Dictionary:
	var result: Dictionary = _mapping_for_aging(mapping, aging)
	if aging <= 0.0: return result
	var stage: String = "cozy_aged_light" if aging < 0.35 else ("cozy_aged_medium" if aging < 0.70 else "cozy_aged_heavy")
	# 坐标来自公共v008：stone / mint_white / gray / darkwood，均是现有纯色格。
	var defaults: Dictionary = {
		"cozy_aged_light": mapping.get("slab_aged", {"row": 0, "column": 3}),
		"cozy_aged_medium": {"row": 0, "column": 5},
		"cozy_aged_heavy": {"row": 7, "column": 3},
		"cozy_weathering": mapping.get("timber_aged", {"row": 1, "column": 6})}
	result["cozy"] = mapping.get(stage, defaults[stage])
	result["cozy_weathering"] = mapping.get("cozy_weathering", defaults.cozy_weathering)
	return result

static func _encode_shell_palette_uv(source: PackedVector2Array, palette: String, aging: float) -> PackedVector2Array:
	var mapping: Dictionary = _shell_aging_mapping(_load_palette_mapping(), aging)
	var result: PackedVector2Array = PackedVector2Array()
	for uv in source:
		result.append(_palette_uv_with_mapping(uv, palette, mapping))
	return result

static func _palette_uv_with_mapping(source_uv: Vector2, palette: String, mapping: Dictionary) -> Vector2:
	var cell: Dictionary = mapping.get(palette, mapping.get("cozy", {"row": 0, "column": 0}))
	var row := clampi(int(cell.get("row", 0)), 0, 7)
	var column := clampi(int(cell.get("column", 0)), 0, 7)
	var local_x := clampf(source_uv.x, 0.0, 1.0)
	var local_y := clampf(source_uv.y, 0.0, 1.0)
	var pixel_x := float(column) * CELL_PX + SAFE_INSET_PX + local_x * CELL_AREA_PX
	var pixel_y_top := float(row) * CELL_PX + SAFE_INSET_PX + local_y * CELL_AREA_PX
	return Vector2(pixel_x / 512.0, pixel_y_top / 512.0)

## 与正式场景引用完全相同的四个 .tres，不能按色格复制材质或修改共享参数。
static var _shared_scene_materials: Dictionary = {}

static func shared_materials() -> Dictionary:
	if _shared_scene_materials.is_empty():
		for pair: Array in [["SEA_Matte", "res://assets/materials/solar_cabin/sunny_matte.tres"], ["SEA_Metal", "res://assets/materials/solar_cabin/sunny_metal.tres"], ["SEA_Gloss", "res://assets/materials/solar_cabin/sunny_gloss.tres"], ["SEA_Emission", "res://assets/materials/solar_cabin/sunny_emission.tres"]]:
			_shared_scene_materials[pair[0]] = load(str(pair[1])) as ShaderMaterial
	# 浅拷贝字典，保留四个Resource的同一身份；不允许调用者擦除公共缓存。
	return _shared_scene_materials.duplicate()

static func material(palette: String, _aging: float, cache: Dictionary = {}, role: String = "") -> ShaderMaterial:
	var material_role: String = role if not role.is_empty() else ("SEA_Gloss" if palette == "glass" else "SEA_Matte")
	if cache.has(material_role):
		return cache[material_role] as ShaderMaterial
	var result: ShaderMaterial = shared_materials().get(material_role) as ShaderMaterial
	assert(result != null, "未知共享材质角色: " + material_role)
	cache[material_role] = result
	return result
