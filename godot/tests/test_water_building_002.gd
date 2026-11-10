extends SceneTree

const PREFIX := "res://scenes/components/facilities/water_building_002/"
const ASSEMBLY := "res://scenes/facilities/water_building_002.tscn"
const RUNTIME_DATA := "res://assets/data/water_building_002_instances.json"
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const ROLE_MATERIALS := {
	"res://assets/materials/solar_cabin/sunny_matte.tres": "SEA_Matte",
	"res://assets/materials/solar_cabin/sunny_metal.tres": "SEA_Metal",
	"res://assets/materials/solar_cabin/sunny_gloss.tres": "SEA_Gloss",
}

var checks := 0
var failures := 0
var main: Node
var assembly: Node3D

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func triangle_count(node: Node) -> int:
	var total := 0
	for visual in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := visual as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			total += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(vertices.size() / 3)
	return total

func serialized_overrides(packed: PackedScene) -> Array:
	var result: Array = []
	var state := packed.get_state()
	for node_index in state.get_node_count():
		for property_index in state.get_node_property_count(node_index):
			var property := str(state.get_node_property_name(node_index, property_index))
			if not property.begins_with("surface_material_override"):
				continue
			var material := state.get_node_property_value(node_index, property_index) as Material
			result.append(material.resource_path if material != null else "")
	return result

func check_components() -> void:
	var files := DirAccess.get_files_at(PREFIX)
	var count := 0
	for file in files:
		if not file.ends_with(".tscn"):
			continue
		count += 1
		var packed := load(PREFIX + file) as PackedScene
		check(packed != null, file + " wrapper loads independently")
		if packed == null:
			continue
		var component := packed.instantiate() as Node3D
		check(component != null and component.transform.is_equal_approx(Transform3D.IDENTITY), file + " root identity")
		check(component.get_meta("source_version", "") == "v003", file + " v003 metadata")
		check(component.get_meta("asset_id", "") != "", file + " asset metadata")
		check(component.get_meta("water_layer", "") != "", file + " water layer metadata")
		check(component.get_meta("category", "") != "", file + " category metadata")
		var meshes := component.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), file + " imported mesh exists")
		for mesh_node in meshes:
			var mesh := mesh_node as MeshInstance3D
			check(mesh.mesh != null, file + " real mesh resource")
			check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, file + " shadow on")
			if mesh.mesh == null:
				component.free()
				continue
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as ShaderMaterial
				check(material != null, file + " serialized role material")
				if material == null:
					continue
				var palette := material.get_shader_parameter("palette") as Texture2D
				check(palette != null and palette.resource_path == PALETTE, file + " unique timber palette")
		var overrides := serialized_overrides(packed)
		check(not overrides.is_empty(), file + " serialized surface override")
		for path in overrides:
			check(ROLE_MATERIALS.has(path), file + " existing three-role material")
		component.free()
	check(count == 28, "28 stable wrappers")

func expected_transform(values: Array) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(float(values[0]), float(values[1]), float(values[2])),
			Vector3(float(values[3]), float(values[4]), float(values[5])),
			Vector3(float(values[6]), float(values[7]), float(values[8]))
		),
		Vector3(float(values[9]), float(values[10]), float(values[11]))
	)

func min_rect_position(rects: Array) -> Vector2:
	var result := Vector2(INF, INF)
	for rect in rects:
		var value := rect as Rect2
		result.x = minf(result.x, value.position.x)
		result.y = minf(result.y, value.position.y)
	return result

func configure_real_main() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	if main.cam != null:
		main.cam.set_process(false)
		main.cam.suspend_follow()
	if main.boat != null:
		main.boat.set_process(false)
	if main.hud != null:
		main.hud.hide()
	var economy := root.get_node_or_null("Economy")
	if economy != null:
		economy.set("ticking", false)
	for i in 8:
		await process_frame

func attach_assembly_to_real_main() -> void:
	assembly = main.get_node_or_null("World/SeaStructures/water_building_002") as Node3D
	check(assembly != null, "002 is serialized in production main, not injected by test")
	for i in 4:
		await process_frame

