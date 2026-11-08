@tool
extends "res://src/navigation/walk_area.gd"
## 从模型几何派生可走面 —— 绑定模型，不额外制作。
##
## 为什么不手写 rects：
##   霓虹花园这类楼体的楼顶有楼梯间、水箱、空调、女儿墙，手写矩形必然盖住凸起；
##   模型一发版就要重抄一遍坐标。这里改成：给一个几何源节点，运行时从它的
##   真实三角形里找出「水平、够大、上方有站立净空」的那一层，自己算出 rects。
##   模型移动、缩放、改版，下一次重建自动跟随，场景数据不用动。
##
## 与 BlockerSet 的分工：
##   BlockerSet 管「船不能进」（水线到船高这一段），本节点管「人能站」
##   （净空 0.06–1.75 米这一段）。两者都从同一份几何派生，互不引用。
##
## 只读：派生结果写在 rects / surface_y 上，不回写场景文件。

## 几何来源。留空则取父节点的兄弟 `../Visual`。
@export var source_path: NodePath
## 栅格边长（米）。0.5 对楼顶够用：女儿墙内侧锯齿不超过半格。
@export_range(0.2, 2.0, 0.1) var precision := 0.5
## 选层策略：
##   largest —— 水平面总面积最大的那一层（楼顶、种植屋面通常是最大面）。
##   highest —— 最高的一层（会被屋顶楼梯间/水箱顶抢走，慎用）。
##   nearest —— 最接近 target_y 的一层。
@export_enum("largest", "highest", "nearest") var select := "largest"
## select = nearest 时的目标世界高度。
@export var target_y := 0.0
## 脚往上留多少才不算踩在自己这层上。
@export var clear_low := 0.06
## 站立净空上限（角色身高）。低矮管道不应把整片屋面判成不可站。
@export var clear_high := 1.75
## 遮挡物必须穿过站立带这么高才算挡人（米）。种植槽沿只有 10 厘米，
## 是能跨过去的边；0.35 把「边沿」和「柜子/墙」分开。
@export var min_obstruction := 0.35
## band 模式是否压平成矩形。
##
## true（默认）：可站格合并成矩形，surface_y 取中位高度。坡面高度差在
##   0.3 米以内的（种植土面）压平后角色只轻微浮空；换来的是导航一定能连片、
##   求路稳定 —— 斜面精确网格在 2.5 米宽的带上经常被腐蚀成孤岛。
## false：输出 surface_triangles 精确斜面，适合更宽、更大的坡。
@export var flatten_slopes := true
## 允许站立的坡度上限（度）。双坡屋面超过这个就只留平台。
@export_range(0.0, 60.0, 1.0) var max_slope_deg := 40.0
## 单层水平面总面积低于这个值就不当作可走层（避免把雨棚当楼顶）。
@export var min_layer_area := 8.0
## 目标高度这一带再纳入的上下容差（米）。
##
## 0 = 走「水平层 + 矩形」：适合平整楼顶。
## >0 = 走「这一带的可走坡度曲面」：适合有起伏或双坡的种植土面，结果用
##      surface_triangles 表达，非平面也能贴地（角色不会浮在坡上）。
## 此时 target_y 是这条带的中心，select 被忽略。
@export var band_tolerance := 0.0

## 派生结果摘要，供验证脚本读取（不参与导航）。
var derived_surface_y := NAN
var derived_cells := 0
var derived_usable := 0
var derived_layer_area := 0.0
var derived_rects := 0
var derived_signature := 0

var _built := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	rebuild_derived()


