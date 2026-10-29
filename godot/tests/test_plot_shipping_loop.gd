extends SceneTree
var checks := 0
var failures := 0
var main
var economy

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func _init() -> void: call_deferred("run")

func click_at(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame

func find_button(text: String) -> Button:
	for button in main.hud.services.action_body.find_children("*","Button",true,false):
		if button.text==text and button.is_visible_in_tree(): return button
	for button in main.hud.world_actions.buttons:
		if main.hud.world_actions.active and str(button.get_meta("action_label",""))==text: return button
	for child in main.hud._tab_body.find_children("*","Button",true,false):
		if child.text == text: return child
	return null

func choose(text: String) -> void:
	await create_timer(0.3).timeout
	if main.hud.services.visible and text in ["放入 1","取回 1"]:
		var pool:=0 if text=="放入 1" else 1
		for tile in main.hud.services.slots[pool]:
			if str(tile.get_meta("item_id"))=="vegetable":
				await click_at(tile.get_global_transform_with_canvas()*(tile.size*0.5))
				await create_timer(0.22).timeout
				break
	var button := find_button(text)
	check(button != null and not button.disabled,"available button "+text)
	if button == null or button.disabled: return
	await click_at(button.get_global_transform_with_canvas()*(button.size*0.5))
	await settle_action()

func settle_action() -> void:
	await create_timer(0.23).timeout
	for frame in 1800:
		main.actor_controller.tick(1.0/60.0)
		main.interactor.active = not main.actor_controller.walking() and not main.hud.is_modal()
		main.interactor.update(1.0/60.0,main.interactor.auto_hold)
		if frame>10 and main.actor_controller.auto_target==null: break
	await process_frame

func interact_world(node: Node3D) -> void:
	main.hud.close_card()
	main.hud.world_actions.close(true)
	await process_frame
	var anchor: Vector3 = node.focus_position() if node.has_method("focus_position") else node.global_position
	anchor += Vector3.UP*(0.18 if node.is_in_group("farm_plots") else 0.75)
	var screen: Vector2 = main.cam.unproject_position(anchor)
	var hit: Dictionary = main.hover._pick(screen)
	check(hit.get("node")==node,"screen pick selects "+node.name)
	await click_at(screen)
	print("[plot-input] ",node.name," screen=",screen," state=",main.actor_controller.state_id()," target=",main.actor_controller.auto_target," hover=",root.gui_get_hovered_control())
	for frame in 1800:
		main.actor_controller.tick(1.0/60.0)
		main.interactor.active = not main.actor_controller.walking() and not main.hud.is_modal()
		main.interactor.update(1.0/60.0,main.interactor.auto_hold)
		if main.hud.is_panel_open() or (frame>10 and main.actor_controller.auto_target==null): break
	await process_frame

func snapshot(name: String) -> void:
	main._process(0.0)
	for i in 8: await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("res://outputs/"+name+".png")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	economy=root.get_node("Economy")
	economy.set_process(false)
	main.interactor.set_process(false)
	main.cam.set_process(false)
	main.cam.follow_enabled=false
	var farm = economy.farm
	var daily = economy.daily
	var clock = main.world_clock
	check(preload("res://src/inventory/item_db.gd").label("coins")=="瓶盖","currency display renamed without changing saved ID")
	check(clock.query().hour==7.0,"new day starts at 07:00")
	for id in ["lettuce","tomato","pumpkin"]: check(farm.grow_days(id)==3,"three days for "+id)
	main._on_destination("zone5")
	for frame in 8000:
		if not main.boat.starts_sailing(): break
		main.boat._steer(1.0/60.0)
	check(root.get_node("GameState").current_zone=="zone5","sail to cultivation platform")
	var zone = main._zone_nodes.zone5
	var legacy: Dictionary = preload("res://src/save/save_game.gd").encode(main)
	legacy.game.mode=0
	legacy.game.player=[21.0,1.25,16.0]
	check(preload("res://src/save/save_game.gd").restore(main,legacy).ok and is_equal_approx(main.player.global_position.y,1.48),"old platform position snaps to new wooden deck")
	main.cam.global_position=Vector3(16,12,27)
	main.cam.look_at(Vector3(22,1.2,16))
	main.cam.fov=40
	await process_frame
	var plot = main.farm_field.find("platform_plot")
	for i in 6:
		var id := "platform_plot" if i==0 else "platform_plot:%d" % i
		var cell = main.farm_field.find(id)
		check(cell!=null and cell.scale.x>1.3,"independent full soil cell "+id)
		var hit: Dictionary = main.hover._pick(main.cam.unproject_position(cell.global_position+Vector3.UP*0.18))
		check(hit.get("node")==cell,"six cells separately selectable "+id)
	await interact_world(plot)
	check(main.hud.world_actions.active and farm.is_empty("platform_plot"),"click opens action bubbles, never plants automatically")
	check(not main.hud.is_panel_open(),"no oversized detail card on plot click")
	check(find_button("种植")!=null,"owned seeds offered")
	await snapshot("plot-select-seed")
	check(main._owned_seeds()==["lettuce"],"only owned seed pack is offered")
	await choose("种植")
	# 二级：选种子。即使背包里只有一种种子也要给玩家看一眼再种
	# （SEA-FARM-R09），所以这里必须再点一次作物名。
	check(find_button("生菜")!=null,"plant opens the seed picker")
	await snapshot("plot-seed-picker")
	await choose("生菜")
	check(economy.count("lettuce_seed")==2 and farm.crop_of("platform_plot")=="lettuce","seed click consumes exactly one")
	check(farm.is_dry("platform_plot"),"planting does not secretly water")
	await interact_world(plot)
	check(find_button("浇水")!=null,"planted cell offers water")
	await choose("浇水")
	check(not farm.is_dry("platform_plot") and farm.watering_can==11,"explicit watering consumes one unit")
	await interact_world(plot)
	check(find_button("浇水")!=null and not find_button("浇水").available,"repeat watering unavailable")
	main.hud.world_actions.close(true)
	main.hud.close_card()
	await snapshot("plot-day-0-watered")
	var stages := []
	for day in 3:
		clock.rest_to_morning()
		plot._sync(0.0)
		# 阶段由 SEA-CROP 的 CropView 负责；资产四阶段为 seed/sprout/leaf/harvest。
		stages.append(plot.current_stage())
		await snapshot("plot-day-%d" % (day+1))
		if day<2:
			await interact_world(plot)
			await choose("浇水")
			main.hud.close_card()
	check(stages==[1,2,3],"each dawn has a different visible growth stage")
	check(farm.phase("platform_plot")=="ready","mature after three watered mornings")
	await interact_world(plot)
	check(farm.phase("platform_plot")=="ready","mature click waits for explicit harvest")
	await choose("收获")
	check(farm.is_empty("platform_plot") and economy.count("vegetable")==2,"world click harvests to bag")
	main.hud.close_card()
	main._on_destination("zone1")
	for frame in 9000:
		main.actor_controller.tick(1.0/60.0)
		if main.boat.starts_sailing(): main.boat._steer(1.0/60.0)
		if root.get_node("GameState").current_zone=="zone1" and not main.boat.starts_sailing(): break
	check(root.get_node("GameState").current_zone=="zone1","return home with produce")
	main.cam.global_position=Vector3(-6,14,29)
	main.cam.look_at(Vector3(2,2,14))
	main.cam.fov=38
	var box = main._zone_nodes.zone1.get_node("Objects/ShippingBox")
	check(main._zone_nodes.zone1.landing_point("main").ground().contains_world(box.global_position.x,box.global_position.z),"shipping box is on accessible dock")
	await snapshot("dock-shipping-box")
	await interact_world(box)
	await choose("放入 / 取回")
	check(main.hud._tab=="shipping","dock box opens shipping inventory")
	check(main.hud.services.visible and not main.hud._panel.visible,"physical box opens pocket grid instead of legacy detail form")
	var coins: int = economy.coins
	await choose("放入 1")
	check(daily.query().items.get("vegetable",0)==1 and economy.count("vegetable")==1,"GUI deposits harvest")
	await choose("取回 1")
	check(daily.query().items.is_empty() and economy.count("vegetable")==2,"can cancel shipment")
	await choose("放入 1")
	await snapshot("shipping-before-pickup")
	var tomorrow: int = clock.day+1
	clock.from_dict({"day":tomorrow,"seconds":25199.0,"day_length":1200.0})
	check(economy.coins==coins and daily.query().expected>0,"06:59:59 keeps shipment")
	clock.tick(0.02)
	check(economy.coins==coins+6 and daily.query().items.is_empty(),"07:00 collector pays bottle caps once")
	daily.observe(clock.query())
	check(economy.coins==coins+6,"same morning cannot pay twice")
	var saves = preload("res://src/save/save_game.gd")
	check(saves.write("user://plot-loop.json",main).ok,"save after new 07:00 boundary")
	check(saves.restore(main,saves.read("user://plot-loop.json").snapshot).ok,"restore harvested cell and settled box")
	print("[plot-shipping] ",checks," checks, ",failures," failures")
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
