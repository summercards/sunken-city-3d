extends RefCounted
## Host-provided boundary. Farming owns crop state; the host owns inventory and progression.
var inventory: RefCounted
var pay: Callable
var give: Callable
var has_greenhouse: Callable
var access_reason: Callable

func is_configured() -> bool:
	return inventory != null and pay.is_valid() and give.is_valid() and has_greenhouse.is_valid() and access_reason.is_valid()
