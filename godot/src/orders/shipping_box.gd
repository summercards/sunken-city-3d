@tool
extends "res://src/interaction/interactable.gd"
## Interaction adapter for the existing cooler visual. No inventory duplication.
signal opened

func _on_ready() -> void:
	interaction_context = "shore"
	trigger_padding = 0.35
	id = "home_shipping_box"
	label = "出货箱"
	verb = "放入 / 取回"
	priority = 3
	focus_radius = 2.4
	hold_time = 0.12
	add_to_group("shipping_boxes")

func interact(_actor: Node3D) -> Dictionary:
	opened.emit()
	return {"event":"shipping_opened"}

func focus_text() -> String:
	return "出货箱 · 每天07:00收货，换成瓶盖"
