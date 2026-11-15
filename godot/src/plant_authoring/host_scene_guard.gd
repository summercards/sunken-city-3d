@tool
extends RefCounted
## 仅用文件文本检查加载闭包；不构造 Variant 对象或实例化资源。
## 项目公共 PNG/着色器及其导入缓存可信；不防御审计与加载之间的并发磁盘替换。

const SAFE_NODES := ["Node", "Node3D", "MeshInstance3D", "StaticBody3D", "CollisionShape3D", "Marker3D"]
const SAFE_RESOURCES := ["Resource", "StandardMaterial3D", "ShaderMaterial", "ArrayMesh", "BoxMesh", "SphereMesh", "CylinderMesh", "CapsuleMesh", "ConcavePolygonShape3D", "ConvexPolygonShape3D", "BoxShape3D", "SphereShape3D", "CylinderShape3D", "CapsuleShape3D"]
const SAFE_MATERIAL_TYPES := ["StandardMaterial3D", "ShaderMaterial"]
const DATA_TYPES := ["Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i", "Transform2D", "Transform3D", "Basis", "Quaternion", "Plane", "AABB", "Color", "NodePath", "PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array", "PackedVector4Array", "PackedColorArray"]
const PNG := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const SHADERS := ["res://shaders/sunny_palette.gdshader", "res://shaders/sunny_palette_gloss.gdshader"]
const MAX_BYTES := 64 * 1024 * 1024

static func audit_path(path: String) -> String:
	if path.get_file() != "building.tscn": return "宿主入口必须是 building.tscn"
	return _file(path, "PackedScene", {}, 0)

static func _path_reason(path: String) -> String:
	if not path.begins_with("res://") or path.contains("..") or path.contains("\\") or path.simplify_path() != path:
		return "宿主路径必须为规范 res:// 且不含 ..：" + path
	var relative := path.trim_prefix("res://")
	if relative.is_empty() or relative.contains(":"):
		return "宿主路径非法：" + path
	var parent := ProjectSettings.globalize_path("res://").trim_suffix("/")
	for part in relative.split("/", true):
		if part.is_empty() or part.strip_edges() != part: return "宿主路径分段非法：" + path
		var directory := DirAccess.open(parent)
		if directory == null: return "宿主目录不可读：" + parent
		if directory.is_link(part): return "宿主路径禁止符号链接：" + path
		parent = parent.path_join(part)
	return ""

static func _file(path: String, expected: String, active: Dictionary, depth: int) -> String:
	var reason := _path_reason(path)
	if not reason.is_empty(): return reason
	if active.has(path) or depth > 32: return "宿主依赖循环或层数超限：" + path
	if FileAccess.file_exists(path + ".remap"): return "宿主禁止资源重定向：" + path
	if path == PNG and expected == "Texture2D":
		return "" if FileAccess.file_exists(path) else "公共 PNG 不存在"
	var shader := SHADERS.has(path) and expected == "Shader"
	if not shader and not (path.get_extension() == "tscn" and expected == "PackedScene") and not (path.get_extension() == "tres" and (expected == "Material" or SAFE_RESOURCES.has(expected))):
		return "宿主外链类型或路径不在白名单：" + expected + " / " + path
	if FileAccess.file_exists(path + ".import"): return "宿主文本资源禁止导入重定向：" + path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return "宿主依赖不可读：" + path
	if file.get_length() > MAX_BYTES: return "宿主文本资源过大：" + path
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.has(0): return "宿主禁止二进制资源：" + path
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes: return "宿主必须是完整 UTF-8 文本：" + path
	active[path] = true
	reason = _shader(text, active, depth) if shader else _document(text, path, expected, active, depth)
	active.erase(path)
	return reason

static func _shader(text: String, active: Dictionary, depth: int) -> String:
	# 只接受已知项目 shader 的字面 include；宏、相对路径和网络路径均不放行。
	var directive := RegEx.create_from_string("#\\s*include([^\\n]*)")
	var literal := RegEx.create_from_string('^\\s*"([^"\\\\]+)"\\s*$')
	for item in directive.search_all(text):
		var found := literal.search(item.get_string(1))
		if found == null: return "shader include 必须是白名单字面路径"
		var path := found.get_string(1)
		if not SHADERS.has(path): return "shader include 不在白名单：" + path
		var reason := _file(path, "Shader", active, depth + 1)
		if not reason.is_empty(): return reason
	return ""

