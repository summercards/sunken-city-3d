extends Control
## Two pockets linked by injected commands. Never owns inventory or trading rules.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Items = preload("res://src/inventory/item_db.gd")
const Tile = preload("res://src/ui/ac_icon.gd")
signal operation_requested(id: String, action: String, amount: int)
signal close_requested
## 拖拽整理：把 `from_id` 放到 `to_id` 的位置（空串=挪到末尾）。
## 本界面不算账，只把意图转给宿主（hud → Inventory）。
signal sort_requested(from_id: String, to_id: String)
var query: Callable
var font: Font
var mode := "shipping"
var snapshot: Dictionary = {}
var grids: Array[GridContainer] = []
var slots: Array = [[],[]]
var pages := [0,0]
var page_labels: Array[Label] = []
var page_arrows: Array = [[],[]]
var heading: Label
var caption: Label
var total: Label
var name_tag: Label
var actions: PanelContainer
var action_body: VBoxContainer
var selected_pool := 0
var selected_index := -1
var selected_data: Dictionary = {}
var action_tween: Tween
var action_closing := false
var _action_buttons: Array[Button] = []
var _buy_minus: Button
var _buy_plus: Button
var _buy_button: Button
var _buy_counter: Label
var _buy_limit := 0
var _page_counts := [1,1]
var _restore_id := ""
## 购买气泡里当前选中的数量。每次重开气泡重置为 1。
var buy_amount := 1

func _ready() -> void:
	set_meta("cozy_skip",true)
	size=Vector2(1000,690);pivot_offset=size/2
	mouse_filter=Control.MOUSE_FILTER_STOP
	draw.connect(_paint)
	heading=_tag("背包",Cozy.TEAL,Color.WHITE,26);heading.position=Vector2(28,8);add_child(heading)
	var identity:=_tag("",Cozy.GOLD,Cozy.INK,26);identity.name="ServiceName";identity.position=Vector2(784,8);add_child(identity)
	caption=_tag("",Cozy.TEAL,Color.WHITE,24);caption.position=Vector2(28,411);add_child(caption)
	for pool in 2:
		var grid:=GridContainer.new();grid.columns=8;grid.position=Vector2(78,93 if pool==0 else 481)
		grid.add_theme_constant_override("h_separation",22);grid.add_theme_constant_override("v_separation",8)
		add_child(grid);grids.append(grid)
		var previous:=_button("‹");previous.position=Vector2(7,208 if pool==0 else 499);previous.size=Vector2(48,48)
		previous.pressed.connect(func(): turn(pool,-1));add_child(previous)
		var next:=_button("›");next.position=Vector2(947,208 if pool==0 else 499);next.size=Vector2(48,48)
		next.pressed.connect(func(): turn(pool,1));add_child(next)
		page_arrows[pool]=[previous,next]
		var page_label:=_label("",18,Cozy.DIM);page_label.position=Vector2(895,359 if pool==0 else 581)
		add_child(page_label);page_labels.append(page_label)
	total=_tag("",Color("#b8a54f"),Cozy.CREAM,26);total.position=Vector2(18,631);add_child(total)
	# 原先这里有一枚「完成」按钮收面板。按 SEA-UI-R47 移除：关闭入口只保留
	# 屏幕右下角那一枚动物森友会式圆键，面板内不再各挂一个「完成/×」。
	# `close_requested` 信号与 Esc / 点空白回退路径都没变，只是少一个可见按钮。
	name_tag=_tag("",Cozy.TEAL,Color.WHITE,23);add_child(name_tag);name_tag.hide()
	actions=PanelContainer.new();actions.add_theme_stylebox_override("panel",Cozy.surface(Color("#fff0ab"),28));add_child(actions)
	action_body=VBoxContainer.new();action_body.add_theme_constant_override("separation",6);actions.add_child(action_body);actions.hide()
	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: back();accept_event())

func _label(text: String, pixels: int, color: Color) -> Label:
	var label:=Label.new();label.text=text;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",color)
	return label

func _tag(text: String, color: Color, ink: Color, pixels: int) -> Label:
	var label:=_label(text,pixels,ink);var style:=Cozy.surface(color,25)
	style.content_margin_left=22;style.content_margin_right=22;style.content_margin_top=6;style.content_margin_bottom=6
	label.add_theme_stylebox_override("normal",style);return label

