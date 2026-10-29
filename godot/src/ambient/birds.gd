extends Node3D
## Flock placement only. The bird prefab owns its visual and motion.
const Bird = preload("res://scenes/decorations/animals/bird.tscn")
## 烘焙 baseY 是 Three 原型的坐标（5.8~9.2），搬进 Godot 要抬到屋顶之上。
## 原先抬 12 → 整群飞在 18.8~21.2 m，比屋顶（实测 11.84）高 7 m，实机像贴着画面上沿。
## 改成 8.5 → 14.3~17.7 m，最低那只仍在屋顶上方 2.4 m，净空断言（屋顶 +1 m）保留 0.6 m 余量。
@export var altitude_offset := 8.5
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
