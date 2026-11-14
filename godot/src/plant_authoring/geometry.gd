@tool
extends RefCounted
## 顺时针正面；曲面叶片与苔藓保留连续 UV 岛，全部收进色板单格安全区。

const PALETTE_PATH := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const PALETTE_SIZE := 512.0
const CELL_SIZE := 64.0
const INSET := 8.0

static func cell_uv(cell: int, point: Vector2) -> Vector2:
	var origin := Vector2(float(cell % 8), floor(float(cell) / 8.0)) * CELL_SIZE
	return (origin + Vector2.ONE * INSET + point.clamp(Vector2.ZERO, Vector2.ONE) * (CELL_SIZE - INSET * 2.0)) / PALETTE_SIZE

static func append_tube(points: Array[Vector3], radii: Array[float], sides: int, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, uvs: PackedVector2Array = PackedVector2Array(), cell: int = 13) -> void:
	if points.size() < 2:
		return
	var frames := tube_frames(points)
	for i in range(points.size() - 1):
		for j in sides:
			var a := _ring_point(points, radii, frames, i, j, sides)
			var b := _ring_point(points, radii, frames, i, j + 1, sides)
			var c := _ring_point(points, radii, frames, i + 1, j + 1, sides)
			var d := _ring_point(points, radii, frames, i + 1, j, sides)
			var na := _tube_normal(points, radii, frames, i, j, sides)
			var nb := _tube_normal(points, radii, frames, i, j + 1, sides)
			var nc := _tube_normal(points, radii, frames, i + 1, j + 1, sides)
			var nd := _tube_normal(points, radii, frames, i + 1, j, sides)
			quad(a, b, c, d, na, nb, nc, nd, vertices, normals, indices, uvs, cell)
	for end in [0, points.size() - 1]:
		var normal := tangent(points, end) * (-1.0 if end == 0 else 1.0)
		for j in sides:
			var a := _ring_point(points, radii, frames, end, j, sides)
			var b := _ring_point(points, radii, frames, end, j + 1, sides)
			if end == 0:
				triangle(points[end], b, a, normal, normal, normal, vertices, normals, indices, uvs, cell)
			else:
				triangle(points[end], a, b, normal, normal, normal, vertices, normals, indices, uvs, cell)

static func tube_frames(points: Array[Vector3]) -> Array[Basis]:
	var frames: Array[Basis] = []
	var previous := Vector3.RIGHT
	for i in points.size():
		var forward := tangent(points, i)
		var side := previous - forward * previous.dot(forward)
		if side.length_squared() < 0.00001:
			side = forward.cross(Vector3.FORWARD)
		if side.length_squared() < 0.00001:
			side = forward.cross(Vector3.RIGHT)
		side = side.normalized()
		var other := side.cross(forward).normalized()
		frames.append(Basis(side, other, forward))
		previous = side
	return frames

static func _ring_point(points: Array[Vector3], radii: Array[float], frames: Array[Basis], i: int, j: int, sides: int) -> Vector3:
	var angle := TAU * float(j) / float(sides)
	return points[i] + (frames[i].x * cos(angle) + frames[i].y * sin(angle)) * radii[i]

static func _tube_normal(points: Array[Vector3], radii: Array[float], frames: Array[Basis], i: int, j: int, sides: int) -> Vector3:
	var angle := TAU * float(j) / float(sides)
	var low := maxi(0, i - 1)
	var high := mini(points.size() - 1, i + 1)
	var slope := (radii[high] - radii[low]) / maxf(points[high].distance_to(points[low]), 0.00001)
	return (frames[i].x * cos(angle) + frames[i].y * sin(angle) - frames[i].z * slope).normalized()

# 与实际变径、弯曲、十二边形树皮的三角面逐点对应，供苔藓和藤蔓附着使用。
static func tube_surface(points: Array[Vector3], radii: Array[float], t: float, angle: float, sides: int = 12, frames: Array[Basis] = []) -> Dictionary:
	if frames.is_empty():
		frames = tube_frames(points)
	var scaled := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var i := mini(int(floor(scaled)), points.size() - 2)
	var v := scaled - float(i)
	var sector := fposmod(angle, TAU) / TAU * float(sides)
	var j := int(floor(sector))
	var u := sector - float(j)
	var a := _ring_point(points, radii, frames, i, j, sides)
	var b := _ring_point(points, radii, frames, i, j + 1, sides)
	var c := _ring_point(points, radii, frames, i + 1, j + 1, sides)
	var d := _ring_point(points, radii, frames, i + 1, j, sides)
	var position: Vector3
	var normal: Vector3
	if u >= v:
		position = a * (1.0 - u) + b * (u - v) + c * v
		normal = (c - a).cross(b - a).normalized()
	else:
		position = a * (1.0 - v) + c * u + d * (v - u)
		normal = (d - a).cross(c - a).normalized()
	return {"position": position, "normal": normal}

