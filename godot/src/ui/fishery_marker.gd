extends CanvasLayer
## A screen-space projection of the fishery interaction, outside the water pass.
signal harvest_requested
const Bubble = preload("res://src/ui/action_bubble.gd")
var camera: Camera3D
var anchor: Node3D
var state_query: Callable
var allowed_query: Callable
var button: Button
var _canvas: Control

func _ready() -> void:
	name = "FisheryMarker"
	layer = 9
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	button = Bubble.new()
	button.name = "HarvestFish"
	button.kind = "fish"
	button.set_meta("action_id","harvest")
	_canvas.add_child(button)
	button.pressed.connect(func(): harvest_requested.emit())
	hide()

func configure(cam: Camera3D, target: Node3D, query: Callable, allowed: Callable) -> void:
	camera = cam
	anchor = target
	state_query = query
	allowed_query = allowed
	refresh()

func refresh() -> void:
	if not state_query.is_valid(): return
	var state: Dictionary = state_query.call()
	var amount := int(state.get("pending",0))
	button.available = amount > 0
	button.caption = "收获 ×%d" % amount if amount > 0 else "生长中"
	button.tooltip_text = "收获鱼类 ×%d" % amount if amount > 0 else "鱼群正在生长，每4小时可收获3条鱼"
	button.queue_redraw()
	_process(0.0)

func _process(_delta: float) -> void:
	visible = is_instance_valid(anchor) and anchor.is_visible_in_tree() and camera != null
	if visible and allowed_query.is_valid(): visible = bool(allowed_query.call())
	if not visible: return
	var point: Vector3 = anchor.focus_position()+Vector3.UP*0.75
	if camera.is_position_behind(point) or camera.global_position.distance_to(point)>190.0:
		hide()
		return
	var screen := camera.unproject_position(point)
	var extent := get_viewport().get_visible_rect().size
	if not Rect2(Vector2(-60,-60),extent+Vector2(120,120)).has_point(screen):
		hide()
		return
	_canvas.size = extent
	# Keep both the round button and its caption on screen at the edges.
	screen = screen.clamp(Vector2(52,44),extent-Vector2(52,80))
	button.position = screen-button.size*0.5
