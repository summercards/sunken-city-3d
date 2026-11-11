@tool
extends Control
## 编辑器主屏只拥有 UI；会话、版本落盘和组件替换各走独立端口。

const Session = preload("res://src/workshop/session.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Preview = preload("res://addons/building_workshop/editor_preview.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const DEFAULT_ROOT: String = "res://scenes/workshop_buildings"
const SAMPLE_ROOT: String = "res://data/workshop/samples"
const PAGES: Array[String] = ["结构", "门窗", "破旧", "植物", "空间", "构架", "形体", "文件"]
const FORM_CATEGORIES: Array[String] = ["structure", "opening", "accessory"]
const FORM_LABELS: Dictionary = {"structure": "整楼结构", "opening": "窗户洞口", "accessory": "配件"}
const FORM_PRESETS: Dictionary = {
	"SF-A": {"structure": [0.020, 0.040], "opening": [0.020, 0.038], "accessory": [0.025, 0.060]},
	"SF-B": {"structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100]},
	"SF-C": {"structure": [0.060, 0.100], "opening": [0.055, 0.095], "accessory": [0.080, 0.150]}
}
const PARAMETER_KEYS: Array[String] = ["construction_mode", "shape", "width", "depth", "floors", "floor_height", "wall_thickness", "slab_thickness", "column_width", "window_width", "window_height", "window_sill", "bay_width", "door_width", "door_height", "aging", "damage", "bevel_segments", "bevel_width", "vegetation_density", "taper", "structure_seed", "damage_seed", "vegetation_seed", "spatial_profile"]
const ARCHITECTURE_WINDOW_FIELDS: Array[String] = ["enabled", "type", "open_angle", "frame_width", "frame_depth", "glass_thickness", "recess", "sill_enabled", "sill_projection", "sill_thickness", "sill_extension", "width", "height", "sill"]
const ARCHITECTURE_WINDOW_SCOPES: Array[String] = ["global", "floor", "facade", "single"]
const ARCHITECTURE_ROOF_FIELDS: Array[String] = ["mode", "height", "thickness", "cap_thickness", "cap_overhang", "post_spacing", "rail_spacing", "bar_width"]
const INTEGER_KEYS: Array[String] = ["floors", "bevel_segments", "structure_seed", "damage_seed", "vegetation_seed"]
const ROLE_LABELS: Dictionary = {"wall": "墙", "slab": "楼板 / 屋顶", "frame": "门窗框", "glass": "窗玻璃", "pillar": "柱", "plant": "植物"}

var session: Session
var preview: Preview
var buttons: Dictionary = {}
var controls: Dictionary = {}
var pages: Dictionary = {}
var architecture_panels: Array[Control] = []
var state_label: Label
var status_label: Label
var selected_slot_label: Label
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
		session = Session.new()
		session.replace_recipe(Recipe.authoring_defaults())
	_build_ui()
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

func apply_parameters() -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "编辑器主屏尚未初始化"}
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
	var accepted: Dictionary = session.accept_loaded(result.get("recipe", {}), result.get("catalog", {}))
	if not bool(accepted.get("ok", false)):
		return _report_result(accepted, "配方被拒绝")
	_slot_cache.clear()
	_selected_id = ""
	_last_export = {"scene_path": path.get_base_dir().path_join("building.tscn"), "recipe_path": path}
	_refresh_from_session()
	refresh_preview()
	_set_status("已打开：" + path)
	return accepted

func refresh_preview(preserve_slot_fields: bool = false) -> Dictionary:
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
	var result: Dictionary = session.build()
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
	var data: Dictionary = snapshot()
	var scope: String = _window_scope()
	var settings: Dictionary = {}
	if scope == "global":
		settings = _architecture_base_window(data)
	elif scope == "floor":
		var floor: int = int(_spin_value("floor_override_index"))
		var facade: String = _option_value("facade_index")
		settings = Config.window_settings(data, floor, facade)
		settings.merge(Config.normalized(data.get("architecture", {})).get("floor_windows", {}).get(str(floor), {}), true)
	elif scope == "facade":
		var floor_index: int = int(_spin_value("floor_override_index"))
		var current_facade: String = _option_value("facade_index")
		settings = Config.window_settings(data, floor_index, current_facade)
		settings.merge(Config.normalized(data.get("architecture", {})).get("facade_windows", {}).get(current_facade, {}), true)
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
	var keys: Array[String] = []
	if _window_scope() != "global":
		for field: String in ARCHITECTURE_WINDOW_FIELDS:
			keys.append("architecture_window_" + field)
		for field: String in ["width", "height", "sill"]:
			keys.append("architecture_window_" + field)
		for key: String in keys:
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
		if control is SpinBox:
			ui_values[key] = (control as SpinBox).value
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
	var cat: Dictionary = data.get("catalog", {}) as Dictionary
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
	return {"ok": true, "reason": "编辑器草稿已恢复"}

func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var toolbar_scroll: ScrollContainer = ScrollContainer.new()
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toolbar_scroll.custom_minimum_size.y = 42
	toolbar_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(toolbar_scroll)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar_scroll.add_child(toolbar)
	var toolbar_title: Label = _label("楼房工坊", 16)
	toolbar_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	toolbar_title.custom_minimum_size.x = 80
	toolbar.add_child(toolbar_title)
	for spec: Array in [["new", "新建"], ["open", "打开"], ["save", "保存并烘焙"], ["undo", "撤销"], ["redo", "重做"], ["open_scene", "在3D打开"], ["copy_sample", "复制样例"], ["save_as", "另存新ID"], ["toggle_left", "参数栏"], ["toggle_right", "槽位栏"]]:
		toolbar.add_child(_button(str(spec[1]), str(spec[0])))
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
	split.split_offset = 230
	outer_scroll.add_child(split)
	_left_panel = _make_left_panel()
	split.add_child(_left_panel)
	var inner: HSplitContainer = HSplitContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.split_offset = 340
	split.add_child(inner)
	var preview_body: VBoxContainer = VBoxContainer.new()
	preview_body.custom_minimum_size.x = 300
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
	root.add_child(_label("五件 bundle 仅为候选资产，尚未正式登记；不替换当前编辑场景或主场景。"))
	status_label = _label("编辑器独立主屏；无需运行游戏。")
	root.add_child(status_label)
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

func _make_left_panel() -> ScrollContainer:
	var scroll: ScrollContainer = _sidebar()
	var body: VBoxContainer = _sidebar_body(scroll)
	body.add_child(_label("建筑身份", 16))
	body.add_child(_label("building_id（另存请用顶部按钮）"))
	_id_edit = LineEdit.new()
	_id_edit.name = "building_id"
	_id_edit.text_changed.connect(_on_text_changed)
	body.add_child(_id_edit)
	controls["building_id"] = _id_edit
	body.add_child(_label("显示名称"))
	_name_edit = LineEdit.new()
	_name_edit.name = "display_name"
	_name_edit.text_changed.connect(_on_text_changed)
	body.add_child(_name_edit)
	controls["display_name"] = _name_edit
	_page_picker = OptionButton.new()
	for page_name: String in PAGES:
		_page_picker.add_item(page_name)
	_page_picker.item_selected.connect(_select_page)
	body.add_child(_page_picker)
	for page_name: String in PAGES:
		var page: VBoxContainer = VBoxContainer.new()
		page.visible = page_name == PAGES[0]
		body.add_child(page)
		pages[page_name] = page
		_build_page(page_name, page)
	body.add_child(_button("应用全部参数", "apply"))
	return scroll

func _build_page(page_name: String, page: VBoxContainer) -> void:
	match page_name:
		"结构":
			_add_option(page, "construction_mode", "建模内核", [["shell_v2", "连续实体 · 工整模型"], ["modular_v1", "旧版拼装 · 配方兼容"]])
			(controls["construction_mode"] as OptionButton).item_selected.connect(_construction_mode_changed)
			page.add_child(_label("连续墙壳／真实洞口／整板屋顶。新房默认先验干净结构。", 12))
			_add_option(page, "shape", "形状", [["rectangle", "矩形"], ["l", "L 形"]])
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
			for spec: Array in [["architecture_window_open_angle", "开启角度", 0.0, 80.0, 1.0], ["architecture_window_frame_width", "框宽", 0.04, 0.24, 0.01], ["architecture_window_frame_depth", "框深", 0.04, 0.5, 0.01], ["architecture_window_glass_thickness", "玻璃厚度", 0.005, 0.08, 0.005], ["architecture_window_recess", "窗框退入", 0.04, 0.5, 0.01], ["architecture_window_width", "架构窗宽", 0.25, 6.0, 0.01], ["architecture_window_height", "架构窗高", 0.25, 6.0, 0.01], ["architecture_window_sill", "架构窗台", 0.2, 5.0, 0.01]]:
				_spin_spec(window_panel, spec)
			_check("启用窗沿板", "architecture_window_sill_enabled", window_panel)
			for spec: Array in [["architecture_window_sill_projection", "窗沿外挑", 0.0, 10.0, 0.01], ["architecture_window_sill_thickness", "窗沿厚度", 0.001, 2.0, 0.001], ["architecture_window_sill_extension", "窗沿延伸", 0.0, 2.0, 0.01]]:
				_spin_spec(window_panel, spec)
			window_panel.add_child(_button("应用当前范围窗构造", "architecture_apply"))
			window_panel.add_child(_button("清除此范围覆盖", "architecture_clear"))
			window_panel.add_child(_button("应用到当前窗", "window_apply"))
			for key: String in ["architecture_window_enabled", "architecture_window_sill_enabled"]:
				_architecture_visibility.append(key)
			page.add_child(_label("基础窗宽高和旧版覆盖仍保留；架构字段只在shell_v2生效。", 12))
			for spec: Array in [["window_width", "窗宽", 0.1, 10, 0.1], ["window_height", "窗高", 0.1, 10, 0.1], ["window_sill", "窗台", 0.01, 10, 0.1], ["bay_width", "开间", 2, 6, 0.1], ["door_width", "门净宽", 0.1, 10, 0.1], ["door_height", "门净高", 0.1, 10, 0.1]]:
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
			controls["floor_override_index"].value_changed.connect(func(_value: float) -> void: _sync_floor_fields())
			controls["facade_index"].item_selected.connect(func(_index: int) -> void: _sync_facade_fields())
		"破旧":
			page.add_child(_label("连续实体模式暂不支持结构破损，damage须为0；不靠随机删块伪造工整残楼。旧拼装配方保留原能力。", 12))
			for spec: Array in [["aging", "表面老化", 0, 1, 0.01], ["damage", "结构破损", 0, 1, 0.01], ["bevel_segments", "倒角段数", 1, 8, 1], ["bevel_width", "倒角宽", 0.001, 0.5, 0.001]]:
				_spin_spec(page, spec)
			page.add_child(_label("真实破口也会移除对应碰撞；可在右侧禁用单槽。"))
		"植物":
			for spec: Array in [["vegetation_density", "植物密度", 0, 1, 0.01], ["growth_small", "小型比例", 0, 1, 0.01], ["growth_medium", "中型比例", 0, 1, 0.01], ["growth_large", "大型比例", 0, 1, 0.01]]:
				_spin_spec(page, spec)
			page.add_child(_label("植物品种在右侧全局绑定选择；锁定与排除针对选中槽位。"))
		"空间":
			_add_option(page, "spatial_profile", "空间职责", [["above_water", "水上功能"], ["scenic_underwater", "水下观赏"], ["dive_static", "潜水静态"]])
			_spin_spec(page, ["taper", "收分", 0, 0.1, 0.01])
			for pair: Array in [["structure_seed", "结构种子"], ["damage_seed", "破损种子"], ["vegetation_seed", "植物种子"]]:
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
	scroll.custom_minimum_size.x = 230
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll

func _sidebar_body(scroll: ScrollContainer) -> VBoxContainer:
	var body: VBoxContainer = VBoxContainer.new()
	body.custom_minimum_size.x = 210
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	return body

func _label(text: String, font_size: int = 14) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String, id: String) -> Button:
	var button: Button = Button.new()
	button.name = id
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(_button_pressed.bind(id))
	buttons[id] = button
	return button

