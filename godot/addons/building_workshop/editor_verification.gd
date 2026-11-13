@tool
extends RefCounted

const SELF_PATH: String = "res://addons/building_workshop/editor_verification.gd"
const OUTPUT_ROOT: String = "res://outputs/workshop_editor"
const REPORT_PATH: String = "res://outputs/workshop_editor_report.json"
const COMPONENT_ROOT: String = "res://scenes/components/workshop_modules"
const SAMPLE_PATH: String = "res://data/workshop/samples/workshop_sample_001.recipe.json"
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const MeshBuilder = preload("res://src/workshop/mesh_builder.gd")
const SHARED_MATERIAL_PATHS: Dictionary = {
	"SEA_Matte": "res://assets/materials/solar_cabin/sunny_matte.tres",
	"SEA_Metal": "res://assets/materials/solar_cabin/sunny_metal.tres",
	"SEA_Gloss": "res://assets/materials/solar_cabin/sunny_gloss.tres",
	"SEA_Emission": "res://assets/materials/solar_cabin/sunny_emission.tres"
}
const SHARED_PALETTE_PATH: String = "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"

var _shell_samples: Array[Dictionary] = []
var _architecture_samples: Array[Dictionary] = []
var _legacy_check_count: int = 0

var _plugin: EditorPlugin
var _screen: Control
var _store: Object
var _adapter: Object
var _tree: SceneTree
var _checks: Array[Dictionary] = []
var _failures: Array[String] = []
var _artifacts: Array[String] = []
var _build_ids: Array[String] = []
var _dependencies: Array[String] = []
var _edited_root: Node
var _edited_transform: Variant
var _paused: bool = false
var _scene_unchanged: bool = false
var _isolation_ok: bool = false
var _shared_materials: Dictionary = {}
var _shared_material_state: Dictionary = {}

# 仅由真实编辑器中的 plugin.gd 在主线程 await；不是 --script 入口。
static func run(plugin: EditorPlugin) -> void:
	if not Engine.is_editor_hint() or not OS.get_cmdline_user_args().has("--workshop-editor-verify"):
		return
	var script: Script = load(SELF_PATH) as Script
	var verifier: RefCounted = script.new() as RefCounted
	await verifier.call("_execute", plugin)

