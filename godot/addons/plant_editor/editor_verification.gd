@tool
extends RefCounted

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Screen = preload("res://addons/plant_editor/editor_screen.gd")
const REPORT_PATH = "res://outputs/plant_editor_report.json"
const IMAGE_ROOT = "res://outputs/plant_editor_evidence"
const PRODUCTION = "/Users/zyq/work/sea/godot"

var _plugin: EditorPlugin
var _screen: Control
var _tree: SceneTree
var _checks: Array[Dictionary] = []
var _failures: Array[String] = []
var _artifacts: Array[String] = []
var _edited_root: Node
var _edited_state = ""
var _shared_hash = ""
var _building: Control
var _building_state = ""
var _draft_hashes: Dictionary = {}

static func run(plugin: EditorPlugin) -> void:
	if not Engine.is_editor_hint() or not OS.get_cmdline_user_args().has("--plant-editor-verify"):
		return
	var verifier = load("res://addons/plant_editor/editor_verification.gd").new()
	await verifier._execute(plugin)

func _check(label: String, passed: bool, detail: String = "") -> bool:
	_checks.append({"label": label, "ok": passed, "detail": detail})
	if not passed:
		_failures.append(label)
		printerr("[plant-editor-check] %s: %s" % [label, detail])
	return passed

func _execute(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_tree = plugin.get_tree()
	if not _protection():
		# 生产项目绝不写报告、草稿、配方，也不执行 UI 测试。
		print("[plant-editor] %d checks, %d failures" % [_checks.size(), _failures.size()])
		_tree.quit(1)
		return
	_screen = plugin.screen
	if not _check("插件主屏已进入编辑器树", is_instance_valid(_screen) and _screen.is_inside_tree()):
		_finish()
		return
	_edited_root = EditorInterface.get_edited_scene_root()
	_edited_state = _scene_state(_edited_root)
	_shared_hash = FileAccess.get_sha256(Screen.PALETTE.resource_path)
	for path in ["user://plant_authoring_draft.json", "user://building_workshop_editor/recovery.json"]:
		_draft_hashes[path] = _hash(path)
	_building = _find_building_screen(EditorInterface.get_editor_main_screen())
	_check("房屋插件实际主屏存在", is_instance_valid(_building))
	if is_instance_valid(_building):
		# 房屋主屏第一次显示会初始化预览和开口选择；完成初始化后再冻结双工坊隔离基线。
		EditorInterface.set_main_screen_editor("老王场景工坊")
		_building.set_screen_visible(true)
		await _frames(6)
		_building_state = JSON.stringify(_building.get_recovery(), "", true, true)
	EditorInterface.set_main_screen_editor("树木工坊")
	_plugin._make_visible(true)
	await _frames(4)
	_check("顶部独立主屏名称", str(_plugin._get_plugin_name()) == "树木工坊")
	_check("独立 World3D", _screen.preview.viewport.own_world_3d and _screen.preview.viewport.world_3d != _tree.root.world_3d)
	_check("主屏真实可见", _screen.is_visible_in_tree())
	await _test_species_and_images()
	await _test_sliders_and_failure()
	await _test_branch()
	await _test_palette()
	_test_dirty_and_recovery()
	_test_save_reload()
	await _test_wind_and_switch()
	await _test_compact()
	_screen.show_module(0)
	_screen.preview.set_view("perspective")
	_screen.preview.fit_model()
	_screen.preview.select_branch("")
	await _capture("editor_main_screen", EditorInterface.get_base_control().get_viewport())
	for path in ["res://addons/plant_editor/plugin.gd", "res://addons/plant_editor/editor_screen.gd", "res://addons/plant_editor/preview.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		_check("预览不写 shader global " + path.get_file(), not source.contains("global_shader_parameter_set"))
		_check("主屏不引用房屋或启动游戏 " + path.get_file(), not source.contains("res://addons/building_workshop/") and not source.contains("res://src/bootstrap/") and not source.contains("add_autoload_singleton"))
	_check("共享 PNG 哈希未变", _shared_hash == FileAccess.get_sha256(Screen.PALETTE.resource_path))
	_check("编辑场景未打开或修改", EditorInterface.get_edited_scene_root() == _edited_root and _scene_state(_edited_root) == _edited_state)
	if is_instance_valid(_building):
		_check("房屋配方预览草稿未污染", JSON.stringify(_building.get_recovery(), "", true, true) == _building_state)
	for path in _draft_hashes:
		_check("验证不写草稿 " + path, _hash(path) == _draft_hashes[path])
	_finish()

func _protection() -> bool:
	var args = OS.get_cmdline_args()
	var cli = args.has("--editor") and not args.has("--script") and not args.has("-s")
	_check("真实 editor 参数", cli, str(args))
	var copy = ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var isolated = copy != PRODUCTION and not copy.begins_with(PRODUCTION + "/") and copy != "D:/projects/sea/godot"
	_check("拒绝生产项目写入", isolated, copy)
	var no_autoload = true
	for property: Dictionary in ProjectSettings.get_property_list():
		if str(property.name).begins_with("autoload/"):
			no_autoload = false
	_check("minimal 副本无 Autoload", no_autoload)
	var no_main = str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty()
	_check("minimal 副本无 Main 入口", no_main)
	var enabled = PackedStringArray(ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()))
	var both = enabled.size() == 2 and enabled.has("res://addons/plant_editor/plugin.cfg") and enabled.has("res://addons/building_workshop/plugin.cfg")
	_check("只启用两套独立工坊", both, str(enabled))
	var safe_tree = true
	for node: Node in _tree.root.find_children("*", "", true, false):
		var script = node.get_script() as Script
		if node.name == &"Main" or (script != null and script.resource_path.begins_with("res://src/bootstrap/")):
			safe_tree = false
	_check("编辑器树无游戏 Main", safe_tree)
	return cli and isolated and no_autoload and no_main and both and safe_tree

func _test_species_and_images() -> void:
	var fingerprints: Array[String] = []
	for species in Recipe.SPECIES:
		var result: Dictionary = _screen.new_document(species)
		_check("物种实际生成 " + species, bool(result.get("ok", false)) and is_instance_valid(_screen.preview.model))
		_check("物种非空叶片与网格 " + species, int(result.get("stats", {}).get("leaf_count", 0)) > 0 and int(result.get("stats", {}).get("triangles", 0)) > 100)
		fingerprints.append(_mesh_hash(_screen.preview.model))
		_screen.preview.set_view("perspective")
		await _frames(4)
		_screen.preview.fit_model()
		_screen.preview.select_branch("")
		await _capture(species + "_whole", _screen.preview.viewport)
		var example: Dictionary = _screen.snapshot()
		example.name = "example_" + species
		var saved_example: Dictionary = _screen.store.save(example)
		_check("三树种可直接使用的静态候选 " + species, bool(saved_example.get("ok", false)), saved_example.get("reason", ""))
		if bool(saved_example.get("ok", false)):
			_artifacts.append(saved_example.scene_path)
			_artifacts.append(saved_example.recipe_path)
	_check("三种实际模型几何不同", fingerprints.size() == 3 and fingerprints[0] != fingerprints[1] and fingerprints[1] != fingerprints[2] and fingerprints[0] != fingerprints[2])
	_screen.new_document("camphor")
	_screen.show_module(2)
	_screen.controls.leaves_visible.button_pressed = false
	var bare: Dictionary = _screen.flush_pending()
	_check("裸枝实际生成", bool(bare.get("ok", false)) and _screen.preview.model.get_node("Leaves").get_child_count() > 0 and not _screen.snapshot().leaves_visible)
	_screen.preview.fit_model()
	await _capture("bare_branches", _screen.preview.viewport)
	_screen.controls.leaves_visible.button_pressed = true
	_screen.flush_pending()
	var branch: Dictionary = _screen.preview.branches[0]
	var leaf_node: Node3D = _screen.preview.model.get_node(branch.leaf_node_path)
	var foliage: MeshInstance3D = leaf_node.get_node("Foliage")
	var arrays: Array = foliage.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 取第一个真实叶片的近邻包络，不以整枝截图冒充叶片近景。
	var point: Vector3 = leaf_node.position + vertices[mini(30, vertices.size() - 1)]
	_screen.preview.focus_bounds(AABB(point - Vector3.ONE * 0.5, Vector3.ONE))
	await _capture("leaf_close", _screen.preview.viewport)
	_screen.show_module(3)
	_screen.controls.moss_amount.value = 0.9
	_screen.controls.vine_count.value = 5
	_screen.flush_pending()
	var moss: MeshInstance3D = _screen.preview.model.get_node_or_null("Moss/AttachedPatches")
	_check("苔藓实际网格", moss != null and moss.mesh != null)
	_check("藤蔓实际路径网格", _screen.preview.model.get_node("Vines").get_child_count() == 5)
	if moss != null:
		_screen.preview.focus_bounds(moss.mesh.get_aabb().grow(0.2))
	await _capture("epiphyte_close", _screen.preview.viewport)

func _test_sliders_and_failure() -> void:
	_screen.new_document("camphor")
	_screen.show_module(0)
	var baseline: Dictionary = _screen.snapshot()
	var original_mesh = _mesh_hash(_screen.preview.model)
	var slider: HSlider = _screen.controls.height
	var camera_transform: Transform3D = _screen.preview.camera.transform
	slider.drag_started.emit()
	slider.value = 8.0
	await _tree.create_timer(0.24).timeout
	_check("160ms 自动 debounce 更新配方", is_equal_approx(float(_screen.snapshot().height), 8.0))
	_check("滑条真实改变网格", original_mesh != _mesh_hash(_screen.preview.model))
	slider.value = 8.6
	await _tree.create_timer(0.24).timeout
	slider.value = 9.0
	slider.drag_ended.emit(true)
	_check("同拖动成功到最终值", is_equal_approx(float(_screen.snapshot().height), 9.0))
	_check("重建保留摄像头", camera_transform.is_equal_approx(_screen.preview.camera.transform))
	_screen.buttons.undo.pressed.emit()
	_check("单次拖动一次撤销", Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(baseline) and not _screen.session.can_undo())
	_screen.buttons.redo.pressed.emit()
	_check("单次拖动重做", is_equal_approx(float(_screen.snapshot().height), 9.0))
	var successful: Dictionary = _screen.snapshot()
	var model_id: int = _screen.preview.model.get_instance_id()
	_screen.controls.branch_start.value = 15.0
	await _tree.create_timer(0.24).timeout
	_check("失败保留当前输入", is_equal_approx(_screen.controls.branch_start.value, 15.0) and is_equal_approx(float(_screen.input_recipe.branch_start), 15.0))
	_check("失败保留成功配方与同一模型", Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(successful) and _screen.preview.model.get_instance_id() == model_id)
	_check("错误单行有详情", _screen.status.text.begins_with("未应用") and _screen.details.contains("branch_start"))
	_screen.controls.branch_start.value = 3.0
	await _tree.create_timer(0.24).timeout
	_check("纠正输入恢复预览", is_equal_approx(float(_screen.snapshot().branch_start), 3.0) and not _screen.has_pending_fields())
	_screen.new_document("camphor")
	var seed_slider: HSlider = _screen.controls.seed
	_check("seed 完整 UI 范围", seed_slider.min_value == 0 and seed_slider.max_value == 999999 and seed_slider.step == 1)
	seed_slider.value = 0
	_screen.flush_pending()
	var zero_hash = _mesh_hash(_screen.preview.model)
	seed_slider.value = 999999
	_screen.flush_pending()
	_check("seed 上下限实际生成不同网格", int(_screen.snapshot().seed) == 999999 and zero_hash != _mesh_hash(_screen.preview.model))
	_screen.buttons.reroll.pressed.emit()
	_check("重抽 seed 实际改变", int(_screen.snapshot().seed) >= 0 and int(_screen.snapshot().seed) <= 999999 and int(_screen.snapshot().seed) != 999999)
	_screen.buttons.undo.pressed.emit()
	_check("seed 可撤销", int(_screen.snapshot().seed) == 999999)
	for key in Recipe.RANGES:
		var ui_key: String = "branch_" + str(key) if Recipe.OVERRIDE_KEYS.has(key) else str(key)
		_check("数字仅 HSlider " + str(key), _screen.controls.get(ui_key) is HSlider)

func _test_branch() -> void:
	_screen.new_document("camphor")
	_screen.show_module(1)
	_screen.select_branch("branch_00")
	_check("独立 branch ID 选择并高亮", _screen.preview.selected_id == "branch_00" and _screen.preview.selection_visible())
	var branch: Dictionary = _screen.preview.branches[0]
	var old_wood = _mesh_hash(_screen.preview.model.get_node(branch.node_path))
	var old_leaves = _mesh_hash(_screen.preview.model.get_node(branch.leaf_node_path))
	_screen.controls.branch_length_scale.value = 1.5
	_screen.controls.branch_radius_scale.value = 1.4
	_screen.controls.branch_angle_offset.value = 0.4
	_screen.flush_pending()
	_check("每枝长度粗度角度进入配方", _screen.snapshot().branch_overrides.branch_00.size() == 3)
	_check("枝与叶真实一起变化", _mesh_hash(_screen.preview.model.get_node(branch.node_path)) != old_wood and _mesh_hash(_screen.preview.model.get_node(branch.leaf_node_path)) != old_leaves)
	_screen.controls.branch_enabled.button_pressed = false
	_screen.flush_pending()
	_check("隐藏选枝连同叶片", _screen.preview.model.get_node(branch.node_path).get_child_count() == 0 and _screen.preview.model.get_node(branch.leaf_node_path).get_child_count() == 0)
	_screen.controls.branch_enabled.button_pressed = true
	_screen.flush_pending()
	_screen.preview.fit_model()
	await _frames(2)
	var first: Dictionary = _screen.preview.branches[0]
	var point: Vector2 = _screen.preview.camera.unproject_position(first.bounds.get_center())
	var picked: String = _screen.preview.pick_branch(point)
	_check("摄像头射线点击选择实际分枝", not picked.is_empty() and _screen.selected_branch == picked and _screen.preview.selection_visible())

func _test_palette() -> void:
	_screen.new_document("camphor")
	_screen.show_module(4)
	_check("公共 PNG 64 色 8×8", _screen.palette_buttons.size() == 64 and _screen.palette_colors.size() == 64)
	for index in 64:
		_screen.palette_buttons[index].pressed.emit()
		var result: Dictionary = _screen.flush_pending()
		_check("色格实际应用 %02d" % index, bool(result.get("ok", false)) and int(_screen.snapshot().trunk_cell) == index and _screen.snapshot().color_mode == "manual")
		var wood: MeshInstance3D = _screen.preview.model.get_node("Trunk/MainTrunk")
		var arrays = wood.mesh.surface_get_arrays(0)
		var uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][0]
		_check("色格真实 UV %02d" % index, int(floor(uv.x * 8)) + int(floor(uv.y * 8)) * 8 == index)
	for role in ["leaf", "moss", "vine"]:
		var index: int = ["trunk", "leaf", "moss", "vine"].find(role)
		_screen._color_target.select(index)
		_screen.palette_buttons[42 + index].pressed.emit()
		_screen.flush_pending()
		_check("独立颜色目标 " + role, int(_screen.snapshot()[role + "_cell"]) == 42 + index)
	await _capture("manual_palette", _screen.preview.viewport)

