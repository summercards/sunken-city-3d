@tool
extends VBoxContainer

signal document_opened(path: String, token: int)
signal document_request_finished(token: int, result: Dictionary)
signal revision_saved(token: int, result: Dictionary)

var _document_token: int = 0
var _request_token: int = 0

func request_document(path: String, token: int) -> void:
	if _confirm.visible:
		document_request_finished.emit(token, {"ok": false, "reason": "请先处理当前确认窗口"})
		return
	_request_token = token
	_request(_open_bound_document.bind(path, token))

func _open_bound_document(path: String, token: int) -> void:
	_request_token = 0
	var result: Dictionary = open_recipe(path)
	if result.get("ok", false):
		_document_token = token
		document_opened.emit(path, token)
	document_request_finished.emit(token, result)

func _cancel_document_request() -> void:
	_pending_action = Callable()
	if _request_token != 0:
		document_request_finished.emit(_request_token, {"ok": false, "reason": "已取消"})
		_request_token = 0

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Session = preload("res://src/plant_authoring/session.gd")
const Store = preload("res://src/plant_authoring/store.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const Preview = preload("res://addons/plant_editor/preview.gd")
const HostAttachment = preload("res://src/plant_authoring/host_attachment.gd")
const HostSceneGuard = preload("res://src/plant_authoring/host_scene_guard.gd")
const TrunkPath = preload("res://src/plant_authoring/trunk_path.gd")
const PALETTE = preload("res://assets/textures/shared/sea_cabin_timber_8x8_512.png")
const MODULES = ["树形", "枝条", "叶片", "附生", "配色", "文件"]
const FOLIAGE_MODES = ["volumes", "cards", "geometry"]
const FOLIAGE_LABELS = {"volumes": "体块冠", "cards": "贴图单叶", "geometry": "实体叶"}
const FOLIAGE_NOTES = {
	"volumes": "相邻黄绿立体簇＋多方向叶簇贴图外壳。0=纯体块；叶簇卡影响面数/overdraw，图中多叶不等于独立几何叶。",
	"cards": "512×512 图集单叶卡片。保留单叶轮廓，以透明裁切代替实体厚度；细分档位不适用。",
	"geometry": "原实体叶对照，保留厚度与曲面。下方 balanced / high / reference 仅在此模式生效。"
}
const LEAF_GEOMETRY_MODES = ["balanced", "high", "reference"]
const FIELD_LABELS = {
	"height": "主干高度", "trunk_radius": "主干半径", "trunk_curve": "主干弯曲", "crown_radius": "冠幅半径",
	"branch_start": "首分枝高度", "branch_count": "主枝数量", "branch_spread": "主枝伸展", "branch_rise": "主枝上扬",
	"branch_droop": "末端下垂", "subtwig_count": "每枝小枝数", "leaf_size": "叶片尺寸", "leaf_density": "叶片密度",
	"volume_leaf_cards": "每簇外壳卡密度", "cluster_size": "叶簇大小", "cluster_jitter": "叶簇松散", "normal_blend": "球形法线", "color_variation": "颜色差异",
	"moss_amount": "苔藓覆盖", "vine_count": "藤蔓数量", "vine_length": "藤蔓长度", "grass_count": "草簇数量",
	"wind_strength": "本地风强度", "wind_speed": "本地风速度", "variation": "随机变化", "seed": "随机种子",
	"length_scale": "选枝长度", "radius_scale": "选枝粗度", "angle_offset": "选枝角度",
	"trunk_cell": "树干色格", "leaf_cell": "叶片色格", "moss_cell": "苔藓色格", "vine_cell": "藤蔓色格",
	"bark_detail": "树皮细节", "bark_cell": "树皮细节色格", "moss_scale": "苔藓斑块尺寸",
	"moss_bias": "苔藓朝向（弧度）", "moss_height": "苔藓高度比例", "moss_color_variation": "苔藓色差"
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
var host_attachment = HostAttachment.new()
# 仅为未应用输入；已应用绑定及历史始终由 Session 持有。
var host_binding: Dictionary = {}
var _preview_host_path = ""
var _point_picker: OptionButton
var _path_sliders: Dictionary = {}
var _point_index = 0
var _host_path: LineEdit
var _opening_picker: OptionButton
var _host_dialog: FileDialog
var _manifest_path: LineEdit
var _host_offsets: Dictionary = {}

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
	range_text.text = "%d … %d" % [int(slider.min_value), int(slider.max_value)] if Recipe.INTEGER_KEYS.has(key) else "%.2f … %.2f" % [slider.min_value, slider.max_value]
	range_text.clip_text = true
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
	_build_trunk_path()
	_build_host_panel()
	_sliders(pages[1], ["branch_count", "subtwig_count", "branch_spread", "branch_rise", "branch_droop"])
	_branch_picker = OptionButton.new()
	_branch_picker.fit_to_longest_item = false
	_branch_picker.item_selected.connect(_pick_branch_index)
	pages[1].add_child(_branch_picker)
	_button(pages[1], "focus_branch", "聚焦选枝", focus_selected_branch)
	_toggle(pages[1], "enabled", "启用选枝（叶片跟随）", true)
	for key in ["length_scale", "radius_scale", "angle_offset"]:
		_slider(pages[1], key, true)
	var foliage_mode = OptionButton.new()
	foliage_mode.name = "foliage_mode"
	foliage_mode.fit_to_longest_item = false
	foliage_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for title in ["体块冠 · volumes（新树默认）", "贴图单叶 · cards（512图集）", "实体叶 · geometry（原版）"]:
		foliage_mode.add_item(title)
	foliage_mode.tooltip_text = "切换后自动预览，可一次撤销。旧配方缺少模式时保留实体叶，不自动改变外观。"
	foliage_mode.item_selected.connect(func(index: int): _field("foliage_mode", FOLIAGE_MODES[index]))
	pages[2].add_child(foliage_mode)
	controls.foliage_mode = foliage_mode
	var mode_note = Label.new()
	mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_note.custom_minimum_size.x = 260
	pages[2].add_child(mode_note)
	controls.foliage_mode_note = mode_note
	var leaf_geometry_label = Label.new()
	leaf_geometry_label.text = "实体叶细分 · 仅 geometry"
	pages[2].add_child(leaf_geometry_label)
	var leaf_geometry = OptionButton.new()
	leaf_geometry.name = "leaf_geometry"
	leaf_geometry.fit_to_longest_item = false
	leaf_geometry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for title in ["balanced · 保真节省", "high · 原面数索引", "reference · 原版对照"]:
		leaf_geometry.add_item(title)
	leaf_geometry.tooltip_text = "仅改变叶片几何；不减少叶片密度、不改变随机种子。选择后自动预览，可一次撤销。"
	leaf_geometry.item_selected.connect(func(index: int):
		if str(input_recipe.get("foliage_mode", "geometry")) == "geometry":
			_field("leaf_geometry", LEAF_GEOMETRY_MODES[index]))
	pages[2].add_child(leaf_geometry)
	controls.leaf_geometry = leaf_geometry
	_slider(pages[2], "volume_leaf_cards")
	_toggle(pages[2], "leaves_visible", "显示叶片")
	_sliders(pages[2], ["leaf_size", "leaf_density", "cluster_size", "cluster_jitter", "normal_blend", "color_variation", "wind_strength", "wind_speed"])
	_toggle(pages[3], "moss_enabled", "树皮苔藓")
	_sliders(pages[3], ["bark_detail", "bark_cell", "moss_amount", "moss_scale", "moss_bias", "moss_height", "moss_color_variation"])
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
	for title in ["目标：树干", "目标：叶片", "目标：苔藓", "目标：藤蔓", "目标：树皮细节"]:
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
	_button(pages[5], "save_animated", "导出动态独立候选（不接入 Main）", save_animated)
	_manifest_path = LineEdit.new()
	_manifest_path.placeholder_text = "res://outputs/.../attachment.json（新文件）"
	pages[5].add_child(_manifest_path)
	_button(pages[5], "save_attachment", "导出结合描述 JSON（引用上次植物导出）", func(): save_attachment_manifest(_manifest_path.text))
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
	_confirm.canceled.connect(_cancel_document_request)
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
	if key == "volume_leaf_cards" and str(input_recipe.get("foliage_mode", "geometry")) != "volumes":
		controls.volume_leaf_cards.set_value_no_signal(float(input_recipe.get(key, 0)))
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
	if key == "height" and not input_recipe.get("trunk_path", []).is_empty():
		var path: Array = input_recipe.trunk_path.duplicate(true)
		var ratio = float(value) / float(input_recipe.height)
		for point in path:
			point.y = float(point.y) * ratio
		path[-1].y = float(value)
		input_recipe.trunk_path = path
	input_recipe[key] = value
	if key == "foliage_mode":
		_sync_foliage_controls()
	if key in ["height", "trunk_path"]:
		_sync_path_controls()
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
	var context = {"host_binding": host_binding.duplicate(true)}
	if input_recipe.get("species") != session.snapshot().species:
		context.host_binding = {}
	var prepared = _precheck_state(input_recipe, context)
	if not bool(prepared.ok):
		_set_status("未应用：" + str(prepared.reason), true)
		return prepared
	var before = session.state_fingerprint()
	var result: Dictionary = session.preview_candidate_with_context(input_recipe, context, _dragging and _merge_drag, before)
	if bool(result.get("ok", false)):
		if _dragging and session.state_fingerprint() != before:
			_merge_drag = true
		_install_host(prepared)
		input_recipe = session.snapshot()
		host_binding = session.host_binding()
		_accept_result(result)
		_sync_controls()
	else:
		_discard_host(prepared)
		_set_status("未应用：" + str(result.get("reason", "生成失败")), true)
	return result

func has_pending_fields() -> bool:
	var context := {"host_binding": host_binding}
	if not Recipe.validate(input_recipe).is_empty() or not Session.validate_context(context).is_empty():
		return true
	return Session.canonical_state_fingerprint(input_recipe, context) != session.state_fingerprint()

func snapshot() -> Dictionary:
	return session.snapshot()

func _accept_result(result: Dictionary, fit: bool = false) -> bool:
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("reason", "生成失败")), true)
		return false
	preview.set_build(result)
	_apply_host_transform()
	if fit:
		preview.fit_model()
	var stats: Dictionary = result.get("stats", {})
	var mode = str(session.snapshot().get("foliage_mode", "geometry"))
	var foliage_count = "%d 冠簇 · %d 叶簇卡" % [int(stats.get("cluster_count", 0)), int(stats.get("surface_card_count", 0))] if mode == "volumes" else "%d 叶" % int(stats.get("leaf_count", 0))
	_set_status("%s · %s · %d 枝 · %s · %d 顶点 · %d 三角面 · %d 网格 · %d surfaces%s" % [Species.definitions()[session.snapshot().species].name, FOLIAGE_LABELS.get(mode, mode), int(stats.get("branch_count", 0)), foliage_count, int(stats.get("vertices", 0)), int(stats.get("triangles", 0)), int(stats.get("mesh_nodes", 0)), int(stats.get("surfaces", 0)), " · 未保存" if session.is_dirty() else " · 已保存"], false)
	details += "\n生成器实际统计（surfaces 为网格表面数，非实测 draw calls；volumes 的 leaf_count 为预算叶位，surface_card_count 为实际外壳叶簇卡数；贴图每束9片源叶不乘9计作独立几何叶）：\n" + JSON.stringify(stats, "\t")
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
	_sync_foliage_controls()
	_sync_branch_controls()
	_refresh_palette_selection()
	_sync_path_controls()
	_sync_host_controls()
	_syncing = false