func _execute(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_tree = plugin.get_tree()
	_paused = _tree.paused
	_edited_root = EditorInterface.get_edited_scene_root()
	_edited_transform = _root_transform(_edited_root)
	_check("editor_hint", Engine.is_editor_hint())
	_check("主线程", OS.get_thread_caller_id() == OS.get_main_thread_id())
	_check("启动时未运行场景", not EditorInterface.is_playing_scene())
	_isolation_ok = _verify_isolation()
	if not _isolation_ok:
		_finish()
		return
	for frame: int in range(3):
		await _tree.process_frame
	_screen = _property(plugin, "screen") as Control
	_store = _property(plugin, "store") as Object
	_adapter = _property(plugin, "adapter") as Object
	if not _check("插件实际主屏", is_instance_valid(_screen) and _screen.is_inside_tree()):
		_dependencies.append("plugin.screen: 已进入编辑器树的 editor_screen Control")
		_finish()
		return
	var ready: bool = _require_methods(_screen, ["configure", "apply_parameters", "save_building", "open_recipe", "refresh_preview", "snapshot", "has_pending_fields", "select_slot", "get_recovery", "restore_recovery"], "screen")
	ready = _require_methods(_store, ["load_recipe", "export_revision", "list_documents"], "plugin.store") and ready
	ready = _require_methods(plugin, ["_make_visible", "_has_main_screen", "_get_plugin_name"], "plugin") and ready
	if not ready:
		_finish()
		return
	# 只覆盖导出根；保留插件注入的 open_scene / rescan / replace_component 等真实端口。
	_screen.call("configure", {"store": _store, "export_root": OUTPUT_ROOT})
	_plugin.call("_make_visible", true)
	EditorInterface.set_main_screen_editor("老王场景工坊")
	await _tree.process_frame
	_check("主屏名称", str(_plugin.call("_get_plugin_name")) == "老王场景工坊")
	_check("主屏声明", bool(_plugin.call("_has_main_screen")))
	_check("真实编辑器主屏可见", _screen.is_visible_in_tree() and EditorInterface.get_base_control().is_ancestor_of(_screen))
	_check("隔离导出根已注入", str(_property(_screen, "export_root")) == OUTPUT_ROOT)
	var ports: Dictionary = _dictionary(_property(_screen, "_ports"))
	for port: String in ["open_scene", "rescan", "replace_component"]:
		var callback: Callable = ports.get(port, Callable())
		_check("真实端口：" + port, callback.is_valid())
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var buttons: Dictionary = _dictionary(_property(_screen, "buttons"))
	_check("实际 controls 非空", not controls.is_empty(), str(controls.keys()))
	_check("实际 buttons 非空", not buttons.is_empty(), str(buttons.keys()))
	var session: Object = _property(_screen, "session") as Object
	if not _require_methods(session, ["snapshot", "accept_loaded", "apply_patch", "is_dirty"], "screen.session"):
		_finish()
		return
	_test_shared_scene_materials()
	await _test_editor_repair()
	# 专项恢复可能重建 session；历史样例仍由原 parser 继续验收。
	session = _property(_screen, "session") as Object
	var sample: Dictionary = _read_json(SAMPLE_PATH)
	var catalog: Dictionary = _dictionary(_property(session, "catalog"))
	var accepted: Dictionary = _result(session, "accept_loaded", [sample, catalog])
	if not _check_result("版本化样例配方", accepted):
		_finish()
		return
	_screen.call("configure", {})
	var original: Dictionary = _snapshot()
	var invalid: Dictionary = _result(session, "apply_patch", [{"width": -1.0}])
	_check("非法配方原子拒绝", not bool(invalid.get("ok", false)) and _same(original, _snapshot()), str(invalid))
	var building_id: String = "editor_verify_%s_%s" % [str(int(Time.get_unix_time_from_system())), str(Time.get_ticks_usec())]
	_build_ids.append(building_id)
	if not _set_text("building_id", building_id) or not _set_text("display_name", "编辑器验收楼房"):
		_finish()
		return
	for spec: Array in [["width", 15.0], ["depth", 9.0], ["floors", 3.0], ["taper", 0.0], ["damage", 0.0], ["vegetation_density", 0.0]]:
		if not _set_spin(str(spec[0]), float(spec[1])):
			_finish()
			return
	if not _check_result("真实 UI 应用 simple15", _result(_screen, "apply_parameters")):
		_finish()
		return
	_check("simple15 宽度进入配方", is_equal_approx(float(_snapshot().get("width", 0.0)), 15.0))
	var simple15: Dictionary = _snapshot()
	_emit_button("undo")
	_check("同 session 撤销 simple15", _property(_screen, "session") == session and _same(_snapshot(), original))
	_emit_button("redo")
	_check("同 session 重做 simple15", _property(_screen, "session") == session and _same(_snapshot(), simple15))
	_test_overrides()
	await _test_architecture_controls()
	await _test_form_controls()
	await _test_frame_controls()
	await _test_window_weathering()
	_test_preview()
	print("[workshop-editor-stage] component replacement")
	_test_components(session)
	print("[workshop-editor-stage] saving revisions")
	# 组件操作后用真实 configure 同步绑定下拉框，不能让旧 UI 覆盖新槽位绑定。
	_screen.call("configure", {})
	var first: Dictionary = _result(_screen, "save_building")
	var second: Dictionary = {}
	var legacy_document: Dictionary = {}
	if _check_result("第一次真实保存", first):
		print("[workshop-editor-stage] verify first bundle")
		_verify_bundle(first, "revision1")
		print("[workshop-editor-stage] first bundle verified")
		var first_hashes: Dictionary = _bundle_hashes(str(first.get("directory", "")))
		# 改纯元数据字段制造新版本：改宽高会让已替换的模块包络失配而被正确拒绝，
		# 那验的就不是"同一套几何另存 revision"了。
		var name_edit: LineEdit = _property(_screen, "_name_edit") as LineEdit
		if name_edit != null:
			name_edit.text = "海风公寓 · 连续实体 v2"
			name_edit.text_changed.emit(name_edit.text)
		second = _result(_screen, "save_building")
		if _check_result("第二次真实保存", second):
			print("[workshop-editor-stage] verify second bundle")
			_verify_bundle(second, "revision2")
			print("[workshop-editor-stage] second bundle verified")
			var first_recipe: Dictionary = _dictionary(first.get("recipe", {}))
			var second_recipe: Dictionary = _dictionary(second.get("recipe", {}))
			_check("同建筑连续两个 revision", str(first_recipe.get("building_id", "")) == building_id and str(second_recipe.get("building_id", "")) == building_id and int(second_recipe.get("revision", -1)) == int(first_recipe.get("revision", -3)) + 1 and first.get("directory") != second.get("directory"))
			_check("旧 revision 内容不变", _same(first_hashes, _bundle_hashes(str(first.get("directory", "")))))
			_check("保存同步 clean 状态", not bool(session.call("is_dirty")) and not bool(_screen.call("has_pending_fields")))
			print("[workshop-editor-stage] reopen saved recipe")
			var opened: Dictionary = _result(_screen, "open_recipe", [str(second.get("recipe_path", ""))])
			print("[workshop-editor-stage] reopened recipe")
			_check("主屏拒绝旧版配方但保留历史文件", not bool(opened.get("ok", false)) and str(opened.get("reason", "")).contains("旧版") and FileAccess.file_exists(str(second.get("recipe_path", ""))), str(opened))
			_check("打开配方后仍为原 session", _property(_screen, "session") == session)
			print("[workshop-editor-stage] test dirty recovery")
			# 历史parser、替件与两个revision仍验原legacy文档；恢复入口仅允许shell。
			legacy_document = {"recipe": _snapshot().duplicate(true), "catalog": _dictionary(_property(session, "catalog")).duplicate(true)}
			var recovery_recipe: Dictionary = Recipe.authoring_defaults()
			recovery_recipe["building_id"] = building_id + "_recovery"
			_build_ids.append(str(recovery_recipe["building_id"]))
			if _check_result("dirty与生命周期测试载入独立shell文档", _result(session, "accept_loaded", [recovery_recipe, legacy_document["catalog"]])):
				_screen.call("configure", {})
				var recovery_saved: Dictionary = _result(_screen, "save_building")
				if _check_result("dirty恢复基线真实保存shell文档", recovery_saved):
					_verify_bundle(recovery_saved, "shell_recovery_baseline")
					await _test_recovery(str(first.get("recipe_path", "")), session)
			print("[workshop-editor-stage] dirty recovery finished")
	else:
		_check("第二版本及保存后 dirty 验证", false, "首次保存失败，不能用模拟 Store 代替")
	print("[workshop-editor-stage] lifecycle and screenshots")
	await _test_lifecycle()
	if not legacy_document.is_empty():
		var restored_session: Object = _property(_screen, "session") as Object
		_check_result("shell生命周期后原子恢复历史文档与替件catalog", _result(restored_session, "accept_loaded", [legacy_document["recipe"], legacy_document["catalog"]]))
		_screen.call("configure", {})
		_check("生命周期后历史recipe和替件catalog不丢失", _same(legacy_document["recipe"], _snapshot()) and _same(legacy_document["catalog"], _dictionary(_property(restored_session, "catalog"))))
	await _capture(Vector2i(1280, 800))
	await _capture(Vector2i(1600, 1000))
	# 门窗页通过真实 OptionButton 信号切换，额外核对局部覆盖控件布局。
	var picker: OptionButton = _property(_screen, "_page_picker") as OptionButton
	if picker != null and picker.item_count > 1:
		picker.select(1)
		picker.item_selected.emit(1)
		await _tree.process_frame
		await _capture(Vector2i(1600, 1000), "_floor_facade")
	# 旧破旧L形仅作 modular_v1 兼容证据，不代表新的连续外壳成品。
	var sample_recipe: Dictionary = _read_json("res://data/workshop/samples/workshop_sample_002.recipe.json")
	var sample_session: Object = _property(_screen, "session") as Object
	var source_catalog: Dictionary = (load("res://src/workshop/catalog.gd") as Script).definitions()
	_check_result("编辑器载入破旧生态样例", _result(sample_session, "accept_loaded", [sample_recipe, source_catalog]))
	_screen.call("configure", {})
	_check_result("破旧生态样例真实生成", _result(_screen, "refresh_preview"))
	var sample_preview: Object = _property(_screen, "preview") as Object
	sample_preview.call("set_view", "perspective")
	await _capture(Vector2i(1600, 1000), "_damaged_l_plants")
	_legacy_check_count = _checks.size()
	await _test_shell_samples()
	await _test_architecture_samples()
	_finish()

func _test_shared_scene_materials() -> void:
	if not _require_methods(MeshBuilder, ["shared_materials", "material"], "MeshBuilder"):
		return
	_shared_materials = _dictionary(MeshBuilder.shared_materials())
	for role: String in SHARED_MATERIAL_PATHS:
		var source: ShaderMaterial = load(str(SHARED_MATERIAL_PATHS[role])) as ShaderMaterial
		if _check(role + " 正式资源可读取", source != null):
			_shared_material_state[role] = _shared_material_snapshot(source)
	_shared_materials = _dictionary(MeshBuilder.shared_materials())
	_check("共享材质字典恰好四个SEA角色", _shared_materials.size() == SHARED_MATERIAL_PATHS.size())
	var texture: Texture2D = load(SHARED_PALETTE_PATH) as Texture2D
	_check("正式场景共享色盘为512x512", texture != null and texture.get_width() == 512 and texture.get_height() == 512)
	var identities: Dictionary = {}
	for role: String in SHARED_MATERIAL_PATHS:
		var material: ShaderMaterial = _shared_materials.get(role) as ShaderMaterial
		if not _check(role + " 为共享ShaderMaterial", material != null):
			continue
		identities[material.get_instance_id()] = true
		_check(role + " identity/path/name与正式场景一致", material == load(str(SHARED_MATERIAL_PATHS[role])) and material.resource_path == str(SHARED_MATERIAL_PATHS[role]) and material.resource_name == role and not material.resource_local_to_scene)
		_check(role + " 共用同一512色盘实例", texture != null and material.get_shader_parameter("palette") == texture)
	var cache: Dictionary = {}
	for role: String in SHARED_MATERIAL_PATHS:
		for color: String in ["cozy", "glass", "timber"]:
			for aging: float in [0.0, 0.8]:
				_check(role + " 显式角色不随颜色或老化复制", MeshBuilder.material(color, aging, cache, role) == _shared_materials.get(role))
	_check("四共享材质为四个不同实例", identities.size() == 4)
	_check("glass默认Gloss，其余默认Matte", MeshBuilder.material("glass", 0.0, {}) == _shared_materials.get("SEA_Gloss") and MeshBuilder.material("cozy", 0.8, {}) == _shared_materials.get("SEA_Matte"))
	_check_shared_materials_unchanged("首次材质调用后")

func _shared_material_snapshot(material: ShaderMaterial) -> Dictionary:
	var parameters: Dictionary = {}
	if material.shader != null:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var key: String = str(uniform.name)
			var value: Variant = material.get_shader_parameter(key)
			if value == null:
				value = {"roughness_value": 0.62, "metallic_value": 0.0, "emission_value": 0.0, "grid_role": false, "home_window": false, "home_window_recessed": false, "home_window_column": 3, "alpha_value": 0.81, "tint": Color.WHITE, "interior_glass": false}.get(key)
			# GPU默认float为32位，归一表示误差；仍比较全部有效参数。
			parameters[key] = snappedf(float(value), 0.000001) if value is float or value is int else value
	return {"id": material.get_instance_id(), "path": material.resource_path, "name": material.resource_name, "local": material.resource_local_to_scene, "priority": material.render_priority, "next_pass": material.next_pass, "shader": material.shader, "shader_code": material.shader.code if material.shader != null else "", "parameters": parameters.duplicate(true), "file_hash": FileAccess.get_sha256(material.resource_path), "shader_hash": FileAccess.get_sha256(material.shader.resource_path) if material.shader != null else "", "texture_hash": FileAccess.get_sha256(SHARED_PALETTE_PATH)}

func _check_shared_materials_unchanged(label: String) -> void:
	if _shared_material_state.is_empty():
		return
	var current: Dictionary = _dictionary(MeshBuilder.shared_materials())
	_check(label + " 共享材质仍恰好四项", current.size() == 4)
	for role: String in _shared_material_state:
		var material: ShaderMaterial = current.get(role) as ShaderMaterial
		var state: Dictionary = _shared_material_snapshot(material) if material != null else {}
		var differences: Array[String] = []
		for key: String in state:
			if state[key] != _shared_material_state[role].get(key): differences.append(key + ": " + str(_shared_material_state[role].get(key)) + " -> " + str(state[key]))
		_check(label + " " + role + " identity/参数/文件hash不变", material != null and material == _shared_materials.get(role) and differences.is_empty(), str(differences))

func _shared_material_usage(root: Node) -> Dictionary:
	var used: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node.mesh != null:
				var attached: Array[Material] = [mesh_node.material_override, mesh_node.material_overlay]
				for surface: int in mesh_node.mesh.get_surface_count():
					attached.append(mesh_node.mesh.surface_get_material(surface))
					attached.append(mesh_node.get_surface_override_material(surface))
				for material: Material in attached:
					if material == null:
						continue
					var role: String = material.resource_name
					_check(str(root.get_path_to(node)) + " 底层及覆盖材质均共享identity", material is ShaderMaterial and SHARED_MATERIAL_PATHS.has(role) and material == load(str(SHARED_MATERIAL_PATHS.get(role, ""))))
					used[role] = true
				for surface: int in mesh_node.mesh.get_surface_count():
					var material: Material = mesh_node.get_active_material(surface)
					var role: String = material.resource_name if material != null else "<null>"
					_check(str(root.get_path_to(node)) + " 仅引用正式共享四材质", material is ShaderMaterial and SHARED_MATERIAL_PATHS.has(role) and material == load(str(SHARED_MATERIAL_PATHS.get(role, ""))) and material.resource_path == str(SHARED_MATERIAL_PATHS.get(role, "")))
					used[role] = true
		for child: Node in node.get_children():
			stack.append(child)
	return used

func _test_editor_repair() -> void:
	print("[workshop-editor-stage] editor repair")
	_check_editor_repair_ui("修复专项")
	if not _require_methods(_screen, ["generate_building", "_new_document"], "repair.screen"):
		return
	var original_session: Object = _property(_screen, "session") as Object
	var original_recipe: Dictionary = _snapshot().duplicate(true)
	var original_catalog: Dictionary = _dictionary(_property(original_session, "catalog")).duplicate(true)
	var original_recovery: Dictionary = _result(_screen, "get_recovery").duplicate(true)
	var source_catalog: Dictionary = Catalog.definitions().duplicate(true)
	var old_catalog: Dictionary = source_catalog.duplicate(true)
	var components: Dictionary = _dictionary(old_catalog.get("components", {}))
	components.erase("band_cozy")
	components.erase("pillar_cozy")
	var legacy: Dictionary = Recipe.defaults()
	legacy["vegetation_density"] = 0.0
	var wall_id: String = str(_dictionary(legacy.get("component_bindings", {})).get("wall", ""))
	var wall: Dictionary = _dictionary(components.get(wall_id, {})).duplicate(true)
	wall["version"] = str(wall.get("version", "")) + "_editor_repair_preserved"
	components[wall_id] = wall
	old_catalog["components"] = components
	_check("旧catalog夹具确实缺少腰线与柱", not components.has("band_cozy") and not components.has("pillar_cozy") and Catalog.validate(old_catalog).is_empty())
	var accepted: Dictionary = _result(original_session, "accept_loaded", [legacy, old_catalog])
	if _check_result("修复专项通过历史parser载入旧catalog及legacy基线", accepted):
		var legacy_snapshot: Dictionary = _snapshot().duplicate(true)
		_screen.call("configure", {})
		var repaired: Dictionary = _dictionary(_property(original_session, "catalog")).duplicate(true)
		var expected_catalog: Dictionary = old_catalog.duplicate(true)
		var expected_components: Dictionary = _dictionary(expected_catalog.get("components", {}))
		for component_id: String in ["band_cozy", "pillar_cozy"]:
			expected_components[component_id] = _dictionary(source_catalog.get("components", {})).get(component_id)
		expected_catalog["components"] = expected_components
		_check("configure只补齐缺件且完整保留旧catalog定义与替件", _same(repaired, expected_catalog), str(_dictionary(repaired.get("components", {})).keys()))
		_check("configure补齐不丢legacy文档与session", _property(_screen, "session") == original_session and _same(legacy_snapshot, _snapshot()))
		_check("configure保留自定义wall定义", _same(_dictionary(repaired.get("components", {})).get(wall_id), wall))
		_check("补齐未污染全局Catalog与旧catalog入参", _same(source_catalog, Catalog.definitions()) and not _dictionary(old_catalog.get("components", {})).has("band_cozy") and not _dictionary(old_catalog.get("components", {})).has("pillar_cozy"))
		_screen.call("_new_document")
		await _tree.process_frame
		var fresh: Dictionary = _snapshot().duplicate(true)
		_check("旧catalog之后新建确实切换shell文档", str(fresh.get("construction_mode", "")) == "shell_v2" and str(fresh.get("building_id", "")) != str(legacy_snapshot.get("building_id", "")), _status_text())
		_check("新建保留补齐catalog与自定义wall", _same(repaired, _dictionary(_property(_property(_screen, "session") as Object, "catalog"))))
		var before_geometry: Dictionary = _check_editor_repair_geometry("旧catalog新建shell", true)
		var preview: Control = _property(_screen, "preview") as Control
		var before_root: Node3D = _preview_root(preview)
		var before_root_id: int = before_root.get_instance_id() if before_root != null else 0
		var next_width: float = float(fresh.get("width", 12.0)) + 1.0
		var next_seed: int = int(_dictionary(_dictionary(fresh.get("architecture", {})).get("form", {})).get("seed", 11010)) + 1
		_set_spin("width", next_width)
		_set_spin("pilaster_width", 0.40)
		_set_spin("band_thickness", 0.38)
		_set_spin("form_seed", float(next_seed))
		_check("生成前全局构架形体输入未偷偷提交", _same(fresh, _snapshot()) and bool(_screen.call("has_pending_fields")))
		# pressed送达不是成功：必须同时查配方、实际新预览根、网格hash和包围盒。
		_emit_button("generate")
		await _tree.process_frame
		var generated: Dictionary = _snapshot().duplicate(true)
		var architecture: Dictionary = _dictionary(generated.get("architecture", {}))
		_check("固定主按钮真实提交宽度", is_equal_approx(float(generated.get("width", 0.0)), next_width), _status_text())
		_check("生成接受未应用全局构架与形体", is_equal_approx(float(_dictionary(architecture.get("pilaster", {})).get("width", 0.0)), 0.40) and is_equal_approx(float(_dictionary(architecture.get("band", {})).get("thickness", 0.0)), 0.38) and int(_dictionary(architecture.get("form", {})).get("seed", -1)) == next_seed, _status_text())
		var after_geometry: Dictionary = _check_editor_repair_geometry("固定主按钮生成", true)
		var after_root: Node3D = _preview_root(preview)
		_check("固定主按钮确实替换实际预览根", after_root != null and after_root.get_instance_id() != before_root_id)
		_check("固定主按钮确实改变网格及实际宽度", str(before_geometry.get("mesh_geometry_hash", "")) != str(after_geometry.get("mesh_geometry_hash", "")) and float((after_geometry.get("bounds_size", [0.0]) as Array)[0]) > float((before_geometry.get("bounds_size", [0.0]) as Array)[0]))
		var shell_recovery: Dictionary = _result(_screen, "get_recovery").duplicate(true)
		# 直接API也必须接收全局构架/形体，不只验按钮路由。
		_set_check("pilaster_enabled", false)
		_set_check("band_enabled", false)
		_set_check("form_enabled", false)
		_check_result("generate_building真实API接受全局未应用值", _result(_screen, "generate_building"))
		var disabled_architecture: Dictionary = _dictionary(_snapshot().get("architecture", {}))
		var disabled_visual: Node3D = _preview_visual(preview)
		_check("generate_building关闭构架形体进入snapshot及geometry", not bool(_dictionary(disabled_architecture.get("pilaster", {})).get("enabled", true)) and not bool(_dictionary(disabled_architecture.get("band", {})).get("enabled", true)) and not bool(_dictionary(disabled_architecture.get("form", {})).get("enabled", true)) and _count_prefix(disabled_visual, "pilaster_") == 0 and _count_prefix(disabled_visual, "band_") == 0)
		_check_editor_repair_geometry("生成API关闭构架形体", false)
		# 独立验证局部窗、槽、楼层；每次都保留全局宽度输入，拒绝时不许提交任何一部分。
		for local_key: String in ["architecture_window_width", "offset_x", "floor_override_window_width"]:
			_screen.call("configure", {})
			if local_key == "architecture_window_width":
				_set_option("window_scope", "floor")
			elif local_key == "offset_x":
				var slot_ids: Array = _dictionary(_property(_screen, "_slot_cache")).keys()
				_check("局部槽拒绝测试存在真实槽", not slot_ids.is_empty())
				if not slot_ids.is_empty():
					_screen.call("select_slot", str(slot_ids[0]))
			var before_local: Dictionary = _snapshot().duplicate(true)
			var before_local_catalog: Dictionary = _dictionary(_property(_property(_screen, "session") as Object, "catalog")).duplicate(true)
			var local_root: Node3D = _preview_root(preview)
			var local_geometry: Dictionary = _geometry(local_root) if local_root != null else {}
			_set_spin("width", float(before_local.get("width", 12.0)) + 0.5)
			var local_value: float = _spin(local_key) + 0.1
			_set_spin(local_key, local_value)
			var rejected: Dictionary = _result(_screen, "generate_building")
			_check("生成拒绝未应用局部输入：" + local_key, not bool(rejected.get("ok", false)) and not str(rejected.get("reason", "")).is_empty(), str(rejected))
			_emit_button("generate")
			var unchanged_root: Node3D = _preview_root(preview)
			_check("局部拒绝不改recipe/catalog/geometry：" + local_key, _same(before_local, _snapshot()) and _same(before_local_catalog, _dictionary(_property(_property(_screen, "session") as Object, "catalog"))) and unchanged_root != null and _same(local_geometry, _geometry(unchanged_root)))
			_check("局部拒绝保留全局及局部未提交输入：" + local_key, is_equal_approx(_spin("width"), float(before_local.get("width", 12.0)) + 0.5) and is_equal_approx(_spin(local_key), local_value))
		_screen.call("configure", {})
		_set_spin("width", float(_snapshot().get("width", 12.0)) + 0.2)
		_set_spin("floor_override_window_width", _spin("floor_override_window_width") + 0.1)
		var live_before_legacy: Dictionary = _result(_screen, "get_recovery").duplicate(true)
		var live_root: Node3D = _preview_root(preview)
		var live_geometry: Dictionary = _geometry(live_root) if live_root != null else {}
		var live_session: Object = _property(_screen, "session") as Object
		var legacy_recovery: Dictionary = shell_recovery.duplicate(true)
		legacy_recovery["recipe"] = legacy_snapshot
		legacy_recovery["catalog"] = old_catalog.duplicate(true)
		var refused: Dictionary = _result(_screen, "restore_recovery", [legacy_recovery])
		_check("旧legacy recovery明确拒绝并提示新建", not bool(refused.get("ok", false)) and str(refused.get("reason", "")).contains("新建") and _status_text().contains("新建"), str(refused))
		var preserved_root: Node3D = _preview_root(preview)
		_check("拒绝旧recovery不覆盖当前现场", _property(_screen, "session") == live_session and _same(live_before_legacy, _result(_screen, "get_recovery")) and preserved_root != null and _same(live_geometry, _geometry(preserved_root)))
		var incomplete_recovery: Dictionary = shell_recovery.duplicate(true)
		var incomplete_catalog: Dictionary = _dictionary(incomplete_recovery.get("catalog", {}))
		_dictionary(incomplete_catalog.get("components", {})).erase("band_cozy")
		_dictionary(incomplete_catalog.get("components", {})).erase("pillar_cozy")
		incomplete_recovery["catalog"] = incomplete_catalog
		_check("shell恢复夹具确实带shell配方且缺少新增components", str(_dictionary(incomplete_recovery.get("recipe", {})).get("construction_mode", "")) == "shell_v2" and not _dictionary(incomplete_catalog.get("components", {})).has("band_cozy") and not _dictionary(incomplete_catalog.get("components", {})).has("pillar_cozy"))
		var restored: Dictionary = _result(_screen, "restore_recovery", [incomplete_recovery])
		_check_result("缺少新增components的shell recovery必须成功", restored)
		_check("shell恢复原子保留recipe及完整catalog", _same(_dictionary(shell_recovery.get("recipe", {})), _snapshot()) and _same(_dictionary(shell_recovery.get("catalog", {})), _dictionary(_property(_property(_screen, "session") as Object, "catalog"))))
		var restored_geometry: Dictionary = _check_editor_repair_geometry("补齐catalog的shell recovery", true)
		_check("shell recovery恢复的是原真实geometry", _same(after_geometry, restored_geometry))
		_check("shell recovery补齐不修改入参", not _dictionary(incomplete_catalog.get("components", {})).has("band_cozy") and not _dictionary(incomplete_catalog.get("components", {})).has("pillar_cozy"))
		_screen.call("_select_page", 0)
		await _tree.process_frame
		await _capture(Vector2i(1600, 1000), "_laowang_framework")
	# recipe和catalog必须在同一次accept_loaded恢复，不能先换catalog导致当前shell临时失效。
	_check_result("修复专项原子恢复原recipe与catalog", _result(original_session, "accept_loaded", [original_recipe, original_catalog]))
	_screen.call("configure", {"session": original_session})
	_check_result("修复专项恢复原文档现场", _result(_screen, "restore_recovery", [original_recovery]))
	_check("修复专项不丢原文档与catalog", _same(original_recipe, _snapshot()) and _same(original_catalog, _dictionary(_property(_property(_screen, "session") as Object, "catalog"))))
	_check("修复专项恢复原UI未提交字段与现场", _same(original_recovery, _result(_screen, "get_recovery")))

func _check_editor_repair_geometry(label: String, require_frame: bool) -> Dictionary:
	var preview: Control = _property(_screen, "preview") as Control
	var root: Node3D = _preview_root(preview)
	if not _check(label + " 存在实际shell预览", root != null and str(root.get_meta("construction_mode", "")) == "shell_v2"):
		return {}
	var actual: Dictionary = _geometry(root)
	_check(label + " 实际网格碰撞非空且配方指纹匹配", int(actual.get("visual_meshes", 0)) > 0 and int(actual.get("collision_shapes", 0)) > 0 and str(root.get_meta("recipe_fingerprint", "")) == Recipe.fingerprint(_snapshot()))
	var session: Object = _property(_screen, "session") as Object
	var expected: Dictionary = Generator.build(_snapshot(), _dictionary(_property(session, "catalog")))
	var expected_root: Node = expected.get("root") as Node
	_check(label + " 实际geometry匹配当前snapshot重新生成", bool(expected.get("ok", false)) and expected_root != null and _same(actual, _geometry(expected_root)), str(expected.get("reason", "")))
	if expected_root != null:
		expected_root.free()
	if require_frame:
		var visual: Node3D = _preview_visual(preview)
		var counts: Dictionary = {"band_": 0, "pilaster_": 0}
		if visual != null:
			for node: Node in visual.get_children():
				var mesh: MeshInstance3D = node as MeshInstance3D
				if mesh == null or mesh.mesh == null or mesh.mesh.get_faces().is_empty():
					continue
				for prefix: String in counts:
					if str(mesh.name).begins_with(prefix):
						counts[prefix] += 1
		_check(label + " 腰线与柱均有真实三角网格", int(counts["band_"]) > 0 and int(counts["pilaster_"]) > 0, str(counts))
	return actual

func _check_editor_repair_ui(label: String) -> void:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var mode: OptionButton = controls.get("construction_mode") as OptionButton
	# 兼容内部保留双项供历史parser回归；不依赖下拉项数或legacy项是否仍存在。
	_check(label + " construction_mode保留但自身hidden", mode != null and not mode.visible)
	var old_ui: Array[String] = []
	var stack: Array[Node] = [_screen]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control and (node as Control).is_visible_in_tree():
			# 状态栏应允许解释为何拒绝历史草稿，不是旧方案选择入口。
			var text: String = "" if node == _property(_screen, "status_label") else ((node as Label).text if node is Label else ((node as Button).text if node is Button else ""))
			if text.contains("旧版拼装") or text.contains("建模内核") or text.contains("modular_v1"):
				old_ui.append(text)
			if node is OptionButton:
				var option: OptionButton = node as OptionButton
				for index: int in option.item_count:
					if str(option.get_item_metadata(index)) == "modular_v1" or option.get_item_text(index).contains("旧版拼装"):
						old_ui.append(option.get_item_text(index))
		for child: Node in node.get_children():
			if not child is Window:
				stack.append(child)
	_check(label + " 没有旧版可见方案UI", old_ui.is_empty(), str(old_ui))
	var buttons: Dictionary = _dictionary(_property(_screen, "buttons"))
	var generate: Button = buttons.get("generate") as Button
	if _check(label + " 固定生成主按钮存在", generate != null):
		_check(label + " 固定生成主按钮文案", generate.text == "应用参数并生成楼房", generate.text)
		_check(label + " 固定生成主按钮可见且高度至少40", generate.is_visible_in_tree() and generate.size.y >= 40.0, str(generate.size))
		_check(label + " 固定生成主按钮完整落在可见区域", _visible_rect(generate).is_equal_approx(generate.get_global_rect()) and generate.size.x > 0.0, str(_visible_rect(generate)))
		var parent: Node = generate.get_parent()
		var scroll_ancestors: Array[String] = []
		while parent != null:
			if parent is ScrollContainer:
				scroll_ancestors.append(str(parent.get_path()))
			parent = parent.get_parent()
		_check(label + " 生成按钮不在任何ScrollContainer下", scroll_ancestors.is_empty(), str(scroll_ancestors))
	var left: Control = _property(_screen, "_left_panel") as Control
	for key: String in ["generate", "apply"]:
		var button: Button = buttons.get(key) as Button
		_check(label + " 按钮位于独立顶部工具栏：" + key, button != null and left != null and button.is_visible_in_tree() and button.get_global_rect().end.y <= left.get_global_rect().position.y + 1.0)

func _test_shell_samples() -> void:
	print("[workshop-editor-stage] continuous shell samples")
	var session: Object = _property(_screen, "session") as Object
	var preview: Control = _property(_screen, "preview") as Control
	if not _require_methods(preview, ["set_view", "capture_model_image"], "shell.preview"):
		return
	var catalog: Dictionary = Catalog.definitions()
	var token: String = "%s_%s" % [str(int(Time.get_unix_time_from_system())), str(Time.get_ticks_usec())]
	for shape: String in ["rectangle", "l"]:
		var recipe: Dictionary = Recipe.authoring_defaults()
		_check("新创作默认连续实体", str(recipe.get("construction_mode", "")) == "shell_v2")
		var sample_key: String = "rect" if shape == "rectangle" else "l"
		var building_id: String = "shell_%s_%s" % [sample_key, token]
		recipe["building_id"] = building_id
		recipe["shape"] = shape
		if shape == "l":
			recipe["width"] = 12.0
			recipe["depth"] = 12.0
		_build_ids.append(building_id)
		if not _check_result(sample_key + " 连续实体载入默认配方与原始Catalog", _result(session, "accept_loaded", [recipe, catalog])):
			continue
		_screen.call("configure", {"export_root": OUTPUT_ROOT})
		var built: Dictionary = _result(_screen, "refresh_preview")
		if not _check_result(sample_key + " 主屏真实连续生成", built):
			continue
		_check(sample_key + " shell独立配方没有继承legacy覆盖", str(_snapshot().get("construction_mode", "")) == "shell_v2" and str(_snapshot().get("building_id", "")) == building_id and _dictionary(_snapshot().get("slot_overrides", {})).is_empty() and _dictionary(_snapshot().get("floor_overrides", {})).is_empty())
		var model: Node3D = _property(preview, "_model_root") as Node3D
		var root: Node3D = model.get_child(0) as Node3D if model != null and model.get_child_count() == 1 else null
		var audit: Dictionary = _verify_shell_geometry(root, recipe, sample_key)
		_test_shell_surface_selection(preview, root, built.get("openings", []), sample_key)
		var saved_shell: Dictionary = _result(_screen, "save_building")
		if _check_result(sample_key + " 连续模型五件静态烘焙", saved_shell):
			_verify_bundle(saved_shell, "shell_" + sample_key)
		var artifact_start: int = _artifacts.size()
		preview.call("set_view", "perspective")
		if shape == "rectangle":
			await _capture(Vector2i(1600, 1000), "_continuous_rect")
			await _capture_shell_model(preview, "rect")
			preview.call("set_view", "front")
			await _capture(Vector2i(1600, 1000), "_continuous_front")
			await _capture_shell_model(preview, "front")
			preview.call("set_view", "back")
			await _capture(Vector2i(1600, 1000), "_continuous_back")
		else:
			preview.call("set_view", "top")
			await _capture(Vector2i(1600, 1000), "_continuous_l_top")
			preview.call("set_view", "perspective")
			await _capture(Vector2i(1600, 1000), "_continuous_l")
			await _capture_shell_model(preview, "l")
		var sample_artifacts: Array[String] = []
		for index: int in range(artifact_start, _artifacts.size()):
			sample_artifacts.append(_artifacts[index])
		_shell_samples.append({"building_id": building_id, "recipe": _snapshot(), "actual_geometry": audit, "artifacts": sample_artifacts, "source": "真实主屏session.accept_loaded + refresh_preview；模型图为同一预览世界的独立离屏渲染，不是完整编辑器截图"})

func _test_shell_surface_selection(preview: Control, root: Node3D, openings: Array, label: String) -> void:
	for opening: Dictionary in openings:
		if str(opening.get("type", "")) != "window":
			continue
		var origin: Vector3 = root.global_transform * (opening.center + opening.outward * 1.0)
		var direction: Vector3 = -(root.global_transform.basis * (opening.outward as Vector3)).normalized()
		var suffix: String = str(opening.id).trim_prefix("opening_")
		var wall: Dictionary = {"node_path": "GeneratedVisual/wall_shell_" + str(opening.floor)}
		var glass: Dictionary = {"node_path": "GeneratedVisual/glass_" + suffix}
		var wall_hit: float = float(preview.call("_ray_slot_surface", wall, origin, direction))
		var glass_hit: float = float(preview.call("_ray_slot_surface", glass, origin, direction))
		_check(label + " 点击洞口不先选中整层AABB", glass_hit > 0.0 and (wall_hit < 0.0 or glass_hit < wall_hit))
		break

func _capture_shell_model(preview: Control, label: String) -> void:
	var image: Image = (await preview.call("capture_model_image", Vector2i(1400, 1100))) as Image
	if not _check(label + " 真实离屏模型图1400x1100", image != null and not image.is_empty() and image.get_size() == Vector2i(1400, 1100)):
		return
	var model: Node3D = _property(preview, "_model_root") as Node3D
	var view_camera: Camera3D = _property(preview, "camera") as Camera3D
	_check(label + " 模型原始相机与阴影保留", model != null and view_camera != null and _shadow_enabled(preview))
	# 从真实像素测量主体，不把1400px画布等同于600px模型。
	var background: Color = image.get_pixel(0, 0)
	var left: int = image.get_width()
	var right: int = -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if maxf(absf(pixel.r - background.r), maxf(absf(pixel.g - background.g), absf(pixel.b - background.b))) > 0.08:
				left = mini(left, x)
				right = maxi(right, x)
	_check(label + " 模型实际像素宽度至少600", right - left + 1 >= 600, "实际前景宽度：%dpx" % maxi(0, right - left + 1))
	var path: String = "res://outputs/workshop_shell_model_%s.png" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	if _check(label + " 模型大图落盘", image.save_png(path) == OK):
		_artifacts.append(path)

func _shadow_enabled(preview: Control) -> bool:
	var world: Node3D = _property(preview, "_world") as Node3D
	if world == null:
		return false
	for node: Node in world.get_children():
		if node is DirectionalLight3D and (node as DirectionalLight3D).shadow_enabled:
			return true
	return false

func _verify_shell_geometry(root: Node3D, recipe: Dictionary, label: String) -> Dictionary:
	if not _check(label + " 实际连续生成根", root != null and str(root.get_meta("generator_version", "")) == "sea_workshop_continuous_shell_v2" and str(root.get_meta("construction_mode", "")) == "shell_v2"):
		return {}
	var visual: Node3D = root.get_node_or_null("GeneratedVisual") as Node3D
	if not _check(label + " 实际可视几何分支", visual != null):
		return {}
	var walls: int = 0
	var slabs: int = 0
	var roofs: int = 0
	var frames: int = 0
	var glasses: int = 0
	var sills: int = 0
	var plinths: int = 0
	var canopies: int = 0
	var forbidden: Array[String] = []
	var posts_by_floor: Dictionary = {}
	var bands_by_floor: Dictionary = {}
	var topology: Dictionary = {}
	var weathering_inventory: Dictionary = _weathering_inventory(root)
	for node: Node in visual.get_children():
		var id: String = str(node.name)
		if id.begins_with("wall_shell_"):
			walls += 1
		elif id.begins_with("slab_"):
			slabs += 1
		elif id == "roof_main":
			roofs += 1
		elif id.begins_with("wall_weathering_"):
			_check(label + " 斑驳仅在非零aging出现：" + id, float(recipe.get("aging", 0.0)) > 0.0)
			# 仍走下方逐件闭合定向审计；碰撞单独审核，不能只放行名称。
			_check(label + " 斑驳无碰撞：" + id, not weathering_inventory.collisions.has(id))
		elif id.begins_with("frame_"):
			frames += 1
		elif id.begins_with("glass_"):
			glasses += 1
		elif id.begins_with("sill_"):
			sills += 1
		elif id.begins_with("plinth_"):
			plinths += 1
		elif id.begins_with("canopy_"):
			canopies += 1
		elif id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_") or id.begins_with("sash_") or id.begins_with("belt_") or id.begins_with("door_") or id.begins_with("pilaster_") or id.begins_with("band_"):
			# 门扇是整件实体（不是分段墙），与窗台板/活动扇同级别放行；
			# 承重柱与腰线是 v4 起的正式立面构件，件数与逐层一致性另有专门断言。
			if id.begins_with("pilaster_"):
				var post_floor: String = id.trim_prefix("pilaster_").split("_")[0]
				posts_by_floor[post_floor] = int(posts_by_floor.get(post_floor, 0)) + 1
			elif id.begins_with("band_"):
				var band_floor: String = id.trim_prefix("band_").split("_")[0]
				bands_by_floor[band_floor] = int(bands_by_floor.get(band_floor, 0)) + 1
		else:
			forbidden.append(id)
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if not _check(label + " 整件真实ArrayMesh：" + id, mesh_node != null and mesh_node.mesh is ArrayMesh and mesh_node.get_child_count() == 0):
			continue
		var faces: PackedVector3Array = mesh_node.mesh.get_faces()
		var audit: Dictionary = _audit_shell_faces(faces)
		topology[id] = audit
		_check(label + " 实际三角面单连通闭合且定向：" + id, bool(audit.get("closed", false)) and bool(audit.get("oriented", false)) and int(audit.get("connected_components", 0)) == 1, str(audit))
	var run_lengths: Array[float] = [float(recipe.width), float(recipe.depth), float(recipe.width), float(recipe.depth)]
	if str(recipe.shape) == "l":
		run_lengths = [float(recipe.width), float(recipe.depth) * 0.5, float(recipe.width) * 0.5, float(recipe.depth) * 0.5, float(recipe.width) * 0.5, float(recipe.depth)]
	var openings_per_floor: int = 0
	for run_length: float in run_lengths:
		openings_per_floor += maxi(1, floori(run_length / float(recipe.bay_width)))
	var expected_frames: int = openings_per_floor * int(recipe.floors)
	_check(label + " 实际整框与玻璃数量", frames == expected_frames and glasses == expected_frames - 1, "frame=%d glass=%d expected_frame=%d" % [frames, glasses, expected_frames])
	_check(label + " 每层一墙壳一整板及一个整屋顶", walls == int(recipe.floors) and slabs == int(recipe.floors) and roofs == 1, "wall=%d slab=%d roof=%d" % [walls, slabs, roofs])
	_check(label + " 无legacy屋顶cell或分段墙", forbidden.is_empty(), str(forbidden))
	var frame_arch: Dictionary = _dictionary(Config.normalized(recipe).get("architecture", {}))
	var pilaster_on: bool = bool(_dictionary(frame_arch.get("pilaster", {})).get("enabled", false))
	var band_on: bool = bool(_dictionary(frame_arch.get("band", {})).get("enabled", false))
	var post_counts: Array = posts_by_floor.values()
	_check(label + " 承重柱逐层等量且与开关一致",
		(post_counts.size() == int(recipe.floors) and int(post_counts[0]) > 0 and post_counts.min() == post_counts.max()) if pilaster_on else post_counts.is_empty(),
		str(posts_by_floor))
	# 顶层没有上层楼板缝，不生成腰线；其余楼层逐层等段。
	var band_counts: Array = bands_by_floor.values()
	_check(label + " 腰线只在非顶层逐层等段",
		(bands_by_floor.size() == int(recipe.floors) - 1 and not bands_by_floor.has(str(int(recipe.floors) - 1)) and (band_counts.is_empty() or band_counts.min() == band_counts.max())) if band_on else band_counts.is_empty(),
		str(bands_by_floor))
	_check(label + " 整栋一圈勒脚", plinths == 1, str(plinths))
	_check(label + " 每窗一块窗台板", sills == glasses, "sill=%d glass=%d" % [sills, glasses])
	_check(label + " 入口雨棚与两根落地柱", canopies == 3, str(canopies))
	var doors: int = 0
	for node: Node in visual.get_children():
		if str(node.name).begins_with("door_"):
			doors += 1
	_check(label + " 门洞有实际门扇而非看穿", doors == 1, str(doors))
	var height: float = float(recipe.floor_height) * int(recipe.floors)
	var width: float = float(recipe.width)
	var depth: float = float(recipe.depth)
	var actual_taper: float = float(Recipe.normalized(recipe).taper)
	for floor_index: int in range(int(recipe.floors)):
		var wall: MeshInstance3D = visual.get_node_or_null("wall_shell_%d" % floor_index) as MeshInstance3D
		if not _check(label + " 实际楼层墙壳：%d" % floor_index, wall != null and wall.mesh != null):
			continue
		var faces: PackedVector3Array = wall.mesh.get_faces()
		var transform: Transform3D = _relative_transform(wall, root)
		var untapered: AABB = AABB()
		var initialized: bool = false
		for index: int in range(faces.size()):
			faces[index] = transform * faces[index]
			var point: Vector3 = faces[index]
				# 反解用的taper必须与生成实际值一致；形体开启时配方字段只是输入，不是权威值。
			var scale: float = 1.0 - actual_taper * clampf(point.y / height, 0.0, 1.0)
			point = Vector3(point.x / scale, point.y, point.z / scale)
			untapered = untapered.expand(point) if initialized else AABB(point, Vector3.ZERO)
			initialized = true
		_check(label + " 整栋统一taper墙壳包络：%d" % floor_index, initialized and absf(untapered.position.x + width * 0.5) < 0.0001 and absf(untapered.end.x - width * 0.5) < 0.0001 and absf(untapered.position.z + depth * 0.5) < 0.0001 and absf(untapered.end.z - depth * 0.5) < 0.0001)
		# 独立按配方推导正立面洞心，不信任openings/topology元数据。
		var bays: int = maxi(1, floori(width / float(recipe.bay_width)))
		for bay: int in range(bays):
			var is_door: bool = floor_index == 0 and bay == int((bays - 1) / 2)
			var y: float = float(recipe.floor_height) * floor_index + (float(recipe.door_height) * 0.5 if is_door else float(recipe.window_sill) + float(recipe.window_height) * 0.5)
			var scale: float = 1.0 - float(recipe.taper) * y / height
			var x: float = (-width * 0.5 + width * (float(bay) + 0.5) / bays) * scale
			var center: Vector3 = Vector3(x, y, -depth * 0.5 * scale)
			_check(label + " 墙壳真实贯穿门窗：%d/%d" % [floor_index, bay], not _shell_segment_hit(faces, center + Vector3.FORWARD, center + Vector3.BACK))
		var solid_y: float = float(recipe.floor_height) * floor_index + float(recipe.floor_height) - float(recipe.slab_thickness) - 0.1
		var solid_scale: float = 1.0 - float(recipe.taper) * solid_y / height
		var solid: Vector3 = Vector3(0.0, solid_y, -depth * 0.5 * solid_scale)
		_check(label + " 洞外实际墙面存在：%d" % floor_index, _shell_segment_hit(faces, solid + Vector3.FORWARD, solid + Vector3.BACK))
	if str(recipe.shape) == "l":
		for node: Node in visual.get_children():
			if not str(node.name).begins_with("slab_") and str(node.name) != "roof_main":
				continue
			var slab: MeshInstance3D = node as MeshInstance3D
			if slab == null or slab.mesh == null:
				continue
			var faces: PackedVector3Array = slab.mesh.get_faces()
			var transform: Transform3D = _relative_transform(slab, root)
			for index: int in range(faces.size()):
				faces[index] = transform * faces[index]
			_check(label + " L缺口实际无板面：" + str(node.name), not _shell_segment_hit(faces, Vector3(width * 0.25, -1.0, depth * 0.25), Vector3(width * 0.25, height + 1.0, depth * 0.25)))
	return {"geometry": _geometry(root), "wall_shells": walls, "slabs": slabs, "roofs": roofs, "actual_mesh_topology": topology, "generator_topology_auxiliary_only": _dictionary(root.get_meta("quality", {})).get("topology", {})}

func _audit_shell_faces(faces: PackedVector3Array) -> Dictionary:
	var edges: Dictionary = {}
	var adjacency: Dictionary = {}
	var valid: bool = not faces.is_empty() and faces.size() % 3 == 0
	for index: int in range(0, faces.size() - 2, 3):
		valid = valid and faces[index].is_finite() and faces[index + 1].is_finite() and faces[index + 2].is_finite() and (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).length_squared() > 0.000000000001
		for edge: int in range(3):
			var a: Vector3i = Vector3i((faces[index + edge] * 100000.0).round())
			var b: Vector3i = Vector3i((faces[index + (edge + 1) % 3] * 100000.0).round())
			if not adjacency.has(a):
				adjacency[a] = []
			if not adjacency.has(b):
				adjacency[b] = []
			(adjacency[a] as Array).append(b)
			(adjacency[b] as Array).append(a)
			var forward: bool = str(a) < str(b)
			var key: String = "%s:%s" % [str(a), str(b)] if forward else "%s:%s" % [str(b), str(a)]
			var count: Vector2i = edges.get(key, Vector2i.ZERO)
			count.x += 1
			count.y += 1 if forward else -1
			edges[key] = count
	var boundary: int = 0
	var nonmanifold: int = 0
	var orientation: int = 0
	for raw: Variant in edges.values():
		var count: Vector2i = raw
		if count.x == 1:
			boundary += 1
		elif count.x != 2:
			nonmanifold += 1
		if count.y != 0:
			orientation += 1
	var visited: Dictionary = {}
	var components: int = 0
	for raw: Variant in adjacency:
		var vertex: Vector3i = raw
		if visited.has(vertex):
			continue
		components += 1
		var pending: Array[Vector3i] = [vertex]
		visited[vertex] = true
		while not pending.is_empty():
			var current: Vector3i = pending.pop_back()
			for neighbor: Vector3i in adjacency[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)
	return {"closed": valid and boundary == 0 and nonmanifold == 0, "oriented": valid and orientation == 0, "connected_components": components, "boundary_edges": boundary, "nonmanifold_edges": nonmanifold, "orientation_errors": orientation, "triangles": int(faces.size() / 3)}

func _shell_segment_hit(faces: PackedVector3Array, start: Vector3, end: Vector3) -> bool:
	for index: int in range(0, faces.size() - 2, 3):
		if Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2]) != null:
			return true
	return false

