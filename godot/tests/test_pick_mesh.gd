extends SceneTree
## 交互热区必须按模型本体算，不能把地面吞掉。
##
## 2026-10-29 用户截图：站在 zone5 平台上，点两块土箱之间的甲板空地（红框），
## 走不过去。原因是命中用「物体屏幕 AABB 外扩 10 px」，
## 六个土箱两两相邻、缝只有十几像素，各自外扩后整条缝被两侧盖满 ——
## 点地面全被判成点土箱。
##
## 本测试锁死：
##   1. 点在两块土箱之间的甲板缝上 → 不命中任何交互物（交给走路）；
##   2. 点在土箱本体上 → 命中那颗土箱（ray vs mesh，不是靠外扩猜的）；
##   3. 点在物体屏幕上 AABB 覆盖、但模型其实不在的空间 → 不命中；
##   4. 走不到的目标依然不给入口（保持上一轮结论）。

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func settle(n := 8) -> void:
	for i in n:
		await process_frame


func mouse(pos: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)
	await settle(2)


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode": 0, "player": [21.0, 1.48, 16.0]})
	root.get_node("GameState").enter_zone("zone5")
	await settle(40)

	# 俯视整块平台，让六个土箱和它们之间的缝都落在屏幕里。
	main.cam.target = Vector3(22.0, 1.48, 16.0)
	main.cam.distance = 9.0
	main.cam._apply()
	await settle(12)

	var plots: Array = []
	for i in 6:
		var node: Node3D = main.farm_field.find("platform_plot" if i == 0 else "platform_plot:%d" % i)
		if node != null:
			plots.append(node)
	check(plots.size() == 6, "找到六格水上培养土（实际 %d）" % plots.size())
	if plots.size() != 6:
		print("[pick-mesh] %d checks, %d failures" % [checks, failures])
		quit()
		return

	# ---- 1. 点在土箱本体上 → 命中 ----
	var first: Node3D = plots[0]
	var body_hit := false
	var body_at := Vector2.ZERO
	# 找土箱屏幕上确实被模型覆盖的一点：用射线逐点采样它的屏幕包围盒。
	var box: Rect2 = main.hover._screen_bounds(first)
	for gy in range(6):
		for gx in range(6):
			var at := box.position + Vector2(box.size.x * (gx + 0.5) / 6.0, box.size.y * (gy + 0.5) / 6.0)
			var ray_o: Vector3 = main.cam.project_ray_origin(at)
			var ray_d: Vector3 = main.cam.project_ray_normal(at)
			if main.hover._ray_visual_t(ray_o, ray_d, first) >= 0.0:
				body_hit = true
				body_at = at
				break
		if body_hit:
			break
	check(body_hit, "土箱屏幕上找得到真正被模型覆盖的一点")
	if body_hit:
		check(main.hover._pick(body_at).get("node") == first, "点土箱本体命中它")

	# ---- 2. 点在土箱之间的甲板缝 → 不命中 ----
	# 相邻两格的格心连线中点，就是截图里红框那一类位置：
	# 它落在两个屏幕 AABB 的接壤处（旧规则下必然被吞），但模型上真的是空的。
	var seam_tested := 0
	var seam_clean := 0
	var two: Node3D = plots[1]
	var c1: Vector3 = first.focus_position()
	var c2: Vector3 = two.focus_position()
	for step in 7:
		var t := lerpf(0.42, 0.58, float(step) / 6.0)
		var world := c1.lerp(c2, t)
		var at: Vector2 = main.cam.unproject_position(world)
		# 只在缝确实没有模型覆盖时才计入（土箱外框可能有凸起，属正常命中）。
		var ray_o: Vector3 = main.cam.project_ray_origin(at)
		var ray_d: Vector3 = main.cam.project_ray_normal(at)
		var covered := false
		for p: Node3D in plots:
			if main.hover._ray_visual_t(ray_o, ray_d, p) >= 0.0:
				covered = true
		if covered:
			continue
		seam_tested += 1
		var pick: Dictionary = main.hover._pick(at)
		if pick.is_empty():
			seam_clean += 1
		else:
			printerr("  缝上仍被命中：", at, " -> ", str(pick.get("node")))
	check(seam_tested >= 3, "找到够多的真实缝隙采样点（%d 个）" % seam_tested)
	check(seam_clean == seam_tested,
		"甲板缝上不命中任何交互物，点击归走路（%d/%d）" % [seam_clean, seam_tested])

	# ---- 3. AABB 覆盖、模型不在的空间不命中 ----
	# 沿土箱包围盒的角往外挪一点点：屏幕 AABB 还包着它，三角形早就没了。
	var aabb: AABB = first.visual_aabb()
	var corner := Vector3(aabb.end.x + 0.02, aabb.position.y + aabb.size.y * 0.5, aabb.end.z + 0.02)
	var corner_screen: Vector2 = main.cam.unproject_position(corner)
	var ray_o2: Vector3 = main.cam.project_ray_origin(corner_screen)
	var ray_d2: Vector3 = main.cam.project_ray_normal(corner_screen)
	check(main.hover._ray_visual_t(ray_o2, ray_d2, first) < 0.0,
		"包围盒角外侧的空间没有模型，射线不命中")

	# ---- 4. 走不到的目标仍然不给入口 ----
	var far: Node3D = main.farm_field.find("home_plot")
	if far != null:
		var reason: String = main._land_reach_reason(far)
		if reason != "":
			var far_at: Vector2 = main.cam.unproject_position(far.focus_position() + Vector3.UP * 0.18)
			check(main.hover._pick(far_at).is_empty(), "走不到的目标不出现在命中结果里")
			check(main.hover._pick(far_at, true).get("node") == far, "但仍能查到它，用于说明原因")

	# ---- 5. 点缝之后真的能走路 ----
	var walked := false
	if seam_tested > 0:
		for step2 in 7:
			var t2 := lerpf(0.42, 0.58, float(step2) / 6.0)
			var world2 := c1.lerp(c2, t2)
			var at2: Vector2 = main.cam.unproject_position(world2)
			var ro: Vector3 = main.cam.project_ray_origin(at2)
			var rd: Vector3 = main.cam.project_ray_normal(at2)
			var cov := false
			for p2: Node3D in plots:
				if main.hover._ray_visual_t(ro, rd, p2) >= 0.0:
					cov = true
			if cov:
				continue
			var before: Vector3 = main.player.global_position
			await mouse(at2, true)
			await mouse(at2, false)
			await settle(4)
			if main.actor_controller.walking() or main.player.global_position.distance_to(before) > 0.01:
				walked = true
				break
			if not main.hud.world_actions.is_open():
				# 没弹菜单、也没开始走：可能点在甲板外，继续找下一个点。
				continue
	check(walked, "点甲板缝会触发走向那里（不再被交互物吞掉）")

	print("[pick-mesh] %d checks, %d failures" % [checks, failures])
	quit()
