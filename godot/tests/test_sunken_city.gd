extends SceneTree
## 海上主场景的纯水下观赏旧城；由隔离 runner 调用，不创建潜水玩法或替代总装。

const MANIFEST := "res://assets/models/scenery/sunken_city/runtime_manifest.json"
const ASSEMBLY := "res://scenes/world/sunken_city.tscn"
const PREFABS := "res://scenes/components/scenery/sunken_city/"
const MODELS := "res://assets/models/scenery/sunken_city/"
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const REPORT := "res://outputs/sunken-city-structure.json"
const EPS := 0.002
const RUNTIME_VERSION := "v004"
const SOURCE_MAX_HEIGHT_M := 59.6591835
const HEIGHT_CAP_M := 14.9147959
const HEIGHT_CAP_RULE := "global_max_div4_cap"
const ROLES := ["SEA_Matte", "SEA_Metal", "SEA_Gloss"]
const CATEGORIES := ["architecture", "ground", "facilities", "road", "rail", "vehicle", "street_furniture", "vegetation", "debris", "infrastructure", "props", "terrain"]

var checks: int = 0
var failures: int = 0
var failed_labels: Array[String] = []
var components: Dictionary = {}
var vertex_cache: Dictionary = {}
var main: Node
var evidence: Dictionary = {"suite": "sunken_city", "version": RUNTIME_VERSION, "components": [], "instances": []}
var manifest: Dictionary = {}
var height_cap_contract: Dictionary = {}
var root_lift_m: float = 0.0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		failed_labels.append(label)
		printerr("FAIL ", label)


