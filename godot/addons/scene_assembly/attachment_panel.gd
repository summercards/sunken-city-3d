@tool
extends VBoxContainer

signal inputs_changed

# 必须在加入场景树前设置；布局宽度由工坊父级滚动容器决定。
var embedded_workshop := false
var _active := true
var _document_serial := 0
var _category_buttons: Dictionary = {}

const Recipe = preload("res://src/building_attachments/recipe.gd")
const Catalog = preload("res://src/building_attachments/catalog.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const Gallery = preload("res://addons/scene_assembly/attachment_gallery.gd")
const Thumbnail = preload("res://addons/scene_assembly/thumbnail.gd")

var controller: Node
var gallery: ItemList
var search: LineEdit
var category := ""
var gallery_condition := "fresh"
const CONDITION_LABELS := {"fresh": "全新", "damaged": "破损", "ruined": "残破"}
const BUTTON_LABELS := {"signage": "招牌广告", "hvac": "机电通信", "water": "水箱管线", "shelter": "风管棚盖", "frame": "框式", "block": "块式", "marquee": "灯泡边框", "wall": "墙面", "roof": "屋顶"}
var gallery_panel: VBoxContainer
var editor_panel: VBoxContainer
var fields: Dictionary = {}
var choices: Dictionary = {}
var text_input: LineEdit
var text_hint: Label
var summary: Label
var host_label: Label
var status: Label
var preview: TextureRect
var candidate_path: LineEdit
var collision: CheckBox
var underwater: CheckBox
var draft: Dictionary = {}
var _baseline: Dictionary = {}
var _baseline_mount: Dictionary = {}
var _context := ""
var _drafts: Dictionary = {}
var _refreshing := false
var _restoring := false
var _applying := false
var _thumbs: Dictionary = {}
var _thumbnail_errors: Dictionary = {}
var _failure_texture: Texture2D
var _queue: Array[Dictionary] = []
var _busy := false
var _capture: SubViewport
var _current_texture_key := ""
var _preview_timer: Timer
var _last_input_fingerprint := ""

func _input_fingerprint() -> String:
	return JSON.stringify([input_recipe(), choices.mount_mode.value, fields.offset.slider.value, fields.angle.slider.value, gallery_condition]).sha256_text()

func _ready() -> void:
	_refreshing = true
	set_meta("cozy_skip", true)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var modes := HBoxContainer.new()
	add_child(modes)
	_button(modes, "图库", func() -> void: _show_gallery(true))
	_button(modes, "编辑", func() -> void: _show_gallery(false))
	host_label = _label(self, "宿主未锁定\n请选择建筑后锁定")
	_compact_label(host_label)
	_button(self, "锁定选中节点为宿主", _lock_host).visible = not embedded_workshop
	_button(self, "编辑宿主（原工坊）", _edit_host).visible = not embedded_workshop
	if embedded_workshop: host_label.text = "当前工坊房屋"
	gallery_panel = VBoxContainer.new()
	gallery_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(gallery_panel)
	var categories := HFlowContainer.new()
	gallery_panel.add_child(categories)
	var group := ButtonGroup.new()
	for value: String in ["", "signage", "hvac", "water", "shelter"]:
		var button := _button(categories, "全部" if value.is_empty() else str(BUTTON_LABELS[value]), _set_category.bind(value))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = value.is_empty()
		_category_buttons[value] = button
	_choice(gallery_panel, "gallery_condition", "图库状态", ["fresh", "damaged", "ruined"])
	_choice_value("gallery_condition", gallery_condition)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称 / type_id"
	search.text_changed.connect(func(_value: String) -> void:
		if _restoring: return
		refresh_gallery()
		if not _refreshing and not _restoring: inputs_changed.emit())
	gallery_panel.add_child(search)
	gallery = Gallery.new()
	gallery.panel = self
	gallery.fixed_icon_size = Vector2i(112, 96)
	gallery.icon_mode = ItemList.ICON_MODE_TOP
	gallery.max_columns = 2
	gallery.fixed_column_width = 135
	gallery.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gallery.custom_minimum_size.y = 160 if embedded_workshop else 230
	gallery.item_selected.connect(_choose_type)
	gallery.item_activated.connect(_activate_type)
	gallery_panel.add_child(gallery)
	_button(gallery_panel, "编辑组件", _edit_gallery_selection)
	gallery.add_theme_font_size_override("font_size", 16)
	gallery.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	gallery.resized.connect(_resize_gallery)
	call_deferred("_resize_gallery")
	editor_panel = VBoxContainer.new()
	editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(editor_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 200
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_panel.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	summary = _label(form, "请选择类型\n状态、面数与阻挡将在此显示")
	_compact_label(summary)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(160, 120)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	form.add_child(preview)
	_choice(form, "condition", "状态", ["fresh", "damaged", "ruined"])
	_choice(form, "style", "广告样式", ["frame", "block", "marquee"])
	text_input = LineEdit.new()
	text_input.placeholder_text = "英文大写文字，不截断输入"
	text_input.text_changed.connect(func(_value: String) -> void: _input_changed())
	form.add_child(text_input)
	text_hint = _label(form, "A-Z / 0-9 / 空格 / .-!& · 最多24字符；不支持字符会拒绝并保留输入")
	for axis: String in ["width", "height", "depth"]: _slider(form, axis, {"width": "宽度 m", "height": "高度 m", "depth": "深度 m"}[axis], 0.1, 10, 0.001)
	_slider(form, "scale", "大小", 0.75, 1.25, 0.01)
	_choice(form, "mount_mode", "挂载面", ["wall", "roof"])
	_slider(form, "offset", "离面额外偏移 m", 0.0, 0.5, 0.001)
	_slider(form, "angle", "绕法线角度 °", -180, 180, 1)
	fields.offset.label.tooltip_text = "基础世界净空0.012m；补偿非均匀父变换，不缩放房屋。滑块仅改输入，应用才提交历史。"
	collision = CheckBox.new()
	collision.text = "人物阻挡"
	collision.tooltip_text = "显式碰撞层256；不自动生成导航、船只阻挡或潜水功能。"
	collision.toggled.connect(func(_value: bool) -> void: _input_changed())
	form.add_child(collision)
	underwater = CheckBox.new()
	underwater.text = "水下纯观赏"
	underwater.tooltip_text = "须手动关闭人物阻挡；冲突时拒绝应用，不会静默修改。"
	underwater.toggled.connect(func(_value: bool) -> void: _input_changed())
	form.add_child(underwater)
	_button(form, "复制详情", _copy_details)
	var operations := HFlowContainer.new()
	editor_panel.add_child(operations)
	_button(operations, "贴到宿主", _arm)
	_button(operations, "应用到选中外挂", apply_selected)
	_button(operations, "复制", func() -> void: controller.duplicate_selected())
	_button(operations, "删除", func() -> void: controller.delete_selected())
	_button(operations, "重新贴合…", _reproject)
	_button(operations, "取消贴面", func() -> void: controller.cancel_arm())
	_button(operations, "放弃当前输入", _discard)
	candidate_path = LineEdit.new()
	candidate_path.placeholder_text = "候选修订目录 / attachment.recipe.json（白名单）"
	form.add_child(candidate_path)
	var files := HFlowContainer.new()
	form.add_child(files)
	_button(files, "保存独立候选新修订", save_candidate)
	_button(files, "校验并打开候选 JSON", load_candidate)
	candidate_path.visible = not embedded_workshop
	files.visible = not embedded_workshop
	candidate_path.text_changed.connect(func(_value: String) -> void:
		if not _refreshing and not _restoring: inputs_changed.emit())
	status = _label(self, "32 种原生外挂；随建筑作品保存。" if embedded_workshop else "32 种原生外挂；场景 Ctrl+S 手动保存，不自动写 Main。")
	status.max_lines_visible = 4
	_capture = Thumbnail.new()
	add_child(_capture)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.18
	_preview_timer.timeout.connect(_queue_current_preview)
	add_child(_preview_timer)
	controller.message.connect(report)
	controller.changed.connect(refresh_selection)
	for control: Control in find_children("*", "Control", true, false):
		control.add_theme_font_size_override("font_size", 16)
		if control is BaseButton: control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 34)
	var defaults: Dictionary = controller.bind_candidate_defaults("sign_fascia")
	_context = "draft:sign_fascia"
	_load_inputs(defaults.recipe)
	_show_gallery(true)
	refresh_gallery()
	visibility_changed.connect(_visibility_updated)
	_visibility_updated()

func set_active(active: bool) -> void:
	_active = active
	visible = active
	_visibility_updated()

func _visibility_updated() -> void:
	var running := _active and is_inside_tree() and is_visible_in_tree()
	if is_instance_valid(controller): controller.set_active(running)
	if not running:
		if is_instance_valid(_preview_timer): _preview_timer.stop()
	elif not _restoring and is_instance_valid(_preview_timer) and not draft.is_empty():
		_preview_timer.start()
		call_deferred("_render_thumbnails")

func _resize_gallery() -> void:
	if not is_instance_valid(gallery): return
	var width := maxi(1, floori(gallery.size.x) - 28)
	gallery.max_columns = 2 if width >= 200 else 1
	gallery.fixed_column_width = maxi(1, floori(float(width) / float(gallery.max_columns)))
	gallery.fixed_icon_size = Vector2i(mini(112, maxi(24, gallery.fixed_column_width - 20)), 96)

func _compact_label(label: Label) -> void:
	label.max_lines_visible = 2
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _copy_details() -> void:
	DisplayServer.clipboard_set(host_label.tooltip_text + "\n" + summary.tooltip_text + "\n" + status.tooltip_text)
	report("已复制宿主、外挂与状态详情")

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.tooltip_text = text
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _choice(parent: Node, key: String, caption: String, values: Array) -> void:
	var box := VBoxContainer.new()
	parent.add_child(box)
	_label(box, caption)
	var row := HFlowContainer.new()
	box.add_child(row)
	var group := ButtonGroup.new()
	var buttons: Dictionary = {}
	for value: String in values:
		var button := _button(row, str(CONDITION_LABELS.get(value, value)) if key.ends_with("condition") else str(BUTTON_LABELS.get(value, value)), _choose.bind(key, value))
		button.toggle_mode = true
		button.button_group = group
		buttons[value] = button
	choices[key] = {"box": box, "buttons": buttons, "value": str(values[0])}

func _choose(key: String, value: String) -> void:
	choices[key].value = value
	if key == "gallery_condition":
		gallery_condition = value
		# 仅草稿同步全局预览态；已选场景外挂的未应用输入不受影响。
		if _context.begins_with("draft:"): _choice_value("condition", value)
		refresh_gallery()
	elif key == "condition":
		gallery_condition = value
		_choice_value("gallery_condition", value)
	_input_changed()

func _slider(parent: Node, key: String, caption: String, minimum: float, maximum: float, step: float) -> void:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var label := _label(box, caption)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(func(_value: float) -> void:
		_update_slider_label(key)
		_input_changed())
	box.add_child(slider)
	fields[key] = {"slider": slider, "label": label, "caption": caption}

func _update_slider_label(key: String) -> void:
	var item: Dictionary = fields[key]
	var slider: HSlider = item.slider
	item.label.text = "%s  %.3f  [%.3f..%.3f]" % [item.caption, slider.value, slider.min_value, slider.max_value]

func _choice_value(key: String, value: String) -> void:
	choices[key].value = value
	for name: String in choices[key].buttons:
		choices[key].buttons[name].set_pressed_no_signal(name == value)

func _show_gallery(show_gallery: bool) -> void:
	gallery_panel.visible = show_gallery
	editor_panel.visible = not show_gallery
	if show_gallery and is_instance_valid(gallery): refresh_gallery()
	if not _refreshing and not _restoring: inputs_changed.emit()

func _set_category(value: String) -> void:
	category = value
	refresh_gallery()
	if not _refreshing and not _restoring: inputs_changed.emit()

func recipe_for_type(type_id: String) -> Dictionary:
	var recipe: Dictionary
	if draft.get("type_id", "") == type_id:
		recipe = input_recipe()
	elif _drafts.has("draft:" + type_id):
		recipe = _drafts["draft:" + type_id].recipe.duplicate(true)
	else:
		recipe = Recipe.defaults(type_id)
	if not recipe.is_empty(): recipe.condition = gallery_condition
	return recipe

func prepare_drag(type_id: String) -> Dictionary:
	if draft.get("type_id", "") == type_id and _context.begins_with("draft:"):
		_choice_value("condition", gallery_condition)
	var options: Dictionary = _options()
	if not options.ok: return options
	var recipe: Dictionary = recipe_for_type(type_id)
	var reason: String = Recipe.validate(recipe)
	if not reason.is_empty():
		report(reason)
		return {"ok": false, "reason": reason}
	var result: Dictionary = controller.arm(recipe)
	if result.ok:
		controller.set_meta("dragging", true)
		result.recipe = recipe.duplicate(true)
	return result

func refresh_gallery() -> void:
	if not is_instance_valid(gallery) or _restoring: return
	gallery.clear()
	for entry: Dictionary in Catalog.search(search.text, category):
		var recipe := recipe_for_type(entry.type_id)
		var index := gallery.add_item(entry.name + "\n" + entry.type_id)
		gallery.set_item_metadata(index, entry.type_id)
		_enqueue(recipe)
		_update_card(index, recipe)
	call_deferred("_render_thumbnails")

static func thumbnail_key(recipe: Dictionary) -> String:
	return "%s/%s/%s/%s/%s" % [recipe.get("type_id", ""), recipe.get("condition", ""), recipe.get("style", ""), str(recipe.get("text", "")).sha256_text(), JSON.stringify([recipe.get("dimensions", {}), recipe.get("scale", 1.0), recipe.get("colors", {})]).sha256_text()]

func _enqueue(recipe: Dictionary) -> void:
	var key := thumbnail_key(recipe)
	if _thumbs.has(key) or _thumbnail_errors.has(key): return
	for queued: Dictionary in _queue:
		if thumbnail_key(queued) == key: return
	var reason: String = Recipe.validate(recipe)
	if not reason.is_empty():
		_thumbnail_failed(recipe, reason)
		return
	_queue.append(recipe.duplicate(true))

func _update_card(index: int, recipe: Dictionary) -> void:
	var key := thumbnail_key(recipe)
	var entry: Dictionary = Catalog.get_entry(str(recipe.type_id))
	var reason := str(_thumbnail_errors.get(key, ""))
	gallery.set_item_text(index, ("[失败] " if not reason.is_empty() else "") + str(entry.name) + "\n" + str(CONDITION_LABELS[recipe.condition]))
	gallery.set_item_icon(index, _failure_icon() if not reason.is_empty() else _thumbs.get(key))
	gallery.set_item_tooltip(index, "%s · %s · %s\n%s%s" % [entry.category, entry.mount_mode, recipe.condition, entry.damage[recipe.condition], "\n生成失败：" + reason if not reason.is_empty() else ""])

func _failure_icon() -> Texture2D:
	if _failure_texture != null: return _failure_texture
	var image := Image.create(112, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.07, 0.07, 1.0))
	for i: int in range(18, 78):
		for width: int in range(-2, 3):
			image.set_pixel(i + 8, i + width, Color(1, 0.45, 0.35))
			image.set_pixel(103 - i, i + width, Color(1, 0.45, 0.35))
	_failure_texture = ImageTexture.create_from_image(image)
	return _failure_texture

