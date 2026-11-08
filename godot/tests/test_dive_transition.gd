extends SceneTree
## 入口由主线程注册到 run_verification.py；只允许隔离副本，不直接运行主工程。
## visual-dive-transition 使用真实渲染器；headless 只验证生命周期，不冒充绘制证据。
const Session = preload("res://src/diving/dive_session.gd")
const Storage = preload("res://src/save/save_game.gd")
const Catalog = preload("res://src/diving/dive_map_catalog.gd")
const REPORT_PATH := "res://outputs/dive-transition-report.json"
const WAIT_MS := 45000

class FailedReadySession extends "res://src/diving/dive_session.gd":
	func _await_runtime_ready() -> bool:
		return false

var checks := 0
var failures := 0
var main
var session
var curtain
var economy
var sample := {}
var baseline := {}
var report := {"test":"dive-transition", "failure_labels":[], "cases":[], "renders":[],
	"isolation":"runner 工程副本与独立 user://；真实 Main；不读写正式存档"}
var real_renderer := false
var finished := false
var suite_deadline := 0
var blocked_path := ""

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		report.failure_labels.append(label)
		printerr("[dive-transition] FAIL ", label)

func wait_until(predicate: Callable, label: String, timeout_ms := WAIT_MS) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline and not finished:
		await process_frame
	var ok: bool = not finished and bool(predicate.call())
	check(ok, str(sample.get("name", "启动")) + "：等待" + label + "（单调时钟超时）")
	return ok

func settled() -> bool:
	return is_instance_valid(session) and not session.switching

func air_snapshot() -> Dictionary:
	var result := {}
	for key in ["air", "lamp", "low_warned", "crit_warned", "emptied", "recover", "surface_depth"]:
		result[key] = session.air.get(key)
	return result

func surface_snapshot() -> Dictionary:
	var modes := []
	var stack: Array = [main]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# Main 首次装配中已有 queue_free 的旧对话框/订单行不进入稳定基线。
		if node.is_queued_for_deletion(): continue
		modes.append({"node":node, "path":str(main.get_path_to(node)), "mode":node.process_mode})
		# 这些所有者仍须精确恢复模式；其内部投影/缩略图子树按生命周期重建，
		# 不属于 Session 保存并 thaw 的稳定节点，不能要求旧实例继续存活。
		var script: Script = node.get_script()
		var script_path := script.resource_path if script != null else ""
		if node.get_class() == "Terrain3D" or script_path in ["res://src/navigation/ground_space.gd",
			"res://src/building/ui/recipe_thumbnail.gd"]:
			continue
		stack.append_array(node.get_children())
	return {"main_id":main.get_instance_id(), "parent":main.get_parent(), "index":main.get_index(),
		"curtain_id":curtain.get_instance_id(), "curtain_parent":curtain.get_parent(),
		"curtain_index":curtain.get_index(), "focus":curtain.focus_query,
		"clock":main.world_clock.to_dict().duplicate(true), "ticking":economy.ticking,
		"current":current_scene, "modes":modes, "player":main.player.transform,
		"boat":main.boat.transform, "actor_mode":main.actor_controller.mode()}

