@tool
extends "res://src/world/zone_scene.gd"
## SEA-ROOM 房间壳。
##
## 走的是和海上区块同一套接口（`walk_areas` / `area_at` / `pick_walk` / `landing_points`），
## 所以「在房间里点地面走路」「交互判定」「存档位置校验」都不需要另开一条通道 ——
## 房间只是又一个区块，`zone_id="room"`。
##
## 这里只管房间自己的几何关系：地板高度、入口/醒来站位、剖切、床铺布局落地。
## 过场与显隐归 `room_controller`；床的摆放真值归 `room_service`。

const CUTAWAY = preload("res://src/room/room_cutaway.gd")

## 进入房间后玩家出现的位置：玻璃前厅里，正对着门。先站在这儿再走进屋。
const ENTRY_LOCAL := Vector3(0.0, 0.0, 3.25)
## 门内一步（醒来、从外面放回室内时的干净落点）。
const INNER_LOCAL := Vector3(0.0, 0.0, 1.95)

## 玻璃前厅的顶构件名（Blender 组件里的对象名）。它们和天花一样属于「顶面」，
## 相机从上方看时必须一起收起，否则斜玻璃顶会把整个室内挡掉。
const PORCH_ROOF_NAMES := ["前厅玻璃顶", "前厅檐口"]

## 前厅各件的朝外法线。前厅不是「一面墙」，是四片带法线的面：
## 正面（+Z）、东西两侧（±X）。它们和房间的墙走同一套规则 ——
## 相机在哪一侧就收哪一片。用「整排按 Z 阈值收」的写法在转镜头时会出错：
## 相机转到侧后方时，正面玻璃被收了、两侧玻璃却还在，
## 于是有一片半透明的暗玻璃斜插在房间中央（实测截图里就是这样）。
## 值 = [朝外法线, 该面到房间中心的距离]。距离必须按实际尺寸给 ——
## 剖切判据是「相机越过这面墙没有」，用房间墙的 2.5 米套到 1.8 米进深的前厅上，
## 侧玻璃就几乎永远收不掉。
##   · 正面在 z≈+2.70（前厅从 +2.66 到 +4.48，正面玻璃贴着靠内那一端）；
##   · 东西两侧玻璃在 x≈±1.72。
const PORCH_NORMALS := {
	"前厅正面玻璃": [Vector3(0.0, 0.0, 1.0), 2.70],
	"前厅门洞立框": [Vector3(0.0, 0.0, 1.0), 2.70],
	"前厅裙墙": [Vector3(0.0, 0.0, 1.0), 2.70],
	"前厅上圈梁": [Vector3(0.0, 0.0, 1.0), 2.70],
	"前厅立柱": [Vector3(0.0, 0.0, 1.0), 2.70],
	"前厅玻璃_东": [Vector3(1.0, 0.0, 0.0), 1.72],
	"前厅玻璃_西": [Vector3(-1.0, 0.0, 0.0), 1.72],
	# 侧圈梁是细长白杆，贴着玻璃内侧。不跟着收的话，镜头一低就从左下角
	# 斜着横过整个房间（实测截图里那根白条）。
	"前厅侧圈梁_172": [Vector3(1.0, 0.0, 0.0), 1.72],
	"前厅侧圈梁_-172": [Vector3(-1.0, 0.0, 0.0), 1.72],
}

const WALLS := {
	"Shell/WallWindow": Vector3(0.0, 0.0, -1.0),
	"Shell/WallDoor": Vector3(0.0, 0.0, 1.0),
	# 门框与门扇跟着前墙一起收：前墙藏起来之后，光留一圈门框就是悬在空中的白框。
	"Shell/Door": Vector3(0.0, 0.0, 1.0),
	"Shell/WallEast": Vector3(1.0, 0.0, 0.0),
	"Shell/WallWest": Vector3(-1.0, 0.0, 0.0),
}

var service: Node
var camera: Camera3D
## 每个碰撞体自己的层/掩码，进出房间时整体开关（见 set_active）。
var _bodies: Array = []
## 房间里的可交互物（床）。必须在进屋时明确登记 —— 只遍历「已经在组里」的节点
## 会把已经退出组的那些永远留在组外，床就再也点不到了。
var _interactables: Array = []
var bed: Node3D
var _cutaway: Node3D


