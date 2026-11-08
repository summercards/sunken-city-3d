extends CanvasLayer
## 独立ShopService的图标口袋适配层：与背包共用格子、分页、名签和操作气泡，
## 但价格/库存/结算仍全部由ShopService端口裁决。本文件不拥有商品与瓶盖。
signal closed(shop_id: String)
signal opened(shop_id: String)
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Items = preload("res://src/inventory/item_db.gd")
const Pocket = preload("res://src/ui/pocket_service.gd")
const CloseButton = preload("res://src/ui/close_button.gd")
var _service: RefCounted
var _inventory: RefCounted
var _shop_id := ""
var _selected_id := ""
var _amount := 1
var _sequence := 0
var _purchasing := false
var _refreshing := false
var _opened_frame := -1
var _activation_frame := -1
var _actions_frame := -1
var _purchase_frame := -1
var _held_keys: Dictionary = {}
var _last_input_event: InputEvent
var _last_input_frame := -1
var _overlay: Control
var _view
var _title: Label
var _wallet: Label
var _name: Label
var _description: Label
var _details: Label
var _quantity: Label
var _availability: Label
var _feedback: Label
var _minus: Button
var _plus: Button
var _buy: Button
var _close_button: Button
var _product_buttons: Array[Button] = []

func configure(service: RefCounted, inventory: RefCounted) -> void:
	close()
	_disconnect_inventory()
	_service=service
	_inventory=inventory
	if _inventory!=null:
		for signal_name in ["changed","capacity_changed","order_changed"]:
			if _inventory.has_signal(signal_name): _inventory.connect(signal_name,_on_inventory_changed)
	_ensure_ui()

func _exit_tree() -> void:
	_disconnect_inventory()

func _disconnect_inventory() -> void:
	if _inventory==null: return
	for signal_name in ["changed","capacity_changed","order_changed"]:
		if _inventory.has_signal(signal_name) and _inventory.is_connected(signal_name,_on_inventory_changed):
			_inventory.disconnect(signal_name,_on_inventory_changed)

func _on_inventory_changed(_first: Variant=null,_second: Variant=null) -> void:
	if is_open() and not _purchasing: _refresh()

func open_shop(shop_id: String) -> Dictionary:
	_ensure_ui()
	if _service==null or _inventory==null: return {"ok":false,"reason":"商店面板尚未接入服务和背包"}
	if _service.inventory!=_inventory: return {"ok":false,"reason":"商店与面板必须使用同一个背包"}
	var result: Dictionary=_service.open_shop(shop_id)
	if not result.ok:
		if is_open(): _feedback.text=result.reason
		return result
	if is_open(): close()
	_shop_id=shop_id
	_opened_frame=Engine.get_process_frames()
	_selected_id=""
	_amount=1
	_feedback.text=""
	# 首件商品即为当前选中项，但不开气泡：与背包一致，选中之后才确认进入操作。
	_view.selected_pool=1
	_view.selected_index=0
	_view.selected_data={}
	_overlay.show()
	_refresh()
	opened.emit(shop_id)
	return result

func close() -> void:
	if not is_open(): return
	var previous:=_shop_id
	_shop_id=""
	_view.cancel_actions()
	_view.name_tag.hide()
	_overlay.hide()
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null and _overlay.is_ancestor_of(focus): focus.release_focus()
	closed.emit(previous)

func is_open() -> bool:
	return _shop_id!="" and _overlay!=null and _overlay.visible

func _input(event: InputEvent) -> void:
	if handle_input(event): get_viewport().set_input_as_handled()

