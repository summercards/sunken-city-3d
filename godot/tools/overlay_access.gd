extends SceneTree
## 目检用：俯视叠加「水面阻挡（红色实心）/ 可行走面（绿色边框）/
## 上岸点（蓝）/ 停船点（品红）/ 码头边（黄）」。只读场景，不改数据。
##
## 为什么用 BoxMesh 而不是 ImmediateMesh 线条：正交相机下 ImmediateMesh
## 的线宽只有 1 px，截图里几乎看不见；实心薄板稳定得多。

const PREFIX := "res://outputs/plan-"

var main: Node
var shots: Array = []
var block_mat: StandardMaterial3D
var walk_mat: StandardMaterial3D


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.cam.suspend_follow()
	if main.get("hud") != null:
		main.hud.visible = false
	for i in 30:
		await process_frame
	block_mat = _mat(Color(1, 0.1, 0.05, 0.62))
	walk_mat = _mat(Color(0.1, 1, 0.25, 0.95))
	var zones: Dictionary = main._zone_nodes
	for zid in zones:
		if only != "" and only != zid:
			continue
		var zone: Node3D = zones[zid]
		if zone.has_method("rebuild_blockers"):
			zone.rebuild_blockers(1.12, 1.6)
		await shot_zone(zone, zid)
	print("[plan] shots=", shots.size())
	quit(0)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 1
	return mat


func shot_zone(zone: Node3D, zid: String) -> void:
	var rects: Array = zone.get("water_block_rects") if "water_block_rects" in zone else []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var marks: Array = []
	for r: Rect2 in rects:
		lo.x = minf(lo.x, r.position.x); lo.y = minf(lo.y, r.position.y)
		hi.x = maxf(hi.x, r.end.x); hi.y = maxf(hi.y, r.end.y)
		marks.append(_slab(Vector3(r.get_center().x, 30.0, r.get_center().y),
			Vector3(maxf(r.size.x, 0.06), 0.1, maxf(r.size.y, 0.06)), block_mat))
	var areas: Array = zone.get("walk_areas") if "walk_areas" in zone else []
	for area: Node3D in areas:
		var outlines: Array = area.call("outlines")
		for poly: PackedVector2Array in outlines:
			for i in poly.size():
				var p0: Vector2 = poly[i]
				var p1: Vector2 = poly[(i + 1) % poly.size()]
				var w0: Vector3 = area.to_global(Vector3(p0.x, 0, p0.y))
				var w1: Vector3 = area.to_global(Vector3(p1.x, 0, p1.y))
				lo.x = minf(lo.x, minf(w0.x, w1.x)); lo.y = minf(lo.y, minf(w0.z, w1.z))
				hi.x = maxf(hi.x, maxf(w0.x, w1.x)); hi.y = maxf(hi.y, maxf(w0.z, w1.z))
				marks.append(_bar(w0, w1, 30.2, 0.16, walk_mat))
		var tris: PackedVector3Array = area.get("surface_triangles")
		for i in range(0, tris.size() - 2, 3):
			var a: Vector3 = area.to_global(tris[i])
			var b: Vector3 = area.to_global(tris[i + 1])
			var c: Vector3 = area.to_global(tris[i + 2])
			marks.append(_bar(a, b, 30.2, 0.12, walk_mat))
			marks.append(_bar(b, c, 30.2, 0.12, walk_mat))
			marks.append(_bar(c, a, 30.2, 0.12, walk_mat))
			lo.x = minf(lo.x, minf(a.x, minf(b.x, c.x))); lo.y = minf(lo.y, minf(a.z, minf(b.z, c.z)))
			hi.x = maxf(hi.x, maxf(a.x, maxf(b.x, c.x))); hi.y = maxf(hi.y, maxf(a.z, maxf(b.z, c.z)))
		for child in area.get_children():
			if child.has_method("data"):
				var data: Dictionary = child.data()
				marks.append(_slab(Vector3(float(data.landStand[0]), 30.4, float(data.landStand[2])),
					Vector3(0.9, 0.1, 0.9), _mat(Color(0.15, 0.55, 1, 1))))
				marks.append(_slab(Vector3(float(data.boatPark[0]), 30.5, float(data.boatPark[2])),
					Vector3(1.2, 0.1, 1.2), _mat(Color(1, 0.2, 0.9, 1))))
				marks.append(_slab(Vector3(float(data.dockEdge[0]), 30.6, float(data.dockEdge[2])),
					Vector3(0.5, 0.1, 0.5), _mat(Color(1, 1, 0.1, 1))))
	if not lo.is_finite() or hi.x <= lo.x:
		print("[plan] skip ", zid)
		for m in marks:
			m.queue_free()
		return
	var size := (hi - lo).max(Vector2(8, 8)) + Vector2(4, 4)
	var center := (lo + hi) * 0.5
	main.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	main.cam.size = maxf(size.x, size.y)
	main.cam.near = 0.1
	main.cam.far = 400.0
	main.cam.global_position = Vector3(center.x, 120.0, center.y)
	main.cam.rotation = Vector3(-PI * 0.5, 0, 0)
	main.cam.make_current()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		var path := PREFIX + zid + ".png"
		image.save_png(path)
		shots.append(path)
		print("[plan] ", path)
	main.cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	for m in marks:
		m.queue_free()
	for i in 2:
		await process_frame


func _slab(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(node)
	node.global_position = center
	return node


func _bar(a: Vector3, b: Vector3, y: float, thickness: float, mat: Material) -> MeshInstance3D:
	var delta := Vector2(b.x - a.x, b.z - a.z)
	var length := maxf(delta.length(), 0.02)
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.1, thickness)
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(node)
	node.global_position = Vector3((a.x + b.x) * 0.5, y, (a.z + b.z) * 0.5)
	node.rotation = Vector3(0, atan2(-delta.y, delta.x), 0)
	return node
