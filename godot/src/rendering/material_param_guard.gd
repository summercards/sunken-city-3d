extends RefCounted
## ShaderMaterial 参数自愈。
##
## 为什么需要它（2026-10-29，一天内复发两次）：
##   ShaderMaterial 的参数值只存在 .tres 的 `shader_parameter/*` 行里。Godot 重写
##   这些行时，依据的是「当前已编译着色器的 uniform 列表」；该列表一旦为空（着色器
##   正在重编译、或材质早于着色器就绪被保存），整批参数会被**静默丢光，不报错**。
##   `sunny_palette.gdshader` 的 `palette` 没有默认值，丢了之后 `texture()` 返回纯白，
##   整栋太阳能木屋就成了白模。water.tres 的 90 条参数也在同一次保存里一起没了。
##
## 这里在启动时按 `shader_param_contract.json` 把缺的参数补回内存中的材质，
## 保证「磁盘被写坏」也不会直接把画面变成白色；同时 push_error 指名道姓，
## 不让它静默通过。磁盘层面的修复交给 `scripts/repair_material_params.py`。
##
## 判别口径（很重要）：
##   `get_shader_parameter()` 对「着色器有默认值但材质没显式设过」的 uniform 也返回
##   null，例如 sunny_palette 的 home_window 系列。所以**不能凭内存为 null 就报事故**，
##   必须回到 .tres 文本里看那一行在不在：
##     · 文本缺 → 磁盘被清空，是真事故，push_error；
##     · 文本在但内存 null → 着色器还没就绪，静默补上即可（不报警，否则验证套件会误判）。

const CONTRACT := "res://assets/materials/shader_param_contract.json"

## 返回被补过的材质数量。只有磁盘真的缺参数时才 push_error。
static func enforce() -> int:
	if not FileAccess.file_exists(CONTRACT):
		push_error("材质参数基线缺失：" + CONTRACT)
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	if not (parsed is Dictionary):
		push_error("材质参数基线解析失败：" + CONTRACT)
		return 0
	var entries: Dictionary = parsed.get("materials", {})

	var repaired := 0
	for rel in entries:
		var spec: Dictionary = entries[rel]
		var path := "res://" + String(rel).trim_prefix("godot/")
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

		# 磁盘上在、但内存里还没值的，静默补（着色器未就绪时的常态）。
		var filled := 0
		for name in params:
			if mat.get_shader_parameter(String(name)) == null:
				var value: Variant = _decode(params[name])
				if value != null:
					mat.set_shader_parameter(String(name), value)
					filled += 1
		repaired += filled

		if not lost.is_empty():
			push_error("材质参数被清空：%s 缺 %s（已按基线补回；磁盘请跑 scripts/repair_material_params.py）"
				% [path, str(lost)])
	return repaired


## 读 .tres 文本，返回其中已经写了的参数名集合。
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


## 基线里的值：字符串走 `str_to_var`；`{"res": "..."}` 是资源引用。
static func _decode(raw: Variant) -> Variant:
	if raw is Dictionary:
		var res := String(raw.get("res", ""))
		if res.is_empty():
			return null
		return load(res)
	if raw is String:
		return str_to_var(raw)
	return raw
