extends SceneTree
## 只读探针：某块可行走区域的高程图 + 甲板严格边界。
##
## 输出两类信息：
##   1. 每 0.1 m 一格的「最上层实心面的高度」相对 surface_y 的偏差，
##      用来区分「真甲板」(#)、「低一档的包边/裙板」(-)、「水面/空」(~)；
##   2. 每条矩形四条边的严格边界：从矩形内部往外走，最远到哪一格仍是真甲板。
##
##   godot --path godot --script res://tools/probe_deck_measure.gd -- --area=zone1_home_dock --step=0.1

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
	var step := float(args.get("step", "0.1"))

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	root.get_node("GameState").enter_zone("zone1")
	await settle(24)

	var zone: Node = main._zone_nodes.zone1
	var area: Node = null
	for a in zone.walk_areas:
		if str(a.area_id) == area_id:
			area = a
			break
	if area == null:
		print("[deck] 找不到 ", area_id)
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

	# 全局包围盒（留 0.8 m 余量看边界外）
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for rect: Rect2 in rects:
		lo = Vector2(minf(lo.x, rect.position.x), minf(lo.y, rect.position.y))
		hi = Vector2(maxf(hi.x, rect.end.x), maxf(hi.y, rect.end.y))
	lo -= Vector2(0.8, 0.8)
	hi += Vector2(0.8, 0.8)

	var rows := []
	var z := lo.y
	while z <= hi.y:
		var line := ""
		var x := lo.x
		while x <= hi.x:
			line += _cell(x, z, sy)
			x += step
		rows.append("%6.2f %s" % [z, line])
		z += step

	print("[deck] area=", area_id, " surface_y=", sy, " step=", step,
		" x0=", lo.x, " x1=", hi.x, " z0=", lo.y, " z1=", hi.y)
	for l in rows:
		print("[deck-line] " + str(l))

	# 每条矩形：从内往外扫，找最后一行/列仍是真甲板的位置
	for k in rects.size():
		var rect: Rect2 = rects[k]
		print("[deck-rect] #%d  %.2f..%.2f x  %.2f..%.2f" % [
			k, rect.position.x, rect.end.x, rect.position.y, rect.end.y])
		print("[deck-edge] w=", _scan(rect.position.x, rect.end.x, rect.position.y, rect.end.y, "w", sy),
			" e=", _scan(rect.position.x, rect.end.x, rect.position.y, rect.end.y, "e", sy),
			" n=", _scan(rect.position.x, rect.end.x, rect.position.y, rect.end.y, "n", sy),
			" s=", _scan(rect.position.x, rect.end.x, rect.position.y, rect.end.y, "s", sy))

	for b in _bodies:
		(b as Node).queue_free()
	quit(0)


## 沿某条边扫描：返回「最外侧仍是真甲板」的坐标。
func _scan(x0: float, x1: float, z0: float, z1: float, side: String, sy: float) -> float:
	var best := NAN
	var step := 0.05
	if side == "w" or side == "e":
		var x := x0 if side == "w" else x1
		while x >= x0 - 0.8 and x <= x1 + 0.8:
			var ok := true
			var z := z0 + 0.15
			while z <= z1 - 0.15:
				if not _solid(x, z, sy):
					ok = false
					break
				z += 0.15
			if ok:
				best = x
			x += (-step if side == "w" else step)
		return snappedf(best, 0.01) if not is_nan(best) else NAN
	var zz := z0 if side == "n" else z1
	while zz >= z0 - 0.8 and zz <= z1 + 0.8:
		var ok2 := true
		var xx := x0 + 0.15
		while xx <= x1 - 0.15:
			if not _solid(xx, zz, sy):
				ok2 = false
				break
			xx += 0.15
		if ok2:
			best = zz
		zz += (-step if side == "n" else step)
	return snappedf(best, 0.01) if not is_nan(best) else NAN


func _top(x: float, z: float, sy: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, sy + 1.0, z), Vector3(x, sy - 2.0, z))
	q.collide_with_areas = false
	var h: Dictionary = _space.intersect_ray(q)
	if h.is_empty():
		return NAN
	return (h.position as Vector3).y


## 严格：顶面在 surface_y -0.06 … +0.06，且朝上。
func _solid(x: float, z: float, sy: float) -> bool:
	for ox in [-0.04, 0.0, 0.04]:
		for oz in [-0.04, 0.0, 0.04]:
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x + ox, sy + 1.0, z + oz), Vector3(x + ox, sy - 2.0, z + oz))
			q.collide_with_areas = false
			var h: Dictionary = _space.intersect_ray(q)
			if h.is_empty():
				continue
			if absf((h.position as Vector3).y - sy) <= 0.06 and absf((h.normal as Vector3).y) > 0.55:
				return true
	return false


func _cell(x: float, z: float, sy: float) -> String:
	var t := _top(x, z, sy)
	if is_nan(t):
		return " "
	var d := t - sy
	if absf(d) <= 0.06:
		return "#"
	if d > 0.06 and d <= 0.35:
		return "+"
	if d > 0.35:
		return "^"
	if d >= -0.35:
		return "-"
	return "~"


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
