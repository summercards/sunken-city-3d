extends SceneTree
## Real pixel comparison of caustic on/off at all eight authored time slots.
const Slots = preload("res://src/rendering/daylight_slots.gd")
var checks := 0
var failures := 0
var main
var evidence := []
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func shot(tag: String) -> Image:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://outputs/submerged-light-" + tag + ".png")
	return img
func patch_delta(lit: Image, off: Image, point: Vector3) -> Dictionary:
	var screen: Vector2 = main.cam.unproject_position(point)
	var canvas := root.get_visible_rect().size
	var center := Vector2i(screen * Vector2(lit.get_width(), lit.get_height()) / canvas)
	var rect := Rect2i(center - Vector2i(8,8), Vector2i(16,16)).intersection(Rect2i(0,0,lit.get_width(),lit.get_height()))
	var delta := 0.0
	var darkest := 1.0
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var d := lit.get_pixel(x,y).get_luminance() - off.get_pixel(x,y).get_luminance()
			delta += d
			darkest = minf(darkest,d)
			n += 1
	return {"mean":delta/maxi(n,1), "minimum":darkest, "samples":n, "rect":str(rect)}
func signal_stats(lit: Image, off: Image) -> Dictionary:
	var positive := 0
	var total := 0
	var peak := 0.0
	for y in range(lit.get_height()/3, lit.get_height(),2):
		for x in range(0,lit.get_width(),2):
			var d := lit.get_pixel(x,y).get_luminance()-off.get_pixel(x,y).get_luminance()
			if d > .004: positive += 1
			peak = maxf(peak,d)
			total += 1
	return {"positive_fraction":float(positive)/maxi(total,1),"peak":peak}
func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL real renderer required");quit(1);return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.set_process(false)
	main.world_clock.paused = true;main.weather_service.paused = true
	main.cam.set_process(false);main.cam.follow_enabled = false;main.boat.set_process(false)
	for i in 8: await process_frame
	main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide()
	main.cam.target = Vector3(1,0,7)
	main.cam.distance = 73
	main.cam.orbit_dir = Vector3(-.6,.85,.8)
	main.cam.refresh()
	var scenery: Node3D = main.get_node("World/UnderwaterScenery")
	var probes := []
	for key in ["rounded_tower", "stepped_lowrise", "flat_annex"]:
		var node: Node3D = scenery.get_node(key)
		var mesh: MeshInstance3D = node.find_children("*","MeshInstance3D",true,false)[0]
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		probes.append({"key":key,"point":Vector3(box.get_center().x,box.end.y-.19,box.get_center().z)})
	for scheme in ["original","absorption"]:
		main.water_node.use_scheme(scheme)
		var texture: Texture2D = main.water_node.current_material().get_shader_parameter("cross_ripple_mask")
		check(texture != null and texture.resource_path == "res://assets/textures/water/cartoon_cross_ripple.png", scheme+" consumes the real cartoon cross mask")
		if texture != null:
			var mask := texture.get_image()
			check(mask.get_width()==512 and mask.get_height()==512, scheme+" full-resolution mask")
		for slot in Slots.SLOTS:
			main.daylight_rig.apply(float(slot.hour))
			var mat: ShaderMaterial = main.water_node.current_material()
			mat.set_shader_parameter("caustics_enabled",true)
			var lit := await shot(scheme+"-"+slot.id)
			mat.set_shader_parameter("caustics_enabled",false)
			var off := await shot(scheme+"-"+slot.id+"-no-caustic")
			var mark_stats := signal_stats(lit,off)
			check(mark_stats.positive_fraction < .07, scheme+" "+slot.id+" sparse markings, no broad wash")
			check(mark_stats.peak < .15, scheme+" "+slot.id+" faint highlight ceiling")
			if slot.id == "morning" or slot.id == "noon": check(mark_stats.peak > .005, scheme+" "+slot.id+" actual cross texture is visible")
			var row := {"scheme":scheme,"slot":slot.id,"hour":slot.hour,"patches":[],"signal":mark_stats}
			for probe in probes:
				var delta := patch_delta(lit,off,probe.point)
				check(delta.samples > 100, scheme+" "+slot.id+" roof inside camera "+probe.key)
				check(delta.mean >= -.002 and delta.minimum >= -.015, scheme+" "+slot.id+" caustics never create dark blotches "+probe.key+" "+str(delta))
				row.patches.append({"key":probe.key,"delta":delta})
			evidence.append(row)
			mat.set_shader_parameter("caustics_enabled",true)
	main.water_node.use_scheme("original")
	main.cam.target = Vector3(-1,-2,12)
	main.cam.distance = 47
	main.cam.refresh()
	for hour in [9.0,17.0,19.0]:
		main.daylight_rig.apply(hour)
		await shot("cross-close-"+str(int(hour)))
	var file := FileAccess.open("res://outputs/submerged-water-light.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"));file.close()
	main.queue_free();await process_frame
	print("[submerged-water-light] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