func finish() -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	check(directory_error == OK, "证据输出目录可用")
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	check(file != null, "结构证据可写")
	evidence["checks"] = checks
	evidence["failures"] = failures
	evidence["failed_labels"] = failed_labels
	evidence["source_master_sha256"] = str(manifest.get("source_master_sha256", ""))
	evidence["height_cap_contract"] = height_cap_contract
	evidence["root_lift_m"] = root_lift_m
	evidence["scope"] = "海上主场景纯水下观赏；不是潜水玩法地图"
	evidence["coverage_limits"] = "地坪/轨道核数量、实例矩阵及导入几何；不以 AABB 或未验证的射线 API 冒充坡地共边/断桥间隙源级验收"
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	print("[sunken-city] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func meshes_of(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(meshes_of(child))
	return result


func vertices_of(mesh: Mesh) -> PackedVector3Array:
	var id: int = mesh.get_instance_id()
	if vertex_cache.has(id):
		return vertex_cache[id]
	var result: PackedVector3Array = PackedVector3Array()
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		result.append_array(vertices)
	vertex_cache[id] = result
	return result


## 使用实际顶点，不把倾斜件的局部 AABB 再旋转成一个虚大的世界盒。
func geometry_bounds(node: Node3D) -> Dictionary:
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	var count: int = 0
	for visual in meshes_of(node):
		if visual.mesh == null:
			continue
		for vertex in vertices_of(visual.mesh):
			var point: Vector3 = visual.global_transform * vertex
			low = low.min(point)
			high = high.max(point)
			count += 1
	return {"valid": count > 0 and low.is_finite() and high.is_finite(), "min": low, "max": high, "vertices": count}


func vec_json(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func bounds_json(box: Dictionary) -> Dictionary:
	return {"min": vec_json(box["min"]), "max": vec_json(box["max"]), "vertices": box["vertices"]}


func matrix_values(value: Transform3D) -> Array[float]:
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z]


func numeric_array(value: Variant, size: int) -> bool:
	if not value is Array or value.size() != size:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
	return true


func sha256_string(value: Variant) -> bool:
	var text: String = str(value)
	if text.length() != 64:
		return false
	for character in text:
		if not (character in "0123456789abcdefABCDEF"):
			return false
	return true


func role_of(material: Material) -> String:
	if material == null:
		return ""
	var name_lower: String = material.resource_name.to_lower()
	for role in ROLES:
		if name_lower.contains(String(role).to_lower()) or (name_lower.contains("sunken") and name_lower.contains(String(role).trim_prefix("SEA_").to_lower())):
			return String(role)
	return ""


func pure_visual(node: Node, label: String) -> void:
	check(not (node is CollisionObject3D or node is NavigationRegion3D or node is NavigationObstacle3D or node is Area3D), label + " 无物理/导航/触发区域")
	check(node.get_script() == null, label + " 无脚本")
	check(not node.has_method("rebuild_blockers"), label + " 不派生水面阻挡")
	check(not String(node.name).to_lower() in ["blockers", "walkareas", "walkarea", "landingpoints", "landingpoint"], label + " 无空间职责节点")
	for group in node.get_groups():
		# 引擎内部组不是项目交互或区块声明；纯观赏件不允许任何项目组。
		check(String(group).begins_with("_"), label + " 无项目组 " + String(group))
	for child in node.get_children():
		pure_visual(child, label + "/" + String(child.name))


func check_metadata(node: Node3D, label: String) -> void:
	check(node.get_class() == "Node3D", label + " 根仅为 Node3D")
	check(node.get_meta("building_class", "") == "underwater", label + " 水下观赏分类")
	check(node.get_meta("asset_version", "") == RUNTIME_VERSION, label + " v004 版本")


## SceneState 的路径必须能解析到真实 MeshInstance3D；继承节点 type 允许为空。
func serialized_overrides(packed: PackedScene, component: Node3D, key: String) -> Dictionary:
	var result: Dictionary = {}
	var state: SceneState = packed.get_state()
	for node_index in range(state.get_node_count()):
		var path: NodePath = state.get_node_path(node_index)
		var target: Node = component.get_node_or_null(path)
		for property_index in range(state.get_node_property_count(node_index)):
			var property: String = String(state.get_node_property_name(node_index, property_index))
			if not property.begins_with("surface_material_override/"):
				continue
			var value: Variant = state.get_node_property_value(node_index, property_index)
			check(target is MeshInstance3D, key + " 序列化覆盖落在真正 MeshInstance3D: " + String(path))
			check(value is StandardMaterial3D, key + " 序列化材质值可读: " + property)
			if not target is MeshInstance3D:
				continue
			var index: int = int(property.get_slice("/", 1))
			var visual: MeshInstance3D = target as MeshInstance3D
			check(visual.mesh != null and index >= 0 and index < visual.mesh.get_surface_count(), key + " 序列化 surface 存在")
			var token: String = String(component.get_path_to(target)) + ":" + str(index)
			check(not result.has(token), key + " 覆盖路径不重复 " + token)
			result[token] = value
	return result


func check_material(material: StandardMaterial3D, expected_role: String, label: String) -> void:
	check(material.resource_path.begins_with("res://assets/materials/") and material.resource_path.contains("/sunken_city/") and material.resource_path.ends_with(".tres"), label + " 使用旧城持久材质 .tres")
	check(material.resource_name.to_lower().contains("sunken"), label + " SUNKEN 材质命名")
	check(role_of(material) == expected_role and expected_role in ROLES, label + " 与 glTF 原始角色一致 " + expected_role)
	check(material.albedo_texture != null and material.albedo_texture.resource_path == PALETTE, label + " 公共 timber 色盘")
	check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, label + " 最近邻采样 0")
	check(not material.texture_repeat, label + " 禁用 repeat")
	check(material.cull_mode == BaseMaterial3D.CULL_DISABLED, label + " 双面可见")
	check(not material.emission_enabled, label + " 无自发光")


