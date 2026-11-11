extends SceneTree
## 正式 Main 输入链 + 独立大地板，避免窄泊位截断地速测量。
const WalkAreaScript = preload("res://src/navigation/walk_area.gd")
const FLOOR_Y := 10.0
const DT := 1.0 / 60.0
var checks := 0
var failures := 0
var main: Node
var controller: Variant
var player: Node3D
var area: Node3D
var metrics := {}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[shift-jog] FAIL ", label)

func send(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = pressed if code == KEY_SHIFT else Input.is_physical_key_pressed(KEY_SHIFT)
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_all() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT]:
		send(code, false)

func frame(dt := DT) -> void:
	main._update_keyboard_move(dt)
	controller.tick(dt)
	player._process(dt)

func frames(seconds: float, dt := DT) -> void:
	for i in int(round(seconds / dt)):
		frame(dt)

func respawn() -> void:
	release_all()
	controller.restore_pose({"mode": 0, "player": [0.0, FLOOR_Y, 0.0]})
	controller.walk_area = area
	player._process(0.0)

func begin_jog() -> void:
	respawn()
	send(KEY_SHIFT, true)
	send(KEY_W, true)
	frames(0.8)

func cleared(label: String) -> void:
	check(not controller.sprint_held and not player.sprinting() and player.run_blend() < 0.001, label)

