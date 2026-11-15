@tool
extends Node3D
class_name PlantWindRuntime
## 只消费 World 风；不注册 owner，不依赖配方、生成器或编辑器。

const SHADER_PATH := "res://src/plant_authoring/leaf.gdshader"
const FOLIAGE_SHADER_PATH := "res://src/plant_authoring/leaf_card.gdshader"
const VOLUME_SHADER_PATH := "res://src/plant_authoring/leaf_volume.gdshader"
const OWNER_GROUP := "vegetation_wind_owner"
const DEFAULT_STRENGTH := 1.1
const DEFAULT_DIRECTION := Vector2(0.86, 0.5)
const FIRST_PREPARE_GEOMETRY_TOLERANCE := {
	"vertices": 0.0, "indices": 0.0, "normals": 0.0002, "uv": 0.0, "uv2": 0.0
}
const PREPARED_GEOMETRY_META := "plant_wind_geometry_snapshot"
var _materials: Array[ShaderMaterial] = []
var _elapsed := 0.0

func _ready() -> void:
	# 编辑器只允许调用者显式采样；打开或加入场景不能准备网格、改材质或推进时钟。
	if Engine.is_editor_hint():
		set_process(false)
		return
	_materials = prepare(self)
	# 在 owner 之后采样，避免同一帧落后一拍。
	process_priority = 100
	_update_wind(0.0)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_visible_in_tree():
		_update_wind(delta)

