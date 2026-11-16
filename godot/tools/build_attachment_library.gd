extends SceneTree
## 只由测试代理通过隔离runner安排；不加载Main、不改现有资源或登记。
## 首次构建写入96静态场景和快照；已有目标拒绝覆盖。

const Catalog = preload("res://src/building_attachments/catalog.gd")
const Recipe = preload("res://src/building_attachments/recipe.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const Store = preload("res://src/building_attachments/store.gd")
const LIBRARY := "res://scenes/components/facilities/building_attachments/v001"
var errors: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var destination: String = LIBRARY
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--attachment-library-out="):
			destination = argument.trim_prefix("--attachment-library-out=").trim_suffix("/")
	if destination.contains("..") or destination.contains("\\") or not (destination == LIBRARY or destination.begins_with("user://building_attachments/")):
		printerr("拒绝构建目标；仅正式v001库或隔离user://building_attachments子目录")
		quit(1)
		return
	var manifest_path: String = destination.path_join("library_manifest.json")
	if FileAccess.file_exists(manifest_path):
		printerr("正式库已存在；不可变构建拒绝覆盖：", manifest_path)
		quit(1)
		return
	var entries: Array[Dictionary] = Catalog.entries()
	if entries.size() != 32:
		printerr("冻结目录必须恰为32类型")
		quit(1)
		return
	# 先全量预检，避免遇到已有件时留下半批新产物。
	for entry: Dictionary in entries:
		for condition: String in Catalog.CONDITIONS:
			for extension: String in [".tscn", ".native.json", ".recipe.json"]:
				var target: String = destination.path_join(str(entry.type_id)).path_join(condition + extension)
				if FileAccess.file_exists(target):
					errors.append("拒绝覆盖已有产物：" + target)
	if not errors.is_empty():
		finish(destination, [], {})
		return
	var records: Array[Dictionary] = []
	var normalized_fingerprints: Dictionary = {}
	var fresh_fingerprints: Dictionary = {}
	var totals: Dictionary = {"variants": 0, "triangles": 0, "vertices": 0, "surfaces": 0, "mesh_nodes": 0, "collision_shapes": 0}
	for entry: Dictionary in entries:
		for condition: String in Catalog.CONDITIONS:
			var recipe: Dictionary = Recipe.defaults(entry.type_id)
			recipe.condition = condition
			var built: Dictionary = Generator.build(recipe)
			if not built.ok:
				errors.append("%s/%s：%s" % [entry.type_id, condition, built.reason])
				continue
			var root: Node3D = built.root
			var normalized: String = built.fingerprint.normalized_sha256
			if normalized_fingerprints.has(normalized):
				errors.append("归一化几何重复：%s/%s与%s" % [entry.type_id, condition, normalized_fingerprints[normalized]])
			normalized_fingerprints[normalized] = str(entry.type_id) + "/" + condition
			if condition == "fresh":
				fresh_fingerprints[entry.type_id] = built.fingerprint
			var folder: String = destination.path_join(str(entry.type_id))
			var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
			if mkdir_error != OK:
				errors.append("无法创建目录：" + folder)
				root.free()
				continue
			var packed := PackedScene.new()
			var error: Error = packed.pack(root)
			var scene_path: String = folder.path_join(condition + ".tscn")
			if error == OK:
				error = ResourceSaver.save(packed, scene_path)
			root.free()
			if error != OK:
				errors.append("静态场景保存失败：%s (%s)" % [scene_path, error])
				continue
			var native_path: String = folder.path_join(condition + ".native.json")
			var recipe_path: String = folder.path_join(condition + ".recipe.json")
			for pair: Array in [[native_path, built.snapshot], [recipe_path, recipe]]:
				var reason: String = Store.write_json(str(pair[0]), pair[1])
				if not reason.is_empty():
					errors.append(reason)
			var reloaded: PackedScene = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			if reloaded == null:
				errors.append("保存后独立重载失败：" + scene_path)
			else:
				var instance: Node = reloaded.instantiate()
				if not scriptfree(instance):
					errors.append("保存后层级含脚本：" + scene_path)
				instance.free()
			records.append({"type_id": entry.type_id, "condition": condition, "scene": scene_path, "native_geometry": native_path, "recipe": recipe_path, "sha256": {"scene": FileAccess.get_sha256(scene_path), "native_geometry": FileAccess.get_sha256(native_path), "recipe": FileAccess.get_sha256(recipe_path)}, "stats": built.stats, "mount_anchor": built.mount_anchor, "damage_description": entry.damage[condition], "stage": "baked_native_pending_visual_asset_registration"})
			totals.variants += 1
			for key: String in ["triangles", "vertices", "surfaces", "mesh_nodes", "collision_shapes"]:
				totals[key] += int(built.stats[key])
	finish(destination, records, {"totals": totals, "fresh_fingerprints": fresh_fingerprints})

func scriptfree(node: Node) -> bool:
	if node.get_script() != null:
		return false
	for child: Node in node.get_children():
		if not scriptfree(child):
			return false
	return true

func finish(destination: String, records: Array, summary: Dictionary) -> void:
	var success: bool = errors.is_empty() and records.size() == 96
	if success:
		var manifest: Dictionary = {"schema": "sea.building_attachments.library", "schema_version": 1, "generator_version": Generator.GENERATOR_VERSION, "type_count": 32, "variant_count": records.size(), "conditions": Catalog.CONDITIONS, "records": records, "summary": summary, "source": Store.source_manifest(), "shared_materials": Catalog.definitions().materials, "visual_review": "pending", "runtime_world_installation": false, "asset_registration": "pending", "blender_export": "native_json_snapshot_for_derived_source_only"}
		var reason: String = Store.write_json(destination.path_join("library_manifest.json"), manifest)
		if not reason.is_empty():
			errors.append(reason)
	for error: String in errors:
		printerr(error)
	print("ATTACHMENT_LIBRARY_RESULT ", JSON.stringify({"passed": errors.is_empty() and records.size() == 96, "variants": records.size(), "destination": destination, "summary": summary, "errors": errors, "real_rendering": "未执行"}))
	quit(0 if errors.is_empty() and records.size() == 96 else 1)
