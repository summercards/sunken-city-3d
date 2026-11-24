@tool
extends "res://src/interaction/interactable.gd"

@export var repair_area: StringName

func can_interact() -> bool:
	return not Engine.is_editor_hint() and get_parent().get_parent().can_repair(repair_area)

func interact(_actor: Node3D) -> Dictionary:
	get_parent().get_parent().play_repair(repair_area)
	return {}
