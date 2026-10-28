extends RefCounted
## Current release scope; full world remains an explicit development profile.
const HOME_WATER := Rect2(-18, -12, 55, 48)
static func minimal() -> bool:
	return not OS.get_cmdline_user_args().has("--full-world")
static func zone_enabled(id: String) -> bool:
	return not minimal() or id in ["zone1", "zone5"]
static func command_enabled(id: String) -> bool:
	return not minimal() or id not in ["build", "dive", "lamp", "hook", "camera", "orders", "salvage", "rise", "descend"]
