extends SceneTree
## Actual main-scene water/day/night/boarding captures, with fixed motion frames.
var main: Node
var shop: Node3D
var area: Node3D
var checks := 0
var failures := 0
var evidence := {"views":[],"motion":[]}

func _init() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func frame(eye: Vector3,target: Vector3,fov := 36.0) -> void:
	main.cam.global_position=eye
	main.cam.look_at(target,Vector3.UP)
	main.cam.fov=fov

func shot(name: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_width()>=1280 and image.get_height()>=720,"actual renderer image "+name)
	image.save_png("res://outputs/gift-kiosk-"+name+".png")
	evidence.views.append(name)
	print("[gift-kiosk-shot] ",name)

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.suspend_follow()
	main.cam.set_process(false)
	main.boat.set_process(false)
	main.hud.hide()
	root.get_node("Economy").ticking=false
	for i in 12:
		await process_frame
	shop=main.get_node("World/SeaStructures/floating_shop")
	shop.set_physics_process(false)
	shop.set_motion_time(0)
	area=shop.walk_areas[0]
	main.daylight_rig.apply(12.0)
	var p: Vector3=shop.global_position
	var target := p+Vector3(0,3.2,0)
	frame(p+Vector3(25,18,32),target,35)
	await shot("hero-day")
	frame(p+Vector3(0,10,35),target,36)
	await shot("front-day")
	frame(p+Vector3(0,11,-35),target,36)
	await shot("back-day")
	frame(p+Vector3(34,11,0),target,36)
	await shot("right-day")
	frame(p+Vector3(0,44,0.01),p,36)
	await shot("top-day")
	# True normal docking/landing flow, no fake posed character.
	var state: Node=root.get_node("GameState")
	var dock: Node3D=shop.landing_point("main")
	var park: Vector3=dock.get_node("BoatPark").global_position
	state.set_mode(state.Mode.ON_BOAT)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	state.enter_zone("sea_supply")
	state.landing_id="main"
	main.boat.place_at(park,0)
	main._select_landing({"zone":"sea_supply","landing":"main"})
	for i in 12:
		await physics_frame
		main._update_walk(1.0/60.0)
	check(main.actor_controller.state_id()=="ashore_idle","real actor landed through normal chain for captures")
	frame(p+Vector3(10,7,19),p+Vector3(0,1.3,6.3),40)
	await shot("boarding")
	var counter: Node3D=shop.get_node("Objects/SupplyCounter")
	check(main._start_walk(area,counter.global_position),"real walk to counter for capture")
	for i in 600:
		await physics_frame
		main._update_walk(1.0/60.0)
		if main.actor_controller.state_id()=="ashore_idle":break
	frame(p+Vector3(10,7,16),p+Vector3(1,2.5,5.0),39)
	await shot("storefront-character")
	if OS.get_environment("SEA_GKS_SHADOW_PROBE")=="1":
		for mesh: MeshInstance3D in shop.find_children("*","MeshInstance3D",true,false):
			if not str(mesh.get_path()).contains("sign_"):
				continue
			for surface in mesh.mesh.get_surface_count():
				var original: Material=mesh.get_active_material(surface)
				var mat: Material=original.duplicate()
				for property in mat.get_property_list():
					if str(property.name).contains("shadow"):
						print("[shadow-probe] ",property.name,"=",mat.get(property.name))
					if property.name=="disable_receive_shadows":mat.set(property.name,true)
				mesh.set_surface_override_material(surface,mat)
		await shot("font-no-receive-shadows")
		print("[gift-kiosk-render] ",checks," checks, ",failures," failures")
		main.queue_free()
		await process_frame
		quit(0 if failures==0 else 1)
		return
	counter.interact(main.player)
	check(main.shop_panel.is_open(),"real general store panel opened")
	main.hud.show()
	await shot("supply-panel")
	main.shop_panel.close()
	main.hud.hide()
	# Fixed camera: the footage shows genuine platform/character transport.
	frame(p+Vector3(7,5.0,17),p+Vector3(0,1.8,7.3),34)
	for i in 20:
		var t := float(i)*6.8/19.0
		shop.set_motion_time(t)
		main._update_walk(6.8/19.0)
		await shot("motion-%02d"%i)
		var gap: float=main.player.global_position.y-area.surface_y
		check(absf(gap)<0.025,"visible actor feet remain on animated support")
		evidence.motion.append({"time":t,"surface_y":area.surface_y,"actor_y":main.player.global_position.y,"gap_m":gap})
	main.daylight_rig.apply(22.0)
	frame(p+Vector3(25,18,32),target,35)
	await shot("hero-night")
	# The old model's placement is preserved and separately visible for inspection.
	var rest: Node3D=main.get_node("World/SeaStructures/floating_rest_stop")
	var rest_target: Vector3=rest.global_position+Vector3(0,10,0)
	main.daylight_rig.apply(12.0)
	frame(rest_target+Vector3(32,29,35),rest_target,40)
	await shot("old-rest-stop")
	var file := FileAccess.open("res://outputs/gift-kiosk-render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	file.close()
	print("[gift-kiosk-render] ",checks," checks, ",failures," failures")
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
