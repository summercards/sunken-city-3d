@tool
extends VBoxContainer

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Session = preload("res://src/plant_authoring/session.gd")
const Store = preload("res://src/plant_authoring/store.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const Preview = preload("res://addons/plant_editor/preview.gd")
const PALETTE = preload("res://assets/textures/shared/sea_cabin_timber_8x8_512.png")
const MODULES = ["树形", "枝条", "叶片", "附生", "配色", "文件"]
const FIELD_LABELS = {
	"height": "主干高度", "trunk_radius": "主干半径", "trunk_curve": "主干弯曲", "crown_radius": "冠幅半径",
	"branch_start": "首分枝高度", "branch_count": "主枝数量", "branch_spread": "主枝伸展", "branch_rise": "主枝上扬",
	"branch_droop": "末端下垂", "subtwig_count": "每枝小枝数", "leaf_size": "叶片尺寸", "leaf_density": "叶片密度",
	"cluster_size": "叶簇大小", "cluster_jitter": "叶簇松散", "normal_blend": "球形法线", "color_variation": "颜色差异",
	"moss_amount": "苔藓覆盖", "vine_count": "藤蔓数量", "vine_length": "藤蔓长度", "grass_count": "草簇数量",
	"wind_strength": "本地风强度", "wind_speed": "本地风速度", "variation": "随机变化", "seed": "随机种子",
	"length_scale": "选枝长度", "radius_scale": "选枝粗度", "angle_offset": "选枝角度",
	"trunk_cell": "树干色格", "leaf_cell": "叶片色格", "moss_cell": "苔藓色格", "vine_cell": "藤蔓色格"
}

var session = Session.new()
var store = Store.new()
var preview: Control
var controls: Dictionary = {}
var buttons: Dictionary = {}
var input_recipe: Dictionary = {}
var last_export: Dictionary = {}
var selected_branch = ""
var export_root = Store.DEFAULT_ROOT
var toolbar: HBoxContainer
var module_bar: HBoxContainer
var parameter_scroll: ScrollContainer
var pages: Array[VBoxContainer] = []
var palette_buttons: Array[Button] = []
var palette_colors: Array[Color] = []
var status: LineEdit
var details = ""
var _timer: Timer
var _syncing = false
var _dragging = false
var _merge_drag = false
var _drag_key = ""
var _confirm: ConfirmationDialog
var _pending_action = Callable()
var _branch_picker: OptionButton
var _file_list: ItemList
var _file_rows: Array = []
var _path: LineEdit
var _color_target: OptionButton
var _info_dialog: AcceptDialog
var _info_text: TextEdit
var _module = 0
var _ready_done = false

func _ready() -> void:
	set_meta("cozy_skip", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(700, 420)
	add_theme_font_size_override("font_size", 16)
	var own_theme = Theme.new()
	own_theme.default_font_size = 16
	if Engine.is_editor_hint():
		own_theme.default_font = EditorInterface.get_editor_theme().default_font
	own_theme.set_color("font_color", "Label", Color("#e5f1df"))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#274333") if state in ["hover", "pressed"] else Color("#192e26")
		box.border_color = Color("#e4bf70") if state == "focus" else Color("#668c70")
		box.set_border_width_all(1)
		box.set_corner_radius_all(5)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		own_theme.set_stylebox(state, "Button", box)
	own_theme.set_color("font_color", "Button", Color("#e5f1df"))
	own_theme.set_color("font_hover_color", "Button", Color("#fff0bc"))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#14261f")
	own_theme.set_stylebox("panel", "PanelContainer", bg)
	theme = own_theme
	add_theme_constant_override("separation", 5)
	input_recipe = session.snapshot()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.16
	_timer.timeout.connect(flush_pending)
	add_child(_timer)
	_build_toolbar()
	_build_modules()
	var content = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	add_child(content)
	parameter_scroll = ScrollContainer.new()
	parameter_scroll.custom_minimum_size.x = 300
	parameter_scroll.size_flags_horizontal = Control.SIZE_FILL
	parameter_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parameter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(parameter_scroll)
	var panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	parameter_scroll.add_child(panel)
	for title in MODULES:
		var page = VBoxContainer.new()
		page.add_theme_constant_override("separation", 7)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(page)
		pages.append(page)
		var heading = Label.new()
		heading.text = title
		heading.add_theme_font_size_override("font_size", 18)
		page.add_child(heading)
	_build_parameters()
	preview = Preview.new()
	content.add_child(preview)
	module_bar.reparent(preview)
	preview.move_child(module_bar, 0)
	preview.branch_selected.connect(select_branch)
	_build_status()
	_build_dialogs()
	_ready_done = true
	show_module(0)
	_accept_result(session.build(), true)
	_sync_controls()

func _button(parent: Node, key: String, text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_constant_override("outline_size", 0)
	button.pressed.connect(action)
	if parent is VBoxContainer:
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	buttons[key] = button
	return button

func _build_toolbar() -> void:
	toolbar = HBoxContainer.new()
	toolbar.name = "PlantToolbar"
	toolbar.add_theme_constant_override("separation", 3)
	add_child(toolbar)
	_button(toolbar, "new", "新建", request_new)
	for id in Recipe.SPECIES:
		_button(toolbar, id, str(Species.definitions()[id].name), request_species.bind(id))
	_button(toolbar, "random", "随机", reroll_seed)
	_button(toolbar, "save", "保存", save_recipe)
	_button(toolbar, "open", "打开", show_module.bind(5))
	_button(toolbar, "undo", "撤销", undo)
	_button(toolbar, "redo", "重做", redo)
	_button(toolbar, "info", "信息", show_info)

func _build_modules() -> void:
	module_bar = HBoxContainer.new()
	module_bar.name = "PlantModules"
	module_bar.add_theme_constant_override("separation", 4)
	add_child(module_bar)
	for index in MODULES.size():
		var button = _button(module_bar, "module_%d" % index, MODULES[index], show_module.bind(index))
		button.toggle_mode = true

func _sliders(parent: VBoxContainer, keys: Array) -> void:
	for key in keys:
		_slider(parent, str(key))

func _slider(parent: VBoxContainer, key: String, branch: bool = false) -> void:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	parent.add_child(row)
	var title = HBoxContainer.new()
	row.add_child(title)
	var label = Label.new()
	label.text = FIELD_LABELS.get(key, key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(label)
	var value = Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.add_child(value)
	var slider = HSlider.new()
	slider.name = key
	var limits: Array = Recipe.RANGES[key]
	slider.min_value = float(limits[0])
	slider.max_value = 999999.0 if key == "seed" else float(limits[1])
	slider.step = float(limits[2])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 22
	slider.tooltip_text = "范围 %s … %s；拖动实时预览，整次拖动可一次撤销" % [str(slider.min_value), str(slider.max_value)]
	row.add_child(slider)
	var range_text = Label.new()
	range_text.text = "%s … %s" % [str(slider.min_value), str(slider.max_value)]
	range_text.modulate = Color("a8bcb5")
	row.add_child(range_text)
	var control_key = "branch_" + key if branch else key
	controls[control_key] = slider
	controls[control_key + "_value"] = value
	slider.value_changed.connect(_slider_changed.bind(key, branch))
	slider.drag_started.connect(_begin_drag.bind(control_key))
	slider.drag_ended.connect(_end_drag)

func _toggle(parent: VBoxContainer, key: String, text: String, branch: bool = false) -> void:
	var check = CheckBox.new()
	check.text = text
	parent.add_child(check)
	controls["branch_" + key if branch else key] = check
	check.toggled.connect(_toggle_changed.bind(key, branch))

func _build_parameters() -> void:
	_sliders(pages[0], ["height", "trunk_radius", "trunk_curve", "crown_radius", "branch_start", "seed"])
	_button(pages[0], "reroll", "重抽种子 0 … 999999", reroll_seed)
	_toggle(pages[0], "random_enabled", "启用确定性随机")
	_sliders(pages[0], ["variation"])
	_toggle(pages[0], "trunk_visible", "显示树干与枝条")
	_sliders(pages[1], ["branch_count", "subtwig_count", "branch_spread", "branch_rise", "branch_droop"])
	_branch_picker = OptionButton.new()
	_branch_picker.fit_to_longest_item = false
	_branch_picker.item_selected.connect(_pick_branch_index)
	pages[1].add_child(_branch_picker)
	_button(pages[1], "focus_branch", "聚焦选枝", focus_selected_branch)
	_toggle(pages[1], "enabled", "启用选枝（叶片跟随）", true)
	for key in ["length_scale", "radius_scale", "angle_offset"]:
		_slider(pages[1], key, true)
	_toggle(pages[2], "leaves_visible", "显示叶片")
	_sliders(pages[2], ["leaf_size", "leaf_density", "cluster_size", "cluster_jitter", "normal_blend", "color_variation", "wind_strength", "wind_speed"])
	_toggle(pages[3], "moss_enabled", "树皮苔藓")
	_sliders(pages[3], ["moss_amount"])
	_toggle(pages[3], "vine_enabled", "附生藤蔓")
	_sliders(pages[3], ["vine_count", "vine_length"])
	_toggle(pages[3], "grass_enabled", "树下草簇")
	_sliders(pages[3], ["grass_count"])
	var grass = OptionButton.new()
	for id in Recipe.GRASS_ASSETS:
		grass.add_item(id)
	grass.item_selected.connect(func(index: int): _field("grass_asset", Recipe.GRASS_ASSETS[index]))
	pages[3].add_child(grass)
	controls.grass_asset = grass
	_build_palette()
	_build_files()

func _build_palette() -> void:
	var mode = OptionButton.new()
	mode.add_item("自动：同色族变化")
	mode.add_item("手动：精确色格")
	mode.item_selected.connect(func(index: int): _field("color_mode", "auto" if index == 0 else "manual"))
	pages[4].add_child(mode)
	controls.color_mode = mode
	_color_target = OptionButton.new()
	for title in ["目标：树干", "目标：叶片", "目标：苔藓", "目标：藤蔓"]:
		_color_target.add_item(title)
	_color_target.item_selected.connect(func(_index: int): _refresh_palette_selection())
	pages[4].add_child(_color_target)
	var grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	pages[4].add_child(grid)
	var image = PALETTE.get_image()
	if image.is_compressed():
		image.decompress()
	for index in 64:
		var color = image.get_pixel((index % 8) * 64 + 32, int(index / 8) * 64 + 32)
		palette_colors.append(color)
		var swatch = Button.new()
		swatch.custom_minimum_size = Vector2(29, 29)
		swatch.toggle_mode = true
		swatch.tooltip_text = "色格 %d · #%s" % [index, color.to_html(false)]
		for state in ["normal", "hover", "pressed", "focus"]:
			var style = StyleBoxFlat.new()
			style.bg_color = color
			style.set_border_width_all(3 if state == "pressed" else 1)
			style.border_color = Color("ffffff") if state in ["pressed", "focus"] else color.lightened(0.2)
			swatch.add_theme_stylebox_override(state, style)
		swatch.pressed.connect(choose_color.bind(index))
		grid.add_child(swatch)
		palette_buttons.append(swatch)
	_sliders(pages[4], ["trunk_cell", "leaf_cell", "moss_cell", "vine_cell"])

func _build_files() -> void:
	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "另存名称（留空使用物种名）"
	name_edit.max_length = 80
	name_edit.text_changed.connect(func(value: String): _field("name", value))
	pages[5].add_child(name_edit)
	controls.name = name_edit
	var root = OptionButton.new()
	root.add_item("候选 · outputs/plant_editor")
	root.add_item("候选 · scenes/workshop_plants（不自动接入）")
	root.fit_to_longest_item = false
	root.item_selected.connect(func(index: int): export_root = Store.DEFAULT_ROOT if index == 0 else "res://scenes/workshop_plants")
	pages[5].add_child(root)
	_button(pages[5], "save_as", "保存新 revision（不覆盖旧版）", save_recipe)
	_path = LineEdit.new()
	_path.placeholder_text = "plant.recipe.json 的 res:// 路径"
	_path.tooltip_text = "只通过 Store 的受限路径校验，不打开编辑场景"
	pages[5].add_child(_path)
	_button(pages[5], "open_path", "打开路径中的配方", func(): request_open(_path.text))
	_button(pages[5], "refresh", "刷新配方列表", refresh_files)
	_file_list = ItemList.new()
	_file_list.custom_minimum_size.y = 180
	_file_list.item_activated.connect(_open_list_item)
	_file_list.item_selected.connect(func(index: int): _path.text = str(_file_rows[index].recipe_path))
	pages[5].add_child(_file_list)
	_button(pages[5], "open_selected", "打开选中配方", func(): request_open(_path.text))

func _build_status() -> void:
	var row = HBoxContainer.new()
	add_child(row)
	status = LineEdit.new()
	status.editable = false
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.custom_minimum_size.x = 0
	status.add_theme_color_override("font_uneditable_color", Color("#f3de9b"))
	var status_box := StyleBoxFlat.new()
	status_box.bg_color = Color("#203b2c")
	status_box.border_color = Color("#d7bb69")
	status_box.set_border_width_all(2)
	status.add_theme_stylebox_override("read_only", status_box)
	row.add_child(status)
	_button(row, "details", "复制详情", copy_details)

func _build_dialogs() -> void:
	_confirm = ConfirmationDialog.new()
	_confirm.title = "当前树木有未保存修改"
	_confirm.dialog_text = "此操作会替换当前文档，包括未通过校验的输入。是否放弃修改并继续？"
	_confirm.ok_button_text = "放弃并继续"
	_confirm.cancel_button_text = "保留当前树木"
	_confirm.confirmed.connect(func():
		var action = _pending_action
		_pending_action = Callable()
		if action.is_valid(): action.call())
	_confirm.canceled.connect(func(): _pending_action = Callable())
	add_child(_confirm)
	_info_dialog = AcceptDialog.new()
	_info_dialog.title = "树木工坊 · 物种与状态详情"
	_info_dialog.min_size = Vector2i(600, 360)
	_info_text = TextEdit.new()
	_info_text.editable = false
	_info_text.custom_minimum_size = Vector2(580, 310)
	_info_dialog.add_child(_info_text)
	add_child(_info_dialog)

func show_module(index: int) -> void:
	_module = clampi(index, 0, MODULES.size() - 1)
	for i in pages.size():
		pages[i].visible = i == _module
		buttons["module_%d" % i].set_pressed_no_signal(i == _module)
	parameter_scroll.scroll_vertical = 0
	if _module == 5:
		refresh_files()

func _slider_changed(value: float, key: String, branch: bool) -> void:
	if _syncing:
		return
	var control_key = "branch_" + key if branch else key
	controls[control_key + "_value"].text = str(int(value)) if Recipe.INTEGER_KEYS.has(key) else "%.2f" % value
	var number: Variant = int(value) if Recipe.INTEGER_KEYS.has(key) else value
	if branch:
		_branch_field(key, number)
	else:
		if key.ends_with("_cell"):
			input_recipe.color_mode = "manual"
		_field(key, number)

func _toggle_changed(value: bool, key: String, branch: bool) -> void:
	if _syncing:
		return
	if branch:
		_branch_field(key, value)
	else:
		_field(key, value)

func _field(key: String, value: Variant) -> void:
	if _syncing:
		return
	input_recipe[key] = value
	if key == "branch_count":
		var overrides: Dictionary = input_recipe.branch_overrides.duplicate(true)
		for id in overrides.keys():
			if int(str(id).trim_prefix("branch_")) >= int(value):
				overrides.erase(id)
		input_recipe.branch_overrides = overrides
	_timer.start()
	buttons.undo.disabled = false
	_set_status("等待预览 · 输入已保留", false)

func _branch_field(key: String, value: Variant) -> void:
	if selected_branch.is_empty():
		return
	var overrides: Dictionary = input_recipe.branch_overrides.duplicate(true)
	var branch: Dictionary = overrides.get(selected_branch, {}).duplicate(true)
	branch[key] = value
	overrides[selected_branch] = branch
	_field("branch_overrides", overrides)

func _begin_drag(key: String) -> void:
	flush_pending()
	_dragging = true
	_merge_drag = false
	_drag_key = key

func _end_drag(_changed: bool) -> void:
	flush_pending()
	_dragging = false
	_merge_drag = false
	_drag_key = ""

func flush_pending() -> Dictionary:
	_timer.stop()
	if not has_pending_fields():
		return {"ok": true, "root": preview.model}
	var before = session.fingerprint()
	var result: Dictionary = session.preview_candidate(input_recipe, _dragging and _merge_drag, before)
	if bool(result.get("ok", false)):
		if _dragging and session.fingerprint() != before:
			_merge_drag = true
		input_recipe = session.snapshot()
		_accept_result(result)
		_sync_controls()
	else:
		_set_status("未应用：" + str(result.get("reason", "生成失败")), true)
	return result

func has_pending_fields() -> bool:
	return JSON.stringify(input_recipe, "", true, true) != JSON.stringify(session.snapshot(), "", true, true)

func snapshot() -> Dictionary:
	return session.snapshot()

func _accept_result(result: Dictionary, fit: bool = false) -> bool:
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("reason", "生成失败")), true)
		return false
	preview.set_build(result)
	if fit:
		preview.fit_model()
	var stats: Dictionary = result.get("stats", {})
	_set_status("%s · %d 枝 · %d 叶 · %d 三角面%s" % [Species.definitions()[session.snapshot().species].name, int(stats.get("branch_count", 0)), int(stats.get("leaf_count", 0)), int(stats.get("triangles", 0)), " · 未保存" if session.is_dirty() else " · 已保存"], false)
	_update_branch_picker()
	buttons.undo.disabled = not session.can_undo()
	buttons.redo.disabled = not session.can_redo()
	return true

func _sync_controls() -> void:
	_syncing = true
	for key in input_recipe:
		if not controls.has(key):
			continue
		var control: Control = controls[key]
		if control is HSlider:
			control.set_value_no_signal(float(input_recipe[key]))
			controls[key + "_value"].text = str(input_recipe[key]) if Recipe.INTEGER_KEYS.has(key) else "%.2f" % float(input_recipe[key])
		elif control is CheckBox:
			control.set_pressed_no_signal(bool(input_recipe[key]))
		elif control is LineEdit:
			control.text = str(input_recipe[key])
	controls.color_mode.select(0 if input_recipe.color_mode == "auto" else 1)
	controls.grass_asset.select(Recipe.GRASS_ASSETS.find(input_recipe.grass_asset))
	_sync_branch_controls()
	_refresh_palette_selection()
	_syncing = false

func _update_branch_picker() -> void:
	_branch_picker.clear()
	for branch: Dictionary in preview.branches:
		_branch_picker.add_item("%s%s" % [str(branch.id), " · 隐藏" if not branch.enabled else ""])
		_branch_picker.set_item_metadata(_branch_picker.item_count - 1, str(branch.id))
	if selected_branch.is_empty() and not preview.branches.is_empty():
		selected_branch = str(preview.branches[0].id)
	var found = false
	for index in _branch_picker.item_count:
		if _branch_picker.get_item_metadata(index) == selected_branch:
			_branch_picker.select(index)
			found = true
	if not found:
		selected_branch = ""
	preview.select_branch(selected_branch)
	_sync_branch_controls()

func _pick_branch_index(index: int) -> void:
	select_branch(str(_branch_picker.get_item_metadata(index)))

func select_branch(id: String) -> void:
	selected_branch = id
	preview.select_branch(id)
	for index in _branch_picker.item_count:
		if _branch_picker.get_item_metadata(index) == id:
			_branch_picker.select(index)
	_sync_branch_controls()

func _sync_branch_controls() -> void:
	var was_syncing = _syncing
	_syncing = true
	var override: Dictionary = input_recipe.get("branch_overrides", {}).get(selected_branch, {})
	for key in ["length_scale", "radius_scale", "angle_offset"]:
		var slider: HSlider = controls["branch_" + key]
		slider.editable = not selected_branch.is_empty()
		var value = float(override.get(key, 0.0 if key == "angle_offset" else 1.0))
		slider.set_value_no_signal(value)
		controls["branch_" + key + "_value"].text = "%.2f" % value
	controls.branch_enabled.disabled = selected_branch.is_empty()
	controls.branch_enabled.set_pressed_no_signal(bool(override.get("enabled", true)))
	_syncing = was_syncing

func focus_selected_branch() -> void:
	for branch: Dictionary in preview.branches:
		if branch.id == selected_branch:
			preview.focus_bounds(branch.bounds)
			return

func choose_color(index: int) -> void:
	var key: String = ["trunk_cell", "leaf_cell", "moss_cell", "vine_cell"][_color_target.selected]
	input_recipe.color_mode = "manual"
	_field(key, index)
	_sync_controls()

func _refresh_palette_selection() -> void:
	var key: String = ["trunk_cell", "leaf_cell", "moss_cell", "vine_cell"][_color_target.selected]
	for index in palette_buttons.size():
		palette_buttons[index].set_pressed_no_signal(index == int(input_recipe[key]))

func reroll_seed() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var previous = int(input_recipe.seed)
	var next = rng.randi_range(0, 999998)
	if next >= previous:
		next += 1
	_field("seed", next)
	_sync_controls()
	flush_pending()

func undo() -> void:
	_timer.stop()
	_dragging = false
	_merge_drag = false
	if has_pending_fields():
		input_recipe = session.snapshot()
		_sync_controls()
		_set_status("已撤回未通过的输入；模型未变", false)
		return
	if session.undo():
		input_recipe = session.snapshot()
		_accept_result(session.build())
		_sync_controls()

func redo() -> void:
	_timer.stop()
	_dragging = false
	_merge_drag = false
	if has_pending_fields():
		_set_status("请先纠正或撤回当前未应用输入", true)
		return
	if session.redo():
		input_recipe = session.snapshot()
		_accept_result(session.build())
		_sync_controls()

func _request(action: Callable) -> void:
	if session.is_dirty() or has_pending_fields():
		_pending_action = action
		_confirm.popup_centered()
	else:
		action.call()

func request_new() -> void:
	_request(new_document.bind(str(input_recipe.species)))

func request_species(id: String) -> void:
	if id != str(input_recipe.species):
		_request(new_document.bind(id))

func new_document(id: String) -> Dictionary:
	_timer.stop()
	var result: Dictionary = session.new_document(id)
	if bool(result.get("ok", false)):
		input_recipe = session.snapshot()
		selected_branch = ""
		last_export = {}
		_dragging = false
		_merge_drag = false
		_accept_result(result, true)
		_sync_controls()
	else:
		_set_status(str(result.get("reason", "新建失败")), true)
	return result

func request_open(path: String) -> void:
	_request(open_recipe.bind(path))

func open_recipe(path: String) -> Dictionary:
	var loaded: Dictionary = store.load_recipe(path)
	if not bool(loaded.get("ok", false)):
		_set_status(str(loaded.get("reason", "载入失败")), true)
		return loaded
	var result: Dictionary = session.load_recipe(loaded.recipe)
	if bool(result.get("ok", false)):
		_timer.stop()
		input_recipe = session.snapshot()
		selected_branch = ""
		_dragging = false
		_merge_drag = false
		_accept_result(result, true)
		_sync_controls()
	else:
		_set_status(str(result.get("reason", "载入失败")), true)
	return result

func save_recipe() -> Dictionary:
	var applied = flush_pending()
	if not bool(applied.get("ok", false)):
		return applied
	var fp = session.fingerprint()
	var result: Dictionary = store.save(session.snapshot(), export_root)
	if bool(result.get("ok", false)):
		session.mark_saved(fp)
		_merge_drag = false
		last_export = result.duplicate(true)
		_path.text = str(result.recipe_path)
		_set_status("已保存新版本：" + str(result.recipe_path), false)
		refresh_files()
	else:
		_set_status("保存失败：" + str(result.get("reason", "")), true)
	return result

func refresh_files() -> void:
	_file_rows = store.list_recipes(export_root)
	_file_list.clear()
	for row: Dictionary in _file_rows:
		_file_list.add_item("%s / %s" % [str(row.recipe.get("name", row.recipe.species)), str(row.directory).get_file()])
		_file_list.set_item_tooltip(_file_list.item_count - 1, str(row.recipe_path))

func _open_list_item(index: int) -> void:
	request_open(str(_file_rows[index].recipe_path))

func _set_status(message: String, error: bool) -> void:
	status.text = message.replace("\n", " ")
	status.tooltip_text = message
	status.add_theme_color_override("font_uneditable_color", Color("ffb7a5") if error else Color("c0ead0"))
	var style = StyleBoxFlat.new()
	style.bg_color = Color("532b30") if error else Color("213c35")
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.border_color = Color("#ec9a78") if error else Color("#d7bb69")
	style.set_border_width_all(2)
	status.add_theme_stylebox_override("read_only", style)
	var definition: Dictionary = Species.definitions().get(str(input_recipe.get("species", "camphor")), {})
	details = message + "\n" + str(definition.get("latin", "")) + "\n" + str(definition.get("description", ""))
	details += "\n输入配方：\n" + JSON.stringify(input_recipe, "\t")
	details += "\n上次成功配方：\n" + JSON.stringify(session.snapshot(), "\t")
	details += "\n保存结果：\n" + JSON.stringify(last_export, "\t")

func copy_details() -> void:
	DisplayServer.clipboard_set(details)

func show_info() -> void:
	_info_text.text = details
	_info_dialog.popup_centered()

func set_screen_visible(value: bool) -> void:
	visible = value
	if _ready_done:
		if not value:
			_timer.stop()
		preview.set_active(value)
		if value and has_pending_fields():
			_timer.start()

func get_recovery() -> Dictionary:
	return {"version": 1, "session": session.export_draft(), "input": input_recipe.duplicate(true), "selected_branch": selected_branch, "last_export": last_export.duplicate(true)}

func restore_recovery(data: Dictionary) -> Dictionary:
	if data.get("version") != 1 or not (data.get("session") is Dictionary):
		return {"ok": false, "reason": "树木草稿格式不匹配"}
	var result: Dictionary = session.restore_draft(data.session)
	if bool(result.get("ok", false)):
		input_recipe = session.snapshot()
		var pending: Variant = data.get("input", {})
		if pending is Dictionary and pending.keys().size() == input_recipe.keys().size():
			var numeric_safe = true
			for key in input_recipe:
				if not pending.has(key) or typeof(pending[key]) != typeof(input_recipe[key]):
					if not (pending.get(key) is float or pending.get(key) is int) or not (input_recipe[key] is float or input_recipe[key] is int):
						numeric_safe = false
			if numeric_safe:
				input_recipe = pending.duplicate(true)
		selected_branch = str(data.get("selected_branch", ""))
		last_export = data.get("last_export", {}).duplicate(true)
		_accept_result(result)
		_sync_controls()
		if has_pending_fields():
			_set_status("已恢复草稿输入；" + Recipe.validate(input_recipe), not Recipe.validate(input_recipe).is_empty())
	return result
