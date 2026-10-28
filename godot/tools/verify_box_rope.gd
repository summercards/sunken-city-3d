extends SceneTree
## 出货箱是否还穿绳：用缆绳真实顶点与箱体 AABB 求最小间距。
var main: Node

func _init() -> void: call_deferred("run")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 70: await process_frame
	var box: Node3D = main._zone_nodes.zone1.get_node("Objects/ShippingBox")
	var ba := AABB()
	var first := true
	var stack: Array = [box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var a: AABB = mi.global_transform * mi.get_aabb()
			ba = a if first else ba.merge(a)
			first = false
		stack.append_array(n.get_children())
	print("[br] box aabb pos=", ba.position.snapped(Vector3(0.01,0.01,0.01)), " end=", ba.end.snapped(Vector3(0.01,0.01,0.01)))

	var best := INF
	var best_at := Vector3.ZERO
	var stack2: Array = [main._zone_nodes.zone1]
	while not stack2.is_empty():
		var n: Node = stack2.pop_back()
		if n is MultiMeshInstance3D and n.is_visible_in_tree() and str(n.name).to_lower().contains("rope"):
			var mm := n as MultiMeshInstance3D
			if mm.multimesh == null:
				stack2.append_array(n.get_children()); continue
			var arr: Array = mm.multimesh.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in mm.multimesh.instance_count:
				var g: Transform3D = mm.global_transform * mm.multimesh.get_instance_transform(i)
				for v in verts:
					var w: Vector3 = g * v
					# 点到 AABB 的距离
					var dx: float = maxf(maxf(ba.position.x - w.x, w.x - ba.end.x), 0.0)
					var dy: float = maxf(maxf(ba.position.y - w.y, w.y - ba.end.y), 0.0)
					var dz: float = maxf(maxf(ba.position.z - w.z, w.z - ba.end.z), 0.0)
					var d: float = sqrt(dx*dx + dy*dy + dz*dz)
					if d < best:
						best = d
						best_at = w
		stack2.append_array(n.get_children())
	print("[br] 最近绳顶点=", best_at.snapped(Vector3(0.01,0.01,0.01)), " 距离=", snappedf(best, 0.001))
	print("[br] ", "PASS 不穿绳" if best > 0.05 else "FAIL 仍穿绳")
	main.queue_free()
	await process_frame
	print("[br] complete")
	quit(0)
