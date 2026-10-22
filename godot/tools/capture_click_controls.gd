extends "res://tools/capture_farm_cycle.gd"
func mouse(pos: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event,true)
	await settle(2)
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	main._save_path = "user://click_controls_test.json"
	economy = root.get_node("Economy")
	economy.ticking = false
	await settle(10)
	await click(main.hud.command_buttons.plant)
	check(main.hud._panel_open and main.hud._tab=="plant","点击工具栏直达种植")
	await shot("click-controls-surface")
	await click(main.hud.command_buttons.close)
	check(not main.hud._panel_open,"点击关闭")
	await click(main.hud.command_buttons.camera)
	check(main.cam_panel.is_open(),"点击视角面板")
	await click(main.hud.command_buttons.camera)
	await click(main.hud.command_buttons.save)
	check(FileAccess.file_exists("user://click_controls_test.json"),"点击保存到隔离测试槽")
	await click(main.hud.command_buttons.load)
	check(not main._walking,"点击读档")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://click_controls_test.json"))
	main._select_landing({"zone":"zone1","landing":"main","name":"主泊位"})
	await settle(60)
	main.cam.distance = 12.0
	main.cam.target = main.farm_field.find("home_plot").global_position
	main.cam._apply()
	await settle(20)
	var cell: Node3D = main.farm_field.find("home_plot:1")
	var pos: Vector2 = main.cam.unproject_position(cell.global_position+Vector3.UP*.18)
	await mouse(pos,true)
	await mouse(pos,false)
	check(main._auto_target==cell,"直接点击世界中的第二格命中正确目标")
	await click(main.hud.command_buttons.cancel)
	check(main._auto_target==null and not main._walking,"鼠标取消移动与操作")
	await click(main.hud._dive_btn)
	for i in 300:
		await process_frame
		if main.dive.phase=="swim": break
	check(main.dive.active and main.dive.phase=="swim","鼠标下潜")
	var initial_lamp: bool = main.dive.air.lamp
	await click(main.hud.command_buttons.lamp)
	check(main.dive.air.lamp!=initial_lamp,"鼠标切换头灯")
	await click(main.hud.command_buttons.descend)
	check(not main.dive._route.is_empty(),"鼠标下游深度导航")
	await shot("click-controls-underwater")
	await click(main.hud.command_buttons.cancel)
	check(main.dive._route.is_empty(),"鼠标取消游动")
	await click(main.hud._dive_btn)
	for i in 300:
		await process_frame
		if not main.dive.active: break
	check(not main.dive.active,"鼠标上浮")
	main.salvage_panel.begin()
	await settle(5)
	await mouse(main.salvage_panel._action_button.get_global_rect().get_center(),true)
	await settle(5)
	check(main.salvage_panel.model.phase==2,"鼠标停钩进入收线")
	await mouse(Vector2(700,600),false)
	check(not main.salvage_panel._mouse_holding,"按钮外松手也停止收线")
	await shot("click-controls-salvage")
	await click(main.hud.command_buttons.cancel)
	check(not main.salvage_panel.is_open(),"鼠标退出打捞")
	print("[click-ui] failures=",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