func _thumbnail_failed(recipe: Dictionary, reason: String) -> void:
	var key := thumbnail_key(recipe)
	_thumbnail_errors[key] = reason
	if key == _current_texture_key:
		preview.texture = _failure_icon()
		preview.tooltip_text = "生成失败：" + reason
		report("生成失败：" + reason)
	for index: int in gallery.item_count:
		var current := recipe_for_type(str(gallery.get_item_metadata(index)))
		if thumbnail_key(current) == key: _update_card(index, current)

func _render_thumbnails() -> void:
	if _busy or not _active or not is_visible_in_tree() or not is_instance_valid(_capture): return
	_busy = true
	while not _queue.is_empty() and is_inside_tree() and _active and is_visible_in_tree():
		var serial := _document_serial
		var recipe: Dictionary = _queue.pop_front()
		var key := thumbnail_key(recipe)
		var built: Dictionary = controller._build_trusted(recipe)
		if not built.ok:
			_thumbnail_failed(recipe, str(built.get("reason", "原生生成失败")))
			continue
		var texture: Texture2D = await _capture.capture_root(built.root, Vector3(1, 0.7, -1.5))
		if not is_inside_tree():
			_busy = false
			return
		if serial != _document_serial: continue
		if texture == null:
			_thumbnail_failed(recipe, "缩略图捕获失败，未返回有效图像")
			continue
		_thumbs[key] = texture
		if key == _current_texture_key:
			preview.texture = texture
			preview.tooltip_text = ""
		for index: int in gallery.item_count:
			var current := recipe_for_type(str(gallery.get_item_metadata(index)))
			if thumbnail_key(current) == key: _update_card(index, current)
	_busy = false