func _check(text: String, key: String, parent: Control) -> CheckButton:
	var check: CheckButton = CheckButton.new()
	check.name = key
	check.text = text
	check.add_theme_font_size_override("font_size", 14)
	controls[key] = check
	parent.add_child(check)
	return check

func _add_option(parent: Control, key: String, title: String, options: Array) -> void:
	parent.add_child(_label(title))
	var option: OptionButton = OptionButton.new()
	option.name = key
	option.clip_text = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 14)
	for pair: Array in options:
		option.add_item(str(pair[1]))
		option.set_item_metadata(option.item_count - 1, str(pair[0]))
	option.item_selected.connect(func(_index: int) -> void: _on_field_changed())
	controls[key] = option
	parent.add_child(option)

func _spin_spec(parent: Control, spec: Array) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_label(str(spec[1])))
	var spin: SpinBox = SpinBox.new()
	spin.name = str(spec[0])
	spin.custom_minimum_size.x = 95
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.min_value = float(spec[2])
	spin.max_value = float(spec[3])
	spin.step = float(spec[4])
	spin.add_theme_font_size_override("font_size", 14)
	spin.value_changed.connect(func(_value: float) -> void: _on_field_changed())
	controls[str(spec[0])] = spin
	row.add_child(spin)
	parent.add_child(row)

