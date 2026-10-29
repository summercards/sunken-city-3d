extends SceneTree
## 取证：把 zone1 码头的「可行走矩形」画成红框，俯视 + 侧视各拍一张，
## 用来对照哪一段甲板外的矩形落到了水里（= 没阻挡）。
##
##   godot --path godot --script res://tools/capture_walk_edge.gd

var main
var _bodies: Array = []
var _space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func settle(n := 8) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await settle(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/walkedge-" + name + ".png")
	print("[shot] ", name)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	root.get_node("GameState").enter_zone("zone1")
	main.actor_controller.restore_pose({"mode": 0, "player": [3.0, 1.38, 14.0]})
	await settle(30)
	_space = root.world_3d.direct_space_state

	var holder: Node = main.get_node_or_null("World/Zones/Zone1HomeHarbor/WalkAreas")
	if holder == null:
		for n in main.get_children():
			var h: Node = n.get_node_or_null("WalkAreas")
			if h != null:
				holder = h
	if holder == null:
		print("[shot] 找不到 WalkAreas")
		quit(1)
		return
	_draw_rects(holder)
	await settle(4)

	# 俯视：整条码头
	main.cam.orbit_dir = Vector3(0.02, 1.0, 0.16)
	main.cam.target = Vector3(2.0, 1.3, 11.0)
	main.cam.distance = 26.0
	main.cam.refresh()
	await shot("1-top")

	# 侧视：接近主人给的角度
	main.cam.orbit_dir = Vector3(-0.74, 0.42, 0.52)
	main.cam.target = Vector3(2.6, 1.5, 15.0)
	main.cam.distance = 8.5
	main.cam.refresh()
	await shot("2-side")
	quit(0)


func _draw_rects(holder: Node) -> void:
	for area in holder.get_children():
		if not ("rects" in area):
			continue
		var sy := float(area.surface_y) + 0.06
		for r in area.rects:
			var rect: Rect2 = r
			_edge(area, rect.position.x, rect.position.y, rect.end.x, rect.position.y, sy)
			_edge(area, rect.end.x, rect.position.y, rect.end.x, rect.end.y, sy)
			_edge(area, rect.end.x, rect.end.y, rect.position.x, rect.end.y, sy)
			_edge(area, rect.position.x, rect.end.y, rect.position.x, rect.position.y, sy)


func _edge(area: Node, x0: float, z0: float, x1: float, z1: float, sy: float) -> void:
	var a: Vector3 = area.to_global(Vector3(x0, 0, z0))
	var b: Vector3 = area.to_global(Vector3(x1, 0, z1))
	var mid := (a + b) * 0.5
	mid.y = sy
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(absf(b.x - a.x), 0.06), 0.03, maxf(absf(b.z - a.z), 0.06))
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.05, 0.05)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = mid
