extends SceneTree
## 只读探针：把 solar_cabin 各实例（尤其 bridge_rope）的世界 AABB 打出来，
## 用来把「栏杆绳」的位置量准 —— 行走矩形必须以绳为界，不能以甲板边为界。
##
##   godot --path godot --script res://tools/probe_rope_bounds.gd

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
	await settle(30)

	var zone: Node = main._zone_nodes.zone1
	_walk(zone, [])
	quit(0)


func _walk(node: Node, path: Array) -> void:
	for c in node.get_children():
		var here := path + [str(c.name)]
		var label := str(c.get_meta("asset_component", ""))
		if c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.multimesh.instance_count > 0:
				var box := AABB()
				var first := true
				for i in mmi.multimesh.instance_count:
					var xf: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(i)
					var b: AABB = xf * mmi.multimesh.mesh.get_aabb()
					box = b if first else box.merge(b)
					first = false
				if "rope" in label.to_lower() or "rope" in "/".join(here).to_lower():
					print("[rope] component=%s  count=%d" % [label, mmi.multimesh.instance_count])
					print("[rope]   世界 AABB: x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % [
						box.position.x, box.end.x, box.position.y, box.end.y,
						box.position.z, box.end.z])
					for i in mmi.multimesh.instance_count:
						var xf2: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(i)
						var b2: AABB = xf2 * mmi.multimesh.mesh.get_aabb()
						print("[rope]   实例%d: x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % [
							i, b2.position.x, b2.end.x, b2.position.y, b2.end.y,
							b2.position.z, b2.end.z])
		_walk(c, here)
