@tool
extends RefCounted
## 配方边界与确定性序列化；旧配方只补新增字段，不掩盖未知字段或非法值。

const SPECIES := ["camphor", "maple", "birch"]
const GRASS_ASSETS := ["grass_soft", "mound_soft"]
const KEYS := [
	"species", "seed", "name", "height", "trunk_radius", "trunk_curve", "crown_radius",
	"branch_start", "branch_count", "branch_spread", "branch_rise", "branch_droop",
	"leaf_size", "leaf_density", "cluster_size", "cluster_jitter", "normal_blend",
	"color_variation", "trunk_visible", "leaves_visible", "moss_enabled", "moss_amount",
	"vine_enabled", "vine_count", "vine_length", "grass_enabled", "grass_count", "grass_asset",
	"branch_overrides", "subtwig_count", "trunk_cell", "leaf_cell", "moss_cell", "vine_cell",
	"color_mode", "wind_strength", "wind_speed", "random_enabled", "variation"
]
const OPTIONAL_KEYS := [
	"subtwig_count", "trunk_cell", "leaf_cell", "moss_cell", "vine_cell",
	"color_mode", "wind_strength", "wind_speed", "random_enabled", "variation"
]
const OVERRIDE_KEYS := ["enabled", "length_scale", "radius_scale", "angle_offset"]
const LEAF_BUDGET := 1800
const MAX_SEED := 9007199254740991
# 每项为 [最小值, 最大值, 滑条步长]；包含分枝 override，供 UI 直接消费。
const RANGES := {
	"seed": [0, MAX_SEED, 1],
	"height": [3.0, 30.0, 0.1], "trunk_radius": [0.04, 1.2, 0.01],
	"trunk_curve": [0.0, 0.8, 0.01], "crown_radius": [0.8, 10.0, 0.05],
	"branch_start": [0.5, 20.0, 0.1], "branch_count": [3, 18, 1],
	"branch_spread": [0.2, 2.5, 0.01], "branch_rise": [0.0, 1.0, 0.01],
	"branch_droop": [0.0, 1.0, 0.01], "subtwig_count": [1, 8, 1],
	"leaf_size": [0.08, 1.2, 0.01], "leaf_density": [0.25, 2.0, 0.01],
	"cluster_size": [0.25, 1.8, 0.01], "cluster_jitter": [0.0, 0.8, 0.01],
	"normal_blend": [0.0, 1.0, 0.01], "color_variation": [0.0, 0.5, 0.01],
	"moss_amount": [0.0, 1.0, 0.01], "vine_count": [0, 12, 1],
	"vine_length": [0.0, 8.0, 0.05], "grass_count": [0, 80, 1],
	"trunk_cell": [0, 63, 1], "leaf_cell": [0, 63, 1],
	"moss_cell": [0, 63, 1], "vine_cell": [0, 63, 1],
	"wind_strength": [0.0, 1.0, 0.01], "wind_speed": [0.0, 3.0, 0.01],
	"variation": [0.0, 1.0, 0.01],
	"length_scale": [0.0, 2.0, 0.01], "radius_scale": [0.0, 2.0, 0.01],
	"angle_offset": [-1.5, 1.5, 0.01]
}
const INTEGER_KEYS := [
	"seed", "branch_count", "subtwig_count", "vine_count", "grass_count",
	"trunk_cell", "leaf_cell", "moss_cell", "vine_cell"
]

