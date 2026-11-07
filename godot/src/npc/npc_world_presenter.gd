extends Node3D
## 只投影居民与日程；住所、时钟、库存和经营功能均由装配层注入。
signal npc_interaction_requested(npc_id: String)
signal action_requested(npc_id: String, action_id: String)
signal modal_changed(active: bool)
signal schedule_fallback(npc_id: String, requested_anchor: String, fallback_anchor: String, reason: String)
const ActorScript = preload("res://src/npc/npc_actor.gd")
const InteractableScript = preload("res://src/npc/npc_interactable.gd")
const PanelScript = preload("res://src/npc/npc_panel.gd")
const Ports = preload("res://src/npc/npc_world_ports.gd")
const WALK_SPEED := 2.0
const ARRIVAL := 0.035
var service
var actors: Dictionary = {}
var panel
var _ports = Ports.new()
var _world: Dictionary = {}
var _routes: Dictionary = {}
var _rows: Dictionary = {}
var _sync_elapsed := 0.0
const SYNC_INTERVAL := 0.5
var _boundaries: Array = [0.0, 6.0, 21.5, 24.0]
var _last_signature: Array = []
var _last_anchors: Dictionary = {}
var _last_check_frame := -1
var _state_signature: Array = []
var _watch_events := false
var _watch_edges := false
var _state_dirty := true
var _metrics := {"sync_requests": 0, "sync_executed": 0, "notify_requests": 0, "state_queries": 0, "support_carries": 0, "dynamic_support_checks": 0}

func _mark_state_dirty() -> void:
	_state_dirty = true

func _watch_service(connecting: bool) -> void:
	if service == null: return
	for entry in service.get_signal_list():
		if str(entry.name) not in ["npc_met", "affinity_changed", "relation_edge_changed", "dialogue_completed", "request_completed", "npc_request_opened"]: continue
		var callback := Callable(self, "_mark_state_dirty").unbind(entry.args.size())
		if connecting and not service.is_connected(entry.name, callback): service.connect(entry.name, callback)
		elif not connecting and service.is_connected(entry.name, callback): service.disconnect(entry.name, callback)

## 高频通知只保留小型世界值；不解析日程、不采锚点、不触碰持久状态。
func notify_world(world: Dictionary) -> void:
	_metrics.notify_requests += 1
	_world = world.duplicate()

func performance_metrics() -> Dictionary:
	var result := _metrics.duplicate()
	result.merge(_ports.metrics)
	return result

func _index_boundaries() -> void:
	_boundaries = [0.0, 6.0, 21.5, 24.0]
	_watch_events = false
	_watch_edges = false
	for row in _rows.values():
		for rule in row.get("schedule", []):
			_boundaries.append(float(rule.from))
			_boundaries.append(float(rule.to))
			var conditions: Dictionary = rule.get("conditions", {})
			for key in ["hour_from", "hour_to"]:
				if conditions.has(key): _boundaries.append(float(conditions[key]))
			_watch_events = _watch_events or conditions.has("events")
			_watch_edges = _watch_edges or conditions.has("edge")
	_boundaries.sort()

func _schedule_signature() -> Array:
	var hour := float(_world.get("hour", 8.0))
	var segment := 0
	for boundary in _boundaries:
		if hour >= boundary: segment += 1
	return [_world.get("day", 1), floori(hour * 60.0), segment, _world.get("weather", "clear")]

func _poll_service_state() -> Array:
	var result: Array = []
	for id in _rows:
		_metrics.state_queries += 1
		var state: Dictionary = service.npc_snapshot(str(id))
		var runtime: Dictionary = state.get("runtime", {})
		var requests: Array = []
		for request in state.get("requests", []):
			requests.append([request.id, request.get("runtime", {}).get("status", "")])
		result.append([runtime.get("met", false), runtime.get("affinity", 0), requests])
	if _watch_edges: result.append(service.relationship_graph())
	if _watch_events:
		var completed: Array = []
		for event in service.list_events():
			if event.get("completed", false): completed.append(event.id)
		result.append(completed)
	return result

func _ready() -> void:
	# 暂停时仍能撤销会话，但绝不执行物理移动。
	process_mode = Node.PROCESS_MODE_ALWAYS

