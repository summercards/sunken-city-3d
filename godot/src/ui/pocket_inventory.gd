extends Control
## Flat cream pockets; Inventory remains the sole owner of capacity and counts.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Items = preload("res://src/inventory/item_db.gd")
const Tile = preload("res://src/ui/ac_icon.gd")
signal manual_requested
signal item_command(id: String, action: String)
signal close_requested
var inventory: RefCounted
var actions_query: Callable
var font: Font
var slots: Array[Button] = []
var grid: GridContainer
var selected_name: Label
var purse: Label
var capacity_label: Label
var actions: PanelContainer
var action_body: VBoxContainer
var selected_index := -1
var selected_id := ""
var tween: Tween

func _ready() -> void:
	set_meta("cozy_skip",true)
	size = Vector2(960,490)
	pivot_offset = size/2
	mouse_filter = Control.MOUSE_FILTER_STOP
	draw.connect(_paint)
	grid = GridContainer.new();grid.name = "PocketSlots";grid.columns = 8
	grid.position = Vector2(62,88)
	grid.add_theme_constant_override("h_separation",22)
	grid.add_theme_constant_override("v_separation",8)
	add_child(grid)
	selected_name = _label("",24,Color.WHITE)
	selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tag := Cozy.surface(Cozy.TEAL,23)
	tag.content_margin_left = 23;tag.content_margin_right = 23
	tag.content_margin_top = 7;tag.content_margin_bottom = 7;tag.shadow_size = 0
	selected_name.add_theme_stylebox_override("normal",tag)
	add_child(selected_name);selected_name.hide()
	purse = _label("",27,Cozy.CREAM)
	var wallet := Cozy.surface(Color("#b8a54f"),29)
	wallet.content_margin_left=24;wallet.content_margin_right=24
	wallet.content_margin_top=12;wallet.content_margin_bottom=12;wallet.shadow_size=0
	purse.add_theme_stylebox_override("normal",wallet)
	purse.position = Vector2(14,409);add_child(purse)
	capacity_label = _label("",22,Cozy.INK)
	capacity_label.position = Vector2(310,427);add_child(capacity_label)
	capacity_label.hide()
	var manual := _button("生活手册")
	manual.position = Vector2(714,411);manual.size = Vector2(220,58)
	manual.pressed.connect(func(): manual_requested.emit());add_child(manual)
	actions = PanelContainer.new()
	var menu_style := Cozy.surface(Color("#fff0ab"),32)
	menu_style.content_margin_left=24;menu_style.content_margin_right=24
	menu_style.content_margin_top=18;menu_style.content_margin_bottom=18
	menu_style.shadow_size=12;menu_style.shadow_color=Color(0.18,0.21,0.12,0.12)
	actions.add_theme_stylebox_override("panel",menu_style)
	add_child(actions)
	action_body = VBoxContainer.new();action_body.add_theme_constant_override("separation",8);actions.add_child(action_body)
	actions.hide()
	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			actions.hide();accept_event())

func _label(text: String, pixels: int, color: Color) -> Label:
	var node := Label.new();node.text=text
	node.add_theme_font_override("font",font);node.add_theme_font_size_override("font_size",pixels)
	node.add_theme_color_override("font_color",color);node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return node

func _button(text: String) -> Button:
	var node := Button.new();node.text=text;node.set_meta("cozy_skip",true)
	node.add_theme_font_override("font",font);node.add_theme_font_size_override("font_size",24)
	for state in ["normal","hover","pressed","focus"]:
		var style := Cozy.surface(Color("#fff0ab") if state=="normal" else Color("#f0da83"),27)
		style.shadow_size=0;node.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: node.add_theme_color_override(state,Cozy.INK)
	node.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	return node

