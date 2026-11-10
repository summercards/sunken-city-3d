extends SceneTree
## 设施可达性体检：可行走面 / 上岸点 / 水面阻挡。
##
## 只跑正式 main.tscn，不改场景、不写存档。三个维度全部对着**真实几何**量：
##   1. 可行走面：把 surface_y 那一层可见甲板栅格化，和 WalkArea 求差 ——
##      多出来的部分是「走到水面上」，缺的部分是「走不到的甲板」。
##   2. 上岸点：landStand 是否真的落在本区块可行走面上（≤0.01 m）、
##      boatPark 是否在开阔水面且离阻挡有船宽、dockEdge 是否真的在两者之间。
##   3. 阻挡：几何跨水线覆盖的格子 vs BlockerSet 派生的格子 ——
##      缺的是「船能开进去」，多出来的是「看不见的墙」。
##
## 输出 res://outputs/facility-access-audit.json，并由 runner 摘成报告。

const REPORT_PATH := "res://outputs/facility-access-audit.json"
const WATER_Y := 1.12
const WALK_CELL := 0.3
const BLOCK_CELL := 0.4
const BODY_RADIUS := 0.38
const BOAT_BEAM := 1.4
const PARK_CLEARANCE := 0.9

var main: Node
var nav
var shapes: Array = []
var world_meshes: Array = []
var out := {
	"water_y": WATER_Y,
	"facilities": [],
	"baked": {"shapes": [], "orphans": 0},
	"sunken_city": {},
	"notes": [],
}
var _arr_cache := {}
## 不能当几何证据的节点：水面本身就在水线带里，会把整片海算成「有几何」。
var exclude_roots: Array = []


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var path := str(ProjectSettings.get_setting("application/run/main_scene", "res://scenes/main.tscn"))
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("无法加载主场景")
		quit(2)
		return
	main = scene.instantiate()
	root.add_child(main)
	if "_autosave_on" in main:
		main.set("_autosave_on", false)
	for i in 40:
		await process_frame

	shapes = main._water_shapes()
	nav = preload("res://src/navigation/water_navigation.gd").new()
	nav.shape_query = func() -> Array: return shapes

	var water_node: Node = main.get_node_or_null("World/Water")
	if water_node != null:
		exclude_roots.append(water_node)
	var wake: Node = main.get_node_or_null("World/BoatWake")
	if wake != null:
		exclude_roots.append(wake)

	world_meshes = []
	_gather_meshes(main.get_node("World"), world_meshes)

	var zones: Node = main.get_node_or_null("World/Zones")
	for child in zones.get_children():
		_audit_facility(child)
	var structures: Node = main.get_node_or_null("World/SeaStructures")
	for child in structures.get_children():
		_audit_facility(child)
	var interior: Node = main.get_node_or_null("World/Interior")
	if interior != null:
		_audit_facility(interior)

	_audit_baked()
	_audit_sunken_city()

	_write()


# ---------------------------------------------------------------- facility

func _audit_facility(node: Node) -> void:
	var zid := str(node.get("zone_id")) if "zone_id" in node else ""
	var rec := {
		"name": str(node.name),
		"zone_id": zid,
		"path": str(main.get_path_to(node)),
		"registered": zid != "" and main._zone_nodes.get(zid, null) == node,
		"global_y": (node as Node3D).global_position.y,
		"water_layer": str(node.get("water_layer")) if "water_layer" in node else "",
		"walk_areas": [],
		"landings": [],
		"blockers": {},
		"flags": [],
	}
	var has_walk: bool = "walk_areas" in node and (node.get("walk_areas") as Array).size() > 0
	if not has_walk:
		rec["flags"].append("no_walk_area")
	# 阻挡
	if node.has_method("rebuild_blockers"):
		rec["blockers"] = _audit_blockers(node)
	else:
		rec["flags"].append("no_blocker_api")
	var walk_m2 := 0.0
	if has_walk:
		var areas: Array = node.get("walk_areas")
		for area in areas:
			var a := _audit_area(area, node)
			walk_m2 += float(a.get("footprint_m2", 0.0))
			rec["walk_areas"].append(a)
		for lp in node.landing_points():
			rec["landings"].append(_audit_landing(node, lp))
		if rec["landings"].is_empty():
			rec["flags"].append("no_landing")
	rec["walk_m2"] = walk_m2
	out["facilities"].append(rec)
	var b: Dictionary = rec["blockers"]
	print("[audit] %-24s zone=%-18s walk=%d landing=%d block=%-3d rects walk_m2=%.1f" % [
		rec["name"], zid if zid != "" else "-", rec["walk_areas"].size(), rec["landings"].size(),
		int(b.get("rects", 0)), walk_m2])


