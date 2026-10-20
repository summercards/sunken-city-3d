@tool
extends Node3D
## 单个区块（或环境）的静态几何。
##
## 只读自己目录下的 bake.json + instances.bin，几何与贴图走 BakeStore 的共享缓存。
## 场景里一个 StaticBatch 节点 = 一条 or 若干条 MultiMesh 批次。

const BakeStore = preload("res://scripts/world/bake_store.gd")

@export var bake_dir := ""
@export var cast_shadow := true
## 关掉后不建 MultiMesh。区块切到模型装配时由 zone_scene 置 false，避免双份几何。
@export var enabled := true

var instance_count := 0
var batch_count := 0


func _ready() -> void:
	if enabled:
		build()


func build() -> void:
	# @tool：编辑器里重复调用 build() 时先清掉上一批，避免叠两层。
	for c in get_children():
		c.queue_free()
	batch_count = 0
	if bake_dir.is_empty():
		push_warning("StaticBatch 缺少 bake_dir")
		return
	BakeStore.ensure_loaded()

	var text := FileAccess.get_file_as_string(bake_dir + "/bake.json")
	var meta: Variant = JSON.parse_string(text)
	if meta == null:
		push_error("bake.json 解析失败: " + bake_dir)
		return

	var inst := _read_f32(bake_dir + "/instances.bin")
	if inst.is_empty():
		return

	for b in meta.batches:
		var count := int(b.count)
		if count <= 0:
			continue
		var mesh: Mesh = BakeStore.geom(int(b.geom))
		if mesh == null:
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = count
		var off := int(b.instOff) * 16
		mm.buffer = inst.slice(off, off + count * 16)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Batch%03d" % batch_count
		mmi.multimesh = mm
		mmi.material_override = BakeStore.material(
			int(b.tex), bool(b.tint), bool(b.unlit), bool(b.alpha), bool(b.doubleSide))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		batch_count += 1
		instance_count += count

	_build_lines(meta.get("lines", []))


## 区块自己的时间（水下焦散/泡沫）。共享材质按批去重，这里统一推。
func update_time(t: float) -> void:
	for mat in BakeStore.timed_materials():
		mat.set_shader_parameter("u_time", t)


func _build_lines(lines: Array) -> void:
	if lines.is_empty():
		return
	var root := MeshInstance3D.new()
	root.name = "Lines"
	root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := BakeStore.line_material()
	root.material_override = mat

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for line in lines:
		var pos: Array = line.pos
		var col: Array = line.color
		var alpha := float(line.get("alpha", 1.0))
		var color := Color(col[0], col[1], col[2], alpha)
		var n := pos.size() / 3
		for i in n:
			verts.append(Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]))
			colors.append(color)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	root.mesh = mesh
	add_child(root)


func _read_f32(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("缺少 " + path)
		return PackedFloat32Array()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes.to_float32_array()
