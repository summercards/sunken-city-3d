extends Node
const BodyScale = preload("res://src/avatar/avatar_dimensions.gd")
## SEA-ROOM 状态所有者：床铺的摆放与「玩家此刻在不在房间里」。
##
## 唯一写入者。场景只按这里的状态摆放，存档只搬运快照；本文件不读场景、不读 UI、
## 不读时钟，也不发命令。将来「布置」功能要挪床或转床，只调 `place_bed()`。
##
## 坐标口径：全部是**房间局部坐标**（原点 = 室内地面中心，+Z 朝玻璃前厅）。
## 房间在世界里的位置归 SEA-WORLD 的区块装配，换位置不会让床的存档失效。

signal changed

## 房间内部净尺寸的一半（米）。与 component_plan 的 interior_half_extent 对齐。
const HALF := 2.5
## 床铺占地半尺寸（米）。取 Blender 目录里的实际包围盒：1.16 × 2.03。
const BED_HALF := Vector2(0.58, 1.015)
## 床与墙之间留的缝：贴死会让包围盒和墙板 z-fighting。
const WALL_GAP := 0.06
## 闭区间边界只容忍浮点往返误差（米），不据此挪动已接受的位置。
const POSITION_EPSILON := 0.000001
const VERSION := 1

## 初版摆放：西北角，床头贴后墙（-Z）。
const DEFAULT_BED := Vector3(-1.86, 0.0, -1.425)
const DEFAULT_YAW := 0.0

## 房间里的固定陈设，床不能压上去（房间局部 AABB：中心 + 半尺寸）。
const FIXED_FOOTPRINTS := [
	{"name": "床头柜", "center": Vector2(-0.95, -2.29), "half": Vector2(0.285, 0.27)},
	{"name": "靠墙矮柜", "center": Vector2(2.24, -0.15), "half": Vector2(0.283, 0.80)},
	# 门口这段留给进出，床压上去就把自己关在屋里了。
	{"name": "门口通道", "center": Vector2(0.0, 2.15), "half": Vector2(0.85, 0.55)},
]

## G07：起床点必须让正式 CharacterMotor 胶囊停在床 OBB、固定家具和墙边之外。
## 该半径与 CharacterMotor / GroundSpace 共用同一 BodyScale，不按视觉 SCALE 猜一个新值。
const ROOM_SCALE := 1.5
## RoomService 的位置是未缩放房间局部米；碰撞胶囊是世界米，先换算到同一坐标系。
const BEDSIDE_WALL_GAP := 0.05
const BEDSIDE_FURNITURE_GAP := 0.05
const BEDSIDE_FORWARD_OFFSET := 0.15
const BEDSIDE_ROUTE_STEP := 0.10
const BEDSIDE_ROUTE_MARGIN := 0.02

var bed_position := DEFAULT_BED
var bed_yaw := DEFAULT_YAW
var inside := false
## 由 RoomController 注入真实房间 GroundSpace 路线查询；未装配时使用本文件的
## 合法网格矩阵，方便纯状态测试覆盖边界与四朝向。
var route_query: Callable
var room_scale := ROOM_SCALE

func body_radius_local() -> float:
	return BodyScale.BODY_RADIUS / room_scale


func reset() -> void:
	bed_position = DEFAULT_BED
	bed_yaw = DEFAULT_YAW
	inside = false
	changed.emit()


## 床往哪个方向躺：把半尺寸按朝向旋转成世界 AABB 的半尺寸。
func bed_extent(yaw: float) -> Vector2:
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return Vector2(BED_HALF.x * c + BED_HALF.y * s, BED_HALF.x * s + BED_HALF.y * c)


func bed_limits(yaw: float) -> Rect2:
	var extent := bed_extent(yaw)
	var inner := HALF - WALL_GAP
	var span: Vector2 = Vector2(inner, inner) - extent
	return Rect2(-span.x, -span.y, span.x * 2.0, span.y * 2.0)


