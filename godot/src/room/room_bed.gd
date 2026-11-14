@tool
extends "res://src/interaction/interactable.gd"
## SEA-ROOM 床铺：房间里的睡觉入口。
##
## 床是**可交互类物品**：位置与朝向由 `room_service` 拥有（将来「布置」功能改它），
## 本节点只负责把那份状态落到场景上、提供交互，并把「走过去站哪」报给上层。
## 遮挡体跟着节点一起走，所以床搬到哪里，角色就在哪里被挡住。

signal sleep_requested

## 床的占地半尺寸（米）。和 Blender 目录登记的实际包围盒一致：1.16 × 2.03。
const FOOTPRINT_HALF := Vector2(0.58, 1.015)
## 遮挡高度：床垫以上一点，角色撞不进去，视野不受影响。
const BLOCK_HEIGHT := 0.95

var body: StaticBody3D
var approach_path_query: Callable


func _on_ready() -> void:
	id = "room_bed"
	label = "床"
	verb = "睡到早上 06:00"
	priority = 6
	hold_time = 0.15
	focus_radius = 1.9
	# 热区锚点钉在本节点原点：床会搬动，用几何包围盒会把锚点留在旧位置一帧。
	focus_anchor = "node"
	_build_body()


func _build_body() -> void:
	if body != null or Engine.is_editor_hint():
		return
	body = preload("res://src/navigation/actor_collision_body.gd").new()
	body.name = "Block"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FOOTPRINT_HALF.x * 2.0, BLOCK_HEIGHT, FOOTPRINT_HALF.y * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, BLOCK_HEIGHT * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)


func apply_layout(at: Vector3, yaw: float) -> void:
	position = at
	rotation.y = yaw


func set_approach_points(points: Array) -> void:
	set_meta("approach_points", points)


## 可选公共端口：返回包含实际起点与候选终点的世界坐标净空路线。
func approach_path(start: Vector3, goal: Vector3) -> Array:
	return approach_path_query.call(start, goal) if approach_path_query.is_valid() else []


func interact(_actor: Node3D) -> Dictionary:
	sleep_requested.emit()
	return {"event": "sleep_requested"}
