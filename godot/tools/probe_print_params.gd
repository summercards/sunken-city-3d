extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 30: await process_frame
	var mat: ShaderMaterial = main.water_node.current_material()
	print("[p] mat path=", mat.resource_path)
	print("[p] shader=", mat.shader.resource_path)
	for k in ["caustics_enabled","caustics_strength","caustics_scale","caustics_detail","caustics_depth_near","caustics_depth_far","caustics_color"]:
		print("[p] ", k, " = ", mat.get_shader_parameter(k))
	# 着色器里有没有这些 uniform
	var names := []
	for u in mat.shader.get_shader_uniform_list():
		names.append(u.name)
	print("[p] uniform count=", names.size())
	for k in ["caustics_enabled","caustics_strength","caustics_color"]:
		print("[p] exists ", k, " = ", names.has(k))
	quit(0)
