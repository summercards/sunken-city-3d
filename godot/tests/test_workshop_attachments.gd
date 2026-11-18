extends SceneTree

const Data = preload("res://addons/building_workshop/attachment_work_data.gd")
const Store = preload("res://addons/building_workshop/editor_store.gd")
const HouseRecipe = preload("res://src/workshop/recipe.gd")
const HouseCatalog = preload("res://src/workshop/catalog.gd")
const Recipe = preload("res://src/building_attachments/recipe.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const BASE := "res://outputs/workshop_editor/attachment_logic"
const FILES := ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json", "building.attachments.json", "building.attachments.tscn", "building.work.tscn"]
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []

class FailingStore extends "res://addons/building_workshop/editor_store.gd":
	var fail_file := ""
	var fail_after_write := false
	func _write_json(path: String, value: Dictionary) -> bool:
		if path.get_file() == fail_file and not fail_after_write: return false
		var result := super._write_json(path, value)
		return false if path.get_file() == fail_file else result

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	rows.append({"label": label, "passed": value, "mode": "direct_call"})
	if not value:
		failures.append(label)
		printerr("FAIL [workshop-attachments] ", label)

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		quit(1)
		return
	var empty: Dictionary = Data.empty_snapshot()
	check(Data.validate(empty).is_empty(), "空外挂快照合法")
	var layer := Node3D.new()
	layer.name = "Attachments"
	for type_id: String in ["sign_fascia", "tank_tower_cone"]:
		var recipe: Dictionary = Recipe.defaults(type_id)
		recipe.condition = "damaged"
		if type_id == "sign_fascia": recipe.text = "SEA CAFE"
		var built: Dictionary = Generator.build(recipe)
		check(built.ok, "可信原生生成：" + type_id)
		if not built.ok: continue
		var node: Node3D = built.root
		node.name = type_id
		node.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(7.0)), Vector3(1.234567, 2.345678, -3.456789))
		node.set_meta("sea_attachment", {"schema_version": 1, "instance_id": type_id, "instanceid": type_id, "recipe": recipe.duplicate(true), "host_path": ".", "anchor": {"mode": "wall" if type_id == "sign_fascia" else "roof", "mesh_path": "GeneratedVisual/structure_union", "surface": 0, "triangle": 0, "host_position": [0.0, 2.0, 0.0], "host_normal": [0.0, 0.0, 1.0], "local_position": built.mount_anchor.position.duplicate(), "native": built.mount_anchor.duplicate(true), "declared_clearance_m": 0.012, "offset_m": 0.03, "angle_degrees": 7.0}, "stats": built.stats.duplicate(true)})
		layer.add_child(node)
	var snapshot: Dictionary = Data.capture(layer)
	check(Data.validate(snapshot).is_empty(), "两类型可信安装快照合法")
	var rebuilt: Dictionary = Data.build(snapshot)
	check(rebuilt.ok, "快照重新原生生成")
	if rebuilt.ok:
		check(Data.fingerprint(Data.capture(rebuilt.root)) == Data.fingerprint(snapshot), "变换及英文原文无损roundtrip")
		check(static_owned(rebuilt.root, rebuilt.root), "原生静态节点无脚本且owner完整")
		rebuilt.root.free()
	test_invalid(snapshot)
	await process_frame
	test_store(snapshot)
	test_store(empty)
	layer.free()
	var report := {"suite": "workshop-attachments", "checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Data及EditorStore逻辑；仅sign_fascia/tank_tower_cone，不重跑96素材", "automatic_gui": [], "direct_call": rows, "real_rendering": "未执行", "expected_failures": [], "exit_code": 0 if failures.is_empty() else 1}
	write_text("res://outputs/workshop_attachments_logic_report.json", JSON.stringify(report, "\t"))
	print("[workshop-attachments] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_invalid(snapshot: Dictionary) -> void:
	var cases: Dictionary = {}
	var bad := snapshot.duplicate(true)
	bad.schema_version = 2
	cases.future = bad
	bad = snapshot.duplicate(true)
	bad.instances.append(bad.instances[0].duplicate(true))
	cases.duplicate = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].transform[9] = INF
	cases.nonfinite = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment.anchor = {"mode": "not_a_surface", "local_position": ["bad"]}
	cases.malformed_anchor = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment = false
	cases.false_metadata = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment.script = "res://outputs/never_execute.gd"
	cases.script_reference = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment.scene_path = "res://outputs/never_execute.tscn"
	cases.bad_scene = bad
	for key: String in cases:
		check(not Data.validate(cases[key]).is_empty(), "拒绝非法快照：" + key)
		var built: Dictionary = Data.build(cases[key])
		check(not built.ok and built.root == null, "非法快照不构造节点：" + key)
		if built.get("root") != null: built.root.free()