static func defaults(species: String = "camphor") -> Dictionary:
	var common := {
		"species": species, "seed": 24117, "name": "",
		"height": 7.2, "trunk_radius": 0.27, "trunk_curve": 0.22,
		"crown_radius": 2.9, "branch_start": 2.4, "branch_count": 10,
		"branch_spread": 1.0, "branch_rise": 0.38, "branch_droop": 0.12,
		"subtwig_count": 5, "leaf_size": 0.36, "leaf_density": 1.0,
		"cluster_size": 0.92, "cluster_jitter": 0.24, "normal_blend": 0.68,
		"color_variation": 0.16, "color_mode": "auto",
		"trunk_cell": 13, "leaf_cell": 28, "moss_cell": 34, "vine_cell": 29,
		"trunk_visible": true, "leaves_visible": true,
		"moss_enabled": true, "moss_amount": 0.24,
		"vine_enabled": true, "vine_count": 2, "vine_length": 2.2,
		"grass_enabled": true, "grass_count": 12, "grass_asset": "grass_soft",
		"wind_strength": 0.35, "wind_speed": 1.0,
		"random_enabled": true, "variation": 1.0, "branch_overrides": {}
	}
	if species == "maple":
		common.merge({
			"height": 4.8, "trunk_radius": 0.19, "trunk_curve": 0.32,
			"crown_radius": 2.8, "branch_start": 1.25, "branch_count": 9,
			"branch_spread": 1.12, "branch_rise": 0.15, "branch_droop": 0.14,
			"subtwig_count": 4, "leaf_size": 0.34, "cluster_size": 0.72,
			"cluster_jitter": 0.18, "leaf_density": 0.85, "leaf_cell": 27
		}, true)
	elif species == "birch":
		common.merge({
			"height": 9.4, "trunk_radius": 0.18, "trunk_curve": 0.07,
			"crown_radius": 2.1, "branch_start": 3.2, "branch_count": 12,
			"branch_spread": 0.94, "branch_rise": 0.62, "branch_droop": 0.78,
			"subtwig_count": 6, "leaf_size": 0.28, "cluster_size": 0.65,
			"cluster_jitter": 0.17, "leaf_density": 0.8,
			"trunk_cell": 4, "leaf_cell": 27
		}, true)
	return common

static func normalized(data: Dictionary) -> Dictionary:
	# 仅补可选字段、统一合法数值类型；非法输入保留原值，交由 validate 报错。
	var result := data.duplicate(true)
	var species: Variant = data.get("species", "camphor")
	var fallback := defaults(species if species is String and SPECIES.has(species) else "camphor")
	for key in OPTIONAL_KEYS:
		if not result.has(key):
			result[key] = fallback[key]
	for key in RANGES:
		if not result.has(key) or not _finite_number(result[key]):
			continue
		var limits: Array = RANGES[key]
		if INTEGER_KEYS.has(key):
			if _integer_in_range(result[key], int(limits[0]), int(limits[1])):
				result[key] = int(result[key])
		else:
			result[key] = float(result[key])
	if result.get("branch_overrides") is Dictionary:
		for id in result.branch_overrides:
			var override: Variant = result.branch_overrides[id]
			if override is Dictionary:
				for key in ["length_scale", "radius_scale", "angle_offset"]:
					if override.has(key) and _finite_number(override[key]):
						override[key] = float(override[key])
	return result