func configure(npc_service, residence: Node3D, world_query: Callable = Callable(), enabled_query: Callable = Callable()) -> Dictionary:
	cancel_session()
	for body in actors.values():
		remove_child(body)
		body.queue_free()
	actors.clear()
	_routes.clear()
	_rows.clear()
	_watch_service(false)
	service = npc_service
	_watch_service(true)
	_world = {}
	_last_signature = []
	_last_anchors = {}
	_last_check_frame = -1
	_state_signature = []
	_state_dirty = true
	_sync_elapsed = 0.0
	for key in _metrics: _metrics[key] = 0
	_ports.configure(residence, world_query, enabled_query)
	if service == null or not is_instance_valid(residence) or not residence.has_method("anchor_snapshot"):
		return {"ok": false, "reason": "需要NPC服务及正式住所锚点端口"}
	if panel == null:
		panel = PanelScript.new()
		panel.name = "NpcPanel"
		add_child(panel)
		panel.action_requested.connect(_on_action)
		panel.modal_changed.connect(_on_modal)
	panel.configure(service, _ports.home_labels())
	for row in service.roster():
		var id := str(row.id)
		_rows[id] = row
		var body = ActorScript.new()
		body.name = "Npc_" + id
		add_child(body)
		body.configure(row)
		body.set_grounded_motion(false)
		body.visible = false
		var interact = InteractableScript.new()
		interact.name = "NpcInteractable"
		body.add_child(interact)
		interact.configure(id, str(row.display_name), str(row.get("shop_id", "")))
		interact.npc_requested.connect(open_npc)
		actors[id] = body
		_routes[id] = {"spawned": false, "path": [], "target": {}, "requested_anchor": "", "anchor_id": "", "action": "", "fallback": false, "reason": "", "stalled": 0.0, "distance_walked": 0.0}
	_index_boundaries()
	var clock: Variant = _ports.query("world")
	if clock is Dictionary: notify_world(clock)
	if not _world.is_empty(): sync_world(_world, true)
	return {"ok": true, "actors": actors.size()}

func sync_world(world: Dictionary, force := false) -> void:
	_metrics.sync_requests += 1
	_world = world.duplicate()
	if service == null: return
	var signature := _schedule_signature()
	var frame := Engine.get_physics_frames()
	if not force and not _state_dirty and signature == _last_signature and frame == _last_check_frame and _sync_elapsed < SYNC_INTERVAL: return
	_last_check_frame = frame
	_sync_elapsed = 0.0
	var state := _poll_service_state()
	_carry_supports()
	var available := _ports.begin_batch()
	var layout := _ports.layout_snapshot(available)
	var support_changed := _check_actor_support()
	var changed := force or _state_dirty or signature != _last_signature or state != _state_signature or layout != _last_anchors or support_changed
	_state_dirty = false
	_last_signature = signature
	_state_signature = state
	_last_anchors = layout.duplicate(true)
	if not changed: return
	_metrics.sync_executed += 1
	for id in _rows: _sync_npc(str(id))
	_refresh_interactions()

## 站定居民的支撑只在检测批次核对，绝不在每个physics帧遍历屋顶三角形。
func _check_actor_support() -> bool:
	var changed := false
	for id in actors:
		var route: Dictionary = _routes[id]
		if not route.spawned or route.target.is_empty(): continue
		var body = actors[id]
		if not _valid_anchor(route.target):
			if body.visible:
				_halt(str(id), "站立面失效", true)
				changed = true
			continue
		var support: Vector3 = route.target.ground.surface_point(body.global_position)
		if not support.is_finite() or absf(support.y - body.global_position.y) > 0.3:
			if body.visible:
				_halt(str(id), "失去地面支撑", true)
				changed = true
		elif not body.visible:
			changed = true
	return changed