## 布置入口：把床放到 `position`，朝向 `yaw`（弧度）。
##
## 三个拒绝理由分开说，因为玩家能做的补救不一样：超出房间、压到别的家具、
## 堵住门口。可行时也不会静默改值 —— 返回 `ok` 与最终落点，由调用方决定回显。
func place_bed(position: Vector3, yaw: float) -> Dictionary:
	if not position.is_finite() or not is_finite(yaw):
		return {"ok": false, "reason": "位置无效"}
	yaw = wrapf(yaw, -PI, PI)
	var limits := bed_limits(yaw)
	var asked := Vector2(position.x, position.z)
	var clamped := Vector2(clampf(asked.x, limits.position.x, limits.end.x),
		clampf(asked.y, limits.position.y, limits.end.y))
	var reason := _overlap_reason(clamped, yaw)
	if reason != "":
		# 玩家把床拖到墙边/柜子上时，先就近滑到最近的空位 —— 布置的操作手感是
		# 「放下就放下」，不是「先弹一句这里不行、再自己微调」。真的没有空位才拒绝。
		var slid := _nearest_free(clamped, yaw, limits)
		if slid == Vector2.INF:
			return {"ok": false, "reason": reason}
		clamped = slid
	var candidate := to_dict()
	candidate.bed = {"position": [clamped.x, 0.0, clamped.y], "yaw": yaw}
	var error := validate_snapshot(candidate)
	if error != "":
		return {"ok": false, "reason": error}
	if _safe_bedside_candidates(clamped, yaw).is_empty():
		return {"ok": false, "reason": "这里没有安全的床边起床点"}
	bed_position = Vector3(clamped.x, 0.0, clamped.y)
	bed_yaw = yaw
	changed.emit()
	return {"ok": true, "position": bed_position, "yaw": bed_yaw, "clamped": clamped != asked}


## 提交、滑位与快照共用有限闭区间，不能用排除上边界的 Rect2.has_point。
func _within_limits(point: Vector2, limits: Rect2) -> bool:
	return point.is_finite() \
		and point.x >= limits.position.x - POSITION_EPSILON \
		and point.x <= limits.end.x + POSITION_EPSILON \
		and point.y >= limits.position.y - POSITION_EPSILON \
		and point.y <= limits.end.y + POSITION_EPSILON


## 离目标最近、又不压到固定陈设的落点。找不到返回 Vector2.INF。
func _nearest_free(center: Vector2, yaw: float, limits: Rect2) -> Vector2:
	for ring in 40:
		var radius := 0.10 + float(ring) * 0.05
		for i in 16:
			var candidate: Vector2 = center + Vector2.RIGHT.rotated(TAU * float(i) / 16.0) * radius
			if not _within_limits(candidate, limits):
				continue
			if _overlap_reason(candidate, yaw) == "":
				return candidate
	return Vector2.INF


func _overlap_reason(center: Vector2, yaw: float) -> String:
	var extent := bed_extent(yaw)
	var bed := Rect2(center - extent, extent * 2.0)
	for item in FIXED_FOOTPRINTS:
		var half: Vector2 = item.half
		var other := Rect2(item.center - half, half * 2.0)
		if bed.intersects(other):
			return "这里被%s占着" % str(item.name)
	return ""


## 返回床四边按局部朝向生成的安全候选。每个候选都同时通过：
##   · 实际床 OBB 到角色胶囊半径的净空；
##   · 固定陈设与屋内墙边净空；
##   · 房间真实三块 walk rect 的中心域；
##   · 以 0.1m 网格验证到前厅门洞的连通路线。
func bedside_candidates() -> Array:
	return _safe_bedside_candidates(Vector2(bed_position.x, bed_position.z), bed_yaw)


func _safe_bedside_candidates(center: Vector2, yaw: float) -> Array:
	var result: Array = []
	var axes := [Vector2(cos(yaw), -sin(yaw)), Vector2(sin(yaw), cos(yaw))]
	var extent := Vector2(BED_HALF.x, BED_HALF.y)
	var sides := [
		[axes[0], extent.x, axes[1], "右侧"],
		[-axes[0], extent.x, axes[1], "左侧"],
		[axes[1], extent.y, axes[0], "床尾"],
		[-axes[1], extent.y, axes[0], "床头"],
	]
	for side in sides:
		var normal: Vector2 = side[0]
		var tangent: Vector2 = side[2]
		var point := center + normal * (float(side[1]) + body_radius_local() + BEDSIDE_WALL_GAP)
		point += tangent * BEDSIDE_FORWARD_OFFSET
		if not _bedside_clear(point, center, yaw):
			continue
		var route := _route_to_door(point, center, yaw)
		if route.is_empty():
			continue
		var to_bed := (center - point).normalized()
		result.append({
			"point": point,
			"yaw": atan2(to_bed.x, to_bed.y),
			"side": str(side[3]),
			"route": route,
		})
	return result


