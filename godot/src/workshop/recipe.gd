@tool
extends RefCounted
## SEA-WORKSHOP V1 的版本化楼房配方契约。
## 这里不持有运行时状态；规范化始终返回深拷贝，供预览、保存和导出共同使用。

const Config = preload("res://src/workshop/architecture_config.gd")
const SCHEMA := "sea.workshop.building_recipe"
const SCHEMA_VERSION := 1
const STANDARD_FIELDS := [
	"schema", "schema_version", "building_id", "display_name", "revision",
	"standards_id", "catalog_id", "construction_mode", "shape", "width", "depth", "floors",
	"floor_height", "slab_thickness", "wall_thickness", "column_width",
	"window_width", "window_height", "window_sill", "bay_width", "door_width",
	"door_height", "bevel_segments", "bevel_width", "taper", "spatial_profile",
	"aging", "damage", "vegetation_density", "growth_weights", "structure_seed",
	"damage_seed", "vegetation_seed", "component_bindings", "floor_overrides",
	"facade_overrides", "slot_overrides", "excluded_slots", "locked_vegetation",
	"architecture"
]
const COMPONENT_ROLES := ["wall", "slab", "frame", "glass", "pillar", "plant"]
const FACADE_KEYS := ["front", "back", "left", "right"]
const FACADE_FIELDS := ["windows", "sill", "width", "height"]
const SLOT_FIELDS := ["disabled", "component_id", "offset", "growth_key"]
const GROWTH_KEYS := ["small", "medium", "large"]
const SPATIAL_PROFILES := ["above_water", "scenic_underwater", "dive_static"]

static func defaults() -> Dictionary:
	var result := {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"building_id": "workshop_001",
		"display_name": "海风公寓",
		"revision": 1,
		"standards_id": "sea_building_v1",
		"catalog_id": "sea_workshop_v1",
		"construction_mode": "modular_v1",
		"shape": "rectangle",
		"width": 12.0,
		"depth": 9.0,
		"floors": 3,
		"floor_height": 5.1,
		"slab_thickness": 0.2,
		"wall_thickness": 0.3,
		"column_width": 0.5,
		"window_width": 1.4,
		"window_height": 1.8,
		"window_sill": 1.0,
		"bay_width": 3.0,
		"door_width": 1.4,
		"door_height": 2.8,
		"bevel_segments": 3,
		"bevel_width": 0.06,
		"taper": 0.02,
		"spatial_profile": "above_water",
		"aging": 0.15,
		"damage": 0.0,
		"vegetation_density": 0.25,
		"growth_weights": [0.3, 0.4, 0.3],
		"structure_seed": 11010,
		"damage_seed": 11011,
		"vegetation_seed": 11012,
		"component_bindings": {
			"wall": "wall_warm",
			"slab": "slab_warm",
			"frame": "frame_timber",
			"glass": "glass_blue",
			"pillar": "pillar_timber",
			"plant": "plant_shrub"
		},
		"floor_overrides": {},
		"facade_overrides": {},
		"slot_overrides": {},
		"excluded_slots": [],
		"locked_vegetation": []
	}
	var file := FileAccess.open("res://data/workshop/standards_v1.json", FileAccess.READ)
	if file != null:
		var standards: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if standards is Dictionary:
			var authoring: Dictionary = standards.get("authoring_defaults", {})
			var metres: Dictionary = authoring.get("metres", {})
			for mapping in [["floor_height", "ground_floor_to_floor"], ["slab_thickness", "slab_thickness"], ["column_width", "main_column_width"]]:
				if metres.has(mapping[1]): result[mapping[0]] = float(metres[mapping[1]])
			result.bevel_segments = int(authoring.get("bevel_segments_default", 3))
	return result

