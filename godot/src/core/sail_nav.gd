class_name SailNavLib
extends RefCounted

## 水面寻路 —— 与 sea/sail-nav.js 一一对应。
##
## 障碍压成栅格，A* 找路，再用「拉绳」把折线拉直。纯数据实现，不碰场景。
## 坐标约定：世界坐标用 Vector2(x, z)；栅格把 bounds.position 当原点。

const NAV_CELL := 0.5

const DIRS := [
	[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
	[1, 1, sqrt(2.0)], [1, -1, sqrt(2.0)], [-1, 1, sqrt(2.0)], [-1, -1, sqrt(2.0)],
]


## 最小二叉堆（按 f 排序）。
class MinHeap:
	extends RefCounted

	var nodes: Array[int] = []
	var score: Array[float] = []

	func size() -> int:
		return nodes.size()

	func push(idx: int, f: float) -> void:
		nodes.append(idx)
		score.append(f)
		var n := nodes.size() - 1
		while n > 0:
			var p := (n - 1) >> 1
			if score[p] <= score[n]:
				break
			var tn := nodes[p]
			nodes[p] = nodes[n]
			nodes[n] = tn
			var ts := score[p]
			score[p] = score[n]
			score[n] = ts
			n = p

	func pop() -> int:
		if nodes.is_empty():
			return -1
		var top := nodes[0]
		var last := nodes.size() - 1
		nodes[0] = nodes[last]
		score[0] = score[last]
		nodes.remove_at(last)
		score.remove_at(last)
		var size := nodes.size()
		if size > 0:
			var n := 0
			while true:
				var l := n * 2 + 1
				var r := l + 1
				var m := n
				if l < size and score[l] < score[m]:
					m = l
				if r < size and score[r] < score[m]:
					m = r
				if m == n:
					break
				var tn := nodes[m]
				nodes[m] = nodes[n]
				nodes[n] = tn
				var ts := score[m]
				score[m] = score[n]
				score[n] = ts
				n = m
		return top


## 矩形 → 阻挡栅格。矩形按 clearance 外扩后再栅格化，用「格子与矩形有重叠即阻挡」。
## rects 每项是 Rect2(minX, minZ, sizeX, sizeZ)。
static func create_nav_grid(rects: Array, bounds: Rect2, cell: float = NAV_CELL, clearance: float = 1.0) -> Dictionary:
	var cols: int = maxi(1, int(ceil(bounds.size.x / cell)))
	var rows: int = maxi(1, int(ceil(bounds.size.y / cell)))
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	blocked.fill(0)

	for r in rects:
		var min_x: float = r.position.x - clearance
		var max_x: float = r.end.x + clearance
		var min_z: float = r.position.y - clearance
		var max_z: float = r.end.y + clearance
		var i0: int = maxi(0, int(floor((min_x - bounds.position.x) / cell)))
		var i1: int = mini(cols - 1, int(floor((max_x - bounds.position.x) / cell)))
		var j0: int = maxi(0, int(floor((min_z - bounds.position.y) / cell)))
		var j1: int = mini(rows - 1, int(floor((max_z - bounds.position.y) / cell)))
		for j in range(j0, j1 + 1):
			var z0: float = bounds.position.y + j * cell
			if z0 > max_z or z0 + cell < min_z:
				continue
			var row := j * cols
			for i in range(i0, i1 + 1):
				var x0: float = bounds.position.x + i * cell
				if x0 > max_x or x0 + cell < min_x:
					continue
				blocked[row + i] = 1

	return {
		"cell": cell,
		"cols": cols,
		"rows": rows,
		"bounds": bounds,
		"blocked": blocked,
		"clearance": clearance,
	}


static func cell_of(grid: Dictionary, x: float, z: float) -> Vector2i:
	var b: Rect2 = grid.bounds
	var cell: float = grid.cell
	return Vector2i(
		int(floor((x - b.position.x) / cell)),
		int(floor((z - b.position.y) / cell))
	)


static func cell_center(grid: Dictionary, i: int, j: int) -> Vector2:
	var b: Rect2 = grid.bounds
	var cell: float = grid.cell
	return Vector2(b.position.x + (i + 0.5) * cell, b.position.y + (j + 0.5) * cell)


static func is_free_cell(grid: Dictionary, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= grid.cols or j >= grid.rows:
		return false
	return grid.blocked[j * grid.cols + i] == 0


static func is_free(grid: Dictionary, x: float, z: float) -> bool:
	var c := cell_of(grid, x, z)
	return is_free_cell(grid, c.x, c.y)


## 从给定格子向外一圈圈找最近的可通行格（起点/终点常常压在停泊位边上）。
static func nearest_free(grid: Dictionary, x: float, z: float, max_ring: int = 24) -> Variant:
	var c := cell_of(grid, x, z)
	if is_free_cell(grid, c.x, c.y):
		var center := cell_center(grid, c.x, c.y)
		return {"i": c.x, "j": c.y, "x": center.x, "z": center.y}
	for ring in range(1, max_ring + 1):
		var best: Variant = null
		for dj in range(-ring, ring + 1):
			for di in range(-ring, ring + 1):
				# 只扫这一圈的边框，避免重复检查内部。
				if maxi(absi(di), absi(dj)) != ring:
					continue
				var ni := c.x + di
				var nj := c.y + dj
				if not is_free_cell(grid, ni, nj):
					continue
				var d := di * di + dj * dj
				if best == null or d < best.d:
					best = {"i": ni, "j": nj, "d": d}
		if best != null:
			var center := cell_center(grid, best.i, best.j)
			return {"i": best.i, "j": best.j, "x": center.x, "z": center.y}
	return null


## 两点之间是否全程可通行（按格子采样，步长小于半格）。
## skip_start：跳过距起点这么远以内的采样 —— 停泊位本身就压在障碍边上。
static func line_is_clear(grid: Dictionary, a: Vector2, b: Vector2, skip_start: float = 0.0) -> bool:
	var dist := a.distance_to(b)
	var steps: int = maxi(1, int(ceil(dist / (float(grid.cell) * 0.4))))
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		if t * dist < skip_start:
			continue
		if not is_free(grid, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t):
			return false
	return true


## A*。返回世界坐标点列（Vector2），找不到返回 null。
static func find_path(grid: Dictionary, start: Vector2, end: Vector2, max_expansions: int = 240000) -> Variant:
	var cols: int = grid.cols
	var rows: int = grid.rows
	var total := cols * rows

	var s: Variant = nearest_free(grid, start.x, start.y, 24)
	var e: Variant = nearest_free(grid, end.x, end.y, 24)
	if s == null or e == null:
		return null

	var start_idx := int(s.j) * cols + int(s.i)
	var goal_idx := int(e.j) * cols + int(e.i)
	# 起终点落在同一格：直接给一条短直线。
	if start_idx == goal_idx:
		return [start, end]

	var g_score := PackedFloat64Array()
	g_score.resize(total)
	g_score.fill(INF)
	var f_score := PackedFloat64Array()
	f_score.resize(total)
	f_score.fill(INF)
	var from := PackedInt32Array()
	from.resize(total)
	from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(total)
	closed.fill(0)
	var heap := MinHeap.new()

	var goal_i: int = int(e.i)
	var goal_j: int = int(e.j)

	g_score[start_idx] = 0.0
	f_score[start_idx] = _heuristic(int(s.i), int(s.j), goal_i, goal_j)
	heap.push(start_idx, f_score[start_idx])

	var expansions := 0
	var found := false
	while heap.size() > 0:
		var cur := heap.pop()
		if cur == goal_idx:
			found = true
			break
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		expansions += 1
		if expansions > max_expansions:
			break
		var ci := cur % cols
		var cj := (cur - ci) / cols
		for d in DIRS:
			var di: int = d[0]
			var dj: int = d[1]
			var cost: float = d[2]
			var ni := ci + di
			var nj := cj + dj
			if not is_free_cell(grid, ni, nj):
				continue
			# 斜走不许从两个障碍的夹角里蹭过去。
			if di != 0 and dj != 0:
				if not is_free_cell(grid, ci + di, cj) or not is_free_cell(grid, ci, cj + dj):
					continue
			var n_idx := nj * cols + ni
			if closed[n_idx] == 1:
				continue
			# 贴着障碍的格子加一点代价，让船走在水道中间而不是贴着墙。
			var blocked_around := 0
			if not is_free_cell(grid, ni + 1, nj):
				blocked_around += 1
			if not is_free_cell(grid, ni - 1, nj):
				blocked_around += 1
			if not is_free_cell(grid, ni, nj + 1):
				blocked_around += 1
			if not is_free_cell(grid, ni, nj - 1):
				blocked_around += 1
			var tentative: float = g_score[cur] + cost * (1.0 + blocked_around * 0.42)
			if tentative >= g_score[n_idx]:
				continue
			g_score[n_idx] = tentative
			f_score[n_idx] = tentative + _heuristic(ni, nj, goal_i, goal_j)
			from[n_idx] = cur
			heap.push(n_idx, f_score[n_idx])

	if not found:
		return null

	var cells: Array = []
	var idx := goal_idx
	while idx != -1:
		var i := idx % cols
		cells.append(cell_center(grid, i, (idx - i) / cols))
		if idx == start_idx:
			break
		idx = from[idx]
	cells.reverse()
	# 用真实起终点替换首尾（首尾格中心可能被 closest-free 挪开了一两米）。
	cells[0] = start
	cells[cells.size() - 1] = end
	return cells


static func _heuristic(i: int, j: int, goal_i: int, goal_j: int) -> float:
	var dx: int = absi(i - goal_i)
	var dy: int = absi(j - goal_j)
	return float(dx + dy) + (sqrt(2.0) - 2.0) * float(mini(dx, dy))


## 拉绳平滑：从当前锚点尽量往后找「直线可达」的最远点。
static func smooth_path(grid: Dictionary, points: Array) -> Array:
	if points.size() <= 2:
		return points
	var out: Array = [points[0]]
	var anchor := 0
	while anchor < points.size() - 1:
		var next := points.size() - 1
		while next > anchor + 1:
			var a: Vector2 = points[anchor]
			var b: Vector2 = points[next]
			# 起点那一小段可能压在停泊位边上，跳过前 1.6m 的判定。
			if line_is_clear(grid, a, b, 1.6 if anchor == 0 else 0.0):
				break
			next -= 1
		out.append(points[next])
		anchor = next
	return out


## 一次搞定：A* + 平滑。找不到返回 null。
static func plan_route(grid: Dictionary, start: Vector2, end: Vector2) -> Variant:
	var raw: Variant = find_path(grid, start, end)
	if raw == null or raw.size() < 2:
		return null
	return smooth_path(grid, raw)


static func path_length(points: Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total
