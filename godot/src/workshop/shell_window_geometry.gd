@tool
extends RefCounted
## 只构造变形前world顶点；局部原点、全局taper及拓扑审计统一由shell_geometry处理。

const GAP: float = 0.002
const CLEARANCE: float = 0.003
const EPS: float = 0.000001

static func validate(settings: Dictionary, wall_depth: float) -> String:
	var reason: String = preload("res://src/workshop/architecture_config.gd")._validate_window(settings, "合成窗配置")
	if not reason.is_empty(): return reason
	var profile: float = float(settings.frame_width)
	var depth: float = float(settings.frame_depth)
	var recess: float = float(settings.recess)
	# 框可从真实净洞向外或向室内突出，但必须与返回面安全区保持实体深度交集。
	# 不改写 recess 或 depth；厚框不再被墙厚本身封顶。
	var limits: Vector2 = recess_limits(depth, wall_depth)
	if recess < limits.x - EPS or recess > limits.y + EPS:
		return "窗框脱离墙洞：当前框深%.3fm、墙厚%.3fm允许recess %.3f..%.3fm；可调退入或框深，不自动移位" % [depth, wall_depth, limits.x, limits.y]
	var available_depth: float = depth - GAP * 2.0 if str(settings.type) != "fixed" else depth
	if float(settings.glass_thickness) + GAP * 2.0 > available_depth:
		return "玻璃厚度与两侧装配间隙超出窗框/窗扇深度"
	var sash_profile: float = profile * 0.65 if str(settings.type) != "fixed" else 0.0
	if minf(float(settings.width), float(settings.height)) <= sash_profile * 2.0 + GAP * 4.0:
		return "净孔不足以容纳窗扇闭合环及玻璃装配间隙"
	if bool(settings.sill_enabled) and float(settings.sill_projection) <= CLEARANCE:
		return "窗沿外挑必须大于外墙装配间隙"
	return ""

static func recess_limits(depth: float, wall_depth: float) -> Vector2:
	var inset: float = 0.02 + CLEARANCE
	return Vector2(inset + CLEARANCE - depth * 0.5, wall_depth - inset - CLEARANCE + depth * 0.5)

static func _sash_hole(hole: Dictionary) -> Dictionary:
	var result: Dictionary = hole.duplicate(true)
	var settings: Dictionary = hole.settings.duplicate(true)
	var sash_profile: float = float(settings.frame_width) * 0.65
	result.width = float(hole.width) - GAP * 2.0 - sash_profile * 2.0
	result.height = float(hole.height) - GAP * 2.0 - sash_profile * 2.0
	result.sill = float(hole.sill) + GAP + sash_profile
	settings.frame_width = sash_profile
	# 扇体在固定框厚度内留出前后装配间隙，玻璃仍保留实体厚度。
	settings.frame_depth = float(settings.frame_depth) - GAP * 2.0
	result.settings = settings
	return result

static func _hinge(hole: Dictionary, run: Dictionary) -> Dictionary:
	var settings: Dictionary = hole.settings
	var type: String = str(settings.type)
	var pivot_x: float = float(hole.cx)
	var pivot_y: float = float(hole.sill)
	var axis: Vector3 = Vector3.UP
	var sign_angle: float = 1.0
	if type == "awning":
		pivot_y += float(hole.height)
		var run_axis: Vector2 = run.axis
		axis = Vector3(run_axis.x, 0.0, run_axis.y)
		sign_angle = 1.0
	elif type == "casement_right":
		pivot_x += float(hole.width) * 0.5
		sign_angle = -1.0
	else:
		pivot_x -= float(hole.width) * 0.5
	var start: Vector2 = run.start
	var along: Vector2 = run.axis
	var outward: Vector2 = run.outward
	var xz: Vector2 = start + along * pivot_x - outward * float(run.depth) * 0.5
	return {"pivot": Vector3(xz.x, pivot_y, xz.y), "axis": axis, "angle": deg_to_rad(float(settings.open_angle)) * sign_angle}

static func _rotate_point(point: Vector3, hinge: Dictionary, fraction: float = 1.0) -> Vector3:
	var pivot: Vector3 = hinge.pivot
	var axis: Vector3 = hinge.axis
	return pivot + (point - pivot).rotated(axis, float(hinge.angle) * fraction)

static func _rotate(buffer: Dictionary, hinge: Dictionary) -> void:
	var vertices: PackedVector3Array = buffer.v
	for i in vertices.size(): vertices[i] = _rotate_point(vertices[i], hinge)
	buffer.v = vertices

