@tool
extends RefCounted
## 独立植物内核：随机流按语义 ID 派生，公共贴图只读，轻量模式按显示角色合批。

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const TrunkPath = preload("res://src/plant_authoring/trunk_path.gd")
const LightweightFoliage = preload("res://src/plant_authoring/lightweight_foliage.gd")
const FoliageBatch = preload("res://src/plant_authoring/foliage_batch.gd")
const LeafCardShader = preload("res://src/plant_authoring/leaf_card.gdshader")
const LeafVolumeShader = preload("res://src/plant_authoring/leaf_volume.gdshader")
const BARK_PATCH_BUDGET := 64
const BARK_TRIANGLE_BUDGET := 4096
const MOSS_PATCH_BUDGET := 28
const MOSS_TRIANGLE_BUDGET := 8192
const Library = preload("res://src/ambient/vegetation/library.gd")
const LeafShader = preload("res://src/plant_authoring/leaf.gdshader")
const PALETTE = preload("res://assets/textures/shared/sea_cabin_timber_8x8_512.png")
const GRASS_MASK = preload("res://assets/textures/vegetation/meadow_atlas.png")

static func build(data: Dictionary, batch_foliage: bool = true) -> Dictionary:
	var reason := Recipe.validate(data)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "root": null, "branches": [],
			"stats": {"triangles": 0, "leaf_count": 0, "branch_count": 0, "bounds": AABB()}}
	var recipe := Recipe.normalized(data)
	var lightweight: bool = recipe.foliage_mode != "geometry"
	var atlas: Texture2D = null
	var mixed_volumes: bool = recipe.foliage_mode == "volumes" and int(recipe.volume_leaf_cards) > 0
	if recipe.foliage_mode == "cards" or mixed_volumes:
		var atlas_path: String = LightweightFoliage.CLUSTER_ATLAS_PATH if mixed_volumes else LightweightFoliage.ATLAS_PATH
		if ResourceLoader.exists(atlas_path):
			atlas = load(atlas_path) as Texture2D
		if atlas == null:
			return {"ok": false, "reason": "叶卡图集尚未提供或导入：" + atlas_path, "root": null, "branches": [], "stats": {}}
		var atlas_image := atlas.get_image()
		if atlas.get_width() != 512 or atlas.get_height() != 512 or atlas_image == null or not atlas_image.has_mipmaps():
			return {"ok": false, "reason": "叶卡图集必须为 512×512，并启用导入 mipmaps/generate", "root": null, "branches": [], "stats": {}}
	var grass_source: ArrayMesh = null
	if recipe.grass_enabled and int(recipe.grass_count) > 0:
		grass_source = Library.mesh(recipe.grass_asset) as ArrayMesh
		reason = _grass_source_error(grass_source)
		if not reason.is_empty():
			return {"ok": false, "reason": "草资源 %s：%s" % [recipe.grass_asset, reason], "root": null, "branches": [], "stats": {}}
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
	var grass_material: ShaderMaterial = materials.leaf
	if lightweight:
		materials.leaf = _foliage_material("leaf", recipe, 1.0, atlas)
		materials.vine_leaf = _foliage_material("vine", recipe, 0.25, atlas)
	else:
		materials.vine_leaf = materials.vine
	if mixed_volumes:
		materials.surface_leaf = _foliage_material("leaf", recipe, 1.0, atlas, true)
	trunk_group.visible = recipe.trunk_visible
	leaves_group.visible = recipe.leaves_visible
	var trunk_points := _make_trunk_points(recipe)
	var trunk_radii := _trunk_radii(recipe, trunk_points)
	var bark_triangles := 0
	var moss_triangles := 0
	if recipe.trunk_visible:
		var trunk_mesh := _buffer()
		_tube(trunk_mesh, trunk_points, trunk_radii, 12, _cell(recipe, "trunk", "trunk"))
		_emit(trunk_group, "MainTrunk", trunk_mesh, materials.trunk)
		if float(recipe.bark_detail) > 0.0:
			bark_triangles = _build_bark(trunk_group, recipe, trunk_points, trunk_radii, materials.trunk)
	var branches: Array = []
	var leaf_count := 0
	var surface_card_count := 0
	var cluster_count := 0
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
			var surface_foliage := _buffer()
			var points: Array[Vector3] = branch.points
			var radii: Array[float] = branch.radii
			_branch_tube(wood, _to_local(points, start), radii, 8, _cell(recipe, "trunk", id), lightweight)
			for twig_index in int(recipe.subtwig_count):
				var twig_id := "%s/twig_%02d" % [id, twig_index]
				var twig := _make_twig(recipe, points, radii, twig_id, twig_index)
				var twig_points: Array[Vector3] = twig.points
				var twig_radii: Array[float] = twig.radii
				_branch_tube(wood, _to_local(twig_points, start), twig_radii, 6, _cell(recipe, "trunk", twig_id), lightweight)
				if recipe.leaves_visible:
					if recipe.foliage_mode == "volumes":
						surface_card_count += _twig_volumes(foliage, surface_foliage, recipe, _to_local(twig_points, start), twig_id)
						cluster_count += 1
						leaf_count += Recipe.leaves_per_twig(recipe)
					else:
						leaf_count += _twig_leaves(foliage, recipe, definition, _to_local(twig_points, start), twig_radii, twig_id)
			var wood_mesh := _mesh(wood, materials.trunk)
			branch_bounds = AABB(start, Vector3.ZERO) if wood_mesh == null else AABB(wood_mesh.get_aabb().position + start, wood_mesh.get_aabb().size)
			if recipe.trunk_visible and wood_mesh != null:
				_add_mesh(wood_node, "Wood", wood_mesh)
			var leaf_mesh := _emit(leaf_node, "Foliage", foliage, materials.leaf)
			if leaf_mesh != null:
				branch_bounds = branch_bounds.merge(AABB(leaf_mesh.get_aabb().position + start, leaf_mesh.get_aabb().size))
			if mixed_volumes:
				var surface_mesh := _emit(leaf_node, "SurfaceFoliage", surface_foliage, materials.surface_leaf)
				if surface_mesh != null:
					branch_bounds = branch_bounds.merge(AABB(surface_mesh.get_aabb().position + start, surface_mesh.get_aabb().size))
		wood_node.set_meta("branch_id", id)
		leaf_node.set_meta("branch_id", id)
		wood_node.set_meta("branch_bounds", branch_bounds)
		leaf_node.set_meta("branch_bounds", branch_bounds)
		branches.append({
			"id": id, "name": "%s 主枝 %02d" % [definition.name, index],
			"node_path": NodePath("Trunk/" + id), "leaf_node_path": NodePath("Leaves/" + id),
			"position": start, "bounds": branch_bounds, "enabled": enabled
		})
	if recipe.trunk_visible and recipe.moss_enabled and float(recipe.moss_amount) > 0.0:
		moss_triangles = _build_moss(moss_group, recipe, trunk_points, trunk_radii, materials.moss)
	if recipe.vine_enabled and int(recipe.vine_count) > 0 and float(recipe.vine_length) > 0.0:
		leaf_count += _build_vines(vines_group, recipe, trunk_points, trunk_radii, materials.vine, materials.vine_leaf)
	if recipe.grass_enabled and int(recipe.grass_count) > 0:
		reason = _build_grass(grass_group, recipe, grass_material, grass_source)
		if not reason.is_empty():
			root.free()
			return {"ok": false, "reason": "草资源 %s：%s" % [recipe.grass_asset, reason], "root": null, "branches": [], "stats": {}}
	if lightweight and batch_foliage:
		for group: Node3D in [trunk_group, leaves_group, moss_group, vines_group, grass_group]:
			FoliageBatch.merge_group(group)
	root.set_meta("foliage_mode", recipe.foliage_mode)
	root.set_meta("foliage_batched", lightweight and batch_foliage)
	root.set_meta("plant_branches", branches.duplicate(true))
	var stats := _stats(root)
	stats.foliage_mode = recipe.foliage_mode
	stats.batched = lightweight and batch_foliage
	stats.cluster_count = cluster_count
	stats.surface_card_count = surface_card_count
	# 叶团表示的叶数仍与配方预算一致；实际簇数和叶卡数分别报告，不冒称逐叶网格。
	stats.leaf_count = leaf_count
	stats.card_count = leaf_count if recipe.foliage_mode == "cards" else surface_card_count
	stats.branch_count = active_branches
	stats.branch_slots = int(recipe.branch_count)
	stats.subtwig_count = active_branches * int(recipe.subtwig_count)
	stats.leaf_budget = Recipe.LEAF_BUDGET
	stats.bark_triangles = bark_triangles
	stats.moss_triangles = moss_triangles
	stats.bark_patch_budget = BARK_PATCH_BUDGET
	stats.moss_patch_budget = MOSS_PATCH_BUDGET
	stats.bark_triangle_budget = BARK_TRIANGLE_BUDGET
	stats.moss_triangle_budget = MOSS_TRIANGLE_BUDGET
	stats.trunk_rings = trunk_points.size()
	# 分组均在根局部原点；分枝 bounds 已含 start，便于 UI 精确聚焦附生部分。
	var attachment_bounds := {
		"trunk": Geometry.tube_bounds(trunk_points, trunk_radii),
		"moss": _stats(moss_group).bounds, "vines": _stats(vines_group).bounds,
		"leaves": _stats(leaves_group).bounds, "branches": {}
	}
	for branch: Dictionary in branches:
		attachment_bounds.branches[branch.id] = branch.bounds
	Geometry.bind_trunk_metadata(root, recipe, trunk_points, trunk_radii, attachment_bounds)
	return {"ok": true, "reason": "", "root": root, "branches": branches, "stats": stats}

