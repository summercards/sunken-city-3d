@tool
extends "res://src/interaction/interactable.gd"
## SEA-ROOM 房间入口：太阳房门口地毯上的那个点。
##
## 2026-11-05 起它**不再直接睡觉**：睡觉搬到房间里的床上了。
## 这一处只发「进房间」，过场与切场景由 `room_controller` 接管。

signal enter_requested


func _on_ready() -> void:
	id = "room_door"
	label = "太阳房 · 房间"
	verb = "进入房间"
	priority = 5
	hold_time = 0.15
	focus_radius = 2.4
	# 不再立一块「房间」的牌子：这个点是摆在门口地毯上的，立起来的 3D 文字会直接
	# 压在遮阳伞和桌椅上（实测截图里那三个白字就糊在伞面上）。文案由操作气泡给
	# （「进入房间」），和景区其它可交互物一致。


func interact(_actor: Node3D) -> Dictionary:
	enter_requested.emit()
	return {"event": "room_enter_requested"}
