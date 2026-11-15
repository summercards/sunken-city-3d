@tool
extends RefCounted
## 低模叶团与四三角弯折叶卡；不持有随机状态或公共资源副本。

const Geometry = preload("res://src/plant_authoring/geometry.gd")
const ATLAS_PATH := "res://assets/textures/vegetation/workshop_leaf_atlas_512.png"
const CLUSTER_ATLAS_PATH := "res://assets/textures/vegetation/workshop_leaf_clusters_512.png"
const ATLAS_TILES := {"camphor": Vector2(0, 0), "maple": Vector2(1, 0), "birch": Vector2(0, 1), "vine": Vector2(1, 1)}

static func append_card(buffer: Dictionary, base: Vector3, axis: Vector3, width: float, length: float, species: String, cell: int, cluster: Vector3, normal_blend: float, facing: Vector3 = Vector3.ZERO, side_axis: Vector3 = Vector3.ZERO) -> void:
	var forward := axis.normalized()
	var side := side_axis - forward * side_axis.dot(forward)
	if side.length_squared() < 0.00001 and facing.length_squared() > 0.00001:
		side = forward.cross(facing)
	if side.length_squared() < 0.00001:
		side = forward.cross(Vector3.UP)
	if side.length_squared() < 0.00001:
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	var normal := side.cross(forward).normalized()
	if facing.length_squared() > 0.00001 and normal.dot(facing) < 0.0:
		side = -side
		normal = -normal
	var first: int = buffer.v.size()
	var tile: Vector2 = ATLAS_TILES[species]
	# 根在下中、尖朝上；中线轻弯，不再添加逐叶圆柱叶柄。
	for row in 3:
		var t := float(row) * 0.5
		for column in 2:
			var point := base + forward * length * t + side * width * (float(column) - 0.5) + normal * sin(t * PI) * length * 0.07
			var spherical := (point - cluster).normalized()
			if spherical.length_squared() < 0.01:
				spherical = normal
			if spherical.dot(normal) < 0.0:
				spherical = -spherical
			var blended := normal.lerp(spherical, normal_blend)
			buffer.v.append(point)
			buffer.n.append(blended.normalized() if blended.length_squared() > 0.00001 else normal)
			var uv := Vector2(float(column), 1.0 - t)
			buffer.uv.append(Geometry.cell_uv(cell, uv))
			# 有效轮廓规范到像素 8..247，采样其像素中心；根映射到 base。
			buffer.uv2.append((tile * 256.0 + Vector2.ONE * 8.5 + uv * 239.0) / 512.0)
			buffer.colors.append(Color(smoothstep(0.0, 1.0, t), 0.0, 1.0, 1.0))
	for row in 2:
		var a := first + row * 2
		buffer.i.append_array(PackedInt32Array([a, a + 3, a + 1, a, a + 2, a + 3]))

static func card_size(shape: String, width: float, length: float) -> Vector2:
	var outline := Geometry.leaf_outline(shape)
	var low := outline[0]
	var high := outline[0]
	for point in outline:
		low = low.min(point)
		high = high.max(point)
	return (high - low) * Vector2(width, length)

static func append_petiole(buffer: Dictionary, base: Vector3, center: Vector3, cell: int) -> void:
	var direction := center - base
	if direction.length_squared() < 0.00000001:
		return
	var side := direction.normalized().cross(Vector3.UP)
	if side.length_squared() < 0.00001:
		side = direction.normalized().cross(Vector3.RIGHT)
	side = side.normalized() * 0.004
	var normal := side.cross(direction).normalized()
	var first: int = buffer.v.size()
	Geometry.quad(base - side, base + side, center + side * 0.65, center - side * 0.65, normal, normal, normal, normal, buffer.v, buffer.n, buffer.i, buffer.uv, cell)
	for vertex in range(first, buffer.v.size()):
		buffer.uv2.append(Vector2(-1, -1))
		buffer.colors.append(Color(0, 0, 1, 1))

static func _volume_points() -> Array[Vector3]:
	var points: Array[Vector3] = [Vector3(0, -1, 0)]
	for ring in 2:
		for side in 6:
			var angle := float(side) * TAU / 6.0
			points.append(Vector3(cos(angle) * 0.91, -0.42 if ring == 0 else 0.42, sin(angle) * 0.91))
	points.append(Vector3(0, 1, 0))
	return points

static func _volume_faces() -> Array[Vector3i]:
	var faces: Array[Vector3i] = []
	for side in 6:
		var next := (side + 1) % 6
		faces.append(Vector3i(0, 1 + side, 1 + next))
		faces.append(Vector3i(1 + side, 7 + side, 7 + next))
		faces.append(Vector3i(1 + side, 7 + next, 1 + next))
		faces.append(Vector3i(13, 7 + next, 7 + side))
	return faces

static func volume_shell(direction: Vector3, radii: Vector3) -> Vector3:
	# 与实际 24 面凸体求射线交点，不把椭球面误当作低模表面而让叶根悬空。
	var points := _volume_points()
	var distance := INF
	for face in _volume_faces():
		var a := points[face.x] * radii
		var b := points[face.y] * radii
		var c := points[face.z] * radii
		var normal := (c - a).cross(b - a).normalized()
		if normal.dot(a) < 0.0:
			normal = -normal
		var denominator := normal.dot(direction)
		if denominator > 0.00001:
			distance = minf(distance, normal.dot(a) / denominator)
	return direction * distance

static func append_volume(buffer: Dictionary, center: Vector3, radii: Vector3, cell: int, normal_blend: float, shade: float = 1.0) -> void:
	# 两圈六边形加上下极点：闭合 24 面，不是高细分球体。
	var points := _volume_points()
	for face in _volume_faces():
		var a := center + points[face.x] * radii
		var b := center + points[face.y] * radii
		var c := center + points[face.z] * radii
		var normal := (c - a).cross(b - a).normalized()
		if normal.dot((a + b + c) / 3.0 - center) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		var start: int = buffer.v.size()
		Geometry.triangle(a, b, c, normal, normal, normal, buffer.v, buffer.n, buffer.i, buffer.uv, cell)
		for vertex in range(start, buffer.v.size()):
			var relative: Vector3 = buffer.v[vertex] - center
			var smooth := (relative / (radii * radii)).normalized()
			buffer.n[vertex] = normal.lerp(smooth, normal_blend).normalized()
			buffer.uv2.append(Vector2(-1, -1))
			buffer.colors.append(Color(0.25 + 0.45 * clampf((relative.y / radii.y + 1.0) * 0.5, 0.0, 1.0), 0.0, shade, 1.0))