func build_fixture() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 256
	floor_body.collision_mask = 512
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 0.2, 60)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	floor_body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("82978d")
	mesh.material_override = material
	floor_body.add_child(mesh)
	main.add_child(floor_body)
	floor_body.global_position = Vector3(0, FLOOR_Y - 0.1, 0)
	area = WalkAreaScript.new()
	area.name = "ShiftJogFixture"
	main.add_child(area)
	area.surface_y = FLOOR_Y
	area.span_min = FLOOR_Y - 1.0
	area.span_max = FLOOR_Y + 1.0
	area.body_radius = 0.0
	area.rects = [Rect2(-29, -29, 58, 58)]

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/"):
		printerr("[shift-jog] 必须通过隔离 runner 运行")
		quit(2)
		return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	for i in 12:
		await physics_frame
		await process_frame
	controller = main.actor_controller
	player = controller.actor
	check(controller != null and player != null, "正式 Main 角色控制器就绪")
	main.set_physics_process(false)
	player.set_process(false)
	main.cam.set_process(false)
	main.cam.suspend_follow()
	build_fixture()
	for i in 3:
		await physics_frame
		await process_frame
	root.get_node("GameState").enter_zone("zone1")
	check(not main.input_blocked(), "隔离正式场景允许输入")

	# 同时按下：从 idle 起步的第一物理帧即接受 Shift，而非等表现更新。
	respawn()
	send(KEY_SHIFT, true)
	send(KEY_W, true)
	check(Input.is_physical_key_pressed(KEY_SHIFT) and Input.is_action_pressed("move_forward"), "parse + flush 真正写入 Shift 与 W 状态")
	main._update_keyboard_move(DT)
	check(controller.strolling() and controller.sprint_held and player.sprinting(), "起步首帧已提交轻跑意图")
	controller.tick(DT)
	player._process(DT)
	check(player.run_blend() > 0.0 and player.run_blend() < 0.25, "首帧混合非瞬切")
	check(controller.move_velocity.length() > 0.0 and controller.move_velocity.length() < 1.0, "轻跑仍从同一加速积分器起步")
	frames(0.8)
	var jog_speed: float = controller.move_velocity.length()
	metrics["jog_speed"] = jog_speed
	check(absf(jog_speed - 4.0768) < 0.003, "轻跑稳态 4.0768 m/s（2.8×1.456）")
	check(absf(player.walk_speed_ratio - 1.456) < 0.003, "真实地速比即为 1.456，不被 1.35 截断")
	var before: Vector3 = player.global_position
	frames(0.3)
	check(absf(player.global_position.distance_to(before) / 0.3 - 4.0768) < 0.01, "胶囊实际位移等于轻跑地速")
	var phase: float = player.walk_phase()
	frames(0.2)
	var jog_rate := fposmod(player.walk_phase() - phase, TAU) / 0.2
	metrics["jog_phase_rate"] = jog_rate
	check(absf(jog_rate - 14.08 * 1.15) < 0.015, "轻跑稳态步频约 +15%，不是幅度假跑")
	check(player.body_pivot.rotation.x > 0.11 and player.left_elbow.rotation.x < -0.80, "微前倾和持续屈肘")

	# 释放 Shift，但保持 W：速度和姿势平滑退回走路，相位连续。
	var blend_before: float = player.run_blend()
	phase = player.walk_phase()
	send(KEY_SHIFT, false)
	frame()
	check(not controller.sprint_held and not player.sprinting(), "Shift 松开立即清除目标")
	check(player.run_blend() > 0.5 and player.run_blend() < blend_before, "松开后姿势平滑回走")
	# 单帧相位推进在 16.192 rad/s 下是 0.270 rad；真重置会给出 0 或接近一整圈。
	var phase_step_after_release := fposmod(player.walk_phase() - phase, TAU)
	check(phase_step_after_release > 0.02 and phase_step_after_release < 0.38, "切走路相位连续（单帧 %.2f rad，不重置）" % phase_step_after_release)
	check(controller.move_velocity.length() > 2.8 and controller.move_velocity.length() < jog_speed, "松开 Shift 平滑减到走速")
	frames(0.9)
	check(absf(controller.move_velocity.length() - 2.8) < 0.002 and player.run_blend() < 0.001, "走速和姿态稳定恢复")
	phase = player.walk_phase()
	frames(0.2)
	check(absf(fposmod(player.walk_phase() - phase, TAU) / 0.2 - 14.08) < 0.01, "走路步频回到 14.08 rad/s")

	# 原地只按 Shift 不应进入 strolling；松开方向键保留既有刹车。
	respawn()
	send(KEY_SHIFT, true)
	frames(0.3)
	cleared("原地 Shift 不残留轻跑")
	check(controller.state_id() == "ashore_idle" and player.walk_phase() == 0.0, "原地没有空跑相位")
	send(KEY_UP, true)
	frames(0.8)
	check(controller.sprint_held, "方向键同样支持轻跑")
	send(KEY_UP, false)
	frame()
	check(not controller.sprint_held and controller.move_velocity.length() > 0.1, "松方向键清除轻跑但仍有既有减速")
	frames(0.6)
	cleared("减速停稳后无轻跑混合")
	check(controller.state_id() == "ashore_idle" and player.walk_phase() == 0.0, "停稳回 idle 并归零相位")

	# 模态真实进入 HUD，再验证即使不经过下一次 Main 采样也能拦住状态 tick。
	begin_jog()
	main.hud.toggle_panel()
	check(main.input_blocked(), "真实 HUD 面板阻断输入")
	controller.tick(DT)
	check(not controller.sprint_held and controller.move_intent == Vector3.ZERO, "模态 tick 清除旧轻跑意图")
	frames(0.6)
	cleared("模态期间无轻跑残留")
	main.hud.toggle_panel()
	release_all()

	for interruption in ["cancel", "sleep", "restore", "boat", "dive", "click"]:
		begin_jog()
		match interruption:
			"cancel": controller.cancel()
			"sleep": controller.begin_sleep()
			"restore": controller.restore_pose({"mode": 0, "player": [0.0, FLOOR_Y, 0.0]})
			"boat": controller.restore_pose({"mode": 1})
			"dive": controller.reconcile_mode(3)
			"click": check(controller.start_walk(area, player.global_position + Vector3(1, 0, 0)), "点击行走可接管轻跑")
		cleared(interruption + " 同步清除轻跑")
		if interruption in ["sleep", "boat", "dive"]:
			main._update_keyboard_move(DT)
			check(not controller.sprint_held and not player.sprinting(), interruption + " 按住 Shift 不能重新激活")
		release_all()
		player._process(DT)
		cleared(interruption + " 表现帧无残留")

	# 短步曲线与连续混合的数值验收（补充姿势采样，不替代上面的真实输入）。
	respawn()
	player.set_walking(true)
	player.walk_speed_ratio = 1.0
	player._walk_phase = PI / 2.0
	player._process(0.0)
	var walk_stride: float = absf(player.left_leg.rotation.x)
	var walk_knee: float = player.right_knee.rotation.x
	player.set_sprinting(true)
	player.walk_speed_ratio = 1.456
	for i in 60: player._process(DT)
	player._walk_phase = PI / 2.0
	player._process(0.0)
	# 步频只补到走路的 1.15 倍，速度却是 1.456 倍，步幅因此放大 1.266 倍；
	# 腿摆必须跟着放大，否则「腿没迈开、人滑出去」。
	check(absf(player.left_leg.rotation.x) > walk_stride * 1.2, "轻跑步幅按地速÷步频放大（%.3f > %.3f）" % [absf(player.left_leg.rotation.x), walk_stride * 1.2])
	check(player.right_knee.rotation.x > walk_knee + 0.3, "回收腿显著抬膝")
	check(player.left_elbow.rotation.x < -0.8 and player.right_elbow.rotation.x < -0.8, "双肘弯曲，不是直臂快走")

	var distances: Array[float] = []
	var blends: Array[float] = []
	for fps in [30, 60, 120]:
		respawn()
		send(KEY_SHIFT, true)
		send(KEY_W, true)
		frames(0.4, 1.0 / float(fps))
		distances.append(Vector2(player.global_position.x, player.global_position.z).length())
		blends.append(player.run_blend())
		check(absf(controller.move_velocity.length() - 4.0768 * (1.0 - exp(-0.4 / 0.085))) < 0.001, "%d FPS 共用指数积分器" % fps)
	metrics["distances_30_60_120"] = distances
	check((distances.max() - distances.min()) / distances.min() < 0.05, "30/60/120 FPS 位移偏差不超过 5%")
	check(blends.max() - blends.min() < 0.001, "混合时间常数与帧率无关")

	# 顶住边缘不继续以旧地速空跑。
	begin_jog()
	area.rects = [Rect2(player.global_position.x - 0.001, player.global_position.z - 0.001, 0.002, 0.002)]
	frame()
	check(player.walk_speed_ratio == 0.0, "地面挡停清空实际速度比")
	phase = player.walk_phase()
	player._process(DT)
	check(player.walk_phase() == phase, "地速为零时不空踩相位")
	# 站在岸边不能再迈步时，也必须能按方向转脸朝船，不然正面交互会死锁。
	var blocked_position: Vector3 = player.global_position
	var original_yaw: float = player.rotation.y
	send(KEY_W, false)
	send(KEY_D, true)
	frames(0.5)
	var desired_face: Vector3 = main._camera_relative(Vector2.RIGHT)
	check(player.global_position.distance_to(blocked_position) < 0.001, "边界转脸不挪角色根位置")
	check(absf(angle_difference(player.rotation.y, atan2(desired_face.x, desired_face.z))) < 0.02
		and absf(angle_difference(original_yaw, player.rotation.y)) > 0.8, "岸边挡停仍可按侧方向转脸")
	check(player.walk_speed_ratio == 0.0 and player.walk_phase() == phase, "原地转脸不伪造地速或空跑相位")
	area.rects = [Rect2(-29, -29, 58, 58)]
	respawn()
	check(not controller.snapshot().has("sprint_held") and not controller.snapshot().has("run_blend"), "临时轻跑不进入快照字段")

	if DisplayServer.get_name() != "headless":
		await capture_phases()
	release_all()
	controller.cancel()
	print("[shift-jog] metrics ", metrics)
	print("[shift-jog] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func capture_phases() -> void:
	begin_jog()
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.fov = 34.0
	camera.make_current()
	var sheet: Image
	for i in 8:
		frames(0.10)
		camera.global_position = player.global_position + Vector3(4.0, 2.1, 4.8)
		camera.look_at(player.global_position + Vector3(0, 1.0, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.resize(480, 300)
		if sheet == null: sheet = Image.create(1920, 600, false, image.get_format())
		sheet.blit_rect(image, Rect2i(0, 0, 480, 300), Vector2i((i % 4) * 480, (i / 4) * 300))
	check(sheet != null and sheet.save_png("res://outputs/shift-jog-phases.png") == OK, "保存连续八相位真实轻跑图")
	print("[shift-jog] 连续相位图 res://outputs/shift-jog-phases.png")
