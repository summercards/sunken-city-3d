@tool
extends Node3D
class_name FarmField
const Farm_modelDependency = preload("res://src/farming/farm.gd")
var farm_model: Farm_modelDependency
## 菜箱登记器：实体独立摆在区块 Objects 下；规则仍归 farm_model。
##
## 位置是资产，状态与规则在 FarmModel；这里不重复读表，避免两处走偏。

signal acted(plot_id: String, event: String, payload: Dictionary)

var plots: Array = []


func build() -> void:
	# 种植箱由区块实例化，本节点只登记与转发事件，不生成/移动美术物件。
	plots.clear()
	if farm_model != null:
		farm_model.clear_plot_specs()
	var seen := {}
	for node in get_tree().get_nodes_in_group("farm_plots"):
		if node.plot_id.is_empty() or seen.has(node.plot_id):
			push_error("菜箱必须使用唯一 plot_id：" + str(node.get_path()))
			continue
		seen[node.plot_id] = true
		node.farm_model = farm_model
		plots.append(node)
		if farm_model != null:
			farm_model.register_plot({"id": node.plot_id, "zone": node.zone_id,
				"name": node.plot_name, "requires_site": node.requires_site,
				"requires_level": node.requires_level})
		if not node.acted.is_connected(_on_acted):
			node.acted.connect(_on_acted)



func _on_acted(plot_id: String, event: String, payload: Dictionary) -> void:
	acted.emit(plot_id, event, payload)


func find(plot_id: String) -> Node3D:
	for p in plots:
		if p.plot_id == plot_id:
			return p
	return null