func _choose_type(index: int) -> void:
	var type_id := str(gallery.get_item_metadata(index))
	_stash()
	controller.cancel_arm(false)
	# 图库明确进入独立草稿，不把新类型悄悄替换到当前场景外挂。
	_context = "draft:" + type_id
	if _drafts.has(_context):
		_restore(_drafts[_context])
	else:
		var result: Dictionary = controller.bind_candidate_defaults(type_id)
		_load_inputs(result.recipe)
	_choice_value("condition", gallery_condition)
	_input_changed()
	# item_selected 在按下时触发；保持源可见直到拖放判定结束。
	report("已选择 %s；可按住拖入视口，或点击编辑组件/双击进入编辑" % type_id)

func _activate_type(index: int) -> void:
	if _context != "draft:" + str(gallery.get_item_metadata(index)): _choose_type(index)
	_show_gallery(false)

func _edit_gallery_selection() -> void:
	var indices := gallery.get_selected_items()
	if indices.is_empty():
		report("请先选择一个组件")
		return
	_activate_type(int(indices[0]))

func input_recipe() -> Dictionary:
	if draft.is_empty(): return {}
	var recipe := draft.duplicate(true)
	recipe.condition = choices.condition.value
	recipe.style = choices.style.value
	recipe.text = text_input.text
	for axis: String in ["width", "height", "depth"]: recipe.dimensions[axis] = fields[axis].slider.value
	recipe.scale = fields.scale.slider.value
	recipe.collision_enabled = collision.button_pressed
	recipe.usage = "decorative_underwater" if underwater.button_pressed else "above_water"
	return recipe

