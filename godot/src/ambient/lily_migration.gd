extends RefCounted
## Split only triangles proven equal to the original lily bake; never delete by bounds.
const Bake = preload("res://src/world/bake_store.gd")
const Leaf = preload("res://scenes/decorations/water/lily_leaf.tscn")
const DATA := "res://assets/data/lily_components.json"
static func cell(p: Vector3) -> Vector3i:
	return Vector3i(round(p.x*100),round(p.y*100),round(p.z*100))
static func install(zone: Node3D, models: Node3D) -> void:
	if zone.has_node("WaterDecorations") or models == null: return
	var data: Array=JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var targets := {};var selected: Array=[]
	for entry in data:
		if entry.zone_id!=zone.zone_id: continue
		selected.append(entry)
		var t: Array=entry.transform
		var xf := Transform3D(Basis(Vector3(t[0],t[4],t[8]),Vector3(t[1],t[5],t[9]),Vector3(t[2],t[6],t[10])),Vector3(t[3],t[7],t[11]))
		entry["xf"]=xf
		var faces: PackedVector3Array=Bake.geom(int(entry.geometry_id)).get_faces()
		for i in range(0,faces.size(),3):
			var tri := [xf*faces[i],xf*faces[i+1],xf*faces[i+2]]
			var key := cell((tri[0]+tri[1]+tri[2])/3.0)
			if not targets.has(key): targets[key]=[]
			targets[key].append(tri)
	if selected.is_empty(): return
	var removed := _retire(models,zone.global_transform.affine_inverse(),targets)
	var decorations := Node3D.new();decorations.name="WaterDecorations";decorations.set_meta("visual_only",true)
	zone.add_child(decorations)
	for entry in selected:
		var leaf=Leaf.instantiate()
		leaf.name=entry.instance_id.get_file();leaf.instance_id=entry.instance_id
		leaf.geometry_id=int(entry.geometry_id);leaf.transform=entry.xf
		var c: Array=entry.color;leaf.leaf_color=Color(c[0],c[1],c[2],c[3])
		decorations.add_child(leaf)
	decorations.set_meta("retired_triangles",removed)
	print("[lily-migration] ",zone.zone_id," independent=",selected.size()," retired_triangles=",removed)

static func matches(tri: Array, targets: Dictionary) -> bool:
	var center := cell((tri[0]+tri[1]+tri[2])/3.0)
	for x in range(-1,2):
		for y in range(-1,2):
			for z in range(-1,2):
				for other in targets.get(center+Vector3i(x,y,z),[]):
					for permutation in [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]:
						if tri[0].distance_to(other[permutation[0]])<0.002 and tri[1].distance_to(other[permutation[1]])<0.002 and tri[2].distance_to(other[permutation[2]])<0.002: return true
	return false

static func _retire(node: Node, world_to_zone: Transform3D, targets: Dictionary) -> int:
	var removed := 0
	if node is Node3D and not node.visible: return 0
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		var original: ArrayMesh=node.mesh
		var mesh := ArrayMesh.new();var modified := false
		for surface in original.get_surface_count():
			var arrays: Array=original.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices=PackedInt32Array();for i in vertices.size(): indices.append(i)
			var xf: Transform3D=world_to_zone*node.global_transform
			for i in range(0,indices.size(),3):
				var tri := [xf*vertices[indices[i]],xf*vertices[indices[i+1]],xf*vertices[indices[i+2]]]
				if tri[0].distance_to(tri[1])<0.00001: continue
				if matches(tri,targets):
					indices[i+1]=indices[i];indices[i+2]=indices[i];modified=true;removed+=1
			arrays[Mesh.ARRAY_INDEX]=indices
			mesh.add_surface_from_arrays(original.surface_get_primitive_type(surface),arrays)
			mesh.surface_set_material(surface,original.surface_get_material(surface))
		if modified: node.mesh=mesh
	for child in node.get_children(): removed+=_retire(child,world_to_zone,targets)
	return removed
