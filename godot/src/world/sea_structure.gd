@tool
extends Node3D
## 海上独立结构物（不属于任何区块的固定建筑）。
##
## BlockerSet 为建造和漂流物提供水域占用。船壳碰撞由场景中的实体负责。
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
