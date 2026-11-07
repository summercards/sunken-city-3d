extends SceneTree
## 通过统一runner的npc-careers入口执行（res://tests/test_npc_careers.gd）。
## 全部玩法端口使用fake；不实例化Main、不加载Shop/Economy、不触发真实结算。
const CareerPanel = preload("res://src/npc/npc_career_panel.gd")
var checks := 0
var failures := 0
var panel
var ports := FakePorts.new()
var close_count := 0

class FakePorts extends RefCounted:
	var queries: Array = []
	var commands: Array = []
	var available := true
	var reject := false
	var cooldown := 0.0
	var close_after := false
	var during_perform := Callable()
	var rows := {
		"ship": {"display_name": "洛砚", "role": "船匠", "ship_level": 1,
			"cost": {"wood": 6, "parts": 4}, "item_labels": {"wood": "木材", "parts": "零件"}},
		"salvage": {"display_name": "霁沉", "role": "打捞员"},
		"cultivation": {"display_name": "沐禾", "role": "种植师", "crops": [
			{"display_name": "蓝花", "growth_text": "四个成长阶段 · 240 秒", "status_text": "苗圃已有一株"}]},
		"building": {"display_name": "南栀", "role": "建造师"},
		"archive": {"display_name": "白石", "role": "档案员", "events": []}
	}
	func query(action: String) -> Dictionary:
		queries.append(action)
		var row: Dictionary = rows[action].duplicate(true)
		row["ok"] = true
		row["can_execute"] = available
		row["reason"] = "" if available else "真实服务返回：材料不足或仍在冷却"
		if action == "salvage": row["cooldown_left"] = cooldown
		return row
	func perform(action: String, command: Dictionary) -> Dictionary:
		commands.append({"action": action, "command": command.duplicate(true)})
		if during_perform.is_valid(): during_perform.call()
		if reject: return {"ok": false, "reason": "真实owner拒绝：库存已变化"}
		return {"ok": true, "message": "真实owner已完成", "close": close_after}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-careers] ", label)

func _closed() -> void:
	close_count += 1

func button(id: String) -> Button:
	for candidate in panel._buttons:
		if candidate.get_meta("career_command") == id: return candidate
	return null

func press(id: String) -> void:
	var target := button(id)
	check(target != null and not target.disabled, "按钮可用：" + id)
	if target != null and not target.disabled: target.pressed.emit()

func labels() -> String:
	var text: String = panel._identity.text + "\n"
	for child in panel._body.get_children():
		if child is Label: text += child.text + "\n"
	return text