func restored(label: String) -> void:
	check(main.get_instance_id() == baseline.main_id and main.is_inside_tree()
		and main.get_parent() == baseline.parent and main.get_index() == baseline.index,
		label + "：原 Main 实例、parent、index 恢复")
	check(main.dive == session and session.get_parent() == main and session.runtime == null
		and not session.active and not session.switching, label + "：会话归位且无 runtime 残留")
	check(curtain.get_instance_id() == baseline.curtain_id and curtain == main.sleep_curtain
		and curtain.get_parent() == baseline.curtain_parent and curtain.get_index() == baseline.curtain_index
		and curtain.focus_query == baseline.focus, label + "：原 curtain、parent、index、focus 恢复")
	check(curtain.phase == "idle" and not curtain.visible and is_equal_approx(curtain.openness, 1.0)
		and curtain.caption.text.is_empty(), label + "：无文字展开完成")
	check(sample.has("return_boundary") and sample.return_boundary.clock == baseline.clock
		and economy.ticking == baseline.ticking,
		label + "：返回完成边界 clock 完整不变、不跳日，Economy ticking 恢复")
	var same_modes := true
	sample.mode_mismatches = []
	for state in baseline.modes:
		var valid: bool = is_instance_valid(state.node)
		if not valid or state.node.process_mode != state.mode:
			same_modes = false
			sample.mode_mismatches.append({"path":state.path, "expected":state.mode,
				"actual":int(state.node.process_mode) if valid else -1})
	check(same_modes, label + "：Main 和稳定子节点 process_mode 精确恢复 " + JSON.stringify(sample.mode_mismatches))
	check(current_scene == baseline.current and root.get_camera_3d() == main.cam,
		label + "：current_scene 与海面相机恢复")
	check(main.player.transform == baseline.player and main.boat.transform == baseline.boat
		and main.actor_controller.mode() == baseline.actor_mode, label + "：海面角色与船姿态未改变")
	check(not paused and not main.save_registry.is_busy() and main.save_registry.capture().has("dive"),
		label + "：解除暂停且存档注册表重新可用")

func check_blocked(label: String) -> void:
	check(main.input_blocked() and main.save_registry.is_busy(), label + "：输入与快照 busy")
	check(not main.save_game(blocked_path, true).ok and not Storage.write(blocked_path, main).ok
		and not FileAccess.file_exists(blocked_path) and not FileAccess.file_exists(blocked_path + ".tmp")
		and not FileAccess.file_exists(blocked_path + ".bak"), label + "：存档被拒且没有中间文件")

func observe_phase(phase: String) -> void:
	sample.phases.append({"phase":phase, "frame":Engine.get_process_frames(),
		"runtime":is_instance_valid(session.runtime)})
	if phase == "closing":
		sample.kind = "return" if session.active else "dive"
	elif phase == "preparing":
		sample.load = session.trace.load_begin.duplicate(true)
	elif phase == "opening" and session.active:
		var runtime = session.runtime
		sample.opening = {"air":air_snapshot(), "position":runtime.dive_position(),
			"swim":runtime.dive_controller.machine.current == "swim",
			"verified":bool(runtime.get("entry_verified")) if bool(Catalog.get_map(session.source_id).get("world_aligned", false)) else true,
			"frozen":runtime.dive_controller.transition_frozen}

func observe_complete(kind: String) -> void:
	sample.signals.append("completed:" + kind)
	if kind == "return":
		sample.return_boundary = {"clock":main.world_clock.to_dict().duplicate(true),
			"frame":Engine.get_process_frames()}

func observe_failure(_reason: String) -> void:
	sample.signals.append("failed")
	sample.return_boundary = {"clock":main.world_clock.to_dict().duplicate(true),
		"frame":Engine.get_process_frames()}

func observe_curtain(phase: String) -> void:
	sample.curtain_phases.append(phase)
	if phase == "idle" and session.active and sample.has("opening"):
		# idle 信号发生在 uncover_blank 返回之前，仍属于最后一个开幕节点。
		sample.opening_end = {"air":air_snapshot(), "position":session.runtime.dive_position(),
			"frozen":session.runtime.dive_controller.transition_frozen}

func observe_runtime(node: Node) -> void:
	if not sample.is_empty() and node.get_meta("session_owned", false):
		sample.core = {"frame":Engine.get_process_frames(), "runtime_id":node.get_instance_id(),
			"load":session.trace.load_begin.duplicate(true), "main_detached":not main.is_inside_tree(),
			"closed":curtain.phase == "closed" and curtain.visible and is_zero_approx(curtain.openness)}

func capture_frame(key: String, black: bool) -> void:
	# Snapshot exactly this draw now; defer PNG encoding/statistics out of the
	# post-draw dispatch so Session's frame barrier cannot be blocked by I/O.
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		sample.render_errors.append(key + "：渲染图为空")
		return
	var metadata := {"caption_empty":curtain.caption.text.is_empty(), "frame":Engine.get_process_frames(),
		"drawn":Engine.get_frames_drawn(), "before_core":not sample.has("core")}
	save_capture.call_deferred(image, key, black, sample, metadata)

