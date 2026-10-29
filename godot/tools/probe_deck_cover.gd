extends SceneTree
## 只读探针：甲板覆盖图（球检测，抗木板缝隙）+ 严格外边界。
##
## 为什么用球而不是单条射线：栈桥是木条拼的，板缝只有几厘米，
## 单点射线掉进缝里就会把整排判成"没有甲板"，量出来的边界会抖。
## 这里在每格放一个半径 0.10 m 的球，只看「球心附近有没有 surface_y 附近的面」。
##
##   godot --path godot --script res://tools/probe_deck_cover.gd -- --area=zone1_home_dock --step=0.1

var main
var _space: PhysicsDirectSpaceState3D
var _bodies: Array = []
var _shape := SphereShape3D.new()


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
	var x0 := float(args.get("x0", "nan"))
	var x1 := float(args.get("x1", "nan"))
	var z0 := float(args.get("z0", "nan"))
	var z1 := float(args.get("z1", "nan"))

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
	var sy := float(area.surface_y)
	_build(zone)
	await physics_frame
	await physics_frame
	_space = root.world_3d.direct_space_state
	_shape.radius = 0.10

	var rects: Array = []
	for r in area.rects:
		rects.append(r as Rect2)
	if is_nan(x0):
		x0 = INF
		x1 = -INF
		z0 = INF
		z1 = -INF
		for rect: Rect2 in rects:
			x0 = minf(x0, rect.position.x)
			x1 = maxf(x1, rect.end.x)
			z0 = minf(z0, rect.position.y)
			z1 = maxf(z1, rect.end.y)
		x0 -= 0.6
		x1 += 0.6
		z0 -= 0.6
		z1 += 0.6

	# 甲板覆盖：'#' 球检测命中，' ' 没命中；同时标出是否落在行走矩形内（大写 = 矩形内）
	var rows := []
	var z := z0
	while z <= z1 + 0.001:
		var line := ""
		var x := x0
		while x <= x1 + 0.001:
			var deck := _deck(x, z, sy)
			var in_walk := _in_walk(rects, x, z)
			line += ("#" if deck else ("." if in_walk else " "))
			x += step
		rows.append("%6.2f %s" % [z, line])
		z += step

	var ruler := "       "
	var tick := "       "
	var x := x0
	while x <= x1 + 0.001:
		var whole := absf(x - roundf(x)) < 0.001
		ruler += ("%d" % int(roundf(x)) % 10) if whole else " "
		tick += ("|" if whole else ".")
		x += step
	print("[cover] area=", area_id, " surface_y=", sy, " step=", step,
		" x0=", x0, " x1=", x1, " z0=", z0, " z1=", z1)
	print("[cover-l] " + ruler)
	print("[cover-l] " + tick)
	for l in rows:
		print("[cover-l] " + str(l))

	# 严格边界：沿每条矩形边，从外往里找第一处「连续 1 m 有甲板」的位置
	for k in rects.size():
		var rect: Rect2 = rects[k]
		print("[cover-rect] #%d x %.2f..%.2f z %.2f..%.2f | deck_w=%.2f deck_e=%.2f deck_n=%.2f deck_s=%.2f" % [
			k, rect.position.x, rect.end.x, rect.position.y, rect.end.y,
			_edge(rect, "w", sy), _edge(rect, "e", sy), _edge(rect, "n", sy), _edge(rect, "s", sy)])

	for b in _bodies:
		(b as Node).queue_free()
	quit(0)


func _in_walk(rects: Array, x: float, z: float) -> bool:
	for rect: Rect2 in rects:
		if rect.has_point(Vector2(x, z)):
			return true
	return false


## 沿边扫：返回最外侧「含该点的 1 m 线段内 ≥90% 有甲板」的坐标。
func _edge(rect: Rect2, side: String, sy: float) -> float:
	var best := NAN
	if side == "w" or side == "e":
		var z_lo := rect.position.y + 0.2
		var z_hi := rect.end.y - 0.2
		if z_hi - z_lo < 1.0:
			return NAN
		var x := rect.position.x if side == "w" else rect.end.x
		for i in 61:
			var probe := x + (-0.6 + float(i) * 0.02 if side == "w" else -0.6 + float(i) * 0.02)
			if _line_cover(probe, z_lo, z_hi, true, sy) >= 0.9:
				best = probe
				break
		return snappedf(best, 0.01) if not is_nan(best) else NAN
	var x_lo := rect.position.x + 0.2
	var x_hi := rect.end.x - 0.2
	var zz := rect.position.y if side == "n" else rect.end.y
	for i in 61:
		var probe2 := zz + (-0.6 + float(i) * 0.02 if side == "n" else -0.6 + float(i) * 0.02)
		if _line_cover(probe2, x_lo, x_hi, false, sy) >= 0.9:
			best = probe2
			break
	return snappedf(best, 0.01) if not is_nan(best) else NAN


func _line_cover(v: float, lo: float, hi: float, along_z: bool, sy: float) -> float:
	var hit := 0
	var total := 0
	var t := lo
	while t <= hi:
		total += 1
		if _deck(v if along_z else t, t if along_z else v, sy):
			hit += 1
		t += 0.1
	return float(hit) / float(maxi(1, total))


func _deck(x: float, z: float, sy: float) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.transform = Transform3D(Basis(), Vector3(x, sy + 0.02, z))
	params.collide_with_areas = false
	return not _space.intersect_shape(params, 1).is_empty()


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
