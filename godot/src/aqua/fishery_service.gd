extends RefCounted
## 家园补给站 → 渔场的第一段：把「升级」这件事本身做成可操作、可存档、可验收。
##
## 2026-11-01 需求：站在家园补给站那块木牌前点「升级」，交付 100 木板 + 50 鱼，
## 这块平台就变成渔场。本轮只做升级操作与身份切换 —— 养殖、投苗、收鱼属于
## SEA-AQUA 的后续条款（R06 起），不在这里假装已经能养鱼。
##
## 单一写入者：`unlocked` 只有本模块改。材料计数与扣费都走注入端口，
## 本模块不读背包、不读全局经济。

signal changed
## 升级成本。按用户给定的数值：木板 100、鱼 50。
const COST := {"wood": 100, "fish": 50}
## 升级作用的平台。家园补给站 = 家园打捞浮台上的补给入口（`trade_board`）。
const SITE_ID := "home_supply"

var unlocked := false
var ports: Dictionary = {}

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
	var blocked := reason()
	if blocked != "": return {"blocked": blocked}
	if not bool(ports.pay.call(COST.duplicate(true))):
		return {"blocked": "材料不足，先补齐木板和鱼"}
	unlocked = true
	changed.emit()
	return {"message": "补给站改成了渔场", "event": "fishery_unlocked"}

func to_dict() -> Dictionary:
	return {"version": 1, "unlocked": unlocked}

func from_dict(data: Dictionary) -> bool:
	unlocked = bool(data.get("unlocked", false))
	changed.emit()
	return true