static func authoring_defaults() -> Dictionary:
	# 仅用于新建文档。旧配方（Recipe.defaults）保持 modular 原值，不被这批作者默认值改写。
	var result: Dictionary = defaults()
	result["construction_mode"] = "shell_v2"
	result["display_name"] = "海风公寓 · 连续实体"
	result["aging"] = 0.0
	result["damage"] = 0.0
	result["vegetation_density"] = 0.0
	# 住宅比例：3.6m 层高、0.18m 板厚、1.5×1.9 窗、2.4m 门；不再用 5.1m 层高留大片空白墙。
	result["floor_height"] = 3.6
	result["slab_thickness"] = 0.18
	result["window_width"] = 1.5
	result["window_height"] = 1.9
	result["window_sill"] = 0.95
	result["door_width"] = 1.6
	result["door_height"] = 2.4
	result.component_bindings["wall"] = "wall_sun"
	var architecture: Dictionary = Config.defaults()
	# 窗台板与女儿墙作为新建默认：立面有窗台线、屋顶有收头。
	var window: Dictionary = (architecture["window"] as Dictionary).duplicate(true)
	window["sill_enabled"] = true
	window["sill_projection"] = 0.16
	window["sill_thickness"] = 0.08
	window["sill_extension"] = 0.06
	architecture["window"] = window
	var roof: Dictionary = (architecture["roof"] as Dictionary).duplicate(true)
	roof["mode"] = "parapet"
	roof["height"] = 0.9
	roof["thickness"] = 0.26
	roof["cap_thickness"] = 0.1
	roof["cap_overhang"] = 0.05
	architecture["roof"] = roof
	result["architecture"] = architecture
	return result

static func validate(data: Dictionary, catalog: Dictionary = {}) -> String:
	if data.is_empty():
		return "配方不能为空"
	for key in data.keys():
		if not STANDARD_FIELDS.has(str(key)):
			return "未知配方字段: " + str(key)
	if not _finite_tree(data):
		return "配方包含非有限数值或不可保存的JSON类型"
	for field in ["width", "depth", "floor_height", "slab_thickness", "wall_thickness", "column_width", "window_width", "window_height", "window_sill", "bay_width", "door_width", "door_height", "bevel_width", "taper", "aging", "damage", "vegetation_density"]:
		if not (data.get(field) is int or data.get(field) is float):
			return field + "必须为JSON数值"
	if float(data.bay_width) < 2.0 or float(data.bay_width) > 6.0:
		return "bay_width必须在2..6"
	if str(data.get("schema", "")) != SCHEMA:
		return "配方schema不匹配"
	var raw_version: Variant = data.get("schema_version", null)
	if not (raw_version is int or raw_version is float) or not is_finite(float(raw_version)) or float(raw_version) != float(SCHEMA_VERSION):
		return "不支持的配方版本"
	if not _safe_id(str(data.get("building_id", ""))):
		return "building_id非法"
	if not (data.get("display_name", "") is String) or str(data.display_name).is_empty():
		return "display_name非法"
	if not _math_integer(data.get("revision", null)) or int(data.get("revision", 0)) < 1:
		return "revision必须为正整数"
	if str(data.get("standards_id", "")) != "sea_building_v1":
		return "不支持的standards_id"
	if str(data.get("catalog_id", "")) != "sea_workshop_v1":
		return "不支持的catalog_id"
	if str(data.get("construction_mode", "modular_v1")) not in ["modular_v1", "shell_v2"]:
		return "不支持的construction_mode"
	if not ["rectangle", "l", "t", "u"].has(str(data.get("shape", ""))):
		return "shape只支持rectangle、l、t或u"
	if str(data.get("construction_mode", "modular_v1")) != "shell_v2" and str(data.shape) not in ["rectangle", "l"]:
		return "t/u形只支持shell_v2连续模式"
	if not SPATIAL_PROFILES.has(str(data.get("spatial_profile", ""))):
		return "spatial_profile非法"
	if not _math_integer(data.get("floors", null)) or int(data.get("floors", 0)) < 1 or int(data.get("floors", 0)) > 8:
		return "floors必须在1..8"
	if data.has("architecture"):
		var architecture_reason: String = Config.validate(data.architecture, int(data.floors))
		if not architecture_reason.is_empty():
			return architecture_reason
		if str(data.get("construction_mode", "modular_v1")) != "shell_v2" and Config.normalized(data.architecture) != Config.defaults():
			return "非默认architecture只支持shell_v2连续模式，旧模式不能忽略建筑配置"
	if float(data.get("width", 0.0)) < 6.0 or float(data.get("width", 0.0)) > 24.0:
		return "width必须在6..24"
	if float(data.get("depth", 0.0)) < 6.0 or float(data.get("depth", 0.0)) > 20.0:
		return "depth必须在6..20"
	for field in ["floor_height", "slab_thickness", "wall_thickness", "column_width", "window_width", "window_height", "window_sill", "bay_width", "door_width", "door_height"]:
		if not _positive_number(data, field):
			return field + "必须为正数"
	var architecture_windows: bool = data.has("architecture") and str(data.get("construction_mode", "modular_v1")) == "shell_v2"
	if not architecture_windows and float(data.window_sill) + float(data.window_height) > float(data.floor_height) - float(data.slab_thickness):
		return "窗洞超出净层高"
	if float(data.door_height) > float(data.floor_height) - float(data.slab_thickness):
		return "门洞超出净层高"
	if not architecture_windows and float(data.window_width) >= float(data.bay_width):
		return "window_width必须小于bay_width"
	var effective_bay: float = float(data.width) / ceilf(float(data.width) / float(data.bay_width))
	if float(data.door_width) + 0.34 + float(data.column_width) >= effective_bay:
		return "门净洞与门框不能放入有效立面段"
	if float(data.column_width) >= minf(effective_bay, float(data.depth) / ceil(float(data.depth) / float(data.bay_width))) - 0.3:
		return "柱宽超出有效立面段"
	if not _math_integer(data.get("bevel_segments", null)) or int(data.get("bevel_segments", 0)) < 1 or int(data.get("bevel_segments", 0)) > 8:
		return "bevel_segments必须在1..8"
	if float(data.get("bevel_width", 0.0)) <= 0.0 or float(data.bevel_width) >= minf(float(data.wall_thickness), float(data.slab_thickness)) * 0.5:
		return "bevel_width必须小于局部厚度一半"
	if float(data.get("taper", -1.0)) < 0.0 or float(data.taper) > 0.1:
		return "taper必须在0..0.1"
	for field in ["aging", "damage", "vegetation_density"]:
		if float(data.get(field, -1.0)) < 0.0 or float(data.get(field, -1.0)) > 1.0:
			return field + "必须在0..1"
	if not _validate_growth_weights(data.get("growth_weights", null)):
		return "growth_weights必须是三个非负数且总和大于0"
	for seed_field in ["structure_seed", "damage_seed", "vegetation_seed"]:
		if not _math_integer(data.get(seed_field, null)) or int(data[seed_field]) < 0:
			return seed_field + "必须为非负整数"
	var bindings: Variant = data.get("component_bindings", null)
	if not (bindings is Dictionary):
		return "component_bindings必须是对象"
	for role in bindings:
		if str(role) not in COMPONENT_ROLES: return "未知组件绑定槽族"
	for role in COMPONENT_ROLES:
		if not bindings.has(role) or not _safe_id(str(bindings[role])):
			return "缺少组件绑定: " + role
		var binding_reason := _check_component(str(bindings[role]), role, catalog)
		if not binding_reason.is_empty():
			return binding_reason
	var floor_reason := _validate_floor_overrides(data.get("floor_overrides", null), int(data.floors))
	if not floor_reason.is_empty():
		return floor_reason
	var facade_reason := _validate_facade_overrides(data.get("facade_overrides", null))
	if not facade_reason.is_empty():
		return facade_reason
	var effective_reason := _validate_effective_openings(data)
	if not effective_reason.is_empty():
		return effective_reason
	var slot_reason := _validate_slot_overrides(data.get("slot_overrides", null), data.get("excluded_slots", null), catalog)
	if not slot_reason.is_empty():
		return slot_reason
	var lock_reason := _validate_locked_vegetation(data.get("locked_vegetation", null))
	if not lock_reason.is_empty():
		return lock_reason
	var cell_count := int(ceil(float(data.width) / float(data.bay_width))) * int(ceil(float(data.depth) / float(data.bay_width)))
	var estimated_nodes := int(data.floors) * (cell_count * 10 + 90) + cell_count * 18
	# 旧版按cell生成大量节点；连续模式不使用cell板，最终预算由实际生成器检查。
	if str(data.get("construction_mode", "modular_v1")) == "modular_v1" and estimated_nodes > 1900:
		return "配方可能超过2000节点预算"
	return ""

