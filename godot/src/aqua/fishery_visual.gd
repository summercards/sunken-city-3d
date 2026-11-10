extends Node3D
## An injected projection of FisheryModel.unlocked. No economy/state writes.
signal projection_changed
## 岸坪在水面以上、围网沉到水下 —— 跨水线。见 docs/standards/水层分类与空间职责.md。
@export_enum("surface", "amphibious", "submerged", "backdrop") var water_layer := ""
@export var water_layer_role := "entity"
const ISLAND := Rect2(-16.2039985657,10.0958003998,6.3400993347,5.3)
const SURFACE_Y := 1.33
const PEN := Rect2(-25.2,15.8,12.0,10.0)
const PROP_CUTS := [Rect2(-16.21,10.08,2.0,1.75),Rect2(-11.40,13.50,1.55,1.40),Rect2(-16.21,14.15,2.1,1.3)]
var upgraded := false
var _zone: Node3D
var _ground: Node3D
var _legacy_surface: Node3D
var _original_rects: Array = []
var _original_polygons: Array[PackedVector2Array] = []
var _floats: Array = []
var _time := 0.0
var water_surface: Node3D

func _ready() -> void:
	hide()
	set_process(false)
	for node in get_node("Water").get_children():
		if str(node.name).begins_with("float"):
			_floats.append({"node":node,"base":node.position,"phase":_floats.size()*1.71})

func configure(zone: Node3D, ground: Node3D, old_surface: Node3D, water: Node3D) -> void:
	_zone = zone
	_ground = ground
	_legacy_surface = old_surface
	water_surface = water
	_original_rects = ground.rects.duplicate(true)
	_original_polygons = ground.polygons.duplicate(true)

static func walk_outlines() -> Array[PackedVector2Array]:
	var points := PackedVector2Array()
	var r := 0.45
	for corner in [Vector3(ISLAND.end.x-r,ISLAND.end.y-r,0),Vector3(ISLAND.position.x+r,ISLAND.end.y-r,90),Vector3(ISLAND.position.x+r,ISLAND.position.y+r,180),Vector3(ISLAND.end.x-r,ISLAND.position.y+r,270)]:
		for i in 7:
			var angle := deg_to_rad(corner.z+i*15)
			points.append(Vector2(corner.x+r*cos(angle),corner.y+r*sin(angle)))
	var outlines: Array[PackedVector2Array] = [points]
	for rect: Rect2 in PROP_CUTS:
		var cut := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		var next: Array[PackedVector2Array] = []
		for outline in outlines:
			next.append_array(Geometry2D.clip_polygons(outline,cut))
		outlines = next
	return outlines

func apply_upgrade(value: bool) -> void:
	if _ground == null: return
	var changed := upgraded != value
	upgraded = value
	visible = value
	set_process(value)
	_legacy_surface.visible = not value
	if not changed: return
	_ground.rects = [] if value else _original_rects.duplicate(true)
	_ground.polygons = walk_outlines() if value else _original_polygons.duplicate(true)
	_zone.rebuild_ground(_ground)
	projection_changed.emit()

func supports(point: Vector3, value: bool) -> bool:
	if absf(point.y-SURFACE_Y)>0.5: return false
	if value:
		for outline in walk_outlines():
			if Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),outline): return true
	else:
		for rect: Rect2 in _original_rects:
			if rect.has_point(Vector2(point.x,point.z)): return true
	return false

func water_shapes(value: Variant = null) -> Array:
	var active: bool = upgraded if value == null else bool(value)
	if not active: return []
	# Enclosed water is reserved for the net/fish, never a boat or pickup spawn.
	return [{"x":PEN.get_center().x,"z":PEN.get_center().y,"hx":PEN.size.x*0.5,"hz":PEN.size.y*0.5,"round":false}]

func _process(delta: float) -> void:
	_time += delta
	if is_visible_in_tree(): animate(_time)

func animate(time: float) -> void:
	_time = time
	for item in _floats:
		var node: Node3D = item.node
		var base: Vector3 = item.base
		var at := global_transform * base
		var surface := 0.0
		if water_surface != null: surface = water_surface.sample_surface(Vector2(at.x,at.z)).x
		node.position = base+Vector3(0,surface*.35,0)
		node.rotation.z = sin(time*.8+item.phase)*.035