func _input_changed() -> void:
	if _refreshing or _restoring: return
	var fingerprint := _input_fingerprint()
	if fingerprint != _last_input_fingerprint and controller.armed:
		controller.cancel_arm(false)
		report("输入已改变，贴面/拖放已取消；当前输入保留，请重新贴到宿主")
	_last_input_fingerprint = fingerprint
	var recipe := input_recipe()
	text_hint.text = "%d / 24 · A-Z、0-9、空格、.-!&；不截断、不自动转大写" % text_input.text.length()
	var reason: String = Recipe.validate(recipe)
	if not reason.is_empty(): report(reason)
	_current_texture_key = thumbnail_key(recipe)
	if _thumbnail_errors.has(_current_texture_key):
		preview.texture = _failure_icon()
		preview.tooltip_text = str(_thumbnail_errors[_current_texture_key])
	elif _thumbs.has(_current_texture_key):
		preview.texture = _thumbs[_current_texture_key]
		preview.tooltip_text = ""
	if _active and is_visible_in_tree() and is_instance_valid(_preview_timer): _preview_timer.start()
	inputs_changed.emit()

func _queue_current_preview() -> void:
	if not _active or not is_visible_in_tree() or _restoring: return
	_enqueue(input_recipe())
	call_deferred("_render_thumbnails")

