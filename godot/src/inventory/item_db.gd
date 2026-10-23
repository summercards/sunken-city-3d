extends RefCounted
class_name ItemDB
## 物品定义表。唯一来源是 assets/data/items.json。
##
## 为什么单独一层：
##   旧实现里「资源」是 economy.gd 里的 9 个 int 变量，新增一种就要改 4 处
##   （变量、add_resource 分支、HUD 拼接、费用文案）。现在物品是数据，
##   名称/图标/堆叠/售价/描述都在表里，代码只认 id。

const TABLE := "res://assets/data/items.json"

static var _items: Dictionary = {}
static var _order: Array = []
static var _capacity: int = 24
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(TABLE, FileAccess.READ)
	if f == null:
		push_error("找不到物品表：%s" % TABLE)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("物品表格式不对：%s" % TABLE)
		return
	_capacity = int(data.get("capacity", 24))
	for row in data.get("items", []):
		if not (row is Dictionary):
			continue
		var id := str(row.get("id", ""))
		if id == "":
			continue
		_items[id] = row
		_order.append(id)


static func capacity() -> int:
	ensure_loaded()
	return _capacity


static func has(id: String) -> bool:
	ensure_loaded()
	return _items.has(id)


static func get_item(id: String) -> Dictionary:
	ensure_loaded()
	return _items.get(id, {})


static func all_ids() -> Array:
	ensure_loaded()
	return _order.duplicate()


static func ids_in(category: String) -> Array:
	ensure_loaded()
	var out: Array = []
	for id in _order:
		if str(_items[id].get("category", "")) == category:
			out.append(id)
	return out


## 显示名；未知 id 直接回显 id，避免 UI 出现空白。
static func label(id: String) -> String:
	var it := get_item(id)
	return str(it.get("label", id))


static func icon(id: String) -> String:
	var it := get_item(id)
	return str(it.get("icon", "•"))


static func color(id: String) -> Color:
	var it := get_item(id)
	var hex := str(it.get("color", "#ffffff"))
	return Color(hex) if Color.html_is_valid(hex) else Color.WHITE


static func stack_limit(id: String) -> int:
	var it := get_item(id)
	return int(it.get("stack", 1))


static func sell_price(id: String) -> int:
	var it := get_item(id)
	return int(it.get("sell", 0))


static func is_currency(id: String) -> bool:
	return str(get_item(id).get("category", "")) == "currency"
