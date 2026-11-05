extends RefCounted
## SEA-MOVE 键盘自由行走（2026-11-05）。
##
## 只回答两件事：这一步能不能踩、能踩多大。不读键盘、不碰镜头、不结算交互 ——
## 输入由 Main 每帧折算成世界方向后交给 `ActorController.move_intent`。
##
## 与点击走路的差别只在「谁决定终点」：
##   · 点击走路：GroundSpace 求一条折线，逐个航点推进；
##   · 自由行走：每帧按方向迈一步，脚下没有地面就迈不出去。
## 两者共用同一个物理胶囊（`CharacterMotor.move_ground`）、同一个速度、同一个 +Z 朝向契约。

const SPEED := 2.3
## 与点击走路同一套身影内收：0.38 米帽檐不进水面。
## 但自由行走每次只迈 3–4 厘米，按 0.38 判会在 0.9 米宽的门框前直接卡死
## （中心必须离门框 0.38 才放行，人却需要从中间过），所以这里取 0.30：
## 物理胶囊半径 0.22 已经保证不穿墙，多出来的 8 厘米只防帽檐压水。
const EDGE_CLEARANCE := 0.30
## 单步允许的高度差：楼梯一踏步约 0.2 米，斜坡更小；超过这个数说明选错了楼层。
const MAX_STEP_HEIGHT := 0.45

func step(c, delta: float) -> void:
	var dir: Vector3 = c.move_intent
	dir.y = 0.0
	if dir.length_squared() < 0.000001:
		_rest(c)
		return
	dir = dir.normalized()
	var area: Node3D = _area_under(c)
	if area == null:
		_rest(c)
		return
	c.walk_area = area
	var here: Vector3 = c.actor.global_position
	var budget: float = SPEED * delta
	# 分轴尝试：贴着甲板边或门框斜着走时，能沿边走而不是整个人卡住。
	var wish := Vector3.ZERO
	for axis in ["x", "z"]:
		var part: float = dir[axis] * budget
		if absf(part) < 0.00001:
			continue
		var probe := here
		probe[axis] = here[axis] + part
		if _standable(area, probe, here):
			wish[axis] = part
	if wish.length_squared() < 0.000000001:
		return
	var result: Dictionary = c.actor.move_ground(wish, delta)
	var moved: Vector3 = result.moved
	if moved.length() < 0.0002:
		return
	# 与点击走路一致：脸和脚尖朝局部 +Z，偏航把 +Z 对齐实际移动方向。
	c.actor.rotation.y = lerp_angle(c.actor.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-12.0 * delta))

func _rest(c) -> void:
	c.move_intent = Vector3.ZERO
	if c.machine.current == "strolling":
		c.machine.change("ashore_idle")

## 角色脚下属于哪块行走面：优先沿用当前块（避免楼层在边界处来回跳），
## 走不出去时再从所在区块按三维高度重新选一次（跨到相邻平台/楼梯）。
func _area_under(c) -> Node3D:
	var here: Vector3 = c.actor.global_position
	var area: Node3D = c.walk_area
	if is_instance_valid(area) and _standable(area, here, here):
		return area
	var zone: Variant = c.ports.zone.call()
	if zone != null and is_instance_valid(zone) and zone.has_method("area_at"):
		var found: Variant = zone.area_at(here, 0.6)
		if found != null:
			return found
	return null

func _standable(area: Node3D, point: Vector3, from: Vector3) -> bool:
	var at: Vector3 = area.surface_point(Vector3(point.x, from.y, point.z))
	if not at.is_finite():
		return false
	if absf(at.y - from.y) > MAX_STEP_HEIGHT:
		return false
	if not area.surface_triangles.is_empty():
		# 斜面/多层三角面自带精确边界；再做 2D 内收会把斜坡入口判成走不进去。
		return true
	var radius: float = clampf(float(area.body_radius), 0.0, EDGE_CLEARANCE)
	if radius <= 0.001:
		return true
	var local: Vector3 = area.to_local(Vector3(point.x, at.y, point.z))
	return area.clearance(local.x, local.z) + 0.001 >= radius
