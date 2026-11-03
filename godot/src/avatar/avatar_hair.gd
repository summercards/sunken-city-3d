extends RefCounted
## Original SEA source authored 2026-11-03; no external character geometry.
## Deterministic modular hair authoring. No imported game assets or gameplay state.
## The open-front scalp never covers the eye aperture. Long hair is routed behind
## the shoulder/tank envelope rather than extending straight through the torso.
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const SKULL := Vector3(0.258, 0.25, 0.253)
var _materials: Dictionary = {}
var _report: Dictionary = {}
var _bounds := AABB()
var _has_bounds := false
var _minimum_skull := INF
var _lower_front := -INF
var _volume := 0.5
var _length := 0.5
var _sweep := 0.0

func build(parent: Node3D, appearance: Dictionary, morphs: Dictionary) -> void:
	_materials.clear()
	_has_bounds = false
	_minimum_skull = INF
	_lower_front = -INF
	_volume = clampf(float(morphs.get("hair_volume", 0.5)), 0.0, 1.0)
	_length = clampf(float(morphs.get("hair_length", 0.5)), 0.0, 1.0)
	_sweep = clampf(float(morphs.get("hair_sweep", 0.5)), 0.0, 1.0) * 2.0 - 1.0
	var style := str(appearance.get("hair_style", "crop"))
	var covered := str(appearance.get("hat", "none")) != "none"
	var color := Catalog.color(appearance, "hair_color")
	_report = {"style": style, "covered_by_hat": covered, "zones": {}, "tail_anchors": [],
		"native_skull_radii": [SKULL.x, SKULL.y, SKULL.z], "eye_clearance_floor_y": 0.095}
	var root := Node3D.new()
	root.name = "Hair"
	parent.add_child(root)
	var fringe := str(appearance.get("fringe", "auto"))
	if fringe == "auto":
		fringe = "open" if style in ["crop", "undercut", "pixie"] else ("side" if style in ["side", "wave"] else "straight")
	_scalp(root, color, covered, style, fringe)
	if fringe != "open": _fringe(root, color, fringe, covered)
	if style in ["bob", "wave"]: _bob(root, color, style == "wave")
	if style == "curly": _curls(root, color, covered)
	if style == "pixie" and not covered:
		for side in [-1, 1]:
			_tube(root, "PixieTuft" + str(side), [Vector3(side * 0.13, 0.20, -0.07), Vector3(side * 0.18, 0.21, -0.13), Vector3(side * 0.19, 0.18, -0.16)], [0.040, 0.035, 0.004], color, "scalp", false)
	if style == "bun" and not covered:
		_lobe(root, "Bun", Vector3(0, 0.265, -0.105), Vector3(0.083, 0.080, 0.083) * lerpf(0.85, 1.15, _volume), color, "bun")
	if style == "twin" and not covered:
		for side in [-1, 1]:
			_lobe(root, "TwinBun" + str(side), Vector3(side * 0.225, 0.170, -0.115), Vector3(0.075, 0.073, 0.077) * lerpf(0.85, 1.12, _volume), color, "bun")
	if style in ["ponytail", "high_ponytail", "low_ponytail", "braid"]:
		_ponytail(root, color, style, covered)
	if style == "long": _long(root, color)
	var accessory := str(appearance.get("hair_accessory", "none"))
	if accessory != "none": _accessory(root, color, accessory, style, covered)
	_report.bounds_min = [_bounds.position.x, _bounds.position.y, _bounds.position.z] if _has_bounds else []
	var end := _bounds.end
	_report.bounds_max = [end.x, end.y, end.z] if _has_bounds else []
	_report.minimum_skull_q = _minimum_skull
	_report.lower_hair_front_z = _lower_front if is_finite(_lower_front) else null
	root.set_meta("avatar_hair_metrics", _report.duplicate(true))

func metrics() -> Dictionary:
	return _report.duplicate(true)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.90
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _materials[key]

