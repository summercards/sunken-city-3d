extends SceneTree
## 取证 + 量化：某块可行走区域里，哪些格子下面真的是甲板。
##
## 本工程走路不走物理碰撞（场景里没有 StaticBody3D），站得住是因为
## WalkArea.surface_y 直接把脚贴到那个高度。所以「能走进水里」= 矩形越过了甲板。
## 这里给区块可见网格临时建三角碰撞（只在本进程内存里），逐格抖动采样，
## 抗木板缝隙造成的单点误判。
##
##   godot --path godot --script res://tools/probe_deck_edges.gd -- --area=zone1_home_dock
##   godot --path godot --script res://tools/probe_deck_edges.gd -- --area=zone1_salvage

var main
var _space: PhysicsDirectSpaceState3D
var _bodies: Array = []


func _init() -> void:
	_run.call_deferred()


func settle(n := 6) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var area_id := str(args.get("area", "zone1_home_dock"))
	var step := float(args.get("step", "0.25"))

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	root.get_node("GameState").enter_zone("zone1")
	await settle(24)

	var zone: Node = main.get_node("World/Zones/Zone1HomeHarbor")
	var area: Node = zone.get_node("WalkAreas/" + ("Walk_" + area_id))
	if area == null:
		print("[decgrid] 找不到 ", area_id)
		quit(1)
		return
	var sy := float(area.surface_y)
	_build(zone)
	await physics_frame
	await physics_frame
	_space = root.world_3d.direct_space_state

	var rects: Array = []
	for r in area.rects:
		var rect: Rect2 = r
		rects.append(rect)

	var lines := []
	var holes := []
	var cols := 0
	for rect: Rect2 in rects:
		var nx := int(round(rect.size.x / step))
		var nz := int(round(rect.size.y / step))
		cols = maxi(cols, nx)
		lines.append("--- rect x %.2f..%.2f  z %.2f..%.2f  (%dx%d) ---" % [
			rect.position.x, rect.end.x, rect.position.y, rect.end.y, nx, nz])
		for j in nz:
			var line := ""
			for i in nx:
				var x := rect.position.x + (float(i) + 0.5) * step
				var z := rect.position.y + (float(j) + 0.5) * step
				var n := 0
				for oy in [-0.08, 0.0, 0.08]:
					for oz in [-0.08, 0.0, 0.08]:
						if _deck(Vector3(x + oy, 0, z + oz), sy):
							n += 1
				if n >= 5:
					line += "#"
				else:
					line += "~"
					holes.append([snappedf(x, 0.01), snappedf(z, 0.01)])
			lines.append("%6.2f %s" % [rect.position.y + (float(j) + 0.5) * step, line])

	print("[decgrid] " + JSON.stringify({
		"area": area_id, "surface_y": sy, "step": step,
		"rects": _rects(rects), "lines": lines, "holes": holes,
	}))
	for l in lines:
		print("[decgrid-line] " + str(l))
	for b in _bodies:
		(b as Node).queue_free()
	quit(0)


func _rects(rects: Array) -> Array:
	var out := []
	for r: Rect2 in rects:
		out.append([r.position.x, r.position.y, r.end.x, r.end.y])
	return out


func _deck(p: Vector3, sy: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, sy + 0.9, p.z), Vector3(p.x, sy - 0.55, p.z))
	q.collide_with_areas = false
	var h: Dictionary = _space.intersect_ray(q)
	if h.is_empty():
		return false
	var y := (h.position as Vector3).y
	return absf(y - sy) <= 0.30 and absf((h.normal as Vector3).y) > 0.55


func _build(node: Node) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			if mmi.is_visible_in_tree() and mmi.multimesh != null:
				var shape: Shape3D = mmi.multimesh.mesh.create_trimesh_shape()
				if shape != null:
					for i in mmi.multimesh.instance_count:
						_attach(shape, mmi.global_transform * mmi.multimesh.get_instance_transform(i))
		elif child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.is_visible_in_tree() and mi.mesh != null:
				var shape2: Shape3D = mi.mesh.create_trimesh_shape()
				if shape2 != null:
					_attach(shape2, mi.global_transform)
		_build(child)


func _attach(shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.global_transform = xf
	root.add_child(body)
	_bodies.append(body)
