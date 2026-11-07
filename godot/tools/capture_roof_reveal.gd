extends SceneTree
## Main-scene renderer, actual actor and authored goods; controlled transition time.
var main: Node
var shop: Node3D
var area: Node3D
var reveal: Node3D
var checks := 0
var failures := 0
var views := []

func _init() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func shot(label: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_width() >= 1280, "actual rendered frame " + label)
	image.save_png("res://outputs/roof-reveal-"+label+".png")
	views.append({"frame":label,"actor":str(main.player.global_position),"reveal":reveal.snapshot()})

func pose(z: float) -> void:
	var p := shop.to_global(Vector3(0,0.3,z))
	p.y=area.surface_y
	main.actor_controller.restore_pose({"mode":0,"player":[p.x,p.y,p.z]})
	main.actor_controller.walk_area=area

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.suspend_follow()
	main.cam.set_process(false)
	main.boat.set_process(false)
	main.hud.hide()
	root.get_node("Economy").ticking=false
	for i in 12: await process_frame
	shop=main.get_node("World/SeaStructures/floating_shop")
	shop.set_physics_process(false)
	shop.set_motion_time(0)
	area=shop.walk_areas[0]
	reveal=shop.get_node("RoofReveal")
	reveal.set_process(false)
	main.daylight_rig.apply(12.0)
	var p: Vector3=shop.global_position
	main.cam.global_position=p+Vector3(25,26,32)
	main.cam.look_at(p+Vector3(0,2.0,0),Vector3.UP)
	main.cam.fov=35
	pose(7.4)
	reveal.advance(1)
	await shot("closed")
	# Actual walking from deck through the doorway, recording the aperture spread.
	var goal := shop.to_global(Vector3(0,0.3,0))
	goal.y=area.surface_y
	check(main._start_walk(area,goal),"actual actor walks through the open entry")
	var frame_no := 0
	for i in 300:
		await physics_frame
		main._update_walk(1.0/60.0)
		reveal.advance(1.0/60.0)
		if i%6==0:
			await shot("entry-%02d"%frame_no)
			frame_no+=1
		if main.actor_controller.state_id()=="ashore_idle": break
	for i in 60: reveal.advance(1.0/60.0)
	check(reveal.snapshot().amount==1 and reveal.snapshot().visible_roofs==0,"inside is fully unobstructed")
	await shot("inside")
	main.cam.global_position=p+Vector3(12,19,19)
	main.cam.look_at(p+Vector3(0,1.4,0),Vector3.UP)
	await shot("interior-close")
	main.cam.global_position=p+Vector3(25,26,32)
	main.cam.look_at(p+Vector3(0,2.0,0),Vector3.UP)
	goal=shop.to_global(Vector3(0,0.3,7.4))
	goal.y=area.surface_y
	check(main._start_walk(area,goal),"actual actor leaves through the same entry")
	frame_no=0
	for i in 300:
		await physics_frame
		main._update_walk(1.0/60.0)
		reveal.advance(1.0/60.0)
		if i%6==0:
			await shot("exit-%02d"%frame_no)
			frame_no+=1
		if main.actor_controller.state_id()=="ashore_idle": break
	for i in 60: reveal.advance(1.0/60.0)
	check(reveal.snapshot().amount==0 and reveal.snapshot().visible_roofs==78,"outside restores all roof parts")
	await shot("restored")
	var file := FileAccess.open("res://outputs/roof-reveal-render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"views":views,"expected_faults":[],"not_run":["full unrelated feature suite"]},"  "))
	file.close()
	main.queue_free()
	await process_frame
	print("[roof-reveal-render] ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