## 由 ZoneScene / 宿主在几何就绪后调用；可重复调用，内部按签名短路。
func rebuild_derived(force := false) -> void:
	var source := _source()
	if source == null:
		return
	var signature := _signature_of(source)
	if not force and _built and signature == derived_signature:
		return
	derived_signature = signature
	_built = true
	var mesh_source := _collect_triangles(source)
	if mesh_source.is_empty():
		rects = []
		return
	if band_tolerance > 0.0:
		_build_band(mesh_source)
		return
	var layer := _pick_layer(mesh_source)
	if layer.is_empty():
		rects = []
		return
	derived_surface_y = layer.y
	derived_layer_area = layer.area
	var cells: Dictionary = layer.cells
	derived_cells = cells.size()
	# 上方遮挡：一次遍历把「surface_y 之上」的三角形栅格化成占用表。
	var blocked := _blocked_cells(mesh_source, derived_surface_y + precision)
	var usable := {}
	for key: Vector2i in cells:
		if not blocked.has(key):
			usable[key] = true
	derived_usable = usable.size()
	var merged := _merge(usable)
	derived_rects = merged.size()
	surface_y = derived_surface_y
	# 站立面窗口跟着走：射线与点击判定要落在这一层，不能留旧高度。
	span_min = derived_surface_y - 0.5
	span_max = derived_surface_y + 0.5
	rects = merged
	active = not merged.is_empty()


## 该模式输出的三角形已经是「角色中心可行域」：本节点自己做一次
## body_radius 的内收，然后把 body_radius 归零，让 GroundSpace 走精确网格
## 而不是再腐蚀一遍 —— 0.5 米宽的坡面三角形经不起 0.38 米二次腐蚀。
@export var erode_body := true


## 把可站格按 8 邻域收一格：邻域里有不可站的格就丢掉。
## 0.5 米格 + 一格内收 ≈ body_radius 0.38，口径一致。
func _erode(cells: Dictionary) -> Dictionary:
	if not erode_body:
		return cells
	var result := {}
	for key: Vector2i in cells:
		var solid := true
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if not cells.has(Vector2i(key.x + dx, key.y + dz)):
					solid = false
					break
			if not solid:
				break
		if solid:
			result[key] = true
	return result


## 世界点 → 本节点的 XZ 格号。
##
## 必须走 to_local：这栋楼在主场景里被用户转了约 72°，
## 用「世界坐标减原点」当局部坐标会把整片楼顶算到别的位置去
## （实测 rects 全挤在 x[-1.5,3.5]、z[-11.5,-8]，落在后楼那边）。
## 局部 XZ + 世界 y → 世界点。只处理 Y 轴旋转 + 平移（本楼体无缩放）。
func _world_corner(local_x: float, local_z: float, world_y: float) -> Vector3:
	var mapped := global_transform * Vector3(local_x, world_y - global_position.y, local_z)
	return Vector3(mapped.x, world_y, mapped.z)


func _cell_of(point: Vector3) -> Vector2i:
	var local := to_local(point)
	return Vector2i(int(floor(local.x / precision)), int(floor(local.z / precision)))


func _source() -> Node3D:
	if not source_path.is_empty():
		var explicit := get_node_or_null(source_path)
		if explicit is Node3D:
			return explicit
	var sibling := get_parent().get_node_or_null("../Visual") if get_parent() != null else null
	return sibling if sibling is Node3D else null


## 场景一旦换模型、挪位置或缩放，签名就变，下一次重建会重算。
func _signature_of(source: Node3D) -> int:
	var data: Array = [source.global_transform, precision, select, target_y,
		clear_low, clear_high, max_slope_deg, min_layer_area, band_tolerance,
		min_obstruction, flatten_slopes]
	for child in source.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		data.append([mesh.get_instance_id(), mesh.global_transform, mesh.is_visible_in_tree()])
	for child in source.find_children("*", "MultiMeshInstance3D", true, false):
		var multi := child as MultiMeshInstance3D
		if multi.multimesh == null or multi.multimesh.mesh == null:
			continue
		data.append([multi.get_instance_id(), multi.global_transform,
			multi.multimesh.instance_count, multi.is_visible_in_tree()])
	return hash(data)


