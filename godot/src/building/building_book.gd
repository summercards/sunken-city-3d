extends Control
## Concise recipe cards; content and material costs are read from the build catalog.
const Catalog=preload("res://src/building/building_catalog.gd")
const Card=preload("res://src/building/recipe_card.gd")
signal selected(recipe: String)
signal closed
var font: Font=preload("res://src/ui/fonts/LXGW975YuanSC-700W.ttf")
var inventory_query: Callable
var recipe_buttons: Dictionary={}
var cards: Dictionary={}
var counts: Label
var page_label: Label
var page:=0
var category:="all"
var category_buttons: Dictionary={}
const PER_PAGE:=10
func _ready() -> void:
	set_meta("cozy_skip",true);size=Vector2(940,700);mouse_filter=Control.MOUSE_FILTER_STOP
	_label("建造手册",Vector2(38,20),31)
	var close:=_button("×",Vector2(864,20),Vector2(40,40));close.pressed.connect(func(): closed.emit())
	var labels: Array[String]=["全部","拼接平台","框架结构","生活摆件","种植"]
	var keys: Array[String]=["all","platform","structure","decoration","planting"]
	for i in labels.size():
		var key: String=keys[i]
		var node:=_button(labels[i],Vector2(38+i*178,78),Vector2(168,40))
		node.pressed.connect(func(): category=key;page=0;refresh());category_buttons[key]=node
	for kind: String in Catalog.RECIPES:
		var entry: Dictionary=Catalog.RECIPES[kind]
		var node:=Card.new();node.configure(kind,str(entry.name),_cost_text(kind),font);node.hide();add_child(node)
		node.pressed.connect(func(): selected.emit(kind));cards[kind]=node;recipe_buttons[kind]=node
	var previous:=_button("‹",Vector2(38,637),Vector2(40,36));previous.pressed.connect(func(): page=maxi(0,page-1);refresh())
	var next:=_button("›",Vector2(236,637),Vector2(40,36));next.pressed.connect(func(): page+=1;refresh())
	page_label=_label("",Vector2(82,642),19);page_label.size=Vector2(150,24);page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var move:=_button("搬移  M",Vector2(644,637),Vector2(116,36));move.pressed.connect(func(): selected.emit("move"));recipe_buttons.move=move
	var remove:=_button("拆回  Delete",Vector2(774,637),Vector2(130,36));remove.pressed.connect(func(): selected.emit("remove"));recipe_buttons.remove=remove
	counts=_label("",Vector2(323,643),16)
	refresh()
func _cost_text(kind: String) -> String:
	var parts: Array[String]=[]
	for id in Catalog.RECIPES[kind].cost:
		parts.append("%s ×%d"%[preload("res://src/inventory/item_db.gd").label(id),Catalog.RECIPES[kind].cost[id]])
	return "  ".join(parts)
## Reading order of the combined page: platform, frame, furniture, planting.
func _rank(kind: String) -> int:
	if Catalog.is_platform(kind): return 0
	if Catalog.category(kind)==Catalog.CATEGORY_STRUCTURE: return 1
	if Catalog.is_furnishing(kind) and Catalog.role(kind)=="planter": return 3
	return 2
func _label(value: String,pos: Vector2,pixels: int,parent: Node=null) -> Label:
	var node:=Label.new();node.text=value;node.position=pos;node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override("font",font);node.add_theme_font_size_override("font_size",pixels)
	node.add_theme_color_override("font_color",Color("#765d3c"));(self if parent==null else parent).add_child(node);return node
func _button(value: String,pos: Vector2,extent: Vector2,parent: Node=null) -> Button:
	var node:=Button.new();node.text=value;node.position=pos;node.size=extent;node.set_meta("cozy_skip",true)
	node.add_theme_font_override("font",font);node.add_theme_font_size_override("font_size",20)
	for state in ["normal","hover","pressed","focus"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("#edeacb") if state=="normal" else Color("#f4e3a1")
		style.set_corner_radius_all(18);style.set_border_width_all(1);style.border_color=Color(.97,.96,.85,.8)
		node.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: node.add_theme_color_override(state,Color("#816a47"))
	node.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;(self if parent==null else parent).add_child(node);return node
func refresh() -> void:
	if counts==null: return
	var filtered: Array[String]=[]
	for kind: String in Catalog.RECIPES:
		var entry: Dictionary=Catalog.RECIPES[kind];cards[kind].hide()
		if not Catalog.enabled(kind): continue
		# Two content classes: platforms (legacy boards and both rafts) join
		# edge to edge; frames and loose furniture stand on them.
		var group: String="platform" if Catalog.is_platform(kind) else str(entry.get("group","planting"))
		if category=="all" or group==category: filtered.append(kind)
	# "All" reads bottom-up: the platforms come first, then the frames and the
	# furniture that stand on them. Catalog order alone mixed a raft between
	# two beds and made the two classes look like three.
	var ordered: Array=[]
	for i in filtered.size(): ordered.append({"kind":filtered[i],"rank":_rank(filtered[i]),"order":i})
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return a.rank<b.rank if a.rank!=b.rank else a.order<b.order)
	filtered.assign(ordered.map(func(item: Dictionary) -> String: return str(item.kind)))
	var pages:=maxi(1,ceili(filtered.size()/float(PER_PAGE)));page=clampi(page,0,pages-1)
	for j in mini(PER_PAGE,filtered.size()-page*PER_PAGE):
		var card: Button=cards[filtered[page*PER_PAGE+j]];card.place(Vector2(38+(j%5)*176,145+floori(j/5.0)*233));card.show()
		card.image.request_image()
	page_label.text="%d / %d"%[page+1,pages]
	counts.text=""
	for key in category_buttons:
		var node: Button=category_buttons[key];node.modulate=Color.WHITE if key==category else Color(.83,.83,.75)
func _draw() -> void:
	var shadow:=StyleBoxFlat.new();shadow.bg_color=Color(.22,.25,.16,.2);shadow.set_corner_radius_all(27)
	draw_style_box(shadow,Rect2(7,9,940,700))
	var paper:=StyleBoxFlat.new();paper.bg_color=Color("#e9e5c8");paper.set_corner_radius_all(24);paper.set_border_width_all(2);paper.border_color=Color("#faf6df")
	draw_style_box(paper,Rect2(0,0,940,700))
	# Gentle paper grain, generated as vector flecks so it scales with the menu.
	for i in 180:
		var point:=Vector2(18+fmod(i*73.7,904),14+fmod(i*127.3,672))
		draw_circle(point,.7,Color(.69,.67,.42,.10),true,-1,true)
