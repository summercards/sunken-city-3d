extends Node
class_name FarmModel
## 日制种植规则。场景负责位置，规则只读 ID / 定义 / 状态。
signal planted(plot_id: String, crop_id: String)
signal watered(plot_id: String)
signal harvested(plot_id: String, rewards: Dictionary)
signal became_ready(plot_id: String, crop_id: String)
signal plots_changed
signal day_changed(day: int)
const ItemDBLib = preload("res://src/inventory/item_db.gd")
const CROPS_TABLE := "res://assets/data/crops.json"
const PLOTS_TABLE := "res://assets/data/plots.json"
const WATER_CAPACITY := 12
const Ports = preload("res://src/farming/farming_ports.gd")
const CatalogLib = preload("res://src/crops/crop_catalog.gd")
var ports: RefCounted
## 品种数据归 SEA-CROP：本模块只查询数值，不拥有作物定义，也不碰作物模型。
var catalog: CatalogLib

func configure(boundary: RefCounted) -> void:
	assert(boundary.is_configured(), "Farming requires configured inventory/progression ports")
	ports = boundary

func select_crop(crop_id: String) -> bool:
	if not crops.has(crop_id): return false
	selected_crop = crop_id
	plots_changed.emit()
	return true

var specs: Array = []
var crops := {}
var selected_crop := "lettuce"
var states := {}
var day := 1
var watering_can := WATER_CAPACITY

func _ready() -> void:
	assert(ports != null and ports.is_configured(), "Configure farming before adding it to the tree")
	if catalog == null:
		catalog = CatalogLib.new()
		if not catalog.reload(CROPS_TABLE):
			push_error("[farm] 作物表加载失败：" + catalog.error())
	crops = catalog.definitions()
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLOTS_TABLE))
	specs = table.get("plots", [])
	for row in specs:
		states[str(row.id)] = _empty_state()


## 品种目录。表现层与 UI 通过它取模型路径与阶段标签。
func crop_catalog() -> CatalogLib:
	if catalog == null:
		catalog = CatalogLib.new()
		catalog.reload(CROPS_TABLE)
	return catalog

func _empty_state() -> Dictionary:
	return {"crop":"", "remaining":0.0, "total":0.0, "water":0.0, "harvests":0}

func spec(plot_id: String) -> Dictionary:
	for row in specs:
		if str(row.id) == plot_id: return row.duplicate(true)
	return {}

func crop_def(crop_id: String) -> Dictionary:
	if catalog != null:
		return catalog.get_crop(crop_id)
	return crops.get(crop_id, {}).duplicate(true)

func state(plot_id: String) -> Dictionary:
	# Queries never expose a writable reference or create an unknown plot.
	return states.get(plot_id,_empty_state()).duplicate(true)

func plot_specs() -> Array: return specs.duplicate(true)
func crop_definitions() -> Dictionary:
	if catalog != null:
		return catalog.definitions()
	return crops.duplicate(true)

func _state(plot_id: String) -> Dictionary:
	if not states.has(plot_id): states[plot_id] = _empty_state()
	return states[plot_id]

## Explicit preview command for --farm fixtures; ordinary gameplay uses plant/water.
func debug_set_growth(plot_id: String, ratio: float, wet: bool) -> bool:
	if not states.has(plot_id) or is_empty(plot_id) or not is_finite(ratio): return false
	var st := _state(plot_id)
	st.remaining = float(st.total)*clampf(ratio,0.0,1.0)
	st.water = 1.0 if wet else 0.0
	plots_changed.emit()
	return true

func crop_of(plot_id: String) -> String:
	return str(state(plot_id).crop)

func is_empty(plot_id: String) -> bool:
	return crop_of(plot_id) == ""

func phase(plot_id: String) -> String:
	if is_empty(plot_id): return "empty"
	return "ready" if float(state(plot_id).remaining) <= 0.0 else "growing"

func is_dry(plot_id: String) -> bool:
	return phase(plot_id) == "growing" and float(state(plot_id).water) <= 0.0