static func _envelope(hole: Dictionary, run: Dictionary) -> Dictionary:
	var settings: Dictionary = hole.settings
	var moving: bool = str(settings.type) != "fixed"
	var hinge: Dictionary = _hinge(hole, run)
	var x0: float = float(hole.cx) - float(hole.width) * 0.5 + GAP
	var x1: float = float(hole.cx) + float(hole.width) * 0.5 - GAP
	var y0: float = float(hole.sill) + GAP
	var y1: float = float(hole.sill) + float(hole.height) - GAP
	var half_depth: float = (float(settings.frame_depth) - GAP * 2.0) * 0.5
	var recess: float = float(settings.recess)
	var start: Vector2 = run.start
	var along: Vector2 = run.axis
	var outward: Vector2 = run.outward
	var minimum: Vector3 = Vector3(INF, INF, INF)
	var maximum: Vector3 = Vector3(-INF, -INF, -INF)
	var slope: float = float(hole.get("pull", 0.0)) / (float(hole.y1) - float(hole.y0))
	var side_min: float = INF
	var side_max: float = -INF
	# 每个角点坐标及梯形洞左右半平面均为a*cos(t)+b*sin(t)+c；解析极值而非采样漏检。
	for y in [y0, y1]:
		var pull: float = 0.0 if float(y) == y0 else float(hole.get("pull", 0.0))
		for x in [x0 + pull, x1 - pull]:
			for depth in [recess - half_depth, recess + half_depth]:
				var xz: Vector2 = start + along * float(x) - outward * float(depth)
				var point: Vector3 = Vector3(xz.x, float(y), xz.y)
				var local: Vector3 = Vector3(float(x), float(y), float(depth))
				if not moving:
					minimum = minimum.min(local); maximum = maximum.max(local)
					side_min = minf(side_min, local.x - slope * (local.y - float(hole.y0)))
					side_max = maxf(side_max, local.x + slope * (local.y - float(hole.y0)))
					continue
				var pivot: Vector3 = hinge.pivot
				var axis: Vector3 = hinge.axis
				var delta: Vector3 = point - pivot
				var constant: Vector3 = pivot + axis * axis.dot(delta)
				var cosine: Vector3 = delta - axis * axis.dot(delta)
				var sine: Vector3 = axis.cross(delta)
				var c: Vector3 = Vector3((Vector2(constant.x, constant.z) - start).dot(along), constant.y, -(Vector2(constant.x, constant.z) - start).dot(outward))
				var a: Vector3 = Vector3(Vector2(cosine.x, cosine.z).dot(along), cosine.y, -Vector2(cosine.x, cosine.z).dot(outward))
				var b: Vector3 = Vector3(Vector2(sine.x, sine.z).dot(along), sine.y, -Vector2(sine.x, sine.z).dot(outward))
				var low: float = minf(0.0, float(hinge.angle))
				var high: float = maxf(0.0, float(hinge.angle))
				for coordinate in 3:
					var candidates: Array[float] = [low, high]
					var critical: float = atan2(b[coordinate], a[coordinate])
					for turn in range(-2, 3):
						var angle: float = critical + float(turn) * PI
						if angle > low and angle < high: candidates.append(angle)
					for angle in candidates:
						var value: float = c[coordinate] + a[coordinate] * cos(angle) + b[coordinate] * sin(angle)
						minimum[coordinate] = minf(minimum[coordinate], value)
						maximum[coordinate] = maxf(maximum[coordinate], value)
				for side in [-1.0, 1.0]:
					var side_a: float = a.x + float(side) * slope * a.y
					var side_b: float = b.x + float(side) * slope * b.y
					var side_c: float = c.x + float(side) * slope * (c.y - float(hole.y0))
					var angles: Array[float] = [low, high]
					var critical: float = atan2(side_b, side_a)
					for turn in range(-2, 3):
						var angle: float = critical + float(turn) * PI
						if angle > low and angle < high: angles.append(angle)
					for angle in angles:
						var value: float = side_c + side_a * cos(angle) + side_b * sin(angle)
						if side < 0.0: side_min = minf(side_min, value)
						else: side_max = maxf(side_max, value)
	return {"min": minimum, "max": maximum, "side_min": side_min, "side_max": side_max}

