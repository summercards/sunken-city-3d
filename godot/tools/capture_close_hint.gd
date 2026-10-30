extends SceneTree
## 右下角关闭键的真实渲染证据（SEA-UI-R47）。
## 运行：python scripts/run_verification.py visual-close-hint
##
## 只拍两张：面板打开时的全画面（证明它贴在屏幕右下角、不是贴在卡片上），
## 以及右下角的近景（看清圆片、描边、粗叉和那一点倾斜）。
var main: Node
var failures := 0
var checks := 0


func _init() -> void:
	call_deferred("run")


func ok(value: bool, name: String) -> void:
	checks += 1
	print("[close-hint-render] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("_autosave_on", false)
	await frames(12)
	main.hud.open_tab("bag")
	await frames(20)
	var hints: Control = main.hud._hints
	ok(hints.visible, "面板打开时关闭键可见")
	var box: Rect2 = hints.get_global_rect()
	var view: Vector2 = main.hud._root.size
	ok(view.x - box.end.x < 60.0 and view.y - box.end.y < 60.0, "关闭键贴住右下角")
	await RenderingServer.frame_post_draw
	var full := root.get_texture().get_image()
	full.save_png("res://outputs/close-hint-full.png")
	# 近景：把画面右下角裁出来，圆片与描边才看得清。
	# 裁切矩形必须夹在画面内 —— `get_region` 越界不报错，直接给一片全黑。
	var w: int = full.get_width()
	var h: int = full.get_height()
	var crop_w: int = mini(320, w)
	var crop_h: int = mini(240, h)
	var crop := full.get_region(Rect2i(w - crop_w, h - crop_h, crop_w, crop_h))
	crop.save_png("res://outputs/close-hint-closeup.png")
	ok(full != null, "抓到了真实画面")
	# 服务口袋（保管仓库）：这里原来右下角有一枚「完成」，现在只有屏幕右下那一枚圆键。
	main.hud.close_card()
	await frames(4)
	main.hud.open_tab("storage")
	await frames(20)
	ok(hints.visible, "服务口袋打开时同样只有这一枚关闭键")
	var shown: int = 0
	for node in main.hud.services.find_children("*","Button",true,false):
		if (node as Button).text == "完成": shown += 1
	ok(shown == 0, "服务口袋内不再有「完成」按钮（剩 %d 枚）" % shown)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/close-hint-service.png")
	print("[close-hint-render] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
