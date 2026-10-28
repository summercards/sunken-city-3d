extends SceneTree
const Art = preload("res://src/ui/illustrated_icons.gd")
var checks := 0
var failures := 0
var main
var economy
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",message)
func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
		event.position=point;event.pressed=pressed;root.push_input(event,true)
		await process_frame
func key(code: int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event,true);await process_frame
func shot(name: String) -> void:
	main._process(0.0)
	await create_timer(0.35).timeout
	for i in 4: await process_frame
	if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png("res://outputs/"+name+".png")
func run() -> void:
	root.content_scale_size=Vector2i(1600,1000)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.cam.set_process(false);main.cam.follow_enabled=false
	economy=root.get_node("Economy");economy.set_process(false);main.interactor.set_process(false)
	for icon in Art.ACTIONS: check(Art.texture(icon,true)!=null,"white silhouette available: "+icon)
	for icon in Art.ITEMS: check(Art.texture(icon)!=null,"pocket illustration available: "+icon)
	main.cam.global_position=Vector3(-6,14,29);main.cam.look_at(Vector3(2,2,14));main.cam.fov=38
	await process_frame
	var plot=main.farm_field.find("home_plot")
	var anchor: Vector2=main.cam.unproject_position(plot.global_position+Vector3.UP*0.18)
	main.hover.update_hover(anchor)
	main._debug_mouse="%f,%f" % [anchor.x,anchor.y]
	check(main.hover.target.get("node")==plot,"hover hits the chosen plot")
	check(main.hover._card.size.x<=42 and main.hover._card.find_children("*","Label",true,false).is_empty(),"hover shows one small icon, no text")
	await shot("hover-icon")
	check(main.hover._card.visible,"hover marker is actually visible after presenter updates")
	check(main.hover._card.get_theme_stylebox("panel").bg_color.is_equal_approx(Color("#438f83")),"hover marker preserves contrast after shared styling")
	main._debug_mouse=""
	await click(anchor)
	check(main.hud.world_actions.active and not main.hud.is_panel_open(),"world click opens only bubbles")
	check(main.hud.world_actions.buttons[0].scale.x<1.0 and main.hud.world_actions.buttons[0].modulate.a<1.0,"opening has a real intermediate scale and opacity")
	check(not main.hud._backdrop.visible,"world bubbles leave the scene undimmed")
	check(economy.farm.is_empty("home_plot"),"opening menu never plants")
	await shot("plot-bubble")
	var menu=main.hud.world_actions
	await key(KEY_ESCAPE)
	check(menu.closing and not main.hud.menu.active,"Esc starts collapse before pause")
	await create_timer(0.07).timeout
	check(menu.buttons[0].scale.x<1.0 and menu.buttons[0].scale.x>0.15,"closing visibly shrinks before removal")
	await create_timer(0.25).timeout
	check(not menu.root.visible and not menu.is_open(),"collapse finishes and releases input")
	main.cam.global_position=main.trade_board.global_position+Vector3(-8,12,14)
	main.cam.look_at(main.trade_board.global_position)
	main._open_spot_bubbles(main.trade_board)
	check(menu.entries.size()==3,"supply counter offers three service bubbles")
	await shot("three-service-bubbles")
	await click(Vector2(1550,700))
	await create_timer(0.25).timeout
	check(not menu.active and main.actor_controller.auto_target==null,"outside click closes without moving or executing")
	main.cam.global_position=Vector3(-6,14,29);main.cam.look_at(Vector3(2,2,14))
	# Every displayed quantity comes from Inventory. Include an actual split stack.
	for entry in [["wood",45],["parts",3],["fish",4],["shell",2],["vegetable",8],["tomato",6],["pumpkin",2],["tomato_seed",5],["pumpkin_seed",3]]:
		economy.inventory.add(str(entry[0]),int(entry[1]))
	await key(KEY_B)
	await create_timer(0.3).timeout
	var pockets=main.hud.pockets
	check(pockets.visible and not main.hud._panel.visible,"B opens the dedicated pockets")
	check(pockets.slots.size()==economy.inventory.capacity(),"pocket count equals actual capacity")
	var totals: Dictionary={};var empty:=0
	for slot in pockets.slots:
		var id:=str(slot.get_meta("item_id"))
		if id=="": empty+=1
		else: totals[id]=int(totals.get(id,0))+int(slot.get_meta("slot_count"))
	check(totals.get("wood",0)==economy.inventory.count("wood"),"split stack totals match Inventory")
	check(empty==economy.inventory.slots_free(),"empty dots equal free slots")
	check(not totals.has("coins"),"bottle caps never consume a pocket")
	await key(KEY_RIGHT)
	check(pockets.selected_name.visible,"keyboard selection shows item-name capsule")
	await shot("pockets-selected")
	await key(KEY_ENTER)
	check(pockets.actions.visible,"Enter opens the small item action bubble")
	await shot("pockets-item-actions")
	var used_before: int=economy.inventory.slots_used()
	await click(Vector2(1510,750))
	check(economy.inventory.slots_used()==used_before and main.actor_controller.auto_target==null,"modal inventory blocks world clicks")
	await key(KEY_ESCAPE)
	check(not pockets.actions.visible and main.hud.is_panel_open(),"Esc first closes item choices")
	await key(KEY_ESCAPE)
	check(not main.hud.is_panel_open() and not main.hud.menu.active,"second Esc closes pockets")
	# Check anchored menu and pockets in the three actual window sizes.
	for extent in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		if DisplayServer.get_name()!="headless": root.size=extent
		await process_frame
		main.hud.open_tab("bag");main.hud._layout()
		await shot("pockets-%dx%d" % [extent.x,extent.y])
		check(root.get_visible_rect().encloses(pockets.get_global_rect()),"pockets fit %s" % extent)
		main.hud.close_card()
		main.cam.global_position=main.trade_board.global_position+Vector3(-8,12,14)
		main.cam.look_at(main.trade_board.global_position)
		main._open_spot_bubbles(main.trade_board)
		await shot("bubbles-%dx%d" % [extent.x,extent.y])
		for button in menu.buttons: check(root.get_visible_rect().encloses(button.get_global_rect()),"bubble fits %s" % extent)
		menu.close(true)
		main.cam.global_position=Vector3(-6,14,29);main.cam.look_at(Vector3(2,2,14))
	# Cancel a selected command while travelling: no deferred seed may execute later.
	var seeds: int=economy.count("lettuce_seed")
	main._queue_plot_action(plot,"plant","lettuce")
	main.actor_controller.cancel()
	check(not main.interactor.selected_command.is_valid(),"cancel clears the selected one-shot command")
	check(economy.count("lettuce_seed")==seeds and economy.farm.is_empty("home_plot"),"cancel cannot consume or plant")
	print("[pocket-bubbles] ",checks," checks, ",failures," failures")
	main.queue_free();await process_frame
	quit(0 if failures==0 else 1)
