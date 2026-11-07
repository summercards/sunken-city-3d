extends SceneTree
## 单体不装配 Main；集成工况只在 runner 的隔离用户目录里加载正式场景。
const BoatScript = preload("res://src/navigation/boat.gd")
const NavScript = preload("res://src/navigation/water_navigation.gd")
const WakeScript = preload("res://src/rendering/boat_wake.gd")
const FPS := [30, 60, 120]
var checks := 0
var failures := 0
var metrics := {}
var traces: Array = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func xy(boat: Node3D) -> Vector2:
	return Vector2(boat.position.x, boat.position.z)

func fixture(shapes: Array, start: Vector2, direction: Vector2, bounds := Rect2()) -> Dictionary:
	var nav = NavScript.new()
	nav.shape_query = func(): return shapes
	nav.allowed_area = bounds
	var boat = BoatScript.new()
	boat.set_process(false)
	root.add_child(boat)
	boat.place_at(Vector3(start.x, 1.12, start.y), atan2(-direction.x, -direction.y))
	var stats := {"signals": 0, "queries": 0, "rejected": 0, "max_step": 0.0, "arrivals": 0}
	boat.navigation_blocked.connect(func():
		stats.signals += 1
		check(boat.wake_uniform().w == 0.0, "发阻挡信号前实际速度已清零")
		if boat.driving(): check(boat.drive_dir != Vector2.ZERO, "阻挡信号同步回调仍持有驾驶输入"))
	boat.arrived.connect(func(_zone, _landing): stats.arrivals += 1)
	boat.segment_clear = func(a: Vector2, b: Vector2):
		stats.queries += 1
		stats.max_step = maxf(stats.max_step, a.distance_to(b))
		var legal: bool = nav.segment_clear(a, b)
		if not legal: stats.rejected += 1
		return legal
	check(nav.is_open_water(start.x, start.y), "夹具起点合法 " + str(start))
	return {"boat": boat, "nav": nav, "stats": stats}

func tick(f: Dictionary, dt: float, automatic := false) -> void:
	var boat = f.boat
	var before := xy(boat)
	var yaw: float = boat.rotation.y
	if automatic:
		boat._steer(dt)
	else:
		boat._drive(dt)
	var after := xy(boat)
	check(f.nav.is_open_water(after.x, after.y), "逐帧中心仍在合法水域")
	check(f.nav.segment_clear(before, after), "逐帧轨迹不穿岸")
	check(before.distance_to(after) <= boat.SPEED * dt + 0.00002, "无 teleport/超速")
	check(absf(angle_difference(yaw, boat.rotation.y)) <= boat.TURN_RATE * dt + 0.00002, "角位移服从限速")
	check(absf(boat._yaw_rate) <= boat.TURN_RATE + 0.00001, "角速度未突破上限")
	check(absf(boat._turn_rate) <= boat.TURN_RATE + 0.00001, "表现转速未突破上限")
	check(boat._vel >= 0.0 and boat._vel <= boat.cruise_speed() + 0.00001, "速度有效且未超巡航")
	if boat.driving():
		check(absf(boat.travel_direction().angle_to(boat._forward(boat.rotation.y))) <= boat.DRIFT_MAX + 0.00001, "侧滑仍受设计上限约束")

func simulate(f: Dictionary, seconds: float, fps: int, automatic := false) -> void:
	for i in roundi(seconds * fps):
		tick(f, 1.0 / fps, automatic)