func _button(text: String) -> Button:
	var button:=Button.new();button.text=text;button.set_meta("cozy_skip",true)
	button.add_theme_font_override("font",font);button.add_theme_font_size_override("font_size",24)
	for state in ["normal","hover","pressed","focus"]:
		var style:=Cozy.surface(Color("#fff0ab") if state=="normal" else Cozy.GOLD,25)
		if state=="focus": style.bg_color=Color.TRANSPARENT;style.border_color=Cozy.INK;style.set_border_width_all(3)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(state,Cozy.INK)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	return button

func refresh(service: String) -> void:
	if action_tween: action_tween.kill()
	action_closing=false
	var previous_id:=str(selected_data.get("id",_restore_id))
	var previous_pool:=selected_pool
	var previous_index:=selected_index
	if service!=mode:
		pages=[0,0];previous_index=0;previous_id="";previous_pool=1 if service=="shop" else 0
	mode=service
	_action_buttons.clear();_buy_minus=null;_buy_plus=null;_buy_button=null;_buy_limit=0
	if not query.is_valid(): return
	snapshot=query.call(mode)
	get_node("ServiceName").text=str(snapshot.get("shop_name",{"shipping":"出货箱","storage":"保管仓库","shop":"家园补给"}[mode]))
	caption.text=str(snapshot.get("caption",{"shipping":"待出货 · 明早 07:00 收货","storage":"仓库 · 存放的东西不会出售","shop":"种子与土壤 · 选一份带回家"}[mode]))
	total.text="瓶盖 %d · 背包 %d/%d 格" % [int(snapshot.coins),_used(snapshot.bag),int(snapshot.bag_capacity)]
	if mode=="shipping": total.text+=" · 待收 %d" % int(snapshot.expected)
	elif mode=="storage": total.text+=" · 仓库 %d/%d 格" % [_used(snapshot.other),int(snapshot.other_capacity)]
	var rows: Array=[_stacks(snapshot.bag,int(snapshot.bag_capacity),snapshot.get("bag_order",[])),
		snapshot.catalog if mode=="shop" else _stacks(snapshot.other,int(snapshot.other_capacity),snapshot.get("other_order",[]))]
	if previous_id!="":
		var per_page:=24 if previous_pool==0 else 8
		for i in rows[previous_pool].size():
			if str(rows[previous_pool][i].id)==previous_id: pages[previous_pool]=i/per_page;break
	for pool in 2:
		for node in grids[pool].get_children(): grids[pool].remove_child(node);node.queue_free()
		slots[pool]=[]
		var per_page:=24 if pool==0 else 8
		var count:=maxi(1,ceili(float(rows[pool].size())/per_page))
		_page_counts[pool]=count
		pages[pool]=clampi(pages[pool],0,count-1)
		page_labels[pool].text="%d / %d" % [pages[pool]+1,count] if count>1 else ""
		page_labels[pool].show()
		for arrow in page_arrows[pool]: arrow.visible=count>1
		page_arrows[pool][0].disabled=pages[pool]==0
		page_arrows[pool][1].disabled=pages[pool]>=count-1
		for i in mini(per_page,maxi(0,rows[pool].size()-pages[pool]*per_page)):
			var index: int=pages[pool]*per_page+i
			var data: Dictionary=rows[pool][index] if index<rows[pool].size() else {"id":"","count":0}
			_add_tile(pool,i,data)
	name_tag.hide();actions.hide();selected_data={};selected_index=-1
	var target:=clampi(previous_index,0,slots[previous_pool].size()-1)
	for i in slots[previous_pool].size():
		if str(slots[previous_pool][i].get_meta("item_id"))==previous_id and previous_id!="":
			target=i;break
	if not slots[previous_pool].is_empty():
		select(previous_pool,target)
		if is_visible_in_tree(): slots[previous_pool][target].grab_focus()
	queue_redraw()

## 把 {物品id: 数量} 摊成格子行。
##
## `order` 是玩家拖拽整理出的次序（来自 Inventory.ordered_ids()）。
## 不传就退回物品表顺序 —— 旧存档、快照没带 order 时都能照常显示。
## 同一物品数量超过叠放上限会拆成多堆，**跟着自己的 id 挨在一起**，
## 不会因为排序把同种物品的几堆打散到八个格子以外。
func _used(counts: Dictionary) -> int:
	var used:=0
	for id in counts:
		if not Items.is_currency(str(id)): used+=ceili(float(counts[id])/Items.stack_limit(str(id)))
	return used

