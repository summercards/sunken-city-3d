extends RefCounted
## Feature-owned rules. External state is accessed only through configured ports.
signal sites_changed
const FACILITIES := {
	"warehouse": {
		"name": "材料仓库",
		"description": "48 格材料专用仓库；建设自动使用仓库材料。",
		"cost": {"coins": 12, "wood": 4},
		"requires": {"home_cabin": 1},
	},
	"greenhouse": {
		"name": "屋顶温室",
		"description": "新种作物首茬少长 1 天，每茬多收 1 份。",
		"cost": {"coins": 15, "wood": 5, "parts": 3, "glass": 2},
		"requires": {"home_cabin": 2, "rooftop_planter": 1},
	},
	"recycler": {
		"name": "太阳能回收台",
		"description": "每 30 秒分拣 2 个旧零件，需主动收取。",
		"cost": {"coins": 15, "wood": 4, "parts": 4},
		"requires": {"home_cabin": 2, "yokohama_station": 1},
	},
}
var site_names: Dictionary = {}
var facilities := {"greenhouse":false,"recycler":false}
var ports: Dictionary = {}
func configure(boundary: Dictionary) -> void:
	assert(boundary.has("site_level") and boundary["site_level"].is_valid(), "Missing port: site_level")
	assert(boundary.has("construction_pay") and boundary["construction_pay"].is_valid(), "Missing port: construction_pay")
	assert(boundary.has("construction_has") and boundary["construction_has"].is_valid(), "Missing port: construction_has")
	assert(boundary.has("construction_missing_text") and boundary["construction_missing_text"].is_valid(), "Missing port: construction_missing_text")
	ports = boundary.duplicate()

func site_level(id: String) -> int:
	return ports["site_level"].call(id)

func construction_pay(cost: Dictionary) -> bool:
	return ports["construction_pay"].call(cost)

func construction_has(cost: Dictionary) -> bool:
	return ports["construction_has"].call(cost)

func construction_missing_text(cost: Dictionary) -> String:
	return ports["construction_missing_text"].call(cost)


func facility_unlocked(id: String) -> bool:
	return bool(facilities.get(id, false))

func facility_requirement_text(id: String) -> String:
	var spec: Dictionary = FACILITIES.get(id, {})
	for req in spec.get("requires", {}).keys():
		var need := int(spec.requires[req])
		if site_level(req) < need:
			var name := str(site_names.get(req, {}).get("name", req))
			return "需要先把 %s 升到 %d 级" % [name, need]
	return ""

func can_build_facility(id: String) -> bool:
	var spec: Dictionary = FACILITIES.get(id, {})
	if spec.is_empty() or facility_unlocked(id):
		return false
	if facility_requirement_text(id) != "":
		return false
	return construction_has(spec.cost)

func build_facility(id: String) -> Dictionary:
	var spec: Dictionary = FACILITIES.get(id, {})
	if spec.is_empty():
		return {"ok": false, "reason": "未知设施"}
	if facility_unlocked(id):
		return {"ok": false, "reason": "已经建好"}
	var req_text := facility_requirement_text(id)
	if req_text != "":
		return {"ok": false, "reason": req_text}
	if not construction_pay(spec.cost):
		return {"ok": false, "reason": construction_missing_text(spec.cost)}
	facilities[id] = true
	sites_changed.emit()
	return {"ok": true, "name": spec.name}

func to_dict() -> Dictionary: return {"facilities":facilities.duplicate()}
func from_dict(data: Dictionary) -> void:
	facilities.clear()
	for id in FACILITIES: facilities[id]=bool(data.get("facilities",{}).get(id,false))
	sites_changed.emit()
