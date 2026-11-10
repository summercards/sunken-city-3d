extends RefCounted
## Derive waterline contours from visible scene triangles, including MultiMeshes.
## A distance atlas is geometry data; all wave shape, motion and shading live in GLSL.
const RESOLUTION := 1536
const CACHE_ALGORITHM_VERSION := "shore-distance-edt-v1"
const CACHE_FORMAT_VERSION := 1
const CACHE_MAGIC := "SHRCACHE1"
const CACHE_SLOT_FILE := "shore_distance.slot"
const CACHE_MAX_PAYLOAD_BYTES := 20 * 1024 * 1024
var segments: Array[Vector4] = []
var _segment_scale := PackedFloat32Array()
var _nearest := PackedInt32Array()
var bounds := Rect2()
var texture: ImageTexture
var _triangles: Dictionary = {}
var _level := 1.12
var _region := Rect2()
var _field := PackedFloat32Array()
var cache_enabled := true
var cache_directory := "user://shore_distance_cache"
var metrics := {"cache_hit": false, "build_ms": 0.0, "edt_ms": 0.0}
# 全进程只保留一个有上限的原始图条目；不按地图/几何建立大图字典。
static var _process_cache_key := ""
static var _process_cache_directory := ""
static var _process_cache_bytes := PackedByteArray()

func rebuild(roots: Array, level: float, resolution := RESOLUTION, region := Rect2(), outline_rects: Array = []) -> void:
	var started := Time.get_ticks_usec()
	metrics = {"cache_hit": false, "build_ms": 0.0, "edt_ms": 0.0}
	segments.clear()
	_segment_scale.clear()
	_triangles.clear()
	_level = level
	# 漂浮在水面上方的结构（甲板底面高出水面几厘米）切不出几何截面：
	# 竖直方向没有任何一个面跨过水面，于是整块东西一点白沫都没有。
	# 它们改成「把占地轮廓的**外沿**当作种子线段」——距线图本来就是无符号距离场，
	# 播种后内部点离最近边线远、外圈贴一圈，与几何截面出来的效果一致。
	_append_outline_union(outline_rects)
	_region = region
	for node in roots: _visit(node)
	if segments.is_empty():
		bounds = Rect2(-1, -1, 2, 2)
	else:
		bounds = Rect2(Vector2(segments[0].x, segments[0].y), Vector2.ZERO)
		for s in segments:
			bounds = bounds.expand(Vector2(s.x, s.y)).expand(Vector2(s.z, s.w))
		bounds = bounds.grow(6.0)
	if region.has_area(): bounds = region
	# Square pixels keep the Euclidean transform isotropic.
	var span := maxf(bounds.size.x, bounds.size.y)
	bounds = Rect2(bounds.get_center() - Vector2.ONE * span * 0.5, Vector2.ONE * span)
	var cell := span / float(resolution - 1)
	var cache_key := _make_cache_key(resolution, outline_rects) if cache_enabled else ""
	if cache_enabled:
		if cache_key == _process_cache_key and cache_directory == _process_cache_directory and not _process_cache_bytes.is_empty() and _load_payload(_process_cache_bytes, resolution):
			metrics.cache_hit = true
		else:
			var disk_payload := _read_cache(cache_key, resolution)
			if not disk_payload.is_empty() and _load_payload(disk_payload, resolution):
				_process_cache_key = cache_key
				_process_cache_directory = cache_directory
				_process_cache_bytes = disk_payload
				metrics.cache_hit = true
		if metrics.cache_hit:
			metrics.build_ms = float(Time.get_ticks_usec() - started) / 1000.0
			_triangles.clear()
			print("[shore-atlas] resolution=", resolution, " cache_hit=1 build_ms=", metrics.build_ms, " edt_ms=0.0")
			return
	_field.resize(resolution * resolution)
	_field.fill(1.0e12)
	var scales := PackedFloat32Array()
	scales.resize(resolution * resolution)
	for segment_index in segments.size():
		var s := segments[segment_index]
		var a := (Vector2(s.x, s.y) - bounds.position) / cell
		var b := (Vector2(s.z, s.w) - bounds.position) / cell
		var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
		for i in steps + 1:
			var p := a.lerp(b, float(i) / steps)
			if p.x < 0 or p.y < 0 or p.x >= resolution or p.y >= resolution: continue
			var x := clampi(roundi(p.x), 0, resolution - 1)
			var y := clampi(roundi(p.y), 0, resolution - 1)
			_field[y * resolution + x] = 0.0
			scales[y * resolution + x] = maxf(scales[y * resolution + x], _segment_scale[segment_index])
	var line := PackedFloat32Array()
	line.resize(resolution)
	var scale_line := PackedFloat32Array()
	scale_line.resize(resolution)
	var edt_started := Time.get_ticks_usec()
	for y in resolution:
		for x in resolution:
			line[x] = _field[y * resolution + x]
			scale_line[x] = scales[y * resolution + x]
		var result := _edt(line)
		for x in resolution:
			_field[y * resolution + x] = result[x]
			scales[y * resolution + x] = scale_line[_nearest[x]]
	for x in resolution:
		for y in resolution:
			line[y] = _field[y * resolution + x]
			scale_line[y] = scales[y * resolution + x]
		var result := _edt(line)
		for y in resolution:
			_field[y * resolution + x] = minf(sqrt(result[y]) * cell, 100.0)
			scales[y * resolution + x] = scale_line[_nearest[y]]
	metrics.edt_ms = float(Time.get_ticks_usec() - edt_started) / 1000.0
	var pixels := PackedFloat32Array()
	pixels.resize(resolution * resolution * 2)
	for i in _field.size():
		pixels[i * 2] = _field[i]
		pixels[i * 2 + 1] = scales[i]
	var image_bytes := pixels.to_byte_array()
	_set_image(image_bytes, resolution)
	if cache_enabled and image_bytes.size() <= CACHE_MAX_PAYLOAD_BYTES:
		_process_cache_key = cache_key
		_process_cache_directory = cache_directory
		_process_cache_bytes = image_bytes
		_write_cache(cache_key, resolution, image_bytes)
	metrics.build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	print("[shore-atlas] resolution=", resolution, " cache_hit=0 build_ms=", metrics.build_ms, " edt_ms=", metrics.edt_ms)
	_triangles.clear()


