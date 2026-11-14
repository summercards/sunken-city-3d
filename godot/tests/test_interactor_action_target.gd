extends SceneTree
## 正式交互器的动作目标、失效与旧命令回归，不启动 Main。
const Probe = preload("res://src/interaction/interactor.gd")
var checks := 0
var failures := 0
var reachable := true
var command_hits := 0

class Spot extends Interactable:
	var enabled := true
	var hits := 0
	func can_interact() -> bool: return enabled
	func interact(_actor: Node3D) -> Dictionary:
		hits += 1
		return {"event": "acted"}

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [interactor-action-target] ", label)
func query(_spot: Node3D) -> bool: return reachable
func command() -> Dictionary:
	command_hits += 1
	return {"event": "command"}
func make_spot(holder: Node, label: String, at: Vector3, duration: float) -> Spot:
	var spot := Spot.new()
	spot.name = label
	spot.focus_anchor = "node"
	spot.auto_radius = false
	spot.hold_time = duration
	holder.add_child(spot)
	spot.position = at
	return spot
func run() -> void:
	for mode in ["cycle", "hide", "remove", "free", "disabled", "reach", "distance", "scan", "inactive"]:
		var holder := Node3D.new()
		root.add_child(holder)
		var probe := Probe.new()
		holder.add_child(probe)
		probe.set_process(false)
		probe.active = true
		probe.reachable_query = query
		reachable = true
		var a := make_spot(holder, "A", Vector3(0, 0, 1), 0.5)
		var b := make_spot(holder, "B", Vector3(1, 0, 1), 0.0)
		probe.refresh_now()
		probe.update(0.01, true)
		probe.update(0.1, true)
		check(probe.acting and probe.action_target == a, mode + " 锁定初始 A")
		var old_generation: int = probe._action_generation
		probe.queue_command(a, command)
		probe.auto_hold = true
		probe.preferred_target = a
		probe.update(0.01, true)
		match mode:
			"cycle":
				probe.preferred_target = null
				probe.cycle_target()
			"hide": a.hide()
			"remove": holder.remove_child(a)
			"free": a.free()
			"disabled": a.enabled = false
			"reach": reachable = false
			"distance": a.position = Vector3(0, 0, 20)
			"scan":
				probe.preferred_target = null
				probe.rotation.y = PI / 2.0
			"inactive": probe.active = false
		probe.update(0.2, true)
		probe._finish_action(b, old_generation)
		probe.update(1.0, true)
		check(b.hits == 0 and command_hits == 0, mode + " 不转交 B 或执行旧命令")
		check(not probe.acting and not probe.selected_command.is_valid(), mode + " 清动作与旧命令")
		if mode == "remove":
			holder.add_child(a)
			a.add_to_group("interactable")
		if is_instance_valid(a):
			a.show()
			a.enabled = true
			a.position = Vector3(0, 0, 1)
			reachable = true
			probe.active = true
			probe.cancel()
			probe.rotation.y = 0.0
			probe.refresh_now()
			probe.update(0.01, false)
			probe.update(0.01, true)
			probe.update(1.0, false)
			check(a.hits == 1 and command_hits == 0, mode + " 重选 A 不复活旧命令，松键仍完成")
		holder.free()
	var holder := Node3D.new()
	root.add_child(holder)
	var probe := Probe.new()
	holder.add_child(probe)
	probe.set_process(false)
	probe.active = true
	var a := make_spot(holder, "Auto", Vector3(0, 0, 1), 0.5)
	probe.preferred_target = a
	probe.auto_hold = true
	probe.queue_command(a, command)
	probe.update(0.01, true)
	probe.position.x = 0.5
	probe.update(0.2, true)
	check(probe.acting and probe.action_target == a and probe.hold == 0.0, "同目标自动接近只重置锚点")
	probe.update(0.6, false)
	check(command_hits == 1 and a.hits == 0 and not probe.auto_hold, "同目标命令松键完成且只消费一次")
	probe.update(1.0, true)
	check(command_hits == 1, "自动命令不重复")
	probe.cancel()
	probe.refresh_now()
	probe.update(0.01, true)
	var stale_generation: int = probe._action_generation
	probe.cancel()
	probe.refresh_now()
	probe.update(0.01, false)
	probe.update(0.01, true)
	probe._finish_action(a, stale_generation)
	check(probe.acting and a.hits == 0, "同一目标新动作拒绝旧代次完成")
	probe.update(0.6, false)
	check(a.hits == 1, "只有新代次正常完成")
	probe.cancel()
	probe.refresh_now()
	probe.update(0.01, false)
	probe.update(0.01, true)
	var cancel_at_finish := func(ratio: float):
		if ratio == 0.0: probe.cancel()
	probe.progress_changed.connect(cancel_at_finish, CONNECT_ONE_SHOT)
	probe.update(0.6, false)
	check(a.hits == 1, "完成进度回调取消后不执行已捕获目标")
	holder.free()
	await process_frame
	print("[interactor-action-target] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
