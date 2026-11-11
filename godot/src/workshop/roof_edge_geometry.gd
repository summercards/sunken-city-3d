@tool
extends RefCounted
## 屋顶边界附属几何：只生成变形前 worldXZ 顶点，提交与全局 taper 由 shell_geometry 统一处理。

const Config = preload("res://src/workshop/architecture_config.gd")
const MAX_PARTS: int = 2000
const MOUNT_CLEARANCE: float = 0.003
const SLAB_BEVEL: float = 0.028
const GAP_LENGTH_MARGIN: float = 0.15
const CORNER_END_CUT: float = 0.1
const CORNER_CLEARANCE: float = 0.15
const SEAM_CLEARANCE: float = 0.002
const UPPER_ADJACENCY: float = 0.2
const UPPER_TOUCH: float = 0.02
const EPS: float = 0.000001
const SAMPLE_COUNT: int = 24

static func append_parts(parts: Array, recipe: Dictionary, catalog: Dictionary, roof_surfaces: Array, context: Dictionary, geometry: Script) -> String:
	var quality: Dictionary = {
		"surfaces": [],
		"contacts": [],
		"global_taper": float(context.get("globaltaper", context.get("taper", 0.0))),
		"height": float(context.get("height", 0.0)),
		"limits": {
			"max_parts": MAX_PARTS,
			"mount_clearance": MOUNT_CLEARANCE,
			"slab_bevel": SLAB_BEVEL,
			"corner_end_cut": CORNER_END_CUT,
			"gap_length_margin": GAP_LENGTH_MARGIN,
			"corner_gap_clip": CORNER_CLEARANCE,
			"seam_clearance": SEAM_CLEARANCE,
			"upper_edge_samples": SAMPLE_COUNT,
			"source_unique_semantic_components": 5,
			"structural_claim": "仅几何闭合、接触与 taper 映射描述；不签署人群防护规范或建筑承载安全"
		}
	}
	context["roof_edge_quality"] = quality
	context["roof_edge_api_report"] = "append_parts完成；限额、接触和taper信息见context.roof_edge_quality"
	if parts.size() >= MAX_PARTS:
		return "屋顶边界部件预算已耗尽: " + str(MAX_PARTS)
	if roof_surfaces.is_empty():
		return ""

	var roof: Dictionary = Config.normalized(recipe.get("architecture", {})).get("roof", {})
	var default_mode: String = str(roof.get("mode", "none"))
	for raw_surface in roof_surfaces:
		if not raw_surface is Dictionary:
			return "屋顶边界surface必须是Dictionary"
		var surface: Dictionary = raw_surface
		var polygon: Array = surface.get("polygon", [])
		if not _usable_polygon(polygon):
			return "屋顶边界轮廓无效: " + str(surface.get("id", "unknown"))
		var surface_id: String = str(surface.get("id", "roof"))
		var roof_y: float = float(surface.get("y", context.get("height", 0.0)))
		var upper: Array = surface.get("upper_polygon", [])
		var has_upper: bool = upper.size() >= 3 and _usable_polygon(upper)
		var surface_quality: Dictionary = {"id": surface_id, "floor": int(surface.get("floor", -1)), "edges": [], "contacts": []}
		var edge_settings: Array = []
		var fragments: Array = []
		var whole_possible: bool = true
		var first_settings: Dictionary = {}
		for edge_index in polygon.size():
			var edge_id: String = "edge_" + str(edge_index)
			var settings: Dictionary = _surface_edge_settings(recipe, edge_id, surface_id)
			var gap_error: String = _validate_gap(polygon[edge_index], polygon[(edge_index + 1) % polygon.size()], settings)
			if not gap_error.is_empty():
				return surface_id + " " + edge_id + " gap无效: " + gap_error
			var height_error: String = _validate_railing_height(settings)
			if not height_error.is_empty() and str(settings.get("mode", "none")) in ["railing", "mixed"]:
				return surface_id + " " + edge_id + " railing高度无效: " + height_error
			if edge_index == 0:
				first_settings = settings.duplicate(true)
			else:
				if str(settings.get("mode", "none")) != str(first_settings.get("mode", "none")) or absf(float(settings.get("height", 0.0)) - float(first_settings.get("height", 0.0))) > EPS:
					whole_possible = false
			if float(settings.get("gap_width", 0.0)) > EPS:
				whole_possible = false
			edge_settings.append(settings)
			var a: Vector2 = polygon[edge_index]
			var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
			var edge_fragments: Array = _edge_fragments(a, b, settings, upper if has_upper else [], polygon)
			fragments.append(edge_fragments)
			if edge_fragments.size() != 1 or float(edge_fragments[0].raw_t0) > EPS or float(edge_fragments[0].raw_t1) < 1.0 - EPS:
				whole_possible = false
			surface_quality.edges.append({"edge_id": edge_id, "length": a.distance_to(b), "mode": str(settings.get("mode", "none")), "fragments": edge_fragments.size()})
			if has_upper and edge_fragments.size() == 0:
				surface_quality.contacts.append(edge_id + ":upper_wall_adjacent_suppressed")
			elif has_upper:
				surface_quality.contacts.append(edge_id + ":outer_edge_exposed_or_partially_suppressed")

		var surface_mode: String = default_mode
		# 退台板默认不自动生成围护：真实建筑里退台可以是裸板边，逐段截断的女儿墙会读成锯齿碎块。
		# 需要围护时给该 surface 的边写 edge_overrides 显式指定。
		if surface_id != "roof_main" and not _has_edge_override(recipe, surface_id):
			surface_mode = "none"
		if not first_settings.is_empty():
			surface_mode = str(first_settings.get("mode", default_mode)) if surface_id == "roof_main" or _has_edge_override(recipe, surface_id) else "none"
		if surface_mode == "none":
			for settings in edge_settings:
				if str(settings.get("mode", "none")) != "none":
					surface_mode = "edge_override"
					break
		if surface_mode == "none":
			quality.surfaces.append(surface_quality)
			continue

		var whole_mode: String = surface_mode if surface_mode in ["parapet", "railing", "mixed"] else default_mode
		var whole_height: float = float(first_settings.get("height", roof.get("height", 1.1)))
		var no_upper_suppression: bool = true
		if has_upper:
			for edge_index in polygon.size():
				if fragments[edge_index].size() != 1 or float(fragments[edge_index][0].raw_t0) > EPS or float(fragments[edge_index][0].raw_t1) < 1.0 - EPS:
					no_upper_suppression = false
					break
		if whole_possible and no_upper_suppression and whole_mode in ["parapet", "mixed"]:
			_append_whole_parapet(parts, recipe, catalog, context, geometry, surface_id, polygon, roof_y, first_settings, whole_mode, surface_quality)
			if parts.size() >= MAX_PARTS:
				return "屋顶边界部件预算已耗尽: " + str(MAX_PARTS)
			_append_whole_cap(parts, recipe, catalog, context, geometry, surface_id, polygon, roof_y, first_settings, whole_height, surface_quality)
			if whole_mode == "mixed":
				var railing_path: Array = _centerpath(polygon, first_settings, geometry)
				for edge_index in polygon.size():
					var mixed_a: Vector2 = railing_path[edge_index]
					var mixed_b: Vector2 = railing_path[(edge_index + 1) % railing_path.size()]
					var original_a: Vector2 = mixed_a
					var original_b: Vector2 = mixed_b
					mixed_a = _move_inward(original_a, original_b, CORNER_END_CUT)
					mixed_b = _move_inward(original_b, original_a, CORNER_END_CUT)
					_append_edge_railing(parts, recipe, catalog, context, geometry, surface_id, edge_index, 0, mixed_a, mixed_b, roof_y, first_settings, whole_mode, surface_quality)
					if parts.size() >= MAX_PARTS:
						return "屋顶边界部件预算已耗尽: " + str(MAX_PARTS)
		else:
			for edge_index in polygon.size():
				var a: Vector2 = polygon[edge_index]
				var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
				var settings: Dictionary = edge_settings[edge_index]
				var mode: String = str(settings.get("mode", "none"))
				if mode == "none":
					continue
				var edge_fragments: Array = fragments[edge_index]
				var edge_centerpath: Array = _centerpath(polygon, settings, geometry)
				var center_a: Vector2 = edge_centerpath[edge_index]
				var center_b: Vector2 = edge_centerpath[(edge_index + 1) % edge_centerpath.size()]
				for fragment_index in edge_fragments.size():
					var fragment: Dictionary = edge_fragments[fragment_index]
					var path_a: Vector2 = center_a.lerp(center_b, float(fragment.t0))
					var path_b: Vector2 = center_a.lerp(center_b, float(fragment.t1))
					if float(fragment.get("raw_t0", 0.0)) <= EPS:
						path_a = _move_inward(path_a, path_b, CORNER_END_CUT)
					if float(fragment.get("raw_t1", 1.0)) >= 1.0 - EPS:
						path_b = _move_inward(path_b, path_a, CORNER_END_CUT)
					var fa: Vector2 = path_a
					var fb: Vector2 = path_b
					var post_width: float = maxf(0.08, float(settings.get("bar_width", 0.05)) * 2.0)
					if float(fragment.get("raw_t0", 0.0)) <= EPS:
						fa = _move_inward(fa, fb, post_width * 0.5 + MOUNT_CLEARANCE)
					if float(fragment.get("raw_t1", 1.0)) >= 1.0 - EPS:
						fb = _move_inward(fb, fa, post_width * 0.5 + MOUNT_CLEARANCE)
					if path_a.distance_to(path_b) <= SEAM_CLEARANCE * 2.0:
						continue
					if mode in ["parapet", "mixed"]:
						_append_edge_parapet(parts, recipe, catalog, context, geometry, surface_id, edge_index, fragment_index, path_a, path_b, roof_y, settings, mode, surface_quality)
						_append_edge_cap(parts, recipe, catalog, context, geometry, surface_id, edge_index, fragment_index, path_a, path_b, roof_y, settings, mode, surface_quality)
					if mode in ["railing", "mixed"] and fa.distance_to(fb) > SEAM_CLEARANCE * 2.0:
						_append_edge_railing(parts, recipe, catalog, context, geometry, surface_id, edge_index, fragment_index, fa, fb, roof_y, settings, mode, surface_quality)
					if parts.size() >= MAX_PARTS:
						return "屋顶边界部件预算已耗尽: " + str(MAX_PARTS)
		quality.surfaces.append(surface_quality)

	# 顶层contacts是各surface contacts的并集：编辑器与文档读同一处，不要求逐surface遍历。
	for raw_surface_quality in quality.surfaces:
		for contact in (raw_surface_quality as Dictionary).get("contacts", []):
			quality.contacts.append(str(contact))
	quality["semantic_components"] = _semantic_components(quality.surfaces)
	quality["part_count_after_append"] = parts.size()
	return ""