func check_component(entry: Dictionary) -> void:
	var key: String = str(entry.get("key", ""))
	check(str(entry.get("category", "")) in CATEGORIES, key + " category 已分类")
	check(sha256_string(entry.get("source_sha256", "")), key + " source SHA256 为 string64")
	check(sha256_string(entry.get("prefab_sha256", "")), key + " prefab SHA256 为 string64")
	check(sha256_string(entry.get("glb_sha256", "")), key + " GLB SHA256 为 string64")
	check(str(entry.get("asset_version", "")) == RUNTIME_VERSION, key + " component metadata asset_version=v004")
	var import_settings: Variant = entry.get("import_settings", null)
	check(import_settings is Dictionary, key + " 导入 metadata 存在")
	if import_settings is Dictionary:
		check(import_settings.get("embedded_image_handling", -1) == 0, key + " 导入不嵌入图片")
		check(import_settings.get("automatic_lods", true) == false, key + " 导入关闭 LOD")
		check(import_settings.get("shadow_meshes", true) == false, key + " 导入关闭 shadow mesh")
		check(import_settings.get("light_baking", -1) == 0, key + " 导入关闭 light baking")
	var report: Variant = entry.get("source_report", entry.get("proof_report", entry.get("source_verification", null)))
	check(report is Dictionary, key + " 保留 source/proof report 绑定")
	if report is Dictionary:
		check(sha256_string(report.get("source_sha256", report.get("source_master_sha256", ""))), key + " source/proof report 哈希")
	check(not key.is_empty() and not components.has(key), "组件 key 唯一: " + key)
	if key.is_empty() or components.has(key):
		return
	components[key] = entry
	var prefab_path: String = str(entry.get("prefab", ""))
	var glb_path: String = str(entry.get("glb", ""))
	check(prefab_path == PREFABS + key + ".tscn", key + " 稳定 prefab 路径")
	check(glb_path == MODELS + key + "/" + key + ".glb", key + " 稳定独立 GLB 路径")
	var packed: PackedScene = load(prefab_path) as PackedScene
	var glb: PackedScene = load(glb_path) as PackedScene
	check(packed != null and glb != null, key + " prefab/GLB 独立加载")
	if packed == null or glb == null:
		return
	var component: Node3D = packed.instantiate() as Node3D
	var original: Node3D = glb.instantiate() as Node3D
	check(component != null and original != null, key + " 独立实例化")
	if component == null or original == null:
		if component != null:
			component.free()
		if original != null:
			original.free()
		return
	root.add_child(component)
	check_metadata(component, key)
	check(component.transform.is_equal_approx(Transform3D.IDENTITY), key + " 根原点/旋转/缩放恒等")
	check(component.get_meta("asset_id", "") == entry.get("asset_id", "") and not str(entry.get("asset_id", "")).is_empty(), key + " AssetID 对账")
	check(component.get_meta("key", "") == key, key + " metadata/key")
	pure_visual(component, key)
	var visual_root: Node3D = component.get_node_or_null("Visual") as Node3D
	check(visual_root != null and visual_root.scene_file_path == glb_path, key + " Visual 引用独立 GLB")
	var overrides: Dictionary = serialized_overrides(packed, component, key)
	var visuals: Array[MeshInstance3D] = meshes_of(component)
	check(not visuals.is_empty(), key + " 存在真正网格")
	check(visuals.size() == meshes_of(original).size(), key + " 没有遗漏/添加 GLB 网格")
	var surfaces: int = 0
	var triangles: int = 0
	var roles: Dictionary = {}
	for visual in visuals:
		check(visual.mesh != null, key + " mesh 非空")
		if visual.mesh == null:
			continue
		check(visual.is_visible_in_tree(), key + "/" + String(visual.name) + " 网格可见")
		check(visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, key + " 默认真实投影 ON")
		check(visual.material_override == null, key + " 不用整网格材质掩盖 surface 角色")
		var raw_visual: MeshInstance3D = null
		if visual_root != null and visual_root.is_ancestor_of(visual):
			raw_visual = original.get_node_or_null(visual_root.get_path_to(visual)) as MeshInstance3D
		elif visual_root == visual:
			raw_visual = original as MeshInstance3D
		check(raw_visual != null and raw_visual.mesh != null, key + " 可追溯 GLB 真节点 " + String(component.get_path_to(visual)))
		if raw_visual != null and raw_visual.mesh != null:
			check(raw_visual.mesh.get_surface_count() == visual.mesh.get_surface_count(), key + " GLB surface 数一致")
		for surface in range(visual.mesh.get_surface_count()):
			surfaces += 1
			check(visual.mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, key + " 实际三角形 primitive")
			var arrays: Array = visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var elements: int = vertices.size() if indices.is_empty() else indices.size()
			check(elements > 0 and elements % 3 == 0, key + " surface 三角形计数有效")
			triangles += int(elements / 3.0)
			var token: String = String(component.get_path_to(visual)) + ":" + str(surface)
			var material: StandardMaterial3D = visual.get_surface_override_material(surface) as StandardMaterial3D
			check(material != null, key + " 每个 surface 都有 StandardMaterial3D 覆盖 " + token)
			check(overrides.has(token) and overrides.get(token) == material, key + " 覆盖已按节点/surface 序列化 " + token)
			var raw_role: String = ""
			if raw_visual != null and raw_visual.mesh != null and surface < raw_visual.mesh.get_surface_count():
				raw_role = role_of(raw_visual.mesh.surface_get_material(surface))
			roles[raw_role] = true
			if material != null:
				check_material(material, raw_role, key + "/" + token)
	check(overrides.size() == surfaces, key + " 序列化覆盖数量等于所有实际 surface")
	check(triangles > 0 and triangles == int(entry.get("triangles", -1)), key + " 实际 triangles 与 manifest 一致: " + str(triangles))
	var declared_roles: Variant = entry.get("roles", null)
	check(declared_roles is Array, key + " manifest roles 数组")
	if declared_roles is Array:
		check(roles.size() == declared_roles.size(), key + " 材质角色集合数量一致")
		for role in declared_roles:
			check(role in ROLES and roles.has(role), key + " 角色集合含 " + str(role))
	var box: Dictionary = geometry_bounds(component)
	check(bool(box["valid"]), key + " 实际包络有限且非空")
	if str(entry.get("category", "")) == "architecture" and bool(box["valid"]):
		check(float(box["max"].y) <= HEIGHT_CAP_M + EPS, key + " 建筑局部最高点不超过 height cap")
	var declared: Variant = entry.get("bounds_blender", null)
	var valid_bounds: bool = declared is Array and declared.size() == 2
	if valid_bounds:
		valid_bounds = numeric_array(declared[0], 3) and numeric_array(declared[1], 3)
	check(valid_bounds, key + " Blender 包络格式有效")
	if bool(box["valid"]):
		var low: Vector3 = box["min"]
		var high: Vector3 = box["max"]
		check(absf(low.y) <= EPS, key + " 底心原点贴地，容差 0.002m")
		check(absf((low.x + high.x) * 0.5) <= EPS and absf((low.z + high.z) * 0.5) <= EPS, key + " 根原点位于包络底心")
		if valid_bounds:
			var bmin: Array = declared[0]
			var bmax: Array = declared[1]
			var expected_min: Vector3 = Vector3(float(bmin[0]), float(bmin[2]), -float(bmax[1]))
			var expected_max: Vector3 = Vector3(float(bmax[0]), float(bmax[2]), -float(bmin[1]))
			check(max_error_vec(low, expected_min) < EPS and max_error_vec(high, expected_max) < EPS, key + " Blender→Godot 包络逐轴误差 <0.002m")
	var records: Array = evidence["components"]
	records.append({"key": key, "asset_id": entry.get("asset_id", ""), "triangles": triangles, "surfaces": surfaces, "serialized_overrides": overrides.size(), "roles": roles.keys(), "bounds": bounds_json(box)})
	component.free()
	original.free()


