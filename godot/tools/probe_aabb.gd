extends SceneTree
## 打印某个节点的世界包围盒（按直接子节点分组），给「往墙上挂东西」定坐标用。
##
## 用法： --script res://tools/probe_aabb.gd -- --path=World/SeaStructures/neon_garden_quarter/Visual

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	for i in 24:
		await process_frame
	var path := "World/SeaStructures/neon_garden_quarter/Visual"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path="):
			path = arg.substr(7)
	var node: Node3D = main.get_node_or_null(path) as Node3D
	if node == null:
		print("[aabb] 找不到 ", path)
		quit(2)
		return
	print("[aabb] ", path, " global=", node.global_transform.origin)
	for child in node.get_children():
		var box := AABB()
		var first := true
		for mi in (child as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var b: AABB = m.global_transform * m.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			print("[aabb] %-16s （无网格）" % child.name)
			continue
		print("[aabb] %-16s world x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f" % [
			child.name, box.position.x, box.end.x, box.position.y, box.end.y, box.position.z, box.end.z])
		# 同一盒子的父节点局部坐标：往旋转过的建筑上挂东西时要这组数
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in 8:
			var corner := Vector3(
				box.position.x if i & 1 else box.end.x,
				box.position.y if i & 2 else box.end.y,
				box.position.z if i & 4 else box.end.z)
			var lp: Vector3 = node.to_local(corner)
			lo = Vector3(minf(lo.x, lp.x), minf(lo.y, lp.y), minf(lo.z, lp.z))
			hi = Vector3(maxf(hi.x, lp.x), maxf(hi.y, lp.y), maxf(hi.z, lp.z))
		print("[aabb] %-16s local x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f" % [
			"(same)", lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
	quit(0)
