@tool
extends RefCounted
## 连续原生参数外壳；不实例化节点、不写文件、不使用盒子拼接结构。
## position 为变形后几何包围盒中心；bounds_position 始终为 mesh 局部坐标。

const MeshBuilder = preload("res://src/workshop/mesh_builder.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const RoofEdge = preload("res://src/workshop/roof_edge_geometry.gd")
const WindowGeometry = preload("res://src/workshop/shell_window_geometry.gd")
const MAX_PARTS: int = 2000
const WALL_BEVEL: float = 0.02
const OUTER_CORNER_RADIUS: float = 0.07
const OUTER_CORNER_SEGMENTS: int = 3
const FRAME_PROFILE: float = 0.11
const FRAME_DEPTH: float = 0.12
const FRAME_BEVEL: float = 0.018
const CLEARANCE: float = 0.003
const GLASS_GAP: float = 0.002
# 结构板内收 30mm：板完全藏进墙壳，层间不出现"两种材质同面"的拼装亮带。
# 板位改由同色层间束带（_floor_belt）封平，立面读成"基座—墙身—檐口"三段式。
const SLAB_BAND: float = -0.03
# 层间束带：与墙同色、比墙皮只凸4mm，把板缘盖成一道细阴影缝，而不是一条彩色腰线。
const BELT_PROJECTION: float = 0.004
const BELT_BEVEL: float = 0.004
# 勒脚：整栋一圈基座环，让建筑落在场地上而不是浮在板面。
const PLINTH_HEIGHT: float = 0.42
const PLINTH_PROJECTION: float = 0.06
const PLINTH_BITE: float = 0.008
const PLINTH_BEVEL: float = 0.014
# 入口雨棚与落地柱：雨棚挑出、柱脚落地，不生成悬空构件。
const CANOPY_PROJECTION: float = 1.05
const CANOPY_EXTENSION: float = 0.4
const CANOPY_THICKNESS: float = 0.18
const CANOPY_LIFT: float = 0.16
const CANOPY_BEVEL: float = 0.018
# 柱截面0.18、从雨棚外端起算；柱心离开门框净边0.32m，透视下才不会被读成门框延伸出来的杆。
const CANOPY_POST: float = 0.18
const CANOPY_POST_INSET: float = 0.16
const CANOPY_POST_BEVEL: float = 0.014
const CANOPY_POST_EDGE: float = 0.1
# 门扇：厚度50mm、离门框净边2mm、从墙外皮退进60mm；倒角4mm。
const DOOR_LEAF_THICKNESS: float = 0.05
const DOOR_LEAF_RECESS: float = 0.06
const DOOR_LEAF_GAP: float = 0.002
const DOOR_LEAF_BEVEL: float = 0.004
# 板缘倒角收紧：0.028在0.18厚板上占15%，等距视角下会读成一条亮带接缝。
const SLAB_BEVEL: float = 0.012
# 墙底/墙顶只与楼板重叠0.8mm防浮点缝；3mm会在层间留下一道可见凹槽。
const INSET: float = 0.0008
const EPS: float = 0.000001
const WELD: float = 0.00001
const MAX_TRIANGLES: int = 180000

## 静态上下文没有 self，而 roof_edge_geometry / shell_window_geometry 需要本脚本的
## Script 句柄回调本文件的静态方法（它们不能 preload 本文件，否则循环引用）。
static func _self_script() -> Script:
	return load("res://src/workshop/shell_geometry.gd")

static func generate(recipe: Dictionary, catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "parts": [], "openings": [], "footprint": [], "quality": {"verification": "未运行Godot；未签署视觉或引擎验收"}}
	if not Recipe._finite_tree(recipe):
		return _failure(result, "配方必须是有限JSON数据")
	if recipe.has("architecture"):
		var config_reason: String = Config.validate(recipe.architecture, int(recipe.get("floors", 3)))
		if not config_reason.is_empty(): return _failure(result, config_reason)
	var r: Dictionary = Recipe.normalized(recipe)
	var c: Dictionary = catalog if not catalog.is_empty() else Catalog.definitions()
	var reason: String = _validate(r, c)
	if not reason.is_empty():
		return _failure(result, reason)
	var floors: int = int(r.floors)
	var plan: Dictionary = _structure_plan(r)
	var footprint_polygon: Array[Vector2] = _footprint(str(r.shape), float(r.width), float(r.depth), plan)
	var floor_contours: Array = []
	for floor in floors:
		var distance: float = 0.0 if int(plan.setback_start) < 0 else float(maxi(0, floor - int(plan.setback_start) + 1)) * float(plan.setback_step)
		var contour: Array[Vector2] = _offset(footprint_polygon, distance)
		var contour_reason: String = _validate_contour(footprint_polygon, contour, distance, float(r.wall_thickness))
		if not contour_reason.is_empty(): return _failure(result, "floor=" + str(floor) + ": " + contour_reason)
		floor_contours.append(contour)
	var polygon: Array[Vector2] = footprint_polygon
	var total_height: float = 0.0
	for floor in floors:
		total_height += _floor_value(r, floor, "floor_height")
	var context: Dictionary = {"height": total_height, "taper": float(r.taper), "aging": float(r.aging), "cache": {}, "collidable": str(r.spatial_profile) != "scenic_underwater", "error": "", "triangles": 0, "topology": {}}
	var parts: Array = []
	var openings: Array = []
	var roof_surfaces: Array = []
	var window_envelopes: Array = []
	var base: float = 0.0
	var band: Array[Vector2] = _offset(polygon, -SLAB_BAND)
	for floor in floors:
		polygon = floor_contours[floor]
		var slab_contour: Array[Vector2] = floor_contours[maxi(0, floor - 1)]
		band = _offset(slab_contour, -SLAB_BAND)
		var has_terrace: bool = floor > 0 and _polygon_area(floor_contours[floor]) < _polygon_area(floor_contours[floor - 1]) - EPS
		if has_terrace:
			roof_surfaces.append({"id": "terrace_floor_" + str(floor), "polygon": band.duplicate(), "y": base, "upper_polygon": polygon.duplicate(), "floor": floor})
		var thickness: float = _floor_value(r, floor, "slab_thickness")
		var slab: Dictionary = _buffer()
		_solid(slab, band, base - thickness, base, SLAB_BEVEL)
		_part(parts, slab, "slab_" + str(floor), "slab", floor, "", r, c, context, SLAB_BEVEL, true)
		var next_thickness: float = _floor_value(r, mini(floor + 1, floors - 1), "slab_thickness")
		var net_height: float = _floor_value(r, floor, "floor_height") - next_thickness
		var bottom: float = base - INSET
		var top: float = base + net_height + INSET
		var shell: Dictionary = _buffer()
		var counters: Dictionary = {}
		var accessories: Array = []
		var wall_depth: float = float(r.wall_thickness)
		var depth_levels: Array[float] = [0.0, WALL_BEVEL, wall_depth - WALL_BEVEL, wall_depth]
		var contours: Array = []
		for distance in depth_levels:
			var contour: Array[Vector2] = _offset(polygon, distance)
			var corners: Array = []
			for corner in polygon.size():
				corners.append(_corner_arc(polygon, contour[corner], corner, distance))
			contours.append(corners)
		for run_index in polygon.size():
			var next: int = (run_index + 1) % polygon.size()
			var start: Vector2 = polygon[run_index]
			var axis: Vector2 = (polygon[next] - start).normalized()
			var outward: Vector2 = Vector2(axis.y, -axis.x)
			var facade: String = _facade(outward)
			var length: float = start.distance_to(polygon[next])
			var run: Dictionary = {"start": start, "axis": axis, "outward": outward, "length": length, "depth": wall_depth, "ends": []}
			for contour in contours:
				var start_arc: Array[Vector2] = contour[run_index]
				var end_arc: Array[Vector2] = contour[next]
				run.ends.append(Vector2((start_arc[-1] - start).dot(axis), (end_arc[0] - start).dot(axis)))
			# bay_width为目标开间；整条run等分，短翼不能靠缩窗强塞。
			var count: int = maxi(1, floori(length / float(r.bay_width)))
			var door_bay: int = -1
			if floor == 0 and facade == "front":
				var closest: float = INF
				for bay in count:
					var x: float = (start + axis * length * (float(bay) + 0.5) / float(count)).x
					if absf(x) < closest:
						closest = absf(x)
						door_bay = bay
			var settings: Dictionary = _settings(r, floor, facade)
			var holes: Array = []
			for bay in count:
				var ordinal: int = int(counters.get(facade, 0))
				counters[facade] = ordinal + 1
				var is_door: bool = bay == door_bay
				var suffix: String = facade + "_" + str(floor) + "_" + str(ordinal)
				var effective: Dictionary = settings.duplicate(true)
				if r.has("architecture") and not is_door:
					effective.merge(Config.window_settings(r, floor, facade, "opening_" + suffix), true)
				if not is_door and not bool(effective.get("enabled", effective.windows)):
					continue
				if r.has("architecture") and not is_door:
					var window_reason: String = WindowGeometry.validate(Config.window_settings(r, floor, facade, "opening_" + suffix), wall_depth)
					if not window_reason.is_empty(): return _failure(result, "opening_" + suffix + ": " + window_reason)
				var hole: Dictionary = _opening(base, bottom, length * (float(bay) + 0.5) / float(count), effective, is_door)
				if r.has("architecture") and not is_door:
					hole["settings"] = Config.window_settings(r, floor, facade, "opening_" + suffix)
					var envelope_reason: String = WindowGeometry.validate_bay(hole, run, length * float(bay) / float(count), length * float(bay + 1) / float(count), base, top)
					if not envelope_reason.is_empty(): return _failure(result, "opening_" + suffix + ": " + envelope_reason)
					var separation_reason: String = WindowGeometry.register_envelope(window_envelopes, hole, run, "opening_" + suffix, floor)
					if not separation_reason.is_empty(): return _failure(result, separation_reason)
				var margin: float = wall_depth + 0.08
				if float(hole.x0) - WALL_BEVEL < margin or float(hole.x1) + WALL_BEVEL > length - margin or float(hole.y1) + WALL_BEVEL > top - 0.08 or (not is_door and float(hole.y0) - WALL_BEVEL < base + 0.08):
					return _failure(result, "开口与墙角/楼板冲突，不能缩小净尺寸: " + facade + " floor=" + str(floor) + " bay=" + str(bay))
				if float(hole.x1) - float(hole.x0) + WALL_BEVEL * 2.0 + 0.08 > length / float(count):
					return _failure(result, "统一bay无法容纳净洞、框材与墙垛: " + facade)
				holes.append(hole)
				accessories.append({"hole": hole, "run": run, "suffix": suffix, "facade": facade})
				openings.append(_public_opening(hole, run, suffix, facade, floor, context))
			_face_grid(shell, run, holes, bottom, top, 0, 0.0)
			_face_grid(shell, run, holes, bottom, top, 3, wall_depth)
			_caps(shell, run, holes, bottom, top, depth_levels)
			for hole in holes:
				_reveal(shell, run, hole, depth_levels)
		_corner_surfaces(shell, polygon, contours, bottom, top)
		_part(parts, shell, "wall_shell_" + str(floor), "wall", floor, "", r, c, context, WALL_BEVEL, true)
		for entry in accessories:
			var hole: Dictionary = entry.hole
			var run: Dictionary = entry.run
			if hole.has("settings"):
				WindowGeometry.append_parts(parts, hole, run, str(entry.suffix), floor, str(entry.facade), r, c, context, _self_script())
				continue
			var frame: Dictionary = _buffer()
			if bool(hole.door):
				_door_frame(frame, hole, run)
			else:
				_window_frame(frame, hole, run)
			_part(parts, frame, "frame_" + str(entry.suffix), "frame", floor, str(entry.facade), r, c, context, FRAME_BEVEL, false)
			if bool(hole.door):
				# 门洞必须是"门"，不是能看穿室内的墙洞：补一扇实际门扇，按框内净尺寸退进 60mm。
				var leaf: Dictionary = _buffer()
				_door_leaf(leaf, hole, run)
				_part(parts, leaf, "door_" + str(entry.suffix), "frame", floor, str(entry.facade), r, c, context, DOOR_LEAF_BEVEL, false)
			else:
				var glass: Dictionary = _buffer()
				_glass(glass, hole, run)
				_part(parts, glass, "glass_" + str(entry.suffix), "glass", floor, str(entry.facade), r, c, context, 0.0, false)
		if floor == 0:
			for entry in accessories:
				if bool(entry.hole.door):
					_opening_canopy(parts, entry.hole, entry.run, r, c, context)
					break
		# 束带盖住本层板缘：从墙顶到下一层板顶，与墙同材质，立面才连续。
		var belt: Dictionary = _buffer()
		var belt_bottom: float = base + net_height + INSET
		var belt_top: float = base + _floor_value(r, floor, "floor_height")
		var belt_outer: Array[Vector2] = _rounded_outline(polygon, -BELT_PROJECTION)
		var belt_inner: Array[Vector2] = _rounded_outline(polygon, wall_depth * 0.6)
		_ring_solid(belt, belt_outer, belt_inner, belt_bottom, belt_top, BELT_BEVEL)
		_part(parts, belt, "belt_" + str(floor), "wall", floor, "", r, c, context, BELT_BEVEL, false)
		base += _floor_value(r, floor, "floor_height")
	# 勒脚环：与墙皮齐平咬入，不把主体垫高、不封住门洞。
	if str(r.shape) in ["rectangle", "l", "t", "u"]:
		var plinth: Dictionary = _buffer()
		var plinth_outer: Array[Vector2] = _rounded_outline(footprint_polygon, -PLINTH_PROJECTION)
		var plinth_inner: Array[Vector2] = _rounded_outline(footprint_polygon, PLINTH_BITE)
		_ring_solid(plinth, plinth_outer, plinth_inner, 0.0, PLINTH_HEIGHT, PLINTH_BEVEL)
		_part(parts, plinth, "plinth_0", "slab", 0, "", r, c, context, PLINTH_BEVEL, false)
	var roof: Dictionary = _buffer()
	var roof_thickness: float = _floor_value(r, floors - 1, "slab_thickness")
	band = _offset(polygon, -SLAB_BAND)
	_solid(roof, band, total_height - roof_thickness, total_height, SLAB_BEVEL)
	_part(parts, roof, "roof_main", "roof", floors, "", r, c, context, SLAB_BEVEL, true)
	roof_surfaces.append({"id": "roof_main", "polygon": band.duplicate(), "y": total_height, "floor": floors})
	if r.has("architecture"):
		var roof_reason: String = RoofEdge.append_parts(parts, r, c, roof_surfaces, context, _self_script())
		if not roof_reason.is_empty(): return _failure(result, roof_reason)
	if not str(context.error).is_empty():
		return _failure(result, str(context.error))
	var footprint: Array = []
	for point in footprint_polygon:
		footprint.append(Vector3(point.x, 0.0, point.y))
	result.ok = true
	result.parts = parts
	result.openings = openings
	result.footprint = footprint
	result["roof_surfaces"] = roof_surfaces
	result.quality = {
		"verification": "生成时执行位置焊接拓扑审计；未运行Godot，未签署视觉/引擎验收",
		"topology": context.topology, "triangles": context.triangles,
		"wall_corner": "凸外角为三段quarter-circle实体弧面，与墙run及厚度封面连续连接",
		"corner_bevel_width": OUTER_CORNER_RADIUS, "outer_corner_radius": OUTER_CORNER_RADIUS, "outer_corner_segments": OUTER_CORNER_SEGMENTS,
		"corner_radius_space": "变形前worldXZ；taper后按相同高度比例缩放",
		"inner_corner_profile": "锐miter", "l_concave_corner_profile": "锐miter",
		"opening_bevel_width": WALL_BEVEL, "opening_bevel_profile": "chamfer", "opening_bevel_segments": 1,
		"opening_depth_profile": "外侧单段chamfer→直返回面→内侧单段chamfer；不是三段圆弧",
		"slab_bevel_width": SLAB_BEVEL, "slab_bevel_segments": 3,
		"frame_bevel_width": FRAME_BEVEL, "frame_bevel_profile": "chamfer", "frame_bevel_segments": 1,
		"prefab_handling": "按catalog配色生成基线占位网格并保留component_id；shell_generator负责整件替换、安全/接口校验及实例化",
		"topology_scope": "仅基线网格变形前位置焊接审计；taper后实际引擎拓扑与prefab替换后几何待主线程验证",
		"slab_overhang": SLAB_BAND, "joint_intentional_inset": INSET,
		"taper_mapping": "整栋同一worldXZ随y/totalH线性缩放；所有顶点共用映射",
		"opening_dimensions": "clear_width/height为变形前净孔；变形后宽度见width_bottom/width_top",
		"glass_gap": GLASS_GAP, "glass_thickness_before_taper": "各洞口settings.glass_thickness" if r.has("architecture") else 0.02,
		"part_count": parts.size(), "part_budget": MAX_PARTS,
		"plan": plan, "floor_contours_before_taper": floor_contours,
		"roof_surface_space": "变形前worldXZ/y，polygon为结构板最大外边界（板顶弧缘内收0.028m）；terrace.upper_polygon为本层墙外轮廓",
		"roof_boundaries": roof_surfaces, "roof_edge_quality": context.get("roof_edge_quality", {}),
		"supported_shapes": ["rectangle", "l", "t", "u"],
		"window_policy": "architecture可选；旧配方无新扇/窗沿/屋顶附件。单窗enabled=false封实墙但保留ordinal；门不应用窗开关或尺寸。固定框净孔clear_width/height保持不变，实际玻璃净尺寸见glass_clear_*；活动扇留2mm外装配缝，sash_profile=frame_width*0.65。完整0..open_angle解析扫掠包络限制在各bay并检查相邻包络；冲突拒绝、不缩窗",
		"window_recess_policy": "recess为外墙面到固定框中心，框前后端必须在WALL_BEVEL+3mm安全区内；窗沿背面停在墙外3mm",
		"window_hinge_policy": "左右净孔边/上净孔边、中壁深铰链；窗扇与玻璃共同在world中朝外旋转，再应用全局taper",
		"style_verification": "未签署全风格、引擎或视觉验收",
		"standard_exceptions": [{"parts": "slab_*及roof_main", "profile": "连续结构板formed_band", "reason": "不是平台装饰木板；明确采用0.028m三段外缘倒角"}],
		"structural_claim": "自支撑墙壳几何；未执行建筑物理或承载计算",
		"known_limitations": ["damage非0明确拒绝", "支持rectangle/l/t/u正交轮廓与wing_x/wing_z及逐层累计退台；不支持任意多边形；内缩反转/自交/翼宽耗尽直接拒绝", "凸外角仅三段实体圆弧；内角与L/T/U凹角保留锐miter，未做墙顶底水平边圆弧", "洞口与框材每端仅单段chamfer，不是三段quarter-circle", "结构槽仅允许无作用disabled:false/零offset，禁用true/非零位移/排除明确拒绝", "prefab仅保留绑定和基线占位网格，本脚本不加载或实例化prefab", "不生成植物、楼梯、导航或碰撞节点；collidable仅声明三角网格碰撞用途", "全局taper同时缩放净孔/框材/墙厚；原配方尺寸为变形前参数", "taper后的实际引擎拓扑及最终美术效果未验证"]
	}
	return result

static func _failure(result: Dictionary, reason: String) -> Dictionary:
	result.ok = false
	result.reason = reason
	result.parts = []
	result.openings = []
	result.footprint = []
	result["roof_surfaces"] = []
	return result

static func _validate(r: Dictionary, c: Dictionary) -> String:
	for field in ["width", "depth", "floors", "floor_height", "slab_thickness", "wall_thickness", "bay_width", "window_width", "window_height", "window_sill", "door_width", "door_height", "taper", "aging", "damage"]:
		if not (r[field] is float or r[field] is int):
			return "数值字段类型非法: " + field
	if float(r.damage) != 0.0:
		return "连续外壳暂不支持damage非0；不能以删盒子伪造破损"
	if str(r.shape) not in ["rectangle", "l", "t", "u"] or float(r.floors) != float(int(r.floors)) or int(r.floors) < 1 or int(r.floors) > 8:
		return "仅支持rectangle/l/t/u及1..8整数楼层"
	if float(r.width) < 6.0 or float(r.width) > 24.0 or float(r.depth) < 6.0 or float(r.depth) > 20.0:
		return "宽度必须6..24m，深度必须6..20m"
	if float(r.wall_thickness) < 0.12 or float(r.wall_thickness) > 0.6 or float(r.bay_width) < 2.0 or float(r.bay_width) > 6.0:
		return "墙厚必须0.12..0.6m，bay_width必须2..6m"
	if float(r.taper) < 0.0 or float(r.taper) > 0.1 or float(r.aging) < 0.0 or float(r.aging) > 1.0:
		return "taper/aging越界"
	if str(r.spatial_profile) not in ["above_water", "scenic_underwater", "dive_static"]:
		return "未知spatial_profile"
	var floor_reason: String = Recipe._validate_floor_overrides(r.floor_overrides, int(r.floors))
	if not floor_reason.is_empty(): return floor_reason
	var facade_reason: String = Recipe._validate_facade_overrides(r.facade_overrides)
	if not facade_reason.is_empty(): return facade_reason
	if not r.component_bindings is Dictionary or not c.get("components", null) is Dictionary:
		return "缺少组件绑定或catalog.components"
	if not r.slot_overrides is Dictionary or not r.excluded_slots is Array:
		return "slot_overrides/excluded_slots类型非法"
	for role in ["wall", "slab", "frame", "glass"]:
		var component: String = _component(r, role, "")
		var definition: Variant = c.components.get(component, null)
		if not definition is Dictionary or str(definition.get("family", "")) != role or str(definition.get("kind", "")) not in ["parametric", "prefab"]:
			return "连续外壳需要对应族的parametric/prefab组件: " + component
	for excluded in r.excluded_slots:
		if not str(excluded).begins_with("plant_"):
			return "连续结构不支持排除结构槽: " + str(excluded)
	for key in r.slot_overrides:
		if str(key).begins_with("plant_"): continue
		var entry: Variant = r.slot_overrides[key]
		if not entry is Dictionary: return "槽覆盖必须为Dictionary"
		for field in entry:
			match str(field):
				"component_id":
					pass
				"disabled":
					if not entry[field] is bool or entry[field]:
						return "连续结构仅允许disabled:false: " + str(key)
				"offset":
					var offset: Variant = entry[field]
					if not offset is Array or offset.size() != 3:
						return "连续结构offset必须为三维零数组: " + str(key)
					for value in offset:
						if not (value is int or value is float) or float(value) != 0.0:
							return "连续结构不允许非零offset: " + str(key)
				_:
					return "连续结构不支持槽覆盖字段: " + str(key) + "." + str(field)
		var family: String = Recipe._slot_family(str(key))
		if family.is_empty(): return "未知结构槽族: " + str(key)
		if entry.has("component_id"):
			var definition: Variant = c.components.get(str(entry.component_id), null)
			if not definition is Dictionary or str(definition.get("family", "")) != family or str(definition.get("kind", "")) not in ["parametric", "prefab"]:
				return "结构槽组件不兼容: " + str(key)
	for floor in int(r.floors):
		var height: float = _floor_value(r, floor, "floor_height")
		var thickness: float = _floor_value(r, floor, "slab_thickness")
		if height < 2.0 or height > 12.0 or thickness < 0.08 or thickness > 0.6 or thickness >= height:
			return "楼层高度或结构板厚越界"
		for facade in ["front", "back", "left", "right"]:
			var settings: Dictionary = _settings(r, floor, facade)
			if r.has("architecture"):
				var merged: Dictionary = Config.window_settings(r, floor, facade)
				var window_reason: String = Config._validate_window(merged, "合成窗配置")
				if not window_reason.is_empty(): return window_reason
			for field in ["width", "height", "sill", "door_width", "door_height"]:
				if float(settings[field]) <= 0.0: return "开口尺寸必须为正值"
	return ""

static func _component(r: Dictionary, kind: String, id: String) -> String:
	var family: String = Recipe._slot_family(id)
	if family.is_empty(): family = "slab" if kind == "roof" else kind
	var raw_override: Variant = r.slot_overrides.get(id, {})
	var override: Dictionary = raw_override if raw_override is Dictionary else {}
	var defaults: Dictionary = {"wall": "wall_sun", "slab": "slab_warm", "frame": "frame_timber", "glass": "glass_blue"}
	return str(override.get("component_id", r.component_bindings.get(family, defaults.get(family, ""))))

static func _floor_value(r: Dictionary, floor: int, field: String) -> float:
	var entry: Dictionary = r.floor_overrides.get(str(floor), {})
	return float(entry.get(field, r[field]))

static func _settings(r: Dictionary, floor: int, facade: String) -> Dictionary:
	var result: Dictionary = {"windows": true, "width": _floor_value(r, floor, "window_width"), "height": _floor_value(r, floor, "window_height"), "sill": _floor_value(r, floor, "window_sill"), "door_width": float(r.door_width), "door_height": float(r.door_height)}
	var override: Dictionary = r.facade_overrides.get(facade, {})
	for field in override: result[field] = override[field]
	return result

static func _structure_plan(r: Dictionary) -> Dictionary:
	return Config.normalized(r.get("architecture", {})).plan.duplicate(true)

static func _footprint(shape: String, width: float, depth: float, plan: Dictionary = {}) -> Array[Vector2]:
	var x: float = width * 0.5
	var z: float = depth * 0.5
	var wing_x: float = float(plan.get("wing_x", 0.5))
	var wing_z: float = float(plan.get("wing_z", 0.5))
	var xcut: float = -x + width * wing_x
	var zcut: float = -z + depth * wing_z
	match shape:
		"l":
			return [Vector2(-x, -z), Vector2(x, -z), Vector2(x, zcut), Vector2(xcut, zcut), Vector2(xcut, z), Vector2(-x, z)]
		"t":
			var stem: float = width * wing_x * 0.5
			return [Vector2(-x, -z), Vector2(x, -z), Vector2(x, zcut), Vector2(stem, zcut), Vector2(stem, z), Vector2(-stem, z), Vector2(-stem, zcut), Vector2(-x, zcut)]
		"u":
			var side: float = width * wing_x * 0.5
			return [Vector2(-x, -z), Vector2(x, -z), Vector2(x, z), Vector2(x - side, z), Vector2(x - side, zcut), Vector2(-x + side, zcut), Vector2(-x + side, z), Vector2(-x, z)]
	return [Vector2(-x, -z), Vector2(x, -z), Vector2(x, z), Vector2(-x, z)]

static func _polygon_area(polygon: Array[Vector2]) -> float:
	var area: float = 0.0
	for i in polygon.size(): area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return area * 0.5

static func _on_segment(point: Vector2, a: Vector2, b: Vector2) -> bool:
	return absf((b - a).cross(point - a)) <= EPS and (point - a).dot(point - b) <= EPS

static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if _on_segment(a, c, d) or _on_segment(b, c, d) or _on_segment(c, a, b) or _on_segment(d, a, b): return true
	return (b - a).cross(c - a) * (b - a).cross(d - a) < 0.0 and (d - c).cross(a - c) * (d - c).cross(b - c) < 0.0

static func _simple_polygon(polygon: Array[Vector2]) -> bool:
	if polygon.size() < 3 or _polygon_area(polygon) <= EPS: return false
	for i in polygon.size():
		var next: int = (i + 1) % polygon.size()
		if not polygon[i].is_finite() or polygon[i].distance_to(polygon[next]) <= EPS: return false
		for j in range(i + 1, polygon.size()):
			var other_next: int = (j + 1) % polygon.size()
			if j == next or other_next == i: continue
			if _segments_intersect(polygon[i], polygon[next], polygon[j], polygon[other_next]): return false
	return true

static func _valid_inset(source: Array[Vector2], inset: Array[Vector2], minimum_edge: float) -> bool:
	if source.size() != inset.size() or not _simple_polygon(inset): return false
	var packed: PackedVector2Array = PackedVector2Array(source)
	for i in source.size():
		var next: int = (i + 1) % source.size()
		# 面积重新变正也可能是过度offset后绕回；对应边必须仍同向。
		if (inset[next] - inset[i]).dot((source[next] - source[i]).normalized()) <= minimum_edge: return false
		if not Geometry2D.is_point_in_polygon(inset[i], packed): return false
		if not Geometry2D.is_point_in_polygon((inset[i] + inset[next]) * 0.5, packed): return false
		# 同向内缩边仍可能在凹轮廓中越过另一翼；检查真实线段穿越。
		for j in source.size():
			if _segments_intersect(inset[i], inset[next], source[j], source[(j + 1) % source.size()]): return false
	return _polygon_area(inset) <= _polygon_area(source) + EPS

static func _validate_contour(source: Array[Vector2], contour: Array[Vector2], setback: float, wall_depth: float) -> String:
	if not _simple_polygon(contour): return "退台轮廓面积无效或自相交"
	if setback > EPS and not _valid_inset(source, contour, OUTER_CORNER_RADIUS * 2.0 + CLEARANCE):
		return "退台导致翼宽耗尽、轮廓反转或越界"
	var inner: Array[Vector2] = _offset(contour, wall_depth)
	if not _valid_inset(contour, inner, CLEARANCE): return "墙内轮廓反转/自相交或翼宽不足墙厚"
	for i in contour.size():
		if contour[i].distance_to(contour[(i + 1) % contour.size()]) <= OUTER_CORNER_RADIUS * 2.0 + CLEARANCE:
			return "墙段长度不足以连接真实曲角"
	return ""

static func _offset(polygon: Array[Vector2], inward: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in polygon.size():
		var a: Vector2 = (polygon[i] - polygon[(i - 1 + polygon.size()) % polygon.size()]).normalized()
		var b: Vector2 = (polygon[(i + 1) % polygon.size()] - polygon[i]).normalized()
		var na: Vector2 = Vector2(-a.y, a.x)
		var nb: Vector2 = Vector2(-b.y, b.x)
		result.append(polygon[i] + (na + nb) * inward / (1.0 + na.dot(nb)))
	return result

## 与墙壳同源的圆角轮廓：凸外角按同一半径采段，凹角保持 miter。
## 勒脚/层间束带必须用它，否则转角是直角、墙面是圆弧，两者在墙角错开成一条竖缝。
static func _rounded_outline(polygon: Array[Vector2], inset: float) -> Array[Vector2]:
	var contour: Array[Vector2] = _offset(polygon, inset)
	var result: Array[Vector2] = []
	for corner in polygon.size():
		for point in _corner_arc(polygon, contour[corner], corner, inset):
			result.append(point)
	return result

static func _corner_arc(polygon: Array[Vector2], point: Vector2, corner: int, depth: float) -> Array[Vector2]:
	var incoming: Vector2 = (polygon[corner] - polygon[(corner - 1 + polygon.size()) % polygon.size()]).normalized()
	var outgoing: Vector2 = (polygon[(corner + 1) % polygon.size()] - polygon[corner]).normalized()
	# XZ轮廓为CCW；仅左转凸角圆弧化，右转的L凹角仍是共享miter。
	var radius: float = maxf(0.0, OUTER_CORNER_RADIUS - depth) if incoming.cross(outgoing) > EPS else 0.0
	var center: Vector2 = point - incoming * radius + outgoing * radius
	var result: Array[Vector2] = []
	for step in range(OUTER_CORNER_SEGMENTS + 1):
		if step == 0:
			result.append(point - incoming * radius)
		elif step == OUTER_CORNER_SEGMENTS:
			result.append(point + outgoing * radius)
		else:
			var angle: float = float(step) / float(OUTER_CORNER_SEGMENTS) * PI * 0.5
			result.append(center + (incoming * sin(angle) - outgoing * cos(angle)) * radius)
	return result

static func _corner_surfaces(buffer: Dictionary, polygon: Array[Vector2], contours: Array, bottom: float, top: float) -> void:
	for corner in polygon.size():
		for layer in [0, 3]:
			var arc: Array[Vector2] = contours[layer][corner]
			for segment in OUTER_CORNER_SEGMENTS:
				var a: Vector2 = arc[segment]
				var b: Vector2 = arc[segment + 1]
				var edge: Vector2 = b - a
				var normal: Vector3 = Vector3(edge.y, 0.0, -edge.x) * (1.0 if layer == 0 else -1.0)
				_quad(buffer, Vector3(a.x, bottom, a.y), Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, bottom, b.y), normal)
		for layer in 3:
			var outer: Array[Vector2] = contours[layer][corner]
			var inner: Array[Vector2] = contours[layer + 1][corner]
			for segment in OUTER_CORNER_SEGMENTS:
				var a: Vector2 = outer[segment]
				var b: Vector2 = outer[segment + 1]
				var c: Vector2 = inner[segment + 1]
				var d: Vector2 = inner[segment]
				# radius归零后两点重合，_quad保留有效三角扇封面，不生成角柱/内部隔面。
				_quad(buffer, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y), Vector3(d.x, top, d.y), Vector3.UP)
				_quad(buffer, Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(c.x, bottom, c.y), Vector3(d.x, bottom, d.y), Vector3.DOWN)