func _verify_isolation() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	var cli_ok: bool = args.has("--editor") and not args.has("--script") and not args.has("-s")
	_check("真实 --editor 非 --script", cli_ok, str(args))
	var no_autoload: bool = true
	for entry: Dictionary in ProjectSettings.get_property_list():
		if str(entry.get("name", "")).begins_with("autoload/"):
			no_autoload = false
	_check("隔离项目没有 Autoload", no_autoload)
	var no_main: bool = str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty()
	_check("隔离项目没有 Main 入口", no_main)
	var enabled: PackedStringArray = PackedStringArray(ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()))
	var only_plugin: bool = enabled.size() == 1 and enabled[0] == "res://addons/building_workshop/plugin.cfg"
	_check("只启用老王场景工坊插件", only_plugin, str(enabled))
	var copy_path: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var isolated_copy: bool = copy_path != "d:/projects/sea/godot"
	_check("fixture 只能写隔离副本", isolated_copy, copy_path)
	var no_main_node: bool = true
	var stack: Array[Node] = [_tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script() as Script
		if node.name == &"Main" or (script != null and script.resource_path == "res://src/bootstrap/main.gd"):
			no_main_node = false
		for child: Node in node.get_children():
			stack.append(child)
	_check("编辑器树没有启动 Main", no_main_node)
	return cli_ok and no_autoload and no_main and only_plugin and isolated_copy and no_main_node

func _test_overrides() -> void:
	var base_width: float = float(_snapshot().get("width", 0.0))
	_set_spin("width", base_width + 0.5)
	_set_spin("floor_override_index", 0.0)
	_set_spin("floor_override_height", 5.5)
	_emit_button("floor_apply")
	var floors: Dictionary = _dictionary(_snapshot().get("floor_overrides", {}))
	var floor_zero: Dictionary = _dictionary(floors.get("0", {}))
	_check("真实楼层按钮应用覆盖", is_equal_approx(float(floor_zero.get("floor_height", 0.0)), 5.5))
	_check("局部按钮不吞未应用宽度", is_equal_approx(_spin("width"), base_width + 0.5) and is_equal_approx(float(_snapshot().get("width", 0.0)), base_width))
	_set_spin("width", base_width)
	_set_spin("facade_width", 1.2)
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var facade_picker: OptionButton = controls.get("facade_index") as OptionButton
	if not _check("实际立面下拉控件", facade_picker != null and facade_picker.selected >= 0):
		return
	var facade: String = str(facade_picker.get_item_metadata(facade_picker.selected))
	_emit_button("facade_apply")
	var facades: Dictionary = _dictionary(_snapshot().get("facade_overrides", {}))
	_check("真实立面按钮应用覆盖", is_equal_approx(float(_dictionary(facades.get(facade, {})).get("width", 0.0)), 1.2))
	_check_result("覆盖后全部参数可应用", _result(_screen, "apply_parameters"))

## 承重柱与腰线：控件存在、开关各自生效、几何真的跟着变。
func _test_frame_controls() -> void:
	print("[workshop-editor-stage] frame controls")
	var session: Object = _property(_screen, "session") as Object
	if session == null:
		_check("构架测试有session", false)
		return
	var keys: Array[String] = ["pilaster_enabled", "pilaster_corner", "pilaster_middle", "pilaster_width", "pilaster_projection", "pilaster_bite", "band_enabled", "band_projection", "band_thickness"]
	for key: String in keys:
		_check("构架控件存在：" + key, _dictionary(_property(_screen, "controls")).has(key))
	_check("构架应用按钮存在", _dictionary(_property(_screen, "buttons")).has("frame_apply"))

	var original: Dictionary = _snapshot().duplicate(true)
	# 基线必须自己造一份连续实体文档：不能拿"当前文档"当基线——上一个用例可能把编辑器
	# 留在 old modular_v1 老配方上，构架会被正确地拒绝，那测的就不是构架而是模式守卫了。
	var baseline: Dictionary = _orthographic_recipe()
	baseline["building_id"] = str(original.get("building_id", baseline.get("building_id", "")))
	baseline["revision"] = int(original.get("revision", 1))
	baseline["display_name"] = str(original.get("display_name", baseline.get("display_name", "")))
	baseline["taper"] = 0.0
	baseline["bay_width"] = 3.0
	baseline["door_width"] = 1.6
	# 逐层用 get 兜底：dict["a"]["b"] 在缺键时会直接抛错并让整轮验收 124 超时。
	var architecture: Dictionary = _dictionary(baseline.get("architecture", {}))
	if architecture.is_empty():
		architecture = Config.defaults()
	var form: Dictionary = _dictionary(architecture.get("form", {}))
	form["enabled"] = false
	architecture["form"] = form
	architecture["pilaster"] = {"enabled": false, "corner": true, "middle": true, "width": 0.36, "projection": 0.18, "bite": 0.06, "bevel": 0.014}
	architecture["band"] = {"enabled": false, "projection": 0.10, "thickness": 0.34, "bevel": 0.012}
	baseline["architecture"] = architecture
	if not _check("构架基线是连续实体", str(baseline.get("construction_mode", "")) == "shell_v2", str(baseline.get("construction_mode", ""))):
		return
	if not _check_result("构架测试载入基线", _result(session, "accept_loaded", [baseline, _dictionary(_property(session, "catalog"))])):
		return
	_screen.call("configure", {})
	_check_result("构架测试刷新预览", _result(_screen, "refresh_preview"))
	# 构架只在 shell_v2 生效，先确认下拉真的跟着文档回到连续实体。
	var mode_option: OptionButton = _dictionary(_property(_screen, "controls")).get("construction_mode") as OptionButton
	var mode_selected: int = mode_option.selected if mode_option != null else -99
	var mode_value: String = str(mode_option.get_item_metadata(mode_selected)) if mode_option != null and mode_selected >= 0 else "<none>"
	_check("构架测试处于连续实体模式", mode_value == "shell_v2",
		"下拉=%s(sel=%d,items=%d) 配方=%s" % [mode_value, mode_selected, mode_option.item_count if mode_option != null else -1, str(baseline.get("construction_mode", "<missing>"))])
	var closed_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	_check("关闭时没有柱件", _count_prefix(closed_visual, "pilaster_") == 0, str(_count_prefix(closed_visual, "pilaster_")))
	_check("关闭时没有腰线件", _count_prefix(closed_visual, "band_") == 0, str(_count_prefix(closed_visual, "band_")))

	# 1) 只开柱：柱出现、腰线仍无。
	_set_check("pilaster_enabled", true)
	_set_check("pilaster_corner", true)
	_set_check("pilaster_middle", true)
	_set_spin("pilaster_width", 0.36)
	_set_spin("pilaster_projection", 0.18)
	_set_spin("pilaster_bite", 0.06)
	_check_result("开柱应用", _result_button("frame_apply"))
	var post_status: String = _status_text()
	var post_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	var posts: int = _count_prefix(post_visual, "pilaster_")
	var bands_only: int = _count_prefix(post_visual, "band_")
	_check("开柱应用未被拒绝", not post_status.contains("拒绝"), post_status)
	_check("开柱后柱件出现", posts > 0, "%d（%s）" % [posts, post_status])
	_check("只开柱时不生成腰线", bands_only == 0, str(bands_only))
	var post_recipe: Dictionary = _snapshot()
	_check("柱参数进入快照", bool(_dictionary(_dictionary(post_recipe.get("architecture", {})).get("pilaster", {})).get("enabled", false)) and is_equal_approx(float(_dictionary(_dictionary(post_recipe.get("architecture", {})).get("pilaster", {})).get("width", 0.0)), 0.36), post_status)

	# 2) 再开腰线：腰线出现，且必须比柱更靠墙（柱更凸）。
	_set_check("band_enabled", true)
	_set_spin("band_projection", 0.30)
	_set_spin("band_thickness", 0.34)
	_check_result("开腰线应用", _result_button("frame_apply"))
	var both_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	var band_count: int = _count_prefix(both_visual, "band_")
	_check("开腰线后腰线件出现", band_count > 0, str(band_count))
	var depth_half: float = float(_snapshot().get("depth", 9.0)) * 0.5
	var band_front: float = _front_most(both_visual, "band_", depth_half)
	var post_front: float = _front_most(both_visual, "pilaster_", depth_half)
	_check("腰线与柱都伸到正面之外", band_front < INF and post_front < INF, "band=%f post=%f" % [band_front, post_front])
	_check("柱比腰线更凸（腰线收在柱后）", post_front < band_front, "post=%f band=%f" % [post_front, band_front])
	# 顶层不重复腰线：件数不超过 4 边 × (层数-1)。
	_check("顶层不重复生成腰线", band_count <= 4 * (int(_snapshot().get("floors", 3)) - 1), "%d" % band_count)

	# 3) 关闭柱：柱消失、腰线保留（两开关互不连坐）。
	_set_check("pilaster_enabled", false)
	_check_result("关柱应用", _result_button("frame_apply"))
	var band_only_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	_check("关柱后柱件消失", _count_prefix(band_only_visual, "pilaster_") == 0)
	_check("关柱后腰线仍在", _count_prefix(band_only_visual, "band_") > 0)

	_check_result("构架测试后恢复原配方", _result(session, "accept_loaded", [original, _dictionary(_property(session, "catalog"))]))
	_screen.call("configure", {})
	_check_result("构架测试后恢复预览", _result(_screen, "refresh_preview"))

## 门窗/破旧必须走真实控件和按钮信号，不以patch替代待验操作。
func _test_window_weathering() -> void:
	print("[workshop-editor-stage] window weathering")
	_check("门窗风化仅在主线程", OS.get_thread_caller_id() == OS.get_main_thread_id())
	var session: Object = _property(_screen, "session") as Object
	var original: Dictionary = _snapshot().duplicate(true)
	var original_catalog: Dictionary = _dictionary(_property(session, "catalog")).duplicate(true)
	var picker: OptionButton = _property(_screen, "_page_picker") as OptionButton
	var original_page: int = picker.selected if picker != null else 0
	var baseline: Dictionary = _orthographic_recipe()
	baseline.merge({"building_id": "weathering_editor_%s" % str(Time.get_ticks_usec()), "width": 15.0, "depth": 10.0, "floors": 2, "aging": 0.0, "damage": 0.0, "vegetation_density": 0.0, "damage_seed": 11011}, true)
	baseline.architecture.window.merge({"type": "fixed", "enabled": true, "open_angle": 0.0}, true)
	_build_ids.append(str(baseline.building_id))
	if not _check_result("门窗风化独立shell基线", _result(session, "accept_loaded", [baseline, original_catalog])):
		return
	_screen.call("configure", {})
	_check_result("门窗风化基线预览", _result(_screen, "refresh_preview"))
	if picker != null:
		picker.select(1)
		picker.item_selected.emit(1)
	_set_option("window_scope", "global")
	var preview: Control = _property(_screen, "preview") as Control
	preview.call("set_view", "perspective")
	var camera: Camera3D = _property(preview, "camera") as Camera3D
	_check("门窗截图有真实相机", camera != null)
	var view: Dictionary = {"transform": camera.transform, "projection": camera.projection, "size": camera.size, "fov": camera.fov} if camera != null else {}
	var clean_recipe: Dictionary = _snapshot().duplicate(true)
	var clean: Dictionary = _weathering_inventory(_preview_root(preview))
	_verify_shell_geometry(_preview_root(preview), _snapshot(), "门窗clean")
	await _capture(Vector2i(1600, 1000), "_clean", view)

	for spec: Array in [["width", 0.9], ["height", 1.3], ["sill", 1.1]]:
		_set_spin("window_" + str(spec[0]), float(spec[1]))
		_check("global基本窗值即时同步架构：" + str(spec[0]), is_equal_approx(_spin("architecture_window_" + str(spec[0])), float(spec[1])))
	_emit_button("generate")
	_check_window_dimensions("generate基本窗提交", Vector3(0.9, 1.3, 1.1))
	_check("仅编辑window后generate不误改其他配方", _same(_window_unrelated_parameters(clean_recipe), _window_unrelated_parameters(_snapshot())))
	var edited: Dictionary = _weathering_inventory(_preview_root(preview))
	_check_window_bounds("generate真实玻璃", edited, Vector3(0.9, 1.3, 1.1))
	_check("generate确实改变实际glass bounds及hash", _weathering_hash(clean, "glass_") != _weathering_hash(edited, "glass_") and clean.bounds.get("glass_front_0_0") != edited.bounds.get("glass_front_0_0"))
	_check("generate不重置基本建筑尺寸", is_equal_approx(float(_snapshot().width), 15.0) and is_equal_approx(float(_snapshot().depth), 10.0) and int(_snapshot().floors) == 2)
	await _capture(Vector2i(1600, 1000), "_windows_edited", view)

	for button: String in ["architecture_apply", "window_apply"]:
		var before_window_apply: Dictionary = _window_unrelated_parameters(_snapshot())
		_set_spin("width", 15.5)
		var target: Vector3 = Vector3(1.1, 1.5, 1.0) if button == "architecture_apply" else Vector3(1.0, 1.4, 1.1)
		for spec: Array in [["width", target.x], ["height", target.y], ["sill", target.z]]:
			_set_spin("architecture_window_" + str(spec[0]), float(spec[1]))
			_check("global架构反向同步基本：" + str(spec[0]), is_equal_approx(_spin("window_" + str(spec[0])), float(spec[1])))
		_emit_button(button)
		_check_window_dimensions(button + " 两处快照一致", target)
		_check(button + " 只提交window参数，其他配方不变", _same(before_window_apply, _window_unrelated_parameters(_snapshot())))
		_check(button + " 保持global且不吞未提交基本宽度", _option_value("window_scope") == "global" and is_equal_approx(float(_snapshot().width), 15.0) and is_equal_approx(_spin("width"), 15.5))
		_check_window_bounds(button + " 实际玻璃", _weathering_inventory(_preview_root(preview)), target)
		_set_spin("width", 15.0)

	# local三种范围均不得串到基本全局值；测试完逐次恢复，避免局部覆盖污染后续对照。
	var global_recipe: Dictionary = _snapshot().duplicate(true)
	for scope: String in ["floor", "facade", "single"]:
		_set_option("window_scope", scope)
		for spec: Array in [["width", 0.8], ["height", 1.2], ["sill", 1.2]]:
			_set_spin("architecture_window_" + str(spec[0]), float(spec[1]))
			_check(scope + " 局部窗输入不串基本全局：" + str(spec[0]), is_equal_approx(_spin("window_" + str(spec[0])), float(global_recipe["window_" + str(spec[0])])))
		_set_spin("window_width", 1.2)
		_check(scope + " 基本输入不反串局部", is_equal_approx(_spin("architecture_window_width"), 0.8))
		_set_spin("window_width", float(global_recipe.window_width))
		_emit_button("architecture_apply")
		var local_recipe: Dictionary = _snapshot()
		_check(scope + " 局部应用成功且全局快照不变", not _same(local_recipe, global_recipe) and _same(local_recipe.architecture.window, global_recipe.architecture.window) and is_equal_approx(float(local_recipe.window_width), float(global_recipe.window_width)) and is_equal_approx(float(local_recipe.window_height), float(global_recipe.window_height)) and is_equal_approx(float(local_recipe.window_sill), float(global_recipe.window_sill)), _status_text())
		_check_result(scope + " 后恢复全局对照", _result(session, "accept_loaded", [global_recipe, original_catalog]))
		_screen.call("configure", {})
		_check_result(scope + " 后刷新对照", _result(_screen, "refresh_preview"))
	_set_option("window_scope", "global")
	var before_door: Dictionary = _weathering_inventory(_preview_root(preview))
	_set_spin("door_width", 1.3)
	_set_spin("door_height", 2.2)
	_emit_button("generate")
	var after_door: Dictionary = _weathering_inventory(_preview_root(preview))
	_check("generate门宽高进入快照", is_equal_approx(float(_snapshot().door_width), 1.3) and is_equal_approx(float(_snapshot().door_height), 2.2))
	_check("generate实际door geometry变化", _weathering_hash(before_door, "door_") != _weathering_hash(after_door, "door_"))
	var door_count: int = 0
	for id: String in after_door.bounds:
		if not id.begins_with("door_"): continue
		door_count += 1
		var box: AABB = after_door.bounds[id]
		_check("门扇真实宽高为净门尺寸减装配缝：" + id, absf(box.size.x - 1.296) < 0.0001 and absf(box.size.y - 2.196) < 0.0001)
	_check("门尺寸验收非空测", door_count == 1)

	if picker != null:
		picker.select(2)
		picker.item_selected.emit(2)
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var damage: HSlider = controls.get("damage") as HSlider
	var damage_label: bool = false
	if damage != null:
		for sibling: Node in damage.get_parent().get_children():
			if sibling is Label and (sibling as Label).text.contains("门窗破损"): damage_label = true
	_check("damage文案为门窗破损", damage_label)
	_check("damage_apply真实按钮存在", _dictionary(_property(_screen, "buttons")).has("damage_apply"))
	var uv_hashes: Dictionary = {}
	var patch_hashes: Dictionary = {}
	for amount: float in [0.0, 0.2, 0.5, 0.9]:
		_set_spin("aging", amount)
		_set_text("display_name", "门窗风化验收 aging=" + str(amount))
		_emit_button("damage_apply")
		_check("damage_apply按apply_parameters语义提交基础字段", str(_snapshot().display_name) == "门窗风化验收 aging=" + str(amount) and is_equal_approx(float(_snapshot().aging), amount) and (_screen.call("_pending_local_fields") as Array).is_empty(), _status_text())
		_check("aging按钮提交快照：" + str(amount), is_equal_approx(float(_snapshot().aging), amount), _status_text())
		var aged: Dictionary = _weathering_inventory(_preview_root(preview))
		var uv_hash: String = _weathering_hash(aged, "wall_shell_", "uv_hash")
		_check("aging四档真实meshUV hash互异：" + str(amount), not uv_hashes.has(uv_hash))
		uv_hashes[uv_hash] = true
		_check_weathering_geometry("aging=" + str(amount), aged, amount > 0.0, 8)
		_verify_shell_geometry(_preview_root(preview), _snapshot(), "aging=" + str(amount))
		_check_weathering_preserved("aging=" + str(amount), after_door, aged, false)
		if amount > 0.0:
			var patch_hash: String = _weathering_hash(aged, "wall_weathering_")
			_check("斑驳可见面随aging变化：" + str(amount), not patch_hashes.has(patch_hash))
			patch_hashes[patch_hash] = true
		else:
			_check("aging零值mesh数量和完整hash不变", _same(after_door.hashes, aged.hashes))
		_shared_material_usage(_preview_root(preview))
		await _capture(Vector2i(1600, 1000), "_weathered_%02d" % roundi(amount * 100.0), view)
		if amount == 0.9: await _capture(Vector2i(1600, 1000), "_weathered", view)
	_set_spin("aging", 0.0)
	_emit_button("damage_apply")
	var undamaged: Dictionary = _weathering_inventory(_preview_root(preview))
	var previous_glass: String = _weathering_hash(undamaged, "glass_")
	for amount: float in [0.0, 0.4, 0.9]:
		_set_spin("damage", amount)
		_emit_button("damage_apply")
		_check("damage_apply提交快照：" + str(amount), is_equal_approx(float(_snapshot().damage), amount), _status_text())
		var damaged: Dictionary = _weathering_inventory(_preview_root(preview))
		var glass_hash: String = _weathering_hash(damaged, "glass_")
		_check_weathering_preserved("damage=" + str(amount), undamaged, damaged, true)
		_verify_shell_geometry(_preview_root(preview), _snapshot(), "damage=" + str(amount))
		if amount > 0.0:
			_check("damage实际glass faces/hash和木门变化：" + str(amount), glass_hash != previous_glass and undamaged.faces.get("glass_front_0_0") != damaged.faces.get("glass_front_0_0") and _weathering_hash(undamaged, "door_") != _weathering_hash(damaged, "door_"))
		else:
			_check("damage零值严格保持完整mesh", _same(undamaged.hashes, damaged.hashes))
		previous_glass = glass_hash
		_shared_material_usage(_preview_root(preview))
		_check_result("同damage_seed真实重新生成", _result(_screen, "refresh_preview"))
		var repeated: Dictionary = _weathering_inventory(_preview_root(preview))
		_check("damage_seed确定性：" + str(amount), damaged.hashes == repeated.hashes and damaged.collisions == repeated.collisions)
		if amount > 0.0: await _capture(Vector2i(1600, 1000), "_damaged_%02d" % roundi(amount * 100.0), view)
	await _capture(Vector2i(1600, 1000), "_damaged", view)
	var seed_before: Dictionary = _weathering_inventory(_preview_root(preview))
	_set_spin("damage_seed", 11012)
	_emit_button("damage_apply")
	var seed_after: Dictionary = _weathering_inventory(_preview_root(preview))
	_check("换damage_seed真实玻璃hash改变", _weathering_hash(seed_before, "glass_") != _weathering_hash(seed_after, "glass_"))
	_check_weathering_preserved("换damage_seed", seed_before, seed_after, true)
	_set_spin("aging", 0.9)
	_emit_button("damage_apply")
	var saved: Dictionary = _result(_screen, "save_building")
	if _check_result("风化破损真实保存", saved):
		_verify_bundle(saved, "weathered_damaged")
		var saved_geometry: Dictionary = _weathering_inventory(_preview_root(preview))
		var saved_recipe: Dictionary = _snapshot().duplicate(true)
		_check_result("保存后改回干净对照", _result(session, "accept_loaded", [baseline, original_catalog]))
		_screen.call("configure", {})
		var reopened: Dictionary = _result(_screen, "open_recipe", [str(saved.get("recipe_path", ""))])
		_check_result("风化破损真实打开已存配方", reopened)
		var reloaded: Dictionary = _weathering_inventory(_preview_root(preview))
		_check("重载aging/damage/seed与完整门窗快照保持", _same(saved_recipe, _snapshot()))
		_check("保存重载实际UV/斑驳/缺口/碰撞仍生效", _same(saved_geometry.hashes, reloaded.hashes) and _same(saved_geometry.collisions, reloaded.collisions))
		_check_weathering_geometry("保存重载风化", reloaded, true, 8)
	_check_shared_materials_unchanged("门窗风化UI结束")
	_check_result("门窗风化后恢复original文档", _result(session, "accept_loaded", [original, original_catalog]))
	_screen.call("configure", {})
	_check_result("门窗风化后恢复original预览", _result(_screen, "refresh_preview"))
	if picker != null:
		picker.select(original_page)
		picker.item_selected.emit(original_page)
	_check("门窗风化不污染原文档与catalog", _same(original, _snapshot()) and _same(original_catalog, _property(session, "catalog")))

func _window_unrelated_parameters(recipe: Dictionary) -> Dictionary:
	var result: Dictionary = recipe.duplicate(true)
	for key: String in ["window_width", "window_height", "window_sill"]: result.erase(key)
	var architecture: Dictionary = _dictionary(result.get("architecture", {}))
	architecture.erase("window")
	return result

func _check_window_dimensions(label: String, expected: Vector3) -> void:
	var recipe: Dictionary = _snapshot()
	var window: Dictionary = _dictionary(_dictionary(recipe.get("architecture", {})).get("window", {}))
	for spec: Array in [["width", expected.x], ["height", expected.y], ["sill", expected.z]]:
		var field: String = str(spec[0])
		_check(label + " " + field, is_equal_approx(float(recipe.get("window_" + field, -1.0)), float(spec[1])) and is_equal_approx(float(window.get(field, -1.0)), float(spec[1])) and is_equal_approx(_spin("window_" + field), float(spec[1])) and is_equal_approx(_spin("architecture_window_" + field), float(spec[1])), _status_text())

func _check_window_bounds(label: String, inventory: Dictionary, expected: Vector3) -> void:
	var count: int = 0
	for id: String in inventory.bounds:
		if not id.begins_with("glass_front_0_"): continue
		count += 1
		var box: AABB = inventory.bounds[id]
		_check(label + " 实际净尺寸减两侧2mm间隙：" + id, absf(box.size.x - (expected.x - 0.004)) < 0.0001 and absf(box.size.y - (expected.y - 0.004)) < 0.0001 and absf(box.position.y - (expected.z + 0.002)) < 0.0001, str(box))
	_check(label + " 真实正立面首层玻璃非空", count > 0)

func _weathering_inventory(root: Node3D) -> Dictionary:
	var result: Dictionary = {"hashes": {}, "uv_hash": {}, "faces": {}, "bounds": {}, "visible": {}, "collisions": {}, "invalid_collisions": 0}
	if root == null: return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var id: String = str(node.get_meta("slot_id", str(node.name)))
		var transform: Transform3D = _relative_transform(node, root)
		if node is MeshInstance3D:
			var instance: MeshInstance3D = node as MeshInstance3D
			if instance.mesh != null:
				var arrays: Array = []
				var uvs: Array = []
				for surface: int in instance.mesh.get_surface_count():
					var data: Array = instance.mesh.surface_get_arrays(surface)
					arrays.append(data)
					uvs.append(data[Mesh.ARRAY_TEX_UV])
				result.hashes[id] = var_to_bytes([transform, arrays]).hex_encode().sha256_text()
				result.uv_hash[id] = var_to_bytes(uvs).hex_encode().sha256_text()
				var faces: PackedVector3Array = instance.mesh.get_faces()
				for index: int in faces.size(): faces[index] = transform * faces[index]
				result.faces[id] = faces
				result.bounds[id] = transform * instance.mesh.get_aabb()
				result.visible[id] = instance.visible
		if node is CollisionShape3D:
			var collision: CollisionShape3D = node as CollisionShape3D
			if collision.disabled or not collision.shape is ConcavePolygonShape3D:
				result.invalid_collisions += 1
			else:
				var faces: PackedVector3Array = (collision.shape as ConcavePolygonShape3D).get_faces()
				for index: int in faces.size(): faces[index] = transform * faces[index]
				result.collisions[id] = faces
		for child: Node in node.get_children(): stack.append(child)
	return result

func _weathering_hash(inventory: Dictionary, prefix: String, field: String = "hashes") -> String:
	var entries: Array[String] = []
	for id: String in inventory[field]:
		if id.begins_with(prefix): entries.append(id + ":" + str(inventory[field][id]))
	entries.sort()
	return "|".join(entries).sha256_text()

func _check_weathering_preserved(label: String, before: Dictionary, after: Dictionary, damage: bool) -> void:
	var unchanged: bool = true
	if damage:
		_check(label + " 不随机删除整扇门窗或增加替代盒", before.faces.size() == after.faces.size())
	for id: String in before.faces:
		if damage and (id.begins_with("glass_") or id.begins_with("door_")):
			_check(label + " 每件填充保留真实mesh：" + id, after.faces.has(id) and not (after.faces[id] as PackedVector3Array).is_empty())
			continue
		unchanged = unchanged and after.faces.has(id) and before.faces[id] == after.faces.get(id)
	for id: String in after.faces:
		unchanged = unchanged and (before.faces.has(id) or id.begins_with("wall_weathering_"))
	_check(label + " 墙/门洞/楼板/屋顶及非目标原件实际面不变", unchanged)
	_check(label + " 全部结构碰撞三角面不变", before.collisions == after.collisions and int(after.invalid_collisions) == 0)
	var matches: bool = not after.collisions.is_empty()
	for id: String in after.collisions:
		matches = matches and (id.begins_with("wall_shell_") or id.begins_with("slab_") or id.begins_with("roof_") or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_")) and after.faces.has(id) and after.collisions[id] == after.faces.get(id)
	_check(label + " 仅结构有碰撞且与视觉真实面一致", matches)

func _check_weathering_geometry(label: String, inventory: Dictionary, enabled: bool, maximum: int) -> void:
	var count: int = 0
	for id: String in inventory.faces:
		if not id.begins_with("wall_weathering_"): continue
		count += 1
		var address: PackedStringArray = id.trim_prefix("wall_weathering_").split("_")
		var valid_address: bool = address.size() == 2 and address[0].is_valid_int() and address[1].is_valid_int()
		if valid_address: valid_address = int(address[0]) >= 0 and int(address[0]) < int(maximum / 4) and int(address[1]) >= 0 and int(address[1]) < 4
		_check(label + " 斑驳唯一floor/run地址：" + id, valid_address)
		var audit: Dictionary = _audit_shell_faces(inventory.faces[id])
		_check(label + " 真实可见斑驳闭合/定向/单连通且无碰撞：" + id, bool(inventory.visible.get(id, false)) and bool(audit.closed) and bool(audit.oriented) and int(audit.connected_components) == 1 and not inventory.collisions.has(id), str(audit))
	_check(label + " 每floor/run至多一片，零值不增加mesh", (count > 0 and count <= maximum) if enabled else count == 0, str(count))

func _count_prefix(visual: Node3D, prefix: String) -> int:
	if visual == null:
		return 0
	var total: int = 0
	for node: Node in visual.get_children():
		if str(node.name).begins_with(prefix):
			total += 1
	return total

## 某前缀构件在正面(-Z)最靠外的 z。mesh 顶点是局部的，必须加节点 position。
func _front_most(visual: Node3D, prefix: String, depth_half: float) -> float:
	if visual == null:
		return INF
	var extreme: float = INF
	for node: Node in visual.get_children():
		if not str(node.name).begins_with(prefix):
			continue
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var low: float = INF
		for point in mesh_node.mesh.get_faces():
			low = minf(low, point.z)
		low += mesh_node.position.z
		# 只认伸到正面墙皮之外的件
		if low > -(depth_half + 0.02):
			continue
		extreme = minf(extreme, low)
	return extreme

## 形体变形：区间+seed→落值→几何。控件、落值、拒绝与taper归属都要真实走一遍。
func _test_form_controls() -> void:
	print("[workshop-editor-stage] form controls")
	var session: Object = _property(_screen, "session") as Object
	if session == null:
		_check("形体测试有session", false)
		return
	var keys: Array[String] = ["form_enabled", "form_preset", "form_seed", "form_max_tilt", "form_opening_sign"]
	for category: String in ["structure", "opening", "accessory"]:
		keys.append("form_" + category + "_min")
		keys.append("form_" + category + "_max")
	for key: String in keys:
		_check("形体控件存在：" + key, _dictionary(_property(_screen, "controls")).has(key))
	_check("形体按钮存在", _dictionary(_property(_screen, "buttons")).has("form_apply") and _dictionary(_property(_screen, "buttons")).has("form_reroll"))
	# 先存原文档再换基线：恢复时必须回到原building_id，否则后续保存会落到另一个楼名下。
	var original_document: Dictionary = _snapshot().duplicate(true)
	if not _check_result("形体测试前恢复正交基线", _result(session, "accept_loaded", [_orthographic_recipe(), _dictionary(_property(session, "catalog"))])):
		return
	_screen.call("configure", {})
	_check_result("形体测试前刷新预览", _result(_screen, "refresh_preview"))
	var taper_slider: HSlider = _dictionary(_property(_screen, "controls")).get("taper") as HSlider
	_check("形体关闭时taper可手调", taper_slider != null and taper_slider.editable)
	var glass_span_baseline: Vector2 = Vector2.ZERO

	# 开形体 + 设区间：落值必须落在区间内，且 taper 交回形体。
	var before: Dictionary = _snapshot()
	_set_check("form_enabled", true)
	_set_option("form_preset", "SF-B")
	_set_spin("form_seed", 11010)
	_set_spin("form_max_tilt", 8.0)
	_set_option("form_opening_sign", "positive")
	_set_spin("form_structure_min", 0.030)
	_set_spin("form_structure_max", 0.060)
	_set_spin("form_opening_min", 0.020)
	_set_spin("form_opening_max", 0.045)
	_set_spin("form_accessory_min", 0.040)
	_set_spin("form_accessory_max", 0.090)
	_check_result("形体应用", _result_button("form_apply"))
	var after: Dictionary = _snapshot()
	var form: Dictionary = _dictionary(_dictionary(after.get("architecture", {})).get("form", {}))
	_check("形体开关与种子进入快照", bool(form.get("enabled", false)) and int(form.get("seed", -1)) == 11010 and str(form.get("preset", "")) == "SF-B")
	_check("形体区间进入快照", is_equal_approx(float(_dictionary(form.get("structure", {})).get("max", 0.0)), 0.060) and is_equal_approx(float(_dictionary(form.get("opening", {})).get("max", 0.0)), 0.045) and is_equal_approx(float(_dictionary(form.get("accessory", {})).get("max", 0.0)), 0.090))
	_check("墙倾角上限进入快照", is_equal_approx(float(form.get("max_tilt_deg", 0.0)), 8.0), str(form.get("max_tilt_deg")))
	_check("窗洞取号进入快照", str(_dictionary(form.get("opening", {})).get("sign", "")) == "positive", str(_dictionary(form.get("opening", {})).get("sign")))
	_check("形体不改其它架构字段", _same(_dictionary(_dictionary(before.get("architecture", {})).get("roof", {})), _dictionary(_dictionary(after.get("architecture", {})).get("roof", {}))))
	var resolved: Dictionary = Config.resolve_form(after)
	var structure_value: float = float(resolved.get("structure", 0.0))
	_check("整楼落值在区间内", structure_value >= 0.030 - 0.000001 and structure_value <= 0.060 + 0.000001, str(structure_value))
	_check("整楼落值写入taper", is_equal_approx(float(after.get("taper", 0.0)), structure_value), "%f vs %f" % [float(after.get("taper", 0.0)), structure_value])
	_check("形体开启后taper输入被接管", taper_slider != null and not taper_slider.editable)
	var applied_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	var window_slot: String = ""
	var openings: Dictionary = _dictionary(_property(_screen, "_opening_cache"))
	for raw_id: Variant in openings.keys():
		if str(_dictionary(openings[raw_id]).get("type", "")) == "window":
			window_slot = str(raw_id).trim_prefix("opening_")
			break
	_check("形体测试可用窗洞口", not window_slot.is_empty(), str(openings.keys()))
	if not window_slot.is_empty():
		var glass: MeshInstance3D = applied_visual.get_node_or_null("glass_" + window_slot) as MeshInstance3D
		_check("形体开启后窗玻璃实际生成", glass != null and glass.mesh != null)
		if glass != null:
			var span: Vector2 = _top_bottom_span(glass.mesh.get_faces())
			glass_span_baseline = span
			_check("形体开启后窗玻璃上口真窄于下口", span.y < span.x - 0.001, "bottom=%f top=%f" % [span.x, span.y])

	# 换种子必须换落值，且仍落在同一区间。
	var rerolled: Dictionary = _result_button("form_reroll")
	_check_result("换种子应用", rerolled)
	var after_reroll: Dictionary = _snapshot()
	var reroll_seed: int = int(_dictionary(_dictionary(after_reroll.get("architecture", {})).get("form", {})).get("seed", -1))
	var reroll_value: float = float(Config.resolve_form(after_reroll).get("structure", 0.0))
	_check("换种子递增且改变落值", reroll_seed == 11011 and not is_equal_approx(reroll_value, structure_value), "seed=%d value=%f vs %f" % [reroll_seed, reroll_value, structure_value])

	# 倾角可调：同一幅度(0.10)在4°下被拒绝、在8°下被接受——这就是"幅度可以调大"的机械证明。
	var before_reject: Dictionary = _snapshot()
	_set_spin("form_max_tilt", 4.0)
	_set_spin("form_structure_max", 0.10)
	_result_button("form_apply")
	var reject_status: String = str(_property(_screen, "status_label").text) if _property(_screen, "status_label") is Label else ""
	var rejected_form: Dictionary = _dictionary(_dictionary(_snapshot().get("architecture", {})).get("form", {}))
	# 拒绝 = 输入还在控件上(0.10)、已应用值仍是0.060、快照未被写脏。
	_check("4°下超出倾角被拒绝", is_equal_approx(_spin("form_structure_max"), 0.10) and is_equal_approx(float(_dictionary(rejected_form.get("structure", {})).get("max", 0.0)), 0.060), "输入保留%.3f 已应用上限%.3f 状态：%s" % [_spin("form_structure_max"), float(_dictionary(rejected_form.get("structure", {})).get("max", 0.0)), reject_status])
	_check("拒绝原因给出可用上限", reject_status.contains("上限"), reject_status)
	_check("拒绝后配方未改变", _same(before_reject, _snapshot()))
	# 抬到 8° 后同一幅度必须通过：证明"调大倾角上限 = 拿到更大收分"。
	_set_spin("form_max_tilt", 8.0)
	_check_result("8°下同一幅度被接受", _result_button("form_apply"))
	var wide_accepted: Dictionary = _snapshot()
	var wide_form: Dictionary = _dictionary(_dictionary(wide_accepted.get("architecture", {})).get("form", {}))
	_check("8°下幅度已写入0.10", is_equal_approx(float(_dictionary(wide_form.get("structure", {})).get("max", 0.0)), 0.10) and is_equal_approx(float(wide_form.get("max_tilt_deg", 0.0)), 8.0), str(wide_form.get("structure")))
	var wide_value: float = float(Config.resolve_form(wide_accepted).get("structure", 0.0))
	_check("更大幅度得到更大收分", wide_value > structure_value + 0.01, "%.4f vs %.4f" % [wide_value, structure_value])
	var wide_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	if wide_visual != null and not window_slot.is_empty():
		var wide_glass: MeshInstance3D = wide_visual.get_node_or_null("glass_" + window_slot) as MeshInstance3D
		if wide_glass != null and glass_span_baseline != Vector2.ZERO:
			var span_now: Vector2 = _top_bottom_span(wide_glass.mesh.get_faces())
			_check("整楼收分加大后墙实际更斜", span_now.y < glass_span_baseline.y - 0.001, "%.4f vs %.4f" % [span_now.y, glass_span_baseline.y])
	_set_spin("form_structure_max", 0.060)

	# 窗洞取号：mixed 必须真的让同一立面出现"有的上宽、有的上窄"。
	_set_option("form_opening_sign", "mixed")
	_check_result("混合取号应用", _result_button("form_apply"))
	var mixed_recipe: Dictionary = _snapshot()
	var narrow_count: int = 0
	var wide_count: int = 0
	for facade in ["front", "back", "left", "right"]:
		for ordinal in 8:
			var rho: float = Config.opening_rho(mixed_recipe, str(facade) + "_" + str(ordinal))
			if rho > 0.00001: narrow_count += 1
			elif rho < -0.00001: wide_count += 1
	_check("混合取号同时存在上窄与上宽", narrow_count > 0 and wide_count > 0, "上窄%d列 上宽%d列" % [narrow_count, wide_count])
	var mixed_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	var mixed_up_narrow: int = 0
	var mixed_up_wide: int = 0
	if mixed_visual != null:
		for node: Node in mixed_visual.get_children():
			if not str(node.name).begins_with("glass_"):
				continue
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			var s_span: Vector2 = _top_bottom_span(mesh_node.mesh.get_faces())
			if s_span.y < s_span.x - 0.0005:
				mixed_up_narrow += 1
			elif s_span.y > s_span.x + 0.0005:
				mixed_up_wide += 1
	_check("混合取号在真实玻璃上同时出现两个方向", mixed_up_narrow > 0 and mixed_up_wide > 0, "上窄%d片 上宽%d片" % [mixed_up_narrow, mixed_up_wide])
	# 同列上下必须同向：mixed 是"按列取号"，不是逐片掷骰子，否则立面读成噪点。
	var column_consistent: bool = true
	var column_checked: int = 0
	var column_seen: Dictionary = {}
	if mixed_visual != null:
		var library: Dictionary = _dictionary(_property(_screen, "_opening_cache"))
		for raw_id: Variant in library.keys():
			var slot_name: String = str(raw_id).trim_prefix("opening_")
			var parts: PackedStringArray = slot_name.split("_")
			if parts.size() < 3:
				continue
			var column_key: String = str(parts[0]) + "_" + str(parts[2])
			var mesh_node: MeshInstance3D = mixed_visual.get_node_or_null("glass_" + slot_name) as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			var s_span: Vector2 = _top_bottom_span(mesh_node.mesh.get_faces())
			var direction: int = 1 if s_span.y < s_span.x - 0.0005 else (-1 if s_span.y > s_span.x + 0.0005 else 0)
			if direction == 0:
				continue
			if column_seen.has(column_key):
				column_checked += 1
				if int(column_seen[column_key]) != direction:
					column_consistent = false
			else:
				column_seen[column_key] = direction
	_check("混合取号同列上下同向", column_consistent and column_checked > 0, "核对%d对" % column_checked)

	# 统一上宽下窄也必须贯穿到几何：整栋窗全部反过来。
	_set_option("form_opening_sign", "negative")
	_check_result("统一上宽应用", _result_button("form_apply"))
	var negative_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	var negative_up_wide: int = 0
	var negative_up_narrow: int = 0
	if negative_visual != null:
		for node: Node in negative_visual.get_children():
			if not str(node.name).begins_with("glass_"):
				continue
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			var s_span: Vector2 = _top_bottom_span(mesh_node.mesh.get_faces())
			if s_span.y > s_span.x + 0.0005:
				negative_up_wide += 1
			elif s_span.y < s_span.x - 0.0005:
				negative_up_narrow += 1
	_check("统一上宽时无一片上窄", negative_up_wide > 0 and negative_up_narrow == 0, "上宽%d 上窄%d" % [negative_up_wide, negative_up_narrow])
	_set_option("form_opening_sign", "positive")
	_check_result("恢复统一上窄", _result_button("form_apply"))

	# 关形体回到正交：玻璃上下等宽，taper 交回手改。
	_set_check("form_enabled", false)
	_check_result("关闭形体应用", _result_button("form_apply"))
	# 关形体只移交taper，不会自动归零；正交对照必须显式把taper也设为0。
	_set_spin("taper", 0.0)
	_check_result("关闭形体后taper归零", _result_button("apply"))
	var closed_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
	var closed_recipe: Dictionary = _snapshot()
	_check("关闭形体后form.enabled为false", not bool(_dictionary(_dictionary(closed_recipe.get("architecture", {})).get("form", {})).get("enabled", true)))
	_check("关闭形体后taper恢复可手改", taper_slider != null and taper_slider.editable)
	if not window_slot.is_empty():
		var flat_glass: MeshInstance3D = closed_visual.get_node_or_null("glass_" + window_slot) as MeshInstance3D
		_check("关闭形体后窗玻璃存在", flat_glass != null and flat_glass.mesh != null)
		if flat_glass != null:
			var flat_span: Vector2 = _top_bottom_span(flat_glass.mesh.get_faces())
			_check("关闭形体后窗玻璃回正交矩形", absf(flat_span.y - flat_span.x) < 0.002, "bottom=%f top=%f" % [flat_span.x, flat_span.y])
	_check_result("形体验证后恢复原配方", _result(session, "accept_loaded", [original_document, _dictionary(_property(session, "catalog"))]))
	_screen.call("configure", {})
	_check_result("形体验证后恢复预览", _result(_screen, "refresh_preview"))

## 正交基线：形体关闭、taper=0，用于对照"开了形体"的几何差异。
func _orthographic_recipe() -> Dictionary:
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe["building_id"] = "form_editor_baseline_%s" % str(Time.get_ticks_usec())
	recipe["taper"] = 0.0
	recipe["architecture"]["form"]["enabled"] = false
	recipe["floor_overrides"] = {}
	recipe["facade_overrides"] = {}
	recipe["slot_overrides"] = {}
	recipe["excluded_slots"] = []
	recipe["locked_vegetation"] = []
	return recipe

## 与_test_form同口径：最上/最下4mm切片内的x向宽度。
func _top_bottom_span(faces: PackedVector3Array) -> Vector2:
	if faces.is_empty(): return Vector2.ZERO
	var low: float = faces[0].y
	var high: float = faces[0].y
	for point in faces:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var bottom_lo: float = INF
	var bottom_hi: float = -INF
	var top_lo: float = INF
	var top_hi: float = -INF
	for point in faces:
		if point.y < low + 0.004:
			bottom_lo = minf(bottom_lo, point.x)
			bottom_hi = maxf(bottom_hi, point.x)
		if point.y > high - 0.004:
			top_lo = minf(top_lo, point.x)
			top_hi = maxf(top_hi, point.x)
	return Vector2(bottom_hi - bottom_lo, top_hi - top_lo)

func _test_architecture_controls() -> void:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var original: Dictionary = _snapshot()
	var buttons: Dictionary = _dictionary(_property(_screen, "buttons"))
	for key: String in ["architecture_shape_variant", "wing_x", "wing_z", "setback_start", "setback_step", "window_scope", "window_selection", "architecture_window_enabled", "architecture_window_type", "architecture_window_open_angle", "architecture_window_frame_width", "architecture_window_frame_depth", "architecture_window_glass_thickness", "architecture_window_recess", "architecture_window_width", "architecture_window_height", "architecture_window_sill", "architecture_window_sill_enabled", "architecture_window_sill_projection", "architecture_window_sill_thickness", "architecture_window_sill_extension", "architecture_roof_mode", "architecture_roof_height", "architecture_roof_thickness", "architecture_roof_cap_thickness", "architecture_roof_cap_overhang", "architecture_roof_post_spacing", "architecture_roof_rail_spacing", "architecture_roof_bar_width", "architecture_roof_edge_index", "architecture_roof_edge_override_enabled", "architecture_roof_edge_mode", "architecture_roof_gap_center", "architecture_roof_gap_width"]:
		_check("架构控件存在：" + key, controls.has(key))
	_check("架构应用按钮存在", buttons.has("architecture_apply") and buttons.has("roof_apply") and buttons.has("window_apply"))
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe["building_id"] = "architecture_variant_%s" % str(Time.get_ticks_usec())
	recipe["shape"] = "u"
	# 15x12 + 0.35退台会把顶层短臂压到2.45m，刚好放不下1.5m净窗；取样改用16x13，仍是U形+退台+混合屋顶。
	recipe["width"] = 16.0
	recipe["depth"] = 13.0
	recipe["floors"] = 3
	var architecture: Dictionary = _dictionary(recipe.get("architecture", {})).duplicate(true)
	var plan: Dictionary = _dictionary(architecture.get("plan", {})).duplicate(true)
	plan["wing_x"] = 0.42
	plan["wing_z"] = 0.58
	plan["setback_start"] = 2
	plan["setback_step"] = 0.35
	architecture["plan"] = plan
	var window: Dictionary = _dictionary(architecture.get("window", {})).duplicate(true)
	window["type"] = "casement_left"
	window["open_angle"] = 35.0
	window["sill_enabled"] = true
	window["sill_projection"] = 0.24
	architecture["window"] = window
	var roof_config: Dictionary = _dictionary(architecture.get("roof", {})).duplicate(true)
	roof_config["mode"] = "mixed"
	architecture["roof"] = roof_config
	recipe["architecture"] = architecture
	var session: Object = _property(_screen, "session") as Object
	if not _check_result("架构变体真实载入", _result(session, "accept_loaded", [recipe, _dictionary(_property(session, "catalog"))])):
		return
	_screen.call("configure", {})
	var refreshed: Dictionary = _result(_screen, "refresh_preview")
	if not _check_result("架构变体真实生成", refreshed):
		return
	var current: Dictionary = _snapshot()
	var normalized: Dictionary = _dictionary(current.get("architecture", {}))
	_check("架构嵌套配置进入snapshot", str(_dictionary(normalized.get("window", {})).get("type", "")) == "casement_left" and bool(_dictionary(normalized.get("window", {})).get("sill_enabled", false)) and str(_dictionary(normalized.get("roof", {})).get("mode", "")) == "mixed")
	_check("非矩形屋顶边动态发现edge_6/7", _roof_edge_available("edge_6") and _roof_edge_available("edge_7"))
	_set_option("window_scope", "global")
	_set_spin("wing_x", 0.5)
	_set_spin("setback_step", 0.2)
	_set_spin("architecture_window_open_angle", 25.0)
	_set_spin("architecture_window_sill_projection", 0.22)
	_set_option("architecture_window_type", "awning")
	_check_result("全局架构窗按钮真实应用", _result_button("architecture_apply"))
	var changed: Dictionary = _snapshot()
	var changed_architecture: Dictionary = _dictionary(changed.get("architecture", {}))
	var changed_window: Dictionary = _dictionary(changed_architecture.get("window", {}))
	_check("全局窗字段写入architecture.window", float(changed_window.get("open_angle", 0.0)) == 25.0 and str(changed_window.get("type", "")) == "awning")
	_set_option("architecture_roof_mode", "parapet")
	_set_option("architecture_roof_edge_index", "edge_0")
	_set_check("architecture_roof_edge_override_enabled", true)
	_set_option("architecture_roof_edge_mode", "railing")
	_set_spin("architecture_roof_gap_center", 0.4)
	_set_spin("architecture_roof_gap_width", 1.2)
	_check_result("屋顶架构按钮真实应用", _result_button("roof_apply"))
	var roof: Dictionary = _dictionary(_dictionary(_snapshot().get("architecture", {})).get("roof", {}))
	_check("屋顶全局与边覆盖写入", str(roof.get("mode", "")) == "parapet" and _dictionary(roof.get("edge_overrides", {})).has("edge_0"))
	var preview: Control = _property(_screen, "preview") as Control
	var visual: Node3D = _preview_visual(preview)
	var has_parapet: bool = false
	var has_railing: bool = false
	var has_roofcap: bool = false
	var has_sash: bool = false
	var has_sill: bool = false
	if visual != null:
		for child: Node in visual.get_children():
			var id: String = str(child.name)
			has_parapet = has_parapet or id.begins_with("parapet_")
			has_railing = has_railing or id.begins_with("railing_")
			has_roofcap = has_roofcap or id.begins_with("roofcap_")
			has_sash = has_sash or id.begins_with("sash_")
			has_sill = has_sill or id.begins_with("sill_")
	_check("架构屋顶实际女儿墙", has_parapet)
	_check("架构屋顶实际栏杆", has_railing)
	_check("架构屋顶实际压顶", has_roofcap)
	_check("活动窗实际生成窗扇", has_sash)
	_check("窗沿板实际生成", has_sill)
	var window_option: OptionButton = controls.get("window_selection") as OptionButton
	var selected_opening: String = ""
	var other_opening: String = ""
	if window_option != null:
		for index: int in window_option.item_count:
			var opening_id: String = str(window_option.get_item_metadata(index))
			if selected_opening.is_empty():
				selected_opening = opening_id
			elif other_opening.is_empty() and opening_id != selected_opening:
				other_opening = opening_id
		if not selected_opening.is_empty():
			for index: int in window_option.item_count:
				if str(window_option.get_item_metadata(index)) == selected_opening:
					window_option.select(index)
					window_option.item_selected.emit(index)
					break
	_check("真实窗口选择可用", not selected_opening.is_empty())
	_check("真实存在第二个窗口用于隔离核对", not other_opening.is_empty())
	if not selected_opening.is_empty():
		var before_single: Dictionary = _snapshot()
		_set_option("window_scope", "single")
		_set_check("architecture_window_enabled", true)
		_set_option("architecture_window_type", "casement_right")
		_set_spin("architecture_window_open_angle", 35.0)
		_set_spin("architecture_window_frame_width", 0.14)
		_set_spin("architecture_window_frame_depth", 0.18)
		_set_spin("architecture_window_glass_thickness", 0.03)
		_set_spin("architecture_window_recess", 0.16)
		_set_spin("architecture_window_width", 1.3)
		_set_spin("architecture_window_height", 1.7)
		_set_spin("architecture_window_sill", 0.95)
		_set_check("architecture_window_sill_enabled", true)
		_set_spin("architecture_window_sill_projection", 0.25)
		_set_spin("architecture_window_sill_thickness", 0.12)
		_set_spin("architecture_window_sill_extension", 0.10)
		_check_result("单窗完整构造按当前范围应用", _result_button("architecture_apply"))
		var after_single: Dictionary = _snapshot()
		var before_architecture: Dictionary = _dictionary(before_single.get("architecture", {}))
		var after_architecture: Dictionary = _dictionary(after_single.get("architecture", {}))
		var before_overrides: Dictionary = _dictionary(before_architecture.get("window_overrides", {})).duplicate(true)
		var after_overrides: Dictionary = _dictionary(after_architecture.get("window_overrides", {})).duplicate(true)
		var applied_override: Dictionary = _dictionary(after_overrides.get(selected_opening, {}))
		before_overrides.erase(selected_opening)
		after_overrides.erase(selected_opening)
		_check("单窗只改变当前window_override", _same(before_overrides, after_overrides) and str(applied_override.get("type", "")) == "casement_right" and float(applied_override.get("open_angle", 0.0)) == 35.0 and is_equal_approx(float(applied_override.get("width", 0.0)), 1.3) and is_equal_approx(float(applied_override.get("height", 0.0)), 1.7) and is_equal_approx(float(applied_override.get("frame_depth", 0.0)), 0.18) and is_equal_approx(float(applied_override.get("sill", 0.0)), 0.95))
		var selected_before_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
		var before_faces: int = _mesh_face_count(selected_before_visual, "wall_shell_0")
		var other_frame_before: int = _mesh_face_count_by_opening(selected_before_visual, other_opening, "frame_")
		var other_glass_before: int = _mesh_face_count_by_opening(selected_before_visual, other_opening, "glass_")
		var selection_before_close: String = str(window_option.get_item_metadata(window_option.selected))
		_set_check("architecture_window_enabled", false)
		_check_result("单窗封墙按钮真实应用", _result_button("window_apply"))
		var after_close_preview: Control = _property(_screen, "preview") as Control
		var after_close_visual: Node3D = _preview_visual(after_close_preview)
		var after_close_faces: int = _mesh_face_count(after_close_visual, "wall_shell_0")
		var selection_after_close: String = str(window_option.get_item_metadata(window_option.selected))
		var other_frame_after: int = _mesh_face_count_by_opening(after_close_visual, other_opening, "frame_")
		var other_glass_after: int = _mesh_face_count_by_opening(after_close_visual, other_opening, "glass_")
		_check("关闭窗保留window_selection", selection_before_close == selected_opening and selection_after_close == selected_opening)
		_check("enabled=false 当前窗封墙且他窗不变", before_faces > 0 and after_close_faces > 0 and before_faces != after_close_faces and other_frame_before == other_frame_after and other_glass_before == other_glass_after, "wall=%d/%d other_frame=%d/%d other_glass=%d/%d" % [before_faces, after_close_faces, other_frame_before, other_frame_after, other_glass_before, other_glass_after])
		_set_check("architecture_window_enabled", true)
		_check_result("单窗重新开启按钮真实应用", _result_button("window_apply"))
		var restored_visual: Node3D = _preview_visual(_property(_screen, "preview") as Control)
		_check("enabled=true 恢复当前窗且选择不变", _mesh_face_count_by_opening(restored_visual, selected_opening, "frame_") > 0 and str(window_option.get_item_metadata(window_option.selected)) == selected_opening)
		_set_option("window_scope", "floor")
		_set_spin("architecture_window_width", 1.41)
		var pending_floor_width: float = _spin("architecture_window_width")
		_set_option("window_scope", "facade")
		_check("floor未应用输入阻止切范围", str(_option_value("window_scope")) == "floor" and is_equal_approx(_spin("architecture_window_width"), pending_floor_width))
		_check_result("floor范围真实应用", _result_button("architecture_apply"))
		_set_option("window_scope", "facade")
		_set_spin("architecture_window_width", 1.42)
		var pending_facade_width: float = _spin("architecture_window_width")
		_set_option("window_scope", "global")
		_check("facade未应用输入阻止切全局", str(_option_value("window_scope")) == "facade" and is_equal_approx(_spin("architecture_window_width"), pending_facade_width))
		_check_result("facade范围真实应用", _result_button("architecture_apply"))
		_set_option("window_scope", "global")
	var page_picker: OptionButton = _property(_screen, "_page_picker") as OptionButton
	if page_picker != null:
		page_picker.select(1)
		page_picker.item_selected.emit(1)
		await _tree.process_frame
		await _capture(Vector2i(1600, 1000), "_architecture_variant")
	var restored: Dictionary = _result(session, "accept_loaded", [original, _dictionary(_property(session, "catalog"))])
	_check_result("恢复架构验证前配方", restored)
	_screen.call("configure", {})
	_check_result("恢复架构验证前预览", _result(_screen, "refresh_preview"))

func _option_value(key: String) -> String:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var option: OptionButton = controls.get(key) as OptionButton
	if option == null or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))

