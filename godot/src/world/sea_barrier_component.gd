@tool
extends "res://src/ambient/scene_component.gd"
## 家园外围残楼围挡的组件契约。
##
## 只多做一件事：把公共白盒材质落到真正的 MeshInstance3D 上。
##
## 为什么不用在 tscn 里逐个写 `surface_material_override/N`：
##   一个 20 米围挡件里有 15–105 个 mesh 节点，逐个写节点名要求 GLB 节点名
##   完全稳定（含中文与括号），改一次建模就全断。这里按类型遍历，对节点名免疫。
##   历史教训（SEA-ASSET-R43）：override 写在 `Visual` 这类 Node3D 上时单个 surface
##   会被引擎占位重映射救回、多 surface 整组失效 —— 所以必须落在 MeshInstance3D 上。

const MATTE := preload("res://assets/materials/barrier/matte.tres")


func _ready() -> void:
	_apply(self)


func _apply(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface, MATTE)
	for child in node.get_children():
		_apply(child)
