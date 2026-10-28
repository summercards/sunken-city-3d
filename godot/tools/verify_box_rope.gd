extends SceneTree
## 出货箱与码头缆绳的空间关系回归。
##
## 这条断言盯着一个跨文件隐形契约：箱子的落点在 `zone1_home_harbor.tscn`，
## 缆绳在 `solar_cabin` 组件的 GLB 里。两者改任意一边都可能让箱子重新穿绳，
## 而画面上"线从箱子里穿过去"只有真渲染才看得见 —— 光靠注释没人记得。
##
## 判据：缆绳真实顶点到箱体世界 AABB 的最小距离 > MIN_GAP。
## 运行：python scripts/run_verification.py dock-rope-clearance
const MIN_GAP := 0.05
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func world_aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			var mi := n as MeshInstance3D
			var a: AABB = mi.global_transform * mi.get_aabb()
			box = a if first else box.merge(a)
			first = false
		stack.append_array(n.get_children())
	return box

func nearest_rope_gap(box: AABB, root_node: Node) -> Dictionary:
	var best := INF
	var best_at := Vector3.ZERO
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MultiMeshInstance3D and n.is_visible_in_tree() and str(n.name).to_lower().contains("rope"):
			var mm := n as MultiMeshInstance3D
			if mm.multimesh != null:
				var verts: PackedVector3Array = mm.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for i in mm.multimesh.instance_count:
					var g: Transform3D = mm.global_transform * mm.multimesh.get_instance_transform(i)
					for v in verts:
						var w: Vector3 = g * v
						var dx: float = maxf(maxf(box.position.x - w.x, w.x - box.end.x), 0.0)
						var dy: float = maxf(maxf(box.position.y - w.y, w.y - box.end.y), 0.0)
						var dz: float = maxf(maxf(box.position.z - w.z, w.z - box.end.z), 0.0)
						var d: float = sqrt(dx * dx + dy * dy + dz * dz)
						if d < best:
							best = d
							best_at = w
		stack.append_array(n.get_children())
	return {"gap": best, "at": best_at}

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 70: await process_frame
	var zone: Node3D = main._zone_nodes.zone1
	var box: Node3D = zone.get_node("Objects/ShippingBox")
	check(box != null, "码头有出货箱")
	if box != null:
		var ba := world_aabb(box)
		print("[dock-rope] 箱体 AABB ", ba.position.snapped(Vector3(0.01, 0.01, 0.01)),
			" .. ", ba.end.snapped(Vector3(0.01, 0.01, 0.01)))
		var near: Dictionary = nearest_rope_gap(ba, zone)
		print("[dock-rope] 最近缆绳顶点 ", (near.at as Vector3).snapped(Vector3(0.01, 0.01, 0.01)),
			" 间距 ", snappedf(float(near.gap), 0.001))
		check(float(near.gap) > MIN_GAP, "出货箱不穿缆绳")
		# 箱子不能悬在甲板外：可行走矩形并集必须包含箱体中心的地面投影。
		var center := Vector3(ba.get_center().x, 0.0, ba.get_center().z)
		var on_deck := false
		for area in zone.get_node("WalkAreas").get_children():
			if area.get("rects") == null:
				continue
			for r in area.rects:
				if (r as Rect2).has_point(Vector2(center.x, center.z)):
					on_deck = true
		check(on_deck, "出货箱落在可行走甲板内")
	print("[dock-rope] failures=", failures)
	main.queue_free()
	await process_frame
	print("[dock-rope] complete" if failures == 0 else "[dock-rope] FAILED")
	quit(0 if failures == 0 else 1)
