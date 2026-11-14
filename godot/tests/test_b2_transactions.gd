extends SceneTree

const Inventory = preload("res://src/inventory/inventory.gd")
const Farm = preload("res://src/farming/farm.gd")
const FarmPorts = preload("res://src/farming/farming_ports.gd")
const Orders = preload("res://src/orders/orders.gd")
const Fishery = preload("res://src/aqua/fishery_service.gd")
const NpcService = preload("res://src/npc/npc_service.gd")
const Registry = preload("res://src/save/snapshot_registry.gd")

var checks := 0
var failures := 0
var inv
var npc
var reentrant_exchange := {}
var reentrant_restore := {}
var reentrant_service_restore := {}
var restored_count := 0
var reentrant_order_result := {}

func _on_restored() -> void:
	restored_count += 1

class Host extends RefCounted:
	var inventory
	var day := 1
	var exchange_calls := 0
	var result_calls := 0

	func exchange(costs: Dictionary, gains: Dictionary) -> Dictionary:
		exchange_calls += 1
		return inventory.exchange(costs, gains)

	func remove(id: String, amount: int) -> bool:
		return inventory.remove(id, amount)

	func count(id: String) -> int:
		return inventory.count(id)

	func clock() -> Dictionary:
		return {"day": day, "hour": 8.0, "weather": "clear"}

	func result(_value: Variant) -> void:
		result_calls += 1

	func facility(_id: String) -> bool:
		return true

	func pay(costs: Dictionary) -> bool:
		return inventory.exchange(costs, {}).get("ok", false)

	func give(rewards: Dictionary) -> Dictionary:
		var result := {}
		for id in rewards:
			var added: Dictionary = inventory.add(str(id), int(rewards[id]))
			if added.added > 0: result[str(id)] = added.added
		return result

	func receive_all(rewards: Dictionary) -> bool:
		return inventory.add_all(rewards)

class RejectingInventory extends Inventory:
	var reject := false
	func exchange(costs: Dictionary, gains: Dictionary) -> Dictionary:
		if not reject: return super.exchange(costs, gains)
		add("parts", 1)
		return {"ok":false, "reason":"注入目标提交失败"}

