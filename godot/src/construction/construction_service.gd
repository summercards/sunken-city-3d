extends RefCounted
## Feature-owned rules. External state is accessed only through configured ports.
signal sites_changed
signal site_work_started(id: String, seconds: float)
signal site_work_finished(id: String, level: int)
const SITES := {
	"home_cabin": {"name": "太阳能木屋", "zone": "zone1", "max_level": 3, "costs": [
		{"coins": 20, "wood": 4, "parts": 2},
		{"coins": 45, "wood": 9, "parts": 5},
	], "seconds": [18.0, 30.0]},
	"rooftop_planter": {"name": "圆弧屋顶农场", "zone": "zone3", "max_level": 3, "costs": [
		{"coins": 25, "wood": 5, "parts": 3},
		{"coins": 55, "wood": 11, "parts": 6},
	], "seconds": [20.0, 34.0]},
	"yokohama_station": {"name": "横滨沉没铁道", "zone": "zone2", "max_level": 2, "costs": [
		{"coins": 30, "wood": 6, "parts": 4},
	], "seconds": [22.0]},
}
var site_levels := {"home_cabin":1,"rooftop_planter":1,"yokohama_station":1}
var site_work := {}
var ports: Dictionary = {}
func configure(boundary: Dictionary) -> void:
	assert(boundary.has("construction_pay") and boundary["construction_pay"].is_valid(), "Missing port: construction_pay")
	assert(boundary.has("construction_missing_text") and boundary["construction_missing_text"].is_valid(), "Missing port: construction_missing_text")
	ports = boundary.duplicate()

func construction_pay(cost: Dictionary) -> bool:
	return ports["construction_pay"].call(cost)

func construction_missing_text(cost: Dictionary) -> String:
	return ports["construction_missing_text"].call(cost)


func site_level(id: String) -> int:
	return int(site_levels.get(id, 1))

func site_next_cost(id: String) -> Dictionary:
	var spec: Dictionary = SITES.get(id, {})
	var level := site_level(id)
	var costs: Array = spec.get("costs", [])
	if level - 1 >= costs.size():
		return {}
	return costs[level - 1]

func site_maxed(id: String) -> bool:
	var spec: Dictionary = SITES.get(id, {})
	return site_level(id) >= int(spec.get("max_level", 1))

func site_build_seconds(id: String) -> float:
	var spec: Dictionary = SITES.get(id, {})
	var table: Array = spec.get("seconds", [])
	var idx := site_level(id) - 1
	if idx >= 0 and idx < table.size():
		return float(table[idx])
	return 20.0

func is_building(id: String) -> bool:
	return site_work.has(id)

func site_work_left(id: String) -> float:
	if not site_work.has(id):
		return 0.0
	return float(site_work[id].left)

func site_work_progress(id: String) -> float:
	if not site_work.has(id):
		return 0.0
	var w: Dictionary = site_work[id]
	return clampf(1.0 - float(w.left) / maxf(float(w.total), 0.001), 0.0, 1.0)

func begin_site_upgrade(id: String) -> Dictionary:
	if not SITES.has(id):
		return {"ok": false, "reason": "未知建造点"}
	if is_building(id):
		return {"ok": false, "reason": "正在施工中"}
	if site_maxed(id):
		return {"ok": false, "reason": "已经是最高等级"}
	var cost := site_next_cost(id)
	if cost.is_empty():
		return {"ok": false, "reason": "没有更多等级"}
	if not construction_pay(cost):
		return {"ok": false, "reason": construction_missing_text(cost)}
	var seconds := site_build_seconds(id)
	site_work[id] = {"left": seconds, "total": seconds}
	site_work_started.emit(id, seconds)
	sites_changed.emit()
	return {"ok": true, "seconds": seconds, "cost": cost, "name": SITES[id].name}

func tick_sites(delta: float) -> Array:
	var done: Array = []
	for id in site_work.keys():
		var w: Dictionary = site_work[id]
		w.left = float(w.left) - delta
		if w.left > 0.0:
			continue
		site_work.erase(id)
		site_levels[id] = site_level(id) + 1
		done.append(id)
		site_work_finished.emit(id, site_level(id))
	if not done.is_empty():
		sites_changed.emit()
	return done

func construction_has(cost: Dictionary) -> bool:
	return ports["construction_has"].call(cost)

func to_dict() -> Dictionary:
	return {"site_levels":site_levels.duplicate(),"site_work":site_work.duplicate(true)}
func from_dict(data: Dictionary) -> void:
	site_levels = {"home_cabin":1,"rooftop_planter":1,"yokohama_station":1}
	site_work.clear()
	for id in data.get("site_levels",{}):
		if SITES.has(id): site_levels[id]=clampi(int(data.site_levels[id]),1,int(SITES[id].max_level))
	for id in data.get("site_work",{}):
		if SITES.has(id) and not site_maxed(id): site_work[id]=data.site_work[id].duplicate(true)
	sites_changed.emit()
