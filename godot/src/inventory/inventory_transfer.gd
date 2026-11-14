extends RefCounted

static func move(source: RefCounted, target: RefCounted, id: String, amount: int) -> Dictionary:
	if source.is_busy() or target.is_busy(): return {"blocked":"库存正在提交"}
	if amount <= 0 or source.count(id) < amount: return {"blocked":"数量不足"}
	var result := exchange(source, target, {id: amount}, {}, {}, {id: amount})
	if not result.ok: return {"blocked":result.reason}
	return {"ok":true,"moved":amount,"message":"已转移 %s ×%d" % [preload("res://src/inventory/item_db.gd").label(id),amount]}

## 两端都完成预检和静默提交后才发布；失败回滚不产生退款事件。
static func exchange(source: RefCounted, target: RefCounted, source_costs: Dictionary, source_gains: Dictionary, target_costs: Dictionary, target_gains: Dictionary) -> Dictionary:
	if source == target or source.is_busy() or target.is_busy(): return {"ok":false,"reason":"库存正在提交"}
	var owners := [source, target]
	var costs := [source_costs, target_costs]
	var gains := [source_gains, target_gains]
	var before: Array = []
	var orders: Array = []
	var blocked: Array = []
	for i in 2:
		before.append(owners[i].to_dict())
		orders.append(owners[i]._order.duplicate())
		var trial = preload("res://src/inventory/inventory.gd").new()
		trial.from_dict(before[i])
		var checked: Dictionary = trial.exchange(costs[i], gains[i])
		if not checked.ok: return checked
	for owner in owners:
		blocked.append(owner.is_blocking_signals())
		owner.set_block_signals(true)
	var result := {"ok":true,"reason":""}
	for i in 2:
		result = owners[i].exchange(costs[i], gains[i])
		if not result.get("ok", false): break
	if not result.get("ok", false):
		for i in 2:
			owners[i].from_dict(before[i])
			owners[i]._order = orders[i]
	else:
		for owner in owners: owner._transaction_busy = true
	for i in 2: owners[i].set_block_signals(blocked[i])
	if not result.get("ok", false): return result
	for i in 2:
		var ids: Array = costs[i].keys()
		for id in gains[i]:
			if not ids.has(id): ids.append(id)
		for id in ids:
			var delta: int = owners[i].count(id) - int(before[i].counts.get(id, 0))
			if delta != 0: owners[i].changed.emit(str(id), delta)
		owners[i].capacity_changed.emit(owners[i].slots_used(), owners[i].capacity())
	for owner in owners: owner._transaction_busy = false
	return result
