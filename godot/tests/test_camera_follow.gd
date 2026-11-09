extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var cam: Node = main.cam
	# SEA-CAMERA-R11（2026-11-09 修订）：主人指认「最远 = 视野 38%」「最近 = 视野 7%」，
	# 百分比刻度沿用 9–77.8 的参照区间，反解得 35.14 m 与 13.82 m。
	# 开局 54.25 已超出新上限，重取新区间的 66%（=27.9，与旧值同一百分比档）。
	check(absf(cam.zoom_max-35.14)<.001,"缩放上限35.14 实际=%.2f"%cam.zoom_max)
	check(absf(cam.zoom_min-13.82)<.001,"缩放下限13.82 实际=%.2f"%cam.zoom_min)
	check(absf(cam.distance-27.9)<.001,"开局27.9（两端之间）实际=%.2f"%cam.distance)
	check(absf(cam.zoom_ratio()-0.275)<.01,"开局读作 27.5%% 实际=%.3f"%cam.zoom_ratio())
	check(cam.follow_enabled and cam.follow_subject==main.player,"默认跟随角色")
	cam._process(.1)
	check(cam.target.distance_to(main.player.global_position+Vector3.UP*main.BodyScale.CAMERA_FOCUS)<.001,"跟随世界坐标 aim=%.3fm"%main.BodyScale.CAMERA_FOCUS)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = Vector2(500,400)
	e.pressed = true
	cam._unhandled_input(e)
	e.pressed = false
	cam._unhandled_input(e)
	check(cam.follow_enabled,"点击不取消跟随")
	cam._begin_pan(Vector2(500,400))
	cam._drag_pan(Vector2(600,400))
	cam._end_drag()
	check(not cam.follow_enabled,"拖动接管")
	var manual: Vector3 = cam.target
	cam._process(.1)
	check(cam.target.distance_to(manual)<.001,"松手不抢回镜头")
	main._on_click_command("follow")
	check(cam.follow_enabled,"按钮恢复跟随")
	var outputs: Array[Vector3] = []
	cam.suspend_follow()
	for fps in [30,60,120]:
		cam.target = Vector3.ZERO
		cam._apply()
		cam.target = Vector3(10,0,0)
		for i in fps: cam._process(1.0/fps)
		outputs.append(cam._cur_target)
	check(outputs[0].distance_to(outputs[2])<.001,"阻尼帧率一致")
	# 连续往外滚：被 zoom_max 钉在 35.14 m（主人截图那一档），拉不出更远的画面。
	cam.suspend_follow()
	for i in 12:
		cam.zoom_action.execute(cam,1.0/0.86,Vector2(500,400))
	cam._process(.2)
	# 平滑要收敛：ZOOM_DAMP=9，0.2 s 只走 83%，单帧不够。
	for i in 12:
		cam._process(0.1)
	check(absf(cam.distance-cam.zoom_max)<.001 and absf(cam._cur_distance-cam.zoom_max)<.05,"滚轮停在上限 实际=%.2f/%.2f"%[cam.distance,cam._cur_distance])
	# 往里能到 13.82 m，读数停在 7% —— 与主人给的第二张图一致。
	for i in 24:
		cam.zoom_action.execute(cam,0.86,Vector2(500,400))
	for i in 12:
		cam._process(0.1)
	check(absf(cam.distance-cam.zoom_min)<.001,"内侧停在下限 实际=%.2f"%cam.distance)
	check(absf(cam.zoom_ratio()-0.07)<.01,"最近读作 7%% 实际=%.3f"%cam.zoom_ratio())
	print("[camera-follow] 14 checks, failures=",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
