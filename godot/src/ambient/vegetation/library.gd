@tool
extends RefCounted
## Imported geometry and materials have one shared cache, never per-blade copies.
const CATALOG := "res://data/vegetation/catalog.json"
static var _meshes := {}
static var _catalog := {}
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		if not FileAccess.file_exists(CATALOG):
			return {}
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(CATALOG)) != OK or not json.data is Dictionary:
			return {}
		_catalog = json.data
	return _catalog
static func mesh(key: String) -> Mesh:
	if not _meshes.has(key):
		var entry: Variant = catalog().get(key)
		if not entry is Dictionary or not entry.get("model") is String:
			return null
		var path: String = entry.model
		if path.is_empty():
			return null
		if path.get_extension().to_lower() in ["glb", "gltf"] and FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".import"):
			return null
		if not ResourceLoader.exists(path, "PackedScene"):
			return null
		# 源文件和 .import 存在不代表导入产物可用；先检查，避免无谓的加载错误日志。
		if FileAccess.file_exists(path + ".import"):
			var imported := ConfigFile.new()
			if imported.load(path + ".import") != OK:
				return null
			var imported_path: Variant = imported.get_value("remap", "path", "")
			if imported.get_value("remap", "type", "") != "PackedScene" or not imported_path is String:
				return null
			if imported_path.is_empty() or not FileAccess.file_exists(imported_path):
				return null
		var packed := load(path) as PackedScene
		if packed == null or not packed.can_instantiate():
			return null
		var source := packed.instantiate()
		if source == null:
			return null
		var found := source.find_children("*", "MeshInstance3D", true, false)
		var result: Mesh = null
		if found.size() == 1:
			result = found[0].mesh
		source.free()
		if result == null:
			return null
		_meshes[key] = result
	return _meshes[key] as Mesh
static func material(key: String) -> Material:
	return load(catalog()[key].material)