## surface 是否有显式边覆盖（任何 edge_<i> 键）；用于决定退台是否生成围护。
static func _has_edge_override(recipe: Dictionary, surface_id: String) -> bool:
	var roof: Dictionary = Config.normalized(recipe.get("architecture", {})).get("roof", {})
	var overrides: Dictionary = roof.get("edge_overrides", {})
	if overrides.is_empty():
		return false
	for key in overrides:
		if str(key).begins_with(surface_id + ".") or str(key).begins_with(surface_id + "_"):
			return true
	return false

static func _append_whole_parapet(parts: Array, recipe: Dictionary, catalog: Dictionary, context: Dictionary, geometry: Script, surface_id: String, polygon: Array, roof_y: float, settings: Dictionary, mode: String, quality: Dictionary) -> void:
	var thickness: float = float(settings.get("thickness", 0.3))
	var height: float = float(settings.get("height", 1.1))
	var inset: float = _required_center_inset(settings)
	if mode == "mixed": height *= 0.45
	var centerpath: Array = geometry._offset(polygon, inset)
	var outer: Array = geometry._offset(centerpath, -thickness * 0.5)
	var inner: Array = geometry._offset(centerpath, thickness * 0.5)
	var buffer: Dictionary = geometry._buffer()
	_ring(buffer, outer, inner, roof_y + MOUNT_CLEARANCE, roof_y + height, minf(0.04, thickness * 0.24), geometry)
	var parapet_id: String = "parapet_main" if surface_id == "roof_main" else "parapet_" + surface_id
	geometry._part(parts, buffer, parapet_id, "wall", int(quality.floor), "roof", recipe, catalog, context, 0.04, true)
	quality.contacts.append(parapet_id + ":centerpath_inset=" + str(inset) + ";closed_miter_ring")