static func _document(text: String, path: String, expected: String, active: Dictionary, depth: int) -> String:
	# 词法扫描覆盖全部输入；字符串不可伪装成字段，未知构造器在加载前拒绝。
	var lexer := RegEx.create_from_string('\\s+|;[^\\n]*|"(?:[^"\\\\]|\\\\[^\\r\\n])*"|[A-Za-z_][A-Za-z0-9_/]*|[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?|[][{}(),=:&^]')
	var tokens: Array[String] = []
	var offset := 0
	for item in lexer.search_all(text):
		if item.get_start() != offset: return "宿主文本含未知语法：" + path
		offset = item.get_end()
		var token := item.get_string()
		if token.strip_edges().is_empty() or token.begins_with(";"): continue
		tokens.append(token)
	if offset != text.length(): return "宿主文本未完整解析：" + path
	var attribute_regex := RegEx.create_from_string('^([A-Za-z_]+)=(?:"([^"\\\\]*)"|([0-9]+))$')
	var ctx := {"tokens": tokens, "pos": 0, "ext": {}, "sub": {}, "edges": {}, "owner": "", "error": ""}
	var header := true
	var section := ""
	var nodes := 0
	var resource_seen := false
	while ctx.pos < tokens.size():
		if tokens[ctx.pos] == "[":
			ctx.pos += 1
			var kind := _take(ctx)
			var attrs: Dictionary = {}
			while _peek(ctx) != "]" and ctx.pos < tokens.size():
				var key := _take(ctx)
				if attrs.has(key) or _take(ctx) != "=": return "宿主段落重复或非法属性"
				var value := _take(ctx)
				var attribute := attribute_regex.search(key + "=" + value)
				if attribute == null: return "宿主段落仅接受无转义字面属性"
				attrs[attribute.get_string(1)] = attribute.get_string(2) if value.begins_with('"') else attribute.get_string(3)
			if _take(ctx) != "]": return "宿主段落未闭合"
			if header:
				if kind != ("gd_scene" if expected == "PackedScene" else "gd_resource"): return "宿主文本头与外链类型不匹配"
				if expected != "PackedScene":
					var declared_type := str(attrs.get("type", ""))
					if expected == "Material":
						if not SAFE_MATERIAL_TYPES.has(declared_type): return "宿主资源类型未知或不匹配"
					elif not SAFE_RESOURCES.has(declared_type) or declared_type != expected:
						return "宿主资源类型未知或不匹配"
				if not _keys(attrs, ["type", "load_steps", "format", "uid"]) or not str(attrs.get("format", "")).is_valid_int(): return "宿主文本头异常"
				header = false
			elif kind == "ext_resource":
				if nodes > 0 or resource_seen or not _keys(attrs, ["type", "path", "id", "uid"]): return "宿主外链声明位置或字段异常"
				var id := str(attrs.get("id", ""))
				var dep := str(attrs.get("path", ""))
				var type := str(attrs.get("type", ""))
				if id.is_empty() or ctx.ext.has(id): return "宿主外链 ID 缺失或重复"
				if type == "PackedScene" or dep.ends_with(".tscn"): return "宿主保守拒绝嵌套及继承场景"
				if attrs.has("uid"):
					var uid := ResourceUID.text_to_id(str(attrs.uid))
					if ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) != dep: return "宿主外链 UID 与文本路径不一致"
				var reason := _file(dep, type, active, depth + 1)
				if not reason.is_empty(): return reason
				ctx.ext[id] = true
			elif kind == "sub_resource":
				if nodes > 0 or resource_seen or not _keys(attrs, ["type", "id"]): return "宿主子资源声明异常"
				var id := str(attrs.get("id", ""))
				if id.is_empty() or ctx.sub.has(id) or not SAFE_RESOURCES.has(attrs.get("type")): return "宿主子资源类型或 ID 异常"
				ctx.sub[id] = true
				ctx.owner = id
				ctx.edges[id] = []
			elif kind == "node":
				if expected != "PackedScene" or not _keys(attrs, ["name", "type", "parent", "owner", "unique_id", "index"]): return "宿主拒绝嵌套/继承或未知节点属性"
				if not SAFE_NODES.has(attrs.get("type")): return "宿主节点类型未知"
				var name := str(attrs.get("name", ""))
				if name.is_empty() or name.contains("/") or name.contains(".") or name.contains(":"): return "宿主节点名异常"
				if nodes == 0 and (attrs.has("parent") or attrs.get("type") != "Node3D"): return "宿主根必须是独立 Node3D"
				if nodes > 0 and (not attrs.has("parent") or str(attrs.parent).contains("..")): return "宿主 parent 异常"
				nodes += 1
				ctx.owner = ""
			elif kind == "resource":
				if expected == "PackedScene" or resource_seen or not attrs.is_empty(): return "宿主 resource 段异常"
				resource_seen = true
				ctx.owner = ""
			else:
				return "宿主段落不在白名单：" + kind
			section = kind
		else:
			if section not in ["node", "resource", "sub_resource"]: return "宿主属性出现在非法段落"
			var key := _take(ctx)
			if key.contains("\\") or key.trim_prefix('"').trim_suffix('"') in ["script", "top_level"]: return "宿主禁止 script/top_level 属性"
			if _take(ctx) != "=": return "宿主属性语法异常"
			_value(ctx, 0)
			if not str(ctx.error).is_empty(): return ctx.error
	if header or (expected == "PackedScene" and nodes == 0) or (expected != "PackedScene" and not resource_seen): return "宿主文本缺少根段落"
	for id in ctx.edges:
		if _cycle(id, ctx.edges, {}, 0): return "宿主子资源循环或深度异常"
	return ""

