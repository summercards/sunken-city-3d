@tool
extends "res://src/ambient/scene_component.gd"
## 沉没街景的纯观赏身份（SEA-ASSET-R42）。
##
## 颜色**不在运行期绑**：三档材质角色由预制体里序列化的 `surface_material_override`
## 决定，`tools/godot/submerged_street_import.py` 按导入后网格自带的 glTF 材质名写入。
## 2026-10-29 的教训就在这里——靠 @tool 脚本 `_ready()` 上色，编辑器里重新实例化、
## 脚本报错被跳过、或截图早一帧，模型都会退回 GLB 的 0.8 灰底材，看起来像「贴图丢了」。
##
## 本脚本只做一件不改外观的事：打开真实投影。水下楼的轮廓全靠这点阴影才立得住。

func _ready() -> void:
	_bind(self)

func _bind(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_bind(child)