func progress(plot_id: String) -> float:
	var st := state(plot_id)
	return clampf(1.0 - float(st.remaining) / maxf(float(st.total),1.0),0.0,1.0)

func grow_days(crop_id: String) -> int:
	var days := int(crop_def(crop_id).get("grow_days",3))
	return maxi(1, days - (1 if bool(ports.has_greenhouse.call()) else 0))

func yield_of(crop_id: String) -> Dictionary:
	var out: Dictionary = crop_def(crop_id).get("yield",{}).duplicate()
	if bool(ports.has_greenhouse.call()) and not out.is_empty():
		out[out.keys()[0]] = int(out[out.keys()[0]]) + 1
	return out

func crop_name(crop_id: String) -> String:
	return str(crop_def(crop_id).get("name",crop_id))

func action_label(plot_id: String) -> String:
	match phase(plot_id):
		"empty": return "播种"
		"ready": return "收获"
		_: return "浇水" if is_dry(plot_id) else "查看"

func _access_reason(plot_id: String) -> String:
	var row := spec(plot_id)
	if row.is_empty(): return "未知地格"
	if not is_empty(plot_id): return ""
	return str(ports.access_reason.call(row))

func blocked_reason(plot_id: String) -> String:
	var reason := _access_reason(plot_id)
	if reason != "": return reason
	match phase(plot_id):
		"empty":
			var c := crop_def(selected_crop)
			if c.is_empty(): return "请选择作物"
			if ports.inventory.count(str(c.seed)) < 1: return "缺少" + crop_name(selected_crop) + "种子，可在种植页购买"
		"growing":
			if not is_dry(plot_id): return "今天已浇水，休息后生长"
			# 水壶空了不算拒绝：界面会把这一格换成「补水并浇水」，
			# 这里若返回拦截，角色连走过去都不肯，按钮就永远按不动。
			if watering_can <= 0: return ""
		"ready": return _inventory_full(yield_of(crop_of(plot_id)))
	return ""

func status_text(plot_id: String) -> String:
	match phase(plot_id):
		"empty": return "空地 · 待播" + crop_name(selected_crop)
		"ready": return crop_name(crop_of(plot_id)) + " · 可收获"
		_: return "%s · 还需 %d 天 · %s" % [crop_name(crop_of(plot_id)), int(ceil(float(state(plot_id).remaining))), "待浇水" if is_dry(plot_id) else "今日已浇"]

func interact(plot_id: String, crop_id: String = "") -> Dictionary:
	match phase(plot_id):
		"empty": return plant(plot_id, crop_id if crop_id != "" else selected_crop)
		"ready": return harvest(plot_id)
		_: return water(plot_id)

func plant(plot_id: String, crop_id: String) -> Dictionary:
	var reason := _access_reason(plot_id)
	if reason != "": return {"blocked":reason}
	if not is_empty(plot_id): return {"blocked":"这格已经种上了"}
	var c := crop_def(crop_id)
	if c.is_empty(): return {"blocked":"没有这种作物"}
	if not ports.pay.call({str(c.seed):1}): return {"blocked":"缺少" + crop_name(crop_id) + "种子"}
	var days := grow_days(crop_id)
	states[plot_id] = {"crop":crop_id,"remaining":float(days),"total":float(days),"water":0.0,"harvests":0}
	planted.emit(plot_id,crop_id)
	plots_changed.emit()
	return {"event":"planted","crop":crop_id,"name":crop_name(crop_id),"days":days}

func water(plot_id: String) -> Dictionary:
	var reason := _access_reason(plot_id)
	if reason != "": return {"blocked":reason}
	if phase(plot_id) != "growing": return {"blocked":"这格不需要浇水"}
	if not is_dry(plot_id): return {"blocked":"今天已经浇过，不会重复消耗水"}
	# 水壶见底不是死路：`hint` 让界面把这一格换成「补水并浇水」，
	# 否则三颗气泡全灰，玩家站在一格缺水作物前什么都做不了。
	if watering_can <= 0: return {"blocked":"水壶空了，先补水","hint":"refill"}
	watering_can -= 1
	_state(plot_id).water = 1.0
	watered.emit(plot_id)
	plots_changed.emit()
	return {"event":"watered","name":crop_name(crop_of(plot_id))}

