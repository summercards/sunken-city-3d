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
func configure(boundary: Dictionary) -> void:
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
	if not construction_has(cost): return false
	for id in cost:
		var carried := mini(count(id), int(cost[id]))
		inventory.remove(id, carried)
		warehouse.remove(id, int(cost[id]) - carried)
	resources_changed.emit()
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
	if not facility_unlocked("warehouse"): return {"blocked":"先在建设页建好材料仓库"}
	var moved := 0
	var remaining := 0
	for id in inventory.all():
		if str(ItemDBLib.get_item(id).get("category", "")) != "material": continue
		var amount := mini(count(id), warehouse.room_for(id))
		inventory.remove(id, amount)
		warehouse.add(id, amount)
		moved += amount
		remaining += count(id)
	resources_changed.emit()
	return {"message":"已存入 %d 份材料%s" % [moved, "，其余留在背包（仓库已满）" if remaining > 0 else ""], "moved":moved}

func withdraw_material(id: String) -> Dictionary:
	if not facility_unlocked("warehouse"): return {"blocked":"仓库尚未建成"}
	var amount := mini(warehouse.count(id), inventory.room_for(id))
	if amount <= 0: return {"blocked":"背包已满或没有库存"}
	warehouse.remove(id, amount)
	inventory.add(id, amount)
	resources_changed.emit()
	return {"message":"已取出 %s ×%d" % [ItemDBLib.label(id), amount]}

func to_dict() -> Dictionary: return warehouse.to_dict()
func from_dict(data: Dictionary) -> void: warehouse.from_dict(data)
