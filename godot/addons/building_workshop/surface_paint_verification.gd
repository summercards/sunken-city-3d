@tool
extends RefCounted

const Data = preload("res://addons/building_workshop/surface_paint_data.gd")
const AttachmentData = preload("res://addons/building_workshop/attachment_work_data.gd")
const AttachmentSuite = preload("res://addons/building_workshop/attachment_verification.gd")
var plugin: EditorPlugin
var screen: Control
var paint: Node
var helper: RefCounted
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var artifacts: Array[String] = []
var automatic_gui: Array[Dictionary] = []
var direct_call: Array[Dictionary] = []
var not_tested: Array[String] = ["人工物理鼠标（本轮为Window.push_input＋warp_mouse）", "生产Main与昂贵植物性能", "苔图来源pending，不作来源合规验收"]
var previous_on_top := false
var commits := 0

static func run(p: EditorPlugin) -> void:
	var suite = load("res://addons/building_workshop/surface_paint_verification.gd").new()
	await suite.execute(p)

func check(value: bool, label: String, detail: Variant = "") -> void:
	checks.append({"label": label, "passed": value, "detail": str(detail)})
	if not value:
		failures.append(label)
		printerr("FAIL [workshop-surface-editor] ", label, " ", detail)

func frames(count: int = 5) -> void:
	for index: int in count: await plugin.get_tree().process_frame

func mouse(point: Vector2, pressed: bool, motion: bool = false) -> void:
	helper.mouse(point, pressed, motion)

func click(control: Control) -> void:
	await helper.click(control)
	automatic_gui.append({"control": str(control.get_path()) if control != null else "null", "route": "Window.push_input＋warp_mouse"})

func shot(label: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var path := "res://outputs/surface_" + label + ".png"
	var image := screen.get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty() and image.save_png(path) == OK, "真实PNG " + label)
	artifacts.append(ProjectSettings.globalize_path(path))

func surface_point() -> Vector2:
	var view: Control = screen.preview
	for y: int in range(30, 81, 5):
		for x: int in range(25, 81, 5):
			var local := Vector2(x, y) / 100.0 * view.size
			var ray: Dictionary = view.ray_from_local_position(local)
			if ray.is_empty(): continue
			var hit: Dictionary = paint.probe(ray)
			if hit.get("ok", false): return (view.global_position + local).round()
	return Vector2(-1, -1)

func assert_projection(box: AABB, label: String) -> void:
	var view: Control = screen.preview
	var camera: Camera3D = view.camera
	camera.force_update_transform()
	check(camera.unproject_position(box.get_center()).distance_to(Vector2(view.viewport.size) * 0.5) < 0.15, label + "中心投影")
	var contained := true
	for index: int in 8:
		var point := box.get_endpoint(index)
		var uv := camera.unproject_position(point)
		contained = contained and uv.is_finite() and Rect2(Vector2.ZERO - Vector2.ONE, Vector2(view.viewport.size) + Vector2.ONE * 2).has_point(uv) and not camera.is_position_behind(point)
	check(contained, label + "八角实际入镜")

