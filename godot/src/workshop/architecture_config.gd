@tool
extends RefCounted
## schema_version=1 的可选增量字段，不是配方格式迁移；不依赖 Recipe。

const PALETTE_SLOTS := ["wall", "pillar", "band", "frame", "glass", "plant", "slab", "roof"]
const PALETTE_ROLES := ["SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission"]
const SHADING_FIELDS := ["roughness", "metallic", "specular", "emission_energy", "transparency"]
const SHADING_BOUNDS := {
	"roughness": [0.0, 1.0], "metallic": [0.0, 1.0], "specular": [0.0, 1.0],
	"emission_energy": [0.0, 2.0], "transparency": [0.0, 1.0]
}
const SHADING_ROLE_BOUNDS := {
	"SEA_Matte": {"roughness": [0.72, 0.90], "metallic": [0.0, 0.05], "specular": [0.0, 0.50], "emission_energy": [0.0, 0.0], "transparency": [0.0, 0.0]},
	"SEA_Metal": {"roughness": [0.28, 0.45], "metallic": [0.60, 0.85], "specular": [0.30, 1.0], "emission_energy": [0.0, 0.0], "transparency": [0.0, 0.0]},
	"SEA_Gloss": {"roughness": [0.12, 0.22], "metallic": [0.05, 0.20], "specular": [0.30, 1.0], "emission_energy": [0.0, 0.0], "transparency": [0.45, 0.95]},
	"SEA_Emission": {"roughness": [0.30, 0.45], "metallic": [0.0, 0.05], "specular": [0.0, 0.50], "emission_energy": [1.0, 2.0], "transparency": [0.0, 0.0]}
}
const SHADING_ROLE_DEFAULTS := {
	"SEA_Matte": {"roughness": 0.82, "metallic": 0.0, "specular": 0.18, "emission_energy": 0.0, "transparency": 0.0},
	"SEA_Metal": {"roughness": 0.36, "metallic": 0.72, "specular": 0.55, "emission_energy": 0.0, "transparency": 0.0},
	"SEA_Gloss": {"roughness": 0.18, "metallic": 0.10, "specular": 0.70, "emission_energy": 0.0, "transparency": 0.81},
	"SEA_Emission": {"roughness": 0.35, "metallic": 0.0, "specular": 0.20, "emission_energy": 1.20, "transparency": 0.0}
}
const FACADES := ["front", "back", "left", "right"]
const WINDOW_TYPES := ["fixed", "casement_left", "casement_right", "awning"]
const ROOF_MODES := ["none", "parapet", "railing", "mixed"]
const WINDOW_FIELDS := [
	"enabled", "type", "open_angle", "frame_width", "frame_depth",
	"glass_thickness", "recess", "sill_enabled", "sill_projection",
	"sill_thickness", "sill_extension", "width", "height", "sill",
	"color_mode", "color_cell", "color_seed"
]
const WINDOW_BOUNDS := {
	"open_angle": [0.0, 80.0], "frame_width": [0.04, 0.40],
	"frame_depth": [0.04, 0.60], "glass_thickness": [0.005, 0.10],
	"recess": [-0.50, 0.50], "width": [0.25, 6.0],
	"height": [0.25, 6.0], "sill": [0.2, 5.0],
	"sill_projection": [0.0, 1.0], "sill_thickness": [0.001, 0.50],
	"sill_extension": [0.0, 0.50]
}
## 形体变形三档作用域：整楼结构 / 窗洞口 / 配件。范围与SKILL的 stylized_form_variants.json 对齐。
const FORM_CATEGORIES := ["structure", "opening", "accessory"]
## mixed = 逐洞口独立取号：同一栋楼里既有上宽也有上窄。只对 opening / accessory 有意义。
const FORM_SIGNS := ["positive", "negative", "mixed"]
## 可调上限（不是SKILL原值：主人要求更大，故把语法区间放宽到可覆盖8°级收分）。
const FORM_BOUNDS := {
	"structure": [0.01, 0.10], "opening": [0.01, 0.12], "accessory": [0.01, 0.18]
}
## taper 字段自身的合法范围是 0..0.1（recipe.validate）；structure 落值写进 taper，
## 所以结构收分的硬上限只能是这个值。倾角上限比它更严时才轮到倾角说话。
const TAPER_CAP := 0.10
## 墙倾角上限本身可调：SKILL 建议 4°，但体量越宽扁可用收分越小，4° 会把幅度压到看不出。
## 主人要求"幅度更大"，故把倾角上限做成 form.max_tilt_deg（默认8°），4° 仍作为 SKILL 基线保留在文档里。
const TILT_BOUNDS := [1.0, 15.0]
const WALL_TILT_BASE_DEG := 4.0
const TILT_DEFAULT_DEG := 8.0

