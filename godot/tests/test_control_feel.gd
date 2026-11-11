extends SceneTree
## 操控手感专项（2026-11-05）
##
## 手感不是"看着顺眼"，每条都能算：
##   SEA-MOVE-R23    起步/刹车是指数逼近，时间常数 0.085 / 0.055 秒；反向输入走弧线；
##                   步频跟地速耦合（脚不打滑）；同一段时长在 30/60/120 FPS 下位移一致。
##   SEA-CAMERA-R14  跟随视点继承主体位移（匀速段零滞后）+ 速度前视（缓入缓出）。
##   SEA-NAV-R17     船转向有角加速度、舵效随船速变化、航迹滞后船头（侧滑）、低速软收尾。
##   SEA-INTERACT-R13 上下船是一次性动作，0.35 秒内连按被吞。
##
## 用固定的合成长方形地面做基准，避免码头的窄边把测量截断；
## 这正是 `test_walk_facing` 已经在用的做法（行走面 + 独立物理地板，不是新玩法）。

const WalkAreaScript = preload("res://src/navigation/walk_area.gd")
const SPEED := 2.8
const GROUND_LAYER := 256
const ACTOR_LAYER := 512
const FLOOR_Y := 10.0

var checks := 0
var failures := 0
var main: Node
var state: Node
var controller: Variant
var player: Node3D
var cam: Node
var area: Node3D
## 实测数值留档：文档里的数字直接抄这里，不靠回忆。
var metrics := {}


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func release_all() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(action)


## 一帧游戏：先把按键折成方向，再让状态机走一步。
## 和 `main._physics_process` 同序，但可以任意指定 Δt（帧率无关性就靠它）。
func frame(dt: float, with_camera := false) -> void:
	main._update_keyboard_move(dt)
	controller.tick(dt)
	player._process(dt)
	if with_camera:
		cam._process(dt)


func frames(seconds: float, dt: float, with_camera := false) -> void:
	var n := int(round(seconds / dt))
	for i in n:
		frame(dt, with_camera)


func respawn(position := Vector3(0.0, FLOOR_Y, 0.0)) -> void:
	release_all()
	controller.restore_pose({"mode": 0, "player": [position.x, position.y, position.z]})
	controller.walk_area = area
	controller.move_velocity = Vector3.ZERO
	controller.actor.rotation.y = 0.0


func build_fixture() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GROUND_LAYER
	body.collision_mask = ACTOR_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(24.0, 0.2, 24.0)
	collision.shape = shape
	body.add_child(collision)
	main.add_child(body)
	body.global_position = Vector3(0.0, FLOOR_Y - 0.1, 0.0)
	area = WalkAreaScript.new()
	area.name = "FeelFixture"
	main.add_child(area)
	area.surface_y = FLOOR_Y
	area.span_min = FLOOR_Y - 1.0
	area.span_max = FLOOR_Y + 1.0
	area.body_radius = 0.0
	area.rects = [Rect2(-9.0, -9.0, 18.0, 18.0)]


func open_direction(from: Vector3) -> Vector2:
	var candidates: Array = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0),
		Vector2(1, -1).normalized(), Vector2(-1, -1).normalized(),
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]
	for dir: Vector2 in candidates:
		var clear := true
		for i in range(1, 11):
			var p: Vector3 = from + Vector3(dir.x, 0.0, dir.y) * float(i)
			if not main._is_open_water(p.x, p.z):
				clear = false
				break
		if clear:
			return dir
	return Vector2.ZERO


