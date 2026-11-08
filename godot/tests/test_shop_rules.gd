extends SceneTree
## 主线程 run_verification 注册 shop-rules -> 本脚本；只使用库存 fake，不加载主场景/NPC。
## 完成标记：[shop-rules] N checks, 0 failures。未在模块施工线程直接运行 Godot。
const Catalog = preload("res://src/shop/shop_catalog.gd")
const Service = preload("res://src/shop/shop_service.gd")
const ShopPanel = preload("res://src/shop/shop_panel.gd")
const Items = preload("res://src/inventory/item_db.gd")
const Crops = preload("res://src/crops/crop_catalog.gd")
var checks: int = 0
var failures: int = 0

class FakeBag extends RefCounted:
	signal changed(id: String, delta: int)
	signal capacity_changed(used: int, capacity: int)
	var counts: Dictionary = {"coins": 100}
	var order: Array = []
	var events: Array = []
	var exchanges: int = 0
	var reject_exchange: bool = false
	var cap: int = 24
	var room_override: Variant = null
	var coins_override: Variant = null
	var during_exchange: Callable = Callable()

	func count(id: String) -> Variant:
		if id == "coins" and coins_override != null:
			return coins_override
		return counts.get(id, 0)

	func capacity() -> int:
		return cap

	func slots_used() -> int:
		return _slots(counts)

	func _slots(candidate: Dictionary) -> int:
		var used: int = 0
		for id in candidate:
			if Items.is_currency(id):
				continue
			var stack: int = Items.stack_limit(id)
			used += int((int(candidate[id]) + stack - 1) / stack)
		return used

	func room_for(id: String) -> Variant:
		if room_override != null:
			return room_override
		var stack: int = Items.stack_limit(id)
		var current: int = counts.get(id, 0)
		return (cap - slots_used()) * stack + (stack - current % stack) % stack

	func state() -> Dictionary:
		return {"counts": counts.duplicate(true), "order": order.duplicate(true), "events": events.duplicate(true)}

	func exchange(costs: Dictionary, gains: Dictionary) -> Dictionary:
		exchanges += 1
		if during_exchange.is_valid():
			during_exchange.call()
		if reject_exchange:
			return {"ok": false, "reason": "测试端口拒绝提交"}
		var candidate: Dictionary = counts.duplicate(true)
		for group in [costs, gains]:
			for id in group:
				if not id is String or not Items.has(id) or not group[id] is int or group[id] <= 0:
					return {"ok": false, "reason": "交换输入无效"}
		for id in costs:
			if candidate.get(id, 0) < costs[id]:
				return {"ok": false, "reason": "瓶盖不足"}
			candidate[id] = candidate.get(id, 0) - costs[id]
		for id in gains:
			candidate[id] = candidate.get(id, 0) + gains[id]
		if _slots(candidate) > cap:
			return {"ok": false, "reason": "背包已满"}
		counts = candidate
		for id in gains:
			if not Items.is_currency(id) and not order.has(id):
				order.append(id)
		for id in costs:
			events.append([id, -costs[id]])
			changed.emit(id, -costs[id])
		for id in gains:
			events.append([id, gains[id]])
			changed.emit(id, gains[id])
		capacity_changed.emit(slots_used(), cap)
		return {"ok": true, "reason": ""}

class NextFrameConfirm extends Node:
	var opened_frame: int = -1
	var sent_frame: int = -1

	func _process(_delta: float) -> void:
		if Engine.get_process_frames() <= opened_frame:
			return
		sent_frame = Engine.get_process_frames()
		for pressed in [true, false]:
			var event: InputEventKey = InputEventKey.new()
			event.keycode = KEY_ENTER
			event.physical_keycode = KEY_ENTER
			event.pressed = pressed
			get_viewport().push_input(event, true)
		set_process(false)

class ReadOnlyBag extends RefCounted:
	func count(_id: String) -> int: return 100
	func room_for(_id: String) -> int: return 20
	func slots_used() -> int: return 0
	func capacity() -> int: return 24