func _ready() -> void:
	# 站立面高度直接取本节点的世界高度：房间摆在世界哪个位置都可以，
	# 不用在场景文件和装配文件里各写一遍同一个数字（两处不一致时最难查）。
	var areas := get_node_or_null("WalkAreas")
	if areas != null:
		for child in areas.get_children():
			if "surface_y" in child:
				child.surface_y = global_position.y
	super._ready()
	bed = get_node_or_null("Furnishings/Bed")
	for body in find_children("*", "CollisionObject3D", true, false):
		_bodies.append({"node": body,
			"layers": Vector2i(body.collision_layer, body.collision_mask)})
	for node in find_children("*", "", true, false):
		if node.has_method("focus_position") and node.has_method("interact"):
			_interactables.append(node)
	_cutaway = get_node_or_null("Cutaway")
	if _cutaway != null and not Engine.is_editor_hint():
		var entries: Array = []
		for path in WALLS:
			var wall := get_node_or_null(path)
			if wall != null:
				entries.append({"node": wall, "normal": WALLS[path]})
		var roofs: Array = []
		var ceiling := get_node_or_null("Shell/Ceiling")
		if ceiling != null:
			roofs.append(ceiling)
		var porch := get_node_or_null("Shell/Porch")
		if porch != null:
			for node in porch.find_children("*", "Node3D", true, false):
				var label := String(node.name)
				if label.begins_with("前厅顶椽"):
					roofs.append(node)
					continue
				var is_roof := false
				for prefix in PORCH_ROOF_NAMES:
					if label.begins_with(prefix):
						roofs.append(node)
						is_roof = true
						break
				if is_roof:
					continue
				for prefix in PORCH_NORMALS:
					if label.begins_with(prefix):
						var face: Array = PORCH_NORMALS[prefix]
						entries.append({"node": node, "normal": face[0], "offset": face[1],
							"margin": CUTAWAY.PORCH_MARGIN, "porch": true})
						break
		_cutaway.configure(camera, entries, roofs, 2.75)


## 房间在世界里的开关。
##
## 三件事必须一起做，缺一件都会在室外留下痕迹：
##   1. 隐藏几何并停掉处理；
##   2. 退出交互组 —— 否则站在甲板上会点得到 12 米高处的床；
##   3. **关掉碰撞层** —— 静态体的碰撞注册在物理服务器上，跟 `visible` 无关。
##      房间挂载在 `World/Interior`，它的地面碰撞体在屋外仍然存在；
##      以后只要有人在那个高度有可走面，就会撞到一层看不见的地板。
func set_active(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for node in _interactables:
		if not is_instance_valid(node):
			continue
		if on:
			if not node.is_in_group("interactable"):
				node.add_to_group("interactable")
		elif node.is_in_group("interactable"):
			node.remove_from_group("interactable")
	for body in find_children("*", "CollisionObject3D", true, false):
		for entry in _bodies:
			if entry.node == body:
				var layers: Vector2i = entry.layers
				body.set_deferred("collision_layer", layers.x if on else 0)
				body.set_deferred("collision_mask", layers.y if on else 0)
				break
	if on and _cutaway != null:
		_cutaway.refresh()


func set_camera(cam: Camera3D) -> void:
	camera = cam
	if _cutaway != null:
		_cutaway.camera = cam
		_cutaway.refresh()


func is_active() -> bool:
	return visible


## 固定机位：从玻璃前厅一侧斜上方看进屋里。
## 相机在房顶以上 → 天花收起；在南侧 → 前墙收起（见 room_cutaway）。
## 进房间时的默认机位。玩家之后可以右键拖动绕房间转、滚轮拉近拉远
## （见 `OrbitCam.orbit_only`），这里只定「一进来看到什么」。
##
## 距离 14.4 米、视点偏 +Z（0.55）：5×5 米的房间在 31° FOV 下，
## 镜头再近一点四角就顶到画面边缘、前厅地板被切掉一半；视点若钉在房间正中，
## 门前那块地板同样会被下缘切断，读起来像房间悬空。距离上下限 8–24 留两头手感。
func camera_pose() -> Dictionary:
	return {
		"target": to_global(Vector3(0.0, 0.70, 0.55)),
		"distance": 14.4,
		"dir": Vector3(0.06, 0.72, 0.69).normalized(),
	}


func entry_position() -> Vector3:
	return to_global(ENTRY_LOCAL)


func inner_position() -> Vector3:
	return to_global(INNER_LOCAL)


func wake_position() -> Vector3:
	if service == null:
		return inner_position()
	var local: Vector3 = service.bedside_point()
	return to_global(local)


func center_position() -> Vector3:
	return global_position + Vector3(0.0, 1.0, 0.0)


## 把布局状态落到场景上。床是唯一可搬动的家具，其余陈设固定。
func apply_layout() -> void:
	if bed == null or service == null:
		return
	bed.apply_layout(service.bed_position, service.bed_yaw)


## 床铺的交互点给一个「走得到」的站位：床侧空地，随床一起转。
func bed_approach_points() -> Array:
	if service == null:
		return []
	var local: Vector3 = service.bedside_point()
	return [to_global(local)]
