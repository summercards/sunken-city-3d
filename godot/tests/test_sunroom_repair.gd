extends SceneTree
## SEA-SUNROOM-R01/R02/R03 + SEA-SAVE compatibility.
## The test owns fake material ports; no Economy singleton or main scene is loaded.

var checks := 0
var failures := 0
var paid: Dictionary = {}
var stock := {"wood": 20, "soil": 2, "glass": 1}
var service

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func has_cost(cost: Dictionary) -> bool:
	for id in cost:
		if int(stock.get(id, 0)) < int(cost[id]):
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not has_cost(cost):
		return false
	for id in cost:
		stock[id] = int(stock.get(id, 0)) - int(cost[id])
		paid[id] = int(paid.get(id, 0)) + int(cost[id])
	return true

func missing(cost: Dictionary) -> String:
	var bits: Array[String] = []
	for id in cost:
		var lack := int(cost[id]) - int(stock.get(id, 0))
		if lack > 0:
			bits.append("%s×%d" % [id, lack])
	return "还差 " + "  ".join(bits) if not bits.is_empty() else ""

func run() -> void:
	service = preload("res://src/facilities/sunroom_service.gd").new()
	service.configure({
		"construction_has": Callable(self, "has_cost"),
		"construction_pay": Callable(self, "pay"),
		"construction_missing_text": Callable(self, "missing"),
	})
	check(service.stage == "ruined", "new sunroom starts damaged")
	check(not service.ladder_repaired() and not service.upper_restored(), "new sunroom has no upper access")
	check(service.can_repair_ladder(), "wood is enough for ladder repair")
	var repair: Dictionary = service.repair_ladder()
	check(repair.get("event", "") == "sunroom_ladder_repaired", "ladder repair succeeds")
	check(service.stage == "ladder_fixed" and service.ladder_repaired(), "ladder stage is persisted in memory")
	check(int(paid.get("wood", 0)) == 5, "ladder consumes exactly five boards")
	check(service.repair_ladder().has("blocked"), "ladder cannot be paid twice")
	check(service.can_restore_upper(), "upper restoration sees wood soil and glass ports")
	var upper: Dictionary = service.restore_upper()
	check(upper.get("event", "") == "sunroom_upper_restored", "upper restoration succeeds")
	check(service.stage == "restored" and service.upper_restored(), "upper stage unlocks")
	check(int(paid.get("wood", 0)) == 13 and int(paid.get("soil", 0)) == 2 and int(paid.get("glass", 0)) == 1,
		"upper restoration consumes the documented cost")
	var snapshot: Dictionary = service.to_dict()
	check(preload("res://src/facilities/sunroom_service.gd").validate_snapshot(snapshot) == "", "sunroom snapshot validates")
	var restored = preload("res://src/facilities/sunroom_service.gd").new()
	restored.from_dict(snapshot)
	check(restored.stage == "restored" and restored.upper_restored(), "sunroom snapshot round-trips")
	var bad := snapshot.duplicate(true)
	bad.stage = "restored"
	bad.ladder_repaired = false
	check(preload("res://src/facilities/sunroom_service.gd").validate_snapshot(bad) != "", "upper without ladder is rejected")
	print("[sunroom-repair] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