func refresh() -> void:
	if inventory == null: return
	var previous := selected_index
	for node in grid.get_children(): grid.remove_child(node);node.queue_free()
	slots.clear()
	for id in Items.all_ids():
		if Items.is_currency(id): continue
		var remaining: int = inventory.count(id)
		while remaining > 0:
			var count := mini(remaining,Items.stack_limit(id))
			_add_slot(str(id),count);remaining -= count
	while slots.size() < inventory.capacity(): _add_slot("",0)
	purse.text = "瓶盖    %s" % _money(inventory.count("coins"))
	capacity_label.text = "%d / %d 格" % [inventory.slots_used(),inventory.capacity()]
	selected_index = -1;selected_name.hide();actions.hide()
	# Capacity expansions stay scroll-free by adding rows and fitting the whole panel.
	size.y = 490+maxi(0,ceili(float(slots.size())/8)-3)*92
	for node in [purse]: node.position.y = size.y-81
	capacity_label.position.y = size.y-63
	get_child(4).position.y = size.y-79
	queue_redraw()
	if previous >= 0 and previous < slots.size(): select(previous)

func _add_slot(id: String, count: int) -> void:
	var tile := Tile.new();tile.pocket=true;tile.managed_selection=true
	tile.kind=id;tile.caption=Items.label(id);tile.font=font
	tile.amount=count;tile.shown_amount=count;tile.empty_slot=id==""
	tile.set_meta("item_id",id);tile.set_meta("slot_count",count)
	grid.add_child(tile);tile.custom_minimum_size=Vector2(84,84);tile.size=Vector2(84,84)
	var index := slots.size();slots.append(tile)
	tile.mouse_entered.connect(func(): if not actions.visible: select(index))
	tile.focus_entered.connect(func(): select(index))
	tile.pressed.connect(func(): select(index);show_actions())

func select(index: int) -> void:
	if index<0 or index>=slots.size(): return
	selected_index=index;selected_id=str(slots[index].get_meta("item_id",""))
	for i in slots.size(): slots[i].selected=i==index
	selected_name.visible=selected_id!=""
	if selected_id=="": actions.hide();return
	selected_name.text=Items.label(selected_id);selected_name.reset_size()
	var p := grid.position+Vector2((index%8)*106+42,(index/8)*92)
	selected_name.position=Vector2(clampf(p.x-selected_name.size.x/2,20,size.x-selected_name.size.x-20),p.y-52)

func show_actions() -> void:
	if selected_id=="" or not actions_query.is_valid(): return
	for node in action_body.get_children(): action_body.remove_child(node);node.queue_free()
	var options: Array = actions_query.call(selected_id)
	var id := selected_id
	for option in options:
		var button := _button(str(option.label))
		button.custom_minimum_size=Vector2(220,45)
		button.set_meta("item_action",str(option.id))
		button.pressed.connect(func(): item_command.emit(id,str(option.id)))
		action_body.add_child(button)
	actions.reset_size()
	actions.position=Vector2(688,235)
	actions.show()
	if Cozy.motion_enabled:
		if tween: tween.kill()
		actions.pivot_offset=Vector2(20,0);actions.scale=Vector2.ONE*0.86;actions.modulate.a=0
		tween=create_tween().set_parallel(true)
		tween.tween_property(actions,"scale",Vector2.ONE,0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(actions,"modulate:a",1.0,0.12)

func back() -> bool:
	if actions.visible: actions.hide();return true
	return false

func move_selection(step: int) -> void:
	actions.hide()
	select(posmod(maxi(0,selected_index)+step,slots.size()))

func _money(value: int) -> String:
	var raw := str(value);var result := ""
	for i in raw.length():
		if i>0 and (raw.length()-i)%3==0: result+=","
		result+=raw[i]
	return result

func _paint() -> void:
	var paper := StyleBoxFlat.new();paper.bg_color=Color("#fff9e6")
	paper.set_corner_radius_all(72);paper.corner_detail=24;paper.anti_aliasing=true
	paper.shadow_size=22;paper.shadow_offset=Vector2(0,9);paper.shadow_color=Color(0.06,0.19,0.18,0.12)
	draw_style_box(paper,Rect2(0,48,960,size.y-146))
