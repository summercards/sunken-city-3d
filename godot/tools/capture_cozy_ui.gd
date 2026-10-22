extends SceneTree
## 正常渲染的界面展示：演示存档在内存中准备，不碰玩家存档。
var main: Node
func _init() -> void:
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	var economy: Node = root.get_node("Economy")
	economy.ticking = false
	main._select_landing({"zone":"zone1","landing":"main","name":"主泊位"})
	var cell: Node3D = main.farm_field.find("home_plot:1")
	main._walking = false
	main._walk_path.clear()
	main.player.set_walking(false)
	main.player.global_position = cell.global_position+Vector3(0,0,1.35)
	main.cam.distance = 18.0
	main.cam.target = cell.global_position+Vector3(0,0.4,0)
	main.cam._apply()
	economy.give({"lettuce_seed":6,"tomato_seed":6,"pumpkin_seed":6})
	for i in 6:
		var id := "home_plot" if i==0 else "home_plot:%d" % i
		var crop: String = ["lettuce","tomato","pumpkin"][i%3]
		economy.farm.plant(id,crop)
		economy.farm.state(id).remaining = 0.0 if i<3 else 2.0
		economy.farm.state(id).water = 1.0
	for frame in 300:
		if frame == 25: main.hud.open_tab("plant")
		if frame == 110: main.hud._toggle_panel()
		if frame == 135: main._approach(cell)
		if frame == 230: main.salvage_panel.begin()
		await process_frame
		if frame in [65,155,195,265]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://outputs/cozy-ui-%d.png" % frame)
	print("[cozy-ui] native render complete")
	main.queue_free()
	await process_frame
	quit()
