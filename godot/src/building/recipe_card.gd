extends Button
## One concise recipe: component image, name and materials. The whole card is clickable.
const Thumb=preload("res://src/building/recipe_thumbnail.gd")
var kind:=""
var image: TextureRect
var _hover:=false
var _focused:=false
var _lift:=0.0
var _base:=Vector2.ZERO
var _photo_frame: Control
var _cost: Label
var _name: Label
var font: Font

func configure(recipe: String,title: String,cost: String,face: Font) -> void:
	kind=recipe;font=face;custom_minimum_size=Vector2(166,219);size=custom_minimum_size
	flat=true;focus_mode=Control.FOCUS_ALL;mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	_name=_label(title,Vector2(7,166),20);_name.size=Vector2(152,26)
	_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_cost=_label(cost,Vector2(7,192),15);_cost.size=Vector2(152,20);_cost.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	image=Thumb.new();image.position=Vector2(7,12);image.size=Vector2(152,145);image.configure(recipe);add_child(image)
	mouse_entered.connect(func(): _hover=true;queue_redraw())
	mouse_exited.connect(func(): _hover=false;queue_redraw())
	focus_entered.connect(func(): _focused=true;queue_redraw())
	focus_exited.connect(func(): _focused=false;queue_redraw())
	visibility_changed.connect(func(): if is_visible_in_tree(): image.request_image())
	set_process(true)
func place(at: Vector2) -> void: _base=at;position=at
func _label(value: String,at: Vector2,pixels: int) -> Label:
	var node:=Label.new();node.text=value;node.position=at;node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override("font",font);node.add_theme_font_size_override("font_size",pixels)
	node.add_theme_color_override("font_color",Color("#765d3c"));add_child(node);return node
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var amount:=1.0-exp(-18.0*delta);_lift=lerpf(_lift,5.0 if _hover or _focused else 0.0,amount)
	position=_base-Vector2(0,_lift);queue_redraw()
func _draw() -> void:
	var shadow:=StyleBoxFlat.new();shadow.bg_color=Color(.27,.24,.12,.16);shadow.corner_radius_top_left=8;shadow.corner_radius_top_right=8;shadow.corner_radius_bottom_left=8;shadow.corner_radius_bottom_right=8
	draw_style_box(shadow,Rect2(2,4,size.x,size.y))
	var paper:=StyleBoxFlat.new();paper.bg_color=Color("#eee8b6") if not (_hover or _focused) else Color("#faf0b5")
	paper.set_border_width_all(3);paper.border_color=Color("#fffced");paper.set_corner_radius_all(5)
	draw_style_box(paper,Rect2(Vector2.ZERO,size))
	# Sparse botanical stationery motif, painted behind the component photograph.
	for row in 4:
		for column in 3:
			var at:=Vector2(27+column*54+(row%2)*12,29+row*39)
			draw_set_transform(at,-.45)
			_leaf(Vector2.ZERO,Vector2(9,5),Color(.99,.99,.78,.28))
			draw_line(Vector2(-8,0),Vector2(8,0),Color(.79,.82,.52,.20),1,true)
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(12,162),Vector2(154,162),Color(.76,.71,.48,.24),1,true)
	if _hover or _focused:
		var outline:=StyleBoxFlat.new();outline.bg_color=Color.TRANSPARENT;outline.set_border_width_all(2);outline.border_color=Color("#b5bd83");outline.set_corner_radius_all(5)
		draw_style_box(outline,Rect2(-3,-3,size.x+6,size.y+6))
func _leaf(at: Vector2,radius: Vector2,color: Color) -> void:
	var polygon:=PackedVector2Array()
	for i in 16: polygon.append(at+Vector2(cos(TAU*i/16.0)*radius.x,sin(TAU*i/16.0)*radius.y))
	draw_colored_polygon(polygon,color)
