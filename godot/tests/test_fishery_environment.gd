extends SceneTree
const Save = preload("res://src/save/save_game.gd")
const Motor = preload("res://src/player/character_motor.gd")
const COMPONENTS := ["shore","turf","pebbles","reeds","drying_rack","creel","bait_table","buoy","marker_buoy","net_panel","net_corner","fish"]
var checks := 0
var failures := 0
var main: Node
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	print("[fishery-environment] ","PASS " if value else "FAIL ",label)
	if not value: failures+=1
func meshes(node: Node) -> Array:
	return node.find_children("*","MeshInstance3D",true,false)
func bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes(node):
		if mesh.mesh == null: continue
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/fishery-"+label+".png")==OK,"save real render "+label)
func run() -> void:
	for key in COMPONENTS:
		var packed: PackedScene = load("res://scenes/components/fishery/"+key+".tscn")
		var node: Node3D = packed.instantiate()
		root.add_child(node)
		var valid := meshes(node).size()==1
		for mesh: MeshInstance3D in meshes(node):
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.get_active_material(i) as StandardMaterial3D
				valid = valid and mat != null and mat.albedo_texture != null and mat.albedo_texture.resource_path=="res://assets/textures/shared/sea_cabin_timber_8x8_512.png" and mat.texture_filter==0
		check(valid,key+": independent load, one merged mesh and persisted shared palette material")
		node.free()
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	main.set_physics_process(false)
	main.world_clock.paused=true
	main.weather_service.paused=true
	main.props.set_process(false)
	main.boat.set_process(false)
	var economy := root.get_node("Economy")
	economy.set_process(false)
	var zone: Node3D = main.get_node("World/Zones/Zone1HomeHarbor")
	var site: Node3D = main._fishery_visual
	var walk: Node3D = zone.landing_point("salvage").ground()
	var old: MeshInstance3D = zone.get_node("Models/绞盘打捞台/salvage_station/绞盘打捞台-海上区域-01_001")
	var pole: MeshInstance3D = zone.get_node("Models/绞盘打捞台/salvage_station/PoleAndFlowers")
	var pole_before := {"transform":pole.global_transform,"mesh":pole.mesh,"faces":pole.mesh.get_faces(),"materials":[]}
	for i in pole.mesh.get_surface_count():pole_before.materials.append(pole.get_active_material(i))
	var park: Vector3 = zone.landing_point("salvage").get_node("BoatPark").global_position
	var landing: Vector3 = zone.landing_point("salvage").stand_position()
	check(not site.visible and old.visible,"before upgrade retains the original wood platform")
	var old_rects: Array = walk.rects.duplicate(true)
	main.daylight_rig.apply(9)
	main.hud.hide()
	main.cam.suspend_follow()
	main.cam.target=Vector3(-16.8,1.1,18)
	main.cam.distance=43
	main.cam.orbit_dir=Vector3(-.45,.8,.6)
	main.cam.refresh()
	await shot("environment-before")
	economy.inventory.set_count("wood",0)
	economy.warehouse.set_count("wood",100)
	economy.inventory.set_count("fish",0)
	economy.warehouse.set_count("fish",50)
	var result: Dictionary = main._upgrade_fishery()
	check(result.get("event","")=="fishery_unlocked" and site.visible and not old.visible,"real upgrade command swaps only the authorized land surface")
	check(economy.warehouse.count("wood")==0 and economy.warehouse.count("fish")==0,"existing combined-cost rule remains 100 wood plus 50 fish")
	check(pole.visible and pole.global_transform==pole_before.transform and pole.mesh==pole_before.mesh and pole.mesh.get_faces()==pole_before.faces,"utility pole/flowers mesh and world transform remain exact")
	var material_same := true
	for i in pole.mesh.get_surface_count():material_same = material_same and pole.get_active_material(i)==pole_before.materials[i]
	check(material_same,"protected pole materials remain exact")
	var land_box := bounds(site.get_node("Land/shore_000"))
	check(land_box.grow(0.02).has_point(landing), "upgraded shore encompasses the existing landing")
	check(absf(land_box.end.y-landing.y)<.01,"shore top matches the landing plane")
	check(walk.rects.is_empty() and not walk.polygons.is_empty(),"upgraded walk surface uses the authored shore shape")
	for frame in 3:
		await physics_frame
	for prop_name in ["drying_rack_001", "bait_table_002"]:
		var prop: Node3D = site.get_node("Land/" + prop_name)
		var query := PhysicsRayQueryParameters3D.create(prop.global_position + Vector3.UP * 2.0,
			prop.global_position + Vector3.UP * 0.2, Motor.SCENE_GROUND_LAYER)
		var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
		check(hit.get("collider") == site.get_node("SurfaceCollision"), prop_name + " has physical obstruction above the shore")
	check(walk.contains_world(-13.2,11.4) and walk.contains_world(landing.x,landing.z),"original trade board and original landing remain on valid ground")
	check(not walk.contains_world(-19.2,20.8),"enclosed fish water never becomes a walking floor")
	check(zone.landing_point("salvage").get_node("BoatPark").global_position==park and main.navigation.is_open_water(park.x,park.z),"existing berth is unchanged and navigable")
	check(not main.navigation.is_open_water(-19.2,20.8) and main.navigation.is_open_water(-28,21),"pen occupancy is limited to the fishery")
	var net_body: StaticBody3D = site.get_node("Water/NetHullCollision")
	var outer_edge: Vector3 = net_body.get_node("South").global_position
	var hull: Boat = main.boat
	var from := Vector3(outer_edge.x, hull.WATER_LEVEL, outer_edge.z + 7.0)
	var contact := KinematicCollision3D.new()
	check(hull.test_move(Transform3D(Basis.IDENTITY, from), Vector3.FORWARD * 6.0, contact)
		and contact.get_collider() == net_body, "boat hull sweeps into the submerged net on the outer edge")
	check(not main.props._ocean_point_clear(Vector2(-19.2,20.8),false) and not main.props._ocean_point_clear(Vector2(-19.2,20.8),true),"ambient fishing pen cannot also spawn random salvage wood/fish")
	var net_ok := true
	var floats := 0
	var net_count := 0
	for node in site.get_node("Water").get_children():
		if str(node.name).begins_with("net"):
			var box := bounds(node)
			net_ok = net_ok and box.end.y<1.12 and box.position.y<-.9
			net_count+=1
		else: floats+=1
	check(net_ok and net_count>=20 and floats>=20,"full enclosure net stays submerged, round floats mark its outline")
	check(not site.has_node("Swimmers") and main._fishery_schools.get_child_count()==2,"existing ambient fish schools are independent of the facility model")
	site.set_process(false)
	var swimmer: Node3D = main._fishery_schools.get_child(0)
	swimmer.autonomous=false
	swimmer.sample(0)
	var fish_before: Transform3D = swimmer.get_node("Body").get_meta("instance_transforms")[0]
	swimmer.sample(1.2)
	check(swimmer.palette=="surface" and swimmer.size_scale==0.5 and swimmer.count==10 and swimmer.get_node("Body").get_meta("instance_transforms")[0]!=fish_before,"reused colourful surface fish keep their original size, palette and swimming")
	for time in [0.0,12.5,40.0]:
		var inside := true
		for school in main._fishery_schools.get_children():
			school.sample(time)
			for transform: Transform3D in school.get_node("Body").get_meta("instance_transforms"):
				var at: Vector3 = school.global_transform*transform.origin
				var local: Vector3 = site.get_node("PenBounds").to_local(at)
				var half: Vector2 = site.pen_size * 0.5 - Vector2.ONE * 0.25
				inside = inside and absf(local.x) < half.x and absf(local.z) < half.y and at.y < 1.0
		check(inside,"both independent schools remain submerged within the fishing pen at "+str(time))
	await shot("environment-upgraded")
	main.cam.target=Vector3(-13.1,1.3,12.8)
	main.cam.distance=22
	main.cam.refresh()
	await shot("shore-close")
	# Drive the same capsule as the shore controls.
	main.actor_controller.restore_pose({"mode":0,"zone":"zone1","player":[landing.x,landing.y,landing.z]})
	root.get_node("GameState").enter_zone("zone1")
	root.get_node("GameState").landing_id="salvage"
	main.boat.place_at(park,0)
	var destination := Vector3(-13.0,1.33,14.65)
	for i in 240:
		await physics_frame
		var direction: Vector3 = destination - main.player.global_position
		if Vector2(direction.x, direction.z).length() < 0.30:
			break
		main.actor_controller.set_move_intent(direction)
		main.actor_controller.tick(1.0/60.0)
	check(main.player.ground_contact and Vector2(main.player.global_position.x-destination.x,main.player.global_position.z-destination.z).length()<.4,"real capsule walks from berth to the upgraded shore")
	main.actor_controller.cancel()
	await shot("shore-walked")
	var snap: Dictionary = Save.encode(main)
	check(Save.write("user://fishery-environment.json",main).ok,"upgraded actor/berth and unchanged fishery schema save to disk")
	economy.fishery.from_dict({"version":1,"unlocked":false})
	check(not site.visible and old.visible and walk.rects==old_rects,"restoring unupgraded state restores wood and original walk rects")
	var restored: Dictionary = Save.restore(main,Save.read("user://fishery-environment.json").snapshot)
	check(restored.ok and site.visible and not old.visible,"loading upgraded disk snapshot from a locked world restores model and land before actor")
	check(walk.contains_world(main.player.global_position.x,main.player.global_position.z),"restored actor stands on the upgraded shore")
	var before_nodes := site.get_child_count()
	economy.fishery.changed.emit();economy.fishery.changed.emit()
	check(site.get_child_count()==before_nodes and not main.has_node("FisheryFlag"),"repeat notifications do not duplicate models or leave the retired temporary flag")
	var corrupt := snap.duplicate(true)
	corrupt.game.mode=0;corrupt.game.zone="zone1";corrupt.game.player=[-19.2,1.33,20.8]
	check(not Save.restore(main,corrupt).ok and site.visible,"snapshot claiming fish-water land rejects before mutation")
	var legacy := snap.duplicate(true);legacy.economy.erase("fishery");legacy.game.player=[landing.x,landing.y,landing.z]
	check(Save.restore(main,legacy).ok and not site.visible and old.visible,"old snapshot without upgrade state retains the original platform")
	print("[fishery-environment] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