func escape_case(label: String, shapes: Array, start: Vector2, into: Vector2, away: Vector2, fps: int, bounds := Rect2()) -> Dictionary:
	var f := fixture(shapes, start, into, bounds)
	var boat = f.boat
	boat.set_drive(into)
	simulate(f, 2.0, fps)
	check(f.stats.rejected > 0, label + " 确实撞岸（非空跑）")
	check(boat.driving() and boat.starts_sailing(), label + " 撞岸后驾驶未关闭")
	check(boat._manual_blocked and boat._vel == 0.0 and boat.wake_uniform().w == 0.0, label + " 顶岸无推进/新尾流")
	check(f.stats.signals == 1, label + " 持续顶岸仅反馈一次")
	var blocked_at := xy(boat)
	var yaw_before: float = boat.rotation.y
	boat.set_drive(away)
	var trace: Array = []
	var stationary_turn := 0.0
	for i in 6 * fps:
		var previous := xy(boat)
		var previous_yaw: float = boat.rotation.y
		tick(f, 1.0 / fps)
		if previous.distance_to(xy(boat)) < 0.000001:
			stationary_turn += absf(angle_difference(previous_yaw, boat.rotation.y))
		if (i + 1) % (fps / 2) == 0:
			trace.append([boat.position.x, boat.position.z, boat.rotation.y, boat._vel, boat._yaw_rate, boat._manual_blocked])
	check(stationary_turn > 0.05, label + " 被挡时实测持续原地转向")
	check(absf(angle_difference(yaw_before, boat.rotation.y)) > 0.5, label + " 实测改变船头")
	check((xy(boat) - blocked_at).dot(away.normalized()) > 3.0, label + " 改离岸方向确实脱困")
	check(not boat._manual_blocked, label + " 合法划开后清阻挡反馈")
	check(f.stats.signals == 1, label + " 改方向仍被挡的阶段不刷反馈")
	check(f.stats.max_step <= boat.SPEED / 120.0 + 0.00002, label + " 所有候选平移按120Hz验段")
	boat.release_drive()
	simulate(f, 4.0, fps)
	check(not boat.driving() and not boat.starts_sailing(), label + " 松手可退出驾驶")
	check(boat._vel == 0.0 and boat._yaw_rate == 0.0 and not boat._manual_blocked, label + " 松手停稳无残留")
	var stopped := xy(boat)
	var stopped_yaw: float = boat.rotation.y
	simulate(f, 0.5, fps)
	check(xy(boat).distance_to(stopped) < 0.000001 and absf(angle_difference(stopped_yaw, boat.rotation.y)) < 0.000001, label + " 停稳无回弹")
	check(f.stats.arrivals == 0, label + " 手动不自动靠泊")
	var result := {"trace": trace, "stop": [stopped.x, stopped.y, stopped_yaw], "signals": f.stats.signals, "stationary_turn": stationary_turn}
	boat.free()
	return result

func compare_curves(label: String, results: Array) -> void:
	var max_position := 0.0
	var max_angle := 0.0
	var max_speed := 0.0
	for candidate: Dictionary in results:
		for i in candidate.trace.size():
			var base: Array = results[2].trace[i]
			var sample: Array = candidate.trace[i]
			max_position = maxf(max_position, Vector2(base[0], base[1]).distance_to(Vector2(sample[0], sample[1])))
			max_angle = maxf(max_angle, absf(angle_difference(base[2], sample[2])))
			max_speed = maxf(max_speed, absf(base[3] - sample[3]))
			check(base[5] == sample[5], label + " 各FPS阻挡状态相同")
		check(Vector2(candidate.stop[0], candidate.stop[1]).distance_to(Vector2(results[2].stop[0], results[2].stop[1])) < 0.0002, label + " 各FPS停点一致")
	check(max_position < 0.0002 and max_angle < 0.0002 and max_speed < 0.0002, label + " 30/60/120完整时间曲线一致")
	metrics[label] = {"max_position_error": max_position, "max_angle_error": max_angle, "max_speed_error": max_speed}
	traces.append({"case": label, "fps": FPS, "results": results})

func unit_boundaries() -> void:
	var rect := [{"x": 0.0, "z": 0.0, "hx": 3.0, "hz": 3.0}]
	var circle := [{"x": 0.0, "z": 0.0, "hx": 3.0, "round": true}]
	var corner := [{"x": 5.9, "z": -5.0, "hx": 5.0, "hz": 10.0}, {"x": -5.0, "z": 5.9, "hx": 10.0, "hz": 5.0}]
	for c: Dictionary in [
		{"label": "矩形左脱困", "shapes": rect, "start": Vector2(0, -3.901), "into": Vector2.DOWN, "away": Vector2(-1, -1)},
		{"label": "矩形右脱困", "shapes": rect, "start": Vector2(0, -3.901), "into": Vector2.DOWN, "away": Vector2(1, -1)},
		{"label": "圆岸反向脱困", "shapes": circle, "start": Vector2(0, -3.901), "into": Vector2.DOWN, "away": Vector2.UP},
		{"label": "内角反向脱困", "shapes": corner, "start": Vector2(-0.001, -0.001), "into": Vector2(1, 1), "away": Vector2(-1, -1)},
		{"label": "航区边缘脱困", "shapes": [], "start": Vector2(0, -9.999), "into": Vector2.UP, "away": Vector2.DOWN, "bounds": Rect2(-10, -10, 20, 20)}]:
		var results: Array = []
		for fps: int in FPS:
			results.append(escape_case(c.label + "@" + str(fps), c.shapes, c.start, c.into, c.away, fps, c.get("bounds", Rect2())))
		compare_curves(c.label, results)

