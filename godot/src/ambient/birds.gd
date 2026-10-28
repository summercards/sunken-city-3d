extends Node3D
## Flock placement only. The bird prefab owns its visual and motion.
const Bird = preload("res://scenes/decorations/animals/bird.tscn")
@export var altitude_offset := 12.0
var _birds: Array = []
func build() -> void:
	for child in get_children(): child.free()
	_birds.clear()
	var data: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/baked/birds.json"))
	for i in data.size():
		var b: Dictionary=data[i]
		var bird=Bird.instantiate()
		bird.baked_variant=i
		bird.name="Bird%02d" % i;bird.instance_id="surface/bird/%02d" % i
		bird.flight_center=Vector3(b.center[0],0,b.center[2]);bird.radius=Vector2(b.radiusX,b.radiusZ)
		bird.flap_speed=float(b.flapSpeed)
		bird.altitude=float(b.baseY)+altitude_offset;bird.speed=float(b.speed);bird.phase=float(b.phase)
		add_child(bird)
		_birds.append({"root":bird})