func _sync_foliage_controls() -> void:
	var mode = str(input_recipe.get("foliage_mode", "geometry"))
	controls.foliage_mode.select(FOLIAGE_MODES.find(mode))
	controls.foliage_mode_note.text = FOLIAGE_NOTES.get(mode, "未知模式；请纠正输入，成功预览保持不变。")
	controls.leaf_geometry.select(LEAF_GEOMETRY_MODES.find(input_recipe.get("leaf_geometry", "balanced")))
	controls.leaf_geometry.disabled = mode != "geometry"
	controls.volume_leaf_cards.editable = mode == "volumes"
	controls.volume_leaf_cards.tooltip_text = "仅 volumes 生效。0=纯体块；512叶簇贴图外壳受预算约束，增加面数与 overdraw。一张叶簇卡仍是一份卡片几何，不按图中9片源叶倍增计数。其它模式保留此值但不生效。"
	controls.leaf_geometry.tooltip_text = "仅实体叶 geometry 生效；当前档位保留，切回实体叶后恢复。" if mode != "geometry" else "不减少叶数、不改变种子；选择后自动预览，可一次撤销。"

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
	preview.focus_branch(selected_branch)

func choose_color(index: int) -> void:
	var key: String = ["trunk_cell", "leaf_cell", "moss_cell", "vine_cell", "bark_cell"][_color_target.selected]
	input_recipe.color_mode = "manual"
	_field(key, index)
	_sync_controls()

