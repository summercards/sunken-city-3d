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


func contains_local(x: float, z: float) -> bool:
	for r in rects:
		var rect: Rect2 = r
		if rect.has_point(Vector2(x, z)):
			return true
	return false


func contains_world(x: float, z: float) -> bool:
	var local := to_local(Vector3(x, surface_y, z))
	return contains_local(local.x, local.z)


## 射线与该站立面求交，命中返回沿射线的距离，未命中返回 -1。
func pick(origin: Vector3, dir: Vector3) -> float:
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
func clamp_point(x: float, z: float) -> Vector2:
	var local := to_local(Vector3(x, surface_y, z))
	if contains_local(local.x, local.z):
		return Vector2(x, z)
	var best := Vector2(x, z)
	var best_d := INF
	for r in rects:
		var rect: Rect2 = r
		var q := Vector2(clampf(local.x, rect.position.x, rect.end.x),
			clampf(local.z, rect.position.y, rect.end.y))
		var d := Vector2(local.x - q.x, local.z - q.y).length()
		if d < best_d:
			best_d = d
			var w := to_global(Vector3(q.x, surface_y, q.y))
			best = Vector2(w.x, w.z)
	return best


func area_span() -> Vector2:
	return Vector2(span_min, span_max)
