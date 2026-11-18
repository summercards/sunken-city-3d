@tool
extends Node
## 文档 UI 协调器；不扩展房屋配方或访问 Session 私有历史。

signal changed
signal selected
const Data = preload("res://addons/building_workshop/attachment_work_data.gd")
const HouseRecipe = preload("res://src/workshop/recipe.gd")
const HouseCatalog = preload("res://src/workshop/catalog.gd")
const History = preload("res://addons/building_workshop/attachment_history.gd")
const Controller = preload("res://addons/scene_assembly/attachment_controller.gd")
const AttachmentPanel = preload("res://addons/scene_assembly/attachment_panel.gd")
const PreviewInput = preload("res://addons/building_workshop/attachment_preview_input.gd")
const AttachmentCatalog = preload("res://src/building_attachments/catalog.gd")

var screen: Control
var preview: Control
var controller: Node
var panel: VBoxContainer
var history: RefCounted
var input: RefCounted
var instances: ItemList
var position_label: Label
var move_step: HSlider
var saved_fingerprint := ""
var document_id := ""
var _selection: Array = []
var _active := true
var _resetting := false
var _navigating := false
var _house_state := ""
var _house_merge := ""
var _move_buttons: Array[Button] = []
var _done: Array[Dictionary] = []
var _redo: Array[Dictionary] = []

func configure(owner_screen: Control, page: VBoxContainer, view: Control) -> void:
	screen = owner_screen
	preview = view
	history = History.new()
	controller = Controller.new()
	add_child(controller)
	input = PreviewInput.new()
	input.configure(preview, controller, select_nodes)
	preview.attachment_input = input
	controller.configure_workshop({"root": Callable(preview, "get_work_root"), "host_asset": Callable(preview, "get_host_asset"),
		"selection_get": get_selection, "selection_set": _set_selection, "history": history,
		"arm": Callable(input, "arm"), "cancel": Callable(input, "cancel")})
	panel = AttachmentPanel.new()
	panel.name = "WorkshopAttachmentPanel"
	panel.embedded_workshop = true
	panel.controller = controller
	page.add_child(panel)
	# 工坊只有外层参数滚动域；内嵌表单完整展开，避免嵌套滚动与期望高度向主预览传播。
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_FILL
	page.custom_minimum_size.y = 0
	page.size_flags_vertical = Control.SIZE_FILL
	var editor_scroll: ScrollContainer
	for child: Node in panel.editor_panel.get_children():
		if child is ScrollContainer:
			editor_scroll = child
			break
	if editor_scroll != null:
		var form := editor_scroll.get_child(0) as Control
		form.reparent(panel.editor_panel)
		panel.editor_panel.move_child(form, 0)
		form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		form.size_flags_vertical = Control.SIZE_FILL
		editor_scroll.get_parent().remove_child(editor_scroll)
		editor_scroll.free()
	panel.gallery.auto_height = false
	panel.gallery.custom_minimum_size.y = 160
	panel.gallery.size_flags_vertical = Control.SIZE_FILL
	panel.host_label.text = "当前房屋"
	panel.inputs_changed.connect(_inputs_changed)
	controller.changed.connect(_controller_changed)
	controller.message.connect(_message)
	history.committed.connect(_attachment_committed)
	history.changed.connect(_history_changed)
	var title := Label.new()
	title.text = "本栋已有外挂"
	page.add_child(title)
	instances = ItemList.new()
	instances.name = "WorkshopInstalledAttachments"
	instances.custom_minimum_size.y = 100
	instances.item_selected.connect(_select_index)
	page.add_child(instances)
	position_label = Label.new()
	position_label.text = "选择外挂后可沿实际支撑面微调"
	position_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(position_label)
	move_step = HSlider.new()
	move_step.name = "AttachmentMoveStep"
	move_step.min_value = 0.01
	move_step.max_value = 1.0
	move_step.step = 0.01
	move_step.value = 0.1
	move_step.tooltip_text = "局部三轴移动步距（米），每次重新射线贴合并严格检查支撑"
	page.add_child(move_step)
	var axes := HFlowContainer.new()
	page.add_child(axes)
	for axis: int in 3:
		for sign_value: int in [-1, 1]:
			var button := Button.new()
			button.text = ["X", "Y", "Z"][axis] + ("−" if sign_value < 0 else "+")
			button.custom_minimum_size.y = 40
			button.pressed.connect(_move_axis.bind(axis, sign_value))
			axes.add_child(button)
			_move_buttons.append(button)
	move_step.value_changed.connect(func(_value: float) -> void: _update_move_readout())
	for button: Node in panel.find_children("*", "Button", true, false):
		if button.text == "贴到宿主": button.text = "贴到当前房屋"
		if button.text == "复制":
			button.tooltip_text = "复制后使用下方三轴按钮移动；不依赖编辑器原生 gizmo"
		button.add_theme_font_size_override("font_size", 18)
	for control: Node in page.find_children("*", "Control", true, false):
		control.add_theme_font_size_override("font_size", 18 if control is BaseButton else 16)
	_house_state = _house_fingerprint()
	saved_fingerprint = Data.fingerprint(Data.empty_snapshot())
	document_id = str(screen.snapshot().get("building_id", ""))
	controller.set_host(preview.get_work_root())
	set_active(false)

