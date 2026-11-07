@tool
extends "res://src/interaction/interactable.gd"
## 海上补给站的交互点。
##
## 锚在正式设施场景的室内柜台顾客侧，随设施支撑面移动。角色走近后按 E
## 打开现有综合商店；买卖仍由经营功能公开端口拥有。

signal opened(counter: Node3D)


func interact(_actor: Node3D) -> Dictionary:
	opened.emit(self)
	return {}