static func _make_trunk_points(recipe: Dictionary) -> Array[Vector3]:
	return TrunkPath.points(recipe)

static func _trunk_radii(recipe: Dictionary, points: Array[Vector3]) -> Array[float]:
	if recipe.trunk_path.is_empty():
		return _taper(float(recipe.trunk_radius), points.size(), 0.065)
	var radii: Array[float] = []
	for point in points:
		var t := point.y / float(recipe.height)
		radii.append(float(recipe.trunk_radius) * lerpf(1.0, 0.065, pow(t, 0.82)))
	return radii

static func _trunk_station(recipe: Dictionary, points: Array[Vector3], height_ratio: float) -> float:
	# 旧自动干等距采样保持原算式；手动干按实际 y 查找非均匀环索引。
	if recipe.trunk_path.is_empty():
		return height_ratio
	return Geometry.tube_height_station(points, height_ratio * float(recipe.height))

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
	t = _trunk_station(recipe, trunk, t)
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
		var axis := (radial + forward * 0.22 + Vector3.UP * (0.32 if recipe.species != "birch" else -0.16)).normalized()
		var size := float(recipe.leaf_size) * _range(recipe, rng, 0.84, 1.14)
		if recipe.foliage_mode == "cards":
			var card_size := LightweightFoliage.card_size(definition.leaf_shape, size * float(definition.leaf_width_ratio), size * float(definition.leaf_length_ratio))
			LightweightFoliage.append_petiole(buffer, base, center, _cell(recipe, "leaf", "%s/petiole_%03d" % [id, index]))
			LightweightFoliage.append_card(buffer, center, axis, card_size.x, card_size.y, recipe.species, _cell(recipe, "leaf", "%s/leaf_%03d" % [id, index]), cluster_center, float(recipe.normal_blend))
			continue
		var stalk: Array[Vector3] = [base, center]
		_tube(buffer, stalk, _taper(0.004, 2, 0.65), 4, _cell(recipe, "leaf", "%s/petiole_%03d" % [id, index]))
		var leaf_start: int = buffer.v.size()
		Geometry.append_leaf(center, axis, size * float(definition.leaf_width_ratio), size * float(definition.leaf_length_ratio), size * 0.09, definition.leaf_shape, cluster_center, float(recipe.normal_blend), buffer.v, buffer.n, buffer.i, buffer.uv, _cell(recipe, "leaf", "%s/leaf_%03d" % [id, index]), int(definition.leaf_subdivisions), float(definition.leaf_tip), float(definition.leaf_cup), recipe.leaf_geometry)
		# 显式作者权重沿用 runtime 的距离公式；叶柄保持零，顶点索引布局不再是协议。
		var reach := 0.01
		for vertex in range(leaf_start, buffer.v.size()):
			reach = maxf(reach, center.distance_to(buffer.v[vertex]))
		for vertex in range(buffer.colors.size(), buffer.v.size()):
			var weight := 0.0 if vertex < leaf_start else smoothstep(0.01, reach, center.distance_to(buffer.v[vertex]))
			buffer.colors.append(Color(weight, 0.0, 0.0, 1.0))
	return count

