extends SceneTree
## Facility-only regression independent of unfinished main-scene integrations.
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func run() -> void:
	var shop: Node3D=load("res://scenes/facilities/floating_shop.tscn").instantiate()
	# Nonidentity placement exercises world -> facility mask conversion.
	shop.transform=Transform3D(Basis(Vector3.UP,0.63),Vector3(120,1.12,220))
	root.add_child(shop)
	shop.set_physics_process(false)
	shop.set_motion_time(0)
	var visual: Node3D=shop.get_node("Visual")
	var actor:=Node3D.new()
	root.add_child(actor)
	var mode: Dictionary={"ashore":true}
	shop.configure_view_subject(actor,func()->bool:return mode.ashore)
	var reveal: Node3D=shop.get_node("RoofReveal")
	reveal.set_process(false)
	actor.global_position=visual.to_global(Vector3(0,0.3,7.4))
	reveal.advance(0)
	check(reveal.snapshot().roof_roots==78 and reveal.snapshot().amount==0,"formal scene registers all overhead pieces and stays closed outside")
	var bindings: Array=reveal._bindings
	var originals:=[]
	for b in bindings: originals.append(b.mesh.get_surface_override_material(b.surface))
	for fps in [30,60,120]:
		actor.global_position=visual.to_global(Vector3(1.1,0.3,1.2))
		for i in fps: reveal.advance(1.0/fps)
		var s: Dictionary=reveal.snapshot()
		check(s.inside and s.amount==1 and s.visible_roofs==0,"transformed facility opens at %s fps"%fps)
		check((s.center as Vector2).distance_to(Vector2(1.1,1.2))<0.001,"mask uses local actor coordinates")
		for seconds in [0.0,1.7,3.4,5.1,6.8]:
			shop.set_motion_time(seconds)
			actor.global_position=visual.to_global(Vector3(1.1,0.3,1.2))
			reveal.advance(1.0/fps)
			check(reveal.snapshot().inside,"heave does not drop interior state")
		mode.ashore=false
		for i in fps: reveal.advance(1.0/fps)
		check(not reveal.snapshot().inside and reveal.snapshot().amount==0 and reveal.snapshot().visible_roofs==78,"boat mode restores roof at %s fps"%fps)
		mode.ashore=true
	for i in bindings.size():
		var b: Dictionary=bindings[i]
		check(b.mesh.get_surface_override_material(b.surface)==originals[i],"exact serialized material restored")
	actor.global_position=visual.to_global(Vector3(0,0.3,0))
	reveal.advance(0.24)
	var partial: float=reveal.snapshot().amount
	actor.global_position=visual.to_global(Vector3(0,0.3,6.5))
	reveal.advance(0.03)
	check(reveal.snapshot().amount>0 and reveal.snapshot().amount<partial,"reversal does not snap")
	reveal.advance(1)
	actor.global_position=visual.to_global(Vector3(0,0.3,5.18))
	reveal.advance(0.1)
	check(not reveal.snapshot().inside,"entry does not activate outside threshold")
	actor.global_position=visual.to_global(Vector3(0,0.3,5.0))
	reveal.advance(0.1)
	actor.global_position=visual.to_global(Vector3(0,0.3,5.3))
	reveal.advance(0.1)
	check(reveal.snapshot().inside,"door margin prevents threshold chatter")
	actor.queue_free()
	reveal.advance(1)
	await process_frame
	reveal.advance(1)
	check(reveal.snapshot().amount==0,"freed actor safely restores roof")
	shop.queue_free()
	await process_frame
	print("[roof-reveal-component] ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