func handle_input(event: InputEvent) -> bool:
	if not event is InputEventKey: return false
	var key: int=event.keycode if event.keycode!=0 else event.physical_keycode
	if not is_open():
		if not _held_keys.has(key): return false
		if not event.pressed: _held_keys.erase(key)
		return true
	var frame:=Engine.get_process_frames()
	# HUD 委托与自身 _input 可能转发同一事件；先去重再执行交易。
	if event==_last_input_event and frame==_last_input_frame: return true
	_last_input_event=event;_last_input_frame=frame
	if not event.pressed:
		_held_keys.erase(key)
		return true
	var held:=_held_keys.has(key)
	_held_keys[key]=true
	# 开店那帧的确认键属于 NPC 会话，不能顺势花掉瓶盖；echo 同理。
	if frame==_opened_frame or event.echo or held: return true
	if get_tree().paused and key!=KEY_ESCAPE: return true
	if _view.action_closing: return true
	if key==KEY_ESCAPE:
		if not _view.back(): close()
		return true
	# 与背包一致：Tab 关闭面板，不用它遍历控件；焦点只在格子与气泡之间移动。
	if key==KEY_TAB:
		close()
		return true
	if key in [KEY_ENTER,KEY_KP_ENTER,KEY_E,KEY_SPACE]:
		if _activation_frame==frame: return true
		_activation_frame=frame
		var focused:=get_viewport().gui_get_focus_owner()
		if _view.actions.visible:
			if focused is Button and focused in _view.action_buttons() and not focused.disabled: focused.pressed.emit()
		elif focused==_close_button: close()
		elif _view.selected_pool==1 and _view.selected_index>=0: _show_actions()
		_sync_controls()
		return true
	var step:=0
	match key:
		KEY_LEFT,KEY_A: step=-1
		KEY_RIGHT,KEY_D: step=1
		KEY_UP,KEY_W: step=-8
		KEY_DOWN,KEY_S: step=8
	if step!=0:
		if _view.actions.visible:
			if absi(step)==1 and _view.is_buying(): _view.adjust_buy_amount(signi(step))
			else: _view.move_action_selection(signi(step))
		elif event.shift_pressed:
			var reason: String=_view.keyboard_sort(step)
			if reason!="": _feedback.text=reason
		else: _view.move_selection(step)
		_sync_controls()
	elif key in [KEY_PAGEUP,KEY_PAGEDOWN]:
		if not _view.actions.visible: _view.turn(_view.selected_pool,-1 if key==KEY_PAGEUP else 1)
		_sync_controls()
	elif key in [KEY_MINUS,KEY_KP_SUBTRACT,KEY_PLUS,KEY_EQUAL,KEY_KP_ADD] and _view.actions.visible:
		_view.adjust_buy_amount(-1 if key in [KEY_MINUS,KEY_KP_SUBTRACT] else 1)
		_sync_controls()
	return true

func _snapshot(_mode: String) -> Dictionary:
	var shop: Dictionary=_service.shop_snapshot(_shop_id)
	var state: Dictionary=_service.inventory_snapshot()
	var bag: Dictionary={}
	if _inventory.has_method("all"): bag=_inventory.all()
	else:
		for id in Items.all_ids():
			if _inventory.count(str(id))>0: bag[str(id)]=_inventory.count(str(id))
	var catalog: Array=[]
	for product in shop.get("products",[]):
		catalog.append({"id":product.item,"product_id":product.id,"count":_inventory.count(product.item),
			"price":product.price,"max_buy":product.max_buy,"description":product.get("description","")})
	return {"shop_name":shop.get("display_name","商店"),"caption":"今日商品 · 选一份带回家",
		"coins":state.get("coins",0),"bag":bag,"bag_capacity":state.get("capacity",24),
		"bag_order":_inventory.ordered_ids() if _inventory.has_method("ordered_ids") else [],"catalog":catalog}

func _quote(product_id: String,amount: int) -> Dictionary:
	return _service.quote(_shop_id,product_id,amount)

func _refresh() -> void:
	if not is_open() or _refreshing: return
	_refreshing=true
	var was_actions: bool=_view.actions.visible and not _view.action_closing
	var amount: int=_view.buy_amount
	_view.refresh("shop")
	if was_actions:
		_view.show_actions()
		_view.adjust_buy_amount(amount-1)
	_sync_controls()
	for tile in _view.slots[1]:
		var data: Dictionary=tile.get_meta("entry")
		tile.modulate.a=1.0 if int(data.get("max_buy",0))>0 else 0.5
	if not _view.actions.visible and _view.selected_pool==1 and _view.selected_index>=0:
		_view.slots[1][_view.selected_index].grab_focus()
	_refreshing=false
	_place()

func _sync_controls() -> void:
	_selected_id=str(_view.selected_data.get("product_id","")) if _view.selected_pool==1 else ""
	_amount=_view.buy_amount
	_product_buttons.clear()
	_product_buttons.append_array(_view.slots[1])
	_name=_view.name_tag
	_description=_view._buy_description
	_details=_view._buy_info
	_quantity=_view._buy_counter
	_availability=_view._buy_availability
	_minus=_view._buy_minus;_plus=_view._buy_plus;_buy=_view._buy_button

