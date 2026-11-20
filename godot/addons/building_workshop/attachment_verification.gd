@tool
extends RefCounted

const Data = preload("res://addons/building_workshop/attachment_work_data.gd")
const Recipe = preload("res://src/building_attachments/recipe.gd")
const HouseRecipe = preload("res://src/workshop/recipe.gd")
const Surface = preload("res://addons/scene_assembly/attachment_surface.gd")
var plugin: EditorPlugin
var screen: Control
var editor: Node
var panel: Control
var controller: Node
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var gui: Array = []
var direct: Array = []
var artifacts: Array[String] = []
var layouts: Array = []
var scene_before: Node
var pause_before := false
var previous_on_top := false
var diagnostics: Array[Dictionary] = []
var gui_blocked := false
var not_tested: Array[String] = ["最近命中/墙体遮挡点选专项尚未编写执行", "house→attachment→house undo3/redo3及跨域分支专项尚未编写执行", "new/open/cancel/badsidecar/recoveryatomic/FakeStore兼容专项尚未编写执行", "回编场景context导入、双层单undo替换及并发附件冲突专项尚未编写执行", "随机阳光房实际UV、原slot semantic selection与导航由后续upgrade/switch当前源码回归验证"]

class FakeStore extends RefCounted:
	var calls := 0
	func export_revision(recipe: Dictionary, catalog: Dictionary, _base: String) -> Dictionary:
		calls += 1
		return {"ok": true, "recipe": recipe.duplicate(true), "catalog": catalog.duplicate(true), "directory": "res://outputs/workshop_editor/fake", "scene_path": "", "recipe_path": ""}
	func list_documents(_base: String) -> Array:
		return []

static func run(p: EditorPlugin) -> void:
	var suite = load("res://addons/building_workshop/attachment_verification.gd").new()
	await suite.execute(p)

func check(value: bool, label: String, detail: Variant = "") -> void:
	checks.append({"name": label, "passed": value, "detail": str(detail)})
	if not value:
		failures.append(label + ": " + str(detail))
		printerr("FAIL [workshop-attachments-editor] ", label, " ", detail)

func frames(count: int = 5) -> void:
	for i: int in count: await plugin.get_tree().process_frame

func execute(p: EditorPlugin) -> void:
	plugin = p
	screen = plugin.screen
	scene_before = EditorInterface.get_edited_scene_root()
	pause_before = plugin.get_tree().paused
	check(Engine.is_editor_hint() and not EditorInterface.is_playing_scene(), "真实编辑器未运行游戏")
	check(ProjectSettings.globalize_path("res://").contains("sea-work/verification/") and not FileAccess.file_exists("res://scenes/main.tscn"), "最小工程无Main")
	check(not ProjectSettings.has_setting("autoload/Zones") and not ProjectSettings.has_setting("autoload/GameState"), "无游戏Autoload")
	previous_on_top = plugin.get_window().always_on_top
	plugin.get_window().always_on_top = true
	EditorInterface.set_main_screen_editor("老王场景工坊")
	await frames(12)
	editor = screen.attachment_editor
	check(editor != null, "生产外挂协调器完成Godot初始化")
	if editor == null:
		not_tested.append("生产attachment_editor编译或初始化失败；真实GUI、布局和业务链未执行")
		finish()
		return
	panel = editor.panel
	controller = editor.controller
	screen.configure({"export_root": "res://outputs/workshop_editor/attachment_gui"})
	check(panel.embedded_workshop and panel.get_parent() == screen.pages["外挂"], "生产外挂页内嵌工坊而非独立dock")
	check(screen.preview._model_root.get_child_count() == 1, "保留原slots唯一building child")
	var window_id := plugin.get_window().get_window_id()
	DisplayServer.window_move_to_foreground(window_id)
	plugin.get_window().grab_focus()
	await frames(5)
	var navigation: Button = screen.buttons["module_%02d" % screen.PAGES.find("外挂")]
	await click(navigation)
	check(panel.is_visible_in_tree(), "主导航真实鼠标进入外挂页")
	var initial_layout: Dictionary = screen.get_attachment_layout_diagnostics()
	layouts.append({"stage": "fresh_editor_before_reparent", "diagnostics": initial_layout})
	print("[workshop-attachments-initial-layout] ", JSON.stringify(initial_layout))
	check(screen.get_global_rect().encloses(screen.preview.get_global_rect()), "首次真实editor预览包含于工坊主屏", screen.preview.get_global_rect())
	if gui_blocked:
		not_tested.append("主导航GUI输入未确认，停止依赖业务")
		finish()
		return
	await choose_type("sign_fascia", false)
	if gui_blocked:
		finish()
		return
	# 横招默认尺寸跨窗/柱时严格支撑会全部拒绝；沿用已验证的
	# 阳光房夹具档位，显式缩小，不放宽产品支撑或自动缩放。
	panel.fields.width.slider.value = 2.7
	panel.fields.scale.slider.value = 0.75
	panel._input_changed()
	await frames(3)
	panel._choice_value("gallery_condition", "damaged")
	panel.gallery_condition = "damaged"
	panel.refresh_gallery()
	await frames(8)
	await select_gallery()
	await press("编辑组件")
	panel.fields.offset.slider.value = 0.03
	panel.fields.angle.slider.value = 7
	panel._choice_value("condition", "damaged")
	panel._input_changed()
	await frames(3)
	await press("图库")
	if gui_blocked:
		not_tested.append("图库编辑按钮GUI输入未确认，停止依赖drag业务")
		finish()
		return
	var sign := await drag_from_gallery("wall")
	check(sign != null, "图库真实拖入嵌入preview生成sign")
	if sign == null:
		not_tested.append("sign拖放失败，依赖实例的编辑/保存/历史后续未执行")
		await verify_layouts()
		finish()
		return
	check(sign.get_meta("sea_attachment").recipe.condition == "damaged", "drag使用damaged输入")
	check(is_equal_approx(float(sign.get_meta("sea_attachment").anchor.offset_m), 0.03) and is_equal_approx(float(sign.get_meta("sea_attachment").anchor.angle_degrees), 7.0), "drag保留0.03偏移和7度")
	await choose_type("tank_tower_cone", true)
	if gui_blocked:
		not_tested.append("水塔图库编辑输入未确认，停止后续业务")
		finish()
		return
	screen.preview.set_view("top")
	screen.buttons.frame_building.pressed.emit()
	await frames(8)
	await diagnose_roof()
	await press("贴到当前房屋")
	if gui_blocked:
		not_tested.append("按钮GUI输入未确认，停止依赖业务，不以readonly后续掩盖失败")
		finish()
		return
	var point := valid_surface_point("roof", panel.input_recipe())
	check(point.x >= 0, "真实屋顶安装位置存在")
	var tank: Node3D
	if point.x >= 0:
		mouse(point, false, true)
		await frames(3)
		check(editor.input.ghost != null and editor.input.ghost.get_parent() == screen.preview.get_temporary_root(), "ghost只在temporaryroot")
		check(screen.get_attachment_snapshot().instances.size() == 1, "ghost排除作品snapshot")
		mouse(point, true)
		await frames(2)
		mouse(point, false)
		await frames(8)
		tank = controller.selected
		check(tank != null and tank != sign and screen.get_attachment_snapshot().instances.size() == 2, "真实click arm屋顶水塔")
		gui.append({"action": "click_arm_roof", "point": str(point)})
	if tank != null:
		await verify_edits(sign, tank)
	else:
		not_tested.append("真实GUI水塔未放入，双类型参数CRUD/微调专项未执行；不得由直接insert替代")
	await verify_manual_return_and_deleted_dirty()
	await verify_timeline_and_recovery()
	await verify_nearest_occlusion()
	await verify_house_preservation()
	await verify_lifecycle()
	if gui_blocked:
		not_tested.append("生命周期按钮GUI输入未确认，后续保存/场景case停止")
		finish()
		return
	await verify_save_reopen()
	await verify_layouts()
	check(EditorInterface.get_edited_scene_root() == scene_before and plugin.get_tree().paused == pause_before, "工坊本地编辑未改真实编辑scene或pause")
	await verify_scene_context()
	finish()

