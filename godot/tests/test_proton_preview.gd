extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	var stage=load("res://scenes/vegetation_authoring/proton_rooftop_preview.tscn").instantiate()
	root.add_child(stage)
	for i in 90:await process_frame
	var count:=0;var nodes:=0
	for child in stage.find_children("*","MultiMeshInstance3D",true,false):
		if "NativeScatter" not in String(child.get_path()):continue
		nodes+=1;count+=child.multimesh.instance_count
	var passed: bool=count==11542 and nodes>0 and not stage.get_node("RooftopRanch/VegetationTurf").visible
	if not passed:printerr("FAIL reopened ProtonScatter preview ",count," instances ",nodes," batches")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/proton_editor_preview.png")
	print("[proton-preview] %d instances, %d failures"%[count,0 if passed else 1]);quit(0 if passed else 1)
