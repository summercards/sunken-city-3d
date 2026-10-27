extends RefCounted
## Feature-owned rules. External state is accessed only through configured ports.
signal resources_changed
var SITES: Dictionary = {}
var FACILITIES: Dictionary = {}
var tracked_goal := ""
var ship_level: int:
	get: return ports["ship_level"].call()
var ports: Dictionary = {}
func configure(boundary: Dictionary) -> void:
	assert(boundary.has("facility_unlocked") and boundary["facility_unlocked"].is_valid(), "Missing port: facility_unlocked")
	assert(boundary.has("site_level") and boundary["site_level"].is_valid(), "Missing port: site_level")
	assert(boundary.has("ship_cost") and boundary["ship_cost"].is_valid(), "Missing port: ship_cost")
	assert(boundary.has("site_next_cost") and boundary["site_next_cost"].is_valid(), "Missing port: site_next_cost")
	assert(boundary.has("ship_level") and boundary["ship_level"].is_valid(), "Missing port: ship_level")
	ports = boundary.duplicate()

func facility_unlocked(id: String) -> bool:
	return ports["facility_unlocked"].call(id)

func site_level(id: String) -> int:
	return ports["site_level"].call(id)

func ship_cost() -> Dictionary:
	return ports["ship_cost"].call()

func site_next_cost(id: String) -> Dictionary:
	return ports["site_next_cost"].call(id)

func query_ship_level() -> int:
	return ports["ship_level"].call()


func goal_complete(id: String) -> bool:
	if FACILITIES.has(id): return facility_unlocked(id)
	if id == "ship": return ship_level >= 2
	if id == "ship3": return ship_level >= 3
	if SITES.has(id): return site_level(id) >= 2
	return true

func goal_info() -> Dictionary:
	var id := tracked_goal
	if id == "" or goal_complete(id):
		id = ""
		for candidate in ["warehouse", "rooftop_planter", "home_cabin", "ship", "greenhouse", "recycler", "ship3"]:
			if not goal_complete(candidate):
				id = candidate
				break
	if id == "": return {"id":"", "name":"第一阶段建设已完成，享受种植与探索吧", "cost":{}}
	if FACILITIES.has(id): return {"id":id, "name":FACILITIES[id].name, "cost":FACILITIES[id].cost}
	if id.begins_with("ship"): return {"id":id, "name":"小船升到 %d 级" % (2 if id == "ship" else 3), "cost":ship_cost()}
	return {"id":id, "name":SITES[id].name + "升到 2 级", "cost":site_next_cost(id)}

func track_goal(id: String) -> void:
	tracked_goal = id
	resources_changed.emit()

func to_dict() -> Dictionary: return {"tracked_goal":tracked_goal}
func from_dict(data: Dictionary) -> void:
	tracked_goal = str(data.get("tracked_goal",""))
	resources_changed.emit()
