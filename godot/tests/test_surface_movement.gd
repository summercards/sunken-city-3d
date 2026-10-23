extends SceneTree
const BoatScript = preload("res://src/navigation/boat.gd")
const Ground = preload("res://src/navigation/ground_path.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var state: Node = root.get_node("GameState")
	var landings: Array = []
	for zone in main._zone_nodes.values():
		for point in zone.landing_points():
			var data: Dictionary = point.data()
			var pos: Vector3 = point.stand_position()
			check(point.ground().contains_world(pos.x, pos.z), "上岸点在所属地面 " + zone.zone_id)
			check(absf(pos.y - point.ground().surface_y) < 0.001, "上岸高度与地面一致")
			check(main._is_open_water(data.boatPark[0], data.boatPark[2]), "泊位在可航水域 " + zone.zone_id + data.id)
			landings.append({"zone": zone.zone_id, "data": data})
	for plot in main.farm_field.plots:
		var zone: Node3D = main._zone_nodes[plot.zone_id]
		var landing: Node3D = zone.landing_point("main")
		check(plot.scene_file_path == "res://scenes/props/farm_cell.tscn" and plot.get_parent().scene_file_path == "res://scenes/props/farm_plot.tscn", "种植物件是独立场景 " + plot.plot_id)
		check(not landing.ground().path_between(landing.stand_position(), plot.global_position).is_empty(), "种植点可达 " + plot.plot_id)
	var shape: Array = [PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,1),Vector2(1,1),Vector2(1,4),Vector2(0,4)])]
	check(not Ground.clear_segment(shape,Vector2(3,.5),Vector2(.5,3)), "凹形地面不能跨空")
	var around := Ground.route(shape,Vector2(3,.5),Vector2(.5,3))
	check(around.size() >= 3, "凹形地面绕角")
	shape.append(PackedVector2Array([Vector2(10,0),Vector2(11,0),Vector2(11,1),Vector2(10,1)]))
	check(Ground.route(shape,Vector2(.5,.5),Vector2(10.5,.5)).is_empty(), "不连通地面拒绝路径")
	state.enter_zone("zone1")
	state.landing_id = "main"
	state.set_mode(state.Mode.ON_BOAT)
	var home: Node3D = main._zone_nodes.zone1.landing_point("main")
	var farm: Node3D = main.farm_field.find("home_plot")
	check(main._start_walk(home.ground(), farm.global_position), "从泊位走到菜箱")
	check(main.player.global_position.distance_to(home.stand_position()) < .001, "上岸落点不是点击目标")
	var guard := 0
	while main._walking and guard < 2000:
		main._update_walk(1.0/60.0)
		check(home.ground().contains_world(main.player.global_position.x, main.player.global_position.z), "行走全程在地面内")
		guard += 1
	check(guard < 2000 and main.player.global_position.distance_to(farm.global_position) < .01, "木桥连接可达")
	var departing := {"done": false}
	check(main._depart(func() -> void: departing.done = true), "回泊位上船")
	check(not departing.done and main.player.get_parent() != main.boat, "未走回上岸点前不能瞬移上船")
	guard = 0
	while main._walking and guard < 2000:
		main._update_walk(1.0/60.0)
		guard += 1
	check(departing.done and main.player.get_parent() == main.boat, "走回后执行上船")
	var dock_hit := {"zone":"zone1", "landing":"main", "name":"主泊位"}
	main._select_landing(dock_hit)
	main._update_walk(1.0/60.0)
	check(main.player.get_parent() != main.boat, "点击当前泊位上岸")
	main._select_landing(dock_hit)
	main._update_walk(1.0/60.0)
	check(main.player.get_parent() == main.boat, "再次点击泊位回船")
	var parked: Vector3 = main.boat.position
	main.boat.position.x += 20.0
	check(not main._start_walk(home.ground(),home.stand_position()),"船未靠泊不能远程上岸")
	main.boat.position = parked
	var vessel: Node3D = BoatScript.new()
	root.add_child(vessel)
	vessel.set_process(false)
	vessel.segment_clear = main._water_segment_clear
	var arrivals := {"count":0}
	vessel.arrived.connect(func(_z,_l) -> void: arrivals.count += 1)
	var total_routes := 0
	for source in landings:
		for dest in landings:
			if source == dest:
				continue
			var a := Vector3(source.data.boatPark[0],1.12,source.data.boatPark[2])
			var b := Vector3(dest.data.boatPark[0],1.12,dest.data.boatPark[2])
			main.boat.place_at(a,source.data.boatYaw)
			var path: Array = main.plan_route_to(b.x,b.z)
			var label: String = source.zone + source.data.id + " -> " + dest.zone + dest.data.id
			check(path.size() >= 2, "有安全航路 " + label)
			if path.size() < 2: continue
			vessel.place_at(a,source.data.boatYaw)
			vessel.sail_to(b,dest.data.boatYaw,dest.zone,dest.data.id,path)
			var before: int = arrivals.count
			var max_step := 0.0
			var max_turn := 0.0
			guard = 0
			var safe := true
			while vessel.starts_sailing() and guard < 15000:
				var old: Vector3 = vessel.position
				var yaw: float = vessel.rotation.y
				vessel._steer(1.0/60.0)
				max_step = maxf(max_step,old.distance_to(vessel.position))
				max_turn = maxf(max_turn,absf(angle_difference(yaw,vessel.rotation.y)))
				safe = safe and main._is_open_water(vessel.position.x,vessel.position.z)
				guard += 1
			check(guard < 15000 and arrivals.count == before+1, "抵达一次 " + label)
			check(Vector2(vessel.position.x-b.x,vessel.position.z-b.z).length() < .02, "靠泊无位置跳变 " + label)
			check(max_step <= BoatScript.SPEED/60.0+.0001 and max_turn <= BoatScript.TURN_RATE/60.0+.0001, "速度和角速度连续 " + label)
			check(safe,"实际轨迹全程在水域 " + label)
			total_routes += 1
			print("[surface] ",label," frames=",guard," max_step=",max_step)
	# 中途改向不重置速度，手动停船不强制拧回起航朝向。
	vessel.segment_clear = Callable()
	vessel.place_at(Vector3(50,1.12,30),0.0)
	vessel.sail_to_point(Vector3(50,1.12,0))
	for i in 180: vessel._steer(1.0/60.0)
	var speed: float = vessel._vel
	var pos: Vector3 = vessel.position
	vessel.sail_to_point(Vector3(65,1.12,10))
	check(is_equal_approx(speed,vessel._vel) and vessel.position == pos,"改道保留速度与位置")
	guard=0
	while vessel.starts_sailing() and guard<5000:
		vessel._steer(1.0/60.0)
		guard+=1
	check(guard<5000 and vessel._dock_left < .001,"手动停船不掉头")
	# 同一转弯航路在不同帧率下，终点和耗时应接近。
	var durations: Array[float] = []
	for fps in [30, 60, 120]:
		vessel.place_at(Vector3(0,1.12,0),PI)
		vessel.sail_to_point(Vector3(12,1.12,12),[Vector2.ZERO,Vector2(0,12),Vector2(12,12)])
		guard=0
		while vessel.starts_sailing() and guard < fps * 60:
			vessel._steer(1.0 / fps)
			guard+=1
		durations.append(float(guard)/fps)
		check(guard < fps*60 and Vector2(vessel.position.x-12,vessel.position.z-12).length()<.02,"不同帧率正常抵达 %d" % fps)
	check(durations.max()-durations.min()<.08,"30/60/120 FPS 耗时一致")
	print("[surface] frame_rate_seconds=",durations)
	# 动态禁止下一步后必须停船，不能直接越过。
	vessel.place_at(Vector3(0,1.12,0),PI)
	vessel.sail_to_point(Vector3(0,1.12,10))
	vessel.segment_clear = func(_a: Vector2,_b: Vector2) -> bool: return false
	var blocked_pos: Vector3 = vessel.position
	vessel._steer(1.0/60.0)
	check(not vessel.starts_sailing() and vessel.position == blocked_pos,"移动中受阻停船")
	check(main.plan_route_to(1000,1000).is_empty(),"不可达目标不退回穿岸直线")
	vessel.queue_free()
	main.queue_free()
	await process_frame
	print("[surface] routes=",total_routes," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