func _test_dirty_and_recovery() -> void:
	var before: String = Recipe.fingerprint(_screen.snapshot())
	_screen.buttons.maple.pressed.emit()
	_check("脏文档切物种必须确认", _screen._confirm.visible and Recipe.fingerprint(_screen.snapshot()) == before)
	_screen._confirm.canceled.emit()
	_screen._confirm.hide()
	_check("取消切物种保留原文档", Recipe.fingerprint(_screen.snapshot()) == before)
	_screen.request_open("res://outputs/plant_editor/missing/revision_0001/plant.recipe.json")
	_check("脏文档载入必须确认", _screen._confirm.visible and Recipe.fingerprint(_screen.snapshot()) == before)
	_screen._confirm.canceled.emit()
	_screen._confirm.hide()
	var recovery: Dictionary = _screen.get_recovery()
	var result: Dictionary = _screen.restore_recovery(recovery)
	_check("公开草稿接口恢复", bool(result.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == before)
	var invalid: Dictionary = _screen.open_recipe("res://outputs/plant_editor/missing/revision_0001/plant.recipe.json")
	_check("坏路径不替换文档", not bool(invalid.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == before)

func _test_save_reload() -> void:
	_screen.new_document("camphor")
	_screen.show_module(5)
	var edit: LineEdit = _screen.controls.name
	edit.text = "plant_editor_verify_%s" % str(Time.get_ticks_usec())
	edit.text_changed.emit(edit.text)
	_screen.flush_pending()
	var first: Dictionary = _screen.save_recipe()
	if not _check("保存第一版", bool(first.get("ok", false)), str(first.get("reason", ""))):
		return
	var hashes: Dictionary = {}
	for key in ["recipe_path", "scene_path", "manifest_path"]:
		hashes[key] = _hash(first[key])
	_screen.controls.height.value = 8.1
	_screen.flush_pending()
	var expected: String = Recipe.fingerprint(_screen.snapshot())
	var second: Dictionary = _screen.save_recipe()
	if not _check("保存第二版", bool(second.get("ok", false)), str(second.get("reason", ""))):
		return
	_check("连续版本路径不覆盖", first.directory != second.directory and int(second.revision) > int(first.revision))
	for key in hashes:
		_check("旧版本不可变 " + key, hashes[key] == _hash(first[key]))
	var loaded: Dictionary = _screen.open_recipe(second.recipe_path)
	_check("新版本实际配方重载", bool(loaded.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == expected and not _screen.session.is_dirty())
	var packed = ResourceLoader.load(second.scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	_check("保存静态场景可重载", packed != null)
	if packed != null:
		var root = packed.instantiate()
		_check("导出不含任何预览业务节点", _static_tree(root))
		_check("导出与预览相同实际几何", _same_geometry(root, _screen.preview.model))
		root.free()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(second.manifest_path))
	_check("候选 manifest 不登记 Main", manifest is Dictionary and manifest.get("noMain", false) and not manifest.get("formal_registry_written", true))
	_screen.refresh_files()
	_check("文件页显示两版本配方列表", _screen._file_rows.size() >= 2)
	var original_root: String = _screen.export_root
	_screen.export_root = "res://scenes/workshop_plants"
	var scene_export: Dictionary = _screen.save_recipe()
	_check("独立场景根导出可用且不接入房屋", bool(scene_export.get("ok", false)) and str(scene_export.get("scene_path", "")).begins_with("res://scenes/workshop_plants/"), scene_export.get("reason", ""))
	_screen.export_root = original_root

func _test_wind_and_switch() -> void:
	_screen.preview.set_active(true)
	var time_before: float = _screen.preview.local_time
	await _tree.create_timer(0.12).timeout
	_check("可见本地时钟累计", _screen.preview.local_time > time_before)
	var tree_fp: String = Recipe.fingerprint(_screen.snapshot())
	var tree_mesh = _mesh_hash(_screen.preview.model)
	EditorInterface.set_main_screen_editor("老王场景工坊")
	_plugin._make_visible(false)
	await _frames(2)
	var paused: float = _screen.preview.local_time
	await _tree.create_timer(0.12).timeout
	_check("隐藏停止时间与渲染", _screen.preview.local_time == paused and _screen.preview.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var stopped = true
	for material: ShaderMaterial in _screen.preview.materials():
		stopped = stopped and material.get_shader_parameter("preview_wind") == false and is_equal_approx(float(material.get_shader_parameter("local_time")), paused)
	_check("隐藏本地材质停止风", stopped)
	EditorInterface.set_main_screen_editor("树木工坊")
	_plugin._make_visible(true)
	await _tree.create_timer(0.12).timeout
	_check("重新显示继续而不重置时间", _screen.preview.local_time > paused)
	_check("双插件切换树木文档不变", Recipe.fingerprint(_screen.snapshot()) == tree_fp and _mesh_hash(_screen.preview.model) == tree_mesh)
	if is_instance_valid(_building):
		_check("双插件切换房屋不串写", JSON.stringify(_building.get_recovery(), "", true, true) == _building_state)
	var local = true
	for material: ShaderMaterial in _screen.preview.materials():
		local = local and material.get_shader_parameter("preview_wind") == true and material.resource_local_to_scene
	_check("恢复后仅本地材质预览风", local)

func _test_compact() -> void:
	# 在真实编辑器树中另建固定 860×600 布局夹具；不伪造计算尺寸。
	var fixture = PanelContainer.new()
	fixture.name = "PlantCompact860x600"
	fixture.position = Vector2(4, 4)
	fixture.size = Vector2(860, 600)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#14261f")
	fixture.add_theme_stylebox_override("panel", background)
	EditorInterface.get_base_control().add_child(fixture)
	var compact = Screen.new()
	fixture.add_child(compact)
	compact.set_screen_visible(true)
	await _frames(5)
	_check("实际紧凑夹具 860×600", fixture.size.x <= 861 and fixture.size.y <= 601, str(fixture.size))
	_check("参数独立滚动宽 280–320", compact.parameter_scroll.size.x >= 280 and compact.parameter_scroll.size.x <= 320, str(compact.parameter_scroll.size))
	_check("中心预览占最大宽度", compact.preview.size.x > compact.parameter_scroll.size.x)
	_check("顶部单行按钮无溢出", _row_fits(compact.toolbar, compact.size.x))
	_check("模块单行位于预览上方", _row_fits(compact.module_bar, compact.preview.size.x) and compact.module_bar.get_parent() == compact.preview)
	_check("预览高度保留", compact.preview.size.y >= 420, str(compact.preview.size))
	for index in 6:
		compact.show_module(index)
		await _frames(2)
		_check("模块 %d 不横向挤大布局" % index, fixture.size.x <= 861 and compact.parameter_scroll.size.x <= 320)
	await _frames(2)
	RenderingServer.force_draw()
	var crop: Image = _tree.root.get_texture().get_image().get_region(Rect2i(Vector2i(fixture.global_position), Vector2i(fixture.size)))
	var compact_path: String = IMAGE_ROOT + "/compact_860x600.png"
	_check("紧凑夹具独立裁图真实像素", crop.get_size() == Vector2i(860, 600) and crop.save_png(compact_path) == OK)
	_artifacts.append(ProjectSettings.globalize_path(compact_path))
	compact.set_screen_visible(false)
	fixture.queue_free()
	await _frames(2)

func _row_fits(row: HBoxContainer, width: float) -> bool:
	if row.get_child_count() == 0:
		return false
	var y = row.get_child(0).position.y
	for child: Control in row.get_children():
		if absf(child.position.y - y) > 1 or child.position.x + child.size.x > width + 1:
			return false
	return true

func _static_tree(node: Node) -> bool:
	if node.get_script() != null or node is Camera3D or node is Light3D or node is CollisionObject3D or node is SubViewport or node is WorldEnvironment:
		return false
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material is ShaderMaterial and (material.get_shader_parameter("preview_wind") != false or float(material.get_shader_parameter("local_time")) != 0.0):
				return false
	for child in node.get_children():
		if not _static_tree(child):
			return false
	return true

func _mesh_hash(node: Node) -> String:
	var data: Array = []
	for child: Node in _walk(node):
		if child is MeshInstance3D and child.mesh != null:
			var surfaces: Array = []
			for surface in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				surfaces.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_TEX_UV]])
			data.append([str(node.get_path_to(child)), child.transform, surfaces])
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(data))
	return context.finish().hex_encode()

