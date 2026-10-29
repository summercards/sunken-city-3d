extends SceneTree
## 只读探针：量角色模型的实际水平轮廓半径，用来决定行走矩形要内缩多少。
##
##   godot --path godot --script res://tools/probe_player_radius.gd

var main


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
	await settle(24)
	main.actor_controller.restore_pose({"mode": 0, "player": [3.0, 1.38, 15.0]})
	await settle(8)

	var origin: Vector3 = main.player.global_position
	var best := 0.0
	var worst := ""
	_survey(main.player, origin, [])
	quit(0)


func _survey(node: Node, origin: Vector3, path: Array) -> void:
	for child in node.get_children():
		var here := path + [str(child.name)]
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var box: AABB = mi.global_transform * mi.mesh.get_aabb()
				var corners := [
					Vector3(box.position.x, 0, box.position.z),
					Vector3(box.end.x, 0, box.position.z),
					Vector3(box.end.x, 0, box.end.z),
					Vector3(box.position.x, 0, box.end.z),
				]
				for c: Vector3 in corners:
					var d := Vector2(c.x - origin.x, c.z - origin.z).length()
					if d > _best:
						_best = d
						print("[radius] max=%.3f  at %s  aabb=%s" % [
							d, "/".join(here), str(box)])
		_survey(child, origin, here)


var _best := 0.0
