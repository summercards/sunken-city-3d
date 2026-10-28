extends Control
## View only: a two-page construction field guide.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Catalog = preload("res://src/building/building_catalog.gd")
signal selected(recipe: String)
signal closed
var font: Font=preload("res://src/ui/fonts/LXGW975YuanSC-700W.ttf")
var inventory_query: Callable
var recipe_buttons := {}
var counts: Label
func _ready() -> void:
	set_meta("cozy_skip",true);size=Vector2(900,570);mouse_filter=Control.MOUSE_FILTER_STOP
	_label("海上建造手册",Vector2(66,38),34)
	_label("初阶 · 从脚下的平台开始",Vector2(490,45),23)
	_label("拾起漂来的木头，\n一点点接出自己的海上花园。",Vector2(68,94),22)
	_label("在新木板上选择位置，\n每一格都能播种、浇水与收获。",Vector2(490,94),22)
	for i in 2:
		var kind: String=["deck","planter"][i]
		var x:=float(64+i*424)
		_label("01  拼接木板" if i==0 else "02  培养土种植区",Vector2(x,288),27)
		var parts: Array[String]=[]
		for id in Catalog.RECIPES[kind].cost:
			parts.append("%s ×%d"%[preload("res://src/inventory/item_db.gd").label(id),Catalog.RECIPES[kind].cost[id]])
		_label("  +  ".join(parts)+"    ·    %d秒"%Catalog.RECIPES[kind].seconds,Vector2(x,336),21)
		var button:=_button("选择木板" if i==0 else "布置种植区",Vector2(x,386),Vector2(338,54))
		button.pressed.connect(func(): selected.emit(kind));recipe_buttons[kind]=button
	counts=_label("",Vector2(64,474),22)
	_label("土壤可在商店购买  ·  站在种植平台陆地上施工",Vector2(64,515),18)
	var close:=_button("×",Vector2(838,18),Vector2(44,44));close.pressed.connect(func(): closed.emit())
	refresh()
func _label(value: String, pos: Vector2, pixels: int) -> Label:
	var label:=Label.new();label.text=value;label.position=pos;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",pixels);label.add_theme_color_override("font_color",Color("#68543c"));add_child(label);return label
func _button(value: String,pos: Vector2,extent: Vector2) -> Button:
	var button:=Button.new();button.text=value;button.position=pos;button.size=extent;button.set_meta("cozy_skip",true)
	button.add_theme_font_override("font",font);button.add_theme_font_size_override("font_size",24)
	for state in ["normal","hover","pressed","focus"]:
		button.add_theme_stylebox_override(state,Cozy.surface(Color("#80ae8f") if state=="normal" else Color("#d7b76e"),14))
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;add_child(button);return button
func refresh() -> void:
	if counts!=null and inventory_query.is_valid():
		var items: Dictionary=inventory_query.call()
		counts.text="口袋里：木板 %d    土壤 %d"%[items.get("wood",0),items.get("soil",0)]
func _draw() -> void:
	draw_style_box(Cozy.surface(Color(0.12,0.20,0.18,0.18),20),Rect2(8,10,900,570))
	draw_style_box(Cozy.surface(Color("#8a6542"),18),Rect2(0,0,900,570))
	draw_style_box(Cozy.surface(Color("#f9edcf"),12),Rect2(12,9,432,549))
	draw_style_box(Cozy.surface(Color("#fff5dc"),12),Rect2(450,9,438,549))
	for x in [439,443,447,451]: draw_line(Vector2(x,21),Vector2(x,548),Color(0.45,0.31,0.16,0.16),2,true)
	# Small isometric recipe sketches are drawn from the same timber/soil colors.
	for i in 5:
		var p:=Vector2(118+i*30,206-i*4)
		draw_colored_polygon(PackedVector2Array([p,p+Vector2(29,-4),p+Vector2(98,36),p+Vector2(69,40)]),Color("#c19a69").lightened(float(i%2)*0.1))
	var soil:=PackedVector2Array([Vector2(540,211),Vector2(687,189),Vector2(792,238),Vector2(638,264)])
	draw_colored_polygon(soil,Color("#806244"));draw_polyline(PackedVector2Array([soil[0],soil[1],soil[2],soil[3],soil[0]]),Color("#c49b69"),10,true)
	for p in [Vector2(621,215),Vector2(699,234)]:
		draw_line(p,p-Vector2(0,23),Color("#628762"),4,true)
		draw_circle(p-Vector2(8,22),9,Color("#8baa6e"),true,-1,true)
		draw_circle(p+Vector2(8,-28),9,Color("#a5bf79"),true,-1,true)
