extends SceneTree
## 口袋拖拽整理 + 购买数量 +/− 的真实渲染证据。
##
## 逻辑断言在 `tools/check_pocket_drag_buy.gd` 里（不开窗口、快）。
## 这里只负责出图：数量选择器长什么样、拖拽时是什么手感。
##
## 拖拽这一段**走真实鼠标事件**（按下 → 移动 → 松开），不手工造预览：
## 只有真拖起来，Godot 才会走 `_get_drag_data` → viewport 接管预览的完整路径，
## 截出来的才是玩家真正看到的样子。

var main: Node
var economy
var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func ok(value: bool, name: String) -> void:
	checks += 1
	print("[pocket-ui] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1


func shot(label: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/pocket-" + label + ".png")


func center(node: Control) -> Vector2:
	return node.get_global_transform_with_canvas() * (node.size * 0.5)


## 真实鼠标点击（按下 + 抬起），用于开气泡、点 +/−。
func click(node: Control) -> void:
	var at := center(node)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = at
		event.global_position = at
		root.push_input(event, true)
		await process_frame


func slot(pool: int, id: String) -> Control:
	for tile in main.hud.services.slots[pool]:
		if str(tile.get_meta("item_id")) == id: return tile
	return null


func run() -> void:
	root.content_scale_size = Vector2i(1600, 1000)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.cam.set_process(false)
	economy = root.get_node("Economy")
	economy.set_process(false)
	# 补给服务只在岸上可用。
	var plot = main.farm_field.find("home_plot")
	main.actor_controller.restore_pose({"mode": 0,
		"player": [plot.global_position.x, plot.global_position.y, plot.global_position.z + 1]})
	main.cam.global_position = Vector3(-6, 14, 29)
	main.cam.look_at(Vector3(2, 2, 14))
	main.cam.fov = 38

	for id in ["fish", "vegetable", "tomato"]:
		economy.inventory.add(id, 2)
	economy.inventory.set_count("coins", 162)

	main._on_click_command("shop")
	await create_timer(0.3).timeout
	var view = main.hud.services
	ok(view.visible, "补给口袋打开了")

	# --- 购买数量选择器 ---
	var seed_tile := slot(1, "tomato_seed")
	ok(seed_tile != null, "商店目录里有番茄种子")
	if seed_tile == null:
		_finish()
		return
	await click(seed_tile)
	await create_timer(0.25).timeout
	ok(view.actions.visible, "点种子弹出购买气泡")

	var plus: Button = null
	var counter: Label = null
	for node in view.action_body.get_children():
		if node is HBoxContainer:
			for child in node.get_children():
				if child is Button and child.text == "+": plus = child
				elif child is Label: counter = child
	ok(plus != null and counter != null, "气泡里有 + 和数量")
	if plus == null or counter == null:
		_finish()
		return

	await shot("buy-1")
	for i in 2:
		await click(plus)
		await create_timer(0.1).timeout
	ok(counter.text == "3", "点两次 + 后是 3（实测 %s）" % counter.text)
	await shot("buy-3")

	# --- 拖拽整理 ---
	view.back()
	await create_timer(0.2).timeout
	var from := slot(0, "fish")
	var to := slot(0, "tomato")
	ok(from != null and to != null, "背包里有可拖的两格")
	if from == null or to == null:
		_finish()
		return

	var start := center(from)
	var finish := center(to)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	root.push_input(press, true)
	await process_frame

	# 分几步移动：一步到位可能被当成点击而不是拖拽。
	# **必须给 `relative`**：Godot 靠它累计位移判断"这是拖还是点"，
	# 只改 position 时 drag_accum 一直是 0，永远进不了拖拽状态。
	var previous := start
	for step in range(1, 9):
		var point := start.lerp(finish, float(step) / 8.0)
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		motion.relative = point - previous
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		previous = point
		root.push_input(motion, true)
		await process_frame
	await create_timer(0.12).timeout
	ok(root.gui_is_dragging(), "真的处于拖拽状态（Godot 已接管预览）")
	await shot("drag-hover")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = finish
	release.global_position = finish
	root.push_input(release, true)
	await process_frame
	await create_timer(0.2).timeout
	await shot("dropped")

	# 落下后顺序真的换了（鱼的格子在番茄之后）。
	var live: Array = []
	for tile in view.slots[0]:
		if not tile.empty_slot: live.append(str(tile.get_meta("item_id")))
	ok(live.find("tomato") < live.find("fish"), "拖拽后顺序真的换了（%s）" % str(live))

	_finish()


func _finish() -> void:
	print("[pocket-ui] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
