@tool
extends RefCounted
## 仅负责确定性几何写入；不创建节点、不保存脚本资源。

static func append_tube(points: Array[Vector3], radii: Array[float], sides: int, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	if points.size() < 2: return
	var rings: Array = []
	for point_index in points.size():
		var tangent := _tangent(points, point_index)
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 0.0001: side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var other := side.cross(tangent).normalized()
		var ring: Array[Vector3] = []
		for j in sides:
			var radial := side * cos(TAU * float(j) / sides) + other * sin(TAU * float(j) / sides)
			ring.append(point + radial * radii[point_index])
		rings.append(ring)
	for i in range(points.size() - 1):
		for j in sides:
			var n := (j + 1) % sides
			_append_quad(vertices, normals, indices, rings[i][j], rings[i][n], rings[i + 1][n], rings[i + 1][j],
				(rings[i][j] - points[i]).normalized(), (rings[i][n] - points[i]).normalized(),
				(rings[i + 1][n] - points[i + 1]).normalized(), (rings[i + 1][j] - points[i + 1]).normalized())
	_append_cap(vertices, normals, indices, points[0], rings[0], -(_tangent(points, 0)))
	_append_cap(vertices, normals, indices, points[points.size() - 1], rings[rings.size() - 1], _tangent(points, points.size() - 1))

static func append_leaf(center: Vector3, axis: Vector3, width: float, length: float, thickness: float, shape: String, cluster_center: Vector3, normal_blend: float, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var direction := axis.normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001: side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(direction).normalized()
	var normal := lerp(up, (center - cluster_center).normalized(), normal_blend).normalized()
	var length_steps := 2
	var width_steps := 1
	var top_grid: Array[Vector3] = []
	var bottom_grid: Array[Vector3] = []
	for longitudinal in range(length_steps + 1):
		var t := float(longitudinal) / float(length_steps)
		var profile := _leaf_width_profile(shape, t)
		var centerline := center + direction * length * t
		var crown := sin(PI * t) * thickness
		for across in range(width_steps + 1):
			var u := float(across) / float(width_steps) * 2.0 - 1.0
			var point := centerline + side * width * profile * u
			top_grid.append(point + normal * crown)
			bottom_grid.append(point - normal * crown)
	for longitudinal in length_steps:
		for across in width_steps:
			var row := width_steps + 1
			var a := longitudinal * row + across
			var b := a + 1
			var c := a + row + 1
			var d := a + row
			_append_quad(vertices, normals, indices, top_grid[a], top_grid[b], top_grid[c], top_grid[d], normal, normal, normal, normal)
			_append_quad(vertices, normals, indices, bottom_grid[b], bottom_grid[a], bottom_grid[d], bottom_grid[c], -normal, -normal, -normal, -normal)
	# Narrow rim closes the physical leaf edge and keeps it opaque from grazing views.
	for longitudinal in length_steps:
		var row := width_steps + 1
		for across in [0, width_steps]:
			var a := longitudinal * row + across
			var b := a + row
			_append_quad(vertices, normals, indices, top_grid[a], top_grid[b], bottom_grid[b], bottom_grid[a], side * (-1.0 if across == 0 else 1.0), side * (-1.0 if across == 0 else 1.0), side * (-1.0 if across == 0 else 1.0), side * (-1.0 if across == 0 else 1.0))
	for across in range(width_steps):
		var a := across
		var b := across + 1
		var end_a := length_steps * (width_steps + 1) + across
		var end_b := end_a + 1
		_append_quad(vertices, normals, indices, top_grid[a], top_grid[b], bottom_grid[b], bottom_grid[a], -direction, -direction, -direction, -direction)
		_append_quad(vertices, normals, indices, top_grid[end_b], top_grid[end_a], bottom_grid[end_a], bottom_grid[end_b], direction, direction, direction, direction)

static func _leaf_width_profile(shape: String, t: float) -> float:
	if shape == "triangular": return maxf(0.0, sin(PI * t) * (1.0 - 0.42 * t))
	if shape == "palmate": return maxf(0.0, sin(PI * t) * (0.86 + 0.14 * cos(PI * t * 2.0)))
	return maxf(0.0, pow(sin(PI * t), 0.72))

static func append_moss_patch(center: Vector3, normal: Vector3, width: float, height: float, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var side := normal.cross(Vector3.UP)
	if side.length_squared() < 0.0001: side = normal.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(normal).normalized()
	var a := center - side * width * 0.5
	var b := center + side * width * 0.5
	var c := center + side * width * 0.38 + up * height
	var d := center - side * width * 0.38 + up * height * 0.92
	_append_quad(vertices, normals, indices, a, b, c, d, normal, normal, normal, normal)
	_append_quad(vertices, normals, indices, b, a, d, c, -normal, -normal, -normal, -normal)

static func _tangent(points: Array[Vector3], index: int) -> Vector3:
	if index == 0: return (points[1] - points[0]).normalized()
	if index == points.size() - 1: return (points[index] - points[index - 1]).normalized()
	return (points[index + 1] - points[index - 1]).normalized()

static func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	var base := vertices.size()
	vertices.append(a); vertices.append(b); vertices.append(c); vertices.append(d)
	normals.append(na); normals.append(nb); normals.append(nc); normals.append(nd)
	indices.append(base); indices.append(base + 1); indices.append(base + 2)
	indices.append(base); indices.append(base + 2); indices.append(base + 3)

static func _append_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var base := vertices.size()
	vertices.append(a); vertices.append(b); vertices.append(c)
	normals.append(normal); normals.append(normal); normals.append(normal)
	indices.append(base); indices.append(base + 1); indices.append(base + 2)

static func _append_cap(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, center: Vector3, ring: Array[Vector3], normal: Vector3) -> void:
	for i in ring.size():
		var next := (i + 1) % ring.size()
		_append_triangle(vertices, normals, indices, center, ring[next], ring[i], normal)