func save_capture(image: Image, key: String, black: bool, target: Dictionary, metadata: Dictionary) -> void:
	var path := "res://outputs/dive-transition-" + str(target.name) + "-" + key + ".png"
	if image.save_png(path) != OK:
		target.render_errors.append(key + "：PNG 写入失败")
	else:
		report.renders.append(path)
	if black:
		var maximum := 0.0
		var total := 0.0
		var bytes := image.get_data()
		var stride := 4 if image.get_format() == Image.FORMAT_RGBA8 else 3
		for i in range(0, bytes.size(), stride):
			maximum = maxf(maximum, float(maxi(bytes[i], maxi(bytes[i+1], bytes[i+2]))) / 255.0)
			total += float(bytes[i] + bytes[i+1] + bytes[i+2]) / 255.0
		var frame := metadata.duplicate()
		frame.merge({"key":key, "max_rgb":maximum,
			"mean_rgb":total / float(image.get_width() * image.get_height() * 3)})
		target.black_frames.append(frame)

func observe_draw() -> void:
	if sample.is_empty() or not is_instance_valid(curtain) or not curtain.visible:
		return
	var kind := str(sample.get("kind", "dive"))
	var key := kind + "-" + str(curtain.phase)
	if sample.draws.has(key): return
	if curtain.phase in ["closing", "opening"] and (curtain.openness < 0.25 or curtain.openness > 0.75):
		return
	if curtain.phase not in ["closing", "closed", "opening"]: return
	sample.draws[key] = {"frame":Engine.get_process_frames(), "drawn":Engine.get_frames_drawn(),
		"openness":curtain.openness, "caption_empty":curtain.caption.text.is_empty(),
		"runtime":is_instance_valid(session.runtime)}
	capture_frame(key, curtain.phase == "closed")

func draw_evidence(evidence: Dictionary, label: String) -> void:
	check(bool(evidence.get("curtain_closed", false)) and bool(evidence.get("curtain_drawn", false)),
		label + "：trace 必须 closed + drawn")
	var draw: Dictionary = evidence.get("draw_evidence", {})
	check(int(draw.get("curtain_id", 0)) == baseline.curtain_id,
		label + "：绘制证据属于真实注入 curtain")
	if real_renderer:
		check(draw.get("barrier", "") == "frame_post_draw"
			and int(draw.get("frames_drawn", -1)) >= int(draw.get("frames_drawn_before", 0)),
			label + "：生产屏障使用真实 frame_post_draw")
		var key := "return-closed" if evidence.get("event", "") == "commit_return" and sample.get("kind", "") == "return" else "dive-closed"
		var observed: Dictionary = sample.draws.get(key, {})
		check(not observed.is_empty() and int(observed.get("frame", -1)) <= int(evidence.get("process_frame", -2)),
			label + "：独立真实 frame_post_draw 已观测全黑，早于 load/commit")
	else:
		check(draw.get("barrier", "") == "process_frame", label + "：headless 仅声明逻辑屏障")

func begin_case(name: String) -> void:
	print("[dive-transition] case=", name, " ticks_ms=", Time.get_ticks_msec())
	session.air.recover = 0.0
	session.trace = {"events":[], "load_begin":{}, "commit_return":{}}
	sample = {"name":name, "phases":[], "curtain_phases":[], "signals":[], "draws":{},
		"black_frames":[], "render_errors":[], "kind":"dive"}
	baseline = surface_snapshot()

