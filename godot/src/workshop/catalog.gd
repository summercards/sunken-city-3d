@tool
extends RefCounted
## SEA-WORKSHOP V1 的只读组件目录。目录数据唯一来自版本化JSON。

const PATH := "res://data/workshop/catalog_v1.json"
const SCHEMA := "sea.workshop.component_catalog"
const SCHEMA_VERSION := 1
const PREFAB_ROOT := "res://scenes/components/"
static var _definitions: Dictionary = {}

static func definitions() -> Dictionary:
	if _definitions.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file == null:
			return {}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			_definitions = parsed
	return _definitions.duplicate(true)

## 编辑器升级只补缺失的内置组件，不覆盖已保存的 prefab 或同 ID 自定义定义。
## 直接读版本化文件，避免热更新时静态缓存仍是上个版本。
static func editor_catalog(snapshot: Dictionary = {}) -> Dictionary:
	var latest: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not latest is Dictionary or not validate(latest).is_empty():
		return snapshot.duplicate(true)
	if snapshot.is_empty():
		return latest.duplicate(true)
	var result: Dictionary = snapshot.duplicate(true)
	if not result.get("components") is Dictionary:
		return result
	for component_id: String in latest.components:
		if not result.components.has(component_id):
			result.components[component_id] = latest.components[component_id].duplicate(true)
	return result

static func validate(c: Dictionary) -> String:
	if c.is_empty():
		return "组件目录不能为空"
	for key in c.keys():
		if not ["schema", "schema_version", "catalog_id", "source", "components"].has(str(key)):
			return "未知目录字段: " + str(key)
	var raw_version: Variant = c.get("schema_version", null)
	if str(c.get("schema", "")) != SCHEMA or not (raw_version is int or raw_version is float) or float(raw_version) != float(SCHEMA_VERSION):
		return "组件目录版本不匹配"
	if str(c.get("catalog_id", "")) != "sea_workshop_v1":
		return "组件目录ID不匹配"
	if str(c.get("source", "")) != "native_parameter":
		return "组件目录来源必须声明为native_parameter"
	if not c.get("components", null) is Dictionary or c.components.is_empty():
		return "组件目录缺少components"
	for component_id in c.components.keys():
		var reason := _validate_component(str(component_id), c.components[component_id])
		if not reason.is_empty():
			return reason
	return ""

static func fingerprint(c: Dictionary) -> String:
	return _stable_string(c).sha256_text()

static func ids(c: Dictionary = {}) -> Array[String]:
	var source := c if not c.is_empty() else definitions()
	var result: Array[String] = []
	if source.get("components", null) is Dictionary:
		for component_id in source.components.keys():
			result.append(str(component_id))
	result.sort()
	return result

