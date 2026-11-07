extends "res://tools/capture_farm_cycle.gd"
func mouse(pos: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event,true)
	await settle(2)
func map_click(button: Button) -> void:
	# 继承的 click() 会查询海面 HUD；独立地图只向本地控件发送真实鼠标事件。
	check(button.is_visible_in_tree(),"潜水鼠标目标在当前地图内可见")
	var pos := button.get_global_rect().get_center()
	await mouse(pos,true)
	await mouse(pos,false)
func key(code: int) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event,true)
		await process_frame
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
	# The HUD stop button was removed; exercise the existing cancel command directly.
	main._on_click_command("cancel")
	check(main._auto_target==null and not main._walking,"命令取消移动与操作")
	await click(main.hud._dive_btn)
	var session = main.dive
	check(not session.active and session.runtime == null,"海面潜水按钮仍受默认 gate 保护")
	# 新机制：显式进入地图，本地 HUD 承担潜水鼠标操作与状态，不读取海面日志。
	var entered: bool = session.enter_map("zone1")
	check(entered,"显式进入 zone1 潜水地图")
	if not entered:
		main.queue_free()
		await settle(2)
		quit(1)
		return
	var uw = session.runtime
	var map_hud: CanvasLayer
	for child in uw.get_children():
		if child.get_script() == preload("res://src/diving/dive_map_hud.gd"): map_hud = child
	check(map_hud != null,"独立地图 HUD 存在")
	check(current_scene == uw and uw.get_parent() == root and not main.is_inside_tree(),"真实切换至独立地图并移出海面 UI")
	uw.phase_machine.tick(uw.ENTER_TIME)
	await settle(3)
	check(session.active and uw.phase == "swim","独立地图完成下潜")
	var initial_lamp: bool = uw.air.lamp
	await map_click(map_hud.command_buttons.lamp)
	check(uw.air.lamp != initial_lamp and map_hud.presentation_snapshot().lamp_on == uw.air.lamp,"本地鼠标控件切换头灯并显示真实状态")
	await map_click(map_hud.command_buttons.descend)
	check(not uw._route.is_empty(),"本地鼠标下游深度导航")
	await shot("click-controls-underwater")
	await map_click(map_hud.command_buttons.cancel)
	check(uw._route.is_empty() and uw._search.is_empty(),"本地鼠标取消游动与搜索")
	var status: Dictionary = map_hud.presentation_snapshot()
	check(is_equal_approx(status.oxygen,uw.air.ratio()) and is_equal_approx(status.depth,uw.depth),"新机制本地状态栏消费真实氧气和深度")
	var drain: float = uw.air.drain_rate(uw.depth,false,false)
	uw.air.update((uw.air.ratio()-0.25)*uw.air.MAX/drain,uw.depth,false,false);uw._emit_air()
	await settle(2)
	status = map_hud.presentation_snapshot()
	check(status.oxygen > 0.15 and status.oxygen <= 0.30 and status.color == Color("#E08B4A") and status.text.contains("氧气偏低"),"本地氧气低氧告警为橙色并显示文字")
	uw.air.update((uw.air.ratio()-0.12)*uw.air.MAX/drain,uw.depth,false,false);uw._emit_air()
	await settle(2)
	status = map_hud.presentation_snapshot()
	check(status.oxygen > 0.0 and status.oxygen <= 0.15 and status.color == Color("#D4573F") and status.text.contains("氧气危急"),"本地氧气危急告警为红色并显示文字")
	await key(KEY_ESCAPE)
	check(paused and map_hud.presentation_snapshot().menu_open and uw.phase == "swim","Esc 打开独立暂停菜单而非上浮")
	var air_before: float = uw.air.ratio()
	var pos_before: Vector3 = uw.diver_pos
	await settle(20)
	check(is_equal_approx(air_before,uw.air.ratio()) and uw.diver_pos == pos_before,"暂停停止氧气消耗与游动")
	await shot("click-controls-underwater-pause")
	await key(KEY_ESCAPE)
	check(not paused and not map_hud.presentation_snapshot().menu_open and uw.phase == "swim","再次 Esc 恢复独立地图探索")
	await settle(10)
	check(uw.air.ratio() < air_before,"恢复探索后氧气继续消耗")
	await map_click(map_hud.command_buttons.surface)
	check(uw.phase == "exit","本地鼠标上浮进入退出阶段")
	uw.phase_machine.tick(uw.ENTER_TIME)
	await settle(2)
	check(main.is_inside_tree() and current_scene == main and root.get_camera_3d() == main.cam,"上浮返回原 Main 和海面相机")
	check(main.dive == session and not session.active and session.runtime == null,"稳定会话已回收 runtime")
	check(not is_instance_valid(uw) and not is_instance_valid(map_hud),"旧 runtime 与本地 HUD 已销毁")
	check(not paused,"上浮不遗留暂停")
	main.salvage_panel.begin()
	await settle(5)
	await mouse(main.salvage_panel._action_button.get_global_rect().get_center(),true)
	await settle(5)
	check(main.salvage_panel.model.phase==2,"鼠标停钩进入收线")
	await mouse(Vector2(700,600),false)
	check(not main.salvage_panel._mouse_holding,"按钮外松手也停止收线")
	await shot("click-controls-salvage")
	main._on_click_command("cancel")
	check(not main.salvage_panel.is_open(),"命令退出打捞")
	print("[click-ui] failures=",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
