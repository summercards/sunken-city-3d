extends SceneTree

const WaterAsset = preload("res://assets/materials/water.tres")
const EnvironmentAsset = preload("res://assets/materials/world_env.tres")
const Orbit = preload("res://src/camera/orbit_camera.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [surface-visual-reuse] ", label)

func _finish() -> void:
	print("[surface-visual-reuse] %d checks, %d failures" % [checks, failures])
	quit(int(failures > 0))

func _capture(tag: String) -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), tag + " actual frame")
	if image != null and not image.is_empty():
		_check(image.save_png("res://outputs/surface-visual-" + tag + ".png") == OK, tag + " PNG")
	await process_frame
	return image

func _ab(a: Image, b: Image, label: String) -> void:
	if a == null or b == null or a.is_empty() or b.is_empty():
		return
	var changes := 0
	for y in range(8, a.get_height(), 8):
		for x in range(8, a.get_width(), 8):
			var c := a.get_pixel(x, y)
			var d := b.get_pixel(x, y)
			if absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b) > 0.09:
				changes += 1
	print("[surface-visual] ", label, " changed samples=", changes)
	_check(changes > 20, label + " visibly changes the screenshot")

func _run() -> void:
	var slot := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	_check(DisplayServer.get_name() != "headless" and slot.begins_with("sea-verification/"), "real render in isolated runner")
	if failures:
		_finish()
		return
	var entry := str(ProjectSettings.get_setting("application/run/main_scene"))
	var minimal := entry.ends_with("main_minimal.tscn")
	if not minimal:
		_check(OS.get_cmdline_user_args().has("--nosave"), "legacy fixture never loads or autosaves")
	_check(change_scene_to_file(entry) == OK, "configured scene loads")
	if failures:
		_finish()
		return
	await scene_changed
	var scene := current_scene
	for i in 32:
		await physics_frame
	var ocean: MeshInstance3D = scene.get_node("Ocean" if minimal else "World/Water")
	var env: WorldEnvironment = scene.get_node("WorldEnvironment" if minimal else "World/WorldEnvironment")
	var sun: DirectionalLight3D = scene.get_node("Sun" if minimal else "World/Lights/Sun")
	var cam: Orbit = scene.get_node("Camera")
	var subject: Node3D = scene.get_node("Player") if minimal else scene.get("player")
	if not minimal:
		scene.daylight_rig.set_preview(9.0)
		for control in scene.get_children():
			if control is CanvasLayer:
				control.hide()
	var aim := subject.global_position + Vector3.UP * 1.05
	# Same lens, orbit direction, and distance above each scene's own actor;
	# the official home architecture and the whitebox solids are not identical.
	cam.suspend_follow()
	cam.zoom_min = 8.0
	cam.zoom_max = 40.0
	cam.setup(aim + Vector3(0.0, 0.65, 0.76).normalized() * 17.2, aim)
	cam.pose_lock = true
	# Freeze only clocks for the optical A/B. No physics body is repositioned.
	scene.set_process(false)
	ocean.set_process(false)
	var mat: ShaderMaterial = ocean.material_override
	var original_strength := float(mat.get_shader_parameter("contact_foam_strength"))
	var original_reflection := float(mat.get_shader_parameter("reflection_strength"))
	var original_crest := float(mat.get_shader_parameter("crest_foam_strength"))
	mat.set_shader_parameter("u_time", 2.0)
	print("[surface-visual] scene=", entry, " lens=", cam.fov, " relative=", cam.global_position - aim,
		" sun=", sun.light_energy, " fill=", scene.has_node("HemisphereFill") or scene.has_node("World/Lights/HemisphereFill"),
		" wave_scale=", ocean.wave_scale, " shore=", mat.get_shader_parameter("shore_enabled"),
		" contact=", original_strength, " crest=", original_crest, " reflection=", original_reflection)
	_check(mat.shader == WaterAsset.shader and mat != WaterAsset, "existing water shader on local instance")
	_check(env.environment.sky.sky_material == EnvironmentAsset.sky.sky_material or env.environment.sky.sky_material.shader == EnvironmentAsset.sky.sky_material.shader, "existing sky material family")
	var tag := "minimal" if minimal else "legacy"
	var frame := await _capture(tag)
	mat.set_shader_parameter("reflection_strength", 0.0)
	var no_reflection := await _capture(tag + "-reflection-off")
	_ab(frame, no_reflection, tag + " reflection A/B")
	mat.set_shader_parameter("reflection_strength", original_reflection)
	mat.set_shader_parameter("u_time", 3.0)
	var next_wave := await _capture(tag + "-wave-next")
	_ab(frame, next_wave, tag + " wave phase A/B")
	mat.set_shader_parameter("u_time", 2.0)
	if mat.get_shader_parameter("shore_enabled"):
		mat.set_shader_parameter("contact_foam_strength", 0.0)
		var no_foam := await _capture(tag + "-contact-off")
		_ab(frame, no_foam, tag + " waterline foam A/B")
		mat.set_shader_parameter("contact_foam_strength", original_strength)
	else:
		print("[surface-visual] no shoreline atlas bound; contact A/B not executed")
	if minimal and OS.get_environment("SEA_EXPECT_VISUAL_CONTACTS") == "1":
		var atlas = ocean.shoreline
		_check(bool(mat.get_shader_parameter("shore_enabled")) and atlas != null and not atlas.segments.is_empty(), "visible solids seed the existing shoreline atlas")
		if atlas != null:
			# Samples on actual distinct contours, including the CSG apron and
			# a rotated timber; the atlas is not the physics collision layer.
			var deck: MeshInstance3D = scene.get_node("Deck/Visual")
			var apron: Marker3D = scene.get_node("Ramp/LowerJoin")
			var timber: MeshInstance3D = scene.get_node("TimberObstacles/TimberC/Visual")
			var p_deck := deck.to_global(Vector3(-deck.mesh.get_aabb().size.x * 0.5, 0, 0))
			var p_ramp := apron.to_global(Vector3(1.6, 0, 1.2))
			var p_timber := timber.to_global(Vector3(timber.mesh.get_aabb().size.x * 0.5, 0, 0))
			for sample: Vector3 in [p_deck, p_ramp, p_timber]:
				_check(atlas.distance_at(Vector2(sample.x, sample.z)) < 0.16, "visible waterline matches contour: %s" % sample)
		var count := int(mat.get_shader_parameter("boat_hull_count"))
		_check(count >= 3, "actual reused vessel hull outline is bound")
		mat.set_shader_parameter("boat_hull_count", 0)
		var no_hull := await _capture(tag + "-hull-off")
		_ab(frame, no_hull, tag + " hull contact A/B")
		mat.set_shader_parameter("boat_hull_count", count)
		_check(scene.has_node("HemisphereFill") and is_equal_approx(sun.light_energy, 0.54), "fixed authored legacy daylight")
	_check(is_zero_approx(original_crest), "base crest foam remains disabled")
	_check(not FileAccess.file_exists("user://save_slot_0.json") and not FileAccess.file_exists("user://water.cfg"), "no game save or water settings")
	_finish()
