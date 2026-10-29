extends SceneTree
## 走不到的地方，不给操作入口。
##
## 2026-10-29 用户两次反馈的最终结论：
##
##   第一次：「到达不了的区域，可交互物体点不出子菜单」—— 想要的是**有反馈**；
##   第二次（带图）：「人在这边、走路过不去，点另一个平台，应该点不出这个菜单」——
##   要的是**别给入口**。
##
## 两条合起来才成立：不给菜单、不给悬浮图标、不改指针，但点击要有一句话说明。
## 上一版把菜单照弹、每项涂灰写原因，玩家的原话是「这菜单不该出现」。
##
## 本测试锁死：
##   1. 走不到的目标：悬停不命中（无图标）、点击不弹菜单、给一句原因；
##   2. 够得着的目标：点物体本体（不是那颗小图标）就弹菜单，种植走二级选种子；
##   3. 巨型包围盒不许吃掉甲板，否则点击甲板会被判成点箱子、再也走不了路。

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


## 在 `screen_rect` 里采样，找出一点真的被 `spot` 模型覆盖——
## 优先挑离 `far_from` 最远的那个。命中靠射线打三角形，屏幕矩形的角通常是空的。
func body_on_screen(main: Node, spot: Node3D, screen_rect: Rect2, far_from: Vector2) -> Vector2:
	var best := screen_rect.get_center()
	var best_distance := -1.0
	for gy in range(8):
		for gx in range(8):
			var at := screen_rect.position + Vector2(
				screen_rect.size.x * (gx + 0.5) / 8.0, screen_rect.size.y * (gy + 0.5) / 8.0)
			var ray_o: Vector3 = main.cam.project_ray_origin(at)
			var ray_d: Vector3 = main.cam.project_ray_normal(at)
			if main.hover._ray_visual_t(ray_o, ray_d, spot) < 0.0:
				continue
			var d := at.distance_to(far_from)
			if d > best_distance:
				best_distance = d
				best = at
	return best


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	main._select_landing({"zone": "zone1", "landing": "main", "name": "主泊位"})
	await settle(40)

	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	# 截图那一带的机位：人在码头，右边水上平台在视口边缘。
	main.cam.target = Vector3(6.0, 1.0, 12.0)
	main.cam.distance = 20.0
	main.cam._apply()
	await settle(12)

	var box: Node3D = main._zone_nodes.zone1.get_node("Objects/ShippingBox")
	var plot: Node3D = main.farm_field.find("home_plot")
	var far: Node3D = main.farm_field.find("platform_plot")
	check(box != null and plot != null and far != null, "找到出货箱、木屋菜箱与水上平台地格")
	if box == null or plot == null or far == null:
		print("[unreachable-menu] %d checks, %d failures" % [checks, failures])
		quit()
		return

	# ---- 1. 走不到的目标：不给入口 ----
	var far_reason: String = main._land_reach_reason(far)
	check(far_reason != "", "跨区目标判定为走不到（实际：%s）" % far_reason)
	var far_point: Vector2 = main.hover._clamp_to_viewport(
		main.cam.unproject_position(far.focus_position() + Vector3.UP * 0.18))

	main.hover.update_hover(far_point)
	check(main.hover.target.is_empty(), "走不到的目标不出现悬浮图标（悬停层直接判空）")
	check(main.hover._pick(far_point).is_empty(), "默认命中不返回走不到的目标")

	# 点击时仍要查一次，只为了说句话
	var barred: Dictionary = main.hover._pick(far_point, true)
	check(barred.get("node") == far, "点击时仍能查到那颗目标（为了给出原因）")
	check(str(barred.get("barred", "")) == far_reason, "查询结果带着同一个原因")

	await mouse(far_point, true)
	await mouse(far_point, false)
	await settle(6)
	check(not main.hud.world_actions.is_open(), "点走不到的目标不弹操作菜单")
	check(str(main.hud.toast_snapshot().text) == far_reason,
		"改为一句原因提示（实际：%s）" % str(main.hud.toast_snapshot().text))
	if DisplayServer.get_name() != "headless":
		await settle(10)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/unreachable-menu.png")

	# ---- 2. 够得着的目标：点本体就算命中 ----
	# 现在命中靠射线打模型三角形，所以要找「屏幕包围盒里真被模型覆盖」的一点，
	# 而不是包围盒的几何角 —— 角上往往已经是空的。
	var body: Rect2 = main.hover._screen_bounds(box)
	check(body.size.x > 4.0 and body.size.y > 4.0, "出货箱有屏幕包围盒（%s）" % str(body.size))
	if body.size.x > 4.0:
		var icon: Vector2 = main.hover._clamp_to_viewport(
			main.cam.unproject_position(box.focus_position() + Vector3.UP * 0.75))
		var on_body: Vector2 = body_on_screen(main, box, body, icon)
		var gap := on_body.distance_to(icon)
		print("[unreachable-menu] box body=", body, " icon=", icon, " body point gap=%.0f px" % gap)
		check(gap > 30.0, "取到的本体点离图标超过 30 像素（旧规则必然落空，实际 %.0f）" % gap)
		check(main.hover._pick(on_body).get("node") == box, "点在箱体身上就算命中，不要求点中图标")

		await mouse(on_body, true)
		await mouse(on_body, false)
		await settle(6)
		check(main.hud.world_actions.is_open(), "点击箱体弹出操作菜单")
		await settle(30)
		check(main.hud.world_actions.is_open(), "菜单不会自己消失")
		main.hud.world_actions.close(true)
		await settle(4)

	# ---- 3. 菜箱 → 种植 → 二级选种子 ----
	var plot_point: Vector2 = body_on_screen(main, plot, main.hover._screen_bounds(plot), Vector2.ZERO)
	check(main._land_reach_reason(plot) == "", "木屋菜箱在可达范围内")
	await mouse(plot_point, true)
	await mouse(plot_point, false)
	await settle(6)
	check(main.hud.world_actions.is_open(), "点击菜箱弹出操作菜单")
	var plant_index := -1
	for i in main.hud.world_actions.entries.size():
		if str(main.hud.world_actions.entries[i].get("id", "")) == "plant":
			plant_index = i
	check(plant_index >= 0, "菜箱菜单里有「种植」一项")
	if plant_index >= 0:
		var button: Button = main.hud.world_actions.buttons[plant_index]
		var at: Vector2 = button.get_global_rect().get_center()
		await mouse(at, true)
		await mouse(at, false)
		await settle(8)
		check(main.hud.world_actions.is_open(), "选「种植」弹出选种子的二级菜单")
		check(main.hud.world_actions.entries.size() > 0,
			"二级菜单列出持有的种子（%d 项）" % main.hud.world_actions.entries.size())
		check(main.hud.world_actions.hint_label != null
			and main.hud.world_actions.hint_label.text.contains("种子"),
			"二级菜单有层级标题")
		main.hud.world_actions.close(true)
	await settle(4)

	# ---- 4. 铺在地上的大平面：只有真正压到模型才算命中 ----
	# 这一条替代了旧的「AABB 面积超过视口 12% 就不参与命中」。
	# 现在命中的是射线与三角形的交点，所以大平面本身没问题 ——
	# 关键是它**只占模型所在的位置**，不再靠外扩的矩形去猜。
	# 这也正是用户截图那条「土箱之间的缝点不到地面」的根因修法。
	var huge := preload("res://src/interaction/interactable.gd").new()
	huge.name = "HugeProbe"
	huge.id = "huge_probe"
	var body_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	body_node.mesh = plane
	body_node.name = "Visual"
	huge.add_child(body_node)
	main.add_child(huge)
	huge.global_position = plot.global_position
	await settle(3)
	var center_screen: Vector2 = main.cam.unproject_position(plot.global_position)
	var ray_o: Vector3 = main.cam.project_ray_origin(center_screen)
	var ray_d: Vector3 = main.cam.project_ray_normal(center_screen)
	check(main.hover._ray_visual_t(ray_o, ray_d, huge) >= 0.0, "射线能打到铺地平面本体")
	# 平面外侧一点点：屏幕 AABB 可能还压着，但模型上没有东西。
	var outside: Vector3 = plot.global_position + Vector3(2.6, 0.0, 0.0)
	var out_screen: Vector2 = main.cam.unproject_position(outside)
	check(main.hover._ray_visual_t(main.cam.project_ray_origin(out_screen),
		main.cam.project_ray_normal(out_screen), huge) < 0.0,
		"平面外的空间不命中（不再靠外扩矩形猜）")
	check(main.hover._pick(out_screen).get("node") != huge, "平面外的点击不会落到这个交互物上")
	huge.queue_free()
	await settle(2)

	# ---- 5. 真走到失败的路径，接近也要说话 ----
	var probe := preload("res://src/interaction/interactable.gd").new()
	probe.name = "ReachProbe"
	probe.id = "reach_probe"
	probe.label = "测试点"
	probe.verb = "查看"
	main.add_child(probe)
	probe.global_position = Vector3(60.0, 1.3, 60.0)
	await settle(2)
	var before2: String = str(main.hud.toast_snapshot().text)
	var moved: bool = main._approach(probe)
	await settle(4)
	var after2: String = str(main.hud.toast_snapshot().text)
	check(not moved, "走不到的目标不会开始行走")
	check(after2 != before2 and after2 != "", "接近被拒时给出提示，而不是静默返回（实际：%s）" % after2)
	probe.queue_free()

	print("[unreachable-menu] %d checks, %d failures" % [checks, failures])
	quit()