func check_assembly() -> void:
	check(assembly != null, "real main scene has water building assembly")
	if assembly == null:
		return
	check(assembly.get_meta("asset_id", "") == "SEA-SCENE-WATER-BUILDING-002", "assembly asset id")
	check(assembly.get_meta("source_version", "") == "v003", "assembly source version")
	check(assembly.get_meta("building_class", "") == "above_water", "assembly building class")
	check(assembly.get_meta("water_layer", "") == "surface", "assembly water layer")
	check(assembly.get_meta("water_layer_role", "") == "entity", "assembly entity role")
	check(assembly.get_meta("activity_role", "") == "navigation_only", "assembly navigation-only role")
	check(assembly.get_node_or_null("WalkArea") == null and assembly.get_node_or_null("Landing") == null and assembly.get_node_or_null("Zone") == null, "no interaction ownership nodes")
	var runtime := JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_DATA)) as Dictionary
	check(runtime.get("production_auto_rehydrate", true) == false, "runtime JSON is not production auto-rehydration")
	var expected: Dictionary = runtime.get("expected", {})
	check(int(expected.get("instances", -1)) == 167, "runtime expected instance count")
	check(int(expected.get("triangles", -1)) == 10342 and int(expected.get("polygons", -1)) == 6293, "runtime source geometry budget")
	var rows: Array = runtime.get("instances", [])
	check(rows.size() == 167, "runtime has 167 transform records")
	var actual_count := 0
	for group_name in ["Structure", "Furnishings", "Plants"]:
		var group := assembly.get_node("Visual/" + group_name)
		actual_count += group.get_child_count()
	check(actual_count == 167, "assembly has 167 grouped instances")
	var seen := 0
	for row in rows:
		var group_name := str(row.get("group", ""))
		var node := assembly.get_node_or_null("Visual/" + group_name + "/" + str(row.get("name", ""))) as Node3D
		check(node != null, "instance exists " + str(row.get("name", "")))
		if node == null:
			continue
		seen += 1
		check(node.get_meta("component_key", "") == row.get("key", ""), "instance key " + str(row.get("name", "")))
		var expected_xf := expected_transform(row.get("godot_transform", []))
		check(node.transform.is_equal_approx(expected_xf), "C*M*C^-1 transform " + str(row.get("name", "")))
	check(seen == 167, "all runtime transforms resolve")
	var crowns := 0
	var non_uniform_crowns := 0
	for row in rows:
		if str(row.get("key", "")) != "crown_a" and str(row.get("key", "")) != "crown_b":
			continue
		crowns += 1
		var scale: Array = row.get("scale", [])
		if scale.size() == 3 and (not is_equal_approx(float(scale[0]), float(scale[1])) or not is_equal_approx(float(scale[1]), float(scale[2]))):
			non_uniform_crowns += 1
	check(crowns == 18 and non_uniform_crowns >= 17, "18 crown scales retain source non-uniform volume revision")
	check(triangle_count(assembly) == 10342, "actual imported full-scene triangles")
	var role_paths := {}
	var texture_paths := {}
	for mesh_node in assembly.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "all assembly meshes cast shadows")
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			check(material != null, "all surfaces have a serialized shader material")
			if material == null:
				continue
			role_paths[material.resource_path] = true
			var palette := material.get_shader_parameter("palette") as Texture2D
			if palette != null:
				texture_paths[palette.resource_path] = true
	check(role_paths.size() == 3 and role_paths.has("res://assets/materials/solar_cabin/sunny_matte.tres") and role_paths.has("res://assets/materials/solar_cabin/sunny_metal.tres") and role_paths.has("res://assets/materials/solar_cabin/sunny_gloss.tres"), "three unique role materials")
	check(texture_paths.size() == 1 and texture_paths.has(PALETTE), "unique timber palette texture")
	var plants := assembly.get_node("Visual/Plants")
	check(plants.get_meta("visual_only", false), "Plants group visual_only")
	for child in plants.get_children():
		check(child.get_meta("visual_only", false), "plant instance visual_only " + str(child.name))
	check(assembly.find_children("*", "CollisionObject3D", true, false).is_empty(), "navigation-only assembly has no actor collision")

func check_blockers_follow_geometry() -> void:
	var blockers := assembly.get_node("Blockers")
	check(blockers.mode == "auto" and blockers.blocks_water, "Blockers auto water mode")
	check(str(blockers.target_path) == "../Visual/Structure", "Blockers target actual Structure meshes")
	var water_y: float = main.water_node.global_position.y
	assembly.rebuild_blockers(water_y, 1.6)
	check(assembly.water_block_rects.size() > 0, "Blockers rebuild finds actual waterline geometry")
	var shapes: Array = main._water_shapes()
	for rect: Rect2 in assembly.water_block_rects:
		var represented := false
		for shape: Dictionary in shapes:
			if Vector2(float(shape.get("x", INF)), float(shape.get("z", INF))).distance_to(rect.get_center()) < 0.001 and absf(float(shape.get("hx", -1.0)) * 2.0 - rect.size.x) < 0.001 and absf(float(shape.get("hz", -1.0)) * 2.0 - rect.size.y) < 0.001:
				represented = true
				break
		check(represented, "002 footprint collected by actual main water navigation")
	var before := min_rect_position(assembly.water_block_rects)
	assembly.position += Vector3(12.0, 0.0, 16.0)
	assembly.rebuild_blockers(water_y, 1.6)
	var after := min_rect_position(assembly.water_block_rects)
	check((after - before - Vector2(12.0, 16.0)).length() < 0.05, "blockers follow assembly transform, not pinned world coordinates")
	assembly.position -= Vector3(12.0, 0.0, 16.0)
	assembly.rebuild_blockers(water_y, 1.6)

func run() -> void:
	check_components()
	await configure_real_main()
	await attach_assembly_to_real_main()
	check_assembly()
	check_blockers_follow_geometry()
	print("[water-building-002] ", checks, " checks, ", failures, " failures")
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
