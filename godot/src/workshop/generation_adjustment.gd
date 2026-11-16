@tool
extends RefCounted
## 只读建议端口；path 固定为 Array[String]，before=null 表示新增稀疏数值覆盖。
## kind=parameter 计入三参数上限；alias/derived 仍逐项列出真实差异，不提交Session。
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const Generator = preload("res://src/workshop/generator.gd")
const Shell = preload("res://src/workshop/shell_geometry.gd")
const WindowGeometry = preload("res://src/workshop/shell_window_geometry.gd")
const MAX_PARAMETERS := 3
const MAX_NUMBERS := 6
const EPS := 0.000001

static func evaluate(probe: Dictionary, catalog: Dictionary) -> Dictionary:
	var reason: String = Recipe.validate(probe, catalog)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	var built: Dictionary = Generator.build(probe, catalog)
	var result := {"ok": bool(built.ok), "reason": str(built.reason)}
	if is_instance_valid(built.get("root")): built.root.free()
	return result

static func propose(candidate: Dictionary, catalog: Dictionary) -> Dictionary:
	var boundary: String = _boundary(candidate, catalog)
	if not boundary.is_empty(): return _refuse(candidate, boundary, boundary)
	var original: Dictionary = evaluate(candidate, catalog)
	if bool(original.ok):
		return {"ok": true, "reason": "", "candidate": candidate.duplicate(true), "changes": [], "original_reason": "", "parameter_count": 0}
	if str(candidate.get("construction_mode", "modular_v1")) != "shell_v2":
		return _refuse(candidate, "本轮调整仅支持shell_v2，不迁移或修写旧配方：" + str(original.reason), str(original.reason))
	var work: Dictionary = candidate.duplicate(true)
	var edits: Array = []
	_domains(work, edits)
	var scope_reason: String = Recipe._validate_floor_overrides(work.floor_overrides, int(work.floors))
	if scope_reason.is_empty(): scope_reason = Recipe._validate_facade_overrides(work.facade_overrides)
	if not scope_reason.is_empty(): return _refuse(candidate, scope_reason, str(original.reason))
	var contexts: Array = _contexts(work)
	for context: Dictionary in contexts:
		_window_rules(work, context, edits)
	_heights(work, edits)
	var bay_reason: String = _bays(work, edits)
	if not bay_reason.is_empty(): return _refuse(candidate, bay_reason, str(original.reason))
	# 不调用 Recipe.normalized 返回候选；只有确实派生的taper单列，其他默认/覆盖保持原样。
	if not edits.is_empty() and bool(Config.normalized(work.get("architecture", {})).form.enabled):
		_edit_number(work, ["taper"], float(Config.resolve_form(work).structure), "形体派生收分", "比例", "由原形体区间与原seed派生，非独立调整", edits, "derived")
	var changes: Array = []
	var parameters: int = 0
	for edit: Dictionary in edits:
		var before: Variant = _read_path(candidate, edit.path)
		var after: Variant = _read_path(work, edit.path)
		if before == after: continue
		edit.before = before
		edit.after = after
		changes.append(edit)
		if edit.kind == "parameter": parameters += 1
	if parameters > MAX_PARAMETERS or changes.size() > MAX_NUMBERS:
		return _refuse(candidate, "需要调整%d个独立参数、%d个数值，超过本轮最多3个参数/6个数值；请分步修改" % [parameters, changes.size()], str(original.reason))
	if changes.is_empty(): return _refuse(candidate, "没有白名单安全数值方案：" + str(original.reason), str(original.reason))
	var verified: Dictionary = evaluate(work, catalog)
	if not bool(verified.ok):
		return _refuse(candidate, "建议未通过完整校验/生成，不提供修复：" + str(verified.reason), str(original.reason))
	return {"ok": true, "reason": "确认后仅调整%d个参数（共%d项数值变化）" % [parameters, changes.size()], "candidate": work, "changes": changes, "original_reason": str(original.reason), "parameter_count": parameters}

static func _refuse(candidate: Dictionary, reason: String, original: String) -> Dictionary:
	return {"ok": false, "reason": reason, "candidate": candidate.duplicate(true), "changes": [], "original_reason": original, "parameter_count": 0}

