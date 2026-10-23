extends RefCounted
## 小规模地面多边形并集上的可见图；绝不跨越水面或不连通的平台。
static func contains(polygons: Array, p: Vector2) -> bool:
	for poly in polygons:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		for i in poly.size():
			if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < 0.0001:
				return true
	return false

static func clear_segment(polygons: Array, a: Vector2, b: Vector2) -> bool:
	if not contains(polygons, a) or not contains(polygons, b):
		return false
	var length_sq := a.distance_squared_to(b)
	if length_sq < 0.000001:
		return true
	var cuts: Array[float] = [0.0, 1.0]
	for poly in polygons:
		for i in poly.size():
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, poly[i], poly[(i + 1) % poly.size()])
			if hit != null:
				cuts.append(clampf(((hit as Vector2) - a).dot(b - a) / length_sq, 0.0, 1.0))
	cuts.sort()
	for i in range(1, cuts.size()):
		if not contains(polygons, a.lerp(b, (cuts[i - 1] + cuts[i]) * 0.5)):
			return false
	return true

static func route(polygons: Array, start: Vector2, goal: Vector2) -> PackedVector2Array:
	if not contains(polygons, start) or not contains(polygons, goal):
		return PackedVector2Array()
	if clear_segment(polygons, start, goal):
		return PackedVector2Array([start, goal])
	var graph := AStar2D.new()
	var points: Array[Vector2] = [start, goal]
	for poly in polygons:
		for p in poly:
			if not points.has(p):
				points.append(p)
	for i in points.size():
		graph.add_point(i, points[i])
	for i in points.size():
		for j in range(i + 1, points.size()):
			if clear_segment(polygons, points[i], points[j]):
				graph.connect_points(i, j)
	return graph.get_point_path(0, 1)
