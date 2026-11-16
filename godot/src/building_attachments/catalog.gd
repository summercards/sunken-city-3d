extends RefCounted
## 冻结目录唯一入口；返回深副本，UI不能修改共享定义。

const PATH := "res://data/building_attachments/catalog_v1.json"
const CONDITIONS := ["fresh", "damaged", "ruined"]
const STYLES := ["frame", "block", "marquee"]
const ROLES := ["SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission"]

static func definitions() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in definitions().get("entries", []):
		var copy: Dictionary = entry.duplicate(true)
		copy.dimension_bounds = {}
		for axis: String in ["width", "height", "depth"]:
			copy.dimension_bounds[axis] = {"min": float(copy.dimensions[axis]) * 0.75, "max": float(copy.dimensions[axis]) * 1.25}
		copy.scale_bounds = {"min": 0.75, "max": 1.25}
		copy.conditions = CONDITIONS.duplicate()
		copy.styles = STYLES.duplicate()
		result.append(copy)
	return result

static func get_entry(type_id: String) -> Dictionary:
	for entry: Dictionary in entries():
		if entry.type_id == type_id:
			return entry
	return {}

static func list(category: String = "", mount_mode: String = "") -> Array[Dictionary]:
	return search("", category, mount_mode)

static func search(query: String = "", category: String = "", mount_mode: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries():
		if not category.is_empty() and entry.category != category:
			continue
		if not mount_mode.is_empty() and entry.mount_mode != mount_mode and entry.mount_mode != "any":
			continue
		var searchable: String = str(entry.type_id) + " " + str(entry.name) + " " + str(entry.category)
		if query.is_empty() or searchable.to_lower().contains(query.to_lower()):
			result.append(entry)
	return result