func _load_inputs(recipe: Dictionary, mount: Dictionary = {}) -> void:
	_refreshing = true
	draft = recipe.duplicate(true)
	_baseline = recipe.duplicate(true)
	_baseline_mount = mount.duplicate(true)
	var entry: Dictionary = Catalog.get_entry(recipe.type_id)
	_choice_value("condition", recipe.condition)
	_choice_value("style", recipe.style)
	_choice_value("mount_mode", str(mount.get("mode", "roof" if entry.anchor == "mount_roof" else "wall")))
	_baseline_mount.merge({"mode": choices.mount_mode.value, "offset_m": float(mount.get("offset_m", 0.0)), "angle_degrees": float(mount.get("angle_degrees", 0.0))}, true)
	choices.style.box.visible = entry.category == "signage"
	choices.mount_mode.box.visible = entry.mount_mode == "any"
	text_input.editable = entry.category == "signage"
	text_input.text = recipe.text
	for axis: String in ["width", "height", "depth"]:
		var slider: HSlider = fields[axis].slider
		slider.min_value = entry.dimension_bounds[axis].min
		slider.max_value = entry.dimension_bounds[axis].max
		slider.set_value_no_signal(recipe.dimensions[axis])
	fields.scale.slider.set_value_no_signal(recipe.scale)
	fields.offset.slider.set_value_no_signal(float(mount.get("offset_m", 0.0)))
	fields.angle.slider.set_value_no_signal(float(mount.get("angle_degrees", 0.0)))
	collision.set_pressed_no_signal(recipe.collision_enabled)
	underwater.set_pressed_no_signal(recipe.usage == "decorative_underwater")
	for key: String in fields: _update_slider_label(key)
	summary.text = "%s · %s\n%s" % [entry.name, CONDITION_LABELS[recipe.condition], BUTTON_LABELS.get(entry.mount_mode, "可选挂载面")]
	summary.tooltip_text = "%s\n类型：%s\n候选ID：%s\n状态：%s" % [summary.text, recipe.type_id, recipe.attachment_id, recipe.condition]
	_refreshing = false
	_input_changed()

func _stash() -> void:
	if draft.is_empty(): return
	if not _context.begins_with("draft:") and _inputs_clean():
		_drafts.erase(_context)
		return
	_drafts[_context] = _snapshot_inputs()

func _restore(data: Dictionary) -> void:
	var restoring := _restoring
	_restoring = true
	_load_inputs(data.recipe, data.mount)
	_baseline = data.baseline.duplicate(true)
	_baseline_mount = data.get("baseline_mount", {}).duplicate(true)
	if data.has("draft"): draft = data.draft.duplicate(true)
	_restoring = restoring
	_input_changed()

func _snapshot_inputs() -> Dictionary:
	return {"draft": draft.duplicate(true), "recipe": input_recipe(), "baseline": _baseline.duplicate(true), "baseline_mount": _baseline_mount.duplicate(true), "mount": {"mode": choices.mount_mode.value, "offset_m": fields.offset.slider.value, "angle_degrees": fields.angle.slider.value}}

func _snapshot_dirty(data: Dictionary) -> bool:
	var mount: Dictionary = data.mount
	var baseline_mount: Dictionary = data.baseline_mount
	return data.recipe != data.baseline or mount.mode != baseline_mount.get("mode", mount.mode) or not is_equal_approx(float(mount.offset_m), float(baseline_mount.get("offset_m", 0.0))) or not is_equal_approx(float(mount.angle_degrees), float(baseline_mount.get("angle_degrees", 0.0)))

func _installed_contexts() -> Dictionary:
	var installed: Dictionary = {}
	if is_instance_valid(controller.host_container):
		var layer: Node = controller.host_container.get_node_or_null("Attachments")
		if layer != null:
			for node: Node in layer.get_children():
				if node.has_meta("sea_attachment"): installed[str(node.get_meta("sea_attachment").get("instance_id", ""))] = true
	return installed

# 只统计仍安装在当前预览的实例；新库默认草稿不算待应用作品。
func has_pending_inputs() -> bool:
	var installed := _installed_contexts()
	if installed.has(_context) and not draft.is_empty() and not _inputs_clean(): return true
	for context: String in _drafts:
		if context != _context and installed.has(context) and _snapshot_dirty(_drafts[context]): return true
	return false

# 已删除实例缓存保留供撤销恢复，但不阻挡保存；新库/候选只统计修改过的草稿。
func has_unsaved_inputs() -> bool:
	var installed := _installed_contexts()
	if (installed.has(_context) or _context.begins_with("draft:") or _context.begins_with("candidate:")) and not draft.is_empty() and not _inputs_clean(): return true
	for context: String in _drafts:
		if context != _context and (installed.has(context) or context.begins_with("draft:") or context.begins_with("candidate:")) and _snapshot_dirty(_drafts[context]): return true
	return false