func max_error_vec(actual: Vector3, expected: Vector3) -> float:
	var difference: Vector3 = (actual - expected).abs()
	return maxf(difference.x, maxf(difference.y, difference.z))


func check_assembly(city: Node3D, instances: Array, label: String) -> void:
	check_metadata(city, label)
	check(city.get_meta("source_suite", "") == "sunken_city", label + " source_suite")
	check(city.scale.is_equal_approx(Vector3.ONE), label + " 根缩放为 1")
	if label == "main":
		check(is_finite(root_lift_m), label + " root_lift_m 有限")
		check(absf(city.position.y - root_lift_m) < EPS, label + " main 根 Y 等于 manifest root_lift_m")
	else:
		check(absf(city.position.y) < EPS, label + " 独立总装根 Y 为 identity")
	check(city.visible, label + " 默认 visible")
	check(city.get_child_count() == 388, label + " 388 个直接实例")
	pure_visual(city, label)
	var seen: Dictionary = {}
	var actual_keys: Dictionary = {}
	var world_low: Vector3 = Vector3(INF, INF, INF)
	var world_high: Vector3 = Vector3(-INF, -INF, -INF)
	var floors: int = 0
	var trams: int = 0
	var curves: int = 0
	for value in instances:
		if not value is Dictionary:
			check(false, label + " 实例记录必须为 Dictionary")
			continue
		var entry: Dictionary = value
		var id: String = str(entry.get("instance_id", ""))
		var key: String = str(entry.get("key", ""))
		check(not id.is_empty() and not seen.has(id), label + " instance_id 唯一 " + id)
		seen[id] = true
		check(components.has(key), label + " 组件已登记 " + key)
		var child: Node3D = city.get_node_or_null(NodePath(id)) as Node3D
		check(child != null and child.get_parent() == city, label + " 按 instance_id 直接命名 " + id)
		if child == null or not components.has(key):
			continue
		var definition: Dictionary = components[key]
		check(child.scene_file_path == str(definition.get("prefab", "")), id + " 引用稳定独立 prefab")
		check(child.get_meta("instance_id", "") == id and child.get_meta("key", "") == key, id + " metadata/instance_id/key")
		check(entry.get("component_id", "") == definition.get("asset_id", ""), id + " component_id 对应 AssetID")
		check(child.get_meta("asset_id", "") == definition.get("asset_id", ""), id + " 实例继承正确 AssetID")
		var expected: Variant = entry.get("godot_transform", null)
		check(numeric_array(expected, 12), id + " 12 数值列矩阵")
		var actual: Array[float] = matrix_values(child.transform)
		var error: float = 0.0
		if numeric_array(expected, 12):
			for index in range(12):
				error = maxf(error, absf(actual[index] - float(expected[index])))
				check(absf(actual[index] - float(expected[index])) < EPS, "%s 矩阵项 %d 误差 <0.002" % [id, index])
		actual_keys[key] = int(actual_keys.get(key, 0)) + 1
		if str(entry.get("urban_role", "")) == "aligned_ground_domain":
			floors += 1
		if key == "tram_wreck":
			trams += 1
		if key == "viaduct_curve":
			curves += 1
		if label == "main":
			var box: Dictionary = geometry_bounds(child)
			check(bool(box["valid"]), id + " 世界包络非空有限")
			if bool(box["valid"]):
				var low: Vector3 = box["min"]
				var high: Vector3 = box["max"]
				world_low = world_low.min(low)
				world_high = world_high.max(high)
				check(high.y < 1.12, id + " 包括既有倾斜的全部几何低于水面 1.12m")
				check(low.x >= -120.0 - EPS and high.x <= 120.0 + EPS and low.z >= -120.0 - EPS and high.z <= 120.0 + EPS, id + " 全部世界几何在 X/Z [-120,120]")
			var records: Array = evidence["instances"]
			records.append({"instance_id": id, "key": key, "urban_role": entry.get("urban_role", ""), "matrix_max_error": error, "actual_matrix": actual, "bounds": bounds_json(box)})
	check(seen.size() == 388, label + " manifest 388 个唯一实例")
	check(floors == 100, label + " 保留 100 个独立地坪域")
	check(trams == 3, label + " 保留三辆电车")
	check(curves == 4, label + " 保留四段冻结曲线高架")
	check(int(actual_keys.get("viaduct_broken", 0)) > 0, label + " 保留真实断桥组件")
	if label == "main":
		check(world_high.y < 1.12, label + " 世界最高实际 vertex 低于 water 1.12m")
		evidence["world_bounds"] = {"min": vec_json(world_low), "max": vec_json(world_high), "water_clearance_m": 1.12 - world_high.y}
		evidence["counts"] = {"components": components.size(), "instances": city.get_child_count(), "floor_domains": floors, "trams": trams, "curves": curves, "by_key": actual_keys}


