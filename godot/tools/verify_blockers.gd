extends SceneTree
## 阻挡一致性校验：让「模型在哪」和「阻挡在哪」之间有一条会失败的断言。
##
## 检查两件事：
##   1. 空阻挡 —— 派生出的每条阻挡矩形内部必须真的跨水有实体；
##   2. 漏阻挡 —— 可见组件里跨水有实体的地方必须被阻挡覆盖。
## 任何一项超阈值就以 1 退出，接进 run_verification.py。
##
## 必须用真实渲染跑（不加 --headless）：headless 的 dummy renderer 读不出
## MultiMesh 实例变换，木屋这类实例化组件会全部落在原点，结果无效。

const ZONES := [
	["zone1", "zones/zone1_home_harbor.tscn"], ["zone2", "zones/zone2_yokohama_station.tscn"],
	["zone3", "zones/zone3_arc_farm.tscn"], ["zone4", "zones/zone4_far_shore.tscn"],
	["zone5", "zones/zone5_aqua_platform.tscn"],
]
const WATER := 1.12
const HULL := 1.6
const SAMPLE := 0.5
## 支撑率低于这个值，这条矩形就是「水面上看不见的墙」。
const MIN_SUPPORT := 0.35
## 有实体却没被阻挡盖住的比例，超过就是「船能穿模型」。
const MAX_MISS := 0.15
## 漏阻挡检测只查 AABB 内侧这么宽的区域，避开轮廓锯齿。
const EDGE_MARGIN := 0.5
## 小于这个面积的阻挡不参与「空阻挡」判定（栅格擦角）。
const MIN_CHECK_AREA := 1.0

var _space: PhysicsDirectSpaceState3D
var _bodies: Array = []
var _rects: Array[Rect2] = []
var _fails := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var zones: Array = []
	for pair in ZONES:
		var packed: Variant = load("res://scenes/%s" % pair[1])
		if packed == null:
			print("FAIL %s 场景加载失败" % pair[0])
			_fails += 1
			continue
		var zone: Node3D = (packed as PackedScene).instantiate()
		root.add_child(zone)
		zones.append([pair[0], zone])
	await process_frame
	await physics_frame
	_space = root.world_3d.direct_space_state

	for entry in zones:
		_scan_collision(entry[1])
	await physics_frame
	await physics_frame

	for entry in zones:
		_check_zone(entry[0], entry[1])

	for b in _bodies:
		(b as Node).queue_free()
	for entry in zones:
		(entry[1] as Node).queue_free()
	print("[blockers-check] %s failures=%d rects=%d" % [
		"OK" if _fails == 0 else "FAILED", _fails, _rects.size()])
	quit(0 if _fails == 0 else 1)


func _scan_collision(node: Node) -> void:
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.is_visible_in_tree() and mmi.multimesh != null and mmi.multimesh.mesh != null:
			var shape: Shape3D = mmi.multimesh.mesh.create_trimesh_shape()
			if shape != null:
				for i in mmi.multimesh.instance_count:
					_attach(shape, mmi.global_transform * mmi.multimesh.get_instance_transform(i))
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			var shape: Shape3D = mi.mesh.create_trimesh_shape()
			if shape != null:
				_attach(shape, mi.global_transform)
	for child in node.get_children():
		_scan_collision(child)


