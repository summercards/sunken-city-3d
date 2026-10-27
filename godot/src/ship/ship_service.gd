extends RefCounted
## Feature-owned rules. External state is accessed only through configured ports.
signal resources_changed
signal upgraded(level: int)
const SHIP_RECIPE := {"coins": 25, "wood": 6, "parts": 4, "rope": 2}
var ship_level := 1
var ports: Dictionary = {}
func configure(boundary: Dictionary) -> void:
	assert(boundary.has("construction_pay") and boundary["construction_pay"].is_valid(), "Missing port: construction_pay")
	assert(boundary.has("construction_has") and boundary["construction_has"].is_valid(), "Missing port: construction_has")
	assert(boundary.has("construction_missing_text") and boundary["construction_missing_text"].is_valid(), "Missing port: construction_missing_text")
	ports = boundary.duplicate()

func construction_pay(cost: Dictionary) -> bool:
	return ports["construction_pay"].call(cost)

func construction_has(cost: Dictionary) -> bool:
	return ports["construction_has"].call(cost)

func construction_missing_text(cost: Dictionary) -> String:
	return ports["construction_missing_text"].call(cost)


func can_upgrade_ship() -> bool:
	return ship_level < 3 and construction_has(ship_cost())

func upgrade_ship() -> Dictionary:
	if ship_level >= 3:
		return {"ok": false, "reason": "船已经满级"}
	if not construction_pay(ship_cost()):
		return {"ok": false, "reason": construction_missing_text(ship_cost())}
	ship_level += 1
	upgraded.emit(ship_level)
	resources_changed.emit()
	return {"ok": true, "level": ship_level}

func ship_cost() -> Dictionary:
	return SHIP_RECIPE if ship_level == 1 else {"coins":60, "wood":10, "parts":8, "rope":4}

func to_dict() -> Dictionary: return {"ship_level":ship_level}
func from_dict(data: Dictionary) -> void:
	ship_level = clampi(int(data.get("ship_level",1)),1,3)
	resources_changed.emit()
