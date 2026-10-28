@tool
extends Node3D
## Visual-owned identity and intent port. Gameplay owns permission, placement and saves.
signal interaction_requested(instance_id: String, action: String)
@export var instance_id := ""
@export var facility_id := ""
@export var asset_id := ""
@export_enum("building", "upgrade_attachment", "furnishing", "decoration") var component_kind := "building"
@export var subcategory := ""
@export var movable := false
@export var attachment_slot := ""
## Authored default is visible; designers may assign an unlock tier without changing rules.
@export_range(0, 10) var unlock_level := 0

func set_upgrade_level(level: int) -> void:
	if component_kind == "upgrade_attachment": visible = level >= unlock_level

func describe() -> Dictionary:
	return {"instance_id":instance_id,"facility_id":facility_id,"asset_id":asset_id,
		"attachment_slot":attachment_slot,"category":component_kind,"subcategory":subcategory,"movable":movable,
		"actions":PackedStringArray(["inspect", "relocate"]) if movable else PackedStringArray(["inspect"])}

func request_interaction(action: String) -> bool:
	if not action in describe().actions: return false
	interaction_requested.emit(instance_id, action)
	return true
