extends RefCounted
## Current release scope; full world remains an explicit development profile.

## 家园生活区：采集物、鱼群、出生点与旧档迁移回位的判定范围。
## 它比可航区小，只描述「家里这一片」，不代表船能开多远。
const HOME_WATER := Rect2(-18, -12, 55, 48)

## Historical 150m framing reference. Free ocean building/sailing no longer uses
## this rectangle as a fence or relocates a valid distant save back inside it.
const SAIL_BOUNDS := Rect2(-75, -75, 150, 150)
static func minimal() -> bool:
	return not OS.get_cmdline_user_args().has("--full-world")
static func zone_enabled(id: String) -> bool:
	return not minimal() or id in ["zone1", "zone5"]
static func command_enabled(id: String) -> bool:
	return not minimal() or id not in ["build", "dive", "lamp", "hook", "camera", "orders", "salvage", "rise", "descend"]
