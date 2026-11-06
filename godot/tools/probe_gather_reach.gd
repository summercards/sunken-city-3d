extends SceneTree
## 诊断：采集点是否站在可行走面上、能不能从登陆点走过去（2026-11-06）。
## 只打印事实与建议坐标，不改场景。

var main: Node
var state: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	state = root.get_node("GameState")
	root.get_node("Economy").ticking = false
	for i in 10:
		await physics_frame
		await process_frame

	for spot in main.gather.spots:
		var zone_id: String = str(spot.get_meta("zone", ""))
		var pos: Vector3 = spot.global_position
		var zone: Node = main._zone_nodes.get(zone_id, null)
		if zone == null:
			print("[gr] %-14s zone=%s 未装配" % [spot.name, zone_id])
			continue
		var on_area: Variant = zone.area_at(pos, 0.6)
		var best: Vector3 = Vector3.INF
		var best_area: Node3D = null
		var best_d := INF
		for area in zone.walk_areas:
			var flat: Vector2 = area.clamp_point(pos.x, pos.z)
			var at: Vector3 = area.surface_point(Vector3(flat.x, area.surface_y + 0.4, flat.y))
			if not at.is_finite():
				at = area.surface_point(Vector3(flat.x, area.surface_y, flat.y))
			if not at.is_finite():
				continue
			var d := Vector2(at.x - pos.x, at.z - pos.z).length()
			if d < best_d:
				best_d = d
				best = at
				best_area = area
		# 从本区登陆点走过去要几步
		var landings: Array = zone.landing_points() if zone.has_method("landing_points") else []
		var path_len := -1
		if not best.is_finite() or best_area == null:
			print("[gr] %-14s zone=%-6s pos=%s 站不到行走面（最近登陆点 %d 个）" % [
				spot.name, zone_id, pos, landings.size()])
			continue
		for lp in landings:
			var from: Vector3 = lp.stand_position()
			var path: Array = best_area.path_between(from, best)
			if path.is_empty():
				continue
			var total := 0.0
			var prev: Vector3 = from
			for p: Vector3 in path:
				total += prev.distance_to(p)
				prev = p
			path_len = int(round(total))
			break
		print("[gr] %-14s zone=%-6s on=%s 建议=(%.3f, %.3f, %.3f) 位移=%.2fm 步行=%s" % [
			spot.name, zone_id, str(on_area != null), best.x, best.y, best.z, best_d,
			("不可达" if path_len < 0 else str(path_len) + "m")])

	print("[gr] trade_board=", main.trade_board.global_position,
		" board_focus=", main.trade_board.focus_position() if main.trade_board.has_method("focus_position") else Vector3.ZERO)
	for area in main._zone_nodes["zone1"].walk_areas:
		for rect: Rect2 in area.rects:
			print("[gr] zone1 area=", area.area_id, " rect=", rect, " world_center=", area.to_global(Vector3(rect.get_center().x,0,rect.get_center().y)))
	# 区块可走面清单
	for id in main._zone_nodes.keys():
		var zone2: Node = main._zone_nodes[id]
		for area in zone2.walk_areas:
			print("[gr] area %-10s id=%-24s y=%.2f span=%.2f..%.2f rects=%d" % [
				id, str(area.area_id), area.surface_y, area.span_min, area.span_max, area.rects.size()])

	main.queue_free()
	await process_frame
	quit(0)
