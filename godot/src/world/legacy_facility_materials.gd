@tool
extends "res://src/ambient/scene_component.gd"
func _ready() -> void:
 var bindings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/legacy_home/material_bindings.json"))
 apply(self,bindings)
func apply(node: Node, bindings: Dictionary) -> void:
 if node is MeshInstance3D:
  for i in node.mesh.get_surface_count():
   var m: Material=node.mesh.surface_get_material(i)
   if m==null: continue
   var name_parts: PackedStringArray=m.resource_name.split(".")[0].rsplit("_",true,1)
   if name_parts.size()!=2: continue
   var unit: String=name_parts[0];var slot: int=int(name_parts[1])
   if bindings.has(unit) and slot<bindings[unit].size():
    node.set_surface_override_material(i,load("res://assets/materials/models/"+str(bindings[unit][slot])+".tres"))
 for c in node.get_children(): apply(c,bindings)
