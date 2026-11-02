extends SceneTree
const Wood = preload("res://src/pickups/wood_bundle.gd")
const Props = preload("res://src/pickups/sea_props.gd")
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var main: Node
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	print("[wood-bundles] ", "PASS " if value else "FAIL ", label)
	if not value: failures += 1
func yields_by_slot() -> Dictionary:
	var result := {}
	for item in main.props.crates: result[item.slot] = item.wood_amount
	return result
func run() -> void:
	var near := Wood.SUNROOM_CENTER + Vector2(25, 0)
	var outer := Wood.SUNROOM_CENTER + Vector2(180, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261102
	var counts := [Vector3i.ZERO, Vector3i.ZERO]
	var extrema := [Vector2i(99, 0), Vector2i(99, 0), Vector2i(99, 0)]
	for region in 2:
		for i in 20000:
			var amount := Wood.draw(near if region == 0 else outer, rng)
			var tier := Wood.tier(amount)
			if tier < 0: failures += 1; continue
			counts[region][tier] += 1
			extrema[tier].x = mini(extrema[tier].x, amount)
			extrema[tier].y = maxi(extrema[tier].y, amount)
	check(counts[0].x > 17600 and counts[0].z > 100 and counts[0].z < 300, "20k near draws: small about 90%, large about 1%")
	check(counts[1].x > 7600 and counts[1].x < 8400 and counts[1].y > 7600 and counts[1].z > 3600 and counts[1].z < 4400, "20k outer draws: 40/40/20 distribution")
	check(extrema == [Vector2i(2,3), Vector2i(7,9), Vector2i(12,16)], "all inclusive endpoints appear, no quantities between tiers")
	var previous := 0.0
	var smooth := true
	for distance in range(45,151):
		var odds := Wood.weights(Wood.SUNROOM_CENTER + Vector2(distance, 0))
		smooth = smooth and odds.z >= previous and is_equal_approx(odds.x + odds.y + odds.z, 1.0)
		previous = odds.z
	check(smooth, "large odds increase continuously from 45m through 150m and weights sum to one")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.props.set_process(false)
	main.boat.set_process(false)
	main.world_clock.paused = true
	var economy := root.get_node("Economy")
	economy.set_process(false)
	var props = main.props
	var clock: Dictionary = main.world_clock.query()
	var at := Vector3(400,1.12,400)
	main.boat.place_at(at, 0)
	props.sync_population(clock, at)
	var first := yields_by_slot()
	props.sync_population(clock, Vector3(-400,1.12,-400))
	props.sync_population(clock, at)
	check(yields_by_slot() == first, "streaming away and back retains exact yields")
	var snapshot := Save.encode(main)
	check(Save.write("user://wood-bundles.json",main).ok and Save.restore(main,Save.read("user://wood-bundles.json").snapshot).ok, "quantities and generation caches roundtrip through disk")
	check(yields_by_slot() == first, "restoring disk does not reroll yields")
	for bad in [1,4,6,10,11,17,2.5,"8"]:
		var broken := snapshot.duplicate(true)
		broken.pickups.crates[0].wood_amount = bad
		check(not Save.restore(main,broken).ok and yields_by_slot() == first, "invalid yield rejected without changing live state: " + str(bad))
	var broken := snapshot.duplicate(true)
	broken.pickups.ocean.harvested["0:0:fish:0"] = 1
	check(not Save.restore(main,broken).ok, "fish slot cannot masquerade as wood generation")
	broken = snapshot.duplicate(true)
	broken.pickups.ocean.wood_yields["0:0:wood:0"] = 5
	check(not Save.restore(main,broken).ok, "unloaded cached yield also validates tier gaps")
	var legacy := snapshot.duplicate(true)
	legacy.pickups.ocean.erase("harvested")
	legacy.pickups.ocean.erase("wood_yields")
	for item in legacy.pickups.crates: item.erase("wood_amount")
	check(Save.restore(main,legacy).ok, "legacy records without quantity fields load as three units")
	props.sync_population(clock, Vector3(-400,1.12,-400))
	props.sync_population(clock, at)
	var legacy_stable := true
	for item in props.crates: legacy_stable = legacy_stable and item.wood_amount == 3
	check(legacy_stable, "legacy three-unit bundles retain yield after unloading")
	var ancient := legacy.duplicate(true)
	ancient.pickups.erase("ocean")
	ancient.pickups.crates = ancient.pickups.crates.slice(0, 5)
	ancient.pickups.schools = ancient.pickups.schools.slice(0, 3)
	for entity in ancient.pickups.crates + ancient.pickups.schools: entity.erase("slot")
	var landing: Dictionary = root.get_node("Zones").landing("zone1", "main")
	ancient.game.boat = [landing.boatPark[0],landing.boatPark[1],landing.boatPark[2],landing.boatYaw]
	check(Save.restore(main,ancient).ok, "pre-ocean saves also retain their existing bundle quantities")
	var ancient_stable := true
	var ancient_home := 0
	for entity in props.crates:
		if str(entity.slot).begins_with("0:0:wood:"):
			ancient_stable = ancient_stable and entity.wood_amount == 3
			ancient_home += 1
	check(ancient_stable and ancient_home == 5 and props.ocean.missing.has("0:0:wood:5"), "pre-ocean remaining bundles stay three and missing bundle stays depleted")
	Save.restore(main,snapshot)
	# Exercise actual collection and mesh production for every permitted count.
	var totals_ok := true
	var visuals_ok := true
	var copies_match := true
	for amount in [2,3,7,8,9,12,13,14,15,16]:
		var item: Dictionary = props.crates[0]
		item.wood_amount = amount
		var before: int = economy.count("wood")
		var received: Dictionary = props.collect_crate(item)
		totals_ok = totals_ok and received.reward.wood == amount and economy.count("wood") == before + amount and props.collect_crate(item).is_empty()
		var mesh: Node3D = props._build_crate_mesh("planks", amount)
		var units := mesh.find_children("Bundle*", "Node3D", false, false)
		var expected := 1 if amount <= 3 else (2 if amount <= 9 else 3)
		var logs := mesh.find_children("Log*", "MeshInstance3D", true, false).size()
		visuals_ok = visuals_ok and units.size() == expected and logs == expected * 3 and is_equal_approx((mesh.get_node("Ring").mesh as PlaneMesh).size.x, float(Wood.profile(amount).ring) * 2.0)
		for unit in units:
			copies_match = copies_match and unit.scale == Vector3.ONE
			for part in unit.get_children():
				var master: MeshInstance3D = units[0].get_node(NodePath(str(part.name)))
				copies_match = copies_match and part.transform == master.transform and part.mesh == master.mesh and part.material_override == master.material_override
		mesh.free()
	check(totals_ok, "all ten possible yields award the exact quantity once")
	check(visuals_ok, "all ten yields use one/two/three small bundles with tier-sized ripples")
	check(copies_match, "every copied bundle preserves its master's log/strap geometry, materials and scale")
	Save.restore(main,snapshot)
	var item: Dictionary = props.crates[0]
	item.wood_amount = 16
	economy.inventory.from_dict({"capacity":1,"counts":{"wood":990}})
	var missing_before: Dictionary = props.ocean.missing.duplicate(true)
	check(props.collect_crate(item).is_empty() and props.crates.has(item) and props.ocean.missing == missing_before and economy.count("wood") == 990, "bag with nine free units rejects the entire 16-unit bundle without cooldown")
	Save.restore(main,snapshot)
	var slot: String = props.crates[0].slot
	props.collect_crate(props.crates[0])
	var due: float = props.ocean.missing[slot]
	check(props.ocean.harvested[slot] == 1 and not props.ocean.wood_yields.has(slot), "successful harvest advances generation and clears only its old yield")
	props.sync_population({"day":1,"hour":due+0.001},at)
	check(not props.ocean.missing.has(slot) and props.ocean.wood_yields.has(slot), "game-hour cooldown produces a fresh quantity")
	var regenerated := yields_by_slot()
	props.sync_population({"day":1,"hour":due+0.001},Vector3(-400,1.12,-400))
	props.sync_population({"day":1,"hour":due+0.001},at)
	check(yields_by_slot() == regenerated, "new replenishment remains stable on revisit")
	# Range checks use actual pickup state, including failure beyond each tier.
	for amount in [3,8,15]:
		item = props.crates[0]
		item.wood_amount = amount
		var reach: float = props.crate_reach(item)
		main.boat.place_at(item.root.position + Vector3(reach-0.01,0,0),0)
		main._begin_pick_sail({"type":"crate","item":item})
		check(main._pick_in_reach(), "tier %d: gather accepts inside %.1fm" % [amount,reach])
		main.boat.place_at(item.root.position + Vector3(reach+0.01,0,0),0)
		check(not main._pick_in_reach(), "tier %d: gather rejects outside %.1fm" % [amount,reach])
	main._cancel_pending_pick()
	if DisplayServer.get_name() != "headless": await capture()
	print("[wood-bundles] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func capture() -> void:
	main.daylight_rig.apply(9)
	main.hud.hide()
	main.cam.suspend_follow()
	main.cam.target = Vector3(403,1.12,400)
	main.cam.distance = 17
	main.cam.orbit_dir = Vector3(0,1.0,0.7)
	main.cam.refresh()
	var visual_nodes: Array[Node3D] = []
	for index in 3:
		var amount: int = [3,8,15][index]
		var mesh: Node3D = main.props._build_crate_mesh("planks",amount)
		main.add_child(mesh)
		mesh.position = Vector3(398+index*5,1.12,400)
		Props.FishVisual.sync_ripple(mesh.get_node("Ring"),main.props.water_surface,main.props._t)
		visual_nodes.append(mesh)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/wood-bundles-comparison.png")
	# Prove the outer log is clickable beyond the old center-only 26px disc.
	var large: Node3D = visual_nodes[2]
	var demo := {"kind":"planks","wood_amount":15,"root":large}
	var existing: Array = main.props.crates
	main.props.crates = [demo]
	var tip: Vector3 = large.get_node("Bundle01/Log02").global_position
	var tip_screen: Vector2 = main.cam.unproject_position(tip)
	var center_screen: Vector2 = main.cam.unproject_position(large.global_position+Vector3.UP*0.4)
	check(tip_screen.distance_to(center_screen)>26.0, "outer log lies beyond the former 26px center hotspot")
	var hit: Dictionary = main.props.pick(tip_screen,main.cam)
	check(not hit.is_empty() and hit.item == demo, "large bundle outer log is clickable in the real view")
	main.props.crates = existing
	for node in visual_nodes: node.queue_free()