static func _twig_volumes(buffer: Dictionary, cards: Dictionary, recipe: Dictionary, points: Array[Vector3], id: String) -> int:
	var rng := _rng(recipe, id + "/volume")
	var center := _sample(points, 0.64)
	center += Vector3(_range(recipe, rng, -0.3, 0.3), _range(recipe, rng, -0.12, 0.12), _range(recipe, rng, -0.3, 0.3)) * float(recipe.cluster_jitter)
	var size := float(recipe.cluster_size) * sqrt(float(recipe.leaf_density)) * (0.65 + float(recipe.leaf_size))
	var radii := Vector3(size * 0.82, size * 0.64, size * 0.82)
	if recipe.species == "maple":
		radii *= Vector3(1.12, 0.52, 1.12)
	elif recipe.species == "birch":
		radii *= Vector3(0.65, 1.22, 0.65)
	var shade := 1.0
	if recipe.color_mode == "auto":
		# COLOR 按归一化通道存储，明度保持在 0..1，不依赖溢出值。
		shade -= _range(recipe, rng, 0.0, 0.56) * float(recipe.color_variation) * _variation(recipe)
	# 同一色格只变明度，任意用户选色都不会随机跳去另一色相。
	var count := int(recipe.volume_leaf_cards)
	var core_radii := radii * (0.65 if count > 0 else 1.0)
	# 混合内芯只填补叶束缝隙，使用连续平滑法线；纯体块保持原尺寸与法线参数。
	LightweightFoliage.append_volume(buffer, center, core_radii, int(recipe.leaf_cell), 1.0 if count > 0 else float(recipe.normal_blend), shade * (0.98 if count > 0 else 1.0))
	# 独立语义流，增加外叶数量不会重抽体块位置、色差或木质枝条。
	var shell_rng := _rng(recipe, id + "/surface_leaves")
	var rotation := _range(recipe, shell_rng, -PI, PI)
	for index in count:
		var leaf_rng := _rng(recipe, "%s/surface_leaf_%02d" % [id, index])
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
		var angle := float(index) * 2.3999632297 + rotation
		var radial := sqrt(maxf(0.0, 1.0 - y * y))
		var direction := Vector3(cos(angle) * radial, y, sin(angle) * radial)
		var shell := LightweightFoliage.volume_shell(direction, core_radii)
		var outward := (shell / (core_radii * core_radii)).normalized()
		var tangent := outward.cross(Vector3.UP)
		if tangent.length_squared() < 0.00001:
			tangent = outward.cross(Vector3.RIGHT)
		tangent = tangent.normalized().rotated(outward, _range(recipe, leaf_rng, -PI, PI))
		var tilt := _range(recipe, leaf_rng, 0.30, 0.62)
		var axis := (tangent + outward * tilt).normalized()
		var side_axis := axis.cross(outward).normalized()
		# 一张图是多叶束，覆盖尺度取原簇在卡面方向上的半径，而非旧单叶尺寸。
		var span_width := (radii * side_axis).length()
		var span_length := (radii * axis).length()
		var coverage := _range(recipe, leaf_rng, 0.94, 1.08)
		var dimensions := Vector2(span_width * 2.15, span_length * 1.85) * coverage
		# 根沿缩小内芯的实际凸壳埋入，宽叶束相互覆盖内芯，不添加大交叉整冠平面。
		var base := center + shell * 0.78
		var first: int = cards.v.size()
		LightweightFoliage.append_card(cards, base, axis, dimensions.x, dimensions.y, recipe.species, int(recipe.leaf_cell), center, maxf(0.85, float(recipe.normal_blend)), outward, side_axis)
		for vertex in range(first, cards.v.size()):
			var relative: Vector3 = cards.v[vertex] - center
			var body_weight := 0.25 + 0.45 * clampf((relative.y / core_radii.y + 1.0) * 0.5, 0.0, 1.0)
			cards.colors[vertex].r = lerpf(body_weight, 0.9, cards.colors[vertex].r * 0.65)
			cards.colors[vertex].b = 0.96 + 0.04 * maxf(outward.y, 0.0)
	return count

