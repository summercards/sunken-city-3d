extends RefCounted
## 植物网格读取（tools/build_plants.py 写出的紧凑二进制）。
##
## 布局：[vcount u32][icount u32][position f32*3v][normal f32*3v][color f32*3v][index u32*i]
## 读进来直接拼成 ArrayMesh，颜色走顶点色（和烘焙场景一致）。

static var _cache: Dictionary = {}


static func load_mesh(path: String) -> ArrayMesh:
	if _cache.has(path):
		return _cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("缺少植物网格: " + path)
		return null
	var vcount := f.get_32()
	var icount := f.get_32()

	var pos := PackedVector3Array()
	pos.resize(vcount)
	for i in vcount:
		pos[i] = Vector3(f.get_float(), f.get_float(), f.get_float())

	var nor := PackedVector3Array()
	nor.resize(vcount)
	for i in vcount:
		nor[i] = Vector3(f.get_float(), f.get_float(), f.get_float())

	var col := PackedColorArray()
	col.resize(vcount)
	for i in vcount:
		col[i] = Color(f.get_float(), f.get_float(), f.get_float(), 1.0)

	var idx := PackedInt32Array()
	idx.resize(icount)
	for i in icount:
		idx[i] = f.get_32()
	f.close()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[path] = mesh
	return mesh