func mouse(point: Vector2, pressed: bool, motion: bool = false) -> void:
	screen.get_window().warp_mouse(point)
	var event: InputEventMouse
	if motion:
		var move := InputEventMouseMotion.new()
		move.relative = Vector2(20, 12)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event = move
	else:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event = button
	event.window_id = screen.get_window().get_window_id()
	event.position = point
	event.global_position = point
	screen.get_window().push_input(event, true)

func reveal(control: Control) -> void:
	var node: Node = control
	while node.get_parent() != null:
		var parent := node.get_parent()
		if parent is TabContainer: parent.current_tab = node.get_index()
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
			await frames(2)
		node = parent
	await frames(3)
	var window_rect: Rect2 = control.get_viewport().get_visible_rect().grow(-12)
	var rect := control.get_global_rect()
	if rect.end.y > window_rect.end.y and screen._left_panel.is_ancestor_of(control):
		screen._left_panel.scroll_vertical += ceili(rect.end.y - window_rect.end.y)
		await frames(3)
	elif rect.position.y < window_rect.position.y and screen._left_panel.is_ancestor_of(control):
		screen._left_panel.scroll_vertical -= ceili(window_rect.position.y - rect.position.y)
		await frames(3)

func click(control: Control) -> void:
	if gui_blocked: return
	if control == null:
		check(false, "点击目标存在")
		gui_blocked = true
		return
	await reveal(control)
	var rect := control.get_global_rect()
	var wid := control.get_window().get_window_id()
	DisplayServer.window_move_to_foreground(wid)
	control.get_window().grab_focus()
	await frames(2)
	var acknowledgements: Array = []
	var observer: Callable = func(event: InputEvent) -> void:
		if event is InputEventMouseMotion: acknowledgements.append({"window_id": event.window_id, "position": str(event.position)})
	control.gui_input.connect(observer)
	var acknowledged := false
	# macOS Editor 的 Window.push_input 在插件刚切换主屏时可能丢掉首个 motion；
	# 只重发有限次数的真实窗口事件，不直接调用私有 _gui_input 或伪造点击结果。
	for attempt: int in 5:
		if attempt > 0:
			DisplayServer.window_move_to_foreground(wid)
			control.get_window().grab_focus()
			await frames(2)
		mouse(rect.get_center().round(), false, true)
		for frame: int in 10:
			await plugin.get_tree().process_frame
			var target := control.get_viewport().gui_get_hovered_control()
			if not acknowledgements.is_empty() and (target == control or (target != null and control.is_ancestor_of(target))):
				acknowledged = true
				break
		if acknowledged: break
	control.gui_input.disconnect(observer)
	var hovered := control.get_viewport().gui_get_hovered_control()
	var window_data := window_diagnostics(control)
	window_data.merge({"control": str(control.get_path()), "text": control.text if control is Button else "", "rect": str(rect), "hovered": str(hovered.get_path()) if hovered != null else "null", "gui_motion_ack": acknowledgements, "acknowledged": acknowledged})
	diagnostics.append(window_data)
	var inside_window: bool = control.get_viewport().get_visible_rect().encloses(rect)
	check(control.is_visible_in_tree() and rect.size.x > 8 and rect.size.y > 8 and inside_window, "实际GUI控件可见且位于window：" + str(control.name), rect)
	check(acknowledged, "GUI真实悬停及输入ack：" + str(control.name), window_data)
	if not acknowledged:
		gui_blocked = true
		print("[workshop-attachments-click-diagnostic] ", JSON.stringify(window_data))
		return
	mouse(rect.get_center().round(), true)
	await frames(2)
	mouse(rect.get_center().round(), false)
	await frames(4)
	gui.append({"control": str(control.get_path()), "action": "mouse_click", "method": "Window.push_input（非物理鼠标）", "rect": str(rect), "gui_motion_ack": acknowledgements})

func window_diagnostics(control: Control) -> Dictionary:
	var windows: Array = []
	for wid: int in DisplayServer.get_window_list():
		windows.append({"id": wid, "focused": DisplayServer.window_is_focused(wid), "position": str(DisplayServer.window_get_position(wid)), "size": str(DisplayServer.window_get_size(wid))})
	return {"stage": "window_input", "target_window_id": control.get_window().get_window_id(), "target_window_visible": control.get_window().visible, "root_window_id": plugin.get_tree().root.get_window_id(), "viewport_rect": str(control.get_viewport().get_visible_rect()), "screen_rect": str(screen.get_global_rect()), "windows": windows}