func _safe(point: Vector3, lower_tail: bool = false) -> Vector3:
	var q := pow(point.x / SKULL.x, 2.0) + pow(point.y / SKULL.y, 2.0) + pow(point.z / SKULL.z, 2.0)
	if q < 1.035:
		point *= sqrt(1.035 / maxf(q, 0.00001))
	if lower_tail and point.y < -0.170:
		# Continuous envelope: y=-.17 starts behind -.48; lower tips stay farther
		# behind the back-mounted tank even after minimum head scale and yaw.
		point.z = minf(point.z, -0.480 - minf(0.08, (-point.y - 0.170) * 0.65))
	return point

func _mesh(parent: Node3D, id: String, vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, color: Color, zone: String) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = _material(color)
	node.set_meta("avatar_part", "hair")
	node.set_meta("hair_zone", zone)
	parent.add_child(node)
	var local_bounds := AABB(vertices[0], Vector3.ZERO)
	for p in vertices:
		local_bounds = local_bounds.expand(p)
		_bounds = _bounds.expand(p) if _has_bounds else AABB(p, Vector3.ZERO)
		_has_bounds = true
		var q := pow(p.x / SKULL.x, 2.0) + pow(p.y / SKULL.y, 2.0) + pow(p.z / SKULL.z, 2.0)
		_minimum_skull = minf(_minimum_skull, q)
		if p.y < -0.20: _lower_front = maxf(_lower_front, p.z)
	var zones: Dictionary = _report.zones
	var entry: Dictionary = zones.get(zone, {"meshes": 0, "vertices": 0, "bounds_min": [], "bounds_max": []})
	entry.meshes += 1
	entry.vertices += vertices.size()
	if entry.bounds_min.is_empty():
		entry.bounds_min = [local_bounds.position.x, local_bounds.position.y, local_bounds.position.z]
		entry.bounds_max = [local_bounds.end.x, local_bounds.end.y, local_bounds.end.z]
	else:
		for axis in 3:
			entry.bounds_min[axis] = minf(float(entry.bounds_min[axis]), local_bounds.position[axis])
			entry.bounds_max[axis] = maxf(float(entry.bounds_max[axis]), local_bounds.end[axis])
	zones[zone] = entry
	return node

func _scalp(parent: Node3D, color: Color, covered: bool, style: String, fringe: String) -> void:
	var margin := 0.007 + _volume * 0.010
	if covered: margin = 0.005
	var radii := SKULL + Vector3(margin, margin, margin)
	var vertices := PackedVector3Array([Vector3(0, radii.y, 0)])
	var normals := PackedVector3Array([Vector3.UP])
	var indices := PackedInt32Array()
	const SEGMENTS := 64
	const RINGS := 14
	for ring in range(1, RINGS + 1):
		for i in SEGMENTS:
			var theta := TAU * i / float(SEGMENTS)
			var rear := clampf(-sin(theta), 0.0, 1.0)
			var blend := smoothstep(0.15, 0.85, rear)
			# All styles consume the DIY controls, including a short crop. Length
			# changes the hairline/nape; sweep shifts its parting without covering eyes.
			var front_y := lerpf(0.148, 0.108, _length) if fringe == "open" else lerpf(0.112, 0.102, _length)
			if style == "undercut": front_y = lerpf(0.160, 0.120, _length)
			front_y = maxf(0.102, front_y + _sweep * cos(theta) * 0.010)
			var rear_y := lerpf(-0.145, -0.183, _length) + _sweep * cos(theta) * 0.014
			var boundary := lerpf(front_y, rear_y, blend)
			var phi := acos(boundary / radii.y) * ring / float(RINGS)
			var p := Vector3(radii.x * sin(phi) * cos(theta), radii.y * cos(phi), radii.z * sin(phi) * sin(theta))
			if covered:
				# The crown remains compact under the hat; only the exposed side/nape
				# gets extra volume, so this slider retains a visible, safe response.
				var exposed := 1.0 - smoothstep(0.105, 0.155, p.y)
				p.x *= 1.0 + exposed * _volume * 0.040
				p.z *= 1.0 + exposed * _volume * 0.040
			p = _safe(p)
			vertices.append(p)
			normals.append(Vector3(p.x / (radii.x * radii.x), p.y / (radii.y * radii.y), p.z / (radii.z * radii.z)).normalized())
	for i in SEGMENTS: indices.append_array([0, 1 + i, 1 + (i + 1) % SEGMENTS])
	for ring in range(RINGS - 1):
		for i in SEGMENTS:
			var a := 1 + ring * SEGMENTS + i
			var b := 1 + ring * SEGMENTS + (i + 1) % SEGMENTS
			indices.append_array([a, a + SEGMENTS, b + SEGMENTS, a, b + SEGMENTS, b])
	_mesh(parent, "Scalp", vertices, normals, indices, color, "scalp")

