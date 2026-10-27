extends SceneTree
## 验证 toon 材质的焦散：广播不同强度，抓同一帧对比。
var main: Node
var out := "D:/projects/sea-work/caustics/toon"
const F := 4.0
const BakeStore = preload("res://src/world/bake_store.gd")
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 70: await process_frame
	main.hud.hide(); main.markers.hide(); main.ribbon.hide()
	main.cam.suspend_follow()
	main.cam.orbit_dir = Vector3(-0.52, 0.30, 0.42)
	main.cam.target = Vector3(0, -3.0, 6)
	main.cam.distance = 16.0
	main.cam.refresh()
	for i in 12: await process_frame
	main.water_node.set_process(false)
	main.set_process(false); main.set_physics_process(false)
	for spec in [["t000", 0.0], ["t030", 0.30], ["t060", 0.60], ["t100", 1.0]]:
		BakeStore.apply_caustics({"caustic_strength": spec[1], "caustic_speed": 0.0})
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + spec[0] + ".png")
		print("[toon] ", spec[0], " strength=", spec[1])
	quit(0)
