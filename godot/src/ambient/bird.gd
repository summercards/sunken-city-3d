extends "res://src/ambient/scene_component.gd"
## One independently placeable baked bird. Flight phase is cosmetic, never inventory state.
@export var flight_center := Vector3.ZERO
@export var radius := Vector2(4.8,3.6)
@export var altitude := 19.0
@export var speed := 0.52
@export var phase := 0.0
@export var flap_speed := 8.0
@export_range(0,6) var baked_variant := 0
var wing_rest: Array[Transform3D] = []
var elapsed := 0.0
func _ready() -> void:
	var data: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/baked/birds.json"))
	setup(data[clampi(baked_variant,0,data.size()-1)])
func setup(data: Dictionary) -> void:
	component_kind="decoration";subcategory="animals";asset_id="SEA-DECO-ANIMAL-BIRD"
	set_meta("visual_only",true)
	for child in get_children(): child.free()
	wing_rest.clear()
	for part in data.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = _make_mesh(part)
		var mat := StandardMaterial3D.new()
		var c: Array=part.get("c",[1,1,1])
		mat.albedo_color=Color(c[0],c[1],c[2]).linear_to_srgb();mat.roughness=0.9
		if part.get("unlit",false): mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override=mat
		mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t: Array=part.t
		mi.transform=Transform3D(Basis(Vector3(t[0],t[1],t[2]),Vector3(t[3],t[4],t[5]),Vector3(t[6],t[7],t[8])),Vector3(t[9],t[10],t[11]))
		add_child(mi);wing_rest.append(mi.transform)
	sample(0.0)
func sample(t: float) -> void:
	var angle := t*speed+phase
	position=flight_center+Vector3(cos(angle)*radius.x,altitude+sin(t*1.4+phase)*0.65,sin(angle)*radius.y)
	var tangent := Vector3(-sin(angle)*radius.x,0,cos(angle)*radius.y)
	# 鸟身锥尖朝 +Z（Three 烘焙，网页版 lookAt 以 +Z 为前），与鲸鱼、鱼群同一约定。
	# 原先写成 atan2(-tangent.x,-tangent.z)，等于让屁股朝前，整群鸥倒着飞。
	rotation.y=atan2(tangent.x,tangent.z)
	for i in range(1,get_child_count()):
		var wing: Node3D=get_child(i)
		wing.transform=wing_rest[i]
		wing.basis=Basis(Vector3.FORWARD,sin(t*flap_speed)*0.22*(1 if i==1 else -1))*wing.basis
func _process(delta: float) -> void:
	elapsed+=delta;sample(elapsed)

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
