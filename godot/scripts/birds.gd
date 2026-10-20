extends Node3D
## 飞鸟：模型从网页版烘焙，盘旋与振翅参数沿用原值。

const BASE := "res://assets/baked/"

var _birds: Array = []
var _t := 0.0


func build() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(BASE + "birds.json"))
	if data == null:
		return
	for b in data:
		var root := Node3D.new()
		add_child(root)
		for part in b.parts:
			var mesh := _make_mesh(part)
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/toon.gdshader")
			mat.set_shader_parameter("use_texture", false)
			mat.set_shader_parameter("depth_tint", false)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if part.t != null:
				var t: Array = part.t
				mi.transform = Transform3D(
					Basis(Vector3(t[0], t[1], t[2]), Vector3(t[3], t[4], t[5]), Vector3(t[6], t[7], t[8])),
					Vector3(t[9], t[10], t[11])
				)
			root.add_child(mi)
		_birds.append({
			"root": root,
			"center": Vector3(b.center[0], b.center[1], b.center[2]),
			"rx": b.radiusX,
			"rz": b.radiusZ,
			"base_y": b.baseY,
			"speed": b.speed,
			"phase": b.phase,
			"flap": b.flapSpeed
		})


func _process(delta: float) -> void:
	_t += delta
	for b in _birds:
		var angle: float = _t * b.speed + b.phase
		var bx: float = b.center.x + cos(angle) * b.rx
		var bz: float = b.center.z + sin(angle) * b.rz
		var by: float = b.base_y + sin(_t * 1.4 + b.phase) * 0.65
		var next_angle := angle + 0.05
		var nbx: float = b.center.x + cos(next_angle) * b.rx
		var nbz: float = b.center.z + sin(next_angle) * b.rz
		var root: Node3D = b.root
		root.position = Vector3(bx, by, bz)
		root.look_at(Vector3(nbx, by, nbz), Vector3.UP)


func _make_mesh(part: Dictionary) -> ArrayMesh:
	var p: Array = part.p
	var n: Array = part.n if part.n != null else []
	var verts := PackedVector3Array()
	verts.resize(p.size() / 3)
	for i in verts.size():
		verts[i] = Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if n.size() > 0:
		var norms := PackedVector3Array()
		norms.resize(n.size() / 3)
		for i in norms.size():
			norms[i] = Vector3(n[i * 3], n[i * 3 + 1], n[i * 3 + 2])
		arrays[Mesh.ARRAY_NORMAL] = norms
	if part.i != null:
		var idx := PackedInt32Array()
		for v in part.i:
			idx.append(int(v))
		arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