## 收集世界坐标三角形（扁平三元组）。跳过 visual_only 子树。
func _collect_triangles(source: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		# 只看「有没有网格」，不看当前是否在可见链里：派生发生在 _ready，
		# 此时 PlayScope 还没跑完，is_visible_in_tree() 会把整栋楼判成隐藏，
		# 结果一片可走面都生成不出来（实测主场景 rects=0、独立加载却正常）。
		if mesh.mesh == null:
			continue
		if _visual_only(mesh, source):
			continue
		_append_mesh(out, mesh.mesh, mesh.global_transform)
	for multi: MultiMeshInstance3D in source.find_children("*", "MultiMeshInstance3D", true, false):
		if multi.multimesh == null or multi.multimesh.mesh == null:
			continue
		if _visual_only(multi, source):
			continue
		for i in multi.multimesh.instance_count:
			_append_mesh(out, multi.multimesh.mesh,
				multi.global_transform * multi.multimesh.get_instance_transform(i))
	return out


func _visual_only(node: Node, stop: Node) -> bool:
	var cursor := node
	while cursor != null and cursor != stop:
		if cursor.get_meta("visual_only", false):
			return true
		cursor = cursor.get_parent()
	return false


func _append_mesh(out: PackedVector3Array, mesh: Mesh, xf: Transform3D) -> void:
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts == null:
			continue
		var v: PackedVector3Array = verts
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var n := index.size() if index.size() > 0 else v.size()
		var i := 0
		while i + 2 < n:
			out.append(xf * v[index[i] if index.size() > 0 else i])
			out.append(xf * v[index[i + 1] if index.size() > 0 else i + 1])
			out.append(xf * v[index[i + 2] if index.size() > 0 else i + 2])
			i += 3


## band 模式：取目标高度 ± band_tolerance 之内、坡度可走的所有面，
## 输出 surface_triangles。用于双坡种植土面 —— 平面矩形在这里会让角色浮空。
func _build_band(tris: PackedVector3Array) -> void:
	var cos_limit := cos(deg_to_rad(max_slope_deg))
	# target_y 是「相对模型根」的高度（和建模时看到的层高一致），
	# 三角形是世界坐标 —— 必须加上本节点的世界 y 才能比。
	# 这栋楼在主场景里被用户摆到 y=-15.87，不换算的话整片带子取空。
	var target_world := target_y + global_position.y
	var lo := target_world - band_tolerance
	var hi := target_world + band_tolerance
	var kept: PackedVector3Array = PackedVector3Array()
	var area_total := 0.0
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		var normal := (b - a).cross(c - a)
		var length := normal.length()
		if length < 0.0001:
			continue
		if absf(normal.y) / length < cos_limit:
			continue
		var y := (a.y + b.y + c.y) / 3.0
		if y < lo or y > hi:
			continue
		kept.append(a); kept.append(b); kept.append(c)
		area_total += length * 0.5
	if kept.is_empty():
		rects = []
		surface_triangles = PackedVector3Array()
		active = false
		return
	# 先收候选面与它们的格，再只为这些格建遮挡区间表 ——
	# 对整座桥的每个三角形都逐格 append 会让启动卡到十几秒。
	var origin := global_position
	var kept_tris: Array = []
	var cand := {}
	var cells := {}
	var j := 0
	while j + 2 < kept.size():
		var a2 := kept[j]
		var b2 := kept[j + 1]
		var c2 := kept[j + 2]
		j += 3
		kept_tris.append([a2, b2, c2])
		var center := (a2 + b2 + c2) / 3.0
		var key := _cell_of(center)
		cells[key] = true
		if cand.has(key):
			var span: Vector2 = cand[key]
			cand[key] = Vector2(minf(span.x, center.y), maxf(span.y, center.y))
		else:
			cand[key] = Vector2(center.y, center.y)
	var blocked := _blocked_intervals(tris, lo - 2.0, hi + 3.0, cand)
	var usable_tris: PackedVector3Array = PackedVector3Array()
	var usable_cells := {}
	# 每格只留一块：双坡上多条面会重叠（土面 + 菜床底 + 边条），
	# 全留下会让导航烘焙从几百块涨到几万块，启动多花十几秒。
	# 取该格**最低**的可用面 —— 种植土面在最下，菜床和压条在它上面；
	# 若取最高，留下的会是一排菜床顶，人被抬到槽沿上。
	var best_in_cell := {}
	for entry in kept_tris:
		var a3: Vector3 = entry[0]
		var b3: Vector3 = entry[1]
		var c3: Vector3 = entry[2]
		# 按三角形真实覆盖的格填充，不能只用重心那一格 ——
		# 一块跨四格的大三角形只记一格，相邻格就都成了空洞，坡面会碎成几十个孤岛。
		var area2 := (b3.x - a3.x) * (c3.z - a3.z) - (c3.x - a3.x) * (b3.z - a3.z)
		if absf(area2) < 1e-9:
			continue
		var min_x := minf(a3.x, minf(b3.x, c3.x))
		var max_x := maxf(a3.x, maxf(b3.x, c3.x))
		var min_z := minf(a3.z, minf(b3.z, c3.z))
		var max_z := maxf(a3.z, maxf(b3.z, c3.z))
		var c0 := _cell_of(Vector3(min_x, 0.0, min_z))
		var c1 := _cell_of(Vector3(max_x, 0.0, max_z))
		var i0: int = mini(c0.x, c1.x)
		var i1: int = maxi(c0.x, c1.x)
		var j0: int = mini(c0.y, c1.y)
		var j1: int = maxi(c0.y, c1.y)
		if (i1 - i0 + 1) * (j1 - j0 + 1) > 4000:
			continue
		for jj in range(j0, j1 + 1):
			for ii in range(i0, i1 + 1):
				var center_local := Vector3((float(ii) + 0.5) * precision, 0.0,
					(float(jj) + 0.5) * precision)
				var center_world := to_global(center_local)
				var px := center_world.x
				var pz := center_world.z
				var w0 := ((b3.x - px) * (c3.z - pz) - (c3.x - px) * (b3.z - pz)) / area2
				var w1 := ((c3.x - px) * (a3.z - pz) - (a3.x - px) * (c3.z - pz)) / area2
				var w2 := 1.0 - w0 - w1
				if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
					continue
				var key2 := Vector2i(ii, jj)
				var cell_y := a3.y * w0 + b3.y * w1 + c3.y * w2
				if _interval_hit(blocked.get(key2, []), cell_y + clear_low, cell_y + clear_high):
					continue
				if best_in_cell.has(key2):
					var previous: Array = best_in_cell[key2]
					if float(previous[3]) >= cell_y:
						continue
				best_in_cell[key2] = [a3, b3, c3, cell_y]
				usable_cells[key2] = true
	var solid := best_in_cell
	if not flatten_slopes:
		# 精确斜面：已内收过，之后让 GroundSpace 别再腐蚀一遍。
		solid = _erode(best_in_cell)
	derived_layer_area = area_total
	derived_cells = cells.size()
	derived_usable = solid.size()
	if solid.is_empty():
		rects = []
		surface_triangles = PackedVector3Array()
		derived_rects = 0
		active = false
		return
	# surface_y 取可站面高度中位数：只给 hover/pick 一个代表高度。
	var heights: Array = []
	for key4: Vector2i in solid:
		heights.append(float((best_in_cell[key4] as Array)[3]))
	heights.sort()
	derived_surface_y = float(heights[heights.size() / 2]) if not heights.is_empty() else target_world
	surface_y = derived_surface_y
	span_min = lo
	span_max = hi
	if flatten_slopes:
		# 压平：格合并成矩形，交给 GroundSpace 正常腐蚀。
		# 2.5 米宽的带子做成 0.5 米三角片时，精确网格会被 agent_radius 腐蚀成孤岛，
		# 求路直接返回空；矩形没有这个问题。
		rects = _merge(solid)
		surface_triangles = PackedVector3Array()
		derived_rects = rects.size()
		active = true
		return
	# 精确斜面：重建成高度场贴片，相邻格共享顶点，整片坡连成一张网。
	var corner_sum := {}
	for key5: Vector2i in solid:
		var h := float((best_in_cell[key5] as Array)[3])
		for dz in [0, 1]:
			for dx in [0, 1]:
				var corner := Vector2i(key5.x + dx, key5.y + dz)
				if not corner_sum.has(corner):
					corner_sum[corner] = [0.0, 0]
				var acc: Array = corner_sum[corner]
				acc[0] += h
				acc[1] += 1
	var corner_y := {}
	for corner2: Vector2i in corner_sum:
		var acc2: Array = corner_sum[corner2]
		corner_y[corner2] = float(acc2[0]) / float(acc2[1])
	var slope_tris: PackedVector3Array = PackedVector3Array()
	for key6: Vector2i in solid:
		var lx0 := float(key6.x) * precision
		var lz0 := float(key6.y) * precision
		var lx1 := lx0 + precision
		var lz1 := lz0 + precision
		# 角点用局部 XZ + 世界 y：楼体在主场景里带旋转，局部与世界的 XZ 不同轴。
		var p00 := _world_corner(lx0, lz0, float(corner_y[Vector2i(key6.x, key6.y)]))
		var p10 := _world_corner(lx1, lz0, float(corner_y[Vector2i(key6.x + 1, key6.y)]))
		var p11 := _world_corner(lx1, lz1, float(corner_y[Vector2i(key6.x + 1, key6.y + 1)]))
		var p01 := _world_corner(lx0, lz1, float(corner_y[Vector2i(key6.x, key6.y + 1)]))
		slope_tris.append(p00); slope_tris.append(p10); slope_tris.append(p11)
		slope_tris.append(p00); slope_tris.append(p11); slope_tris.append(p01)
	rects = []
	surface_triangles = slope_tris
	derived_rects = 0
	body_radius = 0.0
	active = true


## 遮挡区间表：格 → 该格上方所有几何的高度区间列表。
## 只收 [lo, hi] 里有交集、且落在候选格 `cand` 里的三角形 ——
## 候选格通常只有几百个，这一步把整座桥的三角形挡在外面。
func _blocked_intervals(tris: PackedVector3Array, lo: float, hi: float, cand: Dictionary) -> Dictionary:
	var table := {}
	var origin := global_position
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		var y_min := minf(a.y, minf(b.y, c.y))
		var y_max := maxf(a.y, maxf(b.y, c.y))
		if y_max < lo or y_min > hi:
			continue
		var min_x := minf(a.x, minf(b.x, c.x))
		var max_x := maxf(a.x, maxf(b.x, c.x))
		var min_z := minf(a.z, minf(b.z, c.z))
		var max_z := maxf(a.z, maxf(b.z, c.z))
		var c0 := _cell_of(Vector3(min_x, 0.0, min_z))
		var c1 := _cell_of(Vector3(max_x, 0.0, max_z))
		var i0: int = mini(c0.x, c1.x)
		var i1: int = maxi(c0.x, c1.x)
		var j0: int = mini(c0.y, c1.y)
		var j1: int = maxi(c0.y, c1.y)
		if (i1 - i0 + 1) * (j1 - j0 + 1) > 4000:
			continue
		for j in range(j0, j1 + 1):
			for ii in range(i0, i1 + 1):
				var key := Vector2i(ii, j)
				if not cand.has(key):
					continue
				if not table.has(key):
					table[key] = []
				var list: Array = table[key]
				list.append(Vector2(y_min, y_max))
	return table


## 某格的高度区间里，有没有真正挡人的东西。
##
## 只有「穿过站立带 0.35 米以上」才算遮挡：菜床沿只比土面高 10 厘米，
## 那是可以跨过去的边，不该把整片种植土判成不可站；
## 柜子、墙、天花板穿过大半个人高，必须挡。
func _interval_hit(intervals: Array, lo: float, hi: float) -> bool:
	for interval: Vector2 in intervals:
		var overlap := minf(interval.y, hi) - maxf(interval.x, lo)
		if overlap < min_obstruction:
			continue
		return true
	return false


## 把所有水平面按高度聚成层，按 select 选一层，并把它栅格化。
func _pick_layer(tris: PackedVector3Array) -> Dictionary:
	var cos_limit := cos(deg_to_rad(max_slope_deg))
	var layers := {}
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		var normal := (b - a).cross(c - a)
		var length := normal.length()
		if length < 0.0001:
			continue
		# 只按「离水平多近」筛，不看绕序正负：这批模块的板面绕序不统一
		# （屋顶板多为背面朝上，材质双面渲染）——用有符号 normal.y 会把整片
		# 楼顶判成不可站，只剩女儿墙内侧那点面积。
		if absf(normal.y) / length < cos_limit:
			continue
		var area := length * 0.5
		var key := snappedf((a.y + b.y + c.y) / 3.0, 0.1)
		if not layers.has(key):
			layers[key] = {"y": key, "area": 0.0, "faces": []}
		var layer: Dictionary = layers[key]
		layer.area += area
		(layer.faces as Array).append([a, b, c])
	if layers.is_empty():
		return {}
	var keys: Array = layers.keys()
	keys.sort()
	var chosen: Dictionary = {}
	match select:
		"highest":
			for k in keys:
				if layers[k].area >= min_layer_area:
					chosen = layers[k]
		"nearest":
			var best := INF
			for k in keys:
				if layers[k].area < min_layer_area:
					continue
				var d := absf(float(k) - (target_y + global_position.y))
				if d < best:
					best = d
					chosen = layers[k]
		_:
			var best_area := 0.0
			for k in keys:
				if layers[k].area > best_area:
					best_area = layers[k].area
					chosen = layers[k]
	if chosen.is_empty():
		return {}
	# 把选中层的三角形栅格化成本地格。
	var cells := {}
	var origin := global_position
	for face: Array in chosen.faces:
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var area2 := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		if absf(area2) < 1e-9:
			continue
		var min_x := minf(a.x, minf(b.x, c.x))
		var max_x := maxf(a.x, maxf(b.x, c.x))
		var min_z := minf(a.z, minf(b.z, c.z))
		var max_z := maxf(a.z, maxf(b.z, c.z))
		var c0 := _cell_of(Vector3(min_x, 0.0, min_z))
		var c1 := _cell_of(Vector3(max_x, 0.0, max_z))
		var i0: int = mini(c0.x, c1.x)
		var i1: int = maxi(c0.x, c1.x)
		var j0: int = mini(c0.y, c1.y)
		var j1: int = maxi(c0.y, c1.y)
		if (i1 - i0 + 1) * (j1 - j0 + 1) > 60000:
			continue
		for j in range(j0, j1 + 1):
			for ii in range(i0, i1 + 1):
				var center_world := to_global(Vector3((float(ii) + 0.5) * precision, 0.0,
					(float(j) + 0.5) * precision))
				var px := center_world.x
				var pz := center_world.z
				var w0 := ((b.x - px) * (c.z - pz) - (c.x - px) * (b.z - pz)) / area2
				var w1 := ((c.x - px) * (a.z - pz) - (a.x - px) * (c.z - pz)) / area2
				var w2 := 1.0 - w0 - w1
				if w0 >= -0.001 and w1 >= -0.001 and w2 >= -0.001:
					cells[Vector2i(ii, j)] = true
	if cells.is_empty():
		return {}
	return {"y": chosen.y, "area": chosen.area, "cells": cells}


## 站立净空：把 surface_y 往上一段里的三角形按 XZ 格记成「有遮挡」。
##
## 只记「盖住格中心」的三角形，与栅格化地面同口径 —— 这样半格宽的女儿墙
## 只会挡住自己压到的那一格，不会把整片楼顶判死。
func _blocked_cells(tris: PackedVector3Array, from_y: float) -> Dictionary:
	var blocked := {}
	var origin := global_position
	var lo := from_y
	var hi := from_y + (clear_high - precision)
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		var y_min := minf(a.y, minf(b.y, c.y))
		var y_max := maxf(a.y, maxf(b.y, c.y))
		if y_max < lo or y_min > hi:
			continue
		var area2 := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		if absf(area2) < 1e-9:
			# 竖面/极窄面：退化成线段，按包围盒标记，避免细柱子漏掉。
			_mark_box(blocked, a, b, c, origin, lo, hi)
			continue
		var min_x := minf(a.x, minf(b.x, c.x))
		var max_x := maxf(a.x, maxf(b.x, c.x))
		var min_z := minf(a.z, minf(b.z, c.z))
		var max_z := maxf(a.z, maxf(b.z, c.z))
		var c0 := _cell_of(Vector3(min_x, 0.0, min_z))
		var c1 := _cell_of(Vector3(max_x, 0.0, max_z))
		var i0: int = mini(c0.x, c1.x)
		var i1: int = maxi(c0.x, c1.x)
		var j0: int = mini(c0.y, c1.y)
		var j1: int = maxi(c0.y, c1.y)
		if (i1 - i0 + 1) * (j1 - j0 + 1) > 60000:
			continue
		var hits := false
		for j in range(j0, j1 + 1):
			for ii in range(i0, i1 + 1):
				var center_world := to_global(Vector3((float(ii) + 0.5) * precision, 0.0,
					(float(j) + 0.5) * precision))
				var px := center_world.x
				var pz := center_world.z
				var w0 := ((b.x - px) * (c.z - pz) - (c.x - px) * (b.z - pz)) / area2
				var w1 := ((c.x - px) * (a.z - pz) - (a.x - px) * (c.z - pz)) / area2
				var w2 := 1.0 - w0 - w1
				if w0 >= -0.001 and w1 >= -0.001 and w2 >= -0.001:
					blocked[Vector2i(ii, j)] = true
					hits = true
		if not hits:
			_mark_box(blocked, a, b, c, origin, lo, hi)
	return blocked


## 兜底：三角形没有盖住任何格中心（细柱、栏杆）时按 XZ 包围盒标记，
## 但要宽高都超过一格才标，否则 1 cm 的铆钉也会挡出一整格。
func _mark_box(blocked: Dictionary, a: Vector3, b: Vector3, c: Vector3,
		origin: Vector3, lo: float, hi: float) -> void:
	var min_x := minf(a.x, minf(b.x, c.x))
	var max_x := maxf(a.x, maxf(b.x, c.x))
	var min_z := minf(a.z, minf(b.z, c.z))
	var max_z := maxf(a.z, maxf(b.z, c.z))
	if max_x - min_x < precision and max_z - min_z < precision:
		return
	var c0 := _cell_of(Vector3(min_x, 0.0, min_z))
	var c1 := _cell_of(Vector3(max_x, 0.0, max_z))
	var i0: int = mini(c0.x, c1.x)
	var i1: int = maxi(c0.x, c1.x)
	var j0: int = mini(c0.y, c1.y)
	var j1: int = maxi(c0.y, c1.y)
	if (i1 - i0 + 1) * (j1 - j0 + 1) > 400:
		return
	for j in range(j0, j1 + 1):
		for ii in range(i0, i1 + 1):
			blocked[Vector2i(ii, j)] = true


## 格 → 矩形（按行合并，再纵向吞并同跨度段）。与 BlockerSet 同一套合并逻辑。
func _merge(cells: Dictionary) -> Array:
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
		var runs: Array = []
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
	var out: Array = []
	var open := {}
	for j in js:
		var runs: Array = spans_by_row[j]
		var next_open := {}
		for run: Array in runs:
			var key := Vector2i(run[0], run[1])
			if open.has(key):
				var current: Array = open[key]
				current[1] = j
				next_open[key] = current
			else:
				next_open[key] = [j, j]
		for key: Vector2i in open:
			if not next_open.has(key):
				var current2: Array = open[key]
				out.append(_rect(key.x, key.y, current2[0], current2[1]))
		open = next_open
	for key: Vector2i in open:
		var current3: Array = open[key]
		out.append(_rect(key.x, key.y, current3[0], current3[1]))
	return out


func _rect(i0: int, i1: int, j0: int, j1: int) -> Rect2:
	return Rect2(Vector2(float(i0) * precision, float(mini(j0, j1)) * precision),
		Vector2(float(i1 - i0 + 1) * precision, float(absi(j1 - j0) + 1) * precision))


## 供验证脚本读取的派生摘要。
func report() -> Dictionary:
	return {"area_id": area_id, "surface_y": derived_surface_y, "cells": derived_cells,
		"usable": derived_usable, "layer_area": derived_layer_area,
		"rects": derived_rects, "active": active}
