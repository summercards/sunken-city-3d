@tool
extends RefCounted
## 双工坊专项；只由隔离 runner 分流，绝不加载完整 plant 回归。

const OUT := "res://outputs/workshop_switch"
const HOUSE_PLUGIN := "res://addons/building_workshop/plugin.gd"
const HouseRecipe = preload("res://src/workshop/recipe.gd")

var _tree: SceneTree
var _plant_plugin: EditorPlugin
var _house_plugin: EditorPlugin
var _plant: Control
var _house: Control
var _checks: Array[Dictionary] = []
var _failures: Array[String] = []
var _artifacts: Array[String] = []
var _samples: Array[Dictionary] = []
var _not_tested: Array[String] = [
	"真实产品脚本热重载未测：仅模拟旧 shape 实例后调用迁移入口，不执行 reload。",
	"树草稿 timer 仅显式 emit 真实 timeout 信号并检查原连接；未等待真实 4 秒自然到期，未执行插件退出。草稿保护预期拒绝仅产生 Warning，不计作 unexpected error。",
	"不统计底层 Generator 调用次数；一次返回提交以 Session changed、历史、模型替换计数和队列诊断交叉验证，失败不重试以 timer/attempted_input/failed 队列和状态保持核验。",
	"滑块事务通过 drag_started/value_changed/drag_ended 信号建立并用真实主屏标签点击中断；未签物理按住左键跨标签的 GUI 捕获行为。",
	"人工物理鼠标、真实跨进程恢复、性能和艺术终验未测。"
]
var _plant_changes := 0
var _house_changes := 0
var _plant_installs := 0
var _house_installs := 0
var _started: int
var _finished := false

static func run(plugin: EditorPlugin) -> void:
	var verifier: RefCounted = load("res://addons/plant_editor/switch_verification.gd").new()
	await verifier._execute(plugin)

func _check(label: String, ok: bool, detail: Variant = "") -> bool:
	_checks.append({"label": label, "ok": ok, "detail": str(detail)})
	if not ok:
		_failures.append(label)
		printerr("[workshop-switch-check] %s: %s" % [label, str(detail)])
	return ok

