@tool
extends RefCounted
## 独立植物内核：随机流按语义 ID 派生，公共贴图只读，四个本地材质角色。

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const Library = preload("res://src/ambient/vegetation/library.gd")
const LeafShader = preload("res://src/plant_authoring/leaf.gdshader")
const PALETTE = preload("res://assets/textures/shared/sea_cabin_timber_8x8_512.png")
const GRASS_MASK = preload("res://assets/textures/vegetation/meadow_atlas.png")

static func build(data: Dictionary) -> Dictionary:
	var reason := Recipe.validate(data)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "root": null, "branches": [],
			"stats": {"triangles": 0, "leaf_count": 0, "branch_count": 0, "bounds": AABB()}}
	var recipe := Recipe.normalized(data)
	var definition: Dictionary = Species.definitions()[recipe.species]
	var root := Node3D.new()
	root.name = String(recipe.name).validate_node_name() if not String(recipe.name).is_empty() else String(definition.name)
	var trunk_group := _group(root, "Trunk")
	var leaves_group := _group(root, "Leaves")
	var moss_group := _group(root, "Moss")
	var vines_group := _group(root, "Vines")
	var grass_group := _group(root, "Grass")
	var materials := {
		"trunk": _material("trunk", recipe, 0.0, 0.94),
		"leaf": _material("leaf", recipe, 1.0, 0.86),
		"moss": _material("moss", recipe, 0.0, 1.0),
		"vine": _material("vine", recipe, 0.25, 0.90)
	}
	trunk_group.visible = recipe.trunk_visible
	leaves_group.visible = recipe.leaves_visible
	var trunk_points := _make_trunk_points(recipe)
	var trunk_radii := _taper(float(recipe.trunk_radius), trunk_points.size(), 0.065)
	if recipe.trunk_visible:
		var trunk_mesh := _buffer()
		_tube(trunk_mesh, trunk_points, trunk_radii, 12, _cell(recipe, "trunk", "trunk"))
		_emit(trunk_group, "MainTrunk", trunk_mesh, materials.trunk)
	var branches: Array = []
	var leaf_count := 0
	var active_branches := 0
	for index in int(recipe.branch_count):
		var id := "branch_%02d" % index
		var branch := _make_branch(recipe, trunk_points, trunk_radii, index)
		var start: Vector3 = branch.start
		var wood_node := _group(trunk_group, id)
		wood_node.position = start
		var leaf_node := _group(leaves_group, id)
		leaf_node.position = start
		var branch_bounds := AABB(start, Vector3.ZERO)
		var enabled := Recipe.branch_enabled(recipe, id)
		if enabled:
			active_branches += 1
			var wood := _buffer()
			var foliage := _buffer()
			var points: Array[Vector3] = branch.points
			var radii: Array[float] = branch.radii
			_tube(wood, _to_local(points, start), radii, 8, _cell(recipe, "trunk", id))
			for twig_index in int(recipe.subtwig_count):
				var twig_id := "%s/twig_%02d" % [id, twig_index]
				var twig := _make_twig(recipe, points, radii, twig_id, twig_index)
				var twig_points: Array[Vector3] = twig.points
				var twig_radii: Array[float] = twig.radii
				_tube(wood, _to_local(twig_points, start), twig_radii, 6, _cell(recipe, "trunk", twig_id))
				if recipe.leaves_visible:
					leaf_count += _twig_leaves(foliage, recipe, definition, _to_local(twig_points, start), twig_radii, twig_id)
			var wood_mesh := _mesh(wood, materials.trunk)
			branch_bounds = AABB(start, Vector3.ZERO) if wood_mesh == null else AABB(wood_mesh.get_aabb().position + start, wood_mesh.get_aabb().size)
			if recipe.trunk_visible and wood_mesh != null:
				_add_mesh(wood_node, "Wood", wood_mesh)
			var leaf_mesh := _emit(leaf_node, "Foliage", foliage, materials.leaf)
			if leaf_mesh != null:
				branch_bounds = branch_bounds.merge(AABB(leaf_mesh.get_aabb().position + start, leaf_mesh.get_aabb().size))
		branches.append({
			"id": id, "name": "%s 主枝 %02d" % [definition.name, index],
			"node_path": NodePath("Trunk/" + id), "leaf_node_path": NodePath("Leaves/" + id),
			"position": start, "bounds": branch_bounds, "enabled": enabled
		})
	if recipe.trunk_visible and recipe.moss_enabled and float(recipe.moss_amount) > 0.0:
		_build_moss(moss_group, recipe, trunk_points, trunk_radii, materials.moss)
	if recipe.vine_enabled and int(recipe.vine_count) > 0 and float(recipe.vine_length) > 0.0:
		leaf_count += _build_vines(vines_group, recipe, trunk_points, trunk_radii, materials.vine)
	if recipe.grass_enabled and int(recipe.grass_count) > 0:
		_build_grass(grass_group, recipe, materials.leaf)
	var stats := _stats(root)
	stats.leaf_count = leaf_count
	stats.branch_count = active_branches
	stats.branch_slots = int(recipe.branch_count)
	stats.subtwig_count = active_branches * int(recipe.subtwig_count)
	stats.leaf_budget = Recipe.LEAF_BUDGET
	return {"ok": true, "reason": "", "root": root, "branches": branches, "stats": stats}

