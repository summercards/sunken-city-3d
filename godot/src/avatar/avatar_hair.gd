extends RefCounted
## Sculpt the hairline, crown and lengths on one indexed surface. Tied styles
## replace a patch of the crown with a sweep that shares its boundary vertices.
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const SKULL := Vector3(0.258, 0.25, 0.253)
const SECTORS := 84
const ROWS := 16
const TAIL_STEPS := 16

class Lock:
	var root: Vector2
	var axis: Vector2
	var length: float
	var bend: float
	var wave: float
	var width: float
	var lift: float

	func _init(from: Vector2, to: Vector2, arc: float, curl: float, half_width: float, height: float) -> void:
		root = from
		var span := to - from
		length = span.length()
		axis = span / length
		bend = arc
		wave = curl
		width = half_width
		lift = height

var _vertices := PackedVector3Array()
var _indices := PackedInt32Array()
var _shades := PackedColorArray()
var _patch_rings: Array[PackedInt32Array] = []
var _report: Dictionary = {}
var _style := ""
var _fringe := ""
var _covered := false
var _volume := 0.5
var _length := 0.5
var _sweep := 0.0
var _tie_center := Vector3.ZERO
var _tie_tangent := Vector3.BACK
var _tie_radius := 0.0

func build(parent: Node3D, appearance: Dictionary, morphs: Dictionary) -> void:
	_style = str(appearance.get("hair_style", "crop"))
	_fringe = str(appearance.get("fringe", "auto"))
	if _fringe == "auto":
		_fringe = "straight"
		if _style in ["crop", "undercut", "pixie", "bun", "high_ponytail"]:
			_fringe = "open"
		elif _style in ["side", "wave", "low_ponytail", "long"]:
			_fringe = "side"
	_covered = str(appearance.get("hat", "none")) != "none"
	_volume = clampf(float(morphs.get("hair_volume", 0.5)), 0.0, 1.0)
	_length = clampf(float(morphs.get("hair_length", 0.5)), 0.0, 1.0)
	_sweep = clampf(float(morphs.get("hair_sweep", 0.5)), 0.0, 1.0) * 2.0 - 1.0
	_tie_center = Vector3.ZERO
	_tie_radius = 0.0
	_report = {"style": _style, "covered_by_hat": _covered, "zones": {}, "tail_anchors": [],
		"native_skull_radii": [SKULL.x, SKULL.y, SKULL.z], "eye_clearance_floor_y": 0.095}

	var root := Node3D.new()
	root.name = "Hair"
	parent.add_child(root)
	var patches := _attachments()
	_begin_surface()
	_cap(patches)
	for patch in patches:
		_attachment(patch)
	var scalp := _emit(root, "Scalp", Catalog.color(appearance, "hair_color"), "scalp")
	var bounds := scalp.get_aabb()
	var minimum := INF
	var lower_front := -INF
	for p in _vertices:
		minimum = minf(minimum, (p / SKULL).length_squared())
		if p.y < -0.20:
			lower_front = maxf(lower_front, p.z)
	_report.bounds_min = _components(bounds.position)
	_report.bounds_max = _components(bounds.end)
	_report.minimum_skull_q = minimum
	_report.lower_hair_front_z = lower_front if is_finite(lower_front) else null
	var accessory := str(appearance.get("hair_accessory", "none"))
	if accessory != "none":
		_accessory(root, accessory)
	root.set_meta("avatar_hair_metrics", _report.duplicate(true))

func metrics() -> Dictionary:
	return _report.duplicate(true)

func _attachments() -> Array[Rect2i]:
	const REAR := SECTORS / 2
	if _style in ["ponytail", "high_ponytail", "low_ponytail", "braid"]:
		var row := 8
		if _style == "high_ponytail" and not _covered:
			row = 4
		elif _style == "low_ponytail":
			row = 11
		return [Rect2i(REAR - 4, row, 8, 3)]
	if not _covered:
		if _style == "bun":
			return [Rect2i(REAR - 6, 3, 12, 4)]
		if _style == "twin":
			return [Rect2i(REAR - 16, 5, 8, 4), Rect2i(REAR + 8, 5, 8, 4)]
	return []

func _begin_surface() -> void:
	_vertices = PackedVector3Array()
	_indices = PackedInt32Array()
	_shades = PackedColorArray()