func _roof_edge_available(edge_id: String) -> bool:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var option: OptionButton = controls.get("architecture_roof_edge_index") as OptionButton
	if option == null:
		return false
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == edge_id:
			return true
	return false

func _preview_root(preview: Control) -> Node3D:
	var model: Node3D = _property(preview, "_model_root") as Node3D
	return model.get_child(0) as Node3D if model != null and model.get_child_count() == 1 else null

func _preview_visual(preview: Control) -> Node3D:
	var root: Node3D = _preview_root(preview)
	return root.get_node_or_null("GeneratedVisual") as Node3D if root != null else null

func _mesh_face_count(visual: Node3D, node_name: String) -> int:
	if visual == null:
		return 0
	var mesh_node: MeshInstance3D = visual.get_node_or_null(node_name) as MeshInstance3D
	return mesh_node.mesh.get_faces().size() if mesh_node != null and mesh_node.mesh != null else 0

func _mesh_face_count_by_opening(visual: Node3D, opening_id: String, prefix: String) -> int:
	if visual == null or opening_id.is_empty():
		return 0
	var node: MeshInstance3D = visual.get_node_or_null(prefix + opening_id.trim_prefix("opening_")) as MeshInstance3D
	return node.mesh.get_faces().size() if node != null and node.mesh != null else 0