func diagnose_roof() -> void:
	var preview: Control = screen.preview
	var camera: Camera3D = preview.camera
	var host: Node3D = preview.get_host_asset()
	var roof_box := AABB()
	var all_box := AABB()
	var initialized := false
	var roof_initialized := false
	var mesh_rows: Array = []
	for mesh_node: MeshInstance3D in Surface.meshes(host):
		var bounds: AABB = mesh_node.global_transform * mesh_node.get_aabb()
		all_box = all_box.merge(bounds) if initialized else bounds
		initialized = true
		if str(mesh_node.name).to_lower().contains("roof"):
			roof_box = roof_box.merge(bounds) if roof_initialized else bounds
			roof_initialized = true
		var culls: Array = []
		for surface: int in mesh_node.mesh.get_surface_count(): culls.append(Surface.material_cull(mesh_node.get_active_material(surface)))
		mesh_rows.append({"path": str(host.get_path_to(mesh_node)), "bounds": str(bounds), "cull": culls})
	if not roof_initialized: roof_box = all_box
	var center := roof_box.get_center()
	var origin := Vector3(center.x, roof_box.end.y + 20.0, center.z)
	var native: Dictionary = Surface.raycast(host, origin, Vector3.DOWN, "roof")
	var native_controller: Dictionary = controller._hit(panel.input_recipe(), origin, Vector3.DOWN)
	var states: Array = []
	for stage: String in ["before_force_draw", "after_force_draw_physics"]:
		if stage == "after_force_draw_physics":
			RenderingServer.force_draw()
			await plugin.get_tree().physics_frame
			await frames(2)
		var ray: Dictionary = preview.ray_from_local_position(preview.size * 0.5)
		var hit: Dictionary = Surface.raycast(host, ray.origin, ray.direction, "roof")
		states.append({"stage": stage, "projection": camera.projection, "global_transform": str(camera.global_transform), "camera_transform": str(camera.get_camera_transform()), "up": str(camera.global_basis.y), "fov": camera.fov, "size": camera.size, "yaw": preview._yaw, "pitch": preview._pitch, "target": str(preview._target), "distance": preview._distance, "viewport_size": str(preview.viewport.size), "preview_rect": str(preview.get_global_rect()), "center_ray": {"origin": str(ray.origin), "direction": str(ray.direction)}, "surface_hit": hit})
	var sample_counts := {"all_hits": 0, "window_visible_hits": 0, "all_installable": 0, "window_visible_installable": 0}
	for y: int in range(5, 96, 5):
		for x: int in range(5, 96, 5):
			var local := Vector2(x, y) * 0.01 * preview.size
			var ray: Dictionary = preview.ray_from_local_position(local)
			var hit: Dictionary = Surface.raycast(host, ray.origin, ray.direction, "roof")
			var visible_point := preview.get_viewport().get_visible_rect().has_point(preview.global_position + local)
			if hit.ok:
				sample_counts.all_hits += 1
				if visible_point: sample_counts.window_visible_hits += 1
				if controller.validate_installation(panel.input_recipe(), hit).ok:
					sample_counts.all_installable += 1
					if visible_point: sample_counts.window_visible_installable += 1
	var record := {"stage": "roof_diagnostic", "sample_counts": sample_counts, "projected_roof_center_local": str(camera.unproject_position(center) * preview.size / Vector2(preview.viewport.size)), "projected_roof_center_window": str(preview.global_position + camera.unproject_position(center) * preview.size / Vector2(preview.viewport.size)), "window_rect": str(preview.get_viewport().get_visible_rect()), "roof_specific_mesh_found": roof_initialized, "roof_box": str(roof_box), "host_box": str(all_box), "native_origin": str(origin), "native_direction": str(Vector3.DOWN), "native_surface": native, "native_controller": native_controller, "camera_states": states, "meshes": mesh_rows, "roof_limit": Surface.ROOF_LIMIT, "wall_limit": Surface.WALL_LIMIT, "draft": panel.input_recipe()}
	diagnostics.append(record)
	print("[workshop-attachments-roof-diagnostic] ", JSON.stringify(record))
	direct.append({"action": "世界Y向下独立对照与相机同步前后屋顶射线", "placement": false})

func find_button(text: String) -> Button:
	for node: Node in panel.find_children("*", "Button", true, false):
		if node.text == text: return node
	return null

func press(text: String) -> void:
	var button := find_button(text)
	check(button != null, "按钮存在：" + text)
	if button != null: await click(button)

func choose_type(type_id: String, edit: bool) -> void:
	await press("图库")
	if gui_blocked: return
	panel.search.text = type_id
	panel.refresh_gallery()
	await frames(5)
	direct.append({"action": "search_fixture", "type_id": type_id})
	check(panel.gallery.item_count == 1, "图库搜索唯一：" + type_id)
	if panel.gallery.item_count != 1: return
	await select_gallery()
	check(panel.draft.type_id == type_id and panel.gallery.is_visible_in_tree(), "图库单击保持可drag：" + type_id)
	if edit: await press("编辑组件")

func select_gallery() -> void:
	await reveal(panel.gallery)
	var point: Vector2 = panel.gallery.global_position + panel.gallery.get_item_rect(0).get_center()
	mouse(point, false, true)
	await frames(2)
	mouse(point, true)
	await frames(2)
	mouse(point, false)
	await frames(4)
	gui.append({"action": "gallery_select", "point": str(point)})

func valid_surface_point(mode: String, recipe: Dictionary, payload: Variant = null) -> Vector2:
	var preview: Control = screen.preview
	var best := Vector2(-1, -1)
	var reasons: Dictionary = {}
	var hits := 0
	for y: int in range(5, 96, 2):
		for x: int in range(5, 96, 2):
			var global_point: Vector2 = (preview.global_position + Vector2(x / 100.0, y / 100.0) * preview.size).round()
			var local: Vector2 = global_point - preview.global_position
			if not screen.get_viewport().get_visible_rect().has_point(global_point): continue
			var ray: Dictionary = preview.ray_from_local_position(local)
			if ray.is_empty(): continue
			var hit: Dictionary = Surface.raycast(preview.get_host_asset(), ray.origin, ray.direction, mode)
			if hit.ok:
				hits += 1
				var validation: Dictionary = controller.validate_installation(recipe, hit)
				if validation.ok:
					if payload != null:
						if preview._can_drop_data(local, payload): return global_point
						continue
					best = preview.global_position + local
					return best
				var reason := str(validation.get("reason", ""))
				reasons[reason] = int(reasons.get(reason, 0)) + 1
	print("[workshop-attachments-surface] ", JSON.stringify({"mode": mode, "hits": hits, "rejections": reasons, "recipe": recipe, "host_reason": controller._check_host()}))
	return best

func drag_from_gallery(mode: String) -> Node3D:
	if screen.preview.has_meta("attachment_last_drop"): screen.preview.remove_meta("attachment_last_drop")
	screen.preview.set_view("front")
	screen.buttons.frame_building.pressed.emit()
	await frames(5)
	print("[workshop-attachments-layout-before-drag] ", JSON.stringify(screen.get_attachment_layout_diagnostics()))
	await reveal(panel.gallery)
	var source: Vector2 = panel.gallery.global_position + panel.gallery.get_item_rect(0).get_center()
	var recipe: Dictionary = panel.input_recipe()
	controller.set_mount_options(mode, panel.fields.offset.slider.value, panel.fields.angle.slider.value)
	var destination := valid_surface_point(mode, recipe)
	check(destination.x >= 0, "drag目标有真实可支撑面")
	if destination.x < 0:
		print("[workshop-attachments-drag-trace] ", JSON.stringify(screen.preview.get_attachment_drag_diagnostics()))
		return null
	mouse(source, false, true)
	await frames(2)
	mouse(source, true)
	await frames(2)
	mouse(source + Vector2(35, 15), true, true)
	await frames(4)
	destination = valid_surface_point(mode, controller.armed_recipe if controller.armed else recipe, screen.get_viewport().gui_get_drag_data())
	check(destination.x >= 0, "arm后当前真实几何可支撑目标")
	if destination.x < 0: return null
	mouse(destination, true, true)
	await frames(5)
	check(screen.get_viewport().gui_is_dragging() and controller.armed, "真实Viewport建立图库drag事务")
	var events: Array = []
	var observer: Callable = func(event: InputEvent) -> void:
		if event is InputEventMouseButton: events.append({"pressed": event.pressed, "position": str(event.position), "armed": controller.armed})
	screen.preview.gui_input.connect(observer)
	var payload: Variant = screen.get_viewport().gui_get_drag_data()
	check(payload is Dictionary and payload.get("type") == "sea_building_attachment", "drag载荷来自真实图库")
	if payload is Dictionary:
		check(screen.preview._can_drop_data(destination - screen.preview.global_position, payload), "实际嵌入preview can_drop门禁")
	var drop_ray: Dictionary = screen.preview.ray_from_local_position(destination - screen.preview.global_position)
	var diagnostic_preview: Dictionary = controller.preview_at_ray(controller.armed_recipe, drop_ray.origin, drop_ray.direction) if controller.armed else {}
	print("[workshop-attachments-predrop] ", JSON.stringify({"reason": diagnostic_preview.get("reason", ""), "armed_reason": controller._context_reason(false), "payload_equals": payload is Dictionary and payload.get("recipe") == controller.armed_recipe, "options": [controller.offset, controller.angle_degrees], "draft_options": [panel.fields.offset.slider.value, panel.fields.angle.slider.value], "screen_visible_flag": screen.preview._screen_visible, "visible_tree": screen.preview.is_visible_in_tree(), "local_point": destination - screen.preview.global_position, "size": screen.preview.size, "input_can_drop": editor.input.can_drop(destination - screen.preview.global_position, payload)}))
	var hovered: Control = screen.get_viewport().gui_get_hovered_control()
	var detail := {"before_release": {"dragging": screen.get_viewport().gui_is_dragging(), "armed": controller.armed, "hovered": str(hovered.get_path()) if hovered != null else "null", "preview_rect": str(screen.preview.get_global_rect()), "destination": str(destination), "source": str(source), "status": panel.status.text}}
	mouse(destination, false)
	await frames(10)
	screen.preview.gui_input.disconnect(observer)
	detail.input_events = events
	detail.after_release = {"selected": str(controller.selected), "armed": controller.armed, "drop": screen.preview.get_meta("attachment_last_drop", {}), "status": panel.status.text, "snapshot": screen.get_attachment_snapshot()}
	detail.native_trace = screen.preview.get_attachment_drag_diagnostics()
	print("[workshop-attachments-drag] ", JSON.stringify(detail))
	gui.append({"action": "gallery_drag_to_embedded_preview", "source": str(source), "destination": str(destination), "method": "Window.push_input＋Window.warp_mouse同步查询位置（非人工鼠标）", "detail": detail})
	return controller.selected