static func _make_trunk_points(recipe: Dictionary) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var rng := _rng(recipe, "trunk/shape")
	var phase := _range(recipe, rng, 0.0, TAU)
	for i in 17:
		var t := float(i) / 16.0
		var curve := float(recipe.trunk_curve) * sin(t * PI * 0.9) * (0.30 if recipe.species == "birch" else 1.0)
		points.append(Vector3(curve * sin(t * 2.2 + phase), float(recipe.height) * t, curve * cos(t * 1.7 + phase)))
	return points

static func _make_branch(recipe: Dictionary, trunk: Array[Vector3], trunk_radii: Array[float], index: int) -> Dictionary:
	var id := "branch_%02d" % index
	var rng := _rng(recipe, id + "/wood")
	var override: Dictionary = recipe.branch_overrides.get(id, {})
	var start_ratio := float(recipe.branch_start) / float(recipe.height)
	var rank := float(index) / maxf(1.0, float(int(recipe.branch_count) - 1))
	var t := lerpf(start_ratio, maxf(start_ratio, 0.91), rank)
	var azimuth := float(index) * 2.3999632297
	if recipe.species == "maple":
		# 每层三枝，冠层之间保留可读空隙。
		var layer: float = floorf(float(index) / 3.0)
		var layers: float = ceilf(float(recipe.branch_count) / 3.0)
		t = lerpf(start_ratio, maxf(start_ratio, 0.82), layer / maxf(1.0, layers - 1.0))
		azimuth = float(index % 3) * TAU / 3.0 + layer * 0.62
	var start := _sample(trunk, t)
	var angle := azimuth + _range(recipe, rng, -0.15, 0.15) + float(override.get("angle_offset", 0.0))
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	var envelope := sqrt(maxf(0.12, 1.0 - pow(rank * 0.9, 2.0)))
	if recipe.species == "camphor":
		envelope = 0.68 + 0.34 * sin(rank * PI)
	var length := float(recipe.crown_radius) * float(recipe.branch_spread) * envelope * float(override.get("length_scale", 1.0)) * _range(recipe, rng, 0.90, 1.08)
	var points: Array[Vector3] = []
	var bend := _range(recipe, rng, -0.15, 0.15)
	for step in 9:
		var f := float(step) / 8.0
		var rise := float(recipe.branch_rise) * f * (0.35 if recipe.species == "maple" else 1.0)
		var drop := float(recipe.branch_droop) * pow(f, 2.2) * (0.30 if recipe.species in ["birch", "maple"] else 0.65)
		var arch := sin(f * PI) * (0.20 if recipe.species == "camphor" else 0.035 if recipe.species == "maple" else 0.09)
		var sideways := direction.cross(Vector3.UP) * sin(f * PI) * bend
		points.append(start + direction * length * f + Vector3.UP * length * (rise - drop + arch) + sideways * length)
	var radius := minf(_sample_radius(trunk_radii, t) * 0.72, float(recipe.trunk_radius) * 0.43) * float(override.get("radius_scale", 1.0))
	return {"start": start, "points": points, "radii": _taper(radius, points.size(), 0.10)}

