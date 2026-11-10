extends SceneTree
## SEA-WORKSHOP 样例导出器。
## 只加载原生 Generator/Store 与纯配方 JSON，不实例化 Main 或任何主场景。

const Generator = preload("res://src/workshop/generator.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Store = preload("res://src/workshop/store.gd")

const SAMPLE_ROOT := "res://data/workshop/samples"
const OUTPUT_ROOT := "res://outputs/workshop_samples"
const REPORT_PATH := "res://outputs/workshop_samples_report.json"
const SAMPLE_IDS := ["workshop_sample_001", "workshop_sample_002"]
const REPORT_FILES := ["building.recipe.json", "building.tscn", "candidate_manifest.json", "catalog_snapshot.json", "ledger.json"]

var checks := 0
var failures: Array[String] = []
var samples: Array = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL [workshop-samples] ", message)

func read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed

func sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)

func normalized_build_result(raw: Dictionary) -> Dictionary:
	return {
		"ok": bool(raw.get("ok", false)),
		"root": raw.get("root", null) != null,
		"slots": raw.get("slots", []),
		"stats": raw.get("stats", {}),
		"walk": raw.get("walk", raw.get("walk_surfaces", [])),
		"water": raw.get("water", raw.get("water_blockers", [])),
		"warnings": raw.get("warnings", [])
	}

func export_sample(sample_id: String, catalog: Dictionary, store: Object) -> void:
	var recipe_path := SAMPLE_ROOT + "/" + sample_id + ".recipe.json"
	check(FileAccess.file_exists(recipe_path), sample_id + " 配方存在")
	if not FileAccess.file_exists(recipe_path):
		return
	var recipe_value: Variant = read_json(recipe_path)
	check(recipe_value is Dictionary, sample_id + " 配方为JSON对象")
	if not recipe_value is Dictionary:
		return
	var recipe: Dictionary = recipe_value as Dictionary
	check(str(recipe.get("building_id", "")) == sample_id, sample_id + " building_id匹配")

	var probe_raw: Dictionary = Generator.build(recipe, catalog)
	var probe := normalized_build_result(probe_raw)
	check(bool(probe.get("ok", false)), sample_id + " Generator.build ok")
	check(probe.has_all(["ok", "root", "slots", "stats", "walk", "water", "warnings"]), sample_id + " Generator.build API键齐全")
	var probe_root: Variant = probe_raw.get("root", null)
	if probe_root is Node:
		(probe_root as Node).free()
	if not bool(probe.get("ok", false)):
		return

	var exported: Dictionary = store.export_revision(recipe, catalog, OUTPUT_ROOT)
	check(bool(exported.get("ok", false)), sample_id + " Store.export_revision ok")
	if not bool(exported.get("ok", false)):
		return
	var directory := str(exported.get("directory", ""))
	check(not directory.is_empty(), sample_id + " 返回独立目录")
	var store_paths := {
		"directory": directory,
		"recipe": str(exported.get("recipe_path", directory + "/building.recipe.json")),
		"scene": str(exported.get("scene_path", directory + "/building.tscn")),
		"manifest": str(exported.get("manifest_path", directory + "/candidate_manifest.json")),
		"ledger": str(exported.get("ledger_path", directory + "/ledger.json")),
		"catalog": str(exported.get("catalog_path", directory + "/catalog_snapshot.json"))
	}
	check(store_paths.size() == 6 and store_paths.has_all(["directory", "recipe", "scene", "manifest", "ledger", "catalog"]), sample_id + " Store.export_revision API键齐全")
	var hashes: Dictionary = {}
	var paths: Dictionary = {}
	for file_name in REPORT_FILES:
		var path: String = directory + "/" + str(file_name)
		paths[file_name] = {
			"res_path": path,
			"filesystem_path": ProjectSettings.globalize_path(path)
		}
		check(FileAccess.file_exists(path), sample_id + " 输出 " + file_name)
		if FileAccess.file_exists(path):
			hashes[file_name] = sha256(path)
	check(hashes.size() == REPORT_FILES.size(), sample_id + " 输出文件全部有hash")
	check(str(recipe.get("shape", "")) == ("rectangle" if sample_id.ends_with("001") else "l"), sample_id + " shape契约")
	check(int(recipe.get("floors", 0)) == 3, sample_id + " floors契约")
	if sample_id.ends_with("001"):
		check(is_equal_approx(float(recipe.get("damage", -1.0)), 0.0), sample_id + " damage=0")
	else:
		check(is_equal_approx(float(recipe.get("damage", -1.0)), 0.45), sample_id + " damage=0.45")
		check(is_equal_approx(float(recipe.get("vegetation_density", -1.0)), 0.7), sample_id + " plants=0.7")
		check(str(recipe.get("component_bindings", {}).get("plant", "")) in ["plant_tree", "plant_vine"], sample_id + " plant为tree或vine")
	var manifest_value: Variant = read_json(directory + "/candidate_manifest.json")
	check(manifest_value is Dictionary, sample_id + " candidate manifest可读")
	if manifest_value is Dictionary:
		check(bool((manifest_value as Dictionary).get("static_scene", false)), sample_id + " static_scene=true")
		check(not bool((manifest_value as Dictionary).get("has_workshop_rebuild_script", true)), sample_id + " 无工坊重建脚本")
	samples.append({
		"building_id": sample_id,
		"display_name": recipe.get("display_name", sample_id),
		"directory": directory,
		"directory_filesystem_path": ProjectSettings.globalize_path(directory),
		"recipe": recipe,
		"generator": probe,
		"store_result": {
			"directory": directory,
			"recipe": str(exported.get("recipe_path", "")),
			"scene": str(exported.get("scene_path", "")),
			"manifest": str(exported.get("manifest_path", "")),
			"ledger": str(exported.get("ledger_path", "")),
			"catalog": str(exported.get("catalog_path", ""))
		},
		"paths": paths,
		"hashes": hashes
	})

func write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	var report := {
		"schema_version": 1,
		"runner": "workshop-samples",
		"marker": "workshop-samples",
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures.duplicate(),
		"samples": samples.duplicate(true),
		"generator_api": ["ok", "root", "slots", "stats", "walk", "water", "warnings"],
		"store_api": ["directory", "recipe", "scene", "manifest", "ledger", "catalog"],
		"native_godot_source": true,
		"main_scene_instantiated": false,
		"report_path": REPORT_PATH,
		"report_filesystem_path": ProjectSettings.globalize_path(REPORT_PATH)
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		failures.append("无法写入 " + REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var catalog := Catalog.definitions()
	check(not catalog.is_empty(), "Catalog definitions可读")
	check(Catalog.validate(catalog).is_empty(), "Catalog校验通过")
	var store := Store.new()
	for sample_id in SAMPLE_IDS:
		export_sample(sample_id, catalog, store)
	check(samples.size() == SAMPLE_IDS.size(), "两栋样例均独立导出")
	write_report()
	print("[workshop-samples] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