func set_active(active: bool) -> void:
	if _active == active: return
	_active = active
	panel.set_active(active)
	controller.set_active(active)

func get_selection() -> Array:
	var valid: Array = []
	for node: Variant in _selection:
		if is_instance_valid(node) and node.is_inside_tree(): valid.append(node)
	return valid

func _set_selection(nodes: Array) -> void:
	_selection = nodes.duplicate()
	preview.highlight_attachment(nodes[0] if not nodes.is_empty() else null)

func select_nodes(nodes: Array) -> void:
	_set_selection(nodes)
	controller.select_attachment(nodes[0] if not nodes.is_empty() else null)
	if not nodes.is_empty(): selected.emit()

func _select_index(index: int) -> void:
	var id := str(instances.get_item_metadata(index))
	for node: Node in preview.get_attachment_root().get_children():
		if str(node.get_meta("sea_attachment", {}).get("instance_id", "")) == id:
			select_nodes([node])
			return

func _controller_changed() -> void:
	if _resetting: return
	panel.host_label.text = "当前房屋"
	instances.clear()
	for node: Node in preview.get_attachment_root().get_children():
		var data: Dictionary = node.get_meta("sea_attachment", {})
		var entry: Dictionary = AttachmentCatalog.get_entry(str(data.get("recipe", {}).get("type_id", "")))
		var index := instances.add_item(str(entry.get("name", node.name)))
		instances.set_item_metadata(index, str(data.get("instance_id", "")))
		if node == controller.selected: instances.select(index)
	var target: Node3D = controller.selected
	if is_instance_valid(target):
		position_label.text = "局部位置 X %.3f / Y %.3f / Z %.3f m\n三轴步移重新贴合；离面请用上方偏移，失败保持原位。" % [target.position.x, target.position.y, target.position.z]
		preview.highlight_attachment(target)
	else:
		position_label.text = "选择外挂后可沿实际支撑面微调"
		preview.highlight_attachment(null)
	_update_move_readout()
	changed.emit()

func _update_move_readout() -> void:
	for button: Button in _move_buttons:
		button.tooltip_text = "当前步距 %.2f m · 范围 0.01..1.00 m；沿支撑面移动并重验" % move_step.value
	move_step.tooltip_text = "当前步距 %.2f m · 范围 0.01..1.00 m" % move_step.value
	if position_label != null:
		position_label.text = position_label.text.split("\n步距")[0] + "\n步距 %.2f m [0.01..1.00]" % move_step.value

func _inputs_changed() -> void:
	if not _resetting: changed.emit()

