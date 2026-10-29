extends SceneTree
## 拾取进度条的真实渲染证据：挂在角色头顶、白天夜里都看得见。
##
## 逻辑断言在 `tools/check_progress_bars.gd` 里（无渲染、快）。
## 这里只负责出图 + 复核"画面上真的看得见"。
##
## 为什么要专门拍夜景：主人报"看不到进度条"的那张截图就是夜里 ——
## 深色水面上一条低对比的细线，肉眼看图很容易自我说服"应该有吧"。
## 所以"看得见"不靠肉眼：同一帧拍两次（条显示 / 条隐藏），
## 只比对条所在矩形，必须真有像素变化，白天和夜里各验一次。

var main: Node
var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func ok(value: bool, name: String) -> void:
	checks += 1
	print("[pickup-progress] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1


## 镜头对准角色所在的那条船（真实玩法里 cam 就是这么跟着角色的）。
func aim_at(subject: Vector3, distance: float, dir := Vector3(-0.45, 0.66, 0.60)) -> void:
	main.cam.target = subject
	main.cam.distance = distance
	main.cam.orbit_dir = dir
	main.cam.refresh()


func grab() -> Image:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func save(img: Image, label: String) -> void:
	img.save_png("res://outputs/pickup-progress-" + label + ".png")


## 条所在屏幕矩形。
##
## 注意坐标空间：Control 的位置在**画布坐标**（1600×1000，`stretch/mode=canvas_items`），
## 而抓下来的图是**窗口像素**（1280×800）。必须过 `get_screen_transform()`
## 换算，否则会去比对一块完全错位的水面，得出"什么都没画"的假结论。
func bar_rect() -> Rect2i:
	var bar = main.pickup_progress.bar
	var xf: Transform2D = root.get_screen_transform()
	var a: Vector2 = xf * bar.position
	var b: Vector2 = xf * (bar.position + bar.size)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2i(Vector2i(lo.floor()), Vector2i((hi - lo).ceil()))


## 两张图在指定矩形内的差异像素数（任一通道差 > 24 才算）。
func diff_count(a: Image, b: Image, rect: Rect2i) -> int:
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var x0 := clampi(rect.position.x, 0, w - 1)
	var y0 := clampi(rect.position.y, 0, h - 1)
	var x1 := clampi(rect.position.x + rect.size.x, 0, w)
	var y1 := clampi(rect.position.y + rect.size.y, 0, h)
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) * 255.0 > 24.0 \
				or absf(ca.g - cb.g) * 255.0 > 24.0 \
				or absf(ca.b - cb.b) * 255.0 > 24.0:
				n += 1
	return n


## 在当前机位下验证"条真的画出来了"，并出图。
##
## 拍两张只差 bar.visible 的帧，比对条所在矩形：
## 没有像素变化就等于没画（哪怕 visible 打印出来是 true）。
func prove_and_save(label: String) -> void:
	var with_bar := await grab()
	var rect := bar_rect()
	main.pickup_progress.bar.visible = false
	var without_bar := await grab()
	main.pickup_progress.bar.visible = true

	ok(rect.size.y <= 8, "%s：条在窗口里只有 %d px 高" % [label, rect.size.y])
	var changed := diff_count(with_bar, without_bar, rect)
	ok(changed > 60, "%s：条真的画出来了（条区域 %d px 随显隐变化）" % [label, changed])
	save(with_bar, label)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	main.set_process(false)
	main.props.set_process(false)
	main.boat.set_process(false)
	main.ribbon.hide()
	main.cam.suspend_follow()
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	await process_frame

	# 一、航行段：船还在朝浮木划，**此时不该有任何进度条**。
	#    这是主人这次反馈的核心，先出图留证。
	var crate: Dictionary = main.props.crates[0]
	var goal: Vector3 = crate.base + Vector3(1.4, 0.0, 0.0)
	# 找一个**开阔水面**的起点：固定往 -x 让 16 米可能正好落进岸上的房子，
	# 拍出来的图只有屋顶、看不到船，这种证据没法用。
	var far := goal
	for dir in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]:
		for dist in [16.0, 13.0, 20.0]:
			var p: Vector3 = goal + dir * dist
			if main.navigation.is_open_water(p.x, p.z):
				far = p
				break
		if far != goal:
			break
	main.boat.place_at(far, 0.0)
	main.boat.sail_to(goal, 0.0, "", "manual",
		[Vector2(far.x, far.z), Vector2(goal.x, goal.z)])
	main._begin_pick_sail({"type": "crate", "item": crate})
	var bar = main.pickup_progress.bar
	# 航行段的机位抬陡一点：船离岸较远时，平视机位容易把相机塞进房子。
	aim_at(main.player.global_position, 22.0, Vector3(-0.30, 1.05, 0.42))
	main._update_pickup_progress(1.0 / 60.0)
	ok(main.boat.starts_sailing(), "航行中（还剩 %.1f 米）" % main.boat.remaining_distance())
	ok(not bar.visible, "航行段：条不可见（人还没开始捞）")
	save(await grab(), "sailing")

	# 二、停稳 → 打捞：条从 0 出现。推进半程拿一张有内容的图。
	var wood_before: int = root.get_node("Economy").count("wood")
	main.boat.place_at(goal, 0.0)
	main._update_pickup_progress(0.0)
	ok(main._pick_phase == main.PICK_PHASE_GATHERING, "停稳后进入打捞阶段")
	ok(bar.visible and bar.ratio <= 0.01, "打捞一开始条就出现且从零起步")
	for i in 36:
		main._update_pickup_progress(1.0 / 60.0)
	ok(bar.ratio > 0.3 and bar.ratio < 0.7, "半程时比例在 0.3–0.7（实测 %.2f）" % bar.ratio)
	ok(root.get_node("Economy").count("wood") == wood_before, "打捞途中还没进账")
	ok(main.pickup_progress.subject == main.player, "挂点是角色，不是目标")

	# 取景：把角色和它头顶的条一起框进来。
	aim_at(main.player.global_position, 14.0)
	main.pickup_progress.refresh()
	await prove_and_save("day")

	# 三、夜景：主人报"看不到进度条"的那张截图就是夜里。
	main.world_clock.from_dict({"day": 1, "seconds": 21.0 * 3600.0, "day_length": 1200.0})
	main.daylight_rig.apply(21.0)
	await process_frame
	main.pickup_progress.refresh()
	await prove_and_save("night")

	# 四、夜景 + 航行：确认夜里航行段同样干净。
	main.boat.place_at(goal + Vector3(26.0, 0.0, 0.0), 0.0)
	main.boat.sail_to(goal, 0.0, "", "manual",
		[Vector2(main.boat.position.x, main.boat.position.z), Vector2(goal.x, goal.z)])
	main._begin_pick_sail({"type": "crate", "item": crate})
	main._update_pickup_progress(1.0 / 60.0)
	ok(not bar.visible, "夜里航行段：条不可见（还剩 %.1f 米）" % main.boat.remaining_distance())
	aim_at(main.player.global_position, 30.0)
	await grab()
	save(await grab(), "sailing-night")

	print("[pickup-progress] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