func test_storage() -> void:
	var storage = preload("res://src/warehouse/warehouse_service.gd").new()
	var carried := Inventory.new(4)
	var stored := Inventory.new(4)
	storage.inventory = carried
	storage.warehouse = stored
	storage.configure({"facility_unlocked":func(_id): return true})
	carried.set_count("wood", 5)
	stored.set_count("wood", 5)
	var events: Array = []
	var capacities: Array = []
	carried.capacity_changed.connect(func(_used, _capacity): capacities.append("source"))
	stored.capacity_changed.connect(func(_used, _capacity): capacities.append("target"))
	var resources: Array = []
	storage.resources_changed.connect(func(): resources.append(true))
	var commands := func():
		var old_carried: Dictionary = carried.to_dict()
		var old_stored: Dictionary = stored.to_dict()
		if carried.is_busy() or stored.is_busy():
			var transfer = preload("res://src/inventory/inventory_transfer.gd")
			check(transfer.move(carried, stored, "wood", 1).has("blocked") and transfer.move(stored, carried, "wood", 1).has("blocked"),
				"共享Transfer本身拒绝source或target busy，不依赖UI和storage")
		check(storage.deposit("wood", 1).has("blocked"), "库存busy拒绝storage.deposit，不能复制")
		check(storage.withdraw("wood", 1).has("blocked"), "库存busy拒绝storage.withdraw，不能吞物")
		check(storage.deposit_materials().has("blocked"), "库存busy拒绝批量入库")
		check(storage.withdraw_material("wood").has("blocked"), "库存busy拒绝材料取出")
		check(not storage.construction_pay({"wood":1}), "库存busy拒绝跨仓建设支付")
		storage.from_dict({"capacity":1,"counts":{}})
		check(carried.to_dict() == old_carried and stored.to_dict() == old_stored, "busy所有仓储命令都不修改两端")
	var on_exchange := func(_id, _delta): commands.call()
	for owner in [carried, stored]:
		owner.changed.connect(on_exchange)
		check(owner.exchange({"wood":1}, {}).ok, "两端任一exchange中验证仓储异命令重入")
		owner.changed.disconnect(on_exchange)
	check(resources.is_empty(), "拒绝命令不发resources_changed")
	var outer_events := func(id, delta):
		events.append([id, delta])
		check(carried.is_busy() and stored.is_busy(), "搬运发布事件时两端均busy")
		check(carried.count("wood") == 2 and stored.count("wood") == 6, "搬运首个事件已能读到两端完成态")
		commands.call()
		var old: Dictionary = carried.to_dict()
		carried.expand(1)
		carried.clear()
		carried.move_to_end("wood")
		carried.move_item("wood", "parts")
		check(carried.to_dict() == old, "搬运信号回调不能修改容量、排列或清空")
	carried.changed.connect(outer_events)
	stored.changed.connect(outer_events)
	capacities.clear()
	var moved: Dictionary = storage.deposit("wood", 2)
	check(moved.get("ok", false) and events == [["wood",-2],["wood",2]], "搬运仅发布一次实际扣增事件")
	check(resources.size() == 1 and not storage.is_busy(), "搬运业务事件一次且释放锁")
	check(capacities == ["source","target"], "成功搬运不吞容量通知且每端恰好一次")
	carried.changed.disconnect(outer_events)
	stored.changed.disconnect(outer_events)
	var resource_reentry := func(): commands.call()
	storage.resources_changed.connect(resource_reentry)
	check(storage.withdraw("wood", 1).get("ok", false), "resources_changed期间owner busy阻止异命令")
	storage.resources_changed.disconnect(resource_reentry)
	var rejecting := RejectingInventory.new(4)
	rejecting.set_count("wood", 1)
	rejecting.reject = true
	var before_source: Dictionary = carried.to_dict()
	var before_target: Dictionary = rejecting.to_dict()
	var failed_events: Array = []
	capacities.clear()
	rejecting.capacity_changed.connect(func(_used, _capacity): capacities.append("rejecting"))
	carried.changed.connect(func(id, delta): failed_events.append([id, delta]))
	rejecting.changed.connect(func(id, delta): failed_events.append([id, delta]))
	var failed: Dictionary = preload("res://src/inventory/inventory_transfer.gd").move(carried, rejecting, "wood", 1)
	check(failed.has("blocked") and carried.to_dict() == before_source and rejecting.to_dict() == before_target,
		"目标实际提交失败含部分写入时完整回滚两端")
	check(failed_events.is_empty() and capacities.is_empty(), "失败回滚零物品或容量事件，不发布退款第二次事件")
	check(not carried.is_blocking_signals() and not rejecting.is_blocking_signals(), "失败恢复原信号屏蔽状态")
	stored.set_block_signals(true)
	var stored_events: Array = []
	stored.changed.connect(func(id, delta): stored_events.append([id,delta]))
	check(storage.deposit("wood", 1).get("ok", false) and stored_events.is_empty() and stored.is_blocking_signals(), "尊重调用前已有信号屏蔽")
	stored.set_block_signals(false)
	var bulk = preload("res://src/warehouse/warehouse_service.gd").new()
	bulk.inventory = Inventory.new(4)
	bulk.warehouse = Inventory.new(1)
	bulk.configure({"facility_unlocked":func(_id): return true})
	bulk.inventory.set_count("wood", 4)
	bulk.inventory.set_count("parts", 3)
	var bulk_events: Array = []
	bulk.inventory.changed.connect(func(id, delta):
		bulk_events.append([id, delta])
		check(bulk.inventory.count("wood") == 0 and bulk.warehouse.count("wood") == 4 and bulk.inventory.count("parts") == 3,
			"批量入库按共享容量预检且事件只见完整态")
	)
	check(bulk.deposit_materials().get("moved", 0) == 4 and bulk_events == [["wood",-4]], "批量入库容量不足部分留原处")
	var pay = preload("res://src/warehouse/warehouse_service.gd").new()
	pay.inventory = Inventory.new(4)
	pay.warehouse = Inventory.new(4)
	pay.configure({"facility_unlocked":func(_id): return true})
	pay.inventory.set_count("wood", 2)
	pay.warehouse.set_count("wood", 3)
	pay.inventory.changed.connect(func(_id, _delta):
		check(pay.inventory.count("wood") == 0 and pay.warehouse.count("wood") == 1, "跨仓扣费首事件读到两端完成态")
		check(pay.withdraw("wood", 1).has("blocked"), "跨仓扣费信号不能重入搬运")
	)
	check(pay.construction_pay({"wood":4}), "跨仓扣费使用统一原子提交")

