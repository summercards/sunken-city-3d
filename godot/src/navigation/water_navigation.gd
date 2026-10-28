extends RefCounted
## Legal water area -> route planning -> segment validation. No scene or global dependencies.
const SailNavLib = preload("res://src/navigation/sail_nav.gd")
const BLOCK_INDEX_CELL := 6.0
var _nav_grid: Dictionary = {}
var _block_index: Dictionary = {}
var _safe_nav: Dictionary = {}
var shape_query: Callable
var allowed_area := Rect2()
func _water_shapes() -> Array: return shape_query.call()
func invalidate() -> void:
	_nav_grid.clear()
	_block_index.clear()
	_safe_nav.clear()

func is_open_water(x: float, z: float) -> bool:
	if allowed_area.has_area() and not allowed_area.has_point(Vector2(x,z)): return false
	return is_geometric_water(x,z)

func is_geometric_water(x: float, z: float) -> bool:
	if x < -68.0 or x > 76.0 or z < -78.0 or z > 58.0:
		return false
	if _block_index.is_empty():
		_build_block_index()
	var bucket: Array = _block_index.get(_block_key(x, z), [])
	for s: Dictionary in bucket:
		var cx := float(s.get("x", 0.0))
		var cz := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0)) + 0.9
		if bool(s.get("round", false)):
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz <= hx * hx:
				return false
		else:
			var hz := float(s.get("hz", hx)) + 0.9
			if absf(x - cx) <= hx and absf(z - cz) <= hz:
				return false
	return true

func _block_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / BLOCK_INDEX_CELL)), int(floor(z / BLOCK_INDEX_CELL)))

func _build_block_index() -> void:
	_block_index.clear()
	for s: Dictionary in _water_shapes():
		var cx := float(s.get("x", 0.0))
		var cz := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0)) + 0.9
		var hz := float(s.get("hz", hx)) + 0.9
		var i0 := int(floor((cx - hx) / BLOCK_INDEX_CELL))
		var i1 := int(floor((cx + hx) / BLOCK_INDEX_CELL))
		var j0 := int(floor((cz - hz) / BLOCK_INDEX_CELL))
		var j1 := int(floor((cz + hz) / BLOCK_INDEX_CELL))
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var key := Vector2i(i, j)
				if not _block_index.has(key):
					_block_index[key] = []
				(_block_index[key] as Array).append(s)

func nav_grid() -> Dictionary:
	if not _nav_grid.is_empty():
		return _nav_grid
	var shapes: Array = _water_shapes()
	if shapes.is_empty():
		push_warning("水面阻挡为空（组件 BlockerSet 与远景岸线都没有），暂停航行")
		_nav_grid = {}
		return _nav_grid
	var rects: Array = []
	var rounds: Array = []
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for s in shapes:
		var x := float(s.get("x", 0.0))
		var z := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0))
		var hz := float(s.get("hz", hx))
		if bool(s.get("round", false)):
			rounds.append(Vector3(x, z, hx))
			min_p = Vector2(minf(min_p.x, x - hx), minf(min_p.y, z - hx))
			max_p = Vector2(maxf(max_p.x, x + hx), maxf(max_p.y, z + hx))
		else:
			rects.append(Rect2(x - hx, z - hz, hx * 2.0, hz * 2.0))
			min_p = Vector2(minf(min_p.x, x - hx), minf(min_p.y, z - hz))
			max_p = Vector2(maxf(max_p.x, x + hx), maxf(max_p.y, z + hz))
	# 四周各留 14m：泊位常常就在岸边，网格边缘不能正好卡在泊位上。
	min_p -= Vector2(14.0, 14.0)
	max_p += Vector2(14.0, 14.0)
	var bounds := allowed_area if allowed_area.has_area() else Rect2(min_p, max_p - min_p)
	var clearance := 2.3
	var grid: Dictionary = SailNavLib.create_nav_grid(rects, bounds, 0.5, clearance)

	# 圆形轮廓补进去：按格子中心到圆心的距离判定。
	var blocked: PackedByteArray = grid.blocked
	var cols: int = grid.cols
	var rows: int = grid.rows
	var cell: float = grid.cell
	var origin: Vector2 = bounds.position
	for c in rounds:
		var pad: float = float(c.z) + clearance
		var i0 := maxi(0, int(floor((c.x - pad - origin.x) / cell)))
		var i1 := mini(cols - 1, int(floor((c.x + pad - origin.x) / cell)))
		var j0 := maxi(0, int(floor((c.y - pad - origin.y) / cell)))
		var j1 := mini(rows - 1, int(floor((c.y + pad - origin.y) / cell)))
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var px := origin.x + (float(i) + 0.5) * cell
				var pz := origin.y + (float(j) + 0.5) * cell
				if Vector2(px - c.x, pz - c.y).length() <= pad:
					blocked[j * cols + i] = 1
	grid.blocked = blocked
	_nav_grid = grid
	return _nav_grid

func plan_route_to(from: Vector2, x: float, z: float) -> Array:
	var goal := Vector2(x, z)
	if not is_open_water(from.x, from.y) or not is_open_water(x, z):
		return []
	var grid := nav_grid()
	if grid.is_empty():
		return []
	var path: Variant = SailNavLib.plan_route(grid, from, goal)
	if valid_route(path):
		return path
	if _safe_nav.is_empty():
		_safe_nav = SailNavLib.create_nav_grid([], Rect2(-68, -78, 144, 136), 0.5, 0.9)
		var blocked: PackedByteArray = _safe_nav.blocked
		for j in _safe_nav.rows:
			for i in _safe_nav.cols:
				var p := SailNavLib.cell_center(_safe_nav, i, j)
				blocked[j * int(_safe_nav.cols) + i] = 0 if is_open_water(p.x, p.y) else 1
		_safe_nav.blocked = blocked
	path = SailNavLib.plan_route(_safe_nav, from, goal)
	return path if valid_route(path) else []

func valid_route(path: Variant) -> bool:
	if path == null or path.size() < 2:
		return false
	for i in range(1, path.size()):
		if not segment_clear(path[i - 1], path[i]):
			return false
	return true

func segment_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / 0.1)))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / steps)
		if not is_open_water(p.x, p.y):
			return false
	return true
