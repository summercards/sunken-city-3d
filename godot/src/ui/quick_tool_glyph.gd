extends Control
## 快捷工具统一的程序化白色剪影，不依赖位图资源。

var kind := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(46, 46)
	size = Vector2(46, 46)
	queue_redraw()

func _draw() -> void:
	var ink := Color.WHITE
	match kind:
		"quick_build": _draw_build(ink)
		"quick_demolish": _draw_demolish(ink)
		"quick_fish": _draw_fish(ink)
		"quick_dive": _draw_dive(ink)

func _draw_build(ink: Color) -> void:
	var wall := PackedVector2Array([Vector2(7, 22),Vector2(7, 39),Vector2(34, 39),Vector2(34, 22)])
	draw_colored_polygon(wall, ink)
	draw_colored_polygon(PackedVector2Array([Vector2(4,22),Vector2(20,8),Vector2(37,22)]), ink)
	draw_rect(Rect2(18,29,7,10), Color("#438f83"), true)
	draw_line(Vector2(31,12),Vector2(40,21),ink,4.5,true)
	draw_line(Vector2(29,15),Vector2(35,9),ink,4.5,true)
	draw_line(Vector2(36,22),Vector2(42,16),ink,4.5,true)

func _draw_demolish(ink: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(6,27),Vector2(16,17),Vector2(28,29),Vector2(18,39)]), ink)
	draw_colored_polygon(PackedVector2Array([Vector2(20,32),Vector2(30,22),Vector2(40,32),Vector2(30,42)]), ink)
	draw_line(Vector2(8,10),Vector2(35,37),ink,5.5,true)
	draw_line(Vector2(7,11),Vector2(17,5),ink,5.5,true)
	draw_line(Vector2(7,11),Vector2(4,18),ink,5.5,true)

func _draw_fish(ink: Color) -> void:
	draw_line(Vector2(8,10),Vector2(16,16),ink,3.0,true)
	draw_line(Vector2(16,16),Vector2(22,27),ink,2.2,true)
	draw_arc(Vector2(22,28),8,0.0,PI*0.92,18,ink,2.2,true)
	draw_line(Vector2(29,33),Vector2(35,38),ink,2.2,true)
	draw_colored_polygon(PackedVector2Array([Vector2(8,27),Vector2(17,20),Vector2(32,23),Vector2(37,30),Vector2(29,36),Vector2(17,35)]), ink)
	draw_colored_polygon(PackedVector2Array([Vector2(8,27),Vector2(2,20),Vector2(4,30)]), ink)
	draw_circle(Vector2(29,26),1.5,Color("#438f83"))

func _draw_dive(ink: Color) -> void:
	draw_arc(Vector2(21,25),12,0.0,TAU,28,ink,4.0,true)
	draw_line(Vector2(9,25),Vector2(33,25),ink,4.0,true)
	draw_line(Vector2(12,17),Vector2(30,17),ink,4.0,true)
	draw_line(Vector2(30,17),Vector2(35,10),ink,3.5,true)
	draw_line(Vector2(35,10),Vector2(40,10),ink,3.5,true)
	draw_line(Vector2(37,11),Vector2(37,22),ink,3.0,true)
	draw_arc(Vector2(37,25),5,-PI*0.55,PI*0.55,12,ink,2.6,true)