func _fringe(parent: Node3D, color: Color, mode: String, covered: bool) -> void:
	# Flush sculpted leaves replace the former face-covering sphere fringe.
	for lock in 5:
		var x := (lock - 2) * 0.068
		var width := 0.050
		var bottom := lerpf(0.116, 0.100, _length) + (lock * 0.010 if mode == "side" else absf(lock - 2) * 0.003)
		var top := 0.218
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		const ROWS := 12
		const COLS := 10
		for row in ROWS + 1:
			var t := row / float(ROWS)
			var y := lerpf(top, bottom, t)
			var taper := lerpf(0.90, 0.07, pow(t, 5.0))
			for col in COLS + 1:
				var u := col / float(COLS) * 2.0 - 1.0
				var px := x + u * width * taper + (0.028 * t if mode == "side" else _sweep * 0.012 * t)
				var xy := Vector2(px, y + absf(u) * 0.006 * t)
				var q := pow(xy.x / SKULL.x, 2.0) + pow(xy.y / SKULL.y, 2.0)
				if q > 0.97: xy *= sqrt(0.97 / q)
				var skin := Vector3(xy.x, xy.y, SKULL.z * sqrt(maxf(0.0, 1.0 - pow(xy.x / SKULL.x, 2.0) - pow(xy.y / SKULL.y, 2.0))))
				var n := Vector3(skin.x / pow(SKULL.x, 2.0), skin.y / pow(SKULL.y, 2.0), skin.z / pow(SKULL.z, 2.0)).normalized()
				var depth := (0.019 if covered else 0.023 + _volume * 0.013) + (1.0 - u * u) * 0.007
				vertices.append(_safe(skin + n * depth))
				normals.append(n)
		for row in ROWS:
			for col in COLS:
				var a := row * (COLS + 1) + col
				indices.append_array([a, a + 1, a + COLS + 2, a, a + COLS + 2, a + COLS + 1])
		_mesh(parent, "Fringe" + str(lock), vertices, normals, indices, color.lightened(lock % 2 * 0.012), "bangs")

func _tube(parent: Node3D, id: String, path: Array, radii: Array, color: Color, zone: String, lower_tail: bool = true) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	const SIDES := 12
	var samples: Array[Vector3] = []
	var widths: Array[float] = []
	for segment in path.size() - 1:
		for step in 6:
			var t := step / 6.0
			samples.append((path[segment] as Vector3).lerp(path[segment + 1], t))
			widths.append(lerpf(radii[segment], radii[segment + 1], t))
	samples.append(path.back())
	widths.append(radii.back())
	for i in samples.size():
		var tangent := (samples[mini(i + 1, samples.size() - 1)] - samples[maxi(i - 1, 0)]).normalized()
		var right := tangent.cross(Vector3.RIGHT).normalized()
		if right.length_squared() < 0.01: right = tangent.cross(Vector3.UP).normalized()
		var up := tangent.cross(right).normalized()
		for j in SIDES:
			var angle := TAU * j / float(SIDES)
			var normal := right * cos(angle) + up * sin(angle)
			vertices.append(_safe(samples[i] + normal * widths[i], lower_tail))
			normals.append(normal)
		if i > 0:
			for j in SIDES:
				var a := (i - 1) * SIDES + j
				var b := (i - 1) * SIDES + (j + 1) % SIDES
				indices.append_array([a, a + SIDES, b + SIDES, a, b + SIDES, b])
	# Seal both ends, including the root under the scalp, so no view exposes holes.
	var first := vertices.size()
	vertices.append(_safe(samples[0], lower_tail))
	normals.append((samples[0] - samples[1]).normalized())
	var last := vertices.size()
	vertices.append(_safe(samples.back(), lower_tail))
	normals.append((samples.back() - samples[samples.size() - 2]).normalized())
	for j in SIDES:
		indices.append_array([first, (j + 1) % SIDES, j])
		var end_start := (samples.size() - 1) * SIDES
		indices.append_array([last, end_start + j, end_start + (j + 1) % SIDES])
	_mesh(parent, id, vertices, normals, indices, color, zone)