func assert_entry(id: String) -> void:
	check(session.active and session.source_id == id and current_scene == session.runtime
		and session.runtime.map_id == Catalog.get_map(id).map_id
		and session.runtime.scene_file_path == Catalog.get_map(id).scene_path
		and not main.is_inside_tree(), id + "：真实切换到正确地图")
	check(sample.has("core") and sample.core.closed and sample.core.main_detached,
		id + "：core 提交发生在全黑且 Main 已摘树")
	draw_evidence(sample.get("load", {}), id + " load_begin")
	check(sample.has("core") and not sample.core.load.is_empty()
		and sample.core.load == sample.get("load", {})
		and int(sample.core.load.get("process_frame", -1)) <= int(sample.core.frame),
		id + "：load_begin trace 已存在才提交 core")
	check(sample.has("opening") and sample.opening.swim and sample.opening.verified
		and sample.opening.frozen, id + "：verified/swim 后才 opening 且仍冻结")
	check(sample.has("opening_end") and sample.opening_end.frozen
		and sample.opening.air == sample.opening_end.air
		and sample.opening.position == sample.opening_end.position,
		id + "：整个开幕期间氧气和位置不变")
	check(not session.runtime.dive_controller.transition_frozen, id + "：switching 结束才解除 controller 冻结")
	check(sample.curtain_phases.slice(0, 4) == ["closing", "closed", "opening", "idle"],
		id + "：收幕→全黑→展开→idle")
	if real_renderer:
		var frame: Dictionary = sample.draws.get("dive-closed", {})
		check(not frame.is_empty() and sample.has("core")
			and int(frame.get("frame", -1)) <= int(sample.core.frame)
			and not bool(frame.get("runtime", true)), id + "：独立 frame_post_draw 观测先于 load/core")

func assert_visual(returned := true) -> void:
	if not real_renderer: return
	check(sample.render_errors.is_empty(), str(sample.name) + "：关键帧截图无错误")
	var expected := ["dive-closing", "dive-closed", "dive-opening"]
	if returned: expected.append_array(["return-closing", "return-closed", "return-opening"])
	var complete := true
	for key in expected: complete = complete and sample.draws.has(key)
	check(complete, str(sample.name) + "：真实 closing/closed/opening 关键帧齐全")
	var black: bool = not sample.black_frames.is_empty()
	for frame in sample.black_frames:
		black = black and frame.max_rgb <= 2.0 / 255.0 and frame.mean_rgb <= 1.0 / 255.0 and frame.caption_empty
	check(black, str(sample.name) + "：加载/返回黑幕整帧 RGB 近零且 caption 空")

func archive_case() -> void:
	var data: Dictionary = sample.duplicate(true)
	data.trace = session.trace.duplicate(true)
	# Vector3 在 JSON 中显式编码，避免报告把可复算的位置降成展示字符串。
	for key in ["opening", "opening_end"]:
		if data.has(key):
			var point: Vector3 = data[key].position
			data[key].position = [point.x, point.y, point.z]
	report.cases.append(data)
	sample = {}

func request_entry(id: String, production := false) -> bool:
	var point: Vector3 = main._home_seabed_anchor() + Vector3(7, 0, 5) if id == "home_seabed" else main.boat.position
	var accepted := true
	if production:
		point = main.player.global_position if main.actor_controller.mode() == 0 else main.boat.position
		check(main._dive_source_at(point) == id, id + "：生产入口使用真实位置解析来源")
		main._on_dive()
		accepted = session.switching
	else:
		accepted = session.request_dive(point, id)
	check(accepted and session.switching and session.runtime == null and main.is_inside_tree(),
		id + "：接受即 switching，runtime 仍 null，Main 仍在树中")
	check(not session.request_dive(point, id), id + "：双击立即拒绝")
	check_blocked(id + " 请求刚接受")
	if not accepted: return false
	if not await wait_until(func(): return curtain.phase == "closing" and curtain.openness < 0.8, "收幕中间节点"):
		return false
	check(session.runtime == null and session.trace.load_begin.is_empty() and main.is_inside_tree(),
		id + "：收幕中未 load、未创建 runtime、未摘 Main")
	check(not economy.ticking and main.world_clock.to_dict() == baseline.clock,
		id + "：收幕阶段已经冻结海面 clock/Economy")
	return true