static func _append_whole_cap(parts: Array, recipe: Dictionary, catalog: Dictionary, context: Dictionary, geometry: Script, surface_id: String, polygon: Array, roof_y: float, settings: Dictionary, height: float, quality: Dictionary) -> void:
	var wall_thickness: float = float(settings.get("thickness", 0.3))
	var overhang: float = float(settings.get("cap_overhang", 0.04))
	var cap_thickness: float = float(settings.get("cap_thickness", 0.12))
	var parapet_height: float = height * (0.45 if str(settings.get("mode", "")) == "mixed" else 1.0)
	var centerpath: Array = geometry._offset(polygon, _required_center_inset(settings))
	var width: float = wall_thickness + overhang * 2.0
	var outer: Array = geometry._offset(centerpath, -width * 0.5)
	var inner: Array = geometry._offset(centerpath, width * 0.5)
	var buffer: Dictionary = geometry._buffer()
	_ring(buffer, outer, inner, roof_y + parapet_height + MOUNT_CLEARANCE, roof_y + parapet_height + MOUNT_CLEARANCE + cap_thickness, minf(0.02, cap_thickness * 0.24), geometry)
	var cap_id: String = "roofcap_main" if surface_id == "roof_main" else "roofcap_" + surface_id
	geometry._part(parts, buffer, cap_id, "slab", int(quality.floor), "roof", recipe, catalog, context, 0.02, true)
	quality.contacts.append(cap_id + ":centerpath_inset=" + str(_required_center_inset(settings)) + ";independent_miter_ring;overhang=" + str(overhang))

