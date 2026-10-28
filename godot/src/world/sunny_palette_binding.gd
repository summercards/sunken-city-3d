@tool
extends "res://src/ambient/scene_component.gd"
const MATERIALS = {
 "Matte": preload("res://assets/materials/solar_cabin/sunny_matte.tres"),
 "Metal": preload("res://assets/materials/solar_cabin/sunny_metal.tres"),
 "Gloss": preload("res://assets/materials/solar_cabin/sunny_gloss.tres"),
 "Emission": preload("res://assets/materials/solar_cabin/sunny_emission.tres")}
func _ready() -> void:
 bind(self)
func bind(node: Node) -> void:
 if node is MeshInstance3D:
  for surface in node.mesh.get_surface_count():
   var m: Material=node.mesh.surface_get_material(surface)
   var role: String="Matte"
   if m!=null:
    for name in MATERIALS:
     if name in m.resource_name:role=name
   node.set_surface_override_material(surface,MATERIALS[role])
 for c in node.get_children():bind(c)