static func validate_bay(hole: Dictionary, run: Dictionary, bay_start: float, bay_end: float, base: float, top: float) -> String:
	var settings: Dictionary = hole.settings
	var envelope: Dictionary = _envelope(hole, run)
	var low: Vector3 = envelope.min
	var high: Vector3 = envelope.max
	# 上宽下窄的洞口上沿会超出下沿矩形，开间校验要按最大外廓留边。
	var reach: float = maxf(0.0, -float(hole.get("pull", 0.0)))
	if low.x < bay_start + CLEARANCE or high.x > bay_end - CLEARANCE or low.y < base + CLEARANCE or high.y > top - CLEARANCE:
		return "窗扇完整开合包络超出本开间或楼板安全边界，不能与相邻洞口互穿"
	# 法向突出不等于穿墙：只要完整扫掠仍在真实贯穿洞口的横向/竖向范围内即可。
	if float(envelope.side_min) < float(hole.x0) + CLEARANCE or float(envelope.side_max) > float(hole.x1) - CLEARANCE or low.y < float(hole.y0) + CLEARANCE or high.y > float(hole.y1) - CLEARANCE:
		return "窗扇厚度的完整开合包络超出墙体净洞安全区，存在穿墙风险"
	var frame_low: Vector3 = Vector3(float(hole.x0) - reach + CLEARANCE, float(hole.sill) - float(settings.frame_width), float(settings.recess) - float(settings.frame_depth) * 0.5)
	var frame_high: Vector3 = Vector3(float(hole.x1) + reach - CLEARANCE, float(hole.sill) + float(hole.height) + float(settings.frame_width), float(settings.recess) + float(settings.frame_depth) * 0.5)
	if frame_low.x < bay_start + CLEARANCE or frame_high.x > bay_end - CLEARANCE or frame_low.y < base + CLEARANCE or frame_high.y > top - CLEARANCE:
		return "窗框外廓超出开间或楼板；请增大开间/层高，不能静默缩窗"
	var assembly_low: Vector3 = low.min(frame_low)
	var assembly_high: Vector3 = high.max(frame_high)
	if bool(settings.sill_enabled):
		var half: float = float(hole.width) * 0.5 + float(settings.frame_width) + float(settings.sill_extension)
		if float(hole.cx) - half < bay_start + CLEARANCE or float(hole.cx) + half > bay_end - CLEARANCE:
			return "窗沿超出开间，不能与相邻窗沿交叠"
		var sill_top: float = float(hole.sill) - float(settings.frame_width) - CLEARANCE
		if sill_top - float(settings.sill_thickness) <= base + CLEARANCE: return "窗沿厚度与楼板冲突"
		if low.y < sill_top + CLEARANCE: return "开合包络与窗沿冲突"
		assembly_low = assembly_low.min(Vector3(float(hole.cx) - half, sill_top - float(settings.sill_thickness), -float(settings.sill_projection)))
		assembly_high = assembly_high.max(Vector3(float(hole.cx) + half, sill_top, -CLEARANCE))
	hole["sweep_envelope"] = envelope
	hole["assembly_envelope"] = {"min": assembly_low, "max": assembly_high}
	return ""

