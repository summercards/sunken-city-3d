extends SceneTree
## 取景标定探针：给同一栋家园小屋，在不同相机距离下量它在画面里占多宽/多高。
##
## 用途：主人截图指认「那个取景就是最远」，需要把「看起来的那个大小」反解成米数，
## 而不是靠肉眼猜。这里用相机投影把木屋 AABB 的八个角投到屏幕上，量包围矩形占比。
##
## 跑法：python3 scripts/run_verification.py visual-home-framing
##      （SEA_FRAMING_SET 可覆盖距离表，逗号分隔，如 "60,78,90"）

const OUT_DIR := "res://outputs"
const CABIN_NAME := "太阳能木屋"

var main: Node
var cam: Camera3D


func _init() -> void:
	call_deferred("run")


## 世界空间包围盒。这栋小屋的每一块都是 MultiMeshInstance3D（一个 mesh 多实例），
## 所以不能只取节点 AABB —— 必须逐实例把 mesh 的 AABB 变换后求并集。
func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := child as MultiMeshInstance3D
		if mm.multimesh == null or mm.multimesh.mesh == null:
			continue
		var mesh_box := mm.multimesh.mesh.get_aabb()
		for i in mm.multimesh.instance_count:
			var xform := mm.global_transform * mm.multimesh.get_instance_transform(i)
			for c in 8:
				var p: Vector3 = xform * mesh_box.get_endpoint(c)
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var mesh_box2 := mi.mesh.get_aabb()
		for c in 8:
			var p2: Vector3 = mi.global_transform * mesh_box2.get_endpoint(c)
			if first:
				box = AABB(p2, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p2)
	return box


func _screen_rect(box: AABB) -> Rect2:
	var rect := Rect2()
	var first := true
	for i in 8:
		var p := cam.unproject_position(box.get_endpoint(i))
		if first:
			rect = Rect2(p, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(p)
	return rect


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	root.get_node("Economy").set_process(false)
	main.world_clock.paused = true
	main.world_clock.from_dict({"day": 3, "seconds": 21 * 3600 + 39 * 60, "day_length": 1200})
	main.daylight_rig.apply(21.65)
	for i in 20:
		await process_frame

	var cabin: Node3D = null
	for node in main.find_children("*", "Node3D", true, false):
		if node.name == CABIN_NAME:
			cabin = node
			break
	if cabin == null:
		printerr("[home-framing] FAIL 找不到 " + CABIN_NAME)
		quit(1)
		return
	# 只量水面上那半截：水下基座比上层宽 1.45 倍、还往下伸 17 m，
	# 混进来量出来的宽度与玩家实际看到的屋子无关。
	var surface_part: Node3D = cabin.get_node_or_null("太阳能木屋-海上区域") as Node3D
	var measured: Node = surface_part if surface_part != null else cabin

	var box := _aabb_of(measured)
	print("[home-framing] cabin=", measured.name, " aabb=", box)

	cam = main.cam
	# 标定探针必须能试到超过当前玩家上限的机位。
	cam.zoom_max = 400.0
	cam.suspend_follow()
	cam.target = Vector3(0.45, 1.75, -0.65)
	cam.orbit_dir = Vector3(-54, 76.37, 54)
	cam.refresh()
	var vp := root.get_visible_rect().size
	print("[home-framing] viewport=", vp, " fov=", cam.fov, " aspect=", vp.x / vp.y)

	var spec := OS.get_environment("SEA_FRAMING_SET")
	if spec == "":
		spec = "38,46,54,60,66,72,78,84,90,100,120,150,190"
	var rows: Array[String] = []
	for piece in spec.split(",", false):
		var d := float(piece.strip_edges())
		cam.distance = d
		cam.refresh()
		for i in 2:
			await process_frame
		var rect := _screen_rect(box)
		var w := rect.size.x / vp.x
		var h := rect.size.y / vp.y
		print("[home-framing] distance=%6.2f  width=%5.1f%%  height=%5.1f%%  rect=(%.0f,%.0f)-(%.0f,%.0f)" % [
			d, w * 100.0, h * 100.0, rect.position.x, rect.position.y, rect.end.x, rect.end.y])
		rows.append("%.0f m -> 宽 %.1f%%" % [d, w * 100.0])
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(OUT_DIR + "/home-framing-%d.png" % int(round(d)))

	print("[home-framing] ", " | ".join(rows))
	main.queue_free()
	await process_frame
	quit(0)
