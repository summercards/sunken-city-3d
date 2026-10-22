@tool
extends Node3D
## 独立种植床；六个子地格是场景实例，保存各自状态。
@export var plot_id := ""
@export var zone_id := ""
@export var plot_name := "种植床"
@export var requires_site := ""
@export var requires_level := 0

func _enter_tree() -> void:
	add_to_group("farm_beds")
	var i := 0
	for cell in get_children():
		if not cell.has_method("setup"):
			continue
		# 第 1 格保留原菜箱 ID，旧存档可原位迁移。
		cell.plot_id = plot_id if i == 0 else "%s:%d" % [plot_id, i]
		cell.zone_id = zone_id
		cell.plot_name = "%s · %d" % [plot_name, i + 1]
		cell.requires_site = requires_site
		cell.requires_level = requires_level
		i += 1
