extends SceneTree
## Current Godot character and real FarmPlot/interaction entry, isolated by runner.
const Save = preload("res://src/save/save_game.gd")
## Reference-metre thresholds below are multiplied by the body scale (SEA-AVATAR-R27).
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const AvatarSupport = preload("res://tests/avatar_customization_support.gd")
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
	main.cam.look_at(actor.global_position+Vector3.UP*0.95*Dimensions.SCALE); main.cam.fov = 35
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

func gesture_contract() -> void:
	var subject = preload("res://src/player/character.gd").new()
	root.add_child(subject); subject.build(); subject.set_process(false); subject.set_physics_process(false)
	for shape in [Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(.5,.5)]:
		subject.apply_avatar(AvatarSupport.profile({}, {"body_build":shape.x,"head_size":shape.y,"head_width":1.0,"arm_girth":1.0,"leg_length":0.0}))
		for fps in [30,60,120]:
			subject.play_receive_item("pumpkin")
			var origin: Transform3D = subject.transform
			var length_error := 0.0
			var shoulder_error := 0.0
			var bone_error := 0.0
			var finite := true
			var length_scale: float = subject._avatar_factors.arm_length
			for frame in int(2.4*fps):
				subject._process(1.0/fps)
				for side in [-1,1]:
					var arm: Node3D = subject.left_arm if side < 0 else subject.right_arm
					var elbow: Node3D = subject.left_elbow if side < 0 else subject.right_elbow
					var hand: Node3D = elbow.get_node("Hand")
					length_error = maxf(length_error,absf(elbow.position.y+Dimensions.UPPER_ARM*length_scale))
					length_error = maxf(length_error,absf(hand.position.y+Dimensions.LOWER_ARM*length_scale))
					shoulder_error = maxf(shoulder_error,arm.position.distance_to(subject.avatar_shoulder(side)))
					finite = finite and arm.transform.is_finite() and elbow.transform.is_finite() and hand.global_position.is_finite()
					for segment in ["upper_skin","lower_skin"]:
						var bone: int = subject.limb_skinning.find_bone(("arm.L." if side < 0 else "arm.R.")+segment)
						bone_error = maxf(bone_error,absf(subject.limb_skinning.get_bone_pose_scale(bone).y-length_scale))
			var label := " shape=%s fps=%d" % [shape,fps]
			check(length_error < 0.00001,"whole receipt preserves authored upper and lower arm lengths"+label)
			check(bone_error < 0.00001,"actual skin bones never stretch to follow produce"+label)
			check(shoulder_error < 0.00001 and finite and subject.transform == origin,"gesture preserves shoulder sockets, finite pose and actor root"+label)
			subject.cancel_action("fixture")
	subject.queue_free(); await process_frame

