extends Control
## Recipe and management view, with no gameplay state of its own.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Catalog = preload("res://src/building/building_catalog.gd")
signal selected(recipe: String)
signal closed
var font: Font=preload("res://src/ui/fonts/LXGW975YuanSC-700W.ttf")
var inventory_query: Callable
var recipe_buttons:={}
var counts: Label

func _ready() -> void:
	set_meta("cozy_skip",true); size=Vector2(940,700); mouse_filter=Control.MOUSE_FILTER_STOP
	_label("海上建造手册",Vector2(56,28),32)
	_label("一片海，慢慢长成自己的家",Vector2(494,36),22)
	_label("没有扩建圈数限制。\n沿木面拼接，也能乘船靠近\n空海面建起新的浮台。",Vector2(58,88),21)
	_label("整片新木面都能自由布置。\n培养土可跨接缝、旋转和搬移，\n留好行走与操作的位置。",Vector2(494,88),21)
	for i in 2:
		var kind: String=["deck","planter"][i]
		var x:=float(56+i*438)
		_label("01  拼接木板" if i==0 else "02  培养土种植区",Vector2(x,276),27)
		_label(_cost_text(kind),Vector2(x,320),20)
		var button:=_button("选择木板" if i==0 else "布置标准培养土",Vector2(x,358),Vector2(380,46))
		button.pressed.connect(func(): selected.emit(kind)); recipe_buttons[kind]=button
	_label("建筑、泊位和停船位置会保留通道。\n红色虚影会告诉你具体原因。",Vector2(58,416),18)
	_label("小培养土 · "+_cost_text("planter_small"),Vector2(494,415),18)
	var small:=_button("布置小培养土",Vector2(494,446),Vector2(380,42))
	small.pressed.connect(func(): selected.emit("planter_small")); recipe_buttons.planter_small=small
	var move:=_button("搬移培养土  M",Vector2(56,510),Vector2(380,45))
	move.pressed.connect(func(): selected.emit("move")); recipe_buttons.move=move
	var remove:=_button("拆回材料  Delete",Vector2(494,510),Vector2(380,45))
	remove.pressed.connect(func(): selected.emit("remove")); recipe_buttons.remove=remove
	_label("搬移不收费，作物与生长进度保留。\nR 旋转 · 按住 Shift 精细摆放",Vector2(58,566),18)
	_label("空培养土可拆回，木板须先清空承载物。\n不困住角色，不切断通路；材料全额返还。",Vector2(494,566),18)
	counts=_label("",Vector2(56,640),20)
	var close:=_button("×",Vector2(876,15),Vector2(44,44)); close.pressed.connect(func(): closed.emit())
	refresh()

func _cost_text(kind: String) -> String:
	var parts: Array[String]=[]
	for id in Catalog.RECIPES[kind].cost:
		parts.append("%s ×%d"%[preload("res://src/inventory/item_db.gd").label(id),Catalog.RECIPES[kind].cost[id]])
	return "  +  ".join(parts)+"  ·  %d秒"%Catalog.RECIPES[kind].seconds

func _label(value: String,pos: Vector2,pixels: int) -> Label:
	var label:=Label.new(); label.text=value; label.position=pos; label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",font); label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",Color("#68543c")); add_child(label); return label

func _button(value: String,pos: Vector2,extent: Vector2) -> Button:
	var button:=Button.new(); button.text=value; button.position=pos; button.size=extent; button.set_meta("cozy_skip",true)
	button.add_theme_font_override("font",font); button.add_theme_font_size_override("font_size",22)
	for state in ["normal","hover","pressed","focus"]:
		button.add_theme_stylebox_override(state,Cozy.surface(Color("#80ae8f") if state=="normal" else Color("#d7b76e"),12))
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND; add_child(button); return button

func refresh() -> void:
	if counts!=null and inventory_query.is_valid():
		var items: Dictionary=inventory_query.call()
		counts.text="口袋里：木板 %d    土壤 %d"%[items.get("wood",0),items.get("soil",0)]

func _draw() -> void:
	draw_style_box(Cozy.surface(Color(0.12,0.20,0.18,0.18),20),Rect2(8,10,940,700))
	draw_style_box(Cozy.surface(Color("#8a6542"),18),Rect2(0,0,940,700))
	draw_style_box(Cozy.surface(Color("#f9edcf"),12),Rect2(12,9,452,679))
	draw_style_box(Cozy.surface(Color("#fff5dc"),12),Rect2(470,9,458,679))
	for x in [459,463,467,471]: draw_line(Vector2(x,21),Vector2(x,677),Color(0.45,0.31,0.16,0.16),2,true)
	for i in 5:
		var p:=Vector2(116+i*30,215-i*4)
		draw_colored_polygon(PackedVector2Array([p,p+Vector2(29,-4),p+Vector2(98,36),p+Vector2(69,40)]),Color("#c19a69").lightened(float(i%2)*0.1))
	var soil:=PackedVector2Array([Vector2(540,216),Vector2(687,194),Vector2(810,238),Vector2(655,264)])
	draw_colored_polygon(soil,Color("#806244")); draw_polyline(PackedVector2Array([soil[0],soil[1],soil[2],soil[3],soil[0]]),Color("#c49b69"),10,true)
	for p in [Vector2(631,220),Vector2(712,235)]:
		draw_line(p,p-Vector2(0,23),Color("#628762"),4,true)
		draw_circle(p-Vector2(8,22),9,Color("#8baa6e"),true,-1,true)
		draw_circle(p+Vector2(8,-28),9,Color("#a5bf79"),true,-1,true)
