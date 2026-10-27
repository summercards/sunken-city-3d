extends Node
class_name OrderBoard
## 码头订单板：把「产出」变成「值得专门跑一趟的事」。
##
## 三张长期有效的订单；可免费换单，交付后短暂补位。
## 订单只消费背包物品，仓库建设材料不会被自动交出。

signal changed
## 交付成功：order 是被交掉的那张，reward 是实际进账（含报酬与额外货）。
signal fulfilled(order: Dictionary, reward: Dictionary)
## 单子到期换新。
signal expired(order: Dictionary)
## 新的单子挂上板。
signal offered(order: Dictionary)

const TABLE := "res://assets/data/orders.json"
const ItemDBLib = preload("res://src/inventory/item_db.gd")

const Ports = preload("res://src/orders/order_ports.gd")
var ports: RefCounted

func configure(boundary: RefCounted) -> void:
	assert(boundary.is_configured(), "Orders require configured inventory/progression ports")
	ports = boundary

var slots: Array = []
## 换单与补位用同一套随机源；测试可以 set_seed 固定结果。
var rng := RandomNumberGenerator.new()

var _pool: Array = []
var _cfg: Dictionary = {}
var _by_id: Dictionary = {}


func _ready() -> void:
	assert(ports != null and ports.is_configured(), "Configure orders before adding them to the tree")
	rng.randomize()
	load_table()
	reset()


func load_table(path := TABLE) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("找不到订单表：%s" % path)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("订单表格式不对：%s" % path)
		return
	_cfg = data
	_pool.clear()
	_by_id.clear()
	for row in data.get("orders", []):
		if not (row is Dictionary):
			continue
		# 物品表里没有的订单直接跳过：改物品表不该让整块板子崩掉。
		if not ItemDBLib.has(str(row.get("item", ""))):
			push_warning("订单 %s 指向未知物品，已跳过" % str(row.get("id", "?")))
			continue
		_pool.append(row)
		_by_id[str(row.get("id", ""))] = row


func slot_count() -> int:
	return int(_cfg.get("slots", 3))


func refresh_seconds() -> float:
	return float(_cfg.get("refresh_seconds", 9.0))


func reroll_cost() -> int:
	return 0


## 当前进度能看到的最高档位。1 级起步，船到 2 级或有一处 3 级建造点各加一档。
func max_tier() -> int:
	return clampi(int(ports.max_tier.call()), 1, 3)

## 有货可交（数量够、格子也放得下额外产出）。
func can_fulfill(order: Dictionary) -> bool:
	if order.is_empty():
		return false
	return blocked_reason(order) == ""


func blocked_reason(order: Dictionary) -> String:
	if order.is_empty():
		return "没有订单"
	var item := str(order.get("item", ""))
	var need := int(order.get("amount", 0))
	var have: int = ports.inventory.count(item)
	if have < need:
		return "%s 还差 %d" % [ItemDBLib.label(item), need - have]
	var trial = preload("res://src/inventory/inventory.gd").new()
	trial.from_dict(ports.inventory.to_dict())
	trial.remove(item, need)
	for id in order.get("bonus", {}):
		if int(trial.add(id, int(order.bonus[id])).get("overflow", 0)) > 0:
			return "背包需要留出奖励空间"
	return ""


func time_left(order: Dictionary) -> float:
	return maxf(float(order.get("left", 0.0)), 0.0)


# ---------------------------------------------------------------- 状态机

func reset() -> void:
	slots.clear()
	for i in slot_count():
		slots.append(_roll())
	changed.emit()


func tick(delta: float) -> void:
	var dirty := false
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s.is_empty():
			continue
		if s.has("refill"):
			s.refill = float(s.get("refill", 0.0)) - delta
			if float(s.refill) <= 0.0:
				var fresh := _roll()
				slots[i] = fresh
				dirty = true
				if not fresh.is_empty():
					offered.emit(fresh)
			continue
	if dirty:
		changed.emit()


## 交付一张单子。成功返回 {ok, reward, order}。
func fulfill(uid: String) -> Dictionary:
	var idx := _index_of(uid)
	if idx < 0:
		return {"ok": false, "reason": "这张单子已经不在了"}
	var order: Dictionary = slots[idx]
	var reason := blocked_reason(order)
	if reason != "":
		return {"ok": false, "reason": reason}
	var item := str(order.get("item", ""))
	var need := int(order.get("amount", 0))
	if not ports.inventory.remove(item, need):
		return {"ok": false, "reason": "扣除货物失败"}

	var reward := {"coins": int(order.get("pay", 0))}
	var bonus: Dictionary = order.get("bonus", {})
	for k in bonus.keys():
		reward[str(k)] = int(reward.get(str(k), 0)) + int(bonus[k])
	ports.give.call(reward)

	# 交掉的位子空出来，过一会儿补新单。
	slots[idx] = {"refill": refresh_seconds()}
	changed.emit()
	fulfilled.emit(order, reward)
	return {"ok": true, "reward": reward, "order": order}


