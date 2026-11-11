extends RefCounted
## SEA-MOVE 键盘自由行走（2026-11-05，手感修订 SEA-MOVE-R23）。
##
## 只回答两件事：这一步能不能踩、能踩多大。不读键盘、不碰镜头、不结算交互 ——
## 输入由 Main 每帧折算成世界方向后交给 `ActorController.move_intent`。
##
## 与点击走路的差别只在「谁决定终点」：
##   · 点击走路：GroundSpace 求一条折线，逐个航点推进（速度恒定）；
##   · 自由行走：每帧按方向迈一步，脚下没有地面就迈不出去（速度有加减速）。
## 两者共用同一个物理胶囊（`CharacterMotor.move_ground`）、同一个最高速度、同一个 +Z 朝向契约。
##
## 手感参数全部是时间常数，没有「每帧乘 0.9」这类帧率相关写法：
##   v ← v + (v_target − v)·(1 − e^(−Δt/τ))
## 同样按住 0.25 秒，30 / 60 / 120 FPS 走出的距离一致。

## 岸上行走目标速度（m/s）。2026-11-11 按用户要求「移动速度加快 0.5」由 2.3 提到 2.8；
## 点击走路（walk_action.SPEED）同步同值，两条入口仍是同一个「最高速度」。
const SPEED := 2.8
## Shift 小跑倍率。2026-11-11 按「快跑速度再快 30%」由 1.12 提到 **1.456**（1.12 × 1.3）。
## 2.8 × 1.456 = 4.0768 m/s（14.7 km/h），不改变转向/碰撞/体力，也不引入第二档冲刺。
const SPRINT_MULTIPLIER := 1.456
## 起步时间常数。0.085 s ⇒ 63% 在 0.085 s、95% 在 0.25 s 达到目标速度。
## 取值理由：低于 0.06 像被弹出去，高于 0.12 按一下没反应，0.085 正好是「脚步先着地」。
const ACCEL_TAU := 0.085
## 刹车时间常数。滑行距离 = v·τ = 2.8 × 0.055 ≈ 0.15 m，收在 0.25 s 内停稳。
## 比 ACCEL 短：停要果断，起要柔和 —— 反过来会像冰面。
const DECEL_TAU := 0.055
## 指数收敛永远到不了 0，低于这个速度且没有输入就判站定。
const STOP_SPEED := 0.05
## 反向输入的速度折减：θ = 180° 时只剩 35%，先转身再走，不滑冰。
## scale = 0.35 + 0.65 · (cos θ + 1)/2
const REVERSE_FLOOR := 0.35
## 朝向跟随速度方向的时间常数。比位置慢一点，转弯时肩膀略有领先感。
const FACING_TAU := 0.075
## 低于这个速度不更新朝向：站定时不该被残余速度拧一下脸。
const FACING_MIN_SPEED := 0.15
## 单帧最多消费的物理时间：卡顿后不要一步跨出去半米。
const MAX_STEP := 0.05
## 与点击走路同一套身影内收：0.38 米帽檐不进水面。
## 但自由行走每次只迈 3–4 厘米，按 0.38 判会在 0.9 米宽的门框前直接卡死
## （中心必须离门框 0.38 才放行，人却需要从中间过），所以这里取 0.30：
## 物理胶囊半径 0.22 已经保证不穿墙，多出来的 8 厘米只防帽檐压水。
const EDGE_CLEARANCE := 0.30
## 单步允许的高度差：楼梯一踏步约 0.2 米，斜坡更小；超过这个数说明选错了楼层。
const MAX_STEP_HEIGHT := 0.45