static func _append_edge_parapet(parts: Array, recipe: Dictionary, catalog: Dictionary, context: Dictionary, geometry: Script, surface_id: String, edge_index: int, fragment_index: int, a: Vector2, b: Vector2, roof_y: float, settings: Dictionary, mode: String, quality: Dictionary) -> void:
	var total_height: float = float(settings.get("height", 1.1))
	var parapet_height: float = total_height * (0.45 if mode == "mixed" else 1.0)
	var thickness: float = float(settings.get("thickness", 0.3))
	var buffer: Dictionary = geometry._buffer()
	_append_local_solid(buffer, a, b, thickness, roof_y + MOUNT_CLEARANCE, roof_y + parapet_height, geometry, 0.04)
	geometry._part(parts, buffer, "parapet_" + surface_id + "_" + str(edge_index) + "_" + str(fragment_index), "wall", int(quality.floor), "roof", recipe, catalog, context, 0.04, true)
	quality.contacts.append("parapet_edge_" + str(edge_index) + ":closed_miter_strip")

static func _append_edge_cap(parts: Array, recipe: Dictionary, catalog: Dictionary, context: Dictionary, geometry: Script, surface_id: String, edge_index: int, fragment_index: int, a: Vector2, b: Vector2, roof_y: float, settings: Dictionary, mode: String, quality: Dictionary) -> void:
	var total_height: float = float(settings.get("height", 1.1))
	var parapet_height: float = total_height * (0.45 if mode == "mixed" else 1.0)
	var cap_thickness: float = float(settings.get("cap_thickness", 0.12))
	var width: float = float(settings.get("thickness", 0.3)) + float(settings.get("cap_overhang", 0.04)) * 2.0
	var buffer: Dictionary = geometry._buffer()
	_append_local_solid(buffer, a, b, width, roof_y + parapet_height + MOUNT_CLEARANCE, roof_y + parapet_height + MOUNT_CLEARANCE + cap_thickness, geometry, minf(0.02, cap_thickness * 0.24))
	geometry._part(parts, buffer, "roofcap_" + surface_id + "_" + str(edge_index) + "_" + str(fragment_index), "slab", int(quality.floor), "roof", recipe, catalog, context, 0.02, true)

