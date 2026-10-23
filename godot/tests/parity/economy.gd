class_name EconomyModel
extends RefCounted

## 材料与经营状态机 —— 与 sea/economy.js 一一对应。
##
## 这是纯状态机：不碰场景、不碰 UI。名字里的 camelCase 状态键沿用 JS 原版，
## 便于和原工程逐字段对照（"coins" / "wood" / "workerMode" / "currentZone" …）。

const SAFE_INT := 9007199254740991.0

const MATERIALS := {
	"coins": {"name": "海贝", "capacity": INF, "source": "浅滩贝床采集，也用2份食物交换12枚海贝。"},
	"wood": {"name": "木料", "capacity": 60, "source": "划到海面的漂流木箱/木块旁拾取，绞盘打捞也会补给。"},
	"parts": {"name": "旧零件", "capacity": 60, "source": "划到海面的漂流零件桶旁拾取，回收台也会分拣。"},
	"seeds": {"name": "种子", "capacity": 20, "source": "圆弧农场的种子箱，菜箱收获时返还种子。"},
	"food": {"name": "食物", "capacity": 40, "source": "播种菜箱并按时浇水，成熟后主动收获。"},
	"fish": {"name": "鱼", "capacity": 40, "source": "靠近鱼群采集，浅水养殖台投苗。"},
	"pearl": {"name": "珍珠", "capacity": 12, "source": "升级船只解锁远海后，拾取远海贝匣。"},
}

## 采集点是冷却式的：点一次拿一笔，然后等物资重新长回来。
const COLLECTIONS := [
	{"id": "home_crate", "name": "屋顶物资箱", "zone": "zone1", "icon": "🪵", "reward": {"wood": 3, "parts": 1}, "cooldown": 34.0},
	{"id": "shell_bed", "name": "浅滩贝床", "zone": "zone1", "icon": "🐚", "reward": {"coins": 5}, "cooldown": 26.0},
	{"id": "garden_cache", "name": "农场种子箱", "zone": "zone3", "icon": "🌱", "reward": {"wood": 4, "seeds": 2}, "cooldown": 42.0},
	{"id": "workshop_cache", "name": "铁道回收堆", "zone": "zone2", "icon": "⚙", "reward": {"parts": 3, "wood": 1}, "cooldown": 42.0},
	{"id": "sea_cache", "name": "远海贝匣", "zone": "zone4", "icon": "🫧", "reward": {"pearl": 1, "parts": 2}, "cooldown": 60.0},
]

## 探索：木料与旧零件靠走/划出来，每走一段掷一次骰子。
const EXPLORE := {"step": 7.0, "chance": 0.6, "wood": [1, 2], "parts": [0, 1]}

const HARVEST_THRESHOLD := 10

const FACILITIES := {
	"greenhouse": {
		"name": "屋顶温室",
		"cost": {"coins": 15, "wood": 5, "parts": 3},
		"requires": {"home_cabin": 2, "rooftop_planter": 1},
		"description": "蔬菜成熟缩短为26秒，每次收获3份食物。",
	},
	"recycler": {
		"name": "太阳能回收台",
		"cost": {"coins": 15, "wood": 4, "parts": 4},
		"requires": {"home_cabin": 2, "yokohama_station": 1},
		"description": "每30秒分拣2个旧零件，可暂存6个，需主动收取。",
	},
}

const SHIP_RECIPE := {
	"cost": {"coins": 25, "wood": 6, "parts": 4, "food": 2},
	"requires": {"home_cabin": 2, "rooftop_planter": 1},
}

## 土壤会慢慢变干，干透就停止生长，得再浇一次水。完整浇一次维持 18 秒。
const CROP := {"drainPerSecond": 1.0 / 18.0, "dryDuration": 34.0, "greenhouseDuration": 26.0}

const ZONE_NAMES := {
	"zone1": "sea",
	"zone2": "横滨铁道",
	"zone3": "圆弧农场",
	"zone4": "远海街町",
}

const SITE_NAMES := {
	"home_cabin": "sea · 太阳能木屋花圃",
	"rooftop_planter": "圆弧屋顶农场",
	"yokohama_station": "横滨沉没铁道 · 站台与电车园圃",
}

var state: Dictionary
var materials: Dictionary = MATERIALS
var nodes: Array = []
var plots: Array = []
var facilities: Dictionary = {}
var harvest_threshold: int = HARVEST_THRESHOLD
var job: Variant = null