func step(c, delta: float) -> void:
	var dt := clampf(delta, 0.0, MAX_STEP)
	if dt <= 0.000001:
		return
	var intent: Vector3 = c.move_intent
	intent.y = 0.0
	var has_input := intent.length_squared() > 0.000001
	if has_input:
		intent = intent.normalized()
	var vel: Vector3 = c.move_velocity
	# 目标速度：输入方向与当前速度方向越相反，给的推进越小 —— 转身走弧线，不是瞬移。
	var target := Vector3.ZERO
	if has_input:
		var scale := 1.0
		var speed_now := vel.length()
		if speed_now > 0.20:
			var align := clampf(vel.normalized().dot(intent), -1.0, 1.0)
			scale = REVERSE_FLOOR + (1.0 - REVERSE_FLOOR) * (align * 0.5 + 0.5)
		var max_speed := SPEED * (SPRINT_MULTIPLIER if c.sprint_held else 1.0)
		target = intent * max_speed * scale
	vel = vel.lerp(target, 1.0 - exp(-dt / (ACCEL_TAU if has_input else DECEL_TAU)))
	if not has_input and vel.length() < STOP_SPEED:
		vel = Vector3.ZERO
	c.move_velocity = vel
	if vel.length() < 0.0005:
		_rest(c)
		return
	var area: Node3D = _area_under(c)
	if area == null:
		c.move_velocity = Vector3.ZERO
		_rest(c)
		return
	c.walk_area = area
	var here: Vector3 = c.actor.global_position
	var wish: Vector3 = vel * dt
	# 分轴尝试：贴着甲板边或门框斜着走时，能沿边走而不是整个人卡住。
	var step_vec := Vector3.ZERO
	for axis in ["x", "z"]:
		var part: float = wish[axis]
		if absf(part) < 0.00001:
			continue
		var probe := here
		probe[axis] = here[axis] + part
		if _standable(area, probe, here):
			step_vec[axis] = part
	# 单轴各自可走，合成点仍可能落在内凹角里（两条直角边都够、斜点不够）。
	# 这时退化为其中一支，沿边走 —— 不能靠物理去兜，那会让人卡在角上抖。
	if step_vec.x != 0.0 and step_vec.z != 0.0 and not _standable(area, here + step_vec, here):
		step_vec = Vector3(step_vec.x, 0.0, 0.0) if absf(step_vec.x) >= absf(step_vec.z) else Vector3(0.0, 0.0, step_vec.z)
	if step_vec.length_squared() < 0.0000000001:
		# 顶住边界：吃掉这一帧的动量，避免持续推墙时越攒越大的「弹墙」。
		c.move_velocity = Vector3.ZERO
		c.actor.walk_speed_ratio = 0.0
		# 脚步被甲板外缘挡住，仍能转脸看向船/操作口；否则面对交互
		# 的要求会在岸边变成死锁。只转角色朝向，不挪位置、不空踩。
		if has_input:
			c.actor.rotation.y = lerp_angle(c.actor.rotation.y, atan2(intent.x, intent.z), 1.0 - exp(-dt / FACING_TAU))
		return
	var result: Dictionary = c.actor.move_ground(step_vec, dt)
	var moved: Vector3 = result.moved
	# 实际走了多少就是多少：撞墙/被挡时把速度改成真实值，
	# 否则下一帧还按原速度推，人会在墙边抖。
	var speed_actual := moved.length() / dt
	if speed_actual < vel.length() * 0.5:
		c.move_velocity = moved / dt
	# 与点击走路一致：脸和脚尖朝局部 +Z，偏航把 +Z 对齐实际移动方向。
	if speed_actual > FACING_MIN_SPEED or has_input:
		var face_dir: Vector3 = vel if speed_actual > FACING_MIN_SPEED else intent
		var heading := atan2(face_dir.x, face_dir.z)
		c.actor.rotation.y = lerp_angle(c.actor.rotation.y, heading, 1.0 - exp(-dt / FACING_TAU))
	# 步频跟地速走（SEA-MOVE-R23）：脚不打滑，慢起步时步子也慢下来。
	# 上界必须 ≥ `SPRINT_MULTIPLIER`（1.456），否则轻跑稳态被截到 1.35、步频比地速
	# 慢 7%，脚会在跑起来时明显往后拖。取 1.50 留一点余量容斜坡/推挤的瞬时超速。
	c.actor.walk_speed_ratio = clampf(speed_actual / SPEED, 0.0, 1.50)

func _rest(c) -> void:
	c.move_intent = Vector3.ZERO
	c.move_velocity = Vector3.ZERO
	if is_instance_valid(c.actor):
		c.actor.walk_speed_ratio = 0.0
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
	if float(area.body_radius) <= 0.001:
		# 动态平台（自建木板/浮台）已是角色中心域，物理面自己内收过，别再收一次。
		return true
	var target_local: Vector3 = area.to_local(Vector3(point.x, at.y, point.z))
	var target_clear: float = area.clearance(target_local.x, target_local.z)
	if target_clear + 0.001 >= EDGE_CLEARANCE:
		return true
	# 已经站在比阈值更贴边的地方（栈桥窄、人本来就在边缘）时，
	# 只允许「维持或远离边缘」。死守阈值会让人在边缘上一厘米都挪不动 ——
	# 实测码头栈桥净空 0.265 米，按 0.30 判就是原地卡死。
	var here_local: Vector3 = area.to_local(Vector3(from.x, at.y, from.z))
	var here_clear: float = area.clearance(here_local.x, here_local.z)
	return target_clear + 0.005 >= here_clear
