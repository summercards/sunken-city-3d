@tool
extends RefCounted
## schema_version=1 的可选增量字段，不是配方格式迁移；不依赖 Recipe。

const FACADES := ["front", "back", "left", "right"]
const WINDOW_TYPES := ["fixed", "casement_left", "casement_right", "awning"]
const ROOF_MODES := ["none", "parapet", "railing", "mixed"]
const WINDOW_FIELDS := [
	"enabled", "type", "open_angle", "frame_width", "frame_depth",
	"glass_thickness", "recess", "sill_enabled", "sill_projection",
	"sill_thickness", "sill_extension", "width", "height", "sill"
]
const WINDOW_BOUNDS := {
	"open_angle": [0.0, 80.0], "frame_width": [0.04, 0.24],
	"frame_depth": [0.04, 0.5], "glass_thickness": [0.005, 0.08],
	"recess": [0.04, 0.5], "width": [0.25, 6.0],
	"height": [0.25, 6.0], "sill": [0.2, 5.0]
}
const ROOF_BOUNDS := {
	"height": [0.4, 2.0], "thickness": [0.12, 0.6],
	"cap_thickness": [0.06, 0.25], "cap_overhang": [0.0, 0.15],
	"post_spacing": [0.5, 3.0], "rail_spacing": [0.1, 0.6],
	"bar_width": [0.02, 0.12]
}

static func defaults() -> Dictionary:
	return {
		"plan": {"wing_x": 0.5, "wing_z": 0.5, "setback_start": -1, "setback_step": 0.0},
		"window": {
			"enabled": true, "type": "fixed", "open_angle": 0.0,
			"frame_width": 0.11, "frame_depth": 0.12, "glass_thickness": 0.02,
			"recess": 0.15, "sill_enabled": false, "sill_projection": 0.18,
			"sill_thickness": 0.10, "sill_extension": 0.08
		},
		"floor_windows": {}, "facade_windows": {}, "window_overrides": {},
		"roof": {
			"mode": "none", "height": 1.1, "thickness": 0.3,
			"cap_thickness": 0.12, "cap_overhang": 0.04,
			"post_spacing": 1.5, "rail_spacing": 0.22, "bar_width": 0.05,
			"edge_overrides": {}
		}
	}

static func normalized(architecture: Dictionary) -> Dictionary:
	return _merge_defaults(defaults(), architecture)