var _get_site_level: Callable
var _random: Callable
var _explored_distance := 0.0


func _init(p_state: Dictionary, get_site_level: Callable, random_fn: Callable = Callable()) -> void:
	state = p_state
	_get_site_level = get_site_level
	if random_fn.is_valid():
		_random = random_fn
	else:
		_random = func() -> float: return randf()

	for node in COLLECTIONS:
		var copy: Dictionary = node.duplicate(true)
		copy.left = 0.0
		copy.collections = 0
		nodes.append(copy)

	plots = [
		{"id": "home_plot", "name": "木屋菜箱", "zone": "zone1", "siteId": "home_cabin", "minLevel": 2, "phase": "empty", "remaining": 0.0, "duration": CROP.dryDuration, "reward": null, "moisture": 0.0},
		{"id": "farm_plot", "name": "农场菜箱", "zone": "zone3", "siteId": "rooftop_planter", "minLevel": 1, "phase": "empty", "remaining": 0.0, "duration": CROP.dryDuration, "reward": null, "moisture": 0.0},
	]

	facilities = {
		"greenhouse": {"level": 0, "stored": {}},
		"recycler": {"level": 0, "stored": {}, "timer": 0.0},
	}


func is_busy() -> bool:
	return state.get("workerMode", "") != "IDLE_ASHORE" \
		or state.get("activeJobSite", null) != null \
		or job != null


func busy() -> bool:
	return is_busy()


func _balance(key: String) -> Variant:
	return state.get(key, 0)


func _random_value() -> float:
	var v: Variant = _random.call()
	return float(v)


func _is_safe_int(v: Variant) -> bool:
	if typeof(v) != TYPE_INT:
		return false
	return absi(int(v)) <= int(SAFE_INT)


## 校验材料清单：只允许已知材料、非负安全整数。非法返回 null。
func _bundle_entries(bundle: Variant) -> Variant:
	if typeof(bundle) != TYPE_DICTIONARY:
		return null
	var entries: Array = []
	for key in bundle.keys():
		if typeof(key) != TYPE_STRING or not MATERIALS.has(key):
			return null
		var amount: Variant = bundle[key]
		if not _is_safe_int(amount) or int(amount) < 0:
			return null
		entries.append([key, int(amount)])
	return entries


func _plan_transaction(cost: Variant, reward: Variant) -> Variant:
	var costs: Variant = _bundle_entries(cost)
	var rewards: Variant = _bundle_entries(reward)
	if costs == null or rewards == null:
		return null
	var debit: Dictionary = {}
	var credit: Dictionary = {}
	for e in costs:
		debit[e[0]] = e[1]
	for e in rewards:
		credit[e[0]] = e[1]

	var keys: Array = []
	for k in debit.keys():
		if not keys.has(k):
			keys.append(k)
	for k in credit.keys():
		if not keys.has(k):
			keys.append(k)

	var changes: Array = []
	for key in keys:
		var current: Variant = _balance(key)
		if typeof(current) != TYPE_INT:
			return null
		if absi(int(current)) > int(SAFE_INT) or int(current) < 0:
			return null
		var amount: int = int(debit.get(key, 0))
		if int(current) < amount:
			return null
		var next: int = int(current) - amount + int(credit.get(key, 0))
		if absi(next) > int(SAFE_INT):
			return null
		if credit.has(key) and float(next) > float(MATERIALS[key].capacity):
			return null
		changes.append([key, next])
	return changes


func _transact(cost: Variant, reward: Variant) -> bool:
	var changes: Variant = _plan_transaction(cost, reward)
	if changes == null:
		return false
	for change in changes:
		state[change[0]] = change[1]
	return true


func missing(cost: Variant) -> Dictionary:
	var entries: Variant = _bundle_entries(cost)
	assert(entries != null, "材料清单必须只含已知材料和非负安全整数。")
	if entries == null:
		return {}
	var result: Dictionary = {}
	for e in entries:
		var key: String = e[0]
		var amount: int = e[1]
		var current: Variant = _balance(key)
		assert(typeof(current) == TYPE_INT, "材料余额必须是非负安全整数。")
		if int(current) < 0:
			return {}
		if amount > int(current):
			result[key] = amount - int(current)
	return result


func can_receive(reward: Variant) -> bool:
	return _plan_transaction({}, reward) != null


func spend(cost: Variant) -> bool:
	return _transact(cost, {})


