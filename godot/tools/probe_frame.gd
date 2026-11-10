extends SceneTree
## 只读：把 LeftBuilding 局部的点换算成世界点，并报出泊位与主角色的实际世界坐标。
##
##   --script res://tools/probe_frame.gd -- --points="-7.0,-1.98;-9.0,-3.0"

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
	var quarter: Node3D = main.get_node_or_null("World/SeaStructures/neon_garden_quarter") as Node3D
	if quarter == null:
		print("[frame] 找不到街区")
		quit(2)
		return
	var left: Node3D = quarter.get_node_or_null("Visual/LeftBuilding") as Node3D
	print("[frame] quarter 世界原点 (%.2f, %.2f, %.2f)" % [
		quarter.global_position.x, quarter.global_position.y, quarter.global_position.z])
	print("[frame] quarter basis  x(%.4f,%.4f) z(%.4f,%.4f)" % [
		quarter.global_transform.basis.x.x, quarter.global_transform.basis.x.z,
		quarter.global_transform.basis.z.x, quarter.global_transform.basis.z.z])
	print("[frame] LeftBuilding 世界原点 (%.2f, %.2f, %.2f)" % [
		left.global_position.x, left.global_position.y, left.global_position.z])
	var probe_y := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--y="):
			probe_y = float(arg.substr(4))
	# 泊位三件套
	for landing_name in ["Landing_main"]:
		var landing: Node3D = quarter.get_node_or_null("WalkAreas/WalkLeftRoof/" + landing_name) as Node3D
		if landing == null:
			continue
		print("[frame] %s 世界 (%.2f, %.2f, %.2f)" % [landing_name,
			landing.global_position.x, landing.global_position.y, landing.global_position.z])
		for child_name in ["BoatPark", "DockEdge"]:
			var marker: Node3D = landing.get_node_or_null(child_name) as Node3D
			if marker == null:
				continue
			var w: Vector3 = marker.global_position
			print("[frame]   %s 世界 (%.2f, %.2f, %.2f)  楼体局部 (%.2f, %.2f, %.2f)" % [
				child_name, w.x, w.y, w.z,
				(left.global_transform.affine_inverse() * w).x,
				(left.global_transform.affine_inverse() * w).y,
				(left.global_transform.affine_inverse() * w).z])
	# 逐个坐标换算
	var points := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--points="):
			points = arg.substr(9)
	if points != "":
		print("[frame] LeftBuilding 局部 → 世界：")
		for chunk in points.replace(";", "|").split("|"):
			var parts := chunk.split(",")
			if parts.size() < 2:
				continue
			var lx := float(parts[0])
			var lz := float(parts[1])
			var ly := float(parts[2]) if parts.size() > 2 else probe_y
			var w2: Vector3 = left.to_global(Vector3(lx, ly, lz))
			print("[frame]   局部 (%7.2f, %7.2f, %7.2f) → 世界 (%7.2f, %7.2f, %7.2f)" % [
				lx, ly, lz, w2.x, w2.y, w2.z])
	quit(0)
