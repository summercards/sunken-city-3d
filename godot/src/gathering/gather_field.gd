@tool
extends Node3D
class_name GatherField
## Index the authored gather spots and persist their cooldowns by ID.

signal collected(kind: String, amount: int, label: String, spot: Node3D)
signal blocked(reason: String)

const ConstructionDependency = preload("res://src/construction/construction_service.gd")
var construction: ConstructionDependency
## SEA-ENERGY：可选端口，签名 (action: String) -> String。
## 交给每个采集点自己问，体力不够时按住 E 就直接被拦下，
## 不会出现「采掉了却没进包」。
var energy_reason: Callable
var spots: Array = []

func to_dict() -> Dictionary:
	var result := {}
	for spot in spots:
		if spot.seconds_left()>0.0: result[str(spot.id)]=spot.seconds_left()
	return result

func from_dict(data: Dictionary) -> void:
	for spot in spots: spot.restore_cooldown(float(data.get(str(spot.id),0.0)))


func build() -> void:
	spots.clear()
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is not GatherSpot:
			continue
		node.construction = construction
		node.energy_reason = energy_reason
		var relay := _on_harvested.bind(node)
		if not node.harvested.is_connected(relay):
			node.harvested.connect(relay)
		spots.append(node)


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
