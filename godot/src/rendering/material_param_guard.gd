extends RefCounted
## ShaderMaterial 参数守卫。
##
## 问题（2026-10-29，一天内复发三次）：
##   ShaderMaterial 的参数值只存在 .tres 的 `shader_parameter/*` 行里。Godot 重写这些
##   行时，依据是「当前已编译着色器的 uniform 列表」；该列表一旦为空，整批参数会被
##   **静默丢光且不报错**，连带 ext_resource 贴图行也会一起删掉。
##   `sunny_palette.gdshader` 的 palette 没有默认值，丢了之后 texture() 返回纯白，
##   整栋太阳能木屋就成了白模 —— 现象像「一移动节点就变白」，实际与位置无关。
##
## 两个入口，职责必须分清：
##   enforce()     —— 运行期。把缺的参数补回**内存**，让画面不白。绝不写盘。
##   repair_disk() —— 编辑器。磁盘缺参数就按基线**改文本**补回。绝不碰内存里的资源。
##
## 为什么编辑器里绝不能用 set_shader_parameter：
##   那会把加载中的 .tres 标成「已修改」。下次保存场景时编辑器顺带回写它，而回写
##   那一刻若 uniform 列表还没就绪，参数照样被清空 —— 守卫自己成了肇事者。
##   实测：插件每次加载都标脏 4 条参数，随后保存场景即丢参数。
##   所以编辑器只走文本修复，改完让编辑器重新导入，内存自然就是对的。

const CONTRACT := "res://assets/materials/shader_param_contract.json"


## 运行期：把缺的参数补回内存。只有磁盘真的缺参数时才 push_error。
static func enforce() -> int:
	var entries := _load_contract()
	if entries.is_empty():
		return 0
	var repaired := 0
	for rel in entries:
		var spec: Dictionary = entries[rel]
		var path := _to_res_path(rel)
		var params: Dictionary = spec.get("params", {})

		var on_disk := _params_on_disk(path)
		var lost: Array[String] = []
		for name in params:
			if not on_disk.has(String(name)):
				lost.append(String(name))

		var mat := load(path) as ShaderMaterial
		if mat == null:
			push_error("材质参数自愈：读不到 " + path)
			continue

		# 内存没值的补上。着色器未就绪时 get_shader_parameter 也会返回 null，
		# 所以这里只补、不据此报警。
		var filled := 0
		for name in params:
			if mat.get_shader_parameter(String(name)) == null:
				var value: Variant = _decode(params[name])
				if value != null:
					mat.set_shader_parameter(String(name), value)
					filled += 1
		repaired += filled

		if not lost.is_empty():
			push_error("材质参数被清空：%s 缺 %s（已按基线补回内存；磁盘请跑 scripts/repair_material_params.py）"
				% [path, str(lost)])
	return repaired


## 编辑器：按基线把磁盘上缺的参数行补回。返回修复的文件数。
## 只补 ext_resource 声明与 shader_parameter 行，其余内容原样保留。
static func repair_disk() -> int:
	var entries := _load_contract()
	if entries.is_empty():
		return 0
	var fixed := 0
	for rel in entries:
		var spec: Dictionary = entries[rel]
		if _repair_file(_to_res_path(rel), spec):
			fixed += 1
	return fixed


## 契约登记的所有材质路径，供调用方在修复后重新导入。
static func registered_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for rel in _load_contract():
		out.append(_to_res_path(rel))
	return out


