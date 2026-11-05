extends Node
## SEA-ROOM 进出房间的会话流程。
##
## 一次进出 = 同一枚圆形黑幕过场（SEA-SLEEP 那枚，只是**不写字**）：
## 合拢 → 全黑时换场景/换机位 → 向外打开。过场期间输入与行走全部锁住，
## 重复点击只执行一次（`busy`）。
##
## 分工：
##   · 床的摆放真值与「在不在屋里」—— `room_service`（唯一所有者）
##   · 房间几何、站位、剖切 —— `room_scene`
##   · 世界显隐、机位接管、时钟不动 —— 本文件
## 不碰时间、不碰经济、不写存档。

signal entered
signal exited

var busy := false
var service: Node
var room: Node3D
## ActorController 是 RefCounted（不是 Node），这里不能标 Node 类型。
var actor_controller
var cam: Node3D
var curtain: CanvasLayer
var hud: Node
var state: Node
## 进屋时要收起来的世界节点（室外内容），出去时按原样恢复。
var outdoor_nodes: Array = []
## 世界环境节点。进屋后把背景切成纯黑 —— 房间是室内，窗和玻璃前厅外面
## 不该有天空盒（那是「站在屋外看天」的读法）。环境光仍然取自天空辐照，
## 所以只换背景、不换光照，房间的明暗与昼夜曲线一点不动。
var world_environment: WorldEnvironment
## 出门后站回的位置（太阳房入口前的地毯边）。
var exit_position := Vector3.ZERO
var exit_yaw := 0.0

var _hidden: Array = []
var _outdoor_camera := {}
## 室外背景的原始设置。用 -1 表示「没接管过」，避免出门时把值写回去当成改动。
var _outdoor_background_mode := -1
var _outdoor_background_color := Color.BLACK


func is_inside() -> bool:
	return service != null and bool(service.inside)


func enter(instant := false) -> void:
	if busy or not is_instance_valid(room) or service == null:
		return
	if bool(service.inside):
		return
	busy = true
	if not instant:
		await curtain.cover_blank()
	_begin_inside()
	if not instant:
		await curtain.uncover_blank()
	busy = false
	entered.emit()


## 读档：世界位置已按室外恢复好，这里直接把人、场景和机位拉到室内，不再播过场。
## 和 `enter()` 的区别只有一点 —— 它不看 `service.inside` 的提前返回，因为
## 读档时那个标记本来就已经是 true 了。
func resync_inside() -> void:
	if service == null or not bool(service.inside):
		return
	if busy:
		return
	busy = true
	_begin_inside()
	busy = false
	entered.emit()


## 读档 / 回标题：世界已经由别处恢复好，这里只把**视觉**拉回室外 ——
## 不挪角色、不发信号、不改区块。和 `exit()` 的区别是它不负责「人怎么出去」。
##
## 存在的理由：`inside` 是存档里的一个字段，读一份「在屋外存下的档」时它会变成
## false，但场景里还留着进屋那一刻的状态 —— 世界节点全隐藏、背景全黑。
## 没有这一步，读档后就站在一片漆黑里，而且再也恢复不了。
func resync_outside() -> void:
	if service == null:
		return
	room.set_active(false)
	_hide_outdoor(false)
	_restore_outdoor_environment()
	if hud != null:
		hud.set_room_mode(false)


func exit(instant := false) -> void:
	if busy or service == null or not bool(service.inside):
		return
	busy = true
	if not instant:
		await curtain.cover_blank()
	_begin_outside()
	if not instant:
		await curtain.uncover_blank()
	busy = false
	exited.emit()


func _begin_inside() -> void:
	_store_outdoor_camera()
	_hide_outdoor(true)
	_apply_interior_environment()
	room.set_active(true)
	room.set_camera(cam)
	room.service = service
	room.apply_layout()
	state.enter_zone("room")
	var at: Vector3 = room.entry_position()
	actor_controller.restore_pose({"mode": 0, "player": [at.x, at.y, at.z]})
	_apply_room_camera()
	if hud != null:
		hud.set_room_mode(true)
	service.inside = true


