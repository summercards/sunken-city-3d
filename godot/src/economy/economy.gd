extends Node
## 经营服务兼容适配器：只装配接口、转发事件与旧接口；规则分别由功能服务拥有。
##
## 资源数量由 Inventory 拥有；本门面只转发建造、设施、打捞、船级等服务，
## 并在装配时把支付、奖励与进度查询接到公开端口。
##
## 兼容层：`Economy.wood` 这类属性仍然可以读，也可以赋值，内部走 Inventory，
## 于是旧代码与旧测试不用一次性改完。新代码应该直接用 `Inventory.count(id)`。

signal resources_changed
signal sites_changed
## 施工开始 / 进度推进 / 完成。世界里的建造牌与 HUD 都靠这三个信号，不轮询。
signal site_work_started(id: String, seconds: float)
signal site_work_finished(id: String, level: int)
signal salvage_ready
## 背包满导致产出被丢弃时发出，上层用来提示。
signal overflow(id: String, amount: int)
## 任何物品增减，UI 用它做增量动画。
signal item_gained(id: String, amount: int)

const Scope = preload("res://src/core/play_scope.gd")
var daily = preload("res://src/orders/daily_shipping.gd").new()
const ItemDBLib = preload("res://src/inventory/item_db.gd")
const InventoryLib = preload("res://src/inventory/inventory.gd")
const FarmLib = preload("res://src/farming/farm.gd")
const OrderBoardLib = preload("res://src/orders/orders.gd")

## 采集类资源的展示信息（物品表里的子集）。保留是为了不破坏旧调用。
var COLLECTIONS := {}

# 建造点：等级越高费用越高；第 3 级解锁对应设施的前置。
const SITES = preload("res://src/construction/construction_service.gd").SITES

const FACILITIES = preload("res://src/facilities/facility_service.gd").FACILITIES

const SHIP_RECIPE = preload("res://src/ship/ship_service.gd").SHIP_RECIPE

var construction = preload("res://src/construction/construction_service.gd").new()
var facility = preload("res://src/facilities/facility_service.gd").new()
var ship = preload("res://src/ship/ship_service.gd").new()
var goals = preload("res://src/goals/goal_service.gd").new()
var storage = preload("res://src/warehouse/warehouse_service.gd").new()
var salvage = preload("res://src/salvage/salvage_rewards.gd").new()
var warehouse: RefCounted:
	get: return storage.warehouse
var tracked_goal: String:
	get: return goals.tracked_goal
	set(value): goals.tracked_goal = value
var inventory: RefCounted
## 种植规则与状态（Node 子节点，天然跟场景树同生共死）。
## 故意不加静态类型：FarmModel 的方法（plant/tick/to_dict）在 Node 基类上不存在，
## 标成 Node 会让编译器拒绝调用。
var farm = null
## 码头订单板（规则层）：三张待交的单子、换单、档位解锁。同样不加静态类型。
var orders = null
var ship_level: int:
	get: return ship.ship_level
	set(value): ship.ship_level = value

var site_levels: Dictionary:
	get: return construction.site_levels
	set(value): construction.site_levels = value
## 正在施工的建造点：id → {"left": 剩余秒, "total": 总秒}。
## 计时放在规则层而不是节点里：关掉界面/走开/切区块都照样推进，也方便 headless 断言。
var site_work: Dictionary:
	get: return construction.site_work
	set(value): construction.site_work = value
## 测试可以把自动推进关掉，自己按固定步长调 tick_sites()。
var ticking := true
var facilities: Dictionary:
	get: return facility.facilities
	set(value): facility.facilities = value

const SALVAGE_COOLDOWN := 16.0
var salvage_ready_at: float:
	get: return salvage.salvage_ready_at
	set(value): salvage.salvage_ready_at = value


## ---- 资源读写兼容层 ---------------------------------------------------------
## 这些属性内部走 Inventory：读返回数量，赋值等于 set_count。
## 新代码请直接用 inventory.count("wood")，别在这里加新的变量。