func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()

func _make_cache_key(resolution: int, outline_rects: Array) -> String:
	# Variant 编码保留输入精度、类型、长度和顺序；不得量化水位或排序线段。
	# transform/visibility/mesh/MultiMesh 的有效影响已由本次重新提取的线段与尺度承接。
	return _sha256(var_to_bytes([CACHE_ALGORITHM_VERSION, CACHE_FORMAT_VERSION,
		Engine.get_version_info().string, Image.FORMAT_RGF, false,
		segments, _segment_scale, bounds, _level, resolution, _region, outline_rects])).hex_encode()

func _cache_file_path() -> String:
	# 只写派生缓存专用文件，不允许越过 user:// 或指向项目资源。
	if not cache_directory.begins_with("user://") or cache_directory.contains("..") or cache_directory.contains("\\"):
		return ""
	return cache_directory.path_join(CACHE_SLOT_FILE)

func _read_cache(cache_key: String, resolution: int) -> PackedByteArray:
	var expected := resolution * resolution * 8
	var path := _cache_file_path()
	if expected <= 0 or expected > CACHE_MAX_PAYLOAD_BYTES or path.is_empty() or not FileAccess.file_exists(path): return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return PackedByteArray()
	# 固定头：magic、版本、宽、高、Image 格式、mipmaps、长度、内容 key、payload SHA-256。
	var header_size := CACHE_MAGIC.length() + 5 * 4 + 8 + 32 + 32
	if file.get_length() != header_size + expected: return PackedByteArray()
	if file.get_buffer(CACHE_MAGIC.length()) != CACHE_MAGIC.to_utf8_buffer(): return PackedByteArray()
	if file.get_32() != CACHE_FORMAT_VERSION or file.get_32() != resolution or file.get_32() != resolution: return PackedByteArray()
	if file.get_32() != Image.FORMAT_RGF or file.get_32() != 0 or file.get_64() != expected: return PackedByteArray()
	if file.get_buffer(32).hex_encode() != cache_key: return PackedByteArray()
	var payload_digest := file.get_buffer(32)
	var payload := file.get_buffer(expected)
	if payload.size() != expected or _sha256(payload) != payload_digest: return PackedByteArray()
	return payload

func _load_payload(payload: PackedByteArray, resolution: int) -> bool:
	if payload.size() != resolution * resolution * 8 or payload.size() > CACHE_MAX_PAYLOAD_BYTES: return false
	var pixels := payload.to_float32_array()
	if pixels.size() != resolution * resolution * 2: return false
	_field.resize(resolution * resolution)
	for i in _field.size(): _field[i] = pixels[i * 2]
	_set_image(payload, resolution)
	return texture != null

