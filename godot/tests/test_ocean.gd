extends SceneTree
const Surface = preload("res://src/rendering/water_surface.gd")
const Wake = preload("res://src/rendering/boat_wake.gd")
const Vessel = preload("res://src/navigation/boat.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var water := Surface.new()
	water.material_override = load("res://assets/materials/water.tres")
	water.position.y = 1.12
	root.add_child(water)
	water.set_process(false)
	var wake := Wake.new()
	root.add_child(wake)
	var boat := Vessel.new()
	root.add_child(boat)
	boat.set_process(false)
	boat.water_surface = water
	boat.model = Node3D.new()
	boat.add_child(boat.model)
	var minimum := 100.0
	var maximum := -100.0
	for i in 120:
		var p := Vector2(i * 0.37, i * -0.21)
		var t := i * 0.13
		var s := water.sample_surface(p, t)
		var dx := (water.sample_surface(p + Vector2(0.01,0),t).x - water.sample_surface(p - Vector2(0.01,0),t).x) / 0.02
		var dz := (water.sample_surface(p + Vector2(0,0.01),t).x - water.sample_surface(p - Vector2(0,0.01),t).x) / 0.02
		check(absf(s.y-dx)<0.0002 and absf(s.z-dz)<0.0002,"normal agrees with displaced surface")
		minimum=minf(minimum,s.x)
		maximum=maxf(maximum,s.x)
	check(maximum-minimum>0.25,"waves have measurable geometric displacement")
	check(maxf(absf(minimum),absf(maximum))<0.4,"wave bounds fit harbour/berths")
	water.wave_scale=0.0
	check(water.sample_surface(Vector2(9,17),8.0)==Vector3.ZERO,"flat-water control disables displacement")
	water.wave_scale=1.0
	boat.place_at(Vector3(0,1.12,0),0.0)
	for i in 180:
		water.time=float(i)/60.0
		boat._process(1.0/60.0)
	check(absf(boat.position.y-1.12)>0.005 and absf(boat.model.rotation.x)>0.001,"boat heave and pitch follow sampled wave")
	check(Vector2(boat.position.x,boat.position.z)==Vector2.ZERO,"buoyancy does not alter navigation position")
	# Steer through a real bend. Verify old history stays put and expires after stopping.
	boat.place_at(Vector3(0,1.12,0),PI)
	boat.sail_to_point(Vector3(12,1.12,12),[Vector2.ZERO,Vector2(0,12),Vector2(12,12)])
	var t := 0.0
	for i in 360:
		t+=1.0/60.0
		boat._steer(1.0/60.0)
		wake.update_wake(t,boat,water)
	check(wake.samples.size()>10 and wake.samples.size()<=64,"bounded trail samples follow actual sailing")
	var old_position: Vector2 = wake.samples[0].pos
	boat.rotation.y+=0.8
	wake.update_wake(t+0.01,boat,water)
	check(wake.samples[0].pos==old_position,"turning leaves emitted wake in world space")
	boat._sailing=false
	boat._speed_actual=0.0
	wake.update_wake(t+1.0,boat,water)
	check(wake.visible and not wake.samples.is_empty(),"wake persists after stopping")
	wake.update_wake(t+11.0,boat,water)
	check(wake.samples.is_empty() and not wake.visible,"stopped wake dissipates completely")
	boat._speed_actual=3.0
	for i in 20:
		t+=0.2
		boat.position.z+=0.6
		wake.update_wake(t,boat,water)
	boat.place_at(Vector3(90,1.12,90),0.0)
	boat._speed_actual=0.0
	wake.update_wake(t+0.1,boat,water)
	check(wake.samples.is_empty(),"teleport never draws a cross-map streak")
	var mat := water.material_override as ShaderMaterial
	var gpu_waves: PackedVector4Array = mat.get_shader_parameter("ocean_waves")
	check(gpu_waves==water.ocean_waves,"CPU buoyancy and shader use identical wave parameters")
	check(water.mesh.get_surface_count()==1 and water.mesh.surface_get_array_len(0)==66049,"continuous bounded ocean mesh")
	# Extract actual water/geometry intersections: concave outline, transformed mesh,
	# MultiMesh and hidden/fully-submerged objects. No authored shoreline JSON.
	var shore_root := Node3D.new()
	root.add_child(shore_root)
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 4, 4)
	block.mesh = box
	shore_root.add_child(block)
	var atlas := preload("res://src/rendering/shore_distance.gd").new()
	atlas.rebuild([shore_root], 1.12, 128)
	check(atlas.segments.size() == 8, "box slice derives eight triangle segments")
	check(atlas.distance_at(Vector2(2, 0)) < 0.2, "derived contour follows actual box edge")
	check(absf(atlas.distance_at(Vector2(5, 0)) - 3.0) < 0.2, "distance field measures metres")
	check(absf(atlas.distance_at(Vector2(4, 4)) - sqrt(8.0)) < 0.25, "distance field has circular diagonal falloff")
	block.position.x = 8.0
	block.rotation.y = PI / 4.0
	atlas.rebuild([shore_root], 1.12, 128)
	check(atlas.distance_at(Vector2(8.0 + sqrt(8.0), 0)) < 0.2, "moving and rotating geometry moves shoreline")
	check(atlas.distance_at(Vector2(2, 0)) > 2.0, "old shoreline vanishes after rebuild")
	block.hide()
	atlas.rebuild([shore_root], 1.12, 128)
	check(atlas.segments.is_empty(), "hidden geometry cannot emit foam")
	block.show()
	block.position.y = -6.0
	atlas.rebuild([shore_root], 1.12, 128)
	check(atlas.segments.is_empty(), "submerged geometry does not create false surface edges")
	var instanced := MultiMeshInstance3D.new()
	instanced.multimesh = MultiMesh.new()
	instanced.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instanced.multimesh.mesh = box
	instanced.multimesh.instance_count = 1
	instanced.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(-8, 0, 0)))
	shore_root.add_child(instanced)
	atlas.rebuild([shore_root], 1.12, 128)
	# Dummy RenderingServer does not retain MultiMesh instance transforms.
	# Exercise this assertion in the companion real-renderer test as well.
	if DisplayServer.get_name() != "headless":
		check(atlas.distance_at(Vector2(-6, 0)) < 0.2, "MultiMesh instance waterline uses instance transform")
	instanced.hide()
	block.position = Vector3.ZERO
	block.rotation = Vector3.ZERO
	var thin := BoxMesh.new()
	thin.size = Vector3(2, 0.04, 2)
	var merged_faces := box.get_faces()
	for v in thin.get_faces(): merged_faces.append(v + Vector3(6, 1.12, 0))
	var merged_arrays := []
	merged_arrays.resize(Mesh.ARRAY_MAX)
	merged_arrays[Mesh.ARRAY_VERTEX] = merged_faces
	var merged_mesh := ArrayMesh.new()
	merged_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged_arrays)
	block.mesh = merged_mesh
	atlas.rebuild([shore_root], 1.12, 128)
	check(atlas.segments.size() == 8 and atlas.distance_at(Vector2(5, 0)) > 2.5,
		"thin decoration merged into a building cannot seed spurious foam circles")
	shore_root.queue_free()
	water.queue_free()
	wake.queue_free()
	boat.queue_free()
	await process_frame
	print("[ocean] checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
