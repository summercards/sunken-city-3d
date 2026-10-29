extends SceneTree
## Initial six soil cells use their stable scene IDs and the real mouse/menu chain.
## Runtime fixtures add seeds only after checking the unmodified starting inventory.
const Save = preload("res://src/save/save_game.gd")
const IDS := ["platform_plot","platform_plot:1","platform_plot:2","platform_plot:3","platform_plot:4","platform_plot:5"]
var checks := 0
var failures := 0
var main
var economy
var farm

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func click_at(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		root.push_input(event,true)
		await process_frame

func settle_action() -> void:
	await create_timer(0.24).timeout
	for frame in 2400:
		main.actor_controller.tick(1.0/60.0)
		main.interactor.active=not main.actor_controller.walking() and not main.hud.is_modal()
		main.interactor.update(1.0/60.0,main.interactor.auto_hold)
		if frame>10 and main.actor_controller.auto_target==null: break
	await process_frame
	print("[initial-planter-settled] actor=",main.player.global_position," state=",main.actor_controller.state_id()," target=",main.actor_controller.auto_target," walk_target=",main.actor_controller.walk_target)

func find_action(label: String) -> Button:
	if not main.hud.world_actions.active: return null
	for button: Button in main.hud.world_actions.buttons:
		if str(button.get_meta("action_label",""))==label: return button
	return null

func choose(label: String) -> void:
	await create_timer(0.32).timeout
	var button := find_action(label)
	check(button!=null and not button.disabled and bool(button.available),"available mouse action "+label)
	if button==null or button.disabled or not bool(button.available): return
	await click_at(button.get_global_transform_with_canvas()*(button.size*0.5))
	await settle_action()

func select_plot(plot: Node3D) -> void:
	main.hud.close_card();main.hud.world_actions.close(true)
	await process_frame
	var reason: String=main._land_reach_reason(plot)
	check(reason=="","initial cell reachable "+str(plot.plot_id)+" "+reason)
	var at: Vector2=main.cam.unproject_position(plot.focus_position()+Vector3.UP*0.18)
	var hit: Dictionary=main.hover._pick(at)
	check(hit.get("node")==plot,"screen ray selects independent cell "+str(plot.plot_id))
	await click_at(at)
	check(main.hud.world_actions.active,"real world click opens menu "+str(plot.plot_id))
	print("[initial-planter-input] id=",plot.plot_id," actor=",main.player.global_position," state=",main.actor_controller.state_id()," anchors=",plot.get_meta("approach_points",[]))

func screenshot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var path: String="res://outputs/initial-planters-"+label+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"save native render "+label)
	print("[initial-planter-shot] ",path)

