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

const BodyScale = preload("res://src/avatar/avatar_dimensions.gd")

signal entered
signal exited

var busy := false
var busy_query: Callable
var _generation := 0
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
var _bed_wiring_ready := false


func _ready() -> void:
	call_deferred("_ensure_bedside_wiring")


func is_inside() -> bool:
	return service != null and bool(service.inside)


func enter(instant := false) -> void:
	if busy or (busy_query.is_valid() and busy_query.call()) or not is_instance_valid(room) or service == null:
		return
	if bool(service.inside):
		return
	_generation += 1
	var generation := _generation
	busy = true
	if not instant:
		await curtain.cover_blank()
	if generation != _generation: return
	_begin_inside()
	if generation != _generation: return
	if not instant:
		await curtain.uncover_blank()
	if generation != _generation: return
	busy = false
	entered.emit()


## 读档：世界位置已按室外恢复好，这里直接把人、场景和机位拉到室内，不再播过场。
## 和 `enter()` 的区别只有一点 —— 它不看 `service.inside` 的提前返回，因为
## 读档时那个标记本来就已经是 true 了。
func resync_inside() -> void:
	if service == null or not bool(service.inside):
		return
	cancel_transition()
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
	cancel_transition()
	if service == null:
		return
	room.set_active(false)
	_hide_outdoor(false)
	_restore_outdoor_environment()
	if cam.orbit_only: _restore_outdoor_camera()
	if hud != null:
		hud.set_room_mode(false)


func exit(instant := false) -> void:
	if busy or (busy_query.is_valid() and busy_query.call()) or service == null or not bool(service.inside):
		return
	_generation += 1
	var generation := _generation
	busy = true
	if not instant:
		await curtain.cover_blank()
	if generation != _generation: return
	_begin_outside()
	if generation != _generation: return
	if not instant:
		await curtain.uncover_blank()
	if generation != _generation: return
	busy = false
	exited.emit()


func cancel_transition() -> void:
	_generation += 1
	if busy and is_instance_valid(curtain): curtain.cancel_blank()
	busy = false


func _exit_tree() -> void:
	cancel_transition()


func _begin_inside() -> void:
	_ensure_bedside_wiring()
	if not cam.orbit_only: _store_outdoor_camera()
	if _hidden.is_empty(): _hide_outdoor(true)
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
	# 环绕的缩放区间是**世界米**，房间整体放大后要跟着放大 ——
	# 否则 1.5 倍的房间里，玩家一滚轮就能把镜头塞进床里。
	var zoom: Vector2 = room.orbit_zoom_range()
	cam.orbit_zoom_min = zoom.x
	cam.orbit_zoom_max = zoom.y
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
	# 缩放区间还给室外默认值（8–24 是室内基准，室外是 9–38）。
	cam.orbit_zoom_min = cam.ORBIT_ZOOM_MIN
	cam.orbit_zoom_max = cam.ORBIT_ZOOM_MAX
	if not _outdoor_camera.is_empty():
		cam.target = _outdoor_camera.target
		cam.distance = _outdoor_camera.distance
		cam.orbit_dir = _outdoor_camera.orbit_dir
		cam.refresh()
	cam.restore_follow(actor_controller.actor)
	cam.target = actor_controller.actor.global_position + Vector3.UP * BodyScale.CAMERA_FOCUS
	cam.apply_pose()


## 醒来在房间里：只挪角色与机位，不换场景（换场景在黑幕里由 sleep 自己完成时间与位置的语义）。
func wake_in_room() -> void:
	if service == null:
		return
	_ensure_bedside_wiring()
	if service.bedside_candidates().is_empty():
		actor_controller.notify("床边空间不足，已在安全的前厅入口醒来；请重新布置床铺")
	var at: Vector3 = room.wake_position()
	actor_controller.restore_pose({"mode": 0, "player": [at.x, at.y, at.z]})
	if is_instance_valid(actor_controller.actor):
		actor_controller.actor.rotation.y = service.facing_yaw()
	room.apply_layout()
	_apply_room_camera()


func _ensure_bedside_wiring() -> void:
	if service == null or room == null:
		return
	service.room_scale = room.global_basis.get_scale().x
	if not _bed_wiring_ready:
		if room.has_method("bed_approach_points"):
			service.route_query = func(start: Vector2, goal: Vector2) -> Array:
				var start_world := room.to_global(Vector3(start.x, 0.0, start.y))
				var goal_world := room.to_global(Vector3(goal.x, 0.0, goal.y))
				var area = room.area_at(start_world, 0.8)
				if area == null:
					return []
				var route: Array = area.path_between(start_world, goal_world)
				for index in route.size():
					route[index] = room.to_local(route[index])
				return route
			service.changed.connect(_refresh_bedside_points)
			_bed_wiring_ready = true
	_refresh_bedside_points()


func _refresh_bedside_points() -> void:
	if room == null or service == null:
		return
	var bed: Node3D = room.get_node_or_null("Furnishings/Bed")
	if bed == null:
		return
	var points: Array = []
	for candidate: Dictionary in service.bedside_candidates():
		var local: Vector2 = candidate.point
		points.append(room.to_global(Vector3(local.x, service.bed_position.y, local.y)))
	bed.set_approach_points(points)
	bed.approach_path_query = func(start: Vector3, goal: Vector3) -> Array:
		var local_start := room.to_local(start)
		var local_goal := room.to_local(goal)
		var route: Array = service.bedside_path(Vector2(local_start.x, local_start.z), Vector2(local_goal.x, local_goal.z))
		for index in route.size():
			route[index] = room.to_global(route[index])
		return route


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
			# 光隐藏不够：有些环境节点会**按时段自己把 visible 设回来**
			# （鸟群 `set_hour` 就是）。它们认这个接口，进屋时被抑制，
			# 出门时解除 —— 否则「在屋里睡到天亮」会有一群海鸥穿过卧室。
			if node.has_method("set_interior_hidden"):
				node.set_interior_hidden(true)
	else:
		for entry in _hidden:
			var node = entry.node
			if not is_instance_valid(node):
				continue
			if node.has_method("set_interior_hidden"):
				# 时段消费者拥有可见性；旧屋外快照不能盖掉当前已恢复的时刻。
				node.set_interior_hidden(false)
			else:
				node.visible = bool(entry.visible)
			node.process_mode = int(entry.process)
		_hidden.clear()
