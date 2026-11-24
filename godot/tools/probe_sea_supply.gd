extends SceneTree
## 海上补给站（浮店）接入探针：只读，不改世界状态。
##
## 目的：把「区块登记 / 行走面 / 泊位 / 水面可达 / 交互点」这几件在运行时
## 真正成立的事一次打出来，避免靠截图猜。数值写进 outputs/sea-supply-probe.json。
var main: Node
const Scope = preload("res://src/core/play_scope.gd")
const Transfer = preload("res://src/navigation/berth_transfer.gd")

func _init() -> void:
	call_deferred("run")

func v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.boat.set_process(false)
	for i in 8:
		await physics_frame

	var zones: Node = root.get_node_or_null("Zones")
	var report := {"schema": "sea.probe.sea_supply", "engine": Engine.get_version_info()}
	var shop: Node3D = main.get_node_or_null("World/SeaStructures/floating_shop")
	report["shop_present"] = shop != null
	if shop != null:
		report["shop_global"] = v3(shop.global_position)
		report["registered"] = main._zone_nodes.has("sea_supply")
		report["zone_id"] = str(shop.zone_id)
		report["walk_areas"] = shop.walk_areas.size()
		var area = shop.walk_areas[0] if shop.walk_areas.size() > 0 else null
		if area != null:
			report["area"] = {
				"area_id": area.area_id, "zone_id": area.zone_id,
				"surface_y": area.surface_y, "rects": area.rects.size(),
				"body_radius": area.body_radius,
				"world_center": v3(area.center_world()),
			}
		report["landings"] = shop.landing_points().size()
		var cfg: Dictionary = zones.get_zone("sea_supply")
		report["zone_landings"] = cfg.get("landings", [])
		report["zone_walk"] = cfg.get("walk", [])
		var l: Dictionary = zones.landing("sea_supply", "main")
		report["landing_data"] = l
		var berth: Node3D = shop.landing_point("main")
		if berth != null:
			var park := berth.get_node("BoatPark") as Marker3D
			var center := Vector3(park.global_position.x, main.boat.WATER_LEVEL, park.global_position.z)
			var pose := Transform3D(Basis(Vector3.UP, park.global_rotation.y), center)
			report["boat_park_hull_clear"] = main.boat.hull_clear_at(pose)
			var feet := Transfer.new().safe_feet(main.player, berth.stand_position(), 0.25, 0.25)
			report["stand_has_collision_support"] = feet.is_finite()
		var counter := shop.get_node_or_null("Objects/SupplyCounter")
		report["counter_present"] = counter != null
		if counter != null:
			report["counter_signal"] = counter.has_signal("opened")
			report["counter_focus_radius"] = counter.focus_radius
		report["zone_enabled"] = Scope.zone_enabled("sea_supply")
		report["ground_space"] = shop.ground_space != null
	var file := FileAccess.open("res://outputs/sea-supply-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("[sea-supply-probe] ", JSON.stringify(report))
	var ok: bool = report.get("shop_present", false) and report.get("registered", false)
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
