@tool
extends Control
## 编辑器主屏只拥有 UI；会话、版本落盘和组件替换各走独立端口。

const Session = preload("res://src/workshop/session.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Preview = preload("res://addons/building_workshop/editor_preview.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const WindowGeometry = preload("res://src/workshop/shell_window_geometry.gd")
const Generator = preload("res://src/workshop/generator.gd")
const WINDOW_PREVIEW_DELAY: float = 0.16
const DEFAULT_ROOT: String = "res://scenes/workshop_buildings"
const SAMPLE_ROOT: String = "res://data/workshop/samples"
const PAGES: Array[String] = ["结构", "门窗", "配色", "破旧", "植物", "空间", "构架", "形体", "文件"]
const DEFAULT_MODULES: Array[Dictionary] = [
	{"id": "default_sea_breeze", "label": "海风公寓", "description": "矩形 · 住宅", "file": "workshop_default_sea_breeze.recipe.json"},
	{"id": "default_harbor_market", "label": "码头商铺", "description": "矩形 · 商业", "file": "workshop_default_harbor_market.recipe.json"},
	{"id": "default_lighthouse_studio", "label": "灯塔工作室", "description": "T形 · 高层", "file": "workshop_default_lighthouse_studio.recipe.json"},
	{"id": "default_courtyard_harbor", "label": "回廊庭院", "description": "U形 · 公共空间", "file": "workshop_default_courtyard.recipe.json"}
]
const FORM_CATEGORIES: Array[String] = ["structure", "opening", "accessory"]
const FORM_LABELS: Dictionary = {"structure": "整楼结构", "opening": "窗户洞口", "accessory": "配件"}
const FORM_PRESETS: Dictionary = {
	"SF-A": {"structure": [0.020, 0.040], "opening": [0.020, 0.038], "accessory": [0.025, 0.060]},
	"SF-B": {"structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100]},
	"SF-C": {"structure": [0.060, 0.100], "opening": [0.055, 0.095], "accessory": [0.080, 0.150]}
}
const PARAMETER_KEYS: Array[String] = ["construction_mode", "shape", "width", "depth", "floors", "floor_height", "wall_thickness", "slab_thickness", "column_width", "window_width", "window_height", "window_sill", "bay_width", "door_width", "door_height", "aging", "damage", "bevel_segments", "bevel_width", "vegetation_density", "vegetation_random_enabled", "vegetation_variation", "taper", "structure_seed", "damage_seed", "vegetation_seed", "spatial_profile"]
const ARCHITECTURE_WINDOW_FIELDS: Array[String] = ["enabled", "type", "open_angle", "frame_width", "frame_depth", "glass_thickness", "recess", "sill_enabled", "sill_projection", "sill_thickness", "sill_extension", "width", "height", "sill"]
const ARCHITECTURE_WINDOW_SCOPES: Array[String] = ["global", "floor", "facade", "single"]
const ARCHITECTURE_ROOF_FIELDS: Array[String] = ["mode", "height", "thickness", "cap_thickness", "cap_overhang", "post_spacing", "rail_spacing", "bar_width"]
const VEGETATION_KEYS: Array[String] = ["vegetation_density", "vegetation_random_enabled", "vegetation_variation", "vegetation_seed", "growth_small", "growth_medium", "growth_large"]
const INTEGER_KEYS: Array[String] = ["floors", "bevel_segments", "structure_seed", "damage_seed", "vegetation_seed"]
const ROLE_LABELS: Dictionary = {"wall": "墙", "slab": "楼板 / 屋顶", "frame": "门窗框", "glass": "窗玻璃", "pillar": "柱", "plant": "植物"}
const MATERIAL_ROLE_LABELS: Dictionary = {"SEA_Matte": "SEA_Matte · 哑光", "SEA_Metal": "SEA_Metal · 金属", "SEA_Gloss": "SEA_Gloss · 玻璃/光泽", "SEA_Emission": "SEA_Emission · 发光"}
const MATERIAL_EDIT_FIELDS: Array[String] = ["roughness", "metallic", "specular", "emission_energy", "transparency"]
const MATERIAL_EDIT_LABELS: Dictionary = {"roughness": "粗糙度", "metallic": "金属度", "specular": "镜面强度", "emission_energy": "发光强度", "transparency": "玻璃透明度"}
const MATERIAL_EDIT_BOUNDS: Dictionary = {
	"roughness": [0.0, 1.0, 0.01],
	"metallic": [0.0, 1.0, 0.01],
	"specular": [0.0, 1.0, 0.01],
	"emission_energy": [0.0, 2.0, 0.01],
	"transparency": [0.0, 1.0, 0.01]
}
const WORKSHOP_BG := Color("#101b2d")
const WORKSHOP_SURFACE := Color("#17263b")
const WORKSHOP_SURFACE_ALT := Color("#1d3048")
const WORKSHOP_LINE := Color("#385b7a")
const WORKSHOP_ACCENT := Color("#46c2d7")
const WORKSHOP_ACCENT_HOVER := Color("#70e0e8")
const WORKSHOP_GOLD := Color("#f1c56b")
const WORKSHOP_TEXT := Color("#e8f1f6")
const WORKSHOP_MUTED := Color("#a9bdca")
const WORKSHOP_WARN := Color("#f3a36f")
const MATERIAL_ROLE_DEFAULTS: Dictionary = {
	"SEA_Matte": {"roughness": 0.82, "metallic": 0.0, "specular": 0.18, "emission_energy": 0.0, "transparency": 0.0},
	"SEA_Metal": {"roughness": 0.36, "metallic": 0.72, "specular": 0.55, "emission_energy": 0.0, "transparency": 0.0},
	"SEA_Gloss": {"roughness": 0.18, "metallic": 0.10, "specular": 0.70, "emission_energy": 0.0, "transparency": 0.18},
	"SEA_Emission": {"roughness": 0.38, "metallic": 0.0, "specular": 0.20, "emission_energy": 1.20, "transparency": 0.0}
}

var session: Session
var preview: Preview
var buttons: Dictionary = {}
var controls: Dictionary = {}
var pages: Dictionary = {}
var architecture_panels: Array[Control] = []
var state_label: Label
var status_label: Label
var status_panel: PanelContainer
var status_copy_button: Button
var selected_slot_label: Label
var _last_status_text: String = ""
var _id_edit: LineEdit
var _name_edit: LineEdit
var export_root: String = DEFAULT_ROOT
var _store: Variant
var _ports: Dictionary = {}
var _page_picker: OptionButton
var form_readout_label: Label
var frame_readout_label: Label
var _slot_list: ItemList
var _saved_list: ItemList
var _sample_picker: OptionButton
var _confirm: ConfirmationDialog
var _save_as_dialog: ConfirmationDialog
var _save_as_id: LineEdit
var _file_dialog: FileDialog
var _component_dialog: FileDialog
var _left_panel: ScrollContainer
var _right_panel: ScrollContainer
var _confirm_action: Callable = Callable()
var _last_export: Dictionary = {}
var _slot_cache: Dictionary = {}
var _slot_ids: Array[String] = []
var _selected_id: String = ""
var _selected_opening_id: String = ""
var _last_window_scope: String = "global"
var _ignore_fields: bool = false
var _screen_visible: bool = false
var _initialized: bool = false
var _pending_recovery: Dictionary = {}
var _replacement_component_id: String = ""
var _local_baseline: Dictionary = {}
var _live_slot_ids: Dictionary = {}
var _opening_cache: Dictionary = {}
var _architecture_visibility: Array[String] = []
var _window_preview_timer: Timer
var _window_preview_keys: Dictionary = {}
var _window_failed_keys: Dictionary = {}
var _window_preview_target: Dictionary = {}
var _last_floor_index: float = 0.0
var _last_facade: String = "front"
var _window_drag_key: String = ""
var _window_history_key: String = ""
var _window_history_fingerprint: String = ""
var _window_preview_busy: bool = false
var _range_readouts: Dictionary = {}
var window_preview_result: Dictionary = {}

func configure(ports: Dictionary = {}) -> void:
	_ports.merge(ports, true)
	if ports.has("store"):
		_store = ports["store"]
	if ports.has("export_root") or ports.has("base_dir"):
		export_root = str(ports.get("export_root", ports.get("base_dir", DEFAULT_ROOT)))
	if ports.has("session") and ports["session"] != null:
		if session != null and session.changed.is_connected(_on_session_changed):
			session.changed.disconnect(_on_session_changed)
		session = ports["session"] as Session
		_connect_session()
	if _initialized:
		_ensure_editor_catalog()
		_refresh_from_session()
		refresh_documents()
		if _screen_visible:
			refresh_preview()

func _ready() -> void:
	name = "BuildingWorkshopEditorScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(700, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if Engine.is_editor_hint():
		theme = EditorInterface.get_editor_theme()
	add_theme_font_size_override("font_size", 14)
	if session == null:
		session = Session.new(Catalog.editor_catalog())
		session.replace_recipe(Recipe.authoring_defaults())
	_build_ui()
	_select_page(0)
	_window_preview_timer = Timer.new()
	_window_preview_timer.one_shot = true
	_window_preview_timer.wait_time = WINDOW_PREVIEW_DELAY
	_window_preview_timer.timeout.connect(flush_window_preview)
	add_child(_window_preview_timer)
	_initialized = true
	_connect_session()
	_refresh_from_session()
	refresh_documents()
	_refresh_samples()
	visibility_changed.connect(_on_visibility_changed)
	if not _pending_recovery.is_empty():
		var recovery: Dictionary = _pending_recovery
		_pending_recovery = {}
		restore_recovery(recovery)
	set_screen_visible(_screen_visible)

func _ensure_editor_catalog() -> Dictionary:
	var upgraded: Dictionary = Catalog.editor_catalog(session.catalog)
	if Catalog.fingerprint(upgraded) == Catalog.fingerprint(session.catalog):
		return {"ok": true}
	return session.replace_catalog(upgraded)

func _connect_session() -> void:
	if session != null and not session.changed.is_connected(_on_session_changed):
		session.changed.connect(_on_session_changed)

func set_screen_visible(value: bool) -> void:
	_screen_visible = value
	visible = value
	set_process_unhandled_key_input(value)
	if preview != null:
		preview.set_screen_visible(value)
	if value and _initialized and preview._slots.is_empty():
		refresh_preview()

func _on_visibility_changed() -> void:
	if preview != null:
		preview.set_screen_visible(_screen_visible and is_visible_in_tree())

func snapshot() -> Dictionary:
	return session.snapshot() if session != null else {}

func _collect_ui_patch() -> Dictionary:
	var patch: Dictionary = {"building_id": _id_edit.text.strip_edges(), "display_name": _name_edit.text}
	for key: String in PARAMETER_KEYS:
		patch[key] = _control_value(key)
	if _option_value("construction_mode") == "shell_v2" and controls.has("architecture_shape_variant"):
		patch["shape"] = _option_value("architecture_shape_variant")
	if snapshot().has("architecture"):
		patch["architecture"] = _architecture_snapshot() if _option_value("construction_mode") != "shell_v2" else _architecture_ui_patch(true)
	var bindings: Dictionary = snapshot().get("component_bindings", {}).duplicate(true)
	for role: String in Recipe.COMPONENT_ROLES:
		bindings[role] = _option_value("binding_" + role)
	patch["component_bindings"] = bindings
	patch["growth_weights"] = [_spin_value("growth_small"), _spin_value("growth_medium"), _spin_value("growth_large")]
	return patch

func generate_building() -> Dictionary:
	if str(snapshot().get("construction_mode", "modular_v1")) != "shell_v2":
		return _report_failure("旧版拼装已停止使用，请点击「新建」生成连续实体楼房。")
	return apply_parameters()

func apply_parameters() -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "编辑器主屏尚未初始化"}
	var window_result: Dictionary = flush_window_preview()
	if not bool(window_result.get("ok", false)) or not _window_failed_keys.is_empty():
		return _report_failure("窗输入尚未通过：" + str(window_preview_result.get("reason", "请先修正窗滑块")))
	var catalog_ready: Dictionary = _ensure_editor_catalog()
	if not bool(catalog_ready.get("ok", false)):
		return _report_result(catalog_ready, "组件目录升级失败")
	var pending: Array[String] = _pending_local_fields()
	if not pending.is_empty():
		return _report_failure("存在尚未应用的输入（%s），请先点击对应的局部应用按钮，再应用全部参数或保存。" % ", ".join(pending))
	# 所有基础字段和全局绑定一次提交；失败时保留输入及原会话。
	var result: Dictionary = session.apply_patch(_collect_ui_patch())
	if bool(result.get("ok", false)):
		_refresh_from_session()
		var built: Dictionary = refresh_preview()
		if bool(built.get("ok", false)):
			_set_status("所有参数已原子应用；尚未保存时可撤销。")
	else:
		_set_status("参数未提交：" + str(result.get("reason", "未知错误")))
	_update_state()
	return result

func save_building() -> Dictionary:
	if _store == null:
		return _report_failure("未注入编辑器 Store，不能保存。")
	var applied: Dictionary = apply_parameters()
	if not bool(applied.get("ok", false)):
		return applied
	var result: Dictionary = _store.export_revision(snapshot(), session.catalog, export_root)
	if not bool(result.get("ok", false)):
		return _report_result(result, "保存失败，草稿仍保留")
	_last_export = result.duplicate(true)
	var saved_recipe: Dictionary = result.get("recipe", {}) as Dictionary
	var synced: Dictionary = session.sync_exported_revision(int(saved_recipe.get("revision", snapshot().get("revision", 1))))
	if not bool(synced.get("ok", false)):
		return _report_failure("文件已保存，但会话版本同步失败：" + str(synced.get("reason", "")))
	_refresh_from_session()
	refresh_documents()
	var rescan: Callable = _ports.get("rescan", Callable())
	if rescan.is_valid():
		rescan.call()
	_set_status("已保存并烘焙五件 bundle：%s；候选资产尚未正式登记。" % str(result.get("directory", "")))
	_update_state()
	return result

func open_recipe(path: String) -> Dictionary:
	if has_pending_fields():
		_ask_discard(_open_recipe_now.bind(path), "打开另一栋建筑将丢弃当前未保存修改，是否继续？")
		return {"ok": false, "reason": "等待确认", "confirmation_required": true}
	return _open_recipe_now(path)

func _open_recipe_now(path: String) -> Dictionary:
	if _store == null:
		return _report_failure("未注入编辑器 Store，不能打开配方。")
	var result: Dictionary = _store.load_recipe(path)
	if not bool(result.get("ok", false)):
		return _report_result(result, "打开失败，当前草稿未改变")
	var loaded_recipe: Dictionary = result.get("recipe", {})
	if str(loaded_recipe.get("construction_mode", "modular_v1")) != "shell_v2":
		return _report_failure("旧版拼装配方已停止编辑，原文件未修改；请新建连续实体楼房。")
	var accepted: Dictionary = session.accept_loaded(loaded_recipe, Catalog.editor_catalog(result.get("catalog", {})))
	if not bool(accepted.get("ok", false)):
		return _report_result(accepted, "配方被拒绝")
	_reset_window_preview()
	_slot_cache.clear()
	_selected_id = ""
	_last_export = {"scene_path": path.get_base_dir().path_join("building.tscn"), "recipe_path": path}
	_refresh_from_session()
	refresh_preview()
	_set_status("已打开：" + path)
	return accepted

func refresh_preview(preserve_slot_fields: bool = false, prepared_build: Dictionary = {}) -> Dictionary:
	if session == null or preview == null or not preview.is_node_ready():
		return {"ok": false, "reason": "独立编辑器预览尚未初始化"}
	var previous_ui_values: Dictionary = _capture_ui_values()
	var previous_baseline: Dictionary = _local_baseline.duplicate(true)
	var previous_opening_id: String = _selected_opening_id
	var previous_scope: String = _window_scope()
	var slot_fields: Array[String] = ["component_id", "disabled", "offset_x", "offset_y", "offset_z", "growth_key", "vegetation_lock"]
	var pending_slot_values: Dictionary = {}
	if preserve_slot_fields:
		for key: String in slot_fields:
			pending_slot_values[key] = _raw_control_value(key)
	var result: Dictionary = session.build() if prepared_build.is_empty() else prepared_build
	if not bool(result.get("ok", false)):
		return _report_result(result, "生成失败，保留上一份预览")
	preview.set_build_result(result)
	var previous_openings: Dictionary = _opening_cache.duplicate(true)
	_opening_cache.clear()
	for raw_opening: Variant in result.get("openings", []):
		var opening: Dictionary = raw_opening as Dictionary
		_opening_cache[str(opening.get("id", ""))] = opening.duplicate(true)
	for opening_id: String in previous_openings:
		if not _opening_cache.has(opening_id):
			_opening_cache[opening_id] = previous_openings[opening_id].duplicate(true)
	_live_slot_ids.clear()
	var next_cache: Dictionary = {}
	for raw: Variant in result.get("slots", []):
		var slot: Dictionary = raw as Dictionary
		var id: String = str(slot.get("id", ""))
		_live_slot_ids[id] = true
		next_cache[id] = slot.duplicate(true)
	var data: Dictionary = snapshot()
	var overrides: Dictionary = data.get("slot_overrides", {}) as Dictionary
	var excluded: Array = data.get("excluded_slots", []) as Array
	# 缓存仅保留显式覆盖 / 排除的失效槽，且移除过期几何；只能用于恢复入口。
	for raw_id: Variant in _slot_cache:
		var id: String = str(raw_id)
		if not next_cache.has(id) and (overrides.has(id) or excluded.has(id)):
			var cached: Dictionary = _slot_cache[id] as Dictionary
			next_cache[id] = {"id": id, "kind": cached.get("kind", "")}
	_slot_cache = next_cache
	_update_slot_list()
	if not _slot_ids.has(_selected_id):
		_selected_id = ""
	select_slot(_selected_id)
	_ignore_fields = true
	_selected_opening_id = previous_opening_id
	_last_window_scope = previous_scope
	if controls.has("window_scope"):
		_set_option("window_scope", previous_scope)
	_sync_window_selection(snapshot())
	for key: Variant in previous_ui_values:
		if controls.has(key):
			_set_control_value(str(key), previous_ui_values[key])
	if preserve_slot_fields:
		for key: String in slot_fields:
			_set_control_value(key, pending_slot_values[key])
	_local_baseline = previous_baseline
	if not preserve_slot_fields:
		# select_slot 已按重建后的槽位重填控件并捕获基线；恢复旧基线会把上一份文档的 component_id 带进来，
		# 于是新文档永远显示"存在未应用输入"、连保存都被拦。槽位基线必须跟着实际控件走。
		_capture_local_baseline(slot_fields)
	_ignore_fields = false
	var stats: Dictionary = result.get("stats", {}) as Dictionary
	var label: Label = controls["stats"] as Label
	label.text = "槽位 %d · 三角面 %d\n节点 %d · 碰撞 %d\n行走声明 %d · 水面声明 %d\n空间声明不等于已接入正式世界。" % [result.get("slots", []).size(), int(stats.get("triangles", 0)), int(stats.get("nodes", 0)), int(stats.get("collision_shapes", 0)), result.get("walk_surfaces", []).size(), result.get("water_blockers", []).size()]
	_update_state()
	return result

func has_pending_fields() -> bool:
	if session == null:
		return false
	if session.is_dirty():
		return true
	if not _initialized:
		return false
	var current: Dictionary = snapshot()
	var candidate: Dictionary = current.duplicate(true)
	candidate.merge(_collect_ui_patch(), true)
	# 稀疏旧配方的全局窗尺寸继承顶层值：仅UI展开默认值不算用户修改。
	if str(current.get("construction_mode", "")) == "shell_v2" and _window_scope() == "global":
		var original_window: Dictionary = Config.normalized(current.get("architecture", {})).get("window", {})
		for field: String in ["width", "height", "sill"]:
			if not original_window.has(field) and is_equal_approx(float(candidate.architecture.window.get(field, -1.0)), float(current.get("window_" + field, -2.0))):
				candidate.architecture.window.erase(field)
	if Recipe.fingerprint(candidate) != Recipe.fingerprint(current):
		return true
	return _has_pending_local_fields()

func _has_pending_local_fields() -> bool:
	return not _pending_local_fields().is_empty()

## 返回尚未应用的具体控件键，供状态栏与失败原因使用；不隐藏是哪一个字段在拦。
func _pending_local_fields() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _local_baseline:
		if _raw_control_value(str(key)) != _local_baseline[key]:
			result.append(str(key))
	return result

func _capture_local_baseline(keys: Array) -> void:
	for key: String in keys:
		_local_baseline[key] = _raw_control_value(key)

func _raw_control_value(key: String) -> Variant:
	var control: Control = controls[key] as Control
	if control is CheckButton:
		return (control as CheckButton).button_pressed
	return _control_value(key)

func select_slot(id: String) -> void:
	if _initialized and not _ignore_fields and not _window_preview_busy and id != _selected_id:
		flush_window_preview()
		if not _window_failed_keys.is_empty():
			_set_status("窗预览未通过，先修正或清除输入再选择其他槽位；最后成功模型保持。")
			return
	_selected_id = id
	if id.begins_with("frame_") or id.begins_with("glass_") or id.begins_with("sash_") or id.begins_with("sill_"):
		_selected_opening_id = "opening_" + id.trim_prefix("frame_").trim_prefix("glass_").trim_prefix("sash_").trim_prefix("sill_")
	elif not id.is_empty():
		_selected_opening_id = ""
	if not _initialized:
		return
	preview.select_slot(id, false)
	for index: int in _slot_ids.size():
		if _slot_ids[index] == id:
			_slot_list.select(index)
			_slot_list.ensure_current_is_visible()
			break
	var slot: Dictionary = _selected_slot_data(id)
	var data: Dictionary = snapshot()
	var overrides: Dictionary = data.get("slot_overrides", {}) as Dictionary
	var override: Dictionary = overrides.get(id, {}) as Dictionary
	var live: bool = _live_slot_ids.has(id)
	var excluded: bool = bool(override.get("disabled", false)) or data.get("excluded_slots", []).has(id)
	var state: String = "当前几何" if live else ("已排除；仅保留恢复入口" if excluded else "来源已移除 / 当前未生成；仅保留覆盖记录")
	selected_slot_label.text = "槽位：%s\n组件：%s\n%s" % [id, str(override.get("component_id", slot.get("component_id", ""))), state] if not id.is_empty() else "未选择槽位"
	_ignore_fields = true
	_fill_component_option("component_id", _slot_family(id, str(slot.get("kind", ""))), str(override.get("component_id", slot.get("component_id", ""))))
	var offset: Array = override.get("offset", [0.0, 0.0, 0.0]) as Array
	for axis: int in 3:
		_set_spin(["offset_x", "offset_y", "offset_z"][axis], float(offset[axis]))
	var disabled: CheckButton = controls["disabled"] as CheckButton
	disabled.set_pressed_no_signal(bool(override.get("disabled", false)) or data.get("excluded_slots", []).has(id))
	var lock: CheckButton = controls["vegetation_lock"] as CheckButton
	lock.set_pressed_no_signal(false)
	_set_option("growth_key", str(override.get("growth_key", slot.get("growth_key", "medium"))))
	for raw: Variant in data.get("locked_vegetation", []):
		var entry: Dictionary = raw as Dictionary
		if str(entry.get("slot_id", "")) == id:
			lock.set_pressed_no_signal(true)
			_set_option("growth_key", str(entry.get("growth_key", "medium")))
	_ignore_fields = false
	_sync_window_selection(data)
	buttons["slot_apply"].disabled = not live
	buttons["slot_restore"].disabled = id.is_empty()
	buttons["replace_component"].disabled = not live or not _ports.get("replace_component", Callable()).is_valid()
	buttons["export_module"].disabled = not live or not _ports.get("export_module_component", Callable()).is_valid()
	_capture_local_baseline(["component_id", "disabled", "offset_x", "offset_y", "offset_z", "growth_key", "vegetation_lock"])
	_sync_selected_window_controls()

func _sync_selected_window_controls() -> void:
	if controls.has("window_selection"):
		var option: OptionButton = controls["window_selection"] as OptionButton
		var opening_id: String = _window_override_id()
		for index: int in option.item_count:
			if str(option.get_item_metadata(index)) == opening_id:
				option.select(index)
				break
	if _option_value("construction_mode") == "shell_v2" and _window_scope() != "global":
		_sync_architecture_window_scope()

func _architecture_base_window(data: Dictionary) -> Dictionary:
	var result: Dictionary = Config.normalized(data.get("architecture", {})).get("window", {}).duplicate(true)
	result["width"] = data.get("window_width", 1.4)
	result["height"] = data.get("window_height", 1.8)
	result["sill"] = data.get("window_sill", 1.0)
	return result

func _sync_architecture_window_scope() -> void:
	if not controls.has("window_scope") or _option_value("construction_mode") != "shell_v2":
		return
	var ignored: bool = _ignore_fields
	_ignore_fields = true
	var data: Dictionary = snapshot()
	var scope: String = _window_scope()
	var settings: Dictionary = {}
	if scope == "global":
		settings = _architecture_base_window(data)
	elif scope == "floor":
		var floor: int = int(_spin_value("floor_override_index"))
		# 当前层基线不吸入优先级更高的立面/单窗覆盖。
		var floor_data: Dictionary = data.duplicate(true)
		floor_data["facade_overrides"] = {}
		floor_data.architecture["facade_windows"] = {}
		settings = Config.window_settings(floor_data, floor, "front")
	elif scope == "facade":
		# 立面基线不吸入某一楼层覆盖，避免下次操作把该层的值扩散到整立面。
		var facade_data: Dictionary = data.duplicate(true)
		facade_data["floor_overrides"] = {}
		facade_data.architecture["floor_windows"] = {}
		settings = Config.window_settings(facade_data, 0, _option_value("facade_index"))
	else:
		var opening_id: String = _window_override_id()
		var parts: PackedStringArray = opening_id.split("_")
		if parts.size() == 4:
			settings = Config.window_settings(data, int(parts[2]), str(parts[1]), opening_id)
	for field: String in ARCHITECTURE_WINDOW_FIELDS:
		if settings.has(field) and controls.has("architecture_window_" + field):
			_set_architecture_control("architecture_window_" + field, settings[field])
	if settings.has("width"):
		_set_architecture_control("architecture_window_width", settings.width)
	if settings.has("height"):
		_set_architecture_control("architecture_window_height", settings.height)
	if settings.has("sill"):
		_set_architecture_control("architecture_window_sill", settings.sill)
	_capture_window_local_baseline()
	_ignore_fields = ignored
	_update_window_limit_hint()

func _has_pending_window_fields() -> bool:
	for field: String in ARCHITECTURE_WINDOW_FIELDS:
		var key: String = "architecture_window_" + field
		if _local_baseline.has(key) and _raw_control_value(key) != _local_baseline[key]:
			return true
	for field: String in ["width", "height", "sill"]:
		var key: String = "architecture_window_" + field
		if _local_baseline.has(key) and _raw_control_value(key) != _local_baseline[key]:
			return true
	return false

func _capture_window_local_baseline() -> void:
	for field: String in ARCHITECTURE_WINDOW_FIELDS:
		_local_baseline.erase("architecture_window_" + field)
	for field: String in ["width", "height", "sill"]:
		_local_baseline.erase("architecture_window_" + field)
	for field: String in ARCHITECTURE_WINDOW_FIELDS:
		var key: String = "architecture_window_" + field
		if controls.has(key):
			_local_baseline[key] = _raw_control_value(key)

func export_module_component() -> Dictionary:
	var exporter: Callable = _ports.get("export_module_component", Callable())
	if not exporter.is_valid():
		return _report_failure("组件导出适配器尚未注入；楼房保存不受影响。")
	var applied: Dictionary = apply_parameters()
	if not bool(applied.get("ok", false)):
		return applied
	var result: Dictionary = exporter.call(session)
	if bool(result.get("ok", false)):
		_set_status("独立模块已保存：" + str(result.get("scene_path", "")))
	else:
		_report_result(result, "组件导出失败")
	return result

func _capture_ui_values() -> Dictionary:
	var ui_values: Dictionary = {}
	if not _initialized:
		return ui_values
	for key: Variant in controls:
		var control: Control = controls[key] as Control
		if control is Range:
			ui_values[key] = (control as Range).value
		elif control is OptionButton:
			ui_values[key] = _option_value(str(key))
		elif control is CheckButton:
			ui_values[key] = (control as CheckButton).button_pressed
	return ui_values

func get_recovery() -> Dictionary:
	if session == null:
		return {}
	return {"recipe": snapshot(), "catalog": session.catalog.duplicate(true), "ui_patch": _collect_ui_patch() if _initialized else {}, "ui_values": _capture_ui_values(), "dirty": session.is_dirty(), "selected_slot": _selected_id, "selected_opening_id": _selected_opening_id, "window_scope": _window_scope() if _initialized else "global", "local_baseline": _local_baseline.duplicate(true), "page": _page_picker.selected if _initialized else 0, "last_export": _last_export.duplicate(true), "slot_cache": _slot_cache.duplicate(true), "opening_cache": _opening_cache.duplicate(true)}

func restore_recovery(data: Dictionary) -> Dictionary:
	if not _initialized:
		_pending_recovery = data.duplicate(true)
		return {"ok": true, "reason": "草稿将在主屏就绪时恢复"}
	var recipe: Dictionary = data.get("recipe", {}) as Dictionary
	if str(recipe.get("construction_mode", "modular_v1")) != "shell_v2":
		return _report_failure("旧版拼装草稿已停止使用；原文件保留，请点击「新建」使用连续实体。")
	var cat: Dictionary = Catalog.editor_catalog(data.get("catalog", {}) as Dictionary)
	var reason: String = Recipe.validate(recipe, cat)
	if not reason.is_empty():
		return _report_failure("恢复草稿失败：" + reason)
	# 同一实例重启插件时不重载会话，保留其撤销栈和保存指纹。
	if Recipe.fingerprint(snapshot()) != Recipe.fingerprint(recipe) or Catalog.fingerprint(session.catalog) != Catalog.fingerprint(cat) or (bool(data.get("dirty", false)) and not session.is_dirty()):
		var recovered: Session = Session.new(cat)
		var accepted: Dictionary = recovered.replace_recipe(recipe)
		if not bool(accepted.get("ok", false)):
			return accepted
		if not bool(data.get("dirty", false)):
			recovered.mark_saved()
		if session.changed.is_connected(_on_session_changed):
			session.changed.disconnect(_on_session_changed)
		session = recovered
		_connect_session()
	_selected_opening_id = str(data.get("selected_opening_id", ""))
	_last_window_scope = str(data.get("window_scope", "global"))
	if _last_window_scope not in ARCHITECTURE_WINDOW_SCOPES:
		_last_window_scope = "global"
	_opening_cache = data.get("opening_cache", {}).duplicate(true)
	_refresh_from_session()
	var ui_patch: Dictionary = data.get("ui_patch", {}) as Dictionary
	_ignore_fields = true
	if ui_patch.has("building_id"):
		_id_edit.text = str(ui_patch["building_id"])
	if ui_patch.has("display_name"):
		_name_edit.text = str(ui_patch["display_name"])
	for key: String in PARAMETER_KEYS:
		if ui_patch.has(key):
			_set_control_value(key, ui_patch[key])
	var bindings: Dictionary = ui_patch.get("component_bindings", {}) as Dictionary
	for role: String in Recipe.COMPONENT_ROLES:
		if bindings.has(role):
			_set_option("binding_" + role, str(bindings[role]))
	var weights: Array = ui_patch.get("growth_weights", []) as Array
	if weights.size() == 3:
		_set_spin("growth_small", float(weights[0]))
		_set_spin("growth_medium", float(weights[1]))
		_set_spin("growth_large", float(weights[2]))
	var ui_values: Dictionary = data.get("ui_values", {}) as Dictionary
	for key: Variant in ui_values:
		if controls.has(key):
			_set_control_value(str(key), ui_values[key])
	_ignore_fields = false
	_last_export = data.get("last_export", {}).duplicate(true)
	_slot_cache = data.get("slot_cache", {}).duplicate(true)
	_selected_id = str(data.get("selected_slot", ""))
	_local_baseline = data.get("local_baseline", {}).duplicate(true)
	_select_page(clampi(int(data.get("page", 0)), 0, PAGES.size() - 1))
	refresh_preview()
	# 重建会重新同步选中槽和范围控件，最后还原草稿 UI 与基线。
	_ignore_fields = true
	for key: Variant in ui_values:
		if controls.has(key):
			_set_control_value(str(key), ui_values[key])
	if data.has("local_baseline"):
		_local_baseline = data.get("local_baseline", {}).duplicate(true)
	_ignore_fields = false
	_selected_opening_id = str(data.get("selected_opening_id", _selected_opening_id))
	_last_window_scope = str(data.get("window_scope", _last_window_scope))
	if _last_window_scope not in ARCHITECTURE_WINDOW_SCOPES:
		_last_window_scope = "global"
	_sync_window_selection(snapshot())
	preview.set_wireframe(bool(controls["wireframe"].button_pressed))
	preview.set_collision_overlay(bool(controls["collision_overlay"].button_pressed))
	_update_state()
	_set_status("连续实体草稿已恢复；缺失内置组件已检查，原有替件保持。")
	return {"ok": true, "reason": "编辑器草稿已恢复"}

func _build_ui() -> void:
	set_meta("cozy_skip", true)
	add_theme_color_override("font_color", WORKSHOP_TEXT)
	var background := ColorRect.new()
	background.name = "WorkshopThemeBackground"
	background.color = WORKSHOP_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_meta("cozy_skip", true)
	add_child(background)
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	# 生成操作固定在所有滚动区域之外，窄屏和参数页滚到底仍可直接点击。
	var generate_bar: HBoxContainer = HBoxContainer.new()
	generate_bar.name = "FixedGenerateBar"
	root.add_child(generate_bar)
	var generate: Button = _button("应用参数并生成楼房", "generate")
	generate.custom_minimum_size = Vector2(300, 54)
	generate.add_theme_font_size_override("font_size", 18)
	generate_bar.add_child(generate)
	generate_bar.add_child(_label("连续实体 · 基础框架 / 门窗 / 构架 / 形体在左侧编辑"))
	var toolbar_scroll: ScrollContainer = ScrollContainer.new()
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toolbar_scroll.custom_minimum_size.y = 50
	toolbar_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(toolbar_scroll)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar_scroll.add_child(toolbar)
	var toolbar_title: Label = _label("老王场景工坊", 19)
	toolbar_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	toolbar_title.custom_minimum_size.x = 80
	toolbar.add_child(toolbar_title)
	for spec: Array in [["apply", "应用全部参数"], ["new", "新建"], ["open", "打开"], ["save", "保存并烘焙"], ["undo", "撤销"], ["redo", "重做"], ["open_scene", "在3D打开"], ["copy_sample", "复制样例"], ["save_as", "另存新ID"], ["toggle_left", "参数栏"], ["toggle_right", "槽位栏"]]:
		toolbar.add_child(_button(str(spec[1]), str(spec[0])))
	_build_top_identity_and_modules(root)
	state_label = _label("未保存")
	root.add_child(state_label)
	var outer_scroll: ScrollContainer = ScrollContainer.new()
	outer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(outer_scroll)
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 285
	outer_scroll.add_child(split)
	_left_panel = _make_left_panel()
	split.add_child(_left_panel)
	var inner: HSplitContainer = HSplitContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.split_offset = 390
	split.add_child(inner)
	var preview_body: VBoxContainer = VBoxContainer.new()
	preview_body.custom_minimum_size.x = 380
	preview_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(preview_body)
	var views: HBoxContainer = HBoxContainer.new()
	preview_body.add_child(views)
	for pair: Array in [["front", "正面"], ["back", "背面"], ["top", "俯视"], ["perspective", "透视"]]:
		views.add_child(_button(str(pair[1]), "view_" + str(pair[0])))
	preview = Preview.new()
	preview.name = "EditorWorkshopPreview"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.slot_selected.connect(select_slot)
	preview_body.add_child(preview)
	var overlays: HBoxContainer = HBoxContainer.new()
	preview_body.add_child(overlays)
	var wire: CheckButton = _check("线框", "wireframe", overlays)
	wire.toggled.connect(func(value: bool) -> void: preview.set_wireframe(value))
	var collision: CheckButton = _check("实际碰撞", "collision_overlay", overlays)
	collision.toggled.connect(func(value: bool) -> void: preview.set_collision_overlay(value))
	preview_body.add_child(_label("左键点选 / 拖动旋转；滚轮缩放。窄屏可折叠两侧栏。"))
	_right_panel = _make_right_panel()
	inner.add_child(_right_panel)
	var path_label: Label = _label("保存路径：" + export_root + " / <building_id> / revision_NNNN")
	controls["export_root_label"] = path_label
	root.add_child(path_label)
	root.add_child(_label("共享512×512色盘 · SEA_Matte / SEA_Metal / SEA_Gloss / SEA_Emission · UV选色，材质控制质感"))
	root.add_child(_label("五件 bundle 仅为候选资产，尚未正式登记；不替换当前编辑场景或主场景。"))
	status_panel = PanelContainer.new()
	status_panel.name = "WorkshopStatusPanel"
	status_panel.add_theme_stylebox_override("panel", _stylebox(Color("#203b50"), WORKSHOP_ACCENT, 7, 2))
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	status_panel.add_child(status_row)
	status_label = _label("编辑器独立主屏；无需运行游戏。", 16)
	status_label.custom_minimum_size.y = 46
	status_row.add_child(status_label)
	status_copy_button = _button("复制提示", "copy_status")
	status_copy_button.custom_minimum_size = Vector2(128, 46)
	status_row.add_child(status_copy_button)
	root.add_child(status_panel)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "未保存修改"
	_confirm.ok_button_text = "丢弃并继续"
	_confirm.cancel_button_text = "取消，保留草稿"
	_confirm.confirmed.connect(_confirm_discard)
	_confirm.canceled.connect(_cancel_discard)
	_confirm.get_cancel_button().pressed.connect(_cancel_discard)
	add_child(_confirm)
	_save_as_dialog = ConfirmationDialog.new()
	_save_as_dialog.title = "另存为新建筑"
	_save_as_dialog.ok_button_text = "保存新建筑"
	_save_as_dialog.cancel_button_text = "取消"
	var save_body: VBoxContainer = VBoxContainer.new()
	_save_as_dialog.add_child(save_body)
	save_body.add_child(_label("输入不同的 building_id；原建筑和历史版本不会被覆盖。"))
	_save_as_id = LineEdit.new()
	_save_as_id.custom_minimum_size.x = 360
	save_body.add_child(_save_as_id)
	_save_as_dialog.confirmed.connect(_save_as_confirmed)
	add_child(_save_as_dialog)
	_file_dialog = FileDialog.new()
	_file_dialog.title = "打开项目内楼房配方"
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.recipe.json ; 楼房编辑配方"])
	_file_dialog.file_selected.connect(func(path: String) -> void: open_recipe(path))
	add_child(_file_dialog)
	_component_dialog = FileDialog.new()
	_component_dialog.title = "选择静态组件 PackedScene"
	_component_dialog.access = FileDialog.ACCESS_RESOURCES
	_component_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_component_dialog.filters = PackedStringArray(["*.tscn ; 静态组件场景"])
	_component_dialog.file_selected.connect(_replace_component_selected)
	add_child(_component_dialog)

func _build_top_identity_and_modules(root: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "WorkshopTopInfo"
	panel.add_theme_stylebox_override("panel", _stylebox(WORKSHOP_SURFACE, WORKSHOP_ACCENT, 8, 2))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 8)
	var identity_title := _label("当前建筑", 17)
	identity_title.custom_minimum_size.x = 92
	identity_row.add_child(identity_title)
	identity_row.add_child(_label("building_id", 15))
	_id_edit = LineEdit.new()
	_id_edit.name = "building_id"
	_id_edit.custom_minimum_size = Vector2(210, 40)
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_edit.add_theme_font_size_override("font_size", 18)
	_id_edit.add_theme_stylebox_override("normal", _stylebox(Color("#0d1726"), WORKSHOP_LINE, 5))
	_id_edit.add_theme_stylebox_override("focus", _stylebox(Color("#14263a"), WORKSHOP_GOLD, 5, 2))
	_id_edit.text_changed.connect(_on_text_changed)
	identity_row.add_child(_id_edit)
	identity_row.add_child(_label("名称", 15))
	_name_edit = LineEdit.new()
	_name_edit.name = "display_name"
	_name_edit.custom_minimum_size = Vector2(220, 40)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.add_theme_stylebox_override("normal", _stylebox(Color("#0d1726"), WORKSHOP_LINE, 5))
	_name_edit.add_theme_stylebox_override("focus", _stylebox(Color("#14263a"), WORKSHOP_GOLD, 5, 2))
	_name_edit.text_changed.connect(_on_text_changed)
	identity_row.add_child(_name_edit)
	body.add_child(identity_row)
	var module_title := _label("模块", 16)
	module_title.custom_minimum_size.y = 24
	body.add_child(module_title)
	var module_row := HFlowContainer.new()
	module_row.name = "WorkshopTopModuleBar"
	module_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	module_row.add_theme_constant_override("h_separation", 5)
	module_row.add_theme_constant_override("v_separation", 5)
	for index: int in PAGES.size():
		var module_button := _button(PAGES[index], "module_%02d" % index)
		module_button.custom_minimum_size = Vector2(82, 38)
		module_button.add_theme_font_size_override("font_size", 16)
		module_button.pressed.connect(_select_page.bind(index))
		module_row.add_child(module_button)
	body.add_child(module_row)
	var default_title := _label("默认模组 · 点击即可载入", 16)
	default_title.custom_minimum_size.y = 24
	body.add_child(default_title)
	var defaults_row := HFlowContainer.new()
	defaults_row.name = "WorkshopDefaultModules"
	defaults_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defaults_row.add_theme_constant_override("h_separation", 6)
	defaults_row.add_theme_constant_override("v_separation", 5)
	for index: int in DEFAULT_MODULES.size():
		var item: Dictionary = DEFAULT_MODULES[index]
		var default_button := _button(str(item.label) + " · " + str(item.description), "default_module_%02d" % index)
		default_button.custom_minimum_size = Vector2(150, 38)
		default_button.add_theme_font_size_override("font_size", 15)
		default_button.tooltip_text = "直接载入「%s」；当前未保存修改会先询问" % str(item.label)
		defaults_row.add_child(default_button)
	body.add_child(defaults_row)
	root.add_child(panel)

func _make_left_panel() -> ScrollContainer:
	var scroll: ScrollContainer = _sidebar()
	var body: VBoxContainer = _sidebar_body(scroll)
	body.add_child(_label("当前模块参数", 16))
	body.add_child(_label("左侧只放当前模块的可编辑参数；建筑身份、模块入口和默认模组已移到顶部。", 12))
	_page_picker = OptionButton.new()
	_page_picker.add_theme_font_size_override("font_size", 18)
	for page_name: String in PAGES:
		_page_picker.add_item(page_name)
	_page_picker.item_selected.connect(_select_page)
	_page_picker.visible = false
	body.add_child(_page_picker)
	for page_name: String in PAGES:
		var page: VBoxContainer = VBoxContainer.new()
		page.visible = page_name == PAGES[0]
		body.add_child(page)
		pages[page_name] = page
		_build_page(page_name, page)
	return scroll

func _build_page(page_name: String, page: VBoxContainer) -> void:
	match page_name:
		"结构":
			_add_option(page, "construction_mode", "建模内核", [["shell_v2", "连续实体 · 工整模型"], ["modular_v1", "旧版拼装 · 配方兼容"]])
			# 旧文档解析仍留在内核，作者界面不再暴露内核切换或旧版方案。
			(controls["construction_mode"] as OptionButton).hide()
			(controls["construction_mode"] as Control).get_parent().get_child((controls["construction_mode"] as Control).get_index() - 1).hide()
			(controls["construction_mode"] as OptionButton).item_selected.connect(_construction_mode_changed)
			page.add_child(_label("基础框架 · 连续实体", 16))
			page.add_child(_label("连续墙壳／真实洞口／整板屋顶。完成左侧参数后，点击顶部生成按钮。", 12))
			_add_option(page, "shape", "形状", [["rectangle", "矩形"], ["l", "L 形"]])
			# shape 仅保留历史绑定，统一使用下方四种结构形态，避免两处选项互相覆盖。
			(controls["shape"] as Control).hide()
			(controls["shape"] as Control).get_parent().get_child((controls["shape"] as Control).get_index() - 1).hide()
			(controls["shape"] as OptionButton).item_selected.connect(func(_index: int) -> void: _refresh_roof_edge_options(_option_value("shape")))
			for spec: Array in [["width", "宽度 m", 6, 24, 0.1], ["depth", "进深 m", 6, 20, 0.1], ["floors", "楼层", 1, 8, 1], ["floor_height", "层高 m", 1, 20, 0.1], ["wall_thickness", "墙厚 m", 0.01, 2, 0.01], ["slab_thickness", "板厚 m", 0.01, 2, 0.01], ["column_width", "柱宽 m", 0.01, 2, 0.01]]:
				_spin_spec(page, spec)
			var plan_panel: VBoxContainer = _architecture_panel(page, "architecture_plan_panel")
			plan_panel.add_child(_label("连续实体建筑架构", 16))
			_add_option(plan_panel, "architecture_shape_variant", "结构形态", [["rectangle", "矩形"], ["l", "L 形"], ["t", "T 形"], ["u", "U 形"]])
			(controls["architecture_shape_variant"] as OptionButton).item_selected.connect(_architecture_shape_changed)
			for spec: Array in [["wing_x", "翼部 X 比例", 0.25, 0.75, 0.01], ["wing_z", "翼部 Z 比例", 0.25, 0.75, 0.01], ["setback_start", "退台起始层", -1, 7, 1], ["setback_step", "退台步长", 0.0, 1.2, 0.01]]:
				_spin_spec(plan_panel, spec)
			_add_option(plan_panel, "architecture_roof_mode", "屋顶结构", [["none", "无"], ["parapet", "女儿墙"], ["railing", "栏杆"], ["mixed", "女儿墙 + 栏杆"]])
			for spec: Array in [["architecture_roof_height", "围护总高", 0.4, 2.0, 0.01], ["architecture_roof_thickness", "女儿墙厚", 0.12, 0.6, 0.01], ["architecture_roof_cap_thickness", "压顶厚度", 0.06, 0.25, 0.01], ["architecture_roof_cap_overhang", "压顶外挑", 0.0, 0.15, 0.01], ["architecture_roof_post_spacing", "立柱间距", 0.5, 3.0, 0.01], ["architecture_roof_rail_spacing", "竖杆节距", 0.1, 0.6, 0.01], ["architecture_roof_bar_width", "杆件宽度", 0.02, 0.12, 0.01]]:
				_spin_spec(plan_panel, spec)
			_add_option(plan_panel, "architecture_roof_edge_index", "屋顶边", [["edge_0", "边 0"], ["edge_1", "边 1"], ["edge_2", "边 2"], ["edge_3", "边 3"]])
			_check("启用当前边覆盖", "architecture_roof_edge_override_enabled", plan_panel)
			_add_option(plan_panel, "architecture_roof_edge_mode", "边结构", [["none", "无"], ["parapet", "女儿墙"], ["railing", "栏杆"], ["mixed", "女儿墙 + 栏杆"]])
			for spec: Array in [["architecture_roof_gap_center", "边开口中心", 0.0, 1.0, 0.01], ["architecture_roof_gap_width", "边开口宽度", 0.0, 24.0, 0.01]]:
				_spin_spec(plan_panel, spec)
			plan_panel.add_child(_button("应用屋顶构造", "roof_apply"))
			plan_panel.add_child(_button("清除当前边覆盖", "roof_clear"))
			(controls["architecture_roof_edge_index"] as OptionButton).item_selected.connect(_architecture_roof_edge_changed)
		"门窗":
			var window_panel: VBoxContainer = _architecture_panel(page, "architecture_window_panel")
			window_panel.add_child(_label("当前架构窗构造", 16))
			_add_option(window_panel, "window_scope", "应用范围", [["global", "全局"], ["floor", "当前楼层"], ["facade", "当前立面"], ["single", "当前窗"]])
			(controls["window_scope"] as OptionButton).item_selected.connect(_window_scope_changed)
			_add_option(window_panel, "window_selection", "当前窗口", [])
			(controls["window_selection"] as OptionButton).item_selected.connect(_window_selection_changed)
			_check("启用窗洞", "architecture_window_enabled", window_panel)
			_add_option(window_panel, "architecture_window_type", "窗型", [["fixed", "固定窗"], ["casement_left", "左开窗"], ["casement_right", "右开窗"], ["awning", "上悬窗"]])
			for spec: Array in [["architecture_window_open_angle", "开启角度", 0.0, 80.0, 1.0], ["architecture_window_frame_width", "框宽", 0.04, 0.40, 0.001], ["architecture_window_frame_depth", "框深", 0.04, 0.60, 0.001], ["architecture_window_glass_thickness", "玻璃厚度", 0.005, 0.10, 0.001], ["architecture_window_recess", "窗框退入（负值外移）", -0.50, 0.50, 0.01], ["architecture_window_width", "架构窗宽", 0.25, 6.0, 0.01], ["architecture_window_height", "架构窗高", 0.25, 6.0, 0.01], ["architecture_window_sill", "架构窗台", 0.2, 5.0, 0.01]]:
				_spin_spec(window_panel, spec)
			_check("启用窗沿板", "architecture_window_sill_enabled", window_panel)
			for spec: Array in [["architecture_window_sill_projection", "窗沿外挑", 0.0, 10.0, 0.01], ["architecture_window_sill_thickness", "窗沿厚度", 0.001, 2.0, 0.001], ["architecture_window_sill_extension", "窗沿延伸", 0.0, 2.0, 0.01]]:
				_spin_spec(window_panel, spec)
			var limit_hint: Label = _label("窗参数拖动自动预览，无需点击应用。", 12)
			controls["window_limit_hint"] = limit_hint
			window_panel.add_child(limit_hint)
			window_panel.add_child(_button("重试当前范围窗构造", "architecture_apply"))
			window_panel.add_child(_button("清除此范围覆盖", "architecture_clear"))
			window_panel.add_child(_button("重试当前窗", "window_apply"))
			for key: String in ["architecture_window_enabled", "architecture_window_sill_enabled"]:
				_architecture_visibility.append(key)
			for key: String in ["architecture_window_enabled", "architecture_window_sill_enabled"]:
				(controls[key] as CheckButton).toggled.connect(func(_enabled: bool) -> void: _queue_window_preview(key))
			(controls["architecture_window_type"] as OptionButton).item_selected.connect(func(_index: int) -> void: _queue_window_preview("architecture_window_type"))
			page.add_child(_label("窗滑块自动预览；基础窗只改全局，楼层/立面滑块只改对应范围，其他输入不连带提交。", 12))
			for spec: Array in [["window_width", "窗宽", 0.1, 10, 0.1], ["window_height", "窗高", 0.1, 10, 0.1], ["window_sill", "窗台", 0.01, 10, 0.01], ["bay_width", "开间", 2, 6, 0.1], ["door_width", "门净宽", 0.1, 10, 0.1], ["door_height", "门净高", 0.1, 10, 0.1]]:
				_spin_spec(page, spec)
			page.add_child(_label("逐层覆盖（索引从0开始）", 16))
			for spec: Array in [["floor_override_index", "层索引", 0, 7, 1], ["floor_override_height", "层高", 0.1, 20, 0.1], ["floor_override_window_width", "窗宽", 0.1, 10, 0.1], ["floor_override_window_height", "窗高", 0.1, 10, 0.1], ["floor_override_sill", "窗台", 0.01, 10, 0.1]]:
				_spin_spec(page, spec)
			page.add_child(_button("应用楼层覆盖", "floor_apply"))
			page.add_child(_button("清除楼层覆盖", "floor_clear"))
			page.add_child(_label("逐立面覆盖", 16))
			_add_option(page, "facade_index", "立面", [["front", "正面"], ["back", "背面"], ["left", "左侧"], ["right", "右侧"]])
			_check("显示窗洞", "facade_windows", page)
			for spec: Array in [["facade_width", "窗宽", 0.1, 10, 0.1], ["facade_height", "窗高", 0.1, 10, 0.1], ["facade_sill", "窗台", 0.01, 10, 0.1]]:
				_spin_spec(page, spec)
			page.add_child(_button("应用立面覆盖", "facade_apply"))
			page.add_child(_button("清除立面覆盖", "facade_clear"))
			var label: Label = _label("无局部覆盖")
			controls["override_status"] = label
			page.add_child(label)
			controls["floor_override_index"].value_changed.connect(func(_value: float) -> void: _window_target_changed(true))
			controls["facade_index"].item_selected.connect(func(_index: int) -> void: _window_target_changed(false))
			(controls["facade_windows"] as CheckButton).toggled.connect(func(_enabled: bool) -> void: _queue_window_preview("facade_windows"))
		"配色":
			_build_palette_page(page)
		"破旧":
			page.add_child(_label("老化改变墙面色格并生成斑驳；门窗破损产生真实玻璃破口和门下缘缺口。不改变承重墙或楼板。", 12))
			for spec: Array in [["aging", "表面老化", 0, 1, 0.01], ["damage", "门窗破损", 0, 1, 0.01], ["bevel_segments", "倒角段数", 1, 8, 1], ["bevel_width", "倒角宽", 0.001, 0.5, 0.001]]:
				_spin_spec(page, spec)
			page.add_child(_button("应用破旧并生成", "damage_apply"))
			page.add_child(_label("破损种子控制缺口差异；0为完整门窗。承重墙破洞与残楼尚未实现。"))
		"植物":
			_check("植物 / 树枝随机变化", "vegetation_random_enabled", page).toggled.connect(func(_enabled: bool) -> void: _queue_window_preview("vegetation_random_enabled"))
			for spec: Array in [["vegetation_variation", "随机幅度", 0, 1, 0.01], ["vegetation_seed", "植物种子", 0, 2147483647, 1], ["vegetation_density", "植物密度", 0, 1, 0.01], ["growth_small", "小型权重", 0, 1, 0.01], ["growth_medium", "中型权重", 0, 1, 0.01], ["growth_large", "大型权重", 0, 1, 0.01]]:
				_spin_spec(page, spec)
			page.add_child(_label("拖动自动预览。最大幅度：位置±0.25m、尺寸±20%、朝向±180°。关闭随机后seed不影响植物；幅度0仅关闭姿态扰动，密度及三档权重仍生效。檐边藤蔓和锁定槽不偏移。", 12))
			page.add_child(_label("植物品种在右侧全局绑定选择；锁定与排除针对选中槽位。"))
		"空间":
			_add_option(page, "spatial_profile", "空间职责", [["above_water", "水上功能"], ["scenic_underwater", "水下观赏"], ["dive_static", "潜水静态"]])
			_spin_spec(page, ["taper", "收分", 0, 0.1, 0.01])
			for pair: Array in [["structure_seed", "结构种子"], ["damage_seed", "破损种子"]]:
				_spin_spec(page, [pair[0], pair[1], 0, 2147483647, 1])
			page.add_child(_label("水下观赏无碰撞、导航或玩法功能；不会自动接入正式世界。"))
		"构架":
			var frame_panel: VBoxContainer = _architecture_panel(page, "architecture_frame_panel")
			frame_panel.add_child(_label("承重柱与楼层腰线", 16))
			frame_panel.add_child(_label("柱是贴墙的竖向结构件，咬入墙体；腰线是楼层处整圈凸出的水平线条。两项各自独立开关。", 12))
			_check("承重柱", "pilaster_enabled", frame_panel)
			_check("  转角/边缘柱", "pilaster_corner", frame_panel)
			_check("  窗间中间柱", "pilaster_middle", frame_panel)
			_spin_spec(frame_panel, ["pilaster_width", "柱宽（米）", float(Config.PILASTER_BOUNDS["width"][0]), float(Config.PILASTER_BOUNDS["width"][1]), 0.02])
			_spin_spec(frame_panel, ["pilaster_projection", "柱凸出墙面（米）", float(Config.PILASTER_BOUNDS["projection"][0]), float(Config.PILASTER_BOUNDS["projection"][1]), 0.01])
			_spin_spec(frame_panel, ["pilaster_bite", "柱咬入墙体（米）", float(Config.PILASTER_BOUNDS["bite"][0]), float(Config.PILASTER_BOUNDS["bite"][1]), 0.01])
			_check("楼层腰线", "band_enabled", frame_panel)
			_spin_spec(frame_panel, ["band_projection", "腰线凸出（米）", float(Config.BAND_BOUNDS["projection"][0]), float(Config.BAND_BOUNDS["projection"][1]), 0.01])
			_spin_spec(frame_panel, ["band_thickness", "腰线厚度（米）", float(Config.BAND_BOUNDS["thickness"][0]), float(Config.BAND_BOUNDS["thickness"][1]), 0.02])
			frame_panel.add_child(_button("应用构架", "frame_apply"))
			frame_panel.add_child(_label("腰线始终收在柱侧：柱比腰线凸出，腰线只在窗间可见、到柱边干净收头。顶层的檐口由女儿墙压顶负责，不重复生成腰线。", 12))
			frame_readout_label = _label("", 12)
			frame_panel.add_child(frame_readout_label)
		"形体":
			var form_panel: VBoxContainer = _architecture_panel(page, "architecture_form_panel")
			form_panel.add_child(_label("形体变形 · 随机幅度", 16))
			form_panel.add_child(_label("给区间和种子，落值由种子稳定决定：同种子永远同模型。ρ = 1 − 上口/下口，正为上小下大。", 12))
			_check("启用形体变形", "form_enabled", form_panel)
			_add_option(form_panel, "form_preset", "强度档位", [["SF-A", "SF-A 克制"], ["SF-B", "SF-B 标准"], ["SF-C", "SF-C 强风格"]])
			(controls["form_preset"] as OptionButton).item_selected.connect(_form_preset_changed)
			_spin_spec(form_panel, ["form_seed", "随机种子", 0, 999999, 1])
			_spin_spec(form_panel, ["form_max_tilt", "墙倾角上限（度）", float(Config.TILT_BOUNDS[0]), float(Config.TILT_BOUNDS[1]), 0.5])
			_add_option(form_panel, "form_opening_sign", "窗洞取号", [["positive", "统一上窄下宽"], ["negative", "统一上宽下窄"], ["mixed", "混合（逐个窗独立）"]])
			for category: String in FORM_CATEGORIES:
				form_panel.add_child(_label(str(FORM_LABELS[category]) + " 幅度区间", 14))
				var bounds: Array = Config.FORM_BOUNDS[category]
				_spin_spec(form_panel, ["form_" + category + "_min", "下限 ρ", float(bounds[0]), float(bounds[1]), 0.001])
				_spin_spec(form_panel, ["form_" + category + "_max", "上限 ρ", float(bounds[0]), float(bounds[1]), 0.001])
			form_panel.add_child(_button("应用形体", "form_apply"))
			form_panel.add_child(_button("换一个种子", "form_reroll"))
			form_readout_label = _label("", 12)
			form_panel.add_child(form_readout_label)
			page.add_child(_label("结构收分受墙倾角约束：上限 = tan(倾角) × 总高 / 最大面宽。墙越宽、层越矮可用幅度越小；调大倾角上限即可得到更大的收口。SKILL 建议 4°，默认给 8°。", 12))
		"文件":
			page.add_child(_label("本项目已保存建筑", 16))
			_saved_list = ItemList.new()
			_saved_list.custom_minimum_size = Vector2(0, 155)
			_saved_list.item_activated.connect(func(index: int) -> void: _open_saved_index(index))
			page.add_child(_saved_list)
			page.add_child(_button("打开选中建筑", "open_saved"))
			page.add_child(_button("刷新建筑列表", "refresh_documents"))
			page.add_child(_button("浏览项目配方…", "browse_recipe"))
			page.add_child(_label("版本化样例", 16))
			_sample_picker = OptionButton.new()
			_sample_picker.clip_text = true
			page.add_child(_sample_picker)
			page.add_child(_button("载入样例", "load_sample"))
			page.add_child(_label("载入样例后用「另存新ID」创建自己的楼房；样例源不被覆盖。"))

func _make_right_panel() -> ScrollContainer:
	var scroll: ScrollContainer = _sidebar()
	var body: VBoxContainer = _sidebar_body(scroll)
	body.add_child(_label("槽位 / 稳定 componentID", 16))
	selected_slot_label = _label("未选择槽位")
	body.add_child(selected_slot_label)
	_slot_list = ItemList.new()
	_slot_list.custom_minimum_size = Vector2(0, 175)
	_slot_list.item_selected.connect(func(index: int) -> void: select_slot(_slot_ids[index]))
	body.add_child(_slot_list)
	_add_option(body, "component_id", "选中槽组件", [])
	var disabled: CheckButton = _check("禁用此槽（真实开破口）", "disabled", body)
	disabled.toggled.connect(_disable_slot_toggled)
	for spec: Array in [["offset_x", "偏移 X", -10, 10, 0.05], ["offset_y", "偏移 Y", -10, 10, 0.05], ["offset_z", "偏移 Z", -10, 10, 0.05]]:
		_spin_spec(body, spec)
	_add_option(body, "growth_key", "植物生长档", [["small", "小型"], ["medium", "中型"], ["large", "大型"]])
	_check("锁定选中植物锚点", "vegetation_lock", body)
	body.add_child(_button("应用槽位修改", "slot_apply"))
	body.add_child(_button("恢复此槽默认值", "slot_restore"))
	body.add_child(_button("仅替换当前槽组件…", "replace_component"))
	body.add_child(_button("导出当前槽为独立模块", "export_module"))
	body.add_child(_label("仅当前槽生成独立 componentID，不替换全局同 ID。仅允许 res://scenes/components 下静态 tscn。"))
	body.add_child(_label("全局组件绑定", 16))
	for role: String in Recipe.COMPONENT_ROLES:
		_add_option(body, "binding_" + role, str(ROLE_LABELS[role]), [])
	body.add_child(_button("应用全部绑定与参数", "apply_bindings"))
	var stats: Label = _label("等待生成")
	controls["stats"] = stats
	body.add_child(stats)
	return scroll

func _architecture_panel(parent: Control, key: String) -> VBoxContainer:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = key
	panel.visible = false
	panel.add_theme_constant_override("separation", 6)
	parent.add_child(panel)
	architecture_panels.append(panel)
	return panel

func _sidebar() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.x = 285
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll

func _sidebar_body(scroll: ScrollContainer) -> VBoxContainer:
	var body: VBoxContainer = VBoxContainer.new()
	body.custom_minimum_size.x = 265
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	return body

func _stylebox(fill: Color, border: Color = WORKSHOP_LINE, radius: int = 6, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _apply_button_theme(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _stylebox(WORKSHOP_SURFACE, WORKSHOP_LINE, 6))
	button.add_theme_stylebox_override("hover", _stylebox(WORKSHOP_SURFACE_ALT, WORKSHOP_ACCENT, 6, 1))
	button.add_theme_stylebox_override("pressed", _stylebox(Color("#28506a"), WORKSHOP_ACCENT_HOVER, 6, 2))
	button.add_theme_stylebox_override("focus", _stylebox(Color("#1d3048"), WORKSHOP_GOLD, 6, 2))
	button.add_theme_stylebox_override("disabled", _stylebox(Color("#192331"), Color("#2a3a4b"), 6))
	button.add_theme_color_override("font_color", WORKSHOP_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", WORKSHOP_GOLD)
	button.add_theme_color_override("font_focus_color", WORKSHOP_GOLD)
	button.add_theme_color_override("font_disabled_color", WORKSHOP_MUTED)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 34.0)

func _apply_option_theme(option: OptionButton) -> void:
	option.add_theme_stylebox_override("normal", _stylebox(WORKSHOP_SURFACE, WORKSHOP_LINE, 5))
	option.add_theme_stylebox_override("hover", _stylebox(WORKSHOP_SURFACE_ALT, WORKSHOP_ACCENT, 5))
	option.add_theme_stylebox_override("focus", _stylebox(WORKSHOP_SURFACE_ALT, WORKSHOP_GOLD, 5, 2))
	option.add_theme_color_override("font_color", WORKSHOP_TEXT)
	option.add_theme_color_override("font_hover_color", Color.WHITE)
	option.add_theme_color_override("font_focus_color", WORKSHOP_GOLD)
	option.custom_minimum_size.y = maxf(option.custom_minimum_size.y, 32.0)

func _apply_slider_theme(slider: HSlider) -> void:
	var track := _stylebox(Color("#23364d"), WORKSHOP_LINE, 6)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := _stylebox(WORKSHOP_ACCENT, WORKSHOP_ACCENT_HOVER, 6)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var grab := _stylebox(WORKSHOP_GOLD, Color("#fff0b8"), 8, 1)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_stylebox_override("grabber", grab)
	slider.add_theme_color_override("font_color", WORKSHOP_TEXT)
	slider.custom_minimum_size = Vector2(220, 34)
	slider.focus_mode = Control.FOCUS_ALL

func _label(text: String, font_size: int = 14) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", maxi(font_size, 16))
	label.add_theme_color_override("font_color", WORKSHOP_GOLD if font_size >= 16 else WORKSHOP_MUTED)
	return label

func _button(text: String, id: String) -> Button:
	var button: Button = Button.new()
	button.name = id
	button.text = text
	button.add_theme_font_size_override("font_size", 18)
	_apply_button_theme(button)
	button.pressed.connect(_button_pressed.bind(id))
	buttons[id] = button
	return button

func _check(text: String, key: String, parent: Control) -> CheckButton:
	var check: CheckButton = CheckButton.new()
	check.name = key
	check.text = text
	check.add_theme_font_size_override("font_size", 18)
	check.add_theme_color_override("font_color", WORKSHOP_TEXT)
	check.add_theme_color_override("font_hover_color", Color.WHITE)
	check.custom_minimum_size.y = 30
	controls[key] = check
	parent.add_child(check)
	return check

func _add_option(parent: Control, key: String, title: String, options: Array) -> void:
	parent.add_child(_label(title))
	var option: OptionButton = OptionButton.new()
	option.name = key
	option.clip_text = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 18)
	_apply_option_theme(option)
	for pair: Array in options:
		option.add_item(str(pair[1]))
		option.set_item_metadata(option.item_count - 1, str(pair[0]))
	option.item_selected.connect(func(_index: int) -> void: _on_field_changed())
	controls[key] = option
	parent.add_child(option)

func _build_palette_page(page: VBoxContainer) -> void:
	page.add_child(_label("共享棋盘色板 · 8×8 / 64色", 16))
	page.add_child(_label("仅选择PaletteUV色格，不复制或修改材质球。部件覆盖优先于材质角色；外部prefab不重着色。", 12))
	var targets: Array = [["global", "全部原生材质"]]
	for slot: String in Config.PALETTE_SLOTS:
		targets.append(["slots:" + slot, str(ROLE_LABELS.get(slot, "腰线" if slot == "band" else "屋顶"))])
	for role: String in Config.PALETTE_ROLES:
		targets.append(["materials:" + role, "材质球 " + role])
	_add_option(page, "palette_target", "选色目标", targets)
	controls.palette_target.item_selected.connect(func(_index: int) -> void:
		flush_window_preview()
		_refresh_palette_controls())
	_add_option(page, "palette_mode", "选色模式", [["auto", "auto · 稳定自动"], ["manual", "manual · 手动选格"]])
	controls.palette_mode.item_selected.connect(func(_index: int) -> void: _palette_changed())
	_window_slider(page, ["palette_seed", "颜色种子", 0, 999999, 1], "")
	# 隐藏Range仅存手动格索引，纳入现有草稿恢复/原子预览字段捕获。
	var cell := HSlider.new()
	cell.max_value = 63
	cell.step = 1
	cell.hide()
	controls["palette_cell"] = cell
	page.add_child(cell)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	controls["palette_grid"] = grid
	var image: Image = (load(preload("res://src/workshop/mesh_builder.gd").TEXTURE_PATH) as Texture2D).get_image()
	for index: int in 64:
		var button := Button.new()
		button.name = "cell_%02d" % index
		button.custom_minimum_size = Vector2(30, 30)
		button.toggle_mode = true
		button.tooltip_text = "色格 [%d, %d] · %02d · 点击后实时预览" % [index / 8, index % 8, index]
		var style := StyleBoxFlat.new()
		style.bg_color = image.get_pixel((index % 8) * 64 + 32, (index / 8) * 64 + 32)
		style.set_border_width_all(1)
		style.border_color = Color(0.2, 0.2, 0.2)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		var selected: StyleBoxFlat = style.duplicate()
		selected.set_border_width_all(3)
		selected.border_color = Color.WHITE
		button.add_theme_stylebox_override("pressed", selected)
		button.add_theme_stylebox_override("disabled", style)
		button.pressed.connect(_palette_cell_clicked.bind(index))
		grid.add_child(button)
	page.add_child(grid)
	controls["palette_readout"] = _label("", 12)
	page.add_child(controls.palette_readout)
	_build_shading_controls(page)

func _build_shading_controls(page: VBoxContainer) -> void:
	page.add_child(_label("材质球与着色器实例参数", 16))
	page.add_child(_label("只编辑当前楼房实例，不改公共.tres、共享着色器或色板。颜色仍由PaletteUV决定；粗糙度/金属度/镜面/发光由材质角色实例参数决定。", 12))
	var roles: Array = []
	for role: String in Config.PALETTE_ROLES:
		roles.append([role, MATERIAL_ROLE_LABELS.get(role, role)])
	_add_option(page, "shading_role", "材质角色", roles)
	controls["shading_role"].item_selected.connect(func(_index: int) -> void:
		flush_window_preview()
		_refresh_shading_controls())
	for field: String in MATERIAL_EDIT_FIELDS:
		var bounds: Array = MATERIAL_EDIT_BOUNDS[field]
		_window_slider(page, ["shading_" + field, str(MATERIAL_EDIT_LABELS[field]), bounds[0], bounds[1], bounds[2]], "")
	controls["shading_roughness"].value_changed.connect(func(_value: float) -> void: _queue_window_preview("shading_settings"))
	controls["shading_metallic"].value_changed.connect(func(_value: float) -> void: _queue_window_preview("shading_settings"))
	controls["shading_specular"].value_changed.connect(func(_value: float) -> void: _queue_window_preview("shading_settings"))
	controls["shading_emission_energy"].value_changed.connect(func(_value: float) -> void: _queue_window_preview("shading_settings"))
	controls["shading_transparency"].value_changed.connect(func(_value: float) -> void: _queue_window_preview("shading_settings"))
	var material_hint := _label("合规范围：Matte哑光为主；Metal只用于栏杆/边框；Gloss用于玻璃；Emission只用于灯/屏幕。结构union包含多个角色时保持共享默认，避免一个节点参数覆盖多个surface。", 12)
	controls["shading_hint"] = material_hint
	page.add_child(material_hint)

func _shading_control_settings() -> Dictionary:
	var result: Dictionary = {}
	for field: String in MATERIAL_EDIT_FIELDS:
		result[field] = _spin_value("shading_" + field)
	return result

func _refresh_shading_controls() -> void:
	if not controls.has("shading_role"): return
	var role: String = _option_value("shading_role")
	var shading: Dictionary = _architecture_snapshot().get("shading", {})
	var values: Dictionary = MATERIAL_ROLE_DEFAULTS.get(role, {})
	values = values.duplicate(true)
	values.merge(shading.get("materials", {}).get(role, {}), true)
	var ignored: bool = _ignore_fields
	_ignore_fields = true
	var role_bounds: Dictionary = Config.SHADING_ROLE_BOUNDS.get(role, {})
	for field: String in MATERIAL_EDIT_FIELDS:
		var slider: HSlider = controls["shading_" + field] as HSlider
		var bounds: Array = role_bounds.get(field, MATERIAL_EDIT_BOUNDS[field])
		slider.min_value = float(bounds[0])
		slider.max_value = float(bounds[1])
		slider.editable = not is_equal_approx(float(bounds[0]), float(bounds[1]))
		_set_spin("shading_" + field, float(values.get(field, MATERIAL_ROLE_DEFAULTS[role][field])))
	_ignore_fields = ignored

func _shading_snapshot() -> Dictionary:
	var shading: Dictionary = _architecture_snapshot().get("shading", {}).duplicate(true)
	if not shading.has("materials"): shading["materials"] = {}
	var role: String = _option_value("shading_role")
	shading.materials[role] = _shading_control_settings()
	return shading

func _palette_changed() -> void:
	if _ignore_fields: return
	_queue_window_preview("palette_settings")
	_update_palette_grid()

func _palette_cell_clicked(index: int) -> void:
	# 直接点色格就是最短路径：自动模式下自动切换到手动，不要求用户先找下拉框。
	if _option_value("palette_mode") != "manual":
		_set_option("palette_mode", "manual")
	_set_spin("palette_cell", index)
	_palette_changed()
	_set_status("已选择色格 [%d, %d]，正在实时预览…" % [index / 8, index % 8], WORKSHOP_ACCENT_HOVER)

func _palette_control_settings() -> Dictionary:
	var index: int = int(_spin_value("palette_cell"))
	return {"color_mode": _option_value("palette_mode"), "color_seed": int(_spin_value("palette_seed")), "color_cell": [index / 8, index % 8]}

func _refresh_palette_controls() -> void:
	if not controls.has("palette_target"): return
	var palette: Dictionary = _architecture_snapshot().palette
	var target: PackedStringArray = _option_value("palette_target").split(":")
	var entry: Dictionary = palette.duplicate(true)
	entry.erase("slots")
	entry.erase("materials")
	if target.size() == 2:
		var role: String = target[1] if target[0] == "materials" else ("SEA_Gloss" if target[1] == "glass" else "SEA_Matte")
		entry.merge(palette.get("materials", {}).get(role, {}), true)
		if target[0] == "slots": entry.merge(palette.get("slots", {}).get(target[1], {}), true)
	var ignored: bool = _ignore_fields
	_ignore_fields = true
	_set_option("palette_mode", str(entry.get("color_mode", "auto")))
	_set_spin("palette_seed", float(entry.get("color_seed", 11010)))
	var cell: Array = entry.get("color_cell", [0, 0])
	_set_spin("palette_cell", int(cell[0]) * 8 + int(cell[1]))
	_ignore_fields = ignored
	_update_palette_grid()

func _update_palette_grid() -> void:
	if not controls.has("palette_grid"): return
	var settings: Dictionary = _palette_control_settings()
	var target: String = _option_value("palette_target")
	var role: String = target.trim_prefix("materials:") if target.begins_with("materials:") else ("SEA_Gloss" if target == "slots:glass" else "SEA_Matte")
	var id: String = _selected_id
	var slot: String = target.trim_prefix("slots:")
	if target == "global": slot = "wall"
	if id.is_empty() or target.begins_with("slots:"):
		id = {"wall": "wall_shell_0", "pillar": "pilaster_0_c0", "band": "band_0_0", "frame": "frame_front_0_1", "glass": "glass_front_0_1", "plant": "plant_0", "slab": "slab_0", "roof": "roof_main"}.get(slot, "wall_shell_0")
	# 优先显示当前目标的真实生成槽；自动不是只画一个与模型无关的随机格。
	for actual_id: String in _slot_cache:
		var actual: Dictionary = _slot_cache[actual_id]
		var actual_kind: String = str(actual.get("kind", ""))
		if actual_id.begins_with("band_") or actual_id.begins_with("belt_") or actual_id.begins_with("plinth_"): actual_kind = "band"
		if actual_id == "roof_main": actual_kind = "roof"
		var actual_role: String = str(session.catalog.components.get(str(actual.get("component_id", "")), {}).get("material_role", "SEA_Gloss" if actual_kind == "glass" else "SEA_Matte"))
		if (target.begins_with("slots:") and actual_kind == slot) or (target.begins_with("materials:") and actual_role == role) or target == "global":
			id = actual_id
			role = actual_role
			break
	var cell: Array = Config.palette_cell(settings, id, role)
	var selected: int = int(cell[0]) * 8 + int(cell[1])
	for index: int in 64:
		var button: Button = controls.palette_grid.get_child(index)
		button.set_pressed_no_signal(index == selected)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
	(controls.palette_readout as Label).text = "%s：[%d,%d] / %d\n自动落点示例 %s · %s；实际每槽按稳定ID取格。16px内缩（不低于8px）。" % [settings.color_mode, cell[0], cell[1], selected, id, role]

func _window_numeric_field(key: String) -> String:
	if key.begins_with("architecture_window_"):
		return key.trim_prefix("architecture_window_")
	return {"window_width": "width", "window_height": "height", "window_sill": "sill", "floor_override_window_width": "width", "floor_override_window_height": "height", "floor_override_sill": "sill", "facade_width": "width", "facade_height": "height", "facade_sill": "sill", "facade_windows": "enabled"}.get(key, "")

func _spin_spec(parent: Control, spec: Array) -> void:
	var key: String = str(spec[0])
	var field: String = _window_numeric_field(key)
	if Config.WINDOW_BOUNDS.has(field) or key == "bay_width" or VEGETATION_KEYS.has(key):
		_window_slider(parent, spec, field)
		return
	_range_slider(parent, spec)

func _range_slider(parent: Control, spec: Array) -> void:
	_build_slider(parent, spec, [float(spec[2]), float(spec[3])], false, "")

func _window_slider(parent: Control, spec: Array, field: String) -> void:
	var key: String = str(spec[0])
	var bounds: Array = Config.WINDOW_BOUNDS.get(field, [spec[2], spec[3]])
	_build_slider(parent, spec, bounds, true, field)

func _build_slider(parent: Control, spec: Array, bounds: Array, realtime: bool, field: String) -> void:
	var key: String = str(spec[0])
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	var 	readout: Label = _label("", 15)
	body.add_child(readout)
	var slider: HSlider = HSlider.new()
	slider.name = key
	slider.min_value = float(bounds[0])
	slider.max_value = float(bounds[1])
	var slider_step: float = float(spec[4])
	if realtime and field == "open_angle":
		slider_step = 1.0
	elif realtime and field in ["glass_thickness", "frame_width", "frame_depth", "sill_thickness"]:
		slider_step = 0.001
	slider.step = slider_step
	slider.allow_greater = false
	slider.allow_lesser = false
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_slider_theme(slider)
	controls[key] = slider
	_range_readouts[key] = {"label": readout, "title": str(spec[1]), "step": slider_step}
	slider.value_changed.connect(func(_value: float) -> void:
		_update_range_readout(key)
		if realtime:
			if key.begins_with("shading_"):
				_queue_window_preview("shading_settings")
			else:
				_sync_window_dimension(key)
				if key == "palette_seed": _palette_changed()
				else: _queue_window_preview(key)
		else:
			_set_status("已调整「%s」，点击顶部生成按钮预览" % str(spec[1]))
		_on_field_changed())
	if realtime:
		slider.drag_started.connect(func() -> void:
			_window_drag_key = key
			_window_history_key = "")
		slider.drag_ended.connect(func(_changed: bool) -> void:
			_window_drag_key = ""
			if not _window_preview_keys.is_empty():
				_window_preview_timer.start(0.01)
			else:
				_window_history_key = "")
	body.add_child(slider)
	parent.add_child(body)
	_update_range_readout(key)

func _update_range_readout(key: String) -> void:
	if not _range_readouts.has(key): return
	var entry: Dictionary = _range_readouts[key]
	var slider: Range = controls[key] as Range
	var step: float = float(entry.get("step", slider.step))
	var decimals: int = 0 if step >= 1.0 else (2 if step >= 0.01 else 3)
	var current: String = str(int(roundi(slider.value))) if decimals == 0 else String.num(slider.value, decimals)
	var minimum: String = str(int(roundi(slider.min_value))) if decimals == 0 else String.num(slider.min_value, decimals)
	var maximum: String = str(int(roundi(slider.max_value))) if decimals == 0 else String.num(slider.max_value, decimals)
	(entry.label as Label).text = "%s  %s    [%s – %s]" % [entry.title, current, minimum, maximum]

func _reset_window_preview() -> void:
	if _window_preview_timer != null: _window_preview_timer.stop()
	_window_preview_keys.clear()
	_window_failed_keys.clear()
	_window_preview_target.clear()
	_window_history_key = ""
	_window_drag_key = ""

func _queue_window_preview(key: String) -> void:
	if _ignore_fields or not _initialized or _window_preview_busy: return
	if str(snapshot().get("construction_mode", "")) != "shell_v2": return
	if _window_preview_keys.is_empty():
		_window_preview_target = {"scope": _window_scope(), "floor": str(int(_spin_value("floor_override_index"))), "facade": _option_value("facade_index"), "single": _window_override_id()}
	_window_preview_keys.merge(_window_failed_keys, true)
	for previous: String in _window_preview_keys.keys():
		if _window_edit_identity(previous) == _window_edit_identity(key):
			_window_preview_keys.erase(previous)
	_window_preview_keys[key] = {"target": _option_value("palette_target"), "settings": _palette_control_settings()} if key == "palette_settings" else ({"target": _option_value("shading_role"), "settings": _shading_control_settings()} if key == "shading_settings" else _raw_control_value(key))
	_set_status("预览排队中… 继续拖动会合并为一次更新。", WORKSHOP_GOLD)
	if _window_drag_key.is_empty() or _window_preview_timer.is_stopped():
		_window_preview_timer.start(WINDOW_PREVIEW_DELAY)
	_update_window_limit_hint()

func _window_edit_identity(key: String) -> String:
	var field: String = _window_numeric_field(key)
	if key.begins_with("architecture_window_"):
		field = key.trim_prefix("architecture_window_")
	if field.is_empty(): return key
	var scope: String = str(_window_preview_target.get("scope", _window_scope())) if key.begins_with("architecture_window_") else "global"
	if key.begins_with("floor_override_"): scope = "floor"
	if key.begins_with("facade_"): scope = "facade"
	return scope + "|" + str(_window_preview_target.get(scope, "")) + "|" + field

func _window_preview_patch(values: Dictionary) -> Dictionary:
	var data: Dictionary = snapshot()
	var architecture: Dictionary = _architecture_snapshot()
	var patch: Dictionary = {"architecture": architecture}
	for key: String in values:
		if key == "shading_settings":
			var shading: Dictionary = architecture.get("shading", {}).duplicate(true)
			if not shading.has("materials"): shading["materials"] = {}
			shading.materials[str(values[key].target)] = values[key].settings.duplicate(true)
			architecture.shading = shading
			continue
		if key == "palette_settings":
			var target: PackedStringArray = str(values[key].target).split(":")
			if target.size() == 1:
				architecture.palette.merge(values[key].settings, true)
			else:
				if not architecture.palette.has(target[0]): architecture.palette[target[0]] = {}
				architecture.palette[target[0]][target[1]] = values[key].settings.duplicate(true)
			continue
		if VEGETATION_KEYS.has(key):
			if key.begins_with("growth_"):
				var weights: Array = patch.get("growth_weights", data.growth_weights.duplicate())
				weights[["growth_small", "growth_medium", "growth_large"].find(key)] = values[key]
				patch["growth_weights"] = weights
			else:
				patch[key] = values[key]
			continue
		if key == "bay_width":
			patch[key] = values[key]
			continue
		var field: String = _window_numeric_field(key)
		if key.begins_with("architecture_window_"):
			field = key.trim_prefix("architecture_window_")
		var scope: String = str(_window_preview_target.get("scope", _window_scope())) if key.begins_with("architecture_window_") else "global"
		if key.begins_with("floor_override_"): scope = "floor"
		if key.begins_with("facade_"): scope = "facade"
		if scope == "global":
			architecture.window[field] = values[key]
			if field in ["width", "height", "sill"]: patch["window_" + field] = values[key]
		else:
			var container: String = {"floor": "floor_windows", "facade": "facade_windows", "single": "window_overrides"}[scope]
			var target: String = str(_window_preview_target.get(scope, ""))
			if target.is_empty(): return {"ok": false, "reason": "请先选择实际窗口或已关闭窗口"}
			var override: Dictionary = architecture[container].get(target, {}).duplicate(true)
			override[field] = values[key]
			architecture[container][target] = override
	data.merge(patch, true)
	return {"ok": true, "recipe": Recipe.normalized(data)}

## 单次真实构建后再提交现有Session历史/状态，不走apply_patch探针+refresh双重建模。
## 只在同步主线程内操作；不为每个鼠标像素创建撤销项。
func flush_window_preview() -> Dictionary:
	if _window_preview_busy or _window_preview_keys.is_empty(): return {"ok": true, "reason": "没有待预览窗输入"}
	_window_preview_timer.stop()
	if preview == null or not preview.is_node_ready(): return {"ok": false, "reason": "预览尚未就绪"}
	_window_preview_busy = true
	_set_status("正在生成预览… 请稍候，当前修改不会丢失。", WORKSHOP_ACCENT_HOVER)
	var edits: Dictionary = _window_preview_keys.duplicate(true)
	var staged: Dictionary = _window_preview_patch(edits)
	var result: Dictionary = staged
	if bool(staged.get("ok", false)):
		var candidate: Dictionary = staged.recipe
		var reason: String = Recipe.validate(candidate, session.catalog)
		if not reason.is_empty():
			result = {"ok": false, "reason": reason}
		else:
			var history_key: String = _window_scope() + "|" + str(int(_spin_value("floor_override_index"))) + "|" + _option_value("facade_index") + "|" + _window_override_id()
			var ui: Dictionary = _capture_ui_values()
			var baseline: Dictionary = _local_baseline.duplicate(true)
			result = session.preview_candidate(candidate, _window_history_key == history_key, _window_history_fingerprint)
			if bool(result.get("ok", false)):
				_window_history_key = history_key
				_window_history_fingerprint = Recipe.fingerprint(candidate)
				_refresh_from_session()
				refresh_preview(true, result)
				var committed_ui: Dictionary = _capture_ui_values()
				_ignore_fields = true
				_local_baseline = baseline
				for key: String in ui:
					var submitted: bool = edits.has("palette_settings") and key in ["palette_mode", "palette_seed", "palette_cell"]
					if edits.has("shading_settings") and key.begins_with("shading_"):
						submitted = true
					for edit_key: String in edits:
						if _window_edit_identity(key) == _window_edit_identity(edit_key):
							submitted = true
					_set_control_value(key, committed_ui[key] if submitted else ui[key])
					if submitted and _local_baseline.has(key): _local_baseline[key] = committed_ui[key]
				_ignore_fields = false
				_set_status("参数已实时预览；仅提交本次滑动字段，其他未应用输入保留。")
	if not bool(result.get("ok", false)):
		var failed_root: Node = result.get("root") as Node
		if failed_root != null: failed_root.free()
		_set_status("窗预览被拒绝，保留最后成功模型和滑块输入：" + str(result.get("reason", "未知错误")))
	_window_failed_keys = {} if bool(result.get("ok", false)) else edits.duplicate(true)
	_window_preview_keys.clear()
	_window_preview_busy = false
	if _window_drag_key.is_empty(): _window_history_key = ""
	window_preview_result = {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "fields": edits.keys()}
	_update_window_limit_hint()
	_update_palette_grid()
	_refresh_shading_controls()
	_update_state()
	return window_preview_result

func _update_window_limit_hint() -> void:
	if not controls.has("window_limit_hint"): return
	var depth: float = _spin_value("architecture_window_frame_depth")
	var wall: float = float(snapshot().get("wall_thickness", 0.24))
	var limits: Vector2 = WindowGeometry.recess_limits(depth, wall)
	(controls["window_limit_hint"] as Label).text = "自动预览（160ms防抖，拖动合并撤销）。框可突出墙面，不缩窗。\n当前墙厚%.3fm / 框深%.3fm：recess有效范围 %.3f..%.3fm。玻璃上限 %.3fm；更大窗需先应用更大开间/层高。冲突保留输入并显示原因。" % [wall, depth, maxf(limits.x, float(Config.WINDOW_BOUNDS.recess[0])), minf(limits.y, float(Config.WINDOW_BOUNDS.recess[1])), depth - (0.008 if _option_value("architecture_window_type") != "fixed" else 0.004)]

func _button_pressed(id: String) -> void:
	match id:
		"new": _guard_action(_new_document, "新建将丢弃当前未保存修改，是否继续？")
		"generate": generate_building()
		"open":
			_select_page(PAGES.find("文件"))
			refresh_documents()
			_set_status("在左侧文件页选中已保存建筑，再点击打开；不必全盘查找。")
		"save": save_building()
		"save_as": _show_save_as()
		"undo": _undo(false)
		"redo": _undo(true)
		"apply", "apply_bindings", "damage_apply": apply_parameters()
		"slot_apply": _apply_slot_override()
		"slot_restore": _restore_slot()
		"floor_apply": _apply_floor_override(false)
		"floor_clear": _apply_floor_override(true)
		"facade_apply": _apply_facade_override(false)
		"architecture_apply": _apply_architecture_window()
		"architecture_clear": _clear_architecture_window_scope()
		"window_apply": _apply_window_override()
		"roof_apply": _apply_architecture_roof()
		"frame_apply": _apply_frame()
		"form_apply": _apply_form()
		"form_reroll": _reroll_form()
		"roof_clear": _clear_architecture_roof_edge()
		"facade_clear": _apply_facade_override(true)
		"open_scene": _open_scene()
		"refresh_documents": refresh_documents()
		"open_saved":
			var selected: PackedInt32Array = _saved_list.get_selected_items()
			if not selected.is_empty():
				_open_saved_index(selected[0])
		"browse_recipe":
			_file_dialog.current_dir = export_root if DirAccess.dir_exists_absolute(export_root) else "res://"
			_file_dialog.popup_centered_ratio(0.75)
		"load_sample": _request_sample(false)
		"copy_sample":
			_select_page(PAGES.find("文件"))
			_request_sample(true)
		"replace_component": _choose_component()
		"export_module": export_module_component()
		"toggle_left": _left_panel.visible = not _left_panel.visible
		"toggle_right": _right_panel.visible = not _right_panel.visible
		"copy_status": DisplayServer.clipboard_set(_last_status_text)
		_:
			if id.begins_with("default_module_"):
				_load_default_module(int(id.trim_prefix("default_module_")))
				return
			if id.begins_with("module_"):
				_select_page(int(id.trim_prefix("module_")))
				return
			if id.begins_with("view_"):
				preview.set_view(id.trim_prefix("view_"))

func _undo(redo: bool) -> void:
	_reset_window_preview()
	var changed: bool = session.redo() if redo else session.undo()
	if changed:
		_refresh_from_session()
		refresh_preview()
		_set_status("已重做" if redo else "已撤销")
	else:
		_set_status("没有可重做的修改" if redo else "没有可撤销的修改")

func handle_input(event: InputEvent) -> bool:
	if not _screen_visible or not is_visible_in_tree():
		return false
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not key.ctrl_pressed:
		return false
	if _confirm.visible or _save_as_dialog.visible or _file_dialog.visible or _component_dialog.visible:
		return false
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or (focus != null and not is_ancestor_of(focus) and focus != self):
		return false
	var code: int = key.keycode if key.keycode != 0 else key.physical_keycode
	match code:
		KEY_Z: _undo(key.shift_pressed)
		KEY_Y: _undo(true)
		KEY_S: save_building()
		_: return false
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()

func _guard_action(action: Callable, message: String) -> void:
	if has_pending_fields():
		_ask_discard(action, message)
	else:
		action.call()

func _ask_discard(action: Callable, message: String) -> void:
	_confirm_action = action
	_confirm.dialog_text = message
	_confirm.popup_centered(Vector2i(460, 150))
	_confirm.get_cancel_button().grab_focus()

func _confirm_discard() -> void:
	var action: Callable = _confirm_action
	_confirm_action = Callable()
	if action.is_valid():
		action.call()

func _new_document() -> void:
	_reset_window_preview()
	var catalog_ready: Dictionary = _ensure_editor_catalog()
	if not bool(catalog_ready.get("ok", false)):
		_report_result(catalog_ready, "内置组件目录升级失败")
		return
	var result: Dictionary = session.new_document("building_" + str(int(Time.get_unix_time_from_system())), Recipe.authoring_defaults())
	if bool(result.get("ok", false)):
		_last_export.clear()
		_slot_cache.clear()
		_selected_id = ""
		_refresh_from_session()
		refresh_preview()
		_set_status("新建筑已创建；修改名称和 building_id 后保存。")
	else:
		_report_result(result, "新建失败")

func _show_save_as() -> void:
	if _has_pending_local_fields():
		_set_status("请先应用当前楼层、立面或槽位输入，再另存新建筑。")
		return
	_save_as_id.text = _id_edit.text.strip_edges() + "_copy"
	_save_as_dialog.popup_centered(Vector2i(470, 160))
	_save_as_dialog.get_cancel_button().grab_focus()

func _save_as_confirmed() -> void:
	var new_id: String = _save_as_id.text.strip_edges()
	if new_id == str(snapshot().get("building_id", "")):
		_set_status("另存必须输入不同的 building_id；原 ID 保存请用「保存并烘焙」。")
		return
	var patch: Dictionary = _collect_ui_patch()
	patch["building_id"] = new_id
	patch["revision"] = 1
	var result: Dictionary = session.apply_patch(patch)
	if not bool(result.get("ok", false)):
		_report_result(result, "另存新ID被拒绝")
		return
	_last_export.clear()
	_refresh_from_session()
	save_building()

func refresh_documents() -> Array:
	if _saved_list == null:
		return []
	_saved_list.clear()
	if _store == null:
		_set_status("请由插件注入编辑器 Store。")
		return []
	var rows: Array = _store.list_documents(export_root)
	for raw: Variant in rows:
		var row: Dictionary = raw as Dictionary
		_saved_list.add_item("%s · %s\n%s" % [str(row.get("display_name", "")), str(row.get("revision", "")), str(row.get("building_id", ""))])
		_saved_list.set_item_metadata(_saved_list.item_count - 1, str(row.get("recipe_path", "")))
	buttons["open_saved"].disabled = rows.is_empty()
	return rows

func _open_saved_index(index: int) -> void:
	if index >= 0 and index < _saved_list.item_count:
		open_recipe(str(_saved_list.get_item_metadata(index)))

func _refresh_samples() -> void:
	_sample_picker.clear()
	var dir: DirAccess = DirAccess.open(SAMPLE_ROOT)
	if dir == null:
		return
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for filename: String in names:
		if filename.ends_with(".recipe.json"):
			var sample: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_ROOT.path_join(filename)))
			if not sample is Dictionary or str(sample.get("construction_mode", "modular_v1")) != "shell_v2":
				continue
			_sample_picker.add_item(filename.trim_suffix(".recipe.json"))
			_sample_picker.set_item_metadata(_sample_picker.item_count - 1, SAMPLE_ROOT.path_join(filename))

