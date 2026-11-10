extends SceneTree
## 目检用：每个设施按自己的上岸点/泊位取一张真实渲染图。
## 输出 res://outputs/access-<facility>.png；只读场景，不改玩法数据。

const PREFIX := "res://outputs/access-"

var main: Node
var shots: Array = []


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.cam.suspend_follow()
	if main.get("world_clock") != null:
		main.world_clock.paused = true
	for i in 30:
		await process_frame
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	var zones: Dictionary = main._zone_nodes
	for zid in zones:
		if only != "" and only != zid:
			continue
		var zone: Node3D = zones[zid]
		var lp = null
		for p in zone.landing_points():
			if lp == null or str(p.landing_id) == "main":
				lp = p
		if lp == null:
			continue
		var data: Dictionary = lp.data()
		var stand := Vector3(float(data.landStand[0]), float(data.landStand[1]), float(data.landStand[2]))
		var park := Vector3(float(data.boatPark[0]), float(data.boatPark[1]), float(data.boatPark[2]))
		var flat := Vector3(park.x - stand.x, 0, park.z - stand.z)
		if flat.length() < 0.5:
			flat = Vector3(0, 0, 1)
		var eye := stand + flat.normalized() * 13.0 + Vector3(0, 11.0, 0)
		await shot(zid, eye, stand + Vector3(0, 0.6, 0), 52.0)
	print("[capture] shots=", shots.size())
	quit(0)


func shot(name: String, eye: Vector3, target: Vector3, fov: float) -> void:
	main.cam.fov = fov
	main.cam.near = 0.1
	main.cam.far = 900.0
	main.cam.global_position = eye
	main.cam.look_at(target, Vector3.UP)
	main.cam.make_current()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		print("[capture] FAIL ", name)
		return
	var path := PREFIX + name.strip_edges().to_lower().replace("/", "_") + ".png"
	image.save_png(path)
	shots.append(path)
	print("[capture] ", path)
