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
				var result: Dictionary=main.building.begin({"kind":"deck","x":x,"z":z})
				check(result.ok,"large ocean deck accepted "+str(Vector2i(x,z)))
				main.building.tick(3.0)
		var point:=Catalog.tile_rect(51,21).get_center()
		var planted: Dictionary=main.building.begin({"kind":"planter_small","support":"built_10","px":point.x,"pz":point.y})
		check(planted.ok,"large-layout furnishing accepted")
		main.building.tick(3.0)
		check(economy.farm.plant("dynamic/"+planted.id,"lettuce").get("event")=="planted","large-layout crop planted")
		economy.farm.water("dynamic/"+planted.id)
		point=Catalog.tile_rect(57,27).get_center()
		var moved: Dictionary=main.building.move(planted.id,{"support":"built_64","px":point.x,"pz":point.y,"turn":1})
		check(moved.ok,"crop moves to last-created support")
		var actor:=Catalog.ORIGIN+Vector3(Catalog.tile_rect(50,20).get_center().x,0,Catalog.tile_rect(50,20).get_center().y)
		root.get_node("GameState").landing_id="built:built_1:2"
		root.get_node("GameState").enter_zone("zone5")
		main.actor_controller.restore_pose({"mode":0,"player":[actor.x,actor.y,actor.z]})
		var written: Dictionary=Save.write("user://save_slot_0.json",main)
		check(written.ok,"65-instance offshore world saves: "+str(written.reason))
		check(main.water_node._all_runtime_contacts.size()==64,"all64 boards enter water contact projection")
		check(main.water_node._runtime_contact_count<=24,"foam rendering budget does not cap layout")
	else:
		check(main.building.query().size()==65,"cold startup restores more than54 instances")
		check(main.building.row("built_65").get("support","")=="built_64","relocated furnishing support survives cold start")
		check(main.building.row("built_65").get("turn",0)==1,"rotation survives cold start")
		check(economy.farm.crop_of("dynamic/built_65")=="lettuce" and not economy.farm.is_dry("dynamic/built_65"),"moved crop and water survive cold start")
		check(main.player.global_position.x>120,"distant actor is not clamped back to old world")
		check(main._current_landing()!=null and main._current_landing().landing_id=="built:built_1:2","distant dynamic landing rebuilt after cold start")
		check(main.navigation.is_geometric_water(main.boat.position.x,main.boat.position.z),"distant boat pose remains navigable")
		check(Save.write("user://resaved.json",main).ok,"restored large layout remains saveable")
	main.queue_free();await process_frame
	print("[building-open-restart] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
