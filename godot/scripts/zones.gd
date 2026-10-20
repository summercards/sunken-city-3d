extends Node
## 区块注册表。
##
## 数值来源：网页版 zones.js（tools 里用脚本导出的 zones.json）。
## 约定与网页版一致：所有点位已经是世界坐标（区块内坐标已加 origin）。

const WATER_LEVEL := 1.12

var list: Array = []
var by_id: Dictionary = {}


func _ready() -> void:
	var text := FileAccess.get_file_as_string("res://assets/data/zones.json")
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("zones.json 解析失败")
		return
	list = parsed
	for z in list:
		by_id[z.id] = z


func get_zone(id: String) -> Dictionary:
	return by_id.get(id, {})


func label(id: String) -> String:
	return get_zone(id).get("name", id)


func landing(zone_id: String, landing_id: String = "main") -> Dictionary:
	var zone := get_zone(zone_id)
	if zone.is_empty():
		return {}
	var landings: Array = zone.get("landings", [])
	for l in landings:
		if landing_id == "" or l.id == landing_id:
			return l
	return landings[0] if landings.size() > 0 else {}


func landings_of(zone_id: String) -> Array:
	return get_zone(zone_id).get("landings", [])


func is_unlocked(zone_id: String) -> bool:
	var zone := get_zone(zone_id)
	if zone.is_empty():
		return false
	if zone.get("unlock", null) == "farSea":
		return GameState.far_sea_unlocked
	return true


## 区块在水面上的大致轮廓，供水面岸线泡沫使用。
func footprint(zone_id: String) -> Rect2:
	var zone := get_zone(zone_id)
	var rect := Rect2()
	var first := true
	for w in zone.get("walk", []):
		for r in w.rects:
			var rr := Rect2(r[0], r[2], r[1] - r[0], r[3] - r[2])
			if first:
				rect = rr
				first = false
			else:
				rect = rect.merge(rr)
	return rect


func zone_at(point: Vector3, radius: float = 12.0) -> String:
	var best := ""
	var best_d := radius
	for z in list:
		var fp: Rect2 = footprint(z.id)
		var c := fp.get_center()
		var d := Vector2(point.x - c.x, point.z - c.y).length()
		if d < best_d:
			best_d = d
			best = z.id
	return best
