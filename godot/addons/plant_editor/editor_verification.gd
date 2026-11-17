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
var _source_snapshot: Dictionary = {}

static func run(plugin: EditorPlugin) -> void:
	if not Engine.is_editor_hint() or not OS.get_cmdline_user_args().has("--plant-editor-verify"):
		return
	if OS.get_cmdline_user_args().has("--workshop-switch-verify"):
		var switch_script: Script = load("res://addons/plant_editor/switch_verification.gd") as Script
		if switch_script == null:
			printerr("[workshop-switch] 1 checks, 1 failures: verifier unavailable")
			plugin.get_tree().quit(1)
			return
		await switch_script.run(plugin)
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
	for source in ["addons/plant_editor/editor_screen.gd", "addons/plant_editor/editor_verification.gd", "addons/plant_editor/preview.gd", "src/plant_authoring/generator.gd", "src/plant_authoring/geometry.gd", "src/plant_authoring/recipe.gd", "src/plant_authoring/session.gd", "src/plant_authoring/store.gd", "src/plant_authoring/host_attachment.gd", "src/plant_authoring/host_scene_guard.gd", "src/plant_authoring/trunk_path.gd", "src/plant_authoring/wind_runtime.gd", "src/plant_authoring/leaf.gdshader", "src/plant_authoring/game_wind.gdshaderinc", "src/plant_authoring/lightweight_foliage.gd", "src/plant_authoring/foliage_batch.gd", "src/plant_authoring/leaf_card.gdshader", "src/plant_authoring/leaf_volume.gdshader", "assets/textures/vegetation/workshop_leaf_atlas_512.png", "assets/textures/vegetation/workshop_leaf_clusters_512.png"]:
		_source_snapshot[source] = _hash("res://" + source)
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
	await _test_preview_navigation()
	await _test_species_and_images()
	await _test_sliders_and_failure()
	var leaf_completed: Array[String] = []
	await _test_leaf_geometry_ui(leaf_completed)
	_check("叶几何 UI 专项完整返回", leaf_completed.has("leaf_geometry"))
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
	await _test_deepening()
	var canopy_completed: Array[String] = []
	await _test_foliage_modes_ui(canopy_completed)
	await _test_volume_surface_cards(canopy_completed)
	await _test_canopy_wind_frames(canopy_completed)
	for section in ["foliage_modes", "volume_surface_cards", "canopy_wind"]:
		_check("树冠三模式专项完整返回 " + section, canopy_completed.has(section))
	for path in ["res://addons/plant_editor/plugin.gd", "res://addons/plant_editor/editor_screen.gd", "res://addons/plant_editor/preview.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		_check("预览不写 shader global " + path.get_file(), not source.contains("global_shader_parameter_set"))
		# 草稿IO隔离门禁只读检查bootstrap目录是否存在，不等于加载或启动游戏。
		var loads_bootstrap: bool = source.contains('load("res://src/bootstrap/') or source.contains("load('res://src/bootstrap/")
		_check("主屏不引用房屋或启动游戏 " + path.get_file(), not source.contains("res://addons/building_workshop/") and not loads_bootstrap and not source.contains("add_autoload_singleton"))
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

# 历史 1174 项使用明确的 legacy geometry 夹具；新建默认体块冠由独立专项覆盖。
func _legacy_document(screen: Control, species: String) -> Dictionary:
	var created: Dictionary = screen.new_document(species)
	if not bool(created.get("ok", false)): return created
	var recipe: Dictionary = Recipe.defaults(species)
	recipe.foliage_mode = "geometry"
	var result: Dictionary = screen.session.load_recipe(recipe)
	if bool(result.get("ok", false)):
		screen.input_recipe = screen.session.snapshot()
		screen._accept_result(result, true)
		screen._sync_controls()
	return result

func _nav_mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	Input.warp_mouse(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(2)

func _test_preview_navigation() -> void:
	var preview = _screen.preview
	# Editor startup import dialog owns mouse focus until the initial scan completes.
	for attempt in 1200:
		if not EditorInterface.get_resource_filesystem().is_scanning():
			break
		await _frames(1)
	await _tree.create_timer(1.0).timeout
	var surface: Control = preview._input_surface
	_check("预览独立输入面", surface.mouse_filter == Control.MOUSE_FILTER_STOP and preview._surface.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	for index in 4:
		var button: Button = preview._tools.get_child(index)
		await _nav_mouse(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
		await _nav_mouse(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, false)
		_check("GUI视图按钮点击仍可见 " + button.text, button.is_visible_in_tree() and not button.get_global_rect().intersects(surface.get_global_rect()))
		_check("GUI按钮实际切换投影 " + button.text, preview.camera.projection == (Camera3D.PROJECTION_ORTHOGONAL if index < 2 else Camera3D.PROJECTION_PERSPECTIVE))
		await _capture("navigation_after_button_%d" % index, EditorInterface.get_base_control().get_viewport())
	var point: Vector2 = surface.get_global_rect().get_center()
	for button in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
		var before: Vector3 = preview.target
		var old_yaw: float = preview.yaw
		await _nav_mouse(point, button, true)
		var motion := InputEventMouseMotion.new()
		motion.position = point + Vector2(40, 20)
		motion.global_position = motion.position
		motion.relative = Vector2(40, 20)
		motion.button_mask = 1 << (button - 1)
		Input.parse_input_event(motion)
		await _frames(2)
		await _nav_mouse(motion.position, button, false)
		_check("GUI导航实际改变相机 %d" % button, not preview.target.is_equal_approx(before) if button == MOUSE_BUTTON_MIDDLE else not is_equal_approx(preview.yaw, old_yaw))
	await _capture("navigation_after_pan_orbit", EditorInterface.get_base_control().get_viewport())
	var old_distance: float = preview.distance
	await _nav_mouse(point, MOUSE_BUTTON_WHEEL_UP, true)
	await _nav_mouse(point, MOUSE_BUTTON_WHEEL_UP, false)
	_check("GUI滚轮缩放", preview.distance < old_distance)
	preview.select_branch("")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	key.pressed = false
	Input.parse_input_event(key)
	_check("GUI F适配回模型", preview.target.is_equal_approx((preview.model.global_transform * preview._bounds(preview.model)).get_center()))

func _test_species_and_images() -> void:
	var fingerprints: Array[String] = []
	for species in Recipe.SPECIES:
		var result: Dictionary = _legacy_document(_screen, species)
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
	_legacy_document(_screen, "camphor")
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
	_legacy_document(_screen, "camphor")
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
	_legacy_document(_screen, "camphor")
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

func _test_leaf_geometry_ui(completed: Array[String]) -> void:
	for species in Recipe.SPECIES:
		_legacy_document(_screen, species)
		_screen.show_module(2)
		var picker: OptionButton = _screen.controls.leaf_geometry
		_check("叶几何默认 balanced " + species, picker.item_count == 3 and picker.selected == 0 and _screen.snapshot().leaf_geometry == "balanced")
		_screen.controls.name.text = "leaf_ui_%s_%d" % [species, Time.get_ticks_usec()]
		_screen.controls.name.text_changed.emit(_screen.controls.name.text)
		_screen.flush_pending()
		var baseline: Dictionary = _screen.snapshot()
		var counts: Dictionary = {}
		for mode in ["high", "reference", "balanced"]:
			var before: Dictionary = _screen.snapshot()
			var undo_before: Dictionary = _screen.session.peek_undo_target()
			var camera: Transform3D = _screen.preview.camera.transform
			var previous_mesh = _mesh_hash(_screen.preview.model)
			var index: int = Screen.LEAF_GEOMETRY_MODES.find(mode)
			picker.select(index)
			picker.item_selected.emit(index)
			await _tree.create_timer(0.24).timeout
			var expected: Dictionary = baseline.duplicate(true)
			expected.leaf_geometry = mode
			_check("叶几何自动预览只改一个字段 %s/%s" % [species, mode], Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and not _screen.has_pending_fields())
			_check("叶几何重建保留摄像头 %s/%s" % [species, mode], camera.is_equal_approx(_screen.preview.camera.transform) and previous_mesh != _mesh_hash(_screen.preview.model))
			counts[mode] = _check_live_geometry_stats(species + "/" + mode)
			_screen.buttons.undo.pressed.emit()
			_check("叶几何单次撤销完整恢复 %s/%s" % [species, mode], Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(before) and _screen.session.peek_undo_target() == undo_before and picker.selected == Screen.LEAF_GEOMETRY_MODES.find(before.leaf_geometry))
			_screen.buttons.redo.pressed.emit()
			_check("叶几何重做同步控件 %s/%s" % [species, mode], Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and picker.selected == index)
			var saved: Dictionary = _screen.save_recipe()
			if _check("叶几何保存成功 %s/%s" % [species, mode], bool(saved.get("ok", false)), str(saved.get("reason", ""))):
				var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved.recipe_path))
				_check("叶几何 JSON 保留档位密度种子 %s/%s" % [species, mode], decoded is Dictionary and decoded.leaf_geometry == mode and decoded.leaf_density == baseline.leaf_density and decoded.seed == baseline.seed)
				_legacy_document(_screen, species)
				var loaded: Dictionary = _screen.open_recipe(saved.recipe_path)
				_check("叶几何重载同步配方控件 %s/%s" % [species, mode], bool(loaded.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and picker.selected == index and not _screen.session.is_dirty())
				_check_export_bundle(saved, false)
				_check_live_geometry_stats(species + "/" + mode + "/reload")
		_check("叶几何三档保留叶片数量 " + species, counts.high.leaf_count == counts.reference.leaf_count and counts.balanced.leaf_count == counts.reference.leaf_count)
		_check("叶几何三档真实几何预算 " + species, counts.high.triangles == counts.reference.triangles and counts.high.vertices < counts.reference.vertices and counts.balanced.triangles < counts.high.triangles, str(counts))
	completed.append("leaf_geometry")

func _test_foliage_modes_ui(completed: Array[String]) -> void:
	for species in Recipe.SPECIES:
		var created: Dictionary = _screen.new_document(species)
		if not _check("新建默认低模体块冠 " + species, bool(created.get("ok", false)) and _screen.snapshot().get("foliage_mode") == "volumes"): return
		_screen.show_module(2)
		var picker: OptionButton = _screen.controls.foliage_mode
		_check("叶片页三模式与专属说明 " + species, picker.item_count == 3 and picker.selected == 0 and _screen.controls.leaf_geometry.disabled and not _screen.controls.foliage_mode_note.text.is_empty())
		for mode in ["cards", "geometry", "volumes"]:
			var label = species + "/" + mode
			var before: Dictionary = _screen.snapshot()
			var undo_before: Dictionary = _screen.session.peek_undo_target()
			var camera: Transform3D = _screen.preview.camera.transform
			var index: int = Screen.FOLIAGE_MODES.find(mode)
			picker.select(index)
			picker.item_selected.emit(index)
			_check("模式待应用立即同步专属控件 " + label, _screen.controls.leaf_geometry.disabled == (mode != "geometry"))
			await _tree.create_timer(0.24).timeout
			var expected: Dictionary = before.duplicate(true)
			expected.foliage_mode = mode
			_check("三模式自动预览仅改模式 " + label, Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and not _screen.has_pending_fields() and camera.is_equal_approx(_screen.preview.camera.transform))
			_check_live_geometry_stats(label)
			_screen.undo()
			_check("三模式一次撤销及历史不串 " + label, Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(before) and _screen.session.peek_undo_target() == undo_before and picker.selected == Screen.FOLIAGE_MODES.find(before.foliage_mode))
			_screen.redo()
			_check("三模式重做同步控件 " + label, Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and picker.selected == index and _screen.controls.leaf_geometry.disabled == (mode != "geometry"))
			if mode != "geometry":
				_screen.controls.leaf_geometry.item_selected.emit(2)
				_check("非实体模式不接收细分操作 " + label, not _screen.has_pending_fields() and _screen.input_recipe.leaf_geometry == expected.leaf_geometry)
			var saved: Dictionary = _screen.save_recipe()
			if not _check("三模式保存 " + label, bool(saved.get("ok", false)), str(saved.get("reason", ""))): return
			_screen.new_document(species)
			var loaded: Dictionary = _screen.open_recipe(saved.recipe_path)
			_check("三模式保存重载完整配方 " + label, bool(loaded.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and picker.selected == index and not _screen.session.is_dirty())
			_check_export_bundle(saved, false)
			var recovery: Dictionary = JSON.parse_string(JSON.stringify(_screen.get_recovery(), "", true, true))
			_screen.new_document(species)
			var restored: Dictionary = _screen.restore_recovery(recovery)
			_check("三模式 JSON 草稿恢复 " + label, bool(restored.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and picker.selected == index and _screen.controls.leaf_geometry.disabled == (mode != "geometry"))
			_test_mode_branch_controls(label)
			_screen.show_module(2)
			_screen.preview.select_branch("")
			await _capture("foliage_%s_%s_ui" % [species, mode], EditorInterface.get_base_control().get_viewport())
	_legacy_document(_screen, "camphor")
	_screen._field("leaf_geometry", "reference")
	_screen.flush_pending()
	for mode in ["cards", "volumes", "geometry"]:
		_screen._field("foliage_mode", mode)
		_screen.flush_pending()
		_check("切换三模式不遗失实体 reference 档位 " + mode, _screen.snapshot().get("foliage_mode") == mode and _screen.snapshot().leaf_geometry == "reference" and _screen.controls.leaf_geometry.selected == 2 and _screen.controls.leaf_geometry.disabled == (mode != "geometry"))
	var successful: Dictionary = _screen.snapshot()
	var model_id: int = _screen.preview.model.get_instance_id()
	_screen._field("foliage_mode", "invalid_mode")
	var rejected: Dictionary = _screen.flush_pending()
	_check("非法模式不换最后成功模型", not bool(rejected.get("ok", true)) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(successful) and _screen.preview.model.get_instance_id() == model_id and _screen.has_pending_fields())
	var invalid_recovery: Dictionary = JSON.parse_string(JSON.stringify(_screen.get_recovery(), "", true, true))
	var pending_restored: Dictionary = _screen.restore_recovery(invalid_recovery)
	_check("模式失败草稿保留待修输入和成功外观", bool(pending_restored.get("ok", false)) and _screen.input_recipe.foliage_mode == "invalid_mode" and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(successful) and _screen.has_pending_fields())
	_screen.undo()
	_screen.session.mark_saved(_screen.session.fingerprint())
	var legacy: Dictionary = _screen.get_recovery()
	legacy.session.recipe.erase("foliage_mode")
	legacy.session.recipe.erase("volume_leaf_cards")
	legacy.input.erase("foliage_mode")
	legacy.input.erase("volume_leaf_cards")
	legacy.input.branch_start = 20.0
	var old_saved: Dictionary = JSON.parse_string(legacy.session.saved_fingerprint)
	old_saved.erase("foliage_mode")
	old_saved.erase("volume_leaf_cards")
	legacy.session.saved_fingerprint = Recipe._stable_json(old_saved)
	_screen.new_document("maple")
	var old_restored: Dictionary = _screen.restore_recovery(legacy)
	_check("旧草稿缺模式保留 geometry/reference 外观", bool(old_restored.get("ok", false)) and _screen.snapshot().get("foliage_mode") == "geometry" and _screen.snapshot().leaf_geometry == "reference" and not _screen.session.is_dirty(), str(old_restored.get("reason", "")))
	_check("旧草稿新增可选键不丢待修输入", _screen.has_pending_fields() and float(_screen.input_recipe.branch_start) == 20.0 and _screen.input_recipe.get("foliage_mode") == "geometry")
	_screen.undo()
	_check("旧草稿撤回输入不消耗历史", not _screen.has_pending_fields() and not _screen.session.can_undo())
	var legacy_directory = Screen.Store.DEFAULT_ROOT.path_join("legacy_missing_foliage_%d/revision_0001" % Time.get_ticks_usec())
	if not _check("旧无模式配方测试目录可创建", DirAccess.make_dir_recursive_absolute(legacy_directory) == OK): return
	var legacy_path = legacy_directory.path_join("plant.recipe.json")
	var legacy_file = FileAccess.open(legacy_path, FileAccess.WRITE)
	if _check("旧无模式配方测试文件可写", legacy_file != null):
		legacy_file.store_string(JSON.stringify(legacy.session.recipe, "\t"))
		legacy_file.close()
		var old_loaded: Dictionary = _screen.open_recipe(legacy_path)
		_check("旧配方载入不静默改体块冠", bool(old_loaded.get("ok", false)) and _screen.snapshot().get("foliage_mode") == "geometry" and _screen.snapshot().leaf_geometry == "reference", str(old_loaded.get("reason", "")))
	completed.append("foliage_modes")

func _test_mode_branch_controls(label: String) -> void:
	_screen.show_module(1)
	_screen.select_branch("branch_00")
	var before: Dictionary = _screen.snapshot()
	var branches: Array = _screen.preview.branches.duplicate(true)
	var wood = _mesh_hash(_screen.preview.model.get_node("Trunk"))
	var leaves = _mesh_hash(_screen.preview.model.get_node("Leaves"))
	_screen.controls.branch_length_scale.value = 1.4
	_screen.controls.branch_radius_scale.value = 1.3
	_screen.controls.branch_angle_offset.value = 0.35
	var changed: Dictionary = _screen.flush_pending()
	_check("三模式逐枝参数改变真实枝叶 " + label, bool(changed.get("ok", false)) and _mesh_hash(_screen.preview.model.get_node("Trunk")) != wood and _mesh_hash(_screen.preview.model.get_node("Leaves")) != leaves)
	_check("三模式合批仍按稳定 ID 高亮 " + label, _screen.preview.selected_id == "branch_00" and _screen.preview.selection_visible())
	_screen.focus_selected_branch()
	var branch: Dictionary = _screen.preview.branches[0]
	var world_bounds: AABB = _screen.preview.model.global_transform * branch.bounds
	_check("三模式按元数据聚焦非空选枝 " + label, branch.bounds.size.length() > 0.01 and _screen.preview.target.is_equal_approx(world_bounds.get_center()))
	for index in range(1, branches.size()):
		_check("三模式修改选枝不改其它枝范围 %s/%d" % [label, index], branches[index].id == _screen.preview.branches[index].id and branches[index].bounds == _screen.preview.branches[index].bounds)
	_screen.controls.branch_enabled.button_pressed = false
	var hidden: Dictionary = _screen.flush_pending()
	_check("三模式禁用选枝真实减少枝叶 " + label, bool(hidden.get("ok", false)) and not _screen.preview.branches[0].enabled and int(hidden.stats.branch_count) == int(changed.stats.branch_count) - 1 and int(hidden.stats.triangles) < int(changed.stats.triangles))
	_screen.undo()
	_screen.undo()
	_check("三模式逐枝两次撤销还原 " + label, Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(before) and _mesh_hash(_screen.preview.model.get_node("Trunk")) == wood and _mesh_hash(_screen.preview.model.get_node("Leaves")) == leaves)
	_screen.preview.fit_model()
	var point: Vector3 = _screen.preview.model.global_transform * _screen.preview.branches[0].bounds.get_center()
	var picked: String = _screen.preview.pick_branch(_screen.preview.camera.unproject_position(point))
	_check("三模式合批仍可射线选枝 " + label, not picked.is_empty() and _screen.selected_branch == picked and _screen.preview.selection_visible())

func _test_volume_surface_cards(completed: Array[String]) -> void:
	for species in Recipe.SPECIES:
		var created: Dictionary = _screen.new_document(species)
		if not _check("混合冠新建使用真实图集 " + species, bool(created.get("ok", false)), str(created.get("reason", ""))): return
		_screen.show_module(2)
		var slider: HSlider = _screen.controls.volume_leaf_cards
		var density: int = int(Recipe.defaults(species).volume_leaf_cards)
		var mixed: Dictionary = _screen.snapshot()
		var mixed_stats: Dictionary = _screen.session.build().stats.duplicate(true)
		var mixed_mesh = _mesh_hash(_screen.preview.model.get_node("Leaves"))
		_check("叶簇卡滑块读取内核整数范围及新建密度 " + species, slider.editable and slider.min_value == Recipe.RANGES.volume_leaf_cards[0] and slider.max_value == Recipe.RANGES.volume_leaf_cards[1] and slider.step == 1 and int(slider.value) == density and density > 0)
		_check("混合冠实际叶簇卡非预算叶位 " + species, int(mixed_stats.get("surface_card_count", 0)) > 0)
		_screen.select_branch("branch_00")
		slider.drag_started.emit()
		slider.value = density - 1
		await _tree.create_timer(0.24).timeout
		slider.value = 0
		slider.drag_ended.emit(true)
		var pure: Dictionary = _screen.snapshot()
		var pure_stats: Dictionary = _screen.session.build().stats.duplicate(true)
		_check("拖动叶簇卡自动切纯体块保留选枝 " + species, int(pure.volume_leaf_cards) == 0 and not _screen.has_pending_fields() and _screen.preview.selected_id == "branch_00" and _screen.preview.selection_visible())
		_check("纯体块真实零叶簇卡且面数减少 " + species, pure_stats.has("surface_card_count") and int(pure_stats.surface_card_count) == 0 and pure_stats.cluster_count == mixed_stats.cluster_count and int(pure_stats.triangles) < int(mixed_stats.triangles) and _mesh_hash(_screen.preview.model.get_node("Leaves")) != mixed_mesh)
		_check_live_geometry_stats(species + "/pure")
		_screen.undo()
		_check("叶簇卡整次拖动只需一次撤销 " + species, Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(mixed) and not _screen.session.can_undo() and int(slider.value) == density and _mesh_hash(_screen.preview.model.get_node("Leaves")) == mixed_mesh)
		_screen.redo()
		_check("叶簇卡重做回纯体块 " + species, Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(pure) and int(slider.value) == 0)
		for value in [0, density]:
			slider.value = value
			_screen.flush_pending()
			var expected: Dictionary = _screen.snapshot()
			var label = species + ("/pure" if value == 0 else "/mixed")
			var saved: Dictionary = _screen.save_recipe()
			if not _check("纯体块与混合冠保存 " + label, bool(saved.get("ok", false)), str(saved.get("reason", ""))): return
			var loaded: Dictionary = _screen.open_recipe(saved.recipe_path)
			_check("纯体块与混合冠保存重载 " + label, bool(loaded.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and int(slider.value) == value)
			_check_export_bundle(saved, false)
			var draft: Dictionary = JSON.parse_string(JSON.stringify(_screen.get_recovery(), "", true, true))
			var restored: Dictionary = _screen.restore_recovery(draft)
			_check("纯体块与混合冠草稿恢复 " + label, bool(restored.get("ok", false)) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(expected) and int(slider.value) == value and slider.editable)
			_test_mode_branch_controls(label)
			_screen.show_module(2)
			_check_live_geometry_stats(label)
			_screen.preview.select_branch("")
			await _capture("volume_%s_%s_ui" % [species, "pure" if value == 0 else "mixed"], EditorInterface.get_base_control().get_viewport())
		for mode in ["cards", "geometry", "volumes"]:
			_screen._field("foliage_mode", mode)
			_screen.flush_pending()
			_check("叶簇卡控件仅 volumes 可编辑 " + species + "/" + mode, slider.editable == (mode == "volumes") and int(_screen.snapshot().volume_leaf_cards) == density)
			if mode != "volumes":
				slider.value = 0
				_check("禁用叶簇卡不写配方或历史 " + mode, not _screen.has_pending_fields() and int(_screen.input_recipe.volume_leaf_cards) == density and int(slider.value) == density)
		_screen.session.mark_saved(_screen.session.fingerprint())
		var legacy: Dictionary = _screen.get_recovery()
		legacy.session.recipe.erase("volume_leaf_cards")
		legacy.input.erase("volume_leaf_cards")
		var old_saved: Dictionary = JSON.parse_string(legacy.session.saved_fingerprint)
		old_saved.erase("volume_leaf_cards")
		legacy.session.saved_fingerprint = Recipe._stable_json(old_saved)
		var recovered: Dictionary = _screen.restore_recovery(legacy)
		_check("旧体块草稿缺叶簇卡字段不静默混合 " + species, bool(recovered.get("ok", false)) and _screen.snapshot().foliage_mode == "volumes" and int(_screen.snapshot().volume_leaf_cards) == 0 and int(slider.value) == 0 and not _screen.session.is_dirty(), str(recovered.get("reason", "")))
	completed.append("volume_surface_cards")

func _test_canopy_wind_frames(completed: Array[String]) -> void:
	for mode in ["volumes", "cards"]:
		var sampled: Array[String] = []
		for species in Recipe.SPECIES:
			await _test_species_wind_frames(species, sampled, mode)
		for species in Recipe.SPECIES:
			_check("新模式三树种真实风帧完整返回 " + mode + "/" + species, sampled.has(species))
	completed.append("canopy_wind")

func _check_live_geometry_stats(label: String) -> Dictionary:
	var actual = {"vertices": 0, "triangles": 0, "mesh_nodes": 0, "surfaces": 0}
	for node in _walk(_screen.preview.model):
		if not node is MeshInstance3D or node.mesh == null: continue
		actual.mesh_nodes += 1
		actual.surfaces += node.mesh.get_surface_count()
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			actual.vertices += arrays[Mesh.ARRAY_VERTEX].size()
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			actual.triangles += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	var result: Dictionary = _screen.session.build()
	var stats: Dictionary = result.get("stats", {})
	for key in actual:
		_check("实时几何统计吻合网格 %s/%s" % [label, key], stats.has(key) and int(stats[key]) == int(actual[key]), "实际 %s；stats %s" % [actual[key], stats.get(key)])
	for entry in [["vertices", "顶点"], ["triangles", "三角面"], ["mesh_nodes", "网格"], ["surfaces", "surfaces"]]:
		_check("实时信息显示 %s/%s" % [label, entry[0]], _screen.status.text.contains("%d %s" % [actual[entry[0]], entry[1]]) and _screen.details.contains("%d %s" % [actual[entry[0]], entry[1]]))
	_check("几何统计不冒充渲染批次 " + label, not _screen.status.text.to_lower().contains("drawcall") and not _screen.status.text.contains("批次"))
	if _screen.snapshot().get("foliage_mode") == "volumes":
		_check("体块冠区分实际冠簇叶簇卡及预算叶位 " + label, stats.has("surface_card_count") and _screen.status.text.contains("%d 冠簇" % int(stats.get("cluster_count", -1))) and _screen.status.text.contains("%d 叶簇卡" % int(stats.get("surface_card_count", -1))) and not _screen.status.text.contains("预算叶位") and _screen.details.contains("预算叶位"))
	if _screen.snapshot().get("foliage_mode") in ["volumes", "cards"]:
		var mode: String = _screen.snapshot().foliage_mode
		var atlas_path := "res://assets/textures/vegetation/workshop_leaf_clusters_512.png" if mode == "volumes" else "res://assets/textures/vegetation/workshop_leaf_atlas_512.png"
		var card_vertices := 0
		var card_indices := 0
		for node in _walk(_screen.preview.model.get_node("Leaves")):
			if not node is MeshInstance3D or node.mesh == null: continue
			for surface in node.mesh.get_surface_count():
				var material = node.get_active_material(surface)
				if not material is ShaderMaterial or material.shader.resource_path != "res://src/plant_authoring/leaf_card.gdshader": continue
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				card_vertices += arrays[Mesh.ARRAY_VERTEX].size()
				card_indices += arrays[Mesh.ARRAY_INDEX].size()
				var atlas = material.get_shader_parameter("leaf_atlas")
				_check("按模式使用真实512叶簇或单叶图集 " + label, atlas is Texture2D and atlas.get_size() == Vector2(512, 512) and atlas.resource_path == atlas_path, atlas_path)
		if mode == "volumes":
			_check("叶簇卡统计与实际六顶点四三角卡片一致（不乘9） " + label, card_vertices == int(stats.get("surface_card_count", -1)) * 6 and card_indices == int(stats.get("surface_card_count", -1)) * 12)
		else:
			_check("单叶模式实际存在图集卡片 " + label, card_vertices > 0 and card_indices > 0)
	actual.leaf_count = stats.get("leaf_count", -1)
	return actual

func _test_branch() -> void:
	_legacy_document(_screen, "camphor")
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
	_legacy_document(_screen, "camphor")
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
	_legacy_document(_screen, "camphor")
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
	_legacy_document(compact, "camphor")
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
	compact.show_module(2)
	compact.preview.select_branch("")
	await _frames(2)
	var leaf_picker: OptionButton = compact.controls.leaf_geometry
	var leaf_baseline: Dictionary = compact.snapshot()
	for index in Screen.LEAF_GEOMETRY_MODES.size():
		leaf_picker.select(index)
		leaf_picker.item_selected.emit(index)
		await _tree.create_timer(0.24).timeout
		var expected: Dictionary = leaf_baseline.duplicate(true)
		expected.leaf_geometry = Screen.LEAF_GEOMETRY_MODES[index]
		_check("紧凑叶几何控件可见且不挤大布局 " + expected.leaf_geometry, fixture.size == Vector2(860, 600) and compact.parameter_scroll.get_global_rect().encloses(leaf_picker.get_global_rect()) and _row_fits(compact.toolbar, compact.size.x) and _row_fits(compact.module_bar, compact.preview.size.x))
		_check("紧凑叶几何自动预览不改密度种子 " + expected.leaf_geometry, Recipe.fingerprint(compact.snapshot()) == Recipe.fingerprint(expected))
		compact.preview.select_branch("")
		RenderingServer.force_draw()
		var leaf_crop = _tree.root.get_texture().get_image().get_region(Rect2i(Vector2i(fixture.global_position), Vector2i(fixture.size)))
		var leaf_path = IMAGE_ROOT.path_join("compact_860x600_leaf_" + expected.leaf_geometry + ".png")
		_check("紧凑叶几何真实截图 " + expected.leaf_geometry, leaf_crop.get_size() == Vector2i(860, 600) and leaf_crop.save_png(leaf_path) == OK)
		_artifacts.append(ProjectSettings.globalize_path(leaf_path))
	for species in Recipe.SPECIES:
		compact.new_document(species)
		compact.show_module(2)
		for mode in Screen.FOLIAGE_MODES:
			var mode_picker: OptionButton = compact.controls.foliage_mode
			var index: int = Screen.FOLIAGE_MODES.find(mode)
			mode_picker.select(index)
			mode_picker.item_selected.emit(index)
			await _tree.create_timer(0.24).timeout
			compact.preview.select_branch("")
			await _frames(2)
			var label = species + "/" + mode
			_check("紧凑三模式自动预览 " + label, compact.snapshot().foliage_mode == mode and not compact.has_pending_fields() and compact.controls.leaf_geometry.disabled == (mode != "geometry") and compact.controls.volume_leaf_cards.editable == (mode == "volumes"))
			_check("紧凑每簇叶簇卡滑块仍在叶片滚动页内 " + label, compact.parameter_scroll.get_global_rect().encloses(compact.controls.volume_leaf_cards.get_global_rect()) and compact.controls.volume_leaf_cards.get_parent().get_parent() == compact.pages[2])
			_check("紧凑三模式不缩字体不挤大布局 " + label, fixture.size == Vector2(860, 600) and compact.theme.default_font_size == 16 and compact.parameter_scroll.size.x >= 280 and compact.parameter_scroll.size.x <= 320 and compact.preview.size.x > compact.parameter_scroll.size.x and compact.preview.size.y >= 420)
			_check("紧凑模式及细分控件可见 " + label, compact.parameter_scroll.get_global_rect().encloses(mode_picker.get_global_rect()) and compact.parameter_scroll.get_global_rect().encloses(leaf_picker.get_global_rect()) and _row_fits(compact.toolbar, compact.size.x) and _row_fits(compact.module_bar, compact.preview.size.x))
			RenderingServer.force_draw()
			var mode_crop = _tree.root.get_texture().get_image().get_region(Rect2i(Vector2i(fixture.global_position), Vector2i(fixture.size)))
			var mode_path = IMAGE_ROOT.path_join("compact_860x600_%s_%s.png" % [species, mode])
			_check("紧凑三模式真实 UI 截图 " + label, mode_crop.get_size() == Vector2i(860, 600) and mode_crop.save_png(mode_path) == OK)
			_artifacts.append(ProjectSettings.globalize_path(mode_path))
			if mode == "volumes":
				compact.controls.volume_leaf_cards.value = 0
				await _tree.create_timer(0.24).timeout
				compact.preview.select_branch("")
				await _frames(2)
				_check("紧凑纯体块叶簇卡归零 " + species, int(compact.snapshot().volume_leaf_cards) == 0 and compact.status.text.contains("0 叶簇卡") and compact.parameter_scroll.get_global_rect().encloses(compact.controls.volume_leaf_cards.get_global_rect()) and compact.theme.default_font_size == 16)
				RenderingServer.force_draw()
				var pure_crop = _tree.root.get_texture().get_image().get_region(Rect2i(Vector2i(fixture.global_position), Vector2i(fixture.size)))
				var pure_path = IMAGE_ROOT.path_join("compact_860x600_%s_volumes_pure.png" % species)
				_check("紧凑纯体块真实 UI 截图 " + species, pure_crop.get_size() == Vector2i(860, 600) and pure_crop.save_png(pure_path) == OK)
				_artifacts.append(ProjectSettings.globalize_path(pure_path))
				compact.undo()
	compact.set_screen_visible(false)
	fixture.queue_free()
	await _frames(2)

func _test_deepening() -> void:
	# 新专项追加在旧专项之后；完成哨兵防止脚本异常导致后续断言被静默跳过。
	var completed: Array[String] = []
	print("[plant-editor-stage] path")
	await _test_path_panel(completed)
	print("[plant-editor-stage] bark-moss")
	await _test_bark_moss(completed)
	print("[plant-editor-stage] saved-host")
	await _test_saved_host(completed)
	print("[plant-editor-stage] fixed-wind")
	await _test_fixed_wind_frames(completed)
	print("[plant-editor-stage] compact")
	await _test_compact_panels(completed)
	for section in ["path", "details", "host", "host_exports", "wind", "compact_panels"]:
		_check("深化专项完整返回 " + section, completed.has(section))
	for image in ["manual_trunk_path", "bark_moss_manual_close", "tree_house_whole", "tree_house_breach_trunk_close", "wind_t0000", "wind_t0275", "compact_860x600_host_path"]:
		_check_saved_file(IMAGE_ROOT.path_join(image + ".png"))
	for source_path in ["res://src/plant_authoring/host_attachment.gd", "res://src/plant_authoring/wind_runtime.gd", "res://src/plant_authoring/generator.gd", "res://src/plant_authoring/store.gd"]:
		var source = FileAccess.get_file_as_string(source_path)
		_check("plant 运行实现不依赖房屋制作 " + source_path.get_file(), not source.contains("res://src/workshop/") and not source.contains("res://addons/building_workshop/"))

func _test_path_panel(completed: Array[String]) -> void:
	_legacy_document(_screen, "camphor")
	_screen.show_module(0)
	_screen.buttons.path_panel.pressed.emit()
	_screen.buttons.path_insert.pressed.emit()
	var inserted: Dictionary = _screen.flush_pending()
	if not _check("路径面板从自动建立三控制点", bool(inserted.get("ok", false)) and _screen.snapshot().trunk_path.size() == 3, str(inserted.get("reason", ""))):
		return
	_screen._point_picker.select(1)
	_screen._point_picker.item_selected.emit(1)
	var baseline: Dictionary = _screen.snapshot()
	var mesh_before = _mesh_hash(_screen.preview.model)
	var slider: HSlider = _screen._path_sliders.x
	_check("路径 XYZ 只用米制 HSlider", slider.step == 0.001 and _screen._path_sliders.y is HSlider and _screen._path_sliders.z is HSlider)
	slider.drag_started.emit()
	slider.value = 0.6
	await _tree.create_timer(0.24).timeout
	_check("路径拖动 debounce 真实弯干", is_equal_approx(float(_screen.snapshot().trunk_path[1].x), 0.6) and mesh_before != _mesh_hash(_screen.preview.model))
	slider.value = 0.9
	await _tree.create_timer(0.24).timeout
	slider.value = 1.1
	slider.drag_ended.emit(true)
	var edited: Dictionary = _screen.snapshot()
	_check("路径拖动最终点进入实际中心线", is_equal_approx(float(edited.trunk_path[1].x), 1.1) and _screen.preview.model.get_meta("trunk_path").mode == "manual")
	_screen.buttons.undo.pressed.emit()
	_check("路径单拖一次 undo 恢复完整配方几何", Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(baseline) and _mesh_hash(_screen.preview.model) == mesh_before)
	_screen.buttons.undo.pressed.emit()
	_check("路径第二次 undo 仅撤销建立手动路径", _screen.snapshot().trunk_path.is_empty() and not _screen.session.can_undo())
	_screen.buttons.redo.pressed.emit()
	_screen.buttons.redo.pressed.emit()
	_check("路径公开 redo 恢复拖动终值", Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(edited))
	var model_id: int = _screen.preview.model.get_instance_id()
	# UI 会限制合法 Y；向公开待应用输入注入重复高度，验证边界拒绝而不是放宽滑条。
	_screen.input_recipe.trunk_path[1].y = 0.0
	var rejected: Dictionary = _screen.flush_pending()
	_check("坏路径拒绝且不换成功模型", not bool(rejected.get("ok", true)) and str(rejected.get("reason", "")).contains("trunk_path") and _screen.preview.model.get_instance_id() == model_id and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(edited), str(rejected.get("reason", "")))
	_check("坏路径输入保留待修正", float(_screen.input_recipe.trunk_path[1].y) == 0.0 and _screen.has_pending_fields())
	_screen.buttons.undo.pressed.emit()
	_check("坏路径 undo 只撤回输入不消耗成功历史", not _screen.has_pending_fields() and _screen.preview.model.get_instance_id() == model_id and _screen.session.can_undo())
	_screen.preview.select_branch("")
	_screen.preview.fit_model()
	await _capture("manual_trunk_path", _screen.preview.viewport)
	completed.append("path")

func _test_bark_moss(completed: Array[String]) -> void:
	_screen.show_module(3)
	_screen.controls.bark_detail.value = 0.25
	_screen.controls.moss_amount.value = 0.45
	_screen.controls.moss_enabled.button_pressed = true
	var result: Dictionary = _screen.flush_pending()
	if not _check("树皮苔藓深化基线生成", bool(result.get("ok", false)), str(result.get("reason", ""))): return
	for entry in [["bark_detail", 0.65, "Trunk/BarkDetail"], ["moss_scale", 0.32, "Moss/AttachedPatches"], ["moss_bias", 1.2, "Moss/AttachedPatches"], ["moss_height", 0.55, "Moss/AttachedPatches"]]:
		var node = _screen.preview.model.get_node_or_null(entry[2]) as MeshInstance3D
		if not _check("细节滑条对应非空实 mesh " + entry[0], node != null and node.mesh != null and not node.mesh.get_faces().is_empty()): continue
		var before = _mesh_hash(node)
		_screen.controls[entry[0]].value = entry[1]
		result = _screen.flush_pending()
		_check("细节滑条改变实 mesh " + entry[0], bool(result.get("ok", false)) and before != _mesh_hash(_screen.preview.model.get_node(entry[2])), str(result.get("reason", "")))
	_screen.controls.color_mode.select(0)
	_screen.controls.color_mode.item_selected.emit(0)
	_screen.controls.moss_color_variation.value = 0.0
	_screen.flush_pending()
	var unvaried = _mesh_hash(_screen.preview.model.get_node("Moss/AttachedPatches"))
	_screen.controls.moss_color_variation.value = 0.5
	result = _screen.flush_pending()
	_check("苔藓自动色差改变实际 UV", bool(result.get("ok", false)) and unvaried != _mesh_hash(_screen.preview.model.get_node("Moss/AttachedPatches")))
	_screen.show_module(4)
	for entry in [[0, 13, "Trunk/MainTrunk", "trunk_cell"], [4, 12, "Trunk/BarkDetail", "bark_cell"], [2, 34, "Moss/AttachedPatches", "moss_cell"]]:
		_screen._color_target.select(entry[0])
		_screen._color_target.item_selected.emit(entry[0])
		_screen.palette_buttons[entry[1]].pressed.emit()
		result = _screen.flush_pending()
		_check("深化手动色格提交 " + entry[3], bool(result.get("ok", false)) and _screen.snapshot().color_mode == "manual" and int(_screen.snapshot()[entry[3]]) == entry[1])
		_check_mesh_cell(_screen.preview.model, entry[2], entry[1])
	# 通过真实配方隐藏遮挡物；近景只验收树皮和苔藓，不让草簇代替附着细节。
	_screen.controls.grass_enabled.button_pressed = false
	_screen.controls.vine_enabled.button_pressed = false
	_screen.controls.leaves_visible.button_pressed = false
	var close_result: Dictionary = _screen.flush_pending()
	_check("苔藓近景配方关闭草藤叶遮挡", bool(close_result.get("ok", false)) and not _screen.snapshot().grass_enabled and not _screen.snapshot().vine_enabled and not _screen.snapshot().leaves_visible)
	_screen.preview.select_branch("")
	var patches: MeshInstance3D = _screen.preview.model.get_node("Moss/AttachedPatches")
	var patch_arrays: Array = patches.mesh.surface_get_arrays(0)
	var patch_vertices: PackedVector3Array = patch_arrays[Mesh.ARRAY_VERTEX]
	var patch_index = 0
	for index in patch_vertices.size():
		if patch_vertices[index].y > patch_vertices[patch_index].y: patch_index = index
	var patch_center: Vector3 = patch_vertices[patch_index]
	var normal: Vector3 = patch_arrays[Mesh.ARRAY_NORMAL][patch_index]
	_screen.preview.yaw = atan2(normal.x, normal.z)
	_screen.preview.pitch = 0.12
	_screen.preview.focus_plant_bounds(AABB(patch_center - Vector3(0.45, 0.55, 0.45), Vector3(0.9, 1.1, 0.9)))
	await _capture("bark_moss_manual_close", _screen.preview.viewport)
	completed.append("details")

func _check_mesh_cell(root: Node, path: String, expected: int) -> void:
	var mesh_node = root.get_node_or_null(path) as MeshInstance3D
	var valid = mesh_node != null and mesh_node.mesh != null
	var count = 0
	if valid:
		for surface in mesh_node.mesh.get_surface_count():
			var uvs: PackedVector2Array = mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			for uv in uvs:
				count += 1
				valid = valid and floori(uv.x * 8.0) + 8 * floori(uv.y * 8.0) == expected
	_check("深化全部顶点精确手动色格 " + path, valid and count > 0, "色格 %d，顶点 %d" % [expected, count])

func _make_saved_host() -> Dictionary:
	# 仅测试层依赖房屋制作；宿主必须经真实 Generator 和 Store 落盘，不能用假墙替代。
	var workshop_recipe = load("res://src/workshop/recipe.gd")
	var generator = load("res://src/workshop/generator.gd")
	var store = load("res://addons/building_workshop/editor_store.gd").new()
	var recipe: Dictionary = workshop_recipe.authoring_defaults()
	recipe.building_id = "plant_host_%d" % Time.get_ticks_usec()
	recipe.shape = "rectangle"
	recipe.width = 8.0
	recipe.depth = 6.0
	recipe.floors = 1
	recipe.taper = 0.0
	recipe.architecture.form.enabled = false
	recipe["structural_damage"] = {"enabled": true, "shape": "jagged", "facade": "front", "center_u": 0.5, "center_y": 2.1, "width": 3.8, "height": 2.8, "roughness": 0.25, "seed": 11013}
	var reason: String = workshop_recipe.validate(recipe)
	if not _check("真实宿主 authoring_defaults 单层合法", reason.is_empty(), reason): return {}
	var built: Dictionary = generator.build(recipe)
	if not _check("真实 workshop Generator 生成破墙房屋", bool(built.get("ok", false)), str(built.get("reason", ""))): return {}
	_check("破墙 fixture 保留结构与楼板碰撞", built.root.has_node("GeneratedVisual/structure_union") and built.root.has_node("Spatial/Collision") and built.root.get_meta("damage_openings", []).size() == 1)
	var saved: Dictionary = store.export_revision(recipe, {}, "res://outputs/workshop_editor/plant_host_fixtures")
	if bool(saved.get("ok", false)):
		var packed = ResourceLoader.load(saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		_check("宿主保存场景真实重载", packed != null)
		if packed != null:
			var restored = packed.instantiate()
			_check("宿主保存保持 Generator 实际几何", _same_geometry(built.root, restored))
			restored.free()
	built.root.free()
	if not _check("真实 workshop Store 保存 res outputs", bool(saved.get("ok", false)) and str(saved.get("scene_path", "")).begins_with("res://outputs/"), str(saved.get("reason", ""))): return {}
	for key in ["scene_path", "recipe_path", "manifest_path", "catalog_path", "ledger_path"]:
		_check_saved_file(str(saved[key]))
	return saved

func _test_saved_host(completed: Array[String]) -> void:
	var saved = _make_saved_host()
	if saved.is_empty(): return
	var files_before = _bundle_hashes(saved.directory)
	_legacy_document(_screen, "camphor")
	_screen.controls.name.text = "tree_house_%d" % Time.get_ticks_usec()
	_screen.controls.name.text_changed.emit(_screen.controls.name.text)
	_screen.controls.trunk_radius.value = 0.42
	_screen.controls.bark_detail.value = 0.35
	_screen.controls.branch_start.value = 4.2
	_screen.controls.moss_amount.value = 0.45
	_screen.controls.grass_enabled.button_pressed = false
	_screen.controls.vine_enabled.button_pressed = false
	var tree_result: Dictionary = _screen.flush_pending()
	if not _check("粗干树屋配方生成", bool(tree_result.get("ok", false)), str(tree_result.get("reason", ""))): return
	var loaded: Dictionary = _screen.load_host(saved.scene_path)
	if not _check("Screen 只读加载真实保存房屋", bool(loaded.get("ok", false)) and is_instance_valid(_screen.preview.host_reference), str(loaded.get("reason", ""))): return
	var host_hash = _mesh_hash(_screen.preview.host_reference)
	var damage_index = -1
	var glass_index = -1
	for index in _screen.host_attachment.openings.size():
		var hole: Dictionary = _screen.host_attachment.openings[index]
		if hole.get("source") == "damage_openings": damage_index = index
		var suffix = str(hole.get("id", "")).trim_prefix("opening_")
		if hole.get("source") == "openings" and _screen.preview.host_reference.has_node("GeneratedVisual/glass_" + suffix): glass_index = index
	if not _check("洞选择列表含真实破墙和未移除玻璃窗", damage_index >= 0 and glass_index >= 0, str(_screen.host_attachment.openings)):
		return
	var before_pair: Dictionary = _screen.get_recovery()
	_screen._opening_picker.select(damage_index)
	_screen._opening_picker.item_selected.emit(damage_index)
	var proposed: Dictionary = _screen.propose_host_path(_screen._opening_picker.selected)
	if not _check("破墙 propose 粗干实际预检通过", bool(proposed.get("ok", false)), str(proposed.get("reason", ""))):
		_check("宿主失败仍只读", host_hash == _mesh_hash(_screen.preview.host_reference) and files_before == _bundle_hashes(saved.directory))
		return
	var success: Dictionary = _screen.get_recovery()
	var clearance: Dictionary = _screen.check_host_clearance(_screen.snapshot())
	_check("粗干检查不能以未绑定参考状态冒充通过", bool(_screen.host_binding.get("enabled", false)) and bool(clearance.get("ok", false)) and clearance.has("triangles_checked"), str(clearance))
	var hole: Dictionary = _screen.host_attachment.openings[damage_index]
	var placement: Transform3D = _screen.preview.plant_transform
	var path: Array = _screen.snapshot().trunk_path
	var center: Dictionary = path[2]
	_check("路径洞心与宿主局部坐标一致", (placement * Vector3(center.x, center.y, center.z)).distance_to(hole.center) < 0.0001)
	_check_floor_and_root(hole)
	var model_id: int = _screen.preview.model.get_instance_id()
	var shifted = placement
	shifted.origin.x += 2.65
	var blocked: Dictionary = _screen.set_host_transform(shifted)
	_check("故意 X 平移撞墙必须失败", not bool(blocked.get("ok", true)) and blocked.has("node"), str(blocked))
	_check("撞墙保留同一模型与上次成功坐标", _screen.preview.model.get_instance_id() == model_id and _screen.preview.plant_transform.is_equal_approx(placement) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(success.session.recipe))
	var pending: Dictionary = _screen.get_recovery()
	_check("撞墙请求保留实际失败 matrix 待修正", pending.host_binding.matrix == Screen.HostAttachment.encode_transform(shifted) and _screen.has_pending_fields())
	_test_failed_recovery_rollback(pending, shifted)
	var restored: Dictionary = _screen.restore_recovery(pending)
	_check("重载恢复待修正绑定及上次成功坐标", bool(restored.get("ok", false)) and _screen.host_binding == pending.host_binding and _screen.preview.plant_transform.is_equal_approx(placement), str(restored.get("host_warning", "")))
	_screen.buttons.undo.pressed.emit()
	_check("失败绑定 undo 恢复输入与应用坐标对", _screen.host_binding == success.host_binding and _screen.preview.plant_transform.is_equal_approx(placement))
	var reset: Dictionary = _screen.set_host_transform(placement)
	_check("公开 set_host_transform 恢复通过", bool(reset.get("ok", false)), str(reset.get("reason", "")))
	# restore_draft 会清历史；重建真实操作链测试 propose 的 recipe/binding 成对撤销，绝不写 Session 私有栈。
	_screen.restore_recovery(before_pair)
	var reproposed: Dictionary = _screen.propose_host_path(damage_index)
	_check("成对历史测试再次 propose 成功", bool(reproposed.get("ok", false)), str(reproposed.get("reason", "")))
	_screen.buttons.undo.pressed.emit()
	_check("propose undo 必须同时恢复配方和宿主 binding", Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(before_pair.session.recipe) and _screen.host_binding == before_pair.host_binding and _screen.preview.plant_transform.is_equal_approx(Transform3D.IDENTITY), _screen.status.text)
	_screen.buttons.redo.pressed.emit()
	_check("propose redo 必须同时恢复配方和宿主 binding", Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(success.session.recipe) and _screen.host_binding == success.host_binding and _screen.preview.plant_transform.is_equal_approx(placement), _screen.status.text)
	_screen.restore_recovery(success)
	var nudged = placement
	nudged.origin.x += 0.08
	_screen._begin_drag("host_x")
	var unchanged: Dictionary = _screen.set_host_transform(placement)
	_check("宿主拖拽首个无变化值不创建合并历史", bool(unchanged.get("ok", false)) and not _screen.session.can_undo())
	var moved: Dictionary = _screen.set_host_transform(nudged)
	_screen._end_drag(true)
	_check("合法宿主微移通过且保持树配方", bool(moved.get("ok", false)) and _screen.preview.plant_transform.is_equal_approx(nudged) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(success.session.recipe), str(moved.get("reason", "")))
	_screen.buttons.undo.pressed.emit()
	_check("纯宿主坐标操作也可公开 undo 成对恢复", _screen.host_binding == success.host_binding and _screen.preview.plant_transform.is_equal_approx(placement) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(success.session.recipe), _screen.status.text)
	_screen.restore_recovery(success)
	model_id = _screen.preview.model.get_instance_id()
	_screen._opening_picker.select(glass_index)
	var glass: Dictionary = _screen.propose_host_path(glass_index)
	_check("普通玻璃窗 propose 必须拒绝实际阻挡", not bool(glass.get("ok", true)) and glass.has("node"), str(glass))
	# 另用窄干只穿窗心，不让窗框/楼板先命中掩盖漏检玻璃；玻璃始终保留原 mesh。
	var window: Dictionary = _screen.host_attachment.openings[glass_index]
	var normal: Vector3 = window.normal.normalized()
	var probe: Dictionary = _screen.snapshot()
	probe.trunk_radius = 0.04
	probe.trunk_path = []
	for point in [Vector3.ZERO, normal * 0.8 + Vector3.UP * 0.35, normal * 1.6 + Vector3.UP * 0.7, normal * 3.0 + Vector3.UP * float(probe.height)]:
		probe.trunk_path.append({"x": point.x, "y": point.y, "z": point.z})
	probe.trunk_path[-1].y = float(probe.height)
	var probe_transform = Transform3D(Basis.IDENTITY, window.center - normal * 0.8 - Vector3.UP * 0.35)
	var glass_hit: Dictionary = _screen.host_attachment.check_clearance(probe, probe_transform)
	_check("普通窗中心线实际玻璃 mesh 必须阻挡", not bool(glass_hit.get("ok", true)) and str(glass_hit.get("node", "")).to_lower().contains("glass"), str(glass_hit))
	_check("玻璃窗失败不换模型不改成功路径坐标", _screen.preview.model.get_instance_id() == model_id and _screen.preview.plant_transform.is_equal_approx(placement) and Recipe.fingerprint(_screen.snapshot()) == Recipe.fingerprint(success.session.recipe))
	_screen.buttons.undo.pressed.emit()
	_check("玻璃窗失败 undo 成对撤回路径与绑定输入", _screen.host_binding == success.host_binding and not _screen.has_pending_fields())
	_screen.restore_recovery(success)
	_screen.preview.select_branch("")
	_screen.preview.set_view("perspective")
	# front 是 -Z；默认 +Z 视角会把破墙藏到房屋背面。
	_screen.preview.yaw = PI + 0.55
	_screen.preview.pitch = 0.26
	_screen.preview.fit_model()
	await _capture("tree_house_whole", _screen.preview.viewport)
	var center_world: Vector3 = _screen.preview.host_reference.global_transform * hole.center
	_screen.preview.focus_bounds(AABB(center_world - Vector3(2.3, 1.8, 1.6), Vector3(4.6, 3.6, 3.2)))
	await _capture("tree_house_breach_trunk_close", _screen.preview.viewport)
	_test_host_exports(completed)
	_check("所有宿主操作不修改只读房屋几何", host_hash == _mesh_hash(_screen.preview.host_reference))
	_check("宿主整个保存版本所有文件逐字节不变", files_before == _bundle_hashes(saved.directory))
	completed.append("host")

func _test_failed_recovery_rollback(pending: Dictionary, blocked_transform: Transform3D) -> void:
	var before: Dictionary = _screen.get_recovery()
	var undo_before: Dictionary = _screen.session.peek_undo()
	var redo_before: Dictionary = _screen.session.peek_redo()
	var model_id: int = _screen.preview.model.get_instance_id()
	var host_id: int = _screen.preview.host_reference.get_instance_id()
	var placement: Transform3D = _screen.preview.plant_transform
	var camera: Transform3D = _screen.preview.camera.transform
	var dirty: Array = [_screen.session.is_dirty(), _screen.session.is_recipe_dirty(), _screen.session.is_context_dirty()]
	for failure in ["缺失宿主", "已应用坐标撞墙", "保存指纹非法", "保存上下文非法"]:
		var invalid: Dictionary = pending.duplicate(true)
		match failure:
			"缺失宿主":
				invalid.session.authoring_context.host_binding.host_path = "res://outputs/missing_recovery_host/building.tscn"
			"已应用坐标撞墙":
				invalid.session.authoring_context.host_binding.matrix = Screen.HostAttachment.encode_transform(blocked_transform)
			"保存指纹非法":
				invalid.session.authoring_context.host_binding = {}
				invalid.session.saved_fingerprint = "invalid saved fingerprint"
			"保存上下文非法":
				invalid.session.saved_authoring_context = {"host_binding": "invalid"}
		var result: Dictionary = _screen.restore_recovery(invalid)
		_check("失败草稿必须拒绝 " + failure, not bool(result.get("ok", true)), str(result.get("reason", "")))
		_check("失败草稿完整保留文档与待修正输入 " + failure, _screen.get_recovery() == before and _screen.has_pending_fields())
		_check("失败草稿保留历史事务及 dirty " + failure, _screen.session.peek_undo() == undo_before and _screen.session.peek_redo() == redo_before and dirty == [_screen.session.is_dirty(), _screen.session.is_recipe_dirty(), _screen.session.is_context_dirty()])
		_check("失败草稿不换模型宿主坐标摄像头 " + failure, _screen.preview.model.get_instance_id() == model_id and _screen.preview.host_reference.get_instance_id() == host_id and _screen.preview.plant_transform.is_equal_approx(placement) and _screen.preview.camera.transform.is_equal_approx(camera))
		_check("失败草稿 pending 坐标滑条不被成功坐标覆盖 " + failure, is_equal_approx(_screen._host_offsets.x.value, snappedf(blocked_transform.origin.x, _screen._host_offsets.x.step)) and is_equal_approx(_screen._host_offsets.y.value, snappedf(blocked_transform.origin.y, _screen._host_offsets.y.step)) and is_equal_approx(_screen._host_offsets.z.value, snappedf(blocked_transform.origin.z, _screen._host_offsets.z.step)))

func _check_floor_and_root(hole: Dictionary) -> void:
	var host: Node3D = _screen.preview.host_reference
	var mesh_node: MeshInstance3D = host.get_node("GeneratedVisual/structure_union")
	var triangles = TriangleMesh.new()
	triangles.create_from_faces(mesh_node.mesh.get_faces())
	var origin: Vector3 = _screen.preview.plant_transform.origin
	var floor_hit: Dictionary = triangles.intersect_segment(Vector3(origin.x, 0.3, origin.z), Vector3(origin.x, -0.4, origin.z))
	_check("根下真实楼板未切洞", not floor_hit.is_empty(), str(floor_hit))
	var wall_floor: Vector3 = hole.center
	wall_floor.y = 0.3
	_check("破墙正下方楼板未切", not triangles.intersect_segment(wall_floor, wall_floor - Vector3.UP * 0.7).is_empty())
	var trunk: MeshInstance3D = _screen.preview.model.get_node("Trunk/MainTrunk")
	var vertices: PackedVector3Array = trunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var minimum = INF
	for vertex in vertices:
		minimum = minf(minimum, (_screen.preview.plant_transform * vertex).y)
	var floor_y: float = float(floor_hit.get("position", Vector3.ZERO).y)
	_check("树根实际网格落楼板顶且不悬浮穿板", not floor_hit.is_empty() and minimum >= floor_y - 0.002 and minimum <= floor_y + 0.02, "实际最低点 %.5fm，楼板顶 %.5fm，根原点 %s" % [minimum, floor_y, str(origin)])
	# 明确验证真实贴板候选；不能通过删除楼板或关闭 clearance 制造通过。
	var recovery: Dictionary = _screen.get_recovery()
	var grounded: Transform3D = _screen.preview.plant_transform
	var drop = minimum - floor_y - 0.006
	grounded.origin.y -= drop
	var controls: Array = _screen.snapshot().trunk_path.duplicate(true)
	for index in range(1, controls.size() - 1): controls[index].y = float(controls[index].y) + drop
	_screen.input_recipe.trunk_path = controls
	var result: Dictionary = _screen.set_host_transform(grounded)
	_check("保留楼板的贴板根候选必须通过粗干检查", bool(result.get("ok", false)), str(result))
	_screen.restore_recovery(recovery)

func _test_host_exports(completed: Array[String]) -> void:
	for entry in [["res://outputs/a", "res://outputs/a/plant.tscn", "plant.tscn"], ["res://outputs/a", "res://outputs/a/子目录/plant.tscn", "子目录/plant.tscn"], ["res://outputs/a/结合描述", "res://outputs/a/plant.tscn", "../plant.tscn"], ["res://scenes/workshop_plants/a", "res://outputs/host/building.tscn", "../../../outputs/host/building.tscn"]]:
		_check("结合描述相对路径分段 " + entry[2], _screen._relative_manifest_path(entry[0], entry[1]) == entry[2])
	var expected: Dictionary = _screen.get_recovery()
	var first: Dictionary = _screen.save_recipe()
	if not _check("树屋静态树版本真实保存", bool(first.get("ok", false)), str(first.get("reason", ""))): return
	_check_export_bundle(first, false)
	_check("植物保存不清未导出宿主结合的 dirty", not _screen.session.is_recipe_dirty() and _screen.session.is_context_dirty() and _screen.session.is_dirty())
	var static_binding: Dictionary = _screen.save_attachment_manifest("")
	_check_binding_json(static_binding, first.scene_path, expected.host_binding)
	_check("结合描述落盘后才清宿主 dirty", not _screen.session.is_context_dirty() and not _screen.session.is_dirty())
	var nested_directory: String = str(first.directory).path_join("结合描述 子目录")
	_check("结合描述嵌套测试目录可创建", DirAccess.make_dir_recursive_absolute(nested_directory) == OK)
	var nested_path: String = nested_directory.path_join("attachment.json")
	var nested_binding: Dictionary = _screen.save_attachment_manifest(nested_path)
	_check_binding_json(nested_binding, first.scene_path, expected.host_binding)
	if bool(nested_binding.get("ok", false)):
		_check("结合描述嵌套目录向上引用植物文件", str(nested_binding.manifest.plant_path) == "../plant.tscn")
		var saved_hash = _hash(nested_path)
		var duplicate: Dictionary = _screen.save_attachment_manifest(nested_path)
		_check("结合描述拒绝覆盖且原文件逐字节不变", not bool(duplicate.get("ok", true)) and saved_hash == _hash(nested_path))
	var first_hashes = _bundle_hashes(first.directory)
	_screen.controls.bark_detail.value = 0.55
	var edit: Dictionary = _screen.flush_pending()
	_check("动态保存前真实修改新树版本", bool(edit.get("ok", false)))
	var stale: Dictionary = _screen.save_attachment_manifest(str(first.directory).path_join("stale_attachment.json"))
	_check("结合描述拒绝引用过期树版本且不留文件", not bool(stale.get("ok", true)) and not FileAccess.file_exists(str(first.directory).path_join("stale_attachment.json")), str(stale.get("reason", "")))
	var second: Dictionary = _screen.save_animated()
	if not _check("树屋动态 Store.save_animated 必须成功", bool(second.get("ok", false)), str(second.get("reason", ""))): return
	_check("动态保存新增 tree revision", second.directory != first.directory and int(second.revision) > int(first.revision))
	_check_export_bundle(second, true)
	var dynamic_binding: Dictionary = _screen.save_attachment_manifest("")
	_check_binding_json(dynamic_binding, second.animated_scene_path, expected.host_binding)
	_check("静态旧树与 binding 文件保持不可变", first_hashes == _bundle_hashes(first.directory))
	var recovery: Dictionary = _screen.get_recovery()
	var loaded: Dictionary = _screen.open_recipe(second.recipe_path)
	_check("新树配方真实打开不偷带宿主", bool(loaded.get("ok", false)) and _screen.host_binding.is_empty() and Recipe.fingerprint(_screen.snapshot()) == str(second.fingerprint))
	var restored: Dictionary = _screen.restore_recovery(recovery)
	var decoded: Dictionary = Screen.HostAttachment.decode_transform(recovery.host_binding.matrix)
	_check("公开 recovery 恢复新树版本和宿主坐标", bool(restored.get("ok", false)) and not restored.has("host_warning") and _screen.last_export == second and _screen.host_binding == recovery.host_binding and _screen.preview.plant_transform.is_equal_approx(decoded.transform) and Recipe.fingerprint(_screen.snapshot()) == str(second.fingerprint), str(restored.get("host_warning", "")))
	completed.append("host_exports")

func _check_binding_json(result: Dictionary, plant_path: String, binding: Dictionary) -> void:
	if not _check("结合描述真实导出 " + plant_path.get_file(), bool(result.get("ok", false)), str(result.get("reason", ""))): return
	var path: String = result.path
	_check_saved_file(path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not _check("结合描述写盘重载 JSON 对象", parsed is Dictionary): return
	_check("结合描述只保存非空相对文件引用", not str(parsed.get("host_path", "")).is_empty() and not str(parsed.get("plant_path", "")).is_empty() and str(parsed.host_path).is_relative_path() and str(parsed.plant_path).is_relative_path())
	var base = ProjectSettings.globalize_path(path.get_base_dir())
	var host_path = base.path_join(str(parsed.get("host_path", ""))).simplify_path()
	var tree_path = base.path_join(str(parsed.get("plant_path", ""))).simplify_path()
	_check("binding JSON 引用准确新 tree 版本及只读 host", tree_path == ProjectSettings.globalize_path(plant_path).simplify_path() and host_path == ProjectSettings.globalize_path(binding.host_path).simplify_path() and FileAccess.file_exists(tree_path) and FileAccess.file_exists(host_path))
	var decoded: Dictionary = Screen.HostAttachment.decode_transform(parsed.get("matrix"))
	var expected: Dictionary = Screen.HostAttachment.decode_transform(binding.matrix)
	_check("binding JSON 保留宿主坐标与洞口 ID", bool(decoded.get("ok", false)) and decoded.transform.is_equal_approx(expected.transform) and parsed.get("opening_id") == binding.opening_id and parsed.get("matrix_layout") == "column_major" and parsed.get("coordinate_space") == "plant_to_host_root" and parsed.get("candidate_only") == true)

func _check_export_bundle(result: Dictionary, animated: bool) -> void:
	for key in ["recipe_path", "scene_path", "manifest_path"]:
		_check_saved_file(str(result.get(key, "")))
	if animated: _check_saved_file(str(result.get("animated_scene_path", "")))
	for key in (["scene_path", "animated_scene_path"] if animated else ["scene_path"]):
		var packed = ResourceLoader.load(str(result.get(key, "")), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		if not _check("深化导出 PackedScene 实际重载 " + key, packed != null): continue
		var root = packed.instantiate()
		_check("深化导出实际几何与成功预览一致 " + key, _same_geometry(root, _screen.preview.model))
		if key == "scene_path":
			_check("深化静态导出无运行脚本与预览节点", _static_tree(root))
		else:
			var safe = root.get_script() == Screen.Store.WindRuntime
			for node in _walk(root):
				if node != root and node.get_script() != null: safe = false
			_check("深化动态旁车仅唯一风脚本", safe and root.has_method("sample_at"))
		root.free()

func _check_saved_file(path: String) -> void:
	_check("深化保存文件存在且非空 " + path, FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > 0)
	if FileAccess.file_exists(path): _artifacts.append(path)

func _bundle_hashes(directory: String) -> Dictionary:
	var result: Dictionary = {}
	var dir = DirAccess.open(directory)
	if not _check("深化版本目录存在 " + directory, dir != null): return result
	for filename in dir.get_files(): result[filename] = _hash(directory.path_join(filename))
	return result

func _test_fixed_wind_frames(completed: Array[String]) -> void:
	var sampled: Array[String] = []
	for species in Recipe.SPECIES:
		await _test_species_wind_frames(species, sampled)
	for species in Recipe.SPECIES:
		_check("树种真实风帧专项完整返回 " + species, sampled.has(species))
	completed.append("wind")

func _test_species_wind_frames(species: String, sampled: Array[String], mode: String = "geometry") -> void:
	print("[plant-editor-stage] wind ", species, "/", mode, " build")
	if mode == "geometry":
		_legacy_document(_screen, species)
	else:
		_screen.new_document(species)
		_screen._field("foliage_mode", mode)
	var prefix = ("" if species == "camphor" else species + "_") if mode == "geometry" else mode + "_" + species + "_"
	_screen.controls.name.text = "wind_frames_%s_%d" % [species, Time.get_ticks_usec()]
	_screen.controls.name.text_changed.emit(_screen.controls.name.text)
	_screen.controls.bark_detail.value = 0.4
	_screen.controls.moss_amount.value = 0.6
	_screen.controls.wind_strength.value = 1.0
	_screen.controls.grass_enabled.button_pressed = false
	_screen.controls.vine_enabled.button_pressed = false
	_screen.flush_pending()
	print("[plant-editor-stage] wind ", species, "/", mode, " save")
	var saved: Dictionary = _screen.save_animated()
	print("[plant-editor-stage] wind ", species, "/", mode, " saved")
	if not _check("确定风帧使用真实保存的动态旁车", bool(saved.get("ok", false)), str(saved.get("reason", ""))): return
	_check_export_bundle(saved, true)
	print("[plant-editor-stage] wind ", species, "/", mode, " bundle checked")
	var packed = ResourceLoader.load(saved.animated_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if not _check("风旁车可实例化采样", packed != null): return
	var model: Node3D = packed.instantiate()
	_screen.preview.viewport.add_child(model)
	model.set_process(false)
	_screen.preview.set_active(true)
	_screen.preview.set_process(false)
	_screen.preview.select_branch("")
	_screen.preview.set_view("perspective")
	_screen.preview.fit_model()
	_screen.preview.model.visible = false
	var geometry = _mesh_hash(model)
	var color_data = _wind_color_data(model)
	var clock: float = _screen.preview.local_time
	print("[plant-editor-stage] wind ", species, "/", mode, " sampling")
	var a = await _sample_wind_png(model, 0.0, prefix + "wind_t0000")
	var b = await _sample_wind_png(model, 2.75, prefix + "wind_t0275")
	_check("风两时刻真实 PNG 像素可见变化 " + species, _pixel_difference(a, b) > 20, "变化像素 %d" % _pixel_difference(a, b))
	var repeated = await _sample_wind_png(model, 0.0, prefix + "wind_t0000_repeat")
	_check("风固定时刻重采样像素确定", _pixel_difference(a, repeated) == 0)
	_check("截图期间停止 process 保持预览 clock", not model.is_processing() and not _screen.preview.is_processing() and _screen.preview.local_time == clock)
	model.get_node("Leaves").visible = false
	var fixed_a = await _sample_wind_png(model, 0.0, prefix + "wind_trunk_moss_t0000")
	var fixed_b = await _sample_wind_png(model, 2.75, prefix + "wind_trunk_moss_t0275")
	_check("树干树皮苔藓真实颜色和轮廓固定 " + species, _pixel_difference(fixed_a, fixed_b) == 0, "变化像素 %d" % _pixel_difference(fixed_a, fixed_b))
	model.get_node("Trunk").visible = false
	model.get_node("Moss").visible = false
	var empty = await _sample_wind_png(model, 0.0, prefix + "wind_empty_control")
	_check("固定颜色对照不是空画面", _pixel_difference(fixed_a, empty) > 100)
	model.get_node("Leaves").visible = true
	var leaf_a = await _sample_wind_png(model, 0.0, prefix + "wind_leaves_t0000")
	var leaf_b = await _sample_wind_png(model, 2.75, prefix + "wind_leaves_t0275")
	_check("可见叶片单独两帧像素变化 " + species, _pixel_difference(leaf_a, leaf_b) > 20 and _pixel_difference(leaf_a, empty) > 100, "叶变化像素 %d" % _pixel_difference(leaf_a, leaf_b))
	_check("风采样不改 CPU 几何及 COLOR", geometry == _mesh_hash(model) and color_data == _wind_color_data(model))
	model.free()
	_screen.preview.model.visible = true
	_screen.preview.set_active(true)
	sampled.append(species)

func _wind_color_data(root: Node) -> Dictionary:
	var data: Dictionary = {}
	var fixed_count = 0
	var leaf_moving = 0
	var fixed_valid = true
	for node in _walk(root):
		if not node is MeshInstance3D or node.mesh == null: continue
		for surface in node.mesh.get_surface_count():
			var material = node.get_active_material(surface) as ShaderMaterial
			if material == null: continue
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if not _check("风实际 COLOR 通道存在 " + str(node.name), arrays[Mesh.ARRAY_COLOR] is PackedColorArray): continue
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			data[str(root.get_path_to(node)) + "/%d" % surface] = colors
			_check("风 COLOR 覆盖全部实际顶点 " + str(node.name), colors.size() == arrays[Mesh.ARRAY_VERTEX].size() and not colors.is_empty())
			for color in colors:
				if material.resource_name in ["Plant_trunk", "Plant_moss"]:
					fixed_count += 1
					fixed_valid = fixed_valid and color == Color(0, 0, 0, 1)
				elif material.resource_name == "Plant_leaf" and color.r > 0.05:
					leaf_moving += 1
	_check("树干苔藓逐顶点 COLOR 固定而叶权重非零", fixed_count > 0 and fixed_valid and leaf_moving > 0)
	return data

func _sample_wind_png(model: Node3D, seconds: float, name: String) -> Image:
	model.set_process(false)
	model.call("sample_at", seconds)
	await _capture(name, _screen.preview.viewport)
	var path = IMAGE_ROOT.path_join(name + ".png")
	_check_saved_file(path)
	var fixed_clock = true
	for node in _walk(model):
		if not node is MeshInstance3D or node.mesh == null: continue
		for surface in node.mesh.get_surface_count():
			var material = node.get_active_material(surface) as ShaderMaterial
			if material != null:
				fixed_clock = fixed_clock and is_equal_approx(float(material.get_shader_parameter("local_time")), seconds)
	_check("确定风截图所有材质时刻固定 " + name, fixed_clock)
	return Image.load_from_file(path)

func _pixel_difference(a: Image, b: Image) -> int:
	if a == null or b == null or a.is_empty() or b.is_empty() or a.get_size() != b.get_size(): return -1
	var left = a.duplicate() as Image
	var right = b.duplicate() as Image
	left.convert(Image.FORMAT_RGBA8)
	right.convert(Image.FORMAT_RGBA8)
	var x = left.get_data()
	var y = right.get_data()
	var count = 0
	for index in range(0, x.size(), 4):
		if x[index] != y[index] or x[index + 1] != y[index + 1] or x[index + 2] != y[index + 2]: count += 1
	return count

func _test_compact_panels(completed: Array[String]) -> void:
	var fixture = PanelContainer.new()
	fixture.name = "PlantDeepCompact860x600"
	fixture.position = Vector2(4, 4)
	fixture.size = Vector2(860, 600)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#14261f")
	fixture.add_theme_stylebox_override("panel", background)
	EditorInterface.get_base_control().add_child(fixture)
	var compact = Screen.new()
	fixture.add_child(compact)
	compact.set_screen_visible(true)
	_legacy_document(compact, "camphor")
	compact.show_module(0)
	compact.buttons.path_panel.pressed.emit()
	compact.buttons.host_panel.pressed.emit()
	compact.buttons.path_insert.pressed.emit()
	compact.flush_pending()
	await _frames(5)
	for module in [0, 3, 5]:
		compact.show_module(module)
		await _frames(2)
		_check("深化紧凑展开面板不回退 %d" % module, fixture.size.x <= 861 and fixture.size.y <= 601 and compact.parameter_scroll.size.x >= 280 and compact.parameter_scroll.size.x <= 320 and compact.preview.size.x > compact.parameter_scroll.size.x and compact.preview.size.y >= 420, str(fixture.size))
		_check("深化紧凑工具栏模块仍单行 %d" % module, _row_fits(compact.toolbar, compact.size.x) and _row_fits(compact.module_bar, compact.preview.size.x))
	compact.show_module(0)
	await _frames(3)
	compact.parameter_scroll.ensure_control_visible(compact.buttons.host_route)
	compact.preview.select_branch("")
	await _frames(3)
	_check("深化宿主路径按钮确实滚入可视区", compact.parameter_scroll.get_global_rect().encloses(compact.buttons.host_route.get_global_rect()) and compact.parameter_scroll.scroll_vertical > 0)
	RenderingServer.force_draw()
	var crop: Image = _tree.root.get_texture().get_image().get_region(Rect2i(Vector2i(fixture.global_position), Vector2i(fixture.size)))
	var path = IMAGE_ROOT.path_join("compact_860x600_host_path.png")
	_check("深化紧凑路径宿主面板真实裁图", crop.get_size() == Vector2i(860, 600) and crop.save_png(path) == OK)
	_check_saved_file(path)
	compact.set_screen_visible(false)
	fixture.queue_free()
	await _frames(2)
	completed.append("compact_panels")

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
	# 确定风帧会停本地process；编辑器按需重绘时不能等待一个尚未请求的帧。
	RenderingServer.force_draw()
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
	for source in _source_snapshot:
		_check("隔离源码快照未变 " + source, _source_snapshot[source] == _hash("res://" + source))
	var report = {"source_snapshot_sha256": _source_snapshot, "verification_scope": "历史1174专项保留legacy geometry夹具；新增volumes/cards/geometry UI及compact、volumes/cards三树种真实风帧；仅本次隔离快照，主线程统一联测", "checks": _checks, "check_count": _checks.size(), "failures": _failures, "failure_count": _failures.size(), "artifacts": _artifacts, "editor": Engine.is_editor_hint(), "art_review": "pending", "project": ProjectSettings.globalize_path("res://"), "boundary": "独立 minimal 双插件编辑器；不运行 Main；不写生产工程；不写草稿"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	var file = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("报告无法写入")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[plant-editor] %d checks, %d failures" % [_checks.size(), _failures.size()])
	_tree.quit(0 if _failures.is_empty() else 1)
