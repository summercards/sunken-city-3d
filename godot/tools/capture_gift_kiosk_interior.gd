extends SceneTree
var main: Node
var shop: Node3D
var area: Node3D
var reveal: Node3D
var checks:=0
var failures:=0
var views:=[]
func _init()->void:call_deferred("run")
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frame(eye: Vector3,target: Vector3,fov:=36.0)->void:
	main.cam.global_position=eye;main.cam.look_at(target,Vector3.UP);main.cam.fov=fov
func shot(label: String)->void:
	for i in 4:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();check(image.get_width()>=1280,"actual GPU image "+label);image.save_png("res://outputs/gift-kiosk-interior-"+label+".png");views.append({"label":label,"roof":reveal.snapshot(),"actor":str(main.player.global_position)})
func run()->void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false);main.cam.suspend_follow();main.cam.set_process(false);main.boat.set_process(false);main.hud.hide();root.get_node("Economy").ticking=false
	for i in 12:await process_frame
	shop=main.get_node("World/SeaStructures/floating_shop");shop.set_physics_process(false);shop.set_motion_time(0);area=shop.walk_areas[0];reveal=shop.get_node("RoofReveal");reveal.set_process(false);main.daylight_rig.apply(12.0)
	var p:=shop.global_position
	var start:=shop.to_global(Vector3(0,.3,7.4));start.y=area.surface_y;main.actor_controller.restore_pose({"mode":0,"player":[start.x,start.y,start.z]});main.actor_controller.walk_area=area;reveal.advance(1)
	frame(p+Vector3(18,21,23),p+Vector3(0,1.6,0),35)
	await shot("outside")
	check(main._start_walk(area,shop.to_global(Vector3(0,.3,0))),"actual player enters tiled interior")
	var count:=0
	for i in 350:
		await physics_frame;main._update_walk(1.0/60.0);reveal.advance(1.0/60.0)
		if i%12==0:await shot("entry-%02d"%count);count+=1
		if main.actor_controller.state_id()=="ashore_idle":break
	reveal.advance(1);check(reveal.snapshot().visible_roofs==0,"actual interior roof clear")
	await shot("hero-day")
	frame(p+Vector3(11,14,15),p+Vector3(0,1.4,0),36);await shot("close-day")
	frame(p+Vector3(0,21,.01),p+Vector3(0,.5,0),29);await shot("top-day")
	var counter: Node3D=shop.get_node("Objects/SupplyCounter");check(main._start_walk(area,counter.global_position),"actual player reaches checkout customer side")
	for i in 350:
		await physics_frame;main._update_walk(1.0/60.0);reveal.advance(1.0/60.0)
		if main.actor_controller.state_id()=="ashore_idle":break
	frame(p+Vector3(7,10,11),p+Vector3(-.8,1.1,-1),40);await shot("checkout-day")
	counter.interact(main.player);check(main.shop_panel.is_open(),"checkout retains general store interaction");await shot("checkout-panel");main.shop_panel.close()
	main.daylight_rig.apply(20.0);frame(p+Vector3(11,14,15),p+Vector3(0,1.4,0),36);await shot("inside-night")
	var file:=FileAccess.open("res://outputs/gift-kiosk-interior-render.json",FileAccess.WRITE);file.store_string(JSON.stringify({"views":views,"expected_faults":[],"not_run":["low-end device performance"]},"  "));file.close()
	main.queue_free();await process_frame
	print("[gift-kiosk-interior-render] ",checks," checks, ",failures," failures");quit(0 if failures==0 else 1)