static func normalized(data: Dictionary) -> Dictionary:
	var result := defaults()
	for key in data.keys():
		result[key] = _copy_value(data[key])
	# architecture 缺失时保持缺失，不改变旧配方的默认值与指纹。
	if result.get("architecture") is Dictionary:
		result["architecture"] = Config.normalized(result.architecture)
	for key in ["component_bindings", "floor_overrides", "facade_overrides", "slot_overrides"]:
		if result.get(key) is Dictionary:
			result[key] = (result[key] as Dictionary).duplicate(true)
	for key in ["growth_weights", "excluded_slots", "locked_vegetation"]:
		if result.get(key) is Array:
			result[key] = (result[key] as Array).duplicate(true)
	for key in ["schema_version", "revision", "floors", "bevel_segments", "structure_seed", "damage_seed", "vegetation_seed"]:
		if result.get(key) is float and _math_integer(result[key]):
			result[key] = int(result[key])
	return result

static func fingerprint(data) -> String:
	return _stable_string(normalized(data)).sha256_text()

static func _copy_value(value):
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

static func _math_integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0 and floor(float(value)) == float(value)

static func _positive_number(data: Dictionary, key: String) -> bool:
	var value: Variant = data.get(key, null)
	return (value is int or value is float) and float(value) > 0.0