static func _boundary(r: Dictionary, c: Dictionary) -> String:
	if not Recipe._finite_tree(r) or not Recipe._finite_tree(c): return "输入必须为有限JSON数据"
	var reason: String = Catalog.validate(c)
	if not reason.is_empty(): return reason
	if r.get("schema") != Recipe.SCHEMA or r.get("schema_version") != Recipe.SCHEMA_VERSION: return "不支持的配方schema/未来版本"
	if not Recipe._math_integer(r.get("floors")) or int(r.floors) < 1 or int(r.floors) > 8: return "楼层必须为1..8整数"
	for field: String in ["width", "depth", "floor_height", "slab_thickness", "wall_thickness", "column_width", "window_width", "window_height", "window_sill", "bay_width", "door_width", "door_height", "bevel_width", "taper"]:
		if not Config._number(r.get(field)): return field + "必须为有限数值"
	for field: String in ["floor_overrides", "facade_overrides", "slot_overrides"]:
		if not r.get(field) is Dictionary: return field + "必须为对象"
	for field: String in ["floor_overrides", "facade_overrides"]:
		for key: String in r[field]:
			if not r[field][key] is Dictionary: return field + "覆盖必须为对象"
			for name: String in r[field][key]:
				if name != "windows" and not Config._number(r[field][key][name]): return field + "." + key + "." + name + "必须为数值"
	if r.has("architecture"):
		if not r.architecture is Dictionary: return "architecture必须为对象"
		for key: String in r.architecture:
			if not r.architecture[key] is Dictionary: return "architecture." + key + "必须为对象"
		for scope: String in ["floor_windows", "facade_windows", "window_overrides"]:
			var entries: Dictionary = r.architecture.get(scope, {})
			if entries.size() > 128: return "窗口覆盖超过128项，不进行批量调整"
			for key: String in entries:
				if not entries[key] is Dictionary: return scope + "覆盖必须为对象"
				if scope == "floor_windows" and not Config._floor_key(key, int(r.floors)): return "非法楼层窗覆盖键"
				if scope == "facade_windows" and key not in Config.FACADES: return "非法立面窗覆盖键"
				if scope == "window_overrides" and not Config._opening_id(key, int(r.floors)): return "非法单窗覆盖ID"
		for path: Array in _window_paths(r):
			var entry: Dictionary = _read_path(r, path)
			for field: String in Config.WINDOW_BOUNDS:
				if entry.has(field) and not Config._number(entry[field]): return ".".join(path) + "." + field + "必须为数值"
		var structure: Dictionary = r.architecture.duplicate(true)
		structure.window = Config.defaults().window
		for scope: String in ["floor_windows", "facade_windows", "window_overrides"]: structure[scope] = {}
		reason = Config.validate(structure, int(r.floors))
		if not reason.is_empty(): return reason
		for path: Array in _window_paths(r):
			var checked: Dictionary = (_read_path(r, path) as Dictionary).duplicate(true)
			for field: String in Config.WINDOW_BOUNDS:
				if checked.has(field): checked[field] = clampf(float(checked[field]), float(Config.WINDOW_BOUNDS[field][0]), float(Config.WINDOW_BOUNDS[field][1]))
			if checked.get("type") == "fixed": checked.open_angle = 0.0
			reason = Config._validate_window(checked, ".".join(path))
			if not reason.is_empty(): return reason
	return ""

static func _domains(r: Dictionary, edits: Array) -> void:
	for spec: Array in [["floor_height", 2.0, 12.0, 0.1], ["slab_thickness", 0.08, 0.6, 0.01], ["wall_thickness", 0.12, 0.6, 0.01], ["bay_width", 2.0, 6.0, 0.1]]:
		_bound(r, [spec[0]], float(spec[1]), float(spec[2]), float(spec[3]), edits)
	for key: String in r.floor_overrides:
		for spec: Array in [["floor_height", 2.0, 12.0, 0.1], ["slab_thickness", 0.08, 0.6, 0.01]]:
			if r.floor_overrides[key].has(spec[0]): _bound(r, ["floor_overrides", key, spec[0]], float(spec[1]), float(spec[2]), float(spec[3]), edits)
	var minimum: float = minf(float(r.wall_thickness), float(r.slab_thickness))
	for key: String in r.floor_overrides:
		minimum = minf(minimum, float(r.floor_overrides[key].get("slab_thickness", r.slab_thickness)))
	var max_bevel: float = _down(minimum * 0.5 - EPS, 0.01)
	_bound(r, ["bevel_width"], 0.01, max_bevel, 0.01, edits)
	for path: Array in _window_paths(r):
		var entry: Dictionary = _read_path(r, path)
		for field: String in ["frame_width", "frame_depth", "glass_thickness", "recess", "sill_projection", "sill_thickness", "sill_extension", "open_angle"]:
			if not entry.has(field): continue
			var bounds: Array = Config.WINDOW_BOUNDS[field]
			_bound(r, path + [field], float(bounds[0]), float(bounds[1]), _step(field), edits)
		# Config.validate 同时检查显式fixed条目，即使被更高层覆盖也不能留非法角度。
		if entry.get("type") == "fixed" and entry.has("open_angle"):
			_edit_number(r, path + ["open_angle"], 0.0, "固定窗开角", "°", "fixed只允许0°，不改变窗型", edits)

