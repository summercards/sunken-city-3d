extends SceneTree
var checks:=0
var failures:=0
var main
var economy
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",text)
func click(node: Control) -> void:
	var position:=node.get_global_transform_with_canvas()*(node.size*0.5)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=position
		root.push_input(event,true);await process_frame
func key(code: int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event,true);await process_frame
func slot(pool: int, id: String) -> Control:
	for tile in main.hud.services.slots[pool]:
		if str(tile.get_meta("item_id"))==id: return tile
	return null
func action(pool: int, id: String, amount:=1) -> void:
	var tile:=slot(pool,id);check(tile!=null,"item slot exists "+id)
	if tile==null: return
	await click(tile);await create_timer(0.24).timeout
	for button in main.hud.services.action_body.get_children():
		if button is Button and int(button.get_meta("amount",0))==amount:
			await click(button);await process_frame;return
	check(false,"item action exists "+id)
func shot(name: String) -> void:
	main._process(0.0);await create_timer(0.25).timeout
	for i in 4: await process_frame
	if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png("res://outputs/"+name+".png")
func run() -> void:
	root.content_scale_size=Vector2i(1600,1000)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.interactor.set_process(false);main.cam.set_process(false)
	economy=root.get_node("Economy");economy.set_process(false)
	var plot=main.farm_field.find("home_plot")
	main.actor_controller.restore_pose({"mode":0,"player":[plot.global_position.x,plot.global_position.y,plot.global_position.z+1]})
	main.cam.global_position=Vector3(-6,14,29);main.cam.look_at(Vector3(2,2,14));main.cam.fov=38
	economy.inventory.add("fish",4);economy.inventory.add("vegetable",6);economy.inventory.add("tomato",3)
	var view=main.hud.services
	main._on_click_command("shipping");await create_timer(0.3).timeout
	check(view.visible and not main.hud._panel.visible,"shipping command uses pockets, never the old detail card")
	check(view.slots[0].size()==24 and view.slots[1].size()==8,"real backpack and paged cargo grids")
	check(not slot(0,"fish").empty_slot,"handdrawn fish entry")
	await shot("shipping-pockets-empty")
	var coins: int=economy.coins
	await action(0,"fish")
	check(economy.count("fish")==3 and economy.daily.query().items.get("fish")==1,"mouse deposit transfers exactly one")
	check(economy.coins==coins and view.total.text.contains("5"),"deposit updates pending wallet without selling")
	await action(0,"vegetable",6)
	check(economy.count("vegetable")==0 and economy.daily.query().items.get("vegetable")==6,"whole stack transfer")
	await click(slot(1,"fish"));await shot("shipping-pockets-take-back")
	await key(KEY_ESCAPE)
	await create_timer(0.18).timeout
	check(view.visible and not view.actions.visible,"Esc closes item choices before shipping view")
	await action(1,"fish")
	check(economy.count("fish")==4 and not economy.daily.query().items.has("fish"),"mouse withdraw restores fish")
	main.hud.close_card();main._on_click_command("storage");await process_frame
	check(view.visible and not main.hud._panel.visible,"warehouse also uses pockets")
	await action(0,"lettuce_seed")
	check(economy.warehouse.count("lettuce_seed")==1 and economy.count("lettuce_seed")==2,"warehouse deposit from pocket")
	await action(1,"lettuce_seed")
	check(economy.warehouse.count("lettuce_seed")==0 and economy.count("lettuce_seed")==3,"warehouse withdrawal from tray")
	await shot("warehouse-pockets")
	main.hud.close_card();main._on_click_command("shop");await process_frame
	check(view.visible and not main.hud._panel.visible,"shop also uses pockets")
	await action(1,"tomato_seed")
	check(economy.count("tomato_seed")==1 and economy.coins==coins-int(economy.farm.crop_def("tomato").seed_price),"shop illustration invokes actual seed purchase")
	await shot("shop-pockets")
	main.hud.close_card();main._on_click_command("shipping")
	for extent in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		if DisplayServer.get_name()!="headless": root.size=extent
		await process_frame;main.hud._layout()
		await shot("shipping-pockets-%dx%d" % [extent.x,extent.y])
		check(root.get_visible_rect().encloses(view.get_global_rect()),"service pockets fit "+str(extent))
		view.turn(1,5)
		check(view.pages[1]==5,"last of six cargo pages is accessible")
		view.turn(1,-5)
	var pending: Dictionary=economy.daily.query()
	economy.inventory.from_dict({"capacity":1,"counts":{"wood":40,"coins":coins}})
	main.hud._service_command("vegetable","withdraw",1)
	check(economy.daily.query().items==pending.items and economy.count("vegetable")==0,"full backpack refusal keeps queued crop")
	check(view.slots[0].size()==1,"reduced capacity cannot create fake empty pockets")
	await key(KEY_ESCAPE)
	check(not main.hud.is_panel_open(),"Esc closes shipping without opening another card")
	print("[pocket-services] ",checks," checks, ",failures," failures")
	main.queue_free();await process_frame;quit(1 if failures else 0)