func _fresh_architecture_recipe(building_id: String, shape: String, width: float, depth: float, floors: int) -> Dictionary:
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe["building_id"] = building_id
	recipe["display_name"] = "架构验收 · " + building_id
	recipe["shape"] = shape
	recipe["width"] = width
	recipe["depth"] = depth
	recipe["floors"] = floors
	recipe["floor_overrides"] = {}
	recipe["facade_overrides"] = {}
	recipe["slot_overrides"] = {}
	recipe["excluded_slots"] = []
	recipe["locked_vegetation"] = []
	var architecture: Dictionary = _dictionary(recipe.get("architecture", {})).duplicate(true)
	architecture["floor_windows"] = {}
	architecture["facade_windows"] = {}
	architecture["window_overrides"] = {}
	var roof: Dictionary = _dictionary(architecture.get("roof", {})).duplicate(true)
	roof["edge_overrides"] = {}
	architecture["roof"] = roof
	# 架构/壳体样例用显式taper做受控基线；形体开启会把taper改成派生值，两者不能混用。
	architecture["form"]["enabled"] = false
	recipe["architecture"] = architecture
	return recipe

func _architecture_sample_audit(root: Node3D, recipe: Dictionary, key: String) -> Dictionary:
	var result: Dictionary = {"key": key, "meshes": {}, "roof_meshes": 0, "roof_collisions": 0, "inset_checked": false}
	var visual: Node3D = root.get_node_or_null("GeneratedVisual") as Node3D if root != null else null
	var spatial: Node3D = root.get_node_or_null("Spatial/Collision") as Node3D if root != null else null
	var collision_ids: Dictionary = {}
	if spatial != null:
		for raw_collision: Node in spatial.get_children():
			var collision_id: String = str(raw_collision.get_meta("slot_id", ""))
			if not collision_id.is_empty():
				collision_ids[collision_id] = true
	var roof_meshes: int = 0
	var roof_collisions: int = 0
	var all_closed: bool = true
	var all_oriented: bool = true
	if visual != null:
		for raw_node: Node in visual.get_children():
			var mesh_node: MeshInstance3D = raw_node as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			var node_id: String = str(mesh_node.name)
			var audit: Dictionary = _audit_shell_faces(mesh_node.mesh.get_faces())
			result["meshes"][node_id] = audit
			all_closed = all_closed and bool(audit.get("closed", false))
			all_oriented = all_oriented and bool(audit.get("oriented", false))
			if node_id.begins_with("parapet_") or node_id.begins_with("roofcap_") or node_id.begins_with("railing_"):
				roof_meshes += 1
				if collision_ids.has(node_id):
					roof_collisions += 1
				_check(key + " mesh闭合定向：" + node_id, bool(audit.get("closed", false)) and bool(audit.get("oriented", false)), str(audit))
	var quality: Dictionary = _dictionary(root.get_meta("quality", {}) if root != null else {})
	var edge_quality: Dictionary = _dictionary(quality.get("roof_edge_quality", {}))
	var contacts: Array = edge_quality.get("contacts", []) as Array
	# 女儿墙/压顶按centerpath_inset记录，纯栏杆按railing_edge记录；两种都不能是空数组。
	var roof_mode: String = str(_dictionary(_dictionary(recipe.get("architecture", {})).get("roof", {})).get("mode", "none"))
	var inset_checked: bool = false
	var railing_seen: bool = false
	for raw_contact: Variant in contacts:
		if str(raw_contact).contains("centerpath_inset"):
			inset_checked = true
		if str(raw_contact).begins_with("railing_"):
			railing_seen = true
	result["roof_meshes"] = roof_meshes
	result["roof_collisions"] = roof_collisions
	result["inset_checked"] = inset_checked
	_check(key + " roof cap/railing碰撞完整", roof_meshes > 0 and roof_collisions == roof_meshes, "roof_meshes=%d roof_collisions=%d" % [roof_meshes, roof_collisions])
	var contact_ok: bool = railing_seen if roof_mode == "railing" else inset_checked
	_check(key + " roof inset真实接触审计", contact_ok, str(contacts))
	_check(key + " 所有实际mesh闭合定向", all_closed and all_oriented)
	_check(key + " 允许栏杆多连通体但不允许开口", _roof_components_are_closed(result["meshes"]))
	return result

