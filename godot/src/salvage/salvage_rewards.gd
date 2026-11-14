extends RefCounted

signal salvage_ready
const Items = preload("res://src/inventory/item_db.gd")
const SALVAGE_COOLDOWN := 16.0
var salvage_ready_at := 0.0
var ports: Dictionary = {}
var _settling := false
var _last_result: Dictionary = {}

func to_dict() -> Dictionary:
	return {"left":salvage_cooldown_left(Time.get_ticks_msec()/1000.0)}

func from_dict(data: Dictionary) -> void:
	salvage_ready_at = Time.get_ticks_msec()/1000.0 + float(data.get("left",0.0))

## add_all / receive_all 必须由库存owner保证整笔提交；返回bool或{ok, reason}。
## 旧give边界仍可配置，但不能用逐项入账或事后退款模拟原子事务。
func configure(boundary: Dictionary) -> void:
	ports = boundary.duplicate()

func is_busy() -> bool:
	return _settling

func last_result() -> Dictionary:
	return _last_result.duplicate(true)

func can_salvage(now: float) -> bool:
	return not _settling and now >= salvage_ready_at

func salvage_cooldown_left(now: float) -> float:
	return maxf(salvage_ready_at - now, 0.0)

## 兼容旧caller：成功仅返回实际入账字典，拒绝仍为空字典。
func commit_salvage(now: float, haul: Dictionary) -> Dictionary:
	return commit_salvage_result(now, haul).added

func do_salvage(now: float) -> Dictionary:
	return commit_salvage(now, {"wood": 3, "parts": 2})

## 详细结果不混入奖励字典，避免旧caller把ok/reason当资源处理。
## overflow表示整笔未入账奖励，不是允许丢弃的部分产出。
func commit_salvage_result(now: float, haul: Dictionary) -> Dictionary:
	if _settling:
		return {"ok":false, "added":{}, "overflow":{}, "reason":"打捞正在结算"}
	_last_result = {"ok":false, "added":{}, "overflow":{}, "reason":""}
	if not can_salvage(now):
		_last_result.reason = "打捞正在冷却"
		return last_result()
	if haul.is_empty():
		_last_result.reason = "没有可结算的打捞奖励"
		return last_result()
	var amounts := {}
	for id in haul:
		if not id is String or not Items.has(id):
			_last_result.reason = "未知打捞资源：%s" % str(id)
			return last_result()
		var amount: Variant = haul[id]
		if not (amount is int or amount is float) or not is_finite(float(amount)) or amount <= 0 or float(amount) != floor(float(amount)) or amount > 1000000000:
			_last_result.reason = "打捞奖励数量必须为正整数"
			return last_result()
		amounts[id] = int(amount)
	_last_result.overflow = amounts.duplicate(true)
	var receive: Callable = ports.get("receive_all", ports.get("add_all", Callable()))
	if not receive.is_valid():
		_last_result.reason = "打捞原子入账端口未接入"
		return last_result()
	_settling = true
	var received: Variant = receive.call(amounts.duplicate(true))
	var accepted: bool = received is bool and received == true
	var reason := "背包已满"
	if received is Dictionary:
		accepted = received.get("ok", false) == true
		reason = str(received.get("reason", reason))
	if accepted:
		salvage_ready_at = now + SALVAGE_COOLDOWN
		_last_result = {"ok":true, "added":amounts, "overflow":{}, "reason":""}
		salvage_ready.emit()
	else:
		_last_result.reason = reason if not reason.is_empty() else "打捞奖励入账被拒绝"
	_settling = false
	return last_result()