func _stacks(counts: Dictionary, capacity: int, order: Array = []) -> Array:
	var result: Array=[]
	var ids: Array=[]
	var seen := {}
	for raw in order:
		var key := str(raw)
		if seen.has(key) or int(counts.get(key,0))<=0 or Items.is_currency(key): continue
		seen[key]=true;ids.append(key)
	for id in Items.all_ids():
		if Items.is_currency(id): continue
		var key := str(id)
		if seen.has(key) or int(counts.get(key,0))<=0: continue
		seen[key]=true;ids.append(key)
	for id in ids:
		var remaining:=int(counts.get(id,0))
		while remaining>0:
			var count:=mini(remaining,Items.stack_limit(id));result.append({"id":str(id),"count":count});remaining-=count
	while result.size()<capacity: result.append({"id":"","count":0})
	return result

func _add_tile(pool: int, index: int, data: Dictionary) -> void:
	var tile:=Tile.new();tile.pocket=true;tile.managed_selection=true;tile.font=font
	tile.kind=str(data.id);tile.empty_slot=tile.kind=="";tile.amount=int(data.count);tile.shown_amount=tile.amount
	tile.set_meta("item_id",tile.kind);tile.set_meta("pool",pool);tile.set_meta("slot_count",tile.amount)
	grids[pool].add_child(tile);tile.custom_minimum_size=Vector2(84,84);tile.size=Vector2(84,84)
	tile.focus_mode=Control.FOCUS_ALL
	var focus:=Cozy.surface(Color.TRANSPARENT,18);focus.border_color=Cozy.INK;focus.set_border_width_all(3)
	tile.add_theme_stylebox_override("focus",focus)
	slots[pool].append(tile)
	if pool==0 and mode=="shipping" and not str(data.id) in snapshot.accepts and not tile.empty_slot: tile.modulate.a=0.4
	tile.mouse_entered.connect(func(): if not actions.visible: select(pool,index))
	tile.focus_entered.connect(func(): select(pool,index))
	tile.pressed.connect(func(): select(pool,index);show_actions())
	# 拖拽整理只开给背包（pool 0）：
	# 下方在 shop 模式是商品目录、在出货/仓库模式是另一份独立库存，
	# 两者都不是"我的背包格子"，拖过去没有可解释的后果。
	if pool==0:
		tile.drag_sortable=true;tile.drag_pool=pool
		tile.drag_sorted.connect(func(from_id:String,to_id:String): sort_requested.emit(from_id,to_id))
	tile.set_meta("entry",data.duplicate(true))
	if data.has("price"):
		var price:=_label("%d 瓶盖" % int(data.price),20,Cozy.INK)
		price.position=Vector2(-8,72);price.size=Vector2(100,28);price.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;tile.add_child(price)

func select(pool: int, index: int) -> void:
	if index<0 or index>=slots[pool].size(): return
	selected_pool=pool;selected_index=index
	selected_data=slots[pool][index].get_meta("entry").duplicate(true)
	for p in 2:
		for i in slots[p].size(): slots[p][i].selected=p==pool and i==index
	name_tag.show()
	page_labels[1].visible=not (pool==1 and name_tag.visible)
	name_tag.text="空格" if str(selected_data.id)=="" else "%s · ×%d" % [Items.label(str(selected_data.id)),int(selected_data.count)]
	name_tag.reset_size()
	_restore_id=str(selected_data.id)
	var point:=grids[pool].position+Vector2((index%8)*106+42,(index/8)*92)
	name_tag.position=Vector2(clampf(point.x-name_tag.size.x/2,12,size.x-name_tag.size.x-12),point.y-44 if pool==0 else point.y+86)