static func _window_rules(r: Dictionary, context: Dictionary, edits: Array) -> void:
	var s: Dictionary = _settings(r, context)
	if str(s.type) == "fixed" and float(s.open_angle) != 0.0:
		_set_window(r, context, "open_angle", 0.0, "固定窗只允许0°", edits)
	if not bool(s.enabled): return
	var required_depth: float = float(s.glass_thickness) + (0.004 if str(s.type) == "fixed" else 0.008)
	var moving: bool = str(s.type) != "fixed"
	var available: float = float(s.frame_depth) - (0.004 if moving else 0.0)
	if float(s.glass_thickness) + 0.004 > available:
		var depth: float = _up(required_depth, 0.001)
		# 生成器此处为严格浮点比较；如格点落在不利舍入侧，多留一个1mm步长。
		if float(s.glass_thickness) + 0.004 > depth - (0.004 if moving else 0.0): depth += 0.001
		_set_window(r, context, "frame_depth", depth, "优先增框深，保留玻璃厚度与两侧装配缝（含严格比较的步长余量）", edits)
	s = _settings(r, context)
	var limits: Vector2 = WindowGeometry.recess_limits(float(s.frame_depth), float(r.wall_thickness))
	var low: float = _up(maxf(-0.5, limits.x), 0.01)
	var high: float = _down(minf(0.5, limits.y), 0.01)
	if low <= high and (float(s.recess) < low - EPS or float(s.recess) > high + EPS):
		_set_window(r, context, "recess", clampf(float(s.recess), low, high), "按真实框深/墙厚的返回面交集区间调整退入", edits)
	if bool(s.sill_enabled):
		if float(s.sill_projection) <= WindowGeometry.CLEARANCE:
			_set_window(r, context, "sill_projection", 0.01, "窗沿外挑必须大于3mm装配缝", edits)
		var required_sill: float = float(s.frame_width) + float(s.sill_thickness) + WindowGeometry.CLEARANCE * 2.0 + EPS
		# 同时保留洞口下方0.08m墙体及0.02m倒角。
		required_sill = maxf(required_sill, float(s.frame_width) + 0.103)
		if float(s.sill) < required_sill:
			_set_window(r, context, "sill", _up(required_sill, 0.01), "提高实际窗台以保留原窗沿厚度、框材和楼板安全距离", edits)

static func _heights(r: Dictionary, edits: Array) -> void:
	var required: Array[float] = []
	for floor: int in int(r.floors):
		var need: float = 2.0
		for context: Dictionary in _contexts(r):
			if int(context.floor) != floor: continue
			var s: Dictionary = _settings(r, context)
			if bool(s.enabled): need = maxf(need, float(s.sill) + float(s.height) + float(s.frame_width) + 0.103)
		if floor == 0: need = maxf(need, float(r.door_height) + Shell.FRAME_PROFILE + 0.103)
		var slab: float = _floor_value(r, mini(floor + 1, int(r.floors) - 1), "slab_thickness")
		required.append(_up(need + slab, 0.1))
	var all_need: bool = true
	var max_need: float = 0.0
	for floor: int in int(r.floors):
		all_need = all_need and required[floor] > _floor_value(r, floor, "floor_height") + EPS
		max_need = maxf(max_need, required[floor])
	if all_need and r.floor_overrides.is_empty() and max_need <= 12.0:
		_edit_number(r, ["floor_height"], max_need, "层高", "m", "优先增加层高容纳原净窗/门高、框材和上层板厚", edits)
	else:
		for floor: int in int(r.floors):
			if required[floor] <= _floor_value(r, floor, "floor_height") + EPS or required[floor] > 12.0: continue
			var path: Array = ["floor_overrides", str(floor), "floor_height"]
			_edit_number(r, path, required[floor], "第%d层层高" % floor, "m", "仅在冲突楼层承载层高，不清除窗/立面/单窗覆盖，不缩净洞", edits)