var coins: int:
	get: return _inv().count("coins")
	set(value): _inv().set_count("coins", value)
var wood: int:
	get: return _inv().count("wood")
	set(value): _inv().set_count("wood", value)
var parts: int:
	get: return _inv().count("parts")
	set(value): _inv().set_count("parts", value)
var fish: int:
	get: return _inv().count("fish")
	set(value): _inv().set_count("fish", value)
var shell: int:
	get: return _inv().count("shell")
	set(value): _inv().set_count("shell", value)
var pearl: int:
	get: return _inv().count("pearl")
	set(value): _inv().set_count("pearl", value)
var rope: int:
	get: return _inv().count("rope")
	set(value): _inv().set_count("rope", value)
var glass: int:
	get: return _inv().count("glass")
	set(value): _inv().set_count("glass", value)
var seed: int:
	get: return _inv().count("seed")
	set(value): _inv().set_count("seed", value)


func _process(delta: float) -> void:
	if ticking and not Scope.minimal():
		tick_sites(delta)
		if farm != null:
			farm.tick(delta)
		if orders != null:
			orders.tick(delta)


func _ready() -> void:
	inventory = InventoryLib.new()
	_configure_services()
	inventory.changed.connect(_on_inventory_changed)
	inventory.capacity_changed.connect(func(_u: int, _c: int) -> void: resources_changed.emit())
	_build_collections()
	inventory.set_count("coins", 80)
	inventory.set_count("lettuce_seed", 3)
	farm = FarmLib.new()
	var farm_ports = preload("res://src/farming/farming_ports.gd").new()
	farm_ports.inventory = inventory
	farm_ports.pay = pay
	farm_ports.give = give
	farm_ports.has_greenhouse = func() -> bool: return not Scope.minimal() and facility_unlocked("greenhouse")
	farm_ports.access_reason = _farm_access_reason
	farm.configure(farm_ports)
	daily.inventory = inventory
	daily.grow = func() -> Dictionary: return farm.advance_day(true)
	daily.sync_day = farm.sync_calendar_day
	daily.changed.connect(func(): resources_changed.emit())
	farm.name = "Farm"
	add_child(farm)
	orders = OrderBoardLib.new()
	var order_ports = preload("res://src/orders/order_ports.gd").new()
	order_ports.inventory = inventory
	order_ports.give = give
	order_ports.max_tier = _order_tier
	orders.configure(order_ports)
	orders.name = "Orders"
	add_child(orders)


## 采集类资源的展示信息从物品表生成：货币与成品不在采集表里。
func _build_collections() -> void:
	COLLECTIONS = {}
	for id in ["wood", "parts", "fish", "shell", "rope", "glass", "seed"]:
		var it := ItemDBLib.get_item(id)
		if it.is_empty():
			continue
		COLLECTIONS[id] = {
			"icon": str(it.get("icon", "•")),
			"label": str(it.get("label", id)),
			"desc": str(it.get("desc", "")),
		}


func _inv() -> RefCounted:
	if inventory == null:
		inventory = InventoryLib.new()
		inventory.changed.connect(_on_inventory_changed)
	return inventory


func _on_inventory_changed(id: String, delta: int) -> void:
	if id != "" and delta != 0:
		item_gained.emit(id, delta)
	resources_changed.emit()


## ---- 打捞 -------------------------------------------------------------------

func can_salvage(now: float) -> bool:
	return salvage.can_salvage(now)


func salvage_cooldown_left(now: float) -> float:
	return salvage.salvage_cooldown_left(now)


## 绞盘小游戏结算：产出由 `SalvageModel.haul()` 决定，这里只负责进冷却 + 入包。
func commit_salvage(now: float, haul: Dictionary) -> Dictionary:
	return salvage.commit_salvage(now, haul)


## 旧接口（一次性产出 3 木 2 零件），保留给自检与老调用；新流程走 commit_salvage。
func do_salvage(now: float) -> Dictionary:
	return salvage.do_salvage(now)


## ---- 物品进出 ---------------------------------------------------------------

