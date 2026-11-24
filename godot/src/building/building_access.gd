extends Node
## A finished dock contributes its authored berth. Ordinary board edges have none.
const Catalog = preload("res://src/building/building_catalog.gd")

var service: RefCounted
var world: Node3D
var markers: CanvasLayer

func configure(model: RefCounted, projection: Node3D, icons: CanvasLayer) -> void:
	service = model
	world = projection
	markers = icons
	service.changed.connect(refresh_markers)
	refresh_markers()

static func is_dynamic(id: String) -> bool:
	return id.begins_with("built:")

static func dock_id(instance_id: String) -> String:
	return "built:" + instance_id + ":dock"

func has_berth(id: String, rows: Array) -> bool:
	for row: Dictionary in rows:
		if Catalog.is_dock(row.kind) and row.left <= 0 and dock_id(row.id) == id:
			return true
	return false

func landing_node(id: String) -> Node3D:
	var parts := id.split(":")
	if parts.size() != 3 or parts[0] != "built" or parts[2] != "dock": return null
	var row: Dictionary = service.row(parts[1])
	if row.is_empty() or not Catalog.is_dock(row.kind) or row.left > 0: return null
	var component: Node3D = world.node_for(parts[1])
	return component.get_node("DockWalk/Berth") if is_instance_valid(component) else null

func landing_data(id: String) -> Dictionary:
	var berth := landing_node(id)
	return berth.data() if berth != null else {}

func berth_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in service.query():
		if Catalog.is_dock(row.kind) and row.left <= 0: ids.append(dock_id(row.id))
	return ids

func refresh_markers() -> void:
	var definitions: Array = []
	for id in berth_ids():
		var berth := landing_node(id)
		if berth == null: continue
		var edge := berth.get_node("DockEdge") as Marker3D
		definitions.append({"zone":"zone5", "landing":id, "name":berth.landing_label,
			"world":edge.global_position + Vector3.UP * 0.55, "dynamic_build":true})
	markers.sync_dynamic_markers(definitions)