func receive(reward: Variant) -> bool:
	return _transact({}, reward)


func access_reason(zone: String) -> String:
	if state.get("currentZone", "") != zone:
		return "先前往%s靠岸" % ZONE_NAMES.get(zone, zone)
	if is_busy():
		return "旅人忙碌中"
	return ""


func requirement_reason(requires: Dictionary) -> String:
	var unmet: Array = []
	for id in requires.keys():
		var level: Variant = _get_site_level.call(id)
		var current: int = 0 if level == null else int(level)
		var need: int = int(requires[id])
		if current < need:
			unmet.append("%s需%d级（当前%d级）" % [SITE_NAMES.get(id, id), need, current])
	return "" if unmet.is_empty() else "前置建筑不足：%s" % "；".join(unmet)


func material_reason(cost: Variant) -> String:
	var deficits: Dictionary = missing(cost)
	if deficits.is_empty():
		return ""
	var parts: Array = []
	for key in deficits.keys():
		parts.append("%s缺%d（来源：%s）" % [MATERIALS[key].name, deficits[key], MATERIALS[key].source])
	return "材料不足：%s" % "；".join(parts)


func capacity_reason(reward: Dictionary) -> String:
	if can_receive(reward):
		return ""
	var full: Array = []
	for key in reward.keys():
		var current: Variant = _balance(key)
		var next: float = float(current) + float(reward[key])
		if typeof(current) != TYPE_INT or next > float(MATERIALS[key].capacity) or next > SAFE_INT:
			full.append(MATERIALS[key].name)
	return "库存已满或余额异常%s，请先腾出空间" % ("：" + "、".join(full) if not full.is_empty() else "")


func _action(reason: String, label: Variant = null) -> Dictionary:
	if label == null:
		return {"available": reason.is_empty(), "reason": reason}
	return {"available": reason.is_empty(), "reason": reason, "label": label}


func _find_node(id: String) -> Variant:
	for node in nodes:
		if node.id == id:
			return node
	return null


func _find_plot(id: String) -> Variant:
	for plot in plots:
		if plot.id == id:
			return plot
	return null


func get_collection_action(id: String) -> Dictionary:
	var node: Variant = _find_node(id)
	if node == null:
		return _action("未知采集点")
	var reason := ""
	if id == "sea_cache" and not bool(state.get("farSeaUnlocked", false)):
		reason = "远海尚未解锁，请先升级船只"
	if reason.is_empty():
		reason = access_reason(node.zone)
	if reason.is_empty() and node.left > 0.0:
		reason = "物资补充中，还需%d秒" % int(ceil(node.left))
	if reason.is_empty():
		reason = capacity_reason(node.reward)
	return _action(reason)


func collect(id: String) -> Dictionary:
	var availability := get_collection_action(id)
	if not availability.available:
		return {"ok": false, "reason": availability.reason, "reward": {}}
	var node: Variant = _find_node(id)
	var reward: Dictionary = node.reward.duplicate(true)
	if not receive(reward):
		return {"ok": false, "reason": capacity_reason(reward), "reward": {}}
	node.left = float(node.cooldown)
	node.collections = int(node.collections) + 1
	return {"ok": true, "reason": "", "reward": reward}


func get_plot_action(id: String) -> Dictionary:
	var plot: Variant = _find_plot(id)
	if plot == null:
		return _action("未知菜箱", "不可用")
	var label := "播种"
	if plot.phase == "ready":
		label = "收获"
	elif plot.phase == "growing":
		label = "浇水"

	var reason := access_reason(plot.zone)
	if reason.is_empty():
		reason = requirement_reason({plot.siteId: plot.minLevel})
	if reason.is_empty():
		if plot.phase == "growing":
			# 土壤还有湿气时允许提前补水，干透则必须浇水才能继续长。
			if plot.moisture >= 1.0:
				reason = "土壤湿润，蔬菜生长中，还需%d秒" % int(ceil(plot.remaining))
		elif plot.phase == "ready":
			reason = capacity_reason(plot.reward)
		else:
			reason = material_reason({"seeds": 1})
	return _action(reason, label)


func water_plot(id: String) -> Dictionary:
	var availability := get_plot_action(id)
	if not availability.available:
		return {"ok": false, "reason": availability.reason}
	var plot: Variant = _find_plot(id)
	if plot.phase != "growing":
		return {"ok": false, "reason": "菜箱还没有播种"}
	plot.moisture = 1.0
	return {"ok": true, "reason": ""}