## 购买数量选择器：`[−] N [+]` 加一个「购买 N」。
##
## 为什么不是一次买一个：种子和土壤是**消耗品**，玩家要一次种好几格、
## 或者一次囤一叠土。只能一个一个点，等于逼人重复点十几次。
##
## 上下限来自快照里的 `max_buy`（瓶盖够几份、背包还放得下几个，取小的）：
## 点 + 到顶就灰掉，而不是让人一路点到"瓶盖不足"再被弹回来。
## 数量变化只改三个控件，不重建整个气泡 —— 否则每点一次 + 都要闪一下。
func _buy_picker() -> void:
	var limit:=maxi(0,int(selected_data.get("max_buy",0)))
	_buy_limit=limit
	if limit<=0:
		var short_coins:=int(snapshot.get("coins",0))<int(selected_data.get("price",0))
		action_body.add_child(_label("瓶盖不足" if short_coins else "背包已满",22,Cozy.INK))
		return
	buy_amount=clampi(buy_amount,1,limit)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	row.alignment=BoxContainer.ALIGNMENT_CENTER
	action_body.add_child(row)
	var minus:=_step_button("−");_buy_minus=minus;row.add_child(minus)
	var counter:=_label(str(buy_amount),26,Cozy.INK);_buy_counter=counter
	counter.custom_minimum_size=Vector2(54,44);counter.size=Vector2(54,44)
	counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	counter.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	row.add_child(counter)
	var plus:=_step_button("+");_buy_plus=plus;row.add_child(plus)
	var buy:=_button("购买 %d" % buy_amount);_buy_button=buy
	_action_buttons=[minus,plus,buy]
	buy.custom_minimum_size=Vector2(190,45)
	buy.set_meta("service_action","buy");buy.set_meta("amount",buy_amount)
	action_body.add_child(buy)
	minus.disabled=buy_amount<=1
	plus.disabled=buy_amount>=limit
	action_body.add_child(_label("上限 %d · 余额 %d 瓶盖" % [limit,int(snapshot.coins)],18,Cozy.INK))
	minus.pressed.connect(func(): adjust_buy_amount(-1))
	plus.pressed.connect(func(): adjust_buy_amount(1))
	buy.pressed.connect(func(): operation_requested.emit(str(selected_data.get("crop",selected_data.id)),"buy",buy_amount))
	buy.grab_focus.call_deferred()
	buy.set_meta("action_hotkey",1)


## 数量选择的 ± 小圆钮：比「购买 N」窄，视觉上从属它。
func _step_button(text: String) -> Button:
	var button:=_button(text)
	button.custom_minimum_size=Vector2(52,44)
	button.add_theme_font_size_override("font_size",28)
	return button


