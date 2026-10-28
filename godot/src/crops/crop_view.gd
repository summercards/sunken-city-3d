@tool
extends Node3D
class_name CropView
## 作物表现装配器：按品种加载 `scenes/crops/<id>.tscn`，按阶段切 visible。
##
## 它只读品种定义与阶段索引，不持有生长状态、不推进时间。状态仍归 SEA-FARM。
## 地格视图（farm_plot.gd）只负责木箱与交互，作物形状全部由本节点承担。
##
## 规则见 docs/features/crop/spec.md SEA-CROP-R03 / R04 / R07。

const StageDef = preload("res://src/crops/crop_stage.gd")
const Catalog = preload("res://src/crops/crop_catalog.gd")

signal crop_changed(crop_id: String)
signal stage_changed(stage: int)

## 编辑器里预览的品种与阶段；运行时由 setup/show_crop 覆盖。
@export var preview_crop := "lettuce"
@export_range(0, 3) var preview_stage := 3

var _crop_id := ""
var _stage := -1
var _shown_stage := -1
var _dry := false
var _models := {}
var _stages: Array = []
var _tints := {}
var _warned := false
var _catalog = null


func _ready() -> void:
	if Engine.is_editor_hint():
		show_crop(preview_crop)
		set_stage(preview_stage)


func current_crop() -> String:
	return _crop_id


func current_stage() -> int:
	return _stage


## 切换到某品种。空 id 表示清空；未知品种保留现有内容并告警一次。
func show_crop(crop_id: String) -> void:
	if crop_id == _crop_id and _models.has(crop_id):
		return
	if crop_id == "":
		_clear()
		return
	if not _models.has(crop_id):
		var node := _instantiate(crop_id)
		if node == null:
			_warn_once("作物模型缺失：" + crop_id + "，保留当前显示")
			return
		_models[crop_id] = node
		add_child(node)
	var previous := _current_root()
	for id in _models:
		_models[id].visible = (id == crop_id)
	_crop_id = crop_id
	if _current_root() != previous:
		_stages.clear()
		_tints.clear()
		_shown_stage = -1
	crop_changed.emit(crop_id)
	_apply_stage(_stage if _stage >= 0 else 0)


## 只改可见性，不销毁、不缩放（SEA-CROP-R03）。
func set_stage(index: int) -> void:
	if not StageDef.is_valid(index):
		_warn_once("非法阶段索引：" + str(index))
		return
	_stage = index
	_apply_stage(index)
	stage_changed.emit(index)


## 缺水不改阶段，只压黄压暗，与「缺水只停长」一致。
func set_dry(dry: bool) -> void:
	if dry == _dry:
		return
	_dry = dry
	_apply_tint()


func _apply_stage(index: int) -> void:
	var root := _current_root()
	if root == null:
		return
	if _stages.is_empty():
		for i in StageDef.count():
			var node := root.get_node_or_null(StageDef.node_name(i))
			if node != null:
				_stages.append(node)
	if index >= _stages.size():
		_warn_once("作物 %s 缺少阶段节点 %s，保留上一阶段" % [_crop_id, StageDef.node_name(index)])
		# 缺阶段时退回到已存在的最后一个阶段，而不是留空箱。
		if _stages.is_empty():
			return
		index = _stages.size() - 1
	for i in _stages.size():
		_stages[i].visible = (i == index)
	_shown_stage = index
	_apply_tint()


func _apply_tint() -> void:
	var target := Color(0.82, 0.78, 0.52)
	for mesh in _collect_meshes():
		if not _dry:
			# 解除缺水回到资产自带材质，不保留任何 override。
			mesh.material_override = null
			continue
		if not _tints.has(mesh):
			var source = mesh.get_active_material(0)
			if source == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				source = mesh.mesh.surface_get_material(0)
			if source == null:
				continue
			var tinted = source.duplicate()
			_tints[mesh] = {"tinted": tinted, "tintable": tinted is BaseMaterial3D}
		var entry: Dictionary = _tints[mesh]
		if not bool(entry.tintable):
			continue
		var mat = entry.tinted
		mat.albedo_color = target
		mesh.material_override = mat


func _collect_meshes() -> Array:
	var out: Array = []
	var root := _current_root()
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is MeshInstance3D:
			out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _current_root() -> Node3D:
	if _crop_id == "":
		return null
	return _models.get(_crop_id, null)


func _instantiate(crop_id: String) -> Node3D:
	if _catalog == null:
		_catalog = Catalog.new()
		_catalog.reload()
	var path: String = str(_catalog.model_scene(crop_id))
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		return null
	var node = packed.instantiate()
	if not (node is Node3D):
		node.queue_free()
		return null
	return node


func _clear() -> void:
	for id in _models:
		_models[id].queue_free()
	_models.clear()
	_stages.clear()
	_tints.clear()
	_crop_id = ""
	_stage = -1
	_shown_stage = -1


func _warn_once(message: String) -> void:
	if _warned:
		return
	_warned = true
	push_warning("[crop] " + message)
