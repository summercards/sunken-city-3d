extends SceneTree
var checks:=0
var failures:=0
func _init()->void: call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok: failures+=1;printerr("FAIL ",label)
## Ray queries target static wall bodies: layer 256. The motor uses the same
## value as its collision mask; 512 is the actor's own layer, not the query mask.
func body_hits(from:Vector3,to:Vector3,mask:=256)->Dictionary:
 return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,mask))
func capsule_hit(start:Vector3,end:Vector3,mask:=256)->Dictionary:
 var actor:=CharacterBody3D.new(); actor.collision_layer=512; actor.collision_mask=mask; actor.position=start
 var collider:=CollisionShape3D.new(); var shape:=CapsuleShape3D.new(); shape.radius=0.22; shape.height=1.3; collider.shape=shape; collider.position.y=0.65; actor.add_child(collider); root.add_child(actor)
 await physics_frame
 var hit:=actor.move_and_collide(end-start,true,0.0001)
 var result:Dictionary={}
 if hit!=null: result={"collider":hit.get_collider(),"position":hit.get_position(),"normal":hit.get_normal()}
 actor.queue_free(); return result
func report_hit(label:String,hit:Dictionary)->void:
 if hit.is_empty(): print("[sunroom-hit] ",label," none")
 else:
  var body:Node=hit.get("collider")
  print("[sunroom-hit] ",label," collider=",body.get_path() if body else "none"," layer=",body.collision_layer if body is CollisionObject3D else -1," pos=",hit.get("position",Vector3.INF)," normal=",hit.get("normal",Vector3.ZERO))
func run()->void:
 var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);main._autosave_on=false
 # Temporary slope fixture only; never saved in main.tscn or user placement.
 var fixture:=Node3D.new();fixture.name="TemporaryUphillFixture";fixture.set_meta("temporary_fixture",true);main.add_child(fixture)
 var ramp:Node3D=load("res://scenes/components/minimal_main/ramp.tscn").instantiate() as Node3D;ramp.name="TemporaryRamp";fixture.add_child(ramp);ramp.position=Vector3(50,0,50)
 for i in 18: await physics_frame
 var surface:Node3D=main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海上区域")
 var collision:Node=surface.get_node_or_null("SurfaceCollision")
 check(collision!=null,"surface owner has stable collision subtree")
 check(surface.get_node_or_null("SurfaceCollision/LeftWall")!=null,"segmented left wall exists")
 check(surface.get_node_or_null("SurfaceCollision/FrontWallLeft")!=null and surface.get_node_or_null("SurfaceCollision/FrontWallRight")!=null,"entry wall is segmented")
 if collision!=null:
  check(collision.collision_layer==256 and collision.collision_mask==512,"wall layer/mask role")
 var submerged:Node=main.get_node_or_null("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海下基座")
 check(submerged==null or submerged.find_children("*","CollisionObject3D",true,false).is_empty(),"submerged base has no actor collision")
 var zone:Node3D=main.get_node("World/Zones/Zone1HomeHarbor")
 var lower=zone.landing_point("main").ground()
 var bottom:Node3D=surface.find_child("SunroomLadderBottomAnchor",true,false)
 var top:Node3D=surface.find_child("SunroomLadderTopAnchor",true,false)
 check(bottom!=null and top!=null,"authored ladder endpoints remain")
 var shore:Vector3=zone.landing_point("main").stand_position()
 var lower_path:Array=lower.path_between(shore,bottom.global_position)
 check(not lower_path.is_empty(),"lower route reaches ladder foot")
 var wall_hit:=body_hits(Vector3(-0.2,4.45,-0.4),Vector3(1.3,4.45,-0.4),256)
 report_hit("wall-ray",wall_hit)
 check(not wall_hit.is_empty() and wall_hit.collider==collision,"ray sees authored wall")
 var waist:=body_hits(Vector3(-0.2,2.0,-0.4),Vector3(1.3,2.0,-0.4),256)
 report_hit("wall-waist-ray",waist)
 var diagonal=await capsule_hit(Vector3(1.2,1.38,-0.4),Vector3(-0.2,1.38,-0.4),256)
 report_hit("wall-capsule-diagonal",diagonal)
 check(not diagonal.is_empty(),"capsule diagonal approach meets authored wall")
 var door_hit:=body_hits(Vector3(4.4,2.15,4.0),Vector3(4.4,2.15,2.8),256)
 check(door_hit.is_empty(),"door/ladder corridor remains open")
 var door_reverse:=body_hits(Vector3(4.4,2.15,2.8),Vector3(4.4,2.15,4.0),256)
 check(door_reverse.is_empty(),"door/ladder corridor remains open in reverse")
 var upper:Node3D=zone.walk_areas.filter(func(a):return str(a.area_id)=="sunroom_upper_deck")[0] if not zone.walk_areas.filter(func(a):return str(a.area_id)=="sunroom_upper_deck").is_empty() else null
 if upper!=null:
  upper.active=true;zone.rebuild_ground()
  check(not upper.path_between(top.global_position,Vector3(6.0,6.246335,0.0)).is_empty(),"upper route remains available")
 check(ramp.get_node_or_null("SlopeCollision")!=null,"temporary ramp has explicit slope collision")
 fixture.queue_free();await process_frame
 check(not is_instance_valid(fixture),"temporary slope removed before exit")
 main.queue_free();await process_frame
 print("[sunroom-surface-collision] %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
