extends SceneTree
## 只读探针：把「模型实际在哪」「可行走面在哪」「岸线阻挡在哪」量到同一份报告里。
##
## 做法：给区块场景里每个可见网格临时建三角面碰撞（只在本进程内存里），
## 再用向下射线采样，判断：
##   · 每个 shore.json 形状内部到底有没有实体支撑（无支撑 = 空阻挡）；
##   · 每个 WalkArea 矩形内部到底有没有可站立甲板（无甲板 = 悬空走道）。
## 本脚本不改场景、不改 shore.json；碰撞体随进程退出消失。
##
## 注意：必须用真实渲染跑（不加 --headless）。headless 的 dummy renderer 读不出
## MultiMesh 实例变换，木屋等烘焙实例会全部落在原点，测量结果无效。

const ZONES := [
	["zone1", "zones/zone1_home_harbor.tscn"], ["zone2", "zones/zone2_yokohama_station.tscn"],
	["zone3", "zones/zone3_arc_farm.tscn"], ["zone4", "zones/zone4_far_shore.tscn"],
	["zone5", "zones/zone5_aqua_platform.tscn"],
	["environment", "world/environment.tscn"],
]
const SAMPLE := 0.5

var out := {}
var _space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var shore: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/baked/shore.json"))
	out["water_level"] = float(shore.get("waterLevel", 1.12)) if shore is Dictionary else 1.12
	var vl := float(out["water_level"])
	out["shore_shapes"] = []
	for s in (shore.get("shapes", []) if shore is Dictionary else []):
		var shape: Dictionary = s
		var sh := {
			"x": float(shape.get("x", 0.0)), "z": float(shape.get("z", 0.0)),
			"hx": float(shape.get("hx", 0.0)), "hz": float(shape.get("hz", shape.get("hx", 0.0))),
			"round": bool(shape.get("round", false)),
			"asset_id": str(shape.get("asset_id", "")),
		}
		out["shore_shapes"].append(sh)
	out["zones"] = {}
	var loaded: Array = []
	for pair in ZONES:
		var one: Variant = await _probe_zone(pair[0], pair[1], vl)
		if one != null:
			loaded.append(one)
	_analyse(vl)
	for zone in loaded:
		(zone as Node).queue_free()
	for b in _bodies:
		(b as Node).queue_free()
	print("[blockers] " + JSON.stringify(out))
	quit(0)


func _probe_zone(zone_id: String, key: String, water: float) -> Variant:
	var path := "res://scenes/%s" % key
	var packed: Variant = load(path)
	if packed == null:
		out["zones"][zone_id] = {"error": "场景加载失败 " + path}
		return null
	var zone: Node3D = (packed as PackedScene).instantiate()
	root.add_child(zone)
	await process_frame
	await process_frame
	_space = root.world_3d.direct_space_state
	await physics_frame

	var report := {"scene": path, "meshes": [], "walk_areas": [], "colliders": 0}
	_collect(zone, zone, report)
	await physics_frame
	await physics_frame
	_measure(zone, report, water)
	out["zones"][zone_id] = report
	return zone


## 遍历可见网格：记录包围盒，并挂一个临时三角碰撞体（只存在于本进程）。
func _collect(node: Node, zone: Node, report: Dictionary) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			if mmi.is_visible_in_tree() and mmi.multimesh != null:
				var box := _multimesh_box(mmi)
				report["meshes"].append({
					"path": str(zone_path(mmi)), "component": str(mmi.get_meta("asset_component", "")),
					"count": mmi.multimesh.instance_count, "aabb": _box(box),
				})
				report["colliders"] += _add_multimesh(zone, mmi)
		elif child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.is_visible_in_tree() and mi.mesh != null:
				report["meshes"].append({
					"path": str(zone_path(mi)), "component": "", "count": 1,
					"aabb": _box(mi.global_transform * mi.mesh.get_aabb()),
				})
				_add_trimesh(zone, mi.mesh, mi.global_transform)
				report["colliders"] += 1
		_collect(child, zone, report)


func _add_trimesh(zone: Node, mesh: Mesh, xf: Transform3D) -> void:
	var shape: Shape3D = mesh.create_trimesh_shape()
	if shape == null:
		return
	_attach(zone, shape, xf)


func _add_multimesh(zone: Node, mmi: MultiMeshInstance3D) -> int:
	var shape: Shape3D = mmi.multimesh.mesh.create_trimesh_shape()
	if shape == null:
		return 0
	for i in mmi.multimesh.instance_count:
		_attach(zone, shape, mmi.global_transform * mmi.multimesh.get_instance_transform(i))
	return mmi.multimesh.instance_count