func _show_actions() -> void:
	if not is_open() or _view.actions.visible: return
	if _view.selected_pool!=1 or str(_view.selected_data.get("product_id",""))=="": return
	_actions_frame=Engine.get_process_frames()
	_view.show_actions()
	_sync_controls()

## 对外入口：打开当前所选商品的购买气泡。装配层与验收工具用这个，
## 不去碰 `_view.actions` 之类的内部字段。
func open_actions() -> bool:
	_show_actions()
	return _view.actions.visible

func _operate(product_id: String,action: String,amount: int) -> void:
	if action!="buy" or _purchasing or not is_open() or not _view.actions.visible or _view.action_closing: return
	var frame:=Engine.get_process_frames()
	# 气泡打开帧和上一次购买帧都不接受第二次提交，避免同帧双击/双转发。
	if frame==_opened_frame or frame==_actions_frame or frame==_purchase_frame: return
	_sync_controls()
	if product_id!=_selected_id or get_tree().paused: return
	_purchase_frame=frame
	_purchasing=true
	_sequence+=1
	var result: Dictionary=_service.buy(_shop_id,product_id,amount,"panel:%s:%s" % [get_instance_id(),_sequence])
	_purchasing=false
	if result.ok:
		_feedback.text="已购入 %s × %d · 花费 %d 瓶盖" % [result.label,result.amount,result.total_cost]
		_view.cancel_actions()
		_view.buy_amount=1
		_refresh()
		for tile in _view.slots[0]:
			if str(tile.get_meta("item_id"))==str(result.item): tile.highlight()
	else:
		_feedback.text=str(result.get("reason","交易未完成"))
		_refresh()

func _sort(from_id: String,to_id: String) -> void:
	if not is_open() or not _inventory.has_method("move_item"): return
	if to_id=="" and _inventory.has_method("move_to_end"): _inventory.move_to_end(from_id)
	else: _inventory.move_item(from_id,to_id)

func _ensure_ui() -> void:
	if _overlay!=null: return
	layer=25
	process_mode=Node.PROCESS_MODE_ALWAYS
	_overlay=Control.new();_overlay.name="ShopOverlay";_overlay.set_meta("cozy_skip",true)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay);_overlay.hide()
	var shade:=ColorRect.new();shade.color=Color(0.12,0.19,0.17,0.2)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			if not _view.back(): close()
			shade.accept_event())
	_view=Pocket.new();_view.name="ShopPockets";_view.font=Cozy.ui_font();_view.detailed_shop=true
	_view.lock_pool=1
	_view.query=_snapshot;_view.purchase_quote=_quote
	_overlay.add_child(_view)
	_view.operation_requested.connect(_operate)
	_view.sort_requested.connect(_sort)
	_view.selection_changed.connect(_sync_controls)
	_view.actions_changed.connect(_sync_controls)
	_title=_view.get_node("ServiceName")
	_wallet=_view.total
	_feedback=Label.new();_feedback.name="PurchaseFeedback";_feedback.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_feedback.add_theme_font_override("font",Cozy.ui_font());_feedback.add_theme_font_size_override("font_size",21)
	_feedback.add_theme_color_override("font_color",Cozy.INK)
	_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_feedback.position=Vector2(360,629);_feedback.size=Vector2(620,52)
	_view.add_child(_feedback)
	_close_button=CloseButton.new();_close_button.name="CloseShop";_close_button.pressed.connect(close)
	_overlay.add_child(_close_button)
	get_viewport().size_changed.connect(_place)

func _place() -> void:
	if _overlay==null: return
	var vp:=get_viewport().get_visible_rect().size
	var board:=Vector2(1000,690)
	var fit:=minf(1.0,minf((vp.x-64)/board.x,(vp.y-64)/board.y))
	_view.scale=Vector2.ONE*fit
	_view.position=((vp-board*fit)*0.5).floor()
	_title.reset_size()
	_title.position.x=board.x-_title.size.x-24
	_feedback.position=Vector2(360,board.y-61)
	# 关闭圆键贴在面板右下角内侧，和背包/服务面板一致，不飘到视口角落。
	_close_button.position=_view.position+Vector2(board.x-CloseButton.DIAMETER-18,board.y-CloseButton.DIAMETER-14)*fit
