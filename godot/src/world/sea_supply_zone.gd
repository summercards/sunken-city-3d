@tool
extends "res://src/world/zone_scene.gd"
## 海上独立结构物 · 可停靠的最小区块。
##
## 海上补给站复用 ZoneScene 的泊位和空间查询，只补两处差异：
##     1. 浮店的建筑几何挂在 `Visual`，不是 `Models`；
##     2. 阻挡声明挂在根节点下，不在建筑子树里。
##
## 浮店是一栋固定建筑，没有种植位，也不随玩家建造升级。

## 资产主记录 ID / 维护分类，保留自 `sea_structure.gd` 的运行期对照口径。
@export var asset_id := ""
@export var role := "shop"


func _register() -> void:
	super._register()
	if models == null:
		var visual := get_node_or_null("Visual")
		if visual is Node3D:
			models = visual


## 父类会给 `models` 下每个可见子节点自动补一个 BlockerSet。
## 浮店的 `Visual` 下是四个材质角色网格（Matte/Metal/Gloss/Emission），
## 那四份互相重叠的派生阻挡没有意义 —— 本结构已经在场景里手工声明了一个
## 覆盖整栋建筑的 Blockers。这里不自动补。
func _ensure_blockers() -> void:
	pass


## 与 `sea_structure.gd` 同一口径：扫整棵子树收集 BlockerSet。
## 不能走父类的 models 子树版本 —— 浮店的 Blockers 挂在根下。
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
