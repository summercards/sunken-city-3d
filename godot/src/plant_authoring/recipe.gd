@tool
extends RefCounted
## v1 扁平配方与严格边界校验。失败时返回明确原因，不静默修正输入。

const SPECIES := ["camphor", "maple", "birch"]
const GRASS_ASSETS := ["grass_soft", "mound_soft"]
const KEYS := [
	"species", "seed", "name", "height", "trunk_radius", "trunk_curve", "crown_radius",
	"branch_start", "branch_count", "branch_spread", "branch_rise", "branch_droop",
	"leaf_size", "leaf_density", "cluster_size", "cluster_jitter", "normal_blend",
	"color_variation", "trunk_visible", "leaves_visible", "moss_enabled", "moss_amount",
	"vine_enabled", "vine_count", "vine_length", "grass_enabled", "grass_count", "grass_asset",
	"branch_overrides"
]
const OVERRIDE_KEYS := ["enabled", "length_scale", "radius_scale", "angle_offset"]
const LEAF_BUDGET := 1800

static func defaults(species: String = "camphor") -> Dictionary:
	var common := {
		"species": species,
		"seed": 24117,
		"name": "",
		"height": 9.0,
		"trunk_radius": 0.34,
		"trunk_curve": 0.12,
		"crown_radius": 2.0,
		"branch_start": 3.0,
		"branch_count": 9,
		"branch_spread": 1.0,
		"branch_rise": 0.25,
		"branch_droop": 0.18,
		"leaf_size": 0.38,
		"leaf_density": 1.0,
		"cluster_size": 0.76,
		"cluster_jitter": 0.22,
		"normal_blend": 0.68,
		"color_variation": 0.16,
		"trunk_visible": true,
		"leaves_visible": true,
		"moss_enabled": true,
		"moss_amount": 0.24,
		"vine_enabled": true,
		"vine_count": 2,
		"vine_length": 2.2,
		"grass_enabled": true,
		"grass_count": 12,
		"grass_asset": "grass_soft",
		"branch_overrides": {}
	}
	return common

static func validate(data: Dictionary) -> String:
	for key in data.keys():
		if not KEYS.has(String(key)):
			return "未知配方键: %s" % String(key)
	for key in KEYS:
		if not data.has(key):
			return "缺少配方键: %s" % key
	if not (data.species is String) or not SPECIES.has(data.species):
		return "species 必须是 camphor、maple 或 birch"
	if not (data.name is String): return "name 必须是字符串"
	if data.name.length() > 80: return "name 长度不能超过 80"
	if not _finite_number(data.seed) or int(data.seed) != data.seed:
		return "seed 必须是有限整数"
	var ranges := {
		"height": [3.0, 30.0], "trunk_radius": [0.04, 1.2], "trunk_curve": [0.0, 0.8],
		"crown_radius": [0.8, 10.0], "branch_start": [0.5, 20.0], "branch_spread": [0.2, 2.5],
		"branch_rise": [0.0, 1.0], "branch_droop": [0.0, 1.0], "leaf_size": [0.08, 1.2],
		"leaf_density": [0.25, 2.0], "cluster_size": [0.25, 1.8], "cluster_jitter": [0.0, 0.8],
		"normal_blend": [0.0, 1.0], "color_variation": [0.0, 0.5], "moss_amount": [0.0, 1.0],
		"vine_length": [0.0, 8.0]
	}
	for key in ranges:
		if not _finite_number(data[key]): return "%s 必须是有限数" % key
		if data[key] < ranges[key][0] or data[key] > ranges[key][1]:
			return "%s 超出范围 [%s, %s]" % [key, ranges[key][0], ranges[key][1]]
	if data.branch_start >= data.height - 0.1: return "branch_start 必须小于 height - 0.1"
	if not _integer_in_range(data.branch_count, 3, 18): return "branch_count 必须是 3-18 的整数"
	if not _integer_in_range(data.vine_count, 0, 12): return "vine_count 必须是 0-12 的整数"
	if not _integer_in_range(data.grass_count, 0, 80): return "grass_count 必须是 0-80 的整数"
	if not (data.grass_asset is String) or not GRASS_ASSETS.has(data.grass_asset):
		return "grass_asset 必须是 grass_soft 或 mound_soft"
	for key in ["trunk_visible", "leaves_visible", "moss_enabled", "vine_enabled", "grass_enabled"]:
		if not (data[key] is bool): return "%s 必须是布尔值" % key
	if not (data.branch_overrides is Dictionary): return "branch_overrides 必须是字典"
	for branch_id in data.branch_overrides:
		if not (branch_id is String) or not String(branch_id).begins_with("branch_"):
			return "未知 branch override: %s" % branch_id
		var suffix := String(branch_id).trim_prefix("branch_")
		if suffix.length() != 2 or not suffix.is_valid_int(): return "未知 branch override: %s" % branch_id
		if int(suffix) < 0 or int(suffix) >= int(data.branch_count):
			return "branch override 超出 branch_count: %s" % branch_id
		var override: Variant = data.branch_overrides[branch_id]
		if not (override is Dictionary): return "%s override 必须是字典" % branch_id
		for key in override.keys():
			if not OVERRIDE_KEYS.has(String(key)): return "%s 含未知 override 键: %s" % [branch_id, key]
		for key in override.keys():
			if key == "enabled":
				if not (override[key] is bool): return "%s.enabled 必须是布尔值" % branch_id
			else:
				if not _finite_number(override[key]): return "%s.%s 必须是有限数" % [branch_id, key]
				var value_range := [0.0, 2.0] if key != "angle_offset" else [-1.5, 1.5]
				if override[key] < value_range[0] or override[key] > value_range[1]:
					return "%s.%s 超出范围 [%s, %s]" % [branch_id, key, value_range[0], value_range[1]]
	var estimated := int(round(float(data.branch_count) * (5.0 + float(data.leaf_density) * 4.0) * (4.0 + float(data.leaf_density) * 3.0) + float(data.vine_count) * 4.0))
	if estimated > LEAF_BUDGET: return "leaf_count 预算超限，估算值 %d > %d" % [estimated, LEAF_BUDGET]
	return ""

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer_in_range(value: Variant, low: int, high: int) -> bool:
	return _finite_number(value) and int(value) == value and int(value) >= low and int(value) <= high