func _components(point: Vector3) -> Array[float]:
	return [point.x, point.y, point.z]

func _vertex(point: Vector3, shade: float) -> int:
	var index := _vertices.size()
	_vertices.append(point)
	_shades.append(Color(shade, shade, shade))
	return index

func _quad(a: int, b: int, c: int, d: int) -> void:
	_indices.append_array([a, b, c, a, c, d])

func _emit(parent: Node3D, id: String, color: Color, zone: String) -> MeshInstance3D:
	var normals := PackedVector3Array()
	normals.resize(_vertices.size())
	for i in range(0, _indices.size(), 3):
		var a := _indices[i]
		var b := _indices[i + 1]
		var c := _indices[i + 2]
		var normal := (_vertices[c] - _vertices[a]).cross(_vertices[b] - _vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in normals.size():
		normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = _shades
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = color.lightened(0.12) if zone == "scalp" else color
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.84
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.rim_enabled = true
	material.rim = 0.16
	material.rim_tint = 0.40
	if zone == "scalp" and _style in ["bob", "wave", "long"]:
		# The underside of the free-hanging curtain is visible from the front.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = material
	node.set_meta("avatar_part", "hair")
	node.set_meta("hair_zone", zone)
	parent.add_child(node)
	var bounds := mesh.get_aabb()
	_report.zones[zone] = {"meshes": 1, "vertices": _vertices.size(), "triangles": _indices.size() / 3,
		"bounds_min": _components(bounds.position), "bounds_max": _components(bounds.end)}
	return node

# The disk unwraps from the crown (0) to the hairline (1). Each guide has its
# own root, cross-section and free end. Strip relief and color use the same
# coordinates so painted highlights follow the modeled locks.
func _direction(theta: float) -> Vector2:
	return Vector2(sin(theta), cos(theta))

func _guides(patches: Array[Rect2i]) -> Array[Lock]:
	var guides: Array[Lock] = []
	var sweep := _sweep * 0.12
	if not patches.is_empty():
		for patch in patches:
			var gather := _direction(TAU * patch.get_center().x / SECTORS) * (float(patch.get_center().y) / ROWS)
			for i in (12 if patches.size() == 1 else 8):
				var theta := TAU * (i + 0.35) / (12.0 if patches.size() == 1 else 8.0)
				var edge := _direction(theta)
				if patches.size() == 2 and edge.x * gather.x < -0.08:
					continue
				guides.append(Lock.new(edge * 1.10, gather, 0.066 * sin(theta * 1.8) + sweep, 0.0, 0.138, 0.023))
	elif _style == "curly":
		for i in 13:
			var theta := TAU * (i + 0.5) / 13.0
			var root := _direction(theta + 0.40 + sweep) * (0.12 + 0.07 * sin(i * 2.4))
			var tip := _direction(theta + 0.15 * sin(i * 2.2)) * (1.04 + 0.08 * sin(i * 1.9))
			guides.append(Lock.new(root, tip, 0.15 + 0.07 * cos(i * 2.4), 0.08, 0.25, 0.052))
	else:
		var loose := _style in ["bob", "wave", "long"]
		var nape := Vector2(0.12 + sweep, -0.17)
		for i in 10:
			var theta := lerpf(1.18, TAU - 1.17, i / 9.0)
			var root := nape.lerp(_direction(theta) * 0.43, 0.41)
			var arc := (0.12 if loose else 0.18) + 0.033 * sin(i * 1.7) + sweep
			var wave := (0.055 * sin(i + 0.60)) if _style == "wave" else 0.016
			var tip := _direction(theta) * 1.12
			guides.append(Lock.new(root, tip, arc, wave, 0.22, (0.037 if loose else 0.020)))
	if _fringe == "side":
		var part := Vector2(0.38 + sweep, -0.09)
		for i in 5:
			var f := i / 4.0
			var root := part + Vector2(-0.30 * f, 0.44 * f)
			var tip := _direction(lerpf(-1.33, 0.28, f) + sweep) * lerpf(1.14, 1.03, f)
			guides.append(Lock.new(root, tip, -lerpf(0.32, 0.11, f), 0.024, lerpf(0.215, 0.15, f), lerpf(0.057, 0.036, f)))
		for i in 3:
			var theta := 0.48 + i * 0.27 + sweep
			guides.append(Lock.new(part + Vector2(0, -0.10 * i), _direction(theta) * 1.08, 0.12, 0.0, 0.16, 0.031))
	elif _fringe == "straight":
		for i in 6:
			var f := i / 5.0
			var tip := _direction(lerpf(-1.05, 1.09, f)) * (1.08 + 0.04 * cos(i * 2.3))
			var root := Vector2(lerpf(-0.35, 0.26, f) + sweep, lerpf(-0.07, 0.26, absf(f - 0.48) * 2))
			guides.append(Lock.new(root, tip, 0.07 + 0.09 * sin(f * PI), 0.0, 0.18, 0.035))
	elif _style in ["pixie", "undercut", "crop"] or (patches.is_empty() and _style != "curly"):
		var flick := _style == "pixie"
		var lifted := _style == "undercut"
		for i in 8:
			var f := i / 7.0
			var theta := lerpf(-1.20, 1.16, f)
			var root := Vector2(lerpf(0.05, 0.65, f) + sweep, lerpf(-0.35, 0.35, f))
			var tip := _direction(theta + sweep) * (1.08 + 0.08 * sin(i * 2.3))
			var height := 0.052 if flick else (0.055 if lifted else 0.032)
			guides.append(Lock.new(root, tip, -0.19 - 0.06 * sin(i), 0.04 if flick else 0.0, 0.18, height))
	return guides

func _lock_relief(point: Vector2, guides: Array[Lock]) -> Vector2:
	var relief := 0.0
	var shine := 0.0
	for lock in guides:
		var delta := point - lock.root
		var t := delta.dot(lock.axis) / lock.length
		if t <= 0.0 or t >= 1.0:
			continue
		var arc := sin(PI * t)
		var across := lock.axis.cross(delta) - lock.bend * arc - lock.wave * sin(TAU * t)
		var half_width := lock.width * (0.43 + 0.61 * arc + 0.12 * t)
		var u := across / half_width
		if absf(u) >= 1.0:
			continue
		var section := (1.0 - u * u)
		var taper := smoothstep(0.0, 0.22, t) * (1.0 - 0.78 * smoothstep(0.84, 1.0, t))
		var crest := section * taper
		var lift := lock.lift * section * crest
		relief = maxf(relief, lift)
		# Shift the light band towards the leading edge, with a narrow lip.
		var band := maxf(0.0, 1.0 - absf(u + 0.24) * 1.7)
		shine = maxf(shine, (0.28 * crest + 0.72 * band * taper) * (0.66 + 0.34 * sin(PI * t)))
	return Vector2(relief, shine)

func _hairline(theta: float) -> float:
	var front := cos(theta)
	var across := sin(theta)
	var brow := lerpf(0.162, 0.132, _length)
	match _fringe:
		"straight":
			brow = lerpf(0.140, 0.119, _length) + 0.010 * across + 0.010 * cos(theta * 12.6 + 0.50 * sin(theta * 6.0))
		"side":
			brow = lerpf(0.167, 0.145, _length) + (0.062 + 0.021 * _sweep) * sin(theta - 0.32)
			brow += 0.038 * exp(-pow((theta - 0.40 - _sweep * 0.18) / 0.24, 2))
			brow -= 0.009 * sin(theta * 15.0) * (1.0 - smoothstep(-0.7, 0.18, theta))
		_:
			if _style == "undercut":
				brow += 0.025
			elif _style == "pixie":
				brow += 0.032 * sin(theta * 8.0 + 1.0 + _sweep)
	brow = maxf(0.099, brow + across * _sweep * 0.015)
	var temple := 0.020 if _style != "undercut" else 0.052
	var nape := lerpf(-0.128, -0.166, _length)
	if _style in ["bob", "wave", "long"]:
		temple = -0.015
		nape = -0.153
	elif _style == "undercut":
		nape = lerpf(-0.077, -0.120, _length)
	elif _style == "curly":
		nape += 0.011 * cos(theta * 9.0)
	return lerpf(lerpf(temple, brow, smoothstep(-0.12, 0.52, front)), nape,
		smoothstep(0.10, 0.87, -front))

func _cap(patches: Array[Rect2i]) -> void:
	var guides := _guides(patches)
	var top := 0.006 if _covered else lerpf(0.009, 0.019, _volume)
	var crown := _lock_relief(Vector2.ZERO, guides)
	_vertex(Vector3(0, SKULL.y + top + crown.x * (0.035 if _covered else 1.0), 0), 0.78 + crown.y * 0.22)
	# Interior vertices of a replaced patch are omitted altogether.
	var rings: Array[PackedInt32Array] = []
	for row in range(1, ROWS + 1):
		var ring := PackedInt32Array()
		for col in SECTORS:
			var interior := false
			for patch in patches:
				interior = interior or (col > patch.position.x and col < patch.end.x
					and row > patch.position.y and row < patch.end.y)
			if interior:
				ring.append(-1)
				continue
			var theta := wrapf(TAU * col / SECTORS, -PI, PI)
			var t := float(row) / ROWS
			var phi := acos(_hairline(theta) / SKULL.y) * t
			var unit := Vector3(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta))
			var strands := _lock_relief(_direction(theta) * t, guides)
			var ridge := clampf(strands.x * 36.0 - 0.58, -0.58, 1.0)
			var margin := lerpf(top, lerpf(0.008, 0.018, _volume), t)
			var relief := strands.x * lerpf(0.76, 1.13, _volume)
			if _style != "curly":
				relief *= lerpf(0.67, 1.0, smoothstep(0.02, 0.48, t))
			margin += relief
			var fade := 0.0
			if _style == "undercut":
				fade = smoothstep(0.60, 0.93, t) * (1.0 - 0.72 * smoothstep(0.33, 0.95, cos(theta)))
				margin = lerpf(margin, 0.005, fade)
			if _covered:
				margin = lerpf(0.005, margin * 0.65, 1.0 - smoothstep(0.084, 0.175, (unit * SKULL).y))
			var p := unit * (SKULL + Vector3.ONE * maxf(0.005, margin))
			p = _lengths(p, theta, t, ridge)
			var shade := 0.61 + strands.y * 0.39 + 0.085 * unit.y
			if _fringe == "side":
				var part := Vector2(0.38 + _sweep * 0.12, -0.09)
				var part_offset := _direction(theta) * t - part
				var crease := exp(-pow((part_offset.x + part_offset.y * 0.74) / 0.035, 2))
				shade -= 0.13 * crease * (1.0 - smoothstep(0.13, 0.37, absf(part_offset.y)))
			ring.append(_vertex(p, lerpf(shade, 1.14, fade)))
		rings.append(ring)
	for col in SECTORS:
		_indices.append_array([0, rings[0][(col + 1) % SECTORS], rings[0][col]])
	for row in range(1, ROWS):
		for col in SECTORS:
			var replaced := false
			for patch in patches:
				replaced = replaced or patch.has_point(Vector2i(col, row))
			if replaced:
				continue
			var next := (col + 1) % SECTORS
			_quad(rings[row - 1][col], rings[row - 1][next], rings[row][next], rings[row][col])
	# Taper the visible edge. The final ring turns in to meet the face or the nape.
	var hem := rings.back() as PackedInt32Array
	var insert := _vertices.size()
	for index in hem:
		var p := _vertices[index]
		var skin := p / (p / SKULL).length()
		var edge := p.move_toward(skin, lerpf(0.024, 0.012, smoothstep(0.14, 0.26, -p.y)))
		_vertex(edge, _shades[index].r * 0.80)
	for col in SECTORS:
		var next := (col + 1) % SECTORS
		_quad(hem[col], hem[next], insert + next, insert + col)
	_patch_rings = rings

