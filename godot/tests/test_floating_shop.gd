extends SceneTree
## 海上悬浮商铺（SEA-SCENE-FSH-ASSEMBLY）的运行时接入检查。
##
## 管三件事，任何一件被后续改动打破都会红：
##   1. 预制体里 4 个材质**序列化**在 tscn 上（不是靠 @tool 运行时补色，
##      否则编辑器里重新实例化就变回 GLB 的 0.8 灰底材 —— 水下六栋踩过）；
##   2. 位置 = 阳光房主体（后部方形建筑 + 前部倾斜太阳能房）占地中心正南 50 米；
##   3. 甲板顶面与家园甲板同高（水面 +0.26），并且真的被水面阻挡登记到，
##      否则船会从浮店中间穿过去。
const PREFAB := "res://scenes/facilities/floating_shop.tscn"
const NODE_PATH := "World/SeaStructures/floating_shop"
const BODY := ["后部方形建筑", "前部倾斜太阳能房"]
const SOUTH_METERS := 50.0
## 甲板顶面离水面的高度：与 zone1 家园甲板（surface_y 1.38 / 水面 1.12）一致。
const DECK_ABOVE_WATER := 0.26
const DECK_TOP_LOCAL := 2.514
const ROLE_BY_SURFACE := {
	"FSH_SEA_Matte": "matte", "FSH_SEA_Metal": "metal",
	"FSH_SEA_Gloss": "gloss", "FSH_SEA_Emission": "emission",
}
var checks := 0
var failures := 0
var main
var evidence := {"model": {}, "sunroom": {}, "shop": {}, "blockers": {}}

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
		# 阳光房是 MultiMesh 装配，浮店是整体网格；两种都要算进来。
		if not (mesh is MeshInstance3D or mesh is MultiMeshInstance3D):
			continue
		var mesh_transform: Transform3D = mesh.transform
		if mesh.is_inside_tree():
			mesh_transform = mesh.global_transform
		else:
			var ancestor: Node = mesh.get_parent()
			while ancestor is Node3D:
				mesh_transform = (ancestor as Node3D).transform * mesh_transform
				ancestor = ancestor.get_parent()
		var part: AABB = mesh_transform * mesh.get_aabb()
		result = part if first else result.merge(part)
		first = false
	return result


