extends SceneTree

const ASSEMBLY := "res://scenes/facilities/water_building_002.tscn"
const OUTPUT_PREFIX := "res://outputs/water-building-002-"

var checks := 0
var failures := 0
var main: Node
var assembly: Node3D
var evidence := {
	"scene": "res://scenes/main.tscn",
	"assembly": ASSEMBLY,
	"frames": [],
	"daylight_hour": 12.0,
	"hud_disabled": true,
	"main_camera_used": true,
	"ticks_disabled": true,
	"fit_margin": 1.25,
}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for visual in node.find_children("*", "GeometryInstance3D", true, false):
		if visual is MeshInstance3D:
			var mesh := visual as MeshInstance3D
			if mesh.mesh == null:
				continue
			var part: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			result = part if first else result.merge(part)
			first = false
		elif visual is MultiMeshInstance3D:
			var multi := visual as MultiMeshInstance3D
			if multi.multimesh == null or multi.multimesh.mesh == null:
				continue
			for index in multi.multimesh.instance_count:
				var transform: Transform3D = multi.global_transform * multi.multimesh.get_instance_transform(index)
				var part: AABB = transform * multi.multimesh.mesh.get_aabb()
				result = part if first else result.merge(part)
				first = false
	return result

func union_bounds(a: AABB, b: AABB) -> AABB:
	if a.size == Vector3.ZERO:
		return b
	if b.size == Vector3.ZERO:
		return a
	return a.merge(b)

func fit_distance(box: AABB, fov_degrees: float) -> float:
	var half_angle := deg_to_rad(fov_degrees * 0.5)
	var radius := maxf(maxf(box.size.x, box.size.y), box.size.z) * 0.5
	return maxf(radius / tan(half_angle) * 1.25, 12.0)

func frame(eye: Vector3, target: Vector3, fov_degrees: float) -> void:
	main.cam.fov = fov_degrees
	main.cam.near = 0.1
	main.cam.far = 800.0
	main.cam.global_position = eye
	main.cam.look_at(target, Vector3.UP)
	main.cam.make_current()

func shot(name: String, eye: Vector3, target: Vector3, fov_degrees: float) -> void:
	frame(eye, target, fov_degrees)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and image.get_width() >= 1280 and image.get_height() >= 720, "real renderer frame " + name)
	if image != null:
		check(image.save_png(OUTPUT_PREFIX + name + ".png") == OK, "saved frame " + name)
	evidence.frames.append(name)

func configure_main() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.cam.suspend_follow()
	main.boat.set_process(false)
	main.hud.hide()
	if main.markers != null:
		main.markers.hide()
	if main.ribbon != null:
		main.ribbon.hide()
	if main._calendar_label != null:
		main._calendar_label.hide()
	var economy := root.get_node_or_null("Economy")
	if economy != null:
		economy.set("ticking", false)
	if main.world_clock != null:
		main.world_clock.paused = true
	if main.weather_service != null:
		main.weather_service.paused = true
	main.daylight_rig.apply(12.0)
	for i in 12:
		await process_frame

func attach_assembly() -> void:
	assembly = main.get_node_or_null("World/SeaStructures/water_building_002") as Node3D
	check(assembly != null, "002 is serialized in production main, not injected by test")
	for i in 8:
		await process_frame

func run() -> void:
	await configure_main()
	await attach_assembly()
	check(assembly != null, "water building is present in isolated real main runner")
	if assembly == null:
		print("[water-building-002-render] ", checks, " checks, ", failures, " failures")
		quit(1)
		return
	var building_box := bounds(assembly)
	check(building_box.size != Vector3.ZERO, "building has measured rendered bounds")
	var building_center := building_box.get_center()
	var hero_distance := fit_distance(building_box, 43.0)
	await shot("hero", building_center + Vector3(hero_distance * 0.78, hero_distance * 0.52, hero_distance * 0.78), building_center, 43.0)
	await shot("back", building_center + Vector3(-hero_distance * 0.78, hero_distance * 0.48, -hero_distance * 0.78), building_center, 43.0)
	var roof_target := building_center + Vector3(0.0, building_box.size.y * 0.10, 0.0)
	var roof_distance := fit_distance(building_box, 48.0)
	await shot("roof", roof_target + Vector3(0.0, roof_distance * 1.45, roof_distance * 0.12), roof_target, 48.0)
	var context := main.get_node_or_null("World/SeaStructures/floating_shop") as Node3D
	var context_box := building_box
	if context != null:
		context_box = union_bounds(building_box, bounds(context))
	var context_center := context_box.get_center()
	var context_distance := fit_distance(context_box, 46.0)
	await shot("shop-context", context_center + Vector3(context_distance * 0.82, context_distance * 0.44, context_distance * 0.82), context_center, 46.0)
	evidence.bounds = {
		"position": building_box.position,
		"size": building_box.size,
		"center": building_center,
	}
	evidence.context = {"floating_shop_present": context != null, "bounds": context_box}
	var file := FileAccess.open("res://outputs/water-building-002-evidence.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "  "))
		file.close()
		check(true, "evidence JSON saved")
	else:
		check(false, "evidence JSON opened")
	print("[water-building-002-render] ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
