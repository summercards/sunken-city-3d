extends SceneTree
## Read-only probe: measure the imported rooftop_ranch components as Godot sees them.
## Reports each component's AABB in ranch-local space plus material bindings, so the
## water-line / walk-surface numbers come from the real geometry instead of guesses.

func _init() -> void:
	call_deferred("run")

func _fmt(box: AABB) -> Array:
	return [snappedf(box.position.x, 0.001), snappedf(box.position.y, 0.001), snappedf(box.position.z, 0.001),
		snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)]

func _local_aabb(node: Node, ranch: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var inv: Transform3D = ranch.global_transform.affine_inverse()
	for mesh in node.find_children("*", "VisualInstance3D", true, false):
		if not (mesh is MeshInstance3D):
			continue
		var mi: MeshInstance3D = mesh
		if mi.mesh == null:
			continue
		var part: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		result = part if first else result.merge(part)
		first = false
	return result

func run() -> void:
	var packed: PackedScene = load("res://scenes/facilities/rooftop_ranch.tscn")
	if packed == null:
		print("PROBE_FAIL no scene")
		quit(1)
		return
	var ranch: Node3D = packed.instantiate()
	root.add_child(ranch)
	await process_frame
	await process_frame
	var report := {}
	var materials := {}
	var models: Node = ranch.get_node_or_null("Models")
	if models == null:
		print("PROBE_FAIL no Models")
		quit(1)
		return
	for child in models.get_children():
		var box := _local_aabb(child, ranch)
		var key := str(child.get_meta("asset_id", child.name))
		report[child.name] = {"asset_id": key, "visible": child.visible, "aabb": _fmt(box)}
		for mesh in child.find_children("*", "VisualInstance3D", true, false):
			if not (mesh is MeshInstance3D):
				continue
			var mi: MeshInstance3D = mesh
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				var path := ""
				if m != null:
					path = m.resource_path if m.resource_path != "" else str(m.get_instance_id())
				materials[path] = int(materials.get(path, 0)) + 1
	print("PROBE_ROOT transform ", str(ranch.global_transform))
	print("PROBE_MATERIALS ", JSON.stringify(materials))
	print("PROBE_AABB ", JSON.stringify(report))
	# Focused readout for the water-line decision.
	for key in ["ORF2_实例_stair_landing.023", "ORF2_实例_stair_landing.022",
			"ORF2_实例_stair_landing.021", "ORF2_实例_stair_landing_open",
			"ORF2_实例_roof_entry", "ORF2_实例_roof", "ORF2_实例_turf_core",
			"ORF2_实例_shell", "ORF3_下挂断裂消防梯"]:
		if report.has(key):
			print("KEY ", key, " ", JSON.stringify(report[key]["aabb"]))
	quit(0)
