@tool
extends Marker3D
## 泊位不拥有另一块地面；父节点就是所属 WalkArea，本节点就是上岸点。
@export var landing_id := "main"
@export var landing_label := "泊位"

func ground() -> Node3D:
	return get_parent() as Node3D

func stand_position() -> Vector3:
	var p := global_position
	var support: Vector3 = ground().surface_point(p)
	if support.is_finite(): p = support
	return p

func data() -> Dictionary:
	var stand := stand_position()
	var park: Marker3D = get_node("BoatPark")
	var edge: Marker3D = get_node("DockEdge")
	return {"id": landing_id, "name": landing_label, "ground_id": ground().area_id,
		"landStand": [stand.x, stand.y, stand.z],
		"boatPark": [park.global_position.x, park.global_position.y, park.global_position.z],
		"boatYaw": park.global_rotation.y,
		"dockEdge": [edge.global_position.x, edge.global_position.y, edge.global_position.z]}