func _request_sample(copy_as_new: bool) -> void:
	if _sample_picker.selected < 0:
		_set_status("项目中没有可加载的样例配方。")
		return
	var path: String = str(_sample_picker.get_item_metadata(_sample_picker.selected))
	_guard_action(_load_sample.bind(path, copy_as_new), "载入样例将丢弃当前未保存修改，是否继续？")

func _load_default_module(index: int) -> void:
	if index < 0 or index >= DEFAULT_MODULES.size():
		_set_status("默认模组索引无效，请刷新工坊。", WORKSHOP_WARN)
		return
	var item: Dictionary = DEFAULT_MODULES[index]
	var path: String = SAMPLE_ROOT.path_join(str(item.get("file", "")))
	if not FileAccess.file_exists(path):
		_set_status("默认模组文件缺失：" + path, WORKSHOP_WARN)
		return
	_guard_action(_load_sample.bind(path, false), "载入「%s」将替换当前未保存修改，是否继续？" % str(item.get("label", "默认模组")))

func _load_sample(path: String, copy_as_new: bool) -> void:
	if not path.begins_with(SAMPLE_ROOT + "/") or path.contains("..") or not path.ends_with(".recipe.json"):
		_set_status("样例路径不在项目样例目录。")
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("无法读取样例。")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_set_status("样例 JSON 不是配方对象。")
		return
	var accepted: Dictionary = session.accept_loaded(parsed as Dictionary, Catalog.definitions())
	if not bool(accepted.get("ok", false)):
		_report_result(accepted, "样例校验失败")
		return
	_slot_cache.clear()
	_selected_id = ""
	_last_export.clear()
	_refresh_from_session()
	refresh_preview()
	_set_status("已载入样例；使用「另存新ID」保存自己的版本，样例源不会改动。")
	if copy_as_new:
		_show_save_as()