func _set_image(payload: PackedByteArray, resolution: int) -> void:
	var image := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGF, payload)
	texture = ImageTexture.create_from_image(image)

func _write_cache(cache_key: String, resolution: int, payload: PackedByteArray) -> void:
	var path := _cache_file_path()
	if path.is_empty() or payload.size() != resolution * resolution * 8 or payload.size() > CACHE_MAX_PAYLOAD_BYTES: return
	var dir_path := cache_directory
	if FileAccess.file_exists(dir_path) or FileAccess.file_exists(dir_path.get_base_dir()): return
	var make_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	if make_error != OK and make_error != ERR_ALREADY_EXISTS: return
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null: return
	file.store_buffer(CACHE_MAGIC.to_utf8_buffer())
	file.store_32(CACHE_FORMAT_VERSION)
	file.store_32(resolution)
	file.store_32(resolution)
	file.store_32(Image.FORMAT_RGF)
	file.store_32(0)
	file.store_64(payload.size())
	file.store_buffer(cache_key.hex_decode())
	file.store_buffer(_sha256(payload))
	file.store_buffer(payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return
	# 固定临时文件；中断/写失败保留旧 slot，下次读取仍须完整校验，不删除任何文件。
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))

## 把一组占地矩形的**外轮廓**边作为距离场种子。
##
## 直接逐块播种会把每块的四条边都算进去：并集内部那些接缝外一圈全是「贴边」，
## 泡沫就会像棋盘一样铺满整块甲板。这里只保留「另一侧没有别人」的边 ——
## 也就是真实的并集外沿。27 块矩形、每块 4 条边，代价可以忽略。
func _append_outline_union(rects: Array) -> void:
	if rects.is_empty(): return
	var scale := 0.8
	var whole := Rect2()
	var first := true
	for raw: Rect2 in rects:
		if not raw.has_area(): continue
		whole = raw if first else whole.merge(raw)
		first = false
	if not whole.has_area(): return
	scale = clampf(maxf(whole.size.x, whole.size.y) * 0.05, 0.12, 1.0)
	for index in rects.size():
		var area: Rect2 = rects[index]
		if not area.has_area(): continue
		var p := area.position
		var e := area.end
		# [起点, 终点, 内侧法线]
		var edges := [
			[p, Vector2(e.x, p.y), Vector2(0.0, 1.0)],
			[Vector2(e.x, p.y), e, Vector2(-1.0, 0.0)],
			[e, Vector2(p.x, e.y), Vector2(0.0, -1.0)],
			[Vector2(p.x, e.y), p, Vector2(1.0, 0.0)],
		]
		for edge: Array in edges:
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			# 内侧法线往里挪 6 厘米取样：压到别人身上说明这条边在并集内部。
			var mid := (a + b) * 0.5 - (edge[2] as Vector2) * 0.06
			var covered := false
			for other_index in rects.size():
				if other_index == index: continue
				var other: Rect2 = rects[other_index]
				if other.grow(-0.01).has_point(mid): covered = true; break
			if covered: continue
			segments.append(Vector4(a.x, a.y, b.x, b.y))
			_segment_scale.append(scale)