static func _append_edge_railing(parts: Array, recipe: Dictionary, catalog: Dictionary, context: Dictionary, geometry: Script, surface_id: String, edge_index: int, fragment_index: int, a: Vector2, b: Vector2, roof_y: float, settings: Dictionary, mode: String, quality: Dictionary) -> void:
	var length: float = a.distance_to(b)
	if length <= EPS:
		return
	var axis: Vector2 = (b - a).normalized()
	var outward: Vector2 = Vector2(axis.y, -axis.x)
	var bar: float = float(settings.get("bar_width", 0.05))
	var post_width: float = maxf(0.08, bar * 2.0)
	var height: float = float(settings.get("height", 1.1))
	var lower: float = roof_y + MOUNT_CLEARANCE
	if mode == "mixed":
		var parapet_height: float = height * 0.45
		lower = roof_y + parapet_height + MOUNT_CLEARANCE + float(settings.get("cap_thickness", 0.12)) + MOUNT_CLEARANCE
	var upper: float = roof_y + height
	var rail_low_bottom: float = lower
	var rail_low_top: float = lower + bar
	var rail_top_bottom: float = upper - bar
	var rail_top_top: float = upper
	if rail_low_top <= rail_low_bottom or rail_top_bottom <= rail_low_top + MOUNT_CLEARANCE:
		return
	var buffer: Dictionary = geometry._buffer()
	var post_spacing: float = float(settings.get("post_spacing", 1.5))
	var post_count: int = maxi(1, ceili(length / post_spacing))
	var post_points: Array = []
	for index in range(post_count + 1):
		var t: float = float(index) / float(post_count)
		var point: Vector2 = a.lerp(b, t)
		post_points.append(point)
		_append_vertical_box(buffer, point, post_width, lower, upper, geometry, minf(0.04, post_width * 0.24))
	var clearance: float = MOUNT_CLEARANCE
	for index in post_count:
		var p0: Vector2 = post_points[index]
		var p1: Vector2 = post_points[index + 1]
		var span: float = p0.distance_to(p1) - post_width - clearance * 2.0
		if span <= bar * 2.0:
			continue
		var center: Vector2 = (p0 + p1) * 0.5
		_append_oriented_box(buffer, center, axis, outward, span, bar, rail_low_bottom, rail_low_top, geometry, minf(0.03, bar * 0.24))
		_append_oriented_box(buffer, center, axis, outward, span, bar, rail_top_bottom, rail_top_top, geometry, minf(0.03, bar * 0.24))
	var picket_spacing: float = float(settings.get("rail_spacing", 0.22))
	var picket_bottom: float = rail_low_top + clearance
	var picket_top: float = rail_top_bottom - clearance
	if picket_top > picket_bottom + bar:
		for index in post_count:
			var p0: Vector2 = post_points[index]
			var p1: Vector2 = post_points[index + 1]
			var interval: float = p0.distance_to(p1) - post_width - clearance * 2.0 - bar
			var count: int = maxi(0, ceili(interval / picket_spacing) - 1)
			if count <= 0:
				continue
			var safe_start: Vector2 = p0 + axis * (post_width * 0.5 + clearance + bar * 0.5)
			var safe_end: Vector2 = p1 - axis * (post_width * 0.5 + clearance + bar * 0.5)
			for picket_index in range(1, count + 1):
				var point: Vector2 = safe_start.lerp(safe_end, float(picket_index) / float(count + 1))
				_append_vertical_box(buffer, point, bar, picket_bottom, picket_top, geometry, minf(0.025, bar * 0.24))
	geometry._part(parts, buffer, "railing_" + surface_id + "_" + str(edge_index) + "_" + str(fragment_index), "pillar", int(quality.floor), "roof", recipe, catalog, context, minf(0.04, post_width * 0.24), true)
	quality.contacts.append("railing_edge_" + str(edge_index) + ":posts_" + str(post_count + 1) + ";pickets_safe_interval;rails_clearance=0.003")