## 免费换单，空着的补位格子一起补齐。
func reroll() -> Dictionary:
	var cost := reroll_cost()
	if ports.inventory.count("coins") < cost:
		return {"ok": false, "reason": "换一批要 %d 海贝" % cost}
	ports.inventory.remove("coins", cost)
	for i in slots.size():
		slots[i] = _roll()
	changed.emit()
	return {"ok": true, "cost": cost}


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	# 只存剩余秒数：订单是「还剩多久」的语义，跨进程存绝对时间会变成负数或几十年。
	var rows: Array = []
	for s in slots:
		if s.is_empty():
			rows.append({})
			continue
		if s.has("refill"):
			rows.append({"refill": maxf(float(s.get("refill", 0.0)), 0.0)})
			continue
		rows.append({
			"uid": str(s.get("uid", "")),
			"order": str(s.get("order", "")),
			"left": maxf(float(s.get("left", 0.0)), 0.0),
		})
	return {"slots": rows}


func from_dict(data: Dictionary) -> void:
	# 先按当前表重建，再合并：表里删掉的订单不会让读档报错。
	reset()
	var rows: Array = data.get("slots", [])
	for i in mini(rows.size(), slots.size()):
		var row: Dictionary = rows[i]
		if row.is_empty():
			slots[i] = {}
			continue
		if row.has("refill"):
			slots[i] = {"refill": maxf(float(row.get("refill", 0.0)), 0.0)}
			continue
		var order_id := str(row.get("order", ""))
		if not _by_id.has(order_id):
			slots[i] = _roll()
			continue
		slots[i] = _make_offer(_by_id[order_id], str(row.get("uid", "")),
			maxf(float(row.get("left", 0.0)), 0.0))
	changed.emit()


# ---------------------------------------------------------------- 内部

func _index_of(uid: String) -> int:
	for i in slots.size():
		var s: Dictionary = slots[i]
		if not s.is_empty() and not s.has("refill") and str(s.get("uid", "")) == uid:
			return i
	return -1


## 从池子里抽一张：档位不超过 max_tier()、不与板上已有的重复。
## 抽不到（池子太小或档位全被占）时返回空字典，面板显示「暂时没有新订单」。
func _roll() -> Dictionary:
	var tier := max_tier()
	var used := {}
	for s in slots:
		if not (s is Dictionary) or s.is_empty() or s.has("refill"):
			continue
		used[str(s.get("order", ""))] = true
	var candidates: Array = []
	var total := 0.0
	for row in _pool:
		if int(row.get("tier", 1)) > tier:
			continue
		if used.has(str(row.get("id", ""))):
			continue
		candidates.append(row)
		total += float(row.get("weight", 1.0))
	if candidates.is_empty():
		return {}
	var pick := rng.randf() * total
	var chosen: Dictionary = candidates[candidates.size() - 1]
	for row in candidates:
		pick -= float(row.get("weight", 1.0))
		if pick <= 0.0:
			chosen = row
			break
	var span: Array = _cfg.get("offer_seconds", [260.0, 420.0])
	var life := rng.randf_range(float(span[0]), float(span[1]))
	return _make_offer(chosen, _uid(), life)


func _make_offer(row: Dictionary, uid: String, left: float) -> Dictionary:
	return {
		"uid": uid,
		"order": str(row.get("id", "")),
		"customer": str(row.get("customer", "码头客人")),
		"item": str(row.get("item", "")),
		"amount": int(row.get("amount", 1)),
		"pay": int(row.get("pay", 0)),
		"bonus": (row.get("bonus", {}) as Dictionary).duplicate(),
		"tier": int(row.get("tier", 1)),
		"left": left,
	}


func _uid() -> String:
	return "o%d" % rng.randi_range(100000, 999999)


## 测试用：固定随机源，让「抽到哪张」可复现。
func set_seed(seed_value: int) -> void:
	rng.seed = seed_value

## Detached query results keep UI/readers from editing live offers and nested rewards.
func offers() -> Array: return slots.duplicate(true)
func offer_at(index: int) -> Dictionary:
	return slots[index].duplicate(true) if index >= 0 and index < slots.size() else {}