func _refresh_palette_selection() -> void:
	var key: String = ["trunk_cell", "leaf_cell", "moss_cell", "vine_cell", "bark_cell"][_color_target.selected]
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
	_drag_key = ""
	if has_pending_fields():
		input_recipe = session.snapshot()
		host_binding = session.host_binding()
		_sync_controls()
		buttons.undo.disabled = not session.can_undo()
		buttons.redo.disabled = not session.can_redo()
		_set_status("已撤回未通过的输入；模型与位置未变", false)
		return
	_step_history("undo")

func redo() -> void:
	_timer.stop()
	_dragging = false
	_merge_drag = false
	_drag_key = ""
	if has_pending_fields():
		_set_status("请先纠正或撤回当前未应用输入", true)
		return
	_step_history("redo")

func _step_history(direction: String) -> void:
	var transaction: Dictionary = session.peek_history(direction)
	if transaction.is_empty(): return
	var target: Dictionary = transaction.state
	var prepared = _precheck_state(target.recipe, target.authoring_context)
	if not bool(prepared.ok):
		_set_status("历史操作被目标宿主预检阻止：" + str(prepared.reason), true)
		return
	var result: Dictionary = session.commit_history(transaction)
	if not bool(result.ok):
		_discard_host(prepared)
		_set_status(str(result.reason), true)
		return
	_install_host(prepared)
	input_recipe = session.snapshot()
	host_binding = session.host_binding()
	_accept_result(result)
	_sync_controls()