static func _surface_edge_settings(recipe: Dictionary, edge_id: String, surface_id: String) -> Dictionary:
	var architecture: Dictionary = Config.normalized(recipe.get("architecture", {}))
	var roof: Dictionary = architecture.get("roof", {}).duplicate(true)
	var overrides: Dictionary = roof.get("edge_overrides", {}).duplicate(true)
	roof.erase("edge_overrides")
	roof["gap_center"] = 0.5
	roof["gap_width"] = 0.0
	if surface_id == "roof_main":
		roof.merge(overrides.get(edge_id, {}), true)
	return roof

static func _required_center_inset(settings: Dictionary) -> float:
	return float(settings.get("thickness", 0.3)) * 0.5 + float(settings.get("cap_overhang", 0.04)) + SLAB_BEVEL + MOUNT_CLEARANCE

static func _centerpath(polygon: Array, settings: Dictionary, geometry: Script) -> Array:
	return geometry._offset(polygon, _required_center_inset(settings))

static func _validate_gap(a: Vector2, b: Vector2, settings: Dictionary) -> String:
	var length: float = a.distance_to(b)
	if length <= EPS:
		return "edge长度无效"
	var gap_width: float = float(settings.get("gap_width", 0.0))
	var center: float = float(settings.get("gap_center", 0.5))
	if gap_width < -EPS:
		return "gap_width不能为负"
	if gap_width <= EPS:
		return ""
	if center < 0.0 or center > 1.0:
		return "gap_center越界"
	var margin_ratio: float = GAP_LENGTH_MARGIN / length
	var half: float = gap_width / length * 0.5
	if gap_width > length - GAP_LENGTH_MARGIN * 2.0 + EPS:
		return "gap_width超过边长扣除两端lengthmargin.15"
	if center - half < margin_ratio - EPS or center + half > 1.0 - margin_ratio + EPS:
		return "gap跨越边端lengthmargin.15，拒绝而非clip"
	return ""

static func _validate_railing_height(settings: Dictionary) -> String:
	var height: float = float(settings.get("height", 1.1))
	var mixed: bool = str(settings.get("mode", "none")) == "mixed"
	var lower: float = MOUNT_CLEARANCE
	if mixed:
		lower += height * 0.45 + float(settings.get("cap_thickness", 0.12)) + MOUNT_CLEARANCE
	if height <= lower + float(settings.get("bar_width", 0.05)) * 2.0 + MOUNT_CLEARANCE:
		return "mixed下栏杆高度不足"
	return ""

static func _move_inward(point: Vector2, toward: Vector2, distance: float) -> Vector2:
	var delta: Vector2 = toward - point
	if delta.length() <= EPS:
		return point
	return point + delta.normalized() * minf(distance, delta.length() * 0.45)

