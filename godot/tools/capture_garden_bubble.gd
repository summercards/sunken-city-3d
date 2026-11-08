extends SceneTree
## 真实渲染：角色头顶招呼气泡的样子（与底部对话框同一张奶白纸面 + 指向头顶的三角）。
##
## 这条只验「气泡画得对不对」：对白内容与触发条件由 `main.gd` 的菜园桥招呼逻辑负责，
## 那边要等豆豆的日程真正落到霓虹花园才接通。这里手动让气泡对着豆豆说一句，
## 拍到的是玩家将来会看到的那张图。

var checks := 0
var failures := 0
var shots: Array[String] = []

func _init() -> void:
	call_deferred("run")

func ok(value: bool, name: String) -> bool:
	checks += 1
	print("[bubble-render] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1
	return value

func shot(label: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not ok(image != null and not image.is_empty(), "真实图像有效 " + label):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	var path := "res://outputs/garden-bubble-" + label + ".png"
	if ok(image.save_png(path) == OK, "保存 " + path):
		shots.append(label)
		print("[bubble-shot] ", path, " ", image.get_width(), "x", image.get_height())

func run() -> void:
	if not ok(DisplayServer.get_name() != "headless", "必须真实渲染，禁止 headless 假通过"):
		_finish()
		return
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("_autosave_on", false)
	main.set_process(false)
	for i in 10:
		await process_frame
	var body = main.npc_world_presenter.actor("npc_mu_he")
	if not ok(is_instance_valid(body), "豆豆的 actor 存在"):
		_finish(); return
	# 把相机摆到豆豆面前，只为了拍到气泡与人物同框。
	main.cam.follow_enabled = false
	main.cam.pose_lock = true
	main.cam.target = body.global_position + Vector3.UP * 1.4
	main.cam.dir = Vector3(0.25, 0.55, 1.0).normalized()
	main.cam.set_distance(9.0)
	main.cam.apply_pose()
	for i in 6:
		await process_frame
	var bubble = main._garden_bubble
	if not ok(bubble != null, "招呼气泡已装配"):
		_finish(); return
	main.cam.apply_pose()
	for i in 4:
		await process_frame
	bubble.speak("这批苗昨天刚抬头，你看这一排叶子，比上周精神多了。", body, main.cam, 120.0)
	for i in 6:
		await process_frame
	ok(bubble.visible and bubble.text() != "", "气泡显示台词")
	ok(bubble.get_global_rect().size.x > 120.0 and bubble.get_global_rect().size.y > 40.0, "气泡有实际尺寸")
	ok(root.get_visible_rect().encloses(bubble.get_global_rect()), "气泡完整在视口内")
	# 尾巴尖必须在气泡底边中点附近，且在角色头部的水平范围内 —— 否则「指向谁」就不成立。
	var head: Vector3 = body.global_position + Vector3.UP * 2.06
	var head_screen: Vector2 = main.cam.unproject_position(head)
	var tail: Vector2 = Vector2(bubble.get_global_rect().get_center().x,
		bubble.get_global_rect().end.y)
	ok(absf(tail.x - head_screen.x) < 90.0 and tail.y < head_screen.y + 20.0,
		"尾巴指向角色头顶（尾 %.0f,%.0f / 头 %.0f,%.0f）" % [tail.x, tail.y, head_screen.x, head_screen.y])
	await shot("single")
	# 换一句更长的，检查换行后仍然在屏内、尾巴仍然指人。
	bubble.speak("我留了一小块土给小花，她说想种点会开花的；你要是路过花店，帮我说一声土已经翻好了。",
		body, main.cam, 120.0)
	for i in 6:
		await process_frame
	ok(root.get_visible_rect().encloses(bubble.get_global_rect()), "长句换行后仍在视口内")
	await shot("long")
	# 玩家真实距离：站在 32 米触发半径的边缘（船上）抬头看。
	# 气泡是屏幕空间固定像素，所以远近不改变它的大小 —— 这一张验的就是
	# 「远处能不能读」这件事本身，以及气泡会不会大过人本身变得滑稽。
	main.cam.set_distance(30.0)
	main.cam.apply_pose()
	for i in 6:
		await process_frame
	bubble.speak("这批苗昨天刚抬头，你看这一排叶子，比上周精神多了。", body, main.cam, 120.0)
	for i in 6:
		await process_frame
	ok(root.get_visible_rect().encloses(bubble.get_global_rect()), "32 米外气泡仍在视口内")
	var head_far: Vector2 = main.cam.unproject_position(body.global_position + Vector3.UP * 2.06)
	var rect: Rect2 = bubble.get_global_rect()
	ok(absf(rect.get_center().x - head_far.x) < 120.0, "32 米外尾巴仍指着头顶")
	await shot("far")
	# 小窗口：1280×800 下气泡不能顶满屏。
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	for i in 8:
		await process_frame
	bubble.speak("我留了一小块土给小花，她说想种点会开花的；你要是路过花店，帮我说一声土已经翻好了。",
		body, main.cam, 120.0)
	for i in 6:
		await process_frame
	ok(root.get_visible_rect().encloses(bubble.get_global_rect()), "1280×800 下长句气泡不越界")
	ok(bubble.get_global_rect().size.x < root.get_visible_rect().size.x * 0.62,
		"1280×800 下气泡宽度不超过屏宽六成（实测 %.0f）" % bubble.get_global_rect().size.x)
	await shot("small")
	bubble.dismiss()
	await process_frame
	ok(not bubble.visible, "说完可收起")
	print("[bubble-render] %d checks, %d failures" % [checks, failures])
	_finish()

func _finish() -> void:
	await process_frame
	quit(0 if failures == 0 else 1)