func _lengths(p: Vector3, theta: float, t: float, ridge: float) -> Vector3:
	var rear := -cos(theta)
	var at_hem := smoothstep(0.50, 1.0, t)
	match _style:
		"bob", "wave":
			var coverage := smoothstep(0.04, 0.65, rear)
			var wave := 0.5 + 0.5 * cos(theta * 8.0 + t * 10.0)
			var curl := sin(at_hem * PI)
			p.x *= 1.0 + coverage * (0.13 * curl - 0.09 * at_hem)
			p.z -= coverage * (0.055 * at_hem + 0.026 * curl)
			p.y -= at_hem * coverage * lerpf(0.009, 0.042, _length)
			if _style == "wave":
				p.y -= at_hem * coverage * (0.015 + 0.036 * wave)
				p.z -= coverage * at_hem * (0.040 * wave + 0.014)
		"long":
			var coverage := smoothstep(0.32, 0.79, rear)
			var drop := smoothstep(0.46, 1.0, t) * coverage
			var setback := smoothstep(0.36, 0.89, t) * coverage
			p.y -= drop * (lerpf(0.132, 0.275, _length) + 0.027 * ridge)
			p.z -= setback * (0.254 + 0.038 * ridge)
			p.z -= drop * 0.020 * sin(t * TAU * 1.2) * coverage
			p.x += drop * (_sweep * 0.072 + sin(theta) * (0.044 + 0.023 * ridge)) * (1.0 - 0.23 * at_hem)
		"pixie", "side":
			var direction := (0.085 if _style == "side" else 0.064) + _sweep * 0.035
			p.x += direction * sin(t * PI) * maxf(0.0, cos(theta - 0.65)) * (0.32 if _covered else 1.0)
	return _outside_skull(p)