static func _facade(normal: Vector2) -> String:
	if normal.x > 0.5: return "right"
	if normal.x < -0.5: return "left"
	return "back" if normal.y > 0.0 else "front"

static func _point(run: Dictionary, x: float, y: float, depth: float) -> Vector3:
	var start: Vector2 = run.start
	var axis: Vector2 = run.axis
	var outward: Vector2 = run.outward
	var point: Vector2 = start + axis * x - outward * depth
	return Vector3(point.x, y, point.y)

static func _opening(base: float, bottom: float, center_x: float, settings: Dictionary, door: bool) -> Dictionary:
	var w: float = float(settings.door_width if door else settings.width)
	var h: float = float(settings.door_height if door else settings.height)
	var sill: float = base if door else base + float(settings.sill)
	var profile: float = FRAME_PROFILE if door else float(settings.get("frame_width", FRAME_PROFILE))
	var half: float = w * 0.5 + profile + CLEARANCE
	return {"x0": center_x - half, "x1": center_x + half, "y0": bottom if door else sill - profile - CLEARANCE, "y1": sill + h + profile + CLEARANCE, "sill": sill, "cx": center_x, "width": w, "height": h, "door": door}

static func _hole_rect(hole: Dictionary, surface: bool) -> Rect2:
	var b: float = WALL_BEVEL if surface else 0.0
	var low: float = float(hole.y0) if bool(hole.door) else float(hole.y0) - b
	return Rect2(Vector2(float(hole.x0) - b, low), Vector2(float(hole.x1) - float(hole.x0) + b * 2.0, float(hole.y1) + b - low))