func _lobe(parent: Node3D, id: String, center: Vector3, radius: Vector3, color: Color, zone: String) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 24
	const RINGS := 16
	for ring in RINGS + 1:
		var phi := PI * ring / float(RINGS)
		for segment in SEGMENTS:
			var theta := TAU * segment / float(SEGMENTS)
			var unit := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			vertices.append(_safe(center + unit * radius))
			normals.append((unit / radius).normalized())
	for ring in RINGS:
		for segment in SEGMENTS:
			var a := ring * SEGMENTS + segment
			var b := ring * SEGMENTS + (segment + 1) % SEGMENTS
			indices.append_array([a, a + SEGMENTS, b + SEGMENTS, a, b + SEGMENTS, b])
	_mesh(parent, id, vertices, normals, indices, color, zone)

func _bob(parent: Node3D, color: Color, wave: bool) -> void:
	for i in 9:
		# Stop behind the ears, including the widest lock at maximum volume.
		var angle := lerpf(PI * 1.19, PI * 1.81, i / 8.0)
		var root := Vector3(cos(angle) * 0.250, 0.040, sin(angle) * 0.249)
		var tip := Vector3(cos(angle) * 0.265, -lerpf(0.125, 0.168, _length), sin(angle) * 0.268)
		var middle := root.lerp(tip, 0.55)
		if wave: middle.x += sin(i * 2.3) * 0.022
		_tube(parent, "BobLock" + str(i), [root, middle, tip], [0.026, lerpf(0.026, 0.043, _volume), 0.008], color.lightened(i % 2 * 0.012), "back", false)

func _curls(parent: Node3D, color: Color, covered: bool) -> void:
	for i in 12:
		var theta := TAU * i / 12.0
		var rear := sin(theta) < 0.0
		var y := 0.13 if rear else 0.17
		if covered and y > 0.14: continue
		var center := Vector3(cos(theta) * 0.222, y, sin(theta) * 0.211)
		_lobe(parent, "Curl" + str(i), center, Vector3(0.049, 0.046, 0.049) * lerpf(0.82, 1.12, _volume), color.lightened(i % 3 * 0.009), "scalp")

