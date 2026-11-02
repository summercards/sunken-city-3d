extends RefCounted
## 渔场改造页（SEA-AQUA-R04）。版式复用种植页的行列表：左侧一句说明、
## 右侧一颗动作胶囊，禁用态写明原因 —— 与「种植 / 浇水 / 收获」完全一致。
##
## 只负责显示与转发：材料计数、扣费、状态都在 `FisheryModel` 后面。
const Rows = preload("res://src/ui/home_loop_panel.gd")
const Items = preload("res://src/inventory/item_db.gd")

static func build(body: VBoxContainer, economy: Node, perform: Callable) -> void:
	var fishery = economy.fishery
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 570
	title.text = "建造渔场\n整理岸坪，搭起围网和浮漂，让游鱼聚在水中。建造需要木板 100、鱼 50。每4小时积累3条鱼，最多24条；到渔场点击收获，装进背包。"
	body.add_child(title)
	var parts: Array[String] = []
	for id in fishery.COST:
		parts.append("%s %d / %d" % [Items.label(str(id)), int(fishery.held(str(id))), int(fishery.COST[id])])
	var stock := Label.new()
	stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock.custom_minimum_size.x = 570
	stock.text = "所需材料 · " + "   ".join(parts) + "\n背包与仓库里的材料一起算。"
	body.add_child(stock)
	if fishery.unlocked:
		Rows.row(body, "这里已经是渔场了", "已完成", func() -> void: pass, false)
		return
	var reason := str(fishery.reason())
	Rows.row(body, "建造渔场" if reason == "" else reason, "建造渔场", perform, reason == "")
