@tool
extends "res://src/interaction/interactable.gd"
## SEA-ROOM 出门点：玻璃前厅正面门洞上的那个「走出去」。
##
## 2026-11-11 补。用户截图报「在屋子里这里没有出去的操作热区，键盘操作出不去」：
## 屋里原来只有一个右下角圆钮和 X 键，**门口没有热区** —— 和屋外的「进入房间」
## 不对称。键盘玩家走到门边按 E 什么也不会发生，只能去发现那个小圆钮。
##
## 所以这里补一个和 `room_door.gd` 对偶的纯逻辑交互点（没有视觉几何，靠近距图标
## 与「[E] 离开房间」提示被看到）。它只发信号，进出流程仍由 `room_controller` 走
## 那条已有的圆幕过场 —— 不新增任何通道。
##
## 位置：前厅正面门洞（局部 z ≈ 4.25，见 `bedroom.tscn`）。摆在**门外一侧**而不是
## 室内门槛，是因为玩家走到房间最外沿（截图里那个位置）就已经想出去了；
## 半径 1.6 米让「刚进屋站在前厅里」也能立刻看见这个入口。

signal exit_requested


func _on_ready() -> void:
	id = "room_exit"
	label = "门口"
	verb = "离开房间"
	priority = 6
	hold_time = 0.15
	# 纯逻辑点没有视觉包围盒：半径必须手写，且不随尺寸放大。
	focus_radius = 1.6
	auto_radius = false
	focus_anchor = "node"


func interact(_actor: Node3D) -> Dictionary:
	exit_requested.emit()
	return {"event": "room_exit_requested"}