func _button_pressed(id: String) -> void:
	match id:
		"new": _guard_action(_new_document, "新建将丢弃当前未保存修改，是否继续？")
		"open":
			_select_page(5)
			refresh_documents()
			_set_status("在左侧文件页选中已保存建筑，再点击打开；不必全盘查找。")
		"save": save_building()
		"save_as": _show_save_as()
		"undo": _undo(false)
		"redo": _undo(true)
		"apply", "apply_bindings": apply_parameters()
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
		_:
			if id.begins_with("view_"):
				preview.set_view(id.trim_prefix("view_"))

func _undo(redo: bool) -> void:
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
			_sample_picker.add_item(filename.trim_suffix(".recipe.json"))
			_sample_picker.set_item_metadata(_sample_picker.item_count - 1, SAMPLE_ROOT.path_join(filename))

func _request_sample(copy_as_new: bool) -> void:
	if _sample_picker.selected < 0:
		_set_status("项目中没有可加载的样例配方。")
		return
	var path: String = str(_sample_picker.get_item_metadata(_sample_picker.selected))
	_guard_action(_load_sample.bind(path, copy_as_new), "载入样例将丢弃当前未保存修改，是否继续？")

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

func _window_scope_changed(_index: int) -> void:
	if _ignore_fields:
		return
	if _has_pending_window_fields():
		_set_option("window_scope", _last_window_scope)
		_set_status("当前窗范围存在未应用输入，请先应用或清除后再切换范围。")
		return
	_sync_architecture_window_scope()
	_last_window_scope = _window_scope()
	_update_state()

