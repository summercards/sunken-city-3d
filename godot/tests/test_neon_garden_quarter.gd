extends SceneTree

const COMPONENTS := "res://scenes/components/facilities/neon_garden_quarter/"
const MODULES := {
	"left_building": ["LeftBuilding", 198],
	"rear_building": ["RearBuilding", 92],
	"right_building": ["RightBuilding", 59],
	"garden_bridge": ["GardenBridge", 118],
	"street_ground": ["Foundation", 39],
}
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const POSTER := "res://assets/textures/facilities/neon_garden_quarter/poster_atlas.png"
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var to_local_space := node.global_transform.affine_inverse()
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		if child is MeshInstance3D and child.mesh != null:
			var part: AABB = to_local_space * child.global_transform * child.mesh.get_aabb()
			result = part if first else result.merge(part)
			first = false
		elif child is MultiMeshInstance3D and child.multimesh != null and child.multimesh.mesh != null:
			for i in child.multimesh.instance_count:
				var transform: Transform3D = to_local_space * child.global_transform * child.multimesh.get_instance_transform(i)
				var part: AABB = transform * child.multimesh.mesh.get_aabb()
				result = part if first else result.merge(part)
				first = false
	return result

func check_components() -> void:
	var count := 0
	var print_surfaces := 0
	for file in DirAccess.get_files_at(COMPONENTS):
		if not file.ends_with(".tscn"): continue
		# The inspection float is a native scene with its own materials.
		if file == "stair_foot.tscn": continue
		var component := (load(COMPONENTS + file) as PackedScene).instantiate()
		count += 1
		check(component.get_meta("asset_version") == "v003", file + " stable wrapper version")
		var meshes := component.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), file + " independent geometry")
		for child in meshes:
			var mesh := child as MeshInstance3D
			for i in mesh.mesh.get_surface_count():
				var material := mesh.get_surface_override_material(i) as StandardMaterial3D
				check(material != null and material.albedo_texture != null, file + " role has texture")
				if material == null or material.albedo_texture == null: continue
				var is_poster := material.resource_name == "SEA_Poster"
				print_surfaces += int(is_poster)
				check(material.albedo_texture.resource_path == (POSTER if is_poster else PALETTE), file + " canonical texture")
				check(is_poster or material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, file + " palette nearest")
		component.free()
	check(count == 50, "50 stable independent components")
	check(print_surfaces == 8, "eight original poster panels retain atlas")
	for key in MODULES:
		var packed := load(COMPONENTS + "modules/" + key + ".tscn") as PackedScene
		check(packed != null, key + " module loads independently")
		if packed == null: continue
		var component := packed.instantiate() as Node3D
		check(component.transform == Transform3D.IDENTITY, key + " independent module origin")
		check(component.get_meta("asset_version") == "v004", key + " independent module version")
		check(component.get_child_count() == MODULES[key][1], key + " expected placement count")
		component.free()

func capture(camera: Camera3D, target: Vector3, offset: Vector3, name: String) -> void:
	camera.position = target + offset
	camera.look_at(target)
	for i in 6: await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	check(image != null and image.get_width() >= 800, "real frame " + name)
	if image != null:
		check(image.save_png("res://outputs/neon_garden_" + name + ".png") == OK, "saved frame " + name)

func run() -> void:
	check_components()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 8: await process_frame
	var quarter := main.get_node("World/SeaStructures/neon_garden_quarter") as Node3D
	var p := quarter.global_position
	check(quarter.is_visible_in_tree(), "quarter is visible at its authored placement")
	var visual := quarter.get_node("Visual")
	check(visual.has_node("StairFoot"), "the inspection float is assembled alongside the original modules")
	var placements := 0
	for key in MODULES:
		var module := visual.get_node_or_null(MODULES[key][0])
		check(module != null and module.scene_file_path == COMPONENTS + "modules/" + key + ".tscn", key + " stable module in production layout")
		if module == null: continue
		for child in module.get_children():
			if not child.scene_file_path.is_empty() and child.scene_file_path.begins_with(COMPONENTS):
				placements += 1
	check(placements == 506, "all Blender placements instantiated once")
	var blockers := quarter.get_node("Blockers")
	check(blockers.get_node_or_null(blockers.target_path) == visual, "water occupancy reads the authored visible assembly")
	var roof: Node3D
	for child in visual.get_node("GardenBridge").get_children():
		if str(child.name).begins_with("roof_soil_"):roof = child
		if str(child.name).begins_with("crop_bed_"):
			check(child.basis.z.y < -0.37 and child.basis.z.y > -0.40, "crop bed tilt follows front roof plane " + str(child.basis))
	check(roof != null, "gable roof instance exists")
	if roof != null:
		var roof_bounds := bounds(roof)
		check(roof_bounds.size.x > 21 and roof_bounds.size.y > 2.65, "gable mesh spans the alley and rises above its eaves")
	var full_bounds := bounds(quarter)
	check(full_bounds.size.x > 41 and full_bounds.size.y > 39, "widened assembly dimensions")
	check(not main.cam.pan_bounds.has_area() or main.cam.pan_bounds.has_point(Vector2(p.x, p.z)), "camera can pan to the quarter")
	check(main._zone_nodes.get("neon_garden_quarter") == quarter, "registered for landing in default scope")
	if DisplayServer.get_name() != "headless":
		main.set_process(false)
		var camera := Camera3D.new()
		camera.fov = 41.0
		main.add_child(camera)
		camera.make_current()
		await capture(camera, p + Vector3(-1, 23, -2), Vector3(-48, 34, 62), "overview")
		await capture(camera, p + Vector3(0, 25.8, 1), Vector3(-3, 12, 38), "roof")
		await capture(camera, p + Vector3(0, 23, -1), Vector3(41, 9, -54), "rear")
	var landing: Node3D = quarter.landing_point("main")
	check(landing != null and visual.get_node("StairFoot").is_ancestor_of(landing),
		"the inspection float owns the current berth")
	if landing != null:
		var park := landing.get_node("BoatPark") as Marker3D
		main.boat.place_at(park.global_position, park.global_rotation.y)
		for frame in 3: await physics_frame
		var transfer := preload("res://src/navigation/berth_transfer.gd").new()
		check(transfer.inspect(main.boat, main.player, landing, true, false).has("point"),
			"the handoff accepts the boat at the authored float")
	print("[neon-garden-quarter] ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