func get_recovery() -> Dictionary:
	var selected_id := ""
	if is_instance_valid(controller.selected): selected_id = str(controller.selected.get_meta("sea_attachment", {}).get("instance_id", ""))
	var gallery_selected := ""
	var indices := gallery.get_selected_items()
	if not indices.is_empty(): gallery_selected = str(gallery.get_item_metadata(indices[0]))
	return {"schema_version": 1, "context": _context, "inputs": _snapshot_inputs(), "drafts": _drafts.duplicate(true), "category": category, "gallery_condition": gallery_condition, "search": search.text, "gallery_visible": gallery_panel.visible, "gallery_selected": gallery_selected, "selected_instance": selected_id, "candidate_path": candidate_path.text}

func _recovery_recipe_reason(value: Variant) -> String:
	if not value is Dictionary: return "配方必须为 Dictionary"
	if not value.get("type_id") is String: return "缺少 type_id"
	var defaults: Dictionary = Recipe.defaults(value.type_id)
	if defaults.is_empty(): return "未知 type_id"
	# 恢复只校验数据形状与输入控件范围，不用业务校验拒绝用户失败输入。
	if not value.get("text") is String or not value.get("collision_enabled") is bool: return "文字或碰撞输入类型错误"
	if not value.get("usage") is String or not ["above_water", "decorative_underwater"].has(value.usage): return "未知 usage"
	var probe: Dictionary = value.duplicate(true)
	probe.text = defaults.text
	probe.collision_enabled = false
	return Recipe.validate(probe)

func _recovery_mount_reason(value: Variant, optional: bool = false) -> String:
	if not value is Dictionary: return "挂载输入必须为 Dictionary"
	if optional and value.is_empty(): return ""
	if not optional and value.size() != 3: return "挂载输入字段无效"
	if not value.get("mode") is String or not ["wall", "roof"].has(value.mode): return "挂载面无效"
	var distance: Variant = value.get("offset_m", 0.0) if optional else value.get("offset_m")
	var angle: Variant = value.get("angle_degrees", 0.0) if optional else value.get("angle_degrees")
	if not Recipe.number(distance) or float(distance) < 0.0 or float(distance) > 0.5: return "偏移越界"
	if not Recipe.number(angle) or absf(float(angle)) > 180.0: return "角度越界"
	if optional and value.size() > 3:
		return _recovery_anchor_reason(value)
	return ""

func _recovery_vector_reason(value: Variant) -> String:
	if not value is Array or value.size() != 3: return "锚点向量必须为三项数组"
	for component: Variant in value:
		if not Recipe.number(component): return "锚点向量必须为有限数值"
	return ""

func _recovery_anchor_reason(anchor: Dictionary) -> String:
	# 完整 anchor 与 controller._metadata 一致；不把已装实例的基线压缩为三个 UI 字段。
	for key: String in ["mode", "mesh_path", "surface", "triangle", "host_position", "host_normal", "local_position", "native", "declared_clearance_m", "offset_m", "angle_degrees"]:
		if not anchor.has(key): return "锚点缺少字段：" + key
	if not anchor.get("mesh_path") is String: return "锚点缺少 mesh_path 字符串"
	for key: String in ["surface", "triangle"]:
		var index: Variant = anchor.get(key)
		if not Recipe.number(index) or float(index) < 0.0 or float(index) != floorf(float(index)): return "锚点索引无效：" + key
	for key: String in ["host_position", "host_normal", "local_position"]:
		var reason := _recovery_vector_reason(anchor.get(key))
		if not reason.is_empty(): return key + "：" + reason
	if not Recipe.number(anchor.get("declared_clearance_m")) or not is_equal_approx(float(anchor.declared_clearance_m), 0.012): return "锚点声明净空无效"
	var native: Variant = anchor.get("native")
	if not native is Dictionary: return "锚点缺少 native"
	if not native.get("name") is String or not ["mount_back", "mount_roof"].has(native.name): return "未知原生锚点"
	if native.get("front_axis") != "-Z" or native.get("up_axis") != "+Y": return "原生锚点轴向无效"
	var reason := _recovery_vector_reason(native.get("position"))
	if not reason.is_empty(): return reason
	return controller.anchor_error({"mount_anchor": native})

func _recovery_inputs_reason(value: Variant) -> String:
	if not value is Dictionary: return "输入快照必须为 Dictionary"
	for key: String in ["recipe", "baseline", "draft"]:
		var reason := _recovery_recipe_reason(value.get(key))
		if not reason.is_empty(): return key + "：" + reason
		if value[key].type_id != value.recipe.type_id: return "快照类型不一致"
	var reason := _recovery_mount_reason(value.get("mount"))
	if not reason.is_empty(): return reason
	return _recovery_mount_reason(value.get("baseline_mount"), true)

