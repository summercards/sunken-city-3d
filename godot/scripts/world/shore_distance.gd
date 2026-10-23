extends RefCounted
## Derive waterline contours from visible scene triangles, including MultiMeshes.
## A distance atlas is geometry data; all wave shape, motion and shading live in GLSL.
const RESOLUTION := 1536
var segments: Array[Vector4] = []
var _segment_scale := PackedFloat32Array()
var _nearest := PackedInt32Array()
var bounds := Rect2()
var texture: ImageTexture
var _triangles: Dictionary = {}
var _level := 1.12
var _region := Rect2()
var _field := PackedFloat32Array()

func rebuild(roots: Array, level: float, resolution := RESOLUTION, region := Rect2()) -> void:
	var started := Time.get_ticks_msec()
	segments.clear()
	_segment_scale.clear()
	_triangles.clear()
	_level = level
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
	var pixels := PackedFloat32Array()
	pixels.resize(resolution * resolution * 2)
	for i in _field.size():
		pixels[i * 2] = _field[i]
		pixels[i * 2 + 1] = scales[i]
	var img := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGF, pixels.to_byte_array())
	texture = ImageTexture.create_from_image(img)
	print("[shore-atlas] resolution=",resolution," build_ms=",Time.get_ticks_msec()-started)
	_triangles.clear()

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
	if node is Node3D and not node.is_visible_in_tree(): return
	if node is MeshInstance3D and node.mesh != null:
		_slice(node.mesh, node.global_transform)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var mm: MultiMesh = node.multimesh
		if mm.mesh != null:
			var count := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
			for i in count: _slice(mm.mesh, node.global_transform * mm.get_instance_transform(i))
	for child in node.get_children(): _visit(child)

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