func _sync_npc(id: String) -> void:
	var row: Dictionary = _rows[id]
	var available := _ports.anchors().duplicate()
	# 旧日程名由场地API按owner解释；不可保留别人的同名锚点掩盖失效。
	for rule in row.get("schedule", []): available.erase(str(rule.anchor))
	# NPC不拥有alias表，也不推测旧坐标。
	for rule in row.get("schedule", []):
		var resolved := _ports.resolve(str(rule.anchor), row, _world, str(rule.action))
		if _valid_anchor(resolved): available[str(rule.anchor)] = resolved
	var result: Dictionary = service.schedule_at(id, _world, available)
	if not result.get("ok", false):
		_report(id, "", "", str(result.get("reason", "日程无效")))
		_halt(id, str(result.get("reason", "日程无效")))
		return
	var route: Dictionary = _routes[id]
	var requested := str(result.get("requested_anchor", ""))
	var target := _ports.resolve(str(result.anchor_id), row, _world, str(result.action))
	var reason := ""
	if result.get("fallback", false): reason = "日程站点失效，返回住所"
	if not _valid_anchor(target):
		target = _ports.resolve(str(row.home_anchor), row, _world, "home_fallback")
		reason = "锚点失效，尝试住所"
	if not _valid_anchor(target):
		_report(id, requested, "", "住所锚点也不可用，停止并隐藏")
		_halt(id, "无可用站立面", true)
		return
	var body = actors[id]
	if not route.spawned:
		# 仅首次实例化从正式站位出生。读档只重新求路，不还原世界坐标。
		var home := _ports.resolve(str(row.home_anchor), row, _world, "home_fallback")
		if not _valid_anchor(home):
			_report(id, requested, "", "出生住所失效")
			return
		body.global_position = home.ground.surface_point(home.position)
		body.set_grounded_motion(true)
		body.visible = true
		route.spawned = true
	var unchanged: bool = route.anchor_id == str(target.anchor_id) and Ports.anchor_layout(route.target) == Ports.anchor_layout(target) and route.reason == reason and body.visible
	route.requested_anchor = requested
	route.action = str(result.action)
	if unchanged: return
	var support: Vector3 = target.ground.surface_point(body.global_position)
	if support.is_finite() and absf(support.y - body.global_position.y) < 0.3:
		body.visible = true
		if not body.grounded_motion_enabled: body.set_grounded_motion(true)
	var path := _ports.path(body.global_position, target)
	if path.is_empty():
		reason = "目标无可行路线且住所不可用，原地停止"
		var home := _ports.resolve(str(row.home_anchor), row, _world, "home_fallback")
		if _valid_anchor(home):
			path = _ports.path(body.global_position, home)
			target = home
		reason = "目标无可行路线，尝试返回住所" if not path.is_empty() else "住所也无路可达，原地停止"
	route.path = path
	route.target = target
	route.anchor_id = str(target.anchor_id)
	route.fallback = reason != ""
	route.reason = reason
	route.stalled = 0.0
	if reason != "": _report(id, requested, str(target.anchor_id), reason)

func _valid_anchor(anchor: Dictionary) -> bool:
	return Ports.valid_anchor(anchor)

func _enabled() -> bool:
	if not is_inside_tree() or get_tree().paused: return false
	if _world.get("paused", false) or _world.get("sleeping", false) or _world.get("player_indoors", false) or _world.get("dialogue_active", false): return false
	if service != null and not is_modal() and service.dialogue_state().get("active", false): return false
	var enabled: Variant = _ports.query("enabled")
	if enabled is bool: return enabled
	if enabled is Dictionary:
		return bool(enabled.get("enabled", true)) and not enabled.get("paused", false) and not enabled.get("sleeping", false) and not enabled.get("player_indoors", false) and not enabled.get("dialogue_active", false)
	return true

## 只对动态矩形支撑做廉价投影；静止天台不进入此逐帧分支。
func _carry_supports() -> void:
	if get_tree().paused: return
	for id in actors:
		var route: Dictionary = _routes[id]
		var target: Dictionary = route.target
		if not route.spawned or not target.has("support_frame"): continue
		var frame: Variant = target.support_frame
		var body = actors[id]
		if not _valid_anchor(target) or not is_instance_valid(frame):
			if body.visible: _halt(str(id), "移动支撑失效", true)
			continue
		var offset: Vector3 = frame.global_position - target.support_origin
		# 恢复时补偿缺失期间位移，仍由半秒检测决定是否重新显现。
		var hidden: bool = not body.visible
		if hidden: body.set_grounded_motion(true)
		body.carry_ground_support(offset)
		if not offset.is_zero_approx(): _metrics.support_carries += 1
		if hidden: body.set_grounded_motion(false)
		for index in route.path.size(): route.path[index] += offset
		target.position += offset
		target.support_origin = frame.global_position
		_metrics.dynamic_support_checks += 1
		var support: Vector3 = target.ground.surface_point(body.global_position)
		if not support.is_finite() or absf(support.y - body.global_position.y) > 0.3:
			_halt(str(id), "失去移动地面支撑", true)

func _physics_process(delta: float) -> void:
	if service == null: return
	if not get_tree().paused: _carry_supports()
	_sync_elapsed += delta
	if _sync_elapsed + 0.000001 >= SYNC_INTERVAL:
		var clock: Variant = _ports.query("world")
		sync_world(clock if clock is Dictionary else _world)
	var enabled := _enabled()
	if not enabled and is_modal(): cancel_session()
	_refresh_interactions()
	for id in actors:
		var body = actors[id]
		if not enabled or is_modal():
			_stop(body)
			continue
		_step(str(id), delta)

