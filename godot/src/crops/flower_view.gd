@tool
extends Node3D
## 原创花卉几何源；只装配四个阶段，切换与缺水着色仍由 CropView 拥有。
const StageDef = preload("res://src/crops/crop_stage.gd")

@export_enum("blue", "sun", "coral") var flower_style := "blue"

var _built := false
var _round_mesh: ArrayMesh
var _stem_mesh: CylinderMesh
var _leaf_material: StandardMaterial3D
var _stem_material: StandardMaterial3D
var _petal_material: StandardMaterial3D
var _heart_material: StandardMaterial3D


func _notification(what: int) -> void:
	# PackedScene 实例化完成时导出值、阶段节点均已就位；离树预览也有真网格。
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		ensure_built()


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	_round_mesh = _make_round_mesh()
	_stem_mesh = CylinderMesh.new()
	_stem_mesh.top_radius = 1.0
	_stem_mesh.bottom_radius = 1.0
	_stem_mesh.height = 1.0
	_stem_mesh.radial_segments = 6
	_stem_mesh.rings = 1
	_leaf_material = _material(Color("#92b98b"))
	_stem_material = _material(Color("#709a79"))
	var petals := Color("#79b8e8")
	var heart := Color("#f4ead0")
	var seed_color := Color("#a3adbd")
	if flower_style == "sun":
		petals = Color("#f2c86b")
		heart = Color("#b89164")
		seed_color = Color("#b39771")
	elif flower_style == "coral":
		petals = Color("#e48d87")
		heart = Color("#f6dcb7")
		seed_color = Color("#c6a297")
	_petal_material = _material(petals)
	_heart_material = _material(heart)
	var soil := _material(Color("#a88a69"))
	var seed := _material(seed_color)
	var seed_size := Vector3(0.025, 0.014, 0.045)
	var sprout_height := 0.19
	var sprout_width := 0.04
	if flower_style == "sun":
		seed_size = Vector3(0.024, 0.014, 0.055)
		sprout_height = 0.23
		sprout_width = 0.065
	elif flower_style == "coral":
		seed_size = Vector3(0.035, 0.014, 0.035)
		sprout_height = 0.18
		sprout_width = 0.075
	for index in StageDef.count():
		var stage := get_node_or_null(StageDef.node_name(index)) as Node3D
		if stage == null:
			continue
		if index == StageDef.SEED:
			for x in [-0.14, 0.14]:
				_oval(stage, "Soil", Vector3(x, 0.018, 0), Vector3(0.13, 0.018, 0.09), soil)
				_oval(stage, "Seed", Vector3(x, 0.038, 0), seed_size, seed)
		elif index == StageDef.SPROUT:
			_stem(stage, Vector3.ZERO, Vector3(0, sprout_height, 0), 0.012)
			for i in 3:
				_leaf(stage, i * TAU / 3.0, sprout_height * 0.68, 0.10, sprout_width)
		elif index == StageDef.LEAF:
			_foliage(stage, false)
		else:
			_foliage(stage, true)
			_blossoms(stage)


func _foliage(stage: Node3D, mature: bool) -> void:
	match flower_style:
		"sun":
			var height := 0.77 if mature else 0.53
			_stem(stage, Vector3.ZERO, Vector3(0, height, 0), 0.019)
			for i in 4:
				_leaf(stage, i * PI * 0.5, 0.16 + i * 0.07, 0.19, 0.085)
		"coral":
			_stem(stage, Vector3.ZERO, Vector3(0, 0.30, 0), 0.019)
			for i in 3:
				var tip := _coral_tip(i, mature)
				_stem(stage, Vector3(0, 0.19, 0), tip, 0.014)
			for i in 5:
				_leaf(stage, i * TAU / 5.0, 0.16 + (i % 2) * 0.07, 0.14, 0.085)
		_:
			_stem(stage, Vector3.ZERO, Vector3(0, 0.49 if mature else 0.31, 0), 0.014)
			for i in 5:
				_leaf(stage, i * TAU / 5.0, 0.10, 0.20, 0.043)


