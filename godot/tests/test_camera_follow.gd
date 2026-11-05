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
	# SEA-CAMERA-R11：玩家能拉到的最远就是 38 m，开局就停在这一档（比例 100%）。
	check(is_equal_approx(cam.zoom_max,38.0),"缩放上限38")
	check(is_equal_approx(cam.distance,38.0),"开局=最远38")
	check(absf(cam.zoom_ratio()-1.0)<.001,"开局即最远")
	check(cam.follow_enabled and cam.follow_subject==main.player,"默认跟随角色")
	cam._process(.1)
	check(cam.target.distance_to(main.player.global_position+Vector3.UP*.7)<.001,"跟随世界坐标")
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
	# 连续往外滚：被 zoom_max 钉在 38 m，拉不出更远的画面。
	cam.suspend_follow()
	for i in 12:
		cam.zoom_action.execute(cam,1.0/0.86,Vector2(500,400))
	cam._process(.2)
	check(absf(cam.distance-38.0)<.001 and absf(cam._cur_distance-38.0)<.001,"滚轮拉不出38m")
	print("[camera-follow] 11 checks, failures=",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