static func _validate_growth_weights(value) -> bool:
	if not value is Array or value.size() != 3:
		return false
	var total := 0.0
	for item in value:
		if not (item is int or item is float) or float(item) < 0.0:
			return false
		total += float(item)
	return is_finite(total) and total > 0.0

static func _validate_floor_overrides(value, floors: int) -> String:
	if not value is Dictionary:
		return "floor_overrides必须是对象"
	for key in value.keys():
		if not str(key).is_valid_int() or str(int(str(key))) != str(key) or int(str(key)) < 0 or int(str(key)) >= floors:
			return "floor_overrides楼层键非法"
		if not value[key] is Dictionary:
			return "floor_overrides值必须是对象"
		for field in value[key].keys():
			if not ["floor_height", "window_height", "window_width", "window_sill", "slab_thickness"].has(str(field)):
				return "未知楼层覆盖字段: " + str(field)
			if not (value[key][field] is int or value[key][field] is float) or float(value[key][field]) <= 0.0:
				return "楼层覆盖值必须为正数"
	return ""

static func _validate_effective_openings(data: Dictionary) -> String:
	for floor in range(int(data.floors)):
		var floor_data: Dictionary = data.floor_overrides.get(str(floor), {})
		var floor_height := float(floor_data.get("floor_height", data.floor_height))
		var next_floor: Dictionary = data.floor_overrides.get(str(floor + 1), {})
		var slab := float(next_floor.get("slab_thickness", data.slab_thickness)) if floor + 1 < int(data.floors) else float(floor_data.get("slab_thickness", data.slab_thickness))
		if floor_height > 12.0 or slab >= floor_height or float(data.bevel_width) >= slab * 0.5:
			return "楼层厚度/层高/倒角组合非法"
		if floor == 0 and float(data.door_height) > floor_height - slab:
			return "楼层覆盖后的门洞超出净层高"
		for facade in FACADE_KEYS:
			if data.has("architecture") and str(data.get("construction_mode", "modular_v1")) == "shell_v2":
				var settings: Dictionary = Config.window_settings(data, floor, facade)
				var reason: String = _validate_architecture_opening(settings, floor_height - slab, float(data.bay_width))
				if not reason.is_empty(): return reason
				# 单窗只按原 ID 的立面、楼层校验，不按当前洞口数量重绑定。
				var overrides: Dictionary = data.architecture.get("window_overrides", {})
				for opening_id in overrides:
					var parts: PackedStringArray = str(opening_id).split("_")
					if parts[1] != facade or int(parts[2]) != floor: continue
					settings = Config.window_settings(data, floor, facade, str(opening_id))
					reason = _validate_architecture_opening(settings, floor_height - slab, float(data.bay_width))
					if not reason.is_empty(): return str(opening_id) + ": " + reason
			else:
				var facade_data: Dictionary = data.facade_overrides.get(facade, {})
				var height := float(facade_data.get("height", floor_data.get("window_height", data.window_height)))
				var width := float(facade_data.get("width", floor_data.get("window_width", data.window_width)))
				var sill := float(facade_data.get("sill", floor_data.get("window_sill", data.window_sill)))
				if sill + height > floor_height - slab or width >= float(data.bay_width):
					return "楼层与立面组合覆盖后的窗洞越界"
	return ""

static func _validate_architecture_opening(settings: Dictionary, clear_height: float, bay_width: float) -> String:
	var reason: String = Config._validate_window(settings, "合成窗配置")
	if not reason.is_empty(): return reason
	if not settings.enabled: return ""
	if float(settings.sill) + float(settings.height) > clear_height or float(settings.width) >= bay_width:
		return "楼层与立面组合覆盖后的窗洞越界"
	return ""

static func _validate_facade_overrides(value) -> String:
	if not value is Dictionary:
		return "facade_overrides必须是对象"
	for key in value.keys():
		if not FACADE_KEYS.has(str(key)) or not value[key] is Dictionary:
			return "立面覆盖键非法"
		for field in value[key].keys():
			if not FACADE_FIELDS.has(str(field)):
				return "未知立面覆盖字段: " + str(field)
			if str(field) == "windows" and not value[key][field] is bool:
				return "windows覆盖必须是布尔值"
			if str(field) != "windows" and (not (value[key][field] is int or value[key][field] is float) or float(value[key][field]) <= 0.0):
				return "立面尺寸覆盖必须为正数"
	return ""

