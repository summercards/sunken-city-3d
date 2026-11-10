extends SceneTree
## OPT-04：同一轮候选扫描只调用一次 reachable_query。
## 该测试只验证查询生命周期与既有候选/焦点语义，不启动正式 Main。

const InteractorScript = preload("res://src/interaction/interactor.gd")
const InteractableScript = preload("res://src/interaction/interactable.gd")

var checks := 0
var failures := 0
var query_counts: Dictionary = {}
var reachable: Dictionary = {}

class CountingSpot extends Interactable:
	var enabled := true

	func can_interact() -> bool:
		return enabled


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [interactor-query-reuse] ", label)


func query(spot: Node3D) -> bool:
	var id := spot.get_instance_id()
	query_counts[id] = int(query_counts.get(id, 0)) + 1
	return bool(reachable.get(id, true))


func reset_counts() -> void:
	query_counts.clear()


func count_for(spot: Node3D) -> int:
	return int(query_counts.get(spot.get_instance_id(), 0))


func make_spot(parent: Node, name: String, position: Vector3) -> CountingSpot:
	var spot := CountingSpot.new()
	spot.name = name
	spot.focus_anchor = "node"
	spot.auto_radius = false
	spot.focus_radius = 2.4
	parent.add_child(spot)
	spot.global_position = position
	return spot


func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var interactor := InteractorScript.new()
	holder.add_child(interactor)
	interactor.global_position = Vector3.ZERO
	interactor.radius = 3.0
	interactor.reachable_query = Callable(self, "query")

	var near := make_spot(holder, "Near", Vector3(0, 0, 1.0))
	var far := make_spot(holder, "Far", Vector3(0, 0, 2.0))
	var side := make_spot(holder, "Side", Vector3(1.0, 0, 1.0))
	await process_frame
	interactor.active = true

	# _refresh_target 的一次扫描：每个节点只询问一次，且距离排序仍选近者。
	reset_counts()
	interactor._refresh_target()
	check(count_for(near) == 1 and count_for(far) == 1 and count_for(side) == 1,
		"_refresh_target 每节点每扫描一次 reachable_query")
	check(interactor.target == near, "同档候选仍按距离排序选近目标")
	var sticky := interactor.target
	reset_counts()
	interactor._refresh_target()
	check(count_for(near) == 1 and count_for(far) == 1 and count_for(side) == 1,
		"重复扫描不引入第二次 reachable_query")
	check(interactor.target == sticky, "候选未变时当前目标保持 sticky")

	# reachable 状态不跨扫描缓存：本次变更在下一轮立即生效。
	reachable[near.get_instance_id()] = false
	reset_counts()
	interactor._refresh_target()
	check(count_for(near) == 1 and count_for(far) == 1 and count_for(side) == 1,
		"reach 改变后下一轮仍每节点只查询一次")
	check(interactor.target == far, "reach 改变后立即排除原目标并按距离选剩余目标")

	# visible 与 disabled 仍在 reachable_query 之前被过滤，public candidates 口径不变。
	side.visible = false
	reset_counts()
	var visible_candidates := interactor.candidates()
	check(count_for(near) == 1 and count_for(far) == 1 and count_for(side) == 0,
		"不可见节点不查询 reachable_query")
	check(not visible_candidates.has(side), "不可见节点不进入 candidates")
	side.visible = true

	# disabled 与候选释放仍走同一轮扫描；禁用当前目标会立即清除焦点。
	reachable[near.get_instance_id()] = true
	far.enabled = false
	reset_counts()
	var public_candidates := interactor.candidates()
	check(count_for(near) == 1 and count_for(side) == 1 and count_for(far) == 0,
		"disabled 节点不查询 reachable_query 且不进入 candidates")
	check(not public_candidates.has(far) and public_candidates.has(near) and public_candidates.has(side),
		"disabled 节点被排除，其他候选保持不变")
	interactor._refresh_target()
	check(interactor.target == near, "禁用竞争目标后仍按距离排序恢复为 near")

	near.enabled = false
	reset_counts()
	interactor._refresh_target()
	check(count_for(near) == 0 and count_for(side) == 1,
		"disabled 当前目标不查询 reachable_query")
	check(interactor.target == side, "禁用当前目标后立即切换到剩余候选")

	side.queue_free()
	await process_frame
	reset_counts()
	interactor._refresh_target()
	check(count_for(near) == 0,
		"释放节点不会被扫描或查询")
	check(interactor.target == null, "释放最后候选后焦点被清除")

	holder.queue_free()
	await process_frame
	print("[interactor-query-reuse] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
