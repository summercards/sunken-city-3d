extends Node
## 经济状态机。
##
## 资源账本已经搬进 `Inventory`（唯一真源），这里只负责「规则」：
## 建造点等级、设施解锁、打捞冷却、船只等级，以及把成本/产出翻译成背包操作。
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

const ItemDBLib = preload("res://scripts/core/item_db.gd")
const InventoryLib = preload("res://scripts/core/inventory.gd")
const FarmLib = preload("res://scripts/core/farm.gd")

## 采集类资源的展示信息（物品表里的子集）。保留是为了不破坏旧调用。
var COLLECTIONS := {}

# 建造点：等级越高费用越高；第 3 级解锁对应设施的前置。
const SITES := {
	"home_cabin": {"name": "太阳能木屋", "zone": "zone1", "max_level": 3, "costs": [
		{"coins": 20, "wood": 4, "parts": 2},
		{"coins": 45, "wood": 9, "parts": 5},
	], "seconds": [18.0, 30.0]},
	"rooftop_planter": {"name": "圆弧屋顶农场", "zone": "zone3", "max_level": 3, "costs": [
		{"coins": 25, "wood": 5, "parts": 3},
		{"coins": 55, "wood": 11, "parts": 6},
	], "seconds": [20.0, 34.0]},
	"yokohama_station": {"name": "横滨沉没铁道", "zone": "zone2", "max_level": 2, "costs": [
		{"coins": 30, "wood": 6, "parts": 4},
	], "seconds": [22.0]},
}

const FACILITIES := {
	"greenhouse": {
		"name": "屋顶温室",
		"description": "菜箱生长缩短 28%，每次浇水更耐旱，每茬多收 1 份。",
		"cost": {"coins": 15, "wood": 5, "parts": 3, "glass": 2},
		"requires": {"home_cabin": 2, "rooftop_planter": 1},
	},
	"recycler": {
		"name": "太阳能回收台",
		"description": "每 30 秒分拣 2 个旧零件，需主动收取。",
		"cost": {"coins": 15, "wood": 4, "parts": 4},
		"requires": {"home_cabin": 2, "yokohama_station": 1},
	},
}

const SHIP_RECIPE := {"coins": 25, "wood": 6, "parts": 4, "rope": 2}

var inventory: RefCounted
## 种植规则与状态（Node 子节点，天然跟场景树同生共死）。
## 故意不加静态类型：FarmModel 的方法（plant/tick/to_dict）在 Node 基类上不存在，
## 标成 Node 会让编译器拒绝调用。
var farm = null
var ship_level: int = 1

var site_levels := {"home_cabin": 1, "rooftop_planter": 1, "yokohama_station": 1}
## 正在施工的建造点：id → {"left": 剩余秒, "total": 总秒}。
## 计时放在规则层而不是节点里：关掉界面/走开/切区块都照样推进，也方便 headless 断言。
var site_work := {}
## 测试可以把自动推进关掉，自己按固定步长调 tick_sites()。
var ticking := true
var facilities := {"greenhouse": false, "recycler": false}

const SALVAGE_COOLDOWN := 16.0
var salvage_ready_at: float = 0.0


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
	if ticking:
		tick_sites(delta)
		if farm != null:
			farm.tick(delta)


func _ready() -> void:
	inventory = InventoryLib.new()
	inventory.changed.connect(_on_inventory_changed)
	inventory.capacity_changed.connect(func(_u: int, _c: int) -> void: resources_changed.emit())
	_build_collections()
	inventory.set_count("coins", 80)
	farm = FarmLib.new()
	farm.name = "Farm"
	add_child(farm)


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
	return now >= salvage_ready_at


func salvage_cooldown_left(now: float) -> float:
	return maxf(salvage_ready_at - now, 0.0)


## 绞盘小游戏结算：产出由 `SalvageModel.haul()` 决定，这里只负责进冷却 + 入包。
func commit_salvage(now: float, haul: Dictionary) -> Dictionary:
	if haul.is_empty():
		return {}
	salvage_ready_at = now + SALVAGE_COOLDOWN
	salvage_ready.emit()
	return give(haul)


## 旧接口（一次性产出 3 木 2 零件），保留给自检与老调用；新流程走 commit_salvage。
func do_salvage(now: float) -> Dictionary:
	if not can_salvage(now):
		return {}
	salvage_ready_at = now + SALVAGE_COOLDOWN
	var gain := give({"wood": 3, "parts": 2})
	return gain


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
	return int(site_levels.get(id, 1))


func site_next_cost(id: String) -> Dictionary:
	var spec: Dictionary = SITES.get(id, {})
	var level := site_level(id)
	var costs: Array = spec.get("costs", [])
	if level - 1 >= costs.size():
		return {}
	return costs[level - 1]


func site_maxed(id: String) -> bool:
	var spec: Dictionary = SITES.get(id, {})
	return site_level(id) >= int(spec.get("max_level", 1))


## 施工时长：跟着「下一级」取，没配就按 20 秒。
func site_build_seconds(id: String) -> float:
	var spec: Dictionary = SITES.get(id, {})
	var table: Array = spec.get("seconds", [])
	var idx := site_level(id) - 1
	if idx >= 0 and idx < table.size():
		return float(table[idx])
	return 20.0