static func _validate_component(component_id: String, raw) -> String:
	if not _safe_id(component_id) or not raw is Dictionary:
		return "组件ID或定义非法: " + component_id
	for field in raw:
		if str(field) not in ["asset_id", "family", "kind", "profile", "color", "version", "front_axis", "pivot", "nominal_size", "replaceable", "prefab", "material_role"]:
			return "未知组件字段: " + str(field)
	if raw.has("material_role") and str(raw.material_role) not in ["SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission"]:
		return "未知共享材质角色: " + component_id
	if str(raw.get("version", "")).is_empty(): return "组件缺少版本"
	if str(raw.get("kind", "")) == "parametric":
		var expected_profiles := ["shrub", "tree", "vine", "moss"] if str(raw.get("family", "")) == "plant" else [str(raw.get("family", ""))]
		if str(raw.get("profile", "")) not in expected_profiles: return "未知参数组件profile"
		if raw.get("pivot", []) != [0.0, 0.0, 0.0] or str(raw.get("front_axis", "")) != "-Z":
			return "原生参数组件接口只支持语义零原点与-Z正面"
	for field in ["family", "kind", "profile", "color", "version", "front_axis", "pivot", "nominal_size", "replaceable"]:
		if not raw.has(field):
			return "组件缺少字段: " + component_id + "." + field
	if not ["wall", "slab", "frame", "glass", "pillar", "plant"].has(str(raw.family)):
		return "组件family非法: " + component_id
	if not ["parametric", "prefab"].has(str(raw.kind)):
		return "组件kind非法: " + component_id
	if not ["-Z", "+Z", "+X", "-X"].has(str(raw.front_axis)):
		return "组件front_axis非法: " + component_id
	if not raw.pivot is Array or raw.pivot.size() != 3 or not _positive_or_zero_vector(raw.pivot):
		return "组件pivot非法: " + component_id
	if not raw.nominal_size is Array or raw.nominal_size.size() != 3 or not _positive_vector(raw.nominal_size):
		return "组件nominal_size非法: " + component_id
	if not raw.replaceable is bool:
		return "组件replaceable非法: " + component_id
	if raw.kind == "prefab":
		var path := str(raw.get("prefab", ""))
		if not path.begins_with(PREFAB_ROOT) or not path.ends_with(".tscn") or path.contains(".."):
			return "prefab不在白名单目录: " + component_id
		var packed := load(path) as PackedScene
		if packed == null:
			return "prefab资源不存在: " + component_id
		if _state_contains_script(packed.get_state()):
			return "prefab包含脚本节点: " + component_id
		if not _compatible_prefab_size(raw):
			return "prefab尺寸接口不兼容: " + component_id
	elif raw.has("prefab") and not str(raw.prefab).is_empty():
		return "parametric组件不能绑定prefab: " + component_id
	return ""

static func _state_contains_script(state: SceneState) -> bool:
	# 递归审查继承场景、嵌套实例和资源；instantiate之前拒绝所有非静态白名单节点。
	if state.get_connection_count() > 0: return true
	for node_index in state.get_node_count():
		var node_type := str(state.get_node_type(node_index))
		if node_type not in ["", "Node3D", "MeshInstance3D", "Marker3D"]: return true
		for property_index in state.get_node_property_count(node_index):
			var property := str(state.get_node_property_name(node_index, property_index))
			if property in ["script", "top_level"]: return true
			if _unsafe_resource(state.get_node_property_value(node_index, property_index), {}): return true
	return false

static func _unsafe_resource(value: Variant, visited: Dictionary) -> bool:
	if value is Script or value is PackedScene: return true
	if value is Resource:
		if visited.has(value.get_instance_id()): return false
		visited[value.get_instance_id()] = true
		if value.get_script() != null: return true
		for property in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				if _unsafe_resource(value.get(str(property.name)), visited): return true
	elif value is Array:
		for item in value:
			if _unsafe_resource(item, visited): return true
	elif value is Dictionary:
		for key in value:
			if _unsafe_resource(value[key], visited): return true
	return false

static func _compatible_prefab_size(raw: Dictionary) -> bool:
	var nominal: Array = raw.get("nominal_size", [])
	return nominal.size() == 3 and float(nominal[0]) > 0.0 and float(nominal[1]) > 0.0 and float(nominal[2]) > 0.0

static func _positive_vector(values: Array) -> bool:
	for value in values:
		if not (value is int or value is float) or float(value) <= 0.0 or not is_finite(float(value)):
			return false
	return true

static func _positive_or_zero_vector(values: Array) -> bool:
	for value in values:
		if not (value is int or value is float) or float(value) < 0.0 or not is_finite(float(value)):
			return false
	return true

static func _safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for character in value:
		var code := character.unicode_at(0)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45):
			return false
	return true

static func _stable_string(value) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append(JSON.stringify(str(key)) + ":" + _stable_string(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(_stable_string(item))
		return "[" + ",".join(parts) + "]"
	if value is String:
		return JSON.stringify(value)
	if value is bool:
		return "true" if value else "false"
	if value == null:
		return "null"
	if value is int:
		return str(value)
	if value is float:
		return str(int(value)) if is_finite(value) and floor(value) == value and absf(value) <= 9007199254740991.0 else JSON.stringify(value)
	return str(value)
