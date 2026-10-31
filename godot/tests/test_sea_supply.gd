extends SceneTree
## 海上补给站（浮店）的功能接入检查。
##
## 管五件事，任何一件坏了浮店就退回「只能看、上不去」的景观：
##   1. 它作为一个最小区块被登记（Zones 里有 landings / walk）；
##   2. 环廊真的能站、主体里面真的站不进去（封闭立面不是可穿墙）；
##   3. 泊位锚点有效：站立点在甲板、船位在开阔水面、靠岸边在甲板外沿；
##   4. 靠妥 → 上岸 → 走到招牌下 → 按 E 打开补给页，全程走正式链路；
##   5. 存档校验接受「人在浮店甲板」这种状态，而不是判为非法位置。
##
## 运行：python scripts/run_verification.py sea-supply
var main: Node
var checks := 0
var failures := 0
var evidence := {}
const ZONE := "sea_supply"
const DECK_TOP := 1.38
const WATER := 1.12
const COUNTER := Vector3(0, 2.514, 6.6)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.boat.set_process(false)
	for i in 8:
		await process_frame

	_check_registration()
	_check_deck()
	await _check_landing_flow()
	_check_save_rules()

	print("[sea-supply] evidence ", JSON.stringify(evidence))
	print("[sea-supply] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)


func _check_registration() -> void:
	var shop: Node3D = main.get_node_or_null("World/SeaStructures/floating_shop")
	check(shop != null, "shop is instanced under World/SeaStructures")
	if shop == null:
		return
	var zones: Node = root.get_node("Zones")
	var cfg: Dictionary = zones.get_zone(ZONE)
	check(not cfg.is_empty(), "zones.json carries the sea_supply entry")
	check(str(cfg.get("name", "")) == "海上补给站", "zone name is the supply station")
	check(main._zone_nodes.has(ZONE), "registered as a minimal zone in main")
	check(main._zone_nodes.get(ZONE) == shop, "registered node is the shop itself")
	check(shop.walk_areas.size() == 1, "one walkable surface")
	check(shop.landing_points().size() == 1, "exactly one landing")
	check(Array(cfg.get("landings", [])).size() == 1, "zone config exposes the landing")
	check(Array(cfg.get("walk", [])).size() == 1, "zone config exposes the deck")
	evidence["registered"] = {"landings": Array(cfg.get("landings", [])).size(),
		"walk": Array(cfg.get("walk", [])).size()}


func _check_deck() -> void:
	var shop: Node3D = main.get_node("World/SeaStructures/floating_shop")
	var area: Node3D = shop.walk_areas[0]
	check(absf(area.surface_y - DECK_TOP) <= 0.01,
		"deck surface is at %.2f (got %.3f)" % [DECK_TOP, area.surface_y])
	check(absf(area.surface_y - (shop.global_position.y + float(shop.get_meta("deck_top_local", 0.0)))) <= 0.01,
		"deck surface follows the instance transform, not a hardcoded world height")

	var origin: Vector3 = shop.global_position
	# 前廊正中、右侧廊正中：都必须命中。
	check(area.contains_world(origin.x, origin.z + 6.0), "front walkway is walkable")
	check(area.contains_world(origin.x + 8.0, origin.z), "right walkway is walkable")
	check(area.contains_world(origin.x, origin.z - 6.0), "rear walkway is walkable")
	# 封闭主体内部：不该能走进去。
	check(not area.contains_world(origin.x, origin.z), "enclosed body is not walkable")
	check(not area.contains_world(origin.x + 4.0, origin.z + 2.0), "body interior rejects the deck rect")

	# 点在甲板最外沿时，落点要被内收到「整个身影都在板上」。
	var raw_x: float = origin.x
	var raw_z: float = origin.z + 6.95
	var clamped: Vector2 = area.clamp_point(raw_x, raw_z)
	check(clamped.y < raw_z - 0.2, "edge click is inset by the body radius")
	check(area.contains_world(clamped.x, clamped.y), "inset point stays on the deck")
	evidence["deck"] = {"surface_y": area.surface_y, "clamped": [clamped.x, clamped.y],
		"raw_z": raw_z}


func _check_landing_flow() -> void:
	var zones: Node = root.get_node("Zones")
	var state: Node = root.get_node("GameState")
	var l: Dictionary = zones.landing(ZONE, "main")
	check(not l.is_empty(), "landing data resolves")
	if l.is_empty():
		return
	var stand := Vector3(float(l.landStand[0]), float(l.landStand[1]), float(l.landStand[2]))
	var park := Vector3(float(l.boatPark[0]), float(l.boatPark[1]), float(l.boatPark[2]))
	var edge := Vector3(float(l.dockEdge[0]), float(l.dockEdge[1]), float(l.dockEdge[2]))
	check(absf(stand.y - DECK_TOP) <= 0.01, "landing stand sits on the deck")
	check(absf(park.y - WATER) <= 0.01, "boat park sits on the water line")
	check(main._is_open_water(park.x, park.z), "boat park is open water (no blocker under it)")
	check(not main._is_open_water(stand.x, stand.z), "stand point is deck, not water")
	check(edge.z < park.z, "dock edge is between the deck and the parked boat")
	evidence["landing"] = l

	# 靠泊 → 上岸，走的是正式链路（与码头同一套 _select_landing / _on_boat_arrived）。
	state.set_mode(state.Mode.ON_BOAT)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	state.enter_zone(ZONE)
	state.landing_id = "main"
	main.boat.place_at(park, float(l.boatYaw))
	main._select_landing({"zone": ZONE, "landing": "main"})
	for i in 6:
		main._update_walk(1.0 / 60.0)
	check(main.actor_controller.state_id() == "ashore_idle", "docking at the shop lands the actor")
	check(main.player.get_parent() == main, "actor hangs on the world after landing")
	var landed: Vector3 = main.player.global_position
	check(Vector2(landed.x - stand.x, landed.z - stand.z).length() < 0.6,
		"actor stands at the shop landing (d=%.2f)" % Vector2(landed.x - stand.x, landed.z - stand.z).length())

	# 走到招牌下的补给点：同一块甲板内，不应该需要换地面。
	var counter: Node3D = main.get_node("World/SeaStructures/floating_shop/Objects/SupplyCounter")
	var target: Vector3 = counter.global_position
	var area: Node3D = main._zone_nodes[ZONE].walk_areas[0]
	check(area.contains_world(target.x, target.z), "counter stands on the deck")
	check(main._start_walk(area, target), "walk to the counter starts")
	for i in 240:
		main._update_walk(1.0 / 60.0)
		if main.actor_controller.state_id() == "ashore_idle":
			break
	var at_counter: Vector3 = main.player.global_position
	check(main.actor_controller.state_id() == "ashore_idle", "actor settles next to the counter")
	check(Vector2(at_counter.x - target.x, at_counter.z - target.z).length() < 2.0,
		"actor reached the counter area (d=%.2f)" % Vector2(at_counter.x - target.x, at_counter.z - target.z).length())
	evidence["walk"] = {"stand": [landed.x, landed.y, landed.z], "at_counter": [at_counter.x, at_counter.y, at_counter.z]}

	# 按 E：交互点必须真的把商店面板打开（不是只发个静默信号）。
	var hud = main.hud
	var before: bool = hud._panel_open
	var result: Dictionary = counter.interact(main.player)
	check(result.is_empty(), "counter interact produces no gameplay payload")
	check(hud._tab == "shop", "counter opens the supply/shop tab (got " + str(hud._tab) + ")")
	check(hud._panel_open and not before, "counter opens the panel")
	evidence["interaction"] = {"tab": hud._tab, "open": hud._panel_open}
	hud.close_card() if hud.has_method("close_card") else null


func _check_save_rules() -> void:
	var state: Node = root.get_node("GameState")
	var stand: Vector3 = main._current_landing().stand_position() if main._current_landing() != null else Vector3.ZERO
	var ok_data := {"zone": ZONE, "landing": "main", "mode": 0,
		"player": [stand.x, stand.y, stand.z], "boat": []}
	var reason: String = main.validate_world_state(ok_data)
	check(reason == "", "save on the shop deck is valid (got: " + reason + ")")
	# 反例：把人存到海面上，必须被拒。
	var bad := ok_data.duplicate(true)
	bad["player"] = [stand.x + 30.0, stand.y, stand.z]
	check(main.validate_world_state(bad) != "", "save floating over open water is rejected")
	check(state.current_zone == ZONE, "world state stayed in the shop zone during the checks")
