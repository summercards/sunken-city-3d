extends SceneTree
## Formal scene regression: planting visuals are pass-through, deck edges are not.
const Catalog = preload("res://src/building/building_catalog.gd")
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var main: Node
var economy: Node
var area: Node3D

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func settle() -> void:
	for i in 3:
		await physics_frame
		await process_frame

func walk_between(start: Vector3,target: Vector3,label: String) -> void:
	main.actor_controller.restore_pose({"mode":0,"player":[start.x,start.y,start.z]})
	var started: bool=main.actor_controller.start_walk(area,target)
	check(started,label+" path starts")
	if not started: return
	for i in 1200:
		main.actor_controller.tick(1.0/60.0)
		if not main.actor_controller.walking(): break
	check(main.actor_controller.state_id()=="ashore_idle" and main.player.global_position.distance_to(target)<0.025,
		label+" capsule reaches target: "+str(main.player.global_position))

func capture_standing(label: String,point: Vector3) -> void:
	if DisplayServer.get_name()=="headless": return
	var camera: Camera3D=main.cam
	var previous_transform: Transform3D=camera.global_transform
	var previous_fov: float=camera.fov
	var was_processing: bool=camera.is_processing()
	var was_following: bool=camera.follow_enabled
	camera.set_process(false);camera.follow_enabled=false
	var aim:=point+Vector3.UP*0.45
	for i in 8:
		camera.global_position=point+Vector3(-2.9,3.5,4.1)
		camera.look_at(aim);camera.fov=38.0;camera.make_current()
		await process_frame
	var viewport: Vector2=root.get_visible_rect().size
	var frame:=Rect2(viewport*0.05,viewport*0.9)
	check(frame.has_point(camera.unproject_position(main.player.global_position+Vector3.UP*0.65)),"render frames standing actor "+label)
	check(frame.has_point(camera.unproject_position(point)),"render frames actual planting cell "+label)
	await RenderingServer.frame_post_draw
	var path: String="res://outputs/planter-walk-"+label+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"save original-render standing evidence "+label)
	print("[planter-walk-shot] ",path," player=",main.player.global_position," cell=",point)
	camera.global_transform=previous_transform;camera.fov=previous_fov
	camera.follow_enabled=was_following;camera.set_process(was_processing)

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	main.boat.set_process(false);main.interactor.set_process(false)
	economy=root.get_node("Economy");economy.set_process(false)
	await settle()
	main._debug_teleport("zone5")
	root.get_node("GameState").enter_zone("zone5")
	area=main._zone_nodes.zone5.landing_point("main").ground()
	economy.inventory.set_count("wood",200)
	economy.inventory.set_count("soil",40)
	economy.inventory.set_count("lettuce_seed",10)
	var fixed: Array=[]
	for plot: Node3D in main.farm_field.plots:
		if str(plot.zone_id)=="zone5" and not str(plot.plot_id).begins_with("dynamic/"): fixed.append(plot)
	check(fixed.size()==6,"all six original planting cells remain registered")
	for plot: Node3D in fixed:
		var center: Vector3=plot.global_position
		center.y=Catalog.ORIGIN.y
		check(area.contains_position(center),"fixed planting cell centre is walkable "+str(plot.plot_id))
		walk_between(center-Vector3(0.55,0,0),center+Vector3(0.55,0,0),"cross empty fixed "+str(plot.plot_id))
	if fixed.is_empty():
		finish();return
	var mature: Node3D=fixed[0]
	check(mature.perform("plant","lettuce").get("event")=="planted","fixed crop can still be planted")
	for day in 3:
		economy.farm.water(mature.plot_id)
		economy.farm.advance_day(true)
	check(economy.farm.phase(mature.plot_id)=="ready","fixed crop reaches its original maturity rule")
	var crop_before: Dictionary=economy.farm.state(mature.plot_id)
	var count_before: int=economy.count("vegetable")
	var center: Vector3=mature.global_position;center.y=Catalog.ORIGIN.y
	walk_between(center-Vector3(0.55,0,0),center+Vector3(0.55,0,0),"cross mature fixed crop")
	check(economy.farm.state(mature.plot_id)==crop_before and economy.count("vegetable")==count_before,
		"walking on mature vegetables neither tramples nor auto-harvests")
	main.actor_controller.restore_pose({"mode":0,"player":[center.x,center.y,center.z]})
	await capture_standing("fixed-mature",center)
	main.hud.world_actions.close(true)
	main._open_spot_bubbles(mature)
	check(main.hud.world_actions.active,"mature planting cell still opens explicit action menu")
	main.hud.world_actions.close(true)
	check(main.actor_controller.approach(mature),"mature planting cell remains reachable through formal approach")
	main.actor_controller.cancel()
	check(mature.perform("harvest").get("event")=="harvested" and economy.count("vegetable")==count_before+2,
		"explicit harvest retains original yield")
	main.actor_controller.restore_pose({"mode":0,"player":[22.0,1.48,16.0]})
	var built: Array=[]
	for x in [3,4]:
		var result: Dictionary=main.building.begin({"kind":"deck","x":x,"z":0})
		check(result.ok,"support board can be built "+str(x))
		if not result.ok: continue
		main.building.tick(3.0)
		built.append(main.building.row(result.id))
	if built.size()!=2:
		finish();return
	var plant_rows: Array=[]
	for index in 2:
		var deck: Dictionary=built[index]
		var point: Vector3=main.building_world.position_for(deck)
		var kind: String="planter" if index==0 else "planter_small"
		var result: Dictionary=main.building.begin({"kind":kind,"support":deck.id,"px":point.x-Catalog.ORIGIN.x,"pz":point.z-Catalog.ORIGIN.z,"turn":0})
		check(result.ok,"DIY planting cell builds "+kind)
		if not result.ok: continue
		main.building.tick(4.0)
		plant_rows.append(main.building.row(result.id))
	await settle()
	for row: Dictionary in plant_rows:
		var plot: Node3D=main.farm_field.find("dynamic/"+str(row.id))
		check(plot!=null,"DIY farm registration remains available "+str(row.kind))
		if plot==null: continue
		var point: Vector3=main.building_world.position_for(row)
		check(area.contains_position(point),"DIY planting cell does not carve navigation hole "+str(row.kind))
		check(plot.perform("plant","lettuce").get("event")=="planted","DIY cell remains plantable "+str(row.kind))
		check(plot.perform("water").get("event")=="watered","DIY cell remains waterable "+str(row.kind))
		var state: Dictionary=economy.farm.state(plot.plot_id)
		walk_between(point-Vector3(0.65,0,0),point+Vector3(0.65,0,0),"cross DIY "+str(row.kind))
		check(economy.farm.state(plot.plot_id)==state,"crossing preserves crop/water/growth "+str(row.kind))
		check(main.actor_controller.approach(plot),"DIY interaction anchors remain reachable "+str(row.kind))
		main.actor_controller.cancel()
		main.actor_controller.restore_pose({"mode":0,"player":[point.x,point.y,point.z]})
		if row.kind=="planter": await capture_standing("diy-planter",point)
		var snapshot: Dictionary=Save.encode(main)
		var written: Dictionary=Save.write("user://walk-on-"+str(row.kind)+".json",main)
		check(written.ok,"standing on planting cell can save "+str(row.kind)+": "+str(written.reason))
		main.actor_controller.restore_pose({"mode":0,"player":[22.0,1.48,16.0]})
		var restored: Dictionary=Save.restore(main,snapshot)
		check(restored.ok and main.player.global_position.distance_to(point)<0.02,
			"standing on planting cell restores at same position "+str(row.kind))
		await settle()
	# A long direct physics request must still stop at the exterior support edge.
	var edge_start:=Catalog.ORIGIN+Vector3(7.0,0,-1.2875)
	main.actor_controller.restore_pose({"mode":0,"player":[edge_start.x,edge_start.y,edge_start.z]})
	var blocked: Dictionary=main.player.move_ground(Vector3(8,0,0),0.5)
	check(blocked.blocked and main.player.global_position.x<Catalog.ORIGIN.x+Catalog.BASE.position.x+5*Catalog.TILE.x+0.02,
		"platform exterior still blocks the real capsule")
	check(not area.contains_position(Catalog.ORIGIN+Vector3(15,0,0)),"ocean outside support is not walkable")
	finish()

func finish() -> void:
	main.queue_free()
	await process_frame
	print("[walk-on-planters] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