func act_plot(id: String) -> Dictionary:
	var availability := get_plot_action(id)
	if not availability.available:
		return {"ok": false, "reason": availability.reason}
	var plot: Variant = _find_plot(id)
	if plot.phase == "growing":
		return water_plot(id)
	if plot.phase == "ready":
		var reward: Dictionary = plot.reward.duplicate(true)
		if not receive(reward):
			return {"ok": false, "reason": capacity_reason(reward)}
		plot.phase = "empty"
		plot.remaining = 0.0
		plot.reward = null
		plot.moisture = 0.0
		return {"ok": true, "reason": "", "reward": reward}
	if not spend({"seeds": 1}):
		return {"ok": false, "reason": material_reason({"seeds": 1})}
	var improved: bool = int(facilities.greenhouse.level) >= 1
	plot.duration = CROP.greenhouseDuration if improved else CROP.dryDuration
	plot.remaining = plot.duration
	plot.moisture = 1.0
	plot.reward = {"food": 3 if improved else 2, "seeds": 1}
	plot.phase = "growing"
	return {"ok": true, "reason": ""}


func get_facility(id: String) -> Variant:
	return facilities.get(id, null)


func facility_collection_reason(id: String) -> String:
	var facility: Variant = get_facility(id)
	if facility == null:
		return "未知设施"
	var reason := access_reason("zone1")
	if reason.is_empty() and int(facility.level) < 1:
		reason = "设施尚未建成"
	if reason.is_empty() and id != "recycler":
		reason = "该设施没有可收取的产物"
	if reason.is_empty() and not (int(facility.stored.get("parts", 0)) > 0):
		reason = "暂无旧零件，每30秒分拣2个"
	if reason.is_empty():
		reason = capacity_reason(facility.stored)
	return reason


func get_facility_action(id: String) -> Dictionary:
	var facility: Variant = get_facility(id)
	if facility == null:
		return _action("未知设施", "不可用")
	if int(facility.level) >= 1:
		if id == "recycler":
			return _action(facility_collection_reason(id), "收取零件")
		return _action("设施已建造", "已建造")
	var recipe: Dictionary = FACILITIES[id]
	var reason := access_reason("zone1")
	if reason.is_empty():
		reason = requirement_reason(recipe.requires)
	if reason.is_empty():
		reason = material_reason(recipe.cost)
	return _action(reason, "施工中" if job != null and job.id == id else "建造")


func build_facility(id: String) -> Dictionary:
	var facility: Variant = get_facility(id)
	if facility == null:
		return {"ok": false, "reason": "未知设施"}
	if int(facility.level) >= 1:
		return {"ok": false, "reason": "设施已建造"}
	var availability := get_facility_action(id)
	if not availability.available:
		return {"ok": false, "reason": availability.reason}
	if not spend(FACILITIES[id].cost):
		return {"ok": false, "reason": material_reason(FACILITIES[id].cost)}
	job = {"id": id, "remaining": 6.0, "duration": 6.0}
	state["workerMode"] = "CRAFTING"
	return {"ok": true, "reason": ""}


func collect_facility(id: String) -> Dictionary:
	var reason := facility_collection_reason(id)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "reward": {}}
	var facility: Variant = get_facility(id)
	var reward: Dictionary = facility.stored.duplicate(true)
	if not receive(reward):
		return {"ok": false, "reason": capacity_reason(reward), "reward": {}}
	facility.stored = {}
	return {"ok": true, "reason": "", "reward": reward}


func get_ship_action() -> Dictionary:
	var reason := access_reason("zone1")
	if reason.is_empty() and (int(state.get("shipLevel", 1)) >= 2 or bool(state.get("farSeaUnlocked", false))):
		reason = "船只已升级，远海已解锁"
	if reason.is_empty():
		reason = requirement_reason(SHIP_RECIPE.requires)
	if reason.is_empty():
		reason = material_reason(SHIP_RECIPE.cost)
	return _action(reason)


func upgrade_ship() -> Dictionary:
	var availability := get_ship_action()
	if not availability.available:
		return {"ok": false, "reason": availability.reason}
	if not spend(SHIP_RECIPE.cost):
		return {"ok": false, "reason": material_reason(SHIP_RECIPE.cost)}
	state["shipLevel"] = 2
	state["farSeaUnlocked"] = true
	return {"ok": true, "reason": ""}