func _blossoms(stage: Node3D) -> void:
	match flower_style:
		"sun":
			var center := Vector3(0, 0.77, 0)
			for i in 10:
				_petal(stage, center, i * TAU / 10.0, 0.15, Vector3(0.12, 0.035, 0.053), 0.10)
			_oval(stage, "FlowerHeart", center + Vector3(0, 0.025, 0), Vector3(0.115, 0.055, 0.115), _heart_material)
		"coral":
			for branch in 3:
				var center := _coral_tip(branch, true)
				for i in 5:
					_petal(stage, center, i * TAU / 5.0 + branch * 0.4, 0.069, Vector3(0.083, 0.034, 0.057), -0.58)
				_oval(stage, "FlowerHeart", center, Vector3(0.04, 0.033, 0.04), _heart_material)
		_:
			var center := Vector3(0, 0.49, 0)
			for i in 5:
				_petal(stage, center, i * TAU / 5.0, 0.115, Vector3(0.16, 0.029, 0.059), 0.14)
			_oval(stage, "FlowerHeart", center + Vector3(0, 0.023, 0), Vector3(0.047, 0.035, 0.047), _heart_material)


func _coral_tip(index: int, mature: bool) -> Vector3:
	var angle := index * TAU / 3.0
	var spread := 0.23 if mature else 0.13
	return Vector3(cos(angle) * spread, (0.47 + index * 0.055) if mature else 0.33, sin(angle) * spread)


func _leaf(stage: Node3D, angle: float, height: float, length: float, width: float) -> void:
	var leaf := _oval(stage, "Leaf", Vector3(cos(angle) * length * 0.72, height, sin(angle) * length * 0.72), Vector3(length, 0.026, width), _leaf_material)
	leaf.rotation = Vector3(0, -angle, 0.24)


func _petal(stage: Node3D, center: Vector3, angle: float, radius: float, size: Vector3, tilt: float) -> void:
	var petal := _oval(stage, "Petal", center + Vector3(cos(angle) * radius, 0, sin(angle) * radius), size, _petal_material)
	petal.rotation = Vector3(0, -angle, tilt)


func _stem(stage: Node3D, start: Vector3, end: Vector3, radius: float) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Stem"
	mesh.mesh = _stem_mesh
	mesh.position = (start + end) * 0.5
	mesh.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	mesh.scale = Vector3(radius, start.distance_to(end), radius)
	_stem_mesh.material = _stem_material
	stage.add_child(mesh)


func _oval(stage: Node3D, label: String, at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	# 材质放网格表面，CropView 解除缺水 override 后仍保留原色。
	var geometry := _round_mesh.duplicate() as ArrayMesh
	geometry.surface_set_material(0, material)
	mesh.mesh = geometry
	mesh.position = at
	mesh.scale = size
	stage.add_child(mesh)
	return mesh


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.metallic_specular = 0.12
	return material


func _make_round_mesh() -> ArrayMesh:
	# 六边、三纬带的闭合柔面；每个花叶 24 三角面，整格各阶段低于 900。
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for band in 3:
		var top := PI * band / 3.0
		var bottom := PI * (band + 1) / 3.0
		for segment in 6:
			var a := TAU * segment / 6.0
			var b := TAU * (segment + 1) / 6.0
			var p0 := Vector3(sin(top) * cos(a), cos(top), sin(top) * sin(a))
			var p1 := Vector3(sin(bottom) * cos(a), cos(bottom), sin(bottom) * sin(a))
			var p2 := Vector3(sin(bottom) * cos(b), cos(bottom), sin(bottom) * sin(b))
			var p3 := Vector3(sin(top) * cos(b), cos(top), sin(top) * sin(b))
			if band > 0:
				for point in [p0, p2, p3]:
					surface.set_normal(point.normalized())
					surface.add_vertex(point)
			if band < 2:
				for point in [p0, p1, p2]:
					surface.set_normal(point.normalized())
					surface.add_vertex(point)
	return surface.commit()