static func _branch_tube(buffer: Dictionary, points: Array[Vector3], radii: Array[float], sides: int, cell: int, lightweight: bool) -> void:
	if not lightweight:
		_tube(buffer, points, radii, sides, cell)
		return
	var sampled_points: Array[Vector3] = []
	var sampled_radii: Array[float] = []
	for index in range(0, points.size(), 2):
		sampled_points.append(points[index])
		sampled_radii.append(radii[index])
	if sampled_points[-1] != points[-1]:
		sampled_points.append(points[-1])
		sampled_radii.append(radii[-1])
	_tube(buffer, sampled_points, sampled_radii, 5 if sides >= 8 else 4, cell)

static func _build_moss(parent: Node3D, recipe: Dictionary, points: Array[Vector3], radii: Array[float], material: Material) -> int:
	var buffer := _buffer()
	var count := int(ceil(float(recipe.moss_amount) * float(MOSS_PATCH_BUDGET)))
	var emitted := 0
	for index in count:
		var id := "moss_%02d" % index
		var rng := _rng(recipe, id)
		var height_t := clampf(0.08 + fposmod(index * 0.61803398875, 1.0) * 0.64 + _range(recipe, rng, -0.04, 0.04), 0.04, 0.78)
		height_t *= float(recipe.moss_height) / 0.78
		var t := _trunk_station(recipe, points, height_t)
		var angle := index * 2.3999632297 + _range(recipe, rng, -0.4, 0.4) + float(recipe.moss_bias)
		var scale_ratio := float(recipe.moss_scale) / 0.175
		var length := _range(recipe, rng, 0.10, 0.25) * scale_ratio
		var angle_width := minf(TAU, _range(recipe, rng, 0.5, 1.3) * scale_ratio)
		var span := Geometry.tube_length_span(points, t, length)
		span.y = minf(span.y, _trunk_station(recipe, points, float(recipe.moss_height)))
		# 默认自动干保留旧苔藓网格；手动路径与改尺寸时按实际弧长贴合。
		if recipe.trunk_path.is_empty() and float(recipe.moss_scale) == 0.175 and float(recipe.moss_height) == 0.78:
			span = Vector2(-1.0, -1.0)
		emitted += Geometry.append_moss_on_tube(points, radii, t, length / float(recipe.height), angle, angle_width, buffer.v, buffer.n, buffer.i, buffer.uv, _cell(recipe, "moss", id), span, MOSS_TRIANGLE_BUDGET - emitted)
		if emitted >= MOSS_TRIANGLE_BUDGET:
			break
	_emit(parent, "AttachedPatches", buffer, material)
	return emitted