func _ponytail(parent: Node3D, color: Color, style: String, covered: bool) -> void:
	var high := style == "high_ponytail" and not covered
	var low := style == "low_ponytail"
	var start_y := 0.205 if high else (-0.025 if low else 0.080)
	var end_y := -lerpf(0.225, 0.450, _length)
	var side := _sweep * 0.090
	# The rear skull narrows strongly near the crown. A fixed -.245 root floats
	# behind a high ponytail; place the root just inside its actual hair surface.
	var root_z := _scalp_back(0, start_y, covered) + 0.004
	var path := [Vector3(0, start_y, root_z), Vector3(side * 0.25, start_y - 0.025, -0.350),
		Vector3(side * 0.65, -0.085, -0.465), Vector3(side, -0.170, -0.555), Vector3(side * 1.13, end_y, -0.595)]
	var width := lerpf(0.035, 0.057, _volume)
	if style == "braid":
		for strand in 3:
			var braided: Array = []
			for i in path.size():
				var p: Vector3 = path[i]
				p.x += sin(i * 3.4 + strand * TAU / 3.0) * width * 0.42
				p.z += cos(i * 3.4 + strand * TAU / 3.0) * width * 0.20
				braided.append(p)
			_tube(parent, "BraidStrand" + str(strand), braided, [width * 0.55, width * 0.56, width * 0.53, width * 0.42, 0.009], color.lightened(strand * 0.012), "ponytail")
	else:
		_tube(parent, "Ponytail", path, [width * 0.74, width, width * 0.95, width * 0.68, 0.008], color, "ponytail")
	_report.tail_anchors.append([0, start_y, root_z])

func _long(parent: Node3D, color: Color) -> void:
	for i in 5:
		var x := (i - 2) * 0.064
		var root := Vector3(x, 0.035, -0.245)
		var shift := _sweep * 0.055
		var tip_y := -lerpf(0.240, 0.450, _length) + absf(i - 2) * 0.014
		_tube(parent, "LongLock" + str(i), [root, Vector3(x, -0.045, -0.355), Vector3(x + shift * 0.5, -0.150, -0.535), Vector3(x + shift, tip_y, -0.610)], [0.032, lerpf(0.031, 0.047, _volume), lerpf(0.028, 0.043, _volume), 0.007], color.lightened(i % 2 * 0.012), "back")
		_report.tail_anchors.append([root.x, root.y, root.z])

func _accessory(parent: Node3D, _hair_color: Color, accessory: String, style: String, covered: bool) -> void:
	# Back-mounted accessories cannot collide with eyes, ears, hat brim or glasses.
	var y := 0.080
	if style == "high_ponytail" and not covered: y = 0.205
	elif style == "low_ponytail": y = -0.025
	var has_tail := style in ["ponytail", "high_ponytail", "low_ponytail", "braid"]
	var center := Vector3(_sweep * 0.012, y, -0.325 if has_tail else -0.268)
	if not has_tail: center.z = _scalp_back(center.x, center.y, covered) + 0.004
	var color := Color("#d98a83")
	if accessory == "ribbon":
		for side in [-1, 1]:
			_lobe(parent, "RibbonLoop" + str(side), center + Vector3(side * 0.035, 0, -0.004), Vector3(0.037, 0.023, 0.014), color, "accessory")
		_lobe(parent, "RibbonKnot", center + Vector3(0, 0, -0.012), Vector3(0.013, 0.015, 0.013), color.lightened(0.12), "accessory")
	else:
		var path: Array = []
		var radii: Array = []
		var band_radius := lerpf(0.035, 0.057, _volume) * 1.03 if has_tail else 0.043
		if has_tail: center.y -= 0.022
		for i in 25:
			var angle := TAU * i / 24.0
			var p := center + Vector3(cos(angle) * band_radius, sin(angle) * (band_radius if has_tail else 0.035), -0.012)
			if not has_tail:
				p.z = _scalp_back(p.x, p.y, covered) - 0.002
			path.append(p)
			radii.append(0.007)
		_tube(parent, "HairBand", path, radii, Color("#e4b75e"), "accessory", false)

func _scalp_back(x: float, y: float, covered: bool) -> float:
	# Use the exact scalp radii, including the exposed volume below a hat. A
	# constant rear anchor leaves a visible gap on the short, least puffy styles.
	var margin := 0.005 if covered else 0.007 + _volume * 0.010
	var radii := SKULL + Vector3.ONE * margin
	if covered:
		var factor := 1.0 + (1.0 - smoothstep(0.105, 0.155, y)) * _volume * 0.040
		radii.x *= factor
		radii.z *= factor
	return -radii.z * sqrt(maxf(0.0, 1.0 - pow(x / radii.x, 2.0) - pow(y / radii.y, 2.0)))
