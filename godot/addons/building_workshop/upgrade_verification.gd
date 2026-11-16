@tool
extends RefCounted
## 当前升级的真实EditorPlugin验收；不运行Main，也不以固定桌面分辨率冒充截图验收。
const Generator = preload("res://src/workshop/generator.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Session = preload("res://src/workshop/session.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Union = preload("res://src/workshop/shell_union_geometry.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const Adapter = preload("res://addons/building_workshop/catalog_adapter.gd")
const RandomRecipe = preload("res://src/workshop/random_recipe.gd")
var checks: Array = []
var failures: Array[String] = []
var artifacts: Array[String] = []
var timings: Array = []
var layout_metrics: Array = []
var screen: Control
var plugin: EditorPlugin
var original_scene: Node
var original_pause: bool

static func run(editor_plugin: EditorPlugin) -> void:
	var verifier: RefCounted = load("res://addons/building_workshop/upgrade_verification.gd").new()
	await verifier.execute(editor_plugin)

func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks.append({"name": label, "passed": ok, "detail": str(detail)})
	if not ok:
		failures.append(label + ": " + str(detail))
		printerr("FAIL [workshop-upgrade] ", label, " ", detail)

func execute(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin
	screen = plugin.screen
	original_scene = EditorInterface.get_edited_scene_root()
	original_pause = plugin.get_tree().paused
	check(Engine.is_editor_hint() and not EditorInterface.is_playing_scene(), "真实编辑器且未运行游戏")
	check(not ProjectSettings.has_setting("autoload/Zones") and not ProjectSettings.has_setting("autoload/GameState"), "隔离副本无游戏Autoload")
	check(ProjectSettings.globalize_path("res://").contains("sea-work/verification/"), "只写工程外隔离副本")
	plugin._make_visible(true)
	EditorInterface.set_main_screen_editor("老王场景工坊")
	screen.configure({"export_root": "res://outputs/workshop_editor"})
	await plugin.get_tree().process_frame
	var top_info: Node = screen.find_child("WorkshopTopInfo", true, false)
	var top_modules: Control = screen.find_child("WorkshopTopModuleBar", true, false) as Control
	var default_modules: Control = screen.find_child("WorkshopDefaultModules", true, false) as Control
	check(top_info is AcceptDialog and not (top_info as AcceptDialog).visible, "建筑信息按需打开，不常驻占空间")
	check(top_modules != null and screen._preview_column.is_ancestor_of(top_modules), "模块横栏位于红框要求的预览上方")
	check(default_modules != null and default_modules.get_child_count() == screen.DEFAULT_MODULES.size() and not screen._defaults_dialog.visible, "默认模组按需打开，不常驻占空间")
	check(not screen._right_panel.visible, "右侧槽位栏默认收起")
	check(screen._left_panel.find_child("building_id", true, false) == null and screen._left_panel.find_child("module_00", true, false) == null, "左侧编辑区不重复放置身份和模块导航")
	for item: Dictionary in screen.DEFAULT_MODULES:
		var default_path: String = screen.SAMPLE_ROOT.path_join(str(item.file))
		var default_file: FileAccess = FileAccess.open(default_path, FileAccess.READ)
		var parsed_default: Variant = JSON.parse_string(default_file.get_as_text()) if default_file != null else null
		if default_file != null:
			default_file.close()
		check(parsed_default is Dictionary, "默认模组JSON可读取 " + str(item.label), default_path)
		if parsed_default is Dictionary:
			var default_reason: String = Recipe.validate(parsed_default as Dictionary, Catalog.definitions())
			check(default_reason.is_empty(), "默认模组配方合规 " + str(item.label), default_reason)
	await verify_authoring_defaults()
	await verify_generation_adjustment()
	await verify_repair_review()
	await verify_palette_target_transactions()
	var recipe: Dictionary = Recipe.authoring_defaults()
	# 此旧拒绝用例专测3.6m层高，不把新默认5.1m误判为原夹具。
	recipe.floor_height = 3.6
	recipe.slab_thickness = 0.18
	recipe.architecture.pilaster.width = 0.36
	recipe.building_id = "upgrade_live"
	recipe.architecture.form.enabled = false
	recipe.taper = 0.0
	var accepted: Dictionary = screen.session.new_document("upgrade_live", recipe)
	check(bool(accepted.ok), "默认楼房真实union可创建", accepted.get("reason", ""))
	if not bool(accepted.ok):
		finish()
		return
	screen._refresh_from_session()
	check(bool(screen.refresh_preview().ok), "默认楼房真实预览")
	screen._select_page(screen.PAGES.find("门窗"))
	screen.preview.set_view("perspective")
	await plugin.get_tree().process_frame
	check_structure("默认")
	var bounds: Dictionary = {"width": 3.75, "height": 4.75, "frame_width": 0.275, "frame_depth": 0.30, "glass_thickness": 0.05, "sill_projection": 0.45, "sill_thickness": 0.25, "sill_extension": 0.20}
	for field: String in Config.WINDOW_BOUNDS:
		var key: String = "architecture_window_" + field
		check(screen.controls.get(key) is HSlider, "窗参数为HSlider " + field)
		if bounds.has(field):
			check((screen.controls[key] as Range).max_value >= float(bounds[field]), "上限至少默认2.5倍 " + field)
	var camera: Transform3D = screen.preview.camera.transform
	var clean_hash: String = visual_hash()
	await capture("01_default")
	# 不点应用按钮：value_changed -> Timer -> Session真实生成 -> 替换预览。
	screen.controls.width.value = 14.0
	var old_undo: int = screen.session._undo.size()
	screen.controls.architecture_window_frame_width.emit_signal("drag_started")
	screen.controls.architecture_window_frame_width.value = 0.22
	await settle("框宽0.22自动预览")
	check(is_equal_approx(float(screen.snapshot().architecture.window.frame_width), 0.22), "无需应用按钮自动提交")
	check(clean_hash != visual_hash(), "实际渲染网格改变，不只改snapshot")
	check(screen.preview.camera.transform.is_equal_approx(camera), "滑块预览保持相机")
	screen.controls.architecture_window_frame_width.value = 0.275
	await settle("框宽2.5倍")
	check(screen.session._undo.size() == old_undo + 1, "一次拖动仅一条撤销")
	screen.controls.architecture_window_frame_width.emit_signal("drag_ended", true)
	check(is_equal_approx(float(screen.snapshot().width), 12.0) and is_equal_approx(screen.controls.width.value, 14.0), "不提交不丢失其它楼宽输入")
	await capture("02_thick_frame_2p5")
	screen.controls.width.value = 12.0
	var valid: String = Recipe.fingerprint(screen.snapshot())
	var valid_hash: String = visual_hash()
	screen.controls.architecture_window_height.value = 4.75
	await settle("层高不足必须拒绝", false)
	check(Recipe.fingerprint(screen.snapshot()) == valid and visual_hash() == valid_hash, "无效尺寸保留上一成功模型及配方")
	check(is_equal_approx(screen.controls.architecture_window_height.value, 4.75), "失败保留滑块输入及原因")
	screen.controls.architecture_window_height.value = 1.9
	await settle("修正无效输入")
	# 2.5倍净窗需真实可用开间和层高；不缩小洞口或偷偷改楼房。
	recipe = Recipe.authoring_defaults()
	recipe.merge({"building_id": "upgrade_large", "width": 12.0, "depth": 12.0, "bay_width": 6.0, "floor_height": 6.8, "floors": 2, "taper": 0.0, "slab_thickness": 0.18}, true)
	recipe.architecture.pilaster.width = 0.36
	recipe.architecture.form.enabled = false
	accepted = screen.session.new_document("upgrade_large", recipe)
	check(bool(accepted.ok), "大开间高楼层fixture", accepted.get("reason", ""))
	if not bool(accepted.ok):
		finish()
		return
	screen._reset_window_preview()
	screen._refresh_from_session()
	screen.refresh_preview()
	screen.preview.set_view("perspective")
	screen.controls.architecture_window_width.value = 3.75
	screen.controls.architecture_window_height.value = 4.75
	screen.controls.architecture_window_frame_width.value = 0.275
	screen.controls.architecture_window_frame_depth.value = 0.30
	screen.controls.architecture_window_glass_thickness.value = 0.05
	screen.controls.architecture_window_sill_projection.value = 0.45
	screen.controls.architecture_window_sill_thickness.value = 0.25
	screen.controls.architecture_window_sill_extension.value = 0.20
	await settle("2.5倍窗和框真实组合")
	var actual_window: Dictionary = {}
	for opening: Dictionary in screen._opening_cache.values():
		if str(opening.get("type", "")) == "window":
			actual_window = opening
			break
	check(not actual_window.is_empty(), "存在真实窗洞")
	check(is_equal_approx(float(actual_window.get("clear_width", 0.0)), 3.75) and is_equal_approx(float(actual_window.get("clear_height", 0.0)), 4.75), "实际净洞达到3.75x4.75m", actual_window)
	check_structure("大窗")
	await capture("03_large_windows_2p5")
	# 局部作用域不串全局。
	for scope: String in ["floor", "facade", "single"]:
		screen._set_option("window_scope", scope)
		screen._window_scope_changed(screen.ARCHITECTURE_WINDOW_SCOPES.find(scope))
		screen.controls.architecture_window_frame_width.value = {"floor": 0.28, "facade": 0.285, "single": 0.29}[scope]
		await settle(scope + "局部实时预览")
		check(is_equal_approx(float(screen.snapshot().architecture.window.frame_width), 0.275), scope + "不改全局")
	# 结构开关重建真正单mesh，而非隐藏拼装件。
	for enabled: bool in [false, true]:
		var architecture: Dictionary = screen.snapshot().architecture.duplicate(true)
		architecture.pilaster.enabled = enabled
		architecture.band.enabled = enabled
		var changed: Dictionary = screen.session.apply_patch({"architecture": architecture})
		check(bool(changed.ok), "柱腰线开关 " + str(enabled), changed.get("reason", ""))
		screen._refresh_from_session()
		screen.refresh_preview()
		check_structure("开关" + str(enabled))
		await capture("04_structure_" + ("on" if enabled else "off"))
	# 语义源模块仍可独立导出，不把无mesh槽误当失败。
	for id: String in ["wall_shell_0", "pilaster_0_c0", "band_0_0"]:
		var exported: Dictionary = Adapter.export_slot(screen.session, id)
		check(bool(exported.ok), "编辑源模块导出 " + id, exported.get("reason", ""))
		if bool(exported.ok):
			var file: FileAccess = FileAccess.open(exported.manifest_path, FileAccess.READ)
			var manifest: Dictionary = JSON.parse_string(file.get_as_text())
			file.close()
			check(str(manifest.layout.geometry_scope) == "semantic_source_module", "模块标明编辑源而非融合切片 " + id)
	var saved: Dictionary = screen.save_building()
	check(bool(saved.ok), "五件bundle实际保存重载", saved.get("reason", ""))
	if bool(saved.ok):
		var packed: PackedScene = ResourceLoader.load(saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var restored: Node3D = packed.instantiate()
		var mesh: Mesh = restored.get_node("GeneratedVisual/structure_union").mesh
		check(bool(Union.audit_faces(mesh.get_faces()).valid), "静态保存的一体网格严格拓扑")
		check(not contains_csg(restored), "导出无CSG及重建脚本")
		restored.free()
		artifacts.append(ProjectSettings.globalize_path(saved.scene_path))
	await capture("05_editor_sliders", true)
	await verify_vegetation()
	await verify_shading()
	await verify_palette()
	await verify_random_house()
	await verify_compact_layout()
	await verify_structural_damage()
	finish()

func verify_authoring_defaults() -> void:
	screen._new_document()
	check(screen.snapshot().floor_height == 5.1 and screen.snapshot().slab_thickness == 0.2 and screen.snapshot().architecture.pilaster.width == 0.5, "新建按钮实际作者默认5.1/0.2/0.5")
	check(screen.snapshot().architecture.shading.materials.is_empty(), "新建shading保持空覆盖")
	var root: Node = screen.preview._model_root.get_child(0)
	var shared: Dictionary = preload("res://src/workshop/mesh_builder.gd").shared_materials()
	for slot: Dictionary in screen._slot_cache.values():
		var kind: String = str(slot.kind)
		var id: String = str(slot.id)
		if id.begins_with("canopy_"): continue
		if id == "roof_main" or id.begins_with("roofcap_"): kind = "roof"
		if id.begins_with("band_") or id.begins_with("belt_") or id.begins_with("plinth_"): kind = "band"
		if not screen.snapshot().architecture.palette.slots.has(kind): continue
		var expected: Array = screen.snapshot().architecture.palette.slots[kind].color_cell
		var meshes: Array = []
		if screen.preview._semantic_sources.has(str(slot.id)):
			for record: Dictionary in screen.preview._semantic_sources[str(slot.id)].mesh_records: meshes.append(record.mesh)
		else:
			var visible_node: MeshInstance3D = root.get_node_or_null(str(slot.node_path)) as MeshInstance3D
			if visible_node != null: meshes.append(visible_node.mesh)
		var correct: bool = not meshes.is_empty()
		for mesh: Mesh in meshes:
			for surface: int in mesh.get_surface_count():
				for point: Vector2 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]:
					correct = correct and floori(point.y * 8) == expected[0] and floori(point.x * 8) == expected[1]
		check(correct, "新默认实际部件UV " + str(slot.id), expected)
		if id.begins_with("slab_") and not meshes.is_empty():
			check(is_equal_approx((meshes[0] as Mesh).get_aabb().size.y, 0.2), "新默认真实楼板厚0.2m " + str(slot.id))
	var cells: Dictionary = {}
	var uv_valid: bool = true
	var materials_valid: bool = true
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for surface: int in node.mesh.get_surface_count():
			materials_valid = materials_valid and node.get_active_material(surface) in shared.values()
			var uv: PackedVector2Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			for point: Vector2 in uv:
				var cell := Vector2i(floori(point.x * 8), floori(point.y * 8))
				cells[str(cell)] = true
				var inside: Vector2 = point * 512.0 - Vector2(cell) * 64.0
				uv_valid = uv_valid and inside.x >= 8.0 and inside.x <= 56.0 and inside.y >= 8.0 and inside.y <= 56.0
	check(materials_valid and uv_valid, "新默认实际Mesh共享材质及UV内缩")
	for cell: Vector2i in [Vector2i(4, 0), Vector2i(1, 1), Vector2i(3, 2), Vector2i(1, 2)]:
		check(cells.has(str(cell)), "新默认最终可见UV色格 " + str(cell), cells)
	var window_found: bool = false
	var door_found: bool = false
	for opening: Dictionary in screen._opening_cache.values():
		if str(opening.get("type", "")) == "window":
			window_found = window_found or (is_equal_approx(float(opening.get("clear_width", 0)), 1.5) and is_equal_approx(float(opening.get("clear_height", 0)), 1.9))
		if str(opening.get("type", "")) == "door":
			door_found = door_found or (is_equal_approx(float(opening.get("clear_width", 0)), 1.6) and is_equal_approx(float(opening.get("clear_height", 0)), 2.4))
	check(window_found and door_found, "新默认真实净窗1.5x1.9净门1.6x2.4", screen._opening_cache.values())
	screen.preview.set_view("perspective")
	await capture("default_solar_ref")

func repair_fixture(id: String = "upgrade_repair") -> void:
	screen._reset_window_preview()
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe.architecture.form.enabled = false
	recipe.taper = 0.0
	# 保留原两层回归，不以三层绕过待内核诊断的union问题。
	recipe.floors = 2
	var accepted: Dictionary = screen.session.new_document(id, recipe)
	check(bool(accepted.ok), "调整真实基线 " + id, accepted.get("reason", ""))
	screen._last_window_scope = "global"
	screen._refresh_from_session()
	screen.refresh_preview()
	screen._select_page(screen.PAGES.find("门窗"))

func confirm_repair() -> void:
	screen._repair_dialog.get_ok_button().pressed.emit()

func verify_generation_adjustment() -> void:
	repair_fixture()
	var before: Dictionary = screen.snapshot()
	var root: Node = screen.preview._model_root.get_child(0)
	var mesh: String = visual_hash()
	var history: int = screen.session._undo.size()
	# 联合候选必须同时携带未应用层高、开间与当前窗，不先flush。
	screen.controls.floor_height.value = 2.5
	screen.controls.bay_width.value = 2.8
	screen.controls.architecture_window_height.value = 3.0
	screen.controls.architecture_window_glass_thickness.value = 0.1
	screen.controls.architecture_window_frame_depth.value = 0.04
	screen._window_preview_timer.stop()
	var staged: Dictionary = screen._collect_repair_candidate()
	check(bool(staged.ok) and staged.candidate.floor_height == 2.5 and staged.candidate.bay_width == 2.8 and staged.candidate.architecture.window.height == 3.0, "联合候选含层高开间及当前窗")
	screen.buttons.repair_generation.pressed.emit()
	check(screen._repair_dialog.visible and not screen._confirm.visible, "真实调整按钮打开独立确认窗", screen.repair_result)
	if not screen._repair_dialog.visible: return
	check(screen.snapshot() == before and screen.preview._model_root.get_child(0) == root and screen.session._undo.size() == history, "提议纯只读不换模型不增历史")
	check(screen._repair_dialog.get_cancel_button().has_focus(), "调整默认焦点取消")
	check(screen._repair_text.selection_enabled and screen._repair_text.scroll_active and screen._repair_text.text.contains("architecture.window.frame_depth") and screen._repair_text.text.contains("→") and screen._repair_text.text.contains("原因"), "方案中文参数完整path原新值单位原因可选择滚动")
	await capture("repair_dialog", true)
	screen._repair_dialog.get_cancel_button().pressed.emit()
	await plugin.get_tree().create_timer(0.25).timeout
	check(screen.snapshot() == before and visual_hash() == mesh and screen.controls.floor_height.value == 2.5 and screen._window_preview_timer.is_stopped(), "取消保持楼模型历史输入且不重启timer")
	screen.buttons.repair_generation.pressed.emit()
	screen.controls.floor_height.value = 2.6
	confirm_repair()
	check(not bool(screen.repair_result.get("ok", true)) and screen.snapshot() == before and not screen._repair_dialog.visible, "过期UI拒绝提交并清确认")
	screen.controls.floor_height.value = 2.5
	screen.buttons.repair_generation.pressed.emit()
	var catalog: Dictionary = screen.session.catalog.duplicate(true)
	screen.session.catalog.components.wall_sun["profile"] = "invalid_stale"
	confirm_repair()
	check(not bool(screen.repair_result.get("ok", true)) and screen.snapshot() == before and screen.session._undo.size() == history, "过期catalog拒绝且无历史")
	screen.session.catalog = catalog
	screen.buttons.repair_generation.pressed.emit()
	# 在UI边界模拟提议后实际构建拒绝，不改Session/Generator实现。
	screen._repair_pending.proposal.candidate.door_height = 5.0
	confirm_repair()
	check(not bool(screen.repair_result.get("ok", true)) and screen.snapshot() == before and screen.preview._model_root.get_child(0) == root and visual_hash() == mesh and screen.session._undo.size() == history and screen.controls.floor_height.value == 2.5, "真实build失败保root模型历史冲突输入")
	screen.buttons.repair_generation.pressed.emit()
	screen.controls.palette_seed.value += 1
	await plugin.get_tree().create_timer(0.25).timeout
	check(screen.snapshot() == before and screen._window_preview_timer.is_stopped(), "确认期间配色窗timer不得提交")
	confirm_repair()
	check(not bool(screen.repair_result.get("ok", true)) and screen.snapshot() == before and screen._window_preview_timer.is_stopped(), "配色输入变化使方案过期且不偷重启timer")
	# 丢弃测试中新排队的配色输入，原冲突窗仍原样保留。
	screen._window_preview_keys.erase("palette_settings")
	screen._refresh_palette_controls()
	screen.buttons.repair_generation.pressed.emit()
	screen._set_option("window_scope", "floor")
	confirm_repair()
	check(not bool(screen.repair_result.get("ok", true)) and screen.snapshot() == before, "目标scope过期拒绝提交")
	screen._set_option("window_scope", "global")
	screen.buttons.repair_generation.pressed.emit()
	screen._document_token += 1
	confirm_repair()
	check(not bool(screen.repair_result.get("ok", true)) and screen.snapshot() == before, "绑定token过期拒绝提交")
	screen._document_token -= 1
	screen.buttons.repair_generation.pressed.emit()
	var changed_recipe: Dictionary = before.duplicate(true)
	changed_recipe.display_name = "外部更新的配方"
	check(bool(screen.session.accept_loaded(changed_recipe, screen.session.catalog).ok), "外部配方合法变更夹具")
	confirm_repair()
	check(not bool(screen.repair_result.get("ok", true)) and screen.snapshot().display_name == "外部更新的配方", "recipe过期拒绝覆盖外部更新")
	check(bool(screen.session.accept_loaded(before, screen.session.catalog).ok), "恢复外部配方过期测试基线")
	# 无关slot输入必须显式拒绝，不能吞掉。
	screen.controls.offset_x.value = 0.2
	screen.buttons.repair_generation.pressed.emit()
	check(not screen._repair_dialog.visible and screen._last_status_text.contains("offset_x"), "无关未应用slot明确拒绝")
	screen.controls.offset_x.value = 0.0
	screen.controls.floor_override_height.value += 0.1
	screen.buttons.repair_generation.pressed.emit()
	check(not screen._repair_dialog.visible and screen._last_status_text.contains("floor_override_height"), "无关未应用floor字段明确拒绝")
	screen.controls.floor_override_height.set_value_no_signal(float(screen._local_baseline.floor_override_height))
	screen.controls.facade_width.value += 0.1
	screen._window_preview_timer.stop()
	screen._window_preview_keys.erase("facade_width")
	screen.buttons.repair_generation.pressed.emit()
	check(not screen._repair_dialog.visible and screen._last_status_text.contains("facade_width"), "无关未应用facade字段明确拒绝")
	screen.controls.facade_width.set_value_no_signal(float(screen._local_baseline.facade_width))
	screen.buttons.repair_generation.pressed.emit()
	var expected: Dictionary = screen.repair_result.candidate.duplicate(true)
	var inputs: Dictionary = screen._capture_input_context()
	confirm_repair()
	check(bool(screen.repair_result.get("ok", false)), "确认实际build成功", screen.repair_result)
	check(Recipe.fingerprint(screen.snapshot()) == Recipe.fingerprint(Recipe.normalized(expected)) and visual_hash() != mesh and screen.session._undo.size() == history + 1, "调整仅提交候选diff且一次真实楼历史")
	var repaired: Dictionary = screen.snapshot()
	var repaired_mesh: String = visual_hash()
	screen.buttons.undo.pressed.emit()
	check(screen.snapshot() == before and visual_hash() == mesh and screen._capture_ui_values() == inputs.ui_values and screen._window_failed_keys == inputs.failed and screen._window_preview_keys == inputs.pending and screen._window_preview_target == inputs.target, "一次undo恢复前有效楼冲突UI及失败key目标scope")
	screen.buttons.redo.pressed.emit()
	check(screen.snapshot() == repaired and visual_hash() == repaired_mesh, "redo恢复修复后真实楼")
	var count: int = screen.session._undo.size()
	screen.buttons.repair_generation.pressed.emit()
	check(not screen._repair_dialog.visible and screen.session._undo.size() == count, "有效无冲突不弹不改无历史")
	# 固定窗非法开角可在局部范围修正，不能扩散至其他owner。
	for scope: String in ["floor", "facade", "single"]:
		repair_fixture("repair_" + scope)
		screen._set_option("window_scope", scope)
		screen._window_scope_changed(screen.ARCHITECTURE_WINDOW_SCOPES.find(scope))
		var baseline: Dictionary = screen.snapshot()
		screen.controls.architecture_window_open_angle.value = 30
		await settle("局部固定窗冲突 " + scope, false)
		var failed_keys: Dictionary = screen._window_failed_keys.duplicate(true)
		screen.buttons.repair_generation.pressed.emit()
		check(screen._repair_dialog.visible, "局部冲突可建议 " + scope, screen.repair_result)
		var owner: String = {"floor": "floor_windows", "facade": "facade_windows", "single": "window_overrides"}[scope]
		confirm_repair()
		check(bool(screen.repair_result.get("ok", false)) and screen.snapshot().architecture.window == baseline.architecture.window, "局部修复不改变全局 " + scope, screen.repair_result)
		for other: String in ["floor_windows", "facade_windows", "window_overrides"]:
			if other != owner: check(screen.snapshot().architecture[other] == baseline.architecture[other], "局部修复保其他owner " + scope + other)
		screen.buttons.undo.pressed.emit()
		check(screen._window_failed_keys == failed_keys and screen._window_scope() == scope and screen.controls.architecture_window_open_angle.value == 30, "局部undo还原失败context " + scope)
		screen.buttons.redo.pressed.emit()
	# 不支持的生成冲突不得冒充可修；保存失败不emit也不异步弹窗。
	repair_fixture("repair_save")
	var emitted: Array = []
	var listener: Callable = func(token: int, result: Dictionary) -> void: emitted.append([token, result])
	screen.revision_saved.connect(listener)
	screen._document_token = 712
	screen.controls.door_height.value = 5.0
	var saved: Dictionary = screen.save_building()
	check(not bool(saved.ok) and emitted.is_empty() and not screen._repair_dialog.visible, "保存严格失败不误emit不自动弹窗")
	screen.buttons.repair_generation.pressed.emit()
	check(not bool(screen.repair_result.get("ok", true)) and not screen._repair_dialog.visible, "无解生成明确拒绝建议", screen.repair_result.get("reason", ""))
	screen.controls.door_height.value = 2.4
	screen.controls.architecture_window_open_angle.value = 30
	screen._window_preview_timer.stop()
	screen.buttons.repair_generation.pressed.emit()
	confirm_repair()
	saved = screen.save_building()
	check(bool(saved.ok) and emitted.size() == 1 and emitted[0][0] == 712 and screen._document_token == 712, "调整后真实保存保持binding token及成功revision事件", saved.get("reason", ""))
	if bool(saved.ok):
		var loaded: Dictionary = screen._store.load_recipe(saved.recipe_path)
		check(bool(loaded.ok) and Recipe.fingerprint(loaded.recipe) == Recipe.fingerprint(screen.snapshot()), "调整保存重载配方一致")
		var packed: PackedScene = ResourceLoader.load(saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var restored: Node = packed.instantiate()
		check(bool(Union.audit_faces(restored.get_node("GeneratedVisual/structure_union").mesh.get_faces()).valid), "调整保存重载实际union")
		restored.free()
	screen.revision_saved.disconnect(listener)

func verify_repair_review() -> void:
	repair_fixture("review_whitelist")
	var before: Dictionary = screen.snapshot()
	# 合法门输入属于白名单；其它未应用UI必须留在控件而不是被候选吸入。
	screen.controls.door_height.value = 2.5
	screen.controls.architecture_roof_height.value = 1.2
	screen.controls.growth_small.set_value_no_signal(0.8)
	screen._id_edit.text = "unsubmitted_identity"
	screen._name_edit.text = "未应用建筑名称"
	screen._set_option("binding_wall", "wall_warm")
	screen.controls.wing_x.set_value_no_signal(0.65)
	screen.controls.pilaster_width.set_value_no_signal(0.65)
	screen.controls.band_thickness.set_value_no_signal(0.4)
	screen._set_option("shape", "l")
	screen._set_option("architecture_shape_variant", "l")
	screen.controls.form_enabled.set_pressed_no_signal(true)
	screen.controls.vegetation_density.set_value_no_signal(0.2)
	screen.controls.damage.set_value_no_signal(0.2)
	screen.controls.palette_seed.set_value_no_signal(1291)
	screen.controls.shading_roughness.set_value_no_signal(0.72)
	screen.controls.architecture_window_glass_thickness.value = 0.1
	screen.controls.architecture_window_frame_depth.value = 0.04
	screen._window_preview_timer.stop()
	var inputs: Dictionary = screen._capture_input_context()
	var collected: Dictionary = screen._collect_repair_candidate()
	check(bool(collected.ok), "review白名单收集成功", collected.get("reason", ""))
	if not bool(collected.ok): return
	var expected: Dictionary = before.duplicate(true)
	expected.door_height = 2.5
	expected.architecture.window.glass_thickness = 0.1
	expected.architecture.window.frame_depth = 0.04
	check(collected.candidate == expected, "review候选只含合法门输入及实际窗队列，不吸入身份屋顶组件植物plan柱腰线")
	screen.buttons.repair_generation.pressed.emit()
	check(screen._repair_dialog.visible, "review真实按钮提议", screen.repair_result)
	if not screen._repair_dialog.visible: return
	check(screen._repair_input_text.selection_enabled and screen._repair_input_text.scroll_active and screen._repair_input_text.text.contains("door_height") and screen._repair_input_text.text.contains("2.4 → 2.5") and screen._repair_input_text.text.contains("architecture.window.glass_thickness"), "用户输入独立可滚动明细披露Session原值到输入")
	check(screen._repair_text.text.contains("修复建议") and not screen._repair_text.text.contains("door_height") and not screen._repair_input_text.text.contains("architecture.roof") and not screen._repair_input_text.text.contains("unsubmitted_identity"), "helper修复区与用户输入区分离且不混无关字段")
	var target: Dictionary = screen.repair_result.candidate.duplicate(true)
	await capture("repair_review_dialog", true)
	confirm_repair()
	check(bool(screen.repair_result.get("ok", false)) and Recipe.fingerprint(screen.snapshot()) == Recipe.fingerprint(target), "review确认只提交完整披露的白名单candidate", screen.repair_result)
	for key: String in ["architecture_roof_height", "growth_small", "binding_wall", "wing_x", "pilaster_width", "band_thickness", "shape", "architecture_shape_variant", "form_enabled", "vegetation_density", "damage", "palette_seed", "shading_roughness"]:
		check(screen._raw_control_value(key) == inputs.ui_values[key], "非候选UI精确保留 " + key)
	check(screen._id_edit.text == inputs.building_id and screen._name_edit.text == inputs.display_name and screen.snapshot().building_id == before.building_id and screen.snapshot().display_name == before.display_name, "非候选身份文本精确保留不提交")
	for key: String in inputs.baseline:
		if not collected.submitted.has(key): check(screen._local_baseline[key] == inputs.baseline[key], "非候选local baseline保留 " + key)
	check(screen.snapshot().architecture.roof == before.architecture.roof and screen.snapshot().growth_weights == before.growth_weights and screen.snapshot().component_bindings == before.component_bindings, "真实楼不混入屋顶growth组件")
	screen.buttons.undo.pressed.emit()
	check(screen.snapshot() == before and screen._capture_ui_values() == inputs.ui_values and screen._window_preview_target == inputs.target and screen._window_preview_keys == inputs.pending, "review undo恢复非候选UI及原冲突链")
	screen.buttons.redo.pressed.emit()
	check(Recipe.fingerprint(screen.snapshot()) == Recipe.fingerprint(target), "review redo真实候选")
	# 排队非窗字段选择明确拒绝，队列和输入保持；恢复草稿式无信号窗输入也必须具体拒绝。
	for key: String in ["growth_small", "palette_seed", "shading_roughness"]:
		repair_fixture("review_queue_" + key)
		screen.controls.architecture_window_frame_depth.value = 0.04
		screen.controls.architecture_window_glass_thickness.value = 0.1
		(screen.controls[key] as Range).value += 0.01 if key != "palette_seed" else 1
		screen._window_preview_timer.stop()
		var queued: Dictionary = screen._capture_input_context()
		screen.buttons.repair_generation.pressed.emit()
		check(not screen._repair_dialog.visible and not bool(screen.repair_result.get("ok", true)) and screen._window_preview_keys == queued.pending and screen._window_failed_keys == queued.failed and screen._capture_ui_values() == queued.ui_values, "排队非窗明确拒绝且保输入队列 " + key, screen._last_status_text)
	for scope: String in ["global", "floor", "facade", "single"]:
		repair_fixture("review_noqueue_" + scope)
		screen._set_option("window_scope", scope)
		screen._window_scope_changed(screen.ARCHITECTURE_WINDOW_SCOPES.find(scope))
		screen.controls.architecture_window_frame_depth.value = 0.04
		screen.controls.architecture_window_glass_thickness.value = 0.1
		screen.controls.architecture_window_recess.set_value_no_signal(0.2)
		screen._window_preview_timer.stop()
		var original: Dictionary = screen._capture_input_context()
		var recipe: Dictionary = screen.snapshot()
		screen.buttons.repair_generation.pressed.emit()
		check(not screen._repair_dialog.visible and screen._last_status_text.contains("architecture_window_recess") and screen._capture_ui_values() == original.ui_values and screen._local_baseline == original.baseline and screen.snapshot() == recipe and screen._window_preview_keys == original.pending, "未排队可见窗具体拒绝不吞输入 " + scope, screen._last_status_text)
		screen._local_baseline["architecture_window_recess"] = 0.2
		var restored: Dictionary = screen._collect_repair_candidate()
		check(not bool(restored.get("ok", true)) and str(restored.get("reason", "")).contains("architecture_window_recess"), "恢复草稿baseline相同仍检查Session可见窗差异 " + scope, restored.get("reason", ""))
		screen._local_baseline = original.baseline.duplicate(true)
	await verify_repair_history_branches()

func verify_repair_history_branches() -> void:
	repair_fixture("review_history")
	var original: Dictionary = screen.snapshot()
	var first: Dictionary = {}
	for marker: String in ["第一分支名称", "第二分支名称"]:
		screen._name_edit.text = marker
		screen.controls.architecture_window_glass_thickness.value = 0.1
		screen.controls.architecture_window_frame_depth.value = 0.04
		screen._window_preview_timer.stop()
		screen.buttons.repair_generation.pressed.emit()
		confirm_repair()
		check(bool(screen.repair_result.get("ok", false)), "重复指纹分支实际修复 " + marker, screen.repair_result)
		if first.is_empty(): first = screen.snapshot()
		check(screen.snapshot() == first, "不同未应用文本仍得到同一候选fingerprint " + marker)
		screen.buttons.undo.pressed.emit()
		check(screen.snapshot() == original and screen._name_edit.text == marker, "同fingerprint历史分支不串原输入 " + marker)
		if marker == "第二分支名称":
			screen.buttons.redo.pressed.emit()
			screen.buttons.undo.pressed.emit()
			check(screen._name_edit.text == marker and screen.snapshot() == original, "重复分支redo后undo仍恢复该分支输入")
	# 连续历史重复到达同一fingerprint，逆序两次undo不得由后一次覆盖前一次。
	screen.buttons.redo.pressed.emit()
	var changed: Dictionary = original.duplicate(true)
	var built: Dictionary = screen.session.preview_candidate(changed)
	check(bool(built.ok), "重复指纹中间真实历史")
	if bool(built.ok):
		screen._refresh_from_session()
		screen.refresh_preview(false, built)
	screen._name_edit.text = "最新未应用名"
	# 只记录公开事务真实生成的输入保护，不伪造Session历史。
	screen.controls.architecture_window_glass_thickness.value = 0.1
	screen.controls.architecture_window_frame_depth.value = 0.04
	screen._window_preview_timer.stop()
	screen.buttons.repair_generation.pressed.emit()
	confirm_repair()
	check(bool(screen.repair_result.get("ok", false)) and screen.snapshot() == first, "连续历史再次到达相同fingerprint", screen.repair_result)
	screen.buttons.undo.pressed.emit()
	check(screen.snapshot() == original and screen._name_edit.text == "最新未应用名", "连续同fingerprint最近记录正确")
	screen.buttons.undo.pressed.emit()
	check(screen.snapshot() == first and screen._name_edit.text != "最新未应用名", "普通中间历史不错误恢复repair输入")
	screen.buttons.undo.pressed.emit()
	check(screen.snapshot() == original and screen._name_edit.text == "第二分支名称", "连续同fingerprint早期记录未被覆盖")
	screen.buttons.redo.pressed.emit()
	var records: Dictionary = screen._random_house_undo_inputs.duplicate(true)
	var recovery: Dictionary = screen.get_recovery()
	check(screen._random_house_undo_inputs == records, "get_recovery不清同Session输入历史")
	check(bool(screen.restore_recovery(recovery).ok) and screen._random_house_undo_inputs == records, "同Session恢复不清输入历史")
	screen._new_document()
	check(screen._random_house_undo_inputs.is_empty() and screen._history_inputs_redo.is_empty(), "new文档清理输入历史映射")
	var saved: Dictionary = screen.save_building()
	check(bool(saved.get("ok", false)), "历史文档隔离保存fixture", saved.get("reason", ""))
	if bool(saved.get("ok", false)):
		screen._random_house_undo_inputs["sentinel"] = [{"document": "旧文档"}]
		screen._history_inputs_redo.append({"document": "旧文档"})
		var opened: Dictionary = screen._open_recipe_now(saved.recipe_path)
		check(bool(opened.get("ok", false)) and screen._random_house_undo_inputs.is_empty() and screen._history_inputs_redo.is_empty(), "open文档清理输入历史映射", opened.get("reason", ""))

func palette_target_button(target: String) -> Button:
	for index: int in screen.PALETTE_TARGETS.size():
		if str(screen.PALETTE_TARGETS[index][0]) == target:
			return screen.buttons["palette_target_%02d" % index]
	return null

func verify_palette_target_transactions() -> void:
	repair_fixture("palette_target_transactions")
	screen._select_page(screen.PAGES.find("配色"))
	palette_target_button("slots:wall").pressed.emit()
	var history: int = screen.session._undo.size()
	# 无await：墙色仍在160ms队列时立即切框并选色，不能覆盖墙的palette_settings。
	screen.controls.palette_grid.get_child(9).pressed.emit()
	palette_target_button("slots:frame").pressed.emit()
	check(screen.snapshot().architecture.palette.slots.wall.color_cell == [1, 1] and screen._option_value("palette_target") == "slots:frame", "快速切目标前先真实提交墙色")
	screen.controls.palette_grid.get_child(18).pressed.emit()
	await settle("快速两目标颜色分别实际提交")
	check(screen.snapshot().architecture.palette.slots.wall.color_cell == [1, 1] and screen.snapshot().architecture.palette.slots.frame.color_cell == [2, 2], "墙框快速连续颜色无队列丢失")
	check(screen.session._undo.size() == history + 2, "快速两次选色各一条历史")
	var original: Dictionary = screen.snapshot()
	var root: Node = screen.preview._model_root.get_child(0)
	var uv: String = palette_hash(root)
	history = screen.session._undo.size()
	palette_target_button("slots:glass").pressed.emit()
	palette_target_button("slots:wall").pressed.emit()
	check(screen.snapshot() == original and screen.preview._model_root.get_child(0) == root and palette_hash(root) == uv and screen.session._undo.size() == history and screen._window_preview_keys.is_empty(), "无pending切目标零模型替换无历史不改色")
	screen.controls.palette_grid.get_child(10).pressed.emit()
	var pending: Dictionary = screen._window_preview_keys.duplicate(true)
	palette_target_button("slots:wall").pressed.emit()
	check(screen.snapshot() == original and screen._window_preview_keys == pending and screen.session._undo.size() == history, "同target不flush不做额外工作")
	# 坏窗与配色一起失败，切target必须保原选色模式/seed/cell与旧target，不能刷新覆盖。
	screen.controls.architecture_window_open_angle.value = 30
	screen._window_preview_timer.stop()
	var settings: Dictionary = screen._palette_control_settings()
	palette_target_button("slots:frame").pressed.emit()
	check(screen._option_value("palette_target") == "slots:wall" and screen._palette_control_settings() == settings and screen.controls.architecture_window_open_angle.value == 30 and screen.snapshot() == original and screen.preview._model_root.get_child(0) == root and screen.session._undo.size() == history, "目标切换失败保旧target上下文输入模型历史")
	check(screen._window_failed_keys.has("palette_settings") and screen._window_failed_keys.palette_settings.target == "slots:wall" and screen._last_status_text.contains("未切换配色目标"), "目标失败保原配色failed队列并提示")
	# 修正窗后重试切换，先提交失败队列中的墙色再切上下文。
	screen.controls.architecture_window_open_angle.value = 0
	palette_target_button("slots:frame").pressed.emit()
	check(screen._option_value("palette_target") == "slots:frame" and screen._window_failed_keys.is_empty() and screen.snapshot().architecture.palette.slots.wall.color_cell == [1, 2], "修正后切目标恢复原墙色队列")
	# 隐藏适配器复用同一事务入口，且切换前不得已换到新上下文。
	screen.controls.palette_grid.get_child(20).pressed.emit()
	var adapter: OptionButton = screen.controls.palette_target
	var index: int = -1
	for item: int in screen.PALETTE_TARGETS.size():
		if str(screen.PALETTE_TARGETS[item][0]) == "slots:glass": index = item
	adapter.select(index)
	adapter.item_selected.emit(index)
	check(screen._option_value("palette_target") == "slots:glass" and screen.snapshot().architecture.palette.slots.frame.color_cell == [2, 4], "隐藏adapter先提交原框色再切目标")
	# repair确认期间目标入口不flush、不切换、不刷新输入。
	screen.controls.architecture_window_open_angle.value = 30
	screen._window_preview_timer.stop()
	screen.buttons.repair_generation.pressed.emit()
	check(screen._repair_dialog.visible, "配色切换确认期阻断fixture", screen.repair_result)
	if screen._repair_dialog.visible:
		var before: Dictionary = screen.snapshot()
		pending = screen._window_preview_keys.duplicate(true)
		settings = screen._palette_control_settings()
		palette_target_button("slots:wall").pressed.emit()
		check(screen._option_value("palette_target") == "slots:glass" and screen.snapshot() == before and screen._window_preview_keys == pending and screen._palette_control_settings() == settings and screen._last_status_text.contains("确认期间不能切换"), "repair确认期间target禁止切换且不flush")
		screen._repair_dialog.get_cancel_button().pressed.emit()
	screen._reset_window_preview()
	screen._refresh_from_session()
	await capture("palette_target_transactions", true)

func verify_structural_damage() -> void:
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe.architecture.form.enabled = false
	recipe.taper = 0.0
	# 右立面无窗墙避开门廊和既有窗洞；只改fixture，不隐藏模型或取消楼板/屋顶保护。
	recipe.facade_overrides["right"] = {"windows": false}
	recipe["structural_damage"] = {"facade": "right", "roughness": 0.75}
	var accepted: Dictionary = screen.session.new_document("upgrade_damage", recipe)
	check(bool(accepted.ok), "结构损毁UI基线", accepted.get("reason", ""))
	screen._reset_window_preview()
	screen._refresh_from_session()
	screen.refresh_preview()
	screen._select_page(screen.PAGES.find("破旧"))
	screen.preview.set_view("perspective")
	for field: String in ["center_u", "center_y", "width", "height", "roughness", "seed"]:
		check(screen.controls.get("structural_damage_" + field) is HSlider, "结构洞滑块 " + field)
	var clean: String = visual_hash()
	screen.controls.structural_damage_enabled.button_pressed = true
	screen.controls.structural_damage_enabled.emit_signal("toggled", true)
	await settle("启用结构大洞")
	check(visual_hash() != clean, "结构洞改变实际mesh")
	var history: int = screen.session._undo.size()
	screen.controls.structural_damage_width.emit_signal("drag_started")
	screen.controls.structural_damage_width.value = 4.0
	await settle("结构洞拖拽宽4米")
	screen.controls.structural_damage_width.value = 4.8
	await settle("结构洞拖拽宽4.8米")
	screen.controls.structural_damage_width.emit_signal("drag_ended", true)
	check(screen.session._undo.size() == history + 1, "结构洞一次拖动一次撤销")
	# 四种轮廓共用真实近景机位；略俯视以显示洞壁厚度和保留的楼板。
	var opening: Dictionary = screen.preview._model_root.get_child(0).get_meta("damage_openings")[0]
	screen.preview._target = opening.center
	screen.preview._yaw = PI * 0.5
	screen.preview._pitch = -0.06
	screen.preview._distance = 10.5
	screen.preview._fit_camera(false)
	for shape: String in ["ellipse", "jagged", "arch", "breach"]:
		screen._set_option("structural_damage_shape", shape)
		screen._queue_window_preview("structural_damage_shape")
		await settle("结构洞形状 " + shape)
		await capture("damage_" + shape, false, true)
	var valid: String = Recipe.fingerprint(screen.snapshot())
	var valid_mesh: String = visual_hash()
	screen.controls.structural_damage_center_y.value = 90.0
	await settle("结构洞越界拒绝", false)
	check(Recipe.fingerprint(screen.snapshot()) == valid and visual_hash() == valid_mesh, "结构洞失败保原配方/预览")
	check(is_equal_approx(screen.controls.structural_damage_center_y.value, 90.0), "结构洞失败保滑块输入")
	screen.controls.structural_damage_center_y.value = 1.7
	await settle("结构洞修正继续")
	await capture("damage_ui", true)
	var saved: Dictionary = screen.save_building()
	check(bool(saved.get("ok", false)), "结构洞五件bundle保存", saved.get("reason", ""))
	if bool(saved.get("ok", false)):
		var packed: PackedScene = ResourceLoader.load(saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var restored: Node3D = packed.instantiate()
		check(restored.get_meta("damage_openings", []).size() == 1, "结构洞静态重载宿主接口")
		check(bool(Union.audit_faces(restored.get_node("GeneratedVisual/structure_union").mesh.get_faces()).valid), "结构洞重载实际闭合mesh")
		restored.free()
	screen.buttons.structural_damage_clear.pressed.emit()
	await settle("清除结构洞")
	check(not bool(screen.snapshot().structural_damage.enabled), "清除结构洞状态")
	check(visual_hash() == clean, "清除结构洞恢复实际完整几何")

func plant_state(build: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not bool(build.get("ok", false)): return result
	for slot: Dictionary in build.slots:
		if str(slot.kind) != "plant": continue
		var node: Node3D = build.root.get_node(str(slot.node_path))
		var mesh: MeshInstance3D = node as MeshInstance3D
		result[str(slot.id)] = {"transform": node.transform, "faces": mesh.mesh.get_faces() if mesh != null else PackedVector3Array(), "growth": slot.get("growth_key", ""), "bounds": slot.bounds_size}
	return result

func release_build(build: Dictionary) -> void:
	if build.get("root") != null: build.root.free()

func verify_vegetation() -> void:
	var base: Dictionary = Recipe.defaults()
	var legacy: Dictionary = base.duplicate(true)
	legacy.erase("vegetation_random_enabled")
	legacy.erase("vegetation_variation")
	check(Recipe.validate(legacy).is_empty() and Recipe.normalized(legacy).vegetation_random_enabled == true and Recipe.normalized(legacy).vegetation_variation == 0.0, "植物旧配方默认兼容")
	check(Recipe.fingerprint(legacy) == Recipe._stable_string(legacy).sha256_text(), "植物兼容默认保持旧fingerprint")
	for pair: Array in [["vegetation_random_enabled", 1], ["vegetation_random_enabled", "false"], ["vegetation_variation", -0.01], ["vegetation_variation", 1.01], ["vegetation_variation", true], ["vegetation_variation", NAN], ["vegetation_seed", -1], ["vegetation_seed", 0.5], ["vegetation_seed", 9007199254740992.0], ["vegetation_variaton", 0.5]]:
		var bad: Dictionary = base.duplicate(true)
		bad[str(pair[0])] = pair[1]
		check(not Recipe.validate(bad).is_empty(), "植物配方非法值拒绝 " + str(pair))
	for pair: Array in [["vegetation_random_enabled", false], ["vegetation_variation", 1.0], ["vegetation_seed", 0]]:
		var changed: Dictionary = base.duplicate(true)
		changed[str(pair[0])] = pair[1]
		check(Recipe.validate(changed).is_empty() and Recipe.fingerprint(changed) != Recipe.fingerprint(base), "植物合法边界和指纹 " + str(pair))
	var json_recipe: Dictionary = JSON.parse_string(JSON.stringify(base))
	check(Recipe.normalized(json_recipe).vegetation_seed is int and Recipe.fingerprint(json_recipe) == Recipe.fingerprint(base), "植物JSON规范化与指纹稳定")
	for mode: String in ["modular_v1", "shell_v2"]:
		for profile: String in ["shrub", "tree", "moss", "vine"]:
			var recipe: Dictionary = Recipe.defaults()
			recipe.merge({"construction_mode": mode, "floors": 1, "width": 6.0, "depth": 6.0, "vegetation_density": 1.0, "growth_weights": [0.0, 1.0, 0.0], "vegetation_variation": 0.0}, true)
			recipe.component_bindings.plant = "plant_" + profile
			var fixed: Dictionary = Generator.build(recipe)
			check(bool(fixed.ok), mode + " " + profile + "基线真实生成", fixed.reason)
			var fixed_state: Dictionary = plant_state(fixed)
			recipe.vegetation_variation = 1.0
			seed(73519)
			var expected_global: float = randf()
			seed(73519)
			var varied: Dictionary = Generator.build(recipe)
			check(randf() == expected_global, mode + profile + "不消耗全局玩法随机流")
			var varied_state: Dictionary = plant_state(varied)
			check(not fixed_state.is_empty() and fixed_state.keys() == varied_state.keys(), mode + profile + "幅度不改变密度槽集合")
			var position_changed: bool = false
			var rotation_changed: bool = false
			var scale_changed: bool = false
			var sizes: Dictionary = {}
			for id: String in varied_state:
				var node: MeshInstance3D = varied.root.get_node("Vegetation/" + id)
				var transform: Transform3D = varied_state[id].transform
				position_changed = position_changed or not transform.origin.is_equal_approx(fixed_state[id].transform.origin)
				rotation_changed = rotation_changed or absf(node.rotation.y) > 0.001
				scale_changed = scale_changed or not node.scale.is_equal_approx(Vector3.ONE)
				sizes[str(node.scale.x)] = true
				check(str(varied_state[id].growth) == "medium", mode + profile + "保留medium生长语义 " + id)
				var bounds: AABB = node.transform * node.mesh.get_aabb()
				var reported: Array = varied_state[id].bounds
				check(bounds.size.is_equal_approx(Vector3(reported[0], reported[1], reported[2])), mode + profile + "元数据匹配真实变换Mesh " + id)
			check(scale_changed and rotation_changed and sizes.size() > 1, mode + profile + "真实尺寸旋转不再平均")
			check(position_changed if profile != "vine" else not position_changed, mode + profile + "真实位置变化或藤蔓檐边保持")
			var again: Dictionary = Generator.build(recipe)
			check(plant_state(again) == varied_state, mode + profile + "同seed逐槽Mesh确定性")
			release_build(again)
			recipe.vegetation_seed += 1
			again = Generator.build(recipe)
			check(plant_state(again) != varied_state, mode + profile + "换seed实际模型变化")
			release_build(again)
			recipe.vegetation_random_enabled = false
			var off: Dictionary = Generator.build(recipe)
			recipe.vegetation_seed += 73
			again = Generator.build(recipe)
			check(plant_state(off) == plant_state(again), mode + profile + "random off完全固定不受seed影响")
			check(str(off.root.get_meta("recipe_fingerprint")) == Recipe.fingerprint(Recipe.normalized(recipe.merged({"vegetation_seed": recipe.vegetation_seed - 73}, true))), mode + profile + "根指纹保留真实配方seed")
			release_build(off)
			release_build(again)
			if not varied_state.is_empty():
				var id: String = str(varied_state.keys()[0])
				recipe.vegetation_random_enabled = true
				recipe.vegetation_density = 0.0
				var anchor: Vector3 = fixed_state[id].transform.origin
				recipe.locked_vegetation = [{"slot_id": id, "position": [anchor.x, anchor.y, anchor.z], "growth_key": "large"}]
				var locked: Dictionary = Generator.build(recipe)
				var state: Dictionary = plant_state(locked)
				check(state.has(id) and state[id].transform.origin.is_equal_approx(anchor) and state[id].growth == "large", mode + profile + "锁定位置生长档且密度0仍保留")
				release_build(locked)
			release_build(fixed)
			release_build(varied)
	# 不同密度保留下来的同id实例不重抽姿态；幅度线性控制同一次抽样。
	base.merge({"vegetation_density": 1.0, "vegetation_variation": 1.0, "growth_weights": [0.0, 1.0, 0.0]}, true)
	var full: Dictionary = Generator.build(base)
	var full_state: Dictionary = plant_state(full)
	base.vegetation_density = 0.5
	var sparse: Dictionary = Generator.build(base)
	var sparse_state: Dictionary = plant_state(sparse)
	var stable_slots: bool = not sparse_state.is_empty() and sparse_state.size() < full_state.size()
	for id: String in sparse_state:
		stable_slots = stable_slots and sparse_state[id] == full_state[id]
	check(stable_slots, "密度仍是阈值且已有slot姿态不漂移")
	release_build(sparse)
	base.vegetation_density = 1.0
	base.vegetation_variation = 0.5
	var half: Dictionary = Generator.build(base)
	for slot: Dictionary in half.slots:
		if str(slot.kind) != "plant": continue
		var full_slot: Dictionary = Generator._slot_by_id(full.slots, str(slot.id))
		check(is_equal_approx(float(slot.vegetation_scale) - 1.0, (float(full_slot.vegetation_scale) - 1.0) * 0.5) and is_equal_approx(float(slot.vegetation_yaw), float(full_slot.vegetation_yaw) * 0.5), "幅度线性收放同一slot抽样 " + str(slot.id))
	release_build(half)
	var heights: Array[float] = []
	for growth: String in ["small", "medium", "large"]:
		base.growth_weights = [1.0 if growth == "small" else 0.0, 1.0 if growth == "medium" else 0.0, 1.0 if growth == "large" else 0.0]
		var built: Dictionary = Generator.build(base)
		var correct: bool = true
		for slot: Dictionary in built.slots:
			if str(slot.kind) == "plant": correct = correct and str(slot.growth_key) == growth
		check(correct, "三档权重保持原生长档 " + growth)
		var first_id: String = str(plant_state(built).keys()[0])
		var first_mesh: MeshInstance3D = built.root.get_node("Vegetation/" + first_id)
		heights.append((first_mesh.transform * first_mesh.mesh.get_aabb()).size.y)
		release_build(built)
	check(heights[0] < heights[1] and heights[1] < heights[2], "小中大实际Mesh体量仍递增")
	release_build(full)
	# 真实编辑器滑块：沿现有Timer/preview_candidate原子事务自动生成，而不是只检查snapshot。
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe.merge({"building_id": "upgrade_vegetation", "floors": 1, "vegetation_density": 0.18, "growth_weights": [0.0, 1.0, 0.0], "vegetation_variation": 0.0}, true)
	recipe.component_bindings.plant = "plant_tree"
	recipe.architecture.form.enabled = false
	recipe.taper = 0.0
	screen._reset_window_preview()
	var accepted: Dictionary = screen.session.new_document("upgrade_vegetation", recipe)
	check(bool(accepted.ok), "植物真实编辑器fixture", accepted.get("reason", ""))
	if not bool(accepted.ok): return
	screen._refresh_from_session()
	screen.refresh_preview()
	screen._select_page(screen.PAGES.find("植物"))
	screen.preview.set_view("perspective")
	for key: String in screen.VEGETATION_KEYS:
		check(screen.controls[key] is CheckButton if key == "vegetation_random_enabled" else screen.controls[key] is HSlider, "植物控件类型 " + key)
	var before: Dictionary = plant_state({"ok": true, "root": screen.preview._model_root.get_child(0), "slots": screen._slot_cache.values()})
	await capture("06_vegetation_fixed")
	screen.controls.width.value = 14.0
	var camera: Transform3D = screen.preview.camera.transform
	var old_undo: int = screen.session._undo.size()
	screen.controls.vegetation_variation.emit_signal("drag_started")
	screen.controls.vegetation_variation.value = 0.5
	await settle("植物幅度0.5自动预览")
	screen.controls.vegetation_variation.value = 1.0
	await settle("植物幅度1自动预览")
	screen.controls.vegetation_variation.emit_signal("drag_ended", true)
	var after: Dictionary = plant_state({"ok": true, "root": screen.preview._model_root.get_child(0), "slots": screen._slot_cache.values()})
	check(before != after and before.keys() == after.keys(), "植物滑块改变真实Mesh位置尺寸旋转而非仅snapshot")
	check(screen.session._undo.size() == old_undo + 1, "植物一次拖动一条撤销")
	check(screen.preview.camera.transform.is_equal_approx(camera), "植物实时预览保持相机")
	check(screen.snapshot().width == 12.0 and screen.controls.width.value == 14.0, "植物预览不提交或丢失其它输入")
	screen.controls.width.value = 12.0
	await capture("07_vegetation_varied")
	var valid: String = Recipe.fingerprint(screen.snapshot())
	var valid_mesh: Dictionary = after.duplicate(true)
	screen.controls.growth_medium.value = 0.0
	await settle("植物全零权重原子拒绝", false)
	check(Recipe.fingerprint(screen.snapshot()) == valid and plant_state({"ok": true, "root": screen.preview._model_root.get_child(0), "slots": screen._slot_cache.values()}) == valid_mesh, "植物非法输入保留最后成功配方Mesh")
	screen.controls.growth_medium.value = 1.0
	await settle("植物修正权重恢复")
	screen.controls.vegetation_random_enabled.button_pressed = false
	await settle("植物随机开关自动预览")
	var off_state: Dictionary = plant_state({"ok": true, "root": screen.preview._model_root.get_child(0), "slots": screen._slot_cache.values()})
	screen.controls.vegetation_seed.value = 777
	await settle("植物seed滑块自动预览")
	check(plant_state({"ok": true, "root": screen.preview._model_root.get_child(0), "slots": screen._slot_cache.values()}) == off_state, "真实UI关闭随机后换seed完全固定")
	screen.controls.vegetation_random_enabled.button_pressed = true
	await settle("植物重新开启随机")
	screen.controls.vegetation_density.value = 0.25
	await settle("植物密度滑块自动预览")
	var saved: Dictionary = screen.save_building()
	check(bool(saved.ok), "植物随机五件bundle保存", saved.get("reason", ""))
	if bool(saved.ok):
		var loaded: Dictionary = screen._store.load_recipe(saved.recipe_path)
		check(bool(loaded.ok) and Recipe.fingerprint(loaded.recipe) == Recipe.fingerprint(screen.snapshot()), "植物配方保存重载fingerprint")
		var packed: PackedScene = ResourceLoader.load(saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var restored: Node3D = packed.instantiate()
		var rebuilt: Dictionary = Generator.build(loaded.recipe, loaded.catalog)
		var static_state: Dictionary = plant_state({"ok": true, "root": restored, "slots": rebuilt.slots})
		check(static_state == plant_state(rebuilt), "植物TSCN重载逐槽真实Mesh变换一致")
		restored.free()
		release_build(rebuilt)
		artifacts.append(ProjectSettings.globalize_path(saved.scene_path))
	await capture("08_vegetation_sliders", true)

func palette_hash(root: Node, prefix: String = "") -> String:
	# CSG union允许不同三角剖分；验收颜色身份时比较每个可见节点实际占用的色格集合，
	# 不比较不稳定的三角顺序/数量。这样仍能发现色格丢失或换色，但不把合法重三角化误报成颜色丢失。
	var occupancy: Array = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if not prefix.is_empty() and not str(node.name).begins_with(prefix): continue
		var cells: Dictionary = {}
		for surface: int in node.mesh.get_surface_count():
			var uvs: PackedVector2Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			for uv: Vector2 in uvs:
				cells[str(Vector2i(floori(uv.x * 8.0), floori(uv.y * 8.0)))] = true
		occupancy.append([str(node.name), cells.keys()])
	occupancy.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	return JSON.stringify(occupancy)

func palette_hash_breakdown(root: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var cells: Dictionary = {}
		for surface: int in node.mesh.get_surface_count():
			var uvs: PackedVector2Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			for uv: Vector2 in uvs:
				cells[str(Vector2i(floori(uv.x * 8.0), floori(uv.y * 8.0)))] = true
		result[str(node.name)] = cells.keys()
	return result

func verify_shading() -> void:
	screen._select_page(screen.PAGES.find("配色"))
	check(screen.controls.shading_role is OptionButton, "材质角色选择器存在")
	for field: String in ["roughness", "metallic", "specular", "emission_energy", "transparency"]:
		check(screen.controls.get("shading_" + field) is HSlider, "着色器参数滑块 " + field)
	var before: String = Recipe.fingerprint(screen.snapshot())
	screen._set_option("shading_role", "SEA_Matte")
	screen._refresh_shading_controls()
	screen.controls.shading_roughness.emit_signal("drag_started")
	screen.controls.shading_roughness.value = 0.74
	await settle("Matte粗糙度实例实时预览")
	screen.controls.shading_roughness.emit_signal("drag_ended", true)
	var after: Dictionary = screen.snapshot()
	check(is_equal_approx(float(after.architecture.shading.materials.SEA_Matte.roughness), 0.74), "Matte粗糙度写入配方")
	var found: bool = false
	for raw: Node in screen.preview._model_root.find_children("*", "MeshInstance3D", true, false):
		var node: MeshInstance3D = raw as MeshInstance3D
		if node == null: continue
		var role_material: bool = false
		for surface: int in node.mesh.get_surface_count():
			if node.get_active_material(surface) == preload("res://src/workshop/mesh_builder.gd").shared_materials().get("SEA_Matte"):
				role_material = true
		if role_material:
			var controls: Vector4 = node.get_instance_shader_parameter("sea_matte_controls")
			if is_equal_approx(controls.x, 0.74): found = true
	check(found, "Matte实例参数写入最终可见Mesh")
	check(Recipe.fingerprint(screen.snapshot()) != before, "材质参数修改产生配方变化")
	check(screen.status_panel != null and not str(screen.status_label.text).is_empty(), "材质操作后底部高亮提示")
	var shading_saved: Dictionary = screen.save_building()
	check(bool(shading_saved.ok), "材质实例参数静态保存", shading_saved.get("reason", ""))
	if bool(shading_saved.ok):
		var loaded_shading: Dictionary = screen._store.load_recipe(shading_saved.recipe_path)
		check(bool(loaded_shading.ok) and loaded_shading.recipe.architecture.shading.materials.SEA_Matte.roughness == 0.74, "材质参数配方重载")
		var packed_shading: PackedScene = ResourceLoader.load(shading_saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var restored_shading: Node = packed_shading.instantiate() if packed_shading != null else null
		var restored_instance: bool = false
		if restored_shading != null:
			for raw: Node in restored_shading.find_children("*", "MeshInstance3D", true, false):
				var node: MeshInstance3D = raw as MeshInstance3D
				if node == null: continue
				var has_matte: bool = false
				for surface: int in node.mesh.get_surface_count():
					if node.get_active_material(surface) == preload("res://src/workshop/mesh_builder.gd").shared_materials().get("SEA_Matte"):
						has_matte = true
				if has_matte and is_equal_approx(float((node.get_instance_shader_parameter("sea_matte_controls") as Vector4).x), 0.74):
					restored_instance = true
					break
			check(restored_instance, "静态TSCN重载保留Matte实例参数")
			restored_shading.free()

func verify_palette() -> void:
	var builder = preload("res://src/workshop/mesh_builder.gd")
	var shared: Dictionary = builder.shared_materials()
	var hashes: Dictionary = {}
	for role: String in shared: hashes[role] = FileAccess.get_sha256(shared[role].resource_path)
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe.building_id = "upgrade_palette"
	# 旧角色继承断言必须留未覆盖的面；新manual slots另由新建默认专项核验。
	recipe.architecture.palette = {}
	recipe.floor_height = 3.6
	recipe.slab_thickness = 0.18
	recipe.architecture.pilaster.width = 0.36
	recipe.architecture.form.enabled = false
	recipe.architecture.window.sill_enabled = false
	recipe.taper = 0.0
	recipe.floors = 2
	recipe.vegetation_density = 0.15
	screen._reset_window_preview()
	var accepted: Dictionary = screen.session.new_document("upgrade_palette", recipe)
	check(bool(accepted.ok), "64色真实编辑器fixture", accepted.get("reason", ""))
	if not bool(accepted.ok): return
	screen._refresh_from_session()
	screen.refresh_preview()
	screen._select_page(screen.PAGES.find("配色"))
	check(screen.controls.palette_grid is GridContainer and screen.controls.palette_grid.columns == 8 and screen.controls.palette_grid.get_child_count() == 64, "真实8x8 GridContainer64格")
	check(screen.controls.palette_seed is HSlider and screen.controls.palette_mode is OptionButton, "真实mode和seed滑块")
	for index: int in screen.PAGES.size():
		check(screen.buttons.has("module_%02d" % index), "模块按钮可见 " + screen.PAGES[index])
	check(screen.status_label.get_theme_font_size("font_size") >= 15, "底部状态提示字号可读")
	check(screen.status_copy_button != null, "底部状态提示可复制")
	var camera: Transform3D = screen.preview.camera.transform
	var root: Node = screen.preview._model_root.get_child(0)
	var geometry: String = visual_hash()
	var clean: String = palette_hash(root, "glass_")
	screen.controls.width.value = 14.0
	screen._set_option("palette_target", "slots:glass")
	screen._refresh_palette_controls()
	screen._set_option("palette_mode", "manual")
	screen.controls.palette_mode.emit_signal("item_selected", 1)
	screen.controls.palette_grid.get_child(63).emit_signal("pressed")
	await settle("固定窗手动选第64格真实预览")
	root = screen.preview._model_root.get_child(0)
	check(palette_hash(root, "glass_") != clean and visual_hash() == geometry, "固定窗颜色改变真实UV/hash且不改几何")
	check(screen.snapshot().architecture.palette.slots.glass.color_cell == [7, 7], "手动[row,column]进入配方")
	check(screen.window_preview_result.get("ok", false), "配色点击后有实时结果反馈")
	check(screen.controls.width.value == 14.0 and screen.snapshot().width == 12.0, "调色不提交其他未应用楼宽")
	check(screen.preview.camera.transform.is_equal_approx(camera), "调色不重置镜头")
	await capture("09_palette_manual")
	for target: String in ["wall", "pillar", "band", "frame", "plant"]:
		screen._set_option("palette_target", "slots:" + target)
		screen._refresh_palette_controls()
		screen._set_option("palette_mode", "manual")
		screen.controls.palette_mode.emit_signal("item_selected", 1)
		screen.controls.palette_grid.get_child({"wall": 9, "pillar": 18, "band": 27, "frame": 36, "plant": 45}[target]).emit_signal("pressed")
		await settle(target + "独立64格选色")
		var expected_cell: int = {"wall": 9, "pillar": 18, "band": 27, "frame": 36, "plant": 45}[target]
		var found: bool = false
		for mesh_node: Node in screen.preview._model_root.find_children("*", "MeshInstance3D", true, false):
			if target == "plant" and not str(mesh_node.name).begins_with("plant_"): continue
			if target == "frame" and not str(mesh_node.name).begins_with("frame_"): continue
			if target in ["wall", "pillar", "band"] and str(mesh_node.name) != "structure_union": continue
			for surface: int in mesh_node.mesh.get_surface_count():
				for uv: Vector2 in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]:
					if floori(uv.y * 8.0) * 8 + floori(uv.x * 8.0) == expected_cell: found = true
		check(found, target + "最终可见Mesh真实命中所选格（含union保色）")
	root = screen.preview._model_root.get_child(0)
	var manual: String = palette_hash(root)
	screen._set_option("palette_target", "slots:glass")
	screen._refresh_palette_controls()
	screen._set_option("palette_mode", "auto")
	screen.controls.palette_mode.emit_signal("item_selected", 0)
	screen.controls.palette_seed.value = 73519
	await settle("auto种子真实UV预览")
	var auto_hash: String = palette_hash(screen.preview._model_root.get_child(0), "glass_")
	var glass_id: String = ""
	for id: String in screen._slot_cache:
		if id.begins_with("glass_"):
			glass_id = id
			break
	var resolved: Array = Config.palette_cell(screen.snapshot().architecture.palette.slots.glass, glass_id, "SEA_Gloss")
	check(screen.controls.palette_grid.get_child(int(resolved[0]) * 8 + int(resolved[1])).button_pressed, "auto色板高亮匹配真实玻璃槽稳定落点")
	check(manual != palette_hash(screen.preview._model_root.get_child(0)), "auto真实落点不同于manual")
	var before_undo: int = screen.session._undo.size()
	screen.controls.palette_seed.emit_signal("drag_started")
	screen.controls.palette_seed.value = 73520
	await settle("auto种子拖动第一次")
	screen.controls.palette_seed.value = 73521
	await settle("auto种子拖动第二次")
	screen.controls.palette_seed.emit_signal("drag_ended", true)
	check(screen.session._undo.size() == before_undo + 1, "颜色seed一次拖动一条撤销")
	screen.controls.palette_seed.value = 73519
	await settle("恢复相同seed")
	check(auto_hash == palette_hash(screen.preview._model_root.get_child(0), "glass_"), "同seed实际UV确定性")
	screen._set_option("palette_target", "materials:SEA_Matte")
	screen._refresh_palette_controls()
	screen._set_option("palette_mode", "manual")
	screen.controls.palette_mode.emit_signal("item_selected", 1)
	screen.controls.palette_grid.get_child(10).emit_signal("pressed")
	var before_role: String = palette_hash(screen.preview._model_root.get_child(0))
	await settle("按共享材质球SEA_Matte选格")
	check(screen.snapshot().architecture.palette.materials.SEA_Matte.color_cell == [1, 2] and palette_hash(screen.preview._model_root.get_child(0)) != before_role, "材质球选色实际改变未被部件覆盖的面")
	check(auto_hash == palette_hash(screen.preview._model_root.get_child(0), "glass_"), "Matte角色不改变Gloss玻璃")
	screen._set_option("palette_target", "slots:glass")
	screen._refresh_palette_controls()
	var valid: String = Recipe.fingerprint(screen.snapshot())
	var valid_uv: String = palette_hash(screen.preview._model_root.get_child(0))
	var invalid: Dictionary = screen.snapshot()
	invalid.architecture.palette.slots.glass.color_cell = [8, 0]
	var rejected: Dictionary = screen.session.preview_candidate(invalid)
	check(not bool(rejected.ok) and Recipe.fingerprint(screen.snapshot()) == valid and palette_hash(screen.preview._model_root.get_child(0)) == valid_uv, "非法色格原子拒绝保留配方历史与真实预览")
	screen.controls.width.value = 12.0
	await capture("10_palette_auto_ui", true)
	var expected: String = palette_hash(screen.preview._model_root.get_child(0))
	var expected_breakdown: Dictionary = palette_hash_breakdown(screen.preview._model_root.get_child(0))
	var before_save_recipe: Dictionary = screen.snapshot().duplicate(true)
	var before_save_fingerprint: String = Recipe.fingerprint(before_save_recipe)
	var saved: Dictionary = screen.save_building()
	check(bool(saved.ok), "64色五件bundle保存", saved.get("reason", ""))
	if bool(saved.ok):
		var packed: PackedScene = ResourceLoader.load(saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var restored: Node = packed.instantiate()
		var restored_hash: String = palette_hash(restored)
		var restored_breakdown: Dictionary = palette_hash_breakdown(restored)
		check(restored_hash == expected, "静态TSCN重载颜色UV包含植物一致", "expected=" + expected + " restored=" + restored_hash + " expected_nodes=" + str(expected_breakdown) + " restored_nodes=" + str(restored_breakdown))
		for node: Node in restored.find_children("*", "MeshInstance3D", true, false):
			for surface: int in node.mesh.get_surface_count():
				check(node.mesh.surface_get_material(surface) in shared.values(), "重载仍外链原共享材质 " + str(node.name))
		restored.free()
		var opened: Dictionary = screen._open_recipe_now(saved.recipe_path)
		var reopened_hash: String = palette_hash(screen.preview._model_root.get_child(0))
		var reopened_breakdown: Dictionary = palette_hash_breakdown(screen.preview._model_root.get_child(0))
		var reopened_fingerprint: String = Recipe.fingerprint(screen.snapshot())
		check(bool(opened.ok) and reopened_hash == expected, "真实编辑器打开配方恢复颜色和seed", "open_ok=" + str(opened.ok) + " expected=" + expected + " reopened=" + reopened_hash + " before_fp=" + before_save_fingerprint + " reopened_fp=" + reopened_fingerprint + " expected_nodes=" + str(expected_breakdown) + " reopened_nodes=" + str(reopened_breakdown))
		artifacts.append(ProjectSettings.globalize_path(saved.recipe_path))
	for role: String in shared:
		check(shared[role] == builder.shared_materials()[role] and hashes[role] == FileAccess.get_sha256(shared[role].resource_path), "共享材质身份及文件hash不变 " + role)

func verify_random_house() -> void:
	check(screen.buttons.get("random_house") is Button, "顶部随机房屋入口存在")
	var before: Dictionary = screen.snapshot()
	var original_hash: String = visual_hash()
	var original_root: Node = screen.preview._model_root.get_child(0)
	var old_history: int = screen.session._undo.size()
	screen.controls.width.value = 13.0
	screen.buttons.random_house.emit_signal("pressed")
	check(screen._confirm.visible, "随机房屋真实按钮点击先确认")
	var waiting: Dictionary = {}
	check(screen._confirm.visible, "随机房屋未保存或未应用输入先确认")
	check(screen.snapshot() == before and screen.session._undo.size() == old_history and screen.preview._model_root.get_child(0) == original_root, "随机确认前不改配方模型历史")
	screen._confirm.get_cancel_button().emit_signal("pressed")
	check(screen.controls.width.value == 13.0 and screen.snapshot() == before and visual_hash() == original_hash, "取消随机保留输入和实际模型")
	# 真实几何失败：使用坏catalog使生成失败，不改配方生成器或事务内部。
	var saved_catalog: Dictionary = screen.session.catalog
	screen.session.catalog = {"schema": "invalid_random_test"}
	waiting = screen.random_house(17)
	check(bool(waiting.get("confirmation_required", false)), "失败路径同样需要确认")
	screen._confirm.hide()
	screen._confirm.emit_signal("confirmed")
	check(not bool(screen.random_house_result.get("ok", true)) and screen.snapshot() == before and screen.controls.width.value == 13.0 and visual_hash() == original_hash and screen.session._undo.size() == old_history, "随机生成失败完整回滚模型输入历史")
	screen.session.catalog = saved_catalog
	waiting = screen.random_house(17)
	screen._confirm.hide()
	screen._confirm.emit_signal("confirmed")
	check(bool(screen.random_house_result.get("ok", false)), "确认后真实随机生成成功", screen.random_house_result)
	if not bool(screen.random_house_result.get("ok", false)): return
	var after: Dictionary = screen.snapshot()
	var after_hash: String = visual_hash()
	check(screen.session._undo.size() == old_history + 1 and after_hash != original_hash, "随机一次实际模型变化只提交一次历史")
	check(after.building_id == before.building_id and after.revision == before.revision, "随机不改变当前文档身份和版本")
	check_structure("随机房屋")
	screen.buttons.undo.emit_signal("pressed")
	check(screen.snapshot() == before and visual_hash() == original_hash and screen.controls.width.value == 13.0, "随机一次撤销恢复前房与未应用输入")
	screen.buttons.redo.emit_signal("pressed")
	check(screen.snapshot() == after and visual_hash() == after_hash, "随机重做恢复相同实际模型")
	var repeat: Dictionary = screen.random_house(17)
	check(bool(repeat.get("confirmation_required", false)), "未保存随机房再次替换仍需确认")
	screen._confirm.hide()
	screen._confirm.emit_signal("confirmed")
	check(screen.snapshot() == after and visual_hash() == after_hash and screen.session._undo.size() == old_history + 1, "同seed随机实际复现且无空历史")
	await capture("12_random_house")

func verify_compact_layout() -> void:
	var original_clipboard: String = DisplayServer.clipboard_get()
	# 同一个真实EditorPlugin主屏放入定尺寸渲染容器，避免Mac窗口管理器忽略分辨率。
	var original_parent: Node = screen.get_parent()
	var original_index: int = screen.get_index()
	var host := SubViewport.new()
	host.name = "WorkshopLayoutProbe"
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	plugin.add_child(host)
	screen.reparent(host)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for target: Vector2i in [Vector2i(1280, 800), Vector2i(1000, 700), Vector2i(860, 600)]:
		host.size = target
		screen.size = Vector2(target)
		screen._left_panel.show()
		screen._right_panel.hide()
		screen._on_layout_resized()
		for frame: int in 6: await plugin.get_tree().process_frame
		var model: Rect2 = screen.preview.get_global_rect()
		var strip: Rect2 = (screen._module_strip.get_parent() as Control).get_global_rect()
		var workspace: Rect2 = screen._workspace.get_global_rect()
		var metric: Dictionary = {"target": str(target), "screen": str(screen.size), "preview": str(model), "preview_height_ratio": model.size.y / target.y, "module_strip": str(strip), "workspace": str(workspace), "left_width": screen._left_panel.size.x, "status_height": screen.status_panel.size.y}
		layout_metrics.append(metric)
		check(screen.size.is_equal_approx(Vector2(target)), "主屏不被最小尺寸撑出容器 " + str(target), metric)
		check(model.size.x >= target.x * 0.52 and model.size.y >= target.y * 0.60, "实际模型预览面积门禁 " + str(target), metric)
		check(strip.position.x >= model.position.x - 1 and absf(strip.end.x - model.end.x) <= 2 and strip.end.y <= model.position.y, "模块横栏对齐模型上方红框 " + str(target), metric)
		check(strip.size.y <= 52 and model.position.y - workspace.position.y <= 96, "模块不换行增高挤压预览 " + str(target), metric)
		check(workspace.position.y <= 100 and screen.status_panel.size.y <= 52, "常驻顶部与底栏高度受控 " + str(target), metric)
		var random_button: Button = screen.buttons.random_house
		var toolbar: Control = screen.find_child("WorkshopMainToolbar", true, false) as Control
		check(random_button.get_parent() == screen.buttons.generate.get_parent() and random_button.get_global_rect().end.y <= toolbar.get_global_rect().end.y and toolbar.size.y <= 44, "随机按钮同一行且不增加栏高 " + str(target), toolbar.size)
		check(toolbar.get_global_rect().encloses(random_button.get_global_rect()) and random_button.pressed.get_connections().size() == 1, "随机按钮三档完整可见且只连一次 " + str(target))
		check(screen._left_panel.size.x <= 330 and screen._left_panel.size.x >= 275, "参数栏宽度可读且不过宽 " + str(target), metric)
		check(not screen._workspace.get_parent() is ScrollContainer, "预览不被全局滚动容器包裹 " + str(target))
		for index: int in screen.PAGES.size():
			var action: Button = screen.buttons["module_%02d" % index]
			check(action.pressed.get_connections().size() == 1, "模块按钮只触发一次 " + str(index) + str(target))
			check(is_equal_approx(action.position.y, 0.0), "模块按钮保持单行 " + str(index) + str(target))
		# 真实按钮进入最后一页，并自动滚到可见位置。
		screen.buttons.module_08.emit_signal("pressed")
		for frame: int in 4: await plugin.get_tree().process_frame
		check(screen.pages["文件"].visible and screen._module_strip.get_global_rect().intersects(screen.buttons.module_08.get_global_rect()), "末端模块点击并滚入视野 " + str(target))
		screen.buttons.module_00.emit_signal("pressed")
		for frame: int in 4: await plugin.get_tree().process_frame
		RenderingServer.force_draw()
		var image: Image = host.get_texture().get_image()
		var path: String = "res://outputs/compact_layout_%dx%d.png" % [target.x, target.y]
		check(image.get_size() == target and image.save_png(path) == OK, "真实定尺寸布局截图 " + str(target))
		artifacts.append(ProjectSettings.globalize_path(path))
		var view_rect: Rect2 = screen._views_scroll.get_global_rect()
		var palette_before: Dictionary = screen.snapshot()
		var palette_history: int = screen.session._undo.size()
		screen.buttons.module_02.pressed.emit()
		for frame: int in 4: await plugin.get_tree().process_frame
		var target_rect: Rect2 = screen._palette_target_row.get_global_rect()
		check(screen._palette_target_row.visible and not screen._views_scroll.visible and not screen.controls.palette_target.visible, "配色仅显式目标按钮且隐藏视角下拉 " + str(target))
		check(absf(target_rect.position.y - view_rect.position.y) <= 1 and target_rect.size.y <= 44 and screen._palette_target_row.get_parent() == screen._preview_column, "配色目标原位替代views第二行 " + str(target), target_rect)
		check(screen.preview.size.x >= target.x * 0.52 and screen.preview.size.y >= target.y * 0.60, "配色页保R81真实预览面积 " + str(target), screen.preview.size)
		check(screen._palette_target_buttons.size() == 13, "十三配色目标无遗漏 " + str(target))
		for spec: Array in screen.PALETTE_TARGETS:
			var action: Button = screen._palette_target_buttons[str(spec[0])]
			action.pressed.emit()
			for frame: int in 2: await plugin.get_tree().process_frame
			check(action.get_theme_font_size("font_size") >= 18 and action.size.y >= 40 and action.position.y == 0 and action.pressed.get_connections().size() == 1, "配色目标字号高度单行单连接 " + str(spec[0]) + str(target))
			check(screen._palette_target_strip.get_global_rect().encloses(action.get_global_rect()) and action.button_pressed and screen._option_value("palette_target") == str(spec[0]), "配色目标实际pressed滚入高亮 " + str(spec[0]) + str(target), action.get_global_rect())
		check(screen.snapshot() == palette_before and screen.session._undo.size() == palette_history, "十三目标上下文切换不变色无历史 " + str(target))
		# 经真实Control GUI输入派发，不只直接调业务函数。
		var gui_button: Button = screen._palette_target_buttons["materials:SEA_Emission"]
		screen._set_option("palette_target", "global")
		var gui_events: Array = []
		var observed: Callable = func() -> void: gui_events.append(true)
		gui_button.pressed.connect(observed)
		gui_button.grab_focus()
		var press := InputEventKey.new()
		press.keycode = KEY_ENTER
		press.pressed = true
		host.push_input(press)
		var release := InputEventKey.new()
		release.keycode = KEY_ENTER
		host.push_input(release)
		await plugin.get_tree().process_frame
		check(gui_button.has_focus() and gui_events.size() == 1 and screen._option_value("palette_target") == "materials:SEA_Emission", "配色目标真实Control键盘GUI事件 " + str(target), gui_events.size())
		gui_button.pressed.disconnect(observed)
		for frame: int in 4: await plugin.get_tree().process_frame
		check(screen._palette_target_strip.get_global_rect().encloses(gui_button.get_global_rect()) and gui_button.button_pressed, "GUI切换后当前目标滚入且高亮 " + str(target), {"target": screen._option_value("palette_target"), "pressed": gui_button.button_pressed, "strip": screen._palette_target_strip.get_global_rect(), "button": gui_button.get_global_rect(), "scroll": screen._palette_target_strip.scroll_horizontal})
		RenderingServer.force_draw()
		var palette_path: String = "res://outputs/upgrade_palette_button_rows_%dx%d.png" % [target.x, target.y]
		check(host.get_texture().get_image().save_png(palette_path) == OK, "配色按钮行真实截图 " + str(target))
		artifacts.append(ProjectSettings.globalize_path(palette_path))
		screen.buttons.module_00.pressed.emit()
		for frame: int in 3: await plugin.get_tree().process_frame
		check(not screen._palette_target_row.visible and screen._views_scroll.visible, "非配色页隐藏十三目标恢复视角 " + str(target))
		# 展开右栏时小窗口自动让左栏退让，不能挤压中心。
		screen.buttons.toggle_right.emit_signal("pressed")
		for frame: int in 4: await plugin.get_tree().process_frame
		check(screen._right_panel.visible and (target.x >= 1120 or not screen._left_panel.visible), "窄屏双侧栏不同时挤占预览 " + str(target))
		check(screen.preview.size.x >= (420 if target.x >= 1120 else 480), "槽位栏展开后预览仍可用 " + str(target), screen.preview.size)
		if target.x == 1280:
			host.size = Vector2i(1000, 700)
			screen.size = Vector2(1000, 700)
			screen._on_layout_resized()
			for frame: int in 4: await plugin.get_tree().process_frame
			check(not screen._right_panel.visible and screen.preview.size.x >= 520, "从宽窗口缩窄时自动收起多余侧栏")
			host.size = target
			screen.size = Vector2(target)
		# 长错误不会把状态栏撑高，复制和详情保留完整信息。
		var long_status: String = "[警告] 参数冲突原因与处理建议：".repeat(20) + "\n完整内容不丢失。"
		screen._set_status(long_status, screen.WORKSHOP_WARN)
		for frame: int in 3: await plugin.get_tree().process_frame
		check(screen.status_panel.size.y <= 52 and screen.status_label.get_line_count() == 1, "长提示不挤占编辑区域 " + str(target))
		screen.buttons.copy_status.emit_signal("pressed")
		check(DisplayServer.clipboard_get() == long_status, "复制完整提示而非省略文本 " + str(target))
		screen._show_status_details()
		check(screen._details_text.selection_enabled and screen._details_text.text == long_status, "详情可选择复制完整提示 " + str(target))
		screen._details_dialog.hide()
		screen._left_panel.show()
		screen._right_panel.hide()
	DisplayServer.clipboard_set(original_clipboard)
	screen.reparent(original_parent)
	original_parent.move_child(screen, original_index)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.queue_free()
	for frame: int in 6: await plugin.get_tree().process_frame
	screen._on_layout_resized()
	# 模组按需打开，取消替换后输入与模型保持。
	var before: String = Recipe.fingerprint(screen.snapshot())
	var original_width: float = screen.controls.width.value
	screen.controls.width.value = 13.0
	screen.buttons.show_defaults.emit_signal("pressed")
	check(screen._defaults_dialog.visible, "默认模组入口打开选择窗")
	screen.buttons.default_module_00.emit_signal("pressed")
	check(screen._confirm.visible and Recipe.fingerprint(screen.snapshot()) == before, "载入模组前明确确认且草稿不变")
	screen._confirm.get_cancel_button().emit_signal("pressed")
	check(not screen._confirm.visible and screen.controls.width.value == 13.0 and Recipe.fingerprint(screen.snapshot()) == before, "取消载入保留未应用输入")
	screen.controls.width.set_value_no_signal(original_width)
	screen._update_range_readout("width")
	screen._select_page(0)
	screen._set_status("布局已按示意重排：模块位于预览上方，建筑信息与模组按需打开。", screen.WORKSHOP_ACCENT_HOVER)
	await capture("11_compact_editor", true)

func settle(label: String, expected_ok: bool = true) -> void:
	var start: int = Time.get_ticks_msec()
	await plugin.get_tree().create_timer(0.25).timeout
	for frame: int in 8:
		await plugin.get_tree().process_frame
	var result: Dictionary = screen.window_preview_result
	check(bool(result.get("ok", false)) == expected_ok, label, result.get("reason", "无结果"))
	timings.append({"label": label, "wait_and_build_ms": Time.get_ticks_msec() - start, "result": result})

func check_structure(label: String) -> void:
	var root: Node3D = screen.preview._model_root.get_child(0)
	var structure: MeshInstance3D = root.get_node_or_null("GeneratedVisual/structure_union") as MeshInstance3D
	check(structure != null, label + "有最终结构mesh")
	if structure == null: return
	check(bool(Union.audit_faces(structure.mesh.get_faces()).valid), label + "单连通闭合定向正体积")
	for node: Node in root.get_node("GeneratedVisual").get_children():
		if Union.owns(str(node.name)):
			check(not node is MeshInstance3D and node.get_child_count() == 0, label + "结构源非拼接可见mesh " + str(node.name))
	check(not contains_csg(root), label + "静态根无CSG或脚本")

func contains_csg(root: Node) -> bool:
	if root is CSGShape3D or root.get_script() != null: return true
	for child: Node in root.get_children():
		if contains_csg(child): return true
	return false

func visual_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for node: Node in screen.preview._model_root.find_children("*", "MeshInstance3D", true, false):
		context.update(var_to_bytes(node.mesh.get_faces()))
	return context.finish().hex_encode()

func capture_damage_closeup() -> Image:
	# 复制真实预览世界与当前相机，不调用整楼自动取景，也不裁切/放大已有图片。
	var viewport := SubViewport.new()
	viewport.name = "WorkshopDamageCloseup"
	viewport.own_world_3d = true
	viewport.size = Vector2i(1400, 1100)
	viewport.gui_disable_input = true
	viewport.msaa_3d = screen.preview.viewport.msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	plugin.get_tree().root.add_child(viewport)
	var world: Node3D = screen.preview._world.duplicate(0)
	viewport.add_child(world)
	for overlay: Node3D in [screen.preview._highlight_root, screen.preview._wireframe_root, screen.preview._collision_root]:
		world.get_node(screen.preview._world.get_path_to(overlay)).free()
	var camera: Camera3D = world.get_node(screen.preview._world.get_path_to(screen.preview.camera))
	camera.current = true
	for frame: int in 3:
		await plugin.get_tree().process_frame
	RenderingServer.force_draw()
	var image: Image = viewport.get_texture().get_image()
	viewport.free()
	return image

func capture(label: String, full_ui: bool = false, damage_closeup: bool = false) -> void:
	var image: Image
	if damage_closeup:
		image = await capture_damage_closeup()
	elif full_ui:
		await plugin.get_tree().process_frame
		RenderingServer.force_draw()
		# macOS原生子窗口不在主Viewport截图里；直接取实际确认Window渲染纹理。
		image = screen._repair_dialog.get_texture().get_image() if label.begins_with("repair_") else EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	else:
		image = await screen.preview.capture_model_image(Vector2i(1400, 1100))
	check(image != null and not image.is_empty(), label + "真实渲染图")
	if image == null or image.is_empty(): return
	var path: String = "res://outputs/upgrade_" + label + ".png"
	check(image.save_png(path) == OK, label + "截图落盘")
	artifacts.append(ProjectSettings.globalize_path(path))

func finish() -> void:
	check(EditorInterface.get_edited_scene_root() == original_scene, "不改当前编辑scene")
	check(plugin.get_tree().paused == original_pause, "不改编辑树暂停")
	var report: Dictionary = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "artifacts": artifacts, "timings": timings, "layout_metrics": layout_metrics, "enginehint": Engine.is_editor_hint(), "is_playing": EditorInterface.is_playing_scene(), "actual_window": str(DisplayServer.window_get_size()), "input_method": "真实HSlider值/drag与Button pressed，经Timer提交；另经SubViewport.push_input派发Control键盘GUI事件并计数；非人工鼠标操作", "visual_acceptance": "需主线程目检，截图非空不等于美术终验", "scene_unchanged": EditorInterface.get_edited_scene_root() == original_scene}
	var file: FileAccess = FileAccess.open("res://outputs/workshop_upgrade_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-upgrade] ", checks.size(), " checks, ", failures.size(), " failures")
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
