extends RefCounted
## Current release scope; full world remains an explicit development profile.

## 家园生活区：初始六束浮木补给区及出生/旧档回位参考范围。
## 它比可航区小，只描述「家里这一片」，不代表船能开多远。
const HOME_WATER := Rect2(-18, -12, 55, 48)

## Historical 150m framing reference. Free ocean building/sailing no longer uses
## this rectangle as a fence or relocates a valid distant save back inside it.
const SAIL_BOUNDS := Rect2(-75, -75, 150, 150)
static func minimal() -> bool:
	return not OS.get_cmdline_user_args().has("--full-world")
static func zone_enabled(id: String) -> bool:
	# 海上补给站是家园动线上的固定设施（阳光房正南 50 米），不属于远海内容。
	# 横滨铁道按 2026-11-03 要求放进默认范围；顶层牧场是同一批接入的海上高层农场。
	# 圆弧农场与远海街町已按「只保留横滨」从 main.tscn 移除，不在此列。
	# room 是太阳房上的室内房间（SEA-ROOM），和 zone1 一起属于最小可玩循环。
	return not minimal() or id in ["zone1", "zone2", "zone5", "sea_supply", "rooftop_ranch", "neon_garden_quarter", "room"]
static func command_enabled(id: String) -> bool:
	return not minimal() or id not in ["build", "dive", "lamp", "hook", "camera", "orders", "salvage", "rise", "descend"]