func harvest(plot_id: String) -> Dictionary:
	var reason := _access_reason(plot_id)
	if reason != "": return {"blocked":reason}
	if phase(plot_id) != "ready": return {"blocked":"还没成熟"}
	var crop_id := crop_of(plot_id)
	var reward := yield_of(crop_id)
	reason = _inventory_full(reward)
	if reason != "": return {"blocked":reason}
	ports.give.call(reward)
	var st := _state(plot_id)
	st.harvests = int(st.get("harvests",0)) + 1
	var c := crop_def(crop_id)
	var regrow := int(st.harvests) < int(c.get("harvests",1))
	if regrow:
		st.remaining = float(c.regrow_days)
		st.total = float(c.regrow_days)
		st.water = 0.0
	else:
		states[plot_id] = _empty_state()
	harvested.emit(plot_id,reward)
	plots_changed.emit()
	return {"event":"harvested","name":crop_name(crop_id),"crop":crop_id,"reward":reward,"regrow":regrow}

## 帧时间不推进作物。玩家休息时只结算一个游戏日。
func tick(_delta: float) -> void:
	pass

func advance_day(accessible_only := false) -> Dictionary:
	var grew := 0
	var ready := 0
	for id in states.keys():
		if accessible_only and str(ports.access_reason.call(spec(id))) != "": continue
		var st: Dictionary = states[id]
		if phase(id) == "growing" and float(st.water) > 0:
			st.remaining = maxf(0.0,float(st.remaining)-1.0)
			grew += 1
			if float(st.remaining) <= 0:
				ready += 1
				became_ready.emit(id,str(st.crop))
		st.water = 0.0
	day += 1
	day_changed.emit(day)
	plots_changed.emit()
	return {"day":day,"grew":grew,"ready":ready}

func refill() -> Dictionary:
	watering_can = WATER_CAPACITY
	plots_changed.emit()
	return {"message":"淡水补满 · %d/%d" % [watering_can,WATER_CAPACITY]}

func buy_seed(crop_id: String) -> Dictionary:
	var c := crop_def(crop_id)
	if c.is_empty(): return {"blocked":"没有这种种子"}
	var price := int(c.seed_price)
	if not ports.inventory.can_add(str(c.seed),1): return {"blocked":"背包已满，无法购买"}
	if not ports.pay.call({"coins":price}): return {"blocked":"瓶盖不足"}
	ports.give.call({str(c.seed):1})
	return {"message":"买到 1 包"+crop_name(crop_id)+"种子"}

func exchange_seed() -> Dictionary:
	if not ports.inventory.can_add("lettuce_seed",1): return {"blocked":"背包已满"}
	if not ports.pay.call({"seed":1}): return {"blocked":"没有旧种子"}
	ports.give.call({"lettuce_seed":1})
	return {"message":"旧种子换成了生菜种子"}

func sell_produce() -> Dictionary:
	var income := 0
	var sold := {}
	for c in crops.values():
		for id in c.get("yield",{}):
			if sold.has(id): continue
			var count: int = ports.inventory.count(str(id))
			var price := int(ItemDBLib.get_item(str(id)).get("sell",0))
			if count > 0 and price > 0:
				sold[id] = count
				income += price*count
	if income == 0: return {"blocked":"没有可出售的农产品"}
	ports.pay.call(sold)
	ports.give.call({"coins":income})
	return {"message":"出售农产品 · 瓶盖 +%d" % income,"income":income}

func _inventory_full(reward: Dictionary) -> String:
	# 使用整笔奖励的背包副本试装，避免多个产物各自检查通过却合起来放不下。
	var trial = load("res://src/inventory/inventory.gd").new()
	trial.from_dict(ports.inventory.to_dict())
	for id in reward:
		if not trial.add(str(id),int(reward[id])).ok: return "背包已满，作物保留在地里"
	return ""