func _execute(plugin: EditorPlugin) -> void:
	_tree = plugin.get_tree()
	_plant_plugin = plugin
	_started = Time.get_ticks_msec()
	if not _protection():
		print("[workshop-switch] %d checks, %d failures" % [_checks.size(), _failures.size()])
		_tree.quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_tree.create_timer(170.0).timeout.connect(_deadline)
	# 初次扫描可能持有模态导入窗口；按真实时间有界等待，不按千帧无限等。
	var until: int = Time.get_ticks_msec() + 30000
	while EditorInterface.get_resource_filesystem().is_scanning() and Time.get_ticks_msec() < until:
		await _frames(1)
	if not _check("资源扫描在限时内完成", not EditorInterface.get_resource_filesystem().is_scanning()):
		_finish()
		return
	await _tree.create_timer(0.8).timeout
	_house_plugin = _find_plugin(_tree.root)
	_plant = plugin.get("screen") as Control
	if _house_plugin != null:
		_house = _house_plugin.get("screen") as Control
	if not _check("双产品插件真实主屏已就绪", is_instance_valid(_plant) and is_instance_valid(_house)):
		_finish()
		return
	var window: Window = EditorInterface.get_base_control().get_window()
	window.always_on_top = true
	window.grab_focus()
	await _frames(6)
	var edited: Node = EditorInterface.get_edited_scene_root()
	_check("启动未打开编辑场景", edited == null)
	var sources: Dictionary = {}
	for path: String in [HOUSE_PLUGIN, "res://addons/building_workshop/editor_screen.gd", "res://addons/building_workshop/editor_preview.gd", "res://addons/plant_editor/plugin.gd", "res://addons/plant_editor/editor_screen.gd", "res://addons/plant_editor/preview.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	if not await _switch(false, "初次房屋"):
		_finish()
		return
	if not await _switch(true, "初次树木"):
		_finish()
		return
	_plant.session.changed.connect(_on_plant_changed)
	_house.session.changed.connect(_on_house_changed)
	_plant.preview._plant_space.child_entered_tree.connect(_on_plant_model)
	_house.preview._model_root.child_entered_tree.connect(_on_house_model)
	_check("两个预览使用互不相同的 World3D", _plant.preview.viewport.world_3d != _house.preview.viewport.world_3d and _plant.preview.viewport.world_3d != _tree.root.world_3d)
	await _roundtrips()
	await _pending_plant()
	await _pending_house()
	await _failed_inputs()
	await _drag_switch(true)
	await _drag_switch(false)
	await _migration()
	await _rebuild()
	await _draft_protection()
	_check("专项结束未打开或替换编辑场景", EditorInterface.get_edited_scene_root() == edited)
	for path: String in sources:
		_check("产品源码未改 " + path, FileAccess.get_sha256(path) == sources[path])
	_finish()

func _protection() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var cli: bool = Engine.is_editor_hint() and args.has("--editor") and not args.has("--script") and not args.has("-s") and user_args.has("--plant-editor-verify") and user_args.has("--workshop-switch-verify")
	_check("真实 editor 双 flag 且非 script", cli)
	var root: String = ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var expected: String = OS.get_environment("SEA_WORKSHOP_SWITCH_PROJECT").simplify_path().trim_suffix("/")
	var token: String = str(ProjectSettings.get_setting("verification/workshop_switch_token", ""))
	var isolated: bool = not token.is_empty() and token == OS.get_environment("SEA_WORKSHOP_SWITCH_TOKEN") and root == expected and root.get_file() == "project" and not DirAccess.dir_exists_absolute("res://src/bootstrap") and not FileAccess.file_exists("res://scenes/main.tscn")
	_check("拒绝 production：仅接受 runner 隔离副本与令牌", isolated, root)
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var safe_user: bool = ProjectSettings.get_setting("application/config/use_custom_user_dir", false) and str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") and user_root == OS.get_environment("SEA_WORKSHOP_SWITCH_USER").simplify_path().trim_suffix("/")
	_check("user 路径与 runner 独立槽一致", safe_user, user_root)
	var minimal := str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty()
	for property: Dictionary in ProjectSettings.get_property_list():
		if str(property.name).begins_with("autoload/"):
			minimal = false
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	minimal = minimal and enabled.size() == 2 and enabled.has("res://addons/plant_editor/plugin.cfg") and enabled.has("res://addons/building_workshop/plugin.cfg")
	for node: Node in _tree.root.find_children("*", "", true, false):
		var script: Script = node.get_script() as Script
		if node.name == &"Main" or (script != null and script.resource_path.begins_with("res://src/bootstrap/")):
			minimal = false
	_check("minimal 双插件无 Main 无 autoload", minimal)
	return cli and isolated and safe_user and minimal

func _find_plugin(node: Node) -> EditorPlugin:
	var script: Script = node.get_script() as Script
	if node is EditorPlugin and script != null and script.resource_path == HOUSE_PLUGIN:
		return node as EditorPlugin
	for child: Node in node.get_children():
		var found: EditorPlugin = _find_plugin(child)
		if found != null:
			return found
	return null

func _tab(node: Node, text: String) -> Button:
	if node is Button and not node is MenuButton and node.text.contains(text) and node.is_visible_in_tree() and not node.disabled:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _tab(child, text)
		if found != null:
			return found
	return null

func _mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	Input.warp_mouse(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.button_mask = (1 << (button - 1)) if pressed and button <= MOUSE_BUTTON_MIDDLE else 0
	Input.parse_input_event(event)

func _motion(point: Vector2, relative: Vector2, mask: int) -> void:
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = mask
	Input.parse_input_event(event)

func _click_tab(plant: bool) -> bool:
	var text: String = "树木工坊" if plant else "老王场景工坊"
	var button: Button = _tab(EditorInterface.get_base_control(), text)
	if not _check("找到真实主屏标签 " + text, button != null):
		return false
	var point: Vector2 = button.get_global_rect().get_center()
	print("[workshop-switch-tab] ", text, " rect=", button.get_global_rect(), " window=", button.get_window().size, " selected=", button.button_pressed)
	_mouse(point, MOUSE_BUTTON_LEFT, true)
	_mouse(point, MOUSE_BUTTON_LEFT, false)
	Input.flush_buffered_events()
	# 本函数不等待：排队测试在同一帧切换，160ms 前提由时间与状态共同验证。
	return true

func _switch(plant: bool, label: String) -> bool:
	if not _click_tab(plant):
		return false
	await _frames(6)
	var passed: bool = _visible(plant, label)
	if not passed:
		RenderingServer.force_draw()
		var image: Image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		if image != null:
			image.save_png(ProjectSettings.globalize_path(OUT.path_join("failed_switch_editor.png")))
		print("[workshop-switch-state] plant=", _plant.visible, " house=", _house.visible, " house_status=", _house.get_window_preview_state())
	return passed

func _visible(plant: bool, label: String) -> bool:
	var active: Control = _plant if plant else _house
	var hidden: Control = _house if plant else _plant
	var preview: Control = active.preview
	var visible_ok: bool = active.is_visible_in_tree() and not hidden.is_visible_in_tree()
	_check(label + " 唯一实际可见主屏", visible_ok)
	var area: Rect2 = preview.get_global_rect().intersection(active.get_global_rect())
	var viewport: SubViewport = preview.viewport
	_check(label + " 非零预览面积与真实渲染尺寸", area.size.x > 100 and area.size.y > 100 and viewport.size.x > 1 and viewport.size.y > 1, [area, viewport.size])
	_check(label + " 可见更新隐藏停绘", viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and hidden.preview.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	var model: Node3D = _model(plant)
	_check(label + " 有效模型与当前相机", is_instance_valid(model) and model.is_inside_tree() and not model.find_children("*", "MeshInstance3D", true, false).is_empty() and preview.camera.current and viewport.get_camera_3d() == preview.camera)
	_samples.append({"label": label, "plant": plant, "state": _state(plant), "area": str(area), "viewport": str(viewport.size), "camera": _camera(plant)})
	return visible_ok

func _model(plant: bool) -> Node3D:
	if plant:
		return _plant.preview.model as Node3D
	var parent: Node = _house.preview._model_root
	return parent.get_child(0) as Node3D if parent.get_child_count() == 1 else null

func _state(plant: bool) -> String:
	if plant:
		return _plant.session.state_fingerprint()
	return HouseRecipe.fingerprint(_house.snapshot())

func _camera(plant: bool) -> Dictionary:
	var camera: Camera3D = (_plant if plant else _house).preview.camera
	return {"transform": str(camera.transform), "projection": camera.projection, "size": camera.size, "fov": camera.fov}

func _history(plant: bool) -> String:
	# 只读历史证据；不修改 Session 栈，也不以 can_undo 的存在替代内容。
	var session: RefCounted = (_plant if plant else _house).session
	return JSON.stringify({"undo": session.get("_undo"), "redo": session.get("_redo")}, "", true, true)

func _undo_size(plant: bool) -> int:
	var entries: Array = (_plant if plant else _house).session.get("_undo")
	return entries.size()

func _on_plant_changed() -> void:
	_plant_changes += 1

func _on_house_changed() -> void:
	_house_changes += 1

func _on_plant_model(_node: Node) -> void:
	_plant_installs += 1

func _on_house_model(_node: Node) -> void:
	_house_installs += 1

func _roundtrips() -> void:
	for index: int in 3:
		for plant: bool in [false, true]:
			var before: String = _state(plant)
			var history: String = _history(plant)
			var camera: Dictionary = _camera(plant)
			var root: Node3D = _model(plant)
			await _switch(plant, "往返 %d/%s" % [index, plant])
			_check("往返保留配方历史模型镜头 %d/%s" % [index, plant], _state(plant) == before and _history(plant) == history and _model(plant) == root and _camera(plant) == camera)
			await _navigate(plant)
			if index == 0:
				await _capture("roundtrip_" + ("plant" if plant else "house"), plant)
	var clock: float = _plant.preview.local_time
	await _tree.create_timer(0.22).timeout
	_check("树可见风 clock 推进", _plant.preview.local_time > clock)
	await _switch(false, "风隐藏")
	clock = _plant.preview.local_time
	var materials: Array = _plant.preview.materials()
	var samples: Array = []
	_check("隐藏风测试有实际材质而非空循环", not materials.is_empty())
	for material: ShaderMaterial in materials:
		samples.append(material.get_shader_parameter("local_time"))
		_check("隐藏材质关闭本地风", material.get_shader_parameter("preview_wind") == false)
	await _tree.create_timer(0.3).timeout
	_check("隐藏风 clock 与材质采样停", is_equal_approx(_plant.preview.local_time, clock) and not _plant.preview.is_processing())
	for index: int in materials.size():
		_check("隐藏材质时钟未推进 %d" % index, materials[index].get_shader_parameter("local_time") == samples[index])
	await _switch(true, "风返回恢复")
	await _tree.create_timer(0.15).timeout
	_check("返回风 clock 从保留时刻继续", _plant.preview.local_time > clock and _plant.preview.is_processing())

func _navigate(plant: bool) -> void:
	var preview: Control = (_plant if plant else _house).preview
	var surface: Control = preview._input_surface if plant else preview
	var before: Dictionary = _camera(plant)
	var state: String = _state(plant)
	var history: String = _history(plant)
	var point: Vector2 = surface.get_global_rect().get_center()
	Input.warp_mouse(point)
	await _frames(2)
	_mouse(point, MOUSE_BUTTON_WHEEL_UP, true)
	_mouse(point, MOUSE_BUTTON_WHEEL_UP, false)
	await _frames(2)
	_check("切回真实滚轮生效 %s" % plant, _camera(plant) != before)
	before = _camera(plant)
	_mouse(point, MOUSE_BUTTON_MIDDLE, true)
	_motion(point + Vector2(28, 13), Vector2(28, 13), MOUSE_BUTTON_MASK_MIDDLE)
	_mouse(point + Vector2(28, 13), MOUSE_BUTTON_MIDDLE, false)
	await _frames(2)
	_check("切回真实拖动生效且不写状态历史 %s" % plant, _camera(plant) != before and _state(plant) == state and _history(plant) == history)

func _pending_plant() -> void:
	await _switch(true, "树参数排队前")
	var before: String = _state(true)
	var other: String = _state(false)
	var root: Node3D = _model(true)
	var camera: Dictionary = _camera(true)
	var count: int = _plant_changes
	var installs: int = _plant_installs
	var history: int = _undo_size(true)
	var start: int = Time.get_ticks_msec()
	_plant.controls.height.value += 0.1
	_check("树参数真实 value_changed 已排队", not _plant._timer.is_stopped() and _plant.has_pending_fields())
	_click_tab(false)
	var switch_ms: int = Time.get_ticks_msec() - start
	await _frames(2)
	_check("树排队在160ms前发出切换且实际隐藏", switch_ms < 160 and not _plant.is_visible_in_tree(), switch_ms)
	await _tree.create_timer(0.28).timeout
	_check("树 pending 隐藏不提交不换模型", _state(true) == before and _model(true) == root and _plant_changes == count and _plant_installs == installs and _plant._timer.is_stopped() and _plant.has_pending_fields())
	await _switch(true, "树 pending 返回")
	await _tree.create_timer(0.35).timeout
	_check("树返回恰好一提交一模型一历史", _plant_changes == count + 1 and _plant_installs == installs + 1 and _undo_size(true) == history + 1 and not _plant.has_pending_fields() and _state(true) != before)
	_check("树 pending 保镜头且不串房屋", _camera(true) == camera and _state(false) == other)
	await _switch(false, "树提交后切走")
	await _switch(true, "树提交后再返")
	await _tree.create_timer(0.22).timeout
	_check("树再返不重复提交", _plant_changes == count + 1 and _plant_installs == installs + 1)

func _pending_house() -> void:
	await _switch(false, "房屋参数排队前")
	var before: String = _state(false)
	var other: String = _state(true)
	var root: Node3D = _model(false)
	var camera: Dictionary = _camera(false)
	var count: int = _house_changes
	var installs: int = _house_installs
	var history: int = _undo_size(false)
	var start: int = Time.get_ticks_msec()
	_house.controls.architecture_window_frame_width.value += 0.001
	_check("房屋真实 value_changed 已排队", _house.get_window_preview_state().timer_running and not _house.get_window_preview_state().pending.is_empty())
	_click_tab(true)
	var switch_ms: int = Time.get_ticks_msec() - start
	await _frames(2)
	_check("房屋排队在160ms前发出切换且实际隐藏", switch_ms < 160 and not _house.is_visible_in_tree(), switch_ms)
	await _tree.create_timer(0.28).timeout
	var pending: Dictionary = _house.get_window_preview_state()
	_check("房屋 pending 隐藏不提交不换模型", _state(false) == before and _model(false) == root and _house_changes == count and _house_installs == installs and not pending.timer_running and not pending.pending.is_empty())
	await _switch(false, "房屋 pending 返回")
	await _tree.create_timer(0.35).timeout
	_check("房屋返回恰好一提交一模型一历史", _house_changes == count + 1 and _house_installs == installs + 1 and _undo_size(false) == history + 1 and _house.get_window_preview_state().pending.is_empty() and _state(false) != before)
	_check("房屋 pending 保镜头且不串树", _camera(false) == camera and _state(true) == other)
	await _switch(true, "房屋提交后切走")
	await _switch(false, "房屋提交后再返")
	await _tree.create_timer(0.22).timeout
	_check("房屋再返不重复提交", _house_changes == count + 1 and _house_installs == installs + 1)

func _failed_inputs() -> void:
	await _switch(true, "树失败输入前")
	var state: String = _state(true)
	var history: String = _history(true)
	var root: Node3D = _model(true)
	var camera: Dictionary = _camera(true)
	# 明确的非法边界输入，经产品字段端口进入同一调度链，不夹回 slider 范围。
	_plant._field("height", -1.0)
	await _tree.create_timer(0.25).timeout
	var attempted: String = _plant._attempted_input
	var details: String = _plant.details
	_check("树失败被实际尝试且保输入", attempted == _plant._input_signature() and _plant.input_recipe.height == -1.0 and _plant.has_pending_fields() and details.contains("未应用"))
	for index: int in 2:
		await _switch(false, "树失败离开 %d" % index)
		await _switch(true, "树失败返回 %d" % index)
		await _tree.create_timer(0.23).timeout
		_check("树失败切屏不重试保状态 %d" % index, _plant._timer.is_stopped() and _plant._attempted_input == attempted and _plant.details == details and _state(true) == state and _history(true) == history and _model(true) == root and _camera(true) == camera)
	_plant._field("height", _plant.snapshot().height)
	await _tree.create_timer(0.24).timeout
	await _switch(false, "房屋失败输入前")
	state = _state(false)
	history = _history(false)
	root = _model(false)
	camera = _camera(false)
	var original: float = _house.controls.architecture_window_height.value
	_house.controls.architecture_window_height.value = 4.75
	await _tree.create_timer(0.25).timeout
	var failed: Dictionary = _house.get_window_preview_state()
	var status: String = _house._last_status_text
	_check("房屋失败被实际尝试且保输入", not failed.failed.is_empty() and not bool(failed.result.get("ok", true)) and _house.controls.architecture_window_height.value == 4.75, failed)
	for index: int in 2:
		await _switch(true, "房屋失败离开 %d" % index)
		await _switch(false, "房屋失败返回 %d" % index)
		await _tree.create_timer(0.23).timeout
		var current: Dictionary = _house.get_window_preview_state()
		_check("房屋失败切屏不重试保状态 %d" % index, not current.timer_running and current.pending.is_empty() and current.failed == failed.failed and current.result == failed.result and _house._last_status_text == status and _state(false) == state and _history(false) == history and _model(false) == root and _camera(false) == camera)
	_house.controls.architecture_window_height.value = original
	await _tree.create_timer(0.25).timeout

func _drag_switch(plant: bool) -> void:
	await _switch(plant, "滑块事务准备 %s" % plant)
	if plant:
		_plant.show_module(0)
	else:
		_house._select_page(1)
	var slider: HSlider = (_plant.controls.height if plant else _house.controls.architecture_window_frame_width) as HSlider
	var scroll: ScrollContainer = (_plant.parameter_scroll if plant else _house._left_panel) as ScrollContainer
	scroll.ensure_control_visible(slider)
	await _frames(4)
	var rect: Rect2 = slider.get_global_rect()
	if not _check("真实滑块有可点击区域 %s" % plant, slider.is_visible_in_tree() and rect.size.x > 20 and scroll.get_global_rect().intersects(rect)):
		return
	var history: int = _undo_size(plant)
	var value: float = slider.value
	# 拖动事务用真实滑块信号建立，主屏切换仍走鼠标路由。
	# 不重复注入同一左键的 pressed 来绕过 GUI 鼠标捕获，也不伪称物理跨控件拖动。
	slider.drag_started.emit()
	slider.value += slider.step
	_check("滑块信号建立拖动事务 %s" % plant, _plant._dragging if plant else not str(_house.get_window_preview_state().drag_key).is_empty())
	_click_tab(not plant)
	await _frames(2)
	slider.drag_ended.emit(true)
	_check("切屏终止滑块拖动合并 %s" % plant, (not _plant._dragging and not _plant._merge_drag) if plant else (str(_house.get_window_preview_state().drag_key).is_empty() and str(_house.get_window_preview_state().history_key).is_empty()))
	var hidden_state: String = _state(plant)
	var hidden_root: Node3D = _model(plant)
	await _tree.create_timer(0.25).timeout
	_check("隐藏拖动事务不继续构建 %s" % plant, _state(plant) == hidden_state and _model(plant) == hidden_root)
	await _switch(plant, "滑块事务返回 %s" % plant)
	await _tree.create_timer(0.3).timeout
	_check("整次滑块事务只有一条历史 %s" % plant, not is_equal_approx(slider.value, value) and _undo_size(plant) == history + 1)
	await _navigate(plant)

func _migration() -> void:
	await _switch(true, "旧 shape 模拟迁移")
	var preview: Control = _plant.preview
	var model: Node3D = preview.model
	var world: World3D = preview.viewport.world_3d
	var viewport: SubViewport = preview.viewport
	var camera: Dictionary = _camera(true)
	var state: String = _state(true)
	var history: String = _history(true)
	# 不是 reload：从已就绪实例移除新导航节点，并还原旧 surface->handler 连接。
	var frame: Control = preview._surface.get_parent() as Control
	preview._input_surface.free()
	preview._input_surface = null
	preview._tools.free()
	preview._tools = null
	preview._surface.reparent(preview, false)
	frame.free()
	preview._surface.mouse_filter = Control.MOUSE_FILTER_STOP
	preview._surface.gui_input.connect(preview._on_input)
	preview._ensure_navigation()
	preview._ensure_navigation()
	await _frames(4)
	_check("模拟迁移保留旧 model/world/viewport/镜头/历史", preview.model == model and preview.viewport == viewport and viewport.world_3d == world and _camera(true) == camera and _state(true) == state and _history(true) == history)
	_check("模拟迁移不重复导航层与 toolbar", preview.find_children("PreviewNavigation", "Control", true, false).size() == 1 and preview.find_children("PreviewTools", "HBoxContainer", true, false).size() == 1 and preview.find_children("PreviewFrame", "Control", true, false).size() == 1)
	_check("模拟迁移拆旧 surface 连接且新路由仅一份", not preview._surface.gui_input.is_connected(preview._on_input) and preview._input_surface.gui_input.get_connections().size() == 1 and preview._input_surface.gui_input.is_connected(preview._on_input))
	await _navigate(true)
	await _capture("simulated_legacy_migration", true)
	await _switch(false, "房屋旧焦点模拟迁移")
	var house_preview: Control = _house.preview
	var old_world: Node3D = house_preview._world
	model = _model(false)
	camera = _camera(false)
	house_preview.focus_exited.disconnect(house_preview._cancel_navigation)
	house_preview.focus_mode = Control.FOCUS_NONE
	house_preview.ensure_navigation_focus()
	house_preview.ensure_navigation_focus()
	_check("房屋模拟迁移只补一次焦点且保 world/model/镜头", house_preview.focus_mode == Control.FOCUS_ALL and house_preview.focus_exited.get_connections().size() == 1 and house_preview._world == old_world and _model(false) == model and _camera(false) == camera)
	await _navigate(false)

func _rebuild() -> void:
	await _switch(false, "active rebuild 前")
	var state: String = _state(false)
	var old: Control = _house
	_house_plugin.rebuild_screen_for_verification()
	_house = _house_plugin.screen
	await _frames(8)
	_check("房屋 rebuild 专用端口保 active 不补 visible", _house != old and _house.is_screen_active() and _house.is_visible_in_tree() and _state(false) == state)
	_visible(false, "active rebuild 后")
	await _navigate(false)
	await _capture("active_rebuild", false)
	await _switch(true, "rebuild 后真实切树")
	await _switch(false, "rebuild 后真实返回房屋")

func _write(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _check("隔离 fixture 可写 " + path, file != null):
		return false
	file.store_string(text)
	file.close()
	return true

func _draft_protection() -> void:
	# 房屋不带其大回归 flag，真实恢复/写入未被 _is_verification 短路。
	var path := "user://building_workshop_editor/recovery.json"
	_check("房屋生产保存路径未被 verification 禁写", not _house_plugin._is_verification())
	var state: String = _state(false)
	var model: Node3D = _model(false)
	var history: String = _history(false)
	var invalid: Dictionary = _house.get_recovery()
	invalid.recipe.floor_height = -1.0
	for kind: String in ["corrupt_json", "invalid_recovery"]:
		# 每例用全新的真实产品插件对象，避免上一负例的粘性锁制造假绿。
		# 不入树、不再注册主屏；只借现有 screen 测其原始 read/save 和恢复回调。
		var probe: EditorPlugin = load(HOUSE_PLUGIN).new()
		probe.screen = _house
		_house.recovery_restore_finished.connect(probe._on_recovery_restored)
		probe._save_external_data()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check("房屋真实写入正对照 " + kind, not probe._is_verification() and not probe.get_recovery_status().write_blocked and parsed is Dictionary and HouseRecipe.fingerprint(parsed.get("recipe", {})) == HouseRecipe.fingerprint(_house.snapshot()))
		var text: String = "{broken-workshop-switch" if kind == "corrupt_json" else JSON.stringify(invalid)
		if _write(path, text):
			var hash_before: String = FileAccess.get_sha256(path)
			var read: Dictionary = probe._read_recovery()
			var rejected: bool = read.is_empty()
			if kind == "invalid_recovery":
				var result: Dictionary = _house.restore_recovery(read)
				rejected = not read.is_empty() and not bool(result.get("ok", true))
			probe._save_external_data()
			_check("产品 read/restore/save 草稿保护 " + kind, rejected and probe.get_recovery_status().write_blocked and FileAccess.get_sha256(path) == hash_before)
		_house.recovery_restore_finished.disconnect(probe._on_recovery_restored)
		probe.free()
	_check("草稿负例保成功模型状态历史", _state(false) == state and _model(false) == model and _history(false) == history)
	# 不伪造插件或覆盖 verification：只在受令牌与隔离目录约束的真实实例上测试。
	var draft_path: String = "user://plant_authoring_draft.json"
	var draft_timer: Timer = _plant_plugin.get("_draft_timer") as Timer
	if not _check("树真实插件 verification 保持开启且隔离草稿 IO 放行", _plant_plugin._is_verification() and _plant_plugin._draft_io_allowed() and _plant_plugin.get("screen") == _plant):
		return
	if not _check("树真实草稿 timer 保持产品保存连接", is_instance_valid(draft_timer) and draft_timer.timeout.is_connected(Callable(_plant_plugin, "_save_draft"))):
		return
	if not _check("树隔离草稿初始无文件，不覆盖遗留 fixture", not FileAccess.file_exists(draft_path) and not FileAccess.file_exists(draft_path + ".tmp")):
		return
	# 树此时隐藏；建立真实非空 pending，避免只证明空队列未变化。
	if not _check("树草稿测试期间隐藏且参数 timer 停止", not _plant.is_visible_in_tree() and _plant._timer.is_stopped()):
		return
	var original_recovery: String = JSON.stringify(_plant.get_recovery(), "", true, true)
	var original_seed: int = int(_plant.input_recipe.seed)
	var pending_seed: int = int(_plant.snapshot().seed) + 1
	_plant._field("seed", pending_seed if pending_seed != original_seed else pending_seed + 1)
	var plant_session: RefCounted = _plant.session
	var plant_state: String = _state(true)
	var plant_history: String = _history(true)
	var plant_model: Node3D = _model(true)
	var plant_recovery: String = JSON.stringify(_plant.get_recovery(), "", true, true)
	var changes: int = _plant_changes
	var installs: int = _plant_installs
	_check("树草稿测试具有真实待应用输入", _plant.has_pending_fields() and _plant._timer.is_stopped())
	var invalid_plant: Dictionary = _plant.get_recovery()
	invalid_plant.session.recipe.height = -1.0
	for kind: String in ["corrupt_json", "invalid_session_recipe"]:
		# 每个负例前先无文件 restore 解锁并实际落盘，排除 verification 短路或上一例锁定的假绿。
		_plant_plugin._restore_draft()
		if not _check("树无文件恢复放行并启动真实 timer " + kind, not FileAccess.file_exists(draft_path) and bool(_plant_plugin.get("_draft_write_allowed")) and not draft_timer.is_stopped()):
			break
		_plant_plugin._save_draft()
		var saved_text: String = FileAccess.get_file_as_string(draft_path) if FileAccess.file_exists(draft_path) else ""
		var saved_parser: JSON = JSON.new()
		var saved_error: Error = saved_parser.parse(saved_text)
		var saved_data: Variant = saved_parser.data
		if not _check("树真实 _save_draft 新建文件正对照 " + kind, saved_error == OK and saved_data is Dictionary and saved_text == JSON.stringify(_plant.get_recovery(), "\t", true, true) and not FileAccess.file_exists(draft_path + ".tmp")):
			break
		var fixture: String = "{broken-plant-switch" if kind == "corrupt_json" else JSON.stringify(invalid_plant, "\t", true, true)
		if not _write(draft_path, fixture):
			break
		var hash_before: String = FileAccess.get_sha256(draft_path)
		_check("树负例确实替换正对照内容 " + kind, not hash_before.is_empty() and fixture != saved_text and FileAccess.get_file_as_string(draft_path) == fixture)
		if kind == "invalid_session_recipe":
			var fixture_parser: JSON = JSON.new()
			var fixture_error: Error = fixture_parser.parse(FileAccess.get_file_as_string(draft_path))
			var fixture_data: Variant = fixture_parser.data
			if not _check("树非法 session recipe fixture 是有效 JSON", fixture_error == OK and fixture_data is Dictionary and fixture_data.session.recipe.height == -1.0):
				break
		_plant_plugin._restore_draft()
		var locked: bool = not bool(_plant_plugin.get("_draft_write_allowed")) and draft_timer.is_stopped()
		var notice: String = str(_plant.get("_draft_notice"))
		var expected_reason: String = "JSON 损坏或根对象不是字典" if kind == "corrupt_json" else "height 超出范围"
		_check("树真实 restore 拒绝并锁写停 timer " + kind, locked and _plant_plugin._draft_io_allowed() and notice.contains("原草稿已保留") and notice.contains(expected_reason) and FileAccess.get_sha256(draft_path) == hash_before, notice)
		_plant_plugin._save_external_data()
		_check("树真实 _save_external_data 不覆盖原 hash " + kind, not bool(_plant_plugin.get("_draft_write_allowed")) and _plant_plugin._draft_io_allowed() and FileAccess.get_sha256(draft_path) == hash_before and not FileAccess.file_exists(draft_path + ".tmp"))
		# 显式发出真实产品 timer 的 timeout；不是等待 4 秒自然触发，也不直接代调保存。
		draft_timer.timeout.emit()
		_check("树真实 timer timeout 显式 emit 不覆盖原 hash（非自然4秒） " + kind, not bool(_plant_plugin.get("_draft_write_allowed")) and draft_timer.is_stopped() and _plant_plugin._draft_io_allowed() and FileAccess.get_sha256(draft_path) == hash_before and not FileAccess.file_exists(draft_path + ".tmp"))
		_check("树草稿负例保 session/model/pending/history " + kind, _plant.session == plant_session and _state(true) == plant_state and _model(true) == plant_model and _history(true) == plant_history and JSON.stringify(_plant.get_recovery(), "", true, true) == plant_recovery and _plant.has_pending_fields() and _plant._timer.is_stopped() and _plant_changes == changes and _plant_installs == installs)
		if kind == "corrupt_json":
			# 只移除本专项刚写入且 hash 未变的 fixture，下一例重新走无文件恢复与正对照。
			if not _check("树首个负例 fixture 保持原 hash", locked and FileAccess.get_sha256(draft_path) == hash_before):
				break
			if not _check("树隔离 fixture 清理以独立开始下一例", DirAccess.remove_absolute(ProjectSettings.globalize_path(draft_path)) == OK):
				break
	_plant._field("seed", original_seed)
	_check("树草稿专项结束恢复原 pending 且保 session/model/history", JSON.stringify(_plant.get_recovery(), "", true, true) == original_recovery and _plant.session == plant_session and _state(true) == plant_state and _model(true) == plant_model and _history(true) == plant_history and _plant._timer.is_stopped() and _plant_changes == changes and _plant_installs == installs)

func _capture(label: String, plant: bool) -> void:
	await _frames(2)
	RenderingServer.force_draw()
	var preview: Control = (_plant if plant else _house).preview
	var image: Image = preview.viewport.get_texture().get_image()
	if not _check(label + " 嵌入 viewport 图像可读", image != null and not image.is_empty()):
		return
	var foreground := 0
	var background: Color = image.get_pixel(0, 0)
	for y: int in range(0, image.get_height(), 4):
		for x: int in range(0, image.get_width(), 4):
			var color: Color = image.get_pixel(x, y)
			if absf(color.r - background.r) + absf(color.g - background.g) + absf(color.b - background.b) > 0.15:
				foreground += 1
	_check(label + " 嵌入预览真实前景像素", foreground > 50, foreground)
	var path: String = OUT.path_join(label + "_preview.png")
	if _check(label + " 预览 PNG 写入", image.save_png(ProjectSettings.globalize_path(path)) == OK):
		_artifacts.append(path)
	var full: Image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	path = OUT.path_join(label + "_editor.png")
	if _check(label + " 整屏 PNG 写入", full != null and not full.is_empty() and full.save_png(ProjectSettings.globalize_path(path)) == OK):
		_artifacts.append(path)

func _frames(count: int) -> void:
	for index: int in count:
		await _tree.process_frame

func _deadline() -> void:
	if not _finished:
		_check("专项170秒内结束", false, "内部限时触发；不冒称完成")
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report: Dictionary = {"checks": _checks.size(), "failures": _failures.size(), "passed": _failures.is_empty(), "results": _checks, "failure_labels": _failures, "artifacts": _artifacts, "samples": _samples, "not_tested": _not_tested, "migration_kind": "旧结构模拟，非真实热重载", "elapsed_ms": Time.get_ticks_msec() - _started}
	var file: FileAccess = FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		printerr("[workshop-switch] 报告不可写")
		_tree.quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("[workshop-switch] %d checks, %d failures" % [_checks.size(), _failures.size()])
	_tree.quit(0 if _failures.is_empty() else 1)