## 逐帧累加相位增量再平均。相位是折返到 TAU 的循环量：步频 12.8 rad/s 时
## 0.5 秒已转满一圈，用首尾差 wrap 到 ±π 会读成 0.2 rad/s 的假值。
func measure_walk_rate(frames: int) -> float:
	var total := 0.0
	for i in frames:
		var before: float = player.walk_phase()
		player._process(1.0 / 60.0)
		total += fposmod(player.walk_phase() - before, TAU)
	return total / (float(frames) / 60.0)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	state = root.get_node("GameState")
	root.get_node("Economy").ticking = false
	for i in 10:
		await physics_frame
		await process_frame
	controller = main.actor_controller
	player = controller.actor
	cam = main.cam
	if controller == null or player == null:
		printerr("FAIL actor controller unavailable")
		finish()
		return
	build_fixture()
	# 物理体要在下一物理帧才进空间：不等这一下，角色会先掉出地板再被判定站不住。
	for i in 3:
		await physics_frame
		await process_frame
	state.enter_zone("zone1")
	state.set_mode(state.Mode.ASHORE)
	respawn()

	# ---- 1. 起步是指数逼近，不是瞬间满速 --------------------------------
	Input.action_press("move_forward")
	frame(1.0 / 60.0)
	var v1: float = controller.move_velocity.length()
	metrics["v_first"] = v1
	check(v1 > 0.15 and v1 < SPEED * 0.45, "起步第一帧只有 %.2f m/s（不是瞬移满速）" % v1)
	frames(0.24, 1.0 / 60.0)
	var v_full: float = controller.move_velocity.length()
	metrics["v_at_025"] = v_full
	check(v_full > SPEED * 0.88, "0.25 秒达到 %.2f m/s（≥88%% 目标）" % v_full)
	frames(0.5, 1.0 / 60.0)
	check(controller.move_velocity.length() <= SPEED * 1.02, "稳态不超过设计速度")

	# ---- 2. 松开：滑行一小段再停，不是急刹也不是漂移 --------------------
	var glide_from: Vector3 = player.global_position
	release_all()
	frames(0.05, 1.0 / 60.0)
	check(controller.move_velocity.length() > 0.2, "松手后仍有惯性（不是一帧归零）")
	frames(0.30, 1.0 / 60.0)
	var glide := Vector2(player.global_position.x - glide_from.x, player.global_position.z - glide_from.z).length()
	metrics["glide"] = glide
	check(glide > 0.05 and glide < 0.35, "滑行 %.2f m（期望 0.15 m 量级）" % glide)
	check(controller.move_velocity.length() < 0.02, "0.35 秒内停稳")
	check(controller.machine.current == "ashore_idle", "停稳后回到站立状态")
	var settled: Vector3 = player.global_position
	frames(0.3, 1.0 / 60.0)
	check(player.global_position.distance_to(settled) < 0.005, "停稳后不再自走")

	# ---- 3. 反向走弧线，不瞬间翻转 --------------------------------------
	respawn()
	Input.action_press("move_forward")
	frames(0.6, 1.0 / 60.0)
	var heading_before: Vector3 = controller.move_velocity.normalized()
	var turn_from: Vector3 = player.global_position
	release_all()
	Input.action_press("move_back")
	frame(1.0 / 60.0)
	frame(1.0 / 60.0)
	var turning: Vector3 = player.global_position - turn_from
	check(turning.normalized().dot(heading_before) > 0.55, "反向后第一帧仍沿旧方向减速（弧线起步）")
	frames(0.5, 1.0 / 60.0)
	var after: Vector3 = controller.move_velocity.normalized()
	check(after.dot(heading_before) < -0.8, "0.5 秒后确实反向行走")
	release_all()

	# ---- 4. 帧率无关：同一段时长，30/60/120 FPS 位移一致 -----------------
	var travelled: Array[float] = []
	for fps: int in [30, 60, 120]:
		respawn()
		Input.action_press("move_forward")
		frames(0.4, 1.0 / float(fps))
		travelled.append(Vector2(player.global_position.x, player.global_position.z).length())
		release_all()
	metrics["travel_30_60_120"] = travelled
	check(absf(travelled[0] - travelled[1]) < 0.04 and absf(travelled[1] - travelled[2]) < 0.04,
		"30/60/120 FPS 0.4 秒位移一致 (%.3f / %.3f / %.3f)" % [travelled[0], travelled[1], travelled[2]])

	# ---- 5. 步频跟地速耦合 ----------------------------------------------
	# 相位是 fmod 到 TAU 的循环量，步频 14.08 rad/s 时 0.5 秒要转 1.12 圈，
	# 拿首尾差再 wrap 到 ±π 会读成假值；改为逐帧累加折返增量（每帧 0.235 rad）。
	respawn()
	player.set_walking(true)
	player.walk_speed_ratio = 1.0
	var full_rate := measure_walk_rate(30)
	metrics["walk_rate_full"] = full_rate
	check(absf(full_rate - 14.08) < 1.2, "满速步频 %.2f rad/s（设计 6.4×2.2=14.08）" % full_rate)
	player.walk_speed_ratio = 0.5
	var half_rate := measure_walk_rate(30)
	metrics["walk_rate_half"] = half_rate
	check(absf(half_rate - 7.04) < 0.8, "半速步频 %.2f rad/s（设计 7.04，即满速的一半）" % half_rate)
	player.set_walking(false)
	player._process(1.0 / 60.0)
	check(absf(player.walk_phase()) < 0.0001, "停下后相位归零")

	# ---- 6. 镜头：速度前视 ----------------------------------------------
	respawn()
	cam.restore_follow(player)
	cam._process(1.0 / 60.0)
	Input.action_press("move_forward")
	# 2 秒：前视本身有 0.32 s 的缓入，1 秒时还在爬坡，测「匀速段零滞后」要等它稳。
	frames(2.0, 1.0 / 60.0, true)
	var dir: Vector3 = controller.move_velocity.normalized()
	var aim: Vector3 = cam.target - (player.global_position + Vector3.UP * main.BodyScale.CAMERA_FOCUS)
	var lead: float = aim.dot(dir)
	metrics["lead"] = lead
	check(lead > 0.25, "走路时镜头前视 %.2f m" % lead)
	check(lead <= 1.45, "前视不超过 1.4 m 上限（实际 %.2f）" % lead)
	var residual: float = cam._cur_target.distance_to(cam.target)
	metrics["residual"] = residual
	check(residual < 0.12, "匀速段视点无滞后（残差 %.3f m，旧实现约 0.6）" % residual)

	# ---- 7. 镜头：站定后前视归零 ----------------------------------------
	release_all()
	frames(1.2, 1.0 / 60.0, true)
	var settle_dir: Vector3 = dir
	var aim2: Vector3 = cam.target - (player.global_position + Vector3.UP * main.BodyScale.CAMERA_FOCUS)
	check(absf(aim2.dot(settle_dir)) < 0.10, "站定后前视回落（%.3f m）" % absf(aim2.dot(settle_dir)))

	# ---- 8. 船：转向有角加速度 ------------------------------------------
	var landing: Node3D = main._current_landing()
	var park := Vector3(0.0, 1.12, 0.0)
	if landing != null:
		var data: Dictionary = main._landing_data("zone1", "main")
		if not data.is_empty():
			park = Vector3(float(data.boatPark[0]), 1.12, float(data.boatPark[2]))
	var sail_dir: Vector2 = open_direction(park)
	check(sail_dir != Vector2.ZERO, "泊位外有开阔水域")
	main.boat.place_at(park, atan2(-sail_dir.x, -sail_dir.y))
	main.boat.set_drive(Vector2(sail_dir.y, -sail_dir.x))
	main.boat._drive(1.0 / 60.0)
	var rate_first: float = absf(main.boat._yaw_rate)
	main.boat._yaw_rate = 0.0
	for i in 12:
		main.boat._drive(1.0 / 60.0)
	var rate_later: float = absf(main.boat._yaw_rate)
	metrics["yaw_rate_first"] = rate_first
	metrics["yaw_rate_later"] = rate_later
	check(rate_first < 1.8 * 0.12, "第一帧角速度 %.3f rad/s（有惯性，不是瞬间满舵）" % rate_first)
	check(rate_later > rate_first * 2.5, "角速度逐渐建立 %.3f rad/s" % rate_later)
	check(rate_later <= 1.8 * 1.02, "角速度不超过满舵上限")
	main.boat.stop_drive()

	# ---- 9. 船：侧滑（航迹滞后船头） ------------------------------------
	main.boat.place_at(park, atan2(-sail_dir.x, -sail_dir.y))
	main.boat.set_drive(sail_dir)
	for i in 90:
		main.boat._drive(1.0 / 60.0)
	var speed_before: float = main.boat._vel
	main.boat.set_drive(Vector2(sail_dir.y, -sail_dir.x))
	for i in 18:
		main.boat._drive(1.0 / 60.0)
	var lag: float = absf(main.boat._travel_dir.angle_to(main.boat._forward(main.boat.rotation.y)))
	metrics["drift_deg"] = rad_to_deg(lag)
	check(speed_before > 1.5, "转弯前已加速到 %.2f m/s" % speed_before)
	check(lag > 0.02 and lag <= 0.15, "满舵侧滑 %.1f°（上限 8°）" % rad_to_deg(lag))

	# ---- 10. 船：松手软收尾、不顿停、不回弹 ------------------------------
	main.boat.set_drive(sail_dir)
	for i in 75:
		main.boat._drive(1.0 / 60.0)
	var stop_from := Vector2(main.boat.position.x, main.boat.position.z)
	main.boat.release_drive()
	for i in 120:
		main.boat._drive(1.0 / 60.0)
	var glide_boat := Vector2(main.boat.position.x, main.boat.position.z).distance_to(stop_from)
	metrics["boat_glide"] = glide_boat
	check(glide_boat > 0.5, "松手后滑行 %.2f m（有质量）" % glide_boat)
	check(not main.boat.driving() and not main.boat.starts_sailing(), "滑行结束退出手动驾驶")
	check(absf(main.boat._vel) < 0.001, "船速归零")
	var stop_at := Vector2(main.boat.position.x, main.boat.position.z)
	for i in 30:
		main.boat._drive(1.0 / 60.0)
	check(Vector2(main.boat.position.x, main.boat.position.z).distance_to(stop_at) < 0.01, "停稳后不回弹")
	main.boat.stop_drive()

	# ---- 11. E 键去抖 ---------------------------------------------------
	controller.walk_area = null
	main.boat.place_at(park, 0.0)
	state.landing_id = "main"
	state.enter_zone("zone1")
	if landing != null:
		var stand: Vector3 = landing.stand_position()
		var ground: Node3D = landing.ground()
		var near: Vector2 = ground.clamp_point(stand.x + 0.9, stand.z + 0.9)
		var near_point: Vector3 = ground.surface_point(Vector3(near.x, stand.y, near.y))
		if near_point.is_finite():
			respawn(near_point)
	controller.walk_area = null
	player.rotation.y = atan2(park.x - player.global_position.x, park.z - player.global_position.z)
	main._boat_key_left = 0.0
	check(main._boat_key_action() == "board", "泊位旁可以按 E 上船")
	var boarded: bool = main._toggle_boat_by_key()
	check(boarded, "第一次按 E 生效")
	check(main._boat_key_action() == "", "0.35 秒内再按被吞（不会刚上船又上岸）")
	main.actor_controller.cancel()
	controller.walk_area = null
	main._boat_key_left = 0.0
	respawn()

	release_all()
	finish()


func finish() -> void:
	print("[control-feel] metrics ", metrics)
	print("[control-feel] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
