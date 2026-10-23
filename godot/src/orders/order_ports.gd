extends RefCounted
## Orders own offers, while the host owns inventory and progression queries.
var inventory: RefCounted
var give: Callable
var max_tier: Callable

func is_configured() -> bool:
	return inventory != null and give.is_valid() and max_tier.is_valid()
