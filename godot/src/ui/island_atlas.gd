extends Control
var zones: Node
var game_state: Node
## Read-only drawn map from registered footprints. It never invents unlocks or routes.
const Cozy = preload("res://src/ui/cozy_ui.gd")
var font: Font
var bounds := Rect2(-100,-110,210,210)
var footprints := {}

func _ready() -> void:
	custom_minimum_size=Vector2(560,235)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	for zone in zones.list: footprints[zone.id]=zones.footprint(zone.id)
	resized.connect(queue_redraw)

func project(point: Vector2) -> Vector2:
	return Vector2(28,22)+(point-bounds.position)/bounds.size*(size-Vector2(56,44))

func _draw() -> void:
	var base := Cozy.surface(Color("#b8d9cf"),26);base.shadow_size=0
	draw_style_box(base,Rect2(Vector2.ZERO,size))
	for y in range(20,int(size.y),26):
		for x in range(20,int(size.x),40):
			draw_arc(Vector2(x,y),7,0.2,PI-0.2,10,Color(1,1,0.65,0.20),1,true)
	for id in footprints:
		var rect: Rect2=footprints[id]
		if not rect.has_area(): continue
		var p := project(rect.get_center())
		var unlocked: bool=zones.is_unlocked(id)
		var extent := Vector2(maxf(28,rect.size.x*1.5),maxf(15,rect.size.y*0.65))
		var land := Cozy.surface(Cozy.CREAM if unlocked else Color("#a3bdb2"),14);land.shadow_size=0
		draw_style_box(land,Rect2(p-extent/2,extent))
		draw_circle(p,5,Cozy.TEAL if unlocked else Cozy.DIM)
		if font: draw_string(font,p+Vector2(10,-8),zones.label(id),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Cozy.INK)
		if id == game_state.current_zone:
			draw_arc(p,11,0,TAU,24,Color("#dc9970"),3,true)
