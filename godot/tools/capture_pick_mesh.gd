extends SceneTree
## 取证：同一机位各点一次「土箱本体」和「土箱之间的甲板缝」。
## 前者应弹操作菜单，后者应开始走路 —— 热区按模型算之后缝不再是土箱的地盘。

var main
var failures := 0


func _init() -> void:
	call_deferred("run")


func settle(n := 8) -> void:
	for i in n: await process_frame


func shot(name: String) -> void:
	await settle(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/pickmesh-" + name + ".png")
	print("[shot] ", name, " walking=", main.actor_controller.walking(),
		" bubbles=", main.hud.world_actions.is_open(),
		" player=", main.player.global_position)


func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await settle(2)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode": 0, "player": [21.0, 1.48, 16.0]})
	root.get_node("GameState").enter_zone("zone5")
	await settle(30)
	# 俯视整片平台：六格土箱与它们之间的缝都在画面里。
	main.cam.target = Vector3(22.0, 1.48, 16.0)
	main.cam.distance = 9.0
	main.cam._apply()
	await settle(14)
	await shot("1-overview")

	var plots: Array = []
	for i in 6:
		var node: Node3D = main.farm_field.find("platform_plot" if i == 0 else "platform_plot:%d" % i)
		if node != null: plots.append(node)
	print("[shot] plots=", plots.size())

	# 1) 点土箱本体：找屏幕上真被模型覆盖的一点。
	var first: Node3D = plots[0]
	var box: Rect2 = main.hover._screen_bounds(first)
	var body_at := Vector2.ZERO
	var found := false
	for gy in range(8):
		for gx in range(8):
			var at := box.position + Vector2(box.size.x * (gx + 0.5) / 8.0, box.size.y * (gy + 0.5) / 8.0)
			if main.hover._ray_visual_t(main.cam.project_ray_origin(at), main.cam.project_ray_normal(at), first) >= 0.0:
				body_at = at; found = true; break
		if found: break
	print("[shot] body point=", body_at, " hit=", found)
	if found:
		await click_at(body_at)
		await settle(4)
		await shot("2-body-click")
		main.hud.world_actions.close(true)
		main.actor_controller.cancel()
		await settle(4)

	# 2) 点两格之间的甲板缝：应开始走路，不弹菜单。
	var c1: Vector3 = plots[0].focus_position()
	var c2: Vector3 = plots[1].focus_position()
	var seam_at := Vector2.ZERO
	var seam_found := false
	for step in 9:
		var t := lerpf(0.40, 0.60, float(step) / 8.0)
		var at: Vector2 = main.cam.unproject_position(c1.lerp(c2, t))
		var ro: Vector3 = main.cam.project_ray_origin(at)
		var rd: Vector3 = main.cam.project_ray_normal(at)
		var covered := false
		for p: Node3D in plots:
			if main.hover._ray_visual_t(ro, rd, p) >= 0.0: covered = true
		if covered: continue
		seam_at = at; seam_found = true; break
	print("[shot] seam point=", seam_at, " found=", seam_found,
		" pick=", "" if main.hover._pick(seam_at).is_empty() else str(main.hover._pick(seam_at).get("node")))
	if seam_found:
		await click_at(seam_at)
		await settle(3)
		await shot("3-seam-click")
		for i in 60:
			main.actor_controller.tick(1.0 / 60.0)
		await shot("4-seam-walking")
		for i in 240:
			main.actor_controller.tick(1.0 / 60.0)
		await shot("5-seam-arrived")
	print("[shot] done failures=", failures)
	quit()