func is_building(id: String) -> bool:
	return site_work.has(id)


func site_work_left(id: String) -> float:
	if not site_work.has(id):
		return 0.0
	return float(site_work[id].left)


func site_work_progress(id: String) -> float:
	if not site_work.has(id):
		return 0.0
	var w: Dictionary = site_work[id]
	return clampf(1.0 - float(w.left) / maxf(float(w.total), 0.001), 0.0, 1.0)


## 第一阶段：交付材料并开工。等级此时**不变**，要等施工结束。
func begin_site_upgrade(id: String) -> Dictionary:
	if not SITES.has(id):
		return {"ok": false, "reason": "未知建造点"}
	if is_building(id):
		return {"ok": false, "reason": "正在施工中"}
	if site_maxed(id):
		return {"ok": false, "reason": "已经是最高等级"}
	var cost := site_next_cost(id)
	if cost.is_empty():
		return {"ok": false, "reason": "没有更多等级"}
	if not pay(cost):
		return {"ok": false, "reason": missing_text(cost)}
	var seconds := site_build_seconds(id)
	site_work[id] = {"left": seconds, "total": seconds}
	site_work_started.emit(id, seconds)
	sites_changed.emit()
	return {"ok": true, "seconds": seconds, "cost": cost, "name": SITES[id].name}


## 第二阶段：倒计时走完才算建成。返回已完成的 id 列表，方便测试与批量刷新。
func tick_sites(delta: float) -> Array:
	var done: Array = []
	for id in site_work.keys():
		var w: Dictionary = site_work[id]
		w.left = float(w.left) - delta
		if w.left > 0.0:
			continue
		site_work.erase(id)
		site_levels[id] = site_level(id) + 1
		done.append(id)
		site_work_finished.emit(id, site_level(id))
	if not done.is_empty():
		sites_changed.emit()
	return done


func facility_unlocked(id: String) -> bool:
	return bool(facilities.get(id, false))


func facility_requirement_text(id: String) -> String:
	var spec: Dictionary = FACILITIES.get(id, {})
	for req in spec.get("requires", {}).keys():
		var need := int(spec.requires[req])
		if site_level(req) < need:
			var name := str(SITES.get(req, {}).get("name", req))
			return "需要先把 %s 升到 %d 级" % [name, need]
	return ""


func can_build_facility(id: String) -> bool:
	var spec: Dictionary = FACILITIES.get(id, {})
	if spec.is_empty() or facility_unlocked(id):
		return false
	if facility_requirement_text(id) != "":
		return false
	return has(spec.cost)


func build_facility(id: String) -> Dictionary:
	var spec: Dictionary = FACILITIES.get(id, {})
	if spec.is_empty():
		return {"ok": false, "reason": "未知设施"}
	if facility_unlocked(id):
		return {"ok": false, "reason": "已经建好"}
	var req_text := facility_requirement_text(id)
	if req_text != "":
		return {"ok": false, "reason": req_text}
	if not pay(spec.cost):
		return {"ok": false, "reason": missing_text(spec.cost)}
	facilities[id] = true
	sites_changed.emit()
	return {"ok": true, "name": spec.name}


func can_upgrade_ship() -> bool:
	return ship_level < 3 and has(SHIP_RECIPE)


func upgrade_ship() -> Dictionary:
	if ship_level >= 3:
		return {"ok": false, "reason": "船已经满级"}
	if not pay(SHIP_RECIPE):
		return {"ok": false, "reason": missing_text(SHIP_RECIPE)}
	ship_level += 1
	GameState.far_sea_unlocked = true
	resources_changed.emit()
	return {"ok": true, "level": ship_level}


## ---- 存档 -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"inventory": inventory.to_dict(),
		"ship_level": ship_level,
		"site_levels": site_levels.duplicate(),
		"facilities": facilities.duplicate(),
		"salvage_ready_at": salvage_ready_at,
		"site_work": site_work.duplicate(true),
		"farm": farm.to_dict() if farm != null else {},
	}


func from_dict(data: Dictionary) -> void:
	inventory.from_dict(data.get("inventory", {}))
	ship_level = int(data.get("ship_level", 1))
	site_levels = {"home_cabin": 1, "rooftop_planter": 1, "yokohama_station": 1}
	for id in data.get("site_levels", {}).keys():
		site_levels[str(id)] = int(data.site_levels[id])
	facilities = {"greenhouse": false, "recycler": false}
	for id in data.get("facilities", {}).keys():
		facilities[str(id)] = bool(data.facilities[id])
	salvage_ready_at = float(data.get("salvage_ready_at", 0.0))
	site_work = {}
	for id in data.get("site_work", {}).keys():
		var w: Dictionary = data.site_work[id]
		site_work[str(id)] = {
			"left": float(w.get("left", 0.0)),
			"total": float(w.get("total", 1.0)),
		}
	if farm != null:
		farm.from_dict(data.get("farm", {}))
	resources_changed.emit()
	sites_changed.emit()
