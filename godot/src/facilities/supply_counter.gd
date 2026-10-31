@tool
extends "res://src/interaction/interactable.gd"
## 海上补给站的交互点。
##
## 位置语义：锚在正面招牌正下方的甲板上。浮店是封闭立面、没有店门窗，
## 所以不摆柜台也不开窗口 —— 玩家走到招牌下面按 E，就等于在无人值守的
## 补给站自取。规则不在这里：买卖仍走 Order/Farm 的公开端口。

signal opened(counter: Node3D)


func interact(_actor: Node3D) -> Dictionary:
	opened.emit(self)
	return {}
