extends SceneTree
## 正式 Main 夹具：不替换阻挡查询，不传送航行终点，不移动建筑。
const Nav = preload("res://src/navigation/water_navigation.gd")
const Blockers = preload("res://src/world/blocker_set.gd")
var checks := 0
var failures := 0
var main: Node
var ranch: Node3D
var arrivals := []
var blocked := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [rooftop-npc-access] ", label)
	return ok

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func hits(point: Vector3, shapes: Array) -> Array:
	var out := []
	for shape: Dictionary in shapes:
		var nav := Nav.new()
		nav.shape_query = func(): return [shape]
		if not nav.is_geometric_water(point.x, point.z): out.append(shape)
	return out

func pose(landing: Dictionary, zone: String) -> Dictionary:
	return {"zone":zone,"landing":"main","mode":0,"far_sea":false,
		"boat":[landing.boatPark[0],landing.boatPark[1],landing.boatPark[2],landing.boatYaw],"player":landing.landStand}

func run() -> void:
	if not check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/"), "Autoload 前隔离用户存档"):
		quit(1); return
	main = load("res://scenes/main.tscn").instantiate()
	main._autosave_on = false
	ranch = main.get_node("World/SeaStructures/rooftop_ranch")
	var authored: Transform3D = ranch.transform
	var model_transforms := {}
	for child in ranch.get_node("Models").get_children():
		if child is Node3D: model_transforms[child.name] = child.transform
	root.add_child(main)
	await frames(12)
	main.set_process(false)
	main.boat.set_process(false)
	main.boat.arrived.connect(func(zone, landing): arrivals.append([zone,landing]))
	main.boat.navigation_blocked.connect(func(): blocked += 1)
	var landing: Node3D = ranch.landing_point("main")
	var park: Vector3 = landing.get_node("BoatPark").global_position
	var stand: Vector3 = landing.stand_position()
	var shapes: Array = main._water_shapes()
	var old_park := ranch.to_global(Vector3(29.9,57.04,-2.1))
	var old_hits := hits(old_park,shapes)
	print("[rooftop-access-probe] old_park=",old_park," old_hits=",old_hits," landing=",landing.data()," new_hits=",hits(park,shapes))
	check(not old_hits.is_empty(), "诊断保留旧泊位冲突证据，不删旧远景阻挡掩盖问题")
	check(hits(park,shapes).is_empty(), "新泊位避开全部生产阻挡及0.9米船宽余量")
	check(absf(park.y-1.12)<0.01 and absf(stand.y-1.38)<0.01, "船仍在海面，岸点仍在原末段下平台")
	check(root.get_node("Zones").landing("rooftop_ranch","main") == landing.data(), "Zones使用场景回填泊位")
	check(main.validate_world_state(pose(landing.data(),"rooftop_ranch")) == "", "真实泊位通过生产世界存档校验")
	_check_geometry(landing)
	var home: Dictionary = main._zone_nodes.zone1.landing_point("main").data()
	var home_pose := pose(home,"zone1")
	if check(main.validate_world_state(home_pose)=="", "起点使用合法家园夹具"):
		main.restore_world_state(home_pose)
		await frames(2)
		main.hud.destination_pressed.emit("rooftop_ranch")
		if await _sail("rooftop_ranch"):
			check(main._landing_is_docked(), "真实 arrived 后天台泊位靠妥")
			check(main._toggle_boat_by_key(), "正式 E 命令从船上岸")
			await _walk_done(stand,"落脚原下平台")
			var roof := ranch.to_global(Vector3(0,ranch.ROOF_Y,6))
			var route: Array = landing.ground().path_between(stand,roof)
			print("[rooftop-access-walk-route] ",route)
			check(route.size()>=4, "上岸后仍经末段消防梯及原屋顶入口")
			if check(main.actor_controller.start_walk(landing.ground(),roof), "启动正式胶囊登顶"):
				await _walk_done(roof,"真实胶囊登上草皮")
				check(main.validate_world_state(main.capture_world_state())=="", "真实登顶状态仍可通过生产存档世界校验")
			var count := arrivals.size()
			main.hud.destination_pressed.emit("zone1")
			if await _sail("zone1"):
				check(arrivals.size()==count+1, "从楼顶返回原下平台上船后真实返航")
	check(blocked==0, "完整往返无 navigation_blocked")
	check(ranch.transform.is_equal_approx(authored), "保持 Main 手动 root 及旋转")
	for child in ranch.get_node("Models").get_children():
		if child is Node3D: check(child.transform.is_equal_approx(model_transforms[child.name]), "保持旧模型变换 "+str(child.name))
	check(ranch.get_node_or_null("NpcStations")!=null, "保留七 NPC 站位")
	main.queue_free()
	await frames(2)
	print("[rooftop-npc-access] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _sail(zone: String) -> bool:
	var count := arrivals.size()
	var started := false
	for i in 18000:
		main.actor_controller.tick(1.0/60.0)
		var before: Vector3 = main.boat.position
		main.boat._process(1.0/60.0)
		if main.boat.starts_sailing(): started=true
		if before.distance_to(main.boat.position)>0.06:
			return check(false,"航行不得以传送代替真实位移")
		if arrivals.size()>count and not main.boat.starts_sailing():
			print("[rooftop-access-arrival] ",arrivals.back()," ticks=",i," position=",main.boat.position)
			return check(started and arrivals.back()==[zone,"main"], "HUD真实航程抵达 "+zone)
		if i%60==0: await frames(1)
	return check(false,"HUD航行失败 "+zone+" toast="+main.hud._toast.text+" actor="+str(main.actor_controller.snapshot()))

func _walk_done(target: Vector3, label: String) -> bool:
	for i in 9000:
		main.actor_controller.tick(1.0/60.0)
		if not main.actor_controller.walking():
			return check(main.actor_controller.mode()==0 and main.player.global_position.distance_to(target)<0.3,label+" actual="+str(main.player.global_position))
		if i%60==0: await frames(1)
	return check(false,label+"超出步行预算")

func _check_geometry(landing: Node3D) -> void:
	var stand: Vector3 = landing.stand_position()
	var edge: Vector3 = landing.get_node("DockEdge").global_position
	var park: Vector3 = landing.get_node("BoatPark").global_position
	var local_stand := ranch.to_local(stand)
	var local_park := ranch.to_local(park)
	check(local_park.z < -3.0 and absf(local_park.x-local_stand.x)<0.01, "船靠下平台真实-Z侧，不借屋顶或水下梯上岸")
	check(edge.distance_to(stand)<stand.distance_to(park) and (edge-stand).normalized().dot((park-stand).normalized())>0.99, "dockEdge位于岸点与船位之间")
	var deck: Node3D = ranch.get_node("Models/ORF3_实例_stair_landing.022")
	var supported := false
	var rail_hits := []
	for mesh: MeshInstance3D in deck.find_children("*","MeshInstance3D",true,false):
		var faces := mesh.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var a: Vector3 = mesh.global_transform*faces[i]
			var b: Vector3 = mesh.global_transform*faces[i+1]
			var c: Vector3 = mesh.global_transform*faces[i+2]
			var hit = Geometry3D.ray_intersects_triangle(stand+Vector3.UP*0.06,Vector3.DOWN,a,b,c)
			if hit!=null and absf(hit.y-stand.y)<0.06: supported=true
			for height in [0.35,0.6,1.1]:
				for offset in [-0.22,0.0,0.22]:
					var start: Vector3 = stand+Vector3.UP*height+ranch.global_basis.x*offset
					var end: Vector3 = park+Vector3.UP*(height+0.26)+ranch.global_basis.x*offset
					var cross_hit = Geometry3D.segment_intersects_triangle(start,end,a,b,c)
					if cross_hit!=null: rail_hits.append(cross_hit)
	check(supported,"站立点由原平台GLB三角形真实承载")
	check(rail_hits.is_empty(),"上下船胶囊宽度通道不穿原平台栏杆："+str(rail_hits))
	var own := []
	for model in ranch.get_node("Models").get_children():
		for blocker in model.find_children("*","Node3D",true,false):
			if blocker.get_script()!=Blockers: continue
			for rect: Rect2 in blocker.rects_world:
				own.append({"x":rect.get_center().x,"z":rect.get_center().y,"hx":rect.size.x/2,"hz":rect.size.y/2})
	check(hits(ranch.to_global(Vector3(29.9,57.04,-2.1)),own).is_empty(),"旧泊位非楼体整块AABB或水下梯阻挡，真实组件归属已核验")
	check(not own.is_empty(),"天台真实水面组件阻挡仍保留，不放行全船穿墙")
	var blocked_center: Dictionary = own[0]
	check(not main._is_open_water(blocked_center.x,blocked_center.z),"天台实体中心仍不可航行")
	var park_xz := Vector2(park.x,park.z)
	check(not main.navigation.segment_clear(park_xz,Vector2(blocked_center.x,blocked_center.z)),"从泊位驶入天台实体仍被生产segment_clear拒绝")
