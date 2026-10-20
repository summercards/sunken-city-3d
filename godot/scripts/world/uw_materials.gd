extends RefCounted
## 水下材质的共享缓存。
##
## 一个单元按材质槽分成多个 surface，槽位参数（颜色 / 自发光 / 顶点色 / 双面 / 透明）
## 来自 manifest.json。同参数的槽在所有区块之间复用同一个 ShaderMaterial，
## 这样 4 个区块加起来也只是几十个材质，而不是几千个。

const SOLID := "res://shaders/underwater.gdshader"
const ALPHA := "res://shaders/underwater_alpha.gdshader"

static var _cache: Dictionary = {}


static func get_material(slot: Dictionary) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s" % [
		str(slot.get("color", [])),
		str(slot.get("emissive", [])),
		str(slot.get("emissive_strength", 0.0)),
		str(slot.get("vertex_color", false)),
		str(slot.get("alpha", false)),
	]
	if _cache.has(key):
		return _cache[key]

	var alpha: bool = bool(slot.get("alpha", false))
	var mat := ShaderMaterial.new()
	mat.shader = load(ALPHA if alpha else SOLID)
	var c: Array = slot.get("color", [1, 1, 1])
	mat.set_shader_parameter("albedo_color", Color(float(c[0]), float(c[1]), float(c[2])))
	var e: Array = slot.get("emissive", [0, 0, 0])
	mat.set_shader_parameter("emissive_color", Color(float(e[0]), float(e[1]), float(e[2])))
	mat.set_shader_parameter("emissive_strength", float(slot.get("emissive_strength", 0.0)))
	mat.set_shader_parameter("use_vertex_color", bool(slot.get("vertex_color", false)))
	if alpha:
		mat.set_shader_parameter("alpha", float(slot.get("opacity", 0.4)))
		mat.render_priority = 1
	_cache[key] = mat
	return mat


## 屏幕空间水雾的浓淡取决于相机所在深度，每帧推给所有水底材质。
static func set_depth(depth: float) -> void:
	for mat in _cache.values():
		(mat as ShaderMaterial).set_shader_parameter("dive_depth", depth)


static func clear_cache() -> void:
	_cache.clear()
