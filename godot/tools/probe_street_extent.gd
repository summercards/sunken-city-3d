extends SceneTree
func _init() -> void:
	call_deferred("run")
func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "VisualInstance3D", true, false):
		if not (mesh is MeshInstance3D or mesh is MultiMeshInstance3D):
			continue
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		result = part if first else result.merge(part)
		first = false
	return result
func tris(node: Node) -> int:
	var n := 0
	for v in node.find_children("*", "MeshInstance3D", true, false):
		for s in v.mesh.get_surface_count():
			var a: Array = v.mesh.surface_get_arrays(s)
			n += (a[Mesh.ARRAY_INDEX].size() / 3) if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size() / 3
	return n
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame
	print("[street-probe] water_y=", main.water_node.global_position.y)
	var street: Node3D = main.get_node_or_null("World/UnderwaterStreet")
	print("[street-probe] street node=", street, " children=", street.get_child_count() if street else -1)
	if street == null:
		quit(1)
		return
	for c in street.get_children():
		var b: AABB = bounds(c)
		print("[street-probe] ", c.name, " tris=", tris(c), " min=", b.position.snappedf(0.01), " max=", b.end.snappedf(0.01))
		for v in c.find_children("*", "MeshInstance3D", true, false):
			for s in v.mesh.get_surface_count():
				var m = v.mesh.surface_get_material(s)
				var o = v.get_surface_override_material(s)
				print("   surf", s, " mesh=", m.resource_name if m else "-", " override=", o.resource_name if o else "-")
	print("[street-probe] done")
	main.queue_free()
	await process_frame
	quit(0)
