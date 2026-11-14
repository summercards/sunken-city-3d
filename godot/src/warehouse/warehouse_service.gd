extends RefCounted
## Feature-owned rules. External state is accessed only through configured ports.
signal resources_changed
const InventoryLib = preload("res://src/inventory/inventory.gd")
const ItemDBLib = preload("res://src/inventory/item_db.gd")
var warehouse = InventoryLib.new(48)
var inventory: RefCounted
func count(id: String) -> int:
	return inventory.count(id)
var ports: Dictionary = {}
var _busy := false

func is_busy() -> bool:
	return _busy or (inventory != null and inventory.is_busy()) or warehouse.is_busy()
func configure(boundary: Dictionary) -> void:
	if is_busy(): return
	assert(boundary.has("facility_unlocked") and boundary["facility_unlocked"].is_valid(), "Missing port: facility_unlocked")
	ports = boundary.duplicate()

func facility_unlocked(id: String) -> bool:
	return ports["facility_unlocked"].call(id)


func construction_count(id: String) -> int:
	return count(id) + warehouse.count(id)

func construction_has(cost: Dictionary) -> bool:
	for id in cost:
		if construction_count(id) < int(cost[id]): return false
	return true

func construction_pay(cost: Dictionary) -> bool:
	if is_busy() or not construction_has(cost): return false
	var carried_costs := {}
	var stored_costs := {}
	for id in cost:
		var carried := mini(count(id), int(cost[id]))
		if carried > 0: carried_costs[id] = carried
		var stored := int(cost[id]) - carried
		if stored > 0: stored_costs[id] = stored
	_busy = true
	var result := preload("res://src/inventory/inventory_transfer.gd").exchange(inventory, warehouse, carried_costs, {}, stored_costs, {})
	if not result.ok:
		_busy = false
		return false
	resources_changed.emit()
	_busy = false
	return true

func construction_missing_text(cost: Dictionary) -> String:
	var bits: Array[String] = []
	for id in cost:
		var lack := int(cost[id]) - construction_count(id)
		if lack > 0: bits.append("%s×%d" % [ItemDBLib.label(id), lack])
	return "还差 " + "、".join(bits) if not bits.is_empty() else ""

func construction_progress(cost: Dictionary) -> String:
	var bits: Array[String] = []
	for id in cost:
		bits.append("%s %d/%d" % [ItemDBLib.label(id), construction_count(id), int(cost[id])])
	return " · ".join(bits)

func deposit_materials() -> Dictionary:
	if is_busy(): return {"blocked":"库存正在提交"}
	if not facility_unlocked("warehouse"): return {"blocked":"先在建设页建好材料仓库"}
	var moved := 0
	var remaining := 0
	var amounts := {}
	var trial = InventoryLib.new()
	trial.from_dict(warehouse.to_dict())
	for id in inventory.all():
		if str(ItemDBLib.get_item(id).get("category", "")) != "material": continue
		var amount := mini(count(id), trial.room_for(id))
		if amount > 0:
			amounts[id] = amount
			trial.add(id, amount)
		moved += amount
		remaining += count(id) - amount
	_busy = true
	var result := preload("res://src/inventory/inventory_transfer.gd").exchange(inventory, warehouse, amounts, {}, {}, amounts)
	if result.ok: resources_changed.emit()
	_busy = false
	if not result.ok: return {"blocked":result.reason}
	return {"message":"已存入 %d 份材料%s" % [moved, "，其余留在背包（仓库已满）" if remaining > 0 else ""], "moved":moved}

func withdraw_material(id: String) -> Dictionary:
	if is_busy(): return {"blocked":"库存正在提交"}
	if not facility_unlocked("warehouse"): return {"blocked":"仓库尚未建成"}
	var amount := mini(warehouse.count(id), inventory.room_for(id))
	if amount <= 0: return {"blocked":"背包已满或没有库存"}
	return withdraw(id, amount)

func to_dict() -> Dictionary: return warehouse.to_dict()
func from_dict(data: Dictionary) -> void:
	if is_busy(): return
	_busy = true
	warehouse.from_dict(data)
	_busy = false

## General storage is separate from the shipping box; it never sells itself.
func deposit(id: String, amount: int) -> Dictionary:
	if is_busy(): return {"blocked":"库存正在提交"}
	if not facility_unlocked("warehouse"): return {"blocked":"仓库尚未开放"}
	if ItemDBLib.is_currency(id): return {"blocked":"瓶盖不需要入库"}
	_busy = true
	var result := preload("res://src/inventory/inventory_transfer.gd").move(inventory,warehouse,id,amount)
	if result.get("ok", false): resources_changed.emit()
	_busy = false
	return result

func withdraw(id: String, amount: int) -> Dictionary:
	if is_busy(): return {"blocked":"库存正在提交"}
	if not facility_unlocked("warehouse"): return {"blocked":"仓库尚未开放"}
	_busy = true
	var result := preload("res://src/inventory/inventory_transfer.gd").move(warehouse,inventory,id,amount)
	if result.get("ok", false): resources_changed.emit()
	_busy = false
	return result
