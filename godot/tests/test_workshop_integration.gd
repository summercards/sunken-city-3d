extends SceneTree

const MAIN_SCENE_PATH = "res://scenes/main.tscn"

var checks: int = 0
var failures: Array[String] = []
var main: Variant = null
var workshop_host: Variant = null
var world_probe: Node = null

class WorldInputProbe extends Node:
	var key_events: int = 0
	var mouse_events: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and (event as InputEventKey).pressed:
			key_events += 1
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			mouse_events += 1

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL [workshop-integration] ", message)

func frames(count: int = 2) -> void:
	for index: int in count:
		await physics_frame
		await process_frame

func send_key(code: int, pressed: bool, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	root.push_input(event, true)

func key(code: int, ctrl: bool = false) -> void:
	send_key(code, true, ctrl)
	await process_frame
	send_key(code, false, ctrl)
	await process_frame

func click_control(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.position = point
	up.global_position = point
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up, true)
	await process_frame

func finite_wait(predicate: Callable, seconds: float, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await frames(1)
	check(false, message)
	return false

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	check(args.has("--nosave") and args.has("--skip-title"), "集成测试要求 runner 传入 --nosave 与 --skip-title")
	check(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)), "runner 已隔离 user 目录")

	main = load(MAIN_SCENE_PATH).instantiate()
	if main == null:
		check(false, "正式 Main PackedScene 可实例化")
		finish()
		return
	main.set("_autosave_on", false)
	root.add_child(main)
	await frames(8)
	current_scene = main
	await process_frame
	check(current_scene == main and main.is_inside_tree() and main.is_node_ready() and not bool(main.get("_title_active")), "正式 Main ready 后成为 current_scene 且 skip-title 生效")
	workshop_host = main.get("workshop_host") as Node
	var workshop_child: Node = main.get_node_or_null("WorkshopHost")
	check(workshop_host != null and workshop_host == workshop_child and workshop_child.get_parent() == main, "读取 Main 实际 workshop_host 变量且确认 Main/WorkshopHost 层级")
	world_probe = WorldInputProbe.new()
	root.add_child(world_probe)

	main.world_clock.paused = false
	await frames(2)
	var clock_before: Dictionary = main.world_clock.to_dict().duplicate(true)
	var menu: Variant = main.hud.menu
	await key(KEY_ESCAPE)
	check(menu.active and paused, "实际 Esc 经 root.push_input 打开暂停菜单且树 paused")
	var workshop_button: Button = menu.buttons.get("building_workshop") as Button
	check(workshop_button != null and workshop_button.is_visible_in_tree(), "暂停菜单存在楼房工坊按钮")
	if workshop_button != null:
		await click_control(workshop_button)
	await frames(3)
	check(workshop_host.is_open() and paused, "鼠标点击菜单按钮进入工坊并保持 paused")
	var clock_paused: Dictionary = main.world_clock.to_dict().duplicate(true)
	await frames(4)
	check(main.world_clock.to_dict() == clock_paused and clock_paused == clock_before, "工坊打开时 world_clock 不增长")
	check(main.hud.menu.active == false, "进入工坊关闭暂停菜单")

	var panel: Variant = workshop_host.panel
	check(panel != null and panel.visible, "工坊 Panel 可见")
	var line_edit: LineEdit = panel.get("_name_edit") as LineEdit
	check(line_edit != null, "工坊实际 LineEdit 已装配")
	if line_edit != null:
		line_edit.grab_focus()
		line_edit.text = "海上中文测试"
		var draft_before_text: Dictionary = panel.session.snapshot()
		await key(KEY_Z, true)
		check(panel.session.snapshot() == draft_before_text and line_edit.has_focus(), "LineEdit CtrlZ 由文本编辑器处理，不触发配方撤销")
		line_edit.text = "海上中文测试"
		line_edit.caret_column = line_edit.text.length()
		var before_world_keys: int = world_probe.key_events
		var typed_event := InputEventKey.new()
		typed_event.keycode = KEY_W
		typed_event.unicode = 87
		typed_event.pressed = true
		root.push_input(typed_event, true)
		await process_frame
		check(line_edit.text == "海上中文测试W" and world_probe.key_events == before_world_keys, "实际文本键进入LineEdit且不穿透世界")
		line_edit.release_focus()
		check(panel.session.snapshot() == draft_before_text, "未应用的中文文本不擅自写入配方")

	var session: Variant = panel.get("session")
	var original_width: float = float(session.snapshot().get("width", 0.0))
	var patch_result: Dictionary = session.apply_patch({"width": original_width + 1.0})
	check(bool(patch_result.get("ok", false)) and session.is_dirty(), "集成工坊实际 session 修改变 dirty")
	var width_after_patch: float = float(session.snapshot().get("width", 0.0))
	await key(KEY_Z, true)
	check(is_equal_approx(float(session.snapshot().get("width", 0.0)), original_width), "CtrlZ 一按只撤销一次")
	check(not is_equal_approx(float(session.snapshot().get("width", 0.0)), width_after_patch), "CtrlZ 未重复或穿透成二次命令")

	panel.request_close()
	await process_frame
	var confirm: ConfirmationDialog = panel.get("_confirm") as ConfirmationDialog
	check(confirm != null and confirm.visible, "dirty close 弹出确认")
	if confirm != null:
		check(confirm.get_cancel_button().has_focus(), "dirty close 默认焦点为取消")
		await key(KEY_ESCAPE)
		check(workshop_host.is_open() and panel.visible, "dirty close 取消保留工坊与草稿")
		panel.close_now()
	await frames(2)
	check(not workshop_host.is_open() and not paused, "close 恢复原 pause 状态")

	var npc_presenter: Variant = main.get("npc_world_presenter")
	var npc_modal_opened: bool = false
	if npc_presenter != null and npc_presenter.has_method("open_npc"):
		var npc_result: Dictionary = npc_presenter.open_npc("npc_luo_yan")
		npc_modal_opened = bool(npc_result.get("ok", false))
	check(npc_modal_opened or npc_presenter == null, "NPC modal 链可打开或不存在时不伪造成功")
	if npc_modal_opened:
		var gated: Dictionary = workshop_host.open()
		check(not bool(gated.get("ok", false)) and not str(gated.get("reason", "")).is_empty(), "NPC modal 打开时工坊返回可读拒绝原因")
		npc_presenter.cancel_session()
		await frames(2)
	var hud: Variant = main.hud
	var fallback_query_available: bool = hud.owned_modal_query.is_valid()
	var opened_again: Dictionary = workshop_host.open()
	check(fallback_query_available and bool(opened_again.get("ok", false)) and workshop_host.is_open(), "NPC modal 关闭后 fallback modal 链仍可重新打开工坊")
	panel.close_now()
	await frames(2)
	check(not workshop_host.is_open() and not paused and not hud.owned_modal_query.call(), "fallback modal 关闭后生命周期与旧 modal 查询恢复")

	print("[workshop-integration] %d checks, %d failures" % [checks, failures.size()])
	finish()

func finish() -> void:
	if is_instance_valid(world_probe):
		world_probe.queue_free()
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
