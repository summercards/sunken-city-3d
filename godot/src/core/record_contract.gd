extends RefCounted
## Data-only recursive validation; never mutates input or accesses game state.
static func check(value: Variant, rule: Dictionary, path := "snapshot") -> String:
	var kind := str(rule.get("type", "object"))
	match kind:
		"object":
			if not value is Dictionary: return path + " 必须为对象"
			for key in rule.get("required", []):
				if not value.has(key): return path + "." + key + " 缺失"
			for key in value:
				var fields: Dictionary = rule.get("fields", {})
				var child: Dictionary = fields.get(key, rule.get("values", {}))
				if not child.is_empty():
					var error := check(value[key], child, path + "." + str(key))
					if error != "": return error
		"array":
			if not value is Array: return path + " 必须为数组"
			if value.size() > int(rule.get("max", 100000)): return path + " 过长"
			if rule.has("sizes") and not value.size() in rule.sizes: return path + " 长度不合法"
			for item in value:
				var error := check(item, rule.get("items", {}), path + "[]")
				if error != "": return error
		"number", "integer":
			if not (value is int or value is float) or not is_finite(float(value)): return path + " 必须为有限数值"
			if kind == "integer" and float(value) != floor(float(value)): return path + " 必须为整数"
			if float(value) < float(rule.get("min", -1.0e12)) or float(value) > float(rule.get("max", 1.0e12)): return path + " 超出范围"
		"string":
			if not value is String: return path + " 必须为字符串"
			if value.length() > 512: return path + " 字符串过长"
		"bool":
			if not value is bool: return path + " 必须为布尔值"
	if rule.has("enum") and not value in rule.enum: return path + " 未知值"
	return ""
