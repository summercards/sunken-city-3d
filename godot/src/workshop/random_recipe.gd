@tool
extends RefCounted
## 房屋作者配方：只使用本地RNG，不构建、不写会话或世界。
const Recipe = preload("res://src/workshop/recipe.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const COLOR_FIELDS := ["color_mode", "color_cell", "color_seed"]
const SHAPES := ["rectangle", "l", "t", "u"]

static func create(seed_value: int, palette_override: Variant = null, current_recipe: Dictionary = {}) -> Dictionary:
	# 非法外部输入明确拒绝，不强转为Dictionary，也不静默退回默认配色。
	if palette_override != null and not Config.validate_palette(palette_override).is_empty():
		return {}
	if not current_recipe.is_empty() and not Recipe.validate(current_recipe).is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = ("workshop-house-v1:" + str(seed_value)).sha256_text().substr(0, 15).hex_to_int()
	var recipe: Dictionary = Recipe.authoring_defaults()
	var shape: String = SHAPES[rng.randi_range(0, SHAPES.size() - 1)]
	# 平面按开间模数构造，凹形最短翼段也至少有一个完整开间。
	var unit: float = [3.0, 3.5, 4.0][rng.randi_range(0, 2)]
	var nx: int = rng.randi_range(3, 5)
	var nz: int = rng.randi_range(2, 4)
	var wing_x: float = 0.5
	var wing_z: float = 0.5
	if shape == "l":
		nz = rng.randi_range(3, 4)
		wing_x = float(rng.randi_range(1, nx - 1)) / float(nx)
		# 比例边界要求0.25..0.75；整数翼宽仍保留至少一个开间。
		wing_x = clampf(wing_x, 0.25, 0.75)
		wing_z = float(rng.randi_range(1, nz - 1)) / float(nz)
	elif shape == "t":
		nx = rng.randi_range(4, 6)
		nz = rng.randi_range(3, 4)
		wing_x = 2.0 / float(nx)
		wing_z = float(rng.randi_range(1, nz - 1)) / float(nz)
	elif shape == "u":
		nx = rng.randi_range(5, 6)
		nz = rng.randi_range(3, 4)
		wing_x = 2.0 / float(nx)
		wing_z = float(rng.randi_range(1, nz - 1)) / float(nz)
	var floors: int = rng.randi_range(1, 3)
	# 使用作者内核的180mm板厚，避免任意板厚使束带与板缘产生量化薄片。
	var slab: float = 0.18
	var sill_projection: float = [0.12, 0.16, 0.20][rng.randi_range(0, 2)]
	var floor_height: float = [3.4, 3.6, 4.0][rng.randi_range(0, 2)]
	var frame_width: float = [0.08, 0.10, 0.12][rng.randi_range(0, 2)]
	var pillar_width: float = [0.24, 0.30, 0.36][rng.randi_range(0, 2)]
	var sill: float = [0.8, 0.9, 1.0][rng.randi_range(0, 2)]
	# 窗与门同时服从最短翼段、框/柱墙垛和净层高，不先抽超限值再碰运气。
	var opening_budget: float = unit - 2.0 * (0.38 + frame_width) - pillar_width
	var window_width: float = snappedf(rng.randf_range(1.0, minf(1.6, opening_budget)), 0.1)
	var window_height: float = snappedf(rng.randf_range(1.4, minf(2.0, floor_height - slab - sill - frame_width - 0.22)), 0.1)
	var door_width: float = snappedf(rng.randf_range(1.0, minf(1.5, opening_budget)), 0.1)
	var door_height: float = snappedf(rng.randf_range(2.1, minf(2.6, floor_height - slab - 0.4)), 0.1)
	var structure_seed: int = rng.randi_range(0, 999999)
	recipe.merge({"building_id": "random_" + str(seed_value).sha256_text().substr(0, 12),
		"display_name": "随机房屋 · seed " + str(seed_value), "shape": shape,
		"width": unit * nx, "depth": unit * nz, "floors": floors,
		"floor_height": floor_height, "slab_thickness": slab, "bay_width": unit,
		"window_width": window_width, "window_height": window_height, "window_sill": sill,
		"door_width": door_width, "door_height": door_height, "taper": 0.0,
		"structure_seed": structure_seed, "damage_seed": rng.randi_range(0, 999999),
		"vegetation_seed": rng.randi_range(0, 999999)}, true)
	var architecture: Dictionary = recipe.architecture
	architecture.form.enabled = false
	architecture.plan.merge({"wing_x": wing_x, "wing_z": wing_z}, true)
	var window_type: String = ["fixed", "casement_left", "casement_right", "awning"][rng.randi_range(0, 3)]
	architecture.window.merge({"type": window_type,
		"open_angle": 0.0 if window_type == "fixed" else float(rng.randi_range(15, 35)),
		"width": window_width, "height": window_height, "sill": sill,
		"frame_width": frame_width, "frame_depth": [0.10, 0.12, 0.16][rng.randi_range(0, 2)],
		"sill_projection": sill_projection, "sill_enabled": rng.randf() < 0.7}, true)
	architecture.pilaster.merge({"enabled": rng.randf() < 0.7, "width": pillar_width,
		"corner": true, "middle": rng.randf() < 0.65,
		"projection": [0.12, 0.18, 0.24][rng.randi_range(0, 2)]}, true)
	architecture.band.merge({"enabled": floors > 1 and rng.randf() < 0.7,
		"thickness": [0.24, 0.34, 0.44][rng.randi_range(0, 2)],
		"projection": [0.06, 0.10, 0.14][rng.randi_range(0, 2)]}, true)
	architecture.roof.merge({"mode": ["none", "parapet", "railing", "mixed"][rng.randi_range(0, 3)],
		"height": [0.8, 1.0, 1.2][rng.randi_range(0, 2)],
		"thickness": [0.18, 0.24, 0.30][rng.randi_range(0, 2)],
		"post_spacing": [1.6, 2.0, 2.4][rng.randi_range(0, 2)],
		"rail_spacing": [0.4, 0.5, 0.6][rng.randi_range(0, 2)]}, true)
	if not current_recipe.is_empty():
		var current: Dictionary = Recipe.normalized(current_recipe)
		# shell_v2空色板由组件+aging取色；显式auto由稳定槽ID+角色+color_seed取色，
		# 两条路径均不读取structure_seed。完整保留输入，不把自动搭配压成单个手动色。
		recipe.aging = current.aging
		recipe.component_bindings = current.component_bindings.duplicate(true)
		architecture.palette = current.architecture.palette.duplicate(true)
		architecture.shading = current.architecture.shading.duplicate(true)
		for field: String in COLOR_FIELDS:
			architecture.window[field] = current.architecture.window[field].duplicate(true) if current.architecture.window[field] is Array else current.architecture.window[field]
		# 只延续旧窗作用域的颜色，不携带旧洞口尺寸/开关；新增楼层使用全局规则。
		for scope: String in ["floor_windows", "facade_windows", "window_overrides"]:
			for key: String in current.architecture[scope]:
				if scope == "floor_windows" and int(key) >= floors: continue
				if scope == "window_overrides" and int(key.split("_")[2]) >= floors: continue
				var colors: Dictionary = {}
				for field: String in COLOR_FIELDS:
					if current.architecture[scope][key].has(field):
						var value: Variant = current.architecture[scope][key][field]
						colors[field] = value.duplicate(true) if value is Array else value
				if not colors.is_empty(): architecture[scope][key] = colors
	if palette_override != null:
		# 上面的validate_palette已确认类型，此处才允许安全复制。
		architecture.palette = (palette_override as Dictionary).duplicate(true)
	return Recipe.normalized(recipe)

static func generate_candidates(seed_value: int, palette_override: Variant = null, current_recipe: Dictionary = {}) -> Array[Dictionary]:
	# 合法域内构造一个方案；非法输入无候选，不在失败后偷偷替换固定模板。
	var candidate: Dictionary = create(seed_value, palette_override, current_recipe)
	if candidate.is_empty(): return []
	return [candidate]