func _request(action: Callable) -> void:
	if session.is_dirty() or has_pending_fields() or not host_binding.is_empty():
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
		_document_token = 0
		document_opened.emit("", 0)
		_install_host({"host_path": ""})
		host_binding = session.host_binding()
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
		_document_token = 0
		document_opened.emit("", 0)
		_install_host({"host_path": ""})
		host_binding = session.host_binding()
		last_export = {}
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
		revision_saved.emit(_document_token, result.duplicate(true))
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

func _fold(parent: VBoxContainer, key: String, title: String) -> VBoxContainer:
	var body = VBoxContainer.new()
	var toggle = _button(parent, key, title, func(): body.visible = not body.visible)
	toggle.toggle_mode = true
	body.visible = false
	parent.add_child(body)
	return body

func _note(parent: Node, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 260
	parent.add_child(label)

func _build_trunk_path() -> void:
	var body = _fold(pages[0], "path_panel", "主干路径 · 米制控制点")
	_note(body, "空路径为自动。手动 2–8 点，首点固定原点；末点 Y 随树高变化，改变树高会同比缩放全部 Y。失败输入保留，可撤销。")
	_point_picker = OptionButton.new()
	_point_picker.item_selected.connect(func(index: int):
		_point_index = index
		_sync_path_controls())
	body.add_child(_point_picker)
	for axis in ["x", "y", "z"]:
		var label = Label.new()
		label.clip_text = true
		body.add_child(label)
		var slider = HSlider.new()
		slider.min_value = -30.0
		slider.max_value = 30.0
		slider.step = 0.001
		body.add_child(slider)
		_path_sliders[axis] = slider
		_path_sliders[axis + "_label"] = label
		slider.value_changed.connect(_path_axis_changed.bind(axis))
		slider.drag_started.connect(_begin_drag.bind("path_" + axis))
		slider.drag_ended.connect(_end_drag)
	_button(body, "path_insert", "插入点 / 从自动建立手动路径", insert_path_point)
	_button(body, "path_delete", "删除选中内点", delete_path_point)
	_button(body, "path_auto", "恢复自动路径", func(): _field("trunk_path", []))

func _sync_path_controls() -> void:
	if _point_picker == null: return
	var path: Array = input_recipe.get("trunk_path", [])
	_point_picker.clear()
	if path.is_empty(): _point_picker.add_item("自动路径（插入开始手动编辑）")
	for index in path.size():
		_point_picker.add_item("点 %d%s" % [index, " · 根" if index == 0 else " · 冠顶" if index == path.size() - 1 else ""])
	_point_index = clampi(_point_index, 0, maxi(0, path.size() - 1))
	_point_picker.select(_point_index)
	for axis in ["x", "y", "z"]:
		var slider: HSlider = _path_sliders[axis]
		var minimum = -30.0
		var maximum = 30.0
		if axis == "y":
			minimum = float(path[_point_index - 1].y) + 0.01 if _point_index > 0 else 0.0
			maximum = float(path[_point_index + 1].y) - 0.01 if _point_index + 1 < path.size() else float(input_recipe.height)
		slider.set_block_signals(true)
		slider.min_value = minimum
		slider.max_value = maxf(minimum, maximum)
		var value = float(path[_point_index][axis]) if not path.is_empty() else 0.0
		slider.set_value_no_signal(value)
		slider.editable = not path.is_empty() and _point_index > 0 and not (axis == "y" and _point_index == path.size() - 1) and maximum > minimum
		slider.set_block_signals(false)
		_path_sliders[axis + "_label"].text = "%s  %.3fm  [%.3f … %.3f]%s" % [axis.to_upper(), value, minimum, maximum, " · 固定" if not slider.editable else ""]
	buttons.path_insert.disabled = path.size() >= 8
	buttons.path_delete.disabled = path.size() <= 2 or _point_index == 0 or _point_index == path.size() - 1

func _path_axis_changed(value: float, axis: String) -> void:
	if _syncing: return
	var path: Array = input_recipe.trunk_path.duplicate(true)
	if path.is_empty(): return
	path[_point_index][axis] = value
	_field("trunk_path", path)

func insert_path_point() -> void:
	var path: Array = input_recipe.get("trunk_path", []).duplicate(true)
	if path.is_empty():
		for t in [0.0, 0.5, 1.0]:
			var point = TrunkPath.sample(input_recipe, t)
			path.append({"x": point.x, "y": point.y, "z": point.z})
		path[0] = {"x": 0.0, "y": 0.0, "z": 0.0}
		path[-1].y = float(input_recipe.height)
		_point_index = 1
	elif path.size() < 8:
		var index = mini(_point_index, path.size() - 2)
		if float(path[index + 1].y) - float(path[index].y) < 0.02:
			_set_status("相邻点高度不足 0.02m，不能再插入", true)
			return
		var a = TrunkPath._point(path[index])
		var b = TrunkPath._point(path[index + 1])
		var point = a.lerp(b, 0.5)
		path.insert(index + 1, {"x": point.x, "y": point.y, "z": point.z})
		_point_index = index + 1
	_field("trunk_path", path)

func delete_path_point() -> void:
	var path: Array = input_recipe.get("trunk_path", []).duplicate(true)
	if path.size() <= 2 or _point_index <= 0 or _point_index >= path.size() - 1: return
	path.remove_at(_point_index)
	_point_index -= 1
	_field("trunk_path", path)

func _build_host_panel() -> void:
	var body = _fold(pages[0], "host_panel", "宿主结合 · 房屋 / 窗 / 破墙")
	_note(body, "只读加载已保存 building.tscn。窗玻璃、门扇及楼板会阻挡粗干；不修改房屋、不削树、不自动接入 Main。检测只覆盖主干，枝叶外观须另行验收。")
	_host_path = LineEdit.new()
	_host_path.placeholder_text = "res://…/building.tscn"
	body.add_child(_host_path)
	_button(body, "host_browse", "选择已保存房屋…", func(): _host_dialog.popup_centered_ratio(0.65))
	_button(body, "host_load", "只读载入宿主", func(): load_host(_host_path.text))
	_opening_picker = OptionButton.new()
	_opening_picker.fit_to_longest_item = false
	body.add_child(_opening_picker)
	_button(body, "host_route", "生成根→内侧→洞心→外侧→冠顶", func(): propose_host_path(_opening_picker.selected))
	for axis in ["x", "y", "z"]:
		var label = Label.new()
		label.clip_text = true
		body.add_child(label)
		var slider = HSlider.new()
		slider.min_value = -100.0
		slider.max_value = 100.0
		slider.step = 0.01
		body.add_child(slider)
		_host_offsets[axis] = slider
		_host_offsets[axis + "_label"] = label
		slider.value_changed.connect(_host_offset_changed.bind(axis))
		slider.drag_started.connect(_begin_drag.bind("host_" + axis))
		slider.drag_ended.connect(_end_drag)
	_button(body, "host_check", "校验并应用结合（粗干三角形检测）", func():
		if host_binding.is_empty():
			_host_failure("请先载入宿主")
			return
		host_binding.enabled = true
		var result = flush_pending()
		if bool(result.ok):
			preview.fit_model()
			_set_status(str(check_host_clearance(input_recipe).reason), false))
	_button(body, "host_clear", "移除参考宿主（保留树路径）", clear_host)
	_host_dialog = FileDialog.new()
	_host_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_host_dialog.access = FileDialog.ACCESS_RESOURCES
	_host_dialog.filters = PackedStringArray(["building.tscn ; 已保存房屋"])
	_host_dialog.file_selected.connect(load_host)
	add_child(_host_dialog)

func load_host(path: String) -> Dictionary:
	var binding = {"host_path": path, "matrix": HostAttachment.encode_transform(Transform3D.IDENTITY), "opening_id": "", "enabled": false}
	return _commit_host_reference(binding)

func clear_host() -> void:
	_commit_host_reference({})

func _commit_host_reference(binding: Dictionary) -> Dictionary:
	var context = {"host_binding": binding}
	var prepared = _precheck_state(session.snapshot(), context)
	if not bool(prepared.ok): return _host_failure(str(prepared.reason))
	var result: Dictionary = session.preview_candidate_with_context(session.snapshot(), context, false, session.state_fingerprint())
	if not bool(result.ok):
		_discard_host(prepared)
		return _host_failure(str(result.reason))
	_timer.stop()
	_dragging = false
	_merge_drag = false
	_drag_key = ""
	host_binding = session.host_binding()
	_install_host(prepared)
	_accept_result(result)
	_sync_controls()
	buttons.undo.disabled = not session.can_undo() and not has_pending_fields()
	preview.fit_model()
	result.reason = str(prepared.get("reason", "参考宿主已更新；未修改宿主场景"))
	if prepared.has("adapter"):
		result.openings = prepared.adapter.openings.duplicate(true)
		result.surface_count = prepared.adapter.surfaces.size()
	_set_status(result.reason, false)
	return result

func _read_host(path: String) -> Dictionary:
	var path_reason := HostSceneGuard.audit_path(path)
	if not path_reason.is_empty(): return {"ok": false, "reason": path_reason}
	var packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var reason = HostAttachment.audit_scene(packed)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	return {"ok": true, "packed": packed}

# 暂存的新宿主只供预检；失败时释放，成功提交 Session 后才切换画面。
func _prepare_host(path: String) -> Dictionary:
	if path.is_empty(): return {"ok": true, "host_path": ""}
	if path == _preview_host_path and is_instance_valid(preview.host_reference):
		var path_reason := HostSceneGuard.audit_path(path)
		if not path_reason.is_empty(): return {"ok": false, "reason": path_reason}
		return {"ok": true, "host_path": path, "adapter": host_attachment}
	if not path.begins_with("res://") or path.contains("..") or path.get_file() != "building.tscn":
		return {"ok": false, "reason": "请选择项目内已保存的 building.tscn"}
	var loaded := _read_host(path)
	if not bool(loaded.ok): return loaded
	var packed: PackedScene = loaded.packed
	# 文本闭包审查通过后才允许 instantiate；不得事后剥离脚本。
	var node = packed.instantiate()
	if not node is Node3D:
		node.free()
		return {"ok": false, "reason": "宿主根必须为 Node3D"}
	var adapter = HostAttachment.new()
	var result: Dictionary = adapter.bind_host(node)
	if not bool(result.ok):
		node.free()
		return result
	return {"ok": true, "host_path": path, "adapter": adapter, "host_node": node, "reason": result.reason}

func _precheck_state(recipe: Dictionary, context: Dictionary) -> Dictionary:
	var reason = Recipe.validate(recipe)
	if reason.is_empty(): reason = Session.validate_context(context)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	var binding: Dictionary = context.get("host_binding", {})
	var prepared = _prepare_host(str(binding.get("host_path", "")))
	if not bool(prepared.ok): return prepared
	if not binding.is_empty() and bool(binding.get("enabled", false)):
		var decoded = HostAttachment.decode_transform(binding.get("matrix"))
		var clearance: Dictionary = prepared.adapter.check_clearance(recipe, decoded.transform)
		if not bool(clearance.ok):
			_discard_host(prepared)
			return clearance
		prepared.merge(clearance, true)
	else:
		prepared.reason = "宿主仅参考，尚未绑定路径"
	return prepared

func _discard_host(prepared: Dictionary) -> void:
	var node: Variant = prepared.get("host_node")
	if is_instance_valid(node): node.free()

func _install_host(prepared: Dictionary) -> void:
	var path = str(prepared.get("host_path", ""))
	if path.is_empty():
		host_attachment = HostAttachment.new()
		preview.clear_host_reference()
	elif prepared.has("host_node"):
		host_attachment = prepared.adapter
		preview.set_host_reference(prepared.host_node)
	_preview_host_path = path
	_host_path.text = path
	_opening_picker.clear()
	for hole in host_attachment.openings:
		_opening_picker.add_item(str(hole.label))

func propose_host_path(opening_index: int) -> Dictionary:
	var source = host_attachment.propose_path(input_recipe, opening_index)
	if not bool(source.ok): return _host_failure(str(source.reason))
	var candidate = input_recipe.duplicate(true)
	candidate.trunk_path = source.trunk_path
	var binding = host_binding.duplicate(true)
	binding.matrix = HostAttachment.encode_transform(source.plant_to_host)
	binding.opening_id = source.opening_id
	binding.enabled = true
	var result = _apply_candidate(candidate, binding)
	if bool(result.ok): preview.fit_model()
	return result

func set_host_transform(value: Transform3D) -> Dictionary:
	if host_binding.is_empty(): return _host_failure("请先载入宿主")
	var binding = host_binding.duplicate(true)
	binding.matrix = HostAttachment.encode_transform(value)
	binding.enabled = true
	return _apply_candidate(input_recipe, binding)

func _apply_candidate(candidate: Dictionary, binding: Dictionary) -> Dictionary:
	input_recipe = candidate.duplicate(true)
	host_binding = binding.duplicate(true)
	buttons.undo.disabled = false
	_sync_controls()
	var prepared = _precheck_state(candidate, {"host_binding": binding})
	if not bool(prepared.ok):
		_discard_host(prepared)
		_set_status("未应用：" + str(prepared.reason), true)
		return prepared
	var before = session.state_fingerprint()
	var result = session.preview_candidate_with_context(candidate, {"host_binding": binding}, _dragging and _merge_drag, before)
	if not bool(result.ok):
		_discard_host(prepared)
		_set_status("未应用：" + str(result.reason), true)
		return result
	if _dragging and session.state_fingerprint() != before:
		_merge_drag = true
	_install_host(prepared)
	input_recipe = session.snapshot()
	host_binding = session.host_binding()
	_accept_result(result)
	_sync_controls()
	return result

func _host_offset_changed(value: float, axis: String) -> void:
	if _syncing or host_binding.is_empty(): return
	var decoded = HostAttachment.decode_transform(host_binding.get("matrix"))
	if not bool(decoded.ok): return
	var transform: Transform3D = decoded.transform
	transform.origin[{"x": 0, "y": 1, "z": 2}[axis]] = value
	var binding = host_binding.duplicate(true)
	binding.matrix = HostAttachment.encode_transform(transform)
	binding.enabled = true
	_apply_candidate(input_recipe, binding)

func _sync_host_controls() -> void:
	var transform = Transform3D.IDENTITY
	if not host_binding.is_empty():
		var decoded = HostAttachment.decode_transform(host_binding.get("matrix"))
		if bool(decoded.ok): transform = decoded.transform
	for axis in ["x", "y", "z"]:
		if not _host_offsets.has(axis): continue
		var value = transform.origin[{"x": 0, "y": 1, "z": 2}[axis]]
		_host_offsets[axis].set_value_no_signal(value)
		_host_offsets[axis].editable = not host_binding.is_empty()
		_host_offsets[axis + "_label"].text = "树相对宿主 %s：%.2fm [-100 … 100]" % [axis.to_upper(), value]

func check_host_clearance(recipe: Dictionary) -> Dictionary:
	if host_binding.is_empty() or not bool(host_binding.get("enabled", false)):
		return {"ok": true, "reason": "宿主仅参考，尚未绑定路径"}
	var decoded = HostAttachment.decode_transform(host_binding.get("matrix"))
	if not bool(decoded.ok): return decoded
	return host_attachment.check_clearance(recipe, decoded.transform)

func _apply_host_transform() -> void:
	var applied_binding := session.host_binding()
	if applied_binding.is_empty():
		preview.set_plant_transform(Transform3D.IDENTITY)
		return
	var decoded = HostAttachment.decode_transform(applied_binding.get("matrix"))
	if bool(decoded.ok):
		preview.set_plant_transform(decoded.transform)

func _host_failure(reason: String) -> Dictionary:
	_set_status(reason, true)
	return {"ok": false, "reason": reason}

func save_animated() -> Dictionary:
	var applied = flush_pending()
	if not bool(applied.ok): return applied
	var fp = session.fingerprint()
	var result: Dictionary = store.save_animated(session.snapshot(), export_root)
	if not bool(result.ok): return _host_failure(str(result.reason))
	session.mark_saved(fp)
	last_export = result.duplicate(true)
	revision_saved.emit(_document_token, result.duplicate(true))
	_merge_drag = false
	_path.text = str(result.recipe_path)
	_set_status("已导出动态独立候选（不接入 Main）：" + str(result.animated_scene_path), false)
	refresh_files()
	return result

func save_attachment_manifest(path: String) -> Dictionary:
	var applied = flush_pending()
	if not bool(applied.ok): return applied
	if host_binding.is_empty() or not bool(host_binding.get("enabled", false)): return _host_failure("请先选择宿主洞口并通过结合校验")
	if last_export.get("fingerprint", "") != session.fingerprint(): return _host_failure("请先保存当前植物（静态或动态独立候选），避免引用过期配方")
	if path.is_empty(): path = str(last_export.directory).path_join("attachment.json")
	if not path.begins_with("res://outputs/") and not path.begins_with("res://scenes/workshop_plants/"): return _host_failure("结合描述仅写入 outputs 或 scenes/workshop_plants 候选目录")
	if path.contains("..") or path.get_extension() != "json" or FileAccess.file_exists(path): return _host_failure("结合描述必须是未存在的 .json 文件，不覆盖旧文件")
	if not DirAccess.dir_exists_absolute(path.get_base_dir()): return _host_failure("请先保存植物，或指定已存在的候选目录")
	var base = path.get_base_dir()
	var plant = str(last_export.get("animated_scene_path", last_export.scene_path))
	var manifest = {"version": 1, "host_path": _relative_manifest_path(base, str(host_binding.host_path)), "plant_path": _relative_manifest_path(base, plant), "matrix": host_binding.matrix.duplicate(), "matrix_layout": "column_major", "coordinate_space": "plant_to_host_root", "opening_id": host_binding.get("opening_id", ""), "candidate_only": true}
	var saved_state = session.state_fingerprint()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _host_failure("无法写入结合描述：" + error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(manifest, "\t", true, true))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK: return _host_failure("结合描述写入失败：" + error_string(error))
	if not session.mark_context_saved(saved_state): return _host_failure("结合描述已写入，但当前状态已变化，保留未保存标记")
	_merge_drag = false
	_manifest_path.text = path
	_set_status("已保存相对引用结合描述：" + path + "；宿主未改动，不接入 Main", false)
	return {"ok": true, "path": path, "manifest": manifest}

func _relative_manifest_path(directory: String, target: String) -> String:
	# 两端均已限定为 res://；Godot 4.7 的 GDScript 未暴露 path_to/path_to_file。
	var source_parts = directory.simplify_path().trim_prefix("res://").split("/", false)
	var target_parts = target.get_base_dir().simplify_path().trim_prefix("res://").split("/", false)
	var common = 0
	while common < mini(source_parts.size(), target_parts.size()) and source_parts[common] == target_parts[common]:
		common += 1
	var relative = PackedStringArray()
	for index in range(common, source_parts.size()): relative.append("..")
	for index in range(common, target_parts.size()): relative.append(target_parts[index])
	relative.append(target.get_file())
	return "/".join(relative)

func set_screen_visible(value: bool) -> void:
	visible = value
	if _ready_done:
		if not value:
			_timer.stop()
		preview.set_active(value)
		if value and has_pending_fields():
			_timer.start()

func get_recovery() -> Dictionary:
	return {"version": 1, "session": session.export_draft(), "input": input_recipe.duplicate(true), "selected_branch": selected_branch, "last_export": last_export.duplicate(true), "host_binding": host_binding.duplicate(true), "applied_host_binding": session.host_binding()}

func restore_recovery(data: Dictionary) -> Dictionary:
	if data.get("version") != 1 or not (data.get("session") is Dictionary):
		return {"ok": false, "reason": "树木草稿格式不匹配"}
	var draft: Dictionary = data.session.duplicate(true)
	# 仅迁移新增树冠字段缺失的规范保存指纹；损坏或非规范指纹仍交 Session 拒绝。
	if draft.get("saved_fingerprint") is String and not draft.saved_fingerprint.is_empty():
		var saved_parser := JSON.new()
		if saved_parser.parse(draft.saved_fingerprint) != OK:
			return {"ok": false, "reason": "草稿保存指纹非法"}
		var saved_recipe: Variant = saved_parser.data
		if saved_recipe is Dictionary and (not saved_recipe.has("foliage_mode") or not saved_recipe.has("volume_leaf_cards")) and Recipe.validate(saved_recipe).is_empty():
			var legacy_recipe: Dictionary = Recipe.normalized(saved_recipe)
			for key in ["foliage_mode", "volume_leaf_cards"]:
				if not saved_recipe.has(key): legacy_recipe.erase(key)
			if Recipe._stable_json(legacy_recipe) == draft.saved_fingerprint:
				draft.saved_fingerprint = Recipe.fingerprint(saved_recipe)
	var legacy_applied: Variant = data.get("applied_host_binding", data.get("host_binding", {}))
	if not draft.has("authoring_context"):
		draft.authoring_context = {"host_binding": legacy_applied if legacy_applied is Dictionary else {}}
	if not draft.has("saved_authoring_context"):
		draft.saved_authoring_context = {"host_binding": {}}
	if not draft.get("recipe") is Dictionary or not draft.authoring_context is Dictionary:
		return {"ok": false, "reason": "草稿已应用配方或上下文非法"}
	var prepared = _precheck_state(draft.recipe, draft.authoring_context)
	if not bool(prepared.ok):
		_set_status("草稿未恢复：" + str(prepared.reason), true)
		return prepared
	var result: Dictionary = session.restore_draft(draft)
	if not bool(result.get("ok", false)):
		_discard_host(prepared)
		return result
	_timer.stop()
	_dragging = false
	_merge_drag = false
	_drag_key = ""
	_install_host(prepared)
	input_recipe = session.snapshot()
	var pending: Variant = data.get("input", {})
	# 旧草稿待应用输入同样补 geometry；不能因新增可选键丢弃原待修字段。
	if pending is Dictionary and not pending.is_empty():
		pending = Recipe.normalized(pending)
	if pending is Dictionary and pending.keys().size() == input_recipe.keys().size():
		var numeric_safe = true
		for key in input_recipe:
			if not pending.has(key) or typeof(pending[key]) != typeof(input_recipe[key]):
				if not (pending.get(key) is float or pending.get(key) is int) or not (input_recipe[key] is float or input_recipe[key] is int):
					numeric_safe = false
		if numeric_safe:
			input_recipe = pending.duplicate(true)
	var binding: Variant = data.get("host_binding", session.host_binding())
	host_binding = binding.duplicate(true) if binding is Dictionary else session.host_binding()
	selected_branch = str(data.get("selected_branch", ""))
	var exported: Variant = data.get("last_export", {})
	last_export = exported.duplicate(true) if exported is Dictionary else {}
	_accept_result(result)
	_sync_controls()
	if has_pending_fields():
		buttons.undo.disabled = false
		_set_status("已恢复待应用输入；模型与位置保持上次成功状态", false)
	return result
