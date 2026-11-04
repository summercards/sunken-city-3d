extends SceneTree
## Native frames from the production scene, with its actual seat/pose ports.
var main
var checks := 0
var failures := 0
var clock := 0.0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func pose(phase: float, effort: float) -> void:
	main.boat._stroke=phase;main.boat._row_blend=effort
	main.boat._vel=main.boat.cruise_speed()*effort;main.boat._sailing=effort>0.0
	main.boat._animate_oars(0.0);main.player._process(1.0/60.0)
	var contacts: Dictionary=main.boat.rowing_pose()
	for pair in [[main.player.left_elbow,contacts.left_grip],[main.player.right_elbow,contacts.right_grip]]:
		check(pair[0].get_node("Hand").global_position.distance_to(pair[1])<0.008,"production pose port keeps palm on grip")
func shot(label: String) -> void:
	clock+=0.15
	main.water_node.time=clock
	main.water_node.update_surface(clock,main.boat,main.cam.target)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/rowing-game-"+label+".png")==OK,"native capture "+label)
func run() -> void:
	preload("res://tools/lighting_capture_profile.gd").prepare()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.process_mode=Node.PROCESS_MODE_DISABLED
	main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide();main.get_node("Birds").hide()
	if main.start_screen!=null: main.start_screen.hide()
	main.boat.place_at(Vector3(26,1.12,25),0)
	main.boat.model.transform=Transform3D.IDENTITY
	main.actor_controller.restore_pose({"mode":1})
	check(main.player.rowing_pose_query.is_valid() and main.player._boat_seated,"production controller and pose query connected")
	main.player.apply_avatar(preload("res://tests/avatar_customization_support.gd").profile({"hat":"none","hair_style":"curly","hair_color":"sage","top":"vest"}))
	main.cam.follow_enabled=false;main.cam.target=main.boat.global_position+Vector3(0,.45,0)
	main.cam.distance=10.5;main.cam.orbit_dir=Vector3(.65,.90,.80);main.cam.refresh();main.daylight_rig.apply(9.0)
	pose(0.0,1.0);await shot("pull")
	pose(PI*.5,1.0);await shot("middle")
	pose(PI,1.0);await shot("recovery")
	pose(PI*1.5,1.0);await shot("return")
	pose(TAU*.875,1.0);await shot("late-pull")
	main.actor_controller.cancel();pose(0.0,0.0);await shot("idle")
	check(main.player._boat_seated,"cancel remains seated in production")
	main.cam.distance=9.0;main.cam.orbit_dir=Vector3(1,.40,.20);main.cam.refresh()
	pose(PI*.5,1.0);await shot("side")
	main.cam.target=main.boat.global_position+Vector3(0,.95,.42)
	main.cam.distance=5.0;main.cam.orbit_dir=Vector3(.6,.32,1);main.cam.refresh()
	pose(PI,1.0);await shot("arms-close")
	main.actor_controller.restore_pose({"mode":0,"player":[26,2,25]});main.player._process(1.0/60.0)
	check(main.player.get_parent()==main and main.player.grounded_motion_enabled and not main.player._boat_seated,"production ashore restore releases seat and enables capsule")
	check(absf(main.player.body_pivot.position.z)<0.0001 and absf(main.player.left_knee.rotation.x)<0.0001,"ashore has no seat offset or knee bend")
	main.actor_controller.restore_pose({"mode":1});pose(0.0,0.0)
	check(main.player.get_parent()==main.boat and not main.player.grounded_motion_enabled and main.player._boat_seated,"production reboarding restores seat and disables land capsule")
	main.queue_free();await process_frame
	print("[rowing-game] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