# ---------------------------------------------------------------- walk area

func _audit_area(area: Node3D, owner: Node) -> Dictionary:
	var a := {
		"area_id": str(area.get("area_id")),
		"active": bool(area.get("active")),
		"surface_y": float(area.get("surface_y")),
		"rects": (area.get("rects") as Array).size(),
		"polygons": (area.get("polygons") as Array).size(),
		"surface_triangles": (area.get("surface_triangles") as PackedVector3Array).size(),
	}
	var sy: float = float(area.get("surface_y"))
	a["above_water"] = sy - WATER_Y
	var cell := WALK_CELL
	var bounds := _world_bounds(area)
	a["bounds"] = [bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y]
	if not bounds.has_area():
		a["flags"] = ["empty_bounds"]
		return a
	a["footprint_m2"] = float(_cells_area(_outline_cells(area, cell, bounds), cell))
	var wrects: Array = []
	for r: Rect2 in (area.get("rects") as Array):
		var p0: Vector3 = area.to_global(Vector3(r.position.x, 0.0, r.position.y))
		var p1: Vector3 = area.to_global(Vector3(r.end.x, 0.0, r.end.y))
		wrects.append([snappedf(minf(p0.x, p1.x), 0.1), snappedf(minf(p0.z, p1.z), 0.1),
			snappedf(absf(p1.x - p0.x), 0.1), snappedf(absf(p1.z - p0.z), 0.1)])
	a["walk_rects"] = wrects

	var walk_cells := _outline_cells(area, cell, bounds)
	var meshes: Array = []
	_gather_meshes(owner, meshes)
	# 走域自己声明的站立带（span_min..span_max）就是它认为能站的高度范围。
	# 固定用 surface_y±0.30 找几何，会把 band 模式的坡面桥整条判成悬空
	# （菜园桥从 26.05 铺到 28.75，中位面只有 27.4）。平面楼顶的 span 本来就窄，
	# 退化成 ±0.30 时结果不变。
	var floor_lo := sy - 0.30
	var floor_hi := sy + 0.30
	var span_lo := float(area.get("span_min"))
	var span_hi := float(area.get("span_max"))
	# 平面层才按 surface_y±0.35 收面；band 模式的坡面桥铺满整条站立带，
	# 用中位高度卡平面会把低半段整片滤掉（菜园桥因此被判成 100% 悬空）。
	var flat_y := sy
	if span_hi - span_lo > 0.6:
		floor_lo = span_lo
		floor_hi = span_hi
		flat_y = INF
	a["floor_window"] = [snappedf(floor_lo, 0.01), snappedf(floor_hi, 0.01)]
	var floor_cells := _collect_cells(meshes, floor_lo, floor_hi, cell, bounds, flat_y)
	var over := {}
	var under := {}
	for key: Vector2i in walk_cells:
		if not floor_cells.has(key):
			over[key] = true
	for key: Vector2i in floor_cells:
		if not walk_cells.has(key):
			under[key] = true
	var walk_n := walk_cells.size()
	var floor_n := floor_cells.size()
	a["walk_cells"] = walk_n
	a["floor_cells"] = floor_n
	a["over_cells"] = over.size()
	a["under_cells"] = under.size()
	a["over_pct"] = 0.0 if walk_n == 0 else 100.0 * float(over.size()) / float(walk_n)
	a["under_pct"] = 0.0 if floor_n == 0 else 100.0 * float(under.size()) / float(floor_n)
	a["over_clusters"] = _top_clusters(over, cell, 6)
	a["under_clusters"] = _top_clusters(under, cell, 6)

	var islands := _islands(walk_cells, cell)
	a["islands"] = islands.size()
	a["island_areas"] = []
	a["island_boxes"] = []
	for isl in islands.slice(0, 8):
		a["island_areas"].append(float(_cells_area(isl, cell)))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for key: Vector2i in isl:
			lo.x = minf(lo.x, float(key.x) * cell); lo.y = minf(lo.y, float(key.y) * cell)
			hi.x = maxf(hi.x, float(key.x + 1) * cell); hi.y = maxf(hi.y, float(key.y + 1) * cell)
		a["island_boxes"].append([snappedf(lo.x, 0.1), snappedf(lo.y, 0.1),
			snappedf(hi.x - lo.x, 0.1), snappedf(hi.y - lo.y, 0.1), isl.size()])

	# 低甲板（离水 <1.2 m）上不该有「合法水面」：有就说明船能压上甲板。
	if sy - WATER_Y < 1.2:
		var wet := 0
		for key: Vector2i in walk_cells:
			if nav.is_open_water((float(key.x) + 0.5) * cell, (float(key.y) + 0.5) * cell):
				wet += 1
		a["deck_water_cells"] = wet
		a["deck_water_pct"] = 0.0 if walk_cells.is_empty() else 100.0 * float(wet) / float(walk_cells.size())

	# 连通性：从最大岛走到其它岛 / 区域中心
	var flags: Array = []
	if sy - WATER_Y < 0.02:
		flags.append("surface_at_or_below_water")
	if not bool(area.get("active")):
		flags.append("inactive")
	if a["over_pct"] > 6.0:
		flags.append("walk_over_water")
	if a["under_pct"] > 45.0:
		flags.append("walk_under_covers_deck")
	if islands.size() > 1:
		flags.append("walk_disconnected:%d" % islands.size())
	var route := _route_probe(area, islands, cell)
	a["route"] = route
	if route.get("failures", 0) > 0:
		flags.append("walk_unreachable:%d" % int(route["failures"]))
	a["flags"] = flags
	return a


