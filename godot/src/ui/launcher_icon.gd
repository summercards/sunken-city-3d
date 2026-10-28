extends Button
## Full, colorful silhouettes; no visible label text.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Art = preload("res://src/ui/illustrated_icons.gd")
var kind := "menu"
var selected := false:
	set(value): selected=value;queue_redraw()
var hovered := false
var motion: Tween

func _ready() -> void:
	set_meta("cozy_skip",true)
	custom_minimum_size=Vector2(72,72);size=custom_minimum_size;pivot_offset=size/2
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(func(): _hover(true));mouse_exited.connect(func(): _hover(false))
	focus_entered.connect(func(): _hover(true));focus_exited.connect(func(): _hover(false))

func _hover(on: bool) -> void:
	hovered=on;queue_redraw()
	if motion: motion.kill()
	if Cozy.motion_enabled:
		motion=create_tween();motion.tween_property(self,"scale",Vector2.ONE*(1.08 if on else 1.0),0.12)

func _box(rect: Rect2, color: Color, radius: int) -> void:
	draw_style_box(Cozy.surface(color,radius),rect)

func _draw() -> void:
	var colors: Dictionary={"menu":"#e6b951","bag":"#4eaa92","notes":"#d79450","shop":"#e58e78","storage":"#6d9db5","shipping":"#8bae69","map":"#65b4c2","system":"#a59ac5","dive":"#64a3c1","build":"#c79d66"}
	var color:=Color(colors.get(kind,"#4eaa92"))
	if kind=="follow": color=Color("#4eaa92") if selected else Color("#d5b061")
	if hovered: color=color.lightened(0.12)
	draw_circle(Vector2(36,39),34,Color(0.06,0.20,0.22,0.16),true,-1,true)
	draw_circle(Vector2(36,36),34,color,true,-1,true)
	draw_arc(Vector2(36,36),32,0,TAU,64,Color(1,0.98,0.88,0.8),2,true)
	if kind=="menu":
		if selected:
			draw_line(Vector2(25,25),Vector2(47,47),Cozy.CREAM,6,true);draw_line(Vector2(47,25),Vector2(25,47),Cozy.CREAM,6,true)
		else:
			for x in 2:
				for y in 2: _box(Rect2(21+x*17,21+y*17,13,13),Cozy.CREAM,4)
	elif kind=="follow":
		# A person inside four framing corners: restoring the character view.
		for direction in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			var corner: Vector2=Vector2(36,36)+direction*19
			draw_line(corner,corner-Vector2(direction.x*9,0),Cozy.CREAM,4,true)
			draw_line(corner,corner-Vector2(0,direction.y*9),Cozy.CREAM,4,true)
		draw_circle(Vector2(36,28),6,Cozy.CREAM,true,-1,true)
		_box(Rect2(26,38,20,13),Cozy.CREAM,8)
	elif kind=="craft":
		_box(Rect2(18,16,36,42),Cozy.CREAM,5)
		_box(Rect2(18,16,7,42),Color("#98734c"),3)
		draw_line(Vector2(32,47),Vector2(47,27),Color("#b48c50"),6,true)
		draw_line(Vector2(37,24),Vector2(51,34),Color("#78a598"),9,true)
	elif kind=="notes":
		_box(Rect2(21,17,33,41),Color("#855e3e"),5)
		_box(Rect2(18,14,33,41),Cozy.CREAM,5)
		_box(Rect2(17,14,7,41),Color("#9c7044"),3)
		_box(Rect2(41,14,6,20),Color("#73aa86"),1)
		for y in [30,37,44]: draw_line(Vector2(29,y),Vector2(38,y),Color("#c6b58e"),2,true)
	elif kind=="system":
		for i in 8:
			var direction:=Vector2.from_angle(i*TAU/8)
			draw_line(Vector2(36,36)+direction*17,Vector2(36,36)+direction*23,Cozy.CREAM,9,true)
		draw_circle(Vector2(36,36),20,Cozy.CREAM,true,-1,true);draw_circle(Vector2(36,36),8,color,true,-1,true)
	elif kind=="storage":
		_box(Rect2(17,23,38,30),Color("#c1894e"),5)
		_box(Rect2(16,20,40,10),Color("#ffe5a4"),3)
		_box(Rect2(32,28,8,13),Cozy.CREAM,2)
	elif kind=="map":
		draw_colored_polygon(PackedVector2Array([Vector2(16,20),Vector2(30,16),Vector2(43,21),Vector2(57,17),Vector2(55,52),Vector2(42,56),Vector2(29,51),Vector2(15,55)]),Cozy.CREAM)
		draw_line(Vector2(30,17),Vector2(29,50),Color("#dcd5b6"),2,true);draw_line(Vector2(43,22),Vector2(42,55),Color("#dcd5b6"),2,true)
		draw_circle(Vector2(26,31),6,Color("#8abb84"),true,-1,true);draw_circle(Vector2(45,42),7,Color("#8abb84"),true,-1,true)
		draw_line(Vector2(28,33),Vector2(44,42),Color("#df9970"),3,true)
	else:
		var icon:=Art.texture(kind,true)
		if icon: draw_texture_rect(icon,Rect2(15,15,42,42),false,Cozy.CREAM)
