extends Node
class_name FarmModel
## 种植：菜箱状态机 + 作物表。
##
## 与网页版的差别：
##   - 网页版用一条「湿度条」表示水，玩家只能读数字；这里湿润度直接写在土壤颜色上，
##     缺水时作物停长并垂叶，但**不会枯死**（不做惩罚性设计，只是提醒玩家回来浇水）；
##   - 作物定义在 `assets/data/crops.json`，加一种作物不改代码；
##   - 温室是「长得快 + 多收一份」，不是单纯把时间改短；
##   - 每块地的位置/前置在 `assets/data/plots.json`，由工具求解生成。

signal planted(plot_id: String, crop_id: String)
signal watered(plot_id: String)
signal harvested(plot_id: String, rewards: Dictionary)
signal became_ready(plot_id: String, crop_id: String)
signal plots_changed

const ItemDBLib = preload("res://scripts/core/item_db.gd")

const CROPS_TABLE := "res://assets/data/crops.json"
const PLOTS_TABLE := "res://assets/data/plots.json"

## 温室：生长时间乘 0.72、每次浇水多维持 30%、每茬多收 1 份主产物。
const GREENHOUSE_GROW := 0.72
const GREENHOUSE_THIRST := 1.3
const GREENHOUSE_BONUS := 1

## 地块规格（位置 + 前置），与 plots.json 一一对应。
var specs: Array = []
## 作物定义：id → 表行。
var crops := {}
## HUD 里选中的作物，世界里播种时用它。
var selected_crop := ""
## 地块状态：id → {crop, remaining, total, water}
var states := {}


func _ready() -> void:
	_load_crops()
	_load_plots()


func _load_crops() -> void:
	crops.clear()
	var f := FileAccess.open(CROPS_TABLE, FileAccess.READ)
	if f == null:
		push_error("找不到作物表：%s" % CROPS_TABLE)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("作物表格式不对：%s" % CROPS_TABLE)
		return
	for row in data.get("crops", []):
		if not (row is Dictionary):
			continue
		crops[str(row.get("id", ""))] = row
	# 默认选中第一种作物；表是空的就留空，不要让 UI 崩。
	if selected_crop == "" and not crops.is_empty():
		selected_crop = str(crops.keys()[0])


func _load_plots() -> void:
	specs.clear()
	states.clear()
	var f := FileAccess.open(PLOTS_TABLE, FileAccess.READ)
	if f == null:
		push_error("找不到菜箱表：%s" % PLOTS_TABLE)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("菜箱表格式不对：%s" % PLOTS_TABLE)
		return
	for row in data.get("plots", []):
		if not (row is Dictionary):
			continue
		specs.append(row)
		states[str(row.get("id", ""))] = _empty_state()


func _empty_state() -> Dictionary:
	return {"crop": "", "remaining": 0.0, "total": 0.0, "water": 0.0}


# ---- 查询 -------------------------------------------------------------------

func spec(plot_id: String) -> Dictionary:
	for row in specs:
		if str(row.get("id", "")) == plot_id:
			return row
	return {}


func crop_def(crop_id: String) -> Dictionary:
	return crops.get(crop_id, {})


func state(plot_id: String) -> Dictionary:
	if not states.has(plot_id):
		states[plot_id] = _empty_state()
	return states[plot_id]


func crop_of(plot_id: String) -> String:
	return str(state(plot_id).get("crop", ""))


func is_empty(plot_id: String) -> bool:
	return crop_of(plot_id) == ""


## empty / growing / ready
func phase(plot_id: String) -> String:
	var st := state(plot_id)
	if str(st.crop) == "":
		return "empty"
	if float(st.remaining) <= 0.0:
		return "ready"
	return "growing"


func is_dry(plot_id: String) -> bool:
	if phase(plot_id) != "growing":
		return false
	return float(state(plot_id).water) <= 0.0


func progress(plot_id: String) -> float:
	var st := state(plot_id)
	var total := float(st.total)
	if total <= 0.0:
		return 0.0
	return clampf(1.0 - float(st.remaining) / total, 0.0, 1.0)


