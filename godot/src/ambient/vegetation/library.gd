@tool
extends RefCounted
## Imported geometry and materials have one shared cache, never per-blade copies.
const CATALOG := "res://data/vegetation/catalog.json"
static var _meshes := {}
static var _catalog := {}
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		assert(FileAccess.file_exists(CATALOG), "Missing vegetation catalog in project")
		_catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	return _catalog
static func mesh(key: String) -> Mesh:
	if not _meshes.has(key):
		var packed: PackedScene = load(catalog()[key].model)
		var source := packed.instantiate()
		var found := source.find_children("*", "MeshInstance3D", true, false)
		assert(found.size() == 1, "Vegetation source must have one mesh: " + key)
		_meshes[key] = found[0].mesh
		source.free()
	return _meshes[key]
static func material(key: String) -> Material:
	return load(catalog()[key].material)