func _open_scene() -> void:
	var path: String = str(_last_export.get("scene_path", ""))
	var opener: Callable = _ports.get("open_scene", Callable())
	if path.is_empty() or not FileAccess.file_exists(path):
		_set_status("请先保存并烘焙建筑，再显式在3D打开。")
		return
	if not opener.is_valid():
		_set_status("插件尚未注入 open_scene 端口。")
		return
	if has_pending_fields():
		_set_status("打开的是最近保存的静态版本；当前草稿尚未保存。")
	opener.call(path)

func _choose_component() -> void:
	if not _live_slot_ids.has(_selected_id):
		_set_status("请先选择当前实际生成的槽位；已排除槽须先恢复。")
		return
	var slot: Dictionary = _selected_slot_data(_selected_id)
	var override: Dictionary = snapshot().get("slot_overrides", {}).get(_selected_id, {}) as Dictionary
	_replacement_component_id = str(override.get("component_id", slot.get("component_id", "")))
	if _replacement_component_id.is_empty():
		_set_status("该槽位没有可替换的 componentID。")
		return
	_component_dialog.current_dir = "res://scenes/components"
	_component_dialog.popup_centered_ratio(0.75)

func _replace_component_selected(path: String) -> void:
	if not path.begins_with("res://scenes/components/") or path.contains("..") or not path.ends_with(".tscn"):
		_set_status("只能选择项目组件目录内的 .tscn。")
		return
	var replace: Callable = _ports.get("replace_component", Callable())
	if not replace.is_valid():
		_set_status("组件替换适配器未注入。")
		return
	var result: Dictionary = replace.call(session, _replacement_component_id, path)
	if bool(result.get("ok", false)):
		_refresh_from_session(true)
		refresh_preview()
		_set_status("仅当前槽已替换，独立 componentID：%s；不改变其他槽或全局绑定。" % str(result.get("component_id", "")))
	else:
		_report_result(result, "组件替换被拒绝，原组件保留")

