extends SceneTree
## Runs without ANY Autoload or main scene. Production rule classes + explicit fake ports.
const InventoryLib = preload("res://src/inventory/inventory.gd")
const FarmLib = preload("res://src/farming/farm.gd")
const FarmPorts = preload("res://src/farming/farming_ports.gd")
const OrdersLib = preload("res://src/orders/orders.gd")
const OrderPorts = preload("res://src/orders/order_ports.gd")
const AirLib = preload("res://src/diving/dive_air.gd")
const SalvageLib = preload("res://src/salvage/salvage.gd")
var checks := 0
var failures := 0
var bag = InventoryLib.new(24)
var access := ""
var greenhouse := false
var tier := 1

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func pay(cost: Dictionary) -> bool:
	if not bag.has_all(cost): return false
	for id in cost: bag.remove(str(id), int(cost[id]))
	return true

func give(rewards: Dictionary) -> Dictionary:
	for id in rewards: bag.add(str(id), int(rewards[id]))
	return rewards

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(not root.has_node("Economy") and not root.has_node("GameState") and not root.has_node("Zones"), "no production Autoload")
	var farm = FarmLib.new()
	var fp = FarmPorts.new()
	fp.inventory = bag
	fp.pay = pay
	fp.give = give
	fp.has_greenhouse = func() -> bool: return greenhouse
	fp.access_reason = func(_row: Dictionary) -> String: return access
	farm.configure(fp)
	root.add_child(farm)
	var id := str(farm.specs[0].id)
	check(root.get_child_count() == 1, "only farming node, no main scene or world")
	check(farm.plant(id, "lettuce").has("blocked"), "missing seed rejects")
	bag.set_count("coins", 20)
	check(not farm.buy_seed("lettuce").has("blocked"), "seed purchase via injected inventory")
	check(bag.count("coins") == 16 and bag.count("lettuce_seed") == 1, "purchase exact charge")
	access = "locked by fake progression"
	check(farm.plant(id, "lettuce").has("blocked") and bag.count("lettuce_seed") == 1, "locked plot does not consume seed")
	access = ""
	check(farm.plant(id, "lettuce").get("event") == "planted", "plant succeeds without Economy")
	var exposed: Dictionary = farm.state(id)
	exposed.remaining=0.0
	var definitions: Dictionary=farm.crop_definitions()
	definitions.lettuce.seed_price=0
	var plots: Array=farm.plot_specs()
	plots.clear()
	check(farm.phase(id)=="growing" and farm.crop_def("lettuce").seed_price==4 and not farm.plot_specs().is_empty(),"farm queries cannot mutate owned state or definitions")
	var state_count: int=farm.states.size()
	farm.state("unknown-query")
	check(farm.states.size()==state_count,"unknown plot query is side-effect free")
	farm.advance_day()
	check(farm.state(id).remaining == 3, "dry day does not grow")
	farm.water(id)
	var water: int = farm.watering_can
	check(farm.water(id).has("blocked") and farm.watering_can == water, "repeat watering is rejected")
	for n in 3:
		farm.water(id)
		farm.advance_day()
	check(farm.phase(id) == "ready", "three watered days mature")
	var snapshot: Dictionary = farm.to_dict()
	farm.from_dict({})
	farm.from_dict(snapshot)
	check(farm.to_dict() == snapshot, "farm snapshot roundtrip")
	check(farm.harvest(id).get("event") == "harvested" and bag.count("vegetable") == 2, "harvest writes injected inventory")
	check(farm.harvest(id).has("blocked") and bag.count("vegetable") == 2, "repeat harvest no duplicate reward")
	greenhouse = true
	check(farm.grow_days("lettuce") == 2, "facility bonus supplied through query")
	check(not farm.select_crop("missing") and farm.select_crop("tomato"), "crop selection is validated command")
	bag.set_count("tomato_seed", 1)
	farm.plant(id, "tomato")
	for n in 20:
		farm.refill()
		farm.water(id)
		farm.advance_day()
	bag.from_dict({"capacity": 1, "counts": {"wood": 9999}})
	check(farm.harvest(id).has("blocked") and farm.phase(id) == "ready", "full inventory preserves mature crop")
	bag.clear()
	var orders = OrdersLib.new()
	var op = OrderPorts.new()
	op.inventory = bag
	op.give = give
	op.max_tier = func() -> int: return tier
	orders.configure(op)
	root.add_child(orders)
	check(root.get_child_count() == 2, "orders run without world or UI")
	orders.rng.seed = 42
	orders.reset()
	check(orders.slots.size() == 3, "three offers")
	var offers: Array=orders.offers()
	offers[0].pay=0
	var first_offer: Dictionary=orders.offer_at(0)
	first_offer.amount=999999
	check(orders.offer_at(0).pay>0 and orders.offer_at(0).amount!=999999 and orders.offer_at(-1).is_empty(),"order queries cannot mutate live offers")
	var offer: Dictionary = orders.slots[0].duplicate(true)
	check(not orders.fulfill(str(offer.uid)).ok, "no goods rejects order")
	bag.set_count(str(offer.item), int(offer.amount))
	var coins: int = bag.count("coins")
	check(orders.fulfill(str(offer.uid)).ok, "order commits via injected inventory")
	check(bag.count("coins") == coins + int(offer.pay), "exact reward")
	check(not orders.fulfill(str(offer.uid)).ok, "order reward cannot repeat")
	orders.tick(10.0)
	var before: Array = orders.slots.duplicate(true)
	orders.tick(100000.0)
	check(orders.slots == before, "offers never expire")
	tier = 3
	check(orders.max_tier() == 3, "tier query injected")
	var saved: Dictionary = orders.to_dict()
	orders.from_dict(saved)
	check(orders.to_dict() == saved, "order snapshot roundtrip")
	var air = AirLib.new()
	check(air.update(1000, 100, true, true) == "empty", "isolated oxygen depletion")
	check(air.recover > 0.0, "depletion recovery state")
	var salvage = SalvageLib.new()
	salvage.start()
	check(salvage.is_active(), "isolated salvage starts")
	farm.queue_free()
	orders.queue_free()
	await process_frame
	print("[modules] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