static func register_envelope(envelopes: Array, hole: Dictionary, run: Dictionary, id: String, floor: int) -> String:
	var local: Dictionary = hole.get("assembly_envelope", hole.sweep_envelope)
	var low: Vector3 = local.min
	var high: Vector3 = local.max
	var start: Vector2 = run.start
	var along: Vector2 = run.axis
	var outward: Vector2 = run.outward
	var points: Array[Vector3] = []
	for x in [low.x, high.x]:
		for y in [low.y, high.y]:
			for depth in [low.z, high.z]:
				var xz: Vector2 = start + along * float(x) - outward * float(depth)
				points.append(Vector3(xz.x, float(y), xz.y))
	var bounds: AABB = AABB(points[0], Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	for entry in envelopes:
		if int(entry.floor) != floor: continue
		var other: AABB = entry.bounds
		if bounds.grow(CLEARANCE).intersects(other):
			return "窗扇完整开合包络与相邻洞口冲突: " + id + " / " + str(entry.id)
	envelopes.append({"id": id, "floor": floor, "bounds": bounds})
	return ""

static func metadata(hole: Dictionary, run: Dictionary, geometry: Script, context: Dictionary) -> Dictionary:
	var settings: Dictionary = hole.settings
	var moving: bool = str(settings.type) != "fixed"
	var sash: Dictionary = _sash_hole(hole) if moving else hole
	var result: Dictionary = {
		"settings": settings.duplicate(true), "window_type": str(settings.type),
		"open_angle": float(settings.open_angle), "frame_inner_width": float(hole.width),
		"frame_inner_height": float(hole.height), "glass_clear_width": float(sash.width) - GAP * 2.0,
		"glass_clear_height": float(sash.height) - GAP * 2.0,
		"glass_thickness": float(settings.glass_thickness), "frame_front_depth": float(settings.recess) - float(settings.frame_depth) * 0.5,
		"frame_back_depth": float(settings.recess) + float(settings.frame_depth) * 0.5,
		"sash_profile": float(settings.frame_width) * 0.65 if moving else 0.0,
		"sweep_envelope_before_taper": hole.get("sweep_envelope", {}),
		"assembly_envelope_before_taper": hole.get("assembly_envelope", {}),
		"recess_limits": recess_limits(float(settings.frame_depth), float(run.depth)),
		"frame_depth_policy": "允许向外或室内突出；框与墙洞返回面安全区须保持至少3mm深度交集，不自动改值",
		"hinge_space": "变形前world；旋转后统一global taper"
	}
	if moving:
		var hinge: Dictionary = _hinge(hole, run)
		result["hinge_before_taper"] = hinge
		result["hinge_position"] = geometry._map(hinge.pivot, context)
		result["sash_outer_width"] = float(hole.width) - GAP * 2.0
		result["sash_outer_height"] = float(hole.height) - GAP * 2.0
	return result

static func _glass(buffer: Dictionary, hole: Dictionary, run: Dictionary, geometry: Script) -> void:
	var settings: Dictionary = hole.get("settings", {})
	# 玻璃随洞口梯形：上沿与窗框同 pull 收窄，不做正交矩形。
	var profile: Array[Vector2] = geometry._opening_quad(float(hole.cx), float(hole.sill) + GAP, float(hole.width) - GAP * 2.0, float(hole.height) - GAP * 2.0, 0.0, float(hole.get("pull", 0.0)))
	# 有构造配置时以框中心recess定位，并由validate约束玻璃厚度落在frame_depth内。
	# 只有真正无architecture的旧配方才保留墙厚中心与20mm默认厚度。
	var half: float = float(settings.get("glass_thickness", 0.02)) * 0.5
	var recess: float = float(settings.get("recess", float(run.depth) * 0.5))
	var a: Array[Vector3] = geometry._run_ring(profile, run, recess - half)
	var b: Array[Vector3] = geometry._run_ring(profile, run, recess + half)
	var n2: Vector2 = run.outward
	var normal: Vector3 = Vector3(n2.x, 0.0, n2.y)
	geometry._quad(buffer, a[0], a[1], a[2], a[3], normal)
	geometry._quad(buffer, b[0], b[1], b[2], b[3], -normal)
	geometry._join_profile(buffer, a, b, profile, run, false)

static func _sill(buffer: Dictionary, hole: Dictionary, run: Dictionary, geometry: Script) -> float:
	var settings: Dictionary = hole.settings
	var half: float = float(hole.width) * 0.5 + float(settings.frame_width) + float(settings.sill_extension)
	var x0: float = float(hole.cx) - half
	var x1: float = float(hole.cx) + half
	var front: float = -float(settings.sill_projection)
	var back: float = -CLEARANCE
	var polygon: Array[Vector2] = []
	for corner in [Vector2(x0, front), Vector2(x1, front), Vector2(x1, back), Vector2(x0, back)]:
		var point: Vector3 = geometry._point(run, corner.x, 0.0, corner.y)
		polygon.append(Vector2(point.x, point.z))
	polygon = geometry._ccw(polygon)
	var top: float = float(hole.sill) - float(settings.frame_width) - CLEARANCE
	var thickness: float = float(settings.sill_thickness)
	var bevel: float = minf(0.02, minf(thickness, minf(half * 2.0, back - front)) * 0.45)
	geometry._solid(buffer, polygon, top - thickness, top, bevel)
	return bevel

static func append_parts(parts: Array, hole: Dictionary, run: Dictionary, suffix: String, floor: int, facade: String, recipe: Dictionary, catalog: Dictionary, context: Dictionary, geometry: Script) -> void:
	var settings: Dictionary = hole.settings
	var frame: Dictionary = geometry._buffer()
	geometry._window_frame(frame, hole, run)
	var frame_bevel: float = minf(0.018, minf(float(settings.frame_width), float(settings.frame_depth)) * 0.45)
	geometry._part(parts, frame, "frame_" + suffix, "frame", floor, facade, recipe, catalog, context, frame_bevel, false)
	var glass_hole: Dictionary = hole
	var hinge: Dictionary = {}
	if str(settings.type) != "fixed":
		glass_hole = _sash_hole(hole)
		hinge = _hinge(hole, run)
		var sash: Dictionary = geometry._buffer()
		geometry._window_frame(sash, glass_hole, run)
		_rotate(sash, hinge)
		var sash_bevel: float = minf(0.018, minf(float(glass_hole.settings.frame_width), float(glass_hole.settings.frame_depth)) * 0.45)
		geometry._part(parts, sash, "sash_" + suffix, "frame", floor, facade, recipe, catalog, context, sash_bevel, false)
	var glass: Dictionary = geometry._buffer()
	_glass(glass, glass_hole, run, geometry)
	if not hinge.is_empty(): _rotate(glass, hinge)
	geometry._part(parts, glass, "glass_" + suffix, "glass", floor, facade, recipe, catalog, context, 0.0, false)
	if bool(settings.sill_enabled):
		var sill: Dictionary = geometry._buffer()
		var bevel: float = _sill(sill, hole, run, geometry)
		geometry._part(parts, sill, "sill_" + suffix, "frame", floor, facade, recipe, catalog, context, bevel, false)
