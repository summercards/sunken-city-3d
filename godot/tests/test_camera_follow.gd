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
	# SEA-CAMERA-R11（2026-11-05 修订）：主人指认截图那一档就是最远 = 77.8 m，
	# 也就是旧区间 9~190 m 的 38%（9+0.38×181）。开局仍是原来的 54.25 m。
	check(is_equal_approx(cam.zoom_max,77.8),"缩放上限77.8")
	check(is_equal_approx(cam.distance,54.25),"开局54.25")
	check(absf(cam.zoom_ratio()-(54.25-9.0)/(77.8-9.0))<.001,"开局比例%.3f"%cam.zoom_ratio())
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
	# 连续往外滚：被 zoom_max 钉在 77.8 m（主人截图的取景），拉不出更远的画面。
	cam.suspend_follow()
	for i in 12:
		cam.zoom_action.execute(cam,1.0/0.86,Vector2(500,400))
	cam._process(.2)
	# 平滑要收敛：ZOOM_DAMP=9，0.2 s 只走 83%，单帧不够。
	for i in 12:
		cam._process(0.1)
	check(absf(cam.distance-77.8)<.001 and absf(cam._cur_distance-77.8)<.05,"滚轮停在77.8m 实际=%.2f/%.2f"%[cam.distance,cam._cur_distance])
	# 往里仍能到 9 m，说明收紧上限没把缩放整体压死。
	for i in 24:
		cam.zoom_action.execute(cam,0.86,Vector2(500,400))
	for i in 12:
		cam._process(0.1)
	check(absf(cam.distance-9.0)<.001,"内侧仍到9m 实际=%.2f"%cam.distance)
	print("[camera-follow] 12 checks, failures=",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
