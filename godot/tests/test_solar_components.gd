extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func _init() -> void:call_deferred("run")
func nodes(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():out.append_array(nodes(c))
	return out
func run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/solar_cabin/instances.json"))
	var keys := {}
	for e in data.instances:keys["solar_cabin/"+e.component]=true
	var lower: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/bloom_lower_building/instances.json"))
	for e in lower.instances:keys["bloom_lower_building/"+e.component]=true
	for kit in ["solar_cabin", "bloom_lower_building"]:
		if kit != "bloom_lower_building":continue
		for filename in DirAccess.get_files_at("res://scenes/components/"+kit):
			if filename.ends_with(".tscn"):keys[kit+"/"+filename.trim_suffix(".tscn")]=true
	for key in keys:
		var scene: PackedScene=load("res://scenes/components/%s.tscn" % key)
		check(scene!=null,"independent scene "+key)
		if scene==null:continue
		var ob: Node3D=scene.instantiate();root.add_child(ob)
		check(ob.scale.is_equal_approx(Vector3.ONE),"root unit scale "+key)
		var mesh_count := 0
		for n in nodes(ob):
			if not n is MeshInstance3D:continue
			mesh_count+=1
			for i in n.mesh.get_surface_count():
				var m: Material=n.get_surface_override_material(i)
				check(m is ShaderMaterial,"standalone palette shader "+key)
				if m is ShaderMaterial:check(m.get_shader_parameter("palette").resource_path=="res://assets/textures/shared/sea_cabin_muted_8x8_512.png","standalone shared palette "+key)
		check(mesh_count>0,"non-empty component "+key);ob.queue_free()
	await process_frame
	print("[solar-components] components=",keys.size()," checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
