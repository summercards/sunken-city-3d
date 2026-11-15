@tool
extends RefCounted

const BuildingStore = preload("res://addons/building_workshop/editor_store.gd")
const PlantStore = preload("res://src/plant_authoring/store.gd")

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return {}
	return parser.data

static func describe(path: String, kind: String, animated: bool = false) -> Dictionary:
	if path.contains("..") or not path.begins_with("res://"): return {}
	var roots: Array = ["res://scenes/workshop_buildings/", "res://outputs/workshop_editor/"] if kind == "building" else ["res://scenes/workshop_plants/", "res://outputs/plant_editor/"] if kind == "plant" else []
	var allowed := false
	for root: String in roots:
		if path.begins_with(root): allowed = true
	if not allowed: return {}
	var recipe := read_json(path)
	if recipe.is_empty(): return {}
	var directory := path.get_base_dir()
	var scene := directory.path_join("building.tscn" if kind == "building" else "plant_wind.tscn" if animated else "plant.tscn")
	if not FileAccess.file_exists(scene): return {}
	return {"kind": kind, "recipe_path": path, "scene_path": scene,
		"preview_path": directory.path_join("building.tscn" if kind == "building" else "plant.tscn"),
		"manifest_path": directory.path_join("candidate_manifest.json" if kind == "building" else "plant.manifest.json"),
		"asset_id": str(recipe.get("building_id", directory.get_base_dir().get_file())),
		"label": str(recipe.get("display_name", recipe.get("name", directory.get_base_dir().get_file()))),
		"revision": directory.get_file(), "animated": animated,
		"purpose": str(recipe.get("spatial_profile", "visual_only")),
		"editable": kind != "building" or recipe.get("construction_mode", "modular_v1") == "shell_v2",
		"candidate_only": true}

static func collect() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw: Dictionary in BuildingStore.new().list_documents():
		var row := describe(str(raw.recipe_path), "building")
		if not row.is_empty(): rows.append(row)
	for root: String in ["res://outputs/plant_editor", "res://scenes/workshop_plants"]:
		for raw: Dictionary in PlantStore.new().list_recipes(root):
			for animated: bool in [false, true]:
				var row := describe(str(raw.recipe_path), "plant", animated)
				if not row.is_empty(): rows.append(row)
	return rows