class FakeCrops extends RefCounted:
	var rows: Dictionary = {"lettuce": {"seed": "lettuce_seed", "seed_price": 7},
		"tomato": {"seed": "tomato_seed", "seed_price": 10},
		"pumpkin": {"seed": "pumpkin_seed", "seed_price": 12},
		"flower_blue": {"seed": "flower_seed_blue", "seed_price": 8},
		"flower_sun": {"seed": "flower_seed_sun", "seed_price": 10},
		"flower_coral": {"seed": "flower_seed_coral", "seed_price": 12}}
	func ids() -> Array: return rows.keys()
	func get_crop(id: String) -> Dictionary: return rows.get(id, {}).duplicate(true)
	func seed_of(id: String) -> String: return str(rows.get(id, {}).get("seed", ""))

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_catalog_tests()
	_rule_tests()
	_token_tests()
	await _panel_tests()
	await _panel_input_guard_tests()
	await process_frame
	print("[shop-rules] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _catalog_tests() -> void:
	check(Catalog.validate() == "", "正式目录有效")
	check(Catalog.ids() == ["shop_flower", "shop_general"], "两个独立目录")
	check(Catalog.products("shop_flower").size() == 5 and Catalog.products("shop_general").size() == 6, "首批全部商品可见")
	var crops: Crops = Crops.new()
	check(crops.reload(), "正式品种目录可读取")
	for shop in Catalog.all():
		for product in shop.products:
			check(Items.has(product.item) and product.label == Items.label(product.item), "商品有效且名称来自物品表：" + product.id)
			if product.has("crop_id"):
				check(product.price == crops.get_crop(product.crop_id).seed_price, "品种价格唯一真源：" + product.id)
			var product_bag: FakeBag = FakeBag.new()
			product_bag.counts.coins = 1000
			var product_service: Service = Service.new()
			product_service.configure(product_bag)
			check(product_service.buy(shop.id, product.id, 1).ok and product_bag.count(product.item) == 1, "每件正式商品都可实际结算：" + product.id)
	var copied: Array = Catalog.all()
	copied[0].products[0].price = 999
	check(Catalog.product("shop_flower", "flower_seed_blue").price == 8, "目录深拷贝")
	var fake: FakeCrops = FakeCrops.new()
	var service: Service = Service.new()
	var bag: FakeBag = FakeBag.new()
	service.configure(bag, Callable(), Catalog.data(), fake)
	check(service.quote("shop_general", "general_lettuce_seed").unit_price == 7, "价格从注入品种目录解析而非固定副本")
	fake.rows.flower_blue.seed_price = 9
	service.configure(bag, Callable(), Catalog.data(), fake)
	check(service.quote("shop_flower", "flower_seed_blue").unit_price == 9, "花种价格同样来自CropCatalog端口")
	fake.rows.flower_blue.seed_price = 8
	var invalid_tables: Array = [[], {}, {"schema": "sea.shops", "shops": []}]
	for bad_price in [-1, 0, 1.5, INF, NAN, true, "8", 9007199254740992.0]:
		var raw: Dictionary = Catalog.data()
		raw.shops[0].products[3].price = bad_price
		invalid_tables.append(raw)
	for bad_limit in [-1, 0, 1.5, INF, NAN, false, "2"]:
		var raw: Dictionary = Catalog.data()
		raw.shops[0].products[0].max_amount = bad_limit
		invalid_tables.append(raw)
	for mutation in ["empty", "item", "duplicate", "type", "enabled", "crop_price", "crop_item", "unknown_crop"]:
		var raw: Dictionary = Catalog.data()
		match mutation:
			"empty": raw.shops[0].products = []
			"item": raw.shops[0].products[3].item = "no_such_item"
			"duplicate": raw.shops[0].products.append(raw.shops[0].products[0].duplicate(true))
			"type": raw.shops[0].products[0].type = "gift"
			"enabled": raw.shops[0].enabled = 1
			"crop_price": raw.shops[1].products[0].price = 4
			"crop_item": raw.shops[1].products[0].item = "lettuce_seed"
			"unknown_crop": raw.shops[1].products[0].crop_id = "missing"
		invalid_tables.append(raw)
	for raw in invalid_tables:
		var before: Dictionary = bag.state()
		service.configure(bag, Callable(), raw, fake)
		check(service.shops().is_empty(), "坏目录失败关闭")
		check(not service.open_shop("shop_flower").ok and not service.buy("shop_flower", "flower_seed_blue", 1).ok, "坏目录禁止打开和结算")
		check(bag.state() == before, "坏目录不改变现场")
	for bad_seed_price in [-1, 0, 0.5, NAN, INF, "7", false]:
		fake.rows.lettuce.seed_price = bad_seed_price
		check(not Catalog.resolve(Catalog.data(), fake).ok, "品种价格坏数据拒绝")

func _rule_tests() -> void:
	var bag: FakeBag = FakeBag.new()
	var service: Service = Service.new()
	service.configure(bag)
	var observed: Array = []
	var blocked_events: Array = []
	var opened_events: Array = []
	service.purchase_completed.connect(func(a, b, c, d): observed.append([a, b, c, d]))
	service.purchase_blocked.connect(func(a, b, c): blocked_events.append([a, b, c]))
	service.shop_opened.connect(func(a, b): opened_events.append([a, b]))
	var before: Dictionary = bag.state()
	var snapshot: Dictionary = service.shop_snapshot("shop_flower")
	var estimate: Dictionary = service.quote("shop_flower", "flower_seed_blue", 2)
	check(estimate.ok and estimate.unit_price == 8 and estimate.total_cost == 16 and estimate.max_buy == 12, "报价与最大可购数")
	check(estimate.coins == 100 and estimate.room == 480 and estimate.capacity == 24, "购买前余额空间上限")
	snapshot.products[0].price = 999
	estimate.product.price = 999
	var shops: Array = service.shops()
	shops[0].products.clear()
	service.max_buy("shop_flower", "flower_seed_blue")
	check(service.quote("shop_flower", "flower_seed_blue").unit_price == 8, "服务查询深拷贝")
	check(bag.state() == before and observed.is_empty() and blocked_events.is_empty() and opened_events.is_empty() and bag.exchanges == 0, "查询完全无副作用且不发业务事件")
	for amount in [-1, 0, 1.0, 1.5, INF, NAN, true, "2", null, [], {}, Catalog.MAX_VALUE + 1, Catalog.MAX_VALUE]:
		before = bag.state()
		var calls: int = bag.exchanges
		check(not service.buy("shop_flower", "flower_seed_blue", amount).ok, "非法数量拒绝：" + str(amount))
		check(bag.state() == before and bag.exchanges == calls, "非法数量无写调用")
	for pair in [["missing", "flower_seed_blue"], ["shop_flower", "missing"], [1, "flower_seed_blue"], ["shop_flower", null], ["", ""]]:
		before = bag.state()
		check(not service.buy(pair[0], pair[1], 1).ok and bag.state() == before, "非法或未知标识拒绝")
	check(service.open_shop("shop_flower").vendor_npc_id == "npc_hua_yi", "经营者来自目录")
	check(not service.open_shop("shop_flower", "other").ok, "经营者不匹配拒绝")
	var bought: Dictionary = service.buy("shop_flower", "flower_seed_blue", 2)
	check(bought.ok and bag.count("coins") == 84 and bag.count("flower_seed_blue") == 2, "一次原子交易完成扣款和入包")
	check(bag.exchanges == 1 and observed.size() == 1, "一次购买一次交换和事件")
	bag.reject_exchange = true
	before = bag.state()
	check(not service.buy("shop_flower", "flower_seed_blue", 1).ok and bag.state() == before, "交换拒绝不退款不补偿不改变现场")
	bag.reject_exchange = false
	# 模拟查询后外部改满背包；只有交换端口能够最终裁决。
	var weak_bag: WeakRef = weakref(bag)
	bag.during_exchange = func():
		weak_bag.get_ref().cap = 1
		weak_bag.get_ref().counts = {"coins": 1000, "wood": 40}
	check(not service.buy("shop_flower", "flower_seed_blue", 1).ok, "提交时容量变化由原子端口拒绝")
	check(bag.count("coins") == 1000 and bag.count("flower_seed_blue") == 0 and bag.count("wood") == 40, "提交容量冲突不产生部分扣款或入包")
	bag.during_exchange = Callable()
	bag.cap = 24
	bag.counts = {"coins": 0}
	before = bag.state()
	check(service.quote("shop_flower", "flower_seed_blue").reason == "瓶盖不足", "余额不足原因可读")
	check(not service.buy("shop_flower", "flower_seed_blue", 1).ok and bag.state() == before, "余额不足现场不变")
	bag.counts.coins = 1000
	bag.cap = 1
	bag.counts = {"coins": 1000, "wood": 40}
	before = bag.state()
	check(service.max_buy("shop_flower", "flower_seed_blue") == 0, "满包无可购空间")
	check(not service.buy("shop_flower", "flower_seed_blue", 1).ok and bag.state() == before, "满包现场不变")
	bag.counts = {"coins": 1000, "flower_seed_blue": 19}
	check(service.max_buy("shop_flower", "flower_seed_blue") == 1, "满格仍允许叠入已有未满堆")
	check(service.buy("shop_flower", "flower_seed_blue", 1).ok, "补满已有堆原子成功")
	bag.cap = 24
	check(service.max_buy("shop_flower", "flower_bundle") == 1, "礼物单次一件")
	check(service.max_buy("shop_general", "general_rope") == 10 and service.max_buy("shop_general", "general_glass") == 5, "材料配置上限")
	for invalid in [-1, 1.5, INF, NAN, "100", true]:
		bag.coins_override = invalid
		before = bag.state()
		check(not service.buy("shop_flower", "flower_seed_blue", 1).ok and bag.state() == before, "非法背包余额拒绝")
	bag.coins_override = null
	for invalid in [-1, 1.5, INF, NAN, "2", true]:
		bag.room_override = invalid
		before = bag.state()
		check(not service.buy("shop_flower", "flower_seed_blue", 1).ok and bag.state() == before, "非法容量余量拒绝")
	bag.room_override = null
	var raw: Dictionary = Catalog.data()
	raw.shops[0].enabled = false
	service.configure(bag, Callable(), raw)
	check(not service.open_shop("shop_flower").ok and service.max_buy("shop_flower", "flower_seed_blue") == 0, "关闭商店不可购买")
	var read_only: ReadOnlyBag = ReadOnlyBag.new()
	service.configure(read_only)
	check(not service.buy("shop_flower", "flower_seed_blue", 1).ok, "缺少exchange禁止半原子回退")
	service.configure(read_only, Callable(bag, "exchange"))
	check(service.buy("shop_flower", "flower_seed_blue", 1).ok, "可显式注入exchange端口")

func _token_tests() -> void:
	var bag: FakeBag = FakeBag.new()
	var service: Service = Service.new()
	service.configure(bag)
	var events: Array = []
	service.purchase_completed.connect(func(a, b, c, d): events.append([a, b, c, d]))
	var first: Dictionary = service.buy("shop_flower", "flower_seed_blue", 2, "same")
	var after: Dictionary = bag.state()
	first.label = "被改写"
	check(service.buy("shop_flower", "flower_seed_blue", 2, "same").label == Items.label("flower_seed_blue"), "token结果深拷贝")
	check(bag.state() == after and bag.exchanges == 1 and events.size() == 1, "重复token不结算不重复发事件")
	check(not service.buy("shop_flower", "flower_seed_blue", 1, "same").ok and bag.state() == after, "同token不同数量拒绝")
	check(not service.buy("shop_flower", "flower_seed_blue", 2.0, "same").ok, "token指纹区分整数和浮点")
	check(not service.buy("shop_flower", "flower_seed_blue", 1, 42).ok, "非法token拒绝")
	check(not service.buy("shop_flower", "flower_seed_blue", 1, "x".repeat(129)).ok, "超长token拒绝")
	bag.reject_exchange = true
	var failed: Dictionary = service.buy("shop_flower", "flower_seed_blue", 1, "rejected")
	bag.reject_exchange = false
	var calls: int = bag.exchanges
	check(service.buy("shop_flower", "flower_seed_blue", 1, "rejected") == failed and bag.exchanges == calls, "失败请求同样幂等")
	var reentrant: Array = []
	# 只在交换的信号窗口重入，闭包不用强引用服务，避免 RefCounted 环。
	var weak_service: WeakRef = weakref(service)
	bag.during_exchange = func(): reentrant.append(weak_service.get_ref().buy("shop_flower", "flower_seed_blue", 1, "in-flight"))
	check(service.buy("shop_flower", "flower_seed_blue", 1, "in-flight").ok, "外层交换成功")
	check(reentrant.size() == 1 and not reentrant[0].ok, "交换中重入不会重复写入")
	bag.during_exchange = Callable()
	var signal_replay: Array = []
	var replay: Callable = func(_a, _b, _c, _d): signal_replay.append(weak_service.get_ref().buy("shop_flower", "flower_seed_blue", 1, "signal"))
	service.purchase_completed.connect(replay)
	check(service.buy("shop_flower", "flower_seed_blue", 1, "signal").ok and signal_replay.size() == 1 and signal_replay[0].ok, "完成信号重入已缓存token")
	service.purchase_completed.disconnect(replay)
	# 在模块测试内直接推进缓存时间，不等待真实两分钟。
	service._requests.same.at -= Service.TOKEN_TTL_MS
	check(service.buy("shop_flower", "flower_seed_blue", 2, "same").ok, "token过期后作为新请求")
	for i in range(Service.TOKEN_LIMIT + 5):
		service.buy("missing", "missing", 1, "bounded:%d" % i)
	check(service._requests.size() == Service.TOKEN_LIMIT, "短期token缓存有界")
	var fresh: Service = Service.new()
	fresh.configure(bag)
	check(fresh.buy("shop_flower", "flower_seed_blue", 1, "signal").ok, "服务重建无持久化shop状态")

func _key(code: Key, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	return event

func _send_key(code: Key, pressed: bool, echo: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = _key(code, echo)
	event.pressed = pressed
	event.shift_pressed = shift
	root.push_input(event, true)

func _press_key(code: Key, shift: bool = false) -> void:
	_send_key(code, true, false, shift)
	await process_frame
	_send_key(code, false, false, shift)
	await process_frame

func _click(button: Button) -> void:
	# 真实命中测试与按下/松开，不直接发 pressed 信号。
	var position: Vector2 = button.get_global_rect().get_center()
	check(button.is_visible_in_tree() and not button.disabled and root.get_visible_rect().has_point(position), "鼠标目标可见可用：" + button.name)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame

func _panel_tests() -> void:
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	var bag: FakeBag = FakeBag.new()
	var service: Service = Service.new()
	service.configure(bag)
	var panel: ShopPanel = ShopPanel.new()
	root.add_child(panel)
	panel.configure(service, bag)
	var closed: Array = []
	panel.closed.connect(func(id): closed.append(id))
	check(not panel.is_open() and not panel.handle_input(_key(KEY_E)), "关闭时不吞世界输入")
	check(panel.open_shop("shop_flower").ok and panel.is_open(), "独立花店面板可打开")
	# process_frame 在帧开始发出，首次恢复时计数仍可能是开店帧。
	await process_frame
	await process_frame
	check(Engine.get_process_frames() > panel._opened_frame, "真实跨过开店帧后才测试操作")
	check(panel._title.text == "小花花店" and panel._product_buttons.size() == 5, "花店标题及真实商品格")
	check(panel._product_buttons[0].get_meta("product_id") == "flower_seed_blue", "商品格绑定稳定product_id而非物品名")
	var priced := 0
	for tile in panel._product_buttons:
		if tile.price == int(Catalog.product("shop_flower", str(tile.get_meta("product_id"))).price): priced += 1
	check(priced == 5, "五格都在格内画单价角标，不用列表行")
	check(panel._name.text == "蓝星花种子 · 8 瓶盖", "名签显示商品名与单价，不谎称为已有库存")
	check(panel._product_buttons[0].has_focus() and root.gui_get_focus_owner() == panel._product_buttons[0], "开店焦点落在首件商品")
	check(panel._details == null and not panel._view.actions.visible, "开店只摆格子，不替玩家打开购买气泡")
	check(panel._wallet.text.contains("背包"), "底部余额与背包格数可见")
	await _press_key(KEY_ENTER)
	check(panel._view.actions.visible and panel._details != null, "确认键在选中商品后打开购买气泡")
	check(panel._details.text.contains("单价") and panel._details.text.contains("当前可购") and panel._details.text.contains("合计"), "气泡显示单价、可购数与合计")
	check(panel._quantity.text == "1" and panel._buy.text.contains("8 瓶盖"), "气泡默认数量1并显示总价")
	check(bag.exchanges == 0, "打开气泡本身不结算")
	await _press_key(KEY_RIGHT)
	check(panel._amount == 2 and panel._details.text.contains("合计  16 瓶盖"), "键盘增加数量并同步合计")
	await _click(panel._plus)
	check(panel._amount == 3, "鼠标按钮增加数量")
	await _click(panel._minus)
	check(panel._amount == 2, "鼠标按钮减少数量")
	await _click(panel._product_buttons[0])
	check(panel._view.actions.visible and panel._view.selected_index == 0 and bag.exchanges == 0 and panel._amount == 1, "鼠标选择商品重开气泡但不购买")
	await _press_key(KEY_ENTER)
	check(bag.count("flower_seed_blue") == 1 and bag.count("coins") == 92 and bag.exchanges == 1 and panel.is_open(), "Enter购买成功不关闭且只结算一次")
	var calls: int = bag.exchanges
	_send_key(KEY_E, true, true)
	await process_frame
	_send_key(KEY_E, false)
	check(bag.exchanges == calls, "按住确认不连买")
	await _press_key(KEY_RIGHT)
	var sun: Dictionary = Catalog.product("shop_flower", "flower_seed_sun")
	check(panel._selected_id == "flower_seed_sun" and panel._product_buttons[1].has_focus(), "向右选择下一商品并移动真实焦点")
	check(panel._name.text == "晨光花种子 · 10 瓶盖" and not panel._view.actions.visible and panel._view.buy_amount == 1, "换商品收起旧气泡并重置数量")
	await _press_key(KEY_E)
	check(panel._view.actions.visible and bag.exchanges == calls, "E只打开气泡不扣款")
	await _press_key(KEY_E)
	check(bag.count("flower_seed_sun") == 1 and bag.count("coins") == 82 and bag.exchanges == calls + 1, "E确认后购买所选商品一次")
	await _press_key(KEY_LEFT)
	check(panel._selected_id == "flower_seed_blue" and panel._product_buttons[0].has_focus(), "向左选择商品")
	await _press_key(KEY_DOWN)
	check(panel._selected_id == "flower_seed_blue" and panel._product_buttons[0].has_focus(), "商品区上下键不会把焦点甩到背包")
	await _press_key(KEY_ENTER)
	bag.reject_exchange = true
	var before: Dictionary = bag.state()
	await _press_key(KEY_E)
	check(panel.is_open() and panel._feedback.text.contains("拒绝") and bag.state() == before, "购买失败不关闭且原因可读")
	bag.reject_exchange = false
	bag.counts.coins = 0
	bag.changed.emit("coins", -1)
	check((panel._buy == null or panel._buy.disabled) and panel._wallet.text.contains("0") and panel._availability.text.contains("瓶盖不足"), "外部库存事件刷新余额和资格")
	await _press_key(KEY_ESCAPE)
	await create_timer(0.25).timeout
	check(panel.is_open() and not panel._view.actions.visible, "Esc先收起气泡不关店")
	before = bag.state()
	calls = bag.exchanges
	await _press_key(KEY_ESCAPE)
	check(not panel.is_open() and closed == ["shop_flower"] and bag.state() == before and bag.exchanges == calls, "再次Esc关闭只发一次关闭信号且不扣款")
	check(not panel.open_shop("missing").ok and not panel.is_open(), "未知商店不打开旧页")
	check(panel.open_shop("shop_general").ok and panel._title.text == "阿店海上商店", "综合商店独立目录")
	check(panel._product_buttons.size() == 6, "综合商店六件商品同页图标")
	await process_frame
	await process_frame
	await _click(panel._close_button)
	check(not panel.is_open() and closed.size() == 2, "鼠标关闭可达")
	panel.queue_free()
	await process_frame
	check(not bag.changed.has_connections() and not bag.capacity_changed.has_connections(), "释放面板解除库存订阅")

func _panel_input_guard_tests() -> void:
	var bag: FakeBag = FakeBag.new()
	bag.counts.coins = 1000
	var service: Service = Service.new()
	service.configure(bag)
	var panel: ShopPanel = ShopPanel.new()
	root.add_child(panel)
	panel.configure(service, bag)
	panel.open_shop("shop_flower")
	var before: Dictionary = bag.state()
	for code in [KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE]:
		_send_key(code, true)
		_send_key(code, false)
	check(panel.is_open() and bag.state() == before and bag.exchanges == 0 and not panel._view.actions.visible, "开店同帧确认键既不开气泡也不扣钱")
	# 在真实 _process 中捕获首个后继帧；不假设协程恢复时计数恰好加一。
	var next_frame_confirm: NextFrameConfirm = NextFrameConfirm.new()
	next_frame_confirm.opened_frame = panel._opened_frame
	root.add_child(next_frame_confirm)
	await process_frame
	await process_frame
	check(next_frame_confirm.sent_frame == panel._opened_frame + 1, "真实下一计数帧注入确认输入")
	check(panel._view.actions.visible and bag.state() == before and bag.exchanges == 0, "开店下一帧Enter只打开购买气泡")
	await _press_key(KEY_ENTER)
	check(bag.count("coins") == 992 and bag.count("flower_seed_blue") == 1 and bag.exchanges == 1, "气泡内Enter购买一次")
	next_frame_confirm.queue_free()
	# 使用正式 HUD 的委托端口，复现装配层转发同一事件后面板 _input 再收到它。
	var hud = preload("res://src/ui/hud.gd").new()
	hud.owned_modal_input = panel.handle_input
	await _press_key(KEY_ENTER)
	check(panel._view.actions.visible, "再次确认先重开气泡")
	var event: InputEventKey = _key(KEY_E)
	var calls: int = bag.exchanges
	check(hud.owned_modal_input.call(event), "HUD端口消费商店确认事件")
	root.push_input(event, true)
	panel._input(event)
	check(bag.exchanges == calls + 1 and bag.count("coins") == 984 and bag.count("flower_seed_blue") == 2, "同InputEvent经HUD与_input重复转发只购买一次")
	_send_key(KEY_E, false)
	hud.free()
	before = bag.state()
	calls = bag.exchanges
	# 真实按键不会和上一枚确认键同帧；先跨一帧，避免撞上去重窗口。
	await process_frame
	var held_frame: int = Engine.get_process_frames()
	_send_key(KEY_ENTER, true)
	check(bag.exchanges == calls, "长按起始不购买")
	check(panel._view.actions.visible, "长按起始重开气泡")
	check(panel._view.selected_pool == 1 and str(panel._view.selected_data.get("product_id","")) != "", "长按起始选中商品仍在")
	var held_state: Dictionary = bag.state()
	for repeat in 3:
		await process_frame
		await process_frame
		_send_key(KEY_ENTER, true, true)
	check(Engine.get_process_frames() > held_frame and bag.exchanges == calls and bag.state() == held_state, "跨真实帧持续按住的echo不会重复打开或购买")
	_send_key(KEY_ENTER, false)
	before = bag.state()
	await _press_key(KEY_ENTER)
	check(bag.exchanges == calls + 1 and bag.count("flower_seed_blue") == 3 and bag.count("coins") == 976, "松开后新的Enter可再购买一次")
	await _press_key(KEY_ENTER)
	check(panel._view.actions.visible and panel._amount == 1, "购买后再次确认重开数量为1的气泡")
	await _press_key(KEY_RIGHT)
	check(panel._amount == 2 and not panel._minus.disabled, "气泡内右方向键把数量调到2")
	before = bag.state()
	calls = bag.exchanges
	await _press_key(KEY_TAB)
	check(not panel.is_open() and bag.state() == before and bag.exchanges == calls, "Tab与背包一致关闭商店且不结算")
	panel.queue_free()
	await process_frame
