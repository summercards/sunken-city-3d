extends CanvasLayer
## 独立商店面板：只消费 ShopService 的快照/命令，不打开旧 HUD 商店页。
## 装配层负责 vendor_requested -> open_shop，以及打开期间屏蔽世界操作。
## handle_input 返回是否消费；可由装配层优先转发，也支持自身 _input。
signal closed(shop_id: String)
signal opened(shop_id: String)
const Cozy = preload("res://src/ui/cozy_ui.gd")
var _service: RefCounted
var _inventory: RefCounted
var _shop_id: String = ""
var _selected_id: String = ""
var _amount: int = 1
var _sequence: int = 0
var _purchasing: bool = false
var _opened_frame: int = -1
var _last_input_event: InputEvent
var _last_input_frame: int = -1
var _overlay: Control
var _title: Label
var _wallet: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _name: Label
var _description: Label
var _details: Label
var _quantity: Label
var _feedback: Label
var _availability: Label
var _minus: Button
var _plus: Button
var _buy: Button
var _close_button: Button
var _product_buttons: Array[Button] = []
var _focusables: Array[Button] = []

func configure(service: RefCounted, inventory: RefCounted) -> void:
	close()
	_disconnect_inventory()
	_service = service
	_inventory = inventory
	if _inventory != null:
		for signal_name in ["changed", "capacity_changed"]:
			if _inventory.has_signal(signal_name):
				_inventory.connect(signal_name, _on_inventory_changed)
	_ensure_ui()

func _exit_tree() -> void:
	_disconnect_inventory()

func _disconnect_inventory() -> void:
	if _inventory == null:
		return
	for signal_name in ["changed", "capacity_changed"]:
		if _inventory.has_signal(signal_name) and _inventory.is_connected(signal_name, _on_inventory_changed):
			_inventory.disconnect(signal_name, _on_inventory_changed)

func _on_inventory_changed(_first: Variant = null, _second: Variant = null) -> void:
	if is_open():
		_refresh()

func open_shop(shop_id: String) -> Dictionary:
	_ensure_ui()
	if _service == null or _inventory == null:
		return {"ok": false, "reason": "商店面板尚未接入服务和背包"}
	if _service.inventory != _inventory:
		return {"ok": false, "reason": "商店与面板必须使用同一个背包"}
	var result: Dictionary = _service.open_shop(shop_id)
	if not result.ok:
		if is_open():
			_feedback.text = result.reason
		return result
	if is_open():
		close()
	_shop_id = shop_id
	_opened_frame = Engine.get_process_frames()
	_selected_id = ""
	_amount = 1
	_feedback.text = ""
	var snapshot: Dictionary = _service.shop_snapshot(shop_id)
	_title.text = snapshot.get("display_name", "商店")
	_build_products(snapshot.get("products", []))
	_overlay.show()
	if not _product_buttons.is_empty():
		_selected_id = str(_product_buttons[0].get_meta("product_id"))
		_product_buttons[0].grab_focus()
	_refresh()
	opened.emit(shop_id)
	return result

func close() -> void:
	if not is_open():
		return
	var previous: String = _shop_id
	_shop_id = ""
	_overlay.hide()
	var focus: Control = _overlay.get_viewport().gui_get_focus_owner() if _overlay.is_inside_tree() else null
	if focus != null and _overlay.is_ancestor_of(focus):
		focus.release_focus()
	closed.emit(previous)

func is_open() -> bool:
	return _shop_id != "" and _overlay != null and _overlay.visible

func _input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()

