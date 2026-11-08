extends Node3D
## 兼容容器：角色、游动与相机由 DiveRuntimeController 统一管理。
## 保留节点脚本以兼容已发布的家园场景与旧工具引用。

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
