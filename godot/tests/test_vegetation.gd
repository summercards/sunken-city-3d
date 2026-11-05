extends SceneTree
const Library = preload("res://src/ambient/vegetation/library.gd")
const Patch = preload("res://src/ambient/vegetation/patch.gd")
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL vegetation: ", label)
func valid_root_weights(vertices: PackedVector3Array, colors: PackedColorArray) -> bool:
	if colors.size() != vertices.size(): return false
	for i in vertices.size():
		if vertices[i].y < 0.0001 and colors[i].r > 0.001: return false
	return true
func run() -> void:
	for key in Library.catalog():
		var mesh := Library.mesh(key)
		check(mesh == Library.mesh(key), key + " shared mesh")
		check(mesh.get_surface_count() == 1, key + " one surface")
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		check(valid_root_weights(vertices, colors), key + " actual imported roots fixed")
		check(mesh.get_aabb().position.y > -0.001, key + " bottom pivot")
		check((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == vertices.size(), key + " UV0 preserved")
		var broken := colors.duplicate()
		for i in vertices.size():
			if vertices[i].y < 0.0001: broken[i] = Color(1, 0, 0, 1)
		check(not valid_root_weights(vertices, broken), key + " bad weight sample rejected")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main); main._autosave_on = false; main.set_process(false)
	for i in 12: await process_frame
	var owners := get_nodes_in_group("vegetation_wind_owner")
	check(owners.size() == 1, "one wind owner")
	var wind = owners[0]
	wind.frozen = true; wind.sample_at(17.0)
	for i in 3: await process_frame
	check(is_equal_approx(wind.elapsed, 17.0), "frozen clock")
	wind.frozen = false; paused = true
	for i in 3: await process_frame
	check(is_equal_approx(wind.elapsed, 17.0), "tree pause holds clock")
	paused = false; wind.get_parent().hide()
	for i in 3: await process_frame
	check(is_equal_approx(wind.elapsed, 17.0), "hidden World holds clock")
	wind.get_parent().show()
	for i in 3: await process_frame
	check(wind.elapsed > 17.0, "resume continues phase")
	var patches: Array = []
	for n in main.find_children("VegetationTurf", "Node3D", true, false): patches.append(n)
	check(patches.size() == 2, "solar turf plus the requested rooftop")
	var report := []
	for patch in patches:
		check(patch.find_children("*", "CollisionObject3D", true, false).is_empty(), "pure visual turf")
		var count: int = patch.placement_count
		var batches: int = patch.batches.size()
		var is_roof: bool = patch.layout_path.ends_with("rooftop_ranch.json")
		check(count >= (5000 if is_roof else 350) and batches < (100 if is_roof else 30), "broad cards and bounded batches")
		if batches == 0: continue
		var first: Transform3D = patch.batches[0].get_meta("authored_transforms")[0]
		patch.rebuild()
		check(patch.placement_count == count and patch.batches.size() == batches, "rebuild does not duplicate")
		check(first.is_equal_approx(patch.batches[0].get_meta("authored_transforms")[0]), "stable baked placements")
		for batch in patch.batches:
			var mm: MultiMesh = batch.multimesh
			check(mm.use_custom_data and not mm.use_colors, "weights not multiplied by instance color")
			check(mm.custom_aabb.size.x < 12 and mm.custom_aabb.size.z < 12, "spatial chunks rather than world AABB")
			for i in mm.instance_count:
				var a: AABB = batch.get_meta("authored_transforms")[i] * mm.mesh.get_aabb()
				check(mm.custom_aabb.encloses(a.grow(0.5)), "wind displacement culling margin")
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(patch.layout_path))
		if is_roof:
			var mounds := 0
			for row in layout.instances:
				if row.asset != "mound_soft": continue
				mounds += 1
				check(absf(row.position[1]-60.05)<0.001, "mounds grounded on the real rooftop")
			check(mounds == 14, "fourteen authored rooftop mound islands")
		patch.quality = 1
		var camera: Camera3D = main.cam
		var previous: Vector3 = camera.position
		camera.position = Vector3(200,200,200)
		patch.update_quality(camera, true)
		for batch in patch.batches:
			if batch.get_meta("asset_key") == "grass_soft":
				check(batch.multimesh.visible_instance_count > 0, "far grass silhouette retained")
		camera.position = previous
		for region in layout.regions:
			for row in layout.instances:
				if not String(row.id).contains(region.id + "/grass"): continue
				var p: Array = row.position
				for cut in region.exclusions:
					var r: Array = cut.rect
					check(not (p[0]>=r[0] and p[0]<=r[2] and p[2]>=r[1] and p[2]<=r[3]), "road/future footprint exclusion")
		report.append({"layout":patch.layout_path,"instances":count,"batches":batches})
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/solar_cabin/instances.json"))
	var attachments := 0
	var components: Array = main.find_children("*", "Node3D", true, false)
	for i in original.instances.size():
		var row: Dictionary = original.instances[i]
		if row.category != "flora": continue
		var identity: String = row.get("instance_id", "solar_cabin/%03d" % i)
		var found: Node3D = null
		for node in components:
			if node.get_script() != null and node.get_script().resource_path == "res://src/ambient/scene_component.gd" and node.instance_id == identity:
				found = node; break
		check(found != null, "original plant retained " + identity)
		if found == null: continue
		attachments += 1
		check(found.asset_id == row.asset_id, "original plant asset retained")
		var a: Array = row.transform
		check(found.position.is_equal_approx(Vector3(a[0][3], a[1][3], a[2][3])), "original root position retained")
	check(attachments == 56, "56 original plants untouched")
	FileAccess.open("res://outputs/vegetation_contract.json", FileAccess.WRITE).store_string(JSON.stringify({"consumers":report,"solar_attachments":attachments,"checks":checks,"failures":failures},"  "))
	print("[vegetation] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