func unit_lifecycle() -> void:
	for fps: int in FPS:
		var f := fixture([{"x": 0.0, "z": 0.0, "hx": 3.0, "hz": 3.0}], Vector2(0, -3.901), Vector2.DOWN)
		var boat = f.boat
		for command in ["release", "zero", "stop", "place", "sail", "point"]:
			boat.place_at(Vector3(0, 1.12, -3.901), PI)
			f.stats.signals = 0
			boat.set_drive(Vector2.DOWN)
			simulate(f, 1.0, fps)
			check(boat._manual_blocked, command + " 前置确实受阻")
			boat.set_drive(Vector2.RIGHT)
			simulate(f, 0.1, fps)
			check(absf(boat._yaw_rate) > 0.1, "受阻仍建立角速度")
			if command == "release" or command == "zero":
				if command == "release": boat.release_drive()
				else: boat.set_drive(Vector2.ZERO)
				simulate(f, 1.0, fps)
			else:
				boat._dock_left = 1.0
				match command:
					"stop": boat.stop_drive()
					"place": boat.place_at(Vector3(0, 1.12, -5), 0.0)
					"sail": boat.sail_to(Vector3(0, 1.12, -8), 0.0, "zone", "landing")
					"point": boat.sail_to_point(Vector3(0, 1.12, -8))
			check(not boat.driving() and not boat._manual_blocked and boat._manual_clear_distance == 0.0, command + " 清手动阻挡残留")
			check(boat.drive_dir == Vector2.ZERO and boat._yaw_rate == 0.0 and boat._dock_left == 0.0, command + " 清输入/角速/旧泊位对齐")
			if command in ["sail", "point"]:
				check(boat.starts_sailing(), command + " 自动接管未被误停")
				simulate(f, 5.0, fps, true)
				check(xy(boat).distance_to(Vector2(0, -8)) < 0.05, command + " 接管后实际到达")
			else:
				var stopped := xy(boat)
				var yaw: float = boat.rotation.y
				boat._process(0.1)
				check(xy(boat) == stopped and absf(angle_difference(yaw, boat.rotation.y)) < 0.000001, command + " 无旧对齐或位移残留")
		boat.free()

func unit_feedback() -> void:
	var f := fixture([{"x": 0.0, "z": 0.0, "hx": 3.0, "hz": 3.0}], Vector2(0, -3.901), Vector2.DOWN)
	var boat = f.boat
	boat.set_drive(Vector2.DOWN)
	simulate(f, 1.0, 60)
	for sign_value in [-1.0, 1.0]:
		boat._manual_clear_distance = 0.03
		boat.set_drive(Vector2.DOWN.rotated(sign_value * 0.15))
		check(boat._manual_clear_distance == 0.0 and boat._manual_blocked, "正负方向变化对称且不重置碰撞反馈")
		boat.set_drive(Vector2.DOWN)
	for i in 120:
		boat.set_drive(Vector2.DOWN.rotated(0.1 if i % 2 == 0 else -0.1))
		tick(f, 1.0 / 60.0)
	check(f.stats.signals == 1, "墙前反复改方向不重复toast")
	boat.release_drive()
	simulate(f, 1.0, 60)
	boat.set_drive(Vector2.DOWN)
	simulate(f, 1.0, 60)
	check(f.stats.signals == 2, "停稳后新驾驶可以再次反馈")
	boat.set_drive(Vector2.UP)
	simulate(f, 6.0, 60)
	check(not boat._manual_blocked, "脱困后反馈重新武装")
	boat.set_drive(Vector2.DOWN)
	simulate(f, 10.0, 60)
	check(f.stats.signals == 3, "实际划开再撞只新增一次反馈")
	boat.free()