func _route_probe(area: Node3D, islands: Array, cell: float) -> Dictionary:
	var result := {"from": [], "targets": 0, "failures": 0, "failed": []}
	if islands.is_empty():
		return result
	var area_id := str(area.get("area_id"))
	var start := Vector3.INF
	var landing = _landing_on(area)
	if landing != null:
		var stand: Vector3 = landing.stand_position()
		if area.contains_position(stand, 0.05):
			start = stand
			result["from"] = [start.x, start.y, start.z]
	if not start.is_finite():
		var seed: Array = islands[0]
		if seed.is_empty():
			return result
		var c := _cells_centroid(seed, cell)
		var w: Vector3 = area.to_global(Vector3(c.x, 0, c.y))
		start = Vector3(w.x, float(area.get("surface_y")), w.z)
		result["from"] = [start.x, start.y, start.z]
	for i in range(1, islands.size()):
		var isl: Array = islands[i]
		if isl.is_empty():
			continue
		var c := _cells_centroid(isl, cell)
		var w: Vector3 = area.to_global(Vector3(c.x, 0, c.y))
		var target := Vector3(w.x, float(area.get("surface_y")), w.z)
		result["targets"] += 1
		var path: Array = area.path_between(start, target)
		if path.size() < 2:
			result["failures"] += 1
			if result["failed"].size() < 5:
				result["failed"].append([target.x, target.y, target.z])
	return result


func _landing_on(area: Node3D):
	for child in area.get_children():
		if child.has_method("stand_position") and child.has_method("data"):
			return child
	return null


