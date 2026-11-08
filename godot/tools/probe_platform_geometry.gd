extends SceneTree
## 只读：量出 zone1 里「绞盘打捞台 / 野捕渔场 / 电线杆 / 行走面」的世界包围盒。
## 用来确定旋转轴心、以及旋转后电线杆需要多少反向补偿。
##
##   godot --headless --path godot --script res://tools/probe_platform_geometry.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: Variant = load("res://scenes/zones/zone1_home_harbor.tscn")
	if packed == null:
		print("[platform] FAIL 场景加载失败")
		quit(1)
		return
	var zone: Node3D = (packed as PackedScene).instantiate()
	root.add_child(zone)
	await process_frame
	await process_frame

	_report("绞盘打捞台", zone.get_node_or_null("Models/绞盘打捞台"))
	_report("WildFishery", zone.get_node_or_null("Models/WildFishery"))
	var station := zone.get_node_or_null("Models/绞盘打捞台/salvage_station")
	if station != null:
		var pole := station.get_node_or_null("PoleAndFlowers")
		_report("PoleAndFlowers", pole)
		if pole != null:
			print("[platform] PoleAndFlowers world_pos=%s" % str(pole.global_position))
		for child in station.get_children():
			var box := _subtree_box(child)
			if box.has_volume():
				print("[platform] 子件 %s box=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)" % [
					child.name, box.position.x, box.position.y, box.position.z,
					box.size.x, box.size.y, box.size.z])

	var holder := zone.get_node_or_null("WalkAreas")
	if holder != null:
		for area in holder.get_children():
			if not ("rects" in area):
				continue
			print("[platform] WalkArea %s surface_y=%.3f" % [str(area.area_id), float(area.surface_y)])
			for r: Rect2 in area.rects:
				var a: Vector3 = area.to_global(Vector3(r.position.x, 0, r.position.y))
				var b: Vector3 = area.to_global(Vector3(r.end.x, 0, r.end.y))
				print("     rect world x %.2f..%.2f  z %.2f..%.2f" % [
					minf(a.x, b.x), maxf(a.x, b.x), minf(a.z, b.z), maxf(a.z, b.z)])
			for child in area.get_children():
				if child.has_method("stand_position"):
					print("     landing %s world=%s" % [child.name, str(child.global_position)])
	quit(0)


func _report(label: String, node: Node) -> void:
	if node == null:
		print("[platform] %s 找不到" % label)
		return
	var box := _subtree_box(node)
	print("[platform] %s 世界包围盒 pos=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f) center_xz=(%.3f,%.3f)" % [
		label, box.position.x, box.position.y, box.position.z,
		box.size.x, box.size.y, box.size.z,
		box.position.x + box.size.x * 0.5, box.position.z + box.size.z * 0.5])


func _subtree_box(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var box: AABB = mi.global_transform * mi.mesh.get_aabb()
				result = box if first else result.merge(box)
				first = false
		elif n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.is_visible_in_tree():
				var box2: AABB = mmi.global_transform * mmi.multimesh.get_aabb()
				result = box2 if first else result.merge(box2)
				first = false
		stack.append_array(n.get_children())
	return result
