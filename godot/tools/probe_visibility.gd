extends SceneTree
## 默认打开 main.tscn 时，十栋到底在不在画面里？相机能不能摇过去？
## 用户的"能看到吗"有两个含义，这里两个都量：初始镜头取景 + pan_bounds 可达范围。

func _init() -> void:
	call_deferred("run")


func _init_bounds() -> AABB:
	return AABB()


func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# 探针用 120 m 远机位；玩家上限是 38 m（SEA-CAMERA-R11），不抬高会被静默夹回。
	main.cam.zoom_max = 160.0
	for i in 4:
		await process_frame

	var street: Node3D = main.get_node("World/UnderwaterStreet")
	var box := AABB()
	var first := true
	for c in street.get_children():
		for m in c.find_children("*", "VisualInstance3D", true, false):
			if not (m is MeshInstance3D):
				continue
			var part: AABB = m.global_transform * m.get_aabb()
			box = part if first else box.merge(part)
			first = false
	print("[see] street_aabb min=", box.position.snappedf(0.1), " max=", box.end.snappedf(0.1))

	var cam: Camera3D = main.cam
	print("[see] cam target=", cam.target, " distance=", cam.distance,
		" orbit=", cam.orbit_dir, " fov=", cam.cam_fov)

	# 初始镜头：把街区八个角投影到 NDC
	var corners := []
	for xi in [box.position.x, box.end.x]:
		for yi in [box.position.y, box.end.y]:
			for zi in [box.position.z, box.end.z]:
				corners.append(Vector3(xi, yi, zi))
	var inside := 0
	var minx := 9.0
	var maxx := -9.0
	for p in corners:
		var ndc: Vector2 = cam.unproject_position(p)
		var vp: Vector2 = root.get_visible_rect().size
		var nx := ndc.x / vp.x
		var ny := ndc.y / vp.y
		minx = minf(minx, nx)
		maxx = maxf(maxx, nx)
		if nx >= 0.0 and nx <= 1.0 and ny >= 0.0 and ny <= 1.0 and cam.is_position_behind(p) == false:
			inside += 1
	print("[see] 初始镜头：可见角点=", inside, "/8  ndc_x 范围=", snappedf(minx, 0.01), "..", snappedf(maxx, 0.01))

	# pan_bounds 是否覆盖整条街（玩家能不能把镜头摇过去）
	var pan: Rect2 = cam.pan_bounds
	var foot := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
	print("[see] pan_bounds=", pan, " 街区footprint=", foot,
		" 完整覆盖=", pan.encloses(foot))
	print("[see] 街区 x=", snappedf(box.position.x, 0.1), "..", snappedf(box.end.x, 0.1),
		" / pan x=", pan.position.x, "..", pan.end.x)

	# 把镜头对准街区后，是否可见
	cam.target = Vector3(box.get_center().x, 0.0, box.get_center().z)
	cam.distance = 120.0
	cam.orbit_dir = Vector3(-0.55, 0.95, 0.75)
	cam.refresh()
	await process_frame
	await process_frame
	var inside2 := 0
	for p in corners:
		var ndc: Vector2 = cam.unproject_position(p)
		var vp: Vector2 = root.get_visible_rect().size
		var nx := ndc.x / vp.x
		var ny := ndc.y / vp.y
		if nx >= 0.0 and nx <= 1.0 and ny >= 0.0 and ny <= 1.0 and cam.is_position_behind(p) == false:
			inside2 += 1
	print("[see] 对焦街区后：可见角点=", inside2, "/8")

	main.queue_free()
	await process_frame
	quit(0)