## 这块地当前的「动作」：播种 / 浇水 / 查看 / 收获。
func action_label(plot_id: String) -> String:
	match phase(plot_id):
		"ready":
			return "收获"
		"growing":
			return "浇水" if is_dry(plot_id) else "查看"
		_:
			return "播种"


func grow_seconds(crop_id: String) -> float:
	var c := crop_def(crop_id)
	var base := float(c.get("grow", 40.0))
	if Economy.facility_unlocked("greenhouse"):
		base *= GREENHOUSE_GROW
	return maxf(base, 1.0)


func thirst_seconds(crop_id: String) -> float:
	var c := crop_def(crop_id)
	var base := float(c.get("thirst", 16.0))
	if Economy.facility_unlocked("greenhouse"):
		base *= GREENHOUSE_THIRST
	return maxf(base, 1.0)


## 这茬能收什么（含温室加成）。
func yield_of(crop_id: String) -> Dictionary:
	var c := crop_def(crop_id)
	var out := {}
	var table: Dictionary = c.get("yield", {})
	var first := true
	for key in table.keys():
		var amount := int(table[key])
		if first and Economy.facility_unlocked("greenhouse"):
			amount += GREENHOUSE_BONUS
		first = false
		if amount > 0:
			out[str(key)] = amount
	return out


func crop_name(crop_id: String) -> String:
	return str(crop_def(crop_id).get("name", crop_id))


## 不能操作的原因；空字符串表示可以动手。
func blocked_reason(plot_id: String) -> String:
	var row := spec(plot_id)
	if row.is_empty():
		return "未知菜箱"
	var need := str(row.get("requires_site", ""))
	if need != "":
		var level := int(row.get("requires_level", 0))
		if Economy.site_level(need) < level:
			return "%s 需要升到 Lv.%d" % [_site_name(need), level]
	match phase(plot_id):
		"empty":
			var crop := crop_def(selected_crop)
			if crop.is_empty():
				return "没有可播的作物"
			var seed_id := str(crop.get("seed", "seed"))
			if Economy.count(seed_id) < 1:
				return "还差 1 %s" % _item_name(seed_id)
			return ""
		"growing":
			if is_dry(plot_id):
				return ""
			return "%s 生长中 · 还需 %d 秒（土壤湿润）" % [
				crop_name(crop_of(plot_id)), int(ceil(float(state(plot_id).remaining)))]
		_:
			var reward := yield_of(crop_of(plot_id))
			var full := _inventory_full(reward)
			if full != "":
				return "背包已满 · 装不下 %s" % full
			return ""


## 一行短状态，提示条与 HUD 共用（不带菜箱名，调用方自己拼）。
func status_text(plot_id: String) -> String:
	var name := crop_name(crop_of(plot_id))
	match phase(plot_id):
		"empty":
			return "空着 · 待播 %s" % crop_name(selected_crop)
		"ready":
			return "%s · 可以收获" % name
		_:
			var pct := int(round(progress(plot_id) * 100.0))
			if is_dry(plot_id):
				return "%s · 缺水停长 %d%%" % [name, pct]
			return "%s · %d%% · 湿 %d 秒" % [
				name, pct, int(ceil(float(state(plot_id).water)))]


# ---- 操作 -------------------------------------------------------------------

## 统一入口：世界里按 E 走这里。返回 {"blocked": 原因} 或 {"event": ...}。
func interact(plot_id: String, crop_id: String = "") -> Dictionary:
	var reason := blocked_reason(plot_id)
	if reason != "":
		return {"blocked": reason}
	match phase(plot_id):
		"empty":
			return plant(plot_id, crop_id if crop_id != "" else selected_crop)
		"ready":
			return harvest(plot_id)
		_:
			return water(plot_id)


