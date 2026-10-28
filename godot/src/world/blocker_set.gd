@tool
extends Node3D
## 组件自带的阻挡声明。挂在组件 / 设施根节点下，跟着这个组件实例走。
##
## 为什么不是一张全局 shore.json：
##   旧做法把船的水面阻挡烘焙成一份 shore.json，数据源是 zones.json 的 walk.rects。
##   一旦场景里换了模型，shore.json 不会跟着变 —— 于是水面上留下看不见的墙，
##   模型所在的位置反而没有阻挡。本节点把「阻挡」变成组件自己的属性：
##   几何变了就重算，组件被替换 / 移动 / 缩放，阻挡同步跟随。
##
## mode：
##   auto   —— 从 target 的可见几何派生（默认）。只取与船体吃水高度这一段相交的
##             三角形，所以屋檐、阳台、树冠不会在水面生成空阻挡。
##   manual —— 用 manual_rects（组件本地 XZ），给形状特殊、自动派生不准的件兜底。
##   none   —— 明确声明「这个组件不参与水面阻挡」，用来排除小摆件、植物。
##
## 派生结果是世界坐标矩形，写在 rects_world 里，供 ZoneScene / WorldBlocks 收集。

@export_enum("auto", "manual", "none") var mode := "auto"
## 几何来源；留空用父节点。
@export var target_path: NodePath
## 栅格边长（米）。越小轮廓越准，矩形越多。0.4 对甲板/建筑够用。
@export var cell := 0.4
## manual 模式下的本地矩形（XZ）。
@export var manual_rects: Array[Rect2] = []
## 是否参与水面阻挡。
@export var blocks_water := true

var rects_world: Array[Rect2] = []
var derived_tris := 0
var derived_instances := 0

## 同一份 mesh 的顶点/索引只解析一次；MultiMesh 几十个实例共用。
static var _arrays_cache := {}


func _ready() -> void:
	# 实际重建由 ZoneScene.rebuild_blockers() 统一发起（它知道水高）。
	# 这里不自己跑，避免启动时同一份几何被算两遍。
	pass


## 重新派生。water_y 是水面高度，height 是船体需要让开的垂直高度。
func rebuild(water_y: float, height := 1.6) -> void:
	rects_world.clear()
	derived_tris = 0
	derived_instances = 0
	if mode == "none" or not blocks_water:
		return
	if mode == "manual":
		for r in manual_rects:
			var rect: Rect2 = r
			var a := global_transform * Vector3(rect.position.x, 0.0, rect.position.y)
			var b := global_transform * Vector3(rect.end.x, 0.0, rect.end.y)
			rects_world.append(Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)),
				Vector2(absf(b.x - a.x), absf(b.z - a.z))))
		return

	var source: Node = get_node_or_null(target_path) if not target_path.is_empty() else get_parent()
	if source == null:
		return
	var cells := {}
	var lo := water_y - 0.05
	var hi := water_y + height
	_scan(source, lo, hi, cells)
	if cells.is_empty():
		return
	_prune_isolated(cells)
	_fill_gaps(cells)
	rects_world = _merge(cells)


func _scan(node: Node, lo: float, hi: float, cells: Dictionary) -> void:
	if node.get_meta("visual_only", false): return
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.is_visible_in_tree() and mmi.multimesh != null and mmi.multimesh.mesh != null:
			var arrays := _arrays_of(mmi.multimesh.mesh)
			var local := mmi.multimesh.mesh.get_aabb()
			var xforms: Variant = mmi.get_meta("instance_transforms", null)
			for i in mmi.multimesh.instance_count:
				var local_xf: Transform3D = (xforms[i] as Transform3D) if xforms != null and i < (xforms as Array).size() \
					else mmi.multimesh.get_instance_transform(i)
				var xf: Transform3D = mmi.global_transform * local_xf
				# 整件都不在船体高度带里就直接跳过，不解析三角形。
				var box := xf * local
				if not _crosses_band(box.position.y, box.end.y, lo, hi):
					continue
				derived_instances += 1
				_raster(arrays, xf, lo, hi, cells)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			if _crosses_band(box.position.y, box.end.y, lo, hi):
				derived_instances += 1
				_raster(_arrays_of(mi.mesh), mi.global_transform, lo, hi, cells)
	for child in node.get_children():
		_scan(child, lo, hi, cells)


## 三角形是否与水线到船高这一段相交。
## 水平薄面（甲板、平台板）只要面本身落在带内就算 —— 它们厚度为 0，
## 但船确实会撞上去。竖直面/斜面则要求真正穿过一段，避免「擦边」生成空阻挡。
func _crosses_band(y_min: float, y_max: float, lo: float, hi: float) -> bool:
	if y_max < lo or y_min > hi:
		return false
	if absf(y_max - y_min) < 0.05:
		return y_min >= lo and y_min <= hi
	return minf(y_max, hi) - maxf(y_min, lo) >= 0.05