func _outline_cells(area: Node3D, cell: float, bounds: Rect2) -> Dictionary:
	var cells := {}
	var i0 := int(floor(bounds.position.x / cell))
	var i1 := int(floor(bounds.end.x / cell))
	var j0 := int(floor(bounds.position.y / cell))
	var j1 := int(floor(bounds.end.y / cell))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var x := (float(i) + 0.5) * cell
			var z := (float(j) + 0.5) * cell
			if area.contains_world(x, z):
				cells[Vector2i(i, j)] = true
	return cells


func _world_bounds(area: Node3D) -> Rect2:
	var polygons: Array = area.call("outlines")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly: PackedVector2Array in polygons:
		for p in poly:
			var w: Vector3 = area.to_global(Vector3(p.x, 0.0, p.y))
			lo.x = minf(lo.x, w.x); lo.y = minf(lo.y, w.z)
			hi.x = maxf(hi.x, w.x); hi.y = maxf(hi.y, w.z)
	# band 模式的派生可走面只有 surface_triangles，没有 rects / polygons。
	var tris: PackedVector3Array = area.get("surface_triangles")
	for p in tris:
		var w: Vector3 = area.to_global(p)
		lo.x = minf(lo.x, w.x); lo.y = minf(lo.y, w.z)
		hi.x = maxf(hi.x, w.x); hi.y = maxf(hi.y, w.z)
	if not lo.is_finite() or hi.x < lo.x:
		return Rect2()
	return Rect2(lo, hi - lo)


# ---------------------------------------------------------------- landing