static func append_moss_on_tube(points: Array[Vector3], radii: Array[float], t: float, height_ratio: float, angle: float, angle_width: float, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, uvs: PackedVector2Array, cell: int) -> void:
	var ring_count := points.size() - 1
	var frames := tube_frames(points)
	var low := clampf(t - height_ratio * 0.5, 0.0, 1.0) * float(ring_count)
	var high := clampf(t + height_ratio * 0.5, 0.0, 1.0) * float(ring_count)
	var left := (angle - angle_width * 0.5) / TAU * 12.0
	var right := (angle + angle_width * 0.5) / TAU * 12.0
	var patch := PackedVector2Array([
		Vector2(left + 0.10, low), Vector2(right - 0.10, low),
		Vector2(right, lerpf(low, high, 0.5)), Vector2(right - 0.10, high),
		Vector2(left + 0.10, high), Vector2(left, lerpf(low, high, 0.5))
	])
	# 在宿主每个真实三角面的参数域裁剪，跨环/棱边不以弦线切入树皮。
	for row in range(int(floor(low)), mini(ring_count, int(ceil(high)))):
		for column in range(int(floor(left)), int(ceil(right))):
			var a := Vector2(column, row)
			var b := Vector2(column + 1, row)
			var c := Vector2(column + 1, row + 1)
			var d := Vector2(column, row + 1)
			for face in [PackedVector2Array([a, b, c]), PackedVector2Array([a, c, d])]:
				var pieces := Geometry2D.intersect_polygons(patch, face)
				for piece: PackedVector2Array in pieces:
					var faces := Geometry2D.triangulate_polygon(piece)
					for index in range(0, faces.size(), 3):
						var ps: Array[Vector3] = []
						var ns: Array[Vector3] = []
						var island := PackedVector2Array()
						# 同一宿主面统一法线偏移，边界采样不误取相邻面的法线。
						var centroid: Vector2 = (face[0] + face[1] + face[2]) / 3.0
						var host := tube_surface(points, radii, centroid.y / float(ring_count), centroid.x / 12.0 * TAU, 12, frames)
						var n: Vector3 = host.normal
						for corner in 3:
							var uv := piece[faces[index + corner]]
							var sample := tube_surface(points, radii, uv.y / float(ring_count), uv.x / 12.0 * TAU, 12, frames)
							ps.append(sample.position + n * 0.002)
							ns.append(n)
							island.append(Vector2((uv.x - left) / (right - left), (uv.y - low) / (high - low)))
						triangle(ps[0], ps[1], ps[2], ns[0], ns[1], ns[2], vertices, normals, indices, uvs, cell, island)

static func leaf_outline(shape: String) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if shape == "palmate":
		# 七枚尖裂片和深谷直接进入边界拓扑，不是椭圆宽度扰动。
		return PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(-0.18, 0.16), Vector2(-0.86, 0.31),
			Vector2(-0.36, 0.39), Vector2(-1.0, 0.78), Vector2(-0.33, 0.59),
			Vector2(-0.52, 1.02), Vector2(-0.14, 0.72), Vector2(0.0, 1.28),
			Vector2(0.14, 0.72), Vector2(0.52, 1.02), Vector2(0.33, 0.59),
			Vector2(1.0, 0.78), Vector2(0.36, 0.39), Vector2(0.86, 0.31),
			Vector2(0.18, 0.16)
		])
	if shape == "triangular":
		outline.append(Vector2(0.0, 0.0))
		outline.append(Vector2(-0.65, 0.18))
		outline.append(Vector2(-0.92, 0.32))
		for i in range(1, 17):
			var t := float(i) / 17.0
			var width := maxf(0.012, (1.0 - t) * 0.92 + (0.055 if i % 2 == 1 else -0.055))
			outline.append(Vector2(-width, 0.32 + t * 0.68))
		outline.append(Vector2(0.0, 1.0))
		for i in range(16, 0, -1):
			var t := float(i) / 17.0
			var width := maxf(0.012, (1.0 - t) * 0.92 + (0.055 if i % 2 == 1 else -0.055))
			outline.append(Vector2(width, 0.32 + t * 0.68))
		outline.append(Vector2(0.92, 0.32))
		outline.append(Vector2(0.65, 0.18))
		return outline
	for i in 24:
		var angle := TAU * float(i) / 24.0
		outline.append(Vector2(sin(angle) * 0.82, (1.0 - cos(angle)) * 0.5))
	return outline

