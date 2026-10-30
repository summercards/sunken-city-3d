@tool
extends Node3D
## 海上独立结构物（不属于任何区块的固定建筑）。
##
## 为什么单独一份：`World/Zones` 之外的结构没有 ZoneScene 去扫描 BlockerSet，
## 水面阻挡就不会派生 —— 船会直接穿过浮店。这里只做「把自己子树的阻挡
## 交给 main 的水面阻挡入口」这一件事，和 ZoneScene 用同一个 BlockerSet。
##
## 它不拥有行走地面、泊位、交互或存档；那些属于各自的功能所有者。

const BlockerSet = preload("res://src/world/blocker_set.gd")

## 资产主记录 ID，便于运行期和账本对照。
@export var asset_id := ""
## 维护分类（对应账本 classification.subcategory）。
@export var role := ""

var water_block_rects: Array[Rect2] = []


func rebuild_blockers(water_y: float, height := 1.6) -> void:
	water_block_rects.clear()
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() == BlockerSet:
			var blocker := n as Node3D
			blocker.rebuild(water_y, height)
			for r in blocker.rects_world:
				water_block_rects.append(r)
		stack.append_array(n.get_children())