func opening_input() -> void:
	var controller = session.runtime.dive_controller
	var before := air_snapshot()
	var point: Vector3 = session.runtime.dive_position()
	var yaw: float = controller.yaw
	var distance: float = controller.distance
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	root.push_input(key, true)
	controller._unhandled_input(key)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_WHEEL_UP
	button.pressed = true
	controller._unhandled_input(button)
	Input.action_press("dive_forward")
	Input.action_press("dive_sprint")
	controller.machine.tick(0.1)
	Input.action_release("dive_forward")
	Input.action_release("dive_sprint")
	check(not session.swim_to(point + Vector3.RIGHT * 3) and not controller.swim_to(point + Vector3.RIGHT * 3)
		and controller.route.is_empty(), str(sample.name) + "：开幕拒绝导航")
	session.toggle_lamp()
	check(air_snapshot() == before and session.runtime.dive_position() == point
		and controller.yaw == yaw and controller.distance == distance,
		str(sample.name) + "：开幕拒绝键鼠/头灯，运动 tick 不耗氧不移位")
	check_blocked(str(sample.name) + " 开幕")

func round_trip(id: String, production := false) -> void:
	begin_case(id)
	if not await request_entry(id, production): return
	if not await wait_until(func(): return curtain.phase == "opening" and session.active, "入水开幕"):
		return
	opening_input()
	if not await wait_until(settled, "switching=false"):
		return
	assert_entry(id)
	var active_sample_until := Time.get_ticks_msec() + 100
	if not await wait_until(func(): return Time.get_ticks_msec() >= active_sample_until, "活动潜水 clock 采样窗口"):
		return
	check(main.is_processing() and not main.is_inside_tree()
		and main.world_clock.to_dict() == baseline.clock and not economy.ticking,
		id + "：活动潜水中真实 Main 摘树冻结 clock，未禁用 Main process")
	var runtime = session.runtime
	var runtime_id: int = runtime.get_instance_id()
	var hud = runtime.get_child(runtime.get_child_count() - 1)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	check(paused and hud.presentation_snapshot().menu_open, id + "：真实 Esc 暂停潜水")
	hud.menu_buttons.surface.pressed.emit()
	check(not paused and session.switching and controller_frozen(), id + "：pause 上浮立即 unpause 并冻结")
	if not await wait_until(func(): return curtain.phase == "closing", "返回收幕"):
		return
	check(session.runtime == runtime and not main.is_inside_tree() and session.trace.commit_return.is_empty(),
		id + "：返回收幕尚未 commit_return")
	if not await wait_until(func(): return curtain.phase == "opening" and not session.active, "返回开幕"):
		return
	draw_evidence(session.trace.commit_return, id + " commit_return")
	check(main.is_inside_tree() and session.runtime == null and session.switching,
		id + "：返回开幕时 Main 已恢复但仍 switching")
	check_blocked(id + " 返回开幕")
	if not await wait_until(settled, "返回 switching=false"):
		return
	check(not is_instance_id_valid(runtime_id), id + "：旧 runtime 真正释放")
	restored(id)
	assert_visual()
	check(sample.signals == ["started:dive", "completed:dive", "started:return", "completed:return", "exited"],
		id + "：开始/完成/退出信号顺序且各一次")
	archive_case()

func controller_frozen() -> bool:
	return is_instance_valid(session.runtime) and session.runtime.dive_controller.transition_frozen

func queued_return(stage: String) -> void:
	begin_case("queued-" + stage)
	if not await request_entry("zone1"): return
	if stage != "closing":
		if not await wait_until(func(): return curtain.phase == stage, "排队返回阶段 " + stage): return
	if is_instance_valid(session.runtime):
		session.runtime.exited.emit()
	else:
		# 收幕期尚无 runtime；直接走与 runtime.exited 连接相同的返回端口。
		session._request_return()
	check(session._return_requested and session.switching, stage + "：转场中返回请求保留")
	if not await wait_until(func(): return settled() and not session.active, "排队返回完整结束"):
		return
	draw_evidence(session.trace.commit_return, stage + " 排队返回 commit")
	restored(stage + " 排队返回")
	check(sample.signals == ["started:dive", "completed:dive", "started:return", "completed:return", "exited"],
		stage + "：返回没有丢失或重复提交")
	assert_visual()
	archive_case()

