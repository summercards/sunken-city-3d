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
var checks: Array = []
var failures: Array[String] = []
var artifacts: Array[String] = []
var timings: Array = []
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
	var top_info: Control = screen.find_child("WorkshopTopInfo", true, false) as Control
	var top_modules: Control = screen.find_child("WorkshopTopModuleBar", true, false) as Control
	var default_modules: Control = screen.find_child("WorkshopDefaultModules", true, false) as Control
	check(top_info != null and top_info.get_parent() != screen._left_panel, "建筑身份信息位于顶部独立栏")
	check(top_modules != null and top_modules.get_parent() != screen._left_panel, "模块按钮不挤占左侧编辑参数区")
	check(default_modules != null and default_modules.get_child_count() == screen.DEFAULT_MODULES.size(), "顶部提供可直接使用的默认模组")
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
	var recipe: Dictionary = Recipe.authoring_defaults()
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
	recipe.merge({"building_id": "upgrade_large", "width": 12.0, "depth": 12.0, "bay_width": 6.0, "floor_height": 6.8, "floors": 2, "taper": 0.0}, true)
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
	finish()

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

func capture(label: String, full_ui: bool = false) -> void:
	var image: Image
	if full_ui:
		await plugin.get_tree().process_frame
		RenderingServer.force_draw()
		image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
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
	var report: Dictionary = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "artifacts": artifacts, "timings": timings, "enginehint": Engine.is_editor_hint(), "is_playing": EditorInterface.is_playing_scene(), "actual_window": str(DisplayServer.window_get_size()), "input_method": "真实HSlider值和drag信号，经Timer自动提交；非人工鼠标操作", "visual_acceptance": "需主线程目检，截图非空不等于美术终验", "scene_unchanged": EditorInterface.get_edited_scene_root() == original_scene}
	var file: FileAccess = FileAccess.open("res://outputs/workshop_upgrade_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-upgrade] ", checks.size(), " checks, ", failures.size(), " failures")
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