static func _build_bark(parent: Node3D, recipe: Dictionary, points: Array[Vector3], radii: Array[float], material: Material) -> int:
	var buffer := _buffer()
	var count := int(ceil(float(recipe.bark_detail) * float(BARK_PATCH_BUDGET)))
	var emitted := 0
	for index in count:
		var rng := _rng(recipe, "bark/detail_%02d" % index)
		var height_t := 0.025 + fposmod(float(index) * 0.61803398875, 1.0) * 0.94
		var t := _trunk_station(recipe, points, height_t)
		var angle := float(index) * 2.3999632297 + _range(recipe, rng, -0.25, 0.25)
		var length := _range(recipe, rng, 0.08, 0.32)
		var span := Geometry.tube_length_span(points, t, length)
		# bark_cell 是 trunk 材质的显式次色，不随机改动 trunk_cell 或新增材质角色。
		emitted += Geometry.append_moss_on_tube(points, radii, t, length / float(recipe.height), angle, 0.12 + float(recipe.bark_detail) * 0.20, buffer.v, buffer.n, buffer.i, buffer.uv, int(recipe.bark_cell), span, BARK_TRIANGLE_BUDGET - emitted, 0.0008)
		if emitted >= BARK_TRIANGLE_BUDGET:
			break
	_emit(parent, "BarkDetail", buffer, material)
	return emitted