func _attach(zone: Node, shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.global_transform = xf
	root.add_child(body)
	_bodies.append(body)


func _measure(zone: Node, report: Dictionary, water: float) -> void:
	var holder: Node = zone.get_node_or_null("WalkAreas")
	if holder != null:
		for area in holder.get_children():
			if not ("rects" in area):
				continue
			var rects := []
			for r in area.rects:
				var rect: Rect2 = r
				var a: Vector3 = area.to_global(Vector3(rect.position.x, 0.0, rect.position.y))
				var b: Vector3 = area.to_global(Vector3(rect.end.x, 0.0, rect.end.y))
				rects.append([minf(a.x, b.x), maxf(a.x, b.x), minf(a.z, b.z), maxf(a.z, b.z)])
			var deck := _deck_ratio(rects, float(area.surface_y))
			report["walk_areas"].append({
				"area_id": str(area.area_id), "surface_y": float(area.surface_y),
				"rects": rects, "deck_ratio": deck, "samples": _last_samples,
				"y_hist": _sorted_hist(),
			})


var _last_samples := 0
var _last_hist := {}
var _bodies: Array = []


## 在矩形集合内采样，统计「surface_y 附近有朝上的面」的比例。
func _deck_ratio(rects: Array, surface_y: float) -> float:
	var hit := 0
	var total := 0
	_last_hist = {}
	for r: Array in rects:
		var x := float(r[0])
		while x <= float(r[1]):
			var z := float(r[2])
			while z <= float(r[3]):
				total += 1
				var q := PhysicsRayQueryParameters3D.create(
					Vector3(x, surface_y + 0.8, z), Vector3(x, surface_y - 0.45, z))
				q.collide_with_areas = false
				var h: Dictionary = _space.intersect_ray(q)
				if not h.is_empty():
					var key := snappedf((h.position as Vector3).y, 0.25)
					_last_hist[key] = int(_last_hist.get(key, 0)) + 1
				if not h.is_empty() and absf((h.position as Vector3).y - surface_y) <= 0.35:
					var n: Vector3 = h.normal
					if absf(n.y) > 0.6:
						hit += 1
				z += SAMPLE
			x += SAMPLE
	_last_samples = total
	return float(hit) / float(maxi(1, total))


## 每个 shore 形状：内部有多少采样点在 y > 水面处被实体挡住（支撑率）。
func _analyse(water: float) -> void:
	out["shape_support"] = []
	for sh: Dictionary in out["shore_shapes"]:
		var hit := 0
		var total := 0
		var top_max := -INF
		var x := float(sh["x"]) - float(sh["hx"])
		while x <= float(sh["x"]) + float(sh["hx"]):
			var z := float(sh["z"]) - float(sh["hz"])
			while z <= float(sh["z"]) + float(sh["hz"]):
				var in_shape := true
				if bool(sh["round"]):
					var dx := x - float(sh["x"])
					var dz := z - float(sh["z"])
					in_shape = Vector2(dx, dz).length() <= float(sh["hx"])
				if in_shape:
					total += 1
					var q := PhysicsRayQueryParameters3D.create(
						Vector3(x, 60.0, z), Vector3(x, -40.0, z))
					var h: Dictionary = _space.intersect_ray(q)
					if not h.is_empty():
						var y := (h.position as Vector3).y
						top_max = maxf(top_max, y)
						if y > water + 0.15:
							hit += 1
				z += SAMPLE
			x += SAMPLE
		out["shape_support"].append({
			"x": sh["x"], "z": sh["z"], "hx": sh["hx"], "hz": sh["hz"],
			"round": sh["round"], "asset_id": sh["asset_id"],
			"support": float(hit) / float(maxi(1, total)), "top": snappedf(top_max, 0.01),
		})


func _sorted_hist() -> Array:
	var keys := _last_hist.keys()
	keys.sort()
	var out := []
	for k in keys:
		out.append([k, _last_hist[k]])
	return out


func _multimesh_box(mmi: MultiMeshInstance3D) -> AABB:
	var local: AABB = mmi.multimesh.mesh.get_aabb()
	var box := AABB()
	var first := true
	for i in mmi.multimesh.instance_count:
		var xf: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(i)
		var b := xf * local
		box = b if first else box.merge(b)
		first = false
	return box


func zone_path(n: Node) -> String:
	var parts := PackedStringArray()
	var cur: Node = n
	while cur != null and not (cur is Node3D and cur.get_parent() is Window):
		parts.append(str(cur.name))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


func _box(b: AABB) -> Array:
	return [_v(b.position), _v(b.end)]


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
