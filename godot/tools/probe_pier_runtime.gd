extends SceneTree
func _init()->void:
	call_deferred("run")
func run()->void:
	var r:Node3D=load("res://scenes/facilities/rooftop_ranch.tscn").instantiate()
	root.add_child(r)
	await process_frame
	await process_frame
	var p:Node3D=r.get_node("Models/ORF2_实例_pier")
	print("PIER_CHILDREN ",p.get_children().size())
	for n in p.find_children("*","MeshInstance3D",true,false):
		var mi:MeshInstance3D=n
		var mats:Array=[]
		for i in mi.mesh.get_surface_count():
			var m:=mi.get_active_material(i)
			mats.append(m.resource_path if m else "null")
		print("M ",n.name," pos ",n.global_position," mat ",mats)
	quit(0)
