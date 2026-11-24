extends SceneTree
const Catalog = preload("res://src/building/building_catalog.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main.set_process(false);main._autosave_on=false
	var econ=root.get_node("Economy");econ.set_process(false)
	var deck_center := Catalog.ORIGIN + Vector3(.725, 0, -.075)
	if OS.get_cmdline_user_args().has("--building-seed"):
		econ.inventory.set_count("wood",50);econ.inventory.set_count("soil",10)
		main._debug_teleport("zone5")
		main.actor_controller.restore_pose({"mode":0,"player":[22.725,1.49,19.5]});root.get_node("GameState").enter_zone("zone5")
		var result: Dictionary=main.building.begin({"kind":"platform_5x5","px":.725,"pz":-.075})
		check(result.ok,"seed deck")
		if not result.ok: quit(1);return
		main.building.tick(8)
		result=main.building.begin({"kind":"planter","support":result.id,"px":.8,"pz":.5})
		check(result.ok,"seed planter")
		if not result.ok: quit(1);return
		main.building.tick(4)
		check(econ.farm.plant("dynamic/"+result.id,"lettuce").get("event")=="planted","seed crop")
		econ.farm.water("dynamic/"+result.id)
		result=main.building.begin({"kind":"platform_5x5","px":5.725,"pz":-.075})
		main.building.tick(1)
		check(result.ok,"seed unfinished work")
		main.actor_controller.restore_pose({"mode":0,"player":[deck_center.x,deck_center.y,deck_center.z]})
		var written: Dictionary=preload("res://src/save/save_game.gd").write("user://save_slot_0.json",main)
		check(written.ok,"seed saved on constructed ground: "+str(written.reason))
	else:
		for frame in 4: await process_frame
		check(main.building.query().size()==9,"startup restores six initial beds plus three construction records")
		if main.building.query().size()!=9: main.queue_free();await process_frame;quit(1);return
		check(main.farm_field.find("dynamic/built_8")!=null,"startup registers planter")
		check(econ.farm.crop_of("dynamic/built_8")=="lettuce" and not econ.farm.is_dry("dynamic/built_8"),"startup restores planted watered crop")
		check(main.player.global_position.distance_to(deck_center)<=0.3,"startup restores the actor on the added board")
		check(main._zone_nodes.zone5.walk_areas[0].contains_world(main.player.global_position.x,main.player.global_position.z),"startup ground registered and restored actor safe")
		var seconds := float(Catalog.RECIPES.platform_5x5.seconds)
		check(is_equal_approx(main.building.row("built_9").left,seconds-1),"startup preserves work time")
		check(econ.count("wood")==50-2*int(Catalog.RECIPES.platform_5x5.cost.wood)-3 and econ.count("soil")==8,"restart does not charge again")
		check(main.water_node._all_runtime_contacts.size()==6,"only fixed and finished decks produce waterline contacts")
		for mat: ShaderMaterial in main.water_node.schemes.values():
			check(int(mat.get_shader_parameter("runtime_contact_count"))==3,"rendering combines adjoining deck waterlines")
		main.building.tick(seconds)
		check(main.building.row("built_9").left==0,"restored work finishes")
		check(main.building_world.contact_rects().size()==7,"restored work adds its waterline on completion")
	main.queue_free();await process_frame
	print("[building-restart] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