func run() -> void:
	_check_prefab()
	await _check_placement()
	print("[floating-shop] evidence ", JSON.stringify(evidence))
	print("[floating-shop] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)


func _check_prefab() -> void:
	var packed: PackedScene = load(PREFAB)
	check(packed != null, "prefab loads")
	if packed == null:
		return
	var shop: Node = packed.instantiate()
	var surfaces := {}
	for child in shop.find_children("FSH_SEA_*", "MeshInstance3D", true, false):
		surfaces[str(child.name)] = child.mesh.get_surface_count()
	var visual_bounds := bounds(shop)
	check(shop.get_meta("source_version", "") == "v003", "rectangular v003 prefab metadata")
	check(visual_bounds.size.x > 20.0 and visual_bounds.size.z > 15.0,
		"rectangular platform and its fenders have the new extent")
	check(absf(visual_bounds.size.x / visual_bounds.size.z - 4.0 / 3.0) < 0.05,
		"building footprint is approximately 4:3 including fenders")
	# 2026-10-31 零售细修：玻璃橱窗回来了（用户要求恢复上一版的透明玻璃与摆件），
	# 但它是**陈列面**不是入口 —— 门仍然为 0，主体内部仍不可进入（由 sea-supply 断言）。
	check(shop.get_meta("storefront_windows", -1) == 4,
		"four glazed display bays are back (got %s)" % str(shop.get_meta("storefront_windows", -1)))
	check(shop.get_meta("storefront_doors", -1) == 0, "no storefront door was added")
	check(shop.get_meta("storefront_glazing", "") == "display_only",
		"glazing is declared display-only")
	check(int(shop.get_meta("retail_displays", 0)) >= 4, "exterior retail displays present")
	check(int(shop.get_meta("interior_lamps", 0)) >= 4, "interior decorative lamps present")
	shop.free()
	check(surfaces.size() == 4, "prefab has exactly 4 runtime meshes (display support excluded)")
	for key in ROLE_BY_SURFACE:
		check(int(surfaces.get(key, 0)) == 1, "one surface on " + key)
	# 序列化检查：读 PackedScene 状态，不实例化、不跑脚本。
	var state := packed.get_state()
	var overrides := {}
	for node_index in state.get_node_count():
		var node_name := str(state.get_node_name(node_index))
		for p in state.get_node_property_count(node_index):
			var prop := str(state.get_node_property_name(node_index, p))
			if not prop.begins_with("surface_material_override"):
				continue
			var material = state.get_node_property_value(node_index, p)
			overrides[node_name] = material.resource_path if material is Material else ""
	for node_name in ROLE_BY_SURFACE:
		var path := str(overrides.get(node_name, ""))
		check(path == "res://assets/materials/floating_shop/" + ROLE_BY_SURFACE[node_name] + ".tres",
			"serialized palette override on " + node_name + " (got " + path + ")")
	evidence.model = {"surfaces": surfaces, "overrides": overrides}


func _check_placement() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.boat.set_process(false)
	for i in 6:
		await process_frame

	var shop: Node3D = main.get_node_or_null(NODE_PATH)
	check(shop != null, "shop is instanced under World/SeaStructures")
	if shop == null:
		return
	check(shop.get_parent().name == "SeaStructures" and shop.get_parent().get_parent().name == "World",
		"shop lives in World/SeaStructures (not inside a zone)")

	var zone: Node = main.get_node("World/Zones/Zone1HomeHarbor")
	var body := AABB()
	var first := true
	for child_name in BODY:
		var node: Node3D = zone.find_child(child_name, true, false)
		check(node != null, "sunroom body part " + child_name)
		if node == null:
			continue
		var part := bounds(node)
		body = part if first else body.merge(part)
		first = false
	var body_center := body.get_center()
	var shop_center := shop.global_position
	evidence.sunroom = {"body_min": body.position, "body_max": body.end, "body_center": body_center}
	evidence.shop = {"origin": shop_center, "aabb": bounds(shop)}

	# 参照系用冻结值，不用现场量的 AABB。
	#
	# 原因：阳光房的 MultiMesh 装配由 sunny_bloom_visual.gd 在 _ready 里装实例，
	# 而 `MultiMeshInstance3D.get_aabb()` 在这个引擎版本里会随 multimesh 是否
	# 已重算过包围盒而返回两种结果（裸网格 vs 含实例）。同一份场景、同一帧数，
	# 一次跑出中心 z=1.813（union 14.2×11.15），另一次 z=2.474（union 14.3×10.68），
	# 差 0.66 米刚好越过容差 —— 那是测量口径在飘，不是浮店在动。
	# 所以「正南 50 米」这条锚在冻结基准上，现场只做存在性与大范围合理性复核。
	const SUNROOM_BODY_CENTER := Vector3(6.158222, 4.806684, 1.813078)
	const LIVE_TOLERANCE := 3.0
	check(absf(shop_center.x - SUNROOM_BODY_CENTER.x) <= 0.6,
		"shop centered on the sunroom x (dx=%.2f)" % (shop_center.x - SUNROOM_BODY_CENTER.x))
	check(absf((shop_center.z - SUNROOM_BODY_CENTER.z) - SOUTH_METERS) <= 0.6,
		"shop is %.0fm south of the frozen sunroom body centre (dz=%.2f)"
			% [SOUTH_METERS, shop_center.z - SUNROOM_BODY_CENTER.z])
	# 冗余：现场量出来的中心必须与冻结值同量级，真正的世界位移照样会被抓到。
	check(absf(shop_center.z - body_center.z - SOUTH_METERS) <= LIVE_TOLERANCE,
		"live sunroom body agrees with the frozen reference (dz=%.2f)"
			% (shop_center.z - body_center.z))

	var water_y: float = main.WATER_LEVEL
	var deck_top := shop_center.y + DECK_TOP_LOCAL
	check(absf(deck_top - (water_y + DECK_ABOVE_WATER)) <= 0.02,
		"deck top is %.2fm above water (got %.3f, water %.2f)" % [DECK_ABOVE_WATER, deck_top, water_y])
	# 与阳光房一致：0.22m实板，板顶+0.26m，板底+0.04m；浮舱仍在板下。
	var deck_bottom := deck_top - 0.22
	check(absf(deck_bottom - (water_y + 0.04)) <= 0.02,
		"sunroom-standard thin slab bottom is 0.04m above water")
	check(absf(float(shop.get_meta("single_storey_clear_height", 0.0)) - 4.866335) < 0.001,
		"storey height follows measured formal sunroom")
	check(absf(float(shop.get_meta("column_width", 0.0)) - 0.5175) < 0.001,
		"main columns follow sunroom cross section")
	check(absf(float(shop.get_meta("plank_width", 0.0)) - 0.893551) < 0.001,
		"platform plank rhythm follows sunroom")

	# 用当前几何包络，避免改成长方形后仍只检查历史圆盘范围。
	var shop_bounds := bounds(shop)
	var footprint := Rect2(Vector2(shop_bounds.position.x, shop_bounds.position.z),
		Vector2(shop_bounds.size.x, shop_bounds.size.z)).grow(0.4)
	var clear := true
	for zone_node in main.get_node("World/Zones").get_children():
		if not zone_node.has_method("rebuild_blockers"):
			continue
		for r in zone_node.water_block_rects:
			var rect: Rect2 = r
			if rect.intersects(footprint):
				clear = false
				printerr("  overlap with ", zone_node.name, " ", rect)
	check(clear, "shop water footprint does not overlap another zone")

	# 水面阻挡：船不能穿过浮店。走的是 main 自己的唯一入口。
	var shapes: Array = main._water_shapes()
	var covered: bool = not main._is_open_water(shop_center.x, shop_center.z)
	evidence.blockers = {"shapes": shapes.size(), "center_blocked": covered,
		"shop_rects": shop.water_block_rects.size()}
	check(shop.water_block_rects.size() > 0, "shop derived water blockers from its own geometry")
	check(covered, "boat cannot sail through the shop center")
	# These points lie in the rectangular deck's corners, outside the old disc.
	for offset in [Vector2(-8.7, -6.2), Vector2(8.7, -6.2), Vector2(-8.7, 6.2), Vector2(8.7, 6.2)]:
		check(not main._is_open_water(shop_center.x + offset.x, shop_center.z + offset.y),
			"rectangular deck corner blocks boats " + str(offset))