func handle_input(event: InputEvent) -> bool:
	if not is_open() or not event is InputEventKey:
		return false
	var frame: int = Engine.get_process_frames()
	# HUD 委托与自身 _input 可能转发同一事件，必须先去重再执行交易。
	if event == _last_input_event and frame == _last_input_frame:
		return true
	_last_input_event = event
	_last_input_frame = frame
	# NPC 确认键可在本帧开店，消费余下输入，下一帧才允许商店操作。
	if frame == _opened_frame:
		return true
	# 按住确认键不会连买；松键也被模态面板消费，不泄漏给世界交互。
	if not event.pressed or event.echo:
		return true
	var key: Key = event.keycode if event.keycode != 0 else event.physical_keycode
	match key:
		KEY_ESCAPE:
			close()
		KEY_UP:
			_move_focus(-1)
		KEY_DOWN:
			_move_focus(1)
		KEY_LEFT, KEY_MINUS, KEY_KP_SUBTRACT:
			_change_amount(-1)
		KEY_RIGHT, KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			_change_amount(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE:
			var focused: Control = _overlay.get_viewport().gui_get_focus_owner()
			if focused in _product_buttons:
				_purchase()
			elif focused is Button and focused in _focusables and not focused.disabled:
				focused.pressed.emit()
		KEY_TAB:
			_move_focus(-1 if event.shift_pressed else 1)
	return true

func _move_focus(step: int) -> void:
	var focused: Control = _overlay.get_viewport().gui_get_focus_owner()
	var index: int = _focusables.find(focused)
	for offset in range(1, _focusables.size() + 1):
		var next: int = posmod(index + step * offset, _focusables.size())
		if not _focusables[next].disabled:
			_focusables[next].grab_focus()
			return

func _select(product_id: String) -> void:
	if _selected_id != product_id:
		_selected_id = product_id
		_amount = 1
		_feedback.text = ""
	_refresh()

func _change_amount(delta: int) -> void:
	if _service == null or _selected_id == "":
		return
	var limit: int = _service.max_buy(_shop_id, _selected_id)
	_amount = clampi(_amount + delta, 1, maxi(1, limit))
	_feedback.text = ""
	_refresh()

func _purchase() -> void:
	if _purchasing or not is_open() or _selected_id == "":
		return
	_purchasing = true
	_sequence += 1
	var token: String = "panel:%s:%s" % [get_instance_id(), _sequence]
	var result: Dictionary = _service.buy(_shop_id, _selected_id, _amount, token)
	_purchasing = false
	if result.ok:
		_feedback.text = "已购入 %s × %d，花费 %d 瓶盖" % [result.label, result.amount, result.total_cost]
	else:
		_feedback.text = str(result.get("reason", "交易未完成"))
	_refresh()

func _refresh() -> void:
	if not is_open() or _selected_id == "":
		return
	var estimate: Dictionary = _service.quote(_shop_id, _selected_id, _amount)
	_wallet.text = "瓶盖余额  %d    ·    背包  %d / %d 格" % [estimate.get("coins", 0), estimate.get("slots_used", 0), estimate.get("capacity", 0)]
	_name.text = estimate.get("label", "商品暂不可用")
	_description.text = estimate.get("product", {}).get("description", "")
	_quantity.text = str(_amount)
	var price: int = estimate.get("unit_price", 0)
	var total: int = estimate.get("total_cost", 0)
	_details.text = "单价  %d 瓶盖\n合计  %d 瓶盖\n已持有  %d 件 · 还能放入 %d 件\n单次上限  %d 件 · 当前可购 %d 件\n购买后余额  %s" % [price, total,
		estimate.get("owned", 0), estimate.get("room", 0), estimate.get("product", {}).get("max_amount", 0),
		estimate.get("max_buy", 0), str(estimate.get("coins", 0) - total) if estimate.ok else "—"]
	_buy.text = "购买 · %d 瓶盖" % total
	_buy.disabled = not estimate.ok or _purchasing
	_minus.disabled = _amount <= 1
	_plus.disabled = _amount >= estimate.get("max_buy", 0)
	_availability.text = "" if estimate.ok else str(estimate.get("reason", "暂时无法购买"))
	for button in _product_buttons:
		button.set_pressed_no_signal(str(button.get_meta("product_id")) == _selected_id)

func _build_products(products: Array) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_product_buttons.clear()
	for product in products:
		var pid: String = product.id
		var button: Button = _button("%s    %d 瓶盖" % [product.label, product.price], _rows)
		button.name = "Product_" + pid
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_meta("product_id", pid)
		button.pressed.connect(_select.bind(pid))
		button.focus_entered.connect(_focus_product.bind(pid, button))
		_product_buttons.append(button)
	_focusables = _product_buttons.duplicate()
	_focusables.append_array([_minus, _plus, _buy, _close_button])

func _focus_product(product_id: String, button: Button) -> void:
	_select(product_id)
	_scroll.ensure_control_visible(button)

func _ensure_ui() -> void:
	if _overlay != null:
		return
	layer = 25
	_overlay = Control.new()
	_overlay.name = "ShopOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_overlay.hide()
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.12, 0.19, 0.17, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ShopPaper"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.09
	panel.anchor_bottom = 0.91
	_overlay.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	_title = _label("商店", header)
	_title.add_theme_font_size_override("font_size", 32)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button = _button("关闭", header)
	_close_button.name = "CloseShop"
	_close_button.pressed.connect(close)
	_wallet = _label("", column)
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 26)
	column.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	_scroll.add_child(_rows)
	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(detail_scroll)
	var detail: VBoxContainer = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 14)
	detail_scroll.add_child(detail)
	_name = _label("", detail)
	_name.add_theme_font_size_override("font_size", 28)
	_description = _label("", detail)
	_details = _label("", detail)
	var quantity_row: HBoxContainer = HBoxContainer.new()
	detail.add_child(quantity_row)
	_minus = _button("−", quantity_row)
	_minus.name = "DecreaseQuantity"
	_minus.pressed.connect(_change_amount.bind(-1))
	_quantity = _label("1", quantity_row)
	_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plus = _button("+", quantity_row)
	_plus.name = "IncreaseQuantity"
	_plus.pressed.connect(_change_amount.bind(1))
	_buy = _button("购买", detail)
	_buy.name = "BuyProduct"
	_buy.pressed.connect(_purchase)
	_availability = _label("", detail)
	_availability.name = "PurchaseAvailability"
	_feedback = _label("", column)
	_feedback.name = "PurchaseFeedback"
	_feedback.custom_minimum_size.y = 56
	Cozy.apply_tree(_overlay)
	_overlay.add_theme_font_override("font", Cozy.ui_font())

func _label(text: String, parent: Node) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(text: String, parent: Node) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(54, 50)
	parent.add_child(button)
	Cozy.apply(button)
	return button
