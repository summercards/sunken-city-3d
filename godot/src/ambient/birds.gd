extends Node3D
## Flock placement only. The bird prefab owns its visual and motion.
const Bird = preload("res://scenes/decorations/animals/bird.tscn")
## 烘焙 baseY 是 Three 原型的坐标（5.8~9.2），搬进 Godot 要抬到屋顶之上。
## 原先抬 12 → 整群飞在 18.8~21.2 m，比屋顶（实测 11.84）高 7 m，实机像贴着画面上沿。
## 改成 8.5 → 14.3~17.7 m，最低那只仍在屋顶上方 2.4 m，净空断言（屋顶 +1 m）保留 0.6 m 余量。
@export var altitude_offset := 8.5
## 海鸥只在白天飞：06:00 出现，过了 18:00 整群收掉。
##
## 只读 WorldClock 的小时，不存第二份时间、不碰日程规则 —— 鸟是装饰，
## 不该有自己的闹钟。18:00 之后海面只剩船灯与水面，这也是「过了 6 点不再出现」
## 的字面口径（傍晚六点，不是清晨六点）。
const FIRST_HOUR := 6.0
const LAST_HOUR := 18.0
var _birds: Array = []
var _hour := -1.0
## 上一次真正应用的可见状态。三态：-1 = 还没应用过（build 之后第一次 set_hour 必生效）。
##
## 不能初始成 false：`build()` 把根节点设成可见（新局默认白天），
## 若读档刚好停在 19:00，第一次 `set_hour(19)` 算出 shown=false，
## 与初值 false 相等就被当成"状态没变"提前返回 —— 鸟群留在可见。
var _shown := -1
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
	visible = true
	_shown = -1
	# build() 之后若已经有时刻，立刻按它定位一次：19:00 读档不该先闪一群鸟。
	if _hour >= 0.0: set_hour(_hour)
## 按时段收起/放出整群。
##
## 隐藏用**根节点的 visible + 子节点停止 process**，不是只改可见性：
## 只改 visible 的话每只鸟还在算 `sample()`（十二次三角与矩阵），夜里白跑一整晚；
## 停掉 process 后重新出现会从冻结相位接着飞，不会瞬移。
func set_hour(hour: float) -> void:
	_hour = hour
	var shown := 1 if (hour >= FIRST_HOUR and hour < LAST_HOUR) else 0
	if shown == _shown: return
	_shown = shown
	visible = shown == 1
	for entry in _birds:
		var bird: Node = entry["root"]
		if is_instance_valid(bird): bird.set_process(shown == 1)
func is_flying_hour() -> bool:
	return _hour >= FIRST_HOUR and _hour < LAST_HOUR
