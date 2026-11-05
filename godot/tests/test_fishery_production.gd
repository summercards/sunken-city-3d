extends SceneTree
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var main: Node
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	print("[fishery-production] ","PASS " if value else "FAIL ",label)
	if not value: failures += 1
func advance(hours: float) -> void:
	main.world_clock.paused = false
	main.world_clock.tick(hours*main.world_clock.day_length/24.0)
	main.world_clock.paused = true
func drive_interaction() -> void:
	# The real menu remains modal while its 0.16s closing tween runs.
	for i in 120:
		if not main.hud.world_actions.is_open(): break
		await process_frame
	main.interactor.active = true
	for i in 240:
		main.actor_controller.tick(1.0/60.0)
		main.interactor.update(1.0/60.0,main.interactor.auto_hold)
	main.interactor.active = false
func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/fishery-"+label+".png")==OK,"real render "+label)
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.title_camera.begin(main.cam); main.title_camera.finish(main.cam); main._enter_game()
	main.set_process(false); main.set_physics_process(false)
	main.world_clock.paused = true; main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	var economy := root.get_node("Economy")
	economy.set_process(false)
	for i in 240:
		if not main._title_active: break
		await process_frame
	check(not main._title_active,"title transition finishes before testing gameplay input")
	var fishery = economy.fishery
	check(fishery.harvest().has("blocked"),"locked fishery cannot be harvested")
	advance(8)
	check(fishery.pending==0,"time before upgrade produces no fish")
	economy.warehouse.set_count("wood",100); economy.warehouse.set_count("fish",50)
	check(main._upgrade_fishery().get("event")=="fishery_unlocked","real upgrade starts the production cycle")
	check(not main.trade_board.is_visible_in_tree() and main._fishery_harvest.is_visible_in_tree(),"second-stage board is gone and independent harvest marker is visible")
	check(fishery.pending==0 and fishery.harvest().has("blocked"),"upgrading gives no instant catch")
	advance(3.99)
	check(fishery.pending==0,"no yield before the four-hour boundary")
	advance(.01)
	check(fishery.pending==3 and economy.count("fish")==0,"four game hours accumulate exactly three collectible fish")
	for i in 3: fishery.observe(main.world_clock.query())
	check(fishery.pending==3,"repeating the same clock does not duplicate yield")
	var marker: Node3D = main._fishery_harvest
	check(main._fishery_marker.button.caption=="收获 ×3","screen button displays the available catch")
	check(marker.find_children("*","Sprite3D",true,false).is_empty() and marker.find_children("*","Label3D",true,false).is_empty(),"harvest icon and caption have no 3D surfaces to intersect the water")
	var landing: Node3D = main._zone_nodes.zone1.landing_point("salvage")
	root.get_node("GameState").enter_zone("zone1")
	root.get_node("GameState").landing_id="salvage"
	main.actor_controller.restore_pose({"mode":0,"zone":"zone1","player":[-13.2,1.33,12.6]})
	main.boat.place_at(landing.get_node("BoatPark").global_position,0)
	main.cam.suspend_follow(); main.cam.target=Vector3(-17,1.1,18)
	main.cam.distance=37; main.cam.orbit_dir=Vector3(-.45,.8,.6); main.cam.refresh()
	main.daylight_rig.apply(9)
	main._reach_cache.clear()
	check(main._land_reach_reason(marker)=="","harvest point is reachable on the upgraded shore")
	main._open_spot_bubbles(marker)
	var labels: Array=[]
	for button: Button in main.hud.world_actions.buttons: labels.append(button.get_meta("action_label",""))
	check(labels==["收获鱼类"],"fishery offers only harvest without shop, warehouse or shipping")
	await shot("harvest-menu")
	main.hud.world_actions.close(true)
	main._fishery_marker._process(0.0)
	check(main._fishery_marker.visible and main._fishery_marker.button.kind=="fish" and main._fishery_marker.button.item_icon=="","screen button reuses the existing white fish action silhouette")
	await click(main._fishery_marker.button.get_global_rect().get_center())
	await drive_interaction()
	check(economy.count("fish")==3 and fishery.pending==0,"screen button approaches, interacts and deposits the complete catch into the backpack")
	check(marker.interact(main.player).has("blocked") and economy.count("fish")==3,"repeat harvest cannot award twice")
	await click(main._fishery_marker.button.get_global_rect().get_center())
	check(not main.hud.is_panel_open() and fishery.pending==0 and main._fishery_marker.button.caption=="生长中","empty fishery shows growth and never opens supply services")
	advance(8)
	check(fishery.pending==6,"multiple elapsed cycles accumulate")
	economy.inventory.set_count("wood",24*999)
	var before: int = economy.count("fish")
	check(fishery.harvest().has("blocked") and fishery.pending==6 and economy.count("fish")==before,"full backpack leaves accumulated fish intact")
	economy.inventory.set_count("wood",0)
	advance(100)
	check(fishery.pending==24,"long time jumps cap accumulated fish at 24")
	check(main._harvest_fishery().get("fish")==24,"full fishery can be collected")
	fishery.observe(main.world_clock.query())
	check(fishery.pending==0,"full-storage overflow cannot immediately refill after collection")
	# Sleep advances the same clock and grants only elapsed complete cycles.
	main.world_clock.wake_to_morning()
	check(fishery.pending>0,"sleep to next morning advances fish production")
	check(Save.write("user://fishery-production.json",main).ok,"production snapshot writes to disk")
	var saved: Dictionary = Save.read("user://fishery-production.json").snapshot
	var pending_before: int=fishery.pending
	var deadline_before: float=fishery.to_dict().next_hour
	main._harvest_fishery()
	check(Save.restore(main,saved).ok and fishery.pending==pending_before and fishery.to_dict().next_hour==deadline_before,"disk restore preserves catch and the exact next cycle")
	fishery.observe(main.world_clock.query())
	check(fishery.pending==pending_before,"reloaded clock does not duplicate production")
	var bad: Dictionary=saved.duplicate(true); bad.economy.fishery.pending=25
	check(not Save.restore(main,bad).ok and fishery.pending==pending_before,"over-cap corrupt save rejects before mutation")
	bad=saved.duplicate(true); bad.economy.fishery.next_hour=bad.economy.fishery.observed_hour
	check(not Save.restore(main,bad).ok,"expired production deadline rejects before mutation")
	bad=saved.duplicate(true);bad.economy.fishery.erase("pending")
	check(not Save.restore(main,bad).ok,"truncated v2 production record rejects")
	var legacy: Dictionary=saved.duplicate(true);legacy.economy.fishery={"version":1,"unlocked":true}
	check(Save.restore(main,legacy).ok and fishery.pending==0,"old upgraded save starts with zero catch and no retroactive yield")
	legacy.economy.fishery.pending=24
	check(Save.restore(main,legacy).ok and fishery.pending==0,"v1 record cannot smuggle an unvalidated v2 catch")
	advance(4)
	check(fishery.pending==3,"old upgraded save starts a complete fresh cycle")
	main.hud.hide()
	main.cam.suspend_follow(); main.cam.target=Vector3(-17.7,1.1,18.3)
	main.cam.distance=45; main.cam.orbit_dir=Vector3(-.45,.8,.6); main.cam.refresh()
	await shot("harvest-ready")
	var button_size: Vector2=main._fishery_marker.button.size
	main.cam.target=Vector3(-13.1,1.3,12.8); main.cam.distance=22; main.cam.refresh()
	main._fishery_marker._process(0.0)
	check(main._fishery_marker.visible and main._fishery_marker.button.size==button_size,"camera zoom preserves the full screen button and its size")
	await shot("harvest-close")
	print("[fishery-production] %d checks, %d failures" % [checks,failures])
	main.queue_free(); await process_frame
	quit(0 if failures==0 else 1)
