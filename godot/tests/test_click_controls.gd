extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	for command in ["bag","plant","build","follow","save","load","camera","grade","rise","descend","lamp","close"]:
		check(main.hud.command_buttons.has(command),"鼠标入口 "+command)
	check(not main.hud.command_buttons.has("cancel"),"主界面不再显示停止行动")
	main._on_click_command("plant")
	check(main.hud._panel_open and main.hud._tab=="plant","直达种植")
	main._on_click_command("close")
	check(not main.hud._panel_open,"关闭面板")
	var state: Node = root.get_node("GameState")
	state.enter_zone("zone1")
	state.set_mode(state.Mode.ON_BOAT)
	var cell: Node3D = main.farm_field.find("home_plot")
	check(main._approach(cell),"点击地格进入移动")
	main._cancel_action()
	check(not main._walking and main._auto_target==null and not main.interactor.auto_hold and not main._after_walk.is_valid(),"取消同时清理移动和动作")
	var economy: Node = root.get_node("Economy")
	economy.inventory.clear()
	main._open_spot_bubbles(cell)
	check(not main.hud.world_actions.buttons[0].available and not main._walking,"无种子时播种气泡不可用，不走空路")
	main.hud.world_actions.activate(0)
	check(not main._walking,"点击不可用的播种只给轻提示")
	main.hud.world_actions.close(true)
	main.hud.open_tab("bag")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(300,300)
	main._unhandled_input(press)
	press.pressed = false
	main._unhandled_input(press)
	check(not main._walking and not main.boat.starts_sailing(),"面板外点击不穿透")
	main.hud._toggle_panel()
	main._world_press = true
	main._press_pos = Vector2(100,100)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(200,100)
	main._input(motion)
	motion.position = Vector2(100,100)
	main._input(motion)
	check(main._dragged,"拖动再回原点不识别成点击")
	main._board_player()
	state.set_mode(state.Mode.ON_BOAT)
	main._pending_pick = {"type":"crate"}
	# 2026-11-03：zone3 已按范围要求从 main.tscn 移除，改用仍安装的浅水养殖台验证同一条逻辑。
	main._on_destination("zone5")
	check(main.boat.starts_sailing() and main._pending_pick.is_empty(),"新航线取消旧拾取")
	main._on_destination("zone2")
	check(main.boat._to_zone=="zone2","航行途中改道")
	main._cancel_action()
	check(not main.boat.starts_sailing(),"取消停止航行")
	economy.give({"wood":100,"parts":100,"coins":1000,"rope":100,"glass":100})
	main._on_focus_site("home_cabin")
	# 默认最小范围按 SEA-WORLD-R08 关闭建造交互，这时命令应当明确不生效；
	# 显式 --full-world 才走「前往并自动交付」。两条都要断言，不能只认一条。
	if preload("res://src/core/play_scope.gd").minimal():
		check(main._auto_target == null, "最小范围内建造前往被关闭")
	else:
		check(main._auto_target==main.build_field.find("home_cabin"),"建造菜单前往并自动交付")
	main._cancel_action()
	# Match player-reachable startup: complete deferred lighting/presenter/focus setup.
	await process_frame
	await process_frame
	var session = main.dive
	check(session.runtime==null,"海面不常驻潜水地图")
	var entered: bool = session.enter_map("zone1")
	check(entered,"进入 zone1 潜水地图")
	if not entered:
		main.queue_free()
		await process_frame
		quit(1)
		return
	var uw = session.runtime
	check(current_scene==uw and uw.get_parent()==root and not main.is_inside_tree(),"真实切换至独立潜水地图")
	uw.phase_machine.tick(uw.ENTER_TIME)
	uw.diver_pos = Vector3(0,-6,10)
	check(uw.swim_to(Vector3(1,-6,10)),"鼠标潜水导航规划")
	check(not uw._route.is_empty(),"潜水路线建立")
	uw._search = {"id":999,"pos":Vector3(8,-6,10)}
	uw._update_swim(0.016)
	check(not uw._search.is_empty(),"游向宝箱途中保留搜索任务")
	uw.cancel_navigation()
	check(uw._route.is_empty() and uw._search.is_empty(),"取消潜水导航与搜索")
	check(not uw.swim_to(Vector3(999,-6,999)),"拒绝界外目的地")
	uw.surface()
	uw.phase_machine.tick(uw.ENTER_TIME)
	await process_frame
	await process_frame
	check(main.is_inside_tree() and current_scene==main,"上浮返回原海面实例")
	check(root.get_camera_3d()==main.cam,"上浮后相机交还海面")
	check(main.dive==session and not session.active and session.runtime==null,"稳定会话已回收潜水 runtime")
	check(not is_instance_valid(uw),"旧潜水 runtime 已销毁")
	main.salvage_panel.begin()
	check(main.salvage_panel._action_button != null,"打捞鼠标控件")
	main.salvage_panel.cancel()
	check(not main.salvage_panel.is_open(),"打捞可退出")
	print("[click-controls] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
