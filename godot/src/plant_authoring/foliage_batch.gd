@tool
extends RefCounted
## 每个显示角色按材质合批；保留枝定位节点，选择和聚焦继续使用生成器 bounds。

static func merge_group(group: Node3D) -> void:
	var batches: Dictionary = {}
	_collect(group, Transform3D.IDENTITY, batches)
	var serial := 0
	for material: Material in batches:
		var buffer: Dictionary = batches[material]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = buffer.v
		arrays[Mesh.ARRAY_NORMAL] = buffer.n
		arrays[Mesh.ARRAY_INDEX] = buffer.i
		arrays[Mesh.ARRAY_TEX_UV] = buffer.uv
		arrays[Mesh.ARRAY_TEX_UV2] = buffer.uv2
		arrays[Mesh.ARRAY_COLOR] = buffer.colors
		var mesh := ArrayMesh.new()
		mesh.resource_local_to_scene = true
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var visual := MeshInstance3D.new()
		visual.name = "Batch_%02d" % serial
		visual.mesh = mesh
		visual.extra_cull_margin = 0.25
		group.add_child(visual)
		serial += 1

static func _collect(node: Node3D, transform: Transform3D, batches: Dictionary) -> void:
	for child in node.get_children():
		if child is Node3D:
			_collect(child, transform * child.transform, batches)
	if not node is MeshInstance3D or node.mesh == null:
		return
	var normal_basis := transform.basis.inverse().transposed()
	for surface in node.mesh.get_surface_count():
		var material: Material = node.get_active_material(surface)
		if not batches.has(material):
			batches[material] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "colors": PackedColorArray()}
		var buffer: Dictionary = batches[material]
		var arrays: Array = node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var first: int = buffer.v.size()
		for index in vertices.size():
			buffer.v.append(transform * vertices[index])
			buffer.n.append((normal_basis * normals[index]).normalized())
			buffer.colors.append(colors[index] if colors.size() == vertices.size() else Color(0, 0, 1, 1))
		buffer.uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
		buffer.uv2.append_array(arrays[Mesh.ARRAY_TEX_UV2])
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in indices:
			buffer.i.append(first + index)
	# 仅回收本次生成的渲染节点，不删除持有稳定路径的 branch Node3D。
	node.get_parent().remove_child(node)
	node.free()