static func _make_twig(recipe: Dictionary, branch: Array[Vector3], branch_radii: Array[float], id: String, index: int) -> Dictionary:
	var rng := _rng(recipe, id + "/wood")
	var t := 0.30 + 0.65 * (float(index) + 0.5) / float(recipe.subtwig_count)
	var start := _sample(branch, t)
	var forward := (_sample(branch, minf(t + 0.05, 1.0)) - _sample(branch, maxf(0.0, t - 0.05))).normalized()
	var lateral := forward.cross(Vector3.UP).normalized() * (-1.0 if index % 2 == 0 else 1.0)
	var length := branch[0].distance_to(branch[-1]) * _range(recipe, rng, 0.28, 0.47)
	var direction := (forward * 0.45 + lateral * 0.8).normalized()
	var points: Array[Vector3] = []
	for step in 9:
		var f := float(step) / 8.0
		var y := sin(f * PI) * 0.20 + float(recipe.branch_rise) * f * 0.20 - float(recipe.branch_droop) * f * f * 0.42
		if recipe.species == "birch":
			y = 0.18 * f - (0.48 + float(recipe.branch_droop)) * pow(f, 1.65)
		elif recipe.species == "maple":
			y *= 0.35
		points.append(start + direction * length * f + Vector3.UP * length * y)
	var radius := _sample_radius(branch_radii, t) * 0.48
	return {"points": points, "radii": _taper(radius, points.size(), 0.12)}

static func _twig_leaves(buffer: Dictionary, recipe: Dictionary, definition: Dictionary, points: Array[Vector3], radii: Array[float], id: String) -> int:
	var count := Recipe.leaves_per_twig(recipe)
	var opposite: bool = definition.phyllotaxis == "opposite"
	var cluster_center := _sample(points, 0.66)
	for index in count:
		var rng := _rng(recipe, "%s/leaf_%03d" % [id, index])
		var station := int(index / 2) if opposite else index
		var stations := int(count / 2) if opposite else count
		var t := 0.18 + 0.80 * (float(station) + 0.5) / float(stations)
		var base := _sample(points, t)
		var forward := (_sample(points, minf(1.0, t + 0.03)) - _sample(points, maxf(0.0, t - 0.03))).normalized()
		var side := forward.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		var sign_side := -1.0 if index % 2 == 0 else 1.0
		var angle := float(station) * (0.85 if opposite else 2.3999632297)
		var radial := side.rotated(forward, angle) * sign_side
		var jitter := Vector3(_range(recipe, rng, -1.0, 1.0), _range(recipe, rng, -0.4, 0.4), _range(recipe, rng, -1.0, 1.0)) * float(recipe.cluster_jitter)
		if opposite:
			# 同一叶节使用同一扰动，对生叶柄仍从同一点发出。
			var pair_rng := _rng(recipe, "%s/pair_%03d" % [id, station])
			jitter = Vector3(_range(recipe, pair_rng, -1.0, 1.0), 0.0, _range(recipe, pair_rng, -1.0, 1.0)) * float(recipe.cluster_jitter)
		var petiole := float(recipe.cluster_size) * _range(recipe, rng, 0.14, 0.34)
		var center := base + jitter + radial * (petiole + _sample_radius(radii, t))
		var stalk: Array[Vector3] = [base, center]
		_tube(buffer, stalk, _taper(0.004, 2, 0.65), 4, _cell(recipe, "leaf", "%s/petiole_%03d" % [id, index]))
		var axis := (radial + forward * 0.22 + Vector3.UP * (0.32 if recipe.species != "birch" else -0.16)).normalized()
		var size := float(recipe.leaf_size) * _range(recipe, rng, 0.84, 1.14)
		Geometry.append_leaf(center, axis, size * float(definition.leaf_width_ratio), size * float(definition.leaf_length_ratio), size * 0.09, definition.leaf_shape, cluster_center, float(recipe.normal_blend), buffer.v, buffer.n, buffer.i, buffer.uv, _cell(recipe, "leaf", "%s/leaf_%03d" % [id, index]), int(definition.leaf_subdivisions), float(definition.leaf_tip), float(definition.leaf_cup))
	return count

