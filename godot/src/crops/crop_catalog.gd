extends RefCounted
class_name CropCatalog
## 作物品种目录。SEA-CROP 的唯一数据入口。
##
## 规则层（SEA-FARM）只从这里取数值，表现层只从这里取模型路径。
## 没有节点、没有 Autoload、没有场景依赖，隔离测试可直接 new() + reload()。
##
## 规则见 docs/features/crop/spec.md SEA-CROP-R01 / R05 / R08。

const StageDef = preload("res://src/crops/crop_stage.gd")
const DEFAULT_TABLE := "res://assets/data/crops.json"
const ITEMS_TABLE := "res://assets/data/items.json"

var _crops: Dictionary = {}
var _order: Array = []
var _table_path := ""
var _error := ""

func reload(path := DEFAULT_TABLE) -> bool:
	_crops.clear()
	_order.clear()
	_table_path = path
	_error = ""
	if not FileAccess.file_exists(path):
		_error = "作物表不存在：" + path
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_error = "作物表不是对象：" + path
		return false
	for row in parsed.get("crops", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var id := str(row.get("id", ""))
		if id == "" or _crops.has(id):
			continue
		_crops[id] = row.duplicate(true)
		_order.append(id)
	if _crops.is_empty():
		_error = "作物表为空：" + path
		return false
	return true


func error() -> String:
	return _error


func table_path() -> String:
	return _table_path


func ids() -> Array:
	return _order.duplicate()


func count() -> int:
	return _order.size()


func has(crop_id: String) -> bool:
	return _crops.has(crop_id)


## 深副本：查询不得交出可写引用（与 Farm 的查询约定一致）。
func get_crop(crop_id: String) -> Dictionary:
	return _crops.get(crop_id, {}).duplicate(true)


func definitions() -> Dictionary:
	return _crops.duplicate(true)


func stage_labels(crop_id: String) -> Array:
	var labels = _crops.get(crop_id, {}).get("stage_labels", [])
	return labels.duplicate() if labels is Array else StageDef.DEFAULT_LABELS.duplicate()


func model_scene(crop_id: String) -> String:
	return str(_crops.get(crop_id, {}).get("model", ""))


func seed_of(crop_id: String) -> String:
	return str(_crops.get(crop_id, {}).get("seed", ""))


func produce_of(crop_id: String) -> String:
	return str(_crops.get(crop_id, {}).get("produce", ""))


func stage_for_progress(crop_id: String, progress: float, ready: bool) -> int:
	var crop: Dictionary = _crops.get(crop_id, {})
	var labels = crop.get("stage_labels", [])
	var total: int = labels.size() if labels is Array and labels.size() > 0 else StageDef.count()
	var index := StageDef.stage_for_progress(progress, ready)
	# 品种若只登记了更少的阶段，夹到可用范围内，但不得少于四阶段（由 validate 断言）。
	return clampi(index, 0, maxi(total - 1, 0))


## 品种自检：模型、四阶段标签、种子类别、产物一致。
## 返回人类可读的问题列表；空数组表示通过。供测试与契约脚本共用。
func validate() -> Array:
	var problems: Array = []
	var items := _load_items()
	for crop_id in _order:
		var crop: Dictionary = _crops[crop_id]
		for key in ["name", "seed", "produce", "model"]:
			if str(crop.get(key, "")) == "":
				problems.append("%s: 缺少 %s" % [crop_id, key])
		var labels = crop.get("stage_labels", [])
		if not (labels is Array) or labels.size() != StageDef.count():
			problems.append("%s: stage_labels 必须是 %d 项" % [crop_id, StageDef.count()])
		var model := str(crop.get("model", ""))
		if model != "" and not ResourceLoader.exists(model):
			# 未导入时 ResourceLoader 可能拿不到，退回文件存在性判断。
			if not FileAccess.file_exists(model):
				problems.append("%s: 模型场景不存在 %s" % [crop_id, model])
		var seed_id := str(crop.get("seed", ""))
		if not items.is_empty() and seed_id != "":
			if not items.has(seed_id):
				problems.append("%s: 种子 %s 不在物品表" % [crop_id, seed_id])
			elif str(items[seed_id].get("category", "")) != "seed":
				problems.append("%s: %s 不是 seed 类别" % [crop_id, seed_id])
		var produce_id := str(crop.get("produce", ""))
		if not items.is_empty() and produce_id != "" and not items.has(produce_id):
			problems.append("%s: 产物 %s 不在物品表" % [crop_id, produce_id])
		var yields = crop.get("yield", {})
		if yields is Dictionary and produce_id != "":
			for out_id in yields.keys():
				if str(out_id) != produce_id:
					problems.append("%s: yield 键 %s 与 produce %s 不一致" % [crop_id, str(out_id), produce_id])
	return problems


func _load_items() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(ITEMS_TABLE):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_TABLE))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for row in parsed.get("items", []):
		if typeof(row) == TYPE_DICTIONARY and row.has("id"):
			out[str(row.id)] = row
	return out