func _window_selection_changed(_index: int) -> void:
	if _ignore_fields:
		return
	if _has_pending_window_fields():
		var pending_option: OptionButton = controls["window_selection"] as OptionButton
		for pending_index: int in pending_option.item_count:
			if str(pending_option.get_item_metadata(pending_index)) == _selected_opening_id:
				pending_option.select(pending_index)
				break
		_set_status("当前窗存在未应用输入，请先应用或清除后再切换窗口。")
		return
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
	var spin: SpinBox = controls["taper"] as SpinBox
	spin.editable = not form_enabled
	spin.tooltip_text = "由形体「整楼结构」区间 + 种子决定" if form_enabled else "关闭形体后可手动设定"

func _apply_architecture_window() -> Dictionary:
	if _option_value("construction_mode") != "shell_v2":
		return _report_failure("架构窗构造只在shell_v2连续实体模式生效。")
	var scope: String = _window_scope()
	if scope == "single" and _window_override_id().is_empty():
		return _report_failure("当前没有可应用的单窗；请选择实际窗口或已关闭窗口。")
	var result: Dictionary = session.apply_patch({"architecture": _architecture_ui_patch()})
	if bool(result.get("ok", false)):
		_refresh_from_session()
		refresh_preview()
		_set_status("%s窗构造已应用，可撤销。" % _window_scope_label(scope))
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
	if _window_scope() != "single":
		_set_option("window_scope", "single")
		_sync_architecture_window_scope()
	return _apply_architecture_window()

func _clear_architecture_window_scope() -> Dictionary:
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
	_sync_taper_ownership(bool((Config.normalized(data.get("architecture", {})).get("form", {}) as Dictionary).get("enabled", false)))
	# 刷新到 session 值之后，局部基线必须跟着对齐；否则载入配方会被误判成"存在未应用输入"，连保存都拦住。
	_capture_window_local_baseline()

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
	_page_picker.select(index)
	for page_name: String in PAGES:
		pages[page_name].visible = page_name == PAGES[index]

func _control_value(key: String) -> Variant:
	var control: Control = controls[key] as Control
	if control is SpinBox:
		var value: float = (control as SpinBox).value
		return int(value) if INTEGER_KEYS.has(key) or key in ["setback_start"] else value
	if control is CheckButton:
		return (control as CheckButton).button_pressed
	return _option_value(key)

func _set_control_value(key: String, value: Variant) -> void:
	var control: Control = controls[key] as Control
	if control is SpinBox:
		(control as SpinBox).set_value_no_signal(float(value))
	elif control is OptionButton:
		_set_option(key, str(value))
	elif control is CheckButton:
		(control as CheckButton).set_pressed_no_signal(bool(value))

func _spin_value(key: String) -> float:
	return (controls[key] as SpinBox).value

func _set_spin(key: String, value: float) -> void:
	(controls[key] as SpinBox).set_value_no_signal(value)

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

func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

func _report_failure(reason: String) -> Dictionary:
	_set_status(reason)
	return {"ok": false, "reason": reason}

func _report_result(result: Dictionary, prefix: String) -> Dictionary:
	_set_status(prefix + "：" + str(result.get("reason", "成功" if bool(result.get("ok", false)) else "未知错误")))
	return result
