extends SceneTree
## Real input coverage for the DIY editor. Run via the isolated runner with
## a visual-* name; point ownership and crop preservation use the real game.
const Catalog = preload("res://src/building/building_catalog.gd")
var main: Node
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func click(screen: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.position = screen; event.pressed = pressed
		root.push_input(event,true); await process_frame

func button(node: Button) -> void:
	# Wait for the first visible book layout and the renderer to agree on its
	# hit rectangles before dispatching a real click on a fresh game window.
	await create_timer(0.25).timeout
	await click(node.get_global_transform_with_canvas()*(node.size/2))

func key(code: Key,pressed := true) -> void:
	var event := InputEventKey.new(); event.physical_keycode = code; event.pressed = pressed
	root.push_input(event,true); await process_frame

func wait_action() -> void:
	for i in 1800:
		main.actor_controller.tick(1.0/60.0)
		main.building_controller.tick(1.0/60.0)
		if i > 2 and main.building_controller.pending.is_empty(): return

func shot(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/diy-"+name+".png")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on = false; main.set_process(false); main.set_physics_process(false); main.interactor.set_process(false)
	main.cam.set_process(false); main.cam.follow_enabled = false; main.boat.set_process(false)
	var econ: Node = root.get_node("Economy"); econ.set_process(false)
	await process_frame
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode":0,"player":[21.0,1.48,16.0]})
	root.get_node("GameState").enter_zone("zone5")
	econ.inventory.set_count("wood",180); econ.inventory.set_count("soil",30)
	for cell in [Vector2i(3,0),Vector2i(4,0),Vector2i(3,1),Vector2i(4,1)]:
		var made: Dictionary = main.building.begin({"kind":"deck","x":cell.x,"z":cell.y})
		check(made.ok,"DIY fixture deck "+str(cell))
		main.building.tick(3.0)
	await physics_frame; await physics_frame
	main.cam.global_position = Vector3(20,19,29)
	main.cam.look_at(Vector3(25.0,1.4,16.0)); main.cam.fov = 41
	var controller: Node = main.building_controller
	controller.open()
	for i in 12: await process_frame
	check(controller.book.recipe_buttons.has("planter_small"),"compact furnishing in book")
	check(controller.book.recipe_buttons.has("move") and controller.book.recipe_buttons.has("remove"),"management operations in book")
	await shot("book")
	await button(controller.book.recipe_buttons.planter_small)
	check(controller.recipe == "planter_small" and not controller.book.visible,"mouse selects compact furnishing")
	var source := Catalog.ORIGIN+Vector3(4.3,0,-1.2875)
	var precision_point := source+Vector3(0.027,0,0.033)
	controller.update_preview(main.cam.unproject_position(precision_point))
	check(is_equal_approx(float(controller.preview.get("px",NAN)),4.3),"default placement uses 0.1m snapping")
	await key(KEY_SHIFT)
	controller.update_preview(main.cam.unproject_position(precision_point))
	check(controller.precision_held and is_equal_approx(float(controller.preview.get("px",NAN)),4.33),"Shift enables 0.01m placement")
	await key(KEY_SHIFT,false)
	await key(KEY_R)
	check(controller.turn == 1,"rotation key reaches editor")
	await key(KEY_R); await key(KEY_R); await key(KEY_R)
	var before: int = main.building.query().size()
	await click(main.cam.unproject_position(source)); await wait_action()
	check(main.building.query().size() == before+1,"real click builds compact furnishing after approach")
	main.building.tick(4.0)
	await physics_frame; await physics_frame
	var planter: Dictionary = {}
	for row in main.building.query():
		if row.kind == "planter_small": planter = row
	if planter.is_empty():
		print("[building-diy-visual] %d checks, %d failures"%[checks,failures]); quit(1); return
	var id: String = planter.id
	var plot: Node = main.farm_field.find("dynamic/"+id)
	check(plot != null,"compact furnishing registers real farm cell")
	if plot == null: quit(1); return
	econ.inventory.set_count("lettuce_seed",3)
	check(plot.perform("plant","lettuce").get("event") == "planted","crop exists before move")
	var crop_before: Dictionary = econ.farm.state(plot.plot_id).duplicate(true)
	var wood_before: int = econ.count("wood")
	await key(KEY_M)
	check(controller.recipe == "move","M opens move tool")
	await click(main.cam.unproject_position(source))
	check(controller.moving_id == id,"mouse picks furnishing without moving original")
	check(main.building.row(id) == planter,"selection leaves authoritative layout unchanged")
	await key(KEY_ESCAPE)
	check(controller.active and controller.moving_id == "" and main.building.row(id) == planter,"Esc cancels move selection without losing item")
	await click(main.cam.unproject_position(source))
	var destination := Catalog.ORIGIN+Vector3(6.45,0,-1.2875)
	controller.update_preview(main.cam.unproject_position(destination))
	await shot("move-preview")
	await click(main.cam.unproject_position(destination)); await wait_action()
	var moved: Dictionary = main.building.row(id)
	check(not moved.is_empty() and float(moved.px) > 6.3,"real click moves furnishing across deck seam state="+main.actor_controller.state_id()+" pos="+str(main.player.global_position)+" path="+str(main.actor_controller.walk_path)+" message="+main.hud._toast.text)
	check(moved.id == id and moved.support != planter.support,"move preserves instance id and changes support")
	check(econ.count("wood") == wood_before,"move does not charge materials")
	check(econ.farm.state("dynamic/"+id) == crop_before,"move preserves crop and growth state")
	await key(KEY_DELETE)
	controller.update_preview(main.cam.unproject_position(main.building_world.position_for(moved)))
	check(controller.hint.text.contains("作物") or controller.hint.text.contains("收获"),"occupied crop removal explains refusal")
	await click(main.cam.unproject_position(main.building_world.position_for(moved))); await wait_action()
	check(not main.building.row(id).is_empty(),"occupied crop cannot be removed")
	var support_id := ""
	for row in main.building.query():
		if row.kind == "deck" and row.x == 3 and row.z == 1: support_id = row.id
	var empty_result: Dictionary = main.building.begin({"kind":"planter_small","px":4.3,"pz":1.3,"support":support_id,"turn":0})
	check(empty_result.ok,"empty furnishing fixture accepted")
	if empty_result.ok:
		main.building.tick(3.0)
		await physics_frame; await physics_frame
		var empty: Dictionary = main.building.row(empty_result.id)
		var refund_wood: int = econ.count("wood"); var refund_soil: int = econ.count("soil")
		await click(main.cam.unproject_position(main.building_world.position_for(empty))); await wait_action()
		check(main.building.row(empty_result.id).is_empty(),"mouse removes empty furnishing")
		check(econ.count("wood") == refund_wood+2 and econ.count("soil") == refund_soil+1,"remove refunds full recipe atomically")
	controller.select_recipe("deck")
	var remote: Dictionary = {"kind":"deck","x":40,"z":4}
	controller.update_preview(main.cam.unproject_position(main.building_world.position_for(remote)))
	check(not controller.preview.is_empty() and controller.preview.x == 40 and controller.preview.z == 4,"mouse preview exists beyond old ring envelope")
	check(controller.candidate_ghosts.size() <= controller.MAX_FRONTIER_GHOSTS,"rendering frontier budget is bounded")
	await shot("finished")
	controller.close(); main.queue_free(); await process_frame
	print("[building-diy-visual] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