static func _bays(r: Dictionary, edits: Array) -> String:
	var current: float = float(r.bay_width)
	if _horizontal_ok(r, current): return ""
	# 只做最多41个0.1m格点的解析开间判断；不在循环里生成、随机重试或换模板。
	for tick: int in range(int(ceilf((current + EPS) * 10.0)), 61):
		var bay: float = float(tick) / 10.0
		if not _horizontal_ok(r, bay): continue
		if not r.get("architecture", {}).get("window_overrides", {}).is_empty():
			return "增大开间会改变洞口数量/单窗ordinal；本轮不重绑定单窗ID，请先手动确认开间拓扑"
		_edit_number(r, ["bay_width"], bay, "目标开间", "m", "按实际墙run等分计算，增大开间容纳原净洞、框/窗沿和柱，不缩窗或关柱", edits)
		return ""
	return "目标开间2..6m内没有保留净洞、框/窗沿及柱的确定安全方案；不缩窗、不减柱或更换形状"

static func _horizontal_ok(r: Dictionary, bay: float) -> bool:
	if float(r.width) < 6.0 or float(r.width) > 24.0 or float(r.depth) < 6.0 or float(r.depth) > 20.0: return false
	var effective: float = float(r.width) / ceilf(float(r.width) / bay)
	if float(r.door_width) + 0.34 + float(r.column_width) >= effective: return false
	if float(r.column_width) >= minf(effective, float(r.depth) / ceilf(float(r.depth) / bay)) - 0.3: return false
	var a: Dictionary = Config.normalized(r.get("architecture", {}))
	var polygon: Array[Vector2] = Shell._footprint(str(r.shape), float(r.width), float(r.depth), a.plan)
	if polygon.is_empty(): return false
	for floor: int in int(r.floors):
		var distance: float = 0.0 if int(a.plan.setback_start) < 0 else float(maxi(0, floor - int(a.plan.setback_start) + 1)) * float(a.plan.setback_step)
		var contour: Array[Vector2] = Shell._offset(polygon, distance)
		if not Shell._validate_contour(polygon, contour, distance, float(r.wall_thickness)).is_empty(): return false
		var counters: Dictionary = {}
		for index: int in contour.size():
			var start: Vector2 = contour[index]
			var end: Vector2 = contour[(index + 1) % contour.size()]
			var length: float = start.distance_to(end)
			var axis: Vector2 = (end - start).normalized()
			var facade: String = Shell._facade(Vector2(axis.y, -axis.x))
			var count: int = maxi(1, floori(length / bay))
			var door_bay: int = -1
			if floor == 0 and facade == "front":
				var nearest: float = INF
				for ordinal: int in count:
					var x: float = (start + axis * length * (float(ordinal) + 0.5) / float(count)).x
					if absf(x) < nearest:
						nearest = absf(x)
						door_bay = ordinal
			for slot: int in count:
				var ordinal: int = int(counters.get(facade, 0))
				counters[facade] = ordinal + 1
				var id: String = "opening_%s_%d_%d" % [facade, floor, ordinal]
				var s: Dictionary = Config.window_settings(r, floor, facade, id)
				var door: bool = slot == door_bay
				if not door and not bool(s.enabled): continue
				s["door_width"] = r.door_width
				s["door_height"] = r.door_height
				var center: float = length * (float(slot) + 0.5) / float(count)
				var hole: Dictionary = Shell._opening(0.0, -Shell.INSET, center, s, door, Config.opening_rho(r, facade + "_" + str(ordinal)))
				var reach: float = float(hole.reach)
				var margin: float = float(r.wall_thickness) + 0.08
				if center - reach - Shell.WALL_BEVEL < margin or center + reach + Shell.WALL_BEVEL > length - margin: return false
				if reach * 2.0 + Shell.WALL_BEVEL * 2.0 + 0.08 > length / float(count): return false
				if not door and bool(s.sill_enabled) and float(s.width) + 2.0 * (float(s.frame_width) + float(s.sill_extension) + WindowGeometry.CLEARANCE) > length / float(count): return false
				if bool(a.pilaster.enabled) and bool(a.pilaster.middle):
					if slot > 0 and center - reach - 0.02 < length * float(slot) / float(count) + float(a.pilaster.width) * 0.5: return false
					if slot + 1 < count and center + reach + 0.02 > length * float(slot + 1) / float(count) - float(a.pilaster.width) * 0.5: return false
	return true

static func _contexts(r: Dictionary) -> Array:
	var result: Array = []
	for floor: int in int(r.floors):
		for facade: String in Config.FACADES:
			result.append({"floor": floor, "facade": facade, "id": ""})
	var ids: Array = r.get("architecture", {}).get("window_overrides", {}).keys()
	ids.sort()
	for id: String in ids:
		var parts: PackedStringArray = id.split("_")
		result.append({"floor": int(parts[2]), "facade": parts[1], "id": id})
	return result

static func _settings(r: Dictionary, context: Dictionary) -> Dictionary:
	return Config.window_settings(r, int(context.floor), str(context.facade), str(context.id))