func _recovery_json(value: Variant) -> bool:
	if value == null or value is String or value is bool: return true
	if value is int or value is float: return is_finite(float(value))
	if value is Array:
		for item: Variant in value:
			if not _recovery_json(item): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _recovery_json(value[key]): return false
		return true
	return false

func _recovery_reason(data: Dictionary) -> String:
	if not _recovery_json(data): return "恢复数据必须是有限数值的纯 JSON"
	if not Recipe.number(data.get("schema_version")) or float(data.schema_version) != 1.0: return "不支持的恢复版本"
	for key: String in ["context", "category", "gallery_condition", "search", "gallery_selected", "selected_instance", "candidate_path"]:
		if not data.get(key) is String: return "恢复字段必须为字符串：" + key
	if not ["", "signage", "hvac", "water", "shelter"].has(data.category): return "未知图库分类"
	if not CONDITION_LABELS.has(data.gallery_condition): return "未知图库状态"
	if not data.get("gallery_visible") is bool or not data.get("drafts") is Dictionary: return "图库状态或草稿缓存类型错误"
	if not data.gallery_selected.is_empty() and Catalog.get_entry(data.gallery_selected).is_empty(): return "未知图库选择"
	var reason := _recovery_inputs_reason(data.get("inputs"))
	if not reason.is_empty(): return reason
	if not _valid_recovery_context(data.context, data.inputs.recipe): return "当前草稿上下文无效"
	for context: Variant in data.drafts:
		if not context is String: return "草稿缓存 key 必须为字符串"
		reason = _recovery_inputs_reason(data.drafts[context])
		if not reason.is_empty(): return reason
		if not _valid_recovery_context(context, data.drafts[context].recipe): return "缓存草稿上下文无效"
	return ""

func _valid_recovery_context(context: String, recipe: Dictionary) -> bool:
	if context.begins_with("draft:"): return context == "draft:" + str(recipe.type_id)
	if context.begins_with("candidate:"): return context == "candidate:" + str(recipe.attachment_id)
	return not context.is_empty()

func restore_recovery(data: Dictionary) -> Dictionary:
	if not is_node_ready(): return {"ok": false, "reason": "面板尚未 ready"}
	var reason := _recovery_reason(data)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	# 全部校验通过后才写 UI；不 build、不提交历史、不启用贴面。
	_restoring = true
	controller.cancel_arm(false)
	_preview_timer.stop()
	_document_serial += 1
	_queue.clear()
	_drafts = data.drafts.duplicate(true)
	_context = data.context
	_restore(data.inputs)
	category = data.category
	for value: String in _category_buttons: _category_buttons[value].set_pressed_no_signal(value == category)
	gallery_condition = data.gallery_condition
	_choice_value("gallery_condition", gallery_condition)
	search.text = data.search
	candidate_path.text = data.candidate_path
	gallery_panel.visible = data.gallery_visible
	editor_panel.visible = not data.gallery_visible
	var targets: Array = []
	if is_instance_valid(controller.host_container):
		var layer: Node = controller.host_container.get_node_or_null("Attachments")
		if layer != null:
			for node: Node in layer.get_children():
				if str(node.get_meta("sea_attachment", {}).get("instance_id", "")) == data.selected_instance and not data.selected_instance.is_empty(): targets.append(node)
	controller._select_nodes(targets)
	_last_input_fingerprint = _input_fingerprint()
	_restoring = false
	refresh_gallery()
	for index: int in gallery.item_count:
		if str(gallery.get_item_metadata(index)) == data.gallery_selected: gallery.select(index)
	_input_changed()
	return {"ok": true, "reason": ""}

func reset_document() -> void:
	controller.cancel_arm(false)
	_preview_timer.stop()
	_document_serial += 1
	_queue.clear()
	_drafts.clear()
	_baseline.clear()
	_baseline_mount.clear()
	draft.clear()
	_context = ""
	_restoring = true
	controller._select_nodes([])
	candidate_path.text = ""
	search.text = ""
	category = ""
	for value: String in _category_buttons: _category_buttons[value].set_pressed_no_signal(value.is_empty())
	gallery_condition = "fresh"
	_choice_value("gallery_condition", gallery_condition)
	var defaults: Dictionary = controller.bind_candidate_defaults("sign_fascia")
	_context = "draft:sign_fascia"
	_load_inputs(defaults.recipe)
	preview.texture = null
	preview.tooltip_text = ""
	_restoring = false
	_show_gallery(true)
	_input_changed()

func _inputs_clean() -> bool:
	return input_recipe() == _baseline and choices.mount_mode.value == _baseline_mount.get("mode", choices.mount_mode.value) and is_equal_approx(fields.offset.slider.value, float(_baseline_mount.get("offset_m", 0.0))) and is_equal_approx(fields.angle.slider.value, float(_baseline_mount.get("angle_degrees", 0.0)))