func unit_auto_and_limits() -> void:
	for fps: int in FPS:
		var f := fixture([{"x": 0.0, "z": 0.0, "hx": 3.0, "hz": 3.0}], Vector2(0, -4), Vector2.DOWN)
		var boat = f.boat
		boat.sail_to_point(Vector3(0, 1.12, 6))
		simulate(f, 3.0, fps, true)
		check(not boat.starts_sailing() and not boat.driving() and boat._vel == 0.0, "自动路线撞岸必须停止")
		check(f.stats.signals == 1 and f.stats.arrivals == 0, "自动受阻仅一次且不误报到达")
		var stopped := xy(boat)
		simulate(f, 1.0, fps, true)
		check(xy(boat) == stopped and f.stats.signals == 1, "自动停航不会继续顶岸")
		boat.free()
	var open := fixture([], Vector2.ZERO, Vector2.UP)
	var b = open.boat
	b.set_drive(Vector2.RIGHT)
	var previous_rate := 0.0
	for i in 240:
		var ratio: float = clampf(b._vel / b.cruise_speed(), 0.0, 1.0)
		var limit: float = b.TURN_RATE * (b.TURN_AT_REST + (1.0 - b.TURN_AT_REST) * ratio)
		tick(open, 1.0 / 120.0)
		check(absf(b._yaw_rate - previous_rate) <= b.TURN_ACCEL / 120.0 + 0.00001, "角加速度限制保持")
		check(absf(b._yaw_rate) <= maxf(absf(previous_rate), limit) + 0.00001, "舵效随船速变化且按惯性收敛")
		previous_rate = b._yaw_rate
	b.stop_drive()
	b.set_drive(Vector2.UP)
	var p := xy(b)
	b._drive(0.0)
	b._drive(-1.0)
	check(xy(b) == p, "零/负步长无推进")
	b._drive(2.0)
	check(xy(b).distance_to(p) < b.SPEED * 0.25, "大步长仍受0.25秒预算保护")
	b.free()

func unit_speed_collision() -> void:
	for fps: int in FPS:
		var f := fixture([{"x": 0.0, "z": 0.0, "hx": 3.0, "hz": 3.0}], Vector2(0, -5), Vector2.DOWN)
		var boat = f.boat
		boat.set_drive(Vector2.DOWN)
		boat._vel = boat.cruise_speed()
		boat._speed_actual = boat._vel
		var collided := false
		for i in fps:
			var count: int = f.stats.signals
			tick(f, 1.0 / fps)
			if f.stats.signals > count:
				collided = true
				break
		# 一次渲染帧内，受阻后的细步可能仍有少量合法余隙可走；信号当下零速另有同步断言。
		check(collided and boat._vel <= boat.ACCEL / fps + 0.00001 and boat.driving(), "满速撞岸消除旧惯性但不关闭驾驶")
		boat.set_drive(Vector2.RIGHT)
		simulate(f, 0.2, fps)
		check(absf(boat._yaw_rate) > 0.5 and boat._turn_rate == boat._yaw_rate, "碰撞后角速度和表现转速持续建立")
		boat.release_drive()
		simulate(f, 2.0, fps)
		check(not boat.driving() and not boat._manual_blocked, "满速碰撞转向再松手可结束")
		boat.free()

func unit_wake() -> void:
	var b = BoatScript.new()
	var wake = WakeScript.new()
	var surface := MeshInstance3D.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform vec4 wake_points[32]; uniform vec2 wake_strengths[32]; uniform int wake_count;"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	surface.material_override = mat
	b.place_at(Vector3.ZERO, 0.0)
	b._travel_dir = Vector2.LEFT
	b._speed_actual = 1.0
	check(b.travel_direction().is_equal_approx(Vector2.UP), "非手动接口不泄漏陈旧航迹")
	wake.update_wake(0.0, b, surface)
	check(wake.samples.back().pos.is_equal_approx(Vector2(0, 1.9)), "自动首采样无轨迹时退回forward")
	b.position.x += 0.2
	wake.update_wake(0.2, b, surface)
	check((Vector2(0.2, 0) - wake.samples.back().pos).normalized().is_equal_approx(Vector2.RIGHT), "自动尾流沿真实位移而非旧travel/船头")
	b.manual_drive = true
	b._travel_dir = Vector2(0.1, -1).normalized()
	b.position.x += 0.2
	wake.update_wake(0.4, b, surface)
	check((xy(b) - wake.samples.back().pos).normalized().is_equal_approx(b._travel_dir), "手动尾流消费侧滑接口")
	b._speed_actual = 0.0
	var count: int = wake.samples.size()
	wake.update_wake(0.6, b, surface)
	check(wake.samples.size() == count, "受阻原地转向不生成新尾流")
	b.manual_drive = false
	b._speed_actual = 1.0
	b.position = Vector3(50, 1.12, 0)
	wake.update_wake(0.8, b, surface)
	check(wake.samples.size() == 1 and wake.samples.back().pos.is_equal_approx(Vector2(50, 1.9)), "跳变清历史并忽略teleport方向")
	wake.free()
	surface.free()
	b.free()