static func validate(data: Dictionary) -> String:
	for key in data:
		if not (key is String) or not KEYS.has(key):
			return "未知配方键: %s" % str(key)
	for key in KEYS:
		if not data.has(key) and not OPTIONAL_KEYS.has(key):
			return "缺少配方键: %s" % key
	var recipe := normalized(data)
	if not (recipe.species is String) or not SPECIES.has(recipe.species):
		return "species 必须是 camphor、maple 或 birch"
	if not (recipe.name is String) or recipe.name.length() > 80:
		return "name 必须是至多 80 字符的字符串"
	if not (recipe.color_mode is String) or not ["manual", "auto"].has(recipe.color_mode):
		return "color_mode 必须是 manual 或 auto"
	for key in RANGES:
		if OVERRIDE_KEYS.has(key):
			continue
		var limits: Array = RANGES[key]
		if not _finite_number(recipe[key]):
			return "%s 必须是有限数" % key
		if recipe[key] < limits[0] or recipe[key] > limits[1]:
			return "%s 超出范围 [%s, %s]" % [key, limits[0], limits[1]]
		if INTEGER_KEYS.has(key) and not _integer_in_range(recipe[key], int(limits[0]), int(limits[1])):
			return "%s 必须是范围内的整数" % key
	if recipe.branch_start >= recipe.height - 0.1:
		return "branch_start 必须小于 height - 0.1"
	if not (recipe.grass_asset is String) or not GRASS_ASSETS.has(recipe.grass_asset):
		return "grass_asset 必须是 grass_soft 或 mound_soft"
	for key in ["trunk_visible", "leaves_visible", "moss_enabled", "vine_enabled", "grass_enabled", "random_enabled"]:
		if not (recipe[key] is bool):
			return "%s 必须是布尔值" % key
	if not (recipe.branch_overrides is Dictionary):
		return "branch_overrides 必须是字典"
	for branch_id in recipe.branch_overrides:
		if not (branch_id is String):
			return "branch override ID 必须是字符串"
		var suffix: String = branch_id.trim_prefix("branch_")
		if suffix.length() != 2 or not suffix.is_valid_int():
			return "未知 branch override: %s" % branch_id
		if branch_id != "branch_%02d" % int(suffix) or int(suffix) < 0 or int(suffix) >= int(recipe.branch_count):
			return "branch override 超出 branch_count: %s" % branch_id
		var override: Variant = recipe.branch_overrides[branch_id]
		if not (override is Dictionary):
			return "%s override 必须是字典" % branch_id
		for key in override:
			if not (key is String) or not OVERRIDE_KEYS.has(key):
				return "%s 含未知 override 键: %s" % [branch_id, str(key)]
			if key == "enabled":
				if not (override[key] is bool):
					return "%s.enabled 必须是布尔值" % branch_id
			else:
				var limits: Array = RANGES[key]
				if not _finite_number(override[key]):
					return "%s.%s 必须是有限数" % [branch_id, key]
				if override[key] < limits[0] or override[key] > limits[1]:
					return "%s.%s 超出范围 [%s, %s]" % [branch_id, key, limits[0], limits[1]]
	var count := leaf_count(recipe)
	if count > LEAF_BUDGET:
		return "leaf_count 预算超限，实际生成计数 %d > %d" % [count, LEAF_BUDGET]
	return ""

static func branch_enabled(recipe: Dictionary, id: String) -> bool:
	var override: Dictionary = recipe.branch_overrides.get(id, {})
	return bool(override.get("enabled", true)) and float(override.get("length_scale", 1.0)) > 0.0 and float(override.get("radius_scale", 1.0)) > 0.0

static func leaves_per_twig(recipe: Dictionary) -> int:
	var count := maxi(2, int(round(float(recipe.leaf_density) * 12.0)))
	if recipe.species == "maple":
		count = int(ceil(float(count) / 2.0)) * 2
	return count

static func leaf_count(recipe: Dictionary) -> int:
	var count := 0
	if recipe.leaves_visible:
		for index in int(recipe.branch_count):
			if branch_enabled(recipe, "branch_%02d" % index):
				count += int(recipe.subtwig_count) * leaves_per_twig(recipe)
	if recipe.vine_enabled and float(recipe.vine_length) > 0.0:
		count += int(recipe.vine_count) * 4
	return count

static func fingerprint(data: Dictionary) -> String:
	# 无效配方不能产生可用于历史去重或保存的指纹。
	if not validate(data).is_empty():
		return ""
	return _stable_json(normalized(data))

static func _stable_json(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var fields := PackedStringArray()
		for key in keys:
			fields.append(JSON.stringify(str(key)) + ":" + _stable_json(value[key]))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var entries := PackedStringArray()
		for item in value:
			entries.append(_stable_json(item))
		return "[" + ",".join(entries) + "]"
	if _finite_number(value) and absf(float(value)) <= float(MAX_SEED) and float(value) == floor(float(value)):
		return str(int(value))
	# Godot JSON解析会把7.6000000000000005回读为7.6；作者滑条精度>=0.01，
	# 指纹采用明确的1e-9十进制规范，远细于编辑精度，不把二进制尾数当作修改。
	if value is float:
		return String.num(value, 9)
	return JSON.stringify(value, "", true, true)

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer_in_range(value: Variant, low: int, high: int) -> bool:
	if not _finite_number(value) or value < low or value > high:
		return false
	return float(value) == floor(float(value))