func _arrays_of(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	if _arrays_cache.has(key):
		return _arrays_cache[key]
	var out: Array = []
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts == null:
			continue
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		out.append([verts, idx if idx != null else PackedInt32Array()])
	_arrays_cache[key] = out
	return out


func _raster(arrays: Array, xf: Transform3D, lo: float, hi: float, cells: Dictionary) -> void:
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
			if not _crosses_band(y_min, y_max, lo, hi):
				continue
			derived_tris += 1
			_tri_cells(a, b, c, cells)


func _tri_cells(a: Vector3, b: Vector3, c: Vector3, cells: Dictionary) -> void:
	var min_x := minf(a.x, minf(b.x, c.x))
	var max_x := maxf(a.x, maxf(b.x, c.x))
	var min_z := minf(a.z, minf(b.z, c.z))
	var max_z := maxf(a.z, maxf(b.z, c.z))
	var i0 := int(floor(min_x / cell))
	var i1 := int(floor(max_x / cell))
	var j0 := int(floor(min_z / cell))
	var j1 := int(floor(max_z / cell))
	# 退化三角形跳过；极巨大的面（远景整片海床）跳过，避免把整片水标成阻挡。
	# 4000 格 ≈ 40m×16m 的甲板面，正常建筑构件不会超过。
	if (i1 - i0 + 1) * (j1 - j0 + 1) > 4000:
		return
	var area := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
	if absf(area) < 1e-9:
		return
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var px := (float(i) + 0.5) * cell
			var pz := (float(j) + 0.5) * cell
			var w0 := ((b.x - px) * (c.z - pz) - (c.x - px) * (b.z - pz)) / area
			var w1 := ((c.x - px) * (a.z - pz) - (a.x - px) * (c.z - pz)) / area
			var w2 := 1.0 - w0 - w1
			if w0 >= -1e-6 and w1 >= -1e-6 and w2 >= -1e-6:
				cells[Vector2i(i, j)] = true


## 填 1 格宽的缝：多个组件拼接时，相邻件的格子可能差半格，
## 在接缝上留下 0.4m 的洞 —— 船能从缝里钻进建筑。只填「三面被占」的格，
## 外轮廓不会被撑大。
func _fill_gaps(cells: Dictionary) -> void:
	for pass_i in 2:
		var add: Array = []
		var keys: Array = cells.keys()
		var min_x := 999999
		var max_x := -999999
		var min_y := 999999
		var max_y := -999999
		for key: Vector2i in keys:
			min_x = mini(min_x, key.x); max_x = maxi(max_x, key.x)
			min_y = mini(min_y, key.y); max_y = maxi(max_y, key.y)
		for j in range(min_y - 1, max_y + 2):
			for i in range(min_x - 1, max_x + 2):
				var c := Vector2i(i, j)
				if cells.has(c):
					continue
				var l := cells.has(Vector2i(i - 1, j))
				var r := cells.has(Vector2i(i + 1, j))
				var u := cells.has(Vector2i(i, j - 1))
				var d := cells.has(Vector2i(i, j + 1))
				# 左右都被占 / 上下都被占 = 夹在一条 1 格宽的缝里，填掉。
				# 外角只有一个方向的邻居，不会被填，轮廓不会撑大。
				if (l and r) or (u and d):
					add.append(c)
		if add.is_empty():
			return
		for c in add:
			cells[c] = true


## 去掉孤立单格：三角形只擦到格子角时会留下一块 0.4m 的幽灵阻挡。
## 只删四邻域全空的格子，1 格宽的柱子/栏杆仍然保留。
func _prune_isolated(cells: Dictionary) -> void:
	var drop: Array = []
	for key: Vector2i in cells:
		var n := 0
		if cells.has(Vector2i(key.x + 1, key.y)): n += 1
		if cells.has(Vector2i(key.x - 1, key.y)): n += 1
		if cells.has(Vector2i(key.x, key.y + 1)): n += 1
		if cells.has(Vector2i(key.x, key.y - 1)): n += 1
		if n == 0:
			drop.append(key)
	for key in drop:
		cells.erase(key)


## 格子合并：先按行合并连续段，再把上下行完全同跨度的段纵向吞并。
func _merge(cells: Dictionary) -> Array[Rect2]:
	var rows := {}
	for key: Vector2i in cells:
		if not rows.has(key.y):
			rows[key.y] = []
		(rows[key.y] as Array).append(key.x)
	var js: Array = rows.keys()
	js.sort()
	var spans_by_row := {}
	for j in js:
		var xs: Array = rows[j]
		xs.sort()
		var runs := []
		var start: int = xs[0]
		var prev: int = xs[0]
		for k in range(1, xs.size()):
			var x: int = xs[k]
			if x == prev + 1:
				prev = x
				continue
			runs.append([start, prev])
			start = x
			prev = x
		runs.append([start, prev])
		spans_by_row[j] = runs

	var out: Array[Rect2] = []
	var open_spans := {}
	for j in js:
		var runs: Array = spans_by_row[j]
		var next_open := {}
		for run: Array in runs:
			var key := Vector2i(run[0], run[1])
			if open_spans.has(key):
				var cur: Array = open_spans[key]
				cur[1] = j
				next_open[key] = cur
			else:
				next_open[key] = [j, j]
		for key: Vector2i in open_spans:
			if not next_open.has(key):
				var cur: Array = open_spans[key]
				out.append(_span_rect(key.x, key.y, cur[0], cur[1]))
		open_spans = next_open
	for key: Vector2i in open_spans:
		var cur: Array = open_spans[key]
		out.append(_span_rect(key.x, key.y, cur[0], cur[1]))
	return out


func _span_rect(i0: int, i1: int, j0: int, j1: int) -> Rect2:
	return Rect2(Vector2(float(i0) * cell, float(minf(j0, j1)) * cell),
		Vector2(float(i1 - i0 + 1) * cell, float(absi(j1 - j0) + 1) * cell))
