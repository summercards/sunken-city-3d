extends SceneTree
func _init() -> void:
	call_deferred("run")
func walk(n: Node, depth: int) -> void:
	print("[tree] ", "  ".repeat(depth), n.name, " (", n.get_class(), ")")
	if n is MeshInstance3D:
		for s in n.mesh.get_surface_count():
			print("[tree]    surf", s, " override=", n.get_surface_override_material(s))
	for c in n.get_children():
		walk(c, depth + 1)
func run() -> void:
	for p in ["res://scenes/decorations/underwater/street/buildings/food_truck.tscn",
			"res://scenes/decorations/underwater/buildings/terraced_tower.tscn"]:
		print("[tree] ==== ", p)
		var inst: Node = (load(p) as PackedScene).instantiate()
		root.add_child(inst)
		walk(inst, 0)
		inst.queue_free()
	quit(0)
