extends Control
## Procedural selection glove shared by app tiles and menu choices.
var button: Button

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_meta("cozy_skip",true)

func _process(_delta: float) -> void:
	if not is_instance_valid(button): return
	visible=not button.disabled and (button.has_focus() or button.is_hovered())
	position=Vector2(8,(button.size.y-30)/2)
	queue_redraw()

func _draw() -> void:
	paint(self,Vector2.ZERO,0.6)

static func paint(canvas: CanvasItem, origin: Vector2, factor: float) -> void:
	var ink:=Color("#71674f")
	var cream:=Color("#fffdf0")
	canvas.draw_set_transform(origin,-0.18,Vector2.ONE*factor)
	for finger in [[Vector2(13,27),Vector2(8,3)],[Vector2(22,28),Vector2(22,15)],[Vector2(30,29),Vector2(31,20)],[Vector2(36,33),Vector2(39,27)]]:
		canvas.draw_line(finger[0],finger[1],ink,12,true)
		canvas.draw_circle(finger[1],6,ink,true,-1,true)
		canvas.draw_line(finger[0],finger[1],cream,7,true)
		canvas.draw_circle(finger[1],3.5,cream,true,-1,true)
	var palm:=PackedVector2Array([Vector2(10,22),Vector2(34,25),Vector2(43,33),Vector2(37,46),Vector2(17,48),Vector2(3,34),Vector2(0,29),Vector2(4,25),Vector2(12,32)])
	canvas.draw_colored_polygon(palm,cream)
	var edge:=palm.duplicate();edge.append(palm[0])
	canvas.draw_polyline(edge,ink,2.5,true)
	canvas.draw_line(Vector2(17,48),Vector2(37,46),cream,6,true)
	canvas.draw_set_transform(Vector2.ZERO)
