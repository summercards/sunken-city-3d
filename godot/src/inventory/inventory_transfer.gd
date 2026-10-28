extends RefCounted
## Preflight both sides; publish only a complete transfer, including on reentry.
static func move(source: RefCounted, target: RefCounted, id: String, amount: int) -> Dictionary:
	if amount <= 0 or source.count(id) < amount:
		return {"blocked":"数量不足"}
	if not target.can_add(id, amount):
		return {"blocked":"空间不足，物品仍在原处"}
	var source_blocked: bool = source.is_blocking_signals()
	var target_blocked: bool = target.is_blocking_signals()
	source.set_block_signals(true)
	target.set_block_signals(true)
	source.remove(id, amount)
	target.add(id, amount)
	source.set_block_signals(source_blocked)
	target.set_block_signals(target_blocked)
	source.changed.emit(id, -amount)
	target.changed.emit(id, amount)
	source.capacity_changed.emit(source.slots_used(),source.capacity())
	target.capacity_changed.emit(target.slots_used(),target.capacity())
	return {"ok":true,"moved":amount,"message":"已转移 %s ×%d" % [preload("res://src/inventory/item_db.gd").label(id),amount]}
