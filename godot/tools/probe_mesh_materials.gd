extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	for path in ["res://scenes/decorations/underwater/buildings/terraced_tower.tscn",
			"res://scenes/facilities/floating_shop.tscn"]:
		var packed: PackedScene = load(path)
		var node: Node = packed.instantiate()
		root.add_child(node)
		for visual in node.find_children("*", "MeshInstance3D", true, false):
			for s in visual.mesh.get_surface_count():
				var m = visual.mesh.surface_get_material(s)
				print("[mesh-mat] ", path.get_file(), " ", visual.name, " surface=", s,
					" name=", m.resource_name if m else "<none>",
					" path=", m.resource_path if m else "-",
					" override=", str(visual.get_surface_override_material(s).resource_path) if visual.get_surface_override_material(s) else "-")
		node.queue_free()
	await process_frame
	quit(0)
