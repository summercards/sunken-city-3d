extends SceneTree
## Source envelope, component loading, oar motion, physical lamp and native frames.
var checks := 0
var failures := 0
var main
var evidence := {}
const KEYS := ["hull","gunwale","floor_board","bench","rib","outboard","luggage","fender","oar","oarlock","cleat","rope_coil"]
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func box(node: Node3D, basis_node: Node3D) -> AABB:
	var out := AABB()
	var found := false
	for child in node.find_children("*","MeshInstance3D",true,false):
		if child.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:continue
		var b: AABB = basis_node.global_transform.affine_inverse() * child.global_transform * child.mesh.get_aabb()
		out = b if not found else out.merge(b)
		found = true
	return out
func shot(label: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/reference-skiff-"+label+".png")
func run() -> void:
	if DisplayServer.get_name() != "headless": preload("res://tools/lighting_capture_profile.gd").prepare()
	for key in KEYS:
		var component: Node3D=load("res://scenes/components/reference_skiff/"+key+".tscn").instantiate()
		root.add_child(component)
		check(box(component,component).size.length()>.1,"independent component geometry "+key)
		check(component.asset_id.begins_with("SEA-SCENE-SKIFF-"),"component identity "+key)
		check(component.find_children("*","CollisionObject3D",true,false).is_empty(),"visual owns no new collision "+key)
		for visual in component.find_children("*","MeshInstance3D",true,false):
			for surface in visual.mesh.get_surface_count():
				var material: ShaderMaterial=visual.get_active_material(surface)
				check(material!=null and material.shader.resource_path=="res://shaders/skiff_palette.gdshader","shared real-light shader "+key)
		component.free()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.process_mode=Node.PROCESS_MODE_DISABLED
	main.boat.model.transform=Transform3D.IDENTITY
	var hull: AABB=box(main.boat.model.get_node("Parts/hull_000"),main.boat.model).merge(box(main.boat.model.get_node("Parts/gunwale_001"),main.boat.model))
	var expected_min:=Vector3(-1.287456959,-.205626881,-2.935829524)
	var expected_max:=Vector3(1.287251965,.867509990,2.461650025)
	check(hull.position.distance_to(expected_min)<.00002,"legacy hull minimum matched within 0.02mm")
	check(hull.end.distance_to(expected_max)<.00002,"legacy hull maximum matched within 0.02mm")
	check(main.boat.scale==Vector3.ONE and main.boat.model.scale==Vector3.ONE,"unit runtime root scale")
	check(main.boat._oar_l.get_parent()==main.boat.model and main.boat._oar_r.get_parent()==main.boat.model,"oars follow hull heave/pitch/roll")
	var left: Transform3D=main.boat._oar_l.transform
	main.boat._sailing=true;main.boat._vel=main.boat.cruise_speed()
	for i in 90:main.boat._animate_oars(1.0/60.0)
	check(main.boat._row_blend>.99 and main.boat._oar_l.transform!=left,"existing rowing state drives authored oars")
	check(main.boat._oar_l.rotation.y*main.boat._oar_r.rotation.y<0.0,"paired oars mirror their stroke")
	var lowest_blade := INF
	var recovered_blade := -INF
	for i in 120:
		main.boat._animate_oars(1.0/60.0)
		var blade_y: float=box(main.boat._oar_l,main.boat.model).position.y
		lowest_blade=minf(lowest_blade,blade_y);recovered_blade=maxf(recovered_blade,blade_y)
	check(lowest_blade<0.0 and recovered_blade>.3,"authored blade enters water and clears on recovery")
	main.boat._sailing=false;main.boat._vel=0.0
	for i in 180:main.boat._animate_oars(1.0/60.0)
	check(absf(main.boat._oar_l.rotation.y-1.1)<.001 and absf(main.boat._oar_r.rotation.y+1.1)<.001,"idle smoothly folds both oars")
	var lamp: SpotLight3D=main.boat.model.get_node("BoatLamp")
	check(lamp.is_in_group("boat_lamps") and lamp.shadow_enabled,"existing physical navigation lamp retained")
	check(main.boat.model.get_node("BowLantern").instance_id=="boat/furnishing/bow_lantern","lantern stable identity")
	check(main.boat.SPEED==2.6 and main.boat.TURN_RATE==1.8,"navigation tuning unchanged")
	evidence={"hull_min":str(hull.position),"hull_max":str(hull.end),"hull_size":str(hull.size),"component_count":12,"instance_count":44,"expected_faults":[],"unexecuted":["commercial reference rights review","manual gamepad play"]}
	if DisplayServer.get_name()!="headless":
		main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide();main.get_node("Birds").hide()
		if main.start_screen!=null:main.start_screen.hide()
		main.cam.follow_enabled=false
		main.player.hide()
		main.boat.place_at(Vector3(26,1.12,25),0)
		main.cam.target=main.boat.global_position+Vector3.UP*.35;main.cam.distance=13.8;main.cam.orbit_dir=Vector3(-.65,.90,.80);main.cam.refresh()
		main.daylight_rig.apply(9.0);await shot("day")
		var original_cast := {}
		for visual in main.boat.model.find_children("*","MeshInstance3D",true,false):
			original_cast[visual]=visual.cast_shadow;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		await shot("no-boat-casters")
		for visual in original_cast:visual.cast_shadow=original_cast[visual]
		main.water_node.hide();await shot("dry-diagnostic");main.water_node.show()
		var sun: DirectionalLight3D=main.get_node("World/Lights/Sun")
		var shadows: bool=sun.shadow_enabled
		sun.shadow_enabled=false;await shot("day-shadow-diagnostic");sun.shadow_enabled=shadows
		main.cam.distance=12.0;main.cam.orbit_dir=Vector3(.60,.95,-.85);main.cam.refresh();await shot("bow")
		main.boat._sailing=true;main.boat._vel=main.boat.cruise_speed()
		for i in 50:main.boat._animate_oars(1.0/60.0)
		main.cam.distance=15.5;main.cam.orbit_dir=Vector3(-.65,1.30,.80);main.cam.refresh();await shot("rowing")
		main.player.show();main.player.position=Vector3(0,.62,-.30);await shot("with-player")
		main.boat._sailing=false;main.boat._vel=0
		for i in 180:main.boat._animate_oars(1.0/60.0)
		main.daylight_rig.apply(21.0);await shot("night")
		var landing: Dictionary=main._current_landing().data()
		main.player.hide();main.boat.place_at(Vector3(landing.boatPark[0],1.12,landing.boatPark[2]),float(landing.boatYaw));main.daylight_rig.apply(9.0)
		main.cam.target=main.boat.position+Vector3(0,.5,-1.8);main.cam.distance=24;main.cam.orbit_dir=Vector3(-.65,.85,.80);main.cam.refresh();await shot("docked")
	var file:=FileAccess.open("res://outputs/reference-skiff.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	main.queue_free();await process_frame
	print("[reference-skiff] %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
