extends SceneTree
## 霓虹花园屋顶可活动区 + 船老大站位的验后探针（只读）。
##
##   godot --headless --path godot --script res://tools/probe_neon_roof_landing.gd

var main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 12:
		await process_frame
	var quarter: Node3D = main.get_node_or_null("World/SeaStructures/neon_garden_quarter")
	if quarter == null:
		print("[neon-roof] FAIL 霓虹花园不在主场景")
		quit(1)
		return
	print("[neon-roof] 楼根=%s rotY=%.1f° 水面=%.2f" % [
		str(quarter.global_position), rad_to_deg(quarter.global_rotation.y), main.WATER_LEVEL])

	var area: Node3D = quarter.get_node_or_null("WalkAreas/WalkLeftRoof")
	if area == null:
		print("[neon-roof] FAIL 没有 WalkLeftRoof")
		quit(1)
		return
	print("[neon-roof] 左楼屋顶 surface_y=%.2f(局部) 世界=%.2f 派生格=%s 可用=%s" % [
		float(area.surface_y), quarter.global_position.y + float(area.surface_y),
		str(area.get("derived_cells")), str(area.get("derived_usable"))])

	print("[neon-roof] 派生矩形 %d 块:" % (area.rects as Array).size())
	for r in area.rects:
		var rect: Rect2 = r
		print("      pos=(%.2f,%.2f) size=(%.2f,%.2f)" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	print("[neon-roof] span=%.2f..%.2f body_radius=%.2f" % [float(area.span_min), float(area.span_max), float(area.body_radius)])
	var landings: Array = quarter.landing_points()
	print("[neon-roof] landing_points=%d" % landings.size())
	for lp in landings:
		var data: Dictionary = lp.data()
		var stand: Vector3 = lp.stand_position()
		print("[neon-roof]   %s 站立点=%s  船位=%s  y差=%.2f" % [
			str(data.get("id")), str(stand), str(data.get("boatPark")), float(stand.y) - float(data["boatPark"][1])])

	# 船老大锚点是否解析成功
	var hub: Node = main.get_node_or_null("NpcAnchorHub")
	if hub == null:
		print("[neon-roof] WARN 没有 NpcAnchorHub")
	else:
		var snap: Dictionary = hub.anchor_snapshot()
		for key in ["residence_dock_workshop", "residence_dock_workshop_work",
				"residence_dock_workshop_social"]:
			if snap.has(key):
				var row: Dictionary = snap[key]
				print("[neon-roof] 锚点 %s zone=%s pos=%s validated=%s" % [
					key, str(row.get("zone")), str(row.get("position")), str(row.get("support_validated"))])
			else:
				print("[neon-roof] 锚点 %s 缺失" % key)
	quit(0)