static func _keys(attrs: Dictionary, allowed: Array) -> bool:
	for key in attrs:
		if not allowed.has(key): return false
	return true

static func _peek(ctx: Dictionary) -> String:
	return ctx.tokens[ctx.pos] if ctx.pos < ctx.tokens.size() else ""

static func _take(ctx: Dictionary) -> String:
	var token := _peek(ctx)
	ctx.pos += 1
	return token

static func _value(ctx: Dictionary, depth: int) -> void:
	if depth > 64:
		ctx.error = "宿主属性嵌套过深"
		return
	var token := _take(ctx)
	if token in ["&", "^"]:
		if not _take(ctx).begins_with('"'): ctx.error = "宿主字符串值异常"
		return
	if token.begins_with('"') or token.is_valid_float() or token in ["true", "false", "null", "inf", "nan"]: return
	if token in ["ExtResource", "SubResource"]:
		if _take(ctx) != "(": ctx.error = "宿主引用异常"
		var quoted := _take(ctx)
		var id := quoted.trim_prefix('"').trim_suffix('"')
		var table: Dictionary = ctx.ext if token == "ExtResource" else ctx.sub
		if not quoted.begins_with('"') or quoted.contains("\\") or not table.has(id) or _take(ctx) != ")": ctx.error = "宿主引用未声明或异常"
		if token == "SubResource" and not str(ctx.owner).is_empty(): ctx.edges[ctx.owner].append(id)
		return
	var end := ""
	var dictionary := false
	if token == "[": end = "]"
	elif token == "{":
		end = "}"
		dictionary = true
	elif token == "Array":
		if _take(ctx) != "[" or not (DATA_TYPES + ["float", "int", "String", "bool"]).has(_take(ctx)) or _take(ctx) != "]" or _take(ctx) != "(":
			ctx.error = "宿主类型化数组不在数据白名单"
			return
		end = ")"
	elif DATA_TYPES.has(token):
		if _take(ctx) != "(": ctx.error = "宿主数据构造器异常"
		end = ")"
	else:
		ctx.error = "宿主未知或可执行构造器：" + token
		return
	while _peek(ctx) != end and str(ctx.error).is_empty():
		_value(ctx, depth + 1)
		if dictionary and str(ctx.error).is_empty():
			if _take(ctx) != ":":
				ctx.error = "宿主字典键异常"
				return
			_value(ctx, depth + 1)
		if _peek(ctx) == end: break
		if _take(ctx) != ",": ctx.error = "宿主数据分隔符异常"
	if _take(ctx) != end: ctx.error = "宿主数据未闭合"

static func _cycle(id: String, edges: Dictionary, active: Dictionary, depth: int) -> bool:
	if active.has(id) or depth > 64: return true
	active[id] = true
	for child in edges[id]:
		if _cycle(child, edges, active, depth + 1): return true
	active.erase(id)
	return false