static func _build_vines(parent: Node3D, recipe: Dictionary, trunk: Array[Vector3], radii: Array[float], material: Material, foliage_material: Material) -> int:
	for index in int(recipe.vine_count):
		var id := "vine_%02d" % index
		var rng := _rng(recipe, id + "/path")
		var t := clampf(0.36 + fposmod(index * 0.38196601125, 1.0) * 0.40 + _range(recipe, rng, -0.05, 0.05), 0.30, 0.83)
		var angle := index * 2.3999632297 + _range(recipe, rng, -0.35, 0.35)
		t = _trunk_station(recipe, trunk, t)
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
		var foliage := _buffer()
		_branch_tube(buffer, points, _taper(0.017, points.size(), 0.45), 5, _cell(recipe, "vine", id), recipe.foliage_mode != "geometry")
		for leaf_index in 4:
			var base := _sample(points, float(leaf_index + 1) / 5.0)
			var side := -1.0 if leaf_index % 2 == 0 else 1.0
			var axis := Vector3(side * 0.72, -0.18, 0.3).normalized()
			var cell := _cell(recipe, "vine", "%s/leaf_%02d" % [id, leaf_index])
			if recipe.foliage_mode == "cards":
				var card_size := LightweightFoliage.card_size("oval", 0.10, 0.27)
				LightweightFoliage.append_card(foliage, base, axis, card_size.x, card_size.y, "vine", cell, base + Vector3.DOWN * 0.12, 0.35)
			elif recipe.foliage_mode == "volumes":
				LightweightFoliage.append_volume(foliage, base + axis * 0.12, Vector3(0.12, 0.035, 0.09), int(recipe.vine_cell), 0.35)
			else:
				Geometry.append_leaf(base, axis, 0.10, 0.27, 0.018, "oval", base + Vector3.DOWN * 0.12, 0.35, buffer.v, buffer.n, buffer.i, buffer.uv, cell, 4, 1.0, 0.75, recipe.leaf_geometry)
		var top := -INF
		var bottom := INF
		for point: Vector3 in buffer.v:
			top = maxf(top, point.y)
			bottom = minf(bottom, point.y)
		for point: Vector3 in buffer.v:
			buffer.colors.append(Color(smoothstep(0.04, maxf(0.05, top - bottom), top - point.y), 0.0, 0.0, 1.0))
		# 藤叶根不能沿用树叶卡的零权重；按同一藤茎高度域继承位移，细节相位同为零。
		for vertex in foliage.v.size():
			var weight := smoothstep(0.04, maxf(0.05, top - bottom), top - foliage.v[vertex].y)
			foliage.colors[vertex].r = weight
			foliage.colors[vertex].g = 0.0
		_emit(parent, id, buffer, material)
		_emit(parent, id + "_Leaves", foliage, foliage_material)
	return int(recipe.vine_count) * 4

static func _grass_source_error(source: ArrayMesh) -> String:
	if source == null:
		return "网格缺失、尚未导入或不是 ArrayMesh"
	if source.get_surface_count() == 0:
		return "网格没有表面"
	for surface in source.get_surface_count():
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return "表面 %d 不是三角面" % surface
		var reason := _grass_surface_error(source.surface_get_arrays(surface))
		if not reason.is_empty():
			return "表面 %d：%s" % [surface, reason]
	return ""

static func _grass_surface_error(arrays: Array) -> String:
	if arrays.size() != Mesh.ARRAY_MAX:
		return "网格数组长度无效"
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		return "顶点数组缺失或类型错误"
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if positions.is_empty():
		return "顶点数组为空"
	if not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		return "UV 数组缺失或类型错误"
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.size() != positions.size():
		return "UV 与顶点数量不一致"
	for vertex in positions.size():
		if not positions[vertex].is_finite() or not uvs[vertex].is_finite():
			return "顶点或 UV 含非有限数"
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	if normals != null:
		if not normals is PackedVector3Array:
			return "法线数组类型错误"
		if normals.size() == positions.size():
			for normal: Vector3 in normals:
				if not normal.is_finite():
					return "法线含非有限数"
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices != null and not indices is PackedInt32Array:
		return "索引数组类型错误"
	if indices == null or indices.is_empty():
		if positions.size() % 3 != 0:
			return "非索引顶点数量不是三的倍数"
	else:
		if indices.size() % 3 != 0:
			return "索引数量不是三的倍数"
		for index: int in indices:
			if index < 0 or index >= positions.size():
				return "索引超出顶点范围"
	return ""

static func _build_grass(parent: Node3D, recipe: Dictionary, material: Material, source: ArrayMesh = null) -> String:
	if source == null:
		source = Library.mesh(recipe.grass_asset) as ArrayMesh
	var reason := _grass_source_error(source)
	if not reason.is_empty():
		return reason
	# 只复用源几何深副本；重建 UV 并绑定本地叶材质，绝不消费原全局风 Shader。
	source = source.duplicate(true) as ArrayMesh
	if source == null:
		return "网格复制失败"
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
			var arrays := source.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ns := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				ns = arrays[Mesh.ARRAY_NORMAL]
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
	var height := 0.01
	for point: Vector3 in buffer.v:
		height = maxf(height, point.y)
	for point: Vector3 in buffer.v:
		buffer.colors.append(Color(clampf(point.y / height, 0.0, 1.0), 0.0, 0.0, 1.0))
	if _emit(parent, "GroundCover", buffer, material) == null:
		return "草网格未生成"
	return ""