func _audit_landing(zone: Node, lp: Node3D) -> Dictionary:
	var data: Dictionary = lp.data()
	var area: Node3D = lp.ground()
	var sy: float = float(area.get("surface_y"))
	var marker: Vector3 = lp.global_position
	var stand := Vector3(float(data.landStand[0]), float(data.landStand[1]), float(data.landStand[2]))
	var park := Vector2(float(data.boatPark[0]), float(data.boatPark[2]))
	var edge := Vector2(float(data.dockEdge[0]), float(data.dockEdge[2]))
	var rec := {
		"id": str(data.id),
		"name": str(data.name),
		"area_id": str(data.ground_id),
		"stand": [stand.x, stand.y, stand.z],
		"park": [park.x, float(data.boatPark[1]), park.y],
		"dock_edge": [edge.x, float(data.dockEdge[1]), edge.y],
		"stand_height_error": absf(stand.y - sy),
		"marker_on_surface": absf(marker.y - sy),
		"flags": [],
	}
	# 1) landStand 真的落在本区块可行走面上
	var support: Vector3 = area.surface_point(marker)
	var support_err := INF
	if support.is_finite():
		support_err = absf(support.y - marker.y)
	rec["surface_support_error"] = support_err
	if not support.is_finite():
		rec["flags"].append("stand_marker_outside_area")
	elif support_err > 0.01:
		rec["flags"].append("stand_off_surface:%.3f" % support_err)
	var local: Vector3 = area.to_local(Vector3(stand.x, stand.y, stand.z))
	rec["stand_clearance"] = float(area.clearance(local.x, local.z))
	if rec["stand_clearance"] + 0.001 < BODY_RADIUS:
		rec["flags"].append("stand_at_edge")
	# 2) boatPark 在开阔水面、离甲板有船宽
	var open: bool = nav.is_open_water(park.x, park.y)
	rec["park_open"] = open
	var gap := _park_gap(park)
	rec["park_gap_to_blocker"] = gap
	if not open:
		rec["flags"].append("park_in_blocker")
	elif gap < PARK_CLEARANCE + BOAT_BEAM * 0.5:
		rec["flags"].append("park_too_close:%.2f" % gap)
	# 3) 能不能划进来（八个方向各试一次，避免「某一侧被别的设施挡住」被误判成不可达）
	var away := park - Vector2(zone.global_position.x, zone.global_position.z)
	if away.length() < 0.5:
		away = Vector2(1, 0)
	away = away.normalized()
	var outer := park + away * 14.0
	var route: Array = nav.plan_route_to(outer, park.x, park.y)
	var via_away := route.size() >= 2
	var ok_dirs := 0
	var dirs_ok: Array = []
	for k in 8:
		var dirv := Vector2.RIGHT.rotated(TAU * float(k) / 8.0)
		var reached := false
		for distance in [12.0, 20.0, 30.0]:
			if nav.plan_route_to(park + dirv * distance, park.x, park.y).size() >= 2:
				reached = true
				break
		if reached:
			ok_dirs += 1
			dirs_ok.append(k)
	rec["park_reachable_away"] = via_away
	rec["park_approach_dirs"] = ok_dirs
	rec["park_reachable"] = ok_dirs > 0
	if ok_dirs == 0:
		rec["flags"].append("park_unreachable")
	elif ok_dirs < 8:
		rec["flags"].append("park_blocked_sides:%d/8" % (8 - ok_dirs))
	# 3b) 上岸点能不能走到本区域中心（走到别的平台 = 这个泊位上不去）
	var center: Vector3 = area.center_world()
	var to_center: Array = area.path_between(stand, center)
	rec["stand_to_center"] = to_center.size()
	rec["stand_on_walk"] = bool(area.contains_position(stand, 0.05))
	if not rec["stand_on_walk"]:
		rec["flags"].append("stand_off_walk_area")
	elif to_center.size() < 2:
		rec["flags"].append("stand_cannot_walk_in")
	# 4) dockEdge 是否真的在两者之间
	var seg := park - Vector2(stand.x, stand.z)
	var seg_len := seg.length()
	var t := 0.5
	var lateral := 0.0
	if seg_len > 0.01:
		var e := edge - Vector2(stand.x, stand.z)
		t = e.dot(seg) / (seg_len * seg_len)
		lateral = absf(e.x * seg.y - e.y * seg.x) / seg_len
	rec["edge_t"] = t
	rec["edge_lateral"] = lateral
	rec["stand_to_park"] = seg_len
	rec["drop"] = stand.y - float(data.boatPark[1])
	if t < 0.02 or t > 0.98 or lateral > 2.0:
		rec["flags"].append("dock_edge_off_line:t=%.2f lat=%.2f" % [t, lateral])
	if rec["stand_to_park"] < 0.5:
		rec["flags"].append("park_on_deck")
	return rec


## 停船点到最近水面阻挡矩形外沿的距离（矩形本身，已含 0.4 栅格）。
func _park_gap(p: Vector2) -> float:
	var best := INF
	for s: Dictionary in shapes:
		var c := Vector2(float(s.get("x", 0.0)), float(s.get("z", 0.0)))
		if bool(s.get("round", false)):
			best = minf(best, maxf(0.0, (p - c).length() - float(s.get("hx", 0.0))))
		else:
			var half := Vector2(float(s.get("hx", 0.0)), float(s.get("hz", s.get("hx", 0.0))))
			var d := p - c
			var outside := Vector2(maxf(absf(d.x) - half.x, 0.0), maxf(absf(d.y) - half.y, 0.0))
			best = minf(best, outside.length())
	return best


# ---------------------------------------------------------------- blockers

