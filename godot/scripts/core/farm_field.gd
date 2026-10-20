@tool
extends Node3D
class_name FarmField
## 世界里的菜箱容器：地块规格来自 `Economy.farm.specs`（读 plots.json 生成）。
##
## 位置是资产，状态与规则在 FarmModel；这里不重复读表，避免两处走偏。

signal acted(plot_id: String, event: String, payload: Dictionary)

const FarmPlotLib = preload("res://scripts/core/farm_plot.gd")

var plots: Array = []


func _ready() -> void:
	# 编辑器里不能读 Economy.farm（占位实例），直接按 plots.json 摆菜箱。
	if Engine.is_editor_hint() and get_child_count() == 0:
		_build_from_table("res://assets/data/plots.json")


func _build_from_table(path: String) -> void:
	for c in get_children():
		c.queue_free()
	plots.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	for row in data.get("plots", []):
		var node: Node3D = FarmPlotLib.new()
		node.setup(row)
		add_child(node)
		plots.append(node)


func build() -> void:
	for c in get_children():
		c.queue_free()
	plots.clear()
	if Economy.farm == null:
		push_error("种植模型未就绪")
		return
	for row in Economy.farm.specs:
		if not (row is Dictionary):
			continue
		var node: Node3D = FarmPlotLib.new()
		node.setup(row)
		add_child(node)
		node.acted.connect(_on_acted)
		plots.append(node)


func _on_acted(plot_id: String, event: String, payload: Dictionary) -> void:
	acted.emit(plot_id, event, payload)


func find(plot_id: String) -> Node3D:
	for p in plots:
		if p.plot_id == plot_id:
			return p
	return null
