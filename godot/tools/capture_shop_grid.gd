extends SceneTree
## 商店图标网格的真实渲染证据（SEA-SHOP-R12）。
##
## 只构造 ShopService + 真实 Inventory + 独立 ShopPanel，不加载主场景：
## 面板与背包共用 PocketService 的格子/分页/气泡，观感与交互都可单独复核。
## 逻辑断言在 `tests/test_shop_rules.gd`；这里负责"玩家真正看到什么"。

const Catalog = preload("res://src/shop/shop_catalog.gd")
const Service = preload("res://src/shop/shop_service.gd")
const ShopPanel = preload("res://src/shop/shop_panel.gd")
const InventoryLib = preload("res://src/inventory/inventory.gd")
const Items = preload("res://src/inventory/item_db.gd")

var panel
var service
var bag
var checks := 0
var failures := 0
var shots: Array[String] = []


func _init() -> void:
	call_deferred("run")


func ok(value: bool, name: String) -> bool:
	checks += 1
	print("[shop-grid-render] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1
	return value


func shot(label: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not ok(image != null and not image.is_empty() and image.get_width() >= 960 and image.get_height() >= 600, "真实 viewport 图像有效 " + label):
		return
	var colors := {}
	var panel_rect: Rect2i = Rect2i(panel._view.get_global_rect()).abs()
	for y in range(panel_rect.position.y, panel_rect.end.y, 8):
		for x in range(panel_rect.position.x, panel_rect.end.x, 8):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			colors[image.get_pixel(x, y).to_html()] = true
	ok(colors.size() > 12, "面板区域确实画出了图与字 " + label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	var path := "res://outputs/shop-grid-" + label + ".png"
	if ok(image.save_png(path) == OK, "保存真实画面 " + path):
		shots.append(label)
		print("[shop-grid-shot] ", path, " ", image.get_width(), "x", image.get_height())


func press(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	root.push_input(up, true)
	await process_frame


func run() -> void:
	if not ok(DisplayServer.get_name() != "headless", "必须用 DisplayServer real，禁止 headless 截图假通过"):
		_finish()
		return
	root.content_scale_size = Vector2i(1600, 1000)
	bag = InventoryLib.new(24)
	bag.add("coins", 300)
	bag.add("wood", 3)
	service = Service.new()
	service.configure(bag)
	panel = ShopPanel.new()
	root.add_child(panel)
	panel.configure(service, bag)
	panel.open_shop("shop_flower")
	await create_timer(0.2).timeout

	ok(panel.is_open() and panel._title.text == "小花花店", "花店以独立图标面板打开")
	ok(panel._product_buttons.size() == 5, "花店五件商品同页成格")
	var priced := 0
	for tile in panel._product_buttons:
		if tile.price == int(Catalog.product("shop_flower", str(tile.get_meta("product_id"))).price):
			priced += 1
	ok(priced == 5, "每格在格内画出单价角标，不退回列表式")
	ok(panel._name.text.contains("瓶盖") and not panel._view.actions.visible, "名签显示单价且开店不替玩家开气泡")
	ok(not panel._name.get_global_rect().intersects(panel._view.caption.get_global_rect()), "名签不压商品区说明带")
	ok(panel._product_buttons[0].has_focus(), "开店焦点落在首件商品")
	ok(not panel._feedback.get_global_rect().intersects(panel._wallet.get_global_rect()), "购买反馈不压住底部瓶盖")

	# 三种分辨率都要完整入镜，不能只在一种窗口下看起来正常。
	for extent in [Vector2i(1280, 800), Vector2i(1600, 1000), Vector2i(1920, 1080)]:
		root.size = extent
		await process_frame
		await process_frame
		ok(root.get_visible_rect().encloses(panel._view.get_global_rect()), "面板完整入镜 " + str(extent))
		ok(root.get_visible_rect().encloses(panel._close_button.get_global_rect()), "关闭键在视口内 " + str(extent))
		await shot("grid-%dx%d" % [extent.x, extent.y])

	root.size = Vector2i(1600, 1000)
	await process_frame
	await process_frame
	await press(KEY_ENTER)
	ok(panel._view.actions.visible and panel._buy != null, "确认键打开购买气泡")
	ok(panel._details.text.contains("单价") and panel._details.text.contains("当前可购") and panel._details.text.contains("合计"), "气泡展示单价、可购数与合计")
	ok(root.get_visible_rect().encloses(panel._view.actions.get_global_rect()), "气泡完整在视口内")
	ok(not panel._view.actions.get_global_rect().intersects(panel._feedback.get_global_rect()), "气泡不压购买反馈行")
	# 气泡是浮层，压住任何一件商品都会让人没法点它 —— 逐格检查不被遮。
	var covered := 0
	for tile in panel._product_buttons:
		if panel._view.actions.get_global_rect().intersects(tile.get_global_rect()): covered += 1
	ok(covered == 0, "气泡不压任何商品格（被遮 %d 格）" % covered)
	ok(not panel._name.get_global_rect().intersects(panel._view.actions.get_global_rect()), "名签不被气泡压住")
	ok(not panel._name.get_global_rect().intersects(panel._wallet.get_global_rect()), "名签不压底部瓶盖行")
	await shot("bubble-1")
	await press(KEY_RIGHT)
	await press(KEY_RIGHT)
	ok(panel._amount == 3 and panel._details.text.contains("合计  24 瓶盖"), "数量3与合计24瓶盖同步")
	await shot("bubble-3")

	var coins_before: int = bag.count("coins")
	await press(KEY_ENTER)
	ok(bag.count("flower_seed_blue") == 3 and bag.count("coins") == coins_before - 24, "真实购买扣款并入包")
	ok(panel._feedback.text.contains("已购入") and panel.is_open(), "购买反馈可读且不关店")
	await shot("purchase")

	panel.close()
	await create_timer(0.1).timeout
	panel.open_shop("shop_general")
	await create_timer(0.2).timeout
	ok(panel._title.text == "阿店海上商店" and panel._product_buttons.size() == 6, "综合商店六件商品同页图标")
	await shot("general")

	bag.set_count("coins", 0)
	await process_frame
	panel._refresh()
	await press(KEY_ENTER)
	ok(panel._view.actions.visible and panel._availability != null and panel._availability.text.contains("瓶盖不足"), "余额为0时气泡说明不可购买原因")
	await shot("blocked")

	_finish()


func _finish() -> void:
	ok(shots.size() >= 6, "至少产出6张有效商店图标画面")
	print("[shop-grid-render] %d checks, %d failures" % [checks, failures])
	if panel != null:
		panel.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
