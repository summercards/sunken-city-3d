extends SceneTree
## 交互热区必须跟着物体走。
##
## 起因（2026-10-29）：出货箱的热区锚点固定为节点原点，而视觉是带偏移的子节点
## （Visual 偏移 -1.40 / +1.52，缩放 1.72）。实测锚点与箱子几何中心相差 2.07 米，
## 焦点半径才 2.4 米 —— 箱子看得见，却要走回一块空地才能按 E。
##
## 本测试锁死三条契约：
##   1. 锚点 == 视觉包围盒的 XZ 中心（偏差为 0）；
##   2. 移动视觉后，锚点跟着移动同样的量（DIY 摆场景的常态）；
##   3. 移动锚点后，Interactor 能在新位置选中它、在旧位置选不中它。

var checks := 0
var failures := 0

class InteractionContext extends RefCounted:
	var actor: Node3D
	var auto_target: Node3D
	var interactor: Node
	var ports: Dictionary
	var completions := 0
	func complete_interaction() -> void:
		completions += 1
		interactor.auto_hold = false

func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	for i in 6:
		await process_frame

	var box: Node3D = main._zone_nodes.zone1.get_node("Objects/ShippingBox")
	var visual: Node3D = box.get_node("Visual")

	# ---- 1. 锚点 = 视觉中心 ----
	var center: Vector3 = box.visual_aabb().get_center()
	var anchor: Vector3 = box.focus_position()
	var off: float = Vector2(center.x - anchor.x, center.z - anchor.z).length()
	check(off < 0.01, "锚点与视觉中心重合（实际偏差 %.3f 米）" % off)
	check(box.focus_anchor == "geometry", "默认锚点模式是 geometry")

	# ---- 2. 移动视觉，锚点跟着走 ----
	var before: Vector3 = box.focus_position()
	var shift := Vector3(3.0, 0.0, -2.0)
	visual.position += shift
	var after: Vector3 = box.focus_position()
	var moved := Vector2(after.x - before.x, after.z - before.z)
	var want := Vector2(shift.x, shift.z)
	check(moved.distance_to(want) < 0.01,
		"视觉移动 %s 后锚点同步（实际 %s）" % [str(want), str(moved)])

	var center2: Vector3 = box.visual_aabb().get_center()
	check(Vector2(center2.x - after.x, center2.z - after.z).length() < 0.01,
		"移动后锚点仍与视觉中心重合")

	# ---- 3. 判定：新位置够得着，旧位置够不着 ----
	var interactor: Node = main.interactor
	check(interactor != null, "找到 Interactor")
	if interactor != null:
		var reach: float = minf(float(interactor.radius), float(box.effective_focus_radius()))
		# 新位置正前方 0.8 米
		var near: Vector3 = box.focus_position()
		near.x -= 0.8
		interactor.active = false
		interactor._release()
		interactor.global_position = near
		interactor.active = true
		interactor._refresh_target()
		check(interactor.target == box, "站在物体旁能选中出货箱")

		# 旧锚点那一侧：视觉已搬走 3 米，站这里必须够不着（> 有效半径 + 0.9 米余量）
		var far: Vector3 = before - Vector3(0.0, 0.0, 5.0)
		interactor.active = false
		interactor._release()
		interactor.global_position = far
		interactor.active = true
		interactor._refresh_target()
		check(interactor.target != box, "站回旧锚点位置不应再选中（说明热区已搬走）")

	# ---- 4. node 模式仍可用（精确锚点的逃生口） ----
	box.focus_anchor = "node"
	check((box.focus_position() - box.global_position).length() < 0.01,
		"node 模式锚点回到节点原点")
	box.focus_anchor = "geometry"

	# 到位自动长按也必须用同一视觉锚点，不能走到箱旁后还测旧原点。
	var context := InteractionContext.new()
	context.actor = Node3D.new()
	root.add_child(context.actor)
	context.auto_target = box
	context.interactor = interactor
	var gate := {"blocked":false}
	context.ports = {"input_blocked":func(): return gate.blocked}
	var state = preload("res://src/player/states/interacting.gd").new()
	state.context = context
	var outward: Vector3 = box.focus_position() - box.global_position
	outward.y = 0.0
	outward = outward.normalized()
	context.actor.global_position = box.focus_position() + outward
	check(context.actor.global_position.distance_to(box.global_position)>2.2,
		"自动交互反例确实位于旧原点门槛之外")
	state.tick(0.0)
	check(interactor.auto_hold,"视觉旁到位后可自动交互")
	gate.blocked = true
	state.tick(0.0)
	check(not interactor.auto_hold,"模态阻断仍禁止自动交互")
	gate.blocked = false
	context.actor.global_position = box.focus_position() + outward*2.3
	state.tick(0.0)
	check(not interactor.auto_hold,"离开原2.2米范围仍停止自动交互")
	var plain := Node3D.new()
	root.add_child(plain)
	context.auto_target = plain
	context.actor.global_position = plain.global_position + Vector3.RIGHT
	state.tick(0.0)
	check(interactor.auto_hold,"没有视觉锚点接口的目标保留节点位置后备")
	context.auto_target = null
	state.tick(0.0)
	check(context.completions==1 and not interactor.auto_hold,"目标消失仍结束并释放自动输入")
	context.actor.queue_free()
	plain.queue_free()

	print("[interact-focus] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
