extends RefCounted
## Stateless trade command; Inventory remains the only balance owner.
const PRICE := 4
var inventory: RefCounted
func buy_soil() -> Dictionary:
	if not inventory.can_add("soil",1): return {"blocked":"背包已满"}
	if not inventory.has_all({"coins":PRICE}): return {"blocked":"瓶盖不足"}
	var old_blocked := inventory.is_blocking_signals()
	inventory.set_block_signals(true)
	inventory.pay({"coins":PRICE});inventory.add("soil",1)
	inventory.set_block_signals(old_blocked)
	inventory.changed.emit("coins",-PRICE)
	inventory.changed.emit("soil",1)
	inventory.capacity_changed.emit(inventory.slots_used(),inventory.capacity())
	return {"ok":true,"event":"bought","name":"土壤"}
