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
	# Outdoor bounds change; the reference scale and base optics do not.
	check(absf(cam.zoom_max-29.0)<.001,"outdoor zoom maximum")
	check(absf(cam.zoom_min-13.82)<.001,"outdoor zoom minimum")
	check(absf(cam.distance-16.8)<.001,"outdoor starting distance")
	check(absf(cam.zoom_ratio()-(16.8-9.0)/(77.8-9.0))<.001,"unchanged reference scale")
	check(cam.projection == Camera3D.PROJECTION_PERSPECTIVE and cam.keep_aspect == Camera3D.KEEP_HEIGHT and is_equal_approx(cam.fov, 46.0) and is_equal_approx(cam.near, 0.5), "outdoor perspective and vertical FOV")
	var base := OrbitCam.new()
	root.add_child(base)
	check(is_equal_approx(base.fov,31.0) and is_equal_approx(base.distance,27.9) and is_equal_approx(base.zoom_max,35.14), "unconfigured camera keeps base defaults")
	base.queue_free()
	var saved_distance: float = cam.distance
	cam.orbit_only = true
	cam.refresh()
	check(is_equal_approx(cam.fov,31.0), "interior lens unchanged")
	cam.orbit_only = false
	cam.pose_lock = true
	cam.refresh()
	check(is_equal_approx(cam.fov,31.0), "locked lens unchanged")
	cam.pose_lock = false
	cam.distance = saved_distance
	cam.refresh()
	check(is_equal_approx(cam.fov,46.0) and is_equal_approx(cam.distance,saved_distance), "restore to the outdoor lens and saved distance")
	check(main.player.get_parent() == main.boat and cam.follow_enabled and cam.follow_subject == main.boat, "跳过开场的船上夹具默认跟随船")
	cam._process(.1)
	check(cam.target.distance_to(main.boat.global_position+Vector3.UP*main.BodyScale.CAMERA_FOCUS)<.001,"跟随船体世界坐标 aim=%.3fm"%main.BodyScale.CAMERA_FOCUS)
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
	# 连续往外滚停在场景自己的上限。
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
	print("[camera-follow] 19 checks, failures=",failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