func _same_geometry(left: Node, right: Node) -> bool:
	var meshes = 0
	for child: Node in _walk(left):
		if not (child is MeshInstance3D) or child.mesh == null:
			continue
		meshes += 1
		var peer = right.get_node_or_null(left.get_path_to(child)) as MeshInstance3D
		if peer == null or peer.mesh == null or peer.mesh.get_surface_count() != child.mesh.get_surface_count():
			return false
		if not child.transform.is_equal_approx(peer.transform):
			return false
		for surface in child.mesh.get_surface_count():
			var a: Array = child.mesh.surface_get_arrays(surface)
			var b: Array = peer.mesh.surface_get_arrays(surface)
			if a[Mesh.ARRAY_INDEX] != b[Mesh.ARRAY_INDEX]:
				return false
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
				if a[channel].size() != b[channel].size():
					return false
				for index in a[channel].size():
					if a[channel][index].distance_to(b[channel][index]) > 0.0002:
						return false
	return meshes > 0

func _walk(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_walk(child))
	return result

func _scene_state(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	return str(node.get_instance_id()) + ":" + _mesh_hash(node)

func _find_building_screen(node: Node) -> Control:
	for child: Node in _walk(node):
		if child is Control and child.has_method("save_building") and child.has_method("get_recovery"):
			return child
	return null

func _frames(count: int) -> void:
	for frame in count:
		await _tree.process_frame

func _capture(name: String, viewport: Viewport) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	var path = IMAGE_ROOT + "/" + name + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(IMAGE_ROOT))
	var valid = image != null and not image.is_empty()
	_check("真实渲染截图 " + name, valid and image.save_png(path) == OK)
	if valid:
		_artifacts.append(path)

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _finish() -> void:
	var report = {"checks": _checks, "check_count": _checks.size(), "failures": _failures, "failure_count": _failures.size(), "artifacts": _artifacts, "editor": Engine.is_editor_hint(), "art_review": "pending", "project": ProjectSettings.globalize_path("res://"), "boundary": "独立 minimal 双插件编辑器；不运行 Main；不写生产工程；不写草稿"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	var file = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("报告无法写入")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[plant-editor] %d checks, %d failures" % [_checks.size(), _failures.size()])
	_tree.quit(0 if _failures.is_empty() else 1)
