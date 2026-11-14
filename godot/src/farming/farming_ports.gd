extends RefCounted
## Host-provided boundary. Farming owns crop state; the host owns inventory and progression.
var inventory: RefCounted
var pay: Callable
var exchange: Callable
var give: Callable
var has_greenhouse: Callable
var access_reason: Callable
## SEA-ENERGY：行为开销。签名 (action: String) -> String，返回空串表示已扣，
## 否则是拒绝原因。故意做成可选端口：种植规则不拥有体力，也不认识体力表。
var spend_energy: Callable
## 只问不扣：签名 (action: String) -> String。行为开始前的预检走它，
## 免得「体力不够」被扣完种子才发现。
var energy_reason: Callable
var transaction_begin: Callable
var transaction_end: Callable

func is_configured() -> bool:
	return inventory != null and pay.is_valid() and give.is_valid() and has_greenhouse.is_valid() and access_reason.is_valid()
