extends RefCounted
## 水下材质的共享缓存。
##
## 一个单元按材质槽分成多个 surface，槽位参数（颜色 / 自发光 / 顶点色 / 双面 / 透明）
## 来自 manifest.json。同参数的槽在所有区块之间复用同一个 ShaderMaterial，
## 这样 4 个区块加起来也只是几十个材质，而不是几千个。
##
## 所有水下实体都经过本库；manifest 颜色是线性值，Color 构造的美术色走 from_color。
## 单/双面按源材质决定；实体不写 ALPHA，透明物体测试深度但不写深度。

const SOLID := "res://shaders/underwater.gdshader"
const SOLID_CULLED := "res://shaders/underwater_culled.gdshader"
const ALPHA := "res://shaders/underwater_alpha.gdshader"
const ALPHA_CULLED := "res://shaders/underwater_alpha_culled.gdshader"
const FACING_DEBUG := "res://shaders/uw_facing_debug.gdshader"

static var _cache: Dictionary = {}
static var _depth := 10.0
static var _time := -1.0
## 头灯状态。新建材质时也要立刻带上，否则灯开着但新材质是黑的。
static var _lamp := {
	"on": false,
	"pos": Vector3.ZERO,
	"dir": Vector3(0, 0, -1),
}


static func get_material(slot: Dictionary) -> ShaderMaterial:
	var alpha: bool = bool(slot.get("alpha", false))
	var double_side: bool = bool(slot.get("double_side", false))
	# 缓存键必须覆盖所有表面属性，尤其 opacity，不能把不同透明度合并。
	var params := {
		"albedo_color": slot.get("color", [1, 1, 1]),
		"emissive_color": slot.get("emissive", [0, 0, 0]),
		"emissive_strength": float(slot.get("emissive_strength", 0.0)),
		"use_vertex_color": bool(slot.get("vertex_color", false)),
		"roughness": float(slot.get("roughness", 0.58)),
		"metallic": float(slot.get("metallic", 0.06)),
		"alpha": float(slot.get("opacity", 0.4)) if alpha else 1.0,
	}
	var key := str([params, alpha, double_side])
	if _cache.has(key):
		return _cache[key]

	var mat := ShaderMaterial.new()
	if alpha:
		mat.shader = load(ALPHA if double_side else ALPHA_CULLED)
	else:
		mat.shader = load(SOLID if double_side else SOLID_CULLED)
	for param in params:
		var value: Variant = params[param]
		if param in ["albedo_color", "emissive_color"]:
			value = Color(float(value[0]), float(value[1]), float(value[2]))
		mat.set_shader_parameter(param, value)
	mat.set_shader_parameter("dive_depth", _depth)
	mat.set_shader_parameter("time_override", _time)

	_apply_lamp(mat)
	_cache[key] = mat
	return mat


static func _apply_lamp(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("lamp_on", bool(_lamp["on"]))
	mat.set_shader_parameter("lamp_pos", _lamp["pos"])
	mat.set_shader_parameter("lamp_dir", _lamp["dir"])


## 头灯：位置与朝向每帧由潜水员推过来。
## PBR 接收引擎灯光；头灯散射是额外效果（见 uw_common 的 uw_lamp）。
static func set_lamp(on: bool, pos: Vector3, dir: Vector3) -> void:
	_lamp["on"] = on
	_lamp["pos"] = pos
	_lamp["dir"] = dir
	for mat in _cache.values():
		var sm: ShaderMaterial = mat
		sm.set_shader_parameter("lamp_on", on)
		sm.set_shader_parameter("lamp_pos", pos)
		sm.set_shader_parameter("lamp_dir", dir)


## 屏幕空间水雾的浓淡取决于相机所在深度，每帧推给所有水底材质。
static func set_depth(depth: float) -> void:
	_depth = depth
	for mat in _cache.values():
		(mat as ShaderMaterial).set_shader_parameter("dive_depth", depth)


## 把焦散/闪光的相位冻在某一时刻（诊断闪动用；负值恢复成跟 TIME 走）。
static func freeze_time(t: float) -> void:
	_time = t
	for mat in _cache.values():
		(mat as ShaderMaterial).set_shader_parameter("time_override", t)


## 诊断：把指定区块的所有材质换成「正面绿 / 背面红」的调试材质。
## 用法见 `--uwfacing`。只影响画面，不改任何几何数据。
static func set_facing_debug(root: Node, on: bool) -> void:
	var mat: ShaderMaterial = null
	if on:
		if _facing_mat == null:
			_facing_mat = ShaderMaterial.new()
			_facing_mat.shader = load(FACING_DEBUG)
		mat = _facing_mat
	for n in _walk(root):
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null or mi.name == "UnderwaterFogPass":
			continue
		if on and not mi.has_meta("uw_facing_original"):
			mi.set_meta("uw_facing_original", [mi.material_override, mi.cast_shadow])
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif not on and mi.has_meta("uw_facing_original"):
			var original: Array = mi.get_meta("uw_facing_original")
			mi.material_override = original[0]
			mi.cast_shadow = original[1]
			mi.remove_meta("uw_facing_original")


static var _facing_mat: ShaderMaterial


static func _walk(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


static func clear_cache() -> void:
	_cache.clear()
	_facing_mat = null
	_depth = 10.0
	_time = -1.0


## 程序生成的鱼、宝箱等使用 sRGB 美术色；只在入口转换一次。
static func from_color(color: Color, options: Dictionary = {}) -> ShaderMaterial:
	var linear := color.srgb_to_linear()
	var slot := options.duplicate()
	slot["color"] = [linear.r, linear.g, linear.b]
	return get_material(slot)


## 专用水下角色的程序材质也走同一入口，不修改海面角色的共享资源。
static func apply_to_standard_meshes(root: Node) -> void:
	for n in _walk(root):
		if not n is MeshInstance3D:
			continue
		var mi: MeshInstance3D = n
		var original: Material = mi.material_override
		if original is StandardMaterial3D:
			var m: StandardMaterial3D = original
			mi.material_override = from_color(m.albedo_color, {
				"roughness": m.roughness, "metallic": m.metallic,
				"double_side": m.cull_mode == BaseMaterial3D.CULL_DISABLED,
				"alpha": m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
				"opacity": m.albedo_color.a,
			})
