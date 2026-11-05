@tool
extends "res://src/world/sea_structure.gd"
## 家园外围残楼围挡的装配根。
##
## 存在的理由只有一条：让 20 段围挡的水面阻挡走既有的 `_collect_water_shapes` 入口。
## `World/SeaStructures` 下的节点只要带 `rebuild_blockers()`，main 就会在
## `_water_shapes()` 里统一收集；这里不新建第二条阻挡通道。
##
## 每段的阻挡挂在组件自己的 `Blockers`（BlockerSet，mode=manual）上：
## 围挡是「连续墙体」，手动矩形比 0.4 米栅格派生更准 —— 栅格会在树冠、碎石
## 造成的凹凸处留下可穿的缝，而这段围挡的玩法语义就是「不许出去」。

## 供探针读取：本装配包含多少段、矩形总数。
func segment_count() -> int:
	return get_child(0).get_child_count() if get_child_count() > 0 else 0
