extends SceneTree
const Catalog=preload("res://src/building/building_catalog.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	var econ=root.get_node("Economy");econ.set_process(false)
	await process_frame
	check(main.props.crates.size()==6,"six local driftwood bundles")
	for c in main.props.crates:
		check(c.kind=="planks" and preload("res://src/core/play_scope.gd").HOME_WATER.has_point(Vector2(c.base.x,c.base.z)),"local timber pickup")
	var crate: Dictionary=main.props.crates[0]
	var before: int=econ.count("wood")
	check(not main.props.collect_crate(crate).is_empty() and econ.count("wood")==before+3,"pickup enters inventory")
	check(main.props.collect_crate(crate).is_empty(),"pickup cannot repeat")
	var sailing_crate: Dictionary=main.props.crates[0]
	var sailing_wood: int=econ.count("wood")
	main._title_active=false
	main.props.set_process(false);main.boat.set_process(false)
	main._handle_prop_click({"type":"crate","item":sailing_crate})
	check(main.boat.starts_sailing() and econ.count("wood")==sailing_wood,"click starts route without remote pickup")
	for i in 12000:
		if not main.boat.starts_sailing(): break
		main.boat._steer(1.0/60)
	# 到站只代表「可以开始捞」：第一帧进入打捞、但不进账。
	main._process(0.0)
	check(not main.boat.starts_sailing() and econ.count("wood")==sailing_wood,"arrival starts gathering without instant reward")
	# 打捞走完才结算（浮木 1.2 秒，这里给 2 秒余量）。
	for i in 120: main._process(1.0/60)
	check(econ.count("wood")==sailing_wood+3,"gathering completion picks up driftwood")
	var bag: Dictionary=econ.inventory.to_dict()
	econ.inventory.from_dict({"capacity":1,"counts":{"parts":30}})
	var population: int=main.props.crates.size()
	check(main.props.collect_crate(main.props.crates[0]).is_empty() and main.props.crates.size()==population,"full bag retains driftwood")
	check(main.hud.material_shop.buy_soil().has("blocked"),"full bag soil denied")
	econ.inventory.from_dict(bag);econ.inventory.set_count("coins",80)
	check(main.hud.material_shop.buy_soil().get("ok",false) and econ.count("coins")==76 and econ.count("soil")==1,"soil sale")
	econ.inventory.set_count("wood",40);econ.inventory.set_count("soil",8)
	check(main.hud.corner.buttons.has("craft"),"menu eighth slot")
	main.building_controller.open()
	check(main.building_controller.book.visible,"construction book opens")
	main.building_controller.select_recipe("deck")
	check(not main.building_controller.book.visible,"boat can select an ocean foundation")
	main.building_controller.close()
	main._debug_teleport("zone5")
	var landing=main._zone_nodes.zone5.landing_point("main")
	main.actor_controller.restore_pose({"mode":0,"player":[21.0,1.48,16.0]});root.get_node("GameState").enter_zone("zone5")
	var candidate: Dictionary={}
	for c in main.building.candidates():
		if c.x==3 and c.z==0 and main.building.can_place(c)=="": candidate=c;break
	check(not candidate.is_empty(),"east extension offered")
	if candidate.is_empty(): quit(1);return
	main.building_controller.open();main.building_controller.select_recipe("deck")
	check(not main.building_controller.book.visible and main.building_controller.candidate_ghosts.size()>0,"world ghosts")
	var made: Dictionary=main.building.begin(candidate)
	check(made.ok and econ.count("wood")==34,"start paid work")
	main.building_controller.tick(1)
	check(main.building_controller.progress.size()==1,"world progress bar")
	var save=preload("res://src/save/save_game.gd")
	var pending: Dictionary=save.encode(main)
	check(save.restore(main,pending).ok,"restore unfinished work")
	main.building_controller.tick(2)
	var deck: Dictionary=main.building.row(made.id)
	var center: Vector3=main.building_world.position_for(deck)
	var area=landing.ground()
	check(area.contains_world(center.x,center.z),"completed deck walkable")
	check(not area.path_between(landing.stand_position(),center).is_empty(),"cross seam route")
	check(not main.navigation.is_open_water(center.x,center.z),"boat blocks new deck")
	var request: Dictionary={"kind":"planter","support":deck.id,"px":center.x-22,"pz":center.z-16,"turn":0}
	var planted: Dictionary=main.building.begin(request)
	check(planted.ok,"build planter")
	main.building_controller.tick(4)
	var plot=main.farm_field.find("dynamic/"+planted.id)
	check(plot!=null and plot.use_action_menu,"registered interactive plot")
	check(area.contains_world(center.x,center.z),"planter soil remains walkable")
	# Physics projections made by construction/restoration become active on a
	# physics step. Manual controller ticks must use the same boundary as play.
	await physics_frame; await physics_frame
	check(main.actor_controller.approach(plot),"reachable planter interaction anchor")
	for i in 3000:
		if not main._walking and main.actor_controller.state_id()!="approaching": break
		main.actor_controller.tick(1.0/60)
	main.actor_controller.cancel()
	econ.inventory.set_count("lettuce_seed",3)
	check(plot.perform("plant","lettuce").get("event")=="planted","dynamic plot plants")
	check(plot.perform("water").get("event")=="watered","dynamic plot waters")
	var saved: Dictionary=save.encode(main)
	var write_result: Dictionary=save.write("user://building.json",main)
	check(write_result.ok,"write built world: "+str(write_result.reason)+" pose="+str(main.capture_world_state()))
	main.building.from_dict(preload("res://src/building/building_service.gd").empty_snapshot())
	var restored: Dictionary=save.restore(main,saved)
	check(restored.ok,"candidate world validates after layout cleared: "+str(restored.reason))
	check(econ.farm.state("dynamic/"+planted.id).crop=="lettuce","crop restored after registration")
	var bad: Dictionary=saved.duplicate(true);bad.building.instances[1].support="gone"
	check(not save.restore(main,bad).ok and main.building.query().size()==2,"bad layout leaves live state")
	for day in 3:
		econ.farm.water("dynamic/"+planted.id);econ.farm.advance_day(true)
	check(econ.farm.phase("dynamic/"+planted.id)=="ready","three-day maturity")
	check(econ.farm.harvest("dynamic/"+planted.id).get("event")=="harvested","dynamic plot harvest")
	var legacy: Dictionary=saved.duplicate(true);legacy.version=3;legacy.erase("building")
	legacy.economy.farm.plots.erase("dynamic/"+planted.id)
	check(save.decode(JSON.stringify(legacy)).ok,"v3 migration")
	main.queue_free();await process_frame
	print("[building-integration] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