func _message(text: String) -> void:
	text = text.replace("可用原生 gizmo 移动后显式重新贴合", "可用本页三轴步移并严格重验贴合")
	if not _resetting:
		panel.report(text)
		screen._set_status(text)

func capture() -> Dictionary:
	return Data.capture(preview.get_attachment_root())

func is_dirty() -> bool:
	return Data.fingerprint(capture()) != saved_fingerprint

func has_unsaved_inputs() -> bool:
	return panel.has_unsaved_inputs()

func save_block_reason() -> String:
	if panel.has_unsaved_inputs():
		return "外挂存在未应用输入（含其他实例缓存或图库草稿），请先应用到对应实例/贴到当前房屋，或明确放弃输入，再保存。"
	return Data.validate(capture())

func mark_saved() -> void:
	saved_fingerprint = Data.fingerprint(capture())
	changed.emit()

func prepare(snapshot: Variant, panel_recovery: Variant = {}) -> Dictionary:
	if not snapshot is Dictionary: return {"ok": false, "reason": "外挂快照必须为对象"}
	if not panel_recovery is Dictionary: return {"ok": false, "reason": "外挂输入恢复必须为对象"}
	if not panel_recovery.is_empty():
		var reason: String = panel._recovery_reason(panel_recovery)
		if not reason.is_empty(): return {"ok": false, "reason": "外挂输入恢复失败：" + reason}
	var built: Dictionary = Data.build(snapshot)
	if built.get("ok", false): built.snapshot = snapshot.duplicate(true)
	return built

func commit_document(prepared: Dictionary, recovery: Dictionary = {}, saved: String = "", current_document: String = "") -> void:
	_resetting = true
	controller.cancel_arm(false)
	history.clear_history()
	_selection.clear()
	controller.selected = null
	preview.replace_attachment_root(prepared.root)
	controller.set_host(preview.get_work_root())
	panel.reset_document()
	saved_fingerprint = Data.fingerprint(prepared.snapshot) if saved.is_empty() else saved
	document_id = current_document if not current_document.is_empty() else str(screen.snapshot().get("building_id", ""))
	reset_timeline()
	if not recovery.is_empty(): panel.restore_recovery(recovery)
	_resetting = false
	_controller_changed()
	set_active(screen.is_screen_active() and screen._page_picker.selected == screen.PAGES.find("外挂") and screen.is_visible_in_tree())

func house_rebuilt() -> void:
	controller.cancel_arm(false)
	if is_instance_valid(controller.selected): _set_selection([controller.selected])
	if is_instance_valid(controller.selected): preview.highlight_attachment(controller.selected)
	if preview.get_attachment_root().get_child_count() > 0:
		panel.report("房屋已更新，外挂位置保持；请检查贴合，必要时显式重新贴合。")

func recovery() -> Dictionary:
	return {"attachment_snapshot": capture(), "attachment_saved_fingerprint": saved_fingerprint,
		"attachment_panel_recovery": panel.get_recovery(), "attachment_document": document_id}

func _move_axis(axis: int, sign_value: int) -> void:
	var delta := Vector3.ZERO
	delta[axis] = float(sign_value) * move_step.value
	move_selected(delta)

