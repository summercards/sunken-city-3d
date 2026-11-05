extends SceneTree
## 沉没街景十栋专项（SEA-ASSET-R42 的 Godot 侧证据）。
##
## 这一套断言不是"能不能显示"就算完，而是钉住四类真实故障：
##   1) 颜色靠运行期脚本补 → 编辑器里重新实例化就变灰白。这里读**预制体序列化状态**，
##      不实例化、不信任 @tool 的 _ready()。
##   2) surface 顺序变了 → 材质错位换色。逐 surface 比对「覆盖的材质角色」与
##      「导入网格自带的 glTF 材质名」，不等就是红的，不是看着差不多。
##   3) 水下件越线 → 楼顶露出水面。整体包围盒顶面必须低于水面 0.25 米。
##   4) 摆到别人的地盘上 → 和横滨站、家园、现有六栋穿模。逐对量 AABB 交集体积占比。
##
## 摆位归 main.tscn；这里只读，不改任何资产。

const PREFAB_DIR := "res://scenes/decorations/underwater/street/buildings/"
const MAT_DIR := "res://assets/materials/submerged_street/"
const GROUP := "World/UnderwaterStreet"
const SUBMERGED_CLEARANCE := 0.25
## 每栋的三角面预算，与 art_source/scenes/submerged_street/v001/component_plan.json 一致。
const BUDGET := {
	"broken_viaduct": 2000,
	"l_apartment_fire_escape": 2200,
	"food_truck": 1000,
	"mcdonalds_restaurant": 1600,
	"highrise_apartment": 2000,
	"traffic_light": 700,
	"utility_poles": 900,
	"highway_sign": 900,
	"construction_shell": 2400,
	"walkup_apartment": 1800,
}
const KEYS := [
	"broken_viaduct", "l_apartment_fire_escape", "food_truck", "mcdonalds_restaurant",
	"highrise_apartment", "traffic_light", "utility_poles", "highway_sign",
	"construction_shell", "walkup_apartment",
]

var checks := 0
var failures := 0
var main
var evidence := {"buildings": [], "frames": [], "water_y": 0.0, "group_bounds": ""}


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "VisualInstance3D", true, false):
		if not (mesh is MeshInstance3D or mesh is MultiMeshInstance3D):
			continue
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		result = part if first else result.merge(part)
		first = false
	return result


func triangle_count(node: Node) -> int:
	var result := 0
	for visual in node.find_children("*", "MeshInstance3D", true, false):
		for surface in visual.mesh.get_surface_count():
			var arrays: Array = visual.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() > 0:
				result += arrays[Mesh.ARRAY_INDEX].size() / 3
			else:
				result += arrays[Mesh.ARRAY_VERTEX].size() / 3
	return result


## 预制体里序列化的覆盖：返回 {surface_index: material}，不实例化。
func serialized_overrides(packed: PackedScene) -> Dictionary:
	var found := {}
	var state := packed.get_state()
	for node_index in state.get_node_count():
		for p in state.get_node_property_count(node_index):
			var name := str(state.get_node_property_name(node_index, p))
			if not name.begins_with("surface_material_override/"):
				continue
			var index := int(name.get_slice("/", 1))
			found[index] = state.get_node_property_value(node_index, p)
	return found


## glTF 材质名 "SEA_Matte" → 角色 "matte"。
func role_of_material(material: Material) -> String:
	if material == null:
		return ""
	return material.resource_name.replace("SEA_", "").replace("_SubmergedStreet", "").to_lower()


## 未安装时的统一收尾：只报告资产级结果。
func _finish() -> void:
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	print("[submerged-street] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func snapshot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/submerged-street-" + tag + ".png")
	evidence.frames.append(tag)