static func _repair_file(path: String, spec: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("材质参数修复：读不到 " + path)
		return false
	var raw := f.get_as_text()
	f.close()

	var eol := "\r\n" if raw.contains("\r\n") else "\n"
	var lines := raw.replace("\r\n", "\n").split("\n")

	var params: Dictionary = spec.get("params", {})
	var present := {}
	var last_param_idx := -1
	var ext_id := {}
	var used_ids := {}
	var last_ext_idx := -1
	for i in lines.size():
		var t := String(lines[i]).strip_edges()
		if t.begins_with("shader_parameter/"):
			var eq := t.find("=")
			if eq > 0:
				present[t.substr(17, eq - 17).strip_edges()] = true
			last_param_idx = i
		elif t.begins_with("[ext_resource"):
			last_ext_idx = i
			var p := _attr(t, "path")
			var idv := _attr(t, "id")
			if idv != "":
				used_ids[idv] = true
			if p != "" and idv != "":
				ext_id[p] = idv

	var missing: Array = []
	for name in params:
		if not present.has(String(name)):
			missing.append(String(name))
	if missing.is_empty():
		return false

	# 资源型参数：缺 ext_resource 就补一条
	var extra_ext: Array = []
	for name in missing:
		var v: Variant = params[name]
		if not (v is Dictionary):
			continue
		var res := String((v as Dictionary).get("res", ""))
		if res.is_empty() or ext_id.has(res):
			continue
		var serial := ext_id.size()
		var idv := "res_%d" % serial
		while used_ids.has(idv):
			serial += 1
			idv = "res_%d" % serial
		used_ids[idv] = true
		ext_id[res] = idv
		extra_ext.append('[ext_resource type="Texture2D" path="%s" id="%s"]' % [res, idv])

	# 参数行
	var extra_param: Array = []
	for name in missing:
		var v2: Variant = params[name]
		if v2 is Dictionary:
			var res2 := String((v2 as Dictionary).get("res", ""))
			if res2.is_empty() or not ext_id.has(res2):
				continue
			extra_param.append('shader_parameter/%s = ExtResource("%s")' % [name, ext_id[res2]])
		elif v2 is String:
			extra_param.append('shader_parameter/%s = %s' % [name, v2])
		else:
			extra_param.append('shader_parameter/%s = %s' % [name, var_to_str(v2)])

	if not extra_param.is_empty():
		var at := last_param_idx
		if at < 0:
			for i in lines.size():
				if String(lines[i]).strip_edges().begins_with("shader ="):
					at = i
					break
		if at < 0:
			push_error("材质参数修复：%s 找不到插入点" % path)
			return false
		lines.insert(at + 1, "\n".join(extra_param))

	if not extra_ext.is_empty():
		var at2 := last_ext_idx
		if at2 < 0:
			for i in lines.size():
				if String(lines[i]).strip_edges().begins_with("[resource]"):
					at2 = i - 1
					break
		lines.insert(maxi(at2, 0) + 1, "\n".join(extra_ext))

	var out := eol.join(PackedStringArray(lines))
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		push_error("材质参数修复：写不入 " + path)
		return false
	w.store_string(out)
	w.close()
	return true


static func _attr(line: String, key: String) -> String:
	var tag := key + '="'
	var i := line.find(tag)
	if i < 0:
		return ""
	var start := i + tag.length()
	var end := line.find('"', start)
	if end < 0:
		return ""
	return line.substr(start, end - start)


static func _load_contract() -> Dictionary:
	if not FileAccess.file_exists(CONTRACT):
		push_error("材质参数基线缺失：" + CONTRACT)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	if not (parsed is Dictionary):
		push_error("材质参数基线解析失败：" + CONTRACT)
		return {}
	return (parsed as Dictionary).get("materials", {})


## 契约里的键是仓库相对路径（godot/assets/...），转成 res://
static func _to_res_path(rel: Variant) -> String:
	return "res://" + String(rel).trim_prefix("godot/")


static func _params_on_disk(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("shader_parameter/"):
			var eq := trimmed.find("=")
			if eq > 0:
				out[trimmed.substr(17, eq - 17).strip_edges()] = true
	return out


## 基线里的值：字符串走 str_to_var；{"res": "..."} 是资源引用。
static func _decode(raw: Variant) -> Variant:
	if raw is Dictionary:
		var res := String((raw as Dictionary).get("res", ""))
		if res.is_empty():
			return null
		return load(res)
	if raw is String:
		return str_to_var(raw)
	return raw
