extends SceneTree
const Catalog = preload("res://src/diving/dive_map_catalog.gd")
const Storage = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var main
const ENTRY_DT := 1.0 / 60.0
const HOME_ENTRY_TIME := 1.65
const HOME_ENTRY_START_DEPTH := 1.6
const HOME_ENTRY_TARGET_DEPTH := 4.8

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func finish_map() -> void:
	var runtime = main.dive.runtime
	runtime.surface()
	runtime.phase_machine.tick(runtime.ENTER_TIME)
	for i in 3: await process_frame
func finish_home() -> void:
	if not main.dive.active: return
	main.dive.runtime.surface()
	for i in 240:
		await process_frame
		if not main.dive.active: break
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if OS.get_environment("SEA_DIVE_TRACE")=="1":
		node_added.connect(func(node: Node):
			if node.get_class() in ["Terrain3D","Camera3D","WorldEnvironment"] or node.name in ["Main","World","Zones","Boat","Explorer","HUD","Birds","LandingMarkers","ColorGrade"]: print("[dive-tree] ",node.get_path()))
	main._autosave_on = false
	for i in 3: await process_frame
	# Freeze unrelated idle bobbing/following; lifecycle checks compare exact poses.
	main.set_process(false)
	main.set_physics_process(false)
	main.boat.set_process(false)
	main.cam.set_process(false)
	main.player.set_process(false)
	check(Catalog.validate()=="","catalog validates")
	check(Catalog.source_ids().size()==9,"nine stable sea-area mappings")
	check(Catalog.get_map("unknown").is_empty(),"unknown map has no fallback")
	var copy: Dictionary = Catalog.get_map("zone1")
	copy.map_id = "broken"
	check(Catalog.get_map("zone1").map_id=="dive_zone1","catalog query returns copy")
	check(not main.has_node("Underwater") and main.dive.runtime==null,"no resident underwater geometry")
	var source_text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	check(not source_text.contains("scenes/underwater/"),"surface scene has no packed underwater map")
	var original = main
	var session = main.dive
	var before_mode: int = main.actor_controller.mode()
	var before_boat: Transform3D = main.boat.transform
	var before_player: Transform3D = main.player.transform
	var before_camera: Transform3D = main.cam.transform
	var original_environment: Environment = main.world_env.environment
	var seabed: Node = main.get_node_or_null("World/SunkenSeabed")
	var seabed_transform: Transform3D = seabed.transform if seabed!=null else Transform3D.IDENTITY
	var seabed_top: bool = seabed.top_level if seabed!=null else false
	var before_snapshot: Dictionary = Storage.encode(main)
	check(not main.dive.enter_map("unknown") and main.is_inside_tree(),"unknown source rejects without removing main")
	check(not session.dive(main.boat.position,"unknown"),"explicit unknown source never falls back")
	for id in main._zone_nodes:
		if not preload("res://src/core/play_scope.gd").zone_enabled(str(id)) or Catalog.get_map(str(id)).is_empty(): continue
		var points: Array = main._zone_nodes[id].landing_points()
		if points.is_empty(): continue
		var landing_source: String = main._dive_source_at(points[0].global_position)
		var home_water: bool = Catalog.is_home_water(points[0].global_position,main._home_seabed_anchor())
		check(landing_source==("home_seabed" if home_water else str(id)),"source follows live installed landing "+str(id))
	var saved_zone: String = root.get_node("GameState").current_zone
	main.actor_controller.machine.change("ashore_idle",{},true)
	root.get_node("GameState").current_zone="zone2"
	check(main._dive_source_at(Vector3(999,0,999))=="zone2","ashore selects current stable zone ID")
	root.get_node("GameState").current_zone=saved_zone
	main.actor_controller.machine.change("boat_idle" if before_mode==1 else "ashore_idle",{},true)
	var ids := {}
	var paths := {}
	var all_chests := {}
	var images := 0
	for id in Catalog.source_ids():
		var entry := Catalog.get_map(id)
		check(not ids.has(entry.map_id) and not paths.has(entry.scene_path),"distinct map identity and scene "+id)
		ids[entry.map_id]=true;paths[entry.scene_path]=true
		check(session.enter_map(id),"enter map "+id)
		if session.runtime==null: continue
		var runtime = session.runtime
		check(current_scene==runtime and not main.is_inside_tree(),"real current_scene switch and detached surface "+id)
		check(runtime.map_id==entry.map_id and runtime.scene_file_path==entry.scene_path,"selected scene matches source "+id)
		check(not session.enter_map(id),"repeated entry rejected "+id)
		check(main.save_registry.is_busy() and not Storage.write("user://blocked_dive.json",main).ok,"no intermediate save "+id)
		check(not FileAccess.file_exists("user://blocked_dive.json"),"blocked save leaves no file "+id)
		var clock: Dictionary = main.world_clock.to_dict()
		var inventory: Dictionary = root.get_node("Economy").inventory.to_dict()
		var count: int = runtime.region_nodes().size()
		check(count>0 and runtime.region_node("basin")!=null,"visible basin and map content "+id)
		check(runtime.diver_pos.is_equal_approx(runtime.spawn_point),"map-specific spawn "+id)
		runtime.phase_machine.tick(runtime.ENTER_TIME)
		check(is_equal_approx(runtime.ENTER_TIME,2.2) and absf(runtime.diver_pos.y+10.0)<0.001,"旧九图保留2.2s入水及Y=-10终点 "+id)
		check(runtime.phase=="swim" and not runtime.blocked(runtime.diver_pos),"safe enter path and swim "+id)
		check(is_equal_approx(runtime.air.surface_depth,5.0),"legacy maps restore their own 5m breathing band "+id)
		if id=="zone1":
			var overlay = runtime.get_child(runtime.get_child_count()-1)
			var escape := InputEventKey.new()
			escape.keycode=KEY_ESCAPE;escape.pressed=true
			overlay._input(escape)
			check(paused and overlay.presentation_snapshot().menu_open,"independent Esc pause")
			var air_before: float = runtime.air.ratio()
			for i in 3: await process_frame
			check(runtime.air.ratio()==air_before,"pause freezes oxygen")
			overlay._input(escape)
			check(not paused,"independent pause resumes")
			runtime.air.air=25.0;overlay._process(0)
			check(overlay.presentation_snapshot().color==Color("#E08B4A"),"local HUD orange low-air warning")
			runtime.air.air=12.0;overlay._process(0)
			check(overlay.presentation_snapshot().color==Color("#D4573F"),"local HUD critical warning")
			runtime.air.refill()
		for chest in runtime._chests:
			check(not all_chests.has(chest.id),"globally unique chest ID "+str(chest.id))
			all_chests[chest.id]=true
		check(runtime._trench.is_empty()==(runtime.region_node("trench")==null),"no invisible removed trench collision "+id)
		for i in 3: await process_frame
		check(main.world_clock.to_dict()==clock and main.boat.transform==before_boat,"surface time and boat frozen "+id)
		check(root.get_node("Economy").inventory.to_dict()==inventory,"enter has no reward side effect "+id)
		if DisplayServer.get_name()!="headless":
			runtime.debug_teleport(Vector3(0,-12,10))
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png("res://outputs/dive-map-"+id+".png")
			check(error==OK,"real rendered map "+id)
			images+=1
		await finish_map()
		check(main==original and main.is_inside_tree() and session==main.dive,"same surface instance and owner restored "+id)
		check(session.runtime==null and not is_instance_valid(runtime),"underwater map unloaded "+id)
		check(root.get_camera_3d()==main.cam and main.world_env.environment==original_environment,"surface camera/environment restored "+id)
		check(main.actor_controller.mode()==before_mode and main.boat.transform==before_boat and main.player.transform==before_player,"actor and boat return pose unchanged "+id)
		if id=="zone1" and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://outputs/dive-map-return-surface.png")==OK,"real surface render after return")
		check(main.save_registry.capture().has("dive"),"save registry survives detach "+id)
		check(seabed==null or (seabed.is_inside_tree() and seabed.transform==seabed_transform and seabed.top_level==seabed_top),"original scenic terrain pose and flag restored "+id)
		for zone in main._zone_nodes.values():
			check(zone.ground_space!=null and zone.ground_space.get("_areas").size()==zone.walk_areas.size(),"ground projection restored "+str(zone.zone_id))
	# 家园海底：与海面同一套坐标，入水点由下水点换算；九张旧图目录不因此增加。
	var home: Dictionary = Catalog.get_map("home_seabed")
	check(not home.is_empty() and bool(home.get("world_aligned",false)),"home seabed is world aligned")
	check(home.scene_path=="res://scenes/underwater/sunroom_region.tscn","home seabed reuses the sunroom region scene")
	check(home.map_id=="dive_home_seabed" and home.chest_id_base==900 and home.label=="家园海底","home seabed identity and label")
	check(Catalog.source_ids().size()==9,"home seabed does not add a sea-area mapping")
	var anchor: Vector3 = main._home_seabed_anchor()
	check(main._dive_source_at(anchor)=="home_seabed","diving beside the sunroom selects home seabed")
	check(main._dive_source_at(anchor+Vector3(0,0,-400))!="home_seabed","far water keeps its own sea area")
	var entry_point: Vector3 = anchor+Vector3(7,0,5)
	check(session.dive(entry_point,"home_seabed"),"enter home seabed from a surface point")
	if session.active:
		var region = session.runtime
		var controller = region.dive_controller
		# 同步工具入口会自动 release；关闭自动 tick 后用固定步独立校验整段真实碰撞。
		controller.set_physics_process(false)
		controller.transition_frozen = true
		check(region.map_id=="dive_home_seabed" and region.map_label=="家园海底","home runtime identity")
		check(current_scene==region and not main.is_inside_tree(),"home dive really switches scene")
		# Terrain3D 与逐 Mesh 碰撞延后提交；等 map readiness 后再释放 entry。
		for i in 240:
			await physics_frame
			if controller.entry_is_prepared(): break
		check(controller.entry_is_prepared() and region.dive_entry_ready() and controller.machine.current=="enter","家园：地图物理准备完成，仍保持enter")
		check(is_equal_approx(float(controller.snapshot().entry_progress),float(region.dive_entry_progress())),"家园：控制器进度读取map适配器")
		var before_release: Dictionary = controller.snapshot()
		var start: Vector3 = region.dive_position()
		check(absf(float(before_release.get("entry_progress", -1.0))) < 0.001,"家园：固定步开始前entry_progress为0")
		check(is_equal_approx(float(region.entry_depth_below_surface),HOME_ENTRY_TARGET_DEPTH),"home exported entry target remains 4.8m")
		check(absf(region.water_level-start.y-HOME_ENTRY_START_DEPTH)<0.05,"家园：正常夹具从水下1.6m开始，不走街面保底")
		var full_query := PhysicsShapeQueryParameters3D.new()
		var full_capsule := CapsuleShape3D.new()
		full_capsule.radius=0.35; full_capsule.height=1.6
		full_query.shape=full_capsule
		full_query.transform=Transform3D(Basis.IDENTITY,start)
		full_query.collision_mask=1; full_query.collide_with_areas=false
		full_query.exclude=[region.collision_runtime.viewer.get_rid()]
		check(root.world_3d.direct_space_state.intersect_shape(full_query,1).is_empty(),"家园：起点胶囊真实净空")
		full_query.motion=Vector3(0,region.water_level-float(region.entry_depth_below_surface)-start.y,0)
		var full_cast := root.world_3d.direct_space_state.cast_motion(full_query)
		check(full_cast.is_empty() or float(full_cast[0])>=0.999,"家园：1.6m至4.8m完整下沉段精确胶囊扫掠无阻挡")
		controller.release_entry()
		controller.release_entry()
		check(bool(controller.snapshot().get("entry_released",false)),"home release_entry is idempotent")
		var prior := start
		var air_before: float = controller.air.air
		var elapsed := 0.0
		while controller.machine.current=="enter" and elapsed<3.0:
			controller.machine.tick(ENTRY_DT)
			elapsed+=ENTRY_DT
			var current: Vector3 = region.dive_position()
			var segment_query := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius=0.35; capsule.height=1.6
			segment_query.shape=capsule
			segment_query.transform=Transform3D(Basis.IDENTITY,prior)
			segment_query.motion=current-prior
			segment_query.collision_mask=1; segment_query.collide_with_areas=false
			segment_query.exclude=[region.collision_runtime.viewer.get_rid()]
			var cast := root.world_3d.direct_space_state.cast_motion(segment_query)
			check(cast.is_empty() or float(cast[0])>=0.999,"home entry full capsule segment has no collision")
			segment_query.motion=Vector3.ZERO
			segment_query.transform.origin=current
			check(root.world_3d.direct_space_state.intersect_shape(segment_query,1).is_empty(),"home entry capsule never overlaps exact geometry")
			var blend := 1.0-pow(1.0-clampf(elapsed/HOME_ENTRY_TIME,0.0,1.0),3.0)
			var expected_y: float = lerpf(start.y,region.water_level-float(region.entry_depth_below_surface),blend)
			check(absf(current.y-expected_y)<0.002,"home entry fixed step cubic ease-out")
			check(current.y<=prior.y+0.0001 and Vector2(current.x-start.x,current.z-start.z).length()<0.001,"home entry descends continuously without horizontal teleport")
			check(controller.velocity.is_equal_approx((current-prior)/ENTRY_DT) or controller.machine.current=="swim","home entry velocity follows actual collision movement")
			prior=current
		check(absf(elapsed-HOME_ENTRY_TIME)<=ENTRY_DT+0.0001,"home entry duration is 1.65s within one physics tick")
		check(controller.machine.current=="swim" and controller.velocity==Vector3.ZERO,"home entry reaches swim with zero residual velocity")
		check(absf(controller.air.air-air_before)<0.000001,"home entry does not consume oxygen")
		var diver: Vector3 = region.dive_position()
		check(absf(region.water_level-diver.y-float(region.entry_depth_below_surface))<0.05,"home entry reaches the exported 4.8m depth target")
		controller.transition_frozen=false
		controller.set_physics_process(true)
		check(is_equal_approx(region.target_depth_m,120.0) and is_equal_approx(region.viewer_min_y,-18.412558) and is_equal_approx(region.water_level,101.587442),"home seabed depth contract is 120m from surface to the upper street")
		var diver_visual = region.get_node_or_null("DiverVisual")
		check(diver_visual!=null and diver_visual.get_node_or_null("DiverCharacter")!=null,"home dive has third-person character")
		if diver_visual!=null:
			check(diver_visual.get_node("DiverCharacter").visible,"third-person character visible while diving")
		check(Vector2(diver.x-entry_point.x,diver.z-entry_point.z).length()<=region.entry_search_radius,"entry stays inside the declared home-water radius")
		check(diver.y<region.water_level and diver.y>region.lowest_seabed_y,"entry under sea level and above seabed")
		check(absf(region.water_level-101.587442)<0.001,"home surface is 120m above the upper street datum")
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = CapsuleShape3D.new()
		query.shape.radius = 0.35
		query.shape.height = 1.6
		query.transform = Transform3D(Basis.IDENTITY,diver)
		query.collision_mask = 1
		check(root.world_3d.direct_space_state.intersect_shape(query,1).is_empty(),"entry capsule has real clearance")
		check(region.phase=="swim" and region.depth>0.0,"home dive is playable and reports depth")
		var oxygen: float = region.air.ratio()
		for i in 90: await process_frame
		check(region.air.ratio()<oxygen,"home dive consumes oxygen")
		var home_hud = region.get_child(region.get_child_count()-1)
		check(home_hud.presentation_snapshot().text.contains("家园海底"),"local HUD names 家园海底")
		if DisplayServer.get_name()!="headless":
			# 不覆盖朝向：玩家入水看到的就是地图自己选的方向。
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://outputs/dive-map-home-seabed.png")==OK,"real rendered home seabed")
		await finish_home()
		check(not session.active and main.is_inside_tree(),"home seabed returns the same surface")
		check(session.runtime==null and not is_instance_valid(region),"home seabed unloaded")
		check(root.get_camera_3d()==main.cam,"surface camera restored after home dive")
		check(main.player.transform==before_player,"surface actor pose unchanged after home dive")
	# Old v4 shape is unchanged; unknown future ContentIDs survive lazy map unloads.
	session.from_dict({"found":[0,9999],"opened":[0]})
	check(session.to_dict()=={"found":[0,9999],"opened":[0]},"legacy integer progress and unknown IDs retained without scene")
	check(session.enter_map("zone1"),"revisit legacy map")
	check(session.runtime.opened_chests()==1,"legacy opened chest restored")
	var reward_before: Dictionary = root.get_node("Economy").inventory.to_dict()
	session.runtime._open_chest(session.runtime._chests[0])
	check(root.get_node("Economy").inventory.to_dict()==reward_before,"opened chest cannot reward twice")
	await finish_map()
	check(session.enter_map("zone2"),"enter second map for isolation")
	check(session.runtime.opened_chests()==0,"old chest 0 does not open map2 chest 100")
	session.runtime.phase_machine.tick(session.runtime.ENTER_TIME)
	var chest = session.runtime._chests[0]
	session.runtime.debug_discover(0)
	var bag = root.get_node("Economy").inventory
	var bag_state: Dictionary = bag.to_dict()
	bag.from_dict({"capacity":1,"counts":{"lettuce_seed":1}})
	var full_state: Dictionary = bag.to_dict()
	session.runtime._open_chest(chest)
	check(not chest.opened and bag.to_dict()==full_state,"full backpack rejects whole chest with no lost reward")
	var local_hud = session.runtime.get_child(session.runtime.get_child_count()-1)
	check(local_hud._notice.text.contains("背包"),"full reward rejection is visible in local map HUD")
	bag.from_dict(bag_state)
	session.runtime._open_chest(chest)
	check(chest.opened,"new map rewards can open")
	await finish_map()
	check(session.to_dict().opened.has(100) and session.to_dict().opened.has(0) and session.to_dict().found.has(9999),"map progress unions without loss")
	var snapshot: Dictionary = Storage.encode(main)
	check(snapshot.version==4 and snapshot.dive.has("found") and snapshot.dive.has("opened") and snapshot.dive.size()==2,"v4 wire format unchanged")
	check(Storage.write("user://dive_round_trip.json",main).ok,"save after return")
	var decoded := Storage.read("user://dive_round_trip.json")
	var disk_progress := {}
	if decoded.ok:
		for key in ["found","opened"]:
			disk_progress[key] = []
			for value in decoded.snapshot.dive[key]: disk_progress[key].append(int(value))
	check(decoded.ok and disk_progress==snapshot.dive,"progress disk round trip")
	check(main.cam.transform.is_equal_approx(before_camera),"surface camera pose is not reset by switch")
	check(Storage.restore(main,before_snapshot).ok,"original whole session can restore after map switches")
	check(session.to_dict()==before_snapshot.dive,"full restore clears progress from all maps")
	# Diving is reopened for the default profile: the real command must switch maps.
	var dive_entry: Vector3 = main.boat.position
	if main.actor_controller.mode()==0: dive_entry = main.player.global_position
	var expected_source: String = main._dive_source_at(dive_entry)
	main._on_dive()
	check(session.switching and session.runtime==null and main.is_inside_tree(),"production command accepts before asynchronous switch")
	var production_deadline := Time.get_ticks_msec()+45000
	while session.switching and Time.get_ticks_msec()<production_deadline:
		await process_frame
	check(not session.switching and session.active and session.source_id==expected_source,"production command selects source and switches")
	if session.active and not session.switching:
		session.surface()
		production_deadline = Time.get_ticks_msec()+45000
		while session.switching and Time.get_ticks_msec()<production_deadline:
			await process_frame
		check(not session.switching and main.is_inside_tree() and not session.active,"production command returns original surface")
	if session.switching:
		print("[dive-maps] %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	# Cooldown is shared across maps, not reset by unloading.
	session.air.recover=6.0
	check(not session.enter_map("zone2") and session.runtime==null,"cooldown blocks cross-map bypass")
	session._process(6.0)
	check(session.air.can_dive(),"cooldown progresses on surface")
	if DisplayServer.get_name()!="headless": check(images==9,"nine real map renders")
	check(session.enter_map("zone1"),"force-surface fixture enters")
	session.runtime.phase_machine.tick(session.runtime.ENTER_TIME)
	session.runtime.air.air=0.001
	session.runtime.phase_machine.tick(0.05)
	check(session.runtime.phase=="exit" and session.air.recover>0,"oxygen exhaustion starts surface state and cooldown")
	session.runtime.phase_machine.tick(session.runtime.ENTER_TIME)
	for i in 3: await process_frame
	check(not session.active and main.is_inside_tree(),"oxygen exhaustion returns original scene")
	session.air.recover=0
	# Abnormal map destruction frees the suspended host rather than leaking it.
	check(session.enter_map("zone1"),"abnormal teardown fixture enters")
	var abandoned_map = session.runtime
	abandoned_map.queue_free()
	for i in 3: await process_frame
	check(not is_instance_valid(main) and not is_instance_valid(session),"unexpected map teardown releases suspended surface and owner")
	check(not paused and root.get_node("Economy").ticking,"unexpected teardown restores global pause/ticking")
	print("[dive-maps] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
