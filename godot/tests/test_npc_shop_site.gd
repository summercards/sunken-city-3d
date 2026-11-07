extends SceneTree
## 仅通过run_verification的npc-shop-site入口执行，真实浮店加静态天台小fixture。
const Shop = preload("res://scenes/facilities/floating_shop.tscn")
const RoofStations = preload("res://scenes/npc/rooftop_npc_stations.tscn")
const Hub = preload("res://src/npc/npc_anchor_hub.gd")
const Presenter = preload("res://src/npc/npc_world_presenter.gd")
const Service = preload("res://src/npc/npc_service.gd")
const Ports = preload("res://src/npc/npc_world_ports.gd")
const Walk = preload("res://src/navigation/walk_area.gd")
const Space = preload("res://src/navigation/ground_space.gd")
var checks := 0
var failures := 0
var clock := Clock.new()
var world
var shop
var roof
var hub
var service

class Clock extends RefCounted:
	var value := {"day": 1, "hour": 12.0, "weather": "clear"}
	func query() -> Dictionary: return value.duplicate()
	func enabled() -> bool: return not value.get("sleeping", false)

class RoofZone extends Node3D:
	var ground_space
	var zone_id := "rooftop_ranch"

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-shop-site] ", label)

func settle() -> void:
	for id in world.actors:
		var route: Dictionary = world._routes[id]
		if not route.target.is_empty() and world.actor(id).visible:
			world.actor(id).global_position = route.target.position
			route.path = []