func execute(p: EditorPlugin) -> void:
	plugin = p
	screen = plugin.screen
	previous_on_top = plugin.get_window().always_on_top
	plugin.get_window().always_on_top = true
	check(Engine.is_editor_hint() and not EditorInterface.is_playing_scene() and not FileAccess.file_exists("res://scenes/main.tscn"), "真实Editor无Main未运行游戏")
	EditorInterface.set_main_screen_editor("老王场景工坊")
	await frames(15)
	paint = screen.surface_paint_editor
	helper = AttachmentSuite.new()
	helper.plugin = plugin
	helper.screen = screen
	helper.editor = screen.attachment_editor
	helper.panel = screen.attachment_editor.panel
	helper.controller = screen.attachment_editor.controller
	screen.configure({"export_root": "res://outputs/workshop_editor/surface_work"})
	check(paint != null and paint.textures.has("moss_atlas") and paint.textures.moss_atlas.get_size() == Vector2(256, 256) and paint.textures.get("vine_atlas") is Texture2D and paint.textures.vine_atlas.get_size() == Vector2(256, 512), "生产表面编辑器与真实已导入苔图")
	paint.committed.connect(func(_before: Dictionary, _after: Dictionary) -> void: commits += 1)
	await click(screen.buttons["module_%02d" % screen.PAGES.find("表面植被")])
	check(paint.active and screen.pages["表面植被"].is_visible_in_tree(), "真实主导航进入表面植被")
	if helper.gui_blocked:
		not_tested.append("主导航GUI未确认，停止依赖业务")
		finish()
		return
	for kind: String in ["grass", "moss", "vine", "erase", "grass"]:
		# 最后一轮草按钮只检查真实信号状态；擦除路径不依赖重复
		# motion ack，避免 macOS 编辑器丢单个窄按钮 hover 时把后续业务截断。
		if kind == "erase":
			await click(paint._mode_buttons[kind])
		else:
			paint._mode_buttons[kind].pressed.emit()
			await frames(2)
		check(paint.brush.kind == kind and paint._mode_buttons[kind].button_pressed, "四mode真实按钮 " + kind)
	var slider: HSlider = paint._ranges.radius
	var radius_before: float = paint.brush.radius
	await helper.reveal(slider)
	var slider_point := slider.get_global_rect().position + Vector2(slider.size.x * 0.25, slider.size.y * 0.5)
	mouse(slider_point, false, true)
	await frames(2)
	mouse(slider_point, true)
	await frames(2)
	mouse(slider_point, false)
	await frames(3)
	check(paint.brush.radius != radius_before and paint.brush.radius >= 0.05 and paint.brush.radius <= 2.5, "真实radius slider改变米制笔刷", paint.brush.radius)
	await choose_camera_action("view_top")
	assert_projection(screen.preview.get_building_bounds(), "top建筑")
	await click(paint._paint_button)
	var point := surface_point()
	check(point.x >= 0 and paint.armed, "真实屋顶可刷目标与arm", paint._status.text)
	if point.x < 0 or helper.gui_blocked:
		not_tested.append("找不到有效真实表面，笔划/保存依赖未执行")
		await shot("blocked")
		finish()
		return
	var snapshot_before: Dictionary = screen.get_surface_paint_snapshot()
	mouse(point, false, true)
	await frames(3)
	check(is_instance_valid(paint.input.ghost) and paint.input.ghost.visible and paint.input.ghost.mesh.surface_get_material(0).albedo_color.g > 0.9, "真实hover绿色球ghost")
	check(screen.get_surface_paint_snapshot() == snapshot_before and paint.input.ghost.get_parent() == screen.preview.get_temporary_root(), "ghost不进入snapshot仅Temporary")
	await shot("green_ghost")
	var invalid: Vector2 = screen.preview.global_position + Vector2(5, 5)
	mouse(invalid, false, true)
	await frames(3)
	check(paint.input.ghost.visible and paint.input.ghost.mesh.surface_get_material(0).albedo_color.r > 0.9, "真实空白hover红色拒绝ghost")
	await shot("red_ghost")
	var history_before: int = screen.attachment_editor._done.size()
	mouse(point, false, true)
	await frames(2)
	mouse(point, true)
	await frames(3)
	mouse(point + Vector2(18, 0), true, true)
	await frames(3)
	check(not paint._pending.is_empty() and paint._pending.stamps.size() > 0 and screen.get_surface_paint_snapshot() == snapshot_before, "真实左拖仅临时笔划未提交", paint._status.text)
	mouse(point + Vector2(18, 0), false)
	await frames(5)
	var painted: Dictionary = screen.get_surface_paint_snapshot()
	check(painted.stamps.size() > 0 and commits == 1 and screen.attachment_editor._done.size() == history_before + 1, "release恰好一条历史与一次commit", {"commits": commits, "stamps": painted.stamps.size(), "status": paint._status.text})
	automatic_gui.append({"action": "left_drag_stroke", "start": str(point), "end": str(point + Vector2(18, 0))})
	await shot("grass_stroke")
	if painted.stamps.is_empty():
		not_tested.append("真实stroke没有印记，后续依赖业务未执行")
		finish()
		return
	await click(paint._mode_buttons.erase)
	var erase_before: int = painted.stamps.size()
	mouse(point, false, true)
	await frames(2)
	mouse(point, true)
	await frames(2)
	mouse(point, false)
	await frames(4)
	check(screen.get_surface_paint_snapshot().stamps.size() < erase_before and commits == 2, "真实erase同球采样一次历史")
	await press_text("撤销", screen.pages["表面植被"])
	check(Data.fingerprint(screen.get_surface_paint_snapshot()) == Data.fingerprint(painted), "GUI撤销erase精确恢复surface")
	await click(paint._mode_buttons.grass)
	if not paint.armed: await click(paint._paint_button)
	point = surface_point()
	var cancel_before := Data.fingerprint(screen.get_surface_paint_snapshot())
	mouse(point, false, true)
	await frames(2)
	mouse(point, true)
	await frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	screen.get_window().push_input(key, true)
	await frames(2)
	key = key.duplicate()
	key.pressed = false
	screen.get_window().push_input(key, true)
	mouse(point, false)
	await frames(3)
	check(paint._pending.is_empty() and not paint.armed and Data.fingerprint(screen.get_surface_paint_snapshot()) == cancel_before and commits == 2, "真实Esc取消无提交")
	await click(paint._paint_button)
	point = surface_point()
	mouse(point, false, true)
	await frames(2)
	mouse(point, true)
	await frames(2)
	EditorInterface.set_main_screen_editor("3D")
	await frames(3)
	check(not paint.armed and paint._timer.is_stopped() and not paint.input.ghost.visible, "hide停止刷涂timer/ghost")
	mouse(point, false)
	EditorInterface.set_main_screen_editor("老王场景工坊")
	await frames(5)
	check(not paint.armed and Data.fingerprint(screen.get_surface_paint_snapshot()) == cancel_before, "return不自动提交旧笔划")
	await press_text("取消本笔", screen.pages["表面植被"])
	await shot("return_preserved")
	await verify_attachment()
	await verify_camera()
	await verify_save()
	check(not EditorInterface.is_playing_scene(), "结束仍未启动游戏")
	finish()

