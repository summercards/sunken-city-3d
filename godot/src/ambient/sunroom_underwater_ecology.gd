@tool
extends Node3D
## 只从既有 reef 烘焙恢复十二个小单体；摆位、缩放和接地归 TSCN 与父场景。

const MaterialLib = preload("res://src/diving/uw_materials.gd")
const SOURCE := "res://assets/baked/underwater/"
const DEFINITION_COUNT := 12


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "scene.json"))
	if not parsed is Dictionary:
		push_error("阳光房水下生态缺少原始 reef 清单")
		return
	var source: Dictionary = parsed
	var batches: Array[Dictionary] = []
	for raw in source["batches"]:
		if raw.get("region") == "reef" and raw.get("unit") == "coral_00":
			batches.append(raw)
	# 此桶按基石、粉/紫/青/橙的岩块与枝干排列；不允许源改变后误取整片礁群。
	var expected_counts := [32, 117, 84, 117, 84, 110, 84, 78, 56]
	if batches.size() != expected_counts.size():
		push_error("reef coral_00 分组已改变，需要重新审阅单体来源")
		return
	for i in batches.size():
		if int(batches[i]["count"]) != expected_counts[i]:
			push_error("reef coral_00 实例顺序已改变，需要重新审阅单体来源")
			return
	var vertices := FileAccess.get_file_as_bytes(SOURCE + "geoms.bin").to_float32_array()
	var indices := FileAccess.get_file_as_bytes(SOURCE + "geoms_idx.bin").to_int32_array()
	var instances := FileAccess.get_file_as_bytes(SOURCE + "instances.bin").to_float32_array()
	if vertices.is_empty() or indices.is_empty() or instances.is_empty():
		push_error("阳光房水下生态缺少原始 reef 几何数据")
		return
	var definitions: Array[ArrayMesh] = []
	for definition in DEFINITION_COUNT:
		definitions.append(_restore_colony(definition, source["geoms"], batches, vertices, indices, instances))
	for child in $CoralClusters.get_children():
		var visual := child.get_node("Visual") as MeshInstance3D
		var definition := int(child.get_meta("coral_definition"))
		visual.mesh = definitions[definition]
	# Restore only the old street-lamp lens as a lit local material. Shared city
	# materials remain untouched and the existing mesh/UV is reused byte-for-byte.
	for assembly in $FacilityLights.get_children():
		if not str(assembly.get_meta("category","")).begins_with("street_lamp"): continue
		for visual in assembly.get_node("Visual").find_children("*","MeshInstance3D",true,false):
			for surface in visual.mesh.get_surface_count():
				var old: Material = visual.get_active_material(surface)
				var lamp := ShaderMaterial.new()
				lamp.shader = preload("res://shaders/sunroom_underwater_lamp.gdshader")
				lamp.set_shader_parameter("palette",preload("res://assets/textures/shared/sea_cabin_timber_8x8_512.png"))
				lamp.set_shader_parameter("lamp_color",assembly.get_node("Point").light_color)
				if old is StandardMaterial3D:
					lamp.set_shader_parameter("roughness_value",old.roughness)
					lamp.set_shader_parameter("metallic_value",old.metallic)
				visual.set_surface_override_material(surface,lamp)


func _restore_colony(definition: int, geometries: Array, batches: Array[Dictionary], vertices: PackedFloat32Array, indices: PackedInt32Array, instances: PackedFloat32Array) -> ArrayMesh:
	var base := _source_transform(instances, int(batches[0]["instOff"]) + definition)
	var center := base.origin
	var color_batch := 1 + floori(float(definition) / 3.0) * 2
	var form := definition % 3
	var pieces := [{"batch": 0, "first": definition, "count": 1}]
	# 前十二株正好覆盖四个原配色 × 三种轮廓，保留完整原株而不是拼造新珊瑚。
	pieces.append({"batch": color_batch, "first": [0, 11, 32][form], "count": [11, 21, 7][form]})
	if form == 1:
		pieces.append({"batch": color_batch + 1, "first": 0, "count": 28})
	var surfaces: Array[Dictionary] = []
	var bottom := INF
	for piece in pieces:
		var batch: Dictionary = batches[int(piece["batch"])]
		var geometry: Dictionary = geometries[int(batch["geom"])]
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var count := int(geometry["icount"])
		if count == 0:
			count = int(geometry["vcount"])
		for item in int(piece["count"]):
			var pose := _source_transform(instances, int(batch["instOff"]) + int(piece["first"]) + item)
			for triangle in range(0, count, 3):
				var points := PackedVector3Array()
				for corner in 3:
					var vertex := triangle + corner
					if int(geometry["icount"]) > 0:
						vertex = indices[int(geometry["iOff"]) + vertex]
					var offset := int(geometry["pOff"]) + vertex * 3
					var point := pose * Vector3(vertices[offset], vertices[offset + 1], vertices[offset + 2]) - center
					bottom = minf(bottom, point.y)
					points.append(point)
				var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
				# glTF 导入器原本会翻绕序；直接 ArrayMesh 复用时显式转成 Godot 顺时针。
				for corner in [0, 2, 1]:
					positions.append(points[corner])
					normals.append(normal)
		surfaces.append({"positions": positions, "normals": normals, "batch": batch})
	var mesh := ArrayMesh.new()
	mesh.resource_name = "ReefColony%02d" % definition
	for surface in surfaces:
		var positions: PackedVector3Array = surface["positions"]
		for i in positions.size():
			positions[i].y -= bottom
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = surface["normals"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var batch: Dictionary = surface["batch"]
		var slot := {"color": batch["color"], "flat": true, "double_side": batch["doubleSide"], "unlit": batch["unlit"], "alpha": false, "opacity": batch["opacity"]}
		var emission: Variant = batch.get("emissive")
		if emission is Array:
			slot["emissive"] = emission.slice(0, 3)
			slot["emissive_strength"] = float(emission[3])
		mesh.surface_set_material(mesh.get_surface_count() - 1, MaterialLib.get_material(slot))
	return mesh


func _source_transform(instances: PackedFloat32Array, instance: int) -> Transform3D:
	var offset := instance * 16
	return Transform3D(
		Vector3(instances[offset], instances[offset + 4], instances[offset + 8]),
		Vector3(instances[offset + 1], instances[offset + 5], instances[offset + 9]),
		Vector3(instances[offset + 2], instances[offset + 6], instances[offset + 10]),
		Vector3(instances[offset + 3], instances[offset + 7], instances[offset + 11])
	)
