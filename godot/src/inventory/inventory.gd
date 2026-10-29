extends RefCounted
class_name Inventory
## 背包：物品 id → 数量的唯一账本。
##
## 旧实现是 economy.gd 里 9 个 int；这里是唯一真源，经济逻辑只通过它读写。
## 规则：
##   - 货币（category=currency）不占格，数量无上限；
##   - 其余物品按 stack 叠放，每 stack 占一格，总格数受 capacity 限制；
##   - 加不进去的部分不会凭空消失，返回 overflow 让上层提示「背包已满」。
##   - **排列顺序也是背包自己的状态**：玩家在口袋里拖拽整理后要留得住，
##     所以 `_order` 与数量一起存档。它只影响显示次序，不影响任何规则判定。

signal changed(id: String, delta: int)
signal capacity_changed(used: int, capacity: int)
## 只改了排列、没改数量。界面据此重排即可，不必重算容量。
signal order_changed

var _counts: Dictionary = {}
var _capacity: int = 24
## 玩家整理的物品次序（物品 id 序列，不含货币）。
##
## 为什么不叫 slot：一格可能只是某个物品的一个堆（大数量会拆成多堆），
## 所以这里记的是**物品种类**的顺序，同种物品的几个堆始终连在一起。
## 旧存档没有这个字段，读档后为空，`ordered_ids()` 会按物品表顺序补齐。
var _order: Array = []


func _init(capacity: int = -1) -> void:
	_capacity = capacity if capacity > 0 else ItemDB.capacity()


func count(id: String) -> int:
	return int(_counts.get(id, 0))


func all() -> Dictionary:
	return _counts.duplicate()


## 界面显示次序：当前拥有的非货币物品，按玩家整理的顺序，缺的补在后面。
##
## 两条兜底必须都留着：
##   1. 旧存档没有 `_order`，第一次打开时按物品表顺序展示；
##   2. 新捡到的物品还没进 `_order`，也要出现在末尾，不能因为没登记就消失。
func ordered_ids() -> Array:
	var out: Array = []
	var seen := {}
	for raw in _order:
		var id := str(raw)
		if seen.has(id) or count(id) <= 0 or ItemDB.is_currency(id): continue
		seen[id] = true
		out.append(id)
	for id in ItemDB.all_ids():
		var key := str(id)
		if seen.has(key) or count(key) <= 0 or ItemDB.is_currency(key): continue
		seen[key] = true
		out.append(key)
	return out


## 拖拽整理：把 `from_id` 挪到 `to_id` 所处的位置（两者互换）。
##
## 语义选"互换"而不是"插入后整体后移"：玩家把 A 拖到 B 上，期望的是
## "A 到 B 那格、B 到 A 那格"，其余物品一个都不动。这既符合直觉，
## 也保证整理是可逆的（再拖回来就还原）。
## 返回是否真的改了顺序；数量与规则一律不动。
func move_item(from_id: String, to_id: String) -> bool:
	from_id = str(from_id)
	to_id = str(to_id)
	if from_id == to_id or from_id == "" or to_id == "": return false
	if count(from_id) <= 0 or count(to_id) <= 0: return false
	_register(from_id)
	_register(to_id)
	var a := _order.find(from_id)
	var b := _order.find(to_id)
	if a < 0 or b < 0: return false
	_order[a] = to_id
	_order[b] = from_id
	order_changed.emit()
	return true


## 把物品挪到排列末尾（玩家把它拖到空槽上）。
func move_to_end(id: String) -> bool:
	id = str(id)
	if count(id) <= 0: return false
	_register(id)
	var at := _order.find(id)
	if at < 0: return false
	var last := -1
	for i in _order.size():
		if count(str(_order[i])) > 0 and not ItemDB.is_currency(str(_order[i])): last = i
	if last < 0 or last == at: return false
	_order.remove_at(at)
	_order.insert(last, id)
	order_changed.emit()
	return true


## 把物品登记进排列末尾（幂等）。新物品进来时调用。
func _register(id: String) -> void:
	if id == "" or ItemDB.is_currency(id): return
	if not _order.has(id): _order.append(id)


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
		_register(id)
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

## Entire material refund, including stacks shared by several item types.
## Reject before publishing events when any part would overflow the backpack.
func add_all(amounts: Dictionary) -> bool:
	var candidate:=_counts.duplicate()
	for id in amounts:
		if not ItemDB.has(str(id)) or not (amounts[id] is int or amounts[id] is float): return false
		var amount:=float(amounts[id])
		if not is_finite(amount) or amount<0 or amount!=floor(amount): return false
		candidate[id]=int(candidate.get(id,0))+int(amount)
	var used:=0
	for id in candidate:
		if ItemDB.is_currency(str(id)): continue
		used+=int(ceil(float(candidate[id])/float(maxi(1,ItemDB.stack_limit(str(id))))))
	if used>_capacity: return false
	_counts=candidate
	for id in amounts: _register(str(id))
	for id in amounts:
		if int(amounts[id])>0: changed.emit(str(id),int(amounts[id]))
	capacity_changed.emit(slots_used(),_capacity)
	return true


func expand(extra_slots: int) -> void:
	_capacity += maxi(extra_slots, 0)
	capacity_changed.emit(slots_used(), _capacity)


## 存档：只存非零项，读档时按物品表过滤，删掉的物品不会让存档报错。
##
## `order` 只存"当前还持有的物品"，已经用光的东西不该占着顺序位；
## 同时把数量里还没登记的物品补进去，保证读档后的次序与关档前一致。
func to_dict() -> Dictionary:
	var out := {}
	for id in _counts.keys():
		if count(id) > 0:
			out[id] = count(id)
	var order: Array = []
	for id in ordered_ids():
		order.append(str(id))
	return {"capacity": _capacity, "counts": out, "order": order}


func from_dict(data: Dictionary) -> void:
	_counts.clear()
	_order.clear()
	_capacity = int(data.get("capacity", ItemDB.capacity()))
	var counts: Dictionary = data.get("counts", {})
	for id in counts.keys():
		if ItemDB.has(str(id)) and int(counts[id]) > 0:
			_counts[str(id)] = int(counts[id])
	# 旧存档没有 order：留空，`ordered_ids()` 会退回物品表顺序。
	# 只收当前真的还持有的物品，脏 id / 已删物品 / 货币一律丢掉。
	for raw in data.get("order", []):
		var id := str(raw)
		if count(id) > 0 and not ItemDB.is_currency(id) and not _order.has(id):
			_order.append(id)
	changed.emit("", 0)
	capacity_changed.emit(slots_used(), _capacity)
	order_changed.emit()


func clear() -> void:
	_counts.clear()
	_order.clear()
	changed.emit("", 0)
	capacity_changed.emit(0, _capacity)
	order_changed.emit()
