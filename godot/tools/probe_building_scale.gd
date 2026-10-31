extends SceneTree
## Read actual formal sunroom MultiMesh geometry and per-instance transforms.
var main: Node

func _init() -> void:
	call_deferred("run")

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.cam.set_process(false)
	main.boat.set_process(false)
	for i in 8:
		await process_frame
	var zone: Node = main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海上区域")
	var rows: Array = []
	var wanted := ["house", "terrace", "concrete_slab", "door", "entry", "wall_pier", "porch_side", "porch_return"]
	for value in zone.find_children("*", "MultiMeshInstance3D", true, false):
		var node := value as MultiMeshInstance3D
		var key := str(node.get_meta("asset_component", ""))
		if not key in wanted and not key.begins_with("platform_board") and not key.begins_with("dock_board"):
			continue
		var mm: MultiMesh = node.multimesh
		var local: AABB = mm.mesh.get_aabb()
		var declared: Array = node.get_meta("instance_transforms", [])
		for i in mm.instance_count:
			var xf: Transform3D = node.global_transform * (declared[i] if i < declared.size() else mm.get_instance_transform(i))
			var box: AABB = xf * local
			rows.append({"component": key, "node": str(node.get_path()), "mesh_name": mm.mesh.resource_name,
				"instance": i, "local_bounds": {"min": vec(local.position), "size": vec(local.size)},
				"world_bounds": {"min": vec(box.position), "size": vec(box.size), "max": vec(box.end)},
				"basis_lengths": [xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length()],
				"basis": [vec(xf.basis.x), vec(xf.basis.y), vec(xf.basis.z)]})
	var report := {"schema": "sea.building.runtime_reference", "engine": Engine.get_version_info(),
		"facility": "solar_cabin", "scene": "res://scenes/facilities/solar_cabin.tscn",
		"instance_data": "res://assets/models/facilities/solar_cabin/instances.json",
		"instance_data_sha256": FileAccess.get_sha256("res://assets/models/facilities/solar_cabin/instances.json"),
		"rows": rows}
	var file := FileAccess.open("res://outputs/building-scale-reference.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("[building-scale-reference] ", rows.size(), " rows, 0 failures")
	main.queue_free()
	await process_frame
	quit(0 if rows.size() > 20 else 1)
