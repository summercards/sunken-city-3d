extends SceneTree
## Run only through scripts/run_verification.py via the external run_ac.py adapter.
## Fixtures use public business commands in a runner-isolated project/user directory.
var main: Node
var hud: CanvasLayer
var card: Control
var failures := 0
var checks := 0
var visual := false
var shots := ""

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[ac-ui] ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames(n: int) -> void:
	for i in n: await process_frame

func delay(seconds: float) -> void:
	await create_timer(seconds).timeout

func click(control: Control) -> void:
	var scroll: ScrollContainer = card.detail
	if scroll.is_ancestor_of(control):
		scroll.ensure_control_visible(control)
		await frames(3)
	await click_at(control.get_global_rect().get_center())

func click_at(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	root.push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = pos;event.button_index = MOUSE_BUTTON_LEFT;event.pressed = down
		root.push_input(event,true)
		await process_frame

func key(code: int) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code;event.physical_keycode = code;event.pressed = down
		root.push_input(event,true)
		await process_frame

func find_button(fragment: String) -> Button:
	for node in card.body.find_children("*","Button",true,false):
		if node.text.contains(fragment): return node
	return null

func shot(name: String) -> void:
	if not visual: return
	# A macOS-occluded test window may stop automatic drawing while process frames
	# continue. Draw the real viewport explicitly so capture cannot wait forever.
	RenderingServer.force_draw(false)
	var img := root.get_texture().get_image()
	check(img.get_size() == Vector2i(1600,1000),"native viewport 1600×1000 "+name)
	check(img.save_png(shots.path_join(name+".png")) == OK,"capture "+name)

func run() -> void:
	visual = DisplayServer.get_name() != "headless"
	if visual:
		root.size = Vector2i(1600,1000)
		root.content_scale_size = Vector2i(1600,1000)
		shots = OS.get_environment("SEA_WORK_ROOT")
		if shots.is_empty(): shots = ProjectSettings.globalize_path("res://").get_base_dir().path_join("ui_shots_ac")
		else: shots = shots.path_join("ui_shots_ac")
		DirAccess.make_dir_recursive_absolute(shots)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	hud = main.hud;card = hud._panel
	await frames(30)
	var economy: Node = root.get_node("Economy")
	check(not hud.presentation_snapshot().open,"starts with unobstructed world")
	await click(hud.command_buttons.bag)
	check(hud.presentation_snapshot().open,"real mouse opens card")
	check(card.position.y > hud._base_position.y,"open begins below resting position")
	await delay(0.3)
	check(card.position.is_equal_approx(hud._base_position),"open reaches resting position")
	check(card.size == Vector2(420,620) and card.scale.is_equal_approx(Vector2.ONE),"card size and scale")
	check(is_equal_approx(hud._backdrop.material.get_shader_parameter("strength"),1.0),"background fade completed")
	check(card.status.text.contains("时间 —") and card.status.text.contains("潮汐 —"),"missing status stays unknown")
	check(card.status.mouse_filter == Control.MOUSE_FILTER_IGNORE,"status read only")
	check(not card.is_ancestor_of(hud._hints),"hints live outside moving card")
	check(card.pages[0].get_child_count() == 9 and card.pages[1].get_child_count() == 9,"nine tiles per page")
	for id in ["water","hook","lamp"]: check(card.tiles[id].locked,"equipped lock "+id)
	check(card.tiles.fish.amount == 0,"zero quantity has no badge")
	# Actual inventory command drives animated counters and arrival, no UI fixture totals.
	economy.give({"fish":3,"vegetable":8,"tomato":2,"shell":5})
	await delay(0.2)
	check(card.tiles.vegetable.shown_amount > 0 and card.tiles.vegetable.shown_amount < 8,"counter rolls between endpoints")
	check(card.tiles.vegetable.amount_offset < 0,"counter floats upward")
	check(card.flight_layer.get_child_count() > 0,"harvest flies inside clipped card")
	await delay(0.32)
	check(card.tiles.vegetable.flash > 0,"arrival triggers highlight")
	await delay(0.65)
	check(is_zero_approx(card.tiles.vegetable.flash),"highlight decays")
	check(roundi(card.tiles.vegetable.shown_amount) == economy.count("vegetable"),"counter matches owner")
	await shot("01_card_open")
	var hints_pos: Vector2 = hud._hints.position
	var mouse := InputEventMouseMotion.new();mouse.position = card.tiles.hook.get_global_rect().get_center()
	root.push_input(mouse,true)
	await delay(0.15)
	check(card.tiles.hook.scale.is_equal_approx(Vector2.ONE*1.06),"hover reaches 1.06")
	check(card.tiles.hook.selected and not card.tiles.water.selected,"hover selects exactly one tile")
	await click(card.dots[1])
	check(card.turning,"page transition starts via mouse")
	card.flip(0);card.flip(1)
	check(card.page == 1,"repeated flips cannot stack")
	await frames(3)
	check(card.pages[0].position.x < 0 and card.pages[1].position.x > 0,"both pages slide in clipped region")
	await shot("02_page_flip")
	await delay(0.3)
	check(not card.turning and not card.pages[0].visible and card.pages[1].visible,"old page hidden after flip")
	check(card.tiles.plant.selected,"new page has actionable selection")
	check(hud._hints.position == hints_pos,"hints do not follow page animation")
	await shot("04_page_ready")
	# World keys and clicks must not leak through a modal card.
	await click_at(Vector2(1400,500))
	check(not main._walking and not main.boat.starts_sailing(),"backdrop click blocks world navigation")
	await key(KEY_ENTER)
	check(hud._tab == "plant" and card.detail.visible,"keyboard selects first app after flip")
	await key(KEY_ESCAPE)
	check(hud._tab == "bag" and not card.detail.visible,"detail return restores HUD routing")
	economy.give({"wood":1})
	check(not card.detail.visible,"inventory event does not reopen stale detail")
	hud.open_tab("storage")
	await frames(4)
	check(card.body.size.x <= card.detail.size.x,"storage fits same card width")
	check(card.detail.position.y+card.detail.size.y < card.footer.position.y,"detail scroll stays above footer")
	await shot("05_storage")
	hud.open_tab("build")
	await frames(4)
	check(card.body.size.x <= card.detail.size.x,"build fits same card width")
	hud.open_tab("plant")
	await frames(4)
	check(card.body.size.x <= card.detail.size.x,"plant fits same card width")
	hud.open_tab("fish")
	check(find_button("前往码头") != null and find_button("出售全部") == null,"fish uses real trade route, not crop sale")
	hud.open_tab("vegetable")
	check(find_button("出售全部") != null,"crop sale command retained")
	await click(find_button("出售全部"))
	check(economy.count("vegetable") == 8,"sale refused while on boat")
	# Use existing arrival command, then exercise actual crop-sale command from UI.
	main._select_landing({"zone":"zone1","landing":"main","name":"主泊位"})
	await delay(2.0)
	var state: Node = root.get_node("GameState")
	check(state.mode == state.Mode.ASHORE,"arrival command establishes shore state")
	hud.open_tab("vegetable")
	var before: int = economy.count("coins")
	await click(find_button("出售全部"))
	check(economy.count("vegetable") == 0 and economy.count("tomato") == 0 and economy.count("coins") == before+66,"sale obeys owner quantities and prices")
	check(economy.count("fish") == 3,"crop sale leaves fish untouched")
	hud.open_tab("bag")
	check(card.tiles.vegetable.amount == 0,"sold item badge vanishes at zero")
	await key(KEY_C)
	check(not hud._panel_open and main.cam_panel.is_open(),"camera command closes card first")
	await key(KEY_B)
	check(hud._panel_open and not main.cam_panel.is_open(),"bag command closes external panel first")
	await key(KEY_ESCAPE)
	check(not hud._panel_open and not hud._backdrop.visible,"escape closes card and backdrop")
	await click(hud._dive_btn)
	# 新机制：独立地图本地状态栏消费氧气/深度，不再打开海面 B 键日志。
	var session = main.dive
	check(not session.active and session.runtime == null,"海面潜水按钮仍受默认 gate 保护")
	var entered: bool = session.enter_map("zone1")
	check(entered,"显式进入 zone1 潜水地图")
	if not entered:
		main.queue_free()
		await frames(2)
		quit(1)
		return
	var uw = session.runtime
	var map_hud: CanvasLayer
	for child in uw.get_children():
		if child.get_script() == preload("res://src/diving/dive_map_hud.gd"): map_hud = child
	check(map_hud != null,"独立地图 HUD 存在")
	check(current_scene == uw and uw.get_parent() == root and not main.is_inside_tree(),"真实地图切换使海面 UI 移出树")
	uw.phase_machine.tick(uw.ENTER_TIME)
	uw.debug_teleport(Vector3(0,-10,12))
	await frames(3)
	var status: Dictionary = map_hud.presentation_snapshot()
	check(map_hud._status.is_visible_in_tree() and status.text.contains(uw.map_label),"新机制：本地状态栏替代海面日志标题")
	check(is_equal_approx(status.depth,uw.depth) and is_equal_approx(status.oxygen,uw.air.ratio()),"本地状态栏消费真实氧气与深度")
	check(status.found == uw.discovered_count() and status.total == uw.chest_count(),"本地状态栏消费真实宝箱进度")
	var status_pos: Vector2 = map_hud._status.position
	var controls_pos: Vector2 = map_hud.command_buttons.surface.position
	var drain: float = uw.air.drain_rate(uw.depth,false,false)
	uw.air.update((uw.air.ratio()-0.25)*uw.air.MAX/drain,uw.depth,false,false)
	uw._emit_air()
	await frames(2)
	status = map_hud.presentation_snapshot()
	check(status.oxygen <= 0.30 and status.oxygen > 0.15,"本地氧气进入低氧告警档")
	check(status.color == Color("#E08B4A") and status.text.contains("氧气偏低"),"30% 低氧告警显示橙色与文字")
	await shot("06_oxygen_warning")
	uw.air.update((uw.air.ratio()-0.12)*uw.air.MAX/drain,uw.depth,false,false)
	uw._emit_air()
	await frames(2)
	status = map_hud.presentation_snapshot()
	check(status.oxygen <= 0.15 and status.oxygen > 0,"本地氧气进入危急档")
	check(status.color == Color("#D4573F") and status.text.contains("氧气危急"),"15% 危急告警显示红色与文字")
	check(is_equal_approx(status.depth,uw.depth) and is_equal_approx(status.oxygen,uw.air.ratio()),"低氧反馈仍消费真实 runtime 状态")
	check(map_hud._status.position == status_pos and map_hud.command_buttons.surface.position == controls_pos,"新机制低氧用颜色反馈，不抖动状态栏与操作入口")
	await shot("03_low_oxygen")
	await key(KEY_ESCAPE)
	status = map_hud.presentation_snapshot()
	check(paused and status.menu_open and session.active and uw.phase == "swim","Esc 打开本地暂停菜单，不触发上浮")
	var air_before: float = uw.air.ratio()
	var pos_before: Vector3 = uw.diver_pos
	await delay(0.4)
	check(is_equal_approx(air_before,uw.air.ratio()) and uw.diver_pos == pos_before,"独立暂停停止氧气消耗与游动")
	check(map_hud.presentation_snapshot().oxygen == status.oxygen,"暂停期间本地氧气显示保持稳定")
	await key(KEY_ESCAPE)
	check(not paused and not map_hud.presentation_snapshot().menu_open and uw.phase == "swim","再次 Esc 恢复探索而非上浮")
	await delay(0.2)
	check(uw.air.ratio() < air_before,"恢复探索后氧气继续消耗")
	await key(KEY_ESCAPE)
	await click_at(map_hud.menu_buttons.surface.get_global_rect().get_center())
	check(not paused and uw.phase == "exit","本地暂停菜单上浮先解除暂停并进入退出阶段")
	uw.phase_machine.tick(uw.ENTER_TIME)
	await frames(3)
	check(main.is_inside_tree() and current_scene == main and root.get_camera_3d() == main.cam,"上浮返回原 Main 与海面相机")
	check(main.dive == session and not session.active and session.runtime == null,"稳定会话已回收 runtime")
	check(not is_instance_valid(uw) and not is_instance_valid(map_hud),"旧 runtime 与本地 HUD 已销毁")
	check(not paused,"上浮不遗留暂停")
	check(hud._hints.position == hints_pos,"独立地图低氧反馈未移动海面提示")
	check(not hud.presentation_snapshot().diving and hud.presentation_snapshot().oxygen == -1,"surface clears stale dive status")
	print("[ac-ui] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await frames(3)
	quit(0 if failures == 0 else 1)
