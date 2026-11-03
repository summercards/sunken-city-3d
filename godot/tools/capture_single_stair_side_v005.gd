extends SceneTree
func _init()->void: call_deferred("run")
func run()->void:
 var main:Node=load("res://scenes/main.tscn").instantiate();root.add_child(main);main._autosave_on=false;main.set_process(false)
 for i in 12: await process_frame
 var ranch:Node3D=main._zone_nodes.rooftop_ranch
 var cam:Camera3D=main.cam;cam.set_process(false);cam.follow_enabled=false
 # 实际单段梯世界包围盒中心约 x=71,z=-51，专门从侧面拍平台与梯段。
 cam.target=Vector3(71.2,2.8,-51.0);cam.dir=Vector3(-0.15,0.18,-0.97).normalized();cam.distance=12.0;cam.cam_fov=38;cam.apply_pose()
 for i in 10: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://outputs/rooftop_ranch_v005_single_stair_side.png")
 print("SAVED")
 quit(0)