func _bedside_clear(point: Vector2, center: Vector2, yaw: float) -> bool:
	var radius := body_radius_local()
	var wall_limit := HALF - radius - BEDSIDE_WALL_GAP
	if absf(point.x) > wall_limit or absf(point.y) > wall_limit:
		return false
	if not _inside_walk_domain(point, radius + BEDSIDE_ROUTE_MARGIN):
		return false
	if not _circle_clear_obb(point, center, yaw, BED_HALF, radius + BEDSIDE_FURNITURE_GAP):
		return false
	for item in FIXED_FOOTPRINTS:
		if str(item.name) == "门口通道":
			continue
		var footprint := Rect2(item.center - item.half, item.half * 2.0)
		if footprint.grow(radius + BEDSIDE_FURNITURE_GAP).has_point(point):
			return false
	return true


func _inside_walk_domain(point: Vector2, inset: float) -> bool:
	var rects := [
		Rect2(-2.42, -2.42, 4.84, 4.84),
		Rect2(-0.55, 2.4, 1.1, 0.34),
		Rect2(-1.62, 2.7, 3.24, 1.62),
	]
	var contained := false
	for rect: Rect2 in rects:
		if rect.has_point(point):
			contained = true
	if not contained:
		return false
	var boundary := PackedVector2Array([
		Vector2(-2.42, -2.42), Vector2(2.42, -2.42), Vector2(2.42, 2.42),
		Vector2(0.55, 2.42), Vector2(0.55, 2.7), Vector2(1.62, 2.7),
		Vector2(1.62, 4.32), Vector2(-1.62, 4.32), Vector2(-1.62, 2.7),
		Vector2(-0.55, 2.7), Vector2(-0.55, 2.42), Vector2(-2.42, 2.42)])
	for index in boundary.size():
		if Geometry2D.get_closest_point_to_segment(point, boundary[index], boundary[(index + 1) % boundary.size()]).distance_to(point) < inset:
			return false
	return true


func _circle_clear_obb(point: Vector2, center: Vector2, yaw: float, half: Vector2, clearance: float) -> bool:
	var local := (point - center).rotated(yaw)
	var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return local.distance_to(closest) >= clearance - POSITION_EPSILON


## 正式接近与起床连通性共用同一净空求路，起点由实际角色位置提供。
func bedside_path(start: Vector2, goal: Vector2) -> Array:
	return _clear_route(start, goal, Vector2(bed_position.x, bed_position.z), bed_yaw)


func _route_to_door(start: Vector2, bed_center: Vector2, yaw: float) -> Array:
	return _clear_route(start, Vector2(0.0, 3.25), bed_center, yaw)


func _clear_route(start: Vector2, goal: Vector2, bed_center: Vector2, yaw: float) -> Array:
	var direct := [Vector3(start.x, 0.0, start.y), Vector3(goal.x, 0.0, goal.y)]
	if route_query.is_valid():
		var route: Array = route_query.call(start, goal)
		if route.is_empty():
			return []
		if _route_points_clear(route, bed_center, yaw):
			return route
	elif _route_points_clear(direct, bed_center, yaw):
		return direct
	var step := BEDSIDE_ROUTE_STEP
	var origin := Vector2(-2.2, -2.2)
	var size := Vector2i(45, 65)
	var start_cell := Vector2i(roundi((start.x - origin.x) / step), roundi((start.y - origin.y) / step))
	var goal_cell := Vector2i(roundi((goal.x - origin.x) / step), roundi((goal.y - origin.y) / step))
	if not _route_cell_open(start_cell, origin, step, bed_center, yaw) or not _route_cell_open(goal_cell, origin, step, bed_center, yaw):
		return []
	var pending: Array[Vector2i] = [start_cell]
	var visited := {start_cell: start_cell}
	var index := 0
	while index < pending.size():
		var cell := pending[index]
		index += 1
		if cell == goal_cell:
			var path: Array = [Vector3(goal.x, 0.0, goal.y)]
			while true:
				var at := origin + Vector2(cell) * step
				path.push_front(Vector3(at.x, 0.0, at.y))
				if cell == start_cell:
					break
				cell = visited[cell]
			path.push_front(Vector3(start.x, 0.0, start.y))
			return path if _route_points_clear(path, bed_center, yaw) else []
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + delta
			if next.x < 0 or next.x >= size.x or next.y < 0 or next.y >= size.y or visited.has(next):
				continue
			if not _route_cell_open(next, origin, step, bed_center, yaw):
				continue
			visited[next] = cell
			pending.append(next)
	return []