static func _cell(recipe: Dictionary, role: String, id: String) -> int:
	var selected := int(recipe[role + "_cell"])
	# 木质 base 色严格命中所选格；树皮次色只由显式 bark_cell 面岛提供。
	if role == "trunk":
		return selected
	var color_variation := float(recipe.moss_color_variation) if role == "moss" else float(recipe.color_variation)
	if recipe.color_mode == "manual" or _variation(recipe) <= 0.0 or color_variation <= 0.0:
		return selected
	# 只在已知连续同色族内作相邻一级变化，不把绿色跳到蓝色/粉色。
	var families := [[0, 1, 2, 3, 4, 5], [8, 9, 10, 11, 12, 13, 14, 15],
		[24, 25, 26, 27, 28, 29, 30, 31], [32, 33, 34, 35, 36],
		[40, 41, 42, 43, 44, 45], [56, 57, 58, 59, 60, 61, 62, 63]]
	var rng := _rng(recipe, "palette/" + role + "/" + id)
	if rng.randf() > color_variation * _variation(recipe):
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
	material.set_shader_parameter("wind_vertex_weights", role in ["leaf", "vine"])
	material.set_shader_parameter("surface_roughness", roughness)
	return material

static func _foliage_material(role: String, recipe: Dictionary, weight: float, atlas: Texture2D, force_cards: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = "Plant_" + role
	material.resource_local_to_scene = true
	if recipe.foliage_mode == "volumes" and not force_cards:
		material.shader = LeafVolumeShader
		var cell := int(recipe[role + "_cell"])
		var image := PALETTE.get_image()
		if image.is_compressed():
			image.decompress()
		material.set_shader_parameter("palette_color", image.get_pixel((cell % 8) * 64 + 32, int(cell / 8) * 64 + 32))
	else:
		material.shader = LeafCardShader
		material.set_shader_parameter("palette_texture", PALETTE)
		if atlas != null:
			material.set_shader_parameter("leaf_atlas", atlas)
	if recipe.foliage_mode == "volumes" and int(recipe.volume_leaf_cards) > 0 and role == "leaf":
		# 内芯与外叶同一低饱和色域，避免亮叶与深绿块面割裂；不锁死任何色板格。
		material.set_shader_parameter("palette_saturation", 0.70)
		material.set_shader_parameter("palette_value", 0.88)
		if force_cards:
			material.set_shader_parameter("detail_range", Vector2(0.70, 1.08))
			material.set_shader_parameter("detail_scale", 1.15)
	material.set_shader_parameter("local_time", 0.0)
	material.set_shader_parameter("preview_wind", false)
	material.set_shader_parameter("wind_strength", float(recipe.wind_strength))
	material.set_shader_parameter("wind_speed", float(recipe.wind_speed))
	material.set_shader_parameter("wind_weight", weight)
	material.set_shader_parameter("wind_vertex_weights", true)
	material.set_shader_parameter("surface_roughness", 0.86)
	return material

static func _buffer() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "colors": PackedColorArray()}

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
	if not buffer.colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = buffer.colors
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
	var result := {"triangles": 0, "vertices": 0, "mesh_nodes": 0, "surfaces": 0, "bounds": AABB(), "has_bounds": false}
	_accumulate_stats(root, Transform3D.IDENTITY, result)
	return result

static func _accumulate_stats(node: Node3D, parent_transform: Transform3D, stats: Dictionary) -> void:
	var transform := parent_transform * node.transform
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh != null:
			stats.mesh_nodes += 1
			stats.surfaces += mesh.get_surface_count()
			var bounds := transform * mesh.get_aabb()
			stats.bounds = stats.bounds.merge(bounds) if stats.has_bounds else bounds
			stats.has_bounds = true
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				stats.vertices += arrays[Mesh.ARRAY_VERTEX].size()
				stats.triangles += int(indices.size() / 3)
	for child in node.get_children():
		if child is Node3D:
			_accumulate_stats(child, transform, stats)