func verify_edits(sign: Node3D, tank: Node3D) -> void:
	editor.select_nodes([sign])
	await frames(4)
	await press("编辑")
	var tank_before := Data.fingerprint(screen.get_attachment_snapshot())
	var tank_transform := tank.transform
	var tank_metadata: Dictionary = tank.get_meta("sea_attachment").duplicate(true)
	var count_before: int = editor._done.size()
	panel.text_input.text = "SEA CAFE"
	panel._choice_value("condition", "ruined")
	panel._choice_value("style", "block")
	panel._input_changed()
	await press("应用到选中外挂")
	var selected: Node3D = controller.selected
	check(selected != null and selected.get_meta("sea_attachment").recipe.text == "SEA CAFE" and selected.get_meta("sea_attachment").recipe.style == "block", "GUI应用英文与广告样式")
	check(tank.transform == tank_transform and tank.get_meta("sea_attachment") == tank_metadata, "应用参数只影响选中实例")
	check(editor._done.size() == count_before + 1 and Data.fingerprint(screen.get_attachment_snapshot()) != tank_before, "应用只增一条外挂历史且真实模型变化")
	var snapshot := Data.fingerprint(screen.get_attachment_snapshot())
	count_before = editor._done.size()
	panel.text_input.text = "bad中文?"
	panel._input_changed()
	await press("应用到选中外挂")
	check(panel.text_input.text == "bad中文?" and Data.fingerprint(screen.get_attachment_snapshot()) == snapshot and editor._done.size() == count_before, "非法文字保输入模型与历史")
	await press("放弃当前输入")
	await press("复制")
	check(screen.get_attachment_snapshot().instances.size() == 3, "GUI复制新增独立实例")
	await press("删除")
	check(screen.get_attachment_snapshot().instances.size() == 2, "GUI删除只删选中实例")
	direct.append({"action": "selection_fixture", "method": "attachment_editor.select_nodes"})
	var nodes: Array = screen.preview.get_attachment_root().get_children()
	editor.select_nodes([nodes[0]])
	await frames(3)
	var before_move := Data.fingerprint(screen.get_attachment_snapshot())
	var moved: Dictionary = editor.move_selected(Vector3(0.01, 0, 0))
	check(moved.ok and Data.fingerprint(screen.get_attachment_snapshot()) != before_move, "微调成功真实重投支撑面", moved.get("reason", ""))
	var before_edge := Data.fingerprint(screen.get_attachment_snapshot())
	var rejected: Dictionary = editor.move_selected(Vector3(100, 0, 0))
	check(not rejected.ok and Data.fingerprint(screen.get_attachment_snapshot()) == before_edge, "越界微调拒绝原子保持")
	direct.append({"action": "move_selected", "success": moved.ok, "rejected": not rejected.ok})

func verify_manual_return_and_deleted_dirty() -> void:
	controller.cancel_arm(false)
	panel.reset_document()
	var initial_height: float = float(screen.snapshot().floor_height)
	var initial_count: int = screen.get_attachment_snapshot().instances.size()
	screen.controls.floor_height.value = initial_height + 0.1
	check(screen.apply_parameters().ok, "review手调回原值夹具A到B房屋提交")
	var nodes: Array = screen.preview.get_attachment_root().get_children()
	editor.select_nodes([nodes[0]])
	check(controller.duplicate_selected().ok, "review夹在房屋提交之间复制附件")
	screen.controls.floor_height.value = initial_height
	check(screen.apply_parameters().ok, "review手调B回A是新房屋提交")
	var with_copy: String = Data.fingerprint(screen.get_attachment_snapshot())
	screen._undo(false)
	check(is_equal_approx(float(screen.snapshot().floor_height), initial_height + 0.1) and Data.fingerprint(screen.get_attachment_snapshot()) == with_copy and screen.get_attachment_snapshot().instances.size() == initial_count + 1, "手调回A后undo只恢复B不误撤附件")
	screen._undo(true)
	check(is_equal_approx(float(screen.snapshot().floor_height), initial_height) and Data.fingerprint(screen.get_attachment_snapshot()) == with_copy, "手调回A后redo回A保复制附件")
	nodes = screen.preview.get_attachment_root().get_children()
	var target: Node3D = nodes[0]
	var other: Node3D = nodes[1]
	var target_id: String = str(target.get_meta("sea_attachment").instance_id)
	editor.select_nodes([target])
	panel.text_input.text = "REVIEW非法?"
	panel._input_changed()
	check(panel.has_unsaved_inputs(), "安装实例A非法输入真实dirty")
	check(controller.delete_selected().ok, "删除带非法输入的实例A")
	check(not panel.has_unsaved_inputs(), "已删A当前非法输入及缓存不锁保存")
	var saved: Dictionary = screen.save_building()
	check(saved.ok, "删除脏实例A后可保存新revision", saved.get("reason", ""))
	screen._undo(false)
	var restored: Node3D
	for node: Node in screen.preview.get_attachment_root().get_children():
		if str(node.get_meta("sea_attachment").instance_id) == target_id: restored = node
	check(restored != null, "保存后undo删除恢复同ID实例A")
	if restored != null:
		editor.select_nodes([restored])
		check(panel.text_input.text == "REVIEW非法?" and panel.has_unsaved_inputs(), "undo恢复A后非法输入保留且重新dirty")
		editor.select_nodes([other])
		panel._discard()
		check(panel.has_unsaved_inputs(), "放弃B不清除仍安装A的非法缓存")
		editor.select_nodes([restored])
		check(panel.text_input.text == "REVIEW非法?", "从B返回A原非法输入不丢")
		panel._discard()
		check(not panel.has_unsaved_inputs(), "明确放弃A后解除输入dirty")
	direct.append({"action": "review手调回原值历史及deleted dirty缓存", "saved_revision": saved.get("recipe_path", "")})
	await frames(3)

