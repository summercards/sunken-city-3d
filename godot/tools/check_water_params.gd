extends SceneTree
## 水面参数清单核对：`water_params.gd` ↔ `water.gdshader`（含 4 个 include）。
##
## 面板是照着清单生成的，所以清单少一项＝玩家永远调不到那个参数。
## 这个脚本从着色器反读每个 uniform 的类型和 hint_range，对着清单查三件事：
##   1. 着色器有、清单没有，且不在豁免名单里 —— 漏了
##   2. 清单有、着色器没有 —— 名字拼错或改过忘了同步
##   3. 类型 / 范围 / 步长对不上 —— 面板会给滑块一个错的区间
##
## 用法：Godot --headless --path godot --script res://tools/check_water_params.gd
## 退出码：0 全对，1 有差异。

const ParamsLib = preload("res://src/rendering/water_params.gd")
const SHADER_PATH := "res://shaders/water.gdshader"
const WATER_MAT_PATH := "res://assets/materials/water.tres"

## 不进面板的参数：要么每帧被别的系统写，要么是采样器/数组。
## 值写清理由 —— 想往里塞新名字之前，先确认它真的不该给玩家调。
const EXEMPT := {
	"water_level": "main.gd 按 WATER_LEVEL 写，还牵着节点 Y 与船吃水",
	"u_reverse_z": "render_flags.gd 按渲染后端换算",
	"emission_gain": "render_flags.gd 的兼容后端补偿",
	"u_time": "water_surface.gd 的模拟时钟",
	"u_boat": "船的位置/朝向/速度",
	"u_ripples": "8 圈桨纹，数组",
	"u_ripple_count": "桨纹环形缓冲的计数",
	"ocean_waves": "4 条波的方向/振幅/波长，数组",
	"wake_points": "尾迹折线，数组",
	"wake_strengths": "尾迹强度，数组",
	"wake_count": "尾迹点计数",
	"shore_distance": "岸线距离图，采样器",
	"shore_bounds": "岸线图的包围盒，rebuild_shoreline 写",
	"shore_texel": "岸线图纹素尺寸，rebuild_shoreline 写",
	"shore_enabled": "有没有岸线图，rebuild_shoreline 写",
	"large_wave_normals": "法线条带贴图，采样器",
	"ripple_pattern": "波纹等高线贴图，采样器",
	"contact_foam_pattern": "吃水线泡沫贴图，采样器",
	"screen_tex": "屏幕纹理",
	"depth_tex": "深度纹理",
}

## Variant.Type 里属于「数组」的那一段（PACKED_*_ARRAY）。
const TYPE_PACKED_MIN := 29
const TYPE_PACKED_MAX := 38


func _init() -> void:
	var problems := PackedStringArray()
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		print("[water-params] FAIL 读不到 ", SHADER_PATH)
		quit(1)
		return

	var uniforms := {}
	for u in shader.get_shader_uniform_list():
		uniforms[String(u.name)] = u

	var spec := ParamsLib.flat()

	# ---- 1. 着色器 → 清单 ---------------------------------------------------
	for name in uniforms.keys():
		if spec.has(name) or EXEMPT.has(name):
			continue
		var u: Dictionary = uniforms[name]
		if int(u.type) == TYPE_OBJECT or (int(u.type) >= TYPE_PACKED_MIN and int(u.type) <= TYPE_PACKED_MAX):
			continue  # 采样器与数组本来就不该做滑块
		problems.append("漏了 %s（着色器里有，清单里没有；类型 %d）" % [name, int(u.type)])

	# ---- 2. 清单 → 着色器 ---------------------------------------------------
	for name in spec.keys():
		if not uniforms.has(name):
			problems.append("清单里的 %s 在着色器里找不到" % name)
			continue
		var u: Dictionary = uniforms[name]
		var row: Dictionary = spec[name]
		var kind := String(row.kind)

		var expect := _kind_of(u)
		if kind == "node":
			# 节点属性，材质里只有一个同名 float 兜底（每帧被 _sync 覆盖）。
			if expect != "float":
				problems.append("%s 标成 node，但着色器里是 %s" % [name, expect])
			continue
		if kind != expect:
			problems.append("%s 清单标 %s，着色器是 %s" % [name, kind, expect])
			continue

		# ---- 3. 范围 / 步长 -------------------------------------------------
		if expect != "float":
			continue
		var hint := int(u.hint)
		if hint != PROPERTY_HINT_RANGE:
			problems.append("%s 没有 hint_range，面板的区间是清单自己编的" % name)
			continue
		var parts := String(u.hint_string).split(",")
		if parts.size() < 2:
			continue
		var lo := float(parts[0])
		var hi := float(parts[1])
		var step := float(parts[2]) if parts.size() > 2 else 0.0
		_check_range(problems, name, "min", lo, float(row.min))
		_check_range(problems, name, "max", hi, float(row.max))
		_check_range(problems, name, "step", step, float(row.step))

	if problems.is_empty():
		problems.append_array(_check_material(spec))

	if problems.is_empty():
		print("[water-params] PASS %d 个参数与着色器一致（另有 %d 个豁免）" % [spec.size(), EXEMPT.size()])
		quit(0)
		return
	for p in problems:
		print("[water-params] FAIL ", p)
	print("[water-params] %d 处差异" % problems.size())
	quit(1)


## 资源本身的两类坑：
##   1. 参数在 .tres 里没有值 —— 面板会读到 null，滑块停在 0，看着像「参数无效」
##   2. `source_color` 的 vec3 存成 Vector3 —— 读出来一模一样，但只要用
##      `ResourceSaver` 存一次（编辑器里点保存也算），就会写成 `= null`，值就没了
func _check_material(spec: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var mat: ShaderMaterial = ResourceLoader.load(WATER_MAT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if mat == null:
		problems.append("读不到 %s" % WATER_MAT_PATH)
		return problems
	for name in spec.keys():
		var row: Dictionary = spec[name]
		if String(row.kind) == "node":
			continue
		var v: Variant = mat.get_shader_parameter(name)
		if v == null:
			problems.append("%s 在 water.tres 里没有值" % name)
			continue
		if String(row.kind) == "color" and not (v is Color):
			problems.append("%s 存成了 %s，必须存 Color，否则一保存就丢" % [name, type_string(typeof(v))])
	# 每帧改的临时参数不该被写进资源。
	var text := FileAccess.get_file_as_string(WATER_MAT_PATH)
	for name in ["u_time", "u_ripples", "u_ripple_count", "u_boat", "ocean_waves",
			"wake_points", "wake_strengths", "wake_count"]:
		if text.contains("shader_parameter/%s = " % name):
			problems.append("water.tres 里混进了运行时参数 %s" % name)
	return problems


func _check_range(problems: PackedStringArray, name: String, field: String, shader_value: float, list_value: float) -> void:
	if absf(shader_value - list_value) > 0.0005:
		problems.append("%s 的 %s：着色器 %.4f，清单 %.4f" % [name, field, shader_value, list_value])


## 从 uniform 的类型 / hint 反推面板该用哪种控件。
func _kind_of(u: Dictionary) -> String:
	match int(u.type):
		TYPE_BOOL:
			return "bool"
		TYPE_COLOR:
			# `vec3 color : source_color` 带 NO_ALPHA，`vec4` 不带。
			return "color" if int(u.hint) == PROPERTY_HINT_COLOR_NO_ALPHA else "color4"
		TYPE_VECTOR3:
			return "vec3"
		TYPE_VECTOR2:
			return "vec2"
		TYPE_INT, TYPE_FLOAT:
			return "float"
		TYPE_OBJECT:
			return "sampler"
	return "array"
