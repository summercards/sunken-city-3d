extends RefCounted
## Stable content IDs. New options only require catalogue data + a visual resolver.
const PATH := "res://assets/data/avatar_catalog.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data.duplicate(true)

static func defaults() -> Dictionary:
	var result := {}
	for slot in data().slots: result[slot.id] = slot.default
	return result

static func options(id: String) -> Array:
	for slot in data().slots:
		if slot.id == id: return slot.options
	return []

static func resolve(id: String, value: String) -> Dictionary:
	for option in options(id):
		if option.id == value: return option
	for option in options(id):
		if option.id == defaults().get(id): return option
	return {}

static func color(slots: Dictionary, id: String) -> Color:
	return Color(str(resolve(id,str(slots.get(id,""))).get("color","#ffffff")))

static func effective(slots: Dictionary) -> Dictionary:
	var result := defaults()
	for id in result: result[id] = resolve(id,str(slots.get(id,result[id]))).id
	return result