func _roof_components_are_closed(meshes: Dictionary) -> bool:
	for node_id: String in meshes:
		if not (node_id.begins_with("parapet_") or node_id.begins_with("roofcap_") or node_id.begins_with("railing_")):
			continue
		var audit: Dictionary = _dictionary(meshes[node_id])
		if not bool(audit.get("closed", false)) or not bool(audit.get("oriented", false)):
			return false
	return true

func _test_architecture_samples() -> void:
	print("[workshop-editor-stage] architecture samples")
	var session: Object = _property(_screen, "session") as Object
	var preview: Control = _property(_screen, "preview") as Control
	if not _require_methods(preview, ["capture_model_image"], "architecture.preview"):
		return
	var catalog: Dictionary = Catalog.definitions()
	var token: String = "%s_%s" % [str(int(Time.get_unix_time_from_system())), str(Time.get_ticks_usec())]
	var samples: Array[Dictionary] = []
	var rect_parapet: Dictionary = _fresh_architecture_recipe("architecture_rect_parapet_" + token, "rectangle", 12.0, 9.0, 3)
	var rect_architecture: Dictionary = _dictionary(rect_parapet.get("architecture", {})).duplicate(true)
	var rect_window: Dictionary = _dictionary(rect_architecture.get("window", {})).duplicate(true)
	rect_window["type"] = "fixed"
	rect_window["sill"] = 1.0
	rect_architecture["window"] = rect_window
	var rect_roof: Dictionary = _dictionary(rect_architecture.get("roof", {})).duplicate(true)
	rect_roof["mode"] = "parapet"
	rect_architecture["roof"] = rect_roof
	rect_parapet["architecture"] = rect_architecture
	samples.append({"key": "architecture_rect_parapet", "recipe": rect_parapet})
	var l_railing: Dictionary = _fresh_architecture_recipe("architecture_l_railing_" + token, "l", 12.0, 12.0, 2)
	var l_architecture: Dictionary = _dictionary(l_railing.get("architecture", {})).duplicate(true)
	var l_roof: Dictionary = _dictionary(l_architecture.get("roof", {})).duplicate(true)
	l_roof["mode"] = "railing"
	l_architecture["roof"] = l_roof
	l_railing["architecture"] = l_architecture
	samples.append({"key": "architecture_l_railing", "recipe": l_railing})
	var t_terrace: Dictionary = _fresh_architecture_recipe("architecture_t_terrace_" + token, "t", 18.0, 16.0, 3)
	var t_architecture: Dictionary = _dictionary(t_terrace.get("architecture", {})).duplicate(true)
	var t_plan: Dictionary = _dictionary(t_architecture.get("plan", {})).duplicate(true)
	t_plan["wing_x"] = 0.5
	t_plan["wing_z"] = 0.5
	t_plan["setback_start"] = 2
	t_plan["setback_step"] = 0.45
	t_architecture["plan"] = t_plan
	var t_window: Dictionary = _dictionary(t_architecture.get("window", {})).duplicate(true)
	t_window["type"] = "casement_right"
	t_window["open_angle"] = 35.0
	t_architecture["window"] = t_window
	var t_roof: Dictionary = _dictionary(t_architecture.get("roof", {})).duplicate(true)
	t_roof["mode"] = "parapet"
	t_architecture["roof"] = t_roof
	t_terrace["architecture"] = t_architecture
	samples.append({"key": "architecture_t_terrace", "recipe": t_terrace})
	var u_mixed: Dictionary = _fresh_architecture_recipe("architecture_u_mixed_" + token, "u", 18.0, 16.0, 3)
	var u_architecture: Dictionary = _dictionary(u_mixed.get("architecture", {})).duplicate(true)
	var u_plan: Dictionary = _dictionary(u_architecture.get("plan", {})).duplicate(true)
	u_plan["wing_x"] = 0.6
	u_plan["wing_z"] = 0.55
	u_architecture["plan"] = u_plan
	var u_window: Dictionary = _dictionary(u_architecture.get("window", {})).duplicate(true)
	u_window["type"] = "awning"
	u_window["open_angle"] = 25.0
	u_window["sill"] = 1.0
	u_architecture["window"] = u_window
	var u_roof: Dictionary = _dictionary(u_architecture.get("roof", {})).duplicate(true)
	u_roof["mode"] = "mixed"
	u_architecture["roof"] = u_roof
	u_mixed["architecture"] = u_architecture
	samples.append({"key": "architecture_u_mixed", "recipe": u_mixed})
	var window_detail: Dictionary = _fresh_architecture_recipe("architecture_window_detail_" + token, "rectangle", 12.0, 9.0, 1)
	var detail_architecture: Dictionary = _dictionary(window_detail.get("architecture", {})).duplicate(true)
	var detail_window: Dictionary = _dictionary(detail_architecture.get("window", {})).duplicate(true)
	detail_window["type"] = "casement_left"
	detail_window["open_angle"] = 45.0
	detail_architecture["window"] = detail_window
	var detail_roof: Dictionary = _dictionary(detail_architecture.get("roof", {})).duplicate(true)
	detail_roof["mode"] = "parapet"
	detail_architecture["roof"] = detail_roof
	window_detail["architecture"] = detail_architecture
	samples.append({"key": "architecture_window_detail", "recipe": window_detail})
	for sample: Dictionary in samples:
		var key: String = str(sample.get("key", ""))
		var recipe: Dictionary = _dictionary(sample.get("recipe", {}))
		var building_id: String = str(recipe.get("building_id", ""))
		_build_ids.append(building_id)
		var entry: Dictionary = {"key": key, "building_id": building_id, "recipe": recipe.duplicate(true), "save_result": {}, "artifacts": []}
		if not _check_result(key + " 真实样例载入", _result(session, "accept_loaded", [recipe, catalog])):
			_architecture_samples.append(entry)
			continue
		_screen.call("configure", {"export_root": OUTPUT_ROOT})
		var built: Dictionary = _result(_screen, "refresh_preview")
		if not _check_result(key + " 真实样例生成", built):
			_architecture_samples.append(entry)
			continue
		var current_preview: Control = _property(_screen, "preview") as Control
		var root: Node3D = _preview_root(current_preview)
		var audit: Dictionary = _architecture_sample_audit(root, recipe, key)
		entry["geometry_audit"] = audit
		var save_result: Dictionary = _result(_screen, "save_building")
		entry["save_result"] = save_result.duplicate(true)
		if _check_result(key + " 保存五件bundle", save_result):
			_verify_bundle(save_result, key)
			var artifact_start: int = _artifacts.size()
			await _capture(Vector2i(1600, 1000), "_" + key)
			var saved_preview: Control = _property(_screen, "preview") as Control
			await _capture_shell_model(saved_preview, key)
			var sample_artifacts: Array[String] = []
			for artifact_index: int in range(artifact_start, _artifacts.size()):
				sample_artifacts.append(_artifacts[artifact_index])
			entry["artifacts"] = sample_artifacts
		_architecture_samples.append(entry)

