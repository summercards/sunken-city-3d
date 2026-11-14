extends RefCounted
## Sole owner of upgrade and accumulated catch. Clock/inventory arrive through ports.

signal changed
## 升级成本。按用户给定的数值：木板 100、鱼 50。
const COST := {"wood": 100, "fish": 50}
## 升级作用的平台。家园补给站 = 家园打捞浮台上的补给入口（`trade_board`）。
const SITE_ID := "home_supply"
const INTERVAL_HOURS := 4.0
const BATCH := 3
const CAPACITY := 24

var unlocked := false
var pending := 0
var _clock_hour := -1.0
var _next_hour := -1.0
var _collecting := false
var _busy := false
var ports: Dictionary = {}

func is_busy() -> bool:
	return _busy or _collecting

func configure(boundary: Dictionary) -> void:
	for key in ["count", "pay", "missing_text"]:
		assert(boundary.has(key) and boundary[key].is_valid(), "Missing fishery port: " + key)
	ports = boundary.duplicate()

## 现在能不能升级？空串表示能，否则是给玩家看的原因。
##
## 「已经升过」优先于「材料不够」：升级完还挂着「还差木板 30」最让人困惑，
## 明明那块牌子已经写着渔场了。
func reason() -> String:
	if unlocked: return "这里已经是渔场了"
	var missing := missing_text()
	if missing != "": return missing
	return ""

func missing_text() -> String:
	if ports.is_empty() or not ports.missing_text.is_valid(): return ""
	return str(ports.missing_text.call(COST))

func held(id: String) -> int:
	if ports.is_empty() or not ports.count.is_valid(): return 0
	return int(ports.count.call(id))

func can_upgrade() -> bool:
	return reason() == ""

func upgrade() -> Dictionary:
	if _busy: return {"blocked":"渔场正在结算"}
	var blocked := reason()
	if blocked != "": return {"blocked": blocked}
	_busy = true
	if not bool(ports.pay.call(COST.duplicate(true))):
		_busy = false
		return {"blocked": "材料不足，先补齐木板和鱼"}
	unlocked = true
	_next_hour = _clock_hour + INTERVAL_HOURS if _clock_hour >= 0 else -1.0
	changed.emit()
	_busy = false
	return {"message": "补给站改成了渔场", "event": "fishery_unlocked"}

func observe(snapshot: Dictionary) -> void:
	var hour := (int(snapshot.day)-1)*24.0+float(snapshot.hour)
	if not is_finite(hour) or hour < 0: return
	var rewind := hour < _clock_hour
	_clock_hour = hour
	if not unlocked: return
	# Legacy saves start their first cycle at the restored game time, without back-pay.
	if _next_hour < 0 or rewind:
		_next_hour = hour+INTERVAL_HOURS
		return
	if hour+0.0000001 < _next_hour: return
	var batches := int(floor((hour-_next_hour+0.0000001)/INTERVAL_HOURS))+1
	_next_hour += batches*INTERVAL_HOURS
	var before := pending
	pending = mini(CAPACITY,pending+batches*BATCH)
	if pending != before: changed.emit()

func harvest_reason() -> String:
	if not unlocked: return "先将补给站升级为渔场"
	if pending <= 0: return "鱼群正在生长，每4小时可收获3条鱼"
	if ports.has("can_receive") and not bool(ports.can_receive.call("fish",pending)):
		return "背包空间不足，先整理背包再收获"
	return ""

func harvest() -> Dictionary:
	if _busy or _collecting: return {"blocked":"正在收获"}
	var blocked := harvest_reason()
	if blocked != "": return {"blocked":blocked}
	if not ports.has("receive"): return {"blocked":"暂时无法收获"}
	_busy = true
	_collecting = true
	var amount := pending
	# add_all is atomic: overflow never consumes any accumulated catch.
	var received := bool(ports.receive.call({"fish":amount}))
	if received: pending = 0
	_collecting = false
	if not received:
		_busy = false
		return {"blocked":"背包空间不足，先整理背包再收获"}
	changed.emit()
	_busy = false
	return {"event":"fishery_harvested","fish":amount,"message":"渔场收获 · 鱼 +%d" % amount}

func to_dict() -> Dictionary:
	return {"version":2,"unlocked":unlocked,"pending":pending,"observed_hour":_clock_hour,"next_hour":_next_hour}

func from_dict(data: Dictionary) -> bool:
	unlocked = bool(data.get("unlocked", false))
	var current := int(data.get("version",1)) >= 2
	pending = int(data.get("pending",0)) if unlocked and current else 0
	_clock_hour = float(data.get("observed_hour",-1)) if current else -1.0
	_next_hour = float(data.get("next_hour",-1)) if unlocked and current else -1.0
	changed.emit()
	return true

static func validate_snapshot(data: Dictionary, clock_hour: float) -> String:
	if int(data.get("version",1)) < 2: return ""
	for key in ["pending","observed_hour","next_hour"]:
		if not data.has(key): return "Missing fishery field: "+key
	var observed := float(data.observed_hour)
	var next := float(data.next_hour)
	if observed < 0 and observed != -1: return "Invalid fishery observation time"
	if observed > clock_hour+0.000001: return "Fishery clock is ahead of world time"
	if not data.unlocked:
		if int(data.pending)!=0 or next!=-1: return "Locked fishery has accumulated catch"
	elif observed == -1:
		if next!=-1 or int(data.pending)!=0: return "Unanchored fishery has accumulated catch"
	elif next<=observed or next>observed+INTERVAL_HOURS+0.000001:
		return "Invalid fishery production deadline"
	return ""