## 承重壁柱：贴墙外皮的竖向构件。corner=转角/边缘柱，middle=开间分界柱。
## projection 是凸出墙皮的量，bite 是咬进墙体的量——bite 不能为 0，否则柱只"贴"在墙上，
#  与墙无实体交叠，接缝契约会判成脱离宿主。
const PILASTER_FIELDS := ["enabled", "corner", "middle", "width", "projection", "bite", "bevel"]
const PILASTER_BOUNDS := {
	"width": [0.14, 0.90], "projection": [0.02, 0.50], "bite": [0.02, 0.24], "bevel": [0.003, 0.06]
}
## 层间腰线：楼层处整圈凸出的水平线条，宽度与凸出都可调。thickness 是竖直方向的厚度。
const BAND_FIELDS := ["enabled", "projection", "thickness", "bevel"]
const BAND_BOUNDS := {
	"projection": [0.01, 0.32], "thickness": [0.08, 0.80], "bevel": [0.003, 0.05]
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
			"sill_thickness": 0.10, "sill_extension": 0.08,
			"color_mode": "auto", "color_cell": [0, 0], "color_seed": 11010
		},
		"palette": {},
		"shading": {"materials": {}},
		"floor_windows": {}, "facade_windows": {}, "window_overrides": {},
		"roof": {
			"mode": "none", "height": 1.1, "thickness": 0.3,
			"cap_thickness": 0.12, "cap_overhang": 0.04,
			"post_spacing": 1.5, "rail_spacing": 0.22, "bar_width": 0.05,
			"edge_overrides": {}
		},
		# 默认关闭：defaults() 是既有配方的基线，开这两个会改变已存建筑的立面。
		# 新建文档在 Recipe.authoring_defaults() 里显式打开。
		"pilaster": {
			"enabled": false, "corner": true, "middle": true,
			"width": 0.36, "projection": 0.18, "bite": 0.06, "bevel": 0.014
		},
		"band": {"enabled": false, "projection": 0.10, "thickness": 0.34, "bevel": 0.012},
		"form": {
			"enabled": false, "preset": "SF-B", "seed": 11010, "max_tilt_deg": 8.0,
			"structure": {"min": 0.015, "max": 0.020, "sign": "positive"},
			"opening": {"min": 0.020, "max": 0.030, "sign": "mixed"},
			"accessory": {"min": 0.030, "max": 0.055, "sign": "positive"}
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
	reason = validate_palette(config.palette)
	if not reason.is_empty(): return reason
	reason = validate_shading(config.shading)
	if not reason.is_empty(): return reason
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
	reason = _validate_pilaster(config.pilaster, "architecture.pilaster")
	if not reason.is_empty(): return reason
	reason = _validate_band(config.band, "architecture.band")
	if not reason.is_empty(): return reason
	return _validate_form(config.get("form", {}), "architecture.form")

static func _validate_pilaster(pilaster: Variant, path: String) -> String:
	if not pilaster is Dictionary: return path + "必须是对象"
	var reason: String = _unknown(pilaster, PILASTER_FIELDS, path)
	if not reason.is_empty(): return reason
	for field in ["enabled", "corner", "middle"]:
		if pilaster.has(field) and not pilaster[field] is bool:
			return path + "." + field + "必须为布尔值"
	for field in PILASTER_BOUNDS:
		if pilaster.has(field):
			reason = _range(pilaster[field], PILASTER_BOUNDS[field][0], PILASTER_BOUNDS[field][1], path + "." + field)
			if not reason.is_empty(): return reason
	# 柱体必须有正截面且有咬入量：projection+bite 是柱在法向的总厚度，bevel 不能吃掉它。
	var thickness: float = float(pilaster.get("projection", 0.12)) + float(pilaster.get("bite", 0.06))
	var bevel: float = float(pilaster.get("bevel", 0.012))
	if thickness <= bevel * 2.5:
		return path + "：projection+bite(%.3f)必须明显大于2.5倍bevel(%.3f)，否则柱没有实体厚度" % [thickness, bevel]
	if float(pilaster.get("bite", 0.06)) <= 0.0:
		return path + ".bite必须大于0：柱必须咬入墙体，不能只贴在墙皮上"
	return ""

static func _validate_band(band: Variant, path: String) -> String:
	if not band is Dictionary: return path + "必须是对象"
	var reason: String = _unknown(band, BAND_FIELDS, path)
	if not reason.is_empty(): return reason
	if band.has("enabled") and not band.enabled is bool:
		return path + ".enabled必须为布尔值"
	for field in BAND_BOUNDS:
		if band.has(field):
			reason = _range(band[field], BAND_BOUNDS[field][0], BAND_BOUNDS[field][1], path + "." + field)
			if not reason.is_empty(): return reason
	if float(band.get("thickness", 0.26)) <= float(band.get("bevel", 0.010)) * 2.5:
		return path + "：thickness(%.3f)必须明显大于2.5倍bevel(%.3f)" % [float(band.get("thickness", 0.26)), float(band.get("bevel", 0.010))]
	return ""

static func _validate_form(form: Variant, path: String) -> String:
	if not form is Dictionary: return path + "必须是对象"
	for key in form:
		if key not in ["enabled", "preset", "seed", "max_tilt_deg", "structure", "opening", "accessory"]:
			return "未知字段: " + path + "." + str(key)
	if form.has("enabled") and not form.enabled is bool:
		return path + ".enabled必须为布尔值"
	if form.has("seed") and (not _integer(form.seed) or int(form.seed) < 0):
		return path + ".seed必须为非负整数"
	if form.has("max_tilt_deg") and (not _number(form.max_tilt_deg) or float(form.max_tilt_deg) < TILT_BOUNDS[0] - 0.000001 or float(form.max_tilt_deg) > TILT_BOUNDS[1] + 0.000001):
		return path + ".max_tilt_deg 必须在" + str(TILT_BOUNDS[0]) + ".." + str(TILT_BOUNDS[1]) + " 度"
	for category in FORM_CATEGORIES:
		if not form.has(category): continue
		var entry: Variant = form[category]
		if not entry is Dictionary: return path + "." + category + "必须是对象"
		for key in entry:
			if key not in ["min", "max", "sign"]:
				return "未知字段: " + path + "." + category + "." + str(key)
		for field in ["min", "max"]:
			if entry.has(field) and not _number(entry[field]):
				return path + "." + category + "." + field + "必须为有限JSON数值"
		var bounds: Array = FORM_BOUNDS[category]
		var low: float = float(entry.get("min", bounds[0]))
		var high: float = float(entry.get("max", bounds[0]))
		if low < float(bounds[0]) - 0.0000001 or high > float(bounds[1]) + 0.0000001:
			return path + "." + category + " 幅度必须在" + str(bounds[0]) + ".." + str(bounds[1])
		if high < low - 0.0000001:
			return path + "." + category + ".max不能小于min"
		if entry.has("sign") and (not entry.sign is String or entry.sign not in FORM_SIGNS):
			return path + "." + category + ".sign非法"
		# mixed 只对洞口有意义：结构与配件必须整体同向，否则立面读成随机噪声而非形体。
		if entry.has("sign") and str(entry.sign) == "mixed" and category != "opening":
			return path + "." + category + ".sign不允许mixed（只有opening可逐洞口取号）"
	# SKILL sign_rules：结构族必须正锥，不做上大下小的墙。
	if bool(form.get("enabled", false)):
		var structure_sign: String = str((form.get("structure", {}) as Dictionary).get("sign", "positive"))
		if structure_sign != "positive":
			return path + ".structure.sign只允许positive（墙不做倒锥）"
	return ""

## 当前允许的墙倾角上限（度）。form.max_tilt_deg 可改；未给时用 TILT_DEFAULT_DEG。
static func tilt_limit(recipe: Dictionary) -> float:
	var form: Dictionary = normalized(recipe.get("architecture", {})).get("form", {})
	var degrees: float = float(form.get("max_tilt_deg", TILT_DEFAULT_DEG))
	return clampf(degrees, TILT_BOUNDS[0], TILT_BOUNDS[1])

## 单看墙倾角允许的收分。
## 本几何的收分摊在整栋高度上：单层墙的 ρ_floor = taper · h_floor / H_total，
## 代入 SKILL 的 β = atan(ρ_floor·W/h_floor) 后 h_floor 约掉，得 β = atan(taper·W/H_total)。
## 因此 taper 上限 = tan(θ)·H_total / max(W_base, D_base)，θ 取 tilt_limit()，而不是按单层高算。
static func tilt_taper_limit(recipe: Dictionary) -> float:
	var span: float = maxf(float(recipe.get("width", 12.0)), float(recipe.get("depth", 9.0)))
	if span <= 0.0: return 0.0
	var floors: float = maxf(1.0, float(recipe.get("floors", 1)))
	var height: float = floors * float(recipe.get("floor_height", 3.6))
	return tan(deg_to_rad(tilt_limit(recipe))) * height / span

## 实际可用收分 = min(倾角限制, taper字段范围)。两者哪个在拦必须能分辨，否则用户不知道该调哪个。
static func structure_limit(recipe: Dictionary) -> float:
	return minf(tilt_taper_limit(recipe), TAPER_CAP)

## 结构区间上限必须落在当前墙倾角内，否则给出可执行的数值而不是静默压小。
static func validate_form(recipe: Dictionary) -> String:
	var architecture: Dictionary = normalized(recipe.get("architecture", {}))
	var form: Dictionary = architecture.get("form", {})
	if not bool(form.get("enabled", false)): return ""
	var limit: float = structure_limit(recipe)
	var high: float = float((form.get("structure", {}) as Dictionary).get("max", 0.0))
	if high > limit + 0.000001:
		var span: float = maxf(float(recipe.get("width", 12.0)), float(recipe.get("depth", 9.0)))
		var height: float = maxf(1.0, float(recipe.get("floors", 1))) * float(recipe.get("floor_height", 3.6))
		if TAPER_CAP <= tilt_taper_limit(recipe) + 0.000001:
			return "结构收分上限%.2f（taper字段合法范围0..%.2f 为硬上限，当前倾角%.1f°还能放到%.4f），structure.max须不大于该值" % [limit, TAPER_CAP, tilt_limit(recipe), tilt_taper_limit(recipe)]
		return "结构收分上限%.4f（墙宽%.1fm、总高%.2fm、墙倾角上限%.1f°），structure.max须不大于该值或调大max_tilt_deg" % [limit, span, height, tilt_limit(recipe)]
	return ""

## 区间 + seed → 稳定落值。纯函数，同seed同类别永远同值，几何可复现。
static func resolve_form(recipe: Dictionary) -> Dictionary:
	var architecture: Dictionary = normalized(recipe.get("architecture", {}))
	var form: Dictionary = architecture.get("form", {})
	var result: Dictionary = {
		"enabled": false, "seed": int(form.get("seed", 0)),
		"structure": 0.0, "opening": 0.0, "accessory": 0.0,
		"max_tilt_deg": tilt_limit(recipe),
		"structure_limit": structure_limit(recipe),
		"tilt_taper_limit": tilt_taper_limit(recipe), "taper_cap": TAPER_CAP,
		"limits": FORM_BOUNDS.duplicate(true),
		"opening_sign": "positive"
	}
	if not bool(form.get("enabled", false)):
		return result
	result.enabled = true
	for category in FORM_CATEGORIES:
		var entry: Dictionary = form.get(category, {})
		var low: float = float(entry.get("min", FORM_BOUNDS[category][0]))
		var high: float = float(entry.get("max", low))
		var value: float = low if high <= low else low + (high - low) * unit_noise(int(result.seed), category)
		var sign_mode: String = str(entry.get("sign", "positive"))
		# mixed 的落值只报幅度（正），实际每个洞口的正负由 opening_rho 按列取号。
		if sign_mode == "negative":
			value = -value
		if category == "opening":
			result["opening_sign"] = sign_mode
		result[category] = value
	return result

## 逐洞口收分：幅度仍由 seed 与区间稳定落值，mixed 时每列独立取号。
## column_key 用「立面_序号」（不含楼层），使同一竖列上下各层方向一致，立面不会读成随机噪点。
static func opening_rho(recipe: Dictionary, column_key: String) -> float:
	var form: Dictionary = normalized(recipe.get("architecture", {})).get("form", {})
	if not bool(form.get("enabled", false)):
		return 0.0
	var entry: Dictionary = form.get("opening", {})
	var low: float = float(entry.get("min", FORM_BOUNDS["opening"][0]))
	var high: float = float(entry.get("max", low))
	var seed_value: int = int(form.get("seed", 0))
	var magnitude: float = low if high <= low else low + (high - low) * unit_noise(seed_value, "opening")
	var sign_mode: String = str(entry.get("sign", "positive"))
	if sign_mode == "mixed":
		sign_mode = "negative" if unit_noise(seed_value, "opening_sign|" + column_key) < 0.5 else "positive"
	return -magnitude if sign_mode == "negative" else magnitude

## FNV-1a 32位：跨版本稳定，不用引擎内置hash，避免同seed漂移。
static func unit_noise(seed_value: int, category: String) -> float:
	var hash_value: int = 2166136261
	var text: String = str(seed_value) + "|" + category
	for index in text.length():
		hash_value = (hash_value ^ text.unicode_at(index)) & 0xFFFFFFFF
		hash_value = (hash_value * 16777619) & 0xFFFFFFFF
	return float(hash_value % 1000003) / 1000003.0

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
	return _validate_color(window, path)

static func _validate_color(entry: Dictionary, path: String) -> String:
	if not entry.get("color_mode", "auto") is String or entry.get("color_mode", "auto") not in ["auto", "manual"]:
		return path + ".color_mode必须为auto或manual"
	var cell: Variant = entry.get("color_cell", [0, 0])
	if not cell is Array or cell.size() != 2:
		return path + ".color_cell必须是0..7的[row,column]"
	for value: Variant in cell:
		if not _integer(value) or float(value) < 0.0 or float(value) > 7.0:
			return path + ".color_cell必须是0..7的整数[row,column]"
	if not _integer(entry.get("color_seed", 11010)) or float(entry.get("color_seed", 11010)) < 0.0:
		return path + ".color_seed必须为非负安全整数"
	return ""

## 空对象保持旧配方外观；slot覆盖优先于材质角色覆盖，再继承全局选色。
static func validate_palette(palette: Variant) -> String:
	if not palette is Dictionary: return "architecture.palette必须是对象"
	var reason: String = _unknown(palette, ["color_mode", "color_cell", "color_seed", "slots", "materials"], "architecture.palette")
	if not reason.is_empty(): return reason
	reason = _validate_color(palette, "architecture.palette")
	if not reason.is_empty(): return reason
	for scope: String in ["slots", "materials"]:
		var entries: Variant = palette.get(scope, {})
		if not entries is Dictionary: return "architecture.palette." + scope + "必须是对象"
		for key: Variant in entries:
			if key not in (PALETTE_SLOTS if scope == "slots" else PALETTE_ROLES):
				return "未知调色目标: " + str(key)
			if not entries[key] is Dictionary: return "调色覆盖必须是对象"
			reason = _unknown(entries[key], ["color_mode", "color_cell", "color_seed"], "architecture.palette." + scope + "." + str(key))
			if reason.is_empty(): reason = _validate_color(entries[key], str(key))
			if not reason.is_empty(): return reason
	return ""

static func validate_shading(shading: Variant) -> String:
	if not shading is Dictionary: return "architecture.shading必须是对象"
	var reason: String = _unknown(shading, ["materials"], "architecture.shading")
	if not reason.is_empty(): return reason
	var materials: Variant = shading.get("materials", {})
	if not materials is Dictionary: return "architecture.shading.materials必须是对象"
	for role: Variant in materials:
		if role not in PALETTE_ROLES: return "未知着色材质角色: " + str(role)
		var settings: Variant = materials[role]
		if not settings is Dictionary: return "材质着色覆盖必须是对象"
		reason = _unknown(settings, SHADING_FIELDS, "architecture.shading.materials." + str(role))
		if not reason.is_empty(): return reason
		var role_bounds: Dictionary = SHADING_ROLE_BOUNDS.get(str(role), SHADING_BOUNDS)
		for field: String in settings:
			if field not in role_bounds: continue
			reason = _range(settings[field], role_bounds[field][0], role_bounds[field][1], "architecture.shading.materials." + str(role) + "." + field)
			if not reason.is_empty(): return reason
	return ""

static func shading_settings(recipe: Dictionary, role: String) -> Dictionary:
	var architecture: Dictionary = normalized(recipe.get("architecture", {}))
	return architecture.get("shading", {}).get("materials", {}).get(role, {}).duplicate(true)

static func palette_settings(recipe: Dictionary, slot: String, role: String) -> Dictionary:
	var palette: Dictionary = recipe.get("architecture", {}).get("palette", {})
	var result: Dictionary = {}
	for field: String in ["color_mode", "color_cell", "color_seed"]:
		if palette.has(field): result[field] = palette[field]
	result.merge(palette.get("materials", {}).get(role, {}), true)
	result.merge(palette.get("slots", {}).get(slot, {}), true)
	return result

static func palette_cell(settings: Dictionary, identity: String, role: String) -> Array:
	if str(settings.get("color_mode", "auto")) == "manual":
		return settings.get("color_cell", [0, 0]).duplicate()
	var value: int = floori(unit_noise(int(settings.get("color_seed", 11010)), "palette|" + identity + "|" + role) * 64.0)
	return [value / 8, value % 8]

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
