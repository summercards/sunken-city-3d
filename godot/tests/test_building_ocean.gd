extends SceneTree
const Catalog=preload("res://src/building/building_catalog.gd")
const Save=preload("res://src/save/save_game.gd")
var checks:=0
var failures:=0
var main: Node
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func advance(frames: int,until: Callable=Callable()) -> void:
	for i in frames:
		main.boat._process(1.0/60.0)
		main.actor_controller.tick(1.0/60.0)
		main.building_controller.tick(1.0/60.0)
		if until.is_valid() and until.call(): break
func shot(name: String,center: Vector3) -> void:
	if DisplayServer.get_name()=="headless": return
	main.cam.follow_enabled=false
	main.cam.global_position=center+Vector3(-8,13,17)
	main.cam.look_at(center);main.cam.fov=38
	main.cam.make_current()
	main.water_node.update_surface(0.0,main.boat,center)
	# Retain the pose through deferred camera-panel/layout initialization too.
	for i in 20:
		main.cam.global_position=center+Vector3(-8,13,17);main.cam.look_at(center)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/ocean-build-"+name+".png")
	print("[ocean-shot] ",name," camera=",main.cam.global_position," target=",center," boat=",main.boat.global_position," player=",main.player.global_position," instances=",main.building.query().size())
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	main.boat.set_process(false);main.cam.set_process(false);main.interactor.set_process(false)
	var economy: Node=root.get_node("Economy");economy.set_process(false)
	await process_frame
	check(not main.navigation.allowed_area.has_area(),"ocean is not fenced by old sail bounds")
	check(main.navigation.is_open_water(500,500),"open sea beyond old hard boundary remains legal")
	var remote_path: Array=main.navigation.plan_route_to(Vector2(500,500),750,500)
	check(remote_path.size()==2 and main.navigation.valid_route(remote_path),"distant clear route needs no world-sized grid")
	main.cam.target=Vector3(500,1.48,500);main.cam._clamp_target()
	check(main.cam.target.x==500 and main.cam.target.z==500,"camera can follow distant construction")
	main._debug_teleport("zone5")
	var request: Dictionary={"kind":"deck","x":40,"z":40}
	var center: Vector3=main.building_world.position_for(request)
	main.boat.place_at(center+Vector3(-10,-0.36,0),0)
	main.actor_controller.restore_pose({"mode":1})
	economy.inventory.set_count("wood",200);economy.inventory.set_count("soil",50)
	var controller: Node=main.building_controller
	controller.open();controller.select_recipe("deck")
	check(not controller.book.visible,"recipe available aboard")
	check(main.building.can_place(request)=="","independent ocean foundation is legal")
	var wood: int=economy.count("wood")
	controller._request_build(request)
	check(not controller.pending.is_empty() and main.building.query().is_empty(),"boat approaches before building")
	check(economy.count("wood")==wood,"travelling does not charge materials")
	advance(3000,func(): return not main.building.query().is_empty())
	check(main.building.query().size()==1,"boat reaches site and starts foundation")
	check(not main.boat.starts_sailing() and economy.count("wood")==wood-6,"stopped boat pays exactly once")
	controller.tick(3.0);controller.close()
	await physics_frame; await physics_frame
	var row: Dictionary=main.building.query()[0]
	var landing_id: String="built:%s:0"%row.id
	var landing: Dictionary=main.building_access.landing_data(landing_id)
	check(not landing.is_empty(),"completed independent platform has derived edge landing")
	var park:=Vector2(landing.boatPark[0],landing.boatPark[2])
	check(main.navigation.is_open_water(park.x,park.y),"derived landing parks in open water")
	main._select_landing({"zone":"zone5","landing":landing_id})
	advance(3000,func(): return main.actor_controller.mode()==0 and not main.actor_controller.walking())
	check(main.actor_controller.mode()==0 and not main.actor_controller.walking(),"clicking distant foundation lands after sailing")
	check(main._current_landing()!=null and main._current_landing().landing_id==landing_id,"actor uses derived landing contract")
	var field: Node=main._zone_nodes.zone5.walk_areas[0]
	check(field.contains_world(main.player.global_position.x,main.player.global_position.z),"disembarked actor stands on new deck")
	for i in 180: main.boat._process(1.0/60.0)
	check(absf(angle_difference(main.boat.rotation.y,float(landing.boatYaw)))<0.02,"boat finishes its natural parallel docking turn")
	await shot("landed",center)
	# Build another board before furnishing so the original landing stays useful.
	var second: Dictionary={"kind":"deck","x":40,"z":41}
	check(main.building.begin(second).ok,"isolated platform extends without a ring limit")
	main.building.tick(3.0)
	var support: String=""
	for item in main.building.query():
		if item.kind=="deck" and item.z==41: support=item.id
	var point:=Catalog.tile_rect(40,41).get_center()
	var planted: Dictionary=main.building.begin({"kind":"planter_small","px":point.x,"pz":point.y,"support":support})
	check(planted.ok,"compact planter on offshore platform")
	if planted.ok:
		main.building.tick(3.0)
		await physics_frame; await physics_frame
		check(economy.farm.plant("dynamic/"+planted.id,"lettuce").get("event")=="planted","offshore planter joins real farm")
	await shot("garden",center)
	var saved: Dictionary=Save.encode(main)
	var written: Dictionary=Save.write("user://offshore.json",main)
	check(written.ok,"offshore ashore world writes: "+str(written.reason))
	check(Save.restore(main,saved).ok,"offshore world restores atomically")
	await physics_frame; await physics_frame
	check(root.get_node("GameState").landing_id==landing_id and main._current_landing()!=null,"dynamic landing identity survives restore")
	# Moving away from the landing board must not make its removal legal: that
	# would strand this actor with a stale current_landing even on connected wood.
	var second_center: Vector3=main.building_world.position_for(second)
	var safe: Vector3=main.building_world.closest_walk_point(second_center+Vector3(-0.65,0,-0.7))
	main.actor_controller.restore_pose({"mode":0,"player":[safe.x,safe.y,safe.z]})
	check(not main.building.can_remove(row.id).is_empty(),"current landing board protected after actor walks elsewhere")
	var blocked: Dictionary={"kind":"deck","x":39,"z":40}
	check(not main.building.can_place(blocked).is_empty(),"occupied current landing approach cannot be built over")
	check(main.building_access.landing_data(landing_id).boatYaw!=atan2(1.0,0.0),"derived berth aligns boat parallel to exposed edge")
	var aboard: bool=main.actor_controller.depart(func(): pass)
	check(aboard,"return to boat starts at dynamic landing")
	advance(3000,func(): return main.actor_controller.mode()==1)
	check(main.actor_controller.mode()==1,"new platform returns actor to boat without teleport state="+main.actor_controller.state_id()+" pos="+str(main.player.global_position)+" route="+str(main.actor_controller.walk_path))
	var active: Dictionary=main.building.row(row.id)
	check(main.building.can_remove(active.id)=="" or main.building.can_remove(active.id).contains("摆件") or main.building.can_remove(active.id).contains("通路"),"onboard removal is checked against layout rather than stale landing")
	# Atomic multi-material refund cannot partially fill one shared backpack slot.
	var inventory=preload("res://src/inventory/inventory.gd").new(1)
	inventory.set_count("wood",39)
	check(not inventory.add_all({"wood":2,"soil":1}) and inventory.count("wood")==39 and inventory.count("soil")==0,"full refund rejects without partial materials")
	check(inventory.add_all({"wood":1}) and inventory.count("wood")==40,"refund can fill existing stack")
	main.queue_free();await process_frame
	print("[building-ocean] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
