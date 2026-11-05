@tool
extends "res://src/ambient/scene_component.gd"
## 角色 → 材质 的单件覆盖。空表 = 走下面四个公共角色，与既有小屋组件完全一致；
## 室内房间的窗与前厅玻璃填 {"Gloss": room_glass.tres} —— 同一套色盘与着色器，
## 只是透光率和压色不同（房间外面是黑的，室外玻璃那么实就成了浅蓝板）。
@export var material_overrides: Dictionary = {}
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
   var mat: Material=material_overrides.get(role,MATERIALS[role])
   node.set_surface_override_material(surface,mat)
 for c in node.get_children():bind(c)
