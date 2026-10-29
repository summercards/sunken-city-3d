extends SceneTree
## 只读探针：数一数运行时的物理世界里到底有多少碰撞体。
##
## 用来回答一个反复被问的问题：「角色能不能走，是不是靠阻挡判断的？」
##
##   godot --path godot --script res://tools/probe_world_colliders.gd

var main
var counts := {}


func _init() -> void:
	_run.call_deferred()


func settle(n := 6) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	root.get_node("GameState").enter_zone("zone1")
	await settle(30)

	_survey(root)
	print("[colliders] 场景树统计: ", JSON.stringify(counts))

	# 物理服务器侧：场景里挂了多少个 body
	var bodies := 0
	for n in _all(root):
		if n is PhysicsBody3D:
			bodies += 1
			var kinds: String = n.get_class()
			counts[kinds] = int(counts.get(kinds, 0)) + 1
	print("[colliders] PhysicsBody3D 总数: ", bodies)
	print("[colliders] 按类型: ", JSON.stringify(counts))

	# 角色与玩家的碰撞设置
	if main.player != null:
		var pb := main.player is PhysicsBody3D
		print("[colliders] player 是 PhysicsBody3D: ", pb,
			"  子节点类型: ", _child_kinds(main.player))

	# 栈桥东缘：从上往下打射线，看有没有"墙"
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	for probe in [[1.0, 14.2], [1.4, 14.2], [3.0, 14.2], [5.4, 14.2], [6.6, 14.2]]:
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(float(probe[0]), 1.38 + 0.5, float(probe[1])),
			Vector3(float(probe[0]), 1.38 - 1.5, float(probe[1])))
		var hit: Dictionary = space.intersect_ray(q)
		print("[colliders] 竖直射线 x=%.2f z=%.2f → %s" % [
			float(probe[0]), float(probe[1]),
			("命中 y=%.2f" % (hit.position as Vector3).y) if not hit.is_empty() else "无任何碰撞体"])
	quit(0)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _child_kinds(n: Node) -> String:
	var kinds := []
	for c in n.get_children():
		kinds.append(c.get_class())
	return ",".join(kinds) if not kinds.is_empty() else "(无子节点)"


func _survey(n: Node) -> void:
	for c in n.get_children():
		var k: String = c.get_class()
		if k in ["StaticBody3D", "CollisionShape3D", "RigidBody3D", "CharacterBody3D",
				"Area3D", "CollisionPolygon3D"]:
			counts[k] = int(counts.get(k, 0)) + 1
		_survey(c)
