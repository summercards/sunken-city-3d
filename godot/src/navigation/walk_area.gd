extends Node3D
## 区块上的「可行动区域」。
##
## 一个 walk 区块 = 一个 WalkArea 节点，rects 是区块内相对坐标（x,z），
## surface_y 是站立面高度（绝对世界高度），span 是允许站立的真实表面窗口
## （原网页版 walk[].span，用来挡掉屋顶/水下）。
##
## 场景里这些节点是可见、可编辑的；点击地面时用射线和这里的矩形求交，
## 所以「哪些地方能走」是场景数据，不是写死在代码里的。

@export var area_id := ""
@export var zone_id := ""
@export var surface_y := 2.15
@export var span_min := 1.3
@export var span_max := 2.45
@export var rects: Array = []
@export var polygons: Array[PackedVector2Array] = []
## Optional local-space 3D triangles for slopes and stacked floors. Existing
## authored rectangles remain the compatibility input for the current content.
@export var surface_triangles := PackedVector3Array()
## Ground boundary edges intentionally joined by another sloped surface.
var open_surface_junctions: Array=[]
var ground_space: Node3D
const GroundPath = preload("res://src/navigation/ground_path.gd")

## 角色轮廓半径：站位点要往里收这么多，人物整个身影才落在甲板上。
##
## 不能只用「脚在甲板上」当标准：角色是斜俯视看到的一整只人，
## 站直时最宽处是渔夫帽檐（CylinderMesh radius 0.34）和手臂外缘，
## 取 0.38 留 4 cm 余量。只把圆心夹到甲板边缘，帽檐就会压在水面上 ——
## 画面上看是"人站在水里"。
##
## 注意别用 AABB 角点当半径：那是斜立方体的对角线（帽檐量出 0.54），虚高一大截，
## 会把可走区域收得过窄。
@export var body_radius := 0.38

func outlines() -> Array:
	var result: Array = polygons.duplicate()
	for r: Rect2 in rects:
		result.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
			r.end, Vector2(r.position.x, r.end.y)]))
	return result


## 从 (x, z) 出发到行走区并集边界的最短距离，用来判断这里能不能放下整个身影。
##
## 用并集而不是单块矩形的边界：两块矩形接缝处不算边界，
## 否则站在接缝上会被误判成贴边、被白白推开。
##
## 只量到 `reach` 为止 —— 判据只需要知道「够不够 body_radius」，
## 不需要真实的最短距离，所以默认只量到半径多一点点（省掉一圈无用二分）。
## 八个方向对轴对齐矩形并集已经够：最近点要么在垂直边、要么在直角处。
func clearance(x: float, z: float, reach := -1.0, directions := 8) -> float:
	if not contains_local(x, z):
		return 0.0
	var limit := reach if reach > 0.0 else body_radius + 0.05
	var best := limit
	for i in directions:
		var u := Vector2.RIGHT.rotated(TAU * float(i) / float(directions))
		var lo := 0.0
		var hi := best
		if not contains_local(x + u.x * hi, z + u.y * hi):
			for k in 9:
				var mid := (lo + hi) * 0.5
				if contains_local(x + u.x * mid, z + u.y * mid):
					lo = mid
				else:
					hi = mid
			best = lo
			if best <= 0.001:
				return 0.0
	return best


## 把落点收进「能容下整个身影」的位置。
##
## 判据：以该点为圆心、body_radius 为半径的圆整个落在行走区并集内。
## 不满足时按「还差多少」先试一圈：贴边时缺口 d 就是需要往内推的距离，
## 一圈 16 方向通常第一个就够，比从 0.05 m 起步逐圈外扩快一个量级
## （实测边缘点击 4.4 ms → 0.4 ms）。试不出来再逐圈外扩兜底。
## 整片区域都容不下人影（走廊比人窄）时返回原位 —— 那是数据侧要改的事，
## 运行时硬挤只会把人挤到别的地方去。
func walkable_local(p: Vector2) -> Vector2:
	var r := body_radius
	if r <= 0.001 or not contains_local(p.x, p.y):
		return p
	var free := clearance(p.x, p.y)
	if free + 0.001 >= r:
		return p
	# 第一轮：按缺口一次推到位。
	var deficit := r - free + 0.02
	for i in 16:
		var u := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
		var q := p + u * deficit
		if contains_local(q.x, q.y) and clearance(q.x, q.y) + 0.001 >= r:
			return q
	# 兜底：缺口估不准（直角凹口、多块矩形夹角）时逐圈外扩。
	for k in 14:
		var t := deficit + float(k + 1) * 0.08
		for i in 16:
			var u2 := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
			var q2 := p + u2 * t
			if contains_local(q2.x, q2.y) and clearance(q2.x, q2.y) + 0.001 >= r:
				return q2
	return p