func _step(id: String, delta: float) -> void:
	var body = actors[id]
	var route: Dictionary = _routes[id]
	if not route.spawned or route.path.is_empty():
		_stop(body)
		return
	if not _valid_anchor(route.target):
		_report(id, str(route.requested_anchor), str(route.anchor_id), "站立面失效，原地停止")
		_halt(id, "站立面失效", true)
		return
	var ground = route.target.ground
	var support: Vector3 = ground.surface_point(body.global_position)
	if not support.is_finite() or absf(support.y - body.global_position.y) > 0.3:
		_report(id, str(route.requested_anchor), str(route.anchor_id), "当前位置失去地面支撑，停止并隐藏")
		_halt(id, "失去地面支撑", true)
		return
	while not route.path.is_empty() and body.global_position.distance_to(route.path[0]) <= ARRIVAL:
		route.path.pop_front()
	if route.path.is_empty():
		_stop(body)
		return
	var offset: Vector3 = route.path[0] - body.global_position
	var step: Vector3 = offset.limit_length(WALK_SPEED * delta)
	var point: Vector3 = ground.surface_point(body.global_position + step)
	if not point.is_finite():
		_report(id, str(route.requested_anchor), str(route.anchor_id), "路线跨越无地面区域，原地停止")
		_halt(id, "路线无支撑")
		return
	var motion: Dictionary = body.move_ground(point - body.global_position, delta)
	var moved: Vector3 = motion.moved
	var distance := Vector2(moved.x, moved.z).length()
	route.distance_walked += distance
	route.stalled = float(route.stalled) + delta if distance < 0.001 else 0.0
	body.walk_speed_ratio = clampf(distance / maxf(delta * WALK_SPEED, 0.0001), 0.0, 1.0)
	body.set_walking(distance > 0.001)
	if distance > 0.001: body.rotation.y = atan2(moved.x, moved.z)
	if route.stalled > 1.0:
		_report(id, str(route.requested_anchor), str(route.anchor_id), "CharacterMotor受阻，原地停止")
		_halt(id, "物理移动受阻")

func _stop(body) -> void:
	body.velocity = Vector3.ZERO
	body.walk_speed_ratio = 0.0
	body.set_walking(false)

func _halt(id: String, reason: String, hide_actor := false) -> void:
	var route: Dictionary = _routes[id]
	route.path = []
	route.reason = reason
	route.fallback = true
	_stop(actors[id])
	if hide_actor:
		actors[id].hide()
		actors[id].set_grounded_motion(false)

func _report(id: String, requested: String, fallback: String, reason: String) -> void:
	schedule_fallback.emit(id, requested, fallback, reason)
	actors[id].set_meta("npc_schedule_fallback", {"requested_anchor": requested, "fallback_anchor": fallback, "reason": reason})

func _refresh_interactions() -> void:
	var enabled := _enabled() and not is_modal()
	for id in actors:
		var body = actors[id]
		body.get_node("NpcInteractable").set_available(enabled and body.visible and _routes[id].spawned)

func open_npc(npc_id: String) -> Dictionary:
	if panel == null or not actors.has(npc_id) or not _enabled() or is_modal() or not actors[npc_id].visible:
		return {"ok": false, "reason": "当前不能交谈"}
	for body in actors.values(): _stop(body)
	var result: Dictionary = panel.open_npc(npc_id)
	_refresh_interactions()
	if result.get("ok", false): npc_interaction_requested.emit(npc_id)
	return result

func actor(npc_id: String):
	return actors.get(npc_id)

## 仅用于观察，不参与存档；持久状态仍只有NpcService。
func world_snapshot() -> Dictionary:
	var residents := {}
	for id in actors:
		var route: Dictionary = _routes[id]
		residents[id] = {"anchor_id": route.anchor_id, "requested_anchor": route.requested_anchor, "action": route.action,
			"fallback": route.fallback, "reason": route.reason, "spawned": route.spawned,
			"position": actors[id].global_position, "moving": not route.path.is_empty() and _enabled() and not is_modal(),
			"remaining_waypoints": route.path.size(), "distance_walked": route.distance_walked}
	return {"world": _world.duplicate(true), "residents": residents, "modal": is_modal(), "enabled": _enabled()}

func refresh_after_restore() -> void:
	cancel_session()
	for route in _routes.values():
		route.anchor_id = ""
		route.path = []
	var clock: Variant = _ports.query("world")
	sync_world(clock if clock is Dictionary else _world, true)

func cancel_session() -> void:
	if panel != null: panel.cancel_session()

func is_modal() -> bool:
	return panel != null and panel.is_modal()

func handle_input(event: InputEvent) -> bool:
	return panel != null and panel.handle_input(event)

func _on_action(npc_id: String, action_id: String) -> void:
	action_requested.emit(npc_id, action_id)

func _on_modal(active: bool) -> void:
	if active:
		for body in actors.values(): _stop(body)
	_refresh_interactions()
	modal_changed.emit(active)

func _exit_tree() -> void:
	cancel_session()
