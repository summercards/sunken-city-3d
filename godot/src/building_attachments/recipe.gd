extends RefCounted
## v1 为严格、无隐式修剪或迁移的独立外挂配方。

const Catalog = preload("res://src/building_attachments/catalog.gd")
const SUPPORTED := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .-!&"
const KEYS := ["schema_version", "attachment_id", "type_id", "condition", "style", "dimensions", "scale", "text", "colors", "usage", "collision_enabled"]

static func defaults(type_id: String) -> Dictionary:
	var entry: Dictionary = Catalog.get_entry(type_id)
	if entry.is_empty():
		return {}
	return {
		"schema_version": 1, "attachment_id": type_id, "type_id": type_id,
		"condition": "fresh", "style": "frame", "dimensions": entry.dimensions.duplicate(true),
		"scale": 1.0, "text": entry.text,
		"colors": {"SEA_Matte": 0, "SEA_Metal": 59, "SEA_Gloss": 16, "SEA_Emission": 9},
		"usage": "above_water", "collision_enabled": entry.collision_default
	}

static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func validate(data: Dictionary) -> String:
	for key: Variant in data:
		if not KEYS.has(key):
			return "不支持的配方字段：%s；状态统一使用condition" % str(key)
	for key: String in KEYS:
		if not data.has(key):
			return "配方缺少字段：" + key
	if not number(data.schema_version) or float(data.schema_version) != 1.0:
		return "只支持schema_version=1"
	if not data.attachment_id is String or not valid_id(data.attachment_id):
		return "attachment_id须为1..64位小写ASCII字母、数字、下划线或连字符"
	if not data.type_id is String:
		return "type_id须为字符串"
	var entry: Dictionary = Catalog.get_entry(data.type_id)
	if entry.is_empty():
		return "未知type_id：" + str(data.type_id)
	if not data.condition is String or not Catalog.CONDITIONS.has(data.condition):
		return "condition只允许fresh/damaged/ruined，不是SF风格档位"
	if not data.style is String or not Catalog.STYLES.has(data.style):
		return "style只允许frame/block/marquee"
	if not data.usage is String or not ["above_water", "decorative_underwater"].has(data.usage):
		return "usage只允许above_water/decorative_underwater"
	if not data.collision_enabled is bool:
		return "collision_enabled须为bool"
	if data.usage == "decorative_underwater" and data.collision_enabled:
		return "水下纯观赏外挂拒绝collision_enabled=true；请显式关闭，不会默改"
	if not number(data.scale) or float(data.scale) < 0.75 or float(data.scale) > 1.25:
		return "scale须为0.75..1.25有限数值"
	if not data.dimensions is Dictionary or data.dimensions.size() != 3:
		return "dimensions须仅含width/height/depth"
	for axis: String in ["width", "height", "depth"]:
		var value: Variant = data.dimensions.get(axis)
		if not number(value):
			return "尺寸须为有限数值：" + axis
		var baseline: float = float(entry.dimensions[axis])
		if float(value) < baseline * 0.75 or float(value) > baseline * 1.25:
			return "%s须在目录默认值的0.75..1.25倍内" % axis
	if not data.colors is Dictionary or data.colors.size() != 4:
		return "colors须包含四个SEA材质角色的色格索引"
	for role: String in Catalog.ROLES:
		var cell: Variant = data.colors.get(role)
		if not number(cell) or float(cell) != floor(float(cell)) or int(cell) < 0 or int(cell) > 63:
			return "颜色须为0..63整数色格：" + role
	if not data.text is String:
		return "text须为字符串；不会转换或丢弃原输入"
	if data.text.length() > 24:
		return "text最多24个ASCII字符；原输入未截断"
	for character: String in data.text:
		if not SUPPORTED.contains(character):
			return "不支持的文字字符：%s；仅支持A-Z、0-9、空格、.-!&，原输入未修改" % character
	if entry.category == "signage" and data.text.strip_edges().is_empty():
		return "招牌文字不能为空或全空格；原输入未修改"
	if entry.category != "signage" and not data.text.is_empty():
		return "此类型没有文字接口；原输入未修改"
	return ""