func _attach(shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.global_transform = xf
	root.add_child(body)
	_bodies.append(body)


func _check_zone(zone_id: String, zone: Node) -> void:
	if not zone.has_method("rebuild_blockers"):
		print("FAIL %s 缺少 rebuild_blockers" % zone_id)
		_fails += 1
		return
	zone.rebuild_blockers(WATER, HULL)
	var rects: Array = zone.water_block_rects
	_rects.append_array(rects)
	if rects.is_empty():
		print("FAIL %s 没有任何阻挡（组件 BlockerSet 没派生出来）" % zone_id)
		_fails += 1
		return

	var empty := []
	for r in rects:
		var rect: Rect2 = r
		# 只盯会影响体验的成片阻挡；0.4m 的擦角边缘不计入空阻挡，
		# 那是栅格量化的固有误差，不是「水面上看不见的墙」。
		if rect.get_area() < MIN_CHECK_AREA:
			continue
		var support := _support(rect)
		if support < MIN_SUPPORT:
			empty.append({"rect": rect, "support": support})
	if not empty.is_empty():
		_fails += 1
		print("FAIL %s 空阻挡 %d/%d 条" % [zone_id, empty.size(), rects.size()])
		for e in empty.slice(0, 5):
			var rect: Rect2 = e["rect"]
			print("     矩形 x=%.1f..%.1f z=%.1f..%.1f 支撑=%.2f" % [
				rect.position.x, rect.end.x, rect.position.y, rect.end.y, e["support"]])

	var miss := _miss_ratio(zone, rects)
	if miss > MAX_MISS:
		_fails += 1
		print("FAIL %s 漏阻挡 %.0f%%（实体在阻挡外）样本 %s" % [zone_id, miss * 100.0, str(_miss_samples.slice(0, 6))])
	print("%s %s rects=%d 空=%d 漏=%.1f%%" % [
		"OK  " if empty.is_empty() and miss <= MAX_MISS else "FAIL", zone_id,
		rects.size(), empty.size(), miss * 100.0])


func _support(rect: Rect2) -> float:
	var hit := 0
	var total := 0
	var x := rect.position.x
	while x <= rect.end.x:
		var z := rect.position.y
		while z <= rect.end.y:
			total += 1
			if _has_solid(x, z):
				hit += 1
			z += SAMPLE
		x += SAMPLE
	return float(hit) / float(maxi(1, total))


## 这个 XZ 点在水线到船高这一段里有没有实体。
##
## 单靠一条向下射线会把「空心建筑的内部」误判成空阻挡 —— 盒子顶面在船高之上，
## 射线只打到屋顶，可侧面明明会挡船。所以补三条：向下、向上、四向水平。
func _has_solid(x: float, z: float) -> bool:
	var down := _ray(x, z, WATER + HULL - 0.02, WATER)
	if not down.is_empty() and (down.position as Vector3).y > WATER + 0.02:
		return true
	var up := _ray(x, z, WATER + 0.02, WATER + HULL)
	if not up.is_empty():
		return true
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var from := Vector3(x, WATER + 0.7, z)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.25)
		if not _space.intersect_ray(q).is_empty():
			return true
	return false


## 可见结构实例的 AABB 内，跨水有实体但不在任何阻挡矩形里的比例。
var _miss_samples: Array = []


func _miss_ratio(zone: Node, rects: Array) -> float:
	var miss := 0
	var total := 0
	_miss_samples.clear()
	for box in _structure_boxes(zone):
		var b: AABB = box
		if b.end.y < WATER + 0.15 or b.position.y > WATER + HULL:
			continue
		# 只查 AABB 内部：贴边 0.5m 是轮廓锯齿与 AABB 外扩噪声，
		# 那里的「漏」是 0.4m 栅格精度，不是船能开进去的洞。
		var x := b.position.x + EDGE_MARGIN
		while x <= b.end.x - EDGE_MARGIN:
			var z := b.position.z + EDGE_MARGIN
			while z <= b.end.z - EDGE_MARGIN:
				var h := _ray(x, z, WATER + HULL + 0.6, WATER)
				if not h.is_empty():
					var y := (h.position as Vector3).y
					if y > WATER + 0.15:
						total += 1
						if not _covered(rects, x, z):
							miss += 1
							if _miss_samples.size() < 20:
								_miss_samples.append(Vector2(snappedf(x, 0.1), snappedf(z, 0.1)))
				z += SAMPLE
			x += SAMPLE
	return float(miss) / float(maxi(1, total))


func _covered(rects: Array, x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for r in rects:
		# 1mm 容差：采样点常常正好落在 0.4m 栅格边界上，浮点误差会让
		# 「刚好在线上」的点被判成不在矩形内，制造假的漏阻挡。
		if (r as Rect2).grow(0.001).has_point(p):
			return true
	return false


func _structure_boxes(zone: Node) -> Array:
	var out: Array = []
	var models: Node = zone.get_node_or_null("Models")
	if models == null:
		return out
	for child in models.get_children():
		if not (child is Node3D) or not (child as Node3D).is_visible_in_tree():
			continue
		var stack: Array = [child]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MultiMeshInstance3D:
				var mmi := n as MultiMeshInstance3D
				if mmi.multimesh != null and mmi.multimesh.mesh != null:
					var local := mmi.multimesh.mesh.get_aabb()
					for i in mmi.multimesh.instance_count:
						var xf: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(i)
						out.append(xf * local)
			elif n is MeshInstance3D:
				var mi := n as MeshInstance3D
				if mi.mesh != null:
					out.append(mi.global_transform * mi.mesh.get_aabb())
			stack.append_array(n.get_children())
	return out


func _ray(x: float, z: float, from_y: float, to_y: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, to_y, z))
	return _space.intersect_ray(q)
