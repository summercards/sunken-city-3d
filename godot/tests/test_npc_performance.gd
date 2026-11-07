extends SceneTree
## 小场景fixture，不实例化Main；通过run_verification的npc-performance入口执行。
const Presenter = preload("res://src/npc/npc_world_presenter.gd")
const Rooftop = preload("res://src/npc/npc_rooftop_anchors.gd")
const Service = preload("res://src/npc/npc_service.gd")
const Catalog = preload("res://src/npc/npc_catalog.gd")
var checks := 0
var failures := 0
var world
var service
var zone
var provider
var ground
var clock := Clock.new()

class Clock extends RefCounted:
	var value := {"day": 1, "hour": 12.0, "weather": "clear"}
	var movement_enabled := false
	func query() -> Dictionary: return value.duplicate()
	func enabled() -> bool: return movement_enabled and not value.get("sleeping", false)

class SmallGround extends Node3D:
	var active := true
	var ground_space
	var surface_y := 0.0
	var span_min := -1.0
	var span_max := 1.0
	var body_radius := 0.0
	var rects: Array = [Rect2(-100, -100, 200, 200)]
	var polygons: Array = []
	var surface_triangles := PackedVector3Array()
	var physical_surface_triangles := PackedVector3Array()
	var open_surface_junctions: Array = []
	var projections := 0
	var paths := 0
	func surface_point(point: Vector3) -> Vector3:
		projections += 1
		var local := to_local(point)
		if not active or not rects[0].has_point(Vector2(local.x, local.z)): return Vector3.INF
		return to_global(Vector3(local.x, surface_y, local.z))
	func path_between(start: Vector3, goal: Vector3) -> Array:
		paths += 1
		return [start, goal]

class SmallSpace extends Node3D:
	var revision := 0
	var ground
	func rebuild() -> void: revision += 1
	func area_at(point: Vector3, _tolerance: float):
		return ground if ground.surface_point(point).is_finite() else null

class SmallZone extends Node3D:
	var ground_space
	var zone_id := "fixture_roof"

class CountingService extends Service:
	var serializations := 0
	var queries := 0
	func to_dict() -> Dictionary:
		serializations += 1
		return super.to_dict()
	func npc_snapshot(id: String) -> Dictionary:
		queries += 1
		return super.npc_snapshot(id)

class OldProvider extends Node3D:
	var entries := {}
	var snapshots := 0
	var aliases := 0
	func anchor_snapshot() -> Dictionary:
		snapshots += 1
		return entries.duplicate(true)
	func resolve_anchor(id: String) -> Dictionary:
		aliases += 1
		return entries.get(Rooftop.ALIASES.get(id, id), {}).duplicate()

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-performance] ", label)

func settle() -> void:
	for id in world.actors:
		var route: Dictionary = world._routes[id]
		if not route.target.is_empty() and world.actor(id).visible:
			world.actor(id).global_position = route.target.position
			route.path = []

func poll() -> void:
	world._physics_process(0.5)