func _set_option(key: String, value: String) -> bool:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var option: OptionButton = controls.get(key) as OptionButton
	if not _check("实际 OptionButton：" + key, option != null):
		return false
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			option.item_selected.emit(index)
			return true
	return _check("OptionButton 接收值：" + key, false, value)

func _test_preview() -> void:
	_check_result("真实预览生成", _result(_screen, "refresh_preview"))
	var preview: Control = _property(_screen, "preview") as Control
	if not _check("独立编辑器预览", preview != null):
		return
	var viewport: SubViewport = _property(preview, "viewport") as SubViewport
	_check("预览 own_world_3d", viewport != null and viewport.own_world_3d and viewport.find_world_3d() != _tree.root.find_world_3d())
	var model: Node3D = _property(preview, "_model_root") as Node3D
	_check("真实模型几何存在", model != null and not model.find_children("*", "MeshInstance3D", true, false).is_empty())
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	for pair: Array in [["wireframe", "_wireframe_root"], ["collision_overlay", "_collision_root"]]:
		var toggle: CheckButton = controls.get(str(pair[0])) as CheckButton
		if not _check("实际覆盖开关：" + str(pair[0]), toggle != null):
			continue
		toggle.button_pressed = true
		var overlay: Node3D = _property(preview, str(pair[1])) as Node3D
		_check("实际覆盖几何：" + str(pair[0]), overlay != null and overlay.get_child_count() > 0)
		toggle.button_pressed = false
		_check("覆盖关闭清空：" + str(pair[0]), overlay != null and overlay.get_child_count() == 0)

func _test_components(session: Object) -> void:
	if not _require_methods(_adapter, ["export_slot", "apply_prefab"], "plugin.adapter"):
		_check("成功替件路径", false, "适配器缺失，不能仅凭拒绝路径宣告通过")
		return
	# prefab替件契约只关心"模块包络是否等于nominal"，与形体无关。
	# 沿用当前文档的 building_id 与其它字段，只把形体关掉、taper 固定，避免整楼收分落值把包络算歪；
	# 换 building_id 会让后续保存落到另一个楼名下，破坏"同建筑连续 revision"。
	var baseline: Dictionary = _snapshot().duplicate(true)
	baseline["taper"] = 0.02
	if baseline.get("architecture") is Dictionary:
		baseline["architecture"]["form"]["enabled"] = false
	if not _check_result("替件测试载入确定性基线", _result(session, "accept_loaded", [baseline, _dictionary(_property(session, "catalog"))])):
		return
	_screen.call("configure", {})
	_check_result("替件测试生成基线模型", _result(_screen, "refresh_preview"))
	var preview: Object = _property(_screen, "preview") as Object
	var slots: Array = _property(preview, "_slots") as Array
	var wall: Dictionary = {}
	var differently_sized: bool = false
	for raw: Variant in slots:
		var slot: Dictionary = _dictionary(raw)
		if str(slot.get("kind", "")) == "wall":
			if wall.is_empty():
				wall = slot
			elif slot.get("component_id") == wall.get("component_id") and not _near_array(slot.get("size", []), wall.get("size", [])):
				differently_sized = true
	if not _check("墙组件覆盖多个不同尺寸槽", not wall.is_empty() and differently_sized):
		return
	var slot_id: String = str(wall.get("id", ""))
	var component_id: String = str(wall.get("component_id", ""))
	_screen.call("select_slot", slot_id)
	var module_button: Button = _dictionary(_property(_screen, "buttons")).get("export_module") as Button
	_check("单槽导出入口可发现且可操作", module_button != null and not module_button.disabled)
	var exported: Dictionary = _result(_screen, "export_module_component")
	if not _check_result("适配器导出真实墙 fixture", exported):
		return
	# 导出结果必须明确给出 prefab_path 或 scene_path；不猜测生成文件名。
	var path: String = str(exported.get("prefab_path", exported.get("scene_path", "")))
	if not _check("fixture 路径在隔离 scenes 下", _isolation_ok and path.begins_with(COMPONENT_ROOT + "/") and not path.contains("..") and path.ends_with(".tscn") and FileAccess.file_exists(path), str(exported)):
		_dependencies.append("adapter.export_slot 返回 prefab_path 或 scene_path")
		return
	_artifacts.append(path)
	if not str(exported.get("manifest_path", "")).is_empty():
		_artifacts.append(str(exported.manifest_path))
	var before: Dictionary = _snapshot()
	var catalog_before: Dictionary = _dictionary(_property(session, "catalog")).duplicate(true)
	var rejected: Dictionary = _result(_adapter, "apply_prefab", [session, component_id, path])
	var reason: String = str(rejected.get("reason", ""))
	# 显式拒绝可以是"尺寸/不兼容"，也可以是生成期 prefab 包络不匹配——都属接口不兼容。
	# 只要不是空原因、状态未变、且确是拒绝，契约即成立；不把断言绑在某一句文案上。
	var explicit_reason: bool = not reason.is_empty() and (reason.contains("不兼容") or reason.to_lower().contains("incompat") or reason.contains("尺寸") or reason.to_lower().begins_with("prefab"))
	_check("全局多尺寸替件明确拒绝且不改状态", not bool(rejected.get("ok", false)) and explicit_reason and _same(before, _snapshot()) and _same(catalog_before, _dictionary(_property(session, "catalog"))), str(rejected))
	if not _require_methods(_adapter, ["apply_prefab_to_slot"], "plugin.adapter"):
		_check("成功替件路径", false, "需要真实 apply_prefab_to_slot(session, slot_id, path)，验证器不直接改 catalog 伪造成功")
		return
	var applied: Dictionary = _result(_adapter, "apply_prefab_to_slot", [session, slot_id, path])
	if not _check_result("选中槽独立成功替件", applied):
		return
	var override: Dictionary = _dictionary(_dictionary(_snapshot().get("slot_overrides", {})).get(slot_id, {}))
	var clone_id: String = str(override.get("component_id", ""))
	var components: Dictionary = _dictionary(_dictionary(_property(session, "catalog")).get("components", {}))
	var clone: Dictionary = _dictionary(components.get(clone_id, {}))
	_check("成功替件创建独立 catalog ID", not clone_id.is_empty() and clone_id != component_id and str(clone.get("kind", "")) == "prefab" and str(clone.get("prefab", "")) == path)
	var before_overrides: Dictionary = _dictionary(before.get("slot_overrides", {}))
	var after_overrides: Dictionary = _dictionary(_snapshot().get("slot_overrides", {})).duplicate(true)
	after_overrides.erase(slot_id)
	before_overrides = before_overrides.duplicate(true)
	before_overrides.erase(slot_id)
	_check("替件不改变其他槽覆盖或原组件", _same(before_overrides, after_overrides) and _same(_dictionary(catalog_before.get("components", {})).get(component_id), components.get(component_id)))
	_check_result("成功替件后真实生成", _result(_screen, "refresh_preview"))
	var new_slots: Array = _property(preview, "_slots") as Array
	var selected_found: bool = false
	var unaffected: bool = true
	for raw: Variant in new_slots:
		var slot: Dictionary = _dictionary(raw)
		if str(slot.get("id", "")) == slot_id:
			selected_found = str(slot.get("component_id", "")) == clone_id and _near_array(slot.get("bounds_size", []), wall.get("bounds_size", []))
		elif str(slot.get("component_id", "")) == clone_id:
			unaffected = false
	_check("真实生成槽使用独立替件且尺寸不变", selected_found and unaffected)
	var model: Node3D = _property(preview, "_model_root") as Node3D
	var real_prefab: bool = false
	if model != null:
		for node: Node in model.find_children("*", "Node3D", true, false):
			if node.scene_file_path == path and str(node.get_meta("slot_id", "")) == slot_id:
				real_prefab = true
	_check("预览实际实例化替件 PackedScene", real_prefab, path)

func _test_recovery(other_recipe: String, session: Object) -> void:
	var saved: Dictionary = _snapshot()
	_set_spin("width", 15.5)
	_check("已保存后仅未 apply 宽度 spin 触发 dirty", not bool(session.call("is_dirty")) and bool(_screen.call("has_pending_fields")) and _same(saved, _snapshot()))
	_set_spin("floor_override_window_width", 1.3)
	var recovery: Dictionary = _result(_screen, "get_recovery")
	var guarded: Dictionary = _result(_screen, "open_recipe", [other_recipe])
	var confirm: ConfirmationDialog = _property(_screen, "_confirm") as ConfirmationDialog
	_check("未应用输入触发真实确认弹窗", bool(guarded.get("confirmation_required", false)) and confirm != null and confirm.visible)
	if confirm != null:
		# 发出真实按钮 pressed，不声称发生了鼠标点击；由新的 _cancel_discard 连接处理关闭。
		print("[workshop-editor-stage] cancelling dirty popup")
		confirm.get_cancel_button().pressed.emit()
		print("[workshop-editor-stage] popup cancelled ", confirm.visible)
		await _tree.process_frame
		print("[workshop-editor-stage] after popup frame")
		_check("取消关闭弹窗", not confirm.visible)
	_check("取消不丢基础和局部输入", _same(saved, _snapshot()) and is_equal_approx(_spin("width"), 15.5) and is_equal_approx(_spin("floor_override_window_width"), 1.3) and bool(_screen.call("has_pending_fields")))
	var action: Variant = _property(_screen, "_confirm_action")
	_check("取消清除待丢弃动作", action is Callable and not (action as Callable).is_valid())
	_set_spin("width", 14.0)
	_set_spin("floor_override_window_width", 1.1)
	var restored: Dictionary = _result(_screen, "restore_recovery", [recovery])
	_check_result("真实 recovery 恢复", restored)
	_check("恢复保留未提交输入与 session", _property(_screen, "session") == session and _same(saved, _snapshot()) and is_equal_approx(_spin("width"), 15.5) and is_equal_approx(_spin("floor_override_window_width"), 1.3) and bool(_screen.call("has_pending_fields")))