func standing(at: Vector3) -> void:
	main.actor_controller.restore_pose({"mode":0,"player":[at.x,at.y,at.z]})
	main._reach_cache.clear();main.hover._reach_cache.clear()

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	main.boat.set_process(false);main.boat.set_physics_process(false);main.interactor.set_process(false)
	main.cam.set_process(false);main.cam.follow_enabled=false
	economy=root.get_node("Economy");economy.set_process(false);farm=economy.farm
	for i in 8: await physics_frame;await process_frame
	check(economy.count("lettuce_seed")==3,"new game still starts with only three lettuce seeds")
	check(main.building.query().is_empty(),"initial scene cells are not duplicate refundable DIY instances")
	var initial: Dictionary=Save.encode(main)
	var fixed: Array=[]
	for id: String in IDS:
		var plot: Node3D=main.farm_field.find(id)
		check(plot!=null,"initial stable scene cell registered "+id)
		if plot==null: continue
		fixed.append(plot)
		check(not farm.spec(id).is_empty() and farm.access_reason(id)=="","initial cell is immediately unlocked "+id)
		check(initial.economy.farm.plots.has(id) and str(initial.economy.farm.plots.get(id,{}).get("crop","missing"))=="","new snapshot explicitly contains empty cell "+id)
		var anchors: Array=plot.get_meta("approach_points",[])
		check(not anchors.is_empty(),"initial cell has operation anchors "+id)
		var has_center:=false
		for point: Vector3 in anchors:
			if point.distance_to(plot.global_position)<0.01: has_center=true
		check(has_center,"passable initial cell includes centre operation point "+id)
	check(fixed.size()==6,"exactly six stable original cells are available")
	if fixed.size()!=6:
		finish();return
	var written: Dictionary=Save.write("user://initial-six-empty.json",main)
	check(written.get("ok",false),"save new game with six explicit empty states")
	# A legacy save contains only the original first ID. Preserve all crop fields,
	# fill the other authored cells, and retain the same scene models and IDs.
	var legacy: Dictionary=initial.duplicate(true)
	var legacy_crop: Dictionary={"crop":"tomato","remaining":2.0,"total":3.0,"water":1.0,"harvests":1}
	legacy.economy.farm.plots={"platform_plot":legacy_crop.duplicate(true)}
	check(Save.restore(main,legacy).get("ok",false),"restore legacy snapshot with only the original first plot")
	check(farm.state("platform_plot")==legacy_crop,"legacy crop/water/remaining/total/harvests preserved exactly")
	for id: String in IDS:
		check(farm.to_dict().plots.has(id),"legacy restore fills initial state "+id)
	var before_rebuild: Dictionary=farm.to_dict()
	for repeat in 2:
		main.farm_field.build();main.building_world.sync()
		for id: String in IDS: farm.register_plot(farm.spec(id))
	check(farm.to_dict()==before_rebuild,"repeated field rebuild and plot registration retain crop state")
	for i in IDS.size():
		check(main.farm_field.find(IDS[i])==fixed[i],"rebuild retains original model instance "+str(IDS[i]))
	check(Save.restore(main,initial).get("ok",false),"restore unmodified new-game inventory and empty cells")
	check(economy.count("lettuce_seed")==3,"compatibility checks preserve starting seed quantity")
	# Only this isolated test fixture supplies enough seeds to exercise all six.
	economy.inventory.set_count("lettuce_seed",9)
	main._debug_teleport("zone5")
	main.cam.set_process(false);main.cam.follow_enabled=false
	for i in 12:
		main.cam.global_position=Vector3(16,12,27);main.cam.look_at(Vector3(22,1.2,16));main.cam.fov=40
		await process_frame
	var starts: Array=[Vector3.ZERO,Vector3(25,1.48,16),Vector3(22,1.48,13.5),Vector3(22,1.48,18.3),Vector3(19.1,1.48,16),Vector3(24,1.48,17.45)]
	for i in fixed.size():
		var plot: Node3D=fixed[i]
		if i==0:
			main.actor_controller.restore_pose({"mode":1})
			main._reach_cache.clear();main.hover._reach_cache.clear()
		else: standing(starts[i])
		await select_plot(plot)
		check(farm.is_empty(plot.plot_id),"click does not plant automatically "+str(plot.plot_id))
		await choose("种植")
		check(find_action("生菜")!=null,"seed picker is explicit for "+str(plot.plot_id))
		await choose("生菜")
		check(farm.crop_of(plot.plot_id)=="lettuce","real menu plants initial cell "+str(plot.plot_id))
		check(main.actor_controller.state_id()=="ashore_idle" and main.actor_controller.auto_target==null,"approach completes once "+str(plot.plot_id))
	check(economy.count("lettuce_seed")==3,"six real plant actions consume exactly six fixture seeds")
	var refills:=0
	for day in 3:
		for plot: Node3D in fixed:
			await select_plot(plot)
			var water_action: String="补水并浇水" if find_action("补水并浇水")!=null else "浇水"
			if water_action=="补水并浇水": refills+=1
			await choose(water_action)
			check(farm.phase(plot.plot_id)=="growing" and float(farm.state(plot.plot_id).water)==1.0,"real menu waters cell "+str(plot.plot_id)+" day "+str(day))
		main.world_clock.rest_to_morning()
		for plot: Node3D in fixed: plot._sync(0.0)
	check(refills==1,"eighteen waterings include one real refill-and-water action at original capacity")
	for plot: Node3D in fixed: check(farm.phase(plot.plot_id)=="ready","three watered mornings mature initial cell "+str(plot.plot_id))
	standing(Vector3(22,1.48,16))
	await screenshot("six-ready")
	var ready: Dictionary=Save.encode(main)
	check(Save.write("user://initial-six-ready.json",main).get("ok",false),"save all six mature initial plots")
	var vegetables: int=economy.count("vegetable")
	for i in fixed.size():
		var plot: Node3D=fixed[i]
		await select_plot(plot)
		check(farm.phase(plot.plot_id)=="ready" and economy.count("vegetable")==vegetables+i*2,"mature click waits for explicit harvest "+str(plot.plot_id))
		if i==0: await screenshot("harvest-menu")
		await choose("收获")
		check(farm.is_empty(plot.plot_id) and economy.count("vegetable")==vegetables+(i+1)*2,"real menu harvests original yield "+str(plot.plot_id))
	check(Save.restore(main,ready).get("ok",false),"restore six planted cells through formal save adapters")
	for id: String in IDS: check(farm.phase(id)=="ready","mature state restored at stable ID "+id)
	await screenshot("restored-six-ready")
	finish()

func finish() -> void:
	main.queue_free();await process_frame
	print("[initial-planters] ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