## 加物品；装不下的部分记进 overflow 并发出信号，不会静默消失。
func give(rewards: Dictionary) -> Dictionary:
	var added := {}
	for id in rewards.keys():
		var amount := int(rewards[id])
		if amount <= 0:
			continue
		var r: Dictionary = _inv().add(str(id), amount)
		if int(r.added) > 0:
			added[str(id)] = int(r.added)
		if int(r.overflow) > 0:
			overflow.emit(str(id), int(r.overflow))
	resources_changed.emit()
	return added


## 兼容旧接口。
func add_resource(key: String, amount: int) -> void:
	give({key: amount})


func count(id: String) -> int:
	return _inv().count(id)


func has(cost: Dictionary) -> bool:
	return _inv().has_all(cost)


func missing(cost: Dictionary) -> Dictionary:
	return _inv().missing(cost)


func pay(cost: Dictionary) -> bool:
	if not _inv().pay(cost):
		return false
	resources_changed.emit()
	return true


## 缺口的可读文案：「还差 木料×2  零件×1」。
func missing_text(cost: Dictionary) -> String:
	var lack := missing(cost)
	if lack.is_empty():
		return ""
	var bits: Array = []
	for id in lack.keys():
		bits.append("%s×%d" % [ItemDBLib.label(id), int(lack[id])])
	return "还差 " + "  ".join(bits)


func cost_text(cost: Dictionary) -> String:
	var bits: Array = []
	for id in cost.keys():
		if int(cost[id]) > 0:
			bits.append("%s%d" % [ItemDBLib.icon(id), int(cost[id])])
	return " ".join(bits)


## ---- 建造点与设施 -----------------------------------------------------------

func site_level(id: String) -> int:
	return construction.site_level(id)


func site_next_cost(id: String) -> Dictionary:
	return construction.site_next_cost(id)


func site_maxed(id: String) -> bool:
	return construction.site_maxed(id)


## 施工时长：跟着「下一级」取，没配就按 20 秒。
func site_build_seconds(id: String) -> float:
	return construction.site_build_seconds(id)


func is_building(id: String) -> bool:
	return construction.is_building(id)


func site_work_left(id: String) -> float:
	return construction.site_work_left(id)


func site_work_progress(id: String) -> float:
	return construction.site_work_progress(id)


## 第一阶段：交付材料并开工。等级此时**不变**，要等施工结束。
func begin_site_upgrade(id: String) -> Dictionary:
	return construction.begin_site_upgrade(id)


## 第二阶段：倒计时走完才算建成。返回已完成的 id 列表，方便测试与批量刷新。
func tick_sites(delta: float) -> Array:
	return construction.tick_sites(delta)


func facility_unlocked(id: String) -> bool:
	return facility.facility_unlocked(id)


func facility_requirement_text(id: String) -> String:
	return facility.facility_requirement_text(id)


func can_build_facility(id: String) -> bool:
	return facility.can_build_facility(id)


func build_facility(id: String) -> Dictionary:
	return facility.build_facility(id)


func can_upgrade_ship() -> bool:
	return ship.can_upgrade_ship()


func upgrade_ship() -> Dictionary:
	return ship.upgrade_ship()


## ---- 存档 -------------------------------------------------------------------

func to_dict() -> Dictionary:
	var data := {"inventory":inventory.to_dict(),"warehouse":storage.to_dict(),"farm":farm.to_dict(),"orders":orders.to_dict(),"daily_loop":daily.to_dict()}
	for owner in [construction,facility,ship,goals]: data.merge(owner.to_dict())
	return data

func snapshot_event_sources() -> Array:
	return [self,inventory,daily,daily.cargo,storage,storage.warehouse,construction,facility,ship,goals,farm,orders]

func publish_restored() -> void:
	# State is already complete across every feature; these are refreshes, not rewards.
	construction.sites_changed.emit()
	facility.sites_changed.emit()
	farm.plots_changed.emit()
	orders.changed.emit()
	inventory.changed.emit("",0)
	storage.warehouse.changed.emit("",0)
	resources_changed.emit()
	sites_changed.emit()