func _apply_slot_override() -> Dictionary:
	if not _live_slot_ids.has(_selected_id):
		return _report_failure("该槽当前没有几何，不能使用缓存位置应用修改；请先恢复此槽或清除失效覆盖。")
	var patch: Dictionary = {"offset": [_spin_value("offset_x"), _spin_value("offset_y"), _spin_value("offset_z")], "disabled": bool(controls["disabled"].button_pressed)}
	var component_id: String = _option_value("component_id")
	if not component_id.is_empty():
		patch["component_id"] = component_id
	var data: Dictionary = snapshot()
	var overrides: Dictionary = data.get("slot_overrides", {}).duplicate(true)
	var current: Dictionary = overrides.get(_selected_id, {}).duplicate(true)
	current.merge(patch, true)
	var slot: Dictionary = _selected_slot_data(_selected_id)
	var locks: Array = data.get("locked_vegetation", []).duplicate(true)
	if _slot_family(_selected_id, str(slot.get("kind", ""))) == "plant":
		current["growth_key"] = _option_value("growth_key")
		var kept: Array = []
		for raw: Variant in locks:
			var entry: Dictionary = raw as Dictionary
			if str(entry.get("slot_id", "")) != _selected_id:
				kept.append(entry)
		if bool(controls["vegetation_lock"].button_pressed):
			kept.append({"slot_id": _selected_id, "position": slot.get("position", [0.0, 0.0, 0.0]), "growth_key": _option_value("growth_key")})
		locks = kept
	overrides[_selected_id] = current
	var excluded: Array = data.get("excluded_slots", []).duplicate(true)
	if not bool(patch["disabled"]):
		excluded.erase(_selected_id)
	var result: Dictionary = session.apply_patch({"slot_overrides": overrides, "locked_vegetation": locks, "excluded_slots": excluded})
	if bool(result.get("ok", false)):
		refresh_preview()
		_set_status("槽位修改已原子应用，可撤销。")
	else:
		_report_result(result, "槽位修改被拒绝")
	return result

