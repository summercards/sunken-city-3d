@tool
extends Node3D
class_name BuildField
## 世界里的建造牌容器：从 `assets/data/build_sites.json` 生成。
##
## 表里只有「牌子立在哪」，费用与施工时长在 `Economy.SITES` 里——
## 一个管位置（资产），一个管规则（玩法），两边都不重复写。
##
## 旧实现没有这个节点：建造是面板里的一个按钮，世界里看不到任何东西。

signal work_started(id: String, name: String, seconds: float)
signal finished(id: String, level: int)

const BuildSiteLib = preload("res://scripts/core/build_site.gd")
const TABLE := "res://assets/data/build_sites.json"

var sites: Array = []


func _ready() -> void:
	# 编辑器里把牌子摆出来（运行时的 build() 由 main.gd 调）。
	if Engine.is_editor_hint() and get_child_count() == 0:
		build()


func build(path := TABLE) -> void:
	for c in get_children():
		c.queue_free()
	sites.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("找不到建造点表：%s" % path)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("建造点表格式不对：%s" % path)
		return
	for row in data.get("sites", []):
		if not (row is Dictionary):
			continue
		var node: Node3D = BuildSiteLib.new()
		node.setup(row)
		add_child(node)
		node.work_started.connect(_on_work_started)
		sites.append(node)
	if Engine.is_editor_hint():
		return
	if not Economy.site_work_finished.is_connected(_on_finished):
		Economy.site_work_finished.connect(_on_finished)


func _on_work_started(id: String, name: String, seconds: float) -> void:
	work_started.emit(id, name, seconds)


func _on_finished(id: String, level: int) -> void:
	finished.emit(id, level)


func find(id: String) -> Node3D:
	for s in sites:
		if s.site_id == id:
			return s
	return null


func zone_sites(zone_id: String) -> Array:
	var out: Array = []
	for s in sites:
		if s.zone_id == zone_id:
			out.append(s)
	return out
