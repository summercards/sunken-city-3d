extends SceneTree
func _init()->void: call_deferred("run")
func run()->void:
 var main:Node=load("res://scenes/main.tscn").instantiate();root.add_child(main);main._autosave_on=false;main.set_process(false)
 for i in 12: await process_frame
 var ranch:Node3D=main._zone_nodes.get("rooftop_ranch",null)
 var area:Node3D=ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
 var landing:Node3D=area.get_node("Landing_main")
 var stand:Vector3=landing.stand_position();var park:Vector3=landing.get_node("BoatPark").global_position
 print("ROOT ",ranch.global_position," water ",main.water_node.global_position.y," area_y ",area.surface_y," triangles ",area.surface_triangles.size()/3)
 print("LANDING stand ",stand," park ",park," edge ",landing.get_node("DockEdge").global_position)
 for n in ranch.get_node("Models").get_children():
  if n.name.begins_with("ORF3_实例_stair") or n.name.begins_with("ORF5") or n.name=="ORF2_实例_pier":
   var b:=AABB();var first=true
   for mesh in n.find_children("*","MeshInstance3D",true,false):
    var mi:MeshInstance3D=mesh;if mi.mesh==null:continue
    var q: AABB=mi.global_transform*mi.mesh.get_aabb();b=q if first else b.merge(q);first=false
   print("NODE ",n.name," vis ",n.visible," box ",b)
 print("OPEN_WATER_PARK ",main._is_open_water(park.x,park.z))
 quit(0)
