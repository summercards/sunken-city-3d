extends RefCounted

const Rewards = preload("res://src/salvage/salvage_rewards.gd")
const Bag = preload("res://src/inventory/inventory.gd")
const Items = preload("res://src/inventory/item_db.gd")

func run(check: Callable) -> void:
	var rewards = Rewards.new()
	var bag = Bag.new(2)
	rewards.configure({"add_all": bag.add_all})
	var signals := [0]
	rewards.salvage_ready.connect(func(): signals[0] += 1)
	var haul := {"wood": 3, "parts": 2}
	for free in [0, 1, 2]:
		bag.clear()
		if free < 2: bag.set_count("glass", Items.stack_limit("glass"))
		if free == 0: bag.set_count("pearl", Items.stack_limit("pearl"))
		var before: Dictionary = bag.to_dict()
		var ready_at: float = rewards.salvage_ready_at
		var got: Dictionary = rewards.do_salvage(100.0)
		var detail: Dictionary = rewards.last_result()
		check.call(got == haul if free == 2 else got.is_empty(), "打捞 %d 空格整笔入账或拒绝" % free)
		check.call(detail.ok == (free == 2) and detail.added == got, "打捞 %d 空格详细结果与兼容返回一致" % free)
		if free < 2:
			check.call(bag.to_dict() == before and rewards.salvage_ready_at == ready_at and signals[0] == 0, "打捞拒绝不改数量/顺序/冷却/信号")
			check.call(detail.overflow == haul and not detail.reason.is_empty(), "打捞拒绝返回整笔未入账数量和原因")
	check.call(rewards.salvage_cooldown_left(100.0) == 16.0 and signals[0] == 1, "打捞成功后才写16秒冷却并通知一次")
	var before: Dictionary = bag.to_dict()
	check.call(rewards.do_salvage(100.0).is_empty() and bag.to_dict() == before and signals[0] == 1, "冷却内重复命令零入账零事件")
	check.call(rewards.last_result().reason == "打捞正在冷却", "重复命令反馈真实冷却原因")
	check.call(rewards.do_salvage(116.0) == haul and signals[0] == 2, "冷却截止时可再次整笔提交")
	var copy: Dictionary = rewards.last_result()
	copy.added.clear()
	copy.overflow["wood"] = 999
	check.call(rewards.last_result().added == haul and rewards.last_result().overflow.is_empty(), "结算结果深副本不可污染owner")

	bag.clear()
	bag.set_count("wood", Items.stack_limit("wood") - 3)
	bag.set_count("parts", Items.stack_limit("parts") - 2)
	rewards.salvage_ready_at = 0.0
	check.call(bag.slots_free() == 0 and rewards.do_salvage(200.0) == haul, "零空格但已有半堆能整笔接收")
	check.call(bag.count("wood") == Items.stack_limit("wood") and bag.count("parts") == Items.stack_limit("parts"), "已有半堆准确补满")
	bag.clear()
	bag.set_count("wood", Items.stack_limit("wood") - 2)
	bag.set_count("parts", Items.stack_limit("parts") - 2)
	rewards.salvage_ready_at = 0.0
	before = bag.to_dict()
	check.call(rewards.do_salvage(300.0).is_empty() and bag.to_dict() == before and rewards.can_salvage(300.0), "一项半堆不足整笔拒绝不提前补另一项")

	var composite := {"wood": 3, "parts": 2, "glass": 1, "pearl": 1}
	for capacity in [3, 4]:
		var composite_bag = Bag.new(capacity)
		rewards.configure({"receive_all": composite_bag.add_all})
		rewards.salvage_ready_at = 0.0
		var got: Dictionary = rewards.commit_salvage(400.0, composite)
		check.call(got == composite if capacity == 4 else got.is_empty(), "四资源复合奖励 %d 格整笔结果" % capacity)
		check.call(composite_bag.all() == composite if capacity == 4 else composite_bag.all().is_empty(), "四资源复合奖励无部分入账")
		check.call(rewards.can_salvage(400.0) == (capacity == 3), "四资源复合奖励仅成功写冷却")

	bag.clear()
	rewards.configure({"add_all": bag.add_all})
	for invalid in [{}, {"wood": 0}, {"wood": -1}, {"wood": 3, "parts": 0}, {"wood": 3, "parts": -2}, {"wood": 3, "missing_item": 1}, {"wood": 1.5}, {"wood": "3"}, {"wood": true}, {"wood": INF}, {"wood": NAN}, {1: 2}]:
		rewards.salvage_ready_at = 0.0
		before = bag.to_dict()
		var events_before: int = signals[0]
		check.call(rewards.commit_salvage(500.0, invalid).is_empty(), "无效/非正/未知资源奖励拒绝：%s" % str(invalid))
		check.call(bag.to_dict() == before and rewards.salvage_ready_at == 0.0 and signals[0] == events_before, "无效奖励不改库存/顺序/冷却/信号")
		check.call(not rewards.last_result().reason.is_empty(), "无效奖励有明确拒绝原因")
	check.call(rewards.commit_salvage(500.0, {"wood": 3.0, "parts": 2.0}) == haul, "JSON整数浮点数量兼容并规范为整数")

	var legacy_calls := [0]
	rewards.configure({"give": func(_gains: Dictionary) -> Dictionary: legacy_calls[0] += 1; return haul})
	rewards.salvage_ready_at = 0.0
	check.call(rewards.do_salvage(600.0).is_empty() and legacy_calls[0] == 0 and rewards.can_salvage(600.0), "只有逐项give时安全拒绝而非部分写入")
	check.call(rewards.last_result().reason == "打捞原子入账端口未接入", "未接线提供可诊断原因")
	rewards.configure({"receive_all": func(_gains: Dictionary) -> Dictionary: return {"ok": false, "reason": "库存暂不可用"}})
	check.call(rewards.do_salvage(600.0).is_empty() and rewards.last_result().reason == "库存暂不可用" and rewards.last_result().overflow == haul, "原子owner拒绝原因及整笔overflow原样反馈")

	bag.clear()
	rewards.configure({"add_all": bag.add_all})
	rewards.salvage_ready_at = 0.0
	var observed := []
	var reentered := []
	var listener := func(_id: String, _delta: int):
		observed.append(rewards.is_busy())
		reentered.append(rewards.commit_salvage_result(700.0, haul))
	bag.changed.connect(listener)
	var result: Dictionary = rewards.commit_salvage_result(700.0, haul)
	check.call(result.ok and result.added == haul and bag.all() == haul, "库存同步回调重入仍仅入账一笔")
	check.call(observed == [true, true] and reentered.size() == 2, "库存发布期间owner保持busy")
	check.call(not reentered[0].ok and reentered[0].reason == "打捞正在结算" and not reentered[1].ok, "同步重入明确拒绝")
	check.call(not rewards.is_busy() and rewards.last_result() == result, "重入拒绝不污染最终结果且退出释放busy")
	bag.changed.disconnect(listener)
	var on_ready := func(): reentered.append(rewards.do_salvage(800.0))
	rewards.salvage_ready.connect(on_ready)
	check.call(rewards.do_salvage(800.0) == haul and bag.count("wood") == 6 and reentered.back().is_empty(), "结算事件内超前时间重入也不重复发奖")
	rewards.salvage_ready.disconnect(on_ready)
	var restored = Rewards.new()
	restored.from_dict({"left": 8.0})
	check.call(absf(float(restored.to_dict().left) - 8.0) < 0.1, "相对冷却快照格式保持兼容")
	print("[salvage-rewards] 专项断言完成")
