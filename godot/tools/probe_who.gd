extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 40: await process_frame
	# 统计场景里所有 ShaderMaterial 用的着色器
	var counts := {}
	_walk(main, counts)
	for k in counts:
		print("[who] ", k, " x", counts[k])
	quit(0)
func _walk(n: Node, c: Dictionary) -> void:
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		var m = gi.material_override
		if m == null and gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				m = mi.mesh.surface_get_material(0)
		if m is ShaderMaterial:
			var p: String = (m as ShaderMaterial).shader.resource_path
			c[p] = c.get(p, 0) + 1
	for ch in n.get_children():
		_walk(ch, c)
