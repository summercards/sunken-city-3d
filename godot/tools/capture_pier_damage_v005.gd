extends SceneTree
func _init()->void: call_deferred("run")
func run()->void:
 var main:Node=load("res://scenes/main.tscn").instantiate();root.add_child(main);main._autosave_on=false;main.set_process(false)
 for i in 12: await process_frame
 var ranch:Node3D=main._zone_nodes.get("rooftop_ranch",null)
 var pier:Node3D=ranch.get_node("Models/ORF2_实例_pier")
 var box:=AABB();var first:=true
 for n in pier.find_children("*","MeshInstance3D",true,false):
  var mi:MeshInstance3D=n
  if mi.mesh==null: continue
  var b: AABB=mi.global_transform*mi.mesh.get_aabb()
  box=b if first else box.merge(b);first=false
 print("PIER_BOUNDS ",box)
 var cam:Camera3D=main.cam;cam.set_process(false);cam.follow_enabled=false;cam.target=box.get_center();cam.dir=Vector3(-0.5,0.12,-0.85).normalized();cam.distance=maxf(box.size.length()*0.75,10.0);cam.cam_fov=40;cam.apply_pose()
 for i in 10: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://outputs/rooftop_ranch_v005_pier_damage_final.png")
 print("SAVED")
 quit(0)
