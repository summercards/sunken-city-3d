extends SceneTree
## 口袋专项：拖拽整理 + 购买数量 +/−。
##
## 为什么需要它：这两件事都不会让任何脚本报错，只会"看起来不对"或者
## "点了没反应"，而现有的 pocket-bubbles / pocket-services 都盯不到：
##   · 拖拽整理若无持久化，关掉背包再打开就恢复原状 —— 玩家会认为"拖了没用"。
##     存档里必须真的多出一个 order，读回来顺序还得一致。
##   · 购买若只能一次一件，种子/土壤这种消耗品就得点十几次；
##     而一旦放开数量，就必须保证"扣了钱没到货"不会发生（原子性）。
##
## 用法：
##   Godot --path godot --script res://tools/check_pocket_drag_buy.gd
## 退出码：0 = 全部合格，1 = 有不合格项。

const InventoryScript = preload("res://src/inventory/inventory.gd")
const Items = preload("res://src/inventory/item_db.gd")

var main: Node
var economy
var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func ok(value: bool, name: String) -> void:
	checks += 1
	print("[pocket-drag-buy] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1


func run() -> void:
	_check_inventory_order()
	await _check_scene()
	_check_atomic()
	print("[pocket-drag-buy] %d checks, %d failures" % [checks, failures])
	if main != null:
		main.queue_free()
		await process_frame
	quit(0 if failures == 0 else 1)


## --- 一、排列是 Inventory 的状态，而且要能存下来 ----------------------------
##
## 这一段不加载场景：顺序规则本身是可以单独验证的纯逻辑。

func _check_inventory_order() -> void:
	var bag: RefCounted = InventoryScript.new(12)
	for id in ["wood", "fish", "vegetable"]:
		bag.add(id, 1)
	var before: Array = bag.ordered_ids()
	ok(before.size() == 3, "三种物品都在排列里")

	# 拖 A 到 B 上 = 两者互换，其余一个都不动。
	ok(bag.move_item("wood", "vegetable"), "拖拽移动返回成功")
	var after: Array = bag.ordered_ids()
	ok(after[0] == "vegetable" and after[2] == "wood", "拖拽后两者互换位置（%s）" % str(after))
	ok(after[1] == "fish", "其余物品位置没被挤动")
	ok(bag.count("wood") == 1 and bag.count("vegetable") == 1, "拖拽只改顺序，不改数量")

	# 拖回来就还原：整理必须是可逆的。
	bag.move_item("wood", "vegetable")
	ok(bag.ordered_ids() == before, "再拖一次能还原")

	# 拖到空槽 = 挪到末尾。
	bag.move_to_end("wood")
	var tail: Array = bag.ordered_ids()
	ok(tail[tail.size() - 1] == "wood", "拖到空槽挪到末尾（%s）" % str(tail))

	# 同种物品超过叠放上限会拆多堆：几堆必须挨在一起，不能被排序打散。
	# 数量按真实 stack_limit 算，不写死 —— 写死 25 在上限是 99 时根本不是两堆。
	var stack: int = int(Items.stack_limit("wood"))
	var big: RefCounted = InventoryScript.new(24)
	big.add("wood", stack + 3)
	big.add("fish", 1)
	big.move_to_end("wood")
	var stacks := _stack_ids(big)
	ok(stacks == ["fish", "wood", "wood"], "同种物品的几堆始终相邻（%s）" % str(stacks))

	# 存档：order 必须写进去，读回来顺序一致。
	var saved: Dictionary = big.to_dict()
	ok(saved.has("order"), "存档里有 order 字段")
	ok(saved.order == ["fish", "wood"], "order 只存当前持有的物品（%s）" % str(saved.order))
	var restored: RefCounted = InventoryScript.new(24)
	restored.from_dict(saved)
	ok(restored.ordered_ids() == ["fish", "wood"], "读档后顺序与关档前一致")
	ok(restored.count("wood") == stack + 3 and restored.count("fish") == 1, "读档数量也一致")

	# 旧存档没有 order：必须能读，并退回物品表顺序（不能崩、不能空）。
	var legacy: RefCounted = InventoryScript.new(24)
	legacy.from_dict({"capacity": 24, "counts": {"wood": 3, "fish": 2}})
	ok(legacy.ordered_ids().size() == 2, "旧存档（无 order）照样能排出两种物品")

	# 脏 order：不存在 / 已经用光 / 货币，全都要被丢掉，不能靠它把界面搞崩。
	var dirty: RefCounted = InventoryScript.new(24)
	dirty.from_dict({"capacity": 24, "counts": {"wood": 3},
		"order": ["ghost_item", "coins", "wood", "wood"]})
	ok(dirty.ordered_ids() == ["wood"], "脏 order 被过滤（%s）" % str(dirty.ordered_ids()))


func _stack_ids(bag: RefCounted) -> Array:
	var out: Array = []
	for id in bag.ordered_ids():
		var remaining: int = bag.count(id)
		while remaining > 0:
			out.append(id)
			remaining -= mini(remaining, Items.stack_limit(id))
	return out


## --- 二、场景：界面真的按整理顺序排、真的能拖 -------------------------------

func _check_scene() -> void:
	root.content_scale_size = Vector2i(1600, 1000)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	economy = root.get_node("Economy")
	economy.set_process(false)
	# 补给服务只在岸上可用（hud._farm_action 会拦），这里先站到种植平台上。
	var plot = main.farm_field.find("home_plot")
	main.actor_controller.restore_pose({"mode": 0,
		"player": [plot.global_position.x, plot.global_position.y, plot.global_position.z + 1]})
	await process_frame

	for id in ["fish", "vegetable", "tomato"]:
		economy.inventory.add(id, 2)
	var view = main.hud.services
	main._on_click_command("shop")
	await process_frame

	var order: Array = view.slots[0].map(func(t): return str(t.get_meta("item_id")))
	ok(order[0] == "fish" and order[1] == "vegetable" and order[2] == "tomato",
		"界面按 Inventory 的排列摆格子（%s）" % str(order.slice(0, 3)))

	await _check_drag(view)
	await _check_buy_picker(view, order)


## 拖拽：直接调 Godot 拖放回调。
##
## 不模拟"按住—移动—松开"的完整鼠标轨迹（那要几十帧且依赖帧率），
## 而是分别验三件事：能不能被拖起来、能不能接住、落下后有没有真的生效。
func _check_drag(view) -> void:
	var source: Control = null
	for tile in view.slots[0]:
		if str(tile.get_meta("item_id")) == "fish": source = tile
	ok(source != null, "找到可拖的格子")
	if source == null: return
	ok(source.drag_sortable, "背包格子开启了拖拽")

	var payload: Variant = source.drag_payload()
	ok(payload is Dictionary and str(payload.get("item_id", "")) == "fish", "拖起来的载荷带物品 id")
	var empty: Control = null
	for tile in view.slots[0]:
		if tile.empty_slot: empty = tile; break
	if empty != null:
		ok(empty.drag_sortable, "空槽也能接住（用于挪到末尾）")

	# 落到 vegetable 上：两者互换。
	var target: Control = null
	for tile in view.slots[0]:
		if str(tile.get_meta("item_id")) == "vegetable": target = tile
	ok(target != null and target._can_drop_data(Vector2.ZERO, payload), "物品格接受落下")
	if target != null:
		target._drop_data(Vector2.ZERO, payload)
	await process_frame
	var after: Array = view.slots[0].map(func(t): return str(t.get_meta("item_id")))
	ok(after[0] == "vegetable" and after[1] == "fish", "落下后界面立即重排（%s）" % str(after.slice(0, 3)))
	ok(economy.inventory.count("fish") == 2 and economy.inventory.count("vegetable") == 2,
		"拖拽没有改动任何数量")

	# 拖到空槽：挪到末尾（在已用物品之后）。
	payload = view.slots[0][0].drag_payload()
	if empty != null:
		empty._drop_data(Vector2.ZERO, payload)
		await process_frame
		var live: Array = []
		for tile in view.slots[0]:
			if not tile.empty_slot: live.append(str(tile.get_meta("item_id")))
		ok(live[live.size() - 1] == "vegetable", "拖到空槽挪到末尾（%s）" % str(live))

	# 商店目录（pool 1）不是我的背包格子：不许接住拖拽。
	var shop_tile: Control = null
	for tile in view.slots[1]:
		if str(tile.get_meta("item_id")) != "": shop_tile = tile; break
	if shop_tile != null:
		ok(not shop_tile.drag_sortable, "商店目录格子不可拖")
		ok(not shop_tile._can_drop_data(Vector2.ZERO, {"item_id": "fish", "pool": 0}),
			"背包物品不能落到商店目录上")


## 购买数量：`[−] N [+]` 与「购买 N」。
func _check_buy_picker(view, order: Array) -> void:
	# 先给足瓶盖，确认 + 能加、能加到顶。
	economy.inventory.set_count("coins", 500)
	view.refresh("shop")
	await process_frame

	var seed_tile: Control = null
	for tile in view.slots[1]:
		if str(tile.get_meta("item_id")) == "tomato_seed": seed_tile = tile
	ok(seed_tile != null, "商店目录里有番茄种子")
	if seed_tile == null: return

	view.select(1, view.slots[1].find(seed_tile))
	view.show_actions()
	await process_frame

	var holder: HBoxContainer = null
	var buy: Button = null
	for node in view.action_body.get_children():
		if node is HBoxContainer: holder = node
		if node is Button and str(node.get_meta("service_action", "")) == "buy": buy = node
	ok(holder != null, "购买气泡里有数量选择行")
	ok(buy != null, "购买气泡里有购买按钮")
	if holder == null or buy == null: return

	# 行内三个控件：减、数字、加。
	var minus: Button = null
	var plus: Button = null
	var counter: Label = null
	for node in holder.get_children():
		if node is Button and node.text == "−": minus = node
		elif node is Button and node.text == "+": plus = node
		elif node is Label: counter = node
	ok(minus != null and plus != null and counter != null, "选择行是 [−] N [+]")
	if minus == null or plus == null or counter == null: return

	ok(counter.text == "1", "默认买 1 个")
	ok(minus.disabled, "数量为 1 时减号置灰")
	ok(buy.text == "购买 1", "按钮文案跟随数量")

	plus.pressed.emit()
	plus.pressed.emit()
	await process_frame
	ok(counter.text == "3" and buy.text == "购买 3", "点两次 + 变成 3（%s）" % counter.text)
	ok(not minus.disabled, "大于 1 时减号可用")

	minus.pressed.emit()
	await process_frame
	ok(counter.text == "2", "减号回退到 2")

	# 真的买 2 包：扣 2 倍价、入包 2。
	var price: int = int(economy.farm.crop_def("tomato").seed_price)
	var coins_before: int = economy.count("coins")
	var seeds_before: int = economy.count("tomato_seed")
	buy.pressed.emit()
	await process_frame
	ok(economy.count("coins") == coins_before - price * 2,
		"买 2 包扣 2 倍价（%d → %d）" % [coins_before, economy.count("coins")])
	ok(economy.count("tomato_seed") == seeds_before + 2, "买 2 包到手 2 包")

	# 上限：瓶盖只够 1 包时，+ 直接置灰，不给"点过头再报错"。
	economy.inventory.set_count("coins", price)
	view.refresh("shop")
	await process_frame
	for tile in view.slots[1]:
		if str(tile.get_meta("item_id")) == "tomato_seed": seed_tile = tile
	view.select(1, view.slots[1].find(seed_tile))
	view.show_actions()
	await process_frame
	var plus2: Button = null
	var minus2: Button = null
	for node in view.action_body.get_children():
		if node is HBoxContainer:
			for child in node.get_children():
				if child is Button and child.text == "+": plus2 = child
				elif child is Button and child.text == "−": minus2 = child
	ok(plus2 != null and plus2.disabled, "只够买 1 个时 + 置灰")
	ok(minus2 != null and minus2.disabled, "只够买 1 个时 − 也置灰")


## --- 三、购买原子性（纯逻辑，不点界面） ------------------------------------
##
## "加到 5 包、扣了瓶盖、只塞进去 2 包"这种半途失败最难解释，这里直接盯死。

func _check_atomic() -> void:
	var price: int = int(economy.farm.crop_def("tomato").seed_price)
	# 瓶盖只够 2 包，却要买 3 包：一点瓶盖都不该扣，种子一个都不该加。
	economy.inventory.set_count("coins", price * 2)
	var seeds_before: int = economy.count("tomato_seed")
	var refused: Dictionary = economy.farm.buy_seed("tomato", 3)
	ok(refused.has("blocked"), "钱不够买 3 包时被拒")
	ok(economy.count("coins") == price * 2 and economy.count("tomato_seed") == seeds_before,
		"被拒时不扣瓶盖也不加种子")

	# 背包塞不下：容量 1 且已有别的东西，买 2 包土壤必须整体失败。
	economy.inventory.from_dict({"capacity": 1, "counts": {"wood": 20, "coins": 400}})
	var soil_before: int = economy.count("soil")
	var shop = preload("res://src/building/material_shop.gd").new()
	shop.inventory = economy.inventory
	var blocked: Dictionary = shop.buy_soil(2)
	ok(blocked.has("blocked"), "背包满时买 2 份土壤被拒")
	ok(economy.count("coins") == 400 and economy.count("soil") == soil_before,
		"被拒时不扣瓶盖也不加土壤")

	# 正例：空间与钱都够，2 份一起到账。
	economy.inventory.from_dict({"capacity": 24, "counts": {"coins": 400}})
	var done: Dictionary = shop.buy_soil(2)
	ok(done.get("ok", false) and economy.count("soil") == 2, "买 2 份土壤一起到账")
	ok(economy.count("coins") == 400 - 4 * 2, "土壤按份数扣款")
