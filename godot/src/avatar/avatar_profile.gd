extends RefCounted
## The sole writer of committed identity; editors own separate disposable drafts.
signal changed
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
var _profile: Dictionary = fresh()

static func fresh(completed := false) -> Dictionary:
	return {"version":1,"name":"旅人","completed":completed,"appearance":Catalog.defaults(),"design_refs":{},"extensions":{}}

static func name_error(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned.length() < 1 or cleaned.length() > 12: return "名字需要 1–12 个字。"
	for i in cleaned.length():
		var c := cleaned.unicode_at(i)
		if c < 32 or c in [127, 0x200b, 0x2028, 0x2029] or cleaned[i] in ["<",">","[","]","/","\\"]:
			return "请使用文字、数字或普通标点。"
	return ""

static func validate_snapshot(value: Variant) -> String:
	if not value is Dictionary: return "角色档案必须为对象"
	for key in ["version","name","completed","appearance","design_refs","extensions"]:
		if not value.has(key): return "角色档案缺少 " + key
	if not (value.version is int or value.version is float) or value.version != 1: return "角色档案版本不支持"
	if not value.name is String or not value.completed is bool: return "角色姓名或完成状态格式错误"
	var error := name_error(value.name)
	if error != "": return error
	if value.name != value.name.strip_edges(): return "角色名字首尾不能有空格"
	if not value.appearance is Dictionary or not value.design_refs is Dictionary or not value.extensions is Dictionary: return "外观或 DIY 数据格式错误"
	for id in Catalog.defaults():
		if not value.appearance.has(id): return "外观缺少 " + id
	for id in value.appearance:
		if not (id is String or id is StringName) or not value.appearance[id] is String or value.appearance[id].length() > 80: return "外观 ID 格式错误"
	for id in value.design_refs:
		if not id in Catalog.defaults() or not value.design_refs[id] is String or value.design_refs[id].length() > 128: return "DIY 引用格式错误"
		if not value.design_refs[id].begins_with("design:") or value.design_refs[id].contains("..") or value.design_refs[id].contains("\\"): return "DIY 必须引用设计 ID"
	if JSON.stringify(value).to_utf8_buffer().size() > 16384: return "角色档案超过 16 KiB"
	return ""

func query() -> Dictionary: return _profile.duplicate(true)
func to_dict() -> Dictionary: return query()
func from_dict(value: Dictionary) -> void:
	_profile = value.duplicate(true)
	changed.emit()

func commit(draft: Dictionary) -> Dictionary:
	var value := draft.duplicate(true)
	if value.get("name") is String: value.name = value.name.strip_edges()
	value.completed = true
	var error := validate_snapshot(value)
	if error != "": return {"ok":false,"reason":error}
	from_dict(value)
	return {"ok":true,"reason":""}
