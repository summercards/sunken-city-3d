extends SceneTree
## 只读：把某个模块里的「楼梯段 / 平台」按高度排出来，给派生走域与梯子交互定坐标。
##
##   --script res://tools/probe_stair_chain.gd -- \
##       --path=World/SeaStructures/neon_garden_quarter/Visual/LeftBuilding --prefix=stair

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
	var path := "World/SeaStructures/neon_garden_quarter/Visual/LeftBuilding"
	var prefix := "stair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path="):
			path = arg.substr(7)
		elif arg.begins_with("--prefix="):
			prefix = arg.substr(9).to_lower()
	var node: Node3D = main.get_node_or_null(path) as Node3D
	if node == null:
		print("[stair] 找不到 ", path)
		quit(2)
		return
	var rows: Array = []
	for child in node.get_children():
		if not str(child.name).to_lower().begins_with(prefix):
			continue
		var box: Variant = _box_of(child, node)
		if box == null:
			continue
		var bb: AABB = box
		rows.append([bb.position.y, str(child.name), bb])
	rows.sort_custom(func(a, c): return a[0] < c[0])
	print("[stair] %s prefix='%s' count=%d  （坐标为 %s 局部，y 从楼体原点算）" % [
		path, prefix, rows.size(), path.get_file()])
	var prev_top := -999.0
	for r in rows:
		var b: AABB = r[2]
		var mid := b.get_center()
		var world: Vector3 = node.to_global(Vector3(mid.x, b.end.y, mid.z))
		print("[stair] %-18s y %7.2f..%7.2f  x %7.2f..%7.2f  z %7.2f..%7.2f  size %.2f x %.2f x %.2f  rise %+.2f  世界顶点 %.2f,%.2f,%.2f" % [
			str(r[1]), b.position.y, b.end.y,
			b.position.x, b.end.x, b.position.z, b.end.z,
			b.size.x, b.size.y, b.size.z, b.end.y - prev_top,
			world.x, world.y, world.z])
		prev_top = b.end.y
	quit(0)


## 包成 `frame` 节点的局部坐标 —— 楼体在主场景里转了 72°，
## 世界 AABB 是斜放盒子的外接盒，会把 3.2 米的楼梯量成 4.8 米。
func _box_of(node: Node, frame: Node3D) -> Variant:
	var inverse := frame.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var found := false
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf: Transform3D = inverse * m.global_transform
		var b: AABB = m.mesh.get_aabb()
		for i in 8:
			var corner := Vector3(
				b.end.x if (i & 1) else b.position.x,
				b.end.y if (i & 2) else b.position.y,
				b.end.z if (i & 4) else b.position.z)
			var p: Vector3 = xf * corner
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
			found = true
	if not found:
		return null
	return AABB(lo, hi - lo)
