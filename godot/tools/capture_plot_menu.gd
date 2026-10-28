extends SceneTree
## 种植二级菜单真实输入证据：开一级气泡 → 用真实鼠标事件点「种植」→ 看二级是否弹出。
## 运行：python scripts/run_verification.py visual-plot-menu
var main: Node
var failures := 0

func _init() -> void: call_deferred("run")

func click_at(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await process_frame

func shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[plot-menu] ", path)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	main.title_camera.begin(main.cam)
	main.title_camera.finish(main.cam)
	var economy: Node = root.get_node("Economy")
	economy.inventory.clear()
	economy.give({"lettuce_seed": 3, "tomato_seed": 2, "pumpkin_seed": 1})
	var cell: Node3D = main.farm_field.find("home_plot")
	main.actor_controller.disembark.execute(main.actor_controller, main._current_landing().stand_position())
	main.actor_controller.reconcile_mode(0)
	main.cam.suspend_follow()
	main.player.global_position = cell.global_position + Vector3(0.4,0,1.6)
	main.cam.target = cell.global_position + Vector3.UP * 0.6
	main.cam.distance = 20.0
	main.cam.orbit_dir = Vector3(-0.5, 0.7, 0.5)
	main.cam.refresh()
	for i in 30: await process_frame
	main._open_spot_bubbles(cell)
	await shot("res://outputs/plot-menu-1.png")
	var wa = main.hud.world_actions
	var ids: Array = []
	for e in wa.entries: ids.append(str(e.get("id")))
	print("[plot-menu] level1 entries=", ids, " buttons=", wa.buttons.size())
	if wa.buttons.is_empty():
		print("[plot-menu] FAIL no level1 buttons")
		failures += 1
	else:
		# 入场补间 0.24s：先等它站稳再取中心，否则取到的是 (-38,-38) 的起始点。
		for i in 24: await process_frame
		var b: Button = wa.buttons[0]
		var center: Vector2 = b.get_global_rect().get_center()
		# 工程是 1600x1000 画布、窗口 1280x800（canvas_items 拉伸）：
		# Control 的坐标属于画布，`Input.parse_input_event` 收的是窗口坐标，必须换算。
		var canvas := root.get_visible_rect().size
		var window := Vector2(DisplayServer.window_get_size())
		var point := center * (window / canvas)
		print("[plot-menu] plant button canvas=", center, " window=", point)
		await click_at(point)
		var ids2: Array = []
		for e in wa.entries: ids2.append(str(e.get("id")))
		print("[plot-menu] level2 entries=", ids2, " open=", wa.is_open())
		if ids2.size() < 2 or not str(ids2[0]).begins_with("seed:"):
			print("[plot-menu] FAIL level2 seed picker missing")
			failures += 1
		await shot("res://outputs/plot-menu-2.png")
	print("[plot-menu] failures=", failures)
	main.queue_free()
	await process_frame
	print("[visual-plot-menu] complete")
	quit(0)