func test_store(snapshot: Dictionary) -> void:
	var store := Store.new()
	var recipe: Dictionary = HouseRecipe.authoring_defaults()
	recipe.building_id = "attachment_empty" if snapshot.instances.is_empty() else "attachment_logic"
	recipe.floors = 1
	var catalog: Dictionary = HouseCatalog.definitions().duplicate(true)
	var saved: Dictionary = store.export_work_revision(recipe, catalog, snapshot, BASE)
	check(saved.ok, "新作品八件原子保存：" + str(saved.get("reason", "")))
	if not saved.ok:
		var parser := JSON.new()
		parser.parse(JSON.stringify(snapshot, "\t"))
		print("[workshop-attachments-diagnostic] JSON差异 ", JSON.stringify(json_differences(snapshot, parser.data)))
		return
	var directory := str(saved.directory)
	var original := file_hashes(directory)
	check(original.size() == 8, "revision恰好固定八件")
	var loaded: Dictionary = store.load_recipe(saved.recipe_path)
	check(loaded.ok, "完整作品重新打开：" + str(loaded.get("reason", "")))
	if loaded.ok:
		check(Data.fingerprint(loaded.attachments_snapshot) == Data.fingerprint(snapshot), "JSON姿态与文本严格往返一致")
		check(not loaded.recipe.has("attachments") and not loaded.recipe.has("attachment_snapshot"), "外挂不进入房屋Recipe")
	var wrapper := FileAccess.get_file_as_string(saved.work_scene_path)
	check(not wrapper.contains(".tmp") and not wrapper.contains("res://") and not wrapper.contains("/Users/"), "wrapper只用同目录相对引用")
	var packed := ResourceLoader.load(saved.work_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(packed != null, "最终目录wrapper真实重载")
	if packed != null:
		var root := packed.instantiate()
		check(root.get_child_count() == 2 and root.has_node("Asset") and root.has_node("Attachments"), "wrapper原生双层")
		var attachments := root.get_node("Attachments") as Node3D
		attachments.scene_file_path = ""
		check(store._static_snapshot_matches(Data.capture(attachments), snapshot), "静态场景姿态和英文一致")
		check(root.find_children("*", "CollisionShape3D", true, false).size() > 0, "保存作品保留真实碰撞")
		check(no_scripts(root), "重开作品全树无重建脚本")
		root.free()
	for fail_file: String in ["building.recipe.json", "catalog_snapshot.json", "building.attachments.json", "candidate_manifest.json", "ledger.json"]:
		for after: bool in [false, true]:
			var failing := FailingStore.new()
			failing.fail_file = fail_file
			failing.fail_after_write = after
			var result: Dictionary = failing.export_work_revision(recipe, catalog, snapshot, BASE)
			check(not result.ok, "注入写失败拒绝：%s/%s" % [fail_file, after])
			check(DirAccess.get_directories_at(directory.get_base_dir()) == PackedStringArray(["revision_0001"]), "失败清理八件且不留最新半revision：%s/%s" % [fail_file, after])
			check(file_hashes(directory) == original, "失败不覆盖旧版：%s/%s" % [fail_file, after])
	var manifest_path := directory.path_join("candidate_manifest.json")
	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var manifest: Dictionary = JSON.parse_string(manifest_text)
	for name: String in ["building.attachments.json", "building.attachments.tscn", "building.work.tscn", "candidate_manifest.json"]:
		var path := directory.path_join(name)
		var old := FileAccess.get_file_as_bytes(path)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".held"))
		check(not store.load_recipe(saved.recipe_path).ok, "新作品缺文件必须拒绝：" + name)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".held"), ProjectSettings.globalize_path(path))
		write_text(path, "{bad json" if name.ends_with(".json") else "malformed scene that must never execute")
		check(not store.load_recipe(saved.recipe_path).ok, "新作品损坏文件必须拒绝：" + name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(old)
		file.close()
	var future := manifest.duplicate(true)
	future.schema_version = 999
	write_text(manifest_path, JSON.stringify(future))
	check(not store.load_recipe(saved.recipe_path).ok, "未来manifest不降级")
	write_text(manifest_path, manifest_text)
	var legacy_recipe := recipe.duplicate(true)
	legacy_recipe.building_id = str(recipe.building_id) + "_legacy"
	var legacy: Dictionary = store.export_revision(legacy_recipe, catalog, BASE)
	check(legacy.ok, "legacy五件仍可导出")
	if legacy.ok:
		var reopened: Dictionary = store.load_recipe(legacy.recipe_path)
		check(reopened.ok and reopened.attachments_snapshot.instances.is_empty(), "legacy仅五件合法为空外挂")
		write_text(str(legacy.directory).path_join("building.attachments.json"), JSON.stringify(snapshot))
		check(not store.load_recipe(legacy.recipe_path).ok, "legacy未声明旁车拒绝")
	check(file_hashes(directory) == original, "所有负例恢复后旧版八件字节不变")

func static_owned(node: Node, root: Node) -> bool:
	if node.get_script() != null or not node.scene_file_path.is_empty(): return false
	if node != root and node.owner != root: return false
	for child: Node in node.get_children():
		if not static_owned(child, root): return false
	return true

func no_scripts(node: Node) -> bool:
	if node.get_script() != null: return false
	for child: Node in node.get_children():
		if not no_scripts(child): return false
	return true

func file_hashes(directory: String) -> Dictionary:
	var hashes: Dictionary = {}
	for name: String in DirAccess.get_files_at(directory): hashes[name] = FileAccess.get_sha256(directory.path_join(name))
	return hashes

func json_differences(a: Variant, b: Variant, path: String = "snapshot") -> Array:
	var differences: Array = []
	if a is Dictionary and b is Dictionary:
		for key: Variant in a:
			differences.append_array(json_differences(a[key], b.get(key), path + "." + str(key)))
	elif a is Array and b is Array:
		for index: int in mini(a.size(), b.size()): differences.append_array(json_differences(a[index], b[index], path + "[%d]" % index))
	elif a != b:
		differences.append({"path": path, "before": str(a), "after": str(b), "delta": float(a) - float(b) if (a is float or a is int) and (b is float or b is int) else ""})
	return differences

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