static func _edge_fragments(a: Vector2, b: Vector2, settings: Dictionary, upper: Array, surface_polygon: Array) -> Array:
	var result: Array = []
	var length: float = a.distance_to(b)
	if length <= EPS:
		return result
	var active: Array = []
	for sample in SAMPLE_COUNT:
		var t0: float = float(sample) / float(SAMPLE_COUNT)
		var t1: float = float(sample + 1) / float(SAMPLE_COUNT)
		var point: Vector2 = a.lerp(b, (t0 + t1) * 0.5)
		var exposed: bool = true
		if upper.size() >= 3 and _upper_touches_edge(a, b, upper):
			exposed = not _upper_occupies(point, upper, UPPER_ADJACENCY)
		active.append({"t0": t0, "t1": t1, "exposed": exposed})
	var runs: Array = []
	var start: float = -1.0
	for entry in active:
		if bool(entry.exposed) and start < 0.0:
			start = float(entry.t0)
		if (not bool(entry.exposed) or float(entry.t1) >= 1.0 - EPS) and start >= 0.0:
			var finish: float = float(entry.t0) if not bool(entry.exposed) else float(entry.t1)
			if finish > start + EPS:
				runs.append({"t0": start, "t1": finish})
			start = -1.0
	if runs.is_empty() and upper.size() < 3:
		runs.append({"t0": 0.0, "t1": 1.0})
	var gap_width: float = maxf(0.0, float(settings.get("gap_width", 0.0)))
	if gap_width > EPS:
		var center: float = float(settings.get("gap_center", 0.5))
		var half: float = gap_width / length * 0.5
		var gap_start: float = center - half
		var gap_end: float = center + half
		if gap_end > gap_start + EPS:
			var clipped: Array = []
			for run in runs:
				if float(run.t1) <= gap_start + EPS or float(run.t0) >= gap_end - EPS:
					clipped.append(run)
					continue
				if float(run.t0) < gap_start - EPS:
					clipped.append({"t0": float(run.t0), "t1": gap_start})
				if float(run.t1) > gap_end + EPS:
					clipped.append({"t0": gap_end, "t1": float(run.t1)})
			runs = clipped
	for run in runs:
		var t0: float = float(run.t0)
		var t1: float = float(run.t1)
		if t0 <= EPS:
			t0 = minf(1.0, SEAM_CLEARANCE / length)
		if t1 >= 1.0 - EPS:
			t1 = maxf(0.0, 1.0 - SEAM_CLEARANCE / length)
		if t1 > t0 + EPS:
			result.append({"t0": t0, "t1": t1, "raw_t0": float(run.t0), "raw_t1": float(run.t1)})
	return result

static func _upper_touches_edge(a: Vector2, b: Vector2, upper: Array) -> bool:
	for index in upper.size():
		var c: Vector2 = upper[index]
		var d: Vector2 = upper[(index + 1) % upper.size()]
		if _segment_distance(a, b, c, d) <= UPPER_TOUCH:
			return true
	return false

static func _upper_occupies(point: Vector2, upper: Array, distance: float) -> bool:
	if Geometry2D.is_point_in_polygon(point, PackedVector2Array(upper)):
		return true
	var nearest: float = INF
	for index in upper.size():
		nearest = minf(nearest, _point_segment_distance(point, upper[index], upper[(index + 1) % upper.size()]))
	return nearest < distance

static func _append_local_solid(buffer: Dictionary, a: Vector2, b: Vector2, width: float, bottom: float, top: float, geometry: Script, bevel: float) -> void:
	var length: float = a.distance_to(b)
	if length <= EPS or top <= bottom + EPS:
		return
	var axis: Vector2 = (b - a).normalized()
	var outward: Vector2 = Vector2(axis.y, -axis.x)
	var center: Vector2 = (a + b) * 0.5
	_append_oriented_box(buffer, center, axis, outward, length, width, bottom, top, geometry, bevel)

static func _append_oriented_box(buffer: Dictionary, center: Vector2, axis: Vector2, outward: Vector2, length: float, width: float, bottom: float, top: float, geometry: Script, bevel: float) -> void:
	var local_polygon: Array[Vector2] = [Vector2(-length * 0.5, -width * 0.5), Vector2(length * 0.5, -width * 0.5), Vector2(length * 0.5, width * 0.5), Vector2(-length * 0.5, width * 0.5)]
	var local: Dictionary = geometry._buffer()
	geometry._solid(local, local_polygon, bottom, top, bevel)
	for index in local.v.size():
		var point: Vector3 = local.v[index]
		var xz: Vector2 = center + axis * point.x + outward * point.z
		local.v[index] = Vector3(xz.x, point.y, xz.y)
	buffer.v.append_array(local.v)
	buffer.n.append_array(local.n)
	buffer.uv.append_array(local.uv)
	var base: int = buffer.v.size() - local.v.size()
	for index in local.i:
		buffer.i.append(base + int(index))