func _outside_skull(p: Vector3) -> Vector3:
	return p * maxf(1.0, 1.009 / (p / SKULL).length())

func _attachment(patch: Rect2i) -> void:
	var loop := PackedInt32Array()
	for col in range(patch.position.x, patch.end.x):
		loop.append(_patch_rings[patch.position.y - 1][col])
	for row in range(patch.position.y, patch.end.y):
		loop.append(_patch_rings[row - 1][patch.end.x])
	for col in range(patch.end.x, patch.position.x, -1):
		loop.append(_patch_rings[patch.end.y - 1][col])
	for row in range(patch.end.y, patch.position.y, -1):
		loop.append(_patch_rings[row - 1][patch.position.x])
	var start := Vector3.ZERO
	for index in loop:
		start += _vertices[index]
	start /= loop.size()
	_report.tail_anchors.append(_components(start))
	var bun := _style in ["bun", "twin"]
	var high := _style == "high_ponytail" and not _covered
	var low := _style == "low_ponytail"
	var end_y := -lerpf(0.234, 0.434, _length)
	var drift := _sweep * 0.150 + (0.053 if not low else -0.025)
	var first := Vector3(drift * 0.28, start.y + (0.068 if high else 0.012), start.z - 0.137)
	var second := Vector3(drift * 0.50, end_y + 0.115, -0.552)
	var end := Vector3(drift, end_y, -0.537 - _length * 0.034)
	if bun:
		var direction := Vector3(start.x * 1.6, (start.y + 0.050) * 1.05, start.z).normalized()
		var depth := lerpf(0.105, 0.143, _volume)
		first = start + direction * (depth * 0.33)
		second = start + direction * (depth * 0.72) + Vector3.UP * 0.015
		end = start + direction * depth
	else:
		const TIE_T := 0.375
		_tie_center = start.bezier_interpolate(first, second, end, TIE_T)
		_tie_tangent = start.bezier_derivative(first, second, end, TIE_T).normalized()
		_tie_radius = _tail_radius(TIE_T, false)
	var tangent := start.bezier_derivative(first, second, end, 0).normalized()
	var basis_x := Vector3.UP.cross(-tangent).normalized()
	var basis_y := basis_x.cross(tangent)
	var angles := PackedFloat32Array()
	for index in loop:
		var offset := _vertices[index] - start
		angles.append(atan2(offset.dot(basis_y), offset.dot(basis_x)))
	var rim := loop
	var steps := 10 if bun else TAIL_STEPS
	for step in range(1, steps):
		var t := float(step) / steps
		var center := start.bezier_interpolate(first, second, end, t)
		tangent = start.bezier_derivative(first, second, end, t).normalized()
		var x := basis_x.slide(tangent).normalized()
		var y := x.cross(tangent)
		var radius := _tail_radius(t, bun)
		var row := _vertices.size()
		for i in loop.size():
			var angle := angles[i]
			var twist := 0.16 * cos(angle * 5.0 - t * 3.1)
			if bun:
				twist = 0.14 * cos(angle * 2.0 + t * TAU * 1.17)
			if _style == "braid":
				twist = 0.19 * cos(angle * 3.0 - t * TAU * 4.0) + 0.11 * cos(t * TAU * 6.0)
			var profile := 1.0 if bun else 0.76
			var p := center + (x * cos(angle) + y * sin(angle) * profile) * radius * (1.0 + twist)
			var root_offset := _vertices[loop[i]] - start
			p = (center + root_offset).lerp(p, smoothstep(0.0, 0.28, t))
			var base_shade := 0.70 + 0.83 * twist
			var shade := lerpf(_shades[loop[i]].r, base_shade, smoothstep(0.0, 0.32, t))
			_vertex(_outside_skull(p), shade)
		var next_rim := PackedInt32Array()
		for i in loop.size():
			var next := (i + 1) % loop.size()
			_quad(rim[i], rim[next], row + next, row + i)
			next_rim.append(row + i)
		rim = next_rim
	var tip := _vertex(end, 0.77)
	for i in rim.size():
		_indices.append_array([rim[i], rim[(i + 1) % rim.size()], tip])