static func _merge_defaults(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key in overlay:
		var value: Variant = overlay[key]
		if value is Dictionary and result.get(key) is Dictionary:
			result[key] = _merge_defaults(result[key], value)
		else:
			result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

## 只在边界校验成功后读取；稀疏覆盖不补默认值，也不重绑定未匹配的洞口 ID。
## enabled=false 表示封墙；sill 是窗洞标高，与 sill_* 窗沿板参数独立。
static func window_settings(recipe: Dictionary, floor: int, facade: String, opening_id: String = "") -> Dictionary:
	var architecture: Dictionary = normalized(recipe.get("architecture", {}))
	var result: Dictionary = {
		"width": recipe["window_width"], "height": recipe["window_height"],
		"sill": recipe["window_sill"]
	}
	result.merge(architecture.window, true)
	var old_floor: Dictionary = recipe.get("floor_overrides", {}).get(str(floor), {})
	for field in ["width", "height", "sill"]:
		if old_floor.has("window_" + field):
			result[field] = old_floor["window_" + field]
	result.merge(architecture.floor_windows.get(str(floor), {}), true)
	var old_facade: Dictionary = recipe.get("facade_overrides", {}).get(facade, {})
	for field in ["width", "height", "sill"]:
		if old_facade.has(field): result[field] = old_facade[field]
	if old_facade.has("windows"): result["enabled"] = old_facade.windows
	result.merge(architecture.facade_windows.get(facade, {}), true)
	result.merge(architecture.window_overrides.get(opening_id, {}), true)
	return result

## gap_center 为沿边比例、gap_width 为米；实际边长与未匹配 ID 警告由生成层处理。
static func roof_edge_settings(recipe: Dictionary, edge_id: String) -> Dictionary:
	var architecture: Dictionary = normalized(recipe.get("architecture", {}))
	var result: Dictionary = architecture.roof.duplicate(true)
	var overrides: Dictionary = result.edge_overrides
	result.erase("edge_overrides")
	result["gap_center"] = 0.5
	result["gap_width"] = 0.0
	result.merge(overrides.get(edge_id, {}), true)
	return result

static func validate(architecture: Variant, floors: int) -> String:
	if not architecture is Dictionary:
		return "architecture必须是对象"
	if not _finite_tree(architecture):
		return "architecture必须为有限JSON数据"
	var reason: String = _unknown(architecture, defaults().keys(), "architecture")
	if not reason.is_empty(): return reason
	for field in defaults():
		if architecture.has(field) and not architecture[field] is Dictionary:
			return "architecture." + field + "必须是对象"
	var config: Dictionary = normalized(architecture)
	reason = _unknown(config.plan, ["wing_x", "wing_z", "setback_start", "setback_step"], "architecture.plan")
	if not reason.is_empty(): return reason
	for field in ["wing_x", "wing_z"]:
		reason = _range(config.plan[field], 0.25, 0.75, "architecture.plan." + field)
		if not reason.is_empty(): return reason
	var start: Variant = config.plan.setback_start
	if not _integer(start) or (float(start) != -1.0 and (float(start) < 1.0 or float(start) >= floors)):
		return "architecture.plan.setback_start必须为-1或1..floors-1的整数"
	reason = _range(config.plan.setback_step, 0.0, 1.2, "architecture.plan.setback_step")
	if not reason.is_empty(): return reason
	if float(start) >= 1.0 and float(config.plan.setback_step) <= 0.0:
		return "启用退台时setback_step必须大于0"
	reason = _validate_window(config.window, "architecture.window")
	if not reason.is_empty(): return reason
	for scope in ["floor_windows", "facade_windows", "window_overrides"]:
		for key in config[scope]:
			if scope == "floor_windows" and not _floor_key(key, floors):
				return "architecture.floor_windows楼层键非法"
			if scope == "facade_windows" and key not in FACADES:
				return "architecture.facade_windows立面键非法"
			if scope == "window_overrides" and not _opening_id(key, floors):
				return "architecture.window_overrides洞口ID非法: " + key
			reason = _validate_window(config[scope][key], "architecture." + scope + "." + key)
			if not reason.is_empty(): return reason
	# 窗型和角度可来自不同层级，必须按最终覆盖组合检查。
	for floor in range(floors):
		for facade in FACADES:
			var effective: Dictionary = config.window.duplicate(true)
			effective.merge(config.floor_windows.get(str(floor), {}), true)
			effective.merge(config.facade_windows.get(facade, {}), true)
			reason = _validate_window(effective, "合成窗配置")
			if not reason.is_empty(): return reason
			for opening_id in config.window_overrides:
				var parts: PackedStringArray = str(opening_id).split("_")
				if parts[1] != facade or int(parts[2]) != floor: continue
				var single: Dictionary = effective.duplicate(true)
				single.merge(config.window_overrides[opening_id], true)
				reason = _validate_window(single, str(opening_id))
				if not reason.is_empty(): return reason
	var roof: Dictionary = config.roof
	var roof_fields: Array = ROOF_BOUNDS.keys()
	roof_fields.append_array(["mode", "edge_overrides"])
	reason = _unknown(roof, roof_fields, "architecture.roof")
	if not reason.is_empty(): return reason
	if not roof.mode is String or roof.mode not in ROOF_MODES:
		return "architecture.roof.mode非法"
	for field in ROOF_BOUNDS:
		reason = _range(roof[field], ROOF_BOUNDS[field][0], ROOF_BOUNDS[field][1], "architecture.roof." + field)
		if not reason.is_empty(): return reason
	if float(roof.post_spacing) <= float(roof.bar_width) or float(roof.rail_spacing) <= float(roof.bar_width):
		return "屋顶post_spacing和rail_spacing必须大于bar_width"
	if not roof.edge_overrides is Dictionary:
		return "architecture.roof.edge_overrides必须是对象"
	for key in roof.edge_overrides:
		if not key.begins_with("edge_") or not _index_key(key.trim_prefix("edge_")):
			return "architecture.roof.edge_overrides边ID非法: " + key
		var edge: Variant = roof.edge_overrides[key]
		if not edge is Dictionary: return "屋顶边覆盖必须是对象"
		reason = _unknown(edge, ["mode", "gap_center", "gap_width", "height"], "architecture.roof.edge_overrides." + key)
		if not reason.is_empty(): return reason
		if edge.has("mode") and (not edge.mode is String or edge.mode not in ROOF_MODES):
			return "屋顶边mode非法"
		if edge.has("height"):
			reason = _range(edge.height, 0.4, 2.0, "屋顶边height")
			if not reason.is_empty(): return reason
		if edge.has("gap_center"):
			reason = _range(edge.gap_center, 0.0, 1.0, "屋顶边gap_center")
			if not reason.is_empty(): return reason
		if edge.has("gap_width") and (not _number(edge.gap_width) or float(edge.gap_width) < 0.0):
			return "屋顶边gap_width必须为非负有限数值（米）"
	return ""

static func _validate_window(window: Variant, path: String) -> String:
	if not window is Dictionary: return path + "必须是对象"
	var reason: String = _unknown(window, WINDOW_FIELDS, path)
	if not reason.is_empty(): return reason
	for field in ["enabled", "sill_enabled"]:
		if window.has(field) and not window[field] is bool:
			return path + "." + field + "必须为布尔值"
	if window.has("type") and (not window.type is String or window.type not in WINDOW_TYPES):
		return path + ".type非法"
	for field in WINDOW_BOUNDS:
		if window.has(field):
			reason = _range(window[field], WINDOW_BOUNDS[field][0], WINDOW_BOUNDS[field][1], path + "." + field)
			if not reason.is_empty(): return reason
	for field in ["sill_projection", "sill_thickness", "sill_extension"]:
		if window.has(field):
			if not _number(window[field]) or float(window[field]) < 0.0 or (field == "sill_thickness" and float(window[field]) == 0.0):
				return path + "." + field + "必须为有限非负数，窗沿板厚度须大于0"
	if window.get("type", "") == "fixed" and window.has("open_angle") and float(window.open_angle) != 0.0:
		return path + "固定窗fixed的open_angle必须为0"
	return ""

static func _unknown(data: Dictionary, fields: Array, path: String) -> String:
	for key in data:
		if key not in fields: return "未知字段: " + path + "." + str(key)
	return ""

static func _range(value: Variant, low: float, high: float, path: String) -> String:
	if not _number(value): return path + "必须为有限JSON数值"
	if float(value) < low or float(value) > high:
		return path + "必须在" + str(low) + ".." + str(high)
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and absf(float(value)) <= 9007199254740991.0 and floor(float(value)) == float(value)

static func _index_key(value: String) -> bool:
	return value.is_valid_int() and str(int(value)) == value and int(value) >= 0

static func _floor_key(value: String, floors: int) -> bool:
	return _index_key(value) and int(value) < floors

static func _opening_id(value: String, floors: int) -> bool:
	var parts: PackedStringArray = value.split("_")
	return parts.size() == 4 and parts[0] == "opening" and parts[1] in FACADES and _floor_key(parts[2], floors) and _index_key(parts[3])

static func _finite_tree(value: Variant) -> bool:
	if value is float: return is_finite(value)
	if value is Dictionary:
		for key in value:
			if not key is String or not _finite_tree(value[key]): return false
		return true
	if value is Array:
		for item in value:
			if not _finite_tree(item): return false
		return true
	return value == null or value is String or value is bool or value is int or value is float
