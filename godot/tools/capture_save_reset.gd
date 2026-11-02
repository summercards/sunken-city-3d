extends SceneTree
## 重置存档的两页真实渲染证据：暂停菜单里的入口 + 它的确认页。
##
## 只抓图，不点确认 —— 确认那一下会把档归档并重建局面，属于行为证据
## （`save-reset` 那一支的事）。这里回答的是「这两屏长什么样、字有没有被吃」。
## 运行：python scripts/run_verification.py visual-save-reset

var main: Node
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
	print("[save-reset-render] ", "PASS " if value else "FAIL ", label)


func shot(path: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[save-reset-render] ", path)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	main.title_camera.begin(main.cam)
	main.title_camera.finish(main.cam)
	for i in 20:
		await process_frame

	# 1) 暂停菜单：入口必须在「读取上次的记录」下面，而且是会让人停一下的那种颜色。
	main.hud.menu.show_menu("pause")
	await shot("res://outputs/save-reset-1-pause.png")
	check(main.hud.menu.buttons.has("reset"), "暂停菜单里有「重新开始（重置存档）」这一项")

	# 2) 确认页：破坏性动作必须单独一屏，且说清旧记录会备份。
	main.hud.menu.show_menu("reset")
	await shot("res://outputs/save-reset-2-confirm.png")
	check(main.hud.menu.page == "reset", "确认页真的切过去了")
	check(main.hud.menu.buttons.has("confirm_reset"), "确认页有「确认重置存档」")
	check(main.hud.menu.buttons.has("cancel"), "确认页有「再想一想」")
	# 默认焦点必须落在「取消」上：Enter 一路按下去不能把档重置掉。
	var first: Button = main.hud.menu.buttons.values()[0] as Button
	check(first != null and not first.text.contains("重置"), "开头那个按钮不是重置（Enter 连按不会误触）")

	print("[save-reset-render] %d failures" % failures)
	quit(0 if failures == 0 else 1)
