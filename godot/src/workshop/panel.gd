extends CanvasLayer
class_name WorkshopPanel
## SEA-WORKSHOP V1 独立编辑器。只调用 WorkshopSession / WorkshopStore。

signal closed
signal opened

const Session = preload("res://src/workshop/session.gd")
const Store = preload("res://src/workshop/store.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const UiFontLib = preload("res://src/ui/ui_font.gd")
const Preview = preload("res://src/workshop/preview.gd")

var session
var preview
var export_root := "user://building_workshop"
var standalone := false
var buttons: Dictionary = {}
var controls: Dictionary = {}
var pages: Dictionary = {}
var status_label: Label
var selected_slot_label: Label
var _open := false
var _was_paused := false
var _font: Font
var _page_picker: OptionButton
var _slot_list: ItemList
var _id_edit: LineEdit
var _name_edit: LineEdit
var _confirm: ConfirmationDialog
var _file_dialog: FileDialog
var _last_export: Dictionary = {}
var _ignore_fields := false
var _confirm_mode := ""
var _pending_recipe_path := ""
var _range_readouts: Dictionary = {}

func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UiFontLib.make(PackedStringArray())
	if session == null:
		session = Session.new()
	_build_ui()
	visible = false
	if not session.changed.is_connected(_on_session_changed):
		session.changed.connect(_on_session_changed)
	if standalone:
		call_deferred("_open_standalone_if_current")

func _open_standalone_if_current() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		open()

func configure(ports: Dictionary = {}) -> void:
	if ports.has("export_root"):
		export_root = str(ports["export_root"])
	elif ports.has("base_dir"):
		export_root = str(ports["base_dir"])
	if ports.has("standalone"):
		standalone = bool(ports["standalone"])
	if controls.has("export_root_label"):
		controls["export_root_label"].text = export_root
	if ports.has("session") and ports["session"] != null:
		if session != null and session.changed.is_connected(_on_session_changed):
			session.changed.disconnect(_on_session_changed)
		session = ports["session"]
		if not session.changed.is_connected(_on_session_changed):
			session.changed.connect(_on_session_changed)
		_refresh_from_session()

func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused if is_inside_tree() else false
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	if is_inside_tree():
		get_tree().paused = true
	_refresh_from_session()
	refresh_preview()
	opened.emit()

func request_close() -> void:
	if not _open:
		return
	if _confirm != null and _confirm.visible:
		return
	if has_pending_fields():
		_confirm_mode = "close"
		_confirm.dialog_text = "当前配方未导出。关闭不会写入候选目录，确定退出并保留本次草稿？"
		_confirm.popup_centered()
		_confirm.get_cancel_button().grab_focus()
		return
	close_now()

func close_now() -> void:
	if not _open and not visible:
		return
	if _confirm != null:
		_confirm.hide()
	_open = false
	visible = false
	if is_inside_tree():
		get_tree().paused = _was_paused
	closed.emit()

func is_open() -> bool:
	return _open

func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var text_focus := focus is LineEdit or focus is TextEdit
	var code := key.keycode if key.keycode != 0 else key.physical_keycode
	if code == KEY_ESCAPE:
		if text_focus:
			focus.release_focus()
			return true
		request_close()
		return true
	if key.ctrl_pressed and not text_focus:
		if code == KEY_Z:
			if session.undo(): refresh_preview()
			return true
		if code == KEY_Y:
			if session.redo(): refresh_preview()
			return true
		if code == KEY_S:
			export_current()
			return true
	return false

func export_current() -> Dictionary:
	var applied: Dictionary = _apply_all_fields(false)
	if not bool(applied.get("ok", false)):
		return applied
	var result: Dictionary = Store.new().export_revision(session.snapshot(), session.catalog, export_root)
	_last_export = result
	if result.get("ok", false):
		var exported_recipe: Variant = result.get("recipe", {})
		if exported_recipe is Dictionary and exported_recipe.has("revision"):
			var synced: Dictionary = session.sync_exported_revision(int(exported_recipe.revision))
			if not bool(synced.get("ok", false)):
				_set_status("导出成功但版本同步失败：%s" % str(synced.get("reason", "未知错误")), Color("#f2a18e"))
				return result
		else:
			session.mark_saved()
		_set_status("已导出候选版本：%s" % str(result.get("directory", "")), Color("#9be0b9"))
	else:
		_set_status("导出失败：%s（仍保留未保存状态）" % str(result.get("reason", "未知错误")), Color("#f2a18e"))
	return result

func refresh_preview() -> Dictionary:
	if session == null or preview == null:
		return {"ok": false, "reason": "预览未初始化"}
	var result: Dictionary = session.build()
	if result.get("ok", false):
		preview.set_build_result(result)
		_update_slot_list()
		_update_stats(result)
		_set_status("预览已刷新 · %d 个槽位" % int(result.get("slots", []).size()), Color("#a9d7de"))
	else:
		_set_status("预览失败：%s" % str(result.get("reason", "未知错误")), Color("#f2a18e"))
	return result

func has_pending_fields() -> bool:
	if session != null and session.is_dirty():
		return true
	if session == null or _id_edit == null or _name_edit == null:
		return false
	var current: Dictionary = session.snapshot()
	var candidate: Dictionary = current.duplicate(true)
	var patch: Dictionary = _collect_ui_patch()
	for key in patch.keys():
		candidate[key] = patch[key]
	return str(Recipe.fingerprint(candidate)) != str(Recipe.fingerprint(current))

func _collect_ui_patch() -> Dictionary:
	var patch: Dictionary = {"building_id": _id_edit.text.strip_edges(), "display_name": _name_edit.text}
	for key in ["shape", "width", "depth", "floors", "floor_height", "wall_thickness", "slab_thickness", "column_width", "window_width", "window_height", "window_sill", "bay_width", "door_width", "door_height", "aging", "damage", "bevel_segments", "bevel_width", "vegetation_density", "taper", "structure_seed", "damage_seed", "vegetation_seed", "spatial_profile"]:
		if controls.has(key):
			patch[key] = _control_value(key)
	if controls.has("plant_component"):
		var bindings: Dictionary = session.snapshot().get("component_bindings", {}) as Dictionary
		bindings["plant"] = _option_value("plant_component")
		patch["component_bindings"] = bindings
	if controls.has("growth_small"):
		patch["growth_weights"] = [_spin_value("growth_small"), _spin_value("growth_medium"), _spin_value("growth_large")]
	return patch

func select_slot(id: String) -> void:
	if preview != null:
		preview.select_slot(id, false)
	_update_slot_details(id)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "WorkshopBackground"
	background.color = Color(0.035, 0.055, 0.075, 0.98)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_meta("cozy_skip", true)
	add_child(background)
	var root := MarginContainer.new()
	root.name = "WorkshopLayout"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 22)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_right", 22)
	root.add_theme_constant_override("margin_bottom", 16)
	background.add_child(root)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	root.add_child(page)
	page.add_child(_make_toolbar())
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	page.add_child(columns)
	columns.add_child(_make_left_panel())
	preview = Preview.new()
	preview.name = "WorkshopPreview"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(400, 500)
	preview.slot_selected.connect(select_slot)
	columns.add_child(preview)
	columns.add_child(_make_right_panel())
	status_label = _label("尚未导出候选", 16, Color("#a9d7de"))
	status_label.custom_minimum_size = Vector2(0, 30)
	page.add_child(status_label)
	_confirm = ConfirmationDialog.new()
	_confirm.name = "WorkshopConfirm"
	_confirm.ok_button_text = "确认"
	_confirm.cancel_button_text = "取消"
	_confirm.confirmed.connect(_confirm_action)
	add_child(_confirm)
	_file_dialog = FileDialog.new()
	_file_dialog.name = "RecipeFileDialog"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.recipe.json ; 楼房配方 JSON"])
	_file_dialog.file_selected.connect(_load_selected_recipe)
	add_child(_file_dialog)