static func append_leaf(center: Vector3, axis: Vector3, width: float, length: float, thickness: float, shape: String, cluster_center: Vector3, normal_blend: float, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, uvs: PackedVector2Array = PackedVector2Array(), cell: int = 28, subdivisions: int = 4, tip: float = 1.0, cup: float = 0.75) -> void:
	var direction := axis.normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.00001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var frame := Basis(side, side.cross(direction).normalized(), direction)
	var outline := leaf_outline(shape)
	var faces := Geometry2D.triangulate_polygon(outline)
	# 两级曲面采样保留中脉/杯曲，禁止对每个轮廓三角形做过量25倍细分。
	var steps := maxi(2, subdivisions)
	var signed_area := 0.0
	for index in outline.size():
		signed_area += outline[index].cross(outline[(index + 1) % outline.size()])
	# 轮廓不同、细分数不同；每个原始三角形铺完整重心网格，逐点采样曲面。
	for face in range(0, faces.size(), 3):
		var a := outline[faces[face]]
		var b := outline[faces[face + 1]]
		var c := outline[faces[face + 2]]
		for row in steps:
			for column in range(steps - row):
				var p := a + (b - a) * float(row) / steps + (c - a) * float(column) / steps
				var q := p + (b - a) / steps
				var r := p + (c - a) / steps
				var tiles := [PackedVector2Array([p, q, r])]
				if row + column < steps - 1:
					tiles.append(PackedVector2Array([q, q + (c - a) / steps, r]))
				for tile: PackedVector2Array in tiles:
					for face_side in [1.0, -1.0]:
						var ps: Array[Vector3] = []
						var ns: Array[Vector3] = []
						var island := PackedVector2Array()
						for point in tile:
							var sample := _leaf_surface(point, frame, width, length, thickness, tip, cup)
							var position: Vector3 = center + sample.position + frame.y * face_side * thickness * 0.06
							var normal: Vector3 = sample.normal * face_side
							var sphere := (position - cluster_center).normalized()
							if sphere.length_squared() < 0.01:
								sphere = normal
							if sphere.dot(normal) < 0.0:
								sphere = -sphere
							ps.append(position)
							ns.append(normal.lerp(sphere, normal_blend).normalized())
							island.append(Vector2(point.x * 0.5 + 0.5, point.y / tip))
						triangle(ps[0], ps[1], ps[2], ns[0], ns[1], ns[2], vertices, normals, indices, uvs, cell, island)
	# 侧边细分与叶肉一致，封闭真实薄厚，不用双面平卡冒充叶片。
	for index in outline.size():
		for segment in steps:
			var first := outline[index].lerp(outline[(index + 1) % outline.size()], float(segment) / steps)
			var last := outline[index].lerp(outline[(index + 1) % outline.size()], float(segment + 1) / steps)
			var a: Vector3 = center + _leaf_surface(first, frame, width, length, thickness, tip, cup).position
			var b: Vector3 = center + _leaf_surface(last, frame, width, length, thickness, tip, cup).position
			var offset := frame.y * thickness * 0.06
			# 顺序沿轮廓向外，深裂谷不使用球心方向判断边法线。
			var edge_normal := (b - a).cross(frame.y).normalized() * signf(signed_area)
			quad(a + offset, b + offset, b - offset, a - offset, edge_normal, edge_normal, edge_normal, edge_normal, vertices, normals, indices, uvs, cell)

static func _leaf_surface(point: Vector2, frame: Basis, width: float, length: float, thickness: float, tip: float, cup: float) -> Dictionary:
	var t := clampf(point.y / tip, 0.0, 1.0)
	var wave := sin(PI * t)
	# 中脉拱曲、横向杯曲和末端回弯；上下表面共享解析法线。
	var dome := thickness * (wave * (1.0 - cup * point.x * point.x) - 0.30 * t * t)
	var dx := -thickness * wave * 2.0 * cup * point.x / width
	var dy := thickness * (PI * cos(PI * t) * (1.0 - cup * point.x * point.x) - 0.60 * t) / (tip * length)
	return {
		"position": frame.x * point.x * width + frame.z * point.y * length + frame.y * dome,
		"normal": (frame.y - frame.x * dx - frame.z * dy).normalized()
	}

static func tangent(points: Array[Vector3], index: int) -> Vector3:
	if index == 0:
		return (points[1] - points[0]).normalized()
	if index == points.size() - 1:
		return (points[index] - points[index - 1]).normalized()
	return (points[index + 1] - points[index - 1]).normalized()

static func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, uvs: PackedVector2Array, cell: int) -> void:
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	normals.append_array(PackedVector3Array([na, nb, nc, nd]))
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		uvs.append(cell_uv(cell, uv))
	if (c - a).cross(b - a).dot(na + nb + nc + nd) < 0.0:
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	else:
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

static func triangle(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, uvs: PackedVector2Array, cell: int, island: PackedVector2Array = PackedVector2Array()) -> void:
	var base := vertices.size()
	var mapped := island if island.size() == 3 else PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)])
	if (c - a).cross(b - a).dot(na + nb + nc) < 0.0:
		vertices.append_array(PackedVector3Array([a, c, b]))
		normals.append_array(PackedVector3Array([na, nc, nb]))
		uvs.append_array(PackedVector2Array([cell_uv(cell, mapped[0]), cell_uv(cell, mapped[2]), cell_uv(cell, mapped[1])]))
	else:
		vertices.append_array(PackedVector3Array([a, b, c]))
		normals.append_array(PackedVector3Array([na, nb, nc]))
		uvs.append_array(PackedVector2Array([cell_uv(cell, mapped[0]), cell_uv(cell, mapped[1]), cell_uv(cell, mapped[2])]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