func from_dict(data: Dictionary) -> void:
	inventory.from_dict(data.get("inventory",{}))
	storage.from_dict(data.get("warehouse",{"capacity":48}))
	for owner in [construction,facility,ship,goals]: owner.from_dict(data)
	farm.from_dict(data.get("farm",{}))
	orders.from_dict(data.get("orders",{}))
	daily.from_dict(data.get("daily_loop",{}))
	resources_changed.emit()
	sites_changed.emit()


## 材料留在仓库，不参与出售或订单；建设先用背包，再用仓库。
func construction_count(id: String) -> int:
	return storage.construction_count(id)

func construction_has(cost: Dictionary) -> bool:
	return storage.construction_has(cost)

func construction_pay(cost: Dictionary) -> bool:
	return storage.construction_pay(cost)

func construction_missing_text(cost: Dictionary) -> String:
	return storage.construction_missing_text(cost)

func construction_progress(cost: Dictionary) -> String:
	return storage.construction_progress(cost)

func deposit_materials() -> Dictionary:
	return storage.deposit_materials()

func withdraw_material(id: String) -> Dictionary:
	return storage.withdraw_material(id)

func ship_cost() -> Dictionary:
	return ship.ship_cost()

func goal_complete(id: String) -> bool:
	return goals.goal_complete(id)

func goal_info() -> Dictionary:
	return goals.goal_info()

func track_goal(id: String) -> void:
	goals.track_goal(id)


## Progression adapters: feature rules query these ports, never global state fields.
func _farm_access_reason(row: Dictionary) -> String:
	if Scope.minimal():
		return "" if Scope.zone_enabled(str(row.get("zone",""))) else "当前只开放家园与浅水平台"
	if str(row.get("zone", "")) == "zone5" and ship_level < 2:
		return "小船升到 2 级后开放平台种植床"
	var need := str(row.get("requires_site", ""))
	if need != "" and site_level(need) < int(row.get("requires_level", 0)):
		return "先将圆弧屋顶农场升到 2 级" if need == "rooftop_planter" else "种植床尚未解锁"
	return ""

func _order_tier() -> int:
	var best_site := 1
	for id in site_levels:
		best_site = maxi(best_site, int(site_levels[id]))
	var tier := 1
	if ship_level >= 2 or best_site >= 2: tier += 1
	if ship_level >= 2 and best_site >= 3: tier += 1
	return mini(tier, 3)


func _configure_services() -> void:
	storage.inventory = inventory
	storage.configure({"facility_unlocked": func(id: String) -> bool: return Scope.minimal() or facility.facility_unlocked(id)})
	var payments := {"construction_pay": storage.construction_pay, "construction_has": storage.construction_has, "construction_missing_text": storage.construction_missing_text}
	construction.configure(payments)
	var facilities_ports := payments.duplicate()
	facilities_ports.site_level = construction.site_level
	facility.configure(facilities_ports)
	facility.site_names = SITES.duplicate(true)
	ship.configure(payments)
	goals.configure({"facility_unlocked":facility.facility_unlocked, "site_level":construction.site_level, "ship_cost":ship.ship_cost, "site_next_cost":construction.site_next_cost, "ship_level":func() -> int: return ship.ship_level})
	goals.SITES = SITES.duplicate(true)
	goals.FACILITIES = FACILITIES.duplicate(true)
	salvage.configure({"give":give})
	construction.sites_changed.connect(func(): sites_changed.emit())
	facility.sites_changed.connect(func(): sites_changed.emit())
	construction.site_work_started.connect(func(id, seconds): site_work_started.emit(id, seconds))
	construction.site_work_finished.connect(func(id, level): site_work_finished.emit(id, level))
	for service in [storage, ship, goals]:
		service.resources_changed.connect(func(): resources_changed.emit())
	salvage.salvage_ready.connect(func(): salvage_ready.emit())

func _exit_tree() -> void:
	daily.grow = Callable()
	daily.sync_day = Callable()
	for service in [storage,construction,facility,ship,goals,salvage]:
		service.ports.clear()