func _test_lifecycle() -> void:
	var old_screen: Control = _screen
	var preview: Object = _property(_screen, "preview") as Object
	var viewport: SubViewport = _property(preview, "viewport") as SubViewport
	var before_recovery: Dictionary = _result(_screen, "get_recovery")
	var before_snapshot: Dictionary = _snapshot()
	var lifecycle_root: Node = EditorInterface.get_edited_scene_root()
	var lifecycle_transform: Variant = _root_transform(lifecycle_root)
	var lifecycle_paused: bool = _tree.paused
	var before_session: Object = _property(_screen, "session") as Object
	var before_catalog: Dictionary = _dictionary(_property(before_session, "catalog")).duplicate(true)
	var before_pending: bool = bool(_screen.call("has_pending_fields"))
	var before_width: float = _spin("width")
	var before_floor_width: float = _spin("floor_override_window_width")
	print("[workshop-editor-stage] hide screen")
	_plugin.call("_make_visible", false)
	await _tree.process_frame
	_check("隐藏主屏停止预览更新", not _screen.visible and viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	_plugin.call("_make_visible", true)
	EditorInterface.set_main_screen_editor("老王场景工坊")
	await _tree.process_frame
	_check("恢复可见恢复预览更新", _screen.is_visible_in_tree() and viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	_check("隐藏恢复不丢草稿", _same(before_recovery, _result(_screen, "get_recovery")))
	print("[workshop-editor-stage] rebuild screen")
	var rebuilt_recovery: Dictionary = _result(_plugin, "rebuild_screen_for_verification")
	print("[workshop-editor-stage] screen recreated")
	for frame: int in range(3):
		await _tree.process_frame
	_screen = _property(_plugin, "screen") as Control
	_plugin.call("_make_visible", true)
	EditorInterface.set_main_screen_editor("老王场景工坊")
	await _tree.process_frame
	var rebuilt_session: Object = _property(_screen, "session") as Object
	var rebuilt_catalog: Dictionary = _dictionary(_property(rebuilt_session, "catalog"))
	var rebuilt_preview: Object = _property(_screen, "preview") as Object
	var rebuilt_viewport: SubViewport = _property(rebuilt_preview, "viewport") as SubViewport
	_check("插件屏幕已实际重建", _screen != null and _screen != old_screen and _screen.is_inside_tree() and not is_instance_valid(old_screen))
	_check("重建 screen recovery 返回一致", _same(before_recovery, rebuilt_recovery) and _same(before_recovery, _result(_screen, "get_recovery")))
	_check("重建恢复草稿 snapshot", _same(before_snapshot, _snapshot()))
	_check("重建恢复 catalog", _same(before_catalog, rebuilt_catalog))
	_check("重建恢复 UI dirty", bool(_screen.call("has_pending_fields")) == before_pending)
	_check("重建恢复 UI width", is_equal_approx(_spin("width"), before_width))
	_check("重建恢复 UI floor override", is_equal_approx(_spin("floor_override_window_width"), before_floor_width))
	_check("重建可见恢复预览更新", _screen.is_visible_in_tree() and rebuilt_viewport != null and rebuilt_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	_check("重建允许新 session", is_instance_valid(rebuilt_session))
	_check("重建保持 edited scene root", EditorInterface.get_edited_scene_root() == lifecycle_root and _root_transform(lifecycle_root) == lifecycle_transform)
	_check("重建保持 tree paused", _tree.paused == lifecycle_paused)
	# 这是插件屏幕生命周期重建（remove old Control + queue_free），不是完整插件卸载/重载。

func _verify_bundle(result: Dictionary, label: String) -> void:
	var directory: String = str(result.get("directory", ""))
	if not _check(label + " 输出隔离", directory.begins_with(OUTPUT_ROOT + "/") and not directory.contains(".."), directory):
		return
	var files: Array[String] = ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json"]
	for name: String in files:
		var path: String = directory.path_join(name)
		if _check(label + " 文件：" + name, FileAccess.file_exists(path)):
			_artifacts.append(path)
	var loaded: Dictionary = _result(_store, "load_recipe", [directory.path_join("building.recipe.json")])
	_check_result(label + " EditorStore 重载", loaded)
	_check(label + " 配方与 catalog 往返", _same(loaded.get("recipe"), result.get("recipe")) and _same(loaded.get("catalog"), result.get("catalog")))
	var manifest: Dictionary = _read_json(directory.path_join("candidate_manifest.json"))
	var ledger: Dictionary = _read_json(directory.path_join("ledger.json"))
	_check(label + " 编辑器来源及候选边界", str(manifest.get("authoring_context", "")) == "editor" and bool(manifest.get("noMain", false)) and manifest.get("formal_registry_written", true) == false and str(ledger.get("status", "")) == "candidate_only")
	var hashes: Dictionary = _dictionary(manifest.get("source_hashes", {}))
	for name: String in ["building.recipe.json", "catalog_snapshot.json", "building.tscn"]:
		_check(label + " SHA256：" + name, not str(hashes.get(name, "")).is_empty() and str(hashes.get(name, "")) == FileAccess.get_sha256(directory.path_join(name)))
	_check(label + " 场景总 hash", str(manifest.get("hash", "")) == FileAccess.get_sha256(directory.path_join("building.tscn")))
	var sources: Dictionary = _dictionary(manifest.get("authoring_source_hashes", {}))
	_check(label + " 创作来源 hashes 非空", not sources.is_empty())
	for source: Variant in sources:
		_check(label + " 来源 hash：" + str(source), FileAccess.file_exists(str(source)) and str(sources[source]) == FileAccess.get_sha256(str(source)))
	var packed: PackedScene = ResourceLoader.load(directory.path_join("building.tscn"), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(label + " 真实 PackedScene 重载", packed != null):
		return
	if not _check(label + " 实例化前递归确认无 Script", not _unsafe_resource(packed, {})):
		return
	var instance: Node = packed.instantiate()
	var twin: Node = packed.instantiate()
	var used_materials: Dictionary = _shared_material_usage(instance)
	_check(label + " 重载双实例共用原材质identity", used_materials == _shared_material_usage(twin) and not used_materials.is_empty())
	var scene_text: String = FileAccess.get_file_as_string(directory.path_join("building.tscn"))
	_check(label + " 序列化不内嵌ShaderMaterial或旧StandardMaterial3D", not scene_text.is_empty() and not scene_text.contains('[sub_resource type="ShaderMaterial"') and not scene_text.contains('type="StandardMaterial3D"'))
	for role: String in used_materials:
		var external: bool = false
		for line: String in scene_text.split("\n"):
			if line.begins_with("[ext_resource ") and (line.contains('type="ShaderMaterial"') or line.contains('type="Material"')) and line.contains('path="' + str(SHARED_MATERIAL_PATHS.get(role, "")) + '"'):
				external = true
		_check(label + " " + role + " 序列化为共享tres外链", external)
	_check_shared_materials_unchanged(label + " 导出重载后")
	var actual: Dictionary = _geometry(instance)
	var duplicate: Dictionary = _geometry(twin)
	var expected: Dictionary = _dictionary(manifest.get("geometry", {}))
	_check(label + " 静态实例无脚本相机灯光", int(actual.get("scripts", -1)) == 0 and int(actual.get("editor_nodes", -1)) == 0 and int(actual.get("unowned_nodes", -1)) == 0)
	_check(label + " 两次实例化 geometry hash 一致", _same(actual, duplicate) and not actual.is_empty())
	var preview: Object = _property(_screen, "preview") as Object
	var model: Node3D = _property(preview, "_model_root") as Node3D
	if _check(label + " 保存后真实预览模型仍存在", model != null and model.get_child_count() == 1):
		var live: Dictionary = _geometry(model.get_child(0))
		_check(label + " 导出实例与实际预览 geometry hash 一致", _same(live, actual), "逐网格路径、变换与 surface arrays 的 SHA256")
	for key: String in ["nodes", "visual_meshes", "collision_shapes", "metadata_meshes"]:
		_check(label + " 几何计数：" + key, int(actual.get(key, -1)) == int(expected.get(key, -2)))
	_check(label + " 非空可视和碰撞", int(actual.get("visual_meshes", 0)) > 0 and int(actual.get("collision_shapes", 0)) > 0)
	for key: String in ["bounds_position", "bounds_size", "collision_bounds_position", "collision_bounds_size"]:
		_check(label + " 实际包围盒：" + key, _near_array(actual.get(key, []), expected.get(key, [])), str(actual.get(key)))
	_check(label + " 配方指纹保留", str(instance.get_meta("recipe_fingerprint", "")) == str(manifest.get("recipe_fingerprint", "")))
	instance.free()
	twin.free()

func _geometry(root: Node) -> Dictionary:
	var result: Dictionary = {"nodes": 0, "scripts": 0, "unowned_nodes": 0, "editor_nodes": 0, "visual_meshes": 0, "collision_shapes": 0, "metadata_meshes": 0}
	var visual: AABB = AABB()
	var collision: AABB = AABB()
	var has_visual: bool = false
	var has_collision: bool = false
	var mesh_hashes: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		result["nodes"] += 1
		if node.get_script() != null:
			result["scripts"] += 1
		if node != root and node.owner == null:
			result["unowned_nodes"] += 1
		if node is Camera3D or node is Light3D:
			result["editor_nodes"] += 1
		var transform: Transform3D = _relative_transform(node, root)
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			result["visual_meshes"] += 1
			if node.has_meta("slot_id") and node.has_meta("component_id"):
				result["metadata_meshes"] += 1
			if mesh_node.mesh != null:
				var box: AABB = transform * mesh_node.mesh.get_aabb()
				visual = visual.merge(box) if has_visual else box
				has_visual = true
				for surface: int in range(mesh_node.mesh.get_surface_count()):
					mesh_hashes.append(var_to_bytes([str(root.get_path_to(node)), transform, mesh_node.mesh.surface_get_arrays(surface)]).hex_encode().sha256_text())
		if node is CollisionShape3D:
			result["collision_shapes"] += 1
			var shape: Shape3D = (node as CollisionShape3D).shape
			var box: AABB = AABB()
			var valid: bool = false
			if shape is BoxShape3D:
				var dimensions: Vector3 = (shape as BoxShape3D).size
				box = transform * AABB(-dimensions * 0.5, dimensions)
				valid = true
			elif shape is ConcavePolygonShape3D:
				for point: Vector3 in (shape as ConcavePolygonShape3D).get_faces():
					var transformed: Vector3 = transform * point
					box = box.expand(transformed) if valid else AABB(transformed, Vector3.ZERO)
					valid = true
			if valid:
				collision = collision.merge(box) if has_collision else box
				has_collision = true
		for child: Node in node.get_children():
			stack.append(child)
	result["bounds_position"] = [visual.position.x, visual.position.y, visual.position.z]
	result["bounds_size"] = [visual.size.x, visual.size.y, visual.size.z]
	result["collision_bounds_position"] = [collision.position.x, collision.position.y, collision.position.z]
	result["collision_bounds_size"] = [collision.size.x, collision.size.y, collision.size.z]
	result["mesh_geometry_hash"] = "|".join(mesh_hashes).sha256_text()
	return result

func _relative_transform(node: Node, root: Node) -> Transform3D:
	var transform: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform

func _unsafe_resource(value: Variant, visited: Dictionary) -> bool:
	if value is Script:
		return true
	if value is Resource:
		var resource: Resource = value as Resource
		var id: int = resource.get_instance_id()
		if visited.has(id):
			return false
		visited[id] = true
		if resource.get_script() != null:
			return true
		if resource is PackedScene:
			return _unsafe_state((resource as PackedScene).get_state(), visited)
		for entry: Dictionary in resource.get_property_list():
			if int(entry.get("usage", 0)) & PROPERTY_USAGE_STORAGE:
				if _unsafe_resource(resource.get(str(entry["name"])), visited):
					return true
	elif value is Array:
		for item: Variant in value:
			if _unsafe_resource(item, visited):
				return true
	elif value is Dictionary:
		for key: Variant in value:
			if _unsafe_resource(value[key], visited):
				return true
	return false

func _unsafe_state(state: SceneState, visited: Dictionary) -> bool:
	if state == null:
		return false
	var base: SceneState = state.get_base_scene_state()
	if base != null and _unsafe_state(base, visited):
		return true
	for index: int in range(state.get_node_count()):
		var nested: PackedScene = state.get_node_instance(index)
		if nested != null and _unsafe_resource(nested, visited):
			return true
		for property_index: int in range(state.get_node_property_count(index)):
			if str(state.get_node_property_name(index, property_index)) == "script" or _unsafe_resource(state.get_node_property_value(index, property_index), visited):
				return true
	return false

func _capture(dimensions: Vector2i, suffix: String = "", fixed_view: Dictionary = {}) -> void:
	print("[workshop-editor-stage] capture ", dimensions, suffix)
	var label: String = "%dx%d%s" % [dimensions.x, dimensions.y, suffix]
	if not _check(label + " 非 headless 渲染", DisplayServer.get_name() != "headless"):
		return
	var scan_ready: bool = await _wait_for_filesystem_scan(label)
	if not scan_ready:
		return
	# 只清理本验证窗口的系统窗口状态；不强制隐藏编辑器的其他 popup。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	_tree.root.size = dimensions
	for frame: int in range(5):
		await _tree.process_frame
	# 门窗对比图固定同一相机；尺寸变更与刷新预览可能自动fit，必须在布局稳定后覆盖。
	if not fixed_view.is_empty():
		var preview: Control = _property(_screen, "preview") as Control
		var camera: Camera3D = _property(preview, "camera") as Camera3D
		if _check(label + " 固定视角相机存在", camera != null):
			camera.transform = fixed_view.transform
			camera.projection = int(fixed_view.projection)
			camera.size = float(fixed_view["size"])
			camera.fov = float(fixed_view.fov)
			_check(label + " 同视角/投影/缩放", camera.transform.is_equal_approx(fixed_view.transform) and camera.projection == int(fixed_view.projection) and is_equal_approx(camera.size, float(fixed_view["size"])) and is_equal_approx(camera.fov, float(fixed_view.fov)))
	# 编辑器可能进入低处理模式，不等待一个可能永不触发的被动帧信号。
	RenderingServer.force_draw()
	print("[workshop-editor-stage] framebuffer ready")
	_check(label + " 实际窗口尺寸", DisplayServer.window_get_size() == dimensions and _tree.root.size == dimensions, str(_tree.root.size))
	_layout_checks(label)
	var image: Image = _tree.root.get_texture().get_image()
	if not _check(label + " 真实编辑器 framebuffer", image != null and not image.is_empty() and image.get_width() == dimensions.x and image.get_height() == dimensions.y):
		return
	var path: String = "res://outputs/workshop_editor_%s.png" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	if _check(label + " 截图落盘", image.save_png(path) == OK):
		_artifacts.append(path)

func _wait_for_filesystem_scan(label: String) -> bool:
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	var deadline_msec: int = Time.get_ticks_msec() + 5000
	var yielded: bool = false
	while filesystem.is_scanning() and Time.get_ticks_msec() < deadline_msec:
		yielded = true
		await _tree.process_frame
	var scanning: bool = filesystem.is_scanning()
	_check(label + " 文件系统扫描已结束", not scanning, "5秒后仍在扫描，截图明确失败" if scanning else ("等待扫描完成" if yielded else "未处于扫描状态"))
	return not scanning

func _layout_checks(label: String) -> void:
	_check_editor_repair_ui(label)
	_check(label + " 主屏实际最小宽度700", _screen.is_visible_in_tree() and _screen.size.x >= 700.0 and _screen.custom_minimum_size.x >= 700.0)
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	_check(label + " 使用编辑器主题", _screen.theme == editor_theme)
	var has_base_color: bool = editor_theme.has_color("base_color", "Editor")
	var base_color: Color = editor_theme.get_color("base_color", "Editor") if has_base_color else Color.WHITE
	_check(label + " EditorMain 暗色主题", has_base_color and base_color.get_luminance() < 0.5 and EditorInterface.get_base_control().is_visible_in_tree(), str(base_color))
	var panels: Array[Control] = []
	for property: String in ["_left_panel", "preview", "_right_panel"]:
		var panel: Control = _property(_screen, property) as Control
		if _check(label + " 实际面板非空：" + property, panel != null and panel.is_visible_in_tree() and panel.size.x > 0.0 and panel.size.y > 0.0 and panel.get_child_count() > 0):
			panels.append(panel)
	for index: int in range(panels.size()):
		for next: int in range(index + 1, panels.size()):
			_check(label + " 主面板无重叠：%d/%d" % [index, next], not _visible_rect(panels[index]).intersects(_visible_rect(panels[next])))
	var title_found: bool = false
	var missing: Array[String] = []
	var overlaps: Array[String] = []
	var pages: Dictionary = _dictionary(_property(_screen, "pages"))
	var constants: Dictionary = _screen.get_script().get_script_constant_map()
	var expected_pages: int = int((constants.get("PAGES", []) as Array).size())
	_check(label + " 参数页均有实际内容", expected_pages > 0 and pages.size() == expected_pages, "%d/%d" % [pages.size(), expected_pages])
	for key: Variant in pages:
		var page: Control = pages[key] as Control
		_check(label + " 页内容非空：" + str(key), page != null and page.get_child_count() > 0)
	var stack: Array[Node] = [_screen]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var text: String = ""
		if node is Label:
			text = (node as Label).text
		elif node is Button:
			text = (node as Button).text
		if text == "老王场景工坊" and node is Control and (node as Control).is_visible_in_tree():
			title_found = true
		if text.to_lower().contains("missing"):
			missing.append(text)
		# 只比较真实容器的可见直接子控件；剪裁掉滚动区域外内容，不使用虚构坐标。
		if node is BoxContainer:
			var children: Array[Control] = []
			for child: Node in node.get_children():
				if child is Control and (child as Control).is_visible_in_tree():
					children.append(child as Control)
			for index: int in range(children.size()):
				for next: int in range(index + 1, children.size()):
					var a: Rect2 = _visible_rect(children[index]).grow(-0.5)
					var b: Rect2 = _visible_rect(children[next]).grow(-0.5)
					if a.has_area() and b.has_area() and a.intersects(b):
						overlaps.append("%s / %s" % [str(children[index].get_path()), str(children[next].get_path())])
		for child: Node in node.get_children():
			if not child is Window:
				stack.append(child)
	_check(label + " 真实标题且无 missing", title_found and missing.is_empty(), str(missing))
	_check(label + " 实际容器控件无重叠", overlaps.is_empty(), str(overlaps))

func _visible_rect(control: Control) -> Rect2:
	var rect: Rect2 = control.get_global_rect().intersection(Rect2(Vector2.ZERO, Vector2(_tree.root.size)))
	var current: Node = control.get_parent()
	while current != null and current != _tree.root:
		if current is Control and (current as Control).clip_contents:
			rect = rect.intersection((current as Control).get_global_rect())
		current = current.get_parent()
	return rect

func _finish() -> void:
	_check_shared_materials_unchanged("全部编辑器验收结束")
	var current_root: Node = EditorInterface.get_edited_scene_root()
	_scene_unchanged = current_root == _edited_root and _root_transform(current_root) == _edited_transform
	_check("edited scene root 及 transform 不变", _scene_unchanged)
	_check("root paused 不变", _tree.paused == _paused)
	_check("最终 editor_hint 为真", Engine.is_editor_hint())
	_check("最终未启动游戏场景", not EditorInterface.is_playing_scene())
	_check("报告目录可创建", DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs")) == OK)
	_artifacts.append(REPORT_PATH)
	var report: Dictionary = {
		"passed": _failures.is_empty(), "checks": _checks, "failures": _failures,
		"enginehint": Engine.is_editor_hint(), "is_playing": EditorInterface.is_playing_scene(),
		"scene_unchanged": _scene_unchanged, "root_paused_unchanged": _tree.paused == _paused,
		"artifacts": _artifacts, "buildids": _build_ids, "dependencies": _dependencies,
		"project_path": ProjectSettings.globalize_path("res://"),
		"input_method": "真实 Control 值及真实 Button.pressed 信号；不是鼠标自动化",
		"lifecycle_scope": "实际插件隐藏/恢复及 UPDATE_DISABLED；未执行插件卸载/重载，不 queue_free 插件",
		"visual_acceptance": "截图仅为真实编辑器证据；非空截图和拓扑通过不代表professional美术验收通过，仍须目检接缝、洞口、倒角与阴影",
		"legacy_scope": "原有modular_v1回归、替件、保存和生命周期检查保留；普通、floor_facade及damaged_l_plants截图仅为legacy兼容证据，不是shell_v2新成品",
		"legacy_checks_before_shell": _legacy_check_count,
		"shell_samples": _shell_samples,
		"architecture_samples": _architecture_samples,
		"shell_capture_scope": "continuous_*为1600x1000真实编辑器framebuffer；workshop_shell_model_*.png为1400x1100独立SubViewport的真实模型渲染；未隐藏侧栏或改变主屏stretch，未关闭阴影",
		"window_weathering_scope": "独立rectangle 15x10两层、form=false/taper=0；真实generate/window_apply/architecture_apply/damage_apply；aging=0/.2/.5/.9，damage=0/.4/.9；完整UI截图_clean/_windows_edited/_weathered/_damaged及分档图均锁定同相机，可由主线程剪裁展示；结束恢复original文档与catalog",
		"game_save_connected": false,
		"boundaries": ["仅生成和保存静态建筑，不启动 Main", "不连接或调用游戏存档", "组件 fixture 仅允许隔离副本", "缺失 API 记为失败，不模拟成功"]
	}
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_check("JSON 报告写入", false, error_string(FileAccess.get_open_error()))
	else:
		file.store_string(JSON.stringify(report, "\t"))
		var error: Error = file.get_error()
		file.close()
		if error != OK:
			_check("JSON 报告写入", false, error_string(error))
	print("[workshop-editor] %d checks, %d failures" % [_checks.size(), _failures.size()])
	_tree.quit(0 if _failures.is_empty() else 1)

func _check(name: String, passed: bool, detail: String = "") -> bool:
	_checks.append({"name": name, "passed": passed, "detail": detail})
	if not passed:
		_failures.append(name + ("：" + detail if not detail.is_empty() else ""))
	return passed

func _check_result(name: String, result: Dictionary) -> bool:
	return _check(name, bool(result.get("ok", false)), str(result.get("reason", "缺少 ok" if not result.has("ok") else "")))

func _property(object: Object, key: String) -> Variant:
	if not is_instance_valid(object):
		return null
	for entry: Dictionary in object.get_property_list():
		if str(entry.get("name", "")) == key:
			return object.get(key)
	return null

func _require_methods(object: Object, methods: Array, owner: String) -> bool:
	var valid: bool = true
	for method: String in methods:
		var available: bool = is_instance_valid(object) and object.has_method(method)
		_check(owner + "." + method + " 可用", available)
		if not available:
			_dependencies.append(owner + "." + method)
			valid = false
	return valid

func _result(object: Object, method: String, args: Array = []) -> Dictionary:
	if not is_instance_valid(object) or not object.has_method(method):
		_check("调用依赖：" + method, false, "缺少真实对象或方法")
		return {"ok": false, "reason": "缺少真实方法：" + method}
	var value: Variant = object.callv(method, args)
	if not value is Dictionary:
		_check("返回 Dictionary：" + method, false, str(value))
		return {"ok": false, "reason": "真实 API 未返回 Dictionary：" + method}
	return value as Dictionary

func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}

func _snapshot() -> Dictionary:
	return _result(_screen, "snapshot")

func _same(a: Variant, b: Variant) -> bool:
	return _stable_value(a) == _stable_value(b)

func _stable_value(value: Variant) -> String:
	# JSON 会将数字读为 float；按数值比较整数，不能把重载差异误报成数据损坏。
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var fields: Array[String] = []
		for key: Variant in keys:
			fields.append(JSON.stringify(str(key)) + ":" + _stable_value(value[key]))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var entries: Array[String] = []
		for item: Variant in value:
			entries.append(_stable_value(item))
		return "[" + ",".join(entries) + "]"
	if value is float and is_finite(float(value)) and floor(float(value)) == float(value) and absf(float(value)) <= 9007199254740991.0:
		return str(int(value))
	return JSON.stringify(value)

func _near_array(a: Variant, b: Variant) -> bool:
	if not a is Array or not b is Array or a.size() != 3 or b.size() != 3:
		return false
	for axis: int in range(3):
		if not is_equal_approx(float(a[axis]), float(b[axis])):
			return false
	return true

func _set_spin(key: String, value: float) -> bool:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var slider: HSlider = controls.get(key) as HSlider
	if not _check("实际 HSlider：" + key, slider != null, str(controls.keys())):
		return false
	slider.value = value
	return _check("HSlider 接收输入：" + key, is_equal_approx(slider.value, value), "期望 %f 实际 %f（min=%f max=%f step=%f）" % [value, slider.value, slider.min_value, slider.max_value, slider.step])

func _spin(key: String) -> float:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var slider: HSlider = controls.get(key) as HSlider
	return slider.value if slider != null else NAN

## 状态栏文字是真实验收产物：按钮被按到不等于操作成功，拒绝原因要能进断言细节。
func _status_text() -> String:
	var label: Label = _property(_screen, "status_label") as Label
	return str(label.text) if label != null else ""

func _set_check(key: String, value: bool) -> bool:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var check: CheckButton = controls.get(key) as CheckButton
	if not _check("实际 CheckButton：" + key, check != null):
		return false
	check.button_pressed = value
	return _check("CheckButton 接收输入：" + key, check.button_pressed == value)

func _set_text(key: String, text: String) -> bool:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var edit: LineEdit = controls.get(key) as LineEdit
	if not _check("实际 LineEdit：" + key, edit != null):
		return false
	edit.text = text
	edit.text_changed.emit(text)
	return true

func _emit_button(key: String) -> bool:
	var buttons: Dictionary = _dictionary(_property(_screen, "buttons"))
	var button: Button = buttons.get(key) as Button
	if not _check("真实按钮信号：" + key, button != null and not button.disabled, "直接 emit pressed，不是鼠标事件"):
		return false
	button.pressed.emit()
	return true

func _result_button(key: String) -> Dictionary:
	if not _emit_button(key):
		return {"ok": false, "reason": "按钮不可用：" + key}
	return {"ok": true}

func _root_transform(root: Node) -> Variant:
	if not is_instance_valid(root):
		return null
	if root is Node3D:
		return (root as Node3D).transform
	if root is CanvasItem:
		return (root as CanvasItem).get_transform()
	return null

func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check("读取 JSON：" + path, false, error_string(FileAccess.get_open_error()))
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check("JSON 对象：" + path, value is Dictionary)
	return _dictionary(value)

func _bundle_hashes(directory: String) -> Dictionary:
	var hashes: Dictionary = {}
	for name: String in ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json"]:
		hashes[name] = FileAccess.get_sha256(directory.path_join(name))
	return hashes