func _audit_blockers(node: Node) -> Dictionary:
	node.rebuild_blockers(WATER_Y, 1.6)
	var rects: Array = node.get("water_block_rects")
	var block_cells := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var for_geo: Array = []
	for r: Rect2 in rects:
		var i0 := int(floor(r.position.x / BLOCK_CELL))
		var i1 := int(floor(r.end.x / BLOCK_CELL))
		var j0 := int(floor(r.position.y / BLOCK_CELL))
		var j1 := int(floor(r.end.y / BLOCK_CELL))
		for j in range(j0, j1):
			for i in range(i0, i1):
				block_cells[Vector2i(i, j)] = true
		lo.x = minf(lo.x, r.position.x); lo.y = minf(lo.y, r.position.y)
		hi.x = maxf(hi.x, r.end.x); hi.y = maxf(hi.y, r.end.y)
	var rec := {"rects": rects.size(), "block_cells": block_cells.size(),
		"block_area_m2": float(block_cells.size()) * BLOCK_CELL * BLOCK_CELL}
	rec["rect_list"] = []
	for r: Rect2 in rects.slice(0, 90):
		rec["rect_list"].append([snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1),
			snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)])
	if rects.is_empty():
		rec["holes"] = []
		rec["extra"] = []
		rec["flag"] = "no_blocker"
		return rec
	var bounds := Rect2(lo, hi - lo).grow(2.0)
	_gather_meshes(node, for_geo)
	var geom := _collect_cells(for_geo, WATER_Y - 0.05, WATER_Y + 1.6, BLOCK_CELL, bounds, INF, true)
	var holes := {}
	var extra := {}
	for key: Vector2i in geom:
		if not block_cells.has(key):
			holes[key] = true
	for key: Vector2i in block_cells:
		if not geom.has(key):
			extra[key] = true
	rec["geom_cells"] = geom.size()
	rec["hole_cells"] = holes.size()
	rec["extra_cells"] = extra.size()
	rec["hole_pct"] = 0.0 if geom.is_empty() else 100.0 * float(holes.size()) / float(geom.size())
	rec["holes"] = _top_clusters(holes, BLOCK_CELL, 6)
	rec["extra"] = _top_clusters(extra, BLOCK_CELL, 6)
	rec["bounds"] = [bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y]
	rec["chords"] = _chord_test(Rect2(lo, hi - lo))
	# 水面阻挡应当把「这条设施自己」围住；整块没有阻挡就在 rec 里体现
	return rec


## 从 16 个方向各拉一条穿过设施包围盒中心的直线：
## 两端都在开阔水面、整段也没有被任何阻挡截断 = 船能从这栋建筑中间开过去。
func _chord_test(box: Rect2) -> Dictionary:
	var center := box.get_center()
	var radius := box.size.length() * 0.75 + 12.0
	var tested := 0
	var clear := 0
	var clear_dirs: Array = []
	for k in 16:
		var dir := Vector2.RIGHT.rotated(TAU * float(k) / 16.0)
		var a := center + dir * radius
		var b := center - dir * radius
		if not nav.is_open_water(a.x, a.y) or not nav.is_open_water(b.x, b.y):
			continue
		tested += 1
		if nav.segment_clear(a, b):
			clear += 1
			clear_dirs.append(k)
	return {"tested": tested, "clear": clear, "clear_dirs": clear_dirs}


# ---------------------------------------------------------------- baked

func _audit_baked() -> void:
	var raw := FileAccess.get_file_as_string("res://assets/baked/shore_environment.json")
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		out["notes"].append("shore_environment.json 不可读")
		return
	var list: Array = (parsed as Dictionary).get("shapes", [])
	var orphan := 0
	for s: Dictionary in list:
		var c := Vector2(float(s.get("x", 0.0)), float(s.get("z", 0.0)))
		var hx := float(s.get("hx", 0.0))
		var hz := float(s.get("hz", hx))
		var bounds := Rect2(c - Vector2(hx, hz), Vector2(hx, hz) * 2.0).grow(0.5)
		var geom := _collect_cells(world_meshes, WATER_Y - 0.05, WATER_Y + 1.6, BLOCK_CELL, bounds, INF)
		var supported := geom.size() > 0
		if not supported:
			orphan += 1
		out["baked"]["shapes"].append({
			"x": c.x, "z": c.y, "hx": hx, "hz": hz,
			"round": bool(s.get("round", false)),
			"geom_cells": geom.size(),
			"supported": supported,
		})
	out["baked"]["orphans"] = orphan


