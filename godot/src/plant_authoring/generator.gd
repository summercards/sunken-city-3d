@tool
extends RefCounted
## 独立植物生成内核：所有资源在本次 build 内创建或 duplicate，不向场景树写入业务节点。

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const Library = preload("res://src/ambient/vegetation/library.gd")

static func build(recipe: Dictionary) -> Dictionary:
	var validation := Recipe.validate(recipe)
	if validation != "":
		return {"ok": false, "reason": validation, "root": null, "branches": [], "stats": {"triangles": 0, "leaf_count": 0, "branch_count": 0}}
	var root := Node3D.new()
	root.name = String(recipe.name) if not String(recipe.name).is_empty() else String(Species.definitions()[recipe.species].name)
	var trunk_group := _group(root, "Trunk")
	var leaves_group := _group(root, "Leaves")
	var moss_group := _group(root, "Moss")
	var vines_group := _group(root, "Vines")
	var grass_group := _group(root, "Grass")
	var trunk_mat := _material(Color("#60412f"), 0.92, false)
	var leaf_mat := _leaf_material(recipe.species, float(recipe.color_variation))
	var moss_mat := _material(Color("#5c8a45"), 0.98, true)
	var vine_mat := _material(Color("#3f6b35"), 0.94, false)
	var trunk_points := _make_trunk_points(recipe)
	var all_triangles := 0
	if recipe.trunk_visible:
		var trunk_data := _mesh_for_tube(trunk_points, _trunk_radii(recipe, trunk_points.size()), 10, trunk_mat)
		_add_mesh(trunk_group, "MainTrunk", trunk_data.mesh)
		all_triangles += trunk_data.triangles
	var branches: Array = []
	var leaf_count := 0
	var trunk_rng := RandomNumberGenerator.new()
	trunk_rng.seed = int(recipe.seed) + 101
	var leaf_rng := RandomNumberGenerator.new()
	leaf_rng.seed = int(recipe.seed) + 202
	for branch_index in int(recipe.branch_count):
		var id := "branch_%02d" % branch_index
		var override: Dictionary = recipe.branch_overrides.get(id, {})
		var enabled := bool(override.get("enabled", true))
		branches.append({"id": id, "name": _branch_name(recipe.species, branch_index)})
		if not enabled: continue
		var start_ratio := float(recipe.branch_start) / float(recipe.height)
		var parent_t := start_ratio + (1.0 - start_ratio) * (float(branch_index) + 0.35) / float(recipe.branch_count)
		var start := _sample_polyline(trunk_points, clampf(parent_t, 0.08, 0.9))
		var angle := TAU * float(branch_index) / float(recipe.branch_count) + float(override.get("angle_offset", 0.0))
		angle += trunk_rng.randf_range(-0.12, 0.12)
		var spread := float(recipe.crown_radius) * float(recipe.branch_spread) * float(override.get("length_scale", 1.0))
		var rise := float(recipe.branch_rise) - float(recipe.branch_droop) * (0.25 + 0.55 * parent_t)
		var species_key: String = recipe.species
		if species_key == "maple": rise += 0.15 * (1.0 - parent_t)
		if species_key == "birch": rise += 0.42 * (1.0 - parent_t)
		var end := start + Vector3(cos(angle) * spread, rise * spread + trunk_rng.randf_range(-0.10, 0.10), sin(angle) * spread)
		var points := _make_branch_points(start, end, species_key, parent_t, trunk_rng)
		var radius_scale := float(override.get("radius_scale", 1.0))
		var radii := _branch_radii(recipe, points.size(), radius_scale)
		var branch_node := Node3D.new()
		branch_node.name = id
		branch_node.position = start
		trunk_group.add_child(branch_node)
		var local_points := _to_local(points, start)
		var branch_data := _mesh_for_tube(local_points, radii, 7, trunk_mat)
		_add_mesh(branch_node, "Wood", branch_data.mesh)
		all_triangles += branch_data.triangles
		if recipe.leaves_visible:
			var leaf_node := Node3D.new()
			leaf_node.name = id
			leaf_node.position = start
			leaves_group.add_child(leaf_node)
			var leaf_vertices := PackedVector3Array()
			var leaf_normals := PackedVector3Array()
			var leaf_indices := PackedInt32Array()
			var cluster_count := maxi(3, int(round(5.0 + float(recipe.leaf_density) * 4.0)))
			var leaves_per_cluster := maxi(4, int(round(3.0 + float(recipe.leaf_density) * 3.0)))
			for cluster_index in cluster_count:
				var cluster_t := (float(cluster_index) + 0.35) / float(cluster_count + 0.2)
				var cluster_center := _sample_polyline(local_points, clampf(cluster_t, 0.12, 1.0))
				cluster_center += Vector3(
					leaf_rng.randf_range(-float(recipe.cluster_jitter), float(recipe.cluster_jitter)),
					leaf_rng.randf_range(-float(recipe.cluster_jitter) * 0.35, float(recipe.cluster_jitter) * 0.35),
					leaf_rng.randf_range(-float(recipe.cluster_jitter), float(recipe.cluster_jitter)))
				for leaf_index in leaves_per_cluster:
					var leaf_angle := TAU * float(leaf_index) / float(leaves_per_cluster) + leaf_rng.randf_range(-0.35, 0.35)
					var leaf_center := cluster_center + Vector3(cos(leaf_angle) * float(recipe.cluster_size) * 0.28, leaf_rng.randf_range(-0.12, 0.12), sin(leaf_angle) * float(recipe.cluster_size) * 0.28)
					var leaf_axis := Vector3(cos(leaf_angle), leaf_rng.randf_range(0.20, 0.65), sin(leaf_angle)).normalized()
					var width := float(recipe.leaf_size) * (0.86 + leaf_rng.randf_range(-float(recipe.color_variation), float(recipe.color_variation)))
					var length := _leaf_length(recipe.species, float(recipe.leaf_size)) * (0.90 + leaf_rng.randf_range(-0.10, 0.10))
					Geometry.append_leaf(leaf_center, leaf_axis, width, length, width * 0.045, _leaf_shape(recipe.species), cluster_center, float(recipe.normal_blend), leaf_vertices, leaf_normals, leaf_indices)
					leaf_count += 1
			if not leaf_vertices.is_empty():
				var leaf_mesh := _mesh_from_arrays(leaf_vertices, leaf_normals, leaf_indices, leaf_mat)
				_add_mesh(leaf_node, "Foliage", leaf_mesh)
				all_triangles += leaf_indices.size() / 3
	if recipe.moss_enabled and float(recipe.moss_amount) > 0.0:
		var moss_vertices := PackedVector3Array()
		var moss_normals := PackedVector3Array()
		var moss_indices := PackedInt32Array()
		var moss_rng := RandomNumberGenerator.new()
		moss_rng.seed = int(recipe.seed) + 303
		var moss_count := int(round(4.0 + float(recipe.moss_amount) * 12.0))
		for i in moss_count:
			var point := _sample_polyline(trunk_points, 0.12 + 0.72 * float(i + 1) / float(moss_count + 1))
			var tangent := _sample_tangent(trunk_points, 0.12 + 0.72 * float(i + 1) / float(moss_count + 1))
			var normal := tangent.cross(Vector3.UP).normalized()
			if normal.length_squared() < 0.01: normal = Vector3.RIGHT
			point += normal * float(recipe.trunk_radius) * 0.92
			Geometry.append_moss_patch(point, normal, moss_rng.randf_range(0.16, 0.32), moss_rng.randf_range(0.12, 0.26), moss_vertices, moss_normals, moss_indices)
		if not moss_vertices.is_empty():
			_add_mesh(moss_group, "AttachedPatches", _mesh_from_arrays(moss_vertices, moss_normals, moss_indices, moss_mat))
			all_triangles += moss_indices.size() / 3
	if recipe.vine_enabled and int(recipe.vine_count) > 0 and float(recipe.vine_length) > 0.0:
		var vine_vertices := PackedVector3Array()
		var vine_normals := PackedVector3Array()
		var vine_indices := PackedInt32Array()
		var vine_rng := RandomNumberGenerator.new()
		vine_rng.seed = int(recipe.seed) + 404
		for vine_index in int(recipe.vine_count):
			var attach := _sample_polyline(trunk_points, 0.28 + 0.55 * float(vine_index + 1) / float(int(recipe.vine_count) + 1))
			var vine_points: Array[Vector3] = []
			var segments := 6
			for segment in segments:
				var t := float(segment) / float(segments - 1)
				vine_points.append(attach + Vector3(sin(t * PI * 1.4 + vine_index) * 0.22, -t * float(recipe.vine_length), cos(t * PI * 1.1 + vine_index) * 0.18))
			Geometry.append_tube(vine_points, _vine_radii(vine_points.size()), 5, vine_vertices, vine_normals, vine_indices)
			for leaf_index in 4:
				var t := float(leaf_index + 1) / 5.0
				var base := vine_points[int(round(t * float(segments - 1)))]
				var side := -1.0 if leaf_index % 2 == 0 else 1.0
				Geometry.append_leaf(base, Vector3(side * 0.72, -0.18, 0.25).normalized(), 0.18, 0.30, 0.008, "oval", base, 0.2, vine_vertices, vine_normals, vine_indices)
				leaf_count += 1
		if not vine_vertices.is_empty():
			_add_mesh(vines_group, "IndependentVines", _mesh_from_arrays(vine_vertices, vine_normals, vine_indices, vine_mat))
			all_triangles += vine_indices.size() / 3
	if recipe.grass_enabled and int(recipe.grass_count) > 0:
		var grass_key: String = recipe.grass_asset
		var grass_mesh: Mesh = Library.mesh(grass_key).duplicate(true)
		grass_mesh.resource_local_to_scene = true
		var grass_material: Material = Library.material(grass_key).duplicate(true)
		grass_material.resource_local_to_scene = true
		var mm := MultiMesh.new()
		mm.resource_local_to_scene = true
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh
		mm.instance_count = int(recipe.grass_count)
		var grass_rng := RandomNumberGenerator.new()
		grass_rng.seed = int(recipe.seed) + 505
		for i in int(recipe.grass_count):
			var a := TAU * float(i) / float(recipe.grass_count)
			var radius := float(recipe.crown_radius) * 0.18 + grass_rng.randf_range(0.0, 0.35)
			var pos := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
			var scale := grass_rng.randf_range(0.7, 1.15)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, grass_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale), pos))
		var grass_visual := MultiMeshInstance3D.new()
		grass_visual.name = "GroundCover"
		grass_visual.multimesh = mm
		grass_visual.material_override = grass_material
		grass_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grass_group.add_child(grass_visual)
		all_triangles += int(grass_mesh.get_surface_count() > 0) * int(grass_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3) * int(recipe.grass_count)
	return {"ok": true, "reason": "", "root": root, "branches": branches, "stats": {"triangles": all_triangles, "leaf_count": leaf_count, "branch_count": branches.size()}}