static func _append_vertical_box(buffer: Dictionary, center: Vector2, width: float, bottom: float, top: float, geometry: Script, bevel: float) -> void:
	var half: float = width * 0.5
	var polygon: Array[Vector2] = [center + Vector2(-half, -half), center + Vector2(half, -half), center + Vector2(half, half), center + Vector2(-half, half)]
	var local: Dictionary = geometry._buffer()
	geometry._solid(local, polygon, bottom, top, bevel)
	buffer.v.append_array(local.v)
	buffer.n.append_array(local.n)
	buffer.uv.append_array(local.uv)
	var base: int = buffer.v.size() - local.v.size()
	for index in local.i:
		buffer.i.append(base + int(index))

static func _ring(buffer: Dictionary, outer: Array, inner: Array, bottom: float, top: float, bevel: float, geometry: Script) -> void:
	if outer.size() < 3 or outer.size() != inner.size() or top <= bottom + EPS:
		return
	var b: float = minf(bevel, (top - bottom) * 0.24)
	var outer_layers: Array = [geometry._offset(outer, b), outer, outer, geometry._offset(outer, b)]
	var inner_layers: Array = [geometry._offset(inner, -b), inner, inner, geometry._offset(inner, -b)]
	var ys: Array = [bottom, bottom + b, top - b, top]
	for edge in outer.size():
		var next: int = (edge + 1) % outer.size()
		geometry._quad(buffer, _v(outer_layers[0][edge], ys[0]), _v(outer_layers[0][next], ys[0]), _v(inner_layers[0][next], ys[0]), _v(inner_layers[0][edge], ys[0]), Vector3.DOWN)
		geometry._quad(buffer, _v(outer_layers[3][edge], ys[3]), _v(inner_layers[3][edge], ys[3]), _v(inner_layers[3][next], ys[3]), _v(outer_layers[3][next], ys[3]), Vector3.UP)
		for layer in range(3):
			var outward: Vector3 = Vector3((outer[next] - outer[edge]).y, 0.0, -(outer[next] - outer[edge]).x).normalized()
			geometry._quad(buffer, _v(outer_layers[layer][edge], ys[layer]), _v(outer_layers[layer][next], ys[layer]), _v(outer_layers[layer + 1][next], ys[layer + 1]), _v(outer_layers[layer + 1][edge], ys[layer + 1]), outward)
			geometry._quad(buffer, _v(inner_layers[layer][next], ys[layer]), _v(inner_layers[layer][edge], ys[layer]), _v(inner_layers[layer + 1][edge], ys[layer + 1]), _v(inner_layers[layer + 1][next], ys[layer + 1]), -outward)

static func _v(point: Vector2, y: float) -> Vector3:
	return Vector3(point.x, y, point.y)

static func _usable_polygon(polygon: Array) -> bool:
	if polygon.size() < 3:
		return false
	var area: float = 0.0
	for index in polygon.size():
		if not polygon[index] is Vector2:
			return false
		area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return area > EPS

static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta: Vector2 = b - a
	var length_sq: float = delta.length_squared()
	if length_sq <= EPS:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(delta) / length_sq, 0.0, 1.0)
	return point.distance_to(a + delta * t)

static func _segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	return minf(minf(_point_segment_distance(a, c, d), _point_segment_distance(b, c, d)), minf(_point_segment_distance(c, a, b), _point_segment_distance(d, a, b)))

static func _semantic_components(surfaces: Array) -> Array:
	var result: Array = []
	for surface in surfaces:
		for edge in surface.get("edges", []):
			var mode: String = str(edge.get("mode", "none"))
			if mode in ["parapet", "mixed"] and not result.has("parapet"): result.append("parapet")
			if mode in ["parapet", "mixed"] and not result.has("cap"): result.append("cap")
			if mode in ["railing", "mixed"]:
				if not result.has("post"): result.append("post")
				if not result.has("rail"): result.append("rail")
				if not result.has("picket"): result.append("picket")
	return result
