@tool
extends "res://src/interaction/interactable.gd"

func can_interact() -> bool:
	return not Engine.is_editor_hint() and get_parent().repair_state == &"damaged"

func interact(_actor: Node3D) -> Dictionary:
	get_parent().play_repair()
	return {}