func run() -> void:
	await gesture_contract()
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
	main.cam.look_at(at+Vector3.UP*0.95*Dimensions.SCALE); main.cam.fov = 35
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
		check(prop.visible and prop.position.y > 1.5*Dimensions.SCALE,"above hat hold "+crop)
		for elbow: Node3D in [actor.left_elbow,actor.right_elbow]:
			var hand: Vector3 = actor.body_pivot.to_local(elbow.get_node("Hand").global_position)
			check(hand.y < actor.head_pivot.position.y-0.15*Dimensions.SCALE and hand.z > 0.15*Dimensions.SCALE,"hands make a chest-height gesture below the face "+crop)
		await shot(crop+"-overhead")
		pose(1.96)
		check(prop.position.distance_to(actor._item_receive.bag.position) < 0.23*Dimensions.SCALE,"item reaches actual satchel mouth "+crop)
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
	# E 只打开成熟地格菜单；真实 Enter 确认后必须等原命令完成，不能把 options 算收获。
	mature(plot,"tomato")
	main.interactor.cancel(); main.interactor.debug_focus(plot)
	main.interactor.active = true; main.interactor._scan_left = 10.0
	# 面朝地格再按 E（SEA-INTERACT-R24）：家园泊位就在旁边，站位同时落在
	# 种植格判定区和上船热区里，此时按面朝向仲裁。不转向的话这一下 E 会被
	# 判成「上船」，是设计如此、不是缺陷；夹具必须把脸转过去。
	var face: Vector3 = plot.global_position - actor.global_position
	# 朝向判据用的是 basis.z（不是相机那种 -Z），所以正向就是 atan2(x, z)。
	actor.rotation.y = atan2(face.x, face.z)
	var e_starts: int = started.size()
	var e_business: Dictionary = economy.to_dict()
	var e_state: Dictionary = farm.state(plot.plot_id)
	var e_item := str(farm.crop_def("tomato").produce)
	var e_count: int = economy.count(e_item)
	var e_yield: int = int(farm.yield_of("tomato")[e_item])
	var e_events: Array = []
	var e_completed: Array = []
	plot.acted.connect(func(_id, event, _payload): e_events.append(event))
	main.interactor.completed.connect(func(_spot, reward): e_completed.append(str(reward.get("event", ""))))
	var e_key := InputEventKey.new()
	e_key.keycode = KEY_E; e_key.physical_keycode = KEY_E; e_key.pressed = true
	Input.parse_input_event(e_key); Input.flush_buffered_events(); await process_frame
	check(Input.is_action_pressed("interact"), "E 真实输入进入交互映射")
	main.interactor._process(0.01)
	check(actor._item_receive.prop == null and started.size() == e_starts, "E 准备阶段不显示未获得的作物或启动成功动作")
	main.interactor._process(float(plot.hold_time)+0.05)
	var menu = main.hud.world_actions
	check(menu.active and e_completed == ["options"], "E hold 完成只打开菜单并返回 options")
	check(farm.state(plot.plot_id) == e_state and economy.to_dict() == e_business
		and started.size() == e_starts and e_events.is_empty() and actor._item_receive.prop == null,
		"E 打开菜单不提前收获、发奖励或庆祝")
	main.interactor._process(float(plot.hold_time)+0.05)
	check(menu.active and e_completed == ["options"] and e_events.is_empty()
		and economy.to_dict() == e_business and farm.state(plot.plot_id) == e_state
		and started.size() == e_starts and actor._item_receive.prop == null,
		"持续 E 不穿透菜单或重复完成")
	e_key.pressed = false; Input.parse_input_event(e_key); Input.flush_buffered_events(); await process_frame
	main.interactor._process(0.0)
	check(not Input.is_action_pressed("interact"), "菜单确认前已真实松开 E")
	var harvest_selected: bool = menu.active and menu.selected_index >= 0 and menu.selected_index < menu.entries.size()
	if harvest_selected:
		var entry: Dictionary = menu.entries[menu.selected_index]
		harvest_selected = str(entry.get("id", "")) == "harvest" and str(entry.get("blocked", "")) == ""
	check(harvest_selected, "成熟菜单实际选中可用的显式收获项")
	if harvest_selected:
		for down in [true, false]:
			var confirm := InputEventKey.new()
			confirm.keycode = KEY_ENTER; confirm.physical_keycode = KEY_ENTER; confirm.pressed = down
			root.push_input(confirm, true)
			await process_frame
		check(main.interactor.command_target == plot and main.interactor.selected_command.is_valid(),
			"真实 Enter 排队原地格收获命令")
		check(economy.to_dict() == e_business and farm.state(plot.plot_id) == e_state
			and started.size() == e_starts and actor._item_receive.prop == null,
			"Enter 仅排队，接近和 hold 完成前不提前奖励或举物")
		for frame in 900:
			main.actor_controller.tick(1.0/60.0)
			main.interactor.active = not main.actor_controller.walking() and not main.hud.is_modal()
			main.interactor.update(1.0/60.0,main.interactor.auto_hold)
			await physics_frame
			await process_frame
			if started.size() > e_starts: break
	check(e_events == ["harvested"] and e_completed == ["options", "harvested"],
		"等待真实命令完成后才有一次收获业务事件")
	check(economy.count(e_item) == e_count + e_yield and int(farm.state(plot.plot_id).harvests) == 1,
		"Enter 收获按原产量仅入包一次并推进番茄再生一次")
	check(started.size() == e_starts+1 and actor._item_receive.prop != null
		and actor._item_receive.prop.get_meta("crop_id", "") == "tomato"
		and actor.action_playback().get("id", "") == "harvesting",
		"E 菜单加 Enter 最终只启动一次匹配番茄的成功动作")
	var e_token: int = int(actor.action_playback().get("token", 0))
	pose(2.4); actor._process(0.0)
	for frame in 90:
		main.actor_controller.tick(1.0/60.0)
		main.interactor.active = not main.actor_controller.walking() and not main.hud.is_modal()
		main.interactor.update(1.0/60.0,main.interactor.auto_hold)
		await process_frame
	check(e_token > 0 and finished.count(["harvesting", e_token]) == 1
		and actor.action_playback().is_empty() and actor._item_receive.prop == null,
		"等待收获动作完整结束且只结束一次，不以开菜单代替成功")
	check(started.size() == e_starts+1 and e_events == ["harvested"]
		and e_completed == ["options", "harvested"] and economy.count(e_item) == e_count + e_yield
		and main.actor_controller.auto_target == null and not main.interactor.auto_hold
		and not main.interactor.selected_command.is_valid(), "动作后续帧不重复奖励或动作，命令已释放")
	actor.cancel_action("test"); main.interactor.cancel()
	# Full inventory refuses without changing mature crop or starting presentation.
	mature(plot,"lettuce")
	var inventory_before: Dictionary = economy.inventory.to_dict()
	economy.inventory.set_count("vegetable",0)
	economy.inventory.set_count("wood",960)
	var before_full: int = started.size()
	var full_state: Dictionary = farm.state(plot.plot_id)
	var full_business: Dictionary = economy.to_dict()
	var full_events: int = e_events.size()
	check(plot.perform("harvest").has("blocked"),"full bag rejects harvest")
	check(farm.state(plot.plot_id) == full_state and economy.to_dict() == full_business
		and e_events.size() == full_events and started.size() == before_full
		and actor.action_playback().is_empty() and actor._item_receive.prop == null,
		"满包失败保留作物与全部业务状态，不发成功事件、不庆祝")
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
		check(actor._item_receive.prop == null and actor.left_arm.scale == Vector3.ONE
			and is_equal_approx(actor.left_elbow.position.y,-Dimensions.UPPER_ARM*float(actor._avatar_factors.arm_length))
			and is_equal_approx(actor.right_elbow.get_node("Hand").position.y,-Dimensions.LOWER_ARM*float(actor._avatar_factors.arm_length)),"interrupt cleans held item and restores authored arm lengths "+reason)
		actor._process(3.0)
		check(not finished.has(["harvesting",token]),"cancelled action cannot finish later "+reason)
		actor.cancel_action("reset"); actor.set_walking(false); actor.set_rowing(false); actor.set_diving(false)
		main.actor_controller.restore_pose({"mode":0,"player":[at.x,at.y,at.z]})
	# Frame rate independence, including long frames crossing the complete action.
	for fps in [30,60,120]:
		actor.play_receive_item("tomato")
		for frame in int(fps*1.2): actor._process(1.0/float(fps))
		check(actor._item_receive.prop != null and absf(actor._item_receive.prop.position.y-1.60*Dimensions.SCALE) < 0.001*Dimensions.SCALE,"same overhead pose at fps "+str(fps))
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