func _audit_sunken_city() -> void:
	var city: Node = main.get_node_or_null("World/SunkenCity")
	if city == null:
		return
	var blockers := 0
	var walks := 0
	var stack: Array = [city]
	var max_y := -INF
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("blocker_set.gd"):
			blockers += 1
		if n.has_method("surface_faces"):
			walks += 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var box: AABB = (n as Node3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			max_y = maxf(max_y, box.end.y)
		stack.append_array(n.get_children())
	out["sunken_city"] = {"blockers": blockers, "walk_areas": walks, "max_y": max_y,
		"water_y": WATER_Y}


# ---------------------------------------------------------------- geometry raster

func _gather_meshes(node: Node, out_list: Array, visual_only := false) -> void:
	var marked: bool = visual_only or node.get_meta("visual_only", false)
	for child in node.get_children():
		if child in exclude_roots:
			continue
		if child is MultiMeshInstance3D or child is MeshInstance3D:
			if not marked:
				out_list.append(child)
		_gather_meshes(child, out_list, marked)


func _collect_cells(meshes: Array, lo: float, hi: float, cell: float, bounds: Rect2, flat_y: float, skip_visual_only := false) -> Dictionary:
	var cells := {}
	for node in meshes:
		if not is_instance_valid(node):
			continue
		if skip_visual_only and node.get_meta("visual_only", false):
			continue
		if not (node as GeometryInstance3D).is_visible_in_tree():
			continue
		if node is MultiMeshInstance3D:
			var mm := node as MultiMeshInstance3D
			if mm.multimesh == null or mm.multimesh.mesh == null:
				continue
			var arrays := _arrays_of(mm.multimesh.mesh)
			var local: AABB = mm.multimesh.mesh.get_aabb()
			var xforms: Variant = mm.get_meta("instance_transforms", null)
			for i in mm.multimesh.instance_count:
				var local_xf: Transform3D = (xforms[i] as Transform3D) if xforms != null and i < (xforms as Array).size() \
					else mm.multimesh.get_instance_transform(i)
				var xf: Transform3D = mm.global_transform * local_xf
				var box: AABB = xf * local
				if box.end.y < lo or box.position.y > hi:
					continue
				if not _aabb_hits(box, bounds):
					continue
				_raster(arrays, xf, lo, hi, cell, bounds, flat_y, cells)
		else:
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			if box.end.y < lo or box.position.y > hi:
				continue
			if not _aabb_hits(box, bounds):
				continue
			_raster(_arrays_of(mi.mesh), mi.global_transform, lo, hi, cell, bounds, flat_y, cells)
	return cells


func _arrays_of(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	if _arr_cache.has(key):
		return _arr_cache[key]
	var result: Array = []
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts == null:
			continue
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		result.append([verts, idx if idx != null else PackedInt32Array()])
	_arr_cache[key] = result
	return result


func _raster(arrays: Array, xf: Transform3D, lo: float, hi: float, cell: float, bounds: Rect2, flat_y: float, cells: Dictionary) -> void:
	for surface: Array in arrays:
		var v: PackedVector3Array = surface[0]
		var index: PackedInt32Array = surface[1]
		var n := index.size() if index.size() > 0 else v.size()
		var i := 0
		while i + 2 < n:
			var a := xf * v[index[i] if index.size() > 0 else i]
			var b := xf * v[index[i + 1] if index.size() > 0 else i + 1]
			var c := xf * v[index[i + 2] if index.size() > 0 else i + 2]
			i += 3
			var y_min := minf(a.y, minf(b.y, c.y))
			var y_max := maxf(a.y, maxf(b.y, c.y))
			if y_max < lo or y_min > hi:
				continue
			if flat_y != INF:
				if absf(y_min - flat_y) > 0.35 or absf(y_max - flat_y) > 0.35:
					continue
				var normal := (b - a).cross(c - a)
				if normal.length_squared() < 1e-12:
					continue
				if absf(normal.normalized().y) < 0.55:
					continue
			_tri_cells(a, b, c, cell, bounds, cells)


func _tri_cells(a: Vector3, b: Vector3, c: Vector3, cell: float, bounds: Rect2, cells: Dictionary) -> void:
	var min_x := minf(a.x, minf(b.x, c.x))
	var max_x := maxf(a.x, maxf(b.x, c.x))
	var min_z := minf(a.z, minf(b.z, c.z))
	var max_z := maxf(a.z, maxf(b.z, c.z))
	if max_x < bounds.position.x or min_x > bounds.end.x or max_z < bounds.position.y or min_z > bounds.end.y:
		return
	var i0 := maxi(int(floor(min_x / cell)), int(floor(bounds.position.x / cell)))
	var i1 := mini(int(floor(max_x / cell)), int(floor(bounds.end.x / cell)))
	var j0 := maxi(int(floor(min_z / cell)), int(floor(bounds.position.y / cell)))
	var j1 := mini(int(floor(max_z / cell)), int(floor(bounds.end.y / cell)))
	if (i1 - i0 + 1) * (j1 - j0 + 1) > 20000:
		return
	var area2 := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
	if absf(area2) < 1e-12:
		return
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var px := (float(i) + 0.5) * cell
			var pz := (float(j) + 0.5) * cell
			var w0 := ((b.x - px) * (c.z - pz) - (c.x - px) * (b.z - pz)) / area2
			var w1 := ((c.x - px) * (a.z - pz) - (a.x - px) * (c.z - pz)) / area2
			var w2 := 1.0 - w0 - w1
			if w0 >= -1e-6 and w1 >= -1e-6 and w2 >= -1e-6:
				cells[Vector2i(i, j)] = true


func _aabb_hits(box: AABB, bounds: Rect2) -> bool:
	return box.end.x >= bounds.position.x and box.position.x <= bounds.end.x \
		and box.end.z >= bounds.position.y and box.position.z <= bounds.end.y


# ---------------------------------------------------------------- cells utils

func _cells_area(cells: Variant, cell: float) -> float:
	var n: int = cells.size()
	return float(n) * cell * cell


func _cells_centroid(cells: Variant, cell: float) -> Vector2:
	var keys: Array = cells.keys() if cells is Dictionary else cells
	if keys.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for key: Vector2i in keys:
		acc += Vector2((float(key.x) + 0.5) * cell, (float(key.y) + 0.5) * cell)
	return acc / float(keys.size())


func _islands(cells: Dictionary, cell: float) -> Array:
	var seen := {}
	var result: Array = []
	for key: Vector2i in cells:
		if seen.has(key):
			continue
		var island: Array = []
		var stack: Array = [key]
		seen[key] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			island.append(c)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb := c + d
				if cells.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		result.append(island)
	result.sort_custom(func(x, y): return x.size() > y.size())
	return result


## 最多返回 n 个最大的连通块，带世界坐标范围，便于直接去场景里找。
func _top_clusters(cells: Dictionary, cell: float, n: int) -> Array:
	var islands := _islands(cells, cell)
	var result: Array = []
	for i in mini(n, islands.size()):
		var isl: Array = islands[i]
		if isl.size() < 2:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for key: Vector2i in isl:
			lo.x = minf(lo.x, float(key.x) * cell); lo.y = minf(lo.y, float(key.y) * cell)
			hi.x = maxf(hi.x, float(key.x + 1) * cell); hi.y = maxf(hi.y, float(key.y + 1) * cell)
		result.append({"cells": isl.size(), "x": (lo.x + hi.x) * 0.5, "z": (lo.y + hi.y) * 0.5,
			"w": hi.x - lo.x, "h": hi.y - lo.y})
	return result


func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("无法写报告")
		quit(1)
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("[audit] baked orphans=%d  facilities=%d" % [int(out["baked"]["orphans"]), out["facilities"].size()])
	print("[audit] report=", ProjectSettings.globalize_path(REPORT_PATH))
	quit(0)