func run() -> void:
	zone = SmallZone.new()
	root.add_child(zone)
	var areas := Node3D.new()
	areas.name = "WalkAreas"
	zone.add_child(areas)
	ground = SmallGround.new()
	ground.name = "Walk_rooftop_ranch_access"
	areas.add_child(ground)
	var space := SmallSpace.new()
	zone.add_child(space)
	space.ground = ground
	ground.ground_space = space
	zone.ground_space = space
	provider = Rooftop.new()
	zone.add_child(provider)
	var index := 0
	for row in Catalog.all():
		var station := Node3D.new()
		station.name = row.residence_id
		station.position.x = index * 5.0
		station.set_meta("npc_id", row.id)
		if row.id == "npc_hua_yi": station.set_meta("work_anchor_id", "anchor_flower_shop")
		if row.id == "npc_bao_he": station.set_meta("work_anchor_id", "anchor_general_store")
		provider.add_child(station)
		for kind in Rooftop.KINDS:
			var marker := Marker3D.new()
			marker.name = kind.capitalize()
			marker.position.z = Rooftop.KINDS.find(kind) * 0.5
			station.add_child(marker)
		index += 1
	service = CountingService.new()
	check(service.configure(clock.query).ok, "注入纯时钟端口")
	var durable: Dictionary = service._state.duplicate(true)
	world = Presenter.new()
	root.add_child(world)
	check(world.configure(service, provider, clock.query, clock.enabled).ok, "小fixture配置七居民")
	world.set_physics_process(false)
	check(world.performance_metrics().anchor_snapshots == 1, "首次七居民同步只采一次35锚点")
	check(provider.anchor_snapshot().size() == 35, "35个作者Marker均有支撑")
	var metrics: Dictionary = world.performance_metrics()
	var projections: int = ground.projections
	var before_usec := Time.get_ticks_usec()
	for repeat in 120:
		world.notify_world(clock.query())
		world.sync_world(clock.query())
	check(world.performance_metrics().sync_executed == metrics.sync_executed, "120次同帧通知及sync不重建日程")
	check(world.performance_metrics().anchor_snapshots == metrics.anchor_snapshots and ground.projections == projections, "重复sync零快照零投影")
	print("[npc-performance] 120 notify+sync usec=", Time.get_ticks_usec() - before_usec)
	settle()
	projections = ground.projections
	for step in 24: world._physics_process(1.0 / 60.0)
	check(ground.projections == projections, "idle每physics不调用surface_point")
	metrics = world.performance_metrics()
	var support_metrics: Dictionary = provider.performance_metrics()
	clock.value.hour = 12.0001
	poll()
	check(world.performance_metrics().sync_executed == metrics.sync_executed, "同分钟同规则段不重建")
	check(world.performance_metrics().pathfinding == metrics.pathfinding, "同段不寻路")
	check(provider.performance_metrics().support_projections == support_metrics.support_projections, "35锚点支撑复用缓存")
	check(world.performance_metrics().state_queries == metrics.state_queries + 7, "每0.5秒只查询七份居民状态")
	clock.value.hour = 12.02
	world.sync_world(clock.query())
	check(world.performance_metrics().sync_executed == metrics.sync_executed + 1, "实际分钟变化执行日程")
	check(world.performance_metrics().pathfinding == metrics.pathfinding, "分钟变化目标不变不寻路")
	_boundaries()
	_changes()
	_pause_restore(durable)
	_legacy()
	check(service.serializations == 0, "同步与签名从不调用to_dict")
	print("[npc-performance] metrics=", world.performance_metrics(), " anchors=", provider.performance_metrics())
	world.free()
	zone.free()
	service = null
	print("[npc-performance] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _boundaries() -> void:
	clock.value.hour = 21.4999
	world.sync_world(clock.query())
	check(world._routes.npc_luo_yan.action != "rest", "21:30前仍为傍晚日程")
	clock.value.hour = 21.5
	world.sync_world(clock.query())
	for id in world.actors: check(world._routes[id].target.kind == "rest", "21:30精确进入本家rest " + id)
	clock.value.hour = 5.9999
	world.sync_world(clock.query())
	clock.value.hour = 6.0
	world.sync_world(clock.query())
	check(world._routes.npc_luo_yan.action == "sort_tools", "06:00精确退出rest")
	# 检测索引必须覆盖任意from/to及条件边界，不能仅取整分钟。
	var row: Dictionary = world._rows.npc_luo_yan
	row.schedule.append({"from": 12.001, "to": 12.002, "anchor": row.home_anchor, "action": "fixture", "conditions": {"hour_from": 12.0012, "hour_to": 12.0018}})
	world._index_boundaries()
	for boundary in [12.001, 12.0012, 12.0018, 12.002]:
		clock.value.hour = boundary - 0.0000001
		world.sync_world(clock.query())
		var before: int = world.performance_metrics().sync_executed
		clock.value.hour = boundary
		world.sync_world(clock.query())
		check(world.performance_metrics().sync_executed == before + 1, "分钟内任意精确边界执行同步 " + str(boundary))
	row.schedule.pop_back()
	world._index_boundaries()
	for hour in [10.0, 17.0, 21.5, 6.0]:
		clock.value.hour = hour - 0.00001
		world.sync_world(clock.query())
		var before: int = world.performance_metrics().sync_executed
		clock.value.hour = hour
		world.sync_world(clock.query())
		check(world.performance_metrics().sync_executed == before + 1, "正式规则from/to实时触发 " + str(hour))

## 按正式事件依赖及第一条合法分支构造可追溯快照，不绕过严格codec。
func _record_event(state: Dictionary, id: String) -> void:
	if state.seen_events.has(id): return
	var event: Dictionary = Catalog.get_event(id)
	for parent in event.conditions.get("events", []): _record_event(state, str(parent))
	for request_id in event.conditions.get("requests", []):
		var request: Dictionary = Catalog.get_request(str(request_id))
		_record_event(state, str(request.source_event))
		state.request_states[request_id].merge({"status": "completed", "completed_day": 1, "result_tag": request.result_tag}, true)
	for npc_id in event.npc_ids: state.graph.met[npc_id] = true
	var choices := {}
	var effects: Array = [event.get("effects", {})]
	var page_id: String = event.pages[0].id
	while page_id != "":
		for i in event.pages.size():
			var page: Dictionary = event.pages[i]
			if page.id != page_id: continue
			page_id = str(page.get("next", event.pages[i + 1].id if i + 1 < event.pages.size() else ""))
			if page.has("choices"):
				var choice: Dictionary = page.choices[0]
				choices[page.id] = choice.id
				state.choice_flags[id + ":" + page.id] = choice.id
				page_id = choice.next
				effects.append(choice.get("effects", {}))
			break
	state.seen_events[id] = {"day": 1, "choices": choices}
	for effect in effects:
		for edge in effect.get("edges", {}): state.graph.edge_deltas[edge] += effect.edges[edge]
		for request_id in effect.get("requests", []):
			state.request_states[request_id] = {"status": "open", "source_event": id, "opened_day": 1}

func _changes() -> void:
	clock.value.hour = 18.0
	clock.value.weather = "rain"
	world.sync_world(clock.query())
	check(world._routes.npc_luo_yan.action == "sew_sails", "天气直接sync实时生效")
	clock.value.weather = "clear"
	world.notify_world(clock.query())
	world._physics_process(0.49)
	check(world._routes.npc_luo_yan.action == "sew_sails", "notify不在半秒期限前重建日程")
	world._physics_process(0.01)
	check(world._routes.npc_luo_yan.action == "watch_routes", "天气notify后0.5秒内生效")
	clock.value.day = 7
	clock.value.hour = 12.0
	world.sync_world(clock.query())
	check(world._routes.npc_luo_yan.action == "check_ferry", "日期星期变化立即生效")
	clock.value.day = 1
	clock.value.hour = 18.0
	world.sync_world(clock.query())
	var saved: Dictionary = service._state.duplicate(true)
	var changed: Dictionary = saved.duplicate(true)
	changed.graph.met.npc_luo_yan = true
	changed.graph.affinity.npc_luo_yan = 500
	check(service.from_dict(changed).ok, "合法读入关系变化")
	poll()
	check(world._routes.npc_luo_yan.action == "teach_knots", "无revision关系变化0.5秒检出")
	_record_event(changed, "relation_old_route")
	check(service.from_dict(changed).ok, "合法读入剧情变化")
	poll()
	check(world._routes.npc_luo_yan.action == "share_route_log", "剧情变化0.5秒检出")
	check(service.from_dict(saved).ok, "还原测试关系状态")
	clock.value.hour = 12.0
	world.sync_world(clock.query(), true)
	settle()
	var marker: Marker3D = provider.get_node("residence_dock_workshop/Work")
	var before: Vector3 = world._routes.npc_luo_yan.target.position
	marker.position.z += 0.25
	var snapshots: int = world.performance_metrics().anchor_snapshots
	poll()
	check(world._routes.npc_luo_yan.target.position.distance_to(before) > 0.2, "手摆Marker变化0.5秒刷新")
	check(world.performance_metrics().anchor_snapshots == snapshots + 1, "Marker变动批次仍只采一次")
	settle()
	before = world._routes.npc_luo_yan.target.position
	zone.position.x += 0.4
	poll()
	check(world._routes.npc_luo_yan.target.position.distance_to(before) > 0.3, "根global_transform变动0.5秒刷新")
	marker.set_meta("active", false)
	poll()
	check(world._routes.npc_luo_yan.fallback and world._routes.npc_luo_yan.anchor_id == "residence_dock_workshop", "anchor active失效返回住所")
	marker.set_meta("active", true)
	poll()
	check(world._routes.npc_luo_yan.anchor_id == "residence_dock_workshop_work", "anchor恢复重新求路")
	ground.active = false
	poll()
	check(not world.actor("npc_luo_yan").visible and world._routes.npc_luo_yan.path.is_empty(), "walk active失效隐藏并停止")
	ground.active = true
	poll()
	check(world.actor("npc_luo_yan").visible, "walk恢复不被支撑缓存掩盖")
	settle()
	var projections: int = provider.performance_metrics().support_projections
	ground.rects[0] = Rect2(-1, -1, 2, 2)
	poll()
	check(provider.performance_metrics().support_projections > projections, "原地修改surface数组使缓存失效")
	check(provider.anchor_snapshot().size() < 35, "surface收缩剔除无支撑站点")
	ground.rects[0] = Rect2(-100, -100, 200, 200)
	poll()

func _pause_restore(durable: Dictionary) -> void:
	check(service._state == durable, "日程与场景刷新不修改任何durable状态")
	clock.movement_enabled = true
	settle()
	var body = world.actor("npc_luo_yan")
	var before: Vector3 = body.global_position
	check(world.open_npc("npc_luo_yan").ok, "保留面板会话入口")
	var after_meet: Dictionary = service._state.duplicate(true)
	check(world.panel.session.command("talk").ok, "保留对白状态")
	clock.value.sleeping = true
	world.notify_world(clock.query())
	world._physics_process(0.01)
	check(not world.is_modal() and not service.dialogue_state().active and body.global_position == before, "睡眠立即取消对白且不移动")
	clock.value.sleeping = false
	world.notify_world(clock.query())
	paused = true
	world._physics_process(0.01)
	check(body.global_position == before and not body.get_node("NpcInteractable").can_interact(), "暂停保留停止与交互门禁")
	paused = false
	var executed: int = world.performance_metrics().sync_executed
	world.refresh_after_restore()
	check(world.performance_metrics().sync_executed == executed + 1 and body.global_position == before, "恢复强制同步且不瞬移")
	check(body.get_node("NpcInteractable").can_interact(), "恢复世界交互")
	check(service._state == after_meet, "睡眠暂停和恢复不额外结算会话")

func _legacy() -> void:
	var legacy := OldProvider.new()
	root.add_child(legacy)
	legacy.entries = provider.anchor_snapshot()
	for entry in legacy.entries.values(): entry.erase("support_validated")
	var ports = preload("res://src/npc/npc_world_ports.gd").new()
	ports.configure(legacy, Callable(), Callable())
	ports.begin_batch()
	var row: Dictionary = Catalog.get_npc("npc_luo_yan")
	var first: Dictionary = ports.resolve("anchor_dock", row, clock.query(), "work")
	for repeat in 120: ports.resolve("anchor_dock", row, clock.query(), "work")
	check(not first.is_empty() and legacy.snapshots == 1 and legacy.aliases == 1, "旧fakeprovider兼容且共享alias解析")
	check(ports.metrics.anchor_projections == 35, "旧provider一批35个锚点各校验一次而非每NPC每rule")
	ports.begin_batch()
	ports.resolve("anchor_dock", row, clock.query(), "work")
	check(legacy.aliases == 1, "旧provider的alias ID跨批次复用")
	legacy.entries.erase("residence_dock_workshop_work")
	ports.begin_batch()
	check(ports.resolve("anchor_dock", row, clock.query(), "work").is_empty(), "alias缓存不保留已失效站位")
	legacy.free()