func _update_wind(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var tree := get_tree()
	var owners := tree.get_nodes_in_group(OWNER_GROUP) if tree != null else []
	var wind_owner: Node = owners[0] if owners.size() == 1 else null
	if wind_owner != null:
		sample_at(float(wind_owner.get("elapsed")), float(wind_owner.get("strength")), wind_owner.get("direction"))
	else:
		sample_at(_elapsed + minf(delta, 0.1))

## 确定帧入口；不推进 World 时钟，可在未入树实例上调用。
func sample_at(seconds: float, strength: float = 1.1, direction: Vector2 = Vector2(0.86, 0.5)) -> void:
	if not is_finite(seconds) or not is_finite(strength) or not direction.is_finite():
		return
	if _materials.is_empty():
		_materials = prepare(self)
	_elapsed = seconds
	apply_sample(_materials, seconds, strength, direction)

static func apply_sample(materials: Array[ShaderMaterial], seconds: float, strength: float = 1.1, direction: Vector2 = Vector2(0.86, 0.5), enabled: bool = true) -> void:
	var heading := direction.normalized()
	for material in materials:
		material.set_shader_parameter("preview_wind", enabled)
		material.set_shader_parameter("local_time", seconds)
		material.set_shader_parameter("world_wind_strength", maxf(strength, 0.0))
		material.set_shader_parameter("world_wind_direction", heading)

## 预览和旁车共用；仅复制当前模型的网格/材质，公共贴图与 shader 始终外链。
static func prepare(root: Node) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	_prepare_node(root, materials)
	return materials

static func _prepare_node(node: Node, materials: Array[ShaderMaterial]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		# 动态旁车实例在加入场景树后会再次走 _ready；已准备的网格不能二次复制，
		# 否则每次 sample_at/prepare 都可能改变资源身份并污染几何快照。
		if bool(node.get_meta("plant_wind_prepared", false)):
			if not _matches_prepared_snapshot(node):
				node.set_meta("plant_wind_prepare_rejected", "prepared geometry changed")
			for surface in node.mesh.get_surface_count():
				var existing := node.get_active_material(surface) as ShaderMaterial
				if existing != null and not materials.has(existing): materials.append(existing)
			for child in node.get_children():
				_prepare_node(child, materials)
			return
		var source: Mesh = node.mesh
		var mesh := ArrayMesh.new()
		mesh.resource_local_to_scene = true
		var overrides: Array[Material] = []
		for surface in source.get_surface_count():
			var material: Material = node.get_active_material(surface)
			var arrays := source.surface_get_arrays(surface)
			if material is ShaderMaterial and material.shader != null and material.shader.resource_path in [SHADER_PATH, FOLIAGE_SHADER_PATH, VOLUME_SHADER_PATH]:
				var copy := material.duplicate(true) as ShaderMaterial
				copy.shader = material.shader
				for uniform: Dictionary in material.shader.get_shader_uniform_list():
					var value: Variant = material.get_shader_parameter(uniform.name)
					if value is Texture2D or value is Texture3D or value is TextureLayered:
						copy.set_shader_parameter(uniform.name, value)
				copy.resource_local_to_scene = true
				if not bool(material.get_shader_parameter("wind_vertex_weights")):
					arrays[Mesh.ARRAY_COLOR] = _weights(arrays, material.resource_name)
				copy.set_shader_parameter("wind_vertex_weights", true)
				materials.append(copy)
				material = copy
			mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
			mesh.surface_set_material(surface, material)
			overrides.append(material)
		var source_snapshot := _mesh_geometry_snapshot(source)
		var prepared_snapshot := _mesh_geometry_snapshot(mesh)
		var reason := _first_prepare_geometry_reason(source_snapshot, prepared_snapshot)
		if not reason.is_empty():
			node.set_meta("plant_wind_prepare_rejected", reason)
			for child in node.get_children():
				_prepare_node(child, materials)
			return
		node.mesh = mesh
		node.material_override = null
		for surface in overrides.size():
			node.set_surface_override_material(surface, overrides[surface])
		node.set_meta("plant_wind_prepared", true)
		# metadata 会随 PackedScene 保存，只保留逐字段摘要，不能重复序列化整份网格。
		node.set_meta(PREPARED_GEOMETRY_META, _geometry_digest(prepared_snapshot))
	for child in node.get_children():
		_prepare_node(child, materials)

static func _mesh_geometry_snapshot(mesh: Mesh) -> Array:
	var result: Array = []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		result.append({
			"vertices": arrays[Mesh.ARRAY_VERTEX],
			"normals": arrays[Mesh.ARRAY_NORMAL],
			"uv": arrays[Mesh.ARRAY_TEX_UV],
			"uv2": arrays[Mesh.ARRAY_TEX_UV2],
			"indices": arrays[Mesh.ARRAY_INDEX]
		})
	return result

static func _first_prepare_geometry_reason(source: Array, prepared: Array) -> String:
	if source.size() != prepared.size():
		return "surface count changed: %d -> %d" % [source.size(), prepared.size()]
	for surface in source.size():
		for field in FIRST_PREPARE_GEOMETRY_TOLERANCE:
			var left: Variant = source[surface].get(field)
			var right: Variant = prepared[surface].get(field)
			if (left == null) != (right == null):
				return "missing %s on surface %d" % [field, surface]
			if left == null:
				continue
			if left.size() != right.size():
				return "%s count changed on surface %d: %d -> %d" % [field, surface, left.size(), right.size()]
			var maximum := 0.0
			for index in left.size():
				var error: float = absf(float(left[index]) - float(right[index])) if field == "indices" else left[index].distance_to(right[index])
				maximum = maxf(maximum, error)
			if maximum > float(FIRST_PREPARE_GEOMETRY_TOLERANCE[field]):
				return "%s error %s exceeds %s on surface %d" % [field, str(maximum), str(FIRST_PREPARE_GEOMETRY_TOLERANCE[field]), surface]
	return ""

static func _geometry_digest(snapshot: Array) -> Array:
	var result: Array = []
	for surface: Dictionary in snapshot:
		var fields: Dictionary = {}
		for field in FIRST_PREPARE_GEOMETRY_TOLERANCE:
			# 带类型/长度的原始 Variant 字节，不量化、不用有损文本或容差。
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			digest.update(var_to_bytes(surface.get(field)))
			fields[field] = digest.finish().hex_encode()
		result.append(fields)
	return result

static func _matches_prepared_snapshot(node: MeshInstance3D) -> bool:
	if not node.has_meta(PREPARED_GEOMETRY_META):
		return false
	return _geometry_digest(_mesh_geometry_snapshot(node.mesh)) == node.get_meta(PREPARED_GEOMETRY_META)

static func _weights(arrays: Array, role: String) -> PackedColorArray:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var mask_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color(0.0, 0.0, 0.0, 1.0))
	if role == "Plant_trunk" or role == "Plant_moss":
		return colors
	if role == "Plant_vine":
		var top := -INF
		var bottom := INF
		for point in vertices:
			top = maxf(top, point.y)
			bottom = minf(bottom, point.y)
		for index in vertices.size():
			colors[index].r = smoothstep(0.04, maxf(0.05, top - bottom), top - vertices[index].y)
		return colors
	if mask_uv.size() == vertices.size() and not mask_uv.is_empty() and mask_uv[0].x >= 0.0:
		var height := 0.01
		for point in vertices:
			height = maxf(height, point.y)
		for index in vertices.size():
			colors[index].r = clampf(vertices[index].y / height, 0.0, 1.0)
		return colors
	# 每片叶都先写40个叶柄顶点；从重复封口中心定位叶片段。
	# 叶柄和叶片根部固定，只有离开连接端后渐进受风，避免断枝。
	var starts: Array[int] = []
	for index in range(vertices.size() - 39):
		if _petiole_at(vertices, index):
			starts.append(index)
	for leaf in starts.size():
		var first := starts[leaf]
		var end := starts[leaf + 1] if leaf + 1 < starts.size() else vertices.size()
		var center := vertices[first + 28]
		var reach := 0.01
		for index in range(first + 40, end):
			reach = maxf(reach, center.distance_to(vertices[index]))
		for index in range(first + 40, end):
			colors[index].r = smoothstep(0.01, reach, center.distance_to(vertices[index]))
	return colors

static func _petiole_at(vertices: PackedVector3Array, first: int) -> bool:
	if first + 39 >= vertices.size():
		return false
	var base := vertices[first + 16]
	var center := vertices[first + 28]
	if base.distance_squared_to(center) < 0.000001:
		return false
	for offset in [19, 22, 25]:
		if vertices[first + offset].distance_squared_to(base) > 0.0000000001:
			return false
	for offset in [31, 34, 37]:
		if vertices[first + offset].distance_squared_to(center) > 0.0000000001:
			return false
	# 两端半径也必须匹配现有四侧叶柄，不能把叶肉的重复三角点误作封口。
	return absf(base.distance_to(vertices[first]) - 0.004) < 0.0001 \
		and absf(center.distance_to(vertices[first + 2]) - 0.0026) < 0.0001
