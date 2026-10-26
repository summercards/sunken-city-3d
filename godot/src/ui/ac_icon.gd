extends Button
## Procedural icon tile. All state here is presentation-only.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const INK := Cozy.INK
const BLUE := Color("#4E9FC4")
var kind := "fish"
var pocket := false
var empty_slot := false
var caption := ""
var tint := Cozy.SKY
var locked := false
var selected := false
var amount := 0
var shown_amount := 0.0
var amount_offset := 0.0
var flash := 0.0
var phase := 0.0
var font: Font
var hover_tween: Tween
var count_tween: Tween
var flash_tween: Tween

func _ready() -> void:
	set_meta("cozy_skip", true)
	set_meta("island_icon", true)
	custom_minimum_size = Vector2(64,64) if pocket else Vector2(96,96)
	size = custom_minimum_size
	pivot_offset = size / 2
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus","disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(func(): _hover(1.06))
	if pocket:
		mouse_entered.connect(func(): selected=true)
		mouse_exited.connect(func(): selected=false)
		focus_entered.connect(func(): selected=true)
		focus_exited.connect(func(): selected=false)
	mouse_exited.connect(func(): _hover(1.0))

func _hover(value: float) -> void:
	if not Cozy.motion_enabled: scale=Vector2.ONE;return
	if hover_tween: hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.tween_property(self,"scale",Vector2.ONE * value,0.12)

func set_amount(value: int, animate := true) -> void:
	if value == amount: return
	amount = maxi(0,value)
	if count_tween: count_tween.kill()
	if not animate or not Cozy.motion_enabled:
		shown_amount = amount
		amount_offset = 0.0
		return
	amount_offset = 0.0
	count_tween = create_tween().set_parallel(true)
	count_tween.tween_property(self,"shown_amount",float(value),0.4)
	count_tween.tween_property(self,"amount_offset",-8.0,0.4)
	count_tween.chain().tween_callback(func(): amount_offset = 0.0)

func highlight() -> void:
	if flash_tween: flash_tween.kill()
	flash = 1.0
	flash_tween = create_tween()
	flash_tween.tween_property(self,"flash",0.0,0.55)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if Cozy.motion_enabled: phase += delta
	queue_redraw()

func _box(rect: Rect2, color: Color, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.corner_detail=16;style.anti_aliasing=true;style.anti_aliasing_size=1.5
	draw_style_box(style,rect)

func _draw() -> void:
	if pocket:
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE*(size.x/96.0))
		if empty_slot:
			_circle(Vector2(48,44),10,Color("#e9e2ce"))
			return
		if selected: _circle(Vector2(48,44),36,Cozy.TEAL)
	else:
		_box(Rect2(0,0,96,96),tint,22)
	if (selected or flash > 0) and not pocket:
		var border := StyleBoxFlat.new()
		border.bg_color = Color.TRANSPARENT
		border.border_color = Color(BLUE, maxf(flash,0.68+0.32*sin(phase*TAU/1.2)))
		border.set_border_width_all(3)
		border.set_corner_radius_all(22)
		border.corner_detail=16;border.anti_aliasing=true
		draw_style_box(border,Rect2(-3,-3,102,102))
	_draw_symbol(kind, Vector2(48,39))
	if font and not pocket:
		var width := font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		draw_string(font,Vector2((96-width)/2,82),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,18,INK)
	if locked:
		_box(Rect2(75,8,13,12),Color(INK,0.62),3)
		draw_arc(Vector2(81.5,8),4,PI,TAU,12,INK,2,true)
	elif amount > 0 and font:
		var badge_size := 22 if pocket else 18
		var txt := "×%d" % maxi(1,roundi(shown_amount))
		var w := font.get_string_size(txt,HORIZONTAL_ALIGNMENT_LEFT,-1,badge_size).x+12
		_box(Rect2(98-w,66+amount_offset if pocket else 87+amount_offset,w,23),Color("#fff7e7"),11)
		draw_string(font,Vector2(104-w,82+amount_offset if pocket else 103+amount_offset),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,badge_size,INK)

	if selected:
		preload("res://src/ui/island_pointer.gd").paint(self,Vector2(66,59)*(size.x/96.0),0.55*(size.x/96.0))

