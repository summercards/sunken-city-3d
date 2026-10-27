extends SceneTree
## 光照参数清单核对：清单 ↔ 引擎属性 ↔ 场景/资源出厂值 ↔ 面板控件，四方对账。
##
## 面板是照着 `light_params.gd` 生成的，所以清单写错一个字，结果不是报错而是
## **滑块静默无效**（`set_indexed` 打到一个不存在的属性上）。这个脚本专门盯这种
## 沉默失败：
##   1. 属性名在 `Environment` / `DirectionalLight3D` 上真的存在
##   2. kind 是认识的三种之一，key 不重复
##   3. 范围包得住出厂值（`world_env.tres` 与 `main.tscn` 里 Sun 节点的实际数值）
##      —— 包不住的话，一开面板滑块就贴在端点上，「复位」还会把场景改坏
##   4. 清单里每一项都真的在面板上生成了控件
##
## 用法：Godot --headless --path godot --script res://tools/check_light_params.gd
## 退出码：0 全对，1 有差异。

const Params = preload("res://src/rendering/light_params.gd")
const PanelScript = preload("res://src/rendering/color_grade_panel.gd")

const ENV_PATH := "res://assets/materials/world_env.tres"
const SCENE_PATH := "res://scenes/main.tscn"

const KINDS := ["float", "bool", "color"]

var checks := 0
var failures := 0
var problems: Array[String] = []


func _init() -> void:
	call_deferred("run")


func check(ok: bool, text: String) -> void:
	checks += 1
	if ok:
		return
	failures += 1
	problems.append(text)


func run() -> void:
	var spec := Params.flat()
	var env: Environment = load(ENV_PATH)
	if env == null:
		check(false, "读不到 " + ENV_PATH)
		env = Environment.new()
	var sun := _scene_sun_values()

	var seen := {}
	for g in Params.GROUPS:
		var group_id := String(g.id)
		check(group_id == Params.section_of(Params.TARGET_ENV) or group_id == Params.section_of(Params.TARGET_SUN),
			"分组 %s 不是合法的存档段名（必须是 environment / sun）" % group_id)
		check(not String(g.get("label", "")).is_empty(), "分组 %s 没有中文名" % group_id)
		for row in g.rows:
			_check_row(row, env, sun, seen)

	# 控件覆盖：清单里有、面板上没有 = 玩家永远调不到。
	var panel = PanelScript.new()
	root.add_child(panel)
	await process_frame
	var missing := PackedStringArray()
	for key in spec.keys():
		if not panel._light_widgets.has(key):
			missing.append(key)
	check(missing.is_empty(), "面板缺少控件：%s" % ", ".join(missing))
	var extra := PackedStringArray()
	for key in panel._light_widgets.keys():
		if not spec.has(key):
			extra.append(String(key))
	check(extra.is_empty(), "面板多出清单里没有的控件：%s" % ", ".join(extra))
	panel.queue_free()
	await process_frame

	if failures == 0:
		print("[lighting-params] PASS %d 个参数（环境 %d + 太阳 %d）" % [
			spec.size(), _count(Params.TARGET_ENV), _count(Params.TARGET_SUN)])
	else:
		for p in problems:
			print("[lighting-params] FAIL ", p)
	print("[lighting-params] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _count(target: String) -> int:
	var n := 0
	for g in Params.GROUPS:
		for row in g.rows:
			if String(row.target) == target:
				n += 1
	return n


func _check_row(row: Dictionary, env: Environment, sun: Dictionary, seen: Dictionary) -> void:
	var key := String(row.key)
	var label := String(row.label)
	var target := String(row.target)
	var prop := String(row.prop)
	var kind := String(row.kind)

	check(not seen.has(key), "%s 重复出现（后一行会覆盖前一行）" % key)
	seen[key] = true
	check(not label.is_empty(), "%s 没有中文名" % key)
	check(KINDS.has(kind), "%s 的 kind「%s」不认识" % [key, kind])
	check(target == Params.TARGET_ENV or target == Params.TARGET_SUN,
		"%s 的 target「%s」不认识" % [key, target])

	# ---- 1. 属性存在 --------------------------------------------------------
	# 太阳那几行要一个 DirectionalLight3D 来查属性表，用完立刻 free ——
	# 建了不还，退出时会打出 RID 泄漏，验证脚本会把那行当成真错误。
	var probe_light: DirectionalLight3D = null
	if target == Params.TARGET_SUN:
		probe_light = DirectionalLight3D.new()
	var obj: Object = env if target == Params.TARGET_ENV else probe_light
	if prop.begins_with("dir:"):
		check(prop == "dir:elevation" or prop == "dir:azimuth",
			"%s 的虚拟轴「%s」不认识" % [key, prop])
		check(kind == "float", "%s 是虚拟角度轴，kind 必须是 float" % key)
		if probe_light != null:
			probe_light.free()
		return
	if not _has_property(obj, prop):
		check(false, "%s 的属性 %s 在 %s 上不存在" % [key, prop, obj.get_class()])
		if probe_light != null:
			probe_light.free()
		return
	if probe_light != null:
		probe_light.free()

	# ---- 2. 出厂值落在范围里 -------------------------------------------------
	if kind != "float":
		return
	var lo := float(row.min)
	var hi := float(row.max)
	var value: Variant = null
	if target == Params.TARGET_ENV:
		value = env.get_indexed(NodePath(prop))
	else:
		value = sun.get(prop)
	if value == null:
		check(false, "%s 在出厂值里找不到（%s）" % [key, ENV_PATH if target == Params.TARGET_ENV else "main.tscn Sun 节点"])
		return
	var v := float(value)
	check(v >= lo and v <= hi, "%s 的出厂值 %.3f 不在 [%.2f, %.2f] 里，滑块会贴在端点" % [key, v, lo, hi])
	check(float(row.step) > 0.0, "%s 的 step 必须大于 0" % key)


func _has_property(obj: Object, prop: String) -> bool:
	var head := prop.split(":")[0]
	for p in obj.get_property_list():
		if String(p.name) == head:
			return true
	return false


## 直接从 `main.tscn` 的 Sun 节点块里读出厂值。
##
## 不实例化场景：`main.tscn` 的 `_ready` 会起整个世界（岸线图重建、灯光装配），
## 只为了读七个数就付这份代价，还会把无关的报错混进日志。文本解析更诚实 ——
## 它读的正是「重开游戏时会加载的那份文件」。
func _scene_sun_values() -> Dictionary:
	var out := {}
	var text := FileAccess.get_file_as_string(SCENE_PATH)
	if text.is_empty():
		return out
	var inside := false
	for line in text.replace("\r\n", "\n").split("\n"):
		var s := String(line)
		if s.begins_with("[node name="):
			inside = s.begins_with("[node name=\"Sun\"")
			continue
		if not inside or s.begins_with("["):
			continue
		var eq := s.find(" = ")
		if eq < 0:
			continue
		var name := s.substr(0, eq)
		var value: Variant = str_to_var(s.substr(eq + 3))
		if value == null:
			continue
		out[name] = value
	# 朝向按基反算，跟面板的 `_sun_angles()` 同一套公式。
	if out.has("transform"):
		var t: Transform3D = out["transform"]
		var d := -t.basis.z
		out["dir:elevation"] = rad_to_deg(asin(clampf(-d.y, -1.0, 1.0)))
		out["dir:azimuth"] = rad_to_deg(atan2(d.x, d.z))
	return out
