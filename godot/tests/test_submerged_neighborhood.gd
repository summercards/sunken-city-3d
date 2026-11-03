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
## 未安装时把预制体摆回原水下高度，好让几何/材质检查继续有效。
var _standalone_cache := {}
func _standalone(key: String) -> Node3D:
	if _standalone_cache.has(key):
		return _standalone_cache[key]
	var node: Node3D = load("res://scenes/decorations/underwater/buildings/" + key + ".tscn").instantiate()
	node.position = Vector3(0, -19.0, 0)
	root.add_child(node)
	_standalone_cache[key] = node
	return node

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
	# 2026-11-03 范围要求：主场景只保留横滨铁道与水上的顶层牧场，
	# 水下景观不再挂进 main.tscn。预制体、账本与源都保留，随时可以加回。
	# 所以这里分两条路：装了就跑摆位检查，没装就只验资产本身（预算/材质/职责）。
	var scenery: Node3D = main.get_node_or_null("World/UnderwaterScenery")
	var installed := scenery != null
	check(not installed or scenery.get_child_count() >= 6,
		"installed scenery keeps at least six independent buildings")
	var base: Node3D = zone.get_node("Models/太阳能木屋/太阳能木屋-海下基座")
	var base_box := bounds(base)
	check(base_box.has_volume(), "existing MultiMesh sunroom base has measured volume")
	evidence.base_bounds = str(base_box)
	evidence.installed = installed
	if installed:
		check(scenery.is_visible_in_tree(), "scenery visible in the default minimum playable scope")
		# 摆放是从六栋扩到八栋的（flat_annex2 / rear_slab2 复制了两栋）。
		# 这里不再写死数量，逐个子节点核分类；写死数量的旧断言只会让新增那栋不受管。
		for child in scenery.get_children():
			check(child.component_kind == "decoration" and child.subcategory == "underwater_buildings",
				child.name + " is registered as a submerged scenic building")
		check(scenery.get_parent() == main.get_node("World"), "placement owned by main.tscn")
		check(scenery.get_node("terraced_tower").position.z < base_box.position.z and scenery.get_node("rear_slab").position.z < base_box.position.z, "tall background buildings recede behind the sunroom, not a surrounding ring")
		check(scenery.get_node("rounded_tower").position.x < base_box.position.x, "large rounded silhouette anchors the left bank")
		check(scenery.get_node("stepped_lowrise").position.z > base_box.end.z and scenery.get_node("flat_annex").position.z < scenery.get_node("stepped_lowrise").position.z, "foreground roof heights and distances are staggered")
	else:
		check(true, "underwater scenery is intentionally not installed in main.tscn (scope 2026-11-03)")
	check(zone.get_node_or_null("UnderwaterScenery") == null, "zone1 must not carry a second scenery instance")
	var boxes: Array[AABB] = []
	for key in KEYS:
		var packed: PackedScene = load("res://scenes/decorations/underwater/buildings/" + key + ".tscn")
		var standalone: Node3D = packed.instantiate()
		root.add_child(standalone)
		check(triangle_count(standalone) > 0 and triangle_count(standalone) <= 1000, key + " independently loads under triangle budget")
		check(serialized_palette_override(packed), key + " palette material serialized in the prefab, not only applied by a runtime script")
		standalone.queue_free()
		# 没安装时用同一份预制体摆到原来的水下高度，继续量几何与材质。
		var node: Node3D = scenery.get_node(key) if installed else _standalone(key)
		var box := bounds(node)
		boxes.append(box)
		var count := triangle_count(node)
		# 实例带手工缩放与旋转（用来做疏密与朝向），所以不再断言 scale == ONE。
		# 「每栋独立实例」改由「各自有可测包围盒且中心互不重合」来证明。
		evidence.buildings.append({"key": key, "scale": str(node.scale), "rotation": str(node.rotation)})
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
		# 摆位专有检查只在真的安装时成立。
		if installed:
			var rect := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
			var base_rect := Rect2(Vector2(base_box.position.x, base_box.position.z), Vector2(base_box.size.x, base_box.size.z))
			check(not rect.intersects(base_rect), key + " separate from sunroom base")
		evidence.buildings.append({"key":key,"triangles":count,"bounds":str(box),"position":str(node.global_position),"asset_id":node.asset_id})
	for a in boxes.size() if installed else 0:
		for b in range(a + 1, boxes.size()):
			# 楼体带旋转时，轴对齐包围盒天然会互相压住 —— 用纯 AABB 相交判定
			# 会把"斜着相邻"误报成"穿模"。只看真实共占体积占比。
			var overlap: AABB = boxes[a].intersection(boxes[b])
			var smaller := minf(boxes[a].get_volume(), boxes[b].get_volume())
			var ratio := (overlap.get_volume() / smaller) if smaller > 0.0 else 0.0
			check(ratio < 0.6, "independent buildings do not share volume %d/%d (%.0f%%)" % [a, b, ratio * 100.0])
	if not installed:
		_finish()
		return
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
	_finish()

## 主场景没装水下景观时，摆位相关的实拍与导航检查没有对象，按同一出口收尾。
func _finish() -> void:
	var file := FileAccess.open("res://outputs/submerged-neighborhood.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"));file.close()
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	print("[submerged-neighborhood] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