func oxygen_return() -> void:
	begin_case("oxygen")
	if not await request_entry("zone1"): return
	if not await wait_until(settled, "耗氧夹具入水完成"): return
	var runtime = session.runtime
	var runtime_id: int = runtime.get_instance_id()
	# 仅设测试输入；自然 physics tick 触发 empty→exit→exited，不手调返回方法。
	runtime.debug_teleport(Vector3(0, -12, 10))
	session.air.air = 0.001
	if not await wait_until(func(): return session.air.emptied and session.air.recover > 0.0, "氧气耗尽"):
		return
	check(runtime.phase == "exit" and session.switching and controller_frozen()
		and runtime.has_meta("request_surface_transition"), "氧气：exit 通过真实 metadata 立即请求收幕并冻结")
	if not await wait_until(func(): return curtain.phase == "closing", "耗氧立即收幕"):
		return
	check(session.runtime == runtime and session.trace.commit_return.is_empty(), "氧气：收幕期间保留 runtime，尚未卸载")
	if not await wait_until(func(): return settled() and not session.active, "耗氧自然上浮返回"):
		return
	draw_evidence(session.trace.commit_return, "氧气 commit_return")
	check(not is_instance_id_valid(runtime_id), "氧气：无 runtime 残留")
	restored("氧气")
	assert_visual()
	archive_case()

func main_composed() -> bool:
	for child in main.hud.get_children():
		if child.get_script() != null and child.get_script().resource_path == "res://src/ui/island_presenters.gd":
			return not child.views.is_empty()
	return false

func create_main(fail_ready := false) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main._autosave_on = false
	root.add_child(main)
	current_scene = main
	if fail_ready:
		# Autoload 初始化后正常装配 Main，仅替换夹具 Session 并重绑其存档端口。
		var previous = main.dive
		var replacement = FailedReadySession.new()
		replacement.name = previous.name
		replacement.give_resource = previous.give_resource
		replacement.give_rewards = previous.give_rewards
		replacement.source_query = previous.source_query
		replacement.curtain = main.sleep_curtain
		for signal_name in ["depth_changed", "zone_changed", "air_changed", "message", "exited"]:
			for connection in previous.get_signal_connection_list(signal_name):
				replacement.connect(signal_name, connection.callable, connection.flags)
		var entry: Dictionary = main.save_registry._entries.dive
		entry.capture = replacement.to_dict
		entry.apply = replacement.from_dict
		entry.event_sources = [weakref(replacement)]
		main.remove_child(previous)
		previous.free()
		main.dive = replacement
		main.add_child(replacement)
		replacement.configure(main)
	session = main.dive
	curtain = main.sleep_curtain
	# 无关的跟随/船浮动不参与转场验收；clock 仍交由真实 Main 推进。
	main.boat.set_process(false)
	main.cam.set_process(false)
	main.player.set_process(false)
	session.transition_phase.connect(observe_phase)
	curtain.phase_changed.connect(observe_curtain)
	session.transition_started.connect(func(kind: String): sample.signals.append("started:" + kind))
	session.transition_completed.connect(observe_complete)
	session.transition_failed.connect(observe_failure)
	session.exited.connect(func(): sample.signals.append("exited"))

func failed_ready() -> void:
	current_scene = null
	main.free()
	create_main(true)
	if not await wait_until(main_composed, "故障夹具真实 Main 延迟装配完成"):
		return
	begin_case("failed-ready")
	session.set_process(false)
	session.from_dict({"found":[0, 9999], "opened":[0]})
	var progress: Dictionary = session.to_dict()
	session.air.air = 42.5
	session.air.lamp = false
	session.air.low_warned = true
	session.air.crit_warned = true
	session.air.emptied = true
	session.air.surface_depth = 0.25
	var air := air_snapshot()
	if not await request_entry("zone1"): return
	if not await wait_until(func(): return settled() and sample.signals.has("failed"), "注入 readiness 失败后展开"):
		return
	check(session.get_script() != Session and sample.has("core"), "故障：仅本夹具 Session 子类失败，已实际进入 core")
	check(air_snapshot() == air and session.to_dict() == progress, "故障：air 全字段与原进度精确回滚")
	check(not is_instance_id_valid(int(sample.core.runtime_id)), "故障：候选 runtime 已释放")
	draw_evidence(session.trace.load_begin, "故障 load_begin")
	draw_evidence(session.trace.commit_return, "故障 commit_return")
	check(sample.signals == ["started:dive", "failed"] and sample.curtain_phases == ["closing", "closed", "opening", "idle"],
		"故障：不发成功/正常退出，失败只一次且仍展开")
	restored("故障")
	assert_visual(false)
	archive_case()

