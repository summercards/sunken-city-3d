extends RefCounted
## Keyboard intent drives the player's physical capsule.
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
	var actual: Vector3 = c.actor.move_on_scene(vel, dt)
	var speed := actual.length()
	var facing := actual if speed > FACING_MIN_SPEED else intent
	if facing.length_squared() > 0.0001:
		c.actor.rotation.y = lerp_angle(c.actor.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-dt / FACING_TAU))
	c.actor.walk_speed_ratio = clampf(speed / SPEED, 0.0, 1.50) if c.actor.ground_contact else 0.0
	if not has_input and vel == Vector3.ZERO:
		_rest(c)

func _rest(c) -> void:
	c.move_intent = Vector3.ZERO
	c.move_velocity = Vector3.ZERO
	if is_instance_valid(c.actor):
		c.actor.walk_speed_ratio = 0.0
	if c.machine.current == "strolling":
		c.machine.change("ashore_idle")
