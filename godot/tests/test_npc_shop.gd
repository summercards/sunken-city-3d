extends SceneTree
## Pure NPC + shop contract suite. No main scene, no Autoload, no UI.
const Catalog = preload("res://src/npc/npc_catalog.gd")
const NpcService = preload("res://src/npc/npc_service.gd")
const ShopCatalog = preload("res://src/shop/shop_catalog.gd")
const ShopService = preload("res://src/shop/shop_service.gd")
const Inventory = preload("res://src/inventory/inventory.gd")
var checks := 0
var failures := 0
var bag = Inventory.new(24)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(root.get_node_or_null("Economy") == null and root.get_node_or_null("GameState") == null and root.get_node_or_null("Zones") == null, "no production Autoload")
	check(Catalog.validate() == "", "seven NPC catalog validates")
	check(Catalog.ids().size() == 7 and Catalog.relationships().size() == 9, "seven roster and nine relationship edges")
	var npc = NpcService.new()
	check(npc.roster().size() == 7, "runtime roster size")
	check(npc.meet("npc_hua_yi").ok, "meet flower vendor")
	check(npc.request_vendor("npc_hua_yi").ok, "vendor request only through NPC port")
	check(npc.talk("npc_hua_yi", 1).ok, "daily talk grants affinity")
	check(not npc.talk("npc_hua_yi", 1).ok, "daily talk limit")
	var schedule := npc.schedule_at("npc_hua_yi", {"hour": 12.0}, {"anchor_flower_shop": Vector3.ZERO})
	check(schedule.anchor_id == "anchor_flower_shop" and not schedule.fallback, "schedule resolves data anchor")
	var fallback := npc.schedule_at("npc_hua_yi", {"hour": 12.0}, {})
	check(fallback.fallback and fallback.action == "home_fallback", "schedule falls back to residence")
	var before := npc.to_dict()
	var graph := npc.relationship_graph()
	graph[0].effective = 9999
	check(npc.relationship_graph()[0].effective != 9999, "relationship query returns copy")
	var shop = ShopService.new()
	shop.configure(bag)
	check(ShopCatalog.validate() == "", "two shops catalog validates")
	check(ShopCatalog.ids().size() == 2, "flower and general shops")
	bag.set_count("coins", 100)
	var snap := shop.shop_snapshot("shop_flower")
	check(snap.products.size() == 5 and snap.coins == 100, "flower shop snapshot")
	var buy := shop.buy("shop_flower", "flower_seed_blue", 2)
	check(buy.ok and bag.count("flower_seed_blue") == 2 and bag.count("coins") == 84, "atomic flower purchase")
	var coins_before := bag.count("coins")
	var blocked := shop.buy("shop_flower", "flower_seed_blue", 999)
	check(not blocked.ok and bag.count("coins") == coins_before, "over-limit purchase preserves state")
	var saved := npc.to_dict()
	var restored = NpcService.new()
	restored.from_dict(saved)
	check(restored.to_dict() == saved, "npc snapshot roundtrip")
	check(restored.validate_snapshot(saved) == "", "npc snapshot validation")
	# Release RefCounted owners before shutdown; the verification harness treats
	# ObjectDB leaks as unexpected errors.
	restored = null; npc = null; shop = null; bag = null
	await process_frame
	print("[npc-shop] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