static func _group(root: Node3D, name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	root.add_child(node)
	return node

static func _add_mesh(parent: Node3D, name: String, mesh: Mesh) -> void:
	var visual := MeshInstance3D.new()
	visual.name = name
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(visual)

static func _mesh_for_tube(points: Array[Vector3], radii: Array[float], sides: int, material: Material) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	Geometry.append_tube(points, radii, sides, vertices, normals, indices)
	return {"mesh": _mesh_from_arrays(vertices, normals, indices, material), "triangles": indices.size() / 3}

static func _mesh_from_arrays(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.resource_local_to_scene = true
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

static func _make_trunk_points(recipe: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(recipe.seed) + 101
	var height := float(recipe.height)
	for i in 7:
		var t := float(i) / 6.0
		var curve := float(recipe.trunk_curve) * sin(t * PI * 1.25)
		result.append(Vector3(curve * sin(t * TAU + 0.4), height * t, curve * cos(t * TAU + 0.4)))
	return result

static func _trunk_radii(recipe: Dictionary, count: int) -> Array[float]:
	var result: Array[float] = []
	for i in count:
		var t := float(i) / float(count - 1)
		result.append(float(recipe.trunk_radius) * lerpf(1.0, 0.12, pow(t, 0.72)))
	return result

static func _make_branch_points(start: Vector3, end: Vector3, species_key: String, parent_t: float, rng: RandomNumberGenerator) -> Array[Vector3]:
	var result: Array[Vector3] = [start]
	for i in range(1, 5):
		var t := float(i) / 4.0
		var p := start.lerp(end, t)
		p.y += sin(t * PI) * (0.18 if species_key != "birch" else 0.10)
		p += Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.05, 0.05))
		if species_key == "birch": p.y -= pow(t, 2.0) * 0.55 * parent_t
		result.append(p)
	return result

static func _branch_radii(recipe: Dictionary, count: int, scale: float) -> Array[float]:
	var result: Array[float] = []
	for i in count:
		var t := float(i) / float(count - 1)
		result.append(float(recipe.trunk_radius) * 0.42 * scale * lerpf(1.0, 0.08, pow(t, 0.8)))
	return result

static func _vine_radii(count: int) -> Array[float]:
	var result: Array[float] = []
	for i in count: result.append(0.025 * lerpf(1.0, 0.45, float(i) / float(count - 1)))
	return result

static func _to_local(points: Array[Vector3], origin: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in points: result.append(point - origin)
	return result

static func _sample_polyline(points: Array[Vector3], t: float) -> Vector3:
	var scaled := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var index := mini(int(floor(scaled)), points.size() - 2)
	return points[index].lerp(points[index + 1], scaled - float(index))

static func _sample_tangent(points: Array[Vector3], t: float) -> Vector3:
	var scaled := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var index := mini(int(floor(scaled)), points.size() - 2)
	return (points[index + 1] - points[index]).normalized()

static func _leaf_shape(species_key: String) -> String:
	if species_key == "maple": return "palmate"
	if species_key == "birch": return "triangular"
	return "oval"

static func _leaf_length(species_key: String, size: float) -> float:
	if species_key == "maple": return size * 1.08
	if species_key == "birch": return size * 0.92
	return size * 1.24

static func _branch_name(species_key: String, index: int) -> String:
	return "%s 主枝 %02d" % [String(Species.definitions()[species_key].name), index]

static func _material(color: Color, roughness: float, double_sided: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.albedo_color = color
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	return material

static func _leaf_material(species_key: String, variation: float) -> StandardMaterial3D:
	var color := Color("#72c94b")
	if species_key == "maple": color = Color("#69bd45")
	elif species_key == "birch": color = Color("#8bd653")
	color = color.lerp(Color("#a8e46d"), variation * 0.28)
	var material := _material(color, 0.82, true)
	material.vertex_color_use_as_albedo = false
	return material
