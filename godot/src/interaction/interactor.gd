extends Node3D
class_name Interactor
## 玩家身上的交互探测器。
##
## 每 0.12 秒扫一次附近的 Interactable，按「距离 + 是否朝着它 + 优先级」挑一个焦点；
## 按住 interact 时累积时间，满了才真正执行。走开、换目标、松手都会打断。
##
## 这里刻意不做「屏幕点击」：海底/海面/以后的所有可交互物共用同一套规则，
## 换相机、换场景都不用改判定。

signal action_started(spot: Node3D)
signal target_changed(spot: Node3D)
signal progress_changed(ratio: float)
signal completed(spot: Node3D, reward: Dictionary)
signal blocked(reason: String)

## 世界坐标的探测半径（米）。
@export var radius := 2.8
## 扫描间隔，避免每帧遍历整张表。
@export var scan_interval := 0.12
## 走动超过这个距离就取消当前动作。
@export var move_tolerance := 0.35

var active := false
## Optional actor-space query. The interactor never owns navigation or rules.
var reachable_query: Callable
## 点击目标后由 main 打开：小人走到位就自动按住，不用玩家再按 E。
var auto_hold := false
## 点击选择的地格优先，避免相邻六格被最近距离抢走。
var preferred_target: Node3D
## One selected command, consumed at the normal hold completion boundary.
var command_target: Node3D
var selected_command: Callable
var target: Node3D = null
var hold := 0.0
var last_blocked := ""

var _scan_left := 0.0
var _anchor := Vector3.ZERO
var _blocked_cooldown := 0.0
var _holding_last := false


static func ensure_input_map() -> void:
	# 输入映射放在代码里注册：project.godot 的 InputEvent 序列化对版本敏感，
	# 而且这样旧存档/旧工程也能直接用。
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event("interact", key)
	if not InputMap.has_action("cancel_action"):
		InputMap.add_action("cancel_action")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("cancel_action", esc)


func _ready() -> void:
	ensure_input_map()
	set_process(true)


func _process(delta: float) -> void:
	update(delta, active and (Input.is_action_pressed("interact") or auto_hold))


## 供测试直接驱动的一帧。
func update(delta: float, holding: bool) -> void:
	if not active:
		if target != null:
			_release()
		_holding_last = false
		return

	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = scan_interval
		_refresh_target()

	if target == null:
		if hold != 0.0:
			hold = 0.0
			progress_changed.emit(0.0)
		_holding_last = false
		return

	if not holding:
		if _holding_last:
			# 松手：进度保留一小会儿会让人误以为“差一点”，直接清零更清楚。
			hold = 0.0
			progress_changed.emit(0.0)
		_holding_last = false
		return

	if not _holding_last:
		_holding_last = true
		_anchor = global_position
		last_blocked = ""
		action_started.emit(target)

	# 走动打断：脚下挪了位置就重来。
	if global_position.distance_to(_anchor) > move_tolerance:
		hold = 0.0
		_holding_last = false
		progress_changed.emit(0.0)
		blocked.emit("走动打断了采集")
		return

	if _blocked_cooldown > 0.0:
		_blocked_cooldown -= delta
		return

	var need := maxf(target.hold_time, 0.01)
	hold += delta
	if hold < need:
		progress_changed.emit(clampf(hold / need, 0.0, 1.0))
		return

	hold = 0.0
	_holding_last = false
	progress_changed.emit(0.0)
	var reward: Dictionary
	if target == command_target and selected_command.is_valid():
		var command := selected_command
		selected_command=Callable();command_target=null
		reward = command.call()
	else: reward = target.interact(self)
	if reward.has("blocked"):
		last_blocked = str(reward.blocked)
		_blocked_cooldown = 0.6
		blocked.emit(last_blocked)
		return
	if not reward.is_empty():
		completed.emit(target, reward)
	# 执行后立刻重选：采空的点不该继续占着焦点。
	_refresh_target()


func _refresh_target() -> void:
	var best: Node3D = null
	var best_score := INF
	var origin := global_position
	var facing := global_transform.basis.x
	for node in get_tree().get_nodes_in_group("interactable"):
		var spot: Node3D = node
		if spot == null or not is_instance_valid(spot):
			continue
		if not spot.is_visible_in_tree():
			continue
		if reachable_query.is_valid() and not bool(reachable_query.call(spot)):
			continue
		# 位置一律走 focus_position()：它跟着视觉几何走，而不是节点原点。
		# 曾经硬编码 global_position，导致给视觉加了偏移的物件（出货箱偏 2.07 米）
		# 要站回原始锚点才能交互。
		var to: Vector3 = spot.focus_position() - origin
		to.y = 0.0
		var dist := to.length()
		if dist > minf(radius, float(spot.effective_focus_radius())) + 0.9:
			continue
		if not spot.can_interact():
			continue
		var dir := to.normalized() if dist > 0.001 else facing
		# 朝向只影响排序，不作为硬门槛：俯视镜头下要求精确面对很别扭。
		var align := facing.normalized().dot(dir)
		var score := dist * (1.22 - 0.22 * align) - float(spot.priority) * 0.25
		if is_instance_valid(preferred_target) and spot == preferred_target:
			score -= 100.0
		if score < best_score:
			best_score = score
			best = spot
	if best == target:
		return
	_release()
	target = best
	hold = 0.0
	if target != null:
		target.focus_enter()
	target_changed.emit(target)


func _release() -> void:
	if target != null and is_instance_valid(target) and target.focused:
		target.focus_exit()
	target = null
	hold = 0.0


func progress() -> float:
	if target == null:
		return 0.0
	return clampf(hold / maxf(target.hold_time, 0.01), 0.0, 1.0)


## 测试：绕过扫描直接锁定一个目标。
func debug_focus(spot: Node3D) -> void:
	_release()
	target = spot
	if target != null:
		target.focus_enter()
	target_changed.emit(target)

func cancel() -> void:
	selected_command=Callable();command_target=null
	auto_hold=false
	preferred_target=null
	_holding_last=false
	_release()

func queue_command(spot: Node3D, command: Callable) -> void:
	command_target=spot;selected_command=command