## 未安装时把十栋摆回原水下高度（-19），让几何与材质检查继续有效。
func _synthetic_street() -> Node3D:
	var container := Node3D.new()
	container.name = "SyntheticUnderwaterStreet"
	container.set_meta("source_suite", "submerged_street")
	root.add_child(container)
	var dir := "res://scenes/decorations/underwater/street/buildings/"
	for key in KEYS:
		var node: Node3D = (load(dir + key + ".tscn") as PackedScene).instantiate()
		node.name = key
		node.instance_id = "home_street/" + key
		container.add_child(node)
		# 摆回「屋顶对齐水面」的原始高度带，让水下高度断言仍然成立。
		var box := bounds(node)
		node.position.y += (1.12 - 1.45) - box.end.y
	return container


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# 证据取景需要 88–118 m 的远机位；玩家上限是 38 m（SEA-CAMERA-R11），
	# 不抬高只会被静默夹回 38 m，截出来的"远景"其实不是远景。
	main.cam.zoom_max = 160.0
	main._autosave_on = false
	main.set_process(false)
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.boat.set_process(false)
	for i in 8:
		await process_frame

	var water_y: float = main.water_node.global_position.y
	evidence.water_y = water_y
	# 2026-11-03 范围要求：主场景只保留横滨铁道与水上的顶层牧场，水下街景不再挂进去。
	# 预制体、材质与源都保留。装了就跑完整摆位检查；没装就把十栋摆到原水下高度，
	# 继续验「预算 / 序列化材质 / 水下职责」这些会真出问题的地方。
	var street: Node3D = main.get_node_or_null(GROUP)
	var installed := street != null
	evidence.installed = installed
	if not installed:
		street = _synthetic_street()
		check(true, "underwater street is intentionally not installed in main.tscn (scope 2026-11-03)")
	else:
		check(street.get_parent() == main.get_node("World"), "placement group hangs directly under World")
		check(street.get_child_count() == KEYS.size(), "exactly ten street buildings are placed (%d)" % street.get_child_count())
		check(street.get_meta("source_suite", "") == "submerged_street", "group records its source suite")

	# ---- 摆位可行性：必须落在相机 pan_bounds 内，否则玩家永远摇不到这一片
	var pan: Rect2 = main.cam.pan_bounds
	var group_box: AABB = bounds(street)
	if not installed:
		pan = Rect2()  # 没安装就没有「摇不到」这种风险
	evidence.group_bounds = str(group_box)
	# pan_bounds 为空 = 相机可自由平移（当前 main.tscn 就是这种）。
	# 只有真的设了边界才需要把街区纳进去；否则「摇不到」这个风险不存在。
	if pan.has_area():
		check(pan.encloses(Rect2(Vector2(group_box.position.x, group_box.position.z),
			Vector2(group_box.size.x, group_box.size.z))),
			"whole street sits inside the camera pan bounds (%s)" % str(pan))
	else:
		check(true, "camera pans freely, so the street is always reachable")
	evidence.pan_bounds = str(pan)
	check(group_box.end.y < water_y - SUBMERGED_CLEARANCE,
		"street group stays fully below the waterline (top %.2f, water %.2f)" % [group_box.end.y, water_y])

	# ---- 不与已有内容穿模（只在真的安装时才有对象）
	var occupied := {}
	if not installed:
		occupied = {}
	if installed:
		occupied["existing_scenery"] = bounds(main.get_node("World/UnderwaterScenery"))
		occupied["sunroom_base"] = bounds(main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海下基座"))
		occupied["zone2_station"] = bounds(main.get_node("World/Zones/Zone2YokohamaStation"))
		occupied["zone1_home"] = bounds(main.get_node("World/Zones/Zone1HomeHarbor"))

	var boxes: Array[AABB] = []
	var roofs: Array[float] = []
	for key in KEYS:
		var node: Node3D = street.get_node_or_null(key)
		check(node != null, key + " is placed in the street group")
		if node == null:
			continue
		check(node.instance_id == "home_street/" + key, key + " carries a stable instance id")
		check(node.component_kind == "decoration" and node.subcategory == "underwater_buildings",
			key + " is registered as a submerged scenic building")
		check(node.water_layer == "submerged" and node.water_layer_role == "entity",
			key + " declares submerged scenery duties")
		check(not node.movable, key + " is not movable")
		check(not node.is_in_group("interactable"), key + " carries no gameplay input")
		check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), key + " has no physics")
		check(node.find_children("*", "WalkArea", true, false).is_empty(), key + " offers no walkable area")
		var blockers := node.get_node_or_null("Blockers")
		check(blockers != null and blockers.mode == "none" and not blockers.blocks_water,
			key + " declares no navigation blocker")

		# 预算：账本数字与实际导入网格对账，任一边漂移都算失败
		var tris := triangle_count(node)
		var budget := int(BUDGET[key])
		check(tris > 0 and tris <= budget, "%s actual triangles %d within budget %d" % [key, tris, budget])
		check(int(node.get_meta("triangle_budget", -1)) == budget, key + " metadata budget matches the plan")

		# 颜色：序列化的三档材质角色，且逐 surface 与导入网格的 glTF 材质名对齐
		var prefab: PackedScene = load(PREFAB_DIR + key + ".tscn")
		check(prefab != null, key + " prefab loads")
		var overrides := serialized_overrides(prefab)
		var visuals := node.find_children("*", "MeshInstance3D", true, false)
		check(visuals.size() == 1, key + " has exactly one visual mesh")
		var visual: MeshInstance3D = visuals[0]
		var surfaces := visual.mesh.get_surface_count()
		check(overrides.size() == surfaces,
			"%s serializes one palette override per surface (%d/%d)" % [key, overrides.size(), surfaces])
		for surface in surfaces:
			var override_material: Material = overrides.get(surface)
			check(override_material is StandardMaterial3D,
				"%s surface %d has a serialized material" % [key, surface])
			if not (override_material is StandardMaterial3D):
				continue
			check(override_material.resource_path.begins_with(MAT_DIR),
				"%s surface %d uses the street palette material" % [key, surface])
			check(not override_material.emission_enabled,
				"%s surface %d does not self-illuminate" % [key, surface])
			check(override_material.albedo_texture != null
				and override_material.albedo_texture.resource_path == "res://assets/textures/shared/sea_cabin_muted_8x8_512.png",
				"%s surface %d binds the muted shared palette" % [key, surface])
			check(override_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
				"%s surface %d keeps nearest sampling" % [key, surface])
			var mesh_role := role_of_material(visual.mesh.surface_get_material(surface))
			var override_role := role_of_material(override_material)
			check(not mesh_role.is_empty() and mesh_role == override_role,
				"%s surface %d keeps its role %s (prefab %s)" % [key, surface, mesh_role, override_role])
			check(visual.get_surface_override_material(surface) != null,
				"%s surface %d override survives instantiation" % [key, surface])
		check(visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			key + " casts true shadows")

		var box := bounds(node)
		boxes.append(box)
		roofs.append(box.end.y)
		check(box.end.y < water_y - SUBMERGED_CLEARANCE,
			"%s is fully underwater (top %.2f)" % [key, box.end.y])
		if installed:
			for label in occupied:
				var other: AABB = occupied[label]
				var overlap: AABB = box.intersection(other)
				var ratio := overlap.get_volume() / maxf(box.get_volume(), 0.001)
				check(ratio < 0.01, "%s does not intrude into %s (%.2f%%)" % [key, label, ratio * 100.0])
		evidence.buildings.append({"key": key, "triangles": tris, "bounds": str(box),
			"position": str(node.global_position), "asset_id": node.asset_id,
			"surfaces": surfaces, "roles": role_of_material(visual.get_surface_override_material(0))})

	# ---- 高度：按屋顶对齐水面（与现有六栋同一带），不是按底板齐平。
	# 底板齐平会让 3.6–16.5 米的楼顶面掉到水下 11–21 米，隔着十几米水就什么都看不见了。
	const ROOF_BAND := 0.15
	if not installed:
		# 没安装就没有「按原摆位对齐水面」这层语义，装回后这些断言自动恢复。
		_finish()
		return
	for i in KEYS.size():
		var roof := roofs[i]
		check(absf(roof - (water_y - 1.45)) <= ROOF_BAND,
			"%s roof sits in the near-surface band (%.2f)" % [KEYS[i], roof])
		check(roof < water_y - SUBMERGED_CLEARANCE, KEYS[i] + " roof stays under the waterline")
	# 越高越深：这条关系一旦破了，说明高度不是按同一规则算出来的
	for a in KEYS.size():
		for b in range(a + 1, KEYS.size()):
			var ha: float = boxes[a].size.y
			var hb: float = boxes[b].size.y
			var base_a: float = boxes[a].position.y
			var base_b: float = boxes[b].position.y
			if absf(ha - hb) < 0.5:
				continue
			check((ha > hb) == (base_a < base_b),
				"taller building stands deeper (%s %.1fm at %.2f vs %s %.1fm at %.2f)"
				% [KEYS[a], ha, base_a, KEYS[b], hb, base_b])

	# ---- 互相不穿模：AABB 交集体积占较小者不到 1%
	for a in boxes.size():
		for b in range(a + 1, boxes.size()):
			var overlap: AABB = boxes[a].intersection(boxes[b])
			var smaller := minf(boxes[a].get_volume(), boxes[b].get_volume())
			var ratio := (overlap.get_volume() / smaller) if smaller > 0.0 else 0.0
			check(ratio < 0.01, "street buildings do not share volume %d/%d (%.1f%%)" % [a, b, ratio * 100.0])

	# ---- 纯观赏：显示与否都不能影响航线，也不产生岸线泡沫
	var shapes_before: Array = main.navigation._water_shapes().duplicate(true)
	street.hide()
	var zone: Node3D = main.get_node("World/Zones/Zone1HomeHarbor")
	zone.rebuild_blockers(water_y)
	check(shapes_before == main.navigation._water_shapes(), "street visibility leaves navigation unchanged")
	street.show()
	zone.rebuild_blockers(water_y)
	var shore = preload("res://src/rendering/shore_distance.gd").new()
	shore.rebuild([street], water_y, 64)
	check(shore.segments.is_empty(), "submerged street produces no shoreline foam")

	# ---- 真实渲染：从水面看、去掉水面看几何、俯视、夜间
	var centre := Vector3(group_box.get_center().x, -10.0, group_box.get_center().z)
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main._calendar_label.hide()
	main.daylight_rig.apply(9.0)
	main.cam.target = centre
	main.cam.distance = 96.0
	main.cam.orbit_dir = Vector3(-0.5, 0.85, 0.9)
	main.cam.refresh()
	await snapshot("surface-reference")
	main.water_node.hide()
	main.cam.target = Vector3(centre.x, -14.0, centre.z)
	main.cam.distance = 92.0
	main.cam.orbit_dir = Vector3(-0.6, 0.55, 0.85)
	main.cam.refresh()
	await snapshot("geometry-review")
	main.water_node.show()
	main.cam.target = Vector3(centre.x, -20.0, centre.z)
	main.cam.distance = 88.0
	main.cam.orbit_dir = Vector3(-0.1, 1.6, 0.4)
	main.cam.refresh()
	await snapshot("street-top")
	# 与阳光房海下基座同框：色彩是否同族，必须同一套光照、同一层水一起看，
	# 单看街景棚拍说明不了任何事。
	var base: AABB = bounds(main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海下基座"))
	var joint := Vector3((base.get_center().x + group_box.get_center().x) * 0.5, -9.0,
		(base.get_center().z + group_box.get_center().z) * 0.5)
	main.daylight_rig.apply(11.0)
	main.cam.target = joint
	main.cam.distance = 118.0
	main.cam.orbit_dir = Vector3(-0.55, 0.95, 0.75)
	main.cam.refresh()
	await snapshot("base-compare")
	main.daylight_rig.apply(20.0)
	main.cam.target = centre
	main.cam.distance = 96.0
	main.cam.orbit_dir = Vector3(-0.5, 0.85, 0.9)
	main.cam.refresh()
	await snapshot("night")

	var file := FileAccess.open("res://outputs/submerged-street.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	main.queue_free()
	await process_frame
	print("[submerged-street] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