func bind(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("shore_distance", texture)
	mat.set_shader_parameter("shore_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	mat.set_shader_parameter("shore_texel", 1.0 / texture.get_width())
	mat.set_shader_parameter("shore_enabled", not segments.is_empty())

func distance_at(p: Vector2) -> float:
	if not bounds.has_point(p): return 100.0
	var n := texture.get_width()
	var uv := (p - bounds.position) / bounds.size
	var x := clampi(roundi(uv.x * (n - 1)), 0, n - 1)
	var y := clampi(roundi(uv.y * (n - 1)), 0, n - 1)
	return _field[y * n + x]

func _visit(node: Node) -> void:
	if node.get_meta("visual_only", false): return
	if node is Node3D and not node.is_visible_in_tree(): return
	if node is MeshInstance3D and node.mesh != null:
		_slice(node.mesh, node.global_transform)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var mm: MultiMesh = node.multimesh
		if mm.mesh != null:
			var count := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
			for i in count: _slice(mm.mesh, node.global_transform * _multimesh_instance_transform(mm, i))
	for child in node.get_children(): _visit(child)

func _multimesh_instance_transform(mm: MultiMesh, index: int) -> Transform3D:
	return mm.get_instance_transform(index)

func _slice(mesh: Mesh, transform: Transform3D) -> void:
	var box: AABB = transform * mesh.get_aabb()
	if box.position.y > _level or box.end.y < _level: return
	# Thin surface decoration, leaves and fish must not seed broad shoreline surf.
	# Their actual water contact remains visible through screen-depth shading.
	# 0.22 m lets floating decks and seawalls register (they are only ~0.3 m
	# thick); leaves, trim and foam tubes are far thinner and stay out.
	if box.size.y < 0.22: return
	if _region.has_area() and not _region.intersects(Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))): return
	var id := mesh.get_instance_id()
	if not _triangles.has(id):
		var faces := PackedVector3Array()
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty(): faces.append_array(vertices)
			else:
				for index in indices: faces.append(vertices[index])
		_triangles[id] = _components(faces)
	# GLB detail meshes merge unrelated props into one surface. Treat connected
	# solids separately so a leaf/old decorative foam tube cannot emit island surf.
	for component in _triangles[id]:
		var part_box: AABB = transform * component.box
		if part_box.size.y < 0.22 or part_box.position.y > _level or part_box.end.y < _level: continue
		var faces: PackedVector3Array = component.faces
		for i in range(0, faces.size() - 2, 3):
			var a := transform * faces[i]
			var b := transform * faces[i + 1]
			var c := transform * faces[i + 2]
			if minf(a.y, minf(b.y, c.y)) > _level or maxf(a.y, maxf(b.y, c.y)) < _level: continue
			var hits := PackedVector2Array()
			_intersect(a, b, hits)
			_intersect(b, c, hits)
			_intersect(c, a, hits)
			if hits.size() == 2 and hits[0].distance_squared_to(hits[1]) > 0.000001:
				segments.append(Vector4(hits[0].x, hits[0].y, hits[1].x, hits[1].y))
				_segment_scale.append(clampf(maxf(part_box.size.x, part_box.size.z) * 0.32, 0.12, 1.0))

func _components(faces: PackedVector3Array) -> Array:
	var ids: Dictionary = {}
	var parents := PackedInt32Array()
	var face_ids := PackedInt32Array()
	face_ids.resize(faces.size())
	for i in faces.size():
		var key := faces[i].snapped(Vector3.ONE * 0.0001)
		if not ids.has(key):
			ids[key] = parents.size()
			parents.append(parents.size())
		face_ids[i] = ids[key]
	for i in range(0, faces.size() - 2, 3):
		var a := _root(parents, face_ids[i])
		for j in [1, 2]:
			var b := _root(parents, face_ids[i + j])
			if a != b: parents[b] = a
	var groups: Dictionary = {}
	for i in range(0, faces.size() - 2, 3):
		var key := _root(parents, face_ids[i])
		if not groups.has(key): groups[key] = {"faces": PackedVector3Array(), "box": AABB(faces[i], Vector3.ZERO)}
		var group: Dictionary = groups[key]
		var points: PackedVector3Array = group.faces
		var box: AABB = group.box
		for j in 3:
			points.append(faces[i + j])
			box = box.expand(faces[i + j])
		group.faces = points
		group.box = box
	return groups.values()

func _root(parents: PackedInt32Array, index: int) -> int:
	var current := index
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current

func _intersect(a: Vector3, b: Vector3, hits: PackedVector2Array) -> void:
	if (a.y <= _level and b.y > _level) or (b.y <= _level and a.y > _level):
		var p := a.lerp(b, (_level - a.y) / (b.y - a.y))
		hits.append(Vector2(p.x, p.z))

# Exact squared Euclidean distance transform of raster seeds, O(n) per scanline.
func _edt(f: PackedFloat32Array) -> PackedFloat32Array:
	var n := f.size()
	var v := PackedInt32Array()
	var z := PackedFloat64Array()
	var d := PackedFloat32Array()
	v.resize(n)
	z.resize(n + 1)
	d.resize(n)
	_nearest.resize(n)
	var k := 0
	v[0] = 0
	z[0] = -INF
	z[1] = INF
	for q in range(1, n):
		var s := ((float(f[q]) + float(q * q)) - (float(f[v[k]]) + float(v[k] * v[k]))) / (2.0 * (q - v[k]))
		while s <= z[k]:
			k -= 1
			s = ((float(f[q]) + float(q * q)) - (float(f[v[k]]) + float(v[k] * v[k]))) / (2.0 * (q - v[k]))
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INF
	k = 0
	for q in n:
		while z[k + 1] < q: k += 1
		d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]
		_nearest[q] = v[k]
	return d
