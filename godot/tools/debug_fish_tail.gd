extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	for _i in 8: await process_frame
	var school: Node = main.get_node("World/Environment/Animals/SolarCabinFishSchools").get_child(0)
	var fin: MultiMeshInstance3D = school.get_node("Fin")
	var body: MultiMeshInstance3D = school.get_node("Body")
	print("school ", school, "members ", school.members.size(), "transforms ", school.transforms.size(), "parts ", school.get_children(), "fin ", fin, "mm ", fin.multimesh)
	school.sample(0.2)
	var a: Transform3D = fin.multimesh.get_instance_transform(0)
	var ba: Transform3D = body.multimesh.get_instance_transform(0)
	print("arrayA ", school.transforms[0])
	school.sample(0.8)
	var b: Transform3D = fin.multimesh.get_instance_transform(0)
	var bb: Transform3D = body.multimesh.get_instance_transform(0)
	print("bodyA ", ba, " bodyB ", bb, "\nfinA ", a, "\nfinB ", b, "\nequal ", a.is_equal_approx(b), "count ", fin.multimesh.instance_count)
	quit()
