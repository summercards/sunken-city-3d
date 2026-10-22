extends SceneTree
## 真实渲染：出航、绕岸、减速靠泊，再由同一上岸点走向独立菜箱。
## Godot --path godot --resolution 960x600 --write-movie outputs/surface-movement.avi --fixed-fps 30 --script res://tools/capture_surface_movement.gd
var main: Node
var frame := 0
var phase := 0
var on_land_frames := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	main.cam.distance = 21.0
	main.cam.target = main.boat.position
	main.cam._apply()
	for i in 15: await process_frame
	var zones: Node = root.get_node("Zones")
	main._sail_to_landing(zones.landing("zone3","main"),"zone3","main")
	while frame < 1050:
		frame += 1
		main.cam.target = main.player.global_position + Vector3(0,.5,0)
		if phase == 0 and not main.boat.starts_sailing():
			phase = 1
			on_land_frames = 0
		if phase == 1:
			on_land_frames += 1
			if on_land_frames == 60:
				main._approach(main.farm_field.find("farm_plot_a"))
			if on_land_frames > 210: break
		await process_frame
		if frame in [90,240,450,600]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://outputs/surface-motion-%d.png" % frame)
	print("[surface-visual] frames=",frame," arrived=",phase==1," player=",main.player.global_position)
	main.queue_free()
	await process_frame
	quit(0 if phase==1 else 1)
