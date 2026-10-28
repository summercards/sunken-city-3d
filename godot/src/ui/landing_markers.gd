extends CanvasLayer
## Presentation only; pick() keeps the existing stable landing IDs and commands.
const Art = preload("res://src/ui/illustrated_icons.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
const ICON_MIN := 30.0
const ICON_MAX := 50.0
const NEAR_RADIUS := 64.0
const VISIBLE_RANGE := 190.0
var zones: Node
var items: Array = []
var camera: Camera3D
var pointer_query: Callable
var current_zone := "zone1"
var _tex: Texture2D
var _canvas: Control

func build(cam: Camera3D) -> void:
	camera=cam;layer=8
	_tex=Art.texture("anchor",true)
	_canvas=Control.new();_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw);add_child(_canvas)
	for z in zones.list:
		if zones.zone_enabled_query.is_valid() and not zones.zone_enabled_query.call(str(z.id)): continue
		for landing in z.get("landings",[]):
			var point: Array=landing.dockEdge
			items.append({"zone":z.id,"landing":landing.id,"name":str(landing.get("name",z.name)),
				"world":Vector3(point[0],float(point[1])+0.55,point[2]),
				"screen":Vector2.ZERO,"size":ICON_MIN,"near":0.0,"visible":false})

func _process(delta: float) -> void:
	if camera==null: return
	var extent:=get_viewport().get_visible_rect().size
	_canvas.size=extent
	var mouse: Vector2=pointer_query.call() if pointer_query.is_valid() else get_viewport().get_mouse_position()
	for item in items:
		item.visible=false
		var world: Vector3=item.world
		if camera.is_position_behind(world) or camera.global_position.distance_to(world)>VISIBLE_RANGE: continue
		var screen:=camera.unproject_position(world)
		if not Rect2(Vector2(-60,-60),extent+Vector2(120,120)).has_point(screen): continue
		item.screen=screen
		var proximity:=1.0-smoothstep(20.0,NEAR_RADIUS,screen.distance_to(mouse))
		item.near=lerpf(float(item.near),proximity,1.0-exp(-delta*14.0)) if Cozy.motion_enabled else proximity
		item.size=lerpf(ICON_MIN,ICON_MAX,float(item.near))
		item.visible=true
	_canvas.queue_redraw()

func _on_draw() -> void:
	for item in items:
		if not item.visible: continue
		var center: Vector2=item.screen
		var radius: float=item.size*0.5
		var ink:=Color("#438f83").lerp(Color("#e6c36e"),float(item.near))
		_canvas.draw_circle(center+Vector2(0,2),radius,Color(0.03,0.16,0.18,0.18),true,-1,true)
		_canvas.draw_circle(center,radius,ink,true,-1,true)
		_canvas.draw_arc(center,radius-1,0,TAU,48,Color("#fff9e7"),1.5,true)
		if _tex:
			var side: float=item.size*0.62
			_canvas.draw_texture_rect(_tex,Rect2(center-Vector2.ONE*side*0.5,Vector2.ONE*side),false,Color.WHITE)

func pick(screen_pos: Vector2, radius: float=26.0) -> Dictionary:
	if not visible: return {}
	var best: Dictionary={}
	var best_distance:=radius
	for item in items:
		if not item.visible: continue
		var distance: float=item.screen.distance_to(screen_pos)
		if distance<best_distance: best_distance=distance;best=item
	return best

func set_highlight(zone_id: String) -> void:
	current_zone=zone_id