static func _window_paths(r: Dictionary) -> Array:
	var result: Array = []
	var a: Dictionary = r.get("architecture", {})
	if a.has("window"): result.append(["architecture", "window"])
	for scope: String in ["floor_windows", "facade_windows", "window_overrides"]:
		var keys: Array = a.get(scope, {}).keys()
		keys.sort()
		for key: String in keys: result.append(["architecture", scope, key])
	return result

static func _owner(r: Dictionary, context: Dictionary, field: String) -> Array:
	var path: Array = ["architecture", "window", field]
	if field in ["width", "height", "sill"] and not r.get("architecture", {}).get("window", {}).has(field): path = ["window_" + field]
	var scopes: Array = [["floor_overrides", str(context.floor), "window_" + field], ["architecture", "floor_windows", str(context.floor), field], ["facade_overrides", str(context.facade), field], ["architecture", "facade_windows", str(context.facade), field], ["architecture", "window_overrides", str(context.id), field]]
	for test: Array in scopes:
		if _read_path(r, test) != null: path = test
	return path

static func _set_window(r: Dictionary, context: Dictionary, field: String, value: float, reason: String, edits: Array) -> void:
	var path: Array = _owner(r, context, field)
	var dependencies: Array = {"open_angle": ["type"], "frame_depth": ["glass_thickness", "type"], "recess": ["frame_depth"], "sill": ["sill_thickness", "frame_width", "sill_enabled"], "sill_projection": ["sill_enabled"]}.get(field, [])
	# 冲突来自更深覆盖时，在该层新增承载值，不能改继承源误伤其它窗。
	for dependency: String in dependencies:
		var carrier: Array = _owner(r, context, dependency)
		if _scope_rank(carrier) > _scope_rank(path): path = carrier.slice(0, -1) + [field]
	_edit_number(r, path, value, "窗参数 " + field, "°" if field == "open_angle" else "m", reason, edits)
	if field in ["width", "height", "sill"]:
		var alias: Array = ["window_" + field] if path == ["architecture", "window", field] else ["architecture", "window", field]
		if path == ["window_" + field] or path == ["architecture", "window", field]:
			if _read_path(r, alias) != null: _edit_number(r, alias, value, "全局窗尺寸同步alias " + field, "m", "与全局实际owner同步的已有镜像字段，明确列出而非独立调整", edits, "alias")

static func _scope_rank(path: Array) -> int:
	if path.size() == 1: return 0
	if path[0] == "floor_overrides": return 1
	if path[0] == "facade_overrides": return 3
	return {"window": 0, "floor_windows": 2, "facade_windows": 4, "window_overrides": 5}.get(path[1], 0)

static func _floor_value(r: Dictionary, floor: int, field: String) -> float:
	return float(r.floor_overrides.get(str(floor), {}).get(field, r[field]))

static func _bound(r: Dictionary, path: Array, low: float, high: float, step: float, edits: Array) -> void:
	var value: float = float(_read_path(r, path))
	if value < low or value > high:
		_edit_number(r, path, clampf(roundf(clampf(value, low, high) / step) * step, low, high), ".".join(path), "°" if path[-1] == "open_angle" else "m", "仅修正此字段合法域，不重置其他参数", edits)

static func _edit_number(r: Dictionary, path: Array, value: float, label: String, unit: String, reason: String, edits: Array, kind: String = "parameter") -> void:
	var before: Variant = _read_path(r, path)
	if before != null and absf(float(before) - value) < EPS: return
	var target: Dictionary = r
	for i: int in path.size() - 1:
		if not target.has(path[i]): target[path[i]] = {}
		target = target[path[i]]
	target[path[-1]] = value
	for edit: Dictionary in edits:
		if edit.path == path:
			if not str(edit.reason).contains(reason): edit.reason += "；" + reason
			return
	var typed_path: Array[String] = []
	for part: String in path: typed_path.append(part)
	edits.append({"path": typed_path, "label": label, "before": before, "after": value, "unit": unit, "reason": reason, "kind": kind})

static func _read_path(r: Dictionary, path: Array) -> Variant:
	var value: Variant = r
	for part: String in path:
		if not value is Dictionary or not value.has(part): return null
		value = value[part]
	return value

static func _up(value: float, step: float) -> float:
	return snappedf(ceilf((value - EPS) / step) * step, step)

static func _down(value: float, step: float) -> float:
	return snappedf(floorf(value / step) * step, step)

static func _step(field: String) -> float:
	if field in ["frame_width", "frame_depth", "glass_thickness", "sill_thickness"]: return 0.001
	return 1.0 if field == "open_angle" else 0.01