func to_dict() -> Dictionary:
	return {"version":2,"day":day,"watering_can":watering_can,"selected_crop":selected_crop,"plots":states.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	states.clear()
	day = maxi(1,int(data.get("day",1)))
	watering_can = clampi(int(data.get("watering_can",WATER_CAPACITY)),0,WATER_CAPACITY)
	for row in specs: states[str(row.id)] = _empty_state()
	var saved: Dictionary = data.get("plots",{})
	for id in saved:
		if not states.has(str(id)): continue
		var st: Dictionary = saved[id]
		var crop_id := str(st.get("crop",""))
		if not crops.has(crop_id): continue
		var total := float(st.get("total",1.0))
		var remaining := float(st.get("remaining",total))
		if int(data.get("version",1)) < 2:
			var ratio := clampf(remaining / maxf(total,1.0),0.0,1.0)
			total = float(grow_days(crop_id))
			remaining = ceil(ratio*total)
		states[str(id)] = {"crop":crop_id,"total":maxf(total,1.0),"remaining":clampf(remaining,0.0,maxf(total,1.0)),"water":1.0 if float(st.get("water",0))>0 else 0.0,"harvests":clampi(int(st.get("harvests",0)),0,int(crops[crop_id].get("harvests",1))-1)}
	_absorb_removed_cells(saved, int(data.get("version",1)))
	selected_crop = str(data.get("selected_crop","lettuce"))
	if not crops.has(selected_crop): selected_crop = "lettuce"
	plots_changed.emit()

## 2026-10-28：太阳房菜箱由 6 格并为 1 格。
##
## 旧档里 `home_plot:1..5` 可能还有正在长的作物，直接丢弃等于没收玩家的收成。
## 这里把「最接近成熟」的那一格搬进保留下来的 `home_plot`（仅当它是空地），
## 其余被删格的状态随本次读档一起丢弃；种子不退还，因为作物本身已经搬过去了。
## 只处理同一基座被删掉的兄弟格，不影响其它区块。
func _absorb_removed_cells(saved: Dictionary, version: int) -> void:
	for base in states.keys():
		var base_state: Dictionary = states[base]
		if str(base_state.crop) != "": continue
		var best: Dictionary = {}
		var best_remaining := INF
		for id in saved.keys():
			var key := str(id)
			if not key.begins_with(str(base) + ":"): continue
			if states.has(key): continue
			var st: Dictionary = saved[id]
			var crop_id := str(st.get("crop",""))
			if not crops.has(crop_id): continue
			var total := float(st.get("total",1.0))
			var remaining := float(st.get("remaining",total))
			if version < 2:
				var ratio := clampf(remaining / maxf(total,1.0),0.0,1.0)
				total = float(grow_days(crop_id))
				remaining = ceil(ratio*total)
			if remaining < best_remaining:
				best_remaining = remaining
				best = {"crop":crop_id,"total":maxf(total,1.0),
					"remaining":clampf(remaining,0.0,maxf(total,1.0)),
					"water":1.0 if float(st.get("water",0))>0 else 0.0,
					"harvests":clampi(int(st.get("harvests",0)),0,int(crops[crop_id].get("harvests",1))-1)}
		if not best.is_empty():
			states[base] = best
			print("[farm-migration] %s 收纳了被删除子格的作物 %s（剩 %d 天）" % [base, str(best.crop), int(best.remaining)])

func clear_plot_specs() -> void:
	specs.clear()

func register_plot(row: Dictionary) -> void:
	assert(not row.get("id","").is_empty())
	for existing in specs:
		if existing.id==row.id: return
	specs.append(row.duplicate(true))

func unregister_plot(id: String) -> void:
	for i in range(specs.size()-1,-1,-1):
		if specs[i].id==id: specs.remove_at(i)
	states.erase(id)
	plots_changed.emit()

func access_reason(id: String) -> String:
	return _access_reason(id)

func sync_calendar_day(value: int) -> void:
	day = maxi(1,value)
	plots_changed.emit()
