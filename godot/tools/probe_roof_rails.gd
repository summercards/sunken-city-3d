extends SceneTree
func _init()->void: call_deferred("run")
func box(node:Node, ranch:Node3D)->AABB:
 var inv:=ranch.global_transform.affine_inverse();var out:=AABB();var first=true
 for c in node.find_children("*","MeshInstance3D",true,false):
  var mi:MeshInstance3D=c;if mi.mesh==null:continue
  var b:AABB=inv*mi.global_transform*mi.mesh.get_aabb();out=b if first else out.merge(b);first=false
 return out
func run()->void:
 var main:Node=load("res://scenes/main.tscn").instantiate();root.add_child(main);main._autosave_on=false;main.set_process(false)
 for i in 12: await process_frame
 var r:Node3D=main._zone_nodes["rooftop_ranch"];var m:=r.get_node("Models")
 for c in m.get_children():
  if str(c.get_meta("source_instance","")).begins_with("ORF2_实例_rail"):
   var b:=box(c,r);var p:=c.position;print(c.get_meta("source_instance")," pos=",p," box=",b)
 quit(0)
