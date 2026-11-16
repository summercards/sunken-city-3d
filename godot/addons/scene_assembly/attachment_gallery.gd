@tool
extends ItemList

const Recipe = preload("res://src/building_attachments/recipe.gd")
var panel: VBoxContainer

func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0: return null
	var type_id := str(get_item_metadata(index))
	var prepared: Dictionary = panel.prepare_drag(type_id)
	if not prepared.ok: return null
	var recipe: Dictionary = prepared.recipe
	var preview := Label.new()
	preview.text = get_item_text(index)
	set_drag_preview(preview)
	return {"type": "sea_building_attachment", "recipe": recipe.duplicate(true), "arm_token": prepared.token}
