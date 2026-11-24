extends Node3D
## An injected projection of FisheryModel.unlocked. No economy/state writes.
signal projection_changed
## 岸坪在水面以上、围网沉到水下 —— 跨水线。见 docs/standards/水层分类与空间职责.md。
@export_enum("surface", "amphibious", "submerged", "backdrop") var water_layer := ""
@export var water_layer_role := "entity"
@export var shore_navigation: PackedVector2Array
@export var pen_size := Vector2(12.0, 10.0)
var upgraded := false
var _zone: Node3D
var _ground: Node3D
var _legacy_surface: Node3D
var _legacy_collision: CollisionObject3D
@onready var _shore_collision: CollisionObject3D = $SurfaceCollision
@onready var _net_collision: StaticBody3D = $Water/NetHullCollision
var _original_rects: Array = []
var _shore_outline := PackedVector2Array()
var _floats: Array = []
var _time := 0.0
var water_surface: Node3D

func _ready() -> void:
	hide()
	_shore_collision.collision_layer = 0
	set_process(false)
	for node in get_node("Water").get_children():
		if str(node.name).begins_with("float"):
			_floats.append({"node":node,"base":node.position,"phase":_floats.size()*1.71})

func configure(zone: Node3D, water: Node3D) -> void:
	_zone = zone
	var site := get_parent()
	_ground = site.get_node("Walk_zone1_salvage")
	_legacy_surface = site.get_node("salvage_station/绞盘打捞台-海上区域-01_001")
	_legacy_collision = site.get_node("SurfaceCollision")
	water_surface = water
	_original_rects = _ground.rects.duplicate()
	_shore_outline.clear()
	for point in shore_navigation:
		var local := _ground.to_local(to_global(Vector3(point.x, 0.0, point.y)))
		_shore_outline.append(Vector2(local.x, local.z))

func apply_upgrade(value: bool) -> void:
	if _ground == null: return
	var changed := upgraded != value
	upgraded = value
	visible = value
	set_process(value)
	_legacy_surface.visible = not value
	_shore_collision.set_deferred("collision_layer", 12288 if value else 0)
	_net_collision.set_deferred("collision_layer", 4096 if value else 0)
	_legacy_collision.set_deferred("collision_layer", 0 if value else 12288)
	if not changed: return
	_ground.rects = [] if value else _original_rects
	_ground.polygons.clear()
	if value:
		_ground.polygons.append(_shore_outline)
	_zone.rebuild_ground(_ground)
	projection_changed.emit()

func supports(point: Vector3, value: bool) -> bool:
	if absf(point.y - _ground.floor_y()) > 0.5: return false
	var at := _ground.to_local(point)
	var planar := Vector2(at.x, at.z)
	if value:
		return Geometry2D.is_point_in_polygon(planar, _shore_outline)
	for rect: Rect2 in _original_rects:
		if rect.has_point(planar): return true
	return false

func water_shapes(value: Variant = null) -> Array:
	var active: bool = upgraded if value == null else bool(value)
	if not active: return []
	var pen := $PenBounds as Marker3D
	var half := Vector3(pen_size.x, 0.0, pen_size.y) * 0.5
	var bounds := pen.global_transform * AABB(-half, half * 2.0)
	var center := bounds.get_center()
	return [{"x":center.x,"z":center.z,"hx":bounds.size.x*0.5,"hz":bounds.size.z*0.5,"round":false}]

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