static func _build_moss(parent: Node3D, recipe: Dictionary, points: Array[Vector3], radii: Array[float], material: Material) -> void:
	var buffer := _buffer()
	var count := int(ceil(float(recipe.moss_amount) * 28.0))
	for index in count:
		var id := "moss_%02d" % index
		var rng := _rng(recipe, id)
		var t := clampf(0.08 + fposmod(index * 0.61803398875, 1.0) * 0.64 + _range(recipe, rng, -0.04, 0.04), 0.04, 0.78)
		var angle := index * 2.3999632297 + _range(recipe, rng, -0.4, 0.4)
		var height_ratio := _range(recipe, rng, 0.10, 0.25) / float(recipe.height)
		Geometry.append_moss_on_tube(points, radii, t, height_ratio, angle, _range(recipe, rng, 0.5, 1.3), buffer.v, buffer.n, buffer.i, buffer.uv, _cell(recipe, "moss", id))
	_emit(parent, "AttachedPatches", buffer, material)

static func _build_vines(parent: Node3D, recipe: Dictionary, trunk: Array[Vector3], radii: Array[float], material: Material) -> int:
	for index in int(recipe.vine_count):
		var id := "vine_%02d" % index
		var rng := _rng(recipe, id + "/path")
		var t := clampf(0.36 + fposmod(index * 0.38196601125, 1.0) * 0.40 + _range(recipe, rng, -0.05, 0.05), 0.30, 0.83)
		var angle := index * 2.3999632297 + _range(recipe, rng, -0.35, 0.35)
		var surface := Geometry.tube_surface(trunk, radii, t, angle)
		var attach: Vector3 = surface.position + surface.normal * 0.016
		var phase := _range(recipe, rng, 0.0, TAU)
		var length := minf(float(recipe.vine_length), maxf(0.0, attach.y - 0.06))
		var points: Array[Vector3] = []
		for step in 13:
			var f := float(step) / 12.0
			var offset := Vector3(sin(phase + f * 4.2) - sin(phase), 0.0, cos(phase + f * 3.7) - cos(phase)) * 0.14
			points.append(attach + Vector3.DOWN * length * f + offset + surface.normal * sin(f * PI) * 0.16)
		var buffer := _buffer()
		_tube(buffer, points, _taper(0.017, points.size(), 0.45), 5, _cell(recipe, "vine", id))
		for leaf_index in 4:
			var base := _sample(points, float(leaf_index + 1) / 5.0)
			var side := -1.0 if leaf_index % 2 == 0 else 1.0
			Geometry.append_leaf(base, Vector3(side * 0.72, -0.18, 0.3).normalized(), 0.10, 0.27, 0.018, "oval", base + Vector3.DOWN * 0.12, 0.35, buffer.v, buffer.n, buffer.i, buffer.uv, _cell(recipe, "vine", "%s/leaf_%02d" % [id, leaf_index]))
		_emit(parent, id, buffer, material)
	return int(recipe.vine_count) * 4

