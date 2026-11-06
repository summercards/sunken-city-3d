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

const ConstructionDependency = preload("res://src/construction/construction_service.gd")
var construction: ConstructionDependency
## SEA-ENERGY：可选端口，签名 (action: String) -> String。
## 交给每个采集点自己问，体力不够时按住 E 就直接被拦下，
## 不会出现「采掉了却没进包」。
var energy_reason: Callable
## 区块查询：签名 (zone_id: String) -> Node（ZoneScene / RoomScene）。
## 只用来在装配时把采集点吸附到**场景里真实的可走面**上，见 _snap_to_ground()。
var zone_query: Callable
var spots: Array = []

func to_dict() -> Dictionary:
	var result := {}
	for spot in spots:
		if spot.seconds_left()>0.0: result[str(spot.id)]=spot.seconds_left()
	return result

func from_dict(data: Dictionary) -> void:
	for spot in spots: spot.restore_cooldown(float(data.get(str(spot.id),0.0)))


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
		spot.construction = construction
		spot.energy_reason = energy_reason
		spot.setup(row)
		spot.set_meta("zone", str(row.get("zone", "")))
		add_child(spot)
		spot.harvested.connect(_on_harvested.bind(spot))
		spots.append(spot)
	for spot in spots:
		_snap_to_ground(spot)


## 把采集点贴到场景里的可走面（SEA-GATHER-R06，2026-11-06）。
##
## 为什么不在生成器里算好：`gather_spots.json` 的 y 来自 `zones.json` 的行走矩形，
## 而那座甲板后来被手工下调过（2.15 → 1.38），表没跟着更新 —— 结果贝壳悬在
## 甲板上方 0.77 米，看着像浮空，落点也判不出「脚下是哪块地」。
## 按仓库约定，场景（TSCN）才是位置的唯一真值，所以这里在装配时以场景回算：
##   1. XZ 保持表里的设计摆放；
##   2. 高度取该 XZ 在当前区块可走面上的真实表面；
##   3. XZ 完全不在任何可走面（>3 米）时，才挪到最近的可站点，并打一行警告。
## 表里的 y 从此只是提示值，改甲板不需要再回来改表。
func _snap_to_ground(spot: Node3D) -> void:
	if not zone_query.is_valid():
		return
	var zone: Variant = zone_query.call(str(spot.get_meta("zone", "")))
	if zone == null or not is_instance_valid(zone) or not ("walk_areas" in zone):
		return
	var p: Vector3 = spot.position
	var best_area: Variant = null
	var best_delta := INF
	for area in zone.walk_areas:
		var at: Vector3 = area.surface_point(Vector3(p.x, area.surface_y, p.z))
		if not at.is_finite():
			continue
		var delta := absf(at.y - p.y)
		if delta < best_delta and delta <= 3.0:
			best_delta = delta
			best_area = area
	if best_area != null:
		spot.position.y = p.y + (best_area.surface_point(Vector3(p.x, best_area.surface_y, p.z)).y - p.y)
		return
	# 表里的 XZ 已经不在任何一块可走面上（布局改过）：挪到最近的可站点。
	var moved := Vector3.INF
	var moved_d := INF
	for area in zone.walk_areas:
		var flat: Vector2 = area.clamp_point(p.x, p.z)
		var at2: Vector3 = area.surface_point(Vector3(flat.x, area.surface_y, flat.y))
		if not at2.is_finite():
			continue
		var d := Vector2(at2.x - p.x, at2.z - p.z).length()
		if d < moved_d:
			moved_d = d
			moved = at2
	if not moved.is_finite():
		push_warning("[gather] %s 找不到可走面，保持表内坐标 %s" % [spot.name, str(p)])
		return
	push_warning("[gather] %s 的表格坐标不在可走面上，吸附到 (%.2f, %.2f, %.2f)" % [
		spot.name, moved.x, moved.y, moved.z])
	spot.position = moved


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
