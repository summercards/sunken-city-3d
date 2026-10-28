extends SceneTree
## Source budgets are rechecked on actual imported meshes and formal scene placement.
var checks := 0
var failures := 0
var main
var evidence := {"buildings": [], "frames": [], "pure_scenery": true}
const KEYS := ["terraced_tower", "rounded_tower", "slender_tower", "stepped_lowrise", "flat_annex", "rear_slab"]
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "VisualInstance3D", true, false):
		if not (mesh is MeshInstance3D or mesh is MultiMeshInstance3D): continue
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		result = part if first else result.merge(part)
		first = false
	return result
func triangle_count(node: Node) -> int:
	var result := 0
	for visual in node.find_children("*", "MeshInstance3D", true, false):
		for surface in visual.mesh.get_surface_count():
			var arrays: Array = visual.mesh.surface_get_arrays(surface)
			result += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() > 0 else arrays[Mesh.ARRAY_VERTEX].size() / 3
	return result
## 贴图来自 .tscn 里序列化的 surface_material_override，而不是只靠 @tool 脚本运行时补。
## 一旦有人把它改成「脚本上色」，编辑器里重新实例化就会变回 GLB 的灰白底材。
func serialized_palette_override(packed: PackedScene) -> bool:
	var state := packed.get_state()
	for node_index in state.get_node_count():
		if state.get_node_name(node_index) != "Visual": continue
		for p in state.get_node_property_count(node_index):
			if not str(state.get_node_property_name(node_index, p)).begins_with("surface_material_override"): continue
			var material = state.get_node_property_value(node_index, p)
			if material is StandardMaterial3D and material.albedo_texture != null \
				and material.albedo_texture.resource_path == "res://assets/textures/shared/sea_cozy_8x8_512.png":
				return true
	return false
func snapshot(tag: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/submerged-" + tag + ".png")
	evidence.frames.append(tag)
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.boat.set_process(false)
	for i in 8: await process_frame
	var zone: Node3D = main.get_node("World/Zones/Zone1HomeHarbor")
	# 摆放由 main.tscn 拥有：六栋是 World 下的独立实例，便于在完整场景里逐个对照调整。
	var scenery: Node3D = main.get_node("World/UnderwaterScenery")
	var base: Node3D = zone.get_node("Models/太阳能木屋/太阳能木屋-海下基座")
	var base_box := bounds(base)
	check(base_box.has_volume(), "existing MultiMesh sunroom base has measured volume")
	evidence.base_bounds = str(base_box)
	check(scenery.is_visible_in_tree(), "scenery visible in the default minimum playable scope")
	check(scenery.get_child_count() == 6, "exactly six independent buildings")
	check(scenery.get_parent() == main.get_node("World"), "placement owned by main.tscn")
	check(zone.get_node_or_null("UnderwaterScenery") == null, "zone1 must not carry a second scenery instance")
	check(scenery.get_node("terraced_tower").position.z < base_box.position.z and scenery.get_node("rear_slab").position.z < base_box.position.z, "tall background buildings recede behind the sunroom, not a surrounding ring")
	check(scenery.get_node("rounded_tower").position.x < base_box.position.x, "large rounded silhouette anchors the left bank")
	check(scenery.get_node("stepped_lowrise").position.z > base_box.end.z and scenery.get_node("flat_annex").position.z < scenery.get_node("stepped_lowrise").position.z, "foreground roof heights and distances are staggered")
	var boxes: Array[AABB] = []
	for key in KEYS:
		var packed: PackedScene = load("res://scenes/decorations/underwater/buildings/" + key + ".tscn")
		var standalone: Node3D = packed.instantiate()
		root.add_child(standalone)
		check(triangle_count(standalone) > 0 and triangle_count(standalone) <= 1000, key + " independently loads under triangle budget")
		check(serialized_palette_override(packed), key + " palette material serialized in the prefab, not only applied by a runtime script")
		standalone.queue_free()
		var node: Node3D = scenery.get_node(key)
		var box := bounds(node)
		boxes.append(box)
		var count := triangle_count(node)
		check(node.scale.is_equal_approx(Vector3.ONE), key + " authored scale and independent instance")
		check(count > 0 and count <= 1000, key + " actual imported triangles <=1000")
		check(box.end.y < main.water_node.global_position.y - .25, key + " entirely underwater including roof attachments")
		check(node.component_kind == "decoration" and node.subcategory == "underwater_buildings" and not node.movable, key + " classification")
		check(not node.is_in_group("interactable"), key + " no gameplay input")
		check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), key + " no physics")
		check(node.get_node("Blockers").mode == "none" and not node.get_node("Blockers").blocks_water, key + " no navigation blocker")
		for visual in node.find_children("*", "MeshInstance3D", true, false):
			for surface in visual.mesh.get_surface_count():
				var mat: StandardMaterial3D = visual.get_surface_override_material(surface)
				check(mat != null and mat.albedo_texture.resource_path == "res://assets/textures/shared/sea_cozy_8x8_512.png" and not mat.emission_enabled, key + " shared lit palette, no emission")
			check(visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, key + " true shadows")
		# Preserve a real channel around the old base instead of fusing buildings.
		var rect := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		var base_rect := Rect2(Vector2(base_box.position.x, base_box.position.z), Vector2(base_box.size.x, base_box.size.z))
		check(not rect.intersects(base_rect), key + " separate from sunroom base")
		evidence.buildings.append({"key":key,"triangles":count,"bounds":str(box),"position":str(node.global_position),"asset_id":node.asset_id})
	for a in boxes.size():
		for b in range(a + 1, boxes.size()): check(not boxes[a].intersects(boxes[b]), "independent buildings do not intersect %d/%d" % [a,b])
	var shapes_before: Array = main.navigation._water_shapes().duplicate(true)
	scenery.hide()
	zone.rebuild_blockers(main.water_node.global_position.y)
	check(shapes_before == main.navigation._water_shapes(), "scenery visibility leaves navigation unchanged")
	scenery.show()
	zone.rebuild_blockers(main.water_node.global_position.y)
	var shore = preload("res://src/rendering/shore_distance.gd").new()
	shore.rebuild([scenery], main.water_node.global_position.y, 64)
	check(shore.segments.is_empty(), "fully submerged scenery produces no shoreline foam")
	main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide()
	main.daylight_rig.apply(9.0)
	main.cam.target = Vector3(3, 1, 8)
	main.cam.distance = 70
	main.cam.orbit_dir = Vector3(-.6, .85, .8)
	main.cam.refresh()
	await snapshot("surface-reference")
	scenery.hide()
	await snapshot("surface-before")
	scenery.show()
	main.cam.target = Vector3(3, -2, 8)
	main.cam.distance = 54
	main.cam.orbit_dir = Vector3(-.2, 1.5, 1.0)
	main.cam.refresh()
	await snapshot("surface-top")
	# Inspection only: expose true model geometry while retaining the same scene.
	main.water_node.hide()
	main.cam.target = Vector3(3, -8, 8)
	main.cam.distance = 63
	main.cam.orbit_dir = Vector3(-.6, .55, .8)
	main.cam.refresh()
	await snapshot("geometry-review")
	main.water_node.show()
	main.daylight_rig.apply(19.0)
	main.cam.target = Vector3(3, -2, 8)
	main.cam.orbit_dir = Vector3(-.6, .85, .8)
	main.cam.refresh()
	await snapshot("night")
	var file := FileAccess.open("res://outputs/submerged-neighborhood.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"));file.close()
	main.queue_free()
	await process_frame
	print("[submerged-neighborhood] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