func real_shore() -> void:
	var isolated := OS.get_user_data_dir().replace("\\", "/").contains("sea-verification/")
	check(isolated, "正式shore工况必须先由runner隔离存档")
	if not isolated: return
	var visual := DisplayServer.get_name() != "headless"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# 禁止脚本自行推进，但保留真实 Main 模型、水面与渲染。
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var park: Dictionary = main._landing_data("zone1", "main")
	check(not park.is_empty(), "正式场景家园泊位存在")
	if park.is_empty():
		main.free()
		return
	var start := Vector2(float(park.boatPark[0]), float(park.boatPark[2]))
	check(bool(main.navigation.is_open_water(start.x, start.y)), "真实泊位起点在合法水域")
	var shore := Vector2.INF
	# 从真实泊位寻找短距岸线，用正式navigation判据，不钉死场景绝对坐标。
	for i in 32:
		var dir := Vector2.from_angle(TAU * i / 32.0)
		for j in range(1, 25):
			var p := start + dir * (float(j) * 0.25)
			if not main.navigation.is_open_water(p.x, p.y):
				shore = dir
				break
		if shore.is_finite(): break
	check(shore.is_finite(), "真实泊位邻近有可复现岸线")
	if shore.is_finite():
		var contact := start
		for j in range(1, 1201):
			var p := start + shore * (float(j) * 0.005)
			if not main.navigation.segment_clear(contact, p): break
			contact = p
		var f := {"boat": main.boat, "nav": main.navigation}
		main.boat.place_at(Vector3(contact.x, 1.12, contact.y), atan2(-shore.x, -shore.y))
		var signals := {"count": 0}
		main.boat.navigation_blocked.connect(func(): signals.count += 1)
		var evidence := {"time": 0.0, "frames": [], "images": [], "paths": []}
		var advance := func():
			# tick 只调用正式 _drive；每次120Hz步进都检查水域、验段、角速与平移上限。
			tick(f, 1.0 / 120.0)
			evidence.time += 1.0 / 120.0
			if visual:
				main.boat._animate_oars(1.0 / 120.0)
				main.water_node.update_surface(evidence.time, main.boat, main.cam.target)
		if visual:
			main.hud.hide()
			main.markers.hide()
			main.ribbon.hide()
			main._calendar_label.hide()
			main.player.hide()
			if main.start_screen != null: main.start_screen.hide()
			main.daylight_rig.apply(9.0)
			main.cam.suspend_follow()
			main.cam.target = Vector3(contact.x - shore.x * 4.5, 1.6, contact.y - shore.y * 4.5)
			var side := shore.orthogonal()
			main.cam.orbit_dir = Vector3(-shore.x * 0.85 + side.x * 0.65, 1.4, -shore.y * 0.85 + side.y * 0.65)
			main.cam.distance = 23.0
			main.cam.cam_fov = 40.0
			main.cam.refresh()
			main.cam.make_current()
			await process_frame
		var capture := func(label: String):
			if not visual: return
			# 等待绘制不推进驾驶；所有阶段沿同一条实测轨迹、同一固定机位取图。
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var path := "res://outputs/boat-unstick-" + label + ".png"
			check(image != null and not image.is_empty(), "真实shore截图非空 " + label)
			if image == null or image.is_empty(): return
			check(image.save_png(path) == OK, "真实shore截图已保存 " + label)
			var center: Vector3 = main.boat.global_position + Vector3.UP * 0.5
			var pixel: Vector2 = main.cam.unproject_position(center)
			check(not main.cam.is_position_behind(center) and root.get_visible_rect().has_point(pixel), "实际船模型位于画面内 " + label)
			check(is_instance_valid(main.boat.model) and main.boat.model.is_visible_in_tree(), "实际船模型可见 " + label)
			evidence.paths.append(path)
			evidence.images.append(image)
			evidence.frames.append({"file": path, "time": evidence.time, "position": [main.boat.position.x, main.boat.position.z], "yaw": main.boat.rotation.y, "speed": main.boat._vel, "yaw_rate": main.boat._yaw_rate, "manual_drive": main.boat.manual_drive, "blocked": main.boat._manual_blocked})
			print("[boat-unstick] screenshot ", path)
		main.boat.set_drive(shore)
		for i in 120: advance.call()
		check(main.boat.driving() and main.boat._manual_blocked, "真实main回调保留受阻驾驶")
		check(main.boat._vel == 0.0 and main.boat.wake_uniform().w == 0.0, "真实shore顶岸无推进或新尾流")
		check(signals.count == 1, "真实shore持续受阻只反馈一次")
		var blocked_at := xy(main.boat)
		var blocked_yaw: float = main.boat.rotation.y
		await capture.call("blocked")
		main.boat.set_drive(-shore)
		var stationary_turn := 0.0
		var stationary_start := blocked_at
		var stationary_yaw := blocked_yaw
		var turn_captured := false
		var max_stationary_displacement := 0.0
		for i in 720:
			var before := xy(main.boat)
			var yaw: float = main.boat.rotation.y
			advance.call()
			var displacement := before.distance_to(xy(main.boat))
			if displacement < 0.000001 and main.boat._manual_blocked:
				stationary_turn += absf(angle_difference(yaw, main.boat.rotation.y))
				if not turn_captured:
					max_stationary_displacement = maxf(max_stationary_displacement, stationary_start.distance_to(xy(main.boat)))
					if absf(angle_difference(stationary_yaw, main.boat.rotation.y)) >= 0.55:
						check(stationary_start.distance_to(xy(main.boat)) < 0.000001, "真实shore转头截图前连续严格原地无平移")
						check(main.boat.manual_drive and absf(main.boat._yaw_rate) > 0.1, "真实shore转头由manual_drive持续推进")
						await capture.call("turning")
						turn_captured = true
			else:
				stationary_start = xy(main.boat)
				stationary_yaw = main.boat.rotation.y
			if visual and (i + 1) in [30, 60, 90, 120, 180, 240, 360, 480, 600]:
				await capture.call("sequence-%03d" % (i + 1))
		check(turn_captured and stationary_turn > 0.55, "真实shore实测连续原地转头并取图")
		check(absf(angle_difference(blocked_yaw, main.boat.rotation.y)) > 0.5, "真实shore实测改变船头")
		var escaped_at := xy(main.boat)
		check((escaped_at - blocked_at).dot(-shore) > 2.0, "真实shore按离岸方向可脱困")
		check(main.boat.manual_drive and not main.boat._manual_blocked, "真实shore脱困仍在手动驾驶且清除阻挡")
		check(signals.count == 1, "真实shore转头脱困不重复阻挡反馈")
		await capture.call("escaped")
		main.boat.release_drive()
		for i in 480: advance.call()
		check(not main.boat.driving() and not main.boat._manual_blocked, "真实shore松手可停")
		if visual:
			check(evidence.images.size() == 12, "真实shore三阶段及九个连续采样全部产出")
			var sheet := Image.create(1920, 900, false, Image.FORMAT_RGB8)
			for i in evidence.images.size():
				var tile: Image = evidence.images[i].duplicate()
				tile.convert(Image.FORMAT_RGB8)
				tile.resize(480, 300, Image.INTERPOLATE_LANCZOS)
				sheet.blit_rect(tile, Rect2i(0, 0, 480, 300), Vector2i((i % 4) * 480, (i / 4) * 300))
			var sheet_path := "res://outputs/boat-unstick-sequence.png"
			check(sheet.save_png(sheet_path) == OK, "真实shore连续图已保存")
			evidence.paths.append(sheet_path)
			print("[boat-unstick] screenshot ", sheet_path)
		metrics["real_shore"] = {"start": [contact.x, contact.y], "blocked": [blocked_at.x, blocked_at.y], "into": [shore.x, shore.y], "escaped": [escaped_at.x, escaped_at.y], "end": [main.boat.position.x, main.boat.position.z], "signals": signals.count, "stationary_turn": stationary_turn, "max_stationary_displacement": max_stationary_displacement, "escape_distance": (escaped_at - blocked_at).dot(-shore), "frames": evidence.frames, "screenshots": evidence.paths, "screenshot_count": evidence.paths.size()}
	main.queue_free()
	await process_frame

func run() -> void:
	unit_boundaries()
	unit_lifecycle()
	unit_feedback()
	unit_auto_and_limits()
	unit_speed_collision()
	unit_wake()
	print("[boat-unstick] 单体 %d checks, %d failures" % [checks, failures])
	if OS.get_environment("SEA_BOAT_UNSTICK_SHORE") == "1" or DisplayServer.get_name() != "headless":
		await real_shore()
	var output := FileAccess.open("res://outputs/boat-unstick-metrics.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"checks": checks, "failures": failures, "metrics": metrics, "curves": traces}, "\t"))
	print("[boat-unstick] metrics ", JSON.stringify(metrics))
	print("[boat-unstick] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