func test_order_reentry(orders) -> void:
	orders.reset()
	var offer: Dictionary = orders.offer_at(0)
	check(not offer.is_empty(), "订单重入测试有可交付订单")
	if offer.is_empty(): return
	inv.set_count(str(offer.item), int(offer.amount))
	var attempts: Array = []
	var attack := func():
		var before: Dictionary = orders.to_dict()
		var seed_before: int = orders.rng.state
		attempts.append(orders.reroll())
		orders.reset()
		orders.from_dict({"slots":[{}]})
		orders.tick(9999.0)
		orders.load_table()
		orders.set_seed(987)
		check(not attempts.back().ok and orders.to_dict() == before and orders.rng.state == seed_before,
			"订单owner busy拒绝reroll/reset/from_dict/tick/表重载与种子改写")
	var inventory_attack := func(_id, _delta): attack.call()
	var changed_attack := func(): attack.call()
	inv.changed.connect(inventory_attack)
	orders.changed.connect(changed_attack)
	var result: Dictionary = orders.fulfill(str(offer.uid))
	check(result.ok and orders.offer_at(0).has("refill") and attempts.size() >= 2, "fulfill异命令重入不覆盖新slots")
	inv.changed.disconnect(inventory_attack)
	var old_count: int = attempts.size()
	orders.from_dict({"slots":[{"refill":2.0},{},{}]})
	check(attempts.size() == old_count + 1 and orders.offer_at(0).get("refill") == 2.0, "from_dict内部重建不自锁且只发布一次完成态")
	check(orders.reroll().ok, "正常免费reroll不自锁")
	orders.reset()
	orders.from_dict({"slots":[{"refill":0.1},{},{}]})
	var offered_attack := func(_order): attack.call()
	orders.offered.connect(offered_attack)
	orders.tick(1.0)
	check(not orders.offer_at(0).is_empty() and not orders.is_busy(), "tick补位offered回调受同一owner锁保护")
	orders.offered.disconnect(offered_attack)
	orders.changed.disconnect(changed_attack)

func test_npc_capture() -> void:
	var service := NpcService.new()
	var host := Host.new()
	service.configure(host.clock)
	var seed: Dictionary = service.to_dict()
	seed.graph.met.npc_luo_yan = true
	seed.graph.affinity.npc_luo_yan = 200
	check(service.from_dict(seed).ok, "NPC剧情负例准备合法进度")
	var started: Dictionary = service.start_event("route_1")
	check(started.ok, "NPC快照负例启动真实剧情")
	for step in 3: service.advance_dialogue()
	check(service.choose_dialogue("new").ok and service.to_dict().seen_events.is_empty(), "真实剧情已选择但未到终页不结算")
	var before: Dictionary = service.capture_runtime()
	var durable: Dictionary = service.to_dict()
	var registry := Registry.new()
	registry.register("npc", service.to_dict, service.from_dict, {"type":"object"}, durable, service.validate_snapshot, [service])
	check(registry.capture().npc == durable and service.capture_runtime() == before, "registry.capture及NPC.to_dict纯读保留会话")
	var fail := [true]
	registry.register("reject", func(): return {}, func(_data):
		if fail[0]:
			fail[0] = false
			return {"ok":false,"reason":"后置owner拒绝"}
		return {"ok":true}, {"type":"object"}, {})
	var events: Array = []
	registry.restored.connect(func(): events.append(true))
	var snapshot: Dictionary = registry.capture()
	check(not registry.restore(snapshot).ok and service.to_dict() == durable and service.capture_runtime() == before,
		"NPC已apply后其他owner失败恢复持久态及runtime memento")
	check(events.is_empty(), "失败恢复不发restored或对白完成事件")
	check(service.advance_dialogue(int(started.state.session_id)).ok, "失败恢复后原session_id仍能继续未提交对白")
	var final_step := {}
	while service.dialogue_state().active: final_step = service.advance_dialogue(int(started.state.session_id))
	check(final_step.get("committed", false) and service.to_dict().seen_events.route_1.choices.choice == "new",
		"runtime回滚保留pending及已选分支，继续到终页仍能正确结算")
	check(service.start_event("route_1").get("ok", false), "成功restore前启动活动回看")
	check(registry.restore(snapshot).ok and not service.dialogue_state().active and events.size() == 1, "明确成功restore取消会话且只发布一次restored")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [b2-transactions] ", label)

