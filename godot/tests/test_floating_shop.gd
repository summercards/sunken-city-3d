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
		var part: AABB = mesh.global_transform * mesh.get_aabb()
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

	check(absf(shop_center.x - body_center.x) <= 0.6,
		"shop centered on the sunroom x (dx=%.2f)" % (shop_center.x - body_center.x))
	check(absf((shop_center.z - body_center.z) - SOUTH_METERS) <= 0.6,
		"shop is %.0fm south of the sunroom body (dz=%.2f)" % [SOUTH_METERS, shop_center.z - body_center.z])

	var water_y: float = main.WATER_LEVEL
	var deck_top := shop_center.y + DECK_TOP_LOCAL
	check(absf(deck_top - (water_y + DECK_ABOVE_WATER)) <= 0.02,
		"deck top is %.2fm above water (got %.3f, water %.2f)" % [DECK_ABOVE_WATER, deck_top, water_y])
	# 甲板底面要没进水里，船体/浮筒才不会悬空。
	var deck_bottom := shop_center.y + 2.04
	check(deck_bottom < water_y, "deck slab dips below the water line (%.3f < %.2f)" % [deck_bottom, water_y])

	# 不能压在别的区块上：浮店四周一格（18.5m 见方）必须是开阔水面。
	var half := 9.3
	var clear := true
	for zone_node in main.get_node("World/Zones").get_children():
		if not zone_node.has_method("rebuild_blockers"):
			continue
		for r in zone_node.water_block_rects:
			var rect: Rect2 = r
			if rect.intersects(Rect2(shop_center.x - half, shop_center.z - half, half * 2.0, half * 2.0)):
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