func _disable_slot_toggled(value: bool) -> void:
	if _ignore_fields or _selected_id.is_empty():
		return
	var data: Dictionary = snapshot()
	var excluded: Array = data.get("excluded_slots", []).duplicate(true)
	if not value:
		excluded.erase(_selected_id)
	var overrides: Dictionary = data.get("slot_overrides", {}).duplicate(true)
	var current: Dictionary = overrides.get(_selected_id, {}).duplicate(true)
	current["disabled"] = value
	overrides[_selected_id] = current
	var result: Dictionary = session.apply_patch({"slot_overrides": overrides, "excluded_slots": excluded})
	if bool(result.get("ok", false)):
		refresh_preview()
		if value:
			_set_status("已排除槽位并移除对应几何 / 碰撞；列表保留恢复入口。")
		elif _live_slot_ids.has(_selected_id):
			_set_status("已恢复槽位。")
		else:
			_set_status("已清除禁用，但该槽来源当前未生成；不会使用过期缓存位置或几何。")
	else:
		_report_result(result, "禁用操作失败")
		select_slot(_selected_id)

func _restore_slot() -> void:
	if _selected_id.is_empty():
		return
	var data: Dictionary = snapshot()
	var overrides: Dictionary = data.get("slot_overrides", {}).duplicate(true)
	overrides.erase(_selected_id)
	var excluded: Array = data.get("excluded_slots", []).duplicate(true)
	excluded.erase(_selected_id)
	var locks: Array = []
	for raw: Variant in data.get("locked_vegetation", []):
		var entry: Dictionary = raw as Dictionary
		if str(entry.get("slot_id", "")) != _selected_id:
			locks.append(entry)
	var result: Dictionary = session.apply_patch({"slot_overrides": overrides, "excluded_slots": excluded, "locked_vegetation": locks})
	if bool(result.get("ok", false)):
		refresh_preview()
		_set_status("已清除此槽覆盖和排除，恢复生成默认值；种子破损仍按全局配方决定。")
	else:
		_report_result(result, "槽位恢复失败")

