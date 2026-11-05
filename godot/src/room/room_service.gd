extends Node
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

var bed_position := DEFAULT_BED
var bed_yaw := DEFAULT_YAW
var inside := false


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
	bed_position = Vector3(clamped.x, 0.0, clamped.y)
	bed_yaw = wrapf(yaw, -PI, PI)
	changed.emit()
	return {"ok": true, "position": bed_position, "yaw": bed_yaw, "clamped": clamped != asked}


## 离目标最近、又不压到固定陈设的落点。找不到返回 Vector2.INF。
func _nearest_free(center: Vector2, yaw: float, limits: Rect2) -> Vector2:
	for ring in 40:
		var radius := 0.10 + float(ring) * 0.05
		for i in 16:
			var candidate: Vector2 = center + Vector2.RIGHT.rotated(TAU * float(i) / 16.0) * radius
			if not limits.has_point(candidate):
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


## 床边站人的位置：床的长边外侧、偏床头一点。醒来的地方也用它。
func bedside_point() -> Vector3:
	var extent := bed_extent(bed_yaw)
	var local := Vector2(bed_position.x, bed_position.z) + Vector2(extent.x + 0.55, 0.15)
	local.x = clampf(local.x, -HALF + 0.45, HALF - 0.45)
	local.y = clampf(local.y, -HALF + 0.45, HALF - 0.45)
	return Vector3(local.x, bed_position.y, local.y)


func facing_yaw() -> float:
	# 床头朝 -Z 时 yaw=0；站人点在床的 +X 侧，面朝床（即朝 -X）。
	return -PI / 2.0


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
	var limits := bed_limits(bed_yaw)
	bed_position = Vector3(clampf(target.x, limits.position.x, limits.end.x), 0.0,
		clampf(target.z, limits.position.y, limits.end.y))
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
	if not limits.has_point(at):
		return "room: bed is outside the room"
	var center := Vector2(clampf(at.x, limits.position.x, limits.end.x),
		clampf(at.y, limits.position.y, limits.end.y))
	if _overlap_reason(center, float(yaw)) != "":
		return "room: bed overlaps fixed furnishing"
	return ""