func _route_points_clear(route: Array, bed_center: Vector2, yaw: float) -> bool:
	for index in route.size():
		var point: Vector3 = route[index]
		if not _route_point_open(Vector2(point.x, point.z), bed_center, yaw):
			return false
		if index == 0:
			continue
		var previous: Vector3 = route[index - 1]
		var length := previous.distance_to(point)
		var samples := maxi(1, ceili(length / BEDSIDE_ROUTE_STEP))
		for sample in range(1, samples):
			var middle := previous.lerp(point, float(sample) / float(samples))
			if not _route_point_open(Vector2(middle.x, middle.z), bed_center, yaw):
				return false
	return true


func _route_cell_open(cell: Vector2i, origin: Vector2, step: float, bed_center: Vector2, yaw: float) -> bool:
	return _route_point_open(origin + Vector2(cell.x, cell.y) * step, bed_center, yaw)


func _route_point_open(point: Vector2, bed_center: Vector2, yaw: float) -> bool:
	if not _inside_walk_domain(point, body_radius_local() + BEDSIDE_ROUTE_MARGIN):
		return false
	for item in FIXED_FOOTPRINTS:
		if str(item.name) == "门口通道":
			continue
		var footprint := Rect2(item.center - item.half, item.half * 2.0)
		if footprint.grow(body_radius_local() + BEDSIDE_ROUTE_MARGIN).has_point(point):
			return false
	if not _circle_clear_obb(point, bed_center, yaw, BED_HALF, body_radius_local() + BEDSIDE_ROUTE_MARGIN):
		return false
	return true


## 床边站人的位置：从安全候选中按四边固定优先级选择。没有候选时不制造
## 一个「夹回后落进床内」的点；新布局拒绝，旧档不挪床，回到受保护的前厅入口。
func bedside_point() -> Vector3:
	var candidates := bedside_candidates()
	if candidates.is_empty():
		return Vector3(0.0, 0.0, 3.25)
	var point: Vector2 = candidates[0].point
	return Vector3(point.x, bed_position.y, point.y)


func facing_yaw() -> float:
	var candidates := bedside_candidates()
	if candidates.is_empty():
		return 0.0
	return float(candidates[0].yaw)


func to_dict() -> Dictionary:
	return {"version": VERSION,
		"bed": {"position": [bed_position.x, bed_position.y, bed_position.z], "yaw": bed_yaw},
		"inside": inside}


func from_dict(data: Dictionary) -> void:
	var bed: Dictionary = data.get("bed", {})
	var pos: Array = bed.get("position", [])
	var target := DEFAULT_BED
	if pos.size() == 3:
		target = Vector3(float(pos[0]), 0.0, float(pos[2]))
	bed_yaw = float(bed.get("yaw", DEFAULT_YAW))
	# 注册表先调用 validate_snapshot；已接受的边界值不得在恢复时再次夹改。
	bed_position = target
	inside = bool(data.get("inside", false))
	changed.emit()


## 存档校验：床必须在房间里、不能压住固定陈设。`inside` 只是标记，不校验场景。
func validate_snapshot(data: Dictionary) -> String:
	if int(data.get("version", 0)) != VERSION:
		return "room: unsupported version"
	var bed: Variant = data.get("bed")
	if not bed is Dictionary:
		return "room: bed is not an object"
	var pos: Variant = bed.get("position")
	if not pos is Array or (pos as Array).size() != 3:
		return "room: bed position must be 3 numbers"
	for value in pos:
		if not (value is float or value is int) or not is_finite(float(value)):
			return "room: bed position must be finite"
	var yaw: Variant = bed.get("yaw")
	if not (yaw is float or yaw is int) or not is_finite(float(yaw)):
		return "room: bed yaw must be finite"
	if not data.get("inside") is bool:
		return "room: inside must be a bool"
	var at := Vector2(float(pos[0]), float(pos[2]))
	var limits := bed_limits(float(yaw))
	if not _within_limits(at, limits):
		return "room: bed is outside the room"
	if _overlap_reason(at, float(yaw)) != "":
		return "room: bed overlaps fixed furnishing"
	return ""
