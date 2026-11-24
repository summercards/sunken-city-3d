extends SceneTree
const Catalog=preload("res://src/building/building_catalog.gd")
const Save=preload("res://src/save/save_game.gd")
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func run() -> void:
	var main: Node=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main.set_process(false);main._autosave_on=false;main.boat.set_process(false)
	var economy: Node=root.get_node("Economy");economy.set_process(false)
	await process_frame
	if OS.get_cmdline_user_args().has("--building-open-seed"):
		main._debug_teleport("zone5")
		economy.inventory.set_count("wood",500);economy.inventory.set_count("soil",40)
		main.boat.place_at(Vector3(160,1.12,110),0)
		main.actor_controller.restore_pose({"mode":1})
		for x in range(50,58):
			for z in range(20,28):
				# Storage stress fixture: explicit boat origin, with energy restored
				# between pieces. Energy spending has its own verification suite.
				economy.energy.refill()
				var result: Dictionary=main.building.begin({"kind":"deck","x":x,"z":z,"origin":"boat"})
				check(result.ok,"large ocean deck accepted "+str(Vector2i(x,z))+": "+str(result.get("reason","")))
				if not result.ok:
					main.queue_free();await process_frame;quit(1);return
				main.building.tick(3.0)
		var point:=Catalog.tile_rect(51,21).get_center()
		var planted: Dictionary=main.building.begin({"kind":"planter_small","support":"built_16","px":point.x,"pz":point.y})
		check(planted.ok,"large-layout furnishing accepted")
		if not planted.ok: quit(1);return
		main.building.tick(3.0)
		check(economy.farm.plant("dynamic/"+planted.id,"lettuce").get("event")=="planted","large-layout crop planted")
		economy.farm.water("dynamic/"+planted.id)
		point=Catalog.tile_rect(57,27).get_center()
		var moved: Dictionary=main.building.move(planted.id,{"support":"built_70","px":point.x,"pz":point.y,"turn":1})
		check(moved.ok,"crop moves to last-created support")
		var actor:=Catalog.ORIGIN+Vector3(Catalog.tile_rect(50,20).get_center().x,0,Catalog.tile_rect(50,20).get_center().y)
		root.get_node("GameState").landing_id="built:built_7:2"
		root.get_node("GameState").enter_zone("zone5")
		main.actor_controller.restore_pose({"mode":0,"player":[actor.x,actor.y,actor.z]})
		var written: Dictionary=Save.write("user://save_slot_0.json",main)
		check(written.ok,"71-instance world saves: "+str(written.reason))
		check(main.water_node._all_runtime_contacts.size()==69,"all 64 new boards and 5 fixed decks enter water contact projection")
		check(main.water_node._runtime_contact_count<=24,"foam rendering budget does not cap layout")
	else:
		for frame in 4: await process_frame
		check(main.building.query().size()==71,"cold startup restores more than 54 instances")
		check(main.building.row("built_71").get("support","")=="built_70","relocated furnishing support survives cold start")
		check(main.building.row("built_71").get("turn",0)==1,"rotation survives cold start")
		check(economy.farm.crop_of("dynamic/built_71")=="lettuce" and not economy.farm.is_dry("dynamic/built_71"),"moved crop and water survive cold start")
		check(main.actor_controller.mode()==1 and main.boat.global_position.x>120,"retired offshore edge berth returns the player to their vessel")
		check(main.building_access.berth_ids().is_empty(),"obsolete edge berth does not reappear")
		check(main.navigation.is_geometric_water(main.boat.position.x,main.boat.position.z),"distant boat pose remains navigable")
		check(Save.write("user://resaved.json",main).ok,"restored large layout remains saveable")
	main.queue_free();await process_frame
	print("[building-open-restart] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
