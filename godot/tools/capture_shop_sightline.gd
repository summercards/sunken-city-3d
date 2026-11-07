extends SceneTree
var main: Node
var shop: Node3D
var roof: Node3D
var cut: Node3D
var checks:=0
var failures:=0
var evidence:=[]
func _init()->void:call_deferred("run")
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func shot(label: String)->void:
	for i in 4:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();check(image.get_width()>=1280,"GPU frame "+label);image.save_png("res://outputs/shop-sightline-"+label+".png");evidence.append({"label":label,"mask":cut.snapshot(),"actor":str(main.player.global_position)})
func run()->void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);main._autosave_on=false;main.set_process(false);main.set_physics_process(false);main.cam.suspend_follow();main.cam.set_process(false);main.boat.set_process(false);main.hud.hide();root.get_node("Economy").ticking=false
	for i in 10:await process_frame
	shop=main.get_node("World/SeaStructures/floating_shop");shop.set_physics_process(false);shop.set_motion_time(0);roof=shop.get_node("RoofReveal");roof.set_process(false);cut=shop.get_node("SightlineReveal");cut.set_process(false)
	check(cut._subject==main.player and cut._camera==main.cam,"production Main injects real actor/camera")
	var start:=shop.to_global(Vector3(0,.3,0));main.actor_controller.restore_pose({"mode":0,"player":[start.x,start.y,start.z]});main.actor_controller.walk_area=shop.walk_areas[0];roof.advance(1)
	var p:=shop.global_position;main.cam.global_position=p+Vector3(11,14,15);main.cam.look_at(p+Vector3(0,1.4,0),Vector3.UP);main.cam.fov=36
	for hour in [12.0,20.0]:
		main.daylight_rig.apply(hour);var suffix: String="day" if hour==12 else "night"
		cut.configure_subject(null,main.cam);cut.advance(1);await shot("before-"+suffix)
		cut.configure_subject(main.player,main.cam);cut.advance(.12);await shot("partial-"+suffix)
		cut.advance(1);await shot("after-"+suffix)
		check(cut.snapshot().active_meshes>10,"foreground mask active "+suffix)
	main.daylight_rig.apply(12)
	for i in 8:
		var angle:=float(i)*TAU/8
		main.cam.global_position=p+Vector3(18*sin(angle),18,18*cos(angle));main.cam.look_at(p+Vector3(0,1.4,0),Vector3.UP);cut.advance(0);await shot("orbit-%02d"%i)
	main.cam.global_position=p+Vector3(11,14,15);main.cam.look_at(p+Vector3(0,1.4,0),Vector3.UP)
	check(main._start_walk(shop.walk_areas[0],shop.to_global(Vector3(0,.3,7.4))),"real actor leaves room")
	for i in 400:
		await physics_frame;main._update_walk(1.0/60.0);roof.advance(1.0/60.0);cut.advance(1.0/60.0)
		if main.actor_controller.state_id()=="ashore_idle":break
	roof.advance(1);cut.advance(1);await shot("outside-restored")
	check(cut.snapshot().active_meshes==0 and roof.snapshot().visible_roofs==78,"outside restores facade and roof")
	var file:=FileAccess.open("res://outputs/shop-sightline-render.json",FileAccess.WRITE);file.store_string(JSON.stringify({"views":evidence,"expected_faults":[],"not_run":["low-end device performance"]},"  "));file.close()
	main.queue_free();await process_frame;print("[shop-sightline-render] ",checks," checks, ",failures," failures");quit(0 if failures==0 else 1)
