extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var path := "res://scenes/decorations/underwater/street/buildings/food_truck.tscn"
	var packed: PackedScene = load(path)
	var state := packed.get_state()
	for ni in state.get_node_count():
		var n := state.get_node_name(ni)
		print("[prefab] node ", ni, " ", n, " type=", state.get_node_type(ni))
		for pi in state.get_node_property_count(ni):
			print("   prop ", state.get_node_property_name(ni, pi), " = ", state.get_node_property_value(ni, pi))
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	for v in inst.find_children("*", "MeshInstance3D", true, false):
		print("[prefab] visual ", v.name, " surfaces=", v.mesh.get_surface_count())
		for s in v.mesh.get_surface_count():
			print("   override ", s, " = ", v.get_surface_override_material(s))
	quit(0)
