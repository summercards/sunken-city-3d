extends SceneTree
var checks:=0
var failures:=0
var main
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		root.push_input(event,true);await process_frame
func button(node: Button) -> void:
	await click(node.get_global_transform_with_canvas()*(node.size/2))
func key(code: Key) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true;root.push_input(event,true);await process_frame
func shot(name: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/building-"+name+".png")
func aim() -> void:
	main.cam.global_position=Vector3(17,17,31);main.cam.look_at(Vector3(23,1.4,16));main.cam.fov=40
func settle() -> void:
	await create_timer(0.25).timeout
	for frame in 2200:
		main.actor_controller.tick(1.0/60)
		main.interactor.active=not main.actor_controller.walking() and not main.hud.is_modal()
		main.interactor.update(1.0/60,main.interactor.auto_hold)
		if frame>10 and main.actor_controller.auto_target==null: break
	await process_frame
func bubble(label: String) -> void:
	await create_timer(0.35).timeout
	var found: Button
	for node in main.hud.world_actions.buttons:
		if node.get_meta("action_label","")==label: found=node
	check(found!=null,"bubble "+label)
	if found!=null: await button(found);await settle()
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.cam.set_process(false);main.cam.follow_enabled=false
	main.interactor.set_process(false)
	var econ=root.get_node("Economy");econ.set_process(false)
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode":0,"player":[21,1.48,16]});root.get_node("GameState").enter_zone("zone5")
	econ.inventory.set_count("wood",30);econ.inventory.set_count("soil",6)
	aim();await process_frame
	await button(main.hud.corner.menu_button)
	check(main.hud.corner.buttons.craft.is_visible_in_tree(),"eighth launcher visible")
	await shot("menu")
	await button(main.hud.corner.buttons.craft)
	check(main.building_controller.book.visible,"mouse opens book")
	await shot("book")
	check(main.hud.is_modal(),"book stays modal after menu sync")
	await button(main.building_controller.book.recipe_buttons.deck)
	check(not main.building_controller.book.visible and main.building_controller.recipe=="deck","mouse chooses deck")
	await shot("ghosts")
	var target:=Vector3(26.3,1.48,14.7125)
	await click(main.cam.unproject_position(target))
	check(main.building.query().size()==1,"world click starts deck")
	main.building_controller.tick(1)
	await shot("progress")
	check(main.building_controller.progress.size()==1,"progress visible")
	await key(KEY_ESCAPE)
	check(not main.building_controller.active and not main.hud.menu.active and not paused,"escape closes placement without pause")
	main.building_controller.tick(2)
	check(main.building.query()[0].left==0,"closed mode still completes")
	await button(main.hud.corner.menu_button);await button(main.hud.corner.buttons.craft)
	await button(main.building_controller.book.recipe_buttons.planter)
	await key(KEY_R)
	check(main.building_controller.turn==1,"rotate key")
	await key(KEY_R);await key(KEY_R);await key(KEY_R)
	await click(main.cam.unproject_position(target))
	check(main.building.query().size()==2,"mouse places planter")
	main.building_controller.tick(4);await key(KEY_ESCAPE)
	var plot=main.farm_field.find("dynamic/built_2")
	check(plot!=null,"built soil exists")
	if plot==null: quit(1);return
	await shot("completed")
	await click(main.cam.unproject_position(plot.global_position+Vector3.UP*0.18))
	check(main.hud.world_actions.active,"built plot opens regular bubbles")
	await bubble("种植");await bubble("生菜")
	check(econ.farm.crop_of(plot.plot_id)=="lettuce","mouse seeds new plot")
	await click(main.cam.unproject_position(plot.global_position+Vector3.UP*0.18))
	await bubble("浇水")
	check(not econ.farm.is_dry(plot.plot_id),"mouse waters new plot")
	await shot("planted")
	main.hud.world_actions.close(true)
	main.hud.open_tab("shop");await process_frame
	var tile: Button
	for node in main.hud.services.slots[1]:
		if node.get_meta("item_id","")=="soil": tile=node
	check(tile!=null,"soil catalog tile")
	if tile!=null:
		await button(tile);await create_timer(0.3).timeout
		var before: int=econ.count("soil")
		await button(main.hud.services.action_body.get_child(0))
		check(econ.count("soil")==before+1,"mouse buys soil")
	await shot("soil-shop")
	main.hud.close_card()
	# Frame the real floating mesh as evidence, without changing its spawn position.
	var drift: Vector3=main.props.crates[0].base
	main.cam.global_position=drift+Vector3(-5,7,8);main.cam.look_at(drift);main.cam.fov=35
	await shot("driftwood")
	main.queue_free();await process_frame
	print("[visual-building] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