func verify_timeline_and_recovery() -> void:
	controller.cancel_arm(false)
	panel._discard()
	editor.panel.reset_document()
	var baseline: Dictionary = screen.snapshot()
	var attachments: Dictionary = screen.get_attachment_snapshot()
	var count: int = attachments.instances.size()
	var first_height: float = float(baseline.floor_height)
	screen.controls.floor_height.value = first_height + 0.1
	var first: Dictionary = screen.apply_parameters()
	check(first.ok, "时间线第一步房屋改层高", first.get("reason", ""))
	var nodes: Array = screen.preview.get_attachment_root().get_children()
	if nodes.is_empty():
		check(false, "时间线存在真实GUI放置外挂")
		return
	editor.select_nodes([nodes[0]])
	var copied: Dictionary = controller.duplicate_selected()
	check(copied.ok and screen.get_attachment_snapshot().instances.size() == count + 1, "时间线第二步外挂复制", copied.get("reason", ""))
	screen.controls.floor_height.value = first_height + 0.2
	var third: Dictionary = screen.apply_parameters()
	check(third.ok, "时间线第三步房屋改层高", third.get("reason", ""))
	for i: int in 3: screen._undo(false)
	check(is_equal_approx(float(screen.snapshot().floor_height), first_height) and Data.fingerprint(screen.get_attachment_snapshot()) == Data.fingerprint(attachments), "house附件house按chronological undo3还原")
	for i: int in 3: screen._undo(true)
	check(is_equal_approx(float(screen.snapshot().floor_height), first_height + 0.2) and screen.get_attachment_snapshot().instances.size() == count + 1, "跨域redo3精确恢复")
	screen._undo(false)
	screen._undo(false)
	screen.controls.floor_height.value = first_height + 0.3
	var branch: Dictionary = screen.apply_parameters()
	var branch_house: String = HouseRecipe.fingerprint(screen.snapshot())
	var branch_attachments: String = Data.fingerprint(screen.get_attachment_snapshot())
	screen._undo(true)
	check(branch.ok and HouseRecipe.fingerprint(screen.snapshot()) == branch_house and Data.fingerprint(screen.get_attachment_snapshot()) == branch_attachments, "跨域undo后新分支不得重做旧附件")
	var recovery: Dictionary = screen.get_recovery()
	var bad: Dictionary = recovery.duplicate(true)
	bad.attachment_snapshot.instances[0].sea_attachment.anchor.mode = "invalid"
	var house_root: Node3D = screen.preview.get_building_root()
	var layer: Node3D = screen.preview.get_attachment_root()
	var result: Dictionary = screen.restore_recovery(bad)
	check(not result.ok and screen.preview.get_building_root() == house_root and screen.preview.get_attachment_root() == layer and Data.fingerprint(screen.get_attachment_snapshot()) == branch_attachments, "坏外挂恢复原子拒绝保双层节点与历史", result.get("reason", ""))
	result = screen.restore_recovery(recovery)
	check(result.ok and Data.fingerprint(screen.get_attachment_snapshot()) == branch_attachments, "有效整作品恢复保姿态文本", result.get("reason", ""))
	not_tested.erase("house→attachment→house undo3/redo3及跨域分支专项尚未编写执行")
	direct.append({"action": "跨域undo3redo3/branch/recoveryatomic", "fixture": "真实GUI先放置的实例"})
	await frames(3)

