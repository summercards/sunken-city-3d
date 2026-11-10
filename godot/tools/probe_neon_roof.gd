extends SceneTree
## 只读：霓虹花园左楼屋顶走域在**楼体局部坐标**下的覆盖图 + 楼梯链贴合。
##   --script res://tools/probe_neon_roof.gd -- [--step=1.0]

var main: Node
var quarter: Node3D
var left: Node3D


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
	var step := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--step="):
			step = float(arg.substr(7))
	quarter = main.get_node_or_null("World/SeaStructures/neon_garden_quarter") as Node3D
	if quarter == null:
		print("[roof] 找不到街区")
		quit(2)
		return
	left = quarter.get_node_or_null("Visual/LeftBuilding") as Node3D
	var roof: Node3D = quarter.get_node_or_null("WalkAreas/WalkLeftRoof")
	if roof == null:
		print("[roof] 找不到 WalkLeftRoof")
		quit(2)
		return
	print("[roof] 屋顶走域 surface_y(世界) %.2f = 局部 %.2f" % [
		roof.surface_y, roof.surface_y - left.global_position.y])
	# 覆盖图：# 有面、. 无面。横轴局部 x，纵轴局部 z。
	var xs := range(-27, -1)
	var zs := range(-13, 15)
	var header := "        "
	for x in xs:
		header += str(absi(x) % 10)
	print("[roof] " + header)
	var covered := 0
	var total := 0
	for z in zs:
		var row := "[roof] z=%4d " % z
		for x in xs:
			var world: Vector3 = left.to_global(Vector3(float(x) + 0.5, 0.0, float(z) + 0.5))
			var hit: Vector3 = roof.surface_point(Vector3(world.x, roof.surface_y, world.z))
			total += 1
			if hit.is_finite():
				row += "#"
				covered += 1
			else:
				row += "."
		print(row)
	print("[roof] 覆盖 %d/%d 格（%.0f%%）" % [covered, total, 100.0 * float(covered) / float(total)])
	# 把每条 rect 摊开：走域局部 → 世界 → LeftBuilding 局部
	print("[roof] rects=%d" % roof.rects.size())
	for r: Rect2 in roof.rects:
		var c: Vector3 = roof.to_global(Vector3(r.get_center().x, 0, r.get_center().y))
		var l: Vector3 = left.to_global(Vector3.ZERO)  # 仅占位，下面用逆变换
		var local_center: Vector3 = left.global_transform.affine_inverse() * c
		print("[roof]   rect %s  世界中心 %.2f,%.2f  楼内 局部 %.2f,%.2f  尺寸 %.2fx%.2f" % [
			str(r), c.x, c.z, local_center.x, local_center.z, r.size.x, r.size.y])
	# 每条 rect 中心竖直向下打射线：走域下面到底有没有实体
	# 每条 rect 中心在楼体**自身三角形**下到底有没有近水平支撑面
	var tris := _collect(left)
	print("[roof] 楼体三角形 %d 个；每条 rect 中心的竖直支撑：" % (tris.size() / 3))
	for r: Rect2 in roof.rects:
		var c: Vector3 = roof.to_global(Vector3(r.get_center().x, 0, r.get_center().y))
		var support := _support_below(tris, c, roof.surface_y)
		if support == -INF:
			print("[roof]   %.2f,%.2f  → 楼体下方 无水平面" % [c.x, c.z])
		else:
			print("[roof]   %.2f,%.2f  → 楼体支撑 y=%.2f  差 %+.2f" % [
				c.x, c.z, support, roof.surface_y - support])
	# 楼梯链顶面
	var tops: Array = []
	for child in left.get_children():
		if not str(child.name).begins_with("stair"):
			continue
		var top := _local_top(child)
		if top != INF:
			tops.append([top, str(child.name)])
	tops.sort_custom(func(a, b): return a[0] < b[0])
	var line := ""
	for entry in tops:
		line += "%s %.2f | " % [str(entry[1]).replace("stair_", ""), float(entry[0])]
	print("[roof] 楼梯顶面（局部）：" + line)
	quit(0)


func _local_top(node: Node3D) -> float:
	var hi := -INF
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf: Transform3D = left.global_transform.affine_inverse() * m.global_transform
		var b: AABB = m.mesh.get_aabb()
		for i in 8:
			var corner := Vector3(
				b.end.x if (i & 1) else b.position.x,
				b.end.y if (i & 2) else b.position.y,
				b.end.z if (i & 4) else b.position.z)
			hi = maxf(hi, (xf * corner).y)
	return hi if hi > -INF else INF


## 收集某节点子树的世界三角形（扁平三元组）。
func _collect(source: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in source.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf: Transform3D = m.global_transform
		for s in m.mesh.get_surface_count():
			var arrays: Array = m.mesh.surface_get_arrays(s)
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			var v: PackedVector3Array = verts
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var n := index.size() if index.size() > 0 else v.size()
			var i := 0
			while i + 2 < n:
				out.append(xf * v[index[i] if index.size() > 0 else i])
				out.append(xf * v[index[i + 1] if index.size() > 0 else i + 1])
				out.append(xf * v[index[i + 2] if index.size() > 0 else i + 2])
				i += 3
	return out


## 某世界 XZ 点下方最近的近水平三角形高度（只看 up_limit 以下的）。
func _support_below(tris: PackedVector3Array, at: Vector3, up_limit: float) -> float:
	var best := -INF
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		var normal := (b - a).cross(c - a)
		if absf(normal.y) / maxf(normal.length(), 0.000001) < 0.9:
			continue
		var y := a.y - (normal.x * (at.x - a.x) + normal.z * (at.z - a.z)) / normal.y
		if y > up_limit + 0.6 or y <= best:
			continue
		var area2 := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		if absf(area2) < 1e-9:
			continue
		var w0 := ((b.x - at.x) * (c.z - at.z) - (c.x - at.x) * (b.z - at.z)) / area2
		var w1 := ((c.x - at.x) * (a.z - at.z) - (a.x - at.x) * (c.z - at.z)) / area2
		var w2 := 1.0 - w0 - w1
		if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
			continue
		best = y
	return best
