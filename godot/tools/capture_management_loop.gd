extends SceneTree
var failures := 0
var main: Node
func _init() -> void: call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	var economy: Node = root.get_node("Economy")
	economy.ticking = false
	main._select_landing({"zone":"zone1","landing":"main","name":"主泊位"})
	economy.give({"wood":12,"parts":8,"rope":4})
	economy.build_facility("warehouse")
	economy.deposit_materials()
	main.hud.open_tab("build")
	await create_timer(2.0).timeout
	root.get_texture().get_image().save_png("res://outputs/management-build.png")
	main.hud.open_tab("bag")
	await create_timer(0.8).timeout
	economy.give({"wood":1})
	await create_timer(0.3).timeout
	await click_named(main.hud._tab_body, "材料一键入库")
	if economy.count("wood") != 0:
		failures += 1
		printerr("FAIL 一键入库鼠标操作")
	root.get_texture().get_image().save_png("res://outputs/management-warehouse.png")
	main.hud._toggle_panel()
	main.order_panel.set_open(true)
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png("res://outputs/management-orders.png")
	var before: String = str(economy.orders.slots[0].uid)
	await click_named(main.order_panel, "免费换一批")
	if str(economy.orders.slots[0].uid) == before:
		failures += 1
		printerr("FAIL 免费换单鼠标操作")
	print("[management-ui] native capture and 2 mouse checks, %d failed" % failures)
	quit(1 if failures else 0)

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var button := find_button(child, title)
		if button != null: return button
	return null

func click_named(node: Node, title: String) -> void:
	var button := find_button(node, title)
	if button == null:
		failures += 1
		printerr("FAIL 找不到按钮 ", title)
		return
	var point := button.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await create_timer(0.4).timeout