func key(code: Key, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func run() -> void:
	panel = CareerPanel.new()
	root.add_child(panel)
	panel.closed.connect(_closed)
	panel.configure(ports.query, ports.perform)
	_open_cancel()
	_confirm_once()
	_failure_and_unavailable()
	_routes_and_archive()
	await _keyboard()
	_reentrant_callbacks()
	_boundary_and_isolation()
	panel.close()
	panel.free()
	panel = null
	ports.during_perform = Callable()
	ports = null
	await process_frame
	print("[npc-careers] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _open_cancel() -> void:
	check(panel.open_service("npc_luo_yan", "ship").ok and panel.is_open(), "公开入口打开船匠职业")
	check(ports.queries == ["ship"] and ports.commands.is_empty(), "打开仅调用query(action)，不执行")
	check(labels().contains("洛砚 · 船匠") and labels().contains("木材 × 6") and labels().contains("零件 × 4"), "展示装配提供的姓名身份和材料名称费用")
	var snapshot: Dictionary = panel.panel_snapshot()
	snapshot.view.cost.wood = 999
	check(panel.panel_snapshot().view.cost.wood == 6 and ports.rows.ship.cost.wood == 6, "快照与输入查询字典隔离")
	press("prepare")
	check(panel.panel_snapshot().confirming and ports.commands.is_empty(), "准备升级只进入确认，不扣费")
	press("cancel")
	check(not panel.panel_snapshot().confirming and ports.commands.is_empty(), "取消确认不执行")
	press("prepare")
	var before := close_count
	panel.close()
	panel.close()
	check(not panel.is_open() and close_count == before + 1 and ports.commands.is_empty(), "关闭幂等且只发一次closed，不执行")

func _confirm_once() -> void:
	panel.open_service("npc_luo_yan", "ship")
	var old_prepare: Callable = button("prepare").pressed.get_connections()[0].callable
	press("prepare")
	old_prepare.call()
	check(panel.panel_snapshot().confirming and ports.commands.is_empty(), "旧准备按钮回调不能推进确认")
	var old_confirm: Callable = button("confirm").pressed.get_connections()[0].callable
	press("confirm")
	old_confirm.call()
	old_confirm.call()
	check(ports.commands.size() == 1, "重复确认和旧按钮回调只执行一次")
	check(ports.commands[0] == {"action": "ship", "command": {"id": "upgrade_ship", "npc_id": "npc_luo_yan"}}, "船只命令精确交给注入perform，不传UI计算费用")
	check(panel.is_open() and panel.panel_snapshot().submitted and labels().contains("真实owner已完成"), "成功保留结果展示，不自动重复准备")
	panel.open_service("npc_ji_chen", "salvage")
	old_confirm.call()
	check(ports.commands.size() == 1 and panel.panel_snapshot().action_id == "salvage", "旧船匠回调不能执行新打捞会话")
	press("prepare")
	check(labels().contains("收获以实际结果为准"), "打捞执行前明确确认，不预造奖励")
	press("confirm")
	check(ports.commands.back() == {"action": "salvage", "command": {"id": "do_salvage", "npc_id": "npc_ji_chen"}}, "打捞命令只请求真实owner")

func _failure_and_unavailable() -> void:
	panel.open_service("npc_luo_yan", "ship")
	ports.reject = true
	press("prepare")
	var stale: Callable = button("confirm").pressed.get_connections()[0].callable
	var before := ports.commands.size()
	press("confirm")
	stale.call()
	check(ports.commands.size() == before + 1, "失败也作废旧确认，不能自动重试")
	check(panel.is_open() and not panel.panel_snapshot().submitted and not panel.panel_snapshot().confirming, "执行失败保留面板并要求重新明确确认")
	check(labels().contains("真实owner拒绝：库存已变化"), "保留真实失败原因")
	ports.reject = false
	press("prepare")
	press("confirm")
	check(ports.commands.size() == before + 2, "失败后可重新确认执行一次")
	ports.available = false
	ports.cooldown = 12.75
	panel.open_service("npc_ji_chen", "salvage")
	check(button("prepare").disabled and labels().contains("12.8 秒") and labels().contains("仍在冷却"), "冷却及灰因使用公开查询快照")
	before = ports.commands.size()
	button("prepare").pressed.emit()
	check(not panel.panel_snapshot().confirming and ports.commands.size() == before, "即使直接触发灰按钮也不执行")
	ports.available = true
	ports.cooldown = 0.0
	press("refresh")
	check(not button("prepare").disabled and labels().contains("0.0 秒"), "刷新只重新查询，不在UI推算冷却")

func _routes_and_archive() -> void:
	panel.open_service("npc_mu_he", "cultivation")
	check(labels().contains("蓝花") and labels().contains("240 秒") and labels().contains("苗圃已有一株"), "种植只显示公开定义与World描述")
	press("shop_general")
	check(ports.commands.back() == {"action": "cultivation", "command": {"id": "shop_general", "npc_id": "npc_mu_he"}}, "买种仅发综合商店意图")
	press("open_plant")
	check(ports.commands.back().command.id == "open_plant", "照料作物交由装配路由")
	panel.open_service("npc_nan_zhi", "building")
	press("open_building")
	check(ports.commands.back() == {"action": "building", "command": {"id": "open_building", "npc_id": "npc_nan_zhi"}}, "建造仅发送open_building意图")
	var events: Array = []
	for i in 25:
		events.append({"id": "story_%d" % i, "title": "故事%d" % i, "completed": true,
			"npc_id": "npc_luo_yan", "kind": "personal" if i < 21 else "relationship"})
	events.append({"id": "unseen", "title": "未完成剧情", "completed": false})
	ports.rows.archive.events = events
	panel.open_service("npc_bai_shi", "archive")
	var replay_count := 0
	for candidate in panel._buttons:
		if candidate.get_meta("career_command") == "replay_event": replay_count += 1
	check(replay_count == 25 and labels().contains("已收录 25 段故事"), "展示全部21个人加4关系已完成剧情，不截断也不解锁剧情")
	press("replay_event")
	check(ports.commands.back() == {"action": "archive", "command": {"id": "replay_event", "npc_id": "npc_bai_shi", "event_id": "story_0", "event_npc_id": "npc_luo_yan"}}, "回看携带事件和归属NPC，由Main交给NpcPanel")
	press("open_events")
	check(ports.commands.back().command.id == "open_events", "支持Main直接路由居民故事")

func _keyboard() -> void:
	panel.open_service("npc_luo_yan", "ship")
	var before := ports.commands.size()
	var opening := key(KEY_E)
	check(panel.handle_input(opening) and not panel.panel_snapshot().confirming, "打开帧E被消费，不立即准备")
	var opened_frame := Engine.get_process_frames()
	# 初始deferred阶段的首次process_frame可先发信号、后递增帧计数。
	while Engine.get_process_frames() == opened_frame:
		await process_frame
	check(Engine.get_process_frames() > opened_frame, "确认键使用真正后续帧，不绕过打开帧保护")
	panel.handle_input(key(KEY_E, false))
	var enter := key(KEY_ENTER)
	check(panel.handle_input(enter) and panel.panel_snapshot().confirming, "Enter进入明确确认")
	check(ports.commands.size() == before, "Enter进入确认仍不执行真实命令")
	check(panel.handle_input(enter) and ports.commands.size() == before, "装配转发与自身输入重复同事件不执行")
	check(panel.handle_input(key(KEY_ENTER, true, true)) and ports.commands.size() == before, "长按回声不会确认")
	check(panel.handle_input(key(KEY_ESCAPE)) and panel.is_open() and not panel.panel_snapshot().confirming and ports.commands.size() == before, "Esc先取消确认，不结算")
	check(panel.handle_input(key(KEY_ESCAPE)) and not panel.is_open(), "Esc关闭服务")
	check(panel.handle_input(key(KEY_ESCAPE, false)), "关闭后的Esc释放仍被消费")
	check(not panel.handle_input(key(KEY_Q)), "关闭后无关新输入放行")
	panel.open_service("npc_ji_chen", "salvage")
	opened_frame = Engine.get_process_frames()
	while Engine.get_process_frames() == opened_frame:
		await process_frame
	panel.handle_input(key(KEY_E))
	panel.handle_input(key(KEY_E, false))
	panel.handle_input(key(KEY_ENTER))
	check(ports.commands.size() == before + 1, "E准备及Enter确认恰好执行一次")
	panel.open_service("npc_luo_yan", "ship")
	paused = true
	panel.handle_input(key(KEY_ENTER))
	check(not panel.panel_snapshot().confirming, "暂停时不可确认")
	check(panel.handle_input(key(KEY_ESCAPE)) and not panel.is_open(), "暂停时Esc仍可关闭")
	paused = false

func _reentrant_callbacks() -> void:
	panel.open_service("npc_luo_yan", "ship")
	press("prepare")
	var stale: Callable = button("confirm").pressed.get_connections()[0].callable
	ports.during_perform = stale
	var before := ports.commands.size()
	press("confirm")
	check(ports.commands.size() == before + 1, "perform同步重入旧确认也只执行一次")
	ports.during_perform = panel.close
	panel.open_service("npc_luo_yan", "ship")
	press("prepare")
	press("confirm")
	check(not panel.is_open(), "Main在perform中关闭并路由后，结果不复活旧面板")
	ports.during_perform = Callable()
	ports.close_after = true
	panel.open_service("npc_nan_zhi", "building")
	var closed_before := close_count
	press("open_building")
	check(not panel.is_open() and close_count == closed_before + 1, "成功结果close字段关闭职业模态一次")
	ports.close_after = false

func _boundary_and_isolation() -> void:
	panel.configure(Callable(), Callable())
	check(not panel.open_service("npc_luo_yan", "ship").ok and not panel.is_open(), "未注入查询时不打开")
	panel.configure(ports.query, Callable())
	panel.open_service("npc_luo_yan", "ship")
	check(button("prepare").disabled and labels().contains("职业命令尚未接入"), "缺少perform可只读展示且不能确认")
	check(not panel.open_service("npc_luo_yan", "unknown").ok, "未知服务不产生规则或路由")
	var source := FileAccess.get_file_as_string("res://src/npc/npc_career_panel.gd")
	check(not source.contains("res://src/shop") and not source.contains("res://src/economy") and not source.contains("res://src/ship") and not source.contains("res://src/salvage"), "NPC职业UI不预载真实业务owner")
	check(not source.contains("Time.get_ticks") and not source.contains("SHIP_RECIPE") and not source.contains("SALVAGE_COOLDOWN"), "面板不自造时钟费用或资源算法")