func _architecture_snapshot() -> Dictionary:
	return Config.normalized(snapshot().get("architecture", {}))

func _architecture_patch_with(changes: Dictionary) -> Dictionary:
	var architecture: Dictionary = _architecture_snapshot()
	architecture.merge(changes, true)
	return architecture

func _architecture_ui_patch(force_global: bool = false) -> Dictionary:
	var architecture: Dictionary = _architecture_snapshot()
	var plan: Dictionary = architecture.get("plan", {}).duplicate(true)
	plan["wing_x"] = _spin_value("wing_x")
	plan["wing_z"] = _spin_value("wing_z")
	plan["setback_start"] = int(_spin_value("setback_start"))
	plan["setback_step"] = _spin_value("setback_step")
	architecture["plan"] = plan
	var scope: String = _window_scope()
	if scope == "global":
		var window: Dictionary = architecture.get("window", {}).duplicate(true)
		for field: String in ARCHITECTURE_WINDOW_FIELDS:
			if controls.has("architecture_window_" + field):
				window[field] = _raw_control_value("architecture_window_" + field)
		var base: Dictionary = {"width": _spin_value("architecture_window_width"), "height": _spin_value("architecture_window_height"), "sill": _spin_value("architecture_window_sill")}
		window.merge(base, true)
		architecture["window"] = window
	elif scope == "floor":
		var floor_windows: Dictionary = architecture.get("floor_windows", {}).duplicate(true)
		floor_windows[str(int(_spin_value("floor_override_index")))] = _architecture_window_control_values()
		architecture["floor_windows"] = floor_windows
	elif scope == "facade":
		var facade_windows: Dictionary = architecture.get("facade_windows", {}).duplicate(true)
		facade_windows[_option_value("facade_index")] = _architecture_window_control_values()
		architecture["facade_windows"] = facade_windows
	elif scope == "single":
		var opening_id: String = _window_override_id()
		if not opening_id.is_empty():
			var overrides: Dictionary = architecture.get("window_overrides", {}).duplicate(true)
			overrides[opening_id] = _architecture_window_control_values()
			architecture["window_overrides"] = overrides
	var roof: Dictionary = architecture.get("roof", {}).duplicate(true)
	for field: String in ARCHITECTURE_ROOF_FIELDS:
		var key: String = "architecture_roof_" + field
		roof[field] = _raw_control_value(key)
	architecture["roof"] = roof
	architecture["form"] = _form_values(architecture)
	architecture["pilaster"] = _frame_pilaster_values(architecture)
	architecture["band"] = _frame_band_values(architecture)
	return architecture

func _architecture_window_control_values() -> Dictionary:
	var values: Dictionary = {}
	for field: String in ARCHITECTURE_WINDOW_FIELDS:
		var key: String = "architecture_window_" + field
		if controls.has(key):
			values[field] = _raw_control_value(key)
	return values

func _construction_mode_changed(_index: int) -> void:
	if _ignore_fields:
		return
	var data: Dictionary = snapshot()
	data["construction_mode"] = _option_value("construction_mode")
	_refresh_architecture_controls(data)
	_on_field_changed()

func _architecture_roof_edge_changed(_index: int) -> void:
	if not _ignore_fields:
		_sync_architecture_roof_edge(_architecture_snapshot().get("roof", {}))

func _architecture_shape_changed(_index: int) -> void:
	if not _ignore_fields and _option_value("construction_mode") == "shell_v2":
		_set_option("shape", _option_value("architecture_shape_variant"))
		_refresh_roof_edge_options(_option_value("architecture_shape_variant"))
		_on_field_changed()

func _window_scope() -> String:
	var scope: String = _option_value("window_scope") if controls.has("window_scope") else "global"
	return scope if scope in ARCHITECTURE_WINDOW_SCOPES else "global"

func _window_target_changed(floor_changed: bool) -> void:
	if _ignore_fields or not _initialized: return
	var requested_floor: float = _spin_value("floor_override_index")
	var requested_facade: String = _option_value("facade_index")
	flush_window_preview()
	if not _window_failed_keys.is_empty():
		_set_spin("floor_override_index", _last_floor_index)
		_set_option("facade_index", _last_facade)
		_set_status("窗输入未通过，请修正或清除后切换楼层/立面。")
		return
	_set_spin("floor_override_index", requested_floor)
	_set_option("facade_index", requested_facade)
	_window_history_key = ""
	if floor_changed:
		_sync_floor_fields()
	else:
		_sync_facade_fields()
	if _window_scope() in ["floor", "facade"]:
		_sync_architecture_window_scope()

func _window_scope_changed(_index: int) -> void:
	if _ignore_fields:
		return
	var requested_scope: String = _window_scope()
	_set_option("window_scope", _last_window_scope)
	flush_window_preview()
	if _has_pending_window_fields() or not _window_failed_keys.is_empty():
		_set_option("window_scope", _last_window_scope)
		_set_status("当前窗范围存在未应用输入，请先应用或清除后再切换范围。")
		return
	_set_option("window_scope", requested_scope)
	_sync_architecture_window_scope()
	_last_window_scope = _window_scope()
	_window_history_key = ""
	_update_state()

func _window_selection_changed(_index: int) -> void:
	if _ignore_fields:
		return
	var requested_opening: String = _option_value("window_selection")
	flush_window_preview()
	if _has_pending_window_fields() or not _window_failed_keys.is_empty():
		var pending_option: OptionButton = controls["window_selection"] as OptionButton
		for pending_index: int in pending_option.item_count:
			if str(pending_option.get_item_metadata(pending_index)) == _selected_opening_id:
				pending_option.select(pending_index)
				break
		_set_status("当前窗存在未应用输入，请先应用或清除后再切换窗口。")
		return
	_set_option("window_selection", requested_opening)
	var option: OptionButton = controls["window_selection"] as OptionButton
	if option.selected >= 0:
		var opening_id: String = str(option.get_item_metadata(option.selected))
		_selected_opening_id = opening_id
		var slot_id: String = _opening_to_slot_id(opening_id)
		_selected_id = slot_id
		if _window_scope() != "global":
			_sync_architecture_window_scope()
		_capture_window_local_baseline()

func _refresh_frame_controls(data: Dictionary) -> void:
	if not controls.has("pilaster_enabled"):
		return
	var architecture: Dictionary = Config.normalized(data.get("architecture", {}))
	var pilaster: Dictionary = architecture.get("pilaster", {})
	var band: Dictionary = architecture.get("band", {})
	_set_control_value("pilaster_enabled", bool(pilaster.get("enabled", false)))
	_set_control_value("pilaster_corner", bool(pilaster.get("corner", true)))
	_set_control_value("pilaster_middle", bool(pilaster.get("middle", true)))
	_set_spin("pilaster_width", float(pilaster.get("width", 0.36)))
	_set_spin("pilaster_projection", float(pilaster.get("projection", 0.18)))
	_set_spin("pilaster_bite", float(pilaster.get("bite", 0.06)))
	_set_control_value("band_enabled", bool(band.get("enabled", false)))
	_set_spin("band_projection", float(band.get("projection", 0.10)))
	_set_spin("band_thickness", float(band.get("thickness", 0.34)))
	_update_frame_readout()

