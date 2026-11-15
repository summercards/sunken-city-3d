@tool
extends RefCounted
## 米制树干中心线；t 是 y / height，不是弧长或控制点序号。

const MIN_POINTS := 2
const MAX_POINTS := 8
const MAX_OFFSET := 30.0
const MIN_Y_STEP := 0.01
const SEGMENT_STEPS := 16
const MAX_RINGS := (MAX_POINTS - 1) * SEGMENT_STEPS + 1

static func validate(value: Variant, height: float) -> String:
	if not (value is Array):
		return "trunk_path 必须是数组；空数组表示自动树干"
	if value.is_empty():
		return ""
	if value.size() < MIN_POINTS or value.size() > MAX_POINTS:
		return "trunk_path 手动模式必须有 2..8 个米制控制点"
	var previous_y := -MIN_Y_STEP
	for index in value.size():
		var point: Variant = value[index]
		if not (point is Dictionary) or point.size() != 3:
			return "trunk_path[%d] 必须仅含 x/y/z" % index
		for axis in ["x", "y", "z"]:
			if not point.has(axis) or not (point[axis] is int or point[axis] is float) or not is_finite(float(point[axis])):
				return "trunk_path[%d].%s 必须是有限数（米）" % [index, axis]
		if absf(float(point.x)) > MAX_OFFSET or absf(float(point.z)) > MAX_OFFSET or float(point.y) < 0.0 or float(point.y) > height:
			return "trunk_path[%d] 超出范围：x/z 为 ±30 米，y 为 0..height" % index
		if index == 0 and (float(point.x) != 0.0 or float(point.y) != 0.0 or float(point.z) != 0.0):
			return "trunk_path 首点必须为 (0, 0, 0)"
		if index > 0 and float(point.y) - previous_y < MIN_Y_STEP - 1.0e-9:
			return "trunk_path 必须严格递增且相邻 y 至少间隔 0.01 米"
		previous_y = float(point.y)
	if absf(previous_y - height) > 1.0e-9:
		return "trunk_path 末点 y 必须等于 height（米），不会自动缩放或裁剪"
	return ""

static func sample(recipe: Dictionary, t: float) -> Vector3:
	# 调用者须先 Recipe.validate；t 仅作为采样站位限制到 [0,1]，不修正配方。
	var station := clampf(t, 0.0, 1.0)
	var controls: Array = recipe.get("trunk_path", [])
	if controls.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = (str(int(recipe.seed)) + ":trunk/shape").sha256_text().substr(0, 15).hex_to_int()
		var variation := float(recipe.get("variation", 1.0)) if recipe.get("random_enabled", true) else 0.0
		var phase := lerpf(PI, rng.randf_range(0.0, TAU), variation)
		var curve := float(recipe.trunk_curve) * sin(station * PI * 0.9) * (0.30 if recipe.species == "birch" else 1.0)
		return Vector3(curve * sin(station * 2.2 + phase), float(recipe.height) * station, curve * cos(station * 1.7 + phase))
	var y := station * float(recipe.height)
	for index in range(controls.size() - 1):
		var a := _point(controls[index])
		var b := _point(controls[index + 1])
		if y <= b.y or index == controls.size() - 2:
			var f := clampf((y - a.y) / (b.y - a.y), 0.0, 1.0)
			# 每段 x/z 单调、端点横向导数为零；y 保持线性，穿窗时不产生横向过冲。
			var eased := f * f * (3.0 - 2.0 * f)
			return Vector3(lerpf(a.x, b.x, eased), y, lerpf(a.z, b.z, eased))
	return _point(controls[-1])

static func points(recipe: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var controls: Array = recipe.get("trunk_path", [])
	if controls.is_empty():
		for index in 17:
			result.append(sample(recipe, float(index) / 16.0))
		return result
	for index in range(controls.size() - 1):
		var a := _point(controls[index])
		var b := _point(controls[index + 1])
		# 控制点直接写入环中心，避免浮点站位换算遗漏；最多 113 环。
		result.append(a)
		for step in range(1, SEGMENT_STEPS):
			var y := lerpf(a.y, b.y, float(step) / float(SEGMENT_STEPS))
			result.append(sample(recipe, y / float(recipe.height)))
	result.append(_point(controls[-1]))
	return result

static func _point(data: Dictionary) -> Vector3:
	return Vector3(float(data.x), float(data.y), float(data.z))
