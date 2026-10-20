extends RefCounted
## 烘焙几何的共享缓存。
##
## 几何表（geoms.bin / geoms_idx.bin）与贴图在所有区块之间共享，只加载一次；
## 每个区块只带自己的 instances.bin + bake.json。这样拆成五个场景也不会
## 把 5MB 几何复制五份。
##
## 材质按 (贴图, 深度染色, unlit, 透明, 双面) 去重，和网页版的合批口径一致。

const BAKED := "res://assets/baked/"
const WATER_LEVEL := 1.12

static var _geoms: Array = []
static var _textures: Array = []
static var _materials: Dictionary = {}
static var _white: ImageTexture
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)

	var meta_text := FileAccess.get_file_as_string(BAKED + "scene.json")
	var meta: Variant = JSON.parse_string(meta_text)
	if meta == null:
		push_error("scene.json 解析失败")
		return

	for rel in meta.textures:
		_textures.append(load(BAKED + rel) as Texture2D)

	var verts := _read_f32("geoms.bin")
	var indices := _read_i32("geoms_idx.bin")
	for g in meta.geoms:
		_geoms.append(_make_mesh(g, verts, indices))


static func geom(index: int) -> Mesh:
	ensure_loaded()
	if index < 0 or index >= _geoms.size():
		return null
	return _geoms[index]


static func material(tex: int, tint: bool, unlit: bool, alpha: bool, double_side: bool) -> ShaderMaterial:
	ensure_loaded()
	var key := "%d|%d|%d|%d|%d" % [tex, int(tint), int(unlit), int(alpha), int(double_side)]
	if _materials.has(key):
		return _materials[key]

	var path := "res://shaders/unlit.gdshader"
	if not unlit:
		path = "res://shaders/toon.gdshader"
	if alpha:
		path = path.replace(".gdshader", "_alpha.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	mat.set_shader_parameter("use_texture", tex >= 0)
	mat.set_shader_parameter("albedo_tex", _textures[tex] if tex >= 0 else _white)
	mat.set_shader_parameter("depth_tint", tint)
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	if double_side:
		mat.set_shader_parameter("double_side", true)
	if alpha:
		mat.render_priority = 1
	_materials[key] = mat
	return mat


## 线框统一用 unlit + 顶点色（构建脚本会把颜色写进顶点色）。
static func line_material() -> ShaderMaterial:
	ensure_loaded()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/unlit.gdshader")
	mat.set_shader_parameter("use_texture", false)
	mat.set_shader_parameter("albedo_tex", _white)
	mat.render_priority = 1
	return mat


static func timed_materials() -> Array:
	return _materials.values()


static func _read_f32(file_name: String) -> PackedFloat32Array:
	var f := FileAccess.open(BAKED + file_name, FileAccess.READ)
	if f == null:
		push_error("缺少 " + file_name)
		return PackedFloat32Array()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes.to_float32_array()


static func _read_i32(file_name: String) -> PackedInt32Array:
	var f := FileAccess.open(BAKED + file_name, FileAccess.READ)
	if f == null:
		push_error("缺少 " + file_name)
		return PackedInt32Array()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes.to_int32_array()


static func _slice_vec3(src: PackedFloat32Array, off: int, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	for i in count:
		var k := off + i * 3
		out[i] = Vector3(src[k], src[k + 1], src[k + 2])
	return out


static func _slice_vec2(src: PackedFloat32Array, off: int, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		var k := off + i * 2
		out[i] = Vector2(src[k], src[k + 1])
	return out


static func _slice_color(src: PackedFloat32Array, off: int, count: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(count)
	for i in count:
		var k := off + i * 3
		out[i] = Color(src[k], src[k + 1], src[k + 2], 1.0)
	return out


static func _make_mesh(g: Dictionary, verts: PackedFloat32Array, indices: PackedInt32Array) -> ArrayMesh:
	var vc := int(g.vcount)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _slice_vec3(verts, int(g.pOff), vc)
	if int(g.nOff) >= 0:
		arrays[Mesh.ARRAY_NORMAL] = _slice_vec3(verts, int(g.nOff), vc)
	if int(g.tOff) >= 0:
		arrays[Mesh.ARRAY_TEX_UV] = _slice_vec2(verts, int(g.tOff), vc)
	if int(g.cOff) >= 0:
		arrays[Mesh.ARRAY_COLOR] = _slice_color(verts, int(g.cOff), vc)
	if int(g.icount) > 0:
		arrays[Mesh.ARRAY_INDEX] = indices.slice(int(g.iOff), int(g.iOff) + int(g.icount))

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
