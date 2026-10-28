extends RefCounted
## Original image assets shared by world actions and pockets. No item state here.
const ROOT := "res://assets/ui/handdrawn/"
const ACTIONS := ["plant","water","harvest","dig","hand","bag","shipping","sleep","shop","fish","anchor","back"]
const ITEMS := ["wood","parts","rope","glass","seed","shell","fish","vegetable","tomato","pumpkin","pearl","lettuce_seed","tomato_seed","pumpkin_seed","water","coins"]
static var textures := {}

static func texture(kind: String, actions := false) -> Texture2D:
	var key := ("action_" if actions else "item_") + kind
	if textures.has(key): return textures[key]
	var path := ROOT + key + ".png"
	if not ResourceLoader.exists(path): return null
	textures[key] = load(path)
	return textures[key]