func _make_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 50)
	bar.add_theme_constant_override("separation", 7)
	bar.add_child(_title("楼房工坊", 24, Color("#f4e8c3")))
	bar.add_child(_spacer())
	for spec in [["new", "新建"], ["open", "打开"], ["save_as", "更换楼房ID"], ["export", "导出"], ["undo", "撤销"], ["redo", "重做"], ["close", "退出"]]:
		var button := _button(spec[1], spec[0])
		bar.add_child(button)
		buttons[spec[0]] = button
	return bar

func _make_left_panel() -> Control:
	var panel := _panel(Color(0.055, 0.08, 0.10, 1.0))
	panel.custom_minimum_size = Vector2(300, 0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(260, 0)
	body.add_theme_constant_override("separation", 9)
	scroll.add_child(body)
	body.add_child(_section_title("文档"))
	_id_edit = _line_edit("building_id", "building_id")
	_name_edit = _line_edit("display_name", "显示名称")
	body.add_child(_label("楼房 ID", 16, Color("#a9d7de"))); body.add_child(_id_edit)
	body.add_child(_label("显示名称", 16, Color("#a9d7de"))); body.add_child(_name_edit)
	body.add_child(_section_title("编辑页"))
	_page_picker = OptionButton.new()
	_page_picker.add_theme_font_override("font", _font)
	_page_picker.add_theme_font_size_override("font_size", 16)
	for page_name in ["结构", "门窗", "破旧", "植物", "空间", "文件"]: _page_picker.add_item(page_name)
	_page_picker.item_selected.connect(_select_page)
	body.add_child(_page_picker)
	for page_name in ["结构", "门窗", "破旧", "植物", "空间", "文件"]:
		var page := VBoxContainer.new()
		page.name = page_name
		page.add_theme_constant_override("separation", 8)
		body.add_child(page)
		pages[page_name] = page
		page.visible = page_name == "结构"
		_build_page(page_name, page)
	var apply := _button("应用本页参数", "apply")
	body.add_child(apply)
	return panel

func _build_page(page_name: String, page: VBoxContainer) -> void:
	if page_name == "结构":
		_add_option(page, "shape", "形状", [["rectangle", "矩形"], ["l", "L 形"]])
		_add_spin(page, "width", "宽度", 6.0, 24.0, 0.1)
		_add_spin(page, "depth", "进深", 6.0, 20.0, 0.1)
		_add_spin(page, "floors", "楼层", 1.0, 8.0, 1.0)
		_add_spin(page, "floor_height", "层高", 1.0, 20.0, 0.1)
		_add_spin(page, "wall_thickness", "墙厚", 0.01, 2.0, 0.01)
		_add_spin(page, "slab_thickness", "板厚", 0.01, 2.0, 0.01)
		_add_spin(page, "column_width", "主柱", 0.01, 2.0, 0.01)
	elif page_name == "门窗":
		_add_spin(page, "window_width", "默认窗宽", 0.1, 10.0, 0.1)
		_add_spin(page, "window_height", "默认窗高", 0.1, 10.0, 0.1)
		_add_spin(page, "window_sill", "默认窗台", 0.0, 10.0, 0.1)
		_add_spin(page, "bay_width", "开间", 0.2, 20.0, 0.1)
		_add_spin(page, "door_width", "门宽", 0.1, 10.0, 0.1)
		_add_spin(page, "door_height", "门高", 0.1, 10.0, 0.1)
		page.add_child(_section_title("逐层覆盖"))
		_add_spin(page, "floor_override_index", "楼层索引", 0.0, 7.0, 1.0)
		_add_spin(page, "floor_override_height", "覆盖层高", 0.1, 20.0, 0.1)
		_add_spin(page, "floor_override_window_width", "覆盖窗宽", 0.1, 10.0, 0.1)
		_add_spin(page, "floor_override_window_height", "覆盖窗高", 0.1, 10.0, 0.1)
		_add_spin(page, "floor_override_sill", "覆盖窗台", 0.0, 10.0, 0.1)
		var floor_buttons := HBoxContainer.new()
		floor_buttons.add_child(_button("应用楼层覆盖", "floor_apply"))
		floor_buttons.add_child(_button("清除楼层覆盖", "floor_clear"))
		page.add_child(floor_buttons)
		page.add_child(_section_title("逐立面覆盖"))
		_add_option(page, "facade_index", "立面", [["front", "正面"], ["back", "背面"], ["left", "左侧"], ["right", "右侧"]])
		var windows := CheckButton.new(); windows.name = "facade_windows"; windows.text = "显示窗洞"; windows.add_theme_font_size_override("font_size", 16); controls["facade_windows"] = windows; page.add_child(windows)
		_add_spin(page, "facade_width", "立面窗宽", 0.1, 10.0, 0.1)
		_add_spin(page, "facade_height", "立面窗高", 0.1, 10.0, 0.1)
		_add_spin(page, "facade_sill", "立面窗台", 0.0, 10.0, 0.1)
		var facade_buttons := HBoxContainer.new()
		facade_buttons.add_child(_button("应用立面覆盖", "facade_apply"))
		facade_buttons.add_child(_button("清除立面覆盖", "facade_clear"))
		page.add_child(facade_buttons)
		controls["override_status"] = _label("覆盖状态：无", 16, Color("#b8c9c5")); page.add_child(controls["override_status"])
	elif page_name == "破旧":
		_add_spin(page, "aging", "老化", 0.0, 1.0, 0.01)
		_add_spin(page, "damage", "破损", 0.0, 1.0, 0.01)
		_add_spin(page, "bevel_segments", "倒角段数", 1.0, 8.0, 1.0)
		_add_spin(page, "bevel_width", "倒角宽", 0.001, 0.5, 0.01)
	elif page_name == "植物":
		_add_spin(page, "vegetation_density", "植物密度", 0.0, 1.0, 0.01)
		_add_spin(page, "growth_small", "小型比例", 0.0, 1.0, 0.01)
		_add_spin(page, "growth_medium", "中型比例", 0.0, 1.0, 0.01)
		_add_spin(page, "growth_large", "大型比例", 0.0, 1.0, 0.01)
		_add_option(page, "growth_key", "锁定生长档", [["small", "小型"], ["medium", "中型"], ["large", "大型"]])
		var lock := CheckButton.new(); lock.name = "vegetation_lock"; lock.text = "锁定植物锚点"; lock.add_theme_font_size_override("font_size", 16); controls["vegetation_lock"] = lock; page.add_child(lock)
	elif page_name == "空间":
		_add_option(page, "spatial_profile", "空间职责", [["above_water", "水上功能"], ["scenic_underwater", "水下观赏"], ["dive_static", "潜水静态"]])
		_add_spin(page, "taper", "收分", 0.0, 0.1, 0.01)
		_add_seed(page, "structure_seed", "结构种子")
		_add_seed(page, "damage_seed", "破损种子")
		_add_seed(page, "vegetation_seed", "植物种子")
	elif page_name == "文件":
		controls["export_root_label"] = _label(export_root, 16, Color("#d6cfae")); controls["export_root_label"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; page.add_child(controls["export_root_label"])
		page.add_child(_label("默认只写 user://building_workshop。测试可注入 user:// 隔离目录或 res://outputs。不会加载 TSCN。", 16, Color("#b8c9c5")))

func _make_right_panel() -> Control:
	var panel := _panel(Color(0.055, 0.08, 0.10, 1.0))
	panel.custom_minimum_size = Vector2(260, 0)
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; panel.add_child(scroll)
	var body := VBoxContainer.new(); body.custom_minimum_size = Vector2(0, 0); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 9); scroll.add_child(body)
	body.add_child(_section_title("预览"))
	var views := HBoxContainer.new()
	for pair in [["front", "正面"], ["back", "背面"], ["top", "俯视"], ["perspective", "透视"]]:
		var b := _button(pair[1], "view_" + pair[0]); b.pressed.connect(func(kind: String = pair[0]) -> void: preview.set_view(kind)); views.add_child(b)
	body.add_child(views)
	var overlays := HBoxContainer.new()
	var wire := CheckButton.new(); wire.text = "线框"; wire.add_theme_font_size_override("font_size", 16); wire.toggled.connect(func(v: bool) -> void: preview.set_wireframe(v)); overlays.add_child(wire)
	var collision := CheckButton.new(); collision.text = "实际碰撞"; collision.add_theme_font_size_override("font_size", 16); collision.toggled.connect(func(v: bool) -> void: preview.set_collision_overlay(v)); overlays.add_child(collision)
	body.add_child(overlays)
	body.add_child(_section_title("选中槽位"))
	selected_slot_label = _label("未选择", 17, Color("#f4e8c3")); selected_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(selected_slot_label)
	_slot_list = ItemList.new(); _slot_list.custom_minimum_size = Vector2(0, 240); _slot_list.add_theme_font_size_override("font_size", 16); _slot_list.item_selected.connect(func(index: int) -> void: _slot_list_selected(index)); body.add_child(_slot_list)
	body.add_child(_section_title("全局植物组件"))
	_add_option(body, "plant_component", "植物组件", [])
	_refresh_plant_component_options()
	body.add_child(_section_title("组件替换与位置偏移"))
	var component := OptionButton.new(); component.name = "component_id"; component.clip_text = true; component.add_theme_font_override("font", _font); component.add_theme_font_size_override("font_size", 16); controls["component_id"] = component; body.add_child(component)
	_add_spin_to(body, "offset_x", "偏移 X", -10.0, 10.0, 0.05); _add_spin_to(body, "offset_y", "偏移 Y", -10.0, 10.0, 0.05); _add_spin_to(body, "offset_z", "偏移 Z", -10.0, 10.0, 0.05)
	body.add_child(_button("应用槽位修改", "slot_apply"))
	body.add_child(_label("组件选项按槽族筛选；不兼容组件会禁用。", 16, Color("#b8c9c5")))
	body.add_child(_section_title("统计"))
	controls["stats"] = _label("等待生成", 16, Color("#b8c9c5")); controls["stats"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(controls["stats"])
	return panel

func _button(text: String, id: String) -> Button:
	var button := Button.new(); button.custom_minimum_size.x = maxf(48.0, _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 20.0); button.text = text; button.name = id; button.clip_text = true; button.focus_mode = Control.FOCUS_ALL; button.add_theme_font_override("font", _font); button.add_theme_font_size_override("font_size", 16); button.set_meta("cozy_skip", true); button.pressed.connect(func() -> void: _button_pressed(id)); return button

func _button_pressed(id: String) -> void:
	match id:
		"new": _request_new()
		"open": _request_open()
		"save_as": _apply_all_fields(true)
		"export": export_current()
		"undo": if session.undo(): refresh_preview()
		"redo": if session.redo(): refresh_preview()
		"close": request_close()
		"apply": _apply_all_fields(false)
		"slot_apply": _apply_slot_override()
		"floor_apply": _apply_floor_override(false)
		"floor_clear": _apply_floor_override(true)
		"facade_apply": _apply_facade_override(false)
		"facade_clear": _apply_facade_override(true)

func _request_new() -> void:
	if has_pending_fields():
		_confirm_mode = "new"; _confirm.dialog_text = "当前配方未导出。确认丢弃当前草稿并新建？"; _confirm.popup_centered(); _confirm.get_cancel_button().grab_focus()
	else: _new_document()

func _request_open() -> void:
	if has_pending_fields():
		_confirm_mode = "open_dialog"; _confirm.dialog_text = "当前配方未导出。确认丢弃当前草稿并打开文件？"; _confirm.popup_centered(); _confirm.get_cancel_button().grab_focus()
	else: _show_file_dialog()

func _confirm_action() -> void:
	match _confirm_mode:
		"close": close_now()
		"new": _new_document()
		"open_dialog": _show_file_dialog()
	_confirm_mode = ""

func _new_document() -> void:
	var result: Dictionary = session.new_document()
	if result.ok: _refresh_from_session(); refresh_preview()
	else: _set_status("新建失败：%s" % result.reason, Color("#f2a18e"))

func _show_file_dialog() -> void:
	_file_dialog.current_dir = export_root
	_file_dialog.popup_centered_ratio(0.8)

func _apply_all_fields(identity_only: bool = false) -> Dictionary:
	var patch: Dictionary = _collect_ui_patch() if not identity_only else {"building_id": _id_edit.text.strip_edges(), "display_name": _name_edit.text}
	var result: Dictionary = session.apply_patch(patch)
	if result.ok:
		_set_status("参数已原子应用" if not identity_only else "楼房 ID 已更新", Color("#9be0b9"))
		_refresh_from_session(); refresh_preview()
	else:
		_set_status("修改被拒绝：%s" % result.reason, Color("#f2a18e"))
	return result

func _apply_slot_override() -> void:
	var slot_id: String = preview.selected_slot()
	if slot_id.is_empty(): _set_status("请先选择一个槽位。", Color("#f0d99b")); return
	var patch: Dictionary = {"offset": [_spin_value("offset_x"), _spin_value("offset_y"), _spin_value("offset_z")]}
	var component: OptionButton = controls["component_id"]
	if component.selected >= 0 and not component.disabled:
		var component_id := str(component.get_item_metadata(component.selected))
		if not component_id.is_empty(): patch["component_id"] = component_id
	var slot: Dictionary = _selected_slot_data(slot_id)
	if str(slot.get("kind", "")) == "plant":
		var growth: String = _option_value("growth_key")
		var position: Array = _bottom_center(slot)
		var lock: CheckButton = controls["vegetation_lock"]
		var result_lock: Dictionary = session.set_vegetation_lock(slot_id, position, growth, lock.button_pressed)
		if not result_lock.ok: _set_status("植物锁定被拒绝：%s" % result_lock.reason, Color("#f2a18e")); return
	var result: Dictionary = session.set_slot_override(slot_id, patch)
	if result.ok: refresh_preview()
	else: _set_status("槽位修改被拒绝：%s" % result.reason, Color("#f2a18e"))

func _apply_floor_override(clear: bool) -> void:
	var index: int = int(_spin_value("floor_override_index"))
	var overrides: Dictionary = session.snapshot().get("floor_overrides", {}) as Dictionary
	if clear: overrides.erase(str(index))
	else: overrides[str(index)] = {"floor_height": _spin_value("floor_override_height"), "window_width": _spin_value("floor_override_window_width"), "window_height": _spin_value("floor_override_window_height"), "window_sill": _spin_value("floor_override_sill")}
	var result: Dictionary = session.apply_patch({"floor_overrides": overrides})
	if result.ok:
		_set_status("楼层覆盖已%s" % ("清除" if clear else "应用"), Color("#9be0b9"))
		refresh_preview()
	else:
		_set_status("楼层覆盖被拒绝：%s" % result.reason, Color("#f2a18e"))

func _apply_facade_override(clear: bool) -> void:
	var facade: String = _option_value("facade_index")
	var overrides: Dictionary = session.snapshot().get("facade_overrides", {}) as Dictionary
	if clear: overrides.erase(facade)
	else: overrides[facade] = {"windows": bool(controls["facade_windows"].button_pressed), "width": _spin_value("facade_width"), "height": _spin_value("facade_height"), "sill": _spin_value("facade_sill")}
	var result: Dictionary = session.apply_patch({"facade_overrides": overrides})
	if result.ok:
		_set_status("立面覆盖已%s" % ("清除" if clear else "应用"), Color("#9be0b9"))
		refresh_preview()
	else:
		_set_status("立面覆盖被拒绝：%s" % result.reason, Color("#f2a18e"))

func _load_selected_recipe(path: String) -> void:
	var result: Dictionary = Store.new().load_recipe(path)
	if not result.ok: _set_status("打开失败：%s" % result.reason, Color("#f2a18e")); return
	var accepted: Dictionary = session.accept_loaded(result.recipe, result.catalog)
	if accepted.ok: _refresh_from_session(); refresh_preview()
	else: _set_status("配方未载入：%s" % accepted.reason, Color("#f2a18e"))

func _on_session_changed() -> void:
	if _open: _refresh_from_session()

func _refresh_from_session() -> void:
	if session == null or _id_edit == null: return
	var data: Dictionary = session.snapshot(); _ignore_fields = true
	_id_edit.text = str(data.get("building_id", "")); _name_edit.text = str(data.get("display_name", ""))
	for key in ["shape", "width", "depth", "floors", "floor_height", "wall_thickness", "slab_thickness", "column_width", "window_width", "window_height", "window_sill", "bay_width", "door_width", "door_height", "aging", "damage", "bevel_segments", "bevel_width", "vegetation_density", "taper", "structure_seed", "damage_seed", "vegetation_seed", "spatial_profile"]:
		if controls.has(key) and data.has(key): _set_control_value(key, data[key])
	_refresh_plant_component_options(str(data.get("component_bindings", {}).get("plant", "")))
	var weights: Array = data.get("growth_weights", [0.3, 0.4, 0.3]) as Array; _set_spin("growth_small", weights[0]); _set_spin("growth_medium", weights[1]); _set_spin("growth_large", weights[2])
	_ignore_fields = false
	_update_slot_list(); _update_overrides_status(data)

func _update_slot_list() -> void:
	if _slot_list == null or preview == null: return
	_slot_list.clear()
	for slot in preview._slots: _slot_list.add_item("%s · %s · F%s" % [slot.get("id", ""), slot.get("kind", ""), slot.get("floor", 0)])

func _slot_list_selected(index: int) -> void:
	if index >= 0 and index < preview._slots.size(): select_slot(str(preview._slots[index].get("id", "")))

func _update_slot_details(id: String) -> void:
	selected_slot_label.text = "选中：%s" % id if not id.is_empty() else "未选择"
	var slot: Dictionary = _selected_slot_data(id); var override: Dictionary = session.snapshot().get("slot_overrides", {}).get(id, {}) as Dictionary
	_refresh_component_options(str(slot.get("kind", "")), str(slot.get("id", "")), str(override.get("component_id", slot.get("component_id", ""))))
	var offset: Array = override.get("offset", [0.0, 0.0, 0.0]); _set_spin("offset_x", offset[0]); _set_spin("offset_y", offset[1]); _set_spin("offset_z", offset[2])
	if str(slot.get("kind", "")) == "plant":
		var locked := false
		for entry in session.snapshot().get("locked_vegetation", []):
			if str(entry.get("slot_id", "")) == id: locked = true; _set_option("growth_key", str(entry.get("growth_key", "medium")))
		controls["vegetation_lock"].button_pressed = locked

func _refresh_plant_component_options(current_component: String = "") -> void:
	if not controls.has("plant_component"):
		return
	var option: OptionButton = controls["plant_component"]
	option.clear()
	var components: Dictionary = session.catalog.get("components", {}) as Dictionary
	for component_id in components.keys():
		if str(components[component_id].get("family", "")) == "plant":
			option.add_item(str(component_id))
			option.set_item_metadata(option.item_count - 1, str(component_id))
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == current_component:
			option.select(index)
			return
	if option.item_count > 0:
		option.select(0)

func _refresh_component_options(kind: String, slot_id: String, current_component: String = "") -> void:
	var option: OptionButton = controls["component_id"]; option.clear(); option.disabled = true
	option.add_item("保持当前组件"); option.set_item_metadata(0, "")
	var family: String = _slot_family(slot_id, kind); var components: Dictionary = session.catalog.get("components", {}) as Dictionary
	for component_id in components.keys():
		if str(components[component_id].get("family", "")) == family:
			option.add_item(str(component_id))
			option.set_item_metadata(option.item_count - 1, str(component_id))
	for index in option.item_count:
		if option.get_item_text(index) == current_component: option.select(index); break
	if current_component.is_empty(): option.select(0)
	option.disabled = option.item_count <= 1

func _update_overrides_status(data: Dictionary) -> void:
	if controls.has("override_status"):
		controls["override_status"].text = "楼层覆盖：%d · 立面覆盖：%d" % [data.get("floor_overrides", {}).size(), data.get("facade_overrides", {}).size()]

func _update_stats(result: Dictionary) -> void:
	var stats: Dictionary = result.get("stats", {})
	controls["stats"].text = "槽位：%d\n行走面：%d\n水面阻挡：%d\n网格三角形：%d\n节点：%d\n碰撞形状：%d\n植物网格：%d" % [result.get("slots", []).size(), result.get("walk_surfaces", []).size(), result.get("water_blockers", []).size(), int(stats.get("triangles", 0)), int(stats.get("nodes", 0)), int(stats.get("collision_shapes", 0)), int(stats.get("plant_meshes", 0))]
	controls["stats"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls["stats"].custom_minimum_size = Vector2(0, 0)

func _select_page(index: int) -> void:
	var names := ["结构", "门窗", "破旧", "植物", "空间", "文件"]
	for key in pages.keys(): pages[key].visible = key == names[index]

func _add_option(parent: Control, key: String, title: String, values: Array) -> void:
	var option := OptionButton.new(); option.name = key; option.add_theme_font_override("font", _font); option.add_theme_font_size_override("font_size", 16)
	for pair in values: option.add_item(pair[1]); option.set_item_metadata(option.item_count - 1, pair[0])
	controls[key] = option; parent.add_child(_label(title, 16, Color("#b8c9c5"))); parent.add_child(option)

func _add_spin(parent: Control, key: String, title: String, minimum: float, maximum: float, step: float) -> void:
	_add_spin_to(parent, key, title, minimum, maximum, step)

func _add_spin_to(parent: Control, key: String, title: String, minimum: float, maximum: float, step: float) -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	var readout := _label("", 14, Color("#a9bdca"))
	body.add_child(readout)
	var slider := HSlider.new()
	slider.name = key
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 30
	slider.focus_mode = Control.FOCUS_ALL
	var track := _style(Color("#23364d"), Color("#385b7a"), 6)
	var fill := _style(Color("#46c2d7"), Color("#70e0e8"), 6)
	var grab := _style(Color("#f1c56b"), Color("#fff0b8"), 8)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_stylebox_override("grabber", grab)
	controls[key] = slider
	_range_readouts[key] = {"label": readout, "title": title, "step": step}
	slider.value_changed.connect(func(_value: float) -> void:
		_update_range_readout(key)
		_set_status("已调整「%s」，点击应用本页参数" % title, Color("#f1c56b")))
	body.add_child(slider)
	parent.add_child(body)
	_update_range_readout(key)

func _add_seed(parent: Control, key: String, title: String) -> void: _add_spin(parent, key, title, 0.0, 2147483647.0, 1.0)

func _line_edit(key: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new(); edit.name = key; edit.placeholder_text = placeholder; edit.add_theme_font_override("font", _font); edit.add_theme_font_size_override("font_size", 16); edit.set_meta("cozy_skip", true); return edit

func _control_value(key: String):
	if controls[key] is Range:
		var value: float = float(controls[key].value)
		return int(value) if key in ["floors", "bevel_segments", "structure_seed", "damage_seed", "vegetation_seed"] else value
	return _option_value(key)

func _set_control_value(key: String, value) -> void:
	if controls[key] is Range:
		(controls[key] as Range).set_value_no_signal(float(value))
		_update_range_readout(key)
	elif controls[key] is OptionButton: _set_option(key, str(value))

func _spin_value(key: String) -> float: return float((controls[key] as Range).value)
func _set_spin(key: String, value) -> void:
	(controls[key] as Range).set_value_no_signal(float(value))
	_update_range_readout(key)

func _update_range_readout(key: String) -> void:
	if not _range_readouts.has(key) or not controls.has(key): return
	var entry: Dictionary = _range_readouts[key]
	var slider: Range = controls[key] as Range
	var step: float = float(entry.get("step", slider.step))
	var decimals: int = 0 if step >= 1.0 else (2 if step >= 0.01 else 3)
	var current: String = str(int(roundi(slider.value))) if decimals == 0 else String.num(slider.value, decimals)
	var minimum: String = str(int(roundi(slider.min_value))) if decimals == 0 else String.num(slider.min_value, decimals)
	var maximum: String = str(int(roundi(slider.max_value))) if decimals == 0 else String.num(slider.max_value, decimals)
	(entry.label as Label).text = "%s  %s    [%s – %s]" % [entry.title, current, minimum, maximum]
func _option_value(key: String) -> String:
	var option: OptionButton = controls[key]; return str(option.get_item_metadata(option.selected)) if option.selected >= 0 else ""
func _set_option(key: String, value: String) -> void:
	var option: OptionButton = controls[key]
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value: option.select(index); return

func _selected_slot_data(id: String) -> Dictionary:
	for slot in preview._slots:
		if str(slot.get("id", "")) == id: return slot
	return {}

func _bottom_center(slot: Dictionary) -> Array:
	var position: Array = slot.get("position", [0.0, 0.0, 0.0])
	return [float(position[0]), float(position[1]), float(position[2])]

func _slot_family(slot_id: String, kind: String) -> String:
	if slot_id.begins_with("wall_"): return "wall"
	if slot_id.begins_with("slab_") or slot_id.begins_with("roof_"): return "slab"
	if slot_id.begins_with("pillar_"): return "pillar"
	if slot_id.begins_with("frame_"): return "frame"
	if slot_id.begins_with("glass_"): return "glass"
	if slot_id.begins_with("plant_") or kind == "plant": return "plant"
	return kind

func _panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel", _style(color, Color(0.30, 0.72, 0.70, 0.36), 8)); return panel

func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = color; style.border_color = border; style.set_border_width_all(1); style.set_corner_radius_all(radius); style.content_margin_left = 12; style.content_margin_right = 12; style.content_margin_top = 10; style.content_margin_bottom = 10; return style

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new(); label.text = text; label.custom_minimum_size = Vector2(0, 0); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.add_theme_font_override("font", _font); label.add_theme_font_size_override("font_size", size); label.add_theme_color_override("font_color", color); label.set_meta("cozy_skip", true); return label
func _title(text: String, size: int, color: Color) -> Label: return _label(text, size, color)
func _section_title(text: String) -> Label: return _label("── %s ──" % text, 17, Color("#f0d99b"))
func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _set_status(text: String, color: Color) -> void:
	if status_label != null:
		status_label.text = text
		status_label.add_theme_color_override("font_color", color)

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if handle_input(event):
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	if key != null and (focus is LineEdit or focus is TextEdit):
		return
	get_viewport().set_input_as_handled()