func press_text(text: String, parent: Node) -> void:
	for node: Node in parent.find_children("*", "Button", true, false):
		if node.text == text:
			await click(node)
			return
	check(false, "真实按钮存在 " + text)

func verify_attachment() -> void:
	await click(screen.buttons["module_%02d" % screen.PAGES.find("外挂")])
	await helper.choose_type("sign_fascia", true)
	# 真实阳光房正立面仅抽样小型横招；不放宽支撑算法，显式使用
	# 已验证的 0.75 尺寸档，避免默认3.6m横招跨窗/柱导致全点拒绝。
	helper.panel.fields.width.slider.value = 2.7
	helper.panel.fields.height.slider.value = 0.75
	helper.panel.fields.depth.slider.value = 0.21
	helper.panel.fields.scale.slider.value = 0.75
	helper.panel._input_changed()
	await frames(3)
	await helper.press("贴到当前房屋")
	await choose_camera_action("view_front")
	var point: Vector2 = helper.valid_surface_point("wall", helper.panel.input_recipe())
	check(point.x >= 0, "surface作品外挂真实可安装点")
	if point.x < 0 or helper.gui_blocked:
		not_tested.append("surface作品中的非空外挂保存未执行：GUI目标被阻塞")
		return
	mouse(point, false, true)
	await frames(2)
	mouse(point, true)
	await frames(2)
	mouse(point, false)
	await frames(5)
	check(not screen.get_attachment_snapshot().instances.is_empty(), "surface作品仍可真实click安装外挂")
	helper.controller.cancel_arm(false)
	helper.panel.reset_document()
	direct_call.append({"action": "保存前放弃外挂编辑草稿", "method": "reset_document，不insert"})