func refresh_selection() -> void:
	if not is_instance_valid(summary) or _restoring: return
	host_label.text = "锁定宿主\n" + str(controller.host_container.name) if is_instance_valid(controller.host_container) else "宿主未锁定"
	host_label.tooltip_text = str(controller.host_container.get_path()) if is_instance_valid(controller.host_container) else "请选择建筑 Placement/Asset 或安全本地 Node3D 后锁定"
	if embedded_workshop:
		host_label.text = "当前工坊房屋"
		host_label.tooltip_text = "外挂仅写当前房屋预览，随建筑作品保存"
	if _applying: return
	if not is_instance_valid(controller.selected) or not controller.selected.is_inside_tree():
		inputs_changed.emit()
		return
	var data: Dictionary = controller.selected.get_meta("sea_attachment", {})
	if data.is_empty(): return
	var context := str(data.instance_id)
	if context != _context:
		_stash()
		_context = context
		if _drafts.has(context): _restore(_drafts[context])
		else: _load_inputs(data.recipe, data.anchor)
	elif _inputs_clean():
		_load_inputs(data.recipe, data.anchor)
	gallery_condition = str(choices.condition.value)
	_choice_value("gallery_condition", gallery_condition)
	var stats: Dictionary = data.get("stats", {})
	summary.text = "%s · %s\n%d 三角面 · %d 表面 · 阻挡%s" % [Catalog.get_entry(data.recipe.type_id).name, CONDITION_LABELS[data.recipe.condition], int(stats.get("triangles", 0)), int(stats.get("surfaces", 0)), "开" if data.recipe.collision_enabled else "关"]
	summary.tooltip_text = summary.text + "\n类型：" + str(data.recipe.type_id) + "\n实例ID：" + str(data.instance_id) + "\n挂载面：" + str(data.anchor.mode) + "\n" + JSON.stringify(data, "  ")
	var revision := str(controller.host_container.get_meta("sea_placement", {}).get("revision", "local"))
	if str(data.get("host_revision", "local")) != revision: report("宿主 revision 已变更；外挂变换保持，请检查贴合，必要时显式重新贴合")
	_show_gallery(false)

func _lock_host() -> void:
	var nodes: Array = controller._selected_nodes()
	if nodes.size() != 1:
		report("请只选择一个建筑宿主")
		return
	controller.set_host(nodes[0])

func _edit_host() -> void:
	if not is_instance_valid(controller.host_container):
		report("请先锁定宿主")
		return
	controller._select_nodes([controller.host_container])
	controller.assembly.edit_selected()

func _options() -> Dictionary:
	return controller.set_mount_options(choices.mount_mode.value, fields.offset.slider.value, fields.angle.slider.value)

func _arm() -> void:
	if not _options().ok: return
	controller.arm(input_recipe())
	if controller.armed: report("已启用贴面；移到工坊房屋预览查看 ghost，点击确认；Escape 取消" if embedded_workshop else "已启用贴面；移到编辑器 3D 视口查看 ghost，点击确认；Escape 取消")

func _reproject() -> void:
	if not is_instance_valid(controller.selected):
		report("请先选择外挂")
		return
	if input_recipe() != _baseline:
		report("存在未应用输入，请先应用或明确放弃，再重新贴合")
		return
	if not _options().ok: return
	controller.arm(input_recipe(), true)

func apply_selected() -> Dictionary:
	if not is_instance_valid(controller.selected):
		report("请先选择场景外挂；草稿使用贴到宿主")
		return {"ok": false, "reason": "未选中外挂"}
	var selected_data: Dictionary = controller.selected.get_meta("sea_attachment")
	if _context != str(selected_data.instance_id):
		report("当前为图库草稿，不能替换选中场景外挂；请重新选择该外挂进入编辑")
		return {"ok": false, "reason": "草稿和选择上下文不同"}
	if not _options().ok: return {"ok": false, "reason": "挂载选项无效"}
	_applying = true
	var result: Dictionary = controller.edit_selected_recipe(input_recipe())
	_applying = false
	if result.ok:
		_drafts.erase(_context)
		var data: Dictionary = result.attachment.get_meta("sea_attachment")
		_load_inputs(data.recipe, data.anchor)
		refresh_selection()
	return result

func _discard() -> void:
	_drafts.erase(_context)
	if is_instance_valid(controller.selected) and str(controller.selected.get_meta("sea_attachment").instance_id) == _context:
		var data: Dictionary = controller.selected.get_meta("sea_attachment")
		_load_inputs(data.recipe, data.anchor)
	else: _load_inputs(_baseline, _baseline_mount)
	report("已明确放弃此上下文未应用输入；场景未修改")

func save_candidate() -> Dictionary:
	var result: Dictionary = controller.save_candidate(input_recipe())
	if result.ok: candidate_path.text = result.recipe_path
	return result

func load_candidate() -> Dictionary:
	var result: Dictionary = controller.load_candidate(candidate_path.text)
	if result.ok:
		_stash()
		_context = "candidate:" + result.recipe.attachment_id
		_load_inputs(result.recipe)
	return result

func report(text: String) -> void:
	if not is_instance_valid(status): return
	status.text = text
	status.tooltip_text = text