static func _validate_slot_overrides(value, excluded, catalog: Dictionary) -> String:
	if not value is Dictionary or not excluded is Array:
		return "slot_overrides/excluded_slots类型非法"
	for key in value.keys():
		if not _safe_slot_id(str(key)) or not value[key] is Dictionary:
			return "slot_overrides键或值非法"
		for field in value[key].keys():
			if not SLOT_FIELDS.has(str(field)):
				return "未知槽覆盖字段: " + str(field)
			if str(field) == "offset":
				if not value[key][field] is Array or value[key][field].size() != 3:
					return "槽offset必须是三维数组"
				for component in value[key][field]:
					if not (component is int or component is float):
						return "槽offset必须为数值"
			if str(field) == "component_id":
				if not _safe_id(str(value[key][field])):
					return "槽组件ID非法"
				if not catalog.is_empty() and not catalog.get("components", {}).has(str(value[key][field])):
					return "未知槽组件: " + str(value[key][field])
				if not catalog.is_empty():
					var slot_family := _slot_family(str(key))
					if not slot_family.is_empty() and str(catalog.components[str(value[key][field])].get("family", "")) != slot_family:
						return "槽组件与槽族不兼容: " + str(value[key][field])
			if str(field) == "disabled" and not value[key][field] is bool:
				return "disabled必须是布尔值"
			if str(field) == "growth_key" and not GROWTH_KEYS.has(str(value[key][field])):
				return "growth_key非法"
	for item in excluded:
		if not _safe_slot_id(str(item)):
			return "excluded_slots包含非法槽ID"
	return ""

static func _validate_locked_vegetation(value) -> String:
	if not value is Array:
		return "locked_vegetation必须是数组"
	var seen: Dictionary = {}
	for item in value:
		if not item is Dictionary:
			return "locked_vegetation项必须是对象"
		for field in item:
			if str(field) not in ["slot_id", "position", "growth_key"]: return "未知植物锁定字段"
		var slot_id := str(item.get("slot_id", ""))
		if seen.has(slot_id): return "植物锁定slot_id重复"
		seen[slot_id] = true
		if not _safe_slot_id(slot_id) or not slot_id.begins_with("plant_roof_"):
			return "locked_vegetation缺少合法屋顶植物slot_id"
		if not item.get("position", null) is Array or item.position.size() != 3:
			return "locked_vegetation.position必须是三维数组"
		if not GROWTH_KEYS.has(str(item.get("growth_key", "medium"))):
			return "locked_vegetation.growth_key非法"
		for value_item in item.position:
			if not (value_item is int or value_item is float):
				return "locked_vegetation.position必须为数值"
	return ""

static func _check_component(component_id: String, role: String, catalog: Dictionary) -> String:
	if catalog.is_empty():
		return ""
	var components: Dictionary = catalog.get("components", {})
	if not components.has(component_id):
		return "未知组件: " + component_id
	var expected := role
	if str(components[component_id].get("family", "")) != expected:
		return "组件与槽族不兼容: " + component_id
	return ""

static func _slot_family(slot_id: String) -> String:
	if slot_id.begins_with("wall_") or slot_id.begins_with("parapet_"): return "wall"
	if slot_id.begins_with("slab_") or slot_id.begins_with("roof_") or slot_id.begins_with("roofcap_"): return "slab"
	if slot_id.begins_with("pillar_") or slot_id.begins_with("railing_"): return "pillar"
	if slot_id.begins_with("frame_") or slot_id.begins_with("sash_") or slot_id.begins_with("sill_"): return "frame"
	if slot_id.begins_with("glass_"): return "glass"
	if slot_id.begins_with("plant_") or slot_id.begins_with("vine_"): return "plant"
	return ""

static func _safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for character in value:
		var code := character.unicode_at(0)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45):
			return false
	return true

static func _safe_slot_id(value: String) -> bool:
	return _safe_id(value) and not value.contains("..")

static func _finite_tree(value) -> bool:
	if value is float:
		return is_finite(value)
	if value is Dictionary:
		for key in value.keys():
			if not key is String or not _finite_tree(value[key]):
				return false
		return true
	if value is Array:
		for item in value:
			if not _finite_tree(item):
				return false
		return true
	return value == null or value is String or value is bool or value is int or value is float

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
		return str(int(value)) if _math_integer(value) and absf(value) <= 9007199254740991.0 else JSON.stringify(value)
	return str(value)
