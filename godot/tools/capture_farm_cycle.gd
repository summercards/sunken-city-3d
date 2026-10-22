extends SceneTree
## 原生渲染及真实 Viewport 鼠标事件验证；不读写玩家存档。
var main: Node
var economy: Node
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("[farm-ui] ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func settle(n: int = 8) -> void:
	for i in n: await process_frame
func click(button: Button) -> void:
	var scroll: ScrollContainer = main.hud._tab_body.get_parent()
	if scroll.is_ancestor_of(button): scroll.ensure_control_visible(button)
	await settle()
	var pos := button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()
func find_button(text: String) -> Button:
	for node in main.hud.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and node.text.contains(text): return node
	return null
func panel() -> void:
	if not main.hud._panel_open: main.hud._toggle_panel()
	main.hud._tab = "plant"
	main.hud._refresh_panel()
	await settle()
func operate(id: String) -> void:
	await panel()
	await click(main.hud._plant_rows[id].button)
	for i in 500:
		await process_frame
		if not main._walking and main._auto_target == null: break
	check(not main._walking and main._auto_target == null, "地格操作完成 "+id)
func shot(name: String) -> void:
	await settle(15)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/"+name+".png")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	economy = root.get_node("Economy")
	economy.ticking = false
	var state: Node = root.get_node("GameState")
	state.enter_zone("zone1")
	main._select_landing({"zone":"zone1","landing":"main","name":"主泊位"})
	await settle(90)
	main.cam.distance = 12.0
	main.cam.target = main.farm_field.find("home_plot").global_position
	main.cam._apply()
	await panel()
	var coins_before: int = economy.coins
	await click(find_button("买 1 包 · 4"))
	check(economy.coins == coins_before-4, "鼠标购买扣款")
	await operate("home_plot:1")
	check(economy.farm.crop_of("home_plot:1")=="lettuce" and economy.farm.is_empty("home_plot"), "指定第二格播种，不误操作第一格")
	for day in 3:
		await operate("home_plot:1")
		check(economy.farm.phase("home_plot:1")=="growing" and not economy.farm.is_dry("home_plot:1"), "鼠标浇水")
		await panel()
		await click(find_button("休息到明天"))
	check(economy.farm.phase("home_plot:1")=="ready", "鼠标休息三日成熟")
	await shot("farming-panel")
	main.hud._toggle_panel()
	await shot("farming-ready")
	await operate("home_plot:1")
	check(economy.count("vegetable")==2, "走到格子并收获")
	await panel()
	await click(find_button("出售农产品"))
	check(economy.coins==coins_before+8 and economy.count("vegetable")==0, "出售完成经济闭环")
	await click(find_button("买 1 包 · 4"))
	await operate("home_plot:1")
	check(economy.farm.phase("home_plot:1")=="growing", "再次播种")
	print("[farm-ui] failures=", failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