func watchdog() -> void:
	if not finished and Time.get_ticks_msec() >= suite_deadline:
		check(false, "全套测试单调时钟 watchdog 超时")
		finish()

func finish() -> void:
	if finished: return
	finished = true
	paused = false
	if not sample.is_empty() and is_instance_valid(session): archive_case()
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "隔离 outputs JSON 报告可写")
	var mode_path := REPORT_PATH.trim_suffix(".json") + ("-visual.json" if real_renderer else "-headless.json")
	var mode_file := FileAccess.open(mode_path, FileAccess.WRITE)
	check(mode_file != null, "双模式独立 JSON 证据可写，不互相覆盖")
	report.checks = checks
	report.failures = failures
	for output in [file, mode_file]:
		if output != null:
			output.store_string(JSON.stringify(report, "\t"))
			output.close()
	# 证据先落盘，再收束夹具。失败时也不能把整棵 Main 留给 SceneTree 强制退出。
	if node_added.is_connected(observe_runtime): node_added.disconnect(observe_runtime)
	if real_renderer and RenderingServer.frame_post_draw.is_connected(observe_draw):
		RenderingServer.frame_post_draw.disconnect(observe_draw)
	baseline.clear()
	if is_instance_valid(session): session.dispose()
	current_scene = null
	if is_instance_valid(main): main.free()
	main = null
	session = null
	curtain = null
	# 清掉 dispose 安排的 queue_free，并让真实渲染器提交资源释放；不用于等待切图。
	await process_frame
	if real_renderer: await RenderingServer.frame_post_draw
	await process_frame
	print("[dive-transition] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var user: String = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	if not user.begins_with("sea-verification/") or not project.ends_with("/project"):
		check(false, "仅允许 runner 隔离工程副本，拒绝主工程")
		print("[dive-transition] %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	if not OS.get_cmdline_user_args().has("--skip-title"):
		check(false, "runner 必须传 --skip-title，禁止标题流程干扰真实 Main")
		finish()
		return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs")) == OK, "隔离 outputs 可用")
	real_renderer = DisplayServer.get_name() != "headless"
	report.renderer = "real" if real_renderer else "headless（不验收像素/真实绘制）"
	blocked_path = "user://dive-transition-blocked-%d.json" % Time.get_ticks_usec()
	suite_deadline = Time.get_ticks_msec() + 240000
	process_frame.connect(watchdog)
	economy = root.get_node("Economy")
	economy.set_process(false)
	economy.set_physics_process(false)
	node_added.connect(observe_runtime)
	if real_renderer: RenderingServer.frame_post_draw.connect(observe_draw)
	create_main()
	var clock_before: Dictionary = main.world_clock.to_dict().duplicate(true)
	if not await wait_until(func(): return main.world_clock.to_dict() != clock_before, "真实 Main 正常推进 clock", 5000):
		finish()
		return
	check(main.is_processing(), "clock 冻结验收不禁用 Main process")
	check(session.curtain == curtain and curtain.phase == "idle", "Main 正常注入真实 SleepCurtain")
	begin_case("unknown")
	check(not session.request_dive(main.boat.position, "unknown") and not session.switching
		and session.runtime == null and main.is_inside_tree() and session.trace.events.is_empty(),
		"未知入口：拒绝且无收幕/切图副作用")
	archive_case()
	await round_trip("home_seabed", true)
	if failures: finish(); return
	await round_trip("zone1")
	if failures: finish(); return
	# Real renderer validates both production map paths and rollback pixels.
	# Race/oxygen permutations are covered by the headless suite, avoiding repeated
	# multi-million-triangle warmups just to repeat the same iris pixels.
	if not real_renderer:
		await queued_return("closing")
		if failures: finish(); return
		await queued_return("closed")
		if failures: finish(); return
		await queued_return("opening")
		if failures: finish(); return
		await oxygen_return()
		if failures: finish(); return
	await failed_ready()
	finish()
