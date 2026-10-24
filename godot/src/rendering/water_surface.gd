@tool
extends MeshInstance3D
## Adaptive, continuous grid: 0.5 m near the view target, coarser toward the horizon.
## Waves are shared with the boat and wake, using one simulation clock.
@export var ocean_waves := PackedVector4Array([
	Vector4(0.94, 0.34, 0.16, 12.0),
	Vector4(-0.42, 0.91, 0.085, 7.6),
	Vector4(0.72, -0.69, 0.0325, 4.9),
	Vector4(-0.85, -0.53, 0.0105, 2.55),
])
## 出厂波幅。写在默认值上而不是 `main.tscn` 的节点属性里：
## 场景覆盖会被编辑器重写丢掉（实测丢过一次），默认值不会。
@export_range(0.0, 2.0, 0.05) var wave_scale := 1.2
var shoreline: RefCounted
var time := 0.0
var wake: Node3D
var _last_stroke := 0.0
var _was_moving := false
var _ripples := PackedVector4Array()
var _ripple_index := 0

func _ready() -> void:
	mesh = _make_grid()
	extra_cull_margin = 2.0
	if material_override != null:
		if not Engine.is_editor_hint():
			material_override = material_override.duplicate()
		_sync(material_override)
	_ripples.resize(8)
	for i in 8: _ripples[i] = Vector4(0, 0, -100, 0)

func _sync(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("ocean_waves", ocean_waves)
	mat.set_shader_parameter("wave_scale", wave_scale)
	mat.set_shader_parameter("u_time", time)

func sample_surface(p: Vector2, at_time: float = -1.0) -> Vector3:
	var t := time if at_time < 0.0 else at_time
	var result := Vector3.ZERO
	for i in ocean_waves.size():
		var w := ocean_waves[i]
		var d := Vector2(w.x, w.y).normalized()
		var k := TAU / maxf(w.w, 0.01)
		var cross_dir := Vector2(-d.y, d.x)
		var cross_k := k * 0.61
		var cross_phase := cross_k * cross_dir.dot(p) + float(i) * 2.31 - t * 0.19
		var envelope := 0.72 + 0.28 * sin(cross_phase)
		var envelope_grad := cross_dir * (0.28 * cross_k * cos(cross_phase))
		var phase := k * d.dot(p) - sqrt(9.81 * k) * t + float(i) * 1.73 + 0.85 * sin(cross_phase * 0.83 + 0.7)
		var phase_grad := k * d + cross_dir * (0.85 * 0.83 * cross_k * cos(cross_phase * 0.83 + 0.7))
		var height := sin(phase) + 0.18 * sin(phase * 2.0)
		var derivative := cos(phase) + 0.36 * cos(phase * 2.0)
		result.x += w.z * envelope * height
		var slope := w.z * (envelope_grad * height + envelope * phase_grad * derivative)
		result.y += slope.x
		result.z += slope.y
	return result * wave_scale

func update_surface(t: float, boat: Node3D, focus: Vector3) -> void:
	time = t
	# Snapping only changes tessellation placement; wave phase stays in world space.
	position.x = snappedf(focus.x, 0.5)
	position.z = snappedf(focus.z, 0.5)
	var mat := material_override as ShaderMaterial
	_sync(mat)
	mat.set_shader_parameter("u_boat", boat.wake_uniform())
	var rowing: Vector2 = boat.rowing_state()
	var moving: bool = boat.starts_sailing()
	if moving and rowing.y > 0.15 and rowing.x < _last_stroke:
		var side := Vector2(cos(boat.rotation.y), -sin(boat.rotation.y))
		for sign_value in [-1.0, 1.0]:
			var p: Vector2 = Vector2(boat.position.x, boat.position.z) + side * float(sign_value) * 2.6
			emit_ripple(p, 0.65)
	if _was_moving and not moving:
		emit_ripple(Vector2(boat.position.x, boat.position.z), 0.5)
	_last_stroke = rowing.x
	_was_moving = moving
	mat.set_shader_parameter("u_ripples", _ripples)
	mat.set_shader_parameter("u_ripple_count", 8)
	if wake != null:
		wake.update_wake(t, boat, self)

func emit_ripple(p: Vector2, strength := 1.0) -> void:
	_ripples[_ripple_index] = Vector4(p.x, p.y, time, strength)
	_ripple_index = (_ripple_index + 1) % 8

func _make_grid() -> ArrayMesh:
	var axis := PackedFloat32Array()
	# 257 x 257 vertices, no overlapping LOD rings or cracks.
	for i in range(-128, 129):
		var a := float(absi(i))
		var distance := a * 0.5 if a <= 96 else 48.0 + pow((a - 96.0) / 32.0, 2.0) * 592.0
		axis.append(signf(float(i)) * distance)
	var n := axis.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for z in n:
		for x in n:
			verts[z * n + x] = Vector3(axis[x], 0, axis[z])
			normals[z * n + x] = Vector3.UP
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			indices.append_array(PackedInt32Array([a, a + 1, a + n, a + 1, a + n + 1, a + n]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func rebuild_shoreline(roots: Array, region := Rect2()) -> void:
	shoreline = preload("res://src/rendering/shore_distance.gd").new()
	shoreline.rebuild(roots, global_position.y, 1536, region)
	shoreline.bind(material_override as ShaderMaterial)
	print("[shoreline] geometry segments=", shoreline.segments.size(), " bounds=", shoreline.bounds)
