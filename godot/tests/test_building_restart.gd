extends SceneTree
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
	if OS.get_cmdline_user_args().has("--building-seed"):
		econ.inventory.set_count("wood",50);econ.inventory.set_count("soil",10)
		main._debug_teleport("zone5")
		main.actor_controller.restore_pose({"mode":0,"player":[21,1.48,16]});root.get_node("GameState").enter_zone("zone5")
		var result: Dictionary=main.building.begin({"kind":"deck","x":3,"z":0})
		check(result.ok,"seed deck")
		main.building.tick(3)
		result=main.building.begin({"kind":"planter","support":result.id,"px":4.3,"pz":-1.3})
		check(result.ok,"seed planter")
		main.building.tick(4)
		check(econ.farm.plant("dynamic/"+result.id,"lettuce").get("event")=="planted","seed crop")
		econ.farm.water("dynamic/"+result.id)
		result=main.building.begin({"kind":"deck","x":3,"z":1})
		main.building.tick(1)
		check(result.ok,"seed unfinished work")
		main.actor_controller.restore_pose({"mode":0,"player":[26.3,1.48,16]})
		var written: Dictionary=preload("res://src/save/save_game.gd").write("user://save_slot_0.json",main)
		check(written.ok,"seed saved on constructed ground: "+str(written.reason))
	else:
		check(main.building.query().size()==3,"startup restores layout")
		if main.building.query().size()!=3: main.queue_free();await process_frame;quit(1);return
		check(main.farm_field.find("dynamic/built_2")!=null,"startup registers planter")
		check(econ.farm.crop_of("dynamic/built_2")=="lettuce" and not econ.farm.is_dry("dynamic/built_2"),"startup restores planted watered crop")
		check(main.player.global_position.is_equal_approx(Vector3(26.3,1.48,16)),"startup restores standing on new plank")
		check(main._zone_nodes.zone5.walk_areas[0].contains_world(26.3,16),"startup ground registered")
		check(is_equal_approx(main.building.row("built_3").left,2),"startup preserves work time")
		check(econ.count("wood")==35 and econ.count("soil")==8,"restart does not charge again")
		main.building.tick(2)
		check(main.building.row("built_3").left==0,"restored work finishes")
	main.queue_free();await process_frame
	print("[building-restart] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
