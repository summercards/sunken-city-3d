extends RefCounted
class_name Inventory
## 背包：物品 id → 数量的唯一账本。
##
## 旧实现是 economy.gd 里 9 个 int；这里是唯一真源，经济逻辑只通过它读写。
## 规则：
##   - 货币（category=currency）不占格，数量无上限；
##   - 其余物品按 stack 叠放，每 stack 占一格，总格数受 capacity 限制；
##   - 加不进去的部分不会凭空消失，返回 overflow 让上层提示「背包已满」。

signal changed(id: String, delta: int)
signal capacity_changed(used: int, capacity: int)

var _counts: Dictionary = {}
var _capacity: int = 24


func _init(capacity: int = -1) -> void:
	_capacity = capacity if capacity > 0 else ItemDB.capacity()


func count(id: String) -> int:
	return int(_counts.get(id, 0))


func all() -> Dictionary:
	return _counts.duplicate()


## 该物品当前占用多少格。
func slots_of(id: String) -> int:
	var stack := ItemDB.stack_limit(id)
	if stack <= 0:
		return 0
	var n := count(id)
	return int(ceil(float(n) / float(stack)))


func slots_used() -> int:
	var total := 0
	for id in _counts.keys():
		total += slots_of(id)
	return total


func capacity() -> int:
	return _capacity


func slots_free() -> int:
	return maxi(_capacity - slots_used(), 0)


## 还能再放多少个（不含货币上限）。
func room_for(id: String) -> int:
	if ItemDB.is_currency(id):
		return 1 << 30
	var stack := maxi(ItemDB.stack_limit(id), 1)
	var free_slots := slots_free()
	# 已有未满的那一格也算余量
	var cur := count(id)
	var partial := (stack - (cur % stack)) % stack
	return free_slots * stack + partial


## 加物品。返回 {ok, added, overflow, reason}。
func add(id: String, amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": true, "added": 0, "overflow": 0, "reason": ""}
	if not ItemDB.has(id):
		return {"ok": false, "added": 0, "overflow": amount, "reason": "未知物品 %s" % id}
	var room := room_for(id)
	var added := mini(amount, room)
	if added > 0:
		_counts[id] = count(id) + added
		changed.emit(id, added)
		capacity_changed.emit(slots_used(), _capacity)
	var overflow := amount - added
	return {
		"ok": overflow == 0,
		"added": added,
		"overflow": overflow,
		"reason": "" if overflow == 0 else "背包已满",
	}


func can_add(id: String, amount: int) -> bool:
	return room_for(id) >= amount


## 扣物品。原子操作：不够就一点不扣。
func remove(id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if count(id) < amount:
		return false
	var left := count(id) - amount
	if left <= 0:
		_counts.erase(id)
	else:
		_counts[id] = left
	changed.emit(id, -amount)
	capacity_changed.emit(slots_used(), _capacity)
	return true


func set_count(id: String, amount: int) -> void:
	var delta := amount - count(id)
	if amount <= 0:
		_counts.erase(id)
	else:
		_counts[id] = amount
	changed.emit(id, delta)
	capacity_changed.emit(slots_used(), _capacity)


## 多物品检查：{"wood": 3, "parts": 2} 是否全部满足。
func has_all(costs: Dictionary) -> bool:
	for id in costs.keys():
		if count(id) < int(costs[id]):
			return false
	return true


## 缺多少：{"wood": 3} 表示还差 3 个木料。齐了返回空字典。
func missing(costs: Dictionary) -> Dictionary:
	var out := {}
	for id in costs.keys():
		var lack := int(costs[id]) - count(id)
		if lack > 0:
			out[id] = lack
	return out


## 一次性扣除一大笔；不足则不扣任何东西。
func pay(costs: Dictionary) -> bool:
	if not has_all(costs):
		return false
	for id in costs.keys():
		remove(id, int(costs[id]))
	return true


func expand(extra_slots: int) -> void:
	_capacity += maxi(extra_slots, 0)
	capacity_changed.emit(slots_used(), _capacity)


## 存档：只存非零项，读档时按物品表过滤，删掉的物品不会让存档报错。
func to_dict() -> Dictionary:
	var out := {}
	for id in _counts.keys():
		if count(id) > 0:
			out[id] = count(id)
	return {"capacity": _capacity, "counts": out}


func from_dict(data: Dictionary) -> void:
	_counts.clear()
	_capacity = int(data.get("capacity", ItemDB.capacity()))
	var counts: Dictionary = data.get("counts", {})
	for id in counts.keys():
		if ItemDB.has(str(id)) and int(counts[id]) > 0:
			_counts[str(id)] = int(counts[id])
	changed.emit("", 0)
	capacity_changed.emit(slots_used(), _capacity)


func clear() -> void:
	_counts.clear()
	changed.emit("", 0)
	capacity_changed.emit(0, _capacity)
