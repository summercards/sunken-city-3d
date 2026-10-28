extends RefCounted
## Presentation only. All mutations go through the supplied command dispatcher.
const Items = preload("res://src/inventory/item_db.gd")

static func build(body: VBoxContainer, tab: String, economy: Node, perform: Callable, navigate: Callable, rest: Callable) -> void:
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	for entry in [["plant","种植"],["storage","仓库"],["shipping","出货箱"],["shop","商店"]]:
		var id: String = entry[0]
		var button := Button.new()
		button.text = entry[1]
		button.disabled = id == tab
		tabs.add_child(button)
		button.pressed.connect(func(): navigate.call(id))
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 570
	body.add_child(title)
	if tab == "shop":
		title.text = "家园补给站 · 瓶盖 %d\n买种子 → 点种植床播种、浇水 → 早晨生长" % economy.count("coins")
		for crop_id in economy.farm.crop_definitions():
			var crop: Dictionary = economy.farm.crop_def(crop_id)
			var id := str(crop_id)
			row(body,"%s种子 ×%d · %d 个浇水日" % [crop.name,economy.count(crop.seed),crop.grow_days],"购买 1 · %d瓶盖" % crop.seed_price,
				func(): perform.call(func() -> Dictionary: return economy.farm.buy_seed(id)),economy.count("coins")>=int(crop.seed_price) and economy.inventory.can_add(crop.seed,1))
	elif tab == "storage":
		title.text = "保管仓库 %d / 48 格\n种子、鱼和收获物都能存取；这里的东西不会自动出售。" % economy.warehouse.slots_used()
		for item in economy.inventory.all():
			var id := str(item)
			if Items.is_currency(id): continue
			row(body,"背包 · %s ×%d" % [Items.label(id),economy.count(id)],"存入 1",func(): perform.call(func() -> Dictionary: return economy.storage.deposit(id,1)))
		for item in economy.warehouse.all():
			var id := str(item)
			row(body,"仓库 · %s ×%d" % [Items.label(id),economy.warehouse.count(id)],"取出 1",func(): perform.call(func() -> Dictionary: return economy.storage.withdraw(id,1)))
	else:
		var pending: Dictionary = economy.daily.query()
		title.text = "出货箱 · 收货员每天早上 07:00 收走货物\n待结算 %d 瓶盖；结算前可取回。仓库里的物品不会出售。" % pending.expected
		var receipt: Dictionary = pending.receipt
		if not receipt.is_empty(): title.text += "\n上次：第 %d 天，收入 %d 瓶盖" % [receipt.day,receipt.income]
		for item in economy.inventory.all():
			var id := str(item)
			if not economy.daily.accepts(id): continue
			row(body,"背包 · %s ×%d · 单价 %d瓶盖" % [Items.label(id),economy.count(id),Items.sell_price(id)],"放入 1",func(): perform.call(func() -> Dictionary: return economy.daily.deposit(id,1)))
		for item in pending.items:
			var id := str(item)
			row(body,"待出货 · %s ×%d" % [Items.label(id),int(pending.items[id])],"取回 1",func(): perform.call(func() -> Dictionary: return economy.daily.withdraw(id,1)))
		if pending.items.is_empty():
			var hint := Label.new()
			hint.text = "尚无出货。先捕鱼或收获，再把物品放进来。"
			body.add_child(hint)
	row(body,"岸上休息 · 醒来06:00，收货07:00","睡到06:00",rest)

static func row(body: VBoxContainer, text: String, action: String, callback: Callable, enabled := true) -> void:
	var box := HBoxContainer.new()
	body.add_child(box)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 340
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	var button := Button.new()
	button.text = action
	button.disabled = not enabled
	box.add_child(button)
	button.pressed.connect(callback)
