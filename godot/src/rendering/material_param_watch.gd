@tool
extends Node
## 编辑器内的材质参数守卫。
##
## 运行期由 `main.gd` 调 `MaterialParamGuard.enforce()`；但「模型变白」是**在编辑器里
## 移动节点时**看到的，那一刻游戏逻辑没跑，运行期的兜底救不了预览。
## 这个节点是 @tool，编辑器打开 main.tscn 就会执行一次，把内存里缺的参数补齐，
## 让编辑器预览和游戏内表现一致。
##
## 只改内存、不写盘：写盘交给 `scripts/repair_material_params.py`，
## 因为 ResourceSaver 正是这次事故的元凶（会按未就绪的 uniform 列表重建参数行）。

const MaterialParamGuard = preload("res://src/rendering/material_param_guard.gd")


func _ready() -> void:
	MaterialParamGuard.enforce()
	if Engine.is_editor_hint():
		print("[material-guard] 编辑器内已按基线校验材质参数")