func _begin_outside() -> void:
	room.set_active(false)
	_hide_outdoor(false)
	_restore_outdoor_environment()
	state.enter_zone("zone1")
	var at := exit_position
	actor_controller.restore_pose({"mode": 0, "player": [at.x, at.y, at.z]})
	if is_instance_valid(actor_controller.actor):
		actor_controller.actor.rotation.y = exit_yaw
	_restore_outdoor_camera()
	if hud != null:
		hud.set_room_mode(false)
	service.inside = false


## 室内机位：绕房间转，而不是钉死一个角度。
##
## `orbit_only` 而不是 `pose_lock` —— 房间只有 5×5 米，玩家想看清床、窗、地毯、
## 门口，必须能自己转过去。所以这里放开**旋转与远近**（右键拖动 / 滚轮），
## 同时把视点钉在房间上（不允许平移）：平移一开，随手一拖镜头就飘出房间，
## 四周全是黑的，那不是自由而是迷路。
##
## `suspend_follow()` 仍然要调：房间里不该跟着角色跑，房间才是主体。
func _apply_room_camera() -> void:
	var pose: Dictionary = room.camera_pose()
	cam.pose_lock = false
	cam.orbit_only = true
	cam.suspend_follow()
	cam.target = pose.target
	cam.distance = pose.distance
	cam.orbit_dir = pose.dir
	cam.refresh()
	cam.apply_pose()


func _store_outdoor_camera() -> void:
	if cam == null:
		return
	_outdoor_camera = {"target": cam.target, "distance": cam.distance,
		"orbit_dir": cam.orbit_dir, "fov": cam.cam_fov}


func _restore_outdoor_camera() -> void:
	cam.pose_lock = false
	cam.orbit_only = false
	if not _outdoor_camera.is_empty():
		cam.target = _outdoor_camera.target
		cam.distance = _outdoor_camera.distance
		cam.orbit_dir = _outdoor_camera.orbit_dir
		cam.refresh()
	cam.restore_follow(actor_controller.actor)
	cam.target = actor_controller.actor.global_position + Vector3.UP * 0.7
	cam.apply_pose()


## 醒来在房间里：只挪角色与机位，不换场景（换场景在黑幕里由 sleep 自己完成时间与位置的语义）。
func wake_in_room() -> void:
	if service == null:
		return
	var at: Vector3 = room.wake_position()
	actor_controller.restore_pose({"mode": 0, "player": [at.x, at.y, at.z]})
	if is_instance_valid(actor_controller.actor):
		actor_controller.actor.rotation.y = service.facing_yaw()
	room.apply_layout()
	_apply_room_camera()


## 室内背景：不画天空盒，画面里没有天空的地方就是纯黑。
##
## 只动 `background_mode` / `background_color` 两项：`ambient_light_source` 仍是
## 天空（房间照旧被日照与环境光点亮），fog 密度本来就是 0。天空盒资源的辐照
## 还在，所以屋里的白天/傍晚/夜里和外面同步 —— 变的只有「窗外看不看得见东西」。
func _apply_interior_environment() -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var env: Environment = world_environment.environment
	if _outdoor_background_mode < 0:
		_outdoor_background_mode = env.background_mode
		_outdoor_background_color = env.background_color
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 1.0)


func _restore_outdoor_environment() -> void:
	if _outdoor_background_mode < 0:
		return
	if is_instance_valid(world_environment) and world_environment.environment != null:
		var env: Environment = world_environment.environment
		env.background_mode = _outdoor_background_mode
		env.background_color = _outdoor_background_color
	_outdoor_background_mode = -1


func _hide_outdoor(hidden: bool) -> void:
	if hidden:
		_hidden.clear()
		for node in outdoor_nodes:
			if not is_instance_valid(node):
				continue
			_hidden.append({"node": node, "visible": node.visible,
				"process": node.process_mode})
			node.visible = false
	else:
		for entry in _hidden:
			var node = entry.node
			if not is_instance_valid(node):
				continue
			node.visible = bool(entry.visible)
			node.process_mode = int(entry.process)
		_hidden.clear()
