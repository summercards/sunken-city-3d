extends RefCounted
## Stateless trade command; Inventory remains the only balance owner.
const PRICE := 4
var inventory: RefCounted


## 买土壤。`amount` 默认 1，界面上的 +/− 可以一次买多份。
##
## 原子性：先算总价、一起检查，够才扣。不允许"扣了一半发现背包放不下"。
## 这样界面上点 + 加到 5 再买，要么 5 份一起到账，要么一分瓶盖都不扣。
func buy_soil(amount := 1) -> Dictionary:
	amount = maxi(1, amount)
	var total: int = PRICE * amount
	if not inventory.can_add("soil",amount): return {"blocked":"背包已满"}
	if not inventory.has_all({"coins":total}): return {"blocked":"瓶盖不足"}
	var old_blocked := inventory.is_blocking_signals()
	inventory.set_block_signals(true)
	inventory.pay({"coins":total});inventory.add("soil",amount)
	inventory.set_block_signals(old_blocked)
	inventory.changed.emit("coins",-total)
	inventory.changed.emit("soil",amount)
	inventory.capacity_changed.emit(inventory.slots_used(),inventory.capacity())
	return {"ok":true,"event":"bought","name":"土壤","amount":amount}