static func _face_grid(buffer: Dictionary, run: Dictionary, holes: Array, bottom: float, top: float, layer: int, depth: float) -> void:
	var limits: Vector2 = run.ends[layer]
	var xs: Array[float] = [limits.x, limits.y]
	var ys: Array[float] = [bottom, top]
	var rectangles: Array[Rect2] = []
	for hole in holes:
		var rect: Rect2 = _hole_rect(hole, true)
		rectangles.append(rect)
		xs.append(rect.position.x); xs.append(rect.end.x)
		ys.append(rect.position.y); ys.append(rect.end.y)
	xs = _unique(xs); ys = _unique(ys)
	var normal2: Vector2 = run.outward
	var expected: Vector3 = Vector3(normal2.x, 0.0, normal2.y) * (1.0 if layer == 0 else -1.0)
	for i in range(xs.size() - 1):
		for j in range(ys.size() - 1):
			var mid: Vector2 = Vector2((xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5)
			var skip: bool = false
			for rect in rectangles:
				if rect.has_point(mid): skip = true; break
			if not skip:
				_quad(buffer, _point(run, xs[i], ys[j], depth), _point(run, xs[i], ys[j + 1], depth), _point(run, xs[i + 1], ys[j + 1], depth), _point(run, xs[i + 1], ys[j], depth), expected)

static func _unique(values: Array[float]) -> Array[float]:
	values.sort()
	var result: Array[float] = []
	for value in values:
		if result.is_empty() or absf(value - result[-1]) > EPS: result.append(value)
	return result

static func _caps(buffer: Dictionary, run: Dictionary, holes: Array, bottom: float, top: float, levels: Array[float]) -> void:
	var door: Dictionary = {}
	for hole in holes:
		if bool(hole.door): door = hole
	for layer in 3:
		var a: Vector2 = run.ends[layer]
		var b: Vector2 = run.ends[layer + 1]
		_quad(buffer, _point(run, a.x, top, levels[layer]), _point(run, a.y, top, levels[layer]), _point(run, b.y, top, levels[layer + 1]), _point(run, b.x, top, levels[layer + 1]), Vector3.UP)
		if door.is_empty():
			_quad(buffer, _point(run, a.x, bottom, levels[layer]), _point(run, a.y, bottom, levels[layer]), _point(run, b.y, bottom, levels[layer + 1]), _point(run, b.x, bottom, levels[layer + 1]), Vector3.DOWN)
		else:
			var ra: Rect2 = _hole_rect(door, layer == 0 or layer == 3)
			var rb: Rect2 = _hole_rect(door, layer + 1 == 3)
			_quad(buffer, _point(run, a.x, bottom, levels[layer]), _point(run, ra.position.x, bottom, levels[layer]), _point(run, rb.position.x, bottom, levels[layer + 1]), _point(run, b.x, bottom, levels[layer + 1]), Vector3.DOWN)
			_quad(buffer, _point(run, ra.end.x, bottom, levels[layer]), _point(run, a.y, bottom, levels[layer]), _point(run, b.y, bottom, levels[layer + 1]), _point(run, rb.end.x, bottom, levels[layer + 1]), Vector3.DOWN)

static func _reveal(buffer: Dictionary, run: Dictionary, hole: Dictionary, levels: Array[float]) -> void:
	# 三个深度区间分别为单段chamfer、直返回面、单段chamfer，并非三段圆弧。
	var rings: Array = []
	for layer in 4:
		var rect: Rect2 = _hole_rect(hole, layer == 0 or layer == 3)
		rings.append([_point(run, rect.position.x, rect.position.y, levels[layer]), _point(run, rect.position.x, rect.end.y, levels[layer]), _point(run, rect.end.x, rect.end.y, levels[layer]), _point(run, rect.end.x, rect.position.y, levels[layer])])
	var axis2: Vector2 = run.axis
	var axis: Vector3 = Vector3(axis2.x, 0.0, axis2.y)
	var expected: Array[Vector3] = [axis, Vector3.DOWN, -axis, Vector3.UP]
	for layer in 3:
		var a: Array = rings[layer]
		var b: Array = rings[layer + 1]
		for edge in (3 if bool(hole.door) else 4):
			var next: int = (edge + 1) % 4
			_quad(buffer, a[edge], a[next], b[next], b[edge], expected[edge])

static func _public_opening(hole: Dictionary, run: Dictionary, suffix: String, facade: String, floor: int, context: Dictionary) -> Dictionary:
	var y: float = float(hole.sill) + float(hole.height) * 0.5
	var center: Vector3 = _point(run, float(hole.cx), y, float(run.depth) * 0.5)
	var axis2: Vector2 = run.axis
	var n2: Vector2 = run.outward
	var scale: float = _scale_at(y, context)
	var normal: Vector3 = Vector3(n2.x / scale, float(context.taper) * (center.x * n2.x + center.z * n2.y) / (float(context.height) * scale), n2.y / scale).normalized()
	var result: Dictionary = {"id": "opening_" + suffix, "facade": facade, "floor": floor, "center": _map(center, context), "clear_width": float(hole.width), "clear_height": float(hole.height), "axis": Vector3(axis2.x, 0.0, axis2.y), "outward": normal, "wall_thickness": float(run.depth) * scale, "width_bottom": float(hole.width) * _scale_at(float(hole.sill), context), "width_top": float(hole.width) * _scale_at(float(hole.sill) + float(hole.height), context), "type": "door" if bool(hole.door) else "window"}
	if hole.has("settings"):
		result.merge(WindowGeometry.metadata(hole, run, _self_script(), context), true)
	return result

static func _window_frame(buffer: Dictionary, hole: Dictionary, run: Dictionary) -> void:
	var cx: float = float(hole.cx)
	var cy: float = float(hole.sill) + float(hole.height) * 0.5
	var w: float = float(hole.width)
	var h: float = float(hole.height)
	var settings: Dictionary = hole.get("settings", {})
	var profile: float = float(settings.get("frame_width", FRAME_PROFILE))
	var depth: float = float(settings.get("frame_depth", FRAME_DEPTH))
	var recess: float = float(settings.get("recess", float(run.depth) * 0.5))
	var bevel: float = minf(FRAME_BEVEL, minf(profile, depth) * 0.45)
	var outer: Array[Vector2] = _rectangle(cx, cy, w + profile * 2.0, h + profile * 2.0)
	var inner: Array[Vector2] = _rectangle(cx, cy, w, h)
	var rings: Array = []
	var levels: Array[float] = [-depth * 0.5, -depth * 0.5 + bevel, depth * 0.5 - bevel, depth * 0.5]
	for layer in 4:
		var face: bool = layer == 0 or layer == 3
		var outside: Array[Vector2] = _offset(outer, bevel if face else 0.0)
		var inside: Array[Vector2] = _offset(inner, -bevel if face else 0.0)
		rings.append([_run_ring(outside, run, recess + levels[layer]), _run_ring(inside, run, recess + levels[layer])])
	var n2: Vector2 = run.outward
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	for layer in 4:
		var outside: Array = rings[layer][0]
		var inside: Array = rings[layer][1]
		if layer == 0 or layer == 3:
			for edge in 4:
				var next: int = (edge + 1) % 4
				_quad(buffer, outside[edge], outside[next], inside[next], inside[edge], n if layer == 0 else -n)
		if layer < 3:
			_join_profile(buffer, rings[layer][0], rings[layer + 1][0], outer, run, false)
			_join_profile(buffer, rings[layer][1], rings[layer + 1][1], inner, run, true)

static func _door_frame(buffer: Dictionary, hole: Dictionary, run: Dictionary) -> void:
	var x0: float = float(hole.cx) - float(hole.width) * 0.5 - FRAME_PROFILE
	var x1: float = float(hole.cx) + float(hole.width) * 0.5 + FRAME_PROFILE
	var y0: float = float(hole.sill)
	var y1: float = y0 + float(hole.height) + FRAME_PROFILE
	var p: float = FRAME_PROFILE
	# 单个U形二维实体，开口向下；没有阈板或三个相叠盒子。
	var profile: Array[Vector2] = [Vector2(x0, y0), Vector2(x0 + p, y0), Vector2(x0 + p, y1 - p), Vector2(x1 - p, y1 - p), Vector2(x1 - p, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	_extrude_profile(buffer, profile, run)

## 门扇：单块实体板，落在洞口净尺寸内、从墙外皮退进 DOOR_LEAF_RECESS。
## 只做门扇本体，不做门把手/玻璃视窗/双开分缝——那些需要有依据的构造图，不猜。
static func _door_leaf(buffer: Dictionary, hole: Dictionary, run: Dictionary) -> void:
	var half: float = float(hole.width) * 0.5 - DOOR_LEAF_GAP
	var cx: float = float(hole.cx)
	var y0: float = float(hole.sill) + DOOR_LEAF_GAP
	var y1: float = float(hole.sill) + float(hole.height) - DOOR_LEAF_GAP
	var near: float = DOOR_LEAF_RECESS
	var far: float = DOOR_LEAF_RECESS + DOOR_LEAF_THICKNESS
	_solid(buffer, _run_rect(run, cx, half, near, far), y0, y1, DOOR_LEAF_BEVEL)

static func _extrude_profile(buffer: Dictionary, profile: Array[Vector2], run: Dictionary) -> void:
	var face: Array[Vector2] = _offset(profile, FRAME_BEVEL)
	var levels: Array[float] = [-FRAME_DEPTH * 0.5, -FRAME_DEPTH * 0.5 + FRAME_BEVEL, FRAME_DEPTH * 0.5 - FRAME_BEVEL, FRAME_DEPTH * 0.5]
	var rings: Array = []
	for layer in 4:
		rings.append(_run_ring(face if layer == 0 or layer == 3 else profile, run, float(run.depth) * 0.5 + levels[layer]))
	var n2: Vector2 = run.outward
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	_profile_face(buffer, rings[0], face, n)
	_profile_face(buffer, rings[3], face, -n)
	for layer in 3:
		_join_profile(buffer, rings[layer], rings[layer + 1], profile, run, false)

static func _rectangle(cx: float, cy: float, w: float, h: float) -> Array[Vector2]:
	return [Vector2(cx - w * 0.5, cy - h * 0.5), Vector2(cx + w * 0.5, cy - h * 0.5), Vector2(cx + w * 0.5, cy + h * 0.5), Vector2(cx - w * 0.5, cy + h * 0.5)]

static func _run_ring(profile: Array[Vector2], run: Dictionary, depth: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in profile: result.append(_point(run, point.x, point.y, depth))
	return result

static func _join_profile(buffer: Dictionary, a: Array, b: Array, profile: Array[Vector2], run: Dictionary, inner: bool) -> void:
	var axis: Vector2 = run.axis
	for edge in profile.size():
		var next: int = (edge + 1) % profile.size()
		var d: Vector2 = (profile[next] - profile[edge]).normalized()
		var normal: Vector3 = Vector3(axis.x * d.y, -d.x, axis.y * d.y) * (-1.0 if inner else 1.0)
		_quad(buffer, a[edge], a[next], b[next], b[edge], normal)

static func _profile_face(buffer: Dictionary, points: Array, profile: Array[Vector2], normal: Vector3) -> void:
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(PackedVector2Array(profile))
	for i in range(0, triangles.size(), 3):
		_tri(buffer, points[triangles[i]], points[triangles[i + 1]], points[triangles[i + 2]], normal)

static func _glass(buffer: Dictionary, hole: Dictionary, run: Dictionary) -> void:
	var profile: Array[Vector2] = _rectangle(float(hole.cx), float(hole.sill) + float(hole.height) * 0.5, float(hole.width) - GLASS_GAP * 2.0, float(hole.height) - GLASS_GAP * 2.0)
	var a: Array[Vector3] = _run_ring(profile, run, float(run.depth) * 0.5 - 0.01)
	var b: Array[Vector3] = _run_ring(profile, run, float(run.depth) * 0.5 + 0.01)
	var n2: Vector2 = run.outward
	var normal: Vector3 = Vector3(n2.x, 0.0, n2.y)
	_quad(buffer, a[0], a[1], a[2], a[3], normal)
	_quad(buffer, b[0], b[1], b[2], b[3], -normal)
	_join_profile(buffer, a, b, profile, run, false)

## 环形实体：外轮廓与内轮廓同点数，上下各一段倒角；用于勒脚这类不封住内部的整圈构件。
static func _ring_solid(buffer: Dictionary, outer: Array[Vector2], inner: Array[Vector2], bottom: float, top: float, bevel: float) -> void:
	if outer.size() != inner.size() or outer.size() < 3:
		return
	var b: float = minf(bevel, (top - bottom) * 0.35)
	# 倒角只收y方向：外轮廓已按墙壳圆弧采段，再对XZ做offset会把它miter化，墙角重新错开。
	var levels: Array[float] = [bottom, bottom + b, top - b, top]
	var outer_rings: Array = []
	for y in levels:
		outer_rings.append(_xz_ring(outer, y))
	var inner_bottom: Array[Vector3] = _xz_ring(inner, bottom)
	var inner_top: Array[Vector3] = _xz_ring(inner, top)
	for layer in range(outer_rings.size() - 1):
		var a: Array = outer_rings[layer]
		var c: Array = outer_rings[layer + 1]
		for edge in outer.size():
			var next: int = (edge + 1) % outer.size()
			var d: Vector2 = (outer[next] - outer[edge]).normalized()
			var normal: Vector3 = Vector3(d.y, -1.0 if layer == 0 else (1.0 if layer == 2 else 0.0), -d.x)
			_quad(buffer, a[edge], a[next], c[next], c[edge], normal)
	for edge in inner.size():
		var next: int = (edge + 1) % inner.size()
		var d: Vector2 = (inner[next] - inner[edge]).normalized()
		_quad(buffer, inner_bottom[edge], inner_bottom[next], inner_top[next], inner_top[edge], Vector3(-d.y, 0.0, d.x))
		_quad(buffer, outer_rings[3][edge], outer_rings[3][next], inner_top[next], inner_top[edge], Vector3.UP)
		_quad(buffer, inner_bottom[edge], inner_bottom[next], outer_rings[0][next], outer_rings[0][edge], Vector3.DOWN)

static func _opening_canopy(parts: Array, door: Dictionary, run: Dictionary, r: Dictionary, c: Dictionary, context: Dictionary) -> void:
	# 门头雨棚：贴墙挑出的平板 + 两根落地柱；柱脚落在场地 y=0，不生成悬挑假构件。
	# 两侧各超出门洞 CANOPY_EXTENSION；柱落在雨棚两端外侧，不能压在门洞净宽上挡门。
	var half: float = float(door.width) * 0.5 + CANOPY_EXTENSION
	# 正深度=向墙内：雨棚必须咬进墙体，不能从墙皮外面凭空起始留缝。
	var back: float = 0.06
	var front: float = back - CANOPY_PROJECTION
	var bottom: float = float(door.y1) + CANOPY_LIFT
	if bottom + CANOPY_THICKNESS > float(context.height):
		return
	var slab: Dictionary = _buffer()
	_solid(slab, _run_rect(run, float(door.cx), half, front, back), bottom, bottom + CANOPY_THICKNESS, CANOPY_BEVEL)
	_part(parts, slab, "canopy_front", "slab", 0, "front", r, c, context, CANOPY_BEVEL, false)
	for side in 2:
		var sign: float = -1.0 if side == 0 else 1.0
		# 柱中心在雨棚端部内 CANTILEVER_POST_MARGIN 处；务必使柱内表面落在门洞净边之外。
		var x: float = float(door.cx) + sign * (half - CANOPY_POST_BEVEL - CANOPY_POST * 0.5)
		var post: Dictionary = _buffer()
		var post_front: float = front + CANOPY_POST_EDGE
		_solid(post, _run_rect(run, x, CANOPY_POST * 0.5, post_front, post_front + CANOPY_POST), 0.0, bottom - 0.01, CANOPY_POST_BEVEL)
		_part(parts, post, "canopy_post_" + str(side), "frame", 0, "front", r, c, context, CANOPY_POST_BEVEL, false)

static func _run_rect(run: Dictionary, center_x: float, half_x: float, depth_a: float, depth_b: float) -> Array[Vector2]:
	var near_depth: float = minf(depth_a, depth_b)
	var far_depth: float = maxf(depth_a, depth_b)
	var result: Array[Vector2] = []
	for corner in [Vector2(center_x - half_x, near_depth), Vector2(center_x + half_x, near_depth), Vector2(center_x + half_x, far_depth), Vector2(center_x - half_x, far_depth)]:
		var point: Vector3 = _point(run, corner.x, 0.0, corner.y)
		result.append(Vector2(point.x, point.z))
	return _ccw(result)

## 立面沿不同朝向映射后可能整体镜像；统一成 XZ 逆时针，_solid 的实体法线才朝外。
static func _ccw(polygon: Array[Vector2]) -> Array[Vector2]:
	if _polygon_area(polygon) >= 0.0:
		return polygon
	var reversed: Array[Vector2] = []
	for index in range(polygon.size() - 1, -1, -1):
		reversed.append(polygon[index])
	return reversed

static func _solid(buffer: Dictionary, polygon: Array[Vector2], bottom: float, top: float, bevel: float) -> void:
	# 截面：底面→三段圆弧实体倒角→完整厚度外侧→三段圆弧→顶面。
	var rings: Array = []
	for step in 4:
		var angle: float = float(step) / 3.0 * PI * 0.5
		var inset: float = bevel * (1.0 - sin(angle))
		var y: float = bottom + bevel * (1.0 - cos(angle))
		rings.append(_xz_ring(_offset(polygon, inset), y))
	for step in 4:
		var angle: float = float(3 - step) / 3.0 * PI * 0.5
		var inset: float = bevel * (1.0 - sin(angle))
		var y: float = top - bevel * (1.0 - cos(angle))
		rings.append(_xz_ring(_offset(polygon, inset), y))
	_profile_face(buffer, rings[0], _offset(polygon, bevel), Vector3.DOWN)
	_profile_face(buffer, rings[-1], _offset(polygon, bevel), Vector3.UP)
	for layer in range(rings.size() - 1):
		var a: Array = rings[layer]
		var b: Array = rings[layer + 1]
		for edge in polygon.size():
			var next: int = (edge + 1) % polygon.size()
			var d: Vector2 = (polygon[next] - polygon[edge]).normalized()
			var normal: Vector3 = Vector3(d.y, -1.0 if layer < 3 else (1.0 if layer > 3 else 0.0), -d.x)
			_quad(buffer, a[edge], a[next], b[next], b[edge], normal)

static func _xz_ring(polygon: Array[Vector2], y: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in polygon: result.append(Vector3(point.x, y, point.y))
	return result

static func _buffer() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}

static func _quad(buffer: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, expected: Vector3) -> void:
	# 折叠的圆弧轮廓以有效三角封口，不能因另一半退化而整块丢弃。
	var first_degenerate: bool = MeshBuilder._degenerate_triangle(a, b, c)
	var second_degenerate: bool = MeshBuilder._degenerate_triangle(a, c, d)
	if first_degenerate or second_degenerate:
		if not first_degenerate:
			var first_normal: Vector3 = (b - a).cross(c - a).normalized()
			if first_normal.dot(expected) < 0.0: first_normal = -first_normal
			_tri(buffer, a, b, c, first_normal)
		if not second_degenerate:
			var second_normal: Vector3 = (c - a).cross(d - a).normalized()
			if second_normal.dot(expected) < 0.0: second_normal = -second_normal
			_tri(buffer, a, c, d, second_normal)
		return
	# 每个实体面按真实面法线；expected只负责CW朝向，绝不以平滑法线伪造倒角。
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.dot(expected) < 0.0: normal = -normal
	MeshBuilder._append_quad(buffer.v, buffer.n, buffer.uv, buffer.i, a, b, c, d, normal)

static func _tri(buffer: Dictionary, a: Vector3, b: Vector3, c: Vector3, expected: Vector3) -> void:
	MeshBuilder._append_triangle_normals(buffer.v, buffer.n, buffer.uv, buffer.i, a, b, c, expected, expected, expected)

static func _scale_at(y: float, context: Dictionary) -> float:
	return 1.0 - float(context.taper) * clampf(y / float(context.height), 0.0, 1.0)

static func _map(point: Vector3, context: Dictionary) -> Vector3:
	var scale: float = _scale_at(point.y, context)
	return Vector3(point.x * scale, point.y, point.z * scale)

static func _part(parts: Array, source: Dictionary, id: String, kind: String, floor: int, facade: String, r: Dictionary, catalog: Dictionary, context: Dictionary, bevel: float, collidable: bool) -> void:
	if not str(context.error).is_empty(): return
	if parts.size() >= MAX_PARTS:
		context.error = "连续外壳超过部件预算: " + str(MAX_PARTS)
		return
	var buffer: Dictionary = _conform(source)
	var audit: Dictionary = _topology(buffer)
	context.topology[id] = audit
	if not bool(audit.closed) or not bool(audit.oriented):
		context.error = "几何闭合/朝向审计未通过: " + id + " " + str(audit)
		return
	var vertices: PackedVector3Array = buffer.v
	var indices: PackedInt32Array = buffer.i
	context.triangles = int(context.triangles) + int(indices.size() / 3)
	if int(context.triangles) > MAX_TRIANGLES:
		context.error = "连续外壳超过三角面预算"
		return
	for i in vertices.size(): vertices[i] = _map(vertices[i], context)
	var bounds: AABB = AABB(vertices[0], Vector3.ZERO)
	for point in vertices: bounds = bounds.expand(point)
	var center: Vector3 = bounds.get_center()
	for i in vertices.size(): vertices[i] -= center
	var normals: PackedVector3Array = buffer.n
	MeshBuilder._rebuild_normals(vertices, normals, indices)
	var component: String = _component(r, kind, id)
	var definition: Dictionary = catalog.components.get(component, {})
	if definition.is_empty():
		context.error = "未知组件: " + component
		return
	# prefab也只生成同规格基线占位网格；实际整件替换由shell_generator拥有。
	var palette: String = str(definition.get("color", "cozy"))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = MeshBuilder._encode_palette_uv(buffer.uv, palette, float(context.aging))
	arrays[Mesh.ARRAY_TEX_UV2] = arrays[Mesh.ARRAY_TEX_UV]
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, MeshBuilder.material(palette, float(context.aging), context.cache))
	var local_bounds: AABB = mesh.get_aabb()
	parts.append({"id": id, "kind": kind, "floor": floor, "facade": facade, "component_id": component, "position": center, "size": local_bounds.size, "mesh": mesh, "collidable": collidable and bool(context.collidable), "bevel_width": bevel, "bounds_position": local_bounds.position, "bounds_size": local_bounds.size})

static func _key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x / WELD), roundi(point.y / WELD), roundi(point.z / WELD))

static func _line(a: Vector3, b: Vector3) -> String:
	var direction: Vector3 = (b - a).normalized()
	if direction.x < -EPS or (absf(direction.x) <= EPS and direction.y < -EPS) or (absf(direction.x) <= EPS and absf(direction.y) <= EPS and direction.z < 0.0): direction = -direction
	return str(_key(direction)) + ":" + str(_key(a.cross(direction)))

static func _conform(source: Dictionary) -> Dictionary:
	# 同一位置焊接，但保留硬法线和PaletteUV边界；拆分长边上的共线顶点以消除T接。
	var vertices: PackedVector3Array = source.v
	var indices: PackedInt32Array = source.i
	var canonical: Dictionary = {}
	for i in vertices.size():
		var key: Vector3i = _key(vertices[i])
		if canonical.has(key): vertices[i] = canonical[key]
		else: canonical[key] = vertices[i]
	var lines: Dictionary = {}
	for start in range(0, indices.size(), 3):
		for edge in 3:
			var a: Vector3 = vertices[indices[start + edge]]
			var b: Vector3 = vertices[indices[start + (edge + 1) % 3]]
			var key: String = _line(a, b)
			if not lines.has(key): lines[key] = {}
			lines[key][_key(a)] = a
			lines[key][_key(b)] = b
	var output: Dictionary = _buffer()
	for start in range(0, indices.size(), 3):
		var boundary: Array[Vector3] = []
		var center: Vector3 = Vector3.ZERO
		for edge in 3:
			var a: Vector3 = vertices[indices[start + edge]]
			var b: Vector3 = vertices[indices[start + (edge + 1) % 3]]
			center += a / 3.0
			var delta: Vector3 = b - a
			var length_sq: float = delta.length_squared()
			var points: Dictionary = {0.0: a}
			var candidates: Dictionary = lines[_line(a, b)]
			for candidate in candidates.values():
				var point: Vector3 = candidate
				var t: float = (point - a).dot(delta) / length_sq
				if t > EPS and t < 1.0 - EPS and point.distance_squared_to(a + delta * t) < WELD * WELD:
					points[t] = point
			var parameters: Array = points.keys()
			parameters.sort()
			for t in parameters: boundary.append(points[t])
		var a: Vector3 = vertices[indices[start]]
		var b: Vector3 = vertices[indices[start + 1]]
		var c: Vector3 = vertices[indices[start + 2]]
		var normal: Vector3 = -(b - a).cross(c - a).normalized()
		if boundary.size() == 3:
			_tri(output, a, b, c, normal)
		else:
			for edge in boundary.size():
				_tri(output, center, boundary[edge], boundary[(edge + 1) % boundary.size()], normal)
	return output

static func _topology(buffer: Dictionary) -> Dictionary:
	var vertices: PackedVector3Array = buffer.v
	var indices: PackedInt32Array = buffer.i
	var edges: Dictionary = {}
	for start in range(0, indices.size(), 3):
		for edge in 3:
			var a: Vector3i = _key(vertices[indices[start + edge]])
			var b: Vector3i = _key(vertices[indices[start + (edge + 1) % 3]])
			var sa: String = str(a)
			var sb: String = str(b)
			var forward: bool = sa < sb
			var key: String = sa + ":" + sb if forward else sb + ":" + sa
			var entry: Vector2i = edges.get(key, Vector2i.ZERO)
			entry.x += 1
			entry.y += 1 if forward else -1
			edges[key] = entry
	var open_edges: int = 0
	var nonmanifold: int = 0
	var reversed_edges: int = 0
	for raw in edges.values():
		var entry: Vector2i = raw
		if entry.x == 1: open_edges += 1
		elif entry.x != 2: nonmanifold += 1
		if entry.y != 0: reversed_edges += 1
	return {"closed": not indices.is_empty() and open_edges == 0 and nonmanifold == 0, "oriented": reversed_edges == 0, "boundary_edges": open_edges, "nonmanifold_edges": nonmanifold, "orientation_errors": reversed_edges, "triangles": indices.size() / 3}