func _frame_pilaster_values(architecture: Dictionary) -> Dictionary:
	var pilaster: Dictionary = architecture.get("pilaster", {}).duplicate(true)
	if not controls.has("pilaster_width"):
		return pilaster
	pilaster["enabled"] = bool(_raw_control_value("pilaster_enabled"))
	pilaster["corner"] = bool(_raw_control_value("pilaster_corner"))
	pilaster["middle"] = bool(_raw_control_value("pilaster_middle"))
	pilaster["width"] = _spin_value("pilaster_width")
	pilaster["projection"] = _spin_value("pilaster_projection")
	pilaster["bite"] = _spin_value("pilaster_bite")
	if not pilaster.has("bevel"):
		pilaster["bevel"] = 0.014
	return pilaster

func _frame_band_values(architecture: Dictionary) -> Dictionary:
	var band: Dictionary = architecture.get("band", {}).duplicate(true)
	if not controls.has("band_projection"):
		return band
	band["enabled"] = bool(_raw_control_value("band_enabled"))
	band["projection"] = _spin_value("band_projection")
	band["thickness"] = _spin_value("band_thickness")
	if not band.has("bevel"):
		band["bevel"] = 0.012
	return band

func _apply_frame() -> Dictionary:
	if _option_value("construction_mode") != "shell_v2":
		return _report_failure("承重柱与腰线只在shell_v2连续实体模式生效。")
	# 构架页控件的值必须先并进 architecture 再提交：_architecture_snapshot() 读的是
	# session 里的旧配方，直接拿它提交等于把用户刚拨的柱宽/腰线凸出量原样丢掉。
	var architecture: Dictionary = _architecture_snapshot()
	architecture["pilaster"] = _frame_pilaster_values(architecture)
	architecture["band"] = _frame_band_values(architecture)
	var result: Dictionary = session.apply_patch({"architecture": architecture})
	if bool(result.get("ok", false)):
		_refresh_from_session()
		refresh_preview()
		_set_status("构架已应用 · " + _frame_summary())
	else:
		_report_result(result, "构架参数被拒绝：柱压到洞口、咬入过深或腰线过薄")
	_update_frame_readout()
	return result

func _frame_summary() -> String:
	var recipe: Dictionary = snapshot().duplicate(true)
	recipe["architecture"] = _architecture_snapshot()
	var architecture: Dictionary = Config.normalized(recipe.get("architecture", {}))
	var pilaster: Dictionary = architecture.get("pilaster", {})
	var band: Dictionary = architecture.get("band", {})
	var parts: Array[String] = []
	if bool(pilaster.get("enabled", false)):
		var sides: Array[String] = []
		if bool(pilaster.get("corner", true)): sides.append("转角")
		if bool(pilaster.get("middle", true)): sides.append("窗间")
		parts.append("柱 %s 宽%.2fm 凸%.2fm" % ["+".join(sides) if not sides.is_empty() else "无", float(pilaster.get("width", 0.0)), float(pilaster.get("projection", 0.0))])
	if bool(band.get("enabled", false)):
		var band_projection: float = float(band.get("projection", 0.0))
		var requested: float = band_projection
		if bool(pilaster.get("enabled", false)):
			# 腰线必须收在柱后，实际凸出量会被柱控住——读数要给出实际值，不能只报用户输入。
			band_projection = minf(band_projection, maxf(float(pilaster.get("projection", 0.18)) - 0.04, 0.03))
		var note: String = "" if is_equal_approx(requested, band_projection) else "（收在柱后，实际%.2fm）" % band_projection
		parts.append("腰线 凸%.2fm 厚%.2fm%s" % [band_projection, float(band.get("thickness", 0.0)), note])
	return " · ".join(parts) if not parts.is_empty() else "柱与腰线均关闭"

func _update_frame_readout() -> void:
	if frame_readout_label == null or not controls.has("pilaster_width"):
		return
	frame_readout_label.text = "当前：%s" % _frame_summary()

func _refresh_form_controls(data: Dictionary) -> void:
	if not controls.has("form_seed"):
		return
	var architecture: Dictionary = Config.normalized(data.get("architecture", {}))
	var form: Dictionary = architecture.get("form", {})
	_set_control_value("form_enabled", bool(form.get("enabled", false)))
	_set_option("form_preset", str(form.get("preset", "SF-B")))
	_set_spin("form_seed", float(form.get("seed", 0)))
	_set_spin("form_max_tilt", float(form.get("max_tilt_deg", Config.TILT_DEFAULT_DEG)))
	var opening: Dictionary = form.get("opening", {})
	_set_option("form_opening_sign", str(opening.get("sign", "positive")))
	for category: String in FORM_CATEGORIES:
		var entry: Dictionary = form.get(category, {})
		var bounds: Array = Config.FORM_BOUNDS[category]
		_set_spin("form_" + category + "_min", float(entry.get("min", bounds[0])))
		_set_spin("form_" + category + "_max", float(entry.get("max", bounds[1])))
	_update_form_readout()

## 把界面上的六个数（三类区间）+种子+开关写进给定 architecture；不改其他字段。
func _form_values(architecture: Dictionary) -> Dictionary:
	var form: Dictionary = architecture.get("form", {}).duplicate(true)
	if not controls.has("form_seed"):
		return form
	form["enabled"] = bool(_raw_control_value("form_enabled"))
	form["seed"] = int(_spin_value("form_seed"))
	form["preset"] = _option_value("form_preset")
	form["max_tilt_deg"] = _spin_value("form_max_tilt")
	for category: String in FORM_CATEGORIES:
		var entry: Dictionary = form.get(category, {}).duplicate(true)
		entry["min"] = _spin_value("form_" + category + "_min")
		entry["max"] = _spin_value("form_" + category + "_max")
		if category == "opening":
			entry["sign"] = _option_value("form_opening_sign")
		elif not entry.has("sign"):
			entry["sign"] = "positive"
		form[category] = entry
	return form

func _form_patch() -> Dictionary:
	var architecture: Dictionary = _architecture_snapshot()
	architecture["form"] = _form_values(architecture)
	return architecture

func _form_preset_changed(_index: int) -> void:
	var preset: String = _option_value("form_preset")
	if not FORM_PRESETS.has(preset):
		return
	var entry: Dictionary = FORM_PRESETS[preset]
	for category: String in FORM_CATEGORIES:
		var bounds: Array = entry[category]
		_set_spin("form_" + category + "_min", float(bounds[0]))
		_set_spin("form_" + category + "_max", float(bounds[1]))
	_update_form_readout()

func _apply_form() -> Dictionary:
	if _option_value("construction_mode") != "shell_v2":
		return _report_failure("形体变形只在shell_v2连续实体模式生效。")
	var result: Dictionary = session.apply_patch({"architecture": _form_patch()})
	if bool(result.get("ok", false)):
		_refresh_from_session()
		refresh_preview()
		_set_status("形体已应用 · " + _form_summary())
	else:
		_report_result(result, "形体参数被拒绝：幅度越界或超出当前墙倾角上限")
	_update_form_readout()
	return result

func _reroll_form() -> Dictionary:
	_set_spin("form_seed", float(int(_spin_value("form_seed")) + 1))
	return _apply_form()

## 落值预览：让"区间"能看到实际落在哪，而不是只有一个范围。
func _form_summary() -> String:
	var recipe: Dictionary = snapshot().duplicate(true)
	recipe["architecture"] = _form_patch()
	var resolved: Dictionary = Config.resolve_form(recipe)
	if not bool(resolved.get("enabled", false)):
		return "未启用形体（退化为正交模型）"
	var sign_note: String = ""
	if str(resolved.get("opening_sign", "positive")) == "mixed":
		var counts: Vector2i = _opening_sign_counts(recipe)
		sign_note = "（上窄%d列 / 上宽%d列）" % [counts.x, counts.y]
	return "整楼%.2f%% · 窗%.2f%%%s · 配件%.2f%%" % [float(resolved.structure) * 100.0, float(resolved.opening) * 100.0, sign_note, float(resolved.accessory) * 100.0]

## 数一遍当前种子下有多少列是上窄、多少列是上宽，让"混合"看得见而不只是勾选项。
func _opening_sign_counts(recipe: Dictionary) -> Vector2i:
	var narrow: int = 0
	var wide: int = 0
	for facade in ["front", "back", "left", "right"]:
		for ordinal in 8:
			var rho: float = Config.opening_rho(recipe, str(facade) + "_" + str(ordinal))
			if absf(rho) <= 0.00001: continue
			if rho > 0.0: narrow += 1
			else: wide += 1
	return Vector2i(narrow, wide)

func _update_form_readout() -> void:
	if form_readout_label == null or not controls.has("form_seed"):
		return
	var recipe: Dictionary = snapshot().duplicate(true)
	recipe["architecture"] = _form_patch()
	var limit: float = Config.structure_limit(recipe)
	var tilt: float = Config.tilt_limit(recipe)
	var span: float = maxf(float(recipe.get("width", 0.0)), float(recipe.get("depth", 0.0)))
	var height: float = maxf(1.0, float(recipe.get("floors", 1))) * float(recipe.get("floor_height", 0.0))
	var advice: String = ""
	var structure_entry: Dictionary = _form_values(_architecture_snapshot()).get("structure", {})
	var wanted: float = float(structure_entry.get("max", 0.0))
	if span > 0.0 and height > 0.0 and wanted > limit + 0.000001:
		# 正向求解需要的最小倾角：让"幅度不够"变成可操作的一个数字，而不是只报上限。
		var needed: float = rad_to_deg(atan(wanted * span / height))
		advice = "\n幅度不足：上限需 ≥ %.1f°（当前 %.1f°）" % [needed, tilt]
	var tilt_only: float = Config.tilt_taper_limit(recipe)
	var cap_note: String = "；taper上限%.2f" % Config.TAPER_CAP if tilt_only > Config.TAPER_CAP + 0.000001 else ""
	form_readout_label.text = "落值：%s\n墙倾角上限 %.1f° → 结构可用收分 %.4f（面宽%.1fm × 总高%.2fm%s）%s" % [_form_summary(), tilt, limit, span, height, cap_note, advice]

## taper 是派生值：形体开启时由 structure 区间落值写入。禁用输入并写明来源，不留"改了没反应"的坑。
func _sync_taper_ownership(form_enabled: bool) -> void:
	if not controls.has("taper"):
		return
	var slider: HSlider = controls["taper"] as HSlider
	if slider == null:
		return
	slider.editable = not form_enabled
	slider.tooltip_text = "由形体「整楼结构」区间 + 种子决定" if form_enabled else "关闭形体后可手动设定"

func _apply_architecture_window() -> Dictionary:
	_reset_window_preview()
	if _option_value("construction_mode") != "shell_v2":
		return _report_failure("架构窗构造只在shell_v2连续实体模式生效。")
	var scope: String = _window_scope()
	if scope == "single" and _window_override_id().is_empty():
		return _report_failure("当前没有可应用的单窗；请选择实际窗口或已关闭窗口。")
	var pending_ui: Dictionary = _capture_ui_values()
	var architecture: Dictionary = _architecture_snapshot()
	var values: Dictionary = _architecture_window_control_values()
	var patch: Dictionary = {"architecture": architecture}
	if scope == "global":
		architecture["window"] = values
		for field: String in ["width", "height", "sill"]:
			patch["window_" + field] = values[field]
	elif scope == "floor":
		architecture["floor_windows"][str(int(_spin_value("floor_override_index")))] = values
	elif scope == "facade":
		architecture["facade_windows"][_option_value("facade_index")] = values
	else:
		architecture["window_overrides"][_window_override_id()] = values
	var result: Dictionary = session.apply_patch(patch)
	if bool(result.get("ok", false)):
		_refresh_from_session()
		refresh_preview()
		# 窗按钮不吞掉用户尚未提交的楼宽、门尺寸或形体等输入。
		_ignore_fields = true
		for key: String in pending_ui:
			if key.begins_with("architecture_window_") or key in ["window_width", "window_height", "window_sill", "window_scope", "window_selection"]:
				continue
			_set_control_value(key, pending_ui[key])
		_ignore_fields = false
		_set_status("%s窗构造已应用并重建；其他基础参数输入保留。" % _window_scope_label(scope))
	else:
		_report_result(result, "架构窗构造被拒绝")
	return result

func _window_scope_label(scope: String) -> String:
	return {"global": "全局", "floor": "楼层", "facade": "立面", "single": "当前窗"}.get(scope, scope)

func _window_override_id() -> String:
	if not _selected_opening_id.is_empty():
		if not _opening_cache.has(_selected_opening_id) or str(_opening_cache[_selected_opening_id].get("type", "window")) != "door":
			return _selected_opening_id
		return ""
	if controls.has("window_selection"):
		var option: OptionButton = controls["window_selection"] as OptionButton
		if option.selected >= 0:
			var metadata: String = str(option.get_item_metadata(option.selected))
			if metadata.begins_with("opening_"):
				return metadata
	var selected: String = _selected_id
	if selected.begins_with("opening_"):
		return selected
	for prefix: String in ["frame_", "glass_", "sash_", "sill_"]:
		if selected.begins_with(prefix):
			return "opening_" + selected.trim_prefix(prefix)
	return ""

func _opening_to_slot_id(opening_id: String) -> String:
	for prefix: String in ["frame_", "glass_", "sash_", "sill_"]:
		var candidate: String = prefix + opening_id.trim_prefix("opening_")
		if _slot_ids.has(candidate):
			return candidate
	return ""

func _apply_window_override() -> Dictionary:
	if _window_scope() == "global":
		return _apply_architecture_window()
	if _window_scope() != "single":
		_set_option("window_scope", "single")
		_sync_architecture_window_scope()
	return _apply_architecture_window()

func _clear_architecture_window_scope() -> Dictionary:
	_reset_window_preview()
	var architecture: Dictionary = _architecture_snapshot()
	var patch: Dictionary = {"architecture": architecture}
	var scope: String = _window_scope()
	if scope == "global":
		return _report_failure("全局没有覆盖可清除；请直接应用全局构造。")
	if scope == "floor":
		var index: String = str(int(_spin_value("floor_override_index")))
		var floors: Dictionary = architecture.get("floor_windows", {}).duplicate(true)
		floors.erase(index)
		architecture["floor_windows"] = floors
		var old_floors: Dictionary = snapshot().get("floor_overrides", {}).duplicate(true)
		var old_floor: Dictionary = old_floors.get(index, {}).duplicate(true)
		for field: String in ["window_width", "window_height", "window_sill"]:
			old_floor.erase(field)
		if old_floor.is_empty():
			old_floors.erase(index)
		else:
			old_floors[index] = old_floor
		patch["floor_overrides"] = old_floors
	elif scope == "facade":
		var facade: String = _option_value("facade_index")
		var facades: Dictionary = architecture.get("facade_windows", {}).duplicate(true)
		facades.erase(facade)
		architecture["facade_windows"] = facades
		var old_facades: Dictionary = snapshot().get("facade_overrides", {}).duplicate(true)
		old_facades.erase(facade)
		patch["facade_overrides"] = old_facades
	else:
		var opening_id: String = _window_override_id()
		if opening_id.is_empty():
			return _report_failure("当前没有可清除的单窗覆盖。")
		var singles: Dictionary = architecture.get("window_overrides", {}).duplicate(true)
		singles.erase(opening_id)
		architecture["window_overrides"] = singles
	patch["architecture"] = architecture
	var result: Dictionary = session.apply_patch(patch)
	if bool(result.get("ok", false)):
		_refresh_from_session()
		refresh_preview()
		_set_status("已清除%s窗覆盖，恢复继承。" % _window_scope_label(scope))
	else:
		_report_result(result, "清除架构窗覆盖被拒绝")
	return result

func _apply_architecture_roof() -> Dictionary:
	if _option_value("construction_mode") != "shell_v2":
		return _report_failure("架构屋顶只在shell_v2连续实体模式生效。")
	var architecture: Dictionary = _architecture_ui_patch(true)
	var roof: Dictionary = architecture.get("roof", {}).duplicate(true)
	var edge_overrides: Dictionary = roof.get("edge_overrides", {}).duplicate(true)
	var edge_id: String = _option_value("architecture_roof_edge_index")
	if bool((controls["architecture_roof_edge_override_enabled"] as CheckButton).button_pressed):
		var edge: Dictionary = {}
		edge["mode"] = _option_value("architecture_roof_edge_mode")
		edge["gap_center"] = _spin_value("architecture_roof_gap_center")
		edge["gap_width"] = _spin_value("architecture_roof_gap_width")
		edge_overrides[edge_id] = edge
	roof["edge_overrides"] = edge_overrides
	architecture["roof"] = roof
	var result: Dictionary = session.apply_patch({"architecture": architecture})
	if bool(result.get("ok", false)):
		_refresh_from_session()
		refresh_preview()
		_set_status("屋顶构造已应用，可撤销。")
	else:
		_report_result(result, "屋顶构造被拒绝")
	return result

func _clear_architecture_roof_edge() -> Dictionary:
	var architecture: Dictionary = _architecture_snapshot()
	var roof: Dictionary = architecture.get("roof", {}).duplicate(true)
	var edge_overrides: Dictionary = roof.get("edge_overrides", {}).duplicate(true)
	edge_overrides.erase(_option_value("architecture_roof_edge_index"))
	roof["edge_overrides"] = edge_overrides
	architecture["roof"] = roof
	var result: Dictionary = session.apply_patch({"architecture": architecture})
	if bool(result.get("ok", false)):
		_refresh_from_session()
		refresh_preview()
		_set_status("已清除当前屋顶边覆盖，恢复继承。")
	else:
		_report_result(result, "清除屋顶边覆盖被拒绝")
	return result