func _init() -> void:
	call_deferred("run")

func _on_inventory_changed(_id: String, _delta: int) -> void:
	reentrant_exchange = inv.exchange({"wood": 1}, {})
	var registry := Registry.new()
	registry.busy_query = func(): return inv.is_busy()
	reentrant_restore = registry.restore({})

func make_farm(host: Host) -> Farm:
	var ports := FarmPorts.new()
	ports.inventory = inv
	ports.pay = host.pay
	ports.exchange = host.exchange
	ports.give = host.give
	ports.has_greenhouse = host.facility
	ports.access_reason = host.facility
	var farm := Farm.new()
	farm.configure(ports)
	root.add_child(farm)
	return farm

func run() -> void:
	test_storage()
	test_npc_capture()
	inv = Inventory.new(24)
	var host := Host.new()
	host.inventory = inv
	inv.set_count("wood", 2)
	inv.set_count("parts", 1)
	inv.set_count("coins", 20)
	inv.changed.connect(_on_inventory_changed)
	var before: Dictionary = inv.to_dict()
	var paid: Dictionary = inv.exchange({"wood": 2, "parts": 1}, {"coins": 4})
	check(paid.ok and inv.count("wood") == 0 and inv.count("parts") == 0 and inv.count("coins") == 24,
		"Inventory.exchange完整提交多项扣物和奖励")
	check(reentrant_exchange.get("ok", true) == false and reentrant_restore.get("ok", true) == false,
		"Inventory.changed回调期间拒绝同命令和restore")
	check(before != inv.to_dict(), "成功事务提交后才改变完整库存")
	inv.changed.disconnect(_on_inventory_changed)

	inv.clear()
	inv.set_count("wood", 2)
	inv.set_count("parts", 1)
	var pay_before: Dictionary = inv.to_dict()
	check(inv.pay({"wood": 2, "parts": 2}) == false and inv.to_dict() == pay_before,
		"Inventory.pay多项不足时整笔拒绝")

	var construction = preload("res://src/construction/construction_service.gd").new()
	construction.configure({"construction_pay":host.pay, "construction_has":func(costs): return inv.has_all(costs), "construction_missing_text":func(_costs): return "missing"})
	inv.clear()
	inv.set_count("coins", 20)
	inv.set_count("wood", 4)
	inv.set_count("parts", 2)
	var build_result: Dictionary = construction.begin_site_upgrade("home_cabin")
	check(build_result.ok and inv.count("coins") == 0 and inv.count("wood") == 0 and inv.count("parts") == 0,
		"Construction旧付费服务支付到状态提交保持busy")
	check(not construction.is_busy(), "Construction发布开工事件后释放busy")

	var farm := make_farm(host)
	await process_frame
	inv.clear()
	inv.set_count("coins", 4)
	var farm_result: Dictionary = farm.buy_seed("lettuce", 2)
	check(farm_result.has("blocked") and inv.count("coins") == 4 and inv.count("lettuce_seed") == 0,
		"Farm买种事务失败不半扣")
	inv.clear()
	inv.set_count("coins", 20)
	var farm_ok: Dictionary = farm.buy_seed("lettuce", 2)
	check(farm_ok.has("message") and inv.count("coins") == 12 and inv.count("lettuce_seed") == 2,
		"Farm买种通过exchange一次提交")
	check(not farm.is_busy(), "Farm业务提交和事件发布后释放busy")

	var orders := Orders.new()
	var order_ports := preload("res://src/orders/order_ports.gd").new()
	order_ports.inventory = inv
	order_ports.give = host.give
	order_ports.max_tier = func(): return 1
	orders.configure(order_ports)
	root.add_child(orders)
	await process_frame
	var offer: Dictionary = orders.offer_at(0)
	if not offer.is_empty():
		inv.set_count(str(offer.item), int(offer.amount))
		var old_coins: int = inv.count("coins")
		var order_result: Dictionary = orders.fulfill(str(offer.uid))
		check(order_result.ok and inv.count("coins") >= old_coins, "Orders交付使用原子exchange")
	check(not orders.is_busy(), "Orders发布fulfilled后释放busy")
	test_order_reentry(orders)

	var fishery := Fishery.new()
	fishery.configure({"count": host.count, "pay": host.pay, "missing_text": func(_cost): return ""})
	fishery.unlocked = true
	fishery.pending = 3
	fishery.ports.can_receive = func(_id, _amount): return true
	fishery.ports.receive = host.receive_all
	inv.changed.connect(func(_id, _delta): check(not fishery.harvest().get("event", "") == "fishery_harvested", "Fishery回调重入不重复收获"))
	var fish_result: Dictionary = fishery.harvest()
	check(fish_result.get("event", "") == "fishery_harvested" and fishery.pending == 0, "Fishery harvest完整提交后清pending")
	check(not fishery.is_busy(), "Fishery harvest发布changed后释放busy")

	npc = NpcService.new()
	var npc_config: Dictionary = npc.configure(host.clock, host.exchange, host.remove, host.count, host.result)
	check(npc_config.ok, "NPC端口配置成功")
	var npc_id := "npc_mu_he"
	if npc._state.graph.met.has(npc_id): npc._state.graph.met[npc_id] = true
	inv.clear()
	inv.set_count("lettuce_seed", 1)
	inv.changed.connect(func(_id, _delta):
		var nested: Dictionary = npc.give_gift(npc_id, "lettuce_seed")
		check(not nested.ok, "NPC礼物在库存changed回调中拒绝重入")
	)
	var gift: Dictionary = npc.give_gift(npc_id, "lettuce_seed")
	check(gift.ok and inv.count("lettuce_seed") == 0 and not npc.is_busy(), "NPC礼物支付到关系提交保持busy")
	var request: Dictionary = npc.fulfill_request("missing_request")
	check(not request.ok, "NPC未知请求拒绝")

	var registry := Registry.new()
	var owner := {"value": 1, "apply_calls": 0, "fail": false}
	restored_count = 0
	registry.restored.connect(_on_restored)
	registry.register("owner", func(): return {"value": owner.value}, func(data):
		owner.apply_calls += 1
		if owner.fail: return {"ok": false, "reason": "测试apply失败"}
		owner.value = int(data.value)
		return {"ok": true}
	, {"fields":{"value":{"type":"integer"}},"required":["value"]}, {"value":1})
	owner.fail = true
	var failed: Dictionary = registry.restore({"owner":{"value":9}})
	check(not failed.ok and owner.value == 1 and restored_count == 0, "registry.apply失败回滚owner且不发restored")
	owner.fail = false
	var succeeded: Dictionary = registry.restore({"owner":{"value":9}})
	check(succeeded.ok and owner.value == 9 and restored_count == 1, "registry兼容void/bool/dict成功apply")

	print("[b2-transactions] %d checks, %d failures" % [checks, failures])
	farm.queue_free()
	orders.queue_free()
	quit(1 if failures else 0)
