@tool
extends Node3D
class_name GatherField
## 采集点容器：从资产表生成世界里的采集物。
##
## 资产表 `assets/data/gather_spots.json` 是唯一来源，坐标是**世界坐标**
## （与 zones.json 一致）。改完表重跑一次场景即可，不需要改代码。

signal collected(kind: String, amount: int, label: String, spot: Node3D)
signal blocked(reason: String)

const GatherSpotLib = preload("res://src/gathering/gather_spot.gd")
const TABLE := "res://assets/data/gather_spots.json"

var spots: Array = []


func _ready() -> void:
	# 编辑器里把采集点摆出来（运行时的 build() 由 main.gd 调）。
	if Engine.is_editor_hint() and get_child_count() == 0:
		build()


func build(path := TABLE) -> void:
	for c in get_children():
		c.queue_free()
	spots.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("找不到采集点表：%s" % path)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("采集点表格式不对：%s" % path)
		return
	for row in data.get("spots", []):
		if not (row is Dictionary):
			continue
		var spot: Node3D = GatherSpotLib.new()
		spot.name = "Spot_%s" % str(row.get("id", "unnamed"))
		spot.setup(row)
		spot.set_meta("zone", str(row.get("zone", "")))
		add_child(spot)
		spot.harvested.connect(_on_harvested.bind(spot))
		spots.append(spot)


func _on_harvested(kind: String, amount: int, label: String, spot: Node3D) -> void:
	collected.emit(kind, amount, label, spot)


func zone_spots(zone_id: String) -> Array:
	var out: Array = []
	for s in spots:
		if str(s.get_meta("zone", "")) == zone_id:
			out.append(s)
	return out


func find(id: String) -> Node3D:
	for s in spots:
		if s.id == id:
			return s
	return null