func _apply_floor_override(clear: bool) -> void:
	var index: String = str(int(_spin_value("floor_override_index")))
	var overrides: Dictionary = snapshot().get("floor_overrides", {}).duplicate(true)
	var architecture: Dictionary = _architecture_snapshot()
	var floor_windows: Dictionary = architecture.get("floor_windows", {}).duplicate(true)
	if clear:
		overrides.erase(index)
		floor_windows.erase(index)
	else:
		var values: Dictionary = {"floor_height": _spin_value("floor_override_height"), "window_width": _spin_value("floor_override_window_width"), "window_height": _spin_value("floor_override_window_height"), "window_sill": _spin_value("floor_override_sill")}
		overrides[index] = values
		floor_windows[index] = _architecture_window_control_values()
		floor_windows[index]["width"] = _spin_value("floor_override_window_width")
		floor_windows[index]["height"] = _spin_value("floor_override_window_height")
		floor_windows[index]["sill"] = _spin_value("floor_override_sill")
	var patch: Dictionary = {"floor_overrides": overrides}
	if _option_value("construction_mode") == "shell_v2" or snapshot().has("architecture"):
		patch["architecture"] = _architecture_patch_with({"floor_windows": floor_windows})
	var result: Dictionary = session.apply_patch(patch)
	_after_override(result, true)

func _apply_facade_override(clear: bool) -> void:
	var facade: String = _option_value("facade_index")
	var overrides: Dictionary = snapshot().get("facade_overrides", {}).duplicate(true)
	var architecture: Dictionary = _architecture_snapshot()
	var facade_windows: Dictionary = architecture.get("facade_windows", {}).duplicate(true)
	if clear:
		overrides.erase(facade)
		facade_windows.erase(facade)
	else:
		var values: Dictionary = {"windows": bool(controls["facade_windows"].button_pressed), "width": _spin_value("facade_width"), "height": _spin_value("facade_height"), "sill": _spin_value("facade_sill")}
		overrides[facade] = values
		facade_windows[facade] = {
			"enabled": values.windows,
			"width": values.width,
			"height": values.height,
			"sill": values.sill
		}
	var patch: Dictionary = {"facade_overrides": overrides}
	if _option_value("construction_mode") == "shell_v2" or snapshot().has("architecture"):
		patch["architecture"] = _architecture_patch_with({"facade_windows": facade_windows})
	var result: Dictionary = session.apply_patch(patch)
	_after_override(result, false)

func _after_override(result: Dictionary, floor_changed: bool) -> void:
	if bool(result.get("ok", false)):
		if floor_changed:
			_sync_floor_fields()
		else:
			_sync_facade_fields()
		_update_override_status()
		refresh_preview(true)
		_set_status("局部覆盖已更新，可撤销；基础字段未提交的输入保持不变。")
	else:
		_report_result(result, "局部覆盖被拒绝")

func _refresh_from_session(preserve_pending_fields: bool = false) -> void:
	if not _initialized:
		return
	var data: Dictionary = snapshot()
	_ignore_fields = true
	if not preserve_pending_fields:
		_id_edit.text = str(data.get("building_id", ""))
		_name_edit.text = str(data.get("display_name", ""))
		for key: String in PARAMETER_KEYS:
			_set_control_value(key, data[key])
		_refresh_architecture_controls(data)
	var bindings: Dictionary = data.get("component_bindings", {}) as Dictionary
	for role: String in Recipe.COMPONENT_ROLES:
		_fill_component_option("binding_" + role, role, str(bindings.get(role, "")))
	if not preserve_pending_fields:
		var weights: Array = data.get("growth_weights", [0.3, 0.4, 0.3]) as Array
		_set_spin("growth_small", float(weights[0]))
		_set_spin("growth_medium", float(weights[1]))
		_set_spin("growth_large", float(weights[2]))
	_ignore_fields = false
	if not preserve_pending_fields:
		_sync_floor_fields()
		_sync_facade_fields()
	_update_override_status()
	var root_label: Label = controls["export_root_label"] as Label
	root_label.text = "保存路径：%s / <building_id> / revision_NNNN" % export_root
	_update_state()

func _refresh_architecture_controls(data: Dictionary) -> void:
	var architecture: Dictionary = Config.normalized(data.get("architecture", {}))
	var shell: bool = str(data.get("construction_mode", "modular_v1")) == "shell_v2"
	for panel: Control in architecture_panels:
		panel.visible = shell
	if controls.has("architecture_shape_variant"):
		_set_option("architecture_shape_variant", str(data.get("shape", "rectangle")))
	if controls.has("window_scope"):
		_set_option("window_scope", _last_window_scope)
	var plan: Dictionary = architecture.get("plan", {})
	for pair: Array in [["wing_x", "wing_x"], ["wing_z", "wing_z"], ["setback_start", "setback_start"], ["setback_step", "setback_step"]]:
		_set_spin(str(pair[0]), float(plan.get(pair[1], 0.0)))
	var window: Dictionary = architecture.get("window", {})
	for field: String in ARCHITECTURE_WINDOW_FIELDS:
		_set_control_value("architecture_window_" + field, window.get(field, false if field in ["enabled", "sill_enabled"] else 0.0))
	_set_control_value("architecture_window_width", window.get("width", data.get("window_width", 1.4)))
	_set_control_value("architecture_window_height", window.get("height", data.get("window_height", 1.8)))
	_set_control_value("architecture_window_sill", window.get("sill", data.get("window_sill", 1.0)))
	var roof: Dictionary = architecture.get("roof", {})
	for field: String in ARCHITECTURE_ROOF_FIELDS:
		_set_control_value("architecture_roof_" + field, roof.get(field, "none" if field == "mode" else 0.0))
	_refresh_roof_edge_options(str(data.get("shape", "rectangle")))
	_sync_window_selection(data)
	if _window_scope() != "global":
		_sync_architecture_window_scope()
	_sync_architecture_roof_edge(roof)
	_refresh_frame_controls(data)
	_refresh_form_controls(data)
	_refresh_palette_controls()
	_refresh_shading_controls()
	_sync_taper_ownership(bool((Config.normalized(data.get("architecture", {})).get("form", {}) as Dictionary).get("enabled", false)))
	# 刷新到 session 值之后，局部基线必须跟着对齐；否则载入配方会被误判成"存在未应用输入"，连保存都拦住。
	_capture_window_local_baseline()
	_update_window_limit_hint()

func _sync_window_selection(data: Dictionary) -> void:
	if not controls.has("window_selection"):
		return
	var option: OptionButton = controls["window_selection"] as OptionButton
	var selected_opening: String = _window_override_id()
	option.clear()
	var opening_ids: Dictionary = _opening_cache.duplicate(true)
	var architecture: Dictionary = Config.normalized(data.get("architecture", {}))
	for raw_id: Variant in architecture.get("window_overrides", {}).keys():
		var opening_id: String = str(raw_id)
		if not opening_ids.has(opening_id):
			opening_ids[opening_id] = {"id": opening_id, "type": "window"}
	var sorted_ids: Array = opening_ids.keys()
	sorted_ids.sort()
	for raw_id: Variant in sorted_ids:
		var opening_id: String = str(raw_id)
		if not opening_id.begins_with("opening_") or str(opening_ids[opening_id].get("type", "window")) == "door":
			continue
		option.add_item(opening_id)
		option.set_item_metadata(option.item_count - 1, opening_id)
		option.set_item_tooltip(option.item_count - 1, "opening_id: " + opening_id)
	if not selected_opening.is_empty():
		for index: int in option.item_count:
			if str(option.get_item_metadata(index)) == selected_opening:
				option.select(index)
				break

func _refresh_roof_edge_options(shape: String) -> void:
	if not controls.has("architecture_roof_edge_index"):
		return
	var option: OptionButton = controls["architecture_roof_edge_index"] as OptionButton
	var current: String = _option_value("architecture_roof_edge_index")
	var count: int = 4 if shape == "rectangle" else (6 if shape == "l" else 8)
	option.clear()
	for index: int in count:
		option.add_item("边 " + str(index))
		option.set_item_metadata(option.item_count - 1, "edge_" + str(index))
	if current.is_empty() or int(current.trim_prefix("edge_")) >= count:
		current = "edge_0"
	_set_option("architecture_roof_edge_index", current)

func _sync_architecture_roof_edge(roof: Dictionary) -> void:
	if not controls.has("architecture_roof_edge_index"):
		return
	var edge_id: String = _option_value("architecture_roof_edge_index")
	var overrides: Dictionary = roof.get("edge_overrides", {}) as Dictionary
	var has_override: bool = overrides.has(edge_id)
	var edge: Dictionary = overrides.get(edge_id, {}) as Dictionary
	_set_control_value("architecture_roof_edge_override_enabled", has_override)
	_set_control_value("architecture_roof_edge_mode", edge.get("mode", roof.get("mode", "none")))
	_set_spin("architecture_roof_gap_center", float(edge.get("gap_center", 0.5)))
	_set_spin("architecture_roof_gap_width", float(edge.get("gap_width", 0.0)))

func _sync_floor_fields() -> void:
	if not _initialized or _ignore_fields:
		return
	var data: Dictionary = snapshot()
	var index: String = str(int(_spin_value("floor_override_index")))
	_last_floor_index = float(index)
	var override: Dictionary = data.get("floor_overrides", {}).get(index, {}) as Dictionary
	var architecture_floor: Dictionary = Config.normalized(data.get("architecture", {})).get("floor_windows", {}).get(index, {}) as Dictionary
	_ignore_fields = true
	for pair: Array in [["floor_override_height", "floor_height"], ["floor_override_window_width", "window_width"], ["floor_override_window_height", "window_height"], ["floor_override_sill", "window_sill"]]:
		var value: Variant = override.get(pair[1], data.get(pair[1], 1.0))
		if pair[1] == "window_width":
			value = architecture_floor.get("width", value)
		elif pair[1] == "window_height":
			value = architecture_floor.get("height", value)
		elif pair[1] == "window_sill":
			value = architecture_floor.get("sill", value)
		_set_spin(str(pair[0]), float(value))
	_ignore_fields = false
	_capture_local_baseline(["floor_override_height", "floor_override_window_width", "floor_override_window_height", "floor_override_sill"])

func _sync_facade_fields() -> void:
	if not _initialized or _ignore_fields:
		return
	var data: Dictionary = snapshot()
	var facade: String = _option_value("facade_index")
	_last_facade = facade
	var override: Dictionary = data.get("facade_overrides", {}).get(facade, {}) as Dictionary
	var architecture_facade: Dictionary = Config.normalized(data.get("architecture", {})).get("facade_windows", {}).get(facade, {}) as Dictionary
	_ignore_fields = true
	controls["facade_windows"].set_pressed_no_signal(bool(architecture_facade.get("enabled", override.get("windows", true))))
	for pair: Array in [["facade_width", "width", "window_width"], ["facade_height", "height", "window_height"], ["facade_sill", "sill", "window_sill"]]:
		_set_spin(str(pair[0]), float(architecture_facade.get(pair[1], override.get(pair[1], data.get(pair[2], 1.0)))))
	_ignore_fields = false
	_capture_local_baseline(["facade_windows", "facade_width", "facade_height", "facade_sill"])

func _update_override_status() -> void:
	var label: Label = controls["override_status"] as Label
	var data: Dictionary = snapshot()
	label.text = "楼层覆盖 %d · 立面覆盖 %d" % [data.get("floor_overrides", {}).size(), data.get("facade_overrides", {}).size()]

func _fill_component_option(key: String, family: String, current: String) -> void:
	var option: OptionButton = controls[key] as OptionButton
	option.clear()
	var components: Dictionary = session.catalog.get("components", {}) as Dictionary
	for component_id: String in Catalog.ids(session.catalog):
		var definition: Dictionary = components[component_id] as Dictionary
		if str(definition.get("family", "")) != family:
			continue
		option.add_item(component_id)
		option.set_item_metadata(option.item_count - 1, component_id)
		option.set_item_tooltip(option.item_count - 1, "%s\n%s · %s" % [component_id, str(definition.get("kind", "")), str(definition.get("prefab", definition.get("profile", "")))])
	_set_option(key, current)
	option.disabled = option.item_count == 0

func _update_slot_list() -> void:
	_slot_list.clear()
	_slot_ids.clear()
	var data: Dictionary = snapshot()
	var overrides: Dictionary = data.get("slot_overrides", {}) as Dictionary
	var excluded: Array = data.get("excluded_slots", []) as Array
	var ids: Dictionary = {}
	for raw: Variant in preview._slots:
		var slot: Dictionary = raw as Dictionary
		ids[str(slot.get("id", ""))] = true
	for id: Variant in overrides:
		ids[str(id)] = true
	for id: Variant in excluded:
		ids[str(id)] = true
	var sorted: Array = ids.keys()
	sorted.sort()
	for raw_id: Variant in sorted:
		var id: String = str(raw_id)
		var slot: Dictionary = _selected_slot_data(id)
		var override: Dictionary = overrides.get(id, {}) as Dictionary
		var disabled: bool = bool(override.get("disabled", false)) or excluded.has(id)
		var family: String = _slot_family(id, str(slot.get("kind", "")))
		var component: String = str(override.get("component_id", slot.get("component_id", data.get("component_bindings", {}).get(family, ""))))
		_slot_ids.append(id)
		var prefix: String = ""
		if disabled:
			prefix = "[已排除] "
		elif not _live_slot_ids.has(id):
			prefix = "[当前未生成] "
		_slot_list.add_item(prefix + id + " · " + component)
		_slot_list.set_item_tooltip(_slot_list.item_count - 1, "slot_id: %s\ncomponentID: %s" % [id, component])

func _selected_slot_data(id: String) -> Dictionary:
	if _live_slot_ids.has(id):
		return _slot_cache.get(id, {}) as Dictionary
	var cached: Dictionary = _slot_cache.get(id, {}) as Dictionary
	var family: String = _slot_family(id, str(cached.get("kind", "")))
	var data: Dictionary = snapshot()
	var override: Dictionary = data.get("slot_overrides", {}).get(id, {}) as Dictionary
	# 失效槽没有可靠的当前位置与包围盒，不把缓存几何用于锚点或替件。
	return {"id": id, "kind": family, "component_id": override.get("component_id", data.get("component_bindings", {}).get(family, ""))}

func _slot_family(id: String, kind: String) -> String:
	if id.begins_with("roof_") or id.begins_with("slab_"):
		return "slab"
	for family: String in Recipe.COMPONENT_ROLES:
		if id.begins_with(family + "_"):
			return family
	return kind

func _select_page(index: int) -> void:
	if index < 0 or index >= PAGES.size(): return
	_page_picker.select(index)
	for page_name: String in PAGES:
		pages[page_name].visible = page_name == PAGES[index]
	for module_index: int in PAGES.size():
		var module_button: Button = buttons.get("module_%02d" % module_index) as Button
		if module_button == null: continue
		var active: bool = module_index == index
		module_button.add_theme_stylebox_override("normal", _stylebox(Color("#28506a") if active else WORKSHOP_SURFACE, WORKSHOP_GOLD if active else WORKSHOP_LINE, 6, 2 if active else 1))
		module_button.add_theme_color_override("font_color", WORKSHOP_GOLD if active else WORKSHOP_TEXT)
	_set_status("已切换模块：" + PAGES[index], WORKSHOP_ACCENT_HOVER)

func _control_value(key: String) -> Variant:
	var control: Control = controls[key] as Control
	if control is Range:
		var value: float = (control as Range).value
		return int(value) if INTEGER_KEYS.has(key) or key in ["setback_start"] else value
	if control is CheckButton:
		return (control as CheckButton).button_pressed
	return _option_value(key)

func _set_control_value(key: String, value: Variant) -> void:
	var control: Control = controls[key] as Control
	if control is Range:
		(control as Range).set_value_no_signal(float(value))
		_update_range_readout(key)
	elif control is OptionButton:
		_set_option(key, str(value))
	elif control is CheckButton:
		(control as CheckButton).set_pressed_no_signal(bool(value))

func _spin_value(key: String) -> float:
	return (controls[key] as Range).value

func _set_spin(key: String, value: float) -> void:
	(controls[key] as Range).set_value_no_signal(value)
	_update_range_readout(key)

func _option_value(key: String) -> String:
	var option: OptionButton = controls[key] as OptionButton
	return str(option.get_item_metadata(option.selected)) if option.selected >= 0 else ""

func _set_option(key: String, value: String) -> void:
	var option: OptionButton = controls[key] as OptionButton
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return

func _set_architecture_control(key: String, value: Variant) -> void:
	if controls.has(key):
		_set_control_value(key, value)

func _on_session_changed() -> void:
	# 不在 changed 回调回填字段，避免槽位操作吞掉尚未应用的基础输入。
	_update_state()

func _on_text_changed(_text: String) -> void:
	_on_field_changed()

func _sync_window_dimension(key: String) -> void:
	if _ignore_fields or not _initialized or _option_value("construction_mode") != "shell_v2" or _window_scope() != "global":
		return
	for field: String in ["width", "height", "sill"]:
		var base: String = "window_" + field
		var advanced: String = "architecture_window_" + field
		if key == base and controls.has(advanced):
			_set_spin(advanced, _spin_value(base))
		elif key == advanced and controls.has(base):
			_set_spin(base, _spin_value(advanced))

func _on_field_changed() -> void:
	if not _ignore_fields:
		_update_state()

func _update_state() -> void:
	if not _initialized or state_label == null:
		return
	var data: Dictionary = snapshot()
	state_label.text = "%s · revision_%04d · %s" % [str(data.get("building_id", "")), int(data.get("revision", 1)), "未保存 / 有待应用字段" if has_pending_fields() else "已保存"]
	buttons["open_scene"].disabled = str(_last_export.get("scene_path", "")).is_empty()

func _cancel_discard() -> void:
	_confirm_action = Callable()
	_confirm.hide()

func _set_status(text: String, color: Color = WORKSHOP_MUTED) -> void:
	_last_status_text = text
	if status_label != null:
		status_label.text = text
		status_label.add_theme_color_override("font_color", WORKSHOP_TEXT)
	if status_panel != null:
		status_panel.add_theme_stylebox_override("panel", _stylebox(Color("#203b50") if color != WORKSHOP_WARN else Color("#4a2f2b"), color, 7, 2))
	if status_copy_button != null:
		status_copy_button.tooltip_text = "复制当前提示：" + text

func _report_failure(reason: String) -> Dictionary:
	_set_status("[警告] " + reason, WORKSHOP_WARN)
	return {"ok": false, "reason": reason}

func _report_result(result: Dictionary, prefix: String) -> Dictionary:
	var ok: bool = bool(result.get("ok", false))
	_set_status(("✓ " if ok else "⚠ ") + prefix + "：" + str(result.get("reason", "成功" if ok else "未知错误")), WORKSHOP_ACCENT_HOVER if ok else WORKSHOP_WARN)
	return result