func plant(plot_id: String, crop_id: String) -> Dictionary:
	if phase(plot_id) != "empty":
		return {"blocked": "这块地已经种上了"}
	var row := spec(plot_id)
	var need := str(row.get("requires_site", ""))
	if need != "" and Economy.site_level(need) < int(row.get("requires_level", 0)):
		return {"blocked": "%s 需要升到 Lv.%d" % [
			_site_name(need), int(row.get("requires_level", 0))]}
	var crop := crop_def(crop_id)
	if crop.is_empty():
		return {"blocked": "没有这种作物"}
	var seed_id := str(crop.get("seed", "seed"))
	if not Economy.pay({seed_id: 1}):
		return {"blocked": "还差 1 %s" % _item_name(seed_id)}
	var total := grow_seconds(crop_id)
	states[plot_id] = {
		"crop": crop_id,
		"remaining": total,
		"total": total,
		"water": thirst_seconds(crop_id),
	}
	planted.emit(plot_id, crop_id)
	plots_changed.emit()
	return {"event": "planted", "crop": crop_id, "name": crop_name(crop_id), "seconds": total}


func water(plot_id: String) -> Dictionary:
	if phase(plot_id) != "growing":
		return {"blocked": "这块地现在不需要浇水"}
	var st := state(plot_id)
	var thirst := thirst_seconds(crop_of(plot_id))
	if float(st.water) >= thirst - 0.5:
		return {"blocked": "土壤还湿着，不用浇"}
	st.water = thirst
	watered.emit(plot_id)
	plots_changed.emit()
	return {"event": "watered", "name": crop_name(crop_of(plot_id))}


func harvest(plot_id: String) -> Dictionary:
	if phase(plot_id) != "ready":
		return {"blocked": "还没长成"}
	var crop_id := crop_of(plot_id)
	var reward := yield_of(crop_id)
	var full := _inventory_full(reward)
	if full != "":
		return {"blocked": "背包已满 · 装不下 %s" % full}
	# 收成走 Economy.give：溢出会发 overflow 信号，不会静默丢。
	Economy.give(reward)
	var name := crop_name(crop_id)
	states[plot_id] = _empty_state()
	harvested.emit(plot_id, reward)
	plots_changed.emit()
	return {"event": "harvested", "crop": crop_id, "name": name, "reward": reward}


## 时间推进：只有「还湿着」的那段时间才长个儿；干透就停住。
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for id in states.keys():
		var st: Dictionary = states[id]
		if str(st.crop) == "" or float(st.remaining) <= 0.0:
			continue
		var wet := minf(delta, maxf(float(st.water), 0.0))
		if wet > 0.0:
			st.remaining = maxf(0.0, float(st.remaining) - wet)
		# 水位按真实时间走，不按生长时间；大步 tick 也不会把湿润期吞掉。
		st.water = maxf(0.0, float(st.water) - delta)
		if float(st.remaining) <= 0.0:
			became_ready.emit(id, str(st.crop))


# ---- 存档 -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"selected_crop": selected_crop,
		"plots": states.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	# 先按当前表重建，再合并存档：删掉的菜箱/作物不会让读档报错。
	for row in specs:
		states[str(row.get("id", ""))] = _empty_state()
	var saved: Dictionary = data.get("plots", {})
	for id in saved.keys():
		if not states.has(str(id)):
			continue
		var row: Dictionary = saved[id]
		var crop_id := str(row.get("crop", ""))
		if crop_id != "" and not crops.has(crop_id):
			continue
		states[str(id)] = {
			"crop": crop_id,
			"remaining": maxf(0.0, float(row.get("remaining", 0.0))),
			"total": maxf(0.0, float(row.get("total", 0.0))),
			"water": maxf(0.0, float(row.get("water", 0.0))),
		}
	var sel := str(data.get("selected_crop", ""))
	if crops.has(sel):
		selected_crop = sel
	plots_changed.emit()


# ---- 内部 -------------------------------------------------------------------

func _site_name(id: String) -> String:
	var spec_row: Dictionary = Economy.SITES.get(id, {})
	return str(spec_row.get("name", id))


func _item_name(id: String) -> String:
	return str(ItemDBLib.get_item(id).get("label", id))


## 返回装不下的物品名；都装得下返回空串。
func _inventory_full(reward: Dictionary) -> String:
	for id in reward.keys():
		if not Economy.inventory.can_add(str(id), int(reward[id])):
			return _item_name(str(id))
	return ""