func trade_food() -> Dictionary:
	var reward := {"coins": 12}
	var reason := access_reason("zone1")
	if reason.is_empty():
		reason = material_reason({"food": 2})
	if reason.is_empty():
		reason = capacity_reason(reward)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "reward": {}}
	if not _transact({"food": 2}, reward):
		return {"ok": false, "reason": "交易余额异常", "reward": {}}
	return {"ok": true, "reason": "", "reward": reward}


## 探索产出：四个区域都算，步行和航行同样累计里程。每 7 米掷一次骰子。
func explore(distance: Variant) -> Dictionary:
	if typeof(distance) != TYPE_FLOAT and typeof(distance) != TYPE_INT:
		return {"ok": false, "reward": {}, "finds": 0, "pending": _explored_distance}
	var d := float(distance)
	if is_nan(d) or is_inf(d) or d < 0.0:
		return {"ok": false, "reward": {}, "finds": 0, "pending": _explored_distance}
	_explored_distance += d
	var reward: Dictionary = {}
	var finds := 0
	while _explored_distance >= EXPLORE.step:
		_explored_distance -= EXPLORE.step
		if _random_value() > EXPLORE.chance:
			continue
		var kind: String = "wood" if _random_value() < 0.62 else "parts"
		var bounds: Array = EXPLORE[kind]
		var amount: int = int(bounds[0]) + int(floor(_random_value() * (int(bounds[1]) - int(bounds[0]) + 1)))
		if amount <= 0:
			continue
		reward[kind] = int(reward.get(kind, 0)) + amount
		finds += 1
	if finds == 0:
		return {"ok": false, "reward": {}, "finds": finds, "pending": _explored_distance}
	if not receive(reward):
		return {"ok": false, "reward": {}, "finds": 0, "pending": _explored_distance}
	return {"ok": true, "reward": reward, "finds": finds, "pending": _explored_distance}


func get_explored_distance() -> float:
	return _explored_distance


## 非法 dt（负数 / NaN / 非数字）返回 false 且不推进任何状态；
## JS 原版这里抛 RangeError，GDScript 没有异常，用返回值表达。
func tick(dt: Variant) -> bool:
	if typeof(dt) != TYPE_FLOAT and typeof(dt) != TYPE_INT:
		return false
	var step := float(dt)
	if is_nan(step) or is_inf(step) or step < 0.0:
		return false

	for node in nodes:
		node.left = maxf(0.0, float(node.left) - step)

	for plot in plots:
		if plot.phase != "growing":
			continue
		var moisture: float = float(plot.moisture)
		# 只在一帧里"还湿着"的那段时间长个儿，剩下的时间土壤是干的，蔬菜停住。
		var wet_seconds: float = minf(step, moisture / float(CROP.drainPerSecond))
		if wet_seconds > 0.0:
			plot.remaining = maxf(0.0, float(plot.remaining) - wet_seconds)
		var next_moisture: float = moisture - float(CROP.drainPerSecond) * step
		# 累减会留下 1e-16 量级的残差，直接归零。
		plot.moisture = 0.0 if next_moisture <= 1e-9 else next_moisture
		if float(plot.remaining) == 0.0:
			plot.phase = "ready"

	var recycler: Dictionary = facilities.recycler
	var recycler_time: float = step if int(recycler.level) >= 1 else 0.0
	if job != null:
		var construction_time: float = float(job.remaining)
		job.remaining = maxf(0.0, construction_time - step)
		if float(job.remaining) == 0.0:
			facilities[job.id].level = 1
			# 本帧先扣除施工时间，回收台只获得完工后的剩余时间。
			if job.id == "recycler":
				recycler_time = step - construction_time
			job = null
			if state.get("workerMode", "") == "CRAFTING":
				state["workerMode"] = "IDLE_ASHORE"

	if int(recycler.level) >= 1 and recycler_time > 0.0:
		var stored: int = int(recycler.stored.get("parts", 0))
		if stored >= 6:
			recycler.timer = 0.0
			return true
		# 最多生产三批即可满仓；满仓停工，不囤积下一次收取后的生产时间。
		var elapsed: float = float(recycler.timer) + minf(recycler_time, 90.0)
		var batches: int = int(floor(elapsed / 30.0))
		var next: int = mini(6, stored + batches * 2)
		if batches > 0:
			recycler.stored["parts"] = next
		recycler.timer = 0.0 if next >= 6 else fposmod(elapsed, 30.0)
	return true