func _draw_symbol(id: String, p: Vector2) -> void:
	var cream := Cozy.CREAM
	match id:
		"wood":
			_box(Rect2(p+Vector2(-25,-13),Vector2(48,27)),Color("#b18b61"),10)
			_circle(p+Vector2(21,0),14,Color("#dcc298"));draw_arc(p+Vector2(21,0),8,0,TAU,20,INK,2,true)
			for y in [-7,3,9]: draw_line(p+Vector2(-20,y),p+Vector2(9,y),Color("#8e6c49"),2,true)
		"parts":
			for i in 8:
				var a:=TAU*i/8
				draw_line(p+Vector2(cos(a),sin(a))*15,p+Vector2(cos(a),sin(a))*26,Color("#849ba1"),10,true)
			_circle(p,21,Color("#849ba1"));_circle(p,9,cream)
		"rope":
			for i in 3: draw_arc(p+Vector2(i*4-4,0),20-i*4,0,TAU,30,Color("#b69460"),4,true)
			draw_line(p+Vector2(17,10),p+Vector2(30,22),Color("#b69460"),5,true)
		"glass":
			_polygon(PackedVector2Array([p+Vector2(-14,-25),p+Vector2(24,-12),p+Vector2(13,25),p+Vector2(-23,8)]),BLUE)
			draw_line(p+Vector2(-9,-14),p+Vector2(8,12),cream,4,true)
		"clock":
			_circle(p,25,cream);draw_arc(p,25,0,TAU,32,INK,3,true)
			draw_line(p,p+Vector2(0,-17),INK,3,true);draw_line(p,p+Vector2(13,5),INK,3,true)
		"fish":
			_polygon(PackedVector2Array([p+Vector2(-20,0),p+Vector2(-34,-13),p+Vector2(-34,13)]),BLUE)
			var fish_shape:=PackedVector2Array()
			for point in 64: fish_shape.append(p+Vector2(cos(TAU*point/64.0)*24.3,sin(TAU*point/64.0)*14.4))
			_polygon(fish_shape,BLUE)
			_circle(p+Vector2(14,-4),3,INK)
			draw_arc(p+Vector2(3,0),9,-1.2,1.2,12,cream,2,true)
		"seed", "lettuce_seed", "tomato_seed", "pumpkin_seed":
			_box(Rect2(p+Vector2(-19,-25),Vector2(38,51)),cream,5)
			_box(Rect2(p+Vector2(-16,-21),Vector2(32,9)),Cozy.CORAL,2)
			_circle(p+Vector2(0,6),13,Cozy.MINT)
			draw_line(p+Vector2(0,18),p+Vector2(0,-2),Color("#45876b"),3,true)
			_circle(p+Vector2(-6,1),6,Color("#629c67"));_circle(p+Vector2(6,4),6,Color("#45876b"))
		"vegetable", "plant":
			draw_line(p+Vector2(0,20),p+Vector2(0,-14),Color("#45876b"),4,true)
			for i in 3:
				var y := -12+i*11
				_polygon(PackedVector2Array([p+Vector2(0,y+8),p+Vector2(-22,y-9),p+Vector2(-20,y+5)]),Color("#45876b"))
				_polygon(PackedVector2Array([p+Vector2(0,y+8),p+Vector2(22,y-9),p+Vector2(20,y+5)]),Color("#629c67"))
		"tomato", "pumpkin":
			var c := Color("#d77661") if id == "tomato" else Color("#d79748")
			_circle(p+Vector2(-8,3),17,c); _circle(p+Vector2(8,3),17,c)
			draw_arc(p+Vector2(3,2),15,-1.2,1.2,14,Color(c,0.5).darkened(0.2),2,true)
			draw_line(p+Vector2(0,-12),p+Vector2(3,-25),Color("#537f53"),5,true)
			draw_line(p+Vector2(-11,-14),p+Vector2(11,-14),Color("#537f53"),4,true)
		"shell":
			var pts := PackedVector2Array([p+Vector2(0,21)])
			for i in 17: pts.append(p+Vector2(cos(PI+i*PI/16),sin(PI+i*PI/16))*25)
			_polygon(pts,Color("#c7937f"))
			for i in 5:
				draw_line(p+Vector2(0,18),p+Vector2(cos(PI+0.3+i*0.63),sin(PI+0.3+i*0.63))*21,cream,2,true)
		"pearl":
			_circle(p,23,Color("#b6a3c8"));_circle(p+Vector2(-2,-3),19,cream);_circle(p+Vector2(-8,-10),5,Color.WHITE)
		"water":
			_box(Rect2(p+Vector2(-18,-9),Vector2(32,29)),Color("#568a9b"),7)
			draw_arc(p+Vector2(-18,0),12,PI/2,PI*1.5,15,Color("#568a9b"),5,true)
			draw_line(p+Vector2(11,7),p+Vector2(30,-8),Color("#568a9b"),7,true)
			draw_line(p+Vector2(26,-12),p+Vector2(35,-3),cream,4,true)
			_box(Rect2(p+Vector2(-11,-15),Vector2(17,5)),cream,2)
		"hook":
			draw_line(p+Vector2(10,-26),p+Vector2(10,8),INK,4,true)
			draw_arc(p+Vector2(-2,8),12,0,PI,20,INK,4,true)
			draw_line(p+Vector2(-14,8),p+Vector2(-14,1),INK,4,true)
			_circle(p+Vector2(10,-23),6,cream);_circle(p+Vector2(10,-23),3,INK)
		"lamp", "dive":
			_box(Rect2(p+Vector2(-23,-12),Vector2(46,30)),INK,12)
			_box(Rect2(p+Vector2(-18,-8),Vector2(36,20)),Cozy.SKY,8)
			draw_line(p+Vector2(0,-7),p+Vector2(0,13),INK,3,true)
			draw_line(p+Vector2(29,-22),p+Vector2(29,14),INK,5,true)
		"build", "home":
			_box(Rect2(p+Vector2(-19,-4),Vector2(38,29)),Color("#ae845b"),4)
			_polygon(PackedVector2Array([p+Vector2(-27,-4),p+Vector2(0,-28),p+Vector2(27,-4)]),cream)
			_box(Rect2(p+Vector2(-5,7),Vector2(10,18)),cream,2)
		"map":
			_polygon(PackedVector2Array([p+Vector2(-26,-16),p+Vector2(-8,-22),p+Vector2(10,-16),p+Vector2(26,-22),p+Vector2(26,18),p+Vector2(10,24),p+Vector2(-8,18),p+Vector2(-26,24)]),cream)
			_circle(p+Vector2(1,-6),10,Color("#d77661"));_polygon(PackedVector2Array([p+Vector2(-7,-2),p+Vector2(9,-2),p+Vector2(1,12)]),Color("#d77661"));_circle(p+Vector2(1,-7),4,cream)
		"camera":
			_box(Rect2(p+Vector2(-27,-15),Vector2(54,38)),INK,7);_box(Rect2(p+Vector2(-10,-23),Vector2(20,10)),INK,3)
			_circle(p,15,cream);_circle(p,10,BLUE)
		"storage", "bag":
			_box(Rect2(p+Vector2(-23,-13),Vector2(46,37)),Color("#b18b60"),8)
			draw_arc(p+Vector2(0,-12),13,PI,TAU,16,INK,4,true)
			draw_line(p+Vector2(-21,1),p+Vector2(21,1),cream,3,true);_box(Rect2(p+Vector2(-4,-3),Vector2(8,11)),cream,2)
		_:
			_box(Rect2(p+Vector2(-20,-24),Vector2(40,48)),cream,7)
			for i in 3: draw_line(p+Vector2(-12,-10+i*10),p+Vector2(11,-10+i*10),Color("#aa9380"),3,true)
			if id == "save": draw_line(p+Vector2(15,-20),p+Vector2(15,7),BLUE,5,true)

func _circle(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center,radius,color,true,-1.0,true)

func _polygon(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points,color)
	var edge:=points.duplicate();edge.append(points[0])
	draw_polyline(edge,color,1.0,true)