func show_actions() -> void:
	if selected_data.is_empty() or str(selected_data.id)=="": return
	# 每次重新开气泡都从 1 起：上一件商品选到 7，换一件还是 7 会误买。
	buy_amount=1
	_action_buttons.clear();_buy_minus=null;_buy_plus=null;_buy_button=null;_buy_limit=0
	action_closing=false;actions.mouse_filter=Control.MOUSE_FILTER_STOP
	for node in action_body.get_children(): action_body.remove_child(node);node.queue_free()
	var id:=str(selected_data.id)
	action_body.add_child(_label(Items.label(id)+" · 库存 ×%d" % int(snapshot.bag.get(id,0)),20,Cozy.INK))
	var action: String="deposit" if selected_pool==0 else ("buy" if mode=="shop" else "withdraw")
	var verb: String="放入" if selected_pool==0 else ("购买" if mode=="shop" else "取回")
	var blocked: bool=selected_pool==0 and ((mode=="shipping" and not id in snapshot.accepts) or mode=="shop")
	if blocked:
		var info:=_label("出货箱只收鱼和农产品" if mode=="shipping" else "在下方选择种子购买",22,Cozy.INK);action_body.add_child(info)
	elif action=="buy":
		_buy_picker()
	else:
		for amount in ([1,int(selected_data.count)] if int(selected_data.count)>1 else [1]):
			var button:=_button("%s %d%s" % [verb,amount,"（整叠）" if amount>1 else ""]);button.custom_minimum_size=Vector2(190,45)
			button.set_meta("service_action",action);button.set_meta("amount",amount)
			button.pressed.connect(func(): operation_requested.emit(str(selected_data.get("crop",id)),action,amount))
			action_body.add_child(button);_action_buttons.append(button)
		if not _action_buttons.is_empty(): _action_buttons[0].grab_focus.call_deferred()
	actions.reset_size();actions.position=Vector2(750,428 if selected_pool==1 else 226);actions.show()
	if Cozy.motion_enabled:
		if action_tween: action_tween.kill()
		actions.scale=Vector2.ONE*0.86;actions.modulate.a=0
		action_tween=create_tween().set_parallel(true)
		action_tween.tween_property(actions,"scale",Vector2.ONE,0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		action_tween.tween_property(actions,"modulate:a",1.0,0.12)
	else: actions.scale=Vector2.ONE;actions.modulate.a=1

func turn(pool: int, step: int) -> void:
	var target:=clampi(pages[pool]+step,0,int(_page_counts[pool])-1)
	if target==pages[pool]: return
	pages[pool]=target;selected_pool=pool;selected_index=0;selected_data={};_restore_id="";refresh(mode)

func move_selection(step: int) -> void:
	if actions.visible: return
	var pool:=selected_pool
	var index:=maxi(0,selected_index)+step
	if index<0:
		pool=1-pool;index=maxi(0,slots[pool].size()-8)+posmod(maxi(0,selected_index),8)
	elif index>=slots[pool].size():
		pool=1-pool;index=posmod(index,8)
	if slots[pool].is_empty(): return
	index=clampi(index,0,slots[pool].size()-1)
	select(pool,index);slots[pool][index].grab_focus()

func keyboard_sort(step: int) -> String:
	if actions.visible: return "请先返回物品网格"
	if selected_pool!=0: return "只能整理上方背包 · 商品、仓库与出货托盘不参与换位"
	var from_id:=str(selected_data.get("id",""))
	if from_id=="": return "当前没有可整理的物品"
	var target:=selected_index+step
	while target>=0 and target<slots[0].size():
		var id:=str(slots[0][target].get_meta("item_id"))
		if id!=from_id:
			sort_requested.emit(from_id,id);return ""
		target+=step
	return "已到本页边界，排列未改变"

func is_buying() -> bool:
	return is_instance_valid(_buy_button) and actions.visible and not action_closing

func buy_button() -> Button:
	return _buy_button

func action_buttons() -> Array[Button]:
	return _action_buttons

func move_action_selection(step: int) -> void:
	if _action_buttons.is_empty(): return
	var focused:=get_viewport().gui_get_focus_owner()
	var index:=_action_buttons.find(focused)
	if index<0: index=0
	for attempt in _action_buttons.size():
		index=posmod(index+step,_action_buttons.size())
		if not _action_buttons[index].disabled:
			_action_buttons[index].grab_focus();return

func adjust_buy_amount(delta: int) -> void:
	if _buy_button==null or _buy_limit<=0: return
	buy_amount=clampi(buy_amount+delta,1,_buy_limit)
	_buy_counter.text=str(buy_amount)
	_buy_button.text="购买 %d" % buy_amount
	_buy_button.set_meta("amount",buy_amount)
	_buy_minus.disabled=buy_amount<=1
	_buy_plus.disabled=buy_amount>=_buy_limit
	var focused:=get_viewport().gui_get_focus_owner()
	if focused is Button and focused.disabled: _buy_button.grab_focus()

func back() -> bool:
	if not actions.visible: return false
	if action_closing: return true
	if action_tween: action_tween.kill()
	_action_buttons.clear()
	if selected_index>=0 and selected_index<slots[selected_pool].size(): slots[selected_pool][selected_index].grab_focus()
	if not Cozy.motion_enabled: actions.hide();return true
	action_closing=true;actions.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in action_body.get_children():
		if child is Button: child.disabled=true
	action_tween=create_tween().set_parallel(true)
	action_tween.tween_property(actions,"scale",Vector2.ONE*0.86,0.12)
	action_tween.tween_property(actions,"modulate:a",0.0,0.12)
	action_tween.chain().tween_callback(func(): actions.hide();action_closing=false)
	return true

func _paint() -> void:
	for rect in [Rect2(0,57,1000,337),Rect2(0,460,1000,156)]:
		var paper:=StyleBoxFlat.new();paper.bg_color=Color("#fff9e6");paper.set_corner_radius_all(52)
		paper.corner_detail=24;paper.anti_aliasing=true;paper.shadow_color=Color(0.03,0.15,0.15,0.12);paper.shadow_size=18
		draw_style_box(paper,rect)
