extends RefCounted
## Owns queued shipments and the dawn watermark. Clock/farm/inventory are ports.
signal changed
signal settled(receipt: Dictionary)
const Items = preload("res://src/inventory/item_db.gd")
const Transfer = preload("res://src/inventory/inventory_transfer.gd")
var cargo = preload("res://src/inventory/inventory.gd").new(48)
var inventory: RefCounted
var grow: Callable
var sync_day: Callable
var _last_morning := -1
var _receipt: Dictionary = {}
var _busy := false

func accepts(id: String) -> bool:
	return id in ["fish","vegetable","tomato","pumpkin"]

func deposit(id: String, amount: int) -> Dictionary:
	if _busy: return {"blocked":"正在结算"}
	if not accepts(id): return {"blocked":"出货箱只收鱼和农产品"}
	var result := Transfer.move(inventory,cargo,id,amount)
	changed.emit()
	return result

func withdraw(id: String, amount: int) -> Dictionary:
	if _busy: return {"blocked":"正在结算"}
	var result := Transfer.move(cargo,inventory,id,amount)
	changed.emit()
	return result

func query() -> Dictionary:
	var total := 0
	for id in cargo.all(): total += cargo.count(id)*Items.sell_price(id)
	return {"items":cargo.all(),"capacity":cargo.capacity(),"slots_used":cargo.slots_used(),"expected":total,"last_morning":_last_morning,"receipt":_receipt.duplicate(true)}

func observe(clock: Dictionary) -> void:
	if _busy: return
	var day := int(clock.day)
	var morning := day if float(clock.hour) >= preload("res://src/time/day_schedule.gd").MORNING_HOUR else day-1
	if _last_morning < 0:
		_last_morning = morning
		sync_day.call(day)
		return
	if morning <= _last_morning: return
	_busy = true
	var income := int(query().expected)
	var items: Dictionary = cargo.all()
	# Complete inventory state and watermark before publishing rewards.
	var blocked: bool = inventory.is_blocking_signals()
	inventory.set_block_signals(true)
	cargo.clear()
	inventory.add("coins",income)
	_last_morning = morning
	_receipt = {"day":day,"income":income,"items":items}
	# A skipped interval has no additional watering; only the first dawn can grow.
	grow.call()
	sync_day.call(day)
	inventory.set_block_signals(blocked)
	_busy = false
	inventory.changed.emit("coins",income)
	changed.emit()
	settled.emit(_receipt.duplicate(true))

func to_dict() -> Dictionary:
	return {"version":1,"cargo":cargo.to_dict(),"last_morning":_last_morning,"receipt":_receipt.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	cargo.from_dict(data.get("cargo",{"capacity":48,"counts":{}}))
	_last_morning = int(data.get("last_morning",-1))
	_receipt = data.get("receipt",{}).duplicate(true)
	changed.emit()

func is_settling() -> bool: return _busy
