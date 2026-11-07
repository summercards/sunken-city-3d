extends SceneTree
var checks := 0
var failures := 0
func _init() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func run() -> void:
	var shop: Node3D=load("res://scenes/facilities/floating_shop.tscn").instantiate()
	shop.position=Vector3(70,1.12,80);shop.rotation.y=.3;root.add_child(shop);shop.set_physics_process(false);shop.set_motion_time(0)
	var actor:=Node3D.new();root.add_child(actor)
	var cam:=Camera3D.new();root.add_child(cam);cam.current=true
	var roof: Node3D=shop.get_node("RoofReveal");roof.set_process(false)
	var cut: Node3D=shop.get_node("SightlineReveal");cut.set_process(false)
	var visual: Node3D=shop.get_node("Visual")
	shop.configure_view_subject(actor,func()->bool:return true,cam)
	check(cut._subject==actor and cut._camera==cam,"actual subject and camera injected")
	check(cut.snapshot().candidates>100 and cut.snapshot().materials<=5,"scoped walls and furnishings use a small role material cache")
	var originals:=[]
	for c in cut._candidates:
		for b in c.bindings:originals.append({"mesh":c.mesh,"surface":b.surface,"material":b.original})
	var all_visible:=[]
	for c in cut._candidates:all_visible.append(c.mesh.visible)
	actor.global_position=visual.to_global(Vector3(0,.3,7.4));roof.advance(1);cut.advance(1)
	check(cut.snapshot().amount==0 and cut.snapshot().active_meshes==0,"outside keeps original facade")
	var initial_pose:=cam.global_transform
	for fps in [30,60,120]:
		actor.global_position=visual.to_global(Vector3(0,.3,0));cam.global_position=visual.to_global(Vector3(11,14,15));cam.look_at(visual.to_global(Vector3(0,1.3,0)),Vector3.UP)
		var pose:=cam.global_transform
		for i in fps:roof.advance(1.0/fps);cut.advance(1.0/fps)
		var s: Dictionary=cut.snapshot()
		check(s.amount==1 and s.active_meshes>10 and s.active_meshes<s.candidates,"foreground subset opens at %s fps"%fps)
		check(cam.global_transform==pose,"cutaway does not move the camera")
		var uv: Vector2=cam.unproject_position(actor.global_position+Vector3.UP*1.05)/cam.get_viewport().get_visible_rect().size
		check((s.center_uv as Vector2).distance_to(uv)<.00001,"oval centred on projected actor torso")
		var front_set: Array=[]
		for c in cut._candidates:
			if c.active:front_set.append(c.mesh.get_path())
		cam.global_position=visual.to_global(Vector3(-11,14,-15));cam.look_at(visual.to_global(Vector3(0,1.3,0)),Vector3.UP);cut.advance(0)
		var swaps:=0
		for c in cut._candidates:
			if c.active and c.mesh.get_path() not in front_set:swaps+=1
		check(swaps>10,"camera rotation changes near-side occluders")
		shop.set_motion_time(2.0);actor.global_position=visual.to_global(Vector3(.2,.3,0));roof.advance(0);cut.advance(0)
		var projected: Vector2=cam.unproject_position(actor.global_position+Vector3.UP*1.05)/cam.get_viewport().get_visible_rect().size
		check((cut.snapshot().center_uv as Vector2).distance_to(projected)<.00001,"window follows actor on heaving platform")
		actor.global_position=visual.to_global(Vector3(0,.3,7.4))
		for i in fps:roof.advance(1.0/fps);cut.advance(1.0/fps)
		check(cut.snapshot().amount==0 and cut.snapshot().active_meshes==0,"exit restores all at %s fps"%fps)
	for original in originals:check(original.mesh.get_surface_override_material(original.surface)==original.material,"exact original per-surface reference restored")
	for c in cut._candidates:check(not str(c.mesh.get_path()).contains("/Floor/") and not str(c.mesh.get_path()).contains("/UnderwaterVisual/"),"floor and underwater parts excluded")
	actor.global_position=visual.to_global(Vector3(0,.3,0));roof.advance(1);cut.advance(.12)
	var partial: float=cut.snapshot().amount
	actor.global_position=visual.to_global(Vector3(0,.3,7.4));roof.advance(.01);cut.advance(.03)
	check(cut.snapshot().amount>0 and cut.snapshot().amount<partial,"quick reversal retains continuous amount")
	cut.advance(1)
	for i in cut._candidates.size():check(cut._candidates[i].mesh.visible==all_visible[i],"mesh visibility never toggled by sightline mask")
	actor.queue_free();await process_frame;roof.advance(1);cut.advance(1)
	check(cut.snapshot().active_meshes==0,"freed actor restores materials safely")
	shop.queue_free();cam.queue_free();await process_frame
	print("[shop-sightline] ",checks," checks, ",failures," failures");quit(0 if failures==0 else 1)
