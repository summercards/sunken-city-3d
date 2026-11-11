@tool
extends "res://src/workshop/store.gd"

const EDITOR_ROOT := "res://scenes/workshop_buildings"
const EDITOR_OUTPUT_ROOT := "res://outputs/workshop_editor"

func export_revision(recipe: Dictionary, catalog: Dictionary = {}, base_dir: String = EDITOR_ROOT) -> Dictionary:
	var reason := _validate_base_dir(base_dir)
	if not reason.is_empty():
		var result := _fail_result()
		result.reason = reason
		return result
	return super.export_revision(recipe, catalog, _editor_resource_path(base_dir))

func load_recipe(path: String) -> Dictionary:
	# 仍由父类强制读取同目录 catalog_snapshot.json，不回退到全局目录。
	return super.load_recipe(_editor_resource_path(path))

func list_documents(base_dir: String = EDITOR_ROOT) -> Array:
	if not _validate_base_dir(base_dir).is_empty():
		return []
	return super.list_documents(_editor_resource_path(base_dir))

func _validate_base_dir(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if not normalized.begins_with("res://") or _editor_resource_path(normalized).is_empty():
		return "编辑器候选根只允许 res://scenes/workshop_buildings 或 res://outputs/workshop_editor 子树"
	return ""

func _is_safe_recipe_path(path: String) -> bool:
	var normalized := _editor_resource_path(path)
	return not normalized.is_empty() and normalized.to_lower().ends_with(".recipe.json")

func _editor_resource_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.is_empty() or normalized.contains("..") or normalized.strip_edges() != normalized:
		return ""
	normalized = normalized.simplify_path().trim_suffix("/")
	for root in [EDITOR_ROOT, EDITOR_OUTPUT_ROOT]:
		var absolute := ProjectSettings.globalize_path(root).replace("\\", "/").simplify_path().trim_suffix("/")
		for prefix in [root, absolute]:
			var folded := normalized.to_lower()
			var folded_prefix := str(prefix).to_lower()
			if folded == folded_prefix:
				return root
			if folded.begins_with(folded_prefix + "/"):
				var suffix := normalized.substr(str(prefix).length())
				if suffix.contains(":"):
					return ""
				return str(root) + suffix
	return ""

func _catalog_is_valid(value: Dictionary) -> bool:
	var adapter = preload("res://addons/building_workshop/catalog_adapter.gd")
	var components: Variant = value.get("components", {})
	if not components is Dictionary:
		return false
	for component_id in components:
		var component: Variant = components[component_id]
		if component is Dictionary and str(component.get("kind", "")) == "prefab":
			var inspected: Dictionary = adapter.inspect_static_prefab(str(component.get("prefab", "")))
			if not bool(inspected.get("ok", false)):
				return false
	return super._catalog_is_valid(value)

func _make_manifest(recipe: Dictionary, catalog: Dictionary, build: Dictionary, revision: int, tree_snapshot: Dictionary, source_hashes: Dictionary) -> Dictionary:
	var manifest := super._make_manifest(recipe, catalog, build, revision, tree_snapshot, source_hashes)
	manifest["authoring_context"] = "editor"
	manifest["noMain"] = true
	manifest["candidate_ledger"] = "ledger.json"
	manifest["formal_registry_written"] = false
	var sources: Dictionary = {}
	for path in ["res://src/workshop/recipe.gd", "res://src/workshop/catalog.gd", "res://src/workshop/generator.gd", "res://src/workshop/mesh_builder.gd", "res://src/workshop/store.gd", "res://src/workshop/shell_geometry.gd", "res://src/workshop/shell_generator.gd", "res://src/workshop/architecture_config.gd", "res://src/workshop/shell_window_geometry.gd", "res://src/workshop/roof_edge_geometry.gd", "res://addons/building_workshop/editor_store.gd", "res://addons/building_workshop/catalog_adapter.gd", "res://data/workshop/catalog_v1.json", "res://data/workshop/standards_v1.json", "res://data/workshop/palette_cells_v1.json"]:
		sources[path] = _sha256_file(path)
	var components: Dictionary = catalog.get("components", {})
	for component_id in components:
		var component: Dictionary = components[component_id]
		if str(component.get("kind", "")) == "prefab":
			var path := str(component.get("prefab", ""))
			if path.begins_with("res://"):
				sources[path] = _sha256_file(path)
	manifest["authoring_source_hashes"] = sources
	return manifest