func run() -> void:
	roof = RoofZone.new()
	roof.position = Vector3(-80, -55.92, -20)
	root.add_child(roof)
	var areas := Node3D.new()
	areas.name = "WalkAreas"
	roof.add_child(areas)
	var ground := Walk.new()
	ground.name = "Walk_rooftop_ranch_access"
	ground.surface_y = roof.global_position.y + 60.05
	ground.span_min = ground.surface_y - 0.3
	ground.span_max = ground.surface_y + 0.3
	ground.rects = [Rect2(-20, -20, 40, 40)]
	ground.body_radius = 0.0
	areas.add_child(ground)
	var space := Space.new()
	roof.add_child(space)
	space.configure([ground])
	roof.ground_space = space
	var stations := RoofStations.instantiate()
	roof.add_child(stations)
	shop = Shop.instantiate()
	# 根变换仅取作者TSCN，不用设计参考位代替用户摆位。
	var scene_text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var authored_shop := scene_text.get_slice('[node name="floating_shop"', 1).get_slice("\n\n", 0)
	var found_pose := false
	for line in authored_shop.split("\n"):
		if line.begins_with("transform = "):
			shop.transform = str_to_var(line.trim_prefix("transform = "))
			found_pose = true
	check(found_pose, "读取现有用户手摆根，不加载或改写Main场景")
	root.add_child(shop)
	shop.set_physics_process(false)
	shop.set_motion_time(0.0)
	await physics_frame
	hub = Hub.new()
	root.add_child(hub)
	var sea_stations = shop.get_node("Objects/NpcStations")
	hub.configure([stations, sea_stations])
	var anchors: Dictionary = hub.anchor_snapshot()
	check(stations.anchor_snapshot().size() == 30, "天台六站30锚点")
	check(sea_stations.anchor_snapshot().size() == 5 and anchors.size() == 35, "浮店五锚点聚合为35")
	check(not stations.has_node("residence_general_store"), "天台不留阿店五Marker")
	check(hub.home_labels().residence_general_store == "东南海上商店 · 阿店", "位置标签来自provider且不宣称住房")
	var names := ["船老大", "豆豆", "阿海", "木头叔", "灯伯", "小花"]
	for index in stations.get_child_count():
		check(str(stations.get_child(index).get_meta("home_label")).contains(names[index]), "六人位置名称 " + names[index])
	var home: Dictionary = anchors.residence_general_store
	for entry in sea_stations.anchor_snapshot().values():
		check(entry.ground == shop.walk_areas[0] and entry.zone_id == "sea_supply", "真实sea_supply Area " + entry.kind)
		check(entry.position.distance_to(entry.ground.surface_point(entry.position)) < 0.002, "五Marker落实际甲板 " + entry.kind)
		check(not entry.ground.path_between(home.position, entry.position).is_empty(), "柜台附近五点连通 " + entry.kind)
		var local: Vector3 = shop.to_local(entry.position)
		check(absf(local.x) > 0.45 and local.z < 0.0, "避开正门中轴及玩家通路 " + entry.kind)
		check(entry.position.distance_to(shop.get_node("Objects/SupplyCounter").global_position) < 2.0, "五点靠近现有Counter " + entry.kind)
	service = Service.new()
	var configured: Dictionary = service.configure(clock.query)
	check(configured.ok, "NPC服务注入独立时钟：" + str(configured.get("reason", "")))
	var ports := Ports.new()
	ports.configure(hub, clock.query, clock.enabled)
	ports.begin_batch()
	for row in service.roster():
		var target: Dictionary = ports.resolve("anchor_home_dock", row, clock.query(), "social")
		check(target.get("zone_id") == ("sea_supply" if row.id == "npc_bao_he" else "rooftop_ranch"), "共享码头别名按owner解析 " + row.id)
		var shared: Dictionary = ports.resolve("anchor_general_store", row, clock.query(), "arrange_shared_shelf")
		check(shared.get("zone_id") == ("sea_supply" if row.id == "npc_bao_he" else "rooftop_ranch"), "共享货架不会带其他六人下海 " + row.id)
	world = Presenter.new()
	root.add_child(world)
	check(world.configure(service, hub, clock.query, clock.enabled).ok, "Presenter注入聚合provider")
	world.set_physics_process(false)
	for row in service.roster():
		check(world.actor(row.id).visible, "七人正常出生不藏人 " + row.id)
		check(world._routes[row.id].target.zone_id == ("sea_supply" if row.id == "npc_bao_he" else "rooftop_ranch"), "七人当前场地 " + row.id)
	settle()
	var durable: Dictionary = service.to_dict()
	var baseline: Dictionary = world.performance_metrics()
	var roof_metrics: Dictionary = stations.performance_metrics()
	var sea_metrics: Dictionary = sea_stations.performance_metrics()
	var revision: int = shop.ground_space.revision
	var local_actor: Vector3 = shop.get_node("Objects").to_local(world.actor("npc_bao_he").global_position)
	var start := Time.get_ticks_usec()
	var max_error := 0.0
	var roof_position: Vector3 = world.actor("npc_luo_yan").global_position
	for frame in 240:
		shop.set_motion_time((frame + 1) / 60.0)
		world._physics_process(1.0 / 60.0)
		var expected: Vector3 = shop.get_node("Objects").to_global(local_actor)
		max_error = maxf(max_error, expected.distance_to(world.actor("npc_bao_he").global_position))
		check(world.actor("npc_bao_he").get_node("NpcInteractable").global_position.distance_to(expected) < 0.003, "热点逐physics跟随支撑")
	check(max_error < 0.003, "连续升沉没有半秒跳变")
	check(world.actor("npc_luo_yan").global_position == roof_position, "海店heave不挪动天台角色")
	check(shop.ground_space.revision == revision, "heave不rebuild或rebake")
	check(world.performance_metrics().pathfinding == baseline.pathfinding, "240帧heave零新增pathfinding")
	check(world.performance_metrics().sync_executed == baseline.sync_executed, "heave不触发七人全量日程batch")
	check(stations.performance_metrics().support_projections == roof_metrics.support_projections, "静态天台30Marker缓存保留")
	check(sea_stations.performance_metrics().support_projections == sea_metrics.support_projections, "浮店局部Marker缓存不随heave失效")
	print("[npc-shop-site] heave240_usec=", Time.get_ticks_usec() - start, " max_error=", max_error, " metrics=", world.performance_metrics(), " roof=", stations.performance_metrics(), " sea=", sea_stations.performance_metrics())
	# 在途航点同量平移，不重新求路，也不逐帧重选目标。
	var route: Dictionary = world._routes.npc_bao_he
	route.path = [route.target.position + Vector3(0.4, 0, 0)]
	var waypoint: Vector3 = route.path[0]
	var origin: Vector3 = shop.get_node("Objects").global_position
	shop.set_motion_time(4.3)
	world._carry_supports()
	check(route.path[0].distance_to(waypoint + shop.get_node("Objects").global_position - origin) < 0.002, "在途路径刚性平移")
	route.path = []
	clock.value.hour = 8.0
	world.sync_world(clock.query())
	var paths_before_walk: int = world.performance_metrics().pathfinding
	var walked_before: float = route.distance_walked
	var walking_supported := true
	var max_step := 0.0
	var max_support_error := 0.0
	for frame in 90:
		shop.set_motion_time(4.3 + frame / 60.0)
		await physics_frame
		world._carry_supports()
		var previous: Vector3 = world.actor("npc_bao_he").global_position
		world._step("npc_bao_he", 1.0 / 60.0)
		var actual: Vector3 = world.actor("npc_bao_he").global_position
		var support: Vector3 = route.target.ground.surface_point(actual)
		walking_supported = walking_supported and support.is_finite() and absf(support.y - actual.y) < 0.01
		if support.is_finite(): max_support_error = maxf(max_support_error, absf(support.y - actual.y))
		max_step = maxf(max_step, Vector2(actual.x - previous.x, actual.z - previous.z).length())
	print("[npc-shop-site] walk_error=", max_support_error, " walk_step=", max_step, " walked=", route.distance_walked - walked_before)
	check(walking_supported and world.actor("npc_bao_he").visible, "真实CharacterMotor在升沉甲板全程有支撑")
	check(route.distance_walked > walked_before + 0.2 and route.path.is_empty(), "阿店实际走到柜台附近目标而非瞬移")
	check(max_step <= 2.0 / 60.0 + 0.001, "升沉中行走仍限速2m/s")
	check(world.performance_metrics().pathfinding == paths_before_walk, "在途升沉不重新route")
	clock.value.hour = 12.0
	world.sync_world(clock.query())
	settle()
	var paths_before_marker: int = world.performance_metrics().pathfinding
	var marker: Marker3D = sea_stations.get_node("residence_general_store/Work")
	marker.position.x -= 0.1
	world._physics_process(0.5)
	check(world.performance_metrics().pathfinding == paths_before_marker + 1, "局部Marker修改只重寻阿店路线")
	settle()
	marker.set_meta("active", false)
	world._physics_process(0.5)
	check(world._routes.npc_bao_he.anchor_id == "residence_general_store" and world.actor("npc_bao_he").visible, "失效work回本店home而不是天台")
	marker.set_meta("active", true)
	world._physics_process(0.5)
	check(world._routes.npc_bao_he.anchor_id == "anchor_general_store", "work恢复回柜台")
	settle()
	var sea_ground = shop.walk_areas[0]
	sea_ground.active = false
	world._physics_process(0.01)
	check(not world.actor("npc_bao_he").visible and not world.actor("npc_bao_he").get_node("NpcInteractable").can_interact(), "失支撑当帧隐藏角色与热点")
	shop.set_motion_time(5.5)
	world._physics_process(0.5)
	check(world.actor("npc_hua_yi").visible, "失海店支撑不隐藏小花")
	sea_ground.active = true
	world._physics_process(0.5)
	check(world.actor("npc_bao_he").visible, "支撑恢复重显阿店")
	settle()
	var before: Vector3 = world.actor("npc_bao_he").global_position
	paused = true
	world._physics_process(0.01)
	check(world.actor("npc_bao_he").global_position == before and not world.actor("npc_bao_he").get_node("NpcInteractable").can_interact(), "暂停不移动且交互关闭")
	paused = false
	check(service.from_dict(durable).ok, "from_dict保留严格恢复")
	var executed: int = world.performance_metrics().sync_executed
	world.refresh_after_restore()
	check(world.performance_metrics().sync_executed == executed + 1, "恢复强制刷新日程")
	clock.value.hour = 22.0
	world.sync_world(clock.query())
	for row in service.roster():
		check(world._routes[row.id].target.kind == "rest", "各owner夜间rest " + row.id)
	check(service.to_dict() == durable, "站位和升沉不修改NpcState")
	world.free()
	hub.free()
	shop.free()
	roof.free()
	service = null
	print("[npc-shop-site] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
