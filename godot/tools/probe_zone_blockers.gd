extends SceneTree
## 只读：把一个区块的水面阻挡矩形（= 水面高度上真实挡船的轮廓）打出来。
##
##   --script res://tools/probe_zone_blockers.gd -- --zone=neon_garden_quarter

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	for i in 24:
		await process_frame
	var zone_id := "neon_garden_quarter"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="):
			zone_id = arg.substr(7)
	var zone: Node3D = main._zone_nodes.get(zone_id)
	if zone == null:
		print("[zblk] 找不到区块 ", zone_id)
		quit(2)
		return
	if zone.has_method("rebuild_blockers"):
		zone.rebuild_blockers(1.12, 1.6)
	var rects: Array = zone.water_block_rects
	var total := 0.0
	for r in rects:
		total += (r as Rect2).get_area()
	print("[zblk] zone=%s rects=%d total=%.1f m2" % [zone_id, rects.size(), total])
	var sorted := rects.duplicate()
	sorted.sort_custom(func(a, b): return (a as Rect2).get_area() > (b as Rect2).get_area())
	for r in sorted:
		var rect: Rect2 = r
		print("[zblk] x %.2f..%.2f  z %.2f..%.2f  (%.2f m2)" % [
			rect.position.x, rect.end.x, rect.position.y, rect.end.y, rect.get_area()])
	quit(0)