static func _build_grass(parent: Node3D, recipe: Dictionary, material: Material) -> void:
	# 只复用源几何深副本；重建 UV 并绑定本地叶材质，绝不消费原全局风 Shader。
	var source := Library.mesh(recipe.grass_asset).duplicate(true) as ArrayMesh
	var buffer := _buffer()
	for index in int(recipe.grass_count):
		var id := "grass_%02d" % index
		var rng := _rng(recipe, id)
		var angle := index * 2.3999632297 + _range(recipe, rng, -0.3, 0.3)
		var radius := float(recipe.crown_radius) * (0.14 + fposmod(index * 0.38196601125, 1.0) * 0.14 + _range(recipe, rng, -0.02, 0.02))
		var scale := _range(recipe, rng, 0.70, 1.15)
		var basis := Basis(Vector3.UP, _range(recipe, rng, 0.0, TAU)).scaled(Vector3.ONE * scale)
		var transform := Transform3D(basis, Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		for surface in source.get_surface_count():
			if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := source.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var source_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var ids := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				ids = arrays[Mesh.ARRAY_INDEX]
			if ids.is_empty():
				for vertex in positions.size():
					ids.append(vertex)
			for face in range(0, ids.size(), 3):
				var a := ids[face]
				var b := ids[face + 1]
				var c := ids[face + 2]
				var na := (basis * ns[a]).normalized() if ns.size() == positions.size() else Vector3.UP
				var nb := (basis * ns[b]).normalized() if ns.size() == positions.size() else Vector3.UP
				var nc := (basis * ns[c]).normalized() if ns.size() == positions.size() else Vector3.UP
				Geometry.triangle(transform * positions[a], transform * positions[b], transform * positions[c], na, nb, nc, buffer.v, buffer.n, buffer.i, buffer.uv, _cell(recipe, "leaf", "%s/face_%05d" % [id, face]))
				# UV选色不变；第二UV只保留既有草卡的透明轮廓，避免不透明卡片变成方块。
				for vertex_index: int in [a, b, c]:
					buffer.uv2.append(source_uv[vertex_index] * 0.5 + Vector2(0.0, 0.5 if recipe.grass_asset == "mound_soft" else 0.0))
	_emit(parent, "GroundCover", buffer, material)

static func _cell(recipe: Dictionary, role: String, id: String) -> int:
	var selected := int(recipe[role + "_cell"])
	if recipe.color_mode == "manual" or _variation(recipe) <= 0.0 or float(recipe.color_variation) <= 0.0:
		return selected
	# 只在已知连续同色族内作相邻一级变化，不把绿色跳到蓝色/粉色。
	var families := [[0, 1, 2, 3, 4, 5], [8, 9, 10, 11, 12, 13, 14, 15],
		[24, 25, 26, 27, 28, 29, 30, 31], [32, 33, 34, 35, 36],
		[40, 41, 42, 43, 44, 45], [56, 57, 58, 59, 60, 61, 62, 63]]
	var rng := _rng(recipe, "palette/" + role + "/" + id)
	if rng.randf() > float(recipe.color_variation) * _variation(recipe):
		return selected
	for family: Array in families:
		var at := family.find(selected)
		if at >= 0:
			var delta := -1 if rng.randf() < 0.5 else 1
			return int(family[clampi(at + delta, 0, family.size() - 1)])
	return selected

static func _variation(recipe: Dictionary) -> float:
	return float(recipe.variation) if recipe.random_enabled else 0.0

static func _range(recipe: Dictionary, rng: RandomNumberGenerator, low: float, high: float) -> float:
	return lerpf((low + high) * 0.5, rng.randf_range(low, high), _variation(recipe))

static func _rng(recipe: Dictionary, id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# SHA 派生避免近邻 seed 相关；截取 60 位，避开有符号整数溢出。
	var digest := (str(int(recipe.seed)) + ":" + id).sha256_text()
	rng.seed = digest.substr(0, 15).hex_to_int()
	return rng

static func _material(role: String, recipe: Dictionary, weight: float, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = "Plant_" + role
	material.resource_local_to_scene = true
	material.shader = LeafShader
	material.set_shader_parameter("palette_texture", PALETTE)
	material.set_shader_parameter("grass_mask", GRASS_MASK)
	material.set_shader_parameter("local_time", 0.0)
	material.set_shader_parameter("preview_wind", false)
	material.set_shader_parameter("wind_strength", float(recipe.wind_strength))
	material.set_shader_parameter("wind_speed", float(recipe.wind_speed))
	material.set_shader_parameter("wind_weight", weight)
	material.set_shader_parameter("surface_roughness", roughness)
	return material

static func _buffer() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array()}

static func _tube(buffer: Dictionary, points: Array[Vector3], radii: Array[float], sides: int, cell: int) -> void:
	Geometry.append_tube(points, radii, sides, buffer.v, buffer.n, buffer.i, buffer.uv, cell)

static func _mesh(buffer: Dictionary, material: Material) -> ArrayMesh:
	if buffer.i.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer.v
	arrays[Mesh.ARRAY_NORMAL] = buffer.n
	arrays[Mesh.ARRAY_INDEX] = buffer.i
	arrays[Mesh.ARRAY_TEX_UV] = buffer.uv
	var mask_uv: PackedVector2Array = buffer.uv2
	if mask_uv.is_empty():
		mask_uv.resize(buffer.v.size())
		mask_uv.fill(Vector2(-1.0, -1.0))
	arrays[Mesh.ARRAY_TEX_UV2] = mask_uv
	var mesh := ArrayMesh.new()
	mesh.resource_local_to_scene = true
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

static func _emit(parent: Node3D, name: String, buffer: Dictionary, material: Material) -> ArrayMesh:
	var mesh := _mesh(buffer, material)
	if mesh != null:
		_add_mesh(parent, name, mesh)
	return mesh

static func _add_mesh(parent: Node3D, name: String, mesh: Mesh) -> void:
	var visual := MeshInstance3D.new()
	visual.name = name
	visual.mesh = mesh
	parent.add_child(visual)

static func _group(parent: Node3D, name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	parent.add_child(node)
	return node

static func _taper(radius: float, count: int, tip_ratio: float) -> Array[float]:
	var result: Array[float] = []
	for index in count:
		var t := float(index) / float(count - 1)
		result.append(radius * lerpf(1.0, tip_ratio, pow(t, 0.82)))
	return result

static func _sample(points: Array[Vector3], t: float) -> Vector3:
	var scaled := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var index := mini(int(floor(scaled)), points.size() - 2)
	return points[index].lerp(points[index + 1], scaled - float(index))

static func _sample_radius(radii: Array[float], t: float) -> float:
	var scaled := clampf(t, 0.0, 1.0) * float(radii.size() - 1)
	var index := mini(int(floor(scaled)), radii.size() - 2)
	return lerpf(radii[index], radii[index + 1], scaled - float(index))

static func _to_local(points: Array[Vector3], origin: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in points:
		result.append(point - origin)
	return result

static func _stats(root: Node3D) -> Dictionary:
	var result := {"triangles": 0, "bounds": AABB(), "has_bounds": false}
	_accumulate_stats(root, Transform3D.IDENTITY, result)
	return result

static func _accumulate_stats(node: Node3D, parent_transform: Transform3D, stats: Dictionary) -> void:
	var transform := parent_transform * node.transform
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh != null:
			var bounds := transform * mesh.get_aabb()
			stats.bounds = stats.bounds.merge(bounds) if stats.has_bounds else bounds
			stats.has_bounds = true
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				stats.triangles += int(indices.size() / 3)
	for child in node.get_children():
		if child is Node3D:
			_accumulate_stats(child, transform, stats)
