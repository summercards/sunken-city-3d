extends SceneTree
## Current Godot character and real FarmPlot/interaction entry, isolated by runner.
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var main
var actor
var farm
var economy
var started: Array = []
var finished: Array = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/receive-"+label+".png") == OK,"native render "+label)

func pose(seconds: float) -> void:
	var elapsed: float = float(actor.action_playback().get("elapsed",0.0))
	actor._process(maxf(seconds-elapsed,0.0))

func capture_clip() -> void:
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute("res://outputs/receive-clip")
	var ok := true
	actor.set_process(false)
	actor.rotation.y = PI
	main.cam.set_process(false); main.cam.follow_enabled = false
	main.cam.global_position = actor.global_position + Vector3(-2.6,2.4,-3.5)
	main.cam.look_at(actor.global_position+Vector3.UP*0.85); main.cam.fov = 35
	var plot: Node3D = main.farm_field.find("platform_plot")
	mature(plot,"pumpkin"); plot.perform("harvest")
	for frame in 96:
		if frame >= 9: actor._process(1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		ok = root.get_texture().get_image().save_png("res://outputs/receive-clip/%04d.png" % frame) == OK and ok
	check(ok,"continuous native receive animation frames")

func mature(plot, crop: String) -> void:
	var state: Dictionary = farm.to_dict()
	state.plots[plot.plot_id] = {"crop":crop,"remaining":0.0,"total":3.0,"water":1.0,"harvests":0}
	farm.from_dict(state)
	plot._sync(0.0)

func click_at(point: Vector2) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.pressed = down
		root.push_input(event,true)
		await process_frame

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on = false; main.set_process(false); main.set_physics_process(false)
	main.boat.set_process(false); main.boat.set_physics_process(false); main.interactor.set_process(false)
	main.cam.set_process(false); main.cam.follow_enabled = false
	economy = root.get_node("Economy"); economy.set_process(false); farm = economy.farm
	actor = main.player; actor.set_process(false)
	actor.action_started.connect(func(id,token): started.append([id,token]))
	actor.action_finished.connect(func(id,token): finished.append([id,token]))
	main._debug_teleport("zone5")
	for i in 8: await physics_frame; await process_frame
	var plot: Node3D = main.farm_field.find("platform_plot")
	var at := plot.global_position + Vector3(0,0,0.90)
	main.actor_controller.restore_pose({"mode":0,"player":[at.x,at.y,at.z]})
	actor.rotation.y = PI
	main.cam.global_position = at + Vector3(-2.6,2.4,-3.5)
	main.cam.look_at(at+Vector3.UP*0.85); main.cam.fov = 35
	main.hud.close_card()
	check(actor._item_receive.bag != null,"satchel is part of the current character")
	var current: int = actor.play_receive_item("lettuce")
	check(actor.play_receive_item("unknown") == 0 and actor.action_playback().token == current,"unsupported item does not replace current receipt")
	actor.cancel_action("fixture")
	var origin: Transform3D = actor.global_transform
	for crop: String in ["lettuce","tomato","pumpkin"]:
		mature(plot,crop)
		var definition: Dictionary = farm.crop_def(crop)
		var item: String = str(definition.produce)
		var count: int = economy.count(item)
		var starts: int = started.size()
		var result: Dictionary = plot.perform("harvest")
		check(result.get("event","") == "harvested","successful harvest "+crop)
		check(economy.count(item) == count+int(definition["yield"][item]),"original yield once "+crop)
		check(started.size() == starts+1,"one animation per FarmPlot success "+crop)
		check(actor.action_playback().get("id","") == "harvesting","success starts registered action "+crop)
		check(is_instance_valid(actor._item_receive.prop),"detached real produce mesh "+crop)
		if not is_instance_valid(actor._item_receive.prop): continue
		check(actor._item_receive.prop.get_meta("crop_id","") == crop,"correct produce identity "+crop)
		check(actor._item_receive.prop.find_children("*","CollisionObject3D",true,false).is_empty(),"visual has no collision "+crop)
		var business: Dictionary = economy.to_dict()
		pose(0.38); await shot(crop+"-take")
		pose(1.23)
		var prop: Node3D = actor._item_receive.prop
		check(prop.visible and prop.position.y > 1.5,"above hat hold "+crop)
		for elbow: Node3D in [actor.left_elbow,actor.right_elbow]:
			var hand: Vector3 = actor.body_pivot.to_local(elbow.to_global(elbow.get_child(1).position))
			check(hand.y > 1.35 and hand.distance_to(prop.position) < 0.29,"wrists support overhead item "+crop)
		await shot(crop+"-overhead")
		pose(1.96)
		check(prop.position.distance_to(actor._item_receive.bag.position) < 0.23,"item reaches actual satchel mouth "+crop)
		check(actor._item_receive.flap.rotation.x < -1.0,"satchel opens during tuck "+crop)
		await shot(crop+"-tuck")
		pose(2.25)
		check(not prop.visible,"item disappears only inside satchel "+crop)
		pose(2.4); actor._process(0.0)
		check(actor._item_receive.prop == null and actor.animation_state() == "idle","finish clears prop and restores idle "+crop)
		check(is_zero_approx(actor._item_receive.flap.rotation.x),"satchel closes "+crop)
		check(economy.to_dict() == business and actor.global_transform == origin,"sampling changes no business or root transform "+crop)
		await shot(crop+"-idle")
	# Actual mouse menu -> approach -> hold completion; no premature success prop.
	mature(plot,"lettuce"); main._reach_cache.clear(); main.hover._reach_cache.clear()
	await click_at(main.cam.unproject_position(plot.focus_position()+Vector3.UP*0.18))
	check(main.hud.world_actions.active,"real plot click opens action bubbles")
	await create_timer(0.35).timeout
	var harvest: Button = null
	for button: Button in main.hud.world_actions.buttons:
		if str(button.get_meta("action_label","")) == "收获": harvest = button
	check(harvest != null,"explicit harvest bubble exists")
	if harvest != null:
		await click_at(harvest.get_global_transform_with_canvas()*(harvest.size*0.5))
		await create_timer(0.25).timeout
		check(actor._item_receive.prop == null,"approach/hold does not fake a successful item")
		var before: int = started.size()
		for frame in 900:
			main.actor_controller.tick(1.0/60.0)
			main.interactor.active = not main.actor_controller.walking() and not main.hud.is_modal()
			main.interactor.update(1.0/60.0,main.interactor.auto_hold)
			if frame > 10 and main.actor_controller.auto_target == null: break
		print("[receive-input] phase=",farm.phase(plot.plot_id)," starts=",started.size()-before," actor=",actor.global_position," state=",main.actor_controller.state_id()," target=",main.actor_controller.auto_target," blocked=",main.interactor.last_blocked," modal=",main.hud.is_modal())
		check(farm.is_empty(plot.plot_id) and started.size() == before+1,"real menu harvest triggers exactly one receipt")
		actor.cancel_action("test")
	# The E path uses the same successful FarmPlot event, with no menu callback.
	mature(plot,"tomato")
	main.interactor.cancel(); main.interactor.debug_focus(plot)
	main.interactor.active = true; main.interactor._scan_left = 10.0
	var e_starts: int = started.size()
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E; e_key.pressed = true
	Input.parse_input_event(e_key); await process_frame
	main.interactor._process(0.01)
	check(actor._item_receive.prop == null,"E preparation does not display unearned produce")
	main.interactor._process(float(plot.hold_time)+0.05)
	e_key.pressed = false; Input.parse_input_event(e_key); await process_frame
	check(started.size() == e_starts+1 and actor._item_receive.prop != null and actor._item_receive.prop.get_meta("crop_id") == "tomato","E harvest starts exactly one matching produce action")
	actor.cancel_action("test"); main.interactor.cancel()
	# Full inventory refuses without changing mature crop or starting presentation.
	mature(plot,"lettuce")
	var inventory_before: Dictionary = economy.inventory.to_dict()
	economy.inventory.set_count("vegetable",0)
	economy.inventory.set_count("wood",960)
	var before_full: int = started.size()
	var full_state: Dictionary = farm.state(plot.plot_id)
	check(plot.perform("harvest").has("blocked"),"full bag rejects harvest")
	check(farm.state(plot.plot_id) == full_state and started.size() == before_full and actor._item_receive.prop == null,"failure retains crop and never celebrates")
	economy.inventory.from_dict(inventory_before)
	# Every interruption removes the held instance synchronously, with no finish.
	for reason: String in ["walking","rowing","diving","cancelled","sleep","restore","replaced"]:
		var token: int = actor.play_receive_item("pumpkin")
		pose(1.25)
		match reason:
			"walking": actor.set_walking(true)
			"rowing": actor.set_rowing(true)
			"diving": actor.set_diving(true)
			"sleep": main.actor_controller.begin_sleep()
			"restore": main.actor_controller.restore_pose({"mode":0,"player":[at.x,at.y,at.z]})
			"replaced": actor.play_farm_action("watered")
			_: actor.cancel_action(reason)
		check(actor._item_receive.prop == null and actor.left_arm.scale == Vector3.ONE,"interrupt cleans held item and stretched sleeves "+reason)
		actor._process(3.0)
		check(not finished.has(["harvesting",token]),"cancelled action cannot finish later "+reason)
		actor.cancel_action("reset"); actor.set_walking(false); actor.set_rowing(false); actor.set_diving(false)
		main.actor_controller.restore_pose({"mode":0,"player":[at.x,at.y,at.z]})
	# Frame rate independence, including long frames crossing the complete action.
	for fps in [30,60,120]:
		actor.play_receive_item("tomato")
		for frame in int(fps*1.2): actor._process(1.0/float(fps))
		check(actor._item_receive.prop != null and absf(actor._item_receive.prop.position.y-1.60) < 0.001,"same overhead pose at fps "+str(fps))
		actor._process(5.0)
		check(actor.action_playback().is_empty() and actor._item_receive.prop == null,"long frame clears transient "+str(fps))
	actor.play_receive_item("lettuce"); pose(1.2)
	var document: Dictionary = Save.encode(main)
	check(not JSON.stringify(document).contains("ReceivedItem"),"transient receipt is not saved")
	check(Save.restore(main,document).get("ok",false) and actor._item_receive.prop == null,"formal save restore clears receipt")
	await capture_clip()
	main.queue_free(); await process_frame
	print("[harvest-receive] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
