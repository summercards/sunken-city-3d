extends SceneTree
var checks:=0
var failures:=0
func _init()->void: call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok: failures+=1;printerr("FAIL ",label)
const Motor = preload("res://src/player/character_motor.gd")
func body_hits(from:Vector3,to:Vector3,mask:=Motor.SCENE_GROUND_LAYER)->Dictionary:
 return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,mask))
func capsule_hit(start:Vector3,end:Vector3,mask:=Motor.SCENE_GROUND_LAYER)->Dictionary:
 var actor:=CharacterBody3D.new(); actor.collision_layer=512; actor.collision_mask=mask; actor.position=start
 var collider:=CollisionShape3D.new(); var shape:=CapsuleShape3D.new(); shape.radius=0.22; shape.height=1.3; collider.shape=shape; collider.position.y=0.65; actor.add_child(collider); root.add_child(actor)
 await physics_frame
 var hit:=actor.move_and_collide(end-start,true,0.0001)
 var result:Dictionary={}
 if hit != null:
  var body := hit.get_collider() as CollisionObject3D
  var hit_shape: Node = body.shape_owner_get_owner(body.shape_find_owner(hit.get_collider_shape_index()))
  result = {"collider": body, "shape": hit_shape.name, "position": hit.get_position(), "normal": hit.get_normal()}
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
 check(surface.get_node_or_null("SurfaceCollision/LowerLeftEdgeGuard")!=null and surface.get_node_or_null("SurfaceCollision/LowerFrontEdgeGuardLeft")!=null and surface.get_node_or_null("SurfaceCollision/LowerFrontEdgeGuardRight")!=null,"lower deck edge guards exist")
 check(surface.get_node_or_null("SurfaceCollision/UpperLeftEdgeGuard")!=null and surface.get_node_or_null("SurfaceCollision/UpperRightEdgeGuard")!=null,"upper deck edge guards exist")
 check(surface.get_node_or_null("SurfaceCollision/StoolFront")!=null and surface.get_node_or_null("SurfaceCollision/StoolSide")!=null,"stool collision proxies exist")
 if collision!=null:
  check(collision.collision_layer==Motor.SCENE_GROUND_LAYER and collision.collision_mask==512,"wall layer/mask role")
 var submerged:Node=main.get_node_or_null("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海下基座")
 check(submerged==null or submerged.find_children("*","CollisionObject3D",true,false).is_empty(),"submerged base has no actor collision")
 var zone:Node3D=main.get_node("World/Zones/Zone1HomeHarbor")
 var lower=zone.landing_point("main").ground()
 check(surface.get_parent().get_node_or_null("WalkAreas/TemporaryHomeRamp") == null, "no temporary ramp in the home scene")
 var old_ramp_feet := surface.to_global(Vector3(2.65, 2.15, 6.0))
 var old_ramp_support := body_hits(old_ramp_feet + Vector3.UP, old_ramp_feet + Vector3.DOWN * 0.1)
 check(old_ramp_support.get("collider") == collision and absf(old_ramp_support.position.y - old_ramp_feet.y) < 0.015,
  "the former ramp footprint has only the normal deck at foot height")
 var bottom:Node3D=surface.find_child("SunroomLadderBottomAnchor",true,false)
 var top:Node3D=surface.find_child("SunroomLadderTopAnchor",true,false)
 check(bottom!=null and top!=null,"authored ladder endpoints remain")
 var shore:Vector3=zone.landing_point("main").stand_position()
 var lower_path:Array=lower.path_between(shore,bottom.global_position)
 check(not lower_path.is_empty(),"lower route reaches ladder foot")
 var wall_hit:=body_hits(Vector3(-0.2,4.45,-0.4),Vector3(1.3,4.45,-0.4))
 report_hit("wall-ray",wall_hit)
 check(not wall_hit.is_empty() and wall_hit.collider==collision,"ray sees authored wall")
 var waist:=body_hits(Vector3(-0.2,2.0,-0.4),Vector3(1.3,2.0,-0.4))
 report_hit("wall-waist-ray",waist)
 var diagonal=await capsule_hit(Vector3(1.2,1.38,-0.4),Vector3(-0.2,1.38,-0.4))
 report_hit("wall-capsule-diagonal",diagonal)
 check(not diagonal.is_empty(),"capsule diagonal approach meets authored wall")
 var infill_hit:=body_hits(surface.to_global(Vector3(4.66,3.15,3.1)),surface.to_global(Vector3(4.66,3.15,2.1)))
 check(infill_hit.get("collider") == collision,"solid infill blocks walking into the former opening")
 var ladder_corridor := surface.to_global(Vector3(4.66225, 2.16, 4.05))
 var ladder_approach := await capsule_hit(ladder_corridor, bottom.global_position + Vector3.UP * 0.01)
 check(ladder_approach.is_empty(), "gap between the sofa and the ladder stays clear")
 check((await capsule_hit(surface.to_global(Vector3(3.3, 2.16, 4.05)), ladder_corridor)).is_empty(),
  "the open deck connects to the ladder corridor")
 var stool_hit := await capsule_hit(surface.to_global(Vector3(8.45, 2.16, 10.85)), surface.to_global(Vector3(9.15, 2.16, 10.96)))
 check(stool_hit.get("shape") == &"StoolFront", "stool blocks the actor capsule")
 var edge_hit:=await capsule_hit(surface.to_global(Vector3(-0.35,1.38,4.15)),surface.to_global(Vector3(-1.4,1.38,4.15)))
 check(not edge_hit.is_empty() and edge_hit.get("collider")==collision,"lower water-side edge blocks the actor capsule")
 await check_bridge_and_solar_room(surface)
 var upper:Node3D=zone.walk_areas.filter(func(a):return str(a.area_id)=="sunroom_upper_deck")[0] if not zone.walk_areas.filter(func(a):return str(a.area_id)=="sunroom_upper_deck").is_empty() else null
 if upper!=null:
  upper.active=true;zone.rebuild_ground()
  check(not upper.path_between(top.global_position,Vector3(6.0,6.246335,0.0)).is_empty(),"upper route remains available to world queries")
 var scene_support:=body_hits(shore+Vector3.UP*0.08,shore+Vector3.DOWN*0.1)
 check(str(scene_support.get("collider","")).contains("BoardHullContact"),"shore marker is supported by the scene bridge")
 check(body_hits(shore+Vector3.UP*0.08,shore+Vector3.DOWN*0.1,Motor.GROUND_LAYER).is_empty(),"no generated floor at the home berth")
 check(body_hits(bottom.global_position+Vector3.UP*0.10,bottom.global_position+Vector3.DOWN*0.10,Motor.GROUND_LAYER).is_empty(),"no generated floor by the sunroom")
 check(ramp.get_node_or_null("SlopeCollision")!=null,"temporary ramp has explicit slope collision")
 fixture.queue_free();await process_frame
 check(not is_instance_valid(fixture),"temporary slope removed before exit")
 main.queue_free();await process_frame
 print("[sunroom-surface-collision] %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)

func check_bridge_and_solar_room(surface: Node3D) -> void:
 const FEET := 2.16
 for test: Array in [
  [&"CourtyardSofa", Vector3(4.0, FEET, 5.77), Vector3(5.16, FEET, 5.77)],
  [&"SolarRoomLeftWall", Vector3(5.88, FEET, 3.65), Vector3(7.0, FEET, 3.65)],
  [&"SolarRoomRightWall", Vector3(11.65, FEET, 5.45), Vector3(10.5, FEET, 5.45)],
  [&"SolarRoomFrontGlass", Vector3(8.35, FEET, 8.75), Vector3(8.35, FEET, 6.6)],
  [&"LeftRope", Vector3(1.7, FEET, 14.7), Vector3(0.1, FEET, 14.7)],
  [&"RightRope", Vector3(4.3, FEET, 13.2), Vector3(6.0, FEET, 13.2)],
  [&"LowerFrontEdgeGuardLeft", Vector3(-0.15, FEET, 10.6), Vector3(-0.15, FEET, 11.8)],
  [&"LowerFrontEdgeGuardRight", Vector3(6.65, FEET, 10.6), Vector3(6.65, FEET, 11.8)],
  [&"End", Vector3(3.07, FEET, 16.85), Vector3(3.07, FEET, 18.2)],
 ]:
  var hit := await capsule_hit(surface.to_global(test[1]), surface.to_global(test[2]))
  check(hit.get("shape") == test[0], "capsule stops at %s, first contact: %s" % [test[0], hit.get("shape", &"none")])

 for x: float in [1.35, 3.07, 4.8]:
  var courtyard := surface.to_global(Vector3(x, FEET, 10.8))
  var bridge := surface.to_global(Vector3(x, FEET, 13.1))
  check((await capsule_hit(courtyard, bridge)).is_empty(), "bridge entry is clear at x = %.2f" % x)
  check((await capsule_hit(bridge, courtyard)).is_empty(), "bridge exit is clear at x = %.2f" % x)
  for z: float in [11.50, 11.60, 11.70]:
   var join := surface.to_global(Vector3(x, FEET, z))
   var support := body_hits(join + Vector3.UP * 0.05, join + Vector3.DOWN * 0.07)
   check(not support.is_empty(), "bridge join has deck support at %.2f, %.2f" % [x, z])