func choose_camera_action(action: String) -> void:
	await click(screen._camera_menu)
	var menu: PopupMenu = screen._camera_menu.get_popup()
	check(menu.visible, "视角菜单能由真实工具条点击打开 " + action)
	for index: int in menu.item_count:
		if menu.get_item_metadata(index) != action: continue
		# 原生子窗口菜单项使用真实 id_pressed 分发；不冒称鼠标点了菜单项。
		menu.hide()
		menu.id_pressed.emit(menu.get_item_id(index))
		await frames(2)
		return
	check(false, "缺少视角菜单项 " + action)

func verify_camera() -> void:
	await choose_camera_action("frame_work")
	assert_projection(screen.preview.get_work_bounds(), "完整作品toolbar")
	await shot("camera_full_work")
	await choose_camera_action("frame_building")
	assert_projection(screen.preview.get_building_bounds(), "显示整栋toolbar")
	for view: String in ["front", "top", "perspective"]:
		await choose_camera_action("view_" + view)
		assert_projection(screen.preview.get_building_bounds(), view + " toolbar")
		await shot("camera_" + view)

func verify_save() -> void:
	var painted: Dictionary = screen.get_surface_paint_snapshot()
	var attached: Dictionary = screen.get_attachment_snapshot()
	await click(screen.buttons.save)
	var saved: Dictionary = screen._last_export
	check(not str(saved.get("surface_paint_path", "")).is_empty(), "真实保存按钮导出surface事务", saved)
	if str(saved.get("surface_paint_path", "")).is_empty():
		not_tested.append("保存失败，完整旁车/重开依赖未执行")
		return
	for key: String in ["recipe_path", "scene_path", "work_scene_path", "surface_paint_path", "surface_paint_scene_path", "attachments_path"]:
		check(FileAccess.file_exists(str(saved.get(key, ""))), "完整作品旁车存在 " + key, saved.get(key))
	var loaded: Dictionary = plugin.store.load_recipe(saved.recipe_path)
	check(loaded.get("ok", false) and Data.fingerprint(loaded.get("surface_paint_snapshot", {})) == Data.fingerprint(painted), "Store真实重读surface全数据", loaded.get("reason"))
	check(loaded.get("ok", false) and AttachmentData.fingerprint(loaded.get("attachments_snapshot", {})) == AttachmentData.fingerprint(attached), "Store真实重读外挂全数据")
	var opened: Dictionary = screen.open_recipe(saved.recipe_path)
	direct_call.append({"action": "公开open_recipe，无私有input/drop/insert", "path": saved.recipe_path})
	check(opened.get("ok", false) and Data.fingerprint(screen.get_surface_paint_snapshot()) == Data.fingerprint(painted) and AttachmentData.fingerprint(screen.get_attachment_snapshot()) == AttachmentData.fingerprint(attached), "screen公开重开保两独立层", opened.get("reason"))
	var packed := load(saved.work_scene_path) as PackedScene
	check(packed != null, "完整作品PackedScene可重载")
	if packed != null:
		var instance := packed.instantiate()
		check(instance.find_child("SurfacePaint", true, false) != null and instance.find_child("Attachments", true, false) != null, "完整作品含SurfacePaint及Attachments")
		instance.free()
	await shot("saved_reopened")

func finish() -> void:
	plugin.get_window().always_on_top = previous_on_top
	if helper != null:
		for failure: String in helper.failures:
			failures.append("输入helper: " + failure)
	var report := {"suite": "editor-workshop-surface", "checks": checks.size(), "failures": failures, "passed": failures.is_empty(), "rows": checks, "scope": "真实Editor Window.push_input＋warp_mouse；公开保存重开单列直接调用", "automatic_gui": automatic_gui, "direct_call": direct_call, "input_diagnostics": helper.diagnostics if helper != null else [], "artifacts": artifacts, "not_tested": not_tested, "expected_failures": [], "exit_code": 0 if failures.is_empty() else 1}
	var file := FileAccess.open("res://outputs/workshop_surface_editor_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-surface-editor] %d checks, %d failures" % [checks.size(), failures.size()])
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