func _tail_radius(t: float, bun: bool) -> float:
	if bun:
		return lerpf(0.066, 0.098, _volume) * sqrt(1.0 - pow((t - 0.41) / 0.59, 2))
	var taper := lerpf(0.041, 0.069, _volume) * pow(1.0 - t, 0.59)
	var gather := 1.0 - 0.20 * exp(-pow((t - 0.375) / 0.10, 2))
	return taper * gather * (1.0 if _style == "braid" else 0.88 + 0.81 * sin(t * PI))

func _accessory(parent: Node3D, style: String) -> void:
	var center := _tie_center
	var x := Vector3.RIGHT
	var y := Vector3.UP
	var normal := Vector3.BACK
	if center == Vector3.ZERO:
		var back := _patch_rings[ROWS * 3 / 4][SECTORS / 2]
		center = _vertices[back]
	elif style == "band":
		normal = _tie_tangent
		x = Vector3.UP.cross(-normal).normalized()
		y = x.cross(normal)
	else:
		center.z -= _tie_radius * 0.65
	_begin_surface()
	if style == "ribbon":
		_ribbon(parent, center)
	else:
		const RING := 24
		const SIDES := 8
		var radius := 0.036 if _tie_radius == 0.0 else _tie_radius
		for i in RING:
			var a := TAU * i / RING
			for j in SIDES:
				var b := TAU * j / SIDES
				var span := radius + cos(b) * 0.006
				var p := center + x * (cos(a) * span) + y * (sin(a) * span * (0.76 if _tie_radius > 0.0 else 1.0))
				p += normal * (sin(b) * 0.006 - (0.013 if _tie_radius == 0.0 else 0.0))
				_vertex(_outside_skull(p), 0.88 + 0.12 * cos(b))
		for i in RING:
			for j in SIDES:
				var next := ((i + 1) % RING) * SIDES
				var side := (j + 1) % SIDES
				_quad(i * SIDES + j, next + j, next + side, i * SIDES + side)
		_emit(parent, "Band", Color("#e4b75e"), "accessory")

func _ribbon(parent: Node3D, center: Vector3) -> void:
	const SIDES := 32
	for section in 3:
		var radius := 1.0 if section == 1 else 0.63
		for i in SIDES:
			var a := TAU * i / SIDES
			var wings := pow(absf(cos(a)), 0.8)
			var p := Vector3(cos(a) * 0.079, sin(a) * (0.011 + 0.058 * wings), -0.003 - section * 0.009)
			p.x *= radius
			p.y *= radius
			_vertex(_outside_skull(center + p), 0.79 + 0.10 * section + 0.07 * sin(a))
	for section in 2:
		for i in SIDES:
			var current := section * SIDES + i
			var next := section * SIDES + (i + 1) % SIDES
			_quad(current, next, next + SIDES, current + SIDES)
	var inner := _vertex(_outside_skull(center), 0.89)
	var outer := _vertex(center + Vector3(0, 0, -0.031), 1.02)
	for i in SIDES:
		var next := (i + 1) % SIDES
		_indices.append_array([inner, next, i, outer, i + 2 * SIDES, next + 2 * SIDES])
	_emit(parent, "Ribbon", Color("#d98a83"), "accessory")
