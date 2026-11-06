extends "res://src/ambient/scene_component.gd"
## A building-local gull flock. Visual-only, daylit, and suppressed indoors.
const Bird = preload("res://scenes/decorations/animals/bird.tscn")

@export var flight_center := Vector3.ZERO
@export var radius := Vector2(6.0, 4.0)
@export var altitude := 14.5
@export var count := 4
@export var speed := 0.42
@export var phase_offset := 0.0
@export var seed_offset := 0

var _birds: Array = []
var _hour := -1.0
var _shown := -1
var suppressed := false

func _ready() -> void:
	component_kind = "decoration"
	subcategory = "animals/gull"
	set_meta("visual_only", true)
	set_meta("water_layer", "surface")
	set_meta("water_layer_role", "none")
	build()

func build() -> void:
	# 保留父建筑实际世界原点（包括牧场下沉量），飞行平面不继承倾斜或缩放。
	global_basis = Basis.IDENTITY
	for child in get_children():
		child.free()
	_birds.clear()
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/baked/birds.json"))
	if data.is_empty():
		return
	for i in count:
		var bird: Node3D = Bird.instantiate() as Node3D
		bird.baked_variant = (i + seed_offset) % data.size()
		bird.name = "Gull%02d" % i
		bird.instance_id = "surface/gull/%s/%02d" % [name.to_snake_case(), i]
		bird.flight_center = flight_center
		bird.radius = radius
		bird.altitude = altitude + float(i % 3) * 0.45
		bird.speed = speed * (0.88 + float(i % 4) * 0.08)
		bird.phase = phase_offset + float(i) * 0.93
		add_child(bird)
		_birds.append(bird)
	visible = not suppressed
	_shown = -1
	if _hour >= 0.0:
		set_hour(_hour)

func set_hour(hour: float) -> void:
	_hour = hour
	var shown := 1 if hour >= 6.0 and hour < 18.0 else 0
	if shown == _shown:
		return
	_shown = shown
	_apply(shown == 1)

func set_interior_hidden(hidden: bool) -> void:
	if suppressed == hidden:
		return
	suppressed = hidden
	_apply(_hour >= 6.0 and _hour < 18.0)

func _apply(daytime: bool) -> void:
	var live := daytime and not suppressed
	visible = live
	for bird in _birds:
		if is_instance_valid(bird):
			bird.set_process(live)