func move_selected(delta: Vector3) -> Dictionary:
	if not delta.is_finite() or delta.length() > 1.001: return {"ok": false, "reason": "移动步距必须为有限值且不超过1米"}
	if panel.has_unsaved_inputs(): return screen._report_failure("请先应用或放弃外挂输入，再移动。")
	var node: Node3D = controller.selected
	if not is_instance_valid(node): return screen._report_failure("请先选择本栋外挂。")
	var metadata: Dictionary = node.get_meta("sea_attachment", {})
	var anchor: Dictionary = metadata.get("anchor", {})
	var values: Array = anchor.get("local_position", [])
	if values.size() != 3: return screen._report_failure("外挂缺少有效安装锚点。")
	var normal: Vector3 = (-node.global_basis.z if anchor.get("mode") == "wall" else node.global_basis.y).normalized()
	var shift: Vector3 = node.get_parent().global_basis * delta
	# 法线方向位移不是沿面移动；偏移由已有有界控件唯一管理。
	shift -= normal * shift.dot(normal)
	if shift.length_squared() < 0.0000001: return screen._report_failure("该轴垂直于支撑面；请用离面偏移或其他轴移动。")
	var point: Vector3 = node.global_transform * Vector3(values[0], values[1], values[2]) + shift
	var distance := float(anchor.get("offset_m", 0.0)) + 0.012
	controller.cancel_arm(false)
	controller.set_mount_options(str(anchor.mode), float(anchor.get("offset_m", 0.0)), float(anchor.get("angle_degrees", 0.0)))
	return controller.reproject_selected(point + normal * (2.0 - distance), -normal)

func _house_fingerprint() -> String:
	var recipe: Dictionary = screen.snapshot()
	recipe.erase("revision")
	return HouseRecipe.fingerprint(recipe) + "/" + HouseCatalog.fingerprint(screen.session.catalog)

func reset_timeline() -> void:
	_done.clear()
	_redo.clear()
	_house_merge = ""
	_house_state = _house_fingerprint()

func observe_house(merge_key: String = "") -> void:
	document_id = str(screen.snapshot().get("building_id", ""))
	var next := _house_fingerprint()
	if next == _house_state: return
	if _resetting or _navigating:
		_house_state = next
		return
	# 普通 changed 始终表示新提交；恢复旧值也不能冒充撤销，marker 仅由明确导航移动。
	_redo.clear()
	if not merge_key.is_empty() and merge_key == _house_merge and not _done.is_empty() and _done.back().domain == "house":
		_done.back().after = next
	else:
		_done.append({"domain": "house", "before": _house_state, "after": next})
	_house_merge = merge_key
	_house_state = next

func _attachment_committed(action_name: String) -> void:
	if _resetting: return
	if action_name == "新增建筑外挂" and is_instance_valid(controller.selected):
		# 明确贴面已消费的库草稿不再作为未应用缓存；其他实例/草稿输入仍保留。
		var installed: Dictionary = controller.selected.get_meta("sea_attachment", {})
		var key := "draft:" + str(installed.get("recipe", {}).get("type_id", ""))
		var cached: Dictionary = panel._drafts.get(key, {})
		if cached.get("recipe", {}) == installed.get("recipe", {}): panel._drafts.erase(key)
	_redo.clear()
	_house_merge = ""
	# 外挂动作截断房屋拖拽合并身份，避免跨域合并导致时间线多一条。
	screen._window_history_key = ""
	screen._window_history_fingerprint = ""
	_done.append({"domain": "attachment"})
	changed.emit()

func _history_changed() -> void:
	if not _resetting: _controller_changed()

func navigate(redo: bool, house_action: Callable) -> void:
	var source: Array[Dictionary] = _redo if redo else _done
	if source.is_empty():
		screen._set_status("没有可重做的修改" if redo else "没有可撤销的修改")
		return
	controller.cancel_arm(false)
	var marker: Dictionary = source.back()
	_navigating = true
	var ok := true
	if marker.domain == "attachment":
		ok = history.redo() if redo else history.undo()
	else:
		var before := _house_fingerprint()
		house_action.call(redo)
		ok = before != _house_fingerprint()
	_navigating = false
	_house_state = _house_fingerprint()
	_house_merge = ""
	if ok:
		source.pop_back()
		(_done if redo else _redo).append(marker)
		_controller_changed()

func _exit_tree() -> void:
	if is_instance_valid(controller):
		controller.cancel_arm(false)
		controller.set_process(false)
	if input != null: input.cancel()
	if history != null: history.clear_history()
	if is_instance_valid(preview): preview.attachment_input = null