func run() -> void:
	check(FileAccess.file_exists(MANIFEST), "runtime_manifest.json 已生成")
	if not FileAccess.file_exists(MANIFEST):
		await finish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	check(parsed is Dictionary, "manifest 是有效 JSON 对象")
	if not parsed is Dictionary:
		await finish()
		return
	manifest = parsed
	check(manifest.get("suite", "") == "sunken_city" and manifest.get("version", "") == RUNTIME_VERSION, "冻结 sunken_city/v004")
	var source_master_sha: String = str(manifest.get("source_master_sha256", ""))
	check(sha256_string(source_master_sha), "manifest source_master_sha256 为动态 string64")
	height_cap_contract = manifest.get("height_cap_contract", {})
	check(height_cap_contract is Dictionary, "manifest height_cap_contract 存在")
	if height_cap_contract is Dictionary:
		check(absf(float(height_cap_contract.get("source_max_height_m", -1.0)) - SOURCE_MAX_HEIGHT_M) < EPS, "source max height 合同")
		check(absf(float(height_cap_contract.get("height_cap_m", -1.0)) - HEIGHT_CAP_M) < EPS, "height cap 合同")
		check(str(height_cap_contract.get("rule", "")) == HEIGHT_CAP_RULE, "height cap rule 合同")
	check(manifest.get("root_lift_m", null) is float or manifest.get("root_lift_m", null) is int, "manifest root_lift_m 为数值")
	root_lift_m = float(manifest.get("root_lift_m", 0.0))
	var definitions: Variant = manifest.get("components", null)
	var placements: Variant = manifest.get("instances", null)
	check(definitions is Array and placements is Array, "manifest 包含组件/实例数组")
	if not definitions is Array or not placements is Array:
		await finish()
		return
	check(definitions.size() == 50 and placements.size() == 388, "冻结 50 组件 / 388 实例")
	for value in definitions:
		check(value is Dictionary, "组件记录是 Dictionary")
		if value is Dictionary:
			check_component(value)
	var assembly: PackedScene = load(ASSEMBLY) as PackedScene
	check(assembly != null, "总装独立加载")
	if assembly != null:
		var independent: Node3D = assembly.instantiate() as Node3D
		check(independent != null, "总装独立实例化")
		if independent != null:
			root.add_child(independent)
			check_assembly(independent, placements, "assembly")
			independent.free()
	var packed_main: PackedScene = load("res://scenes/main.tscn") as PackedScene
	check(packed_main != null, "真实 main 可加载")
	if packed_main == null:
		await finish()
		return
	main = packed_main.instantiate()
	main.set("_autosave_on", false)
	root.add_child(main)
	main.set("_autosave_on", false)
	main.set_process(false)
	main.set_physics_process(false)
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.cam.set_process(false)
	main.cam.suspend_follow()
	main.boat.set_process(false)
	main.boat.set_physics_process(false)
	root.get_node("Economy").set("ticking", false)
	for _frame in range(3):
		await process_frame
	var city: Node3D = main.get_node_or_null("World/SunkenCity") as Node3D
	check(city != null, "真实 World/SunkenCity 已接入，不合成替代场景")
	if city == null:
		await finish()
		return
	check(city.scene_file_path == ASSEMBLY, "main 引用稳定总装")
	check(city.is_visible_in_tree(), "World/SunkenCity 默认范围可见")
	var water: Node3D = main.get_node_or_null("World/Water") as Node3D
	check(water != null and water.is_visible_in_tree(), "真实主场景海水保留可见")
	if water != null:
		check(absf(water.global_position.y - 1.12) < EPS, "既有海面仍为世界 1.12m")
		evidence["water_y"] = water.global_position.y
	var water_before: Array = main.call("_water_shapes").duplicate(true)
	check_assembly(city, placements, "main")
	var zones: Node = main.get_node_or_null("World/Zones")
	var structures: Node = main.get_node_or_null("World/SeaStructures")
	check(zones != null and structures != null and city.get_parent() == main.get_node("World") and not zones.is_ancestor_of(city) and not structures.is_ancestor_of(city), "旧城不在 _collect_water_shapes 的区块/海上结构收集路径")
	check(main.has_method("_collect_water_shapes"), "沿用 Main 既有水面收集器")
	# 全子树无脚本、Blockers、rebuild_blockers 和项目组，故即使扫描也没有形状来源。
	var water_after: Array = main.call("_water_shapes").duplicate(true)
	check(water_before == water_after, "只读结构检查不改变水面阻挡/岸线形状")
	evidence["water_shapes_before"] = water_before.size()
	evidence["water_shapes_after"] = water_after.size()
	evidence["water_collection_excluded"] = zones != null and structures != null and city.get_parent() == main.get_node("World") and not zones.is_ancestor_of(city) and not structures.is_ancestor_of(city)
	await finish()
