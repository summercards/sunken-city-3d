@tool
extends ItemList

var assembly: EditorPlugin

func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0: return null
	var row: Dictionary = get_item_metadata(index)
	var label := Label.new()
	label.text = str(row.label) + " · 候选"
	set_drag_preview(label)
	assembly.arm_drop(row)
	return {"type": "sea_scene_candidate", "entry": row.duplicate(true)}
