extends "res://tools/capture_farm_cycle.gd"
## 航线水纹的实拍。
##
## 目的很窄：确认那条横穿海面的虚线确实没了，落点改成贴浪的扩散波纹，
## 并且波纹本身读得出「水被点了一下」。不写玩家存档；输出到 res://outputs/。
##
## 落点固定在**屏幕正中**：直接拿视口中心当点击坐标，_world_point 把它反投到水面，
## 波纹就一定落在画面中心。早先按世界坐标反算屏幕位置，算出来偏了 200 多像素，
## 裁切全裁在空水上 —— 这不是 shader 的问题，是取景的坑。

const SCREEN_CENTER := Vector2(640, 400)


## 船周围找一块开阔水当取景中心，离岸远一点，水纹才不会被码头的深色阴影吃掉。
func open_water_near(dist: float) -> Vector3:
	var base: Vector3 = main.boat.global_position
	for step in 32:
		var a := float(step) * TAU / 32.0
		var p := base + Vector3(cos(a), 0, sin(a)) * dist
		if main._is_open_water(p.x, p.z):
			return Vector3(p.x, 1.12, p.z)
	return base + Vector3(0, 0, -dist)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	economy = root.get_node("Economy")
	economy.ticking = false
	var state: Node = root.get_node("GameState")
	state.enter_zone("zone1")
	main._select_landing({"zone": "zone1", "landing": "main", "name": "主泊位"})
	await settle(90)
	# 截图要干净的水面：调色室面板会正好盖住画面中心。
	if main.grade != null:
		main.grade.visible = false
	main.hud.hide()
	main.markers.hide()

	# 相机用**默认游戏视距**（orbit_camera.distance=54.25、FOV 31°），不是特写。
	# 特写只能证明 shader 画得出圈，证明不了玩家在正常视角里看得见 ——
	# 这个坑本轮踩过：距离 7.5 时水纹占满画面，看起来很好；回到 54 就只剩一小撮。
	main.cam.target = open_water_near(7.0)
	main.cam._apply()
	await settle(12)

	var ok: bool = main._try_sail_to(SCREEN_CENTER)
	check(ok, "点水面出航")
	# _depart 是异步的：上船动作走完后才铺目标水纹。
	for i in 180:
		await process_frame
		if main.ribbon != null and main.ribbon.visible:
			break

	# 航线虚线已经整条去掉：屏幕上不该再有航路段。
	var bands: int = 0
	if main.ribbon != null and main.ribbon.has_method("debug_band_count"):
		bands = main.ribbon.debug_band_count()
	check(bands == 0, "航线不再铺虚线段")
	check(main.ribbon != null and main.ribbon.visible, "目标水纹在播")

	# 相机重新对准水纹本体：路径末点会被寻路网格吸附，和点击点差几十厘米，
	# 不重新取景的话截图里波纹就偏到画面角上，人工核对时找不到。
	if main.ribbon != null and main.ribbon.visible:
		main.cam.target = main.ribbon.global_position
		main.cam._apply()
		await settle(4)

	# 三个相位：刚起手 / 推到一半 / 快散尽。只看一帧判断不了「像不像水」，
	# 尤其最难判的是「三道圈是不是一样粗、一样亮」。
	await settle(6)
	await shot("route-ripple-a")
	await settle(16)
	await shot("route-ripple-b")
	await settle(26)
	await shot("route-ripple-c")
	# 2s 后：点击那一下已散尽，只剩目标点在原地轻轻荡。
	await settle(70)
	await shot("route-ripple-target")

	print("[route-ripple] checks done, failures=%d" % failures)
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