func verify_nearest_occlusion() -> void:
	controller.cancel_arm(false)
	panel.reset_document()
	var nodes: Array = screen.preview.get_attachment_root().get_children()
	if nodes.is_empty():
		check(false, "最近点选存在外挂实例")
		return
	var node: Node3D = nodes[0]
	var before := node.transform
	screen.preview.set_view("front")
	screen.buttons.frame_building.pressed.emit()
	await frames(4)
	var camera: Camera3D = screen.preview.camera
	var anchor: Array = node.get_meta("sea_attachment").anchor.local_position
	var center: Vector3 = node.global_transform * Vector3(anchor[0], anchor[1], anchor[2])
	var position: Vector2 = camera.unproject_position(center) * screen.preview.size / Vector2(screen.preview.viewport.size)
	var found := false
	for offset: Vector2 in [Vector2.ZERO, Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		if editor.input.pick(position + offset) and controller.selected == node:
			found = true
			position += offset
			break
	check(found, "最近真实三角点选命中外挂而非背后房屋")
	var other_visibility: Dictionary = {}
	for other: Node3D in nodes:
		if other != node:
			other_visibility[other] = other.visible
			other.hide()
	var origin: Vector3 = node.global_position
	var behind: Vector3 = origin + camera.global_position.direction_to(origin) * 30.0
	node.global_position = behind
	editor.select_nodes([])
	var hidden_pick: bool = editor.input.pick(position)
	check(not hidden_pick and controller.selected == null, "墙体遮挡后的外挂不可被选中")
	node.transform = before
	for other: Node3D in other_visibility: other.visible = other_visibility[other]
	editor.select_nodes([node])
	not_tested.erase("最近命中/墙体遮挡点选专项尚未编写执行")
	direct.append({"action": "最近三角点选及墙体遮挡", "method": "生产input.pick射线；非自动鼠标", "position": str(position)})

func verify_house_preservation() -> void:
	var snapshot: Dictionary = screen.get_attachment_snapshot()
	var work: Node3D = screen.preview.get_work_root()
	var host: Node3D = screen.preview.get_host_asset()
	var building: Node3D = screen.preview.get_building_root()
	screen.controls.floor_height.value = float(screen.snapshot().floor_height) + 0.1
	var patch: Dictionary = screen.apply_parameters()
	check(patch.ok, "房屋层高真实提交", patch.get("reason", ""))
	check(Data.fingerprint(screen.get_attachment_snapshot()) == Data.fingerprint(snapshot), "房屋换层高保全部外挂ID与当前transform")
	check(screen.preview.get_work_root() == work and screen.preview.get_host_asset() == host and screen.preview.get_building_root() != building and host.get_child_count() == 1, "stableWorkRoot及Asset包装保持且building更新")
	direct.append({"action": "house_floor_height_patch", "ok": patch.ok})

func verify_lifecycle() -> void:
	var snapshot := Data.fingerprint(screen.get_attachment_snapshot())
	var before: Dictionary = screen.snapshot()
	panel.text_input.text = "INVALID中文"
	panel._input_changed()
	var recovery: Dictionary = panel.get_recovery()
	var root: Node3D = screen.preview.get_building_root()
	EditorInterface.set_main_screen_editor("3D")
	await frames(5)
	check(panel._preview_timer.is_stopped() and not controller.armed, "真实切标签隐藏停止Timer并取消arm")
	EditorInterface.set_main_screen_editor("老王场景工坊")
	await frames(5)
	check(panel.text_input.text == "INVALID中文" and screen.snapshot() == before and Data.fingerprint(screen.get_attachment_snapshot()) == snapshot, "返回保非法未应用外挂输入与模型")
	screen.set_screen_visible(true)
	screen.set_screen_visible(true)
	await frames(4)
	check(screen.preview.get_building_root() == root, "重复activate不重build房屋")
	check(panel.get_recovery().get("drafts", {}) == recovery.get("drafts", {}), "隐藏恢复保其他上下文缓存")
	await press("放弃当前输入")
	RenderingServer.force_draw()
	var image: Image = screen.preview.viewport.get_texture().get_image()
	var foreground := 0
	if image != null and not image.is_empty():
		var background := image.get_pixel(2, 2)
		for y: int in range(0, image.get_height(), 8):
			for x: int in range(0, image.get_width(), 8):
				var pixel := image.get_pixel(x, y)
				if Vector3(pixel.r - background.r, pixel.g - background.g, pixel.b - background.b).length() > 0.08: foreground += 1
		var path := "res://outputs/workshop_attachments_embedded_live.png"
		image.save_png(path)
		artifacts.append(ProjectSettings.globalize_path(path))
	check(foreground > 50, "直接嵌入viewport非空前景像素而非独立重取景", foreground)

func verify_save_reopen() -> void:
	controller.cancel_arm(false)
	panel.reset_document()
	direct.append({"action": "保存正例前显式放弃所有测试草稿", "method": "panel.reset_document"})
	var snapshot: Dictionary = screen.get_attachment_snapshot()
	var saved: Dictionary = screen.save_building()
	check(saved.ok, "工坊新revision保存完整外挂作品", saved.get("reason", ""))
	if not saved.ok:
		not_tested.append("保存失败，依赖该revision的新建/重开/badsidecar/回编场景未执行")
		return
	var loaded: Dictionary = plugin.store.load_recipe(saved.recipe_path)
	check(loaded.ok and Data.fingerprint(loaded.get("attachments_snapshot", {})) == Data.fingerprint(snapshot), "Store新revision重开保全部外挂姿态文本")
	var result: Dictionary = screen.open_recipe(saved.recipe_path)
	check(result.ok and Data.fingerprint(screen.get_attachment_snapshot()) == Data.fingerprint(snapshot), "screen真实重开完整作品")
	check(not screen.snapshot().has("attachments") and not screen.snapshot().has("attachment_snapshot"), "外挂不写房屋Recipe")
	direct.append({"action": "save_building/open_recipe", "path": saved.recipe_path})
	var before: String = Data.fingerprint(screen.get_attachment_snapshot())
	panel.text_input.text = "INVALID中文"
	panel._input_changed()
	screen.request_document(saved.recipe_path, 771)
	check(screen._confirm.visible, "打开脏外挂要求明确确认")
	screen._confirm.canceled.emit()
	check(Data.fingerprint(screen.get_attachment_snapshot()) == before and panel.text_input.text == "INVALID中文" and screen._document_token != 771, "取消打开保外挂输入模型token")
	panel.reset_document()
	var sidecar: String = str(saved.directory).path_join("building.attachments.json")
	var bytes := FileAccess.get_file_as_bytes(sidecar)
	var file := FileAccess.open(sidecar, FileAccess.WRITE)
	file.store_string("{malformed")
	file.close()
	var bad: Dictionary = screen._open_recipe_now(saved.recipe_path)
	check(not bad.ok and Data.fingerprint(screen.get_attachment_snapshot()) == before, "坏旁车打开原子拒绝保当前作品")
	file = FileAccess.open(sidecar, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var real_store: RefCounted = screen._store
	var fake := FakeStore.new()
	screen.configure({"store": fake})
	var rejected: Dictionary = screen.save_building()
	check(not rejected.ok and fake.calls == 0, "FakeStore含附件必须拒绝不得丢失")
	screen._new_document()
	check(screen.get_attachment_snapshot().instances.is_empty(), "新建清空外挂文档")
	var empty_saved: Dictionary = screen.save_building()
	check(empty_saved.ok and fake.calls == 1, "FakeStore仅空外挂兼容旧export_revision", empty_saved.get("reason", ""))
	screen.configure({"store": real_store})
	var reopened: Dictionary = screen._open_recipe_now(saved.recipe_path)
	check(reopened.ok and Data.fingerprint(screen.get_attachment_snapshot()) == before, "新建后重开保全部外挂")
	direct.append({"action": "取消打开/badsidecar/新建/FakeStore空兼容", "path": saved.recipe_path})
	not_tested.erase("new/open/cancel/badsidecar/recoveryatomic/FakeStore兼容专项尚未编写执行")

func verify_layouts() -> void:
	var parent := screen.get_parent()
	var index := screen.get_index()
	var host := SubViewport.new()
	host.name = "WorkshopAttachmentsLayoutProbe"
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	plugin.add_child(host)
	screen.set_screen_visible(false)
	screen.reparent(host)
	screen.set_screen_visible(true)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for target: Vector2i in [Vector2i(1280, 800), Vector2i(1000, 700), Vector2i(860, 600)]:
		host.size = target
		screen.size = Vector2(target)
		screen._left_panel.show()
		screen._right_panel.hide()
		screen._on_layout_resized()
		screen._select_page(screen.PAGES.find("外挂"))
		await frames(8)
		panel._show_gallery(true)
		await frames(4)
		screen.preview.set_view("perspective")
		screen.buttons.frame_building.pressed.emit()
		await frames(4)
		await reveal(panel.gallery)
		check_layout_bounds(target, "gallery")
		var model: Rect2 = screen.preview.get_global_rect()
		var metric := {"target": str(target), "screen": str(screen.size), "preview": str(model), "width_ratio": model.size.x / target.x, "height_ratio": model.size.y / target.y}
		layouts.append(metric)
		check(screen.size.is_equal_approx(Vector2(target)), "真实主屏尺寸：" + str(target), metric)
		check(model.size.x >= target.x * 0.52 and model.size.y >= target.y * 0.60, "原52%宽60%高门禁不降：" + str(target), metric)
		var nav: Button = screen.buttons["module_%02d" % screen.PAGES.find("外挂")]
		check(nav.is_visible_in_tree() and screen._module_strip.get_global_rect().encloses(nav.get_global_rect()), "外挂主nav滚入可见：" + str(target))
		panel._show_gallery(false)
		await frames(4)
		check_layout_bounds(target, "editor")
		for text: String in ["贴到当前房屋", "应用到选中外挂", "复制", "删除", "重新贴合…", "取消贴面", "放弃当前输入"]:
			var action := find_button(text)
			if action == null:
				check(false, "编辑按钮可达：" + text)
				continue
			await reveal(action)
			check(action.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(target)).encloses(action.get_global_rect()), "滚动可达编辑按钮：" + text + str(target), action.get_global_rect())
			check(action.get_theme_font_size("font_size") >= 18, "按钮字体至少18：" + text)
		check(panel.text_input.get_theme_font_size("font_size") >= 16, "文本字体至少16：" + str(target))
		RenderingServer.force_draw()
		var image: Image = host.get_texture().get_image()
		var path := "res://outputs/workshop_attachments_layout_%dx%d.png" % [target.x, target.y]
		check(image != null and image.get_size() == target and image.save_png(path) == OK, "真实内嵌工坊三档截图：" + str(target))
		artifacts.append(ProjectSettings.globalize_path(path))
		panel._show_gallery(true)
		await frames(4)
		await reveal(panel.gallery)
		check_layout_bounds(target, "gallery_return")
		RenderingServer.force_draw()
		var gallery_path := "res://outputs/workshop_attachments_gallery_%dx%d.png" % [target.x, target.y]
		check(host.get_texture().get_image().save_png(gallery_path) == OK, "返回图库真实整屏截图：" + str(target))
		artifacts.append(ProjectSettings.globalize_path(gallery_path))
	screen.set_screen_visible(false)
	screen.reparent(parent)
	screen.set_screen_visible(true)
	parent.move_child(screen, index)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.queue_free()
	await frames(5)
	screen._on_layout_resized()
	await frames(3)

func verify_scene_context() -> void:
	var assembly: EditorPlugin
	for candidate: Node in plugin.get_parent().get_children():
		if candidate is EditorPlugin and candidate.get_script() != null and candidate.get_script().resource_path == "res://addons/scene_assembly/plugin.gd": assembly = candidate
	check(assembly != null, "场景装配真实插件已启用")
	if assembly == null: return
	panel.reset_document()
	var saved: Dictionary = screen.save_building()
	check(saved.ok, "场景回编前作品保存", saved.get("reason", ""))
	if not saved.ok: return
	var root := Node3D.new()
	root.name = "AttachmentContextFixture"
	var packed := PackedScene.new()
	packed.pack(root)
	var fixture := "res://outputs/workshop_attachments_context.tscn"
	ResourceSaver.save(packed, fixture)
	root.free()
	EditorInterface.open_scene_from_path(fixture)
	await frames(12)
	root = EditorInterface.get_edited_scene_root() as Node3D
	var library = load("res://addons/scene_assembly/library.gd")
	var entry: Dictionary = library.describe(saved.recipe_path, "building")
	var inserted: Dictionary = assembly.insert_candidate(entry, Vector3(2, 1, 3))
	check(inserted.get("ok", false), "完整作品作为场景Asset附件兄弟层导入")
	if not inserted.get("ok", false): return
	var target: Node3D = inserted.placement
	var other: Dictionary = assembly.insert_candidate(entry, Vector3(20, 2, -5))
	check(other.get("ok", false), "同款第二实例夹具")
	if not other.get("ok", false): return
	var sibling: Node3D = other.placement
	var sibling_transform := sibling.transform
	var sibling_asset: Node = sibling.get_node("Asset")
	var before: Dictionary = Data.capture(target.get_node("Attachments"))
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(target)
	assembly.edit_selected()
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	await frames(4)
	check(not assembly.binding.is_empty() and Data.fingerprint(screen.get_attachment_snapshot()) == Data.fingerprint(before), "场景已有sibling外挂通过context导入不丢")
	var workshop_button: Button
	for button: Node in assembly.dock.find_children("*", "Button", true, false):
		if button.text == "到建筑工坊编辑外挂": workshop_button = button
	check(workshop_button != null, "场景到建筑工坊编辑外挂按钮存在")
	var doc_before: String = HouseRecipe.fingerprint(screen.snapshot())
	var attached_before: String = Data.fingerprint(screen.get_attachment_snapshot())
	if workshop_button != null:
		screen._select_page(0)
		EditorInterface.set_main_screen_editor("3D")
		await frames(5)
		await click(workshop_button)
		await frames(4)
		check(screen._page_picker.selected == 9 and HouseRecipe.fingerprint(screen.snapshot()) == doc_before and Data.fingerprint(screen.get_attachment_snapshot()) == attached_before, "当前实例点场景按钮直达page9且不改doc")
		selection.clear()
		screen._select_page(0)
		EditorInterface.set_main_screen_editor("3D")
		await frames(5)
		await click(workshop_button)
		await frames(4)
		check(screen._page_picker.selected == 9 and HouseRecipe.fingerprint(screen.snapshot()) == doc_before and Data.fingerprint(screen.get_attachment_snapshot()) == attached_before, "空选择点场景按钮直达page9且不改doc")
		selection.add_node(target)
	var old_asset: Node = target.get_node("Asset")
	var old_layer: Node = target.get_node("Attachments")
	var current_transform := target.transform
	var old_nodes: Array = old_layer.get_children()
	var old_transforms: Array = []
	for node: Node3D in old_nodes: old_transforms.append(node.transform)
	selection.clear()
	selection.add_node(old_nodes[0])
	await frames(2)
	var selected_before: Array = selection.get_selected_nodes().duplicate()
	screen.controls.floor_height.value = float(screen.snapshot().floor_height) + 0.1
	check(screen.apply_parameters().ok, "仅修改房屋参数且外挂snapshot未改")
	check(Data.fingerprint(screen.get_attachment_snapshot()) == Data.fingerprint(before), "未编辑外挂正对照保存前指纹相同")
	var shell_saved: Dictionary = screen.save_building()
	check(shell_saved.ok and target.get_node("Asset") != old_asset and target.get_node("Attachments") == old_layer, "仅房屋save只替Asset并保外挂layer身份")
	var identities_preserved := old_layer.get_children() == old_nodes
	for index: int in old_nodes.size():
		identities_preserved = identities_preserved and old_nodes[index].is_inside_tree() and old_nodes[index].transform == old_transforms[index]
	check(identities_preserved and selection.get_selected_nodes() == selected_before, "未改外挂save保所有子node身份transform及selection")
	check(assembly.binding.get("attachments_fingerprint", "") == Data.fingerprint(before), "未改外挂save仍同步binding指纹")
	var history: UndoRedo = assembly.get_undo_redo().get_history_undo_redo(assembly.get_undo_redo().get_object_history_id(root))
	history.undo()
	check(target.get_node("Asset") == old_asset and target.get_node("Attachments") == old_layer and old_layer.get_children() == old_nodes, "仅房屋save单undo保原外挂对象")
	history.redo()
	check(target.get_node("Asset") != old_asset and target.get_node("Attachments") == old_layer and selection.get_selected_nodes() == selected_before, "仅房屋save单redo保外挂与selection")
	old_asset = target.get_node("Asset")
	var work_nodes: Array = screen.preview.get_attachment_root().get_children()
	var metadata: Dictionary = work_nodes[0].get_meta("sea_attachment").duplicate(true)
	metadata.host_revision = "verification_metadata_only_change"
	work_nodes[0].set_meta("sea_attachment", metadata)
	var edited: Dictionary = screen.get_attachment_snapshot()
	check(Data.fingerprint(edited) != Data.fingerprint(before) and edited.instances[0].transform == before.instances[0].transform, "仅metadata变更须改变snapshot指纹而非transform")
	var next: Dictionary = screen.save_building()
	check(next.ok and target.get_node("Asset") != old_asset and target.get_node("Attachments") != old_layer, "附件snapshot真改保存一次原子替换场景双层")
	check(target.get_child_count() == 2 and Data.fingerprint(Data.capture(target.get_node("Attachments"))) == Data.fingerprint(edited), "不复制叠加且保存metadata变更与原姿态")
	history.undo()
	check(target.get_node("Asset") == old_asset and target.get_node("Attachments") == old_layer and target.transform == current_transform, "单次场景undo同时还原Asset及外挂层")
	history.redo()
	check(target.get_node("Asset") != old_asset and target.get_node("Attachments") != old_layer, "单次场景redo同时恢复双层")
	check(assembly.binding.get("attachments_fingerprint", "") == Data.fingerprint(edited), "已编辑外挂save更新binding为保存指纹")
	check(sibling.transform == sibling_transform and sibling.get_node("Asset") == sibling_asset, "保存不改同款其它实例或transform")
	selection.clear()
	selection.add_node(target)
	assembly.edit_selected()
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	await frames(4)
	var layer: Node3D = target.get_node("Attachments")
	var concurrent: Node3D = layer.get_child(0)
	concurrent.position.x += 0.123
	var conflict_fingerprint := Data.fingerprint(Data.capture(layer))
	var conflict_asset: Node = target.get_node("Asset")
	var conflict: Dictionary = screen.save_building()
	check(conflict.ok and FileAccess.file_exists(conflict.recipe_path), "并发附件冲突仍保留新revision")
	check(target.get_node("Asset") == conflict_asset and target.get_node("Attachments") == layer and Data.fingerprint(Data.capture(layer)) == conflict_fingerprint, "并发附件改变明确拒替换且保现场新状态")
	selection.clear()
	selection.add_node(target)
	assembly.edit_selected()
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	await frames(4)
	var concurrent_meta: Dictionary = concurrent.get_meta("sea_attachment").duplicate(true)
	concurrent_meta.host_revision = "concurrent_metadata_change"
	concurrent.set_meta("sea_attachment", concurrent_meta)
	var metadata_conflict_fp := Data.fingerprint(Data.capture(layer))
	var metadata_conflict: Dictionary = screen.save_building()
	check(metadata_conflict.ok and FileAccess.file_exists(metadata_conflict.recipe_path) and target.get_node("Asset") == conflict_asset and target.get_node("Attachments") == layer and Data.fingerprint(Data.capture(layer)) == metadata_conflict_fp, "仅metadata并发改变同样拒替换且保新revision")
	var empty_snapshot: Dictionary = Data.empty_snapshot()
	empty_snapshot.layer_transform[9] = 0.321
	var empty_built: Dictionary = Data.build(empty_snapshot)
	var prepared_empty: Dictionary = screen._prepare_work_document(screen.snapshot(), screen.session.catalog, empty_snapshot)
	check(empty_built.ok and prepared_empty.ok, "非identity空层测试作品有效")
	if empty_built.ok and prepared_empty.ok:
		selection.clear()
		selection.add_node(target)
		for node: Node in layer.get_children():
			layer.remove_child(node)
			node.free()
		layer.transform = empty_built.root.transform
		empty_built.root.free()
		selection.clear()
		selection.add_node(target)
		assembly.edit_selected()
		if screen._confirm.visible:
			screen._confirm.hide()
			screen._confirm.confirmed.emit()
		await frames(4)
		prepared_empty.built.root.free()
		prepared_empty.attachments.root.free()
		var empty_save: Dictionary = screen.save_building()
		check(empty_save.ok and target.get_node("Attachments") == layer and is_equal_approx(layer.position.x, 0.321), "未改非identity空层保存保身份与局部变换")
		screen.preview.get_attachment_root().position.x += 0.123
		var changed_empty: Dictionary = screen.save_building()
		check(changed_empty.ok and target.get_node("Attachments") != layer and is_equal_approx(target.get_node("Attachments").position.x, 0.444), "空层变换改变必须识别并替换不能仅比较instances")
	elif empty_built.ok:
		empty_built.root.free()
	direct.append({"action": "真实scene context双层保存/单undo/并发冲突", "fixture": fixture, "new_revision": conflict.get("recipe_path", "")})
	not_tested.erase("回编场景context导入、双层单undo替换及并发附件冲突专项尚未编写执行")

func check_layout_bounds(target: Vector2i, stage: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(target))
	var model: Rect2 = screen.preview.get_global_rect()
	var diagnostics: Dictionary = screen.get_attachment_layout_diagnostics()
	layouts.append({"stage": stage, "target": str(target), "diagnostics": diagnostics})
	print("[workshop-attachments-layout] ", stage, " ", str(target), " ", JSON.stringify(diagnostics))
	check(bounds.encloses(model), "预览实际rect包含于screen：" + stage + str(target), model)
	check(bounds.encloses(screen._left_panel.get_global_rect()), "左栏实际rect包含于screen：" + stage + str(target), screen._left_panel.get_global_rect())
	check(model.size.x >= target.x * 0.52 and model.size.y >= target.y * 0.60, "各模式52%宽60%高门禁：" + stage + str(target), model)
	if stage.begins_with("gallery"):
		check(bounds.encloses(panel.gallery.get_global_rect()) and panel.gallery.size.y >= 160, "图库160高并包含于screen：" + stage + str(target), panel.gallery.get_global_rect())
	RenderingServer.force_draw()
	var image: Image = screen.preview.viewport.get_texture().get_image()
	var foreground := 0
	if image != null and not image.is_empty():
		var background := image.get_pixel(2, 2)
		for y: int in range(0, image.get_height(), 8):
			for x: int in range(0, image.get_width(), 8):
				var pixel := image.get_pixel(x, y)
				if Vector3(pixel.r - background.r, pixel.g - background.g, pixel.b - background.b).length() > 0.08: foreground += 1
	check(foreground > 50, "布局后真实嵌入像素非空：" + stage + str(target), foreground)
	var box: AABB = screen.preview._model_aabb()
	for corner: int in 8:
		var projected: Vector2 = screen.preview.camera.unproject_position(box.get_endpoint(corner))
		check(Rect2(Vector2.ZERO, Vector2(screen.preview.viewport.size)).has_point(projected), "整栋八角不裁墙：" + stage + str(target) + "/" + str(corner), projected)

func finish() -> void:
	plugin.get_window().always_on_top = previous_on_top
	var report := {"suite": "workshop-attachments-editor", "passed": failures.is_empty(), "checks": checks.size(), "check_details": checks, "failures": failures, "scope": "真实老王场景工坊内嵌外挂页；自动GUI单路Window.push_input窗口局部坐标并Window.warp_mouse同步引擎drag查询位置，不使用Input.parse_input_event，不签人工物理鼠标/OS焦点或美术终验；直接调用分列", "automatic_gui": gui, "direct_call": direct, "diagnostics": diagnostics, "layouts": layouts, "artifacts": artifacts, "not_tested": not_tested, "expected_failures": [], "exit_code": 0 if failures.is_empty() else 1}
	var file := FileAccess.open("res://outputs/workshop_attachments_editor_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-attachments-editor] %d checks, %d failures" % [checks.size(), failures.size()])
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