## 求路。起点/终点按并集算，不做身影内收 ——
## 交互目标（土箱、菜箱中心）本身不需要站在它正中心，
## 内收会挪动落点、破坏「走到目标点」的语义。内收只在点击落点处做（`clamp_point`）。
func path_between(start: Vector3, goal: Vector3) -> Array[Vector3]:
	goal = surface_point(goal)
	if not goal.is_finite(): return []
	if not is_instance_valid(ground_space) and is_inside_tree():
		var space := preload("res://src/navigation/ground_space.gd").new()
		space.name = "GroundSpace"
		add_child(space)
		space.configure([self])
	if is_instance_valid(ground_space):
		return ground_space.route(start, goal)
	var a := to_local(start)
	var b := to_local(goal)
	var route := GroundPath.route(outlines(), Vector2(a.x, a.z), Vector2(b.x, b.z))
	var result: Array[Vector3] = []
	for p in route:
		var w := to_global(Vector3(p.x, 0, p.y))
		w.y = surface_y
		result.append(w)
	return result


func contains_local(x: float, z: float) -> bool:
	return GroundPath.contains(outlines(), Vector2(x, z))


func contains_world(x: float, z: float) -> bool:
	if not surface_triangles.is_empty():
		return surface_point(Vector3(x, surface_y, z)).is_finite()
	var local := to_local(Vector3(x, surface_y, z))
	return contains_local(local.x, local.z)


## 射线与该站立面求交，命中返回沿射线的距离，未命中返回 -1。
func pick(origin: Vector3, dir: Vector3) -> float:
	if not surface_triangles.is_empty():
		var best := INF
		var faces := surface_faces()
		for i in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, faces[i], faces[i+1], faces[i+2])
			if hit != null: best = minf(best, origin.distance_to(hit))
		return best if is_finite(best) else -1.0
	if absf(dir.y) < 0.0001:
		return -1.0
	var t := (surface_y - origin.y) / dir.y
	if t <= 0.0:
		return -1.0
	var p := origin + dir * t
	if not contains_world(p.x, p.z):
		return -1.0
	return t


func center_world() -> Vector3:
	if rects.is_empty():
		return global_position
	var acc := Vector2.ZERO
	for r in rects:
		acc += (r as Rect2).get_center()
	acc /= float(rects.size())
	var p := to_global(Vector3(acc.x, 0, acc.y))
	return Vector3(p.x, surface_y, p.z)


## 把目标点夹进区域，避免走到甲板外面。
##
## 两步：先夹进矩形并集（否则点在水面上会直接吸到甲板边），
## 再按角色轮廓内收（否则人站在边缘，帽檐和肩膀压在水面上）。
func clamp_point(x: float, z: float) -> Vector2:
	var local := to_local(Vector3(x, surface_y, z))
	var src := Vector2(local.x, local.z)
	var p := src
	if not contains_local(src.x, src.y):
		var best_d := INF
		for r in rects:
			var rect: Rect2 = r
			var q := Vector2(clampf(src.x, rect.position.x, rect.end.x),
				clampf(src.y, rect.position.y, rect.end.y))
			var d := Vector2(src.x - q.x, src.y - q.y).length()
			if d < best_d:
				best_d = d
				p = q
	p = walkable_local(p)
	var w := to_global(Vector3(p.x, surface_y, p.y))
	return Vector2(w.x, w.z)


func area_span() -> Vector2:
	return Vector2(span_min, span_max)

func surface_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	if not surface_triangles.is_empty():
		for p in surface_triangles: faces.append(to_global(p))
	else:
		for outline: PackedVector2Array in outlines():
			var indices := Geometry2D.triangulate_polygon(outline)
			for index in indices:
				var p := to_global(Vector3(outline[index].x, 0.0, outline[index].y))
				p.y = surface_y
				faces.append(p)
	# Recast and one-sided physical floors share the same upward winding.
	for i in range(0, faces.size()-2, 3):
		if (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).y < 0.0:
			var temp := faces[i+1]
			faces[i+1] = faces[i+2]; faces[i+2] = temp
	return faces

func surface_point(point: Vector3) -> Vector3:
	if surface_triangles.is_empty():
		return Vector3(point.x, surface_y, point.z) if contains_world(point.x, point.z) else Vector3.INF
	var best := Vector3.INF
	var distance := INF
	var faces := surface_faces()
	for i in range(0, faces.size()-2, 3):
		var a := faces[i]; var b := faces[i+1]; var c := faces[i+2]
		var normal := (b-a).cross(c-a)
		if absf(normal.y) < 0.00001: continue
		var y := a.y - (normal.x*(point.x-a.x)+normal.z*(point.z-a.z))/normal.y
		var candidate := Vector3(point.x,y,point.z)
		var outline := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
		if not GroundPath.contains([outline],Vector2(point.x,point.z)): continue
		if absf(y-point.y) < distance:
			distance = absf(y-point.y); best = candidate
	return best

func contains_position(point: Vector3, tolerance: float=0.5) -> bool:
	var support := surface_point(point)
	return support.is_finite() and absf(support.y-point.y) <= tolerance

func surface_normal(point: Vector3) -> Vector3:
	if surface_triangles.is_empty(): return Vector3.UP
	var faces := surface_faces()
	for i in range(0,faces.size()-2,3):
		var a := faces[i]; var b := faces[i+1]; var c := faces[i+2]
		var outline := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
		if GroundPath.contains([outline],Vector2(point.x,point.z)):
			return (b-a).cross(c-a).normalized()
	return Vector3.UP
