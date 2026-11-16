extends RefCounted
## 编辑时生成静态层级；生成结果不挂本脚本，也不依赖工坊房屋core。

const Recipe = preload("res://src/building_attachments/recipe.gd")
const Catalog = preload("res://src/building_attachments/catalog.gd")
const Geometry = preload("res://src/building_attachments/geometry.gd")
const Signage = preload("res://src/building_attachments/signage.gd")
const HVAC = preload("res://src/building_attachments/hvac.gd")
const Water = preload("res://src/building_attachments/water.gd")
const Shelter = preload("res://src/building_attachments/shelter.gd")
const GENERATOR_VERSION := "sea_attachments_native_v2_support"

static func build(recipe: Dictionary) -> Dictionary:
	var reason: String = Recipe.validate(recipe)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "root": null, "recipe": recipe.duplicate(true), "stats": {}}
	var entry: Dictionary = Catalog.get_entry(recipe.type_id)
	var geometry := Geometry.new(recipe)
	var author: RefCounted
	match str(entry.category):
		"signage": author = Signage.new(geometry, recipe)
		"hvac": author = HVAC.new(geometry, recipe)
		"water": author = Water.new(geometry, recipe)
		"shelter": author = Shelter.new(geometry, recipe)
		_: return {"ok": false, "reason": "未知目录族", "root": null, "stats": {}}
	var authored: Variant = author.build()
	if authored != true:
		geometry.errors.append("作者构建未显式完成")
	if geometry.errors.is_empty():
		geometry.recenter()
	if not geometry.validate():
		return {"ok": false, "reason": "几何构建拒绝：" + "; ".join(geometry.errors), "errors": geometry.errors.duplicate(), "root": null, "recipe": recipe.duplicate(true), "stats": {}}
	if recipe.collision_enabled and geometry.proxies.is_empty():
		return {"ok": false, "reason": "启用碰撞但实体代理为空", "errors": ["启用碰撞但实体代理为空"], "root": null, "recipe": recipe.duplicate(true), "stats": {}}
	var snapshot: Dictionary = geometry.snapshot()
	if snapshot.meshes.is_empty() or snapshot.meshes.size() > 4:
		return {"ok": false, "reason": "材质surface数量必须为1..4", "root": null, "recipe": recipe.duplicate(true), "stats": {}}
	snapshot.generator_version = GENERATOR_VERSION
	snapshot.recipe = recipe.duplicate(true)
	snapshot.provenance = Catalog.definitions().source
	var anchor_name: String = str(entry.anchor)
	var bounds: AABB = geometry.all_bounds
	var anchor_position := Vector3.ZERO
	if anchor_name == "mount_back":
		anchor_position = Vector3(0, bounds.get_center().y, bounds.end.z)
	var anchor: Dictionary = {"name": anchor_name, "position": Geometry.vec(anchor_position), "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "front_axis": "-Z", "up_axis": "+Y"}
	snapshot.mount_anchor = anchor
	var text_stats: Array = author.text_stats if str(entry.category) == "signage" else []
	snapshot.text = {"input": recipe.text, "preserved": true, "faces": text_stats}
	var triangle_count: int = 0
	var vertex_count: int = 0
	for mesh: Dictionary in snapshot.meshes:
		triangle_count += mesh.indices.size() / 3
		vertex_count += mesh.vertices.size()
	var budget: int = mini(int(entry.get("long_text_budget", entry.budget)), 3500) if recipe.text.length() > 8 else mini(int(entry.budget), 1800)
	if triangle_count > budget:
		return {"ok": false, "reason": "三角面预算拒绝：%d > %d；原输入完整保留" % [triangle_count, budget], "root": null, "recipe": recipe.duplicate(true), "stats": {"triangles": triangle_count, "budget": budget}}
	for face: Dictionary in text_stats:
		for glyph: Dictionary in face.glyphs:
			if int(glyph.triangles) > 128:
				return {"ok": false, "reason": "字形预算超过128三角面", "root": null, "recipe": recipe.duplicate(true), "stats": {}}
	var root := Node3D.new()
	root.name = str(recipe.attachment_id)
	root.set_meta("visual_only", true)
	root.set_meta("attachment_type_id", str(recipe.type_id))
	root.set_meta("attachment_condition", str(recipe.condition))
	root.set_meta("attachment_recipe", recipe.duplicate(true))
	root.set_meta("generator_version", GENERATOR_VERSION)
	root.set_meta("text_input", str(recipe.text))
	root.set_meta("usage", str(recipe.usage))
	root.set_meta("collision_enabled", bool(recipe.collision_enabled))
	root.set_meta("world_derivation", "excluded_visual_only")
	root.set_meta("physics_contract", "explicit_static_layer_256_not_water_navigation_or_dive")
	var materials: Dictionary = Catalog.definitions().materials
	for source_mesh: Dictionary in snapshot.meshes:
		var mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for value: Array in source_mesh.vertices:
			vertices.append(Geometry.from_vec(value))
		for value: Array in source_mesh.normals:
			normals.append(Geometry.from_vec(value))
		for value: Array in source_mesh.uv:
			uvs.append(Vector2(float(value[0]), float(value[1])))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(source_mesh.indices)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material: Material = load(str(materials[source_mesh.material_role])) as Material
		if material == null:
			root.free()
			return {"ok": false, "reason": "正式solar_cabin材质不可加载：" + str(source_mesh.material_role), "root": null, "recipe": recipe.duplicate(true), "stats": {}}
		mesh.surface_set_material(0, material)
		mesh.surface_set_name(0, str(source_mesh.material_role))
		var node := MeshInstance3D.new()
		node.name = str(source_mesh.material_role)
		node.mesh = mesh
		node.set_meta("visual_only", true)
		node.set_meta("uv_layer", "PaletteUV")
		root.add_child(node)
		node.owner = root
		node.set_instance_shader_parameter("sea_material_role", Catalog.ROLES.find(str(source_mesh.material_role)))
	var mount := Marker3D.new()
	mount.name = anchor_name
	mount.position = anchor_position
	root.add_child(mount)
	mount.owner = root
	var shape_count: int = 0
	if recipe.collision_enabled:
		var body := StaticBody3D.new()
		body.name = "AttachmentCollision"
		body.collision_layer = 256
		body.collision_mask = 0
		root.add_child(body)
		body.owner = root
		for item: Dictionary in snapshot.collision_proxies:
			var points := PackedVector3Array()
			for value: Array in item.points:
				points.append(Geometry.from_vec(value))
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			var node := CollisionShape3D.new()
			node.name = "Proxy_%03d" % shape_count
			node.shape = shape
			node.set_meta("source_part", str(item.part))
			body.add_child(node)
			node.owner = root
			shape_count += 1
	var fingerprint: Dictionary = fingerprints(snapshot)
	var stats: Dictionary = {"triangles": triangle_count, "vertices": vertex_count, "surfaces": snapshot.meshes.size(), "mesh_nodes": snapshot.meshes.size(), "bounds": snapshot.bounds.duplicate(true), "physics_bodies": 1 if recipe.collision_enabled else 0, "collision_shapes": shape_count, "collision_proxy_count": snapshot.collision_proxies.size(), "budget": budget, "source_part_count": snapshot.source_parts.size(), "text": text_stats, "fingerprint": fingerprint}
	root.set_meta("geometry_fingerprint", fingerprint.geometry_sha256)
	return {"ok": true, "reason": "", "root": root, "recipe": recipe.duplicate(true), "stats": stats, "snapshot": snapshot, "source_parts": snapshot.source_parts, "mount_anchor": anchor, "fingerprint": fingerprint}

static func fingerprints(snapshot: Dictionary) -> Dictionary:
	var bounds: Dictionary = snapshot.bounds
	var size: Vector3 = Geometry.from_vec(bounds.size)
	var origin: Vector3 = Geometry.from_vec(bounds.position)
	var triangles: Array[String] = []
	var normalized: Array[String] = []
	var cells: Dictionary = {}
	for mesh: Dictionary in snapshot.meshes:
		for i: int in range(0, mesh.indices.size(), 3):
			var actual_points: Array[String] = []
			var normalized_points: Array[String] = []
			for j: int in range(3):
				var point: Vector3 = Geometry.from_vec(mesh.vertices[int(mesh.indices[i + j])])
				actual_points.append("%d,%d,%d" % [roundi(point.x * 100000), roundi(point.y * 100000), roundi(point.z * 100000)])
				var unit: Vector3 = (point - origin) / size
				normalized_points.append("%d,%d,%d" % [roundi(unit.x * 1000), roundi(unit.y * 1000), roundi(unit.z * 1000)])
				cells["%d,%d,%d" % [mini(15, int(unit.x * 16)), mini(15, int(unit.y * 16)), mini(15, int(unit.z * 16))]] = true
			actual_points.sort()
			normalized_points.sort()
			triangles.append("/".join(actual_points))
			normalized.append("/".join(normalized_points))
	triangles.sort()
	normalized.sort()
	var occupancy: Array = cells.keys()
	occupancy.sort()
	return {"algorithm": "quantized_sorted_triangles_v1", "geometry_sha256": "|".join(triangles).sha256_text(), "normalized_sha256": "|".join(normalized).sha256_text(), "occupancy_16_sha256": "|".join(occupancy).sha256_text(), "occupied_cells": cells.size(), "triangle_count": triangles.size(), "normalization": "AABB_unit_scale_translation_invariant_no_type_id_salt"}
