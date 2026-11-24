extends SceneTree

const SURFACE_PATH := "World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海上区域"
const DATA := "res://assets/models/facilities/solar_cabin/v1_6"
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main._title_active = false
	await process_frame
	var surface: Node3D = main.get_node(SURFACE_PATH)
	var player: AnimationPlayer = surface.get_node("BuildingAnimation")
	var parts := surface.find_children("ConstructionPose", "Node3D", true, false)
	check(surface.scale.is_equal_approx(Vector3.ONE), "unit surface root")
	check(not player.is_playing(), "construction never autoplays")
	check(parts.size() == 127, "one visual track target per building part")
	var collision := surface.get_node("SurfaceCollision")
	var collision_pose: Transform3D = collision.global_transform
	var animation := player.get_animation(&"construction")
	var flora := surface.find_children("*", "MultiMeshInstance3D", true, false).filter(
		func(visual): return visual.get_meta("category", "") == "flora")
	check(flora.size() == 56 and animation.get_track_count() == parts.size() * 2 + 2 + flora.size(),
		"position, part visibility and accessory visibility tracks")
	check(is_equal_approx(animation.length, 224.0 / 30), "source frame range and rate")
	var origins: Dictionary[Node3D, Transform3D] = {}
	for part: Node3D in parts:
		origins[part] = part.global_transform
		check(part.visible and part.position.is_zero_approx(), "assembled by default")

	var exports: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA + "/export_manifest.json"))
	for record: Dictionary in exports.components.values():
		var component: PackedScene = load(str(record.prefab).replace("godot/", "res://"))
		var item := component.instantiate()
		root.add_child(item)
		var meshes := item.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), "standalone component renders")
		for mesh: MeshInstance3D in meshes:
			for i in mesh.mesh.get_surface_count():
				var material := mesh.get_surface_override_material(i) as ShaderMaterial
				check(material != null and material.get_shader_parameter("palette").resource_path == PALETTE,
					"component has the original shared palette")
		item.free()

	var umbrella := surface.find_child("umbrella_*", true, false)
	var wind := umbrella.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var fabric := umbrella.find_child("umbrella_fabric*", true, false) as MeshInstance3D
	var pole := umbrella.find_child("umbrella_static*", true, false) as MeshInstance3D
	check(wind.is_playing() and wind.current_animation == "wind", "wind autoplays")
	check(wind.get_animation(&"wind").loop_mode == Animation.LOOP_LINEAR, "wind loops")
	check(absf(wind.get_animation(&"wind").length - 4.0) < 0.035, "wind duration follows Blender")
	check(fabric.get_blend_shape_count() == 2 and pole.get_blend_shape_count() == 0, "only umbrella fabric deforms")
	var pole_pose := pole.transform
	wind.seek(0.0, true)
	var calm := fabric.get_blend_shape_value(0)
	wind.seek(31.0 / 30, true)
	check(fabric.get_blend_shape_value(0) > calm + 0.7, "wind samples the authored gust")
	check(pole.transform.is_equal_approx(pole_pose), "pole stays still in the gust")

	surface.play_construction()
	check(player.is_playing(), "explicit playback starts the clip")
	check(parts.all(func(part): return not part.visible), "first frame waits for the drop")
	var turf := surface.get_node("VegetationTurf") as Node3D
	var damage := surface.find_child("SunroomDamage", true, false) as Node3D
	check(not turf.visible and not damage.is_visible_in_tree() and flora.all(func(visual): return not visual.visible),
		"attached details wait for their support")
	player.seek(128.0 / 30, true)
	var raised := 0
	for part: Node3D in parts:
		check(is_zero_approx(part.position.x) and is_zero_approx(part.position.z), "vertical drop")
		if part.visible and part.position.y > 0.4:
			raised += 1
	check(raised > 0, "middle frame has components visibly in flight")
	check(not turf.visible and damage.get_parent().position.y > 0.1, "grass waits and damage follows the ladder")
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		player.pause()
		main.hud.hide()
		main.markers.hide()
		main.cam.suspend_follow()
		main.cam.target = surface.to_global(Vector3(5.3, 8.2, 5.1))
		main.cam.distance = 46.0
		main.cam.orbit_dir = Vector3(-.63,.63,.9)
		main.cam.refresh()
		await shot("construction")
	surface.finish_construction()
	check(not player.is_playing(), "finish settles without restarting")
	check(collision.global_transform.is_equal_approx(collision_pose), "collision is outside the animation")
	check(turf.visible and damage.is_visible_in_tree(), "ready state restores the original grass and damage")
	check(flora.all(func(visual): return visual.visible), "animation restores flora beneath the stage-controlled anchors")
	for part: Node3D in parts:
		check(part.visible and part.global_transform.is_equal_approx(origins[part]), "final pose matches default")
	if visual:
		main.cam.target = surface.to_global(Vector3(5.3, 5.8, 5.1))
		main.cam.distance = 39.0
		main.cam.refresh()
		await shot("complete")
		main.cam.set_process(false)
		main.cam.pose_lock = true
		main.cam.target = surface.to_global(Vector3(1.9, 7.7, 2.55))
		main.cam.distance = 10.0
		main.cam.orbit_dir = surface.global_basis * Vector3(-0.6, 0.45, 1.0)
		main.cam.refresh()
		await shot("upper-railing")
	main.queue_free()
	await process_frame
	print("[sunroom-animation] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func shot(label: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	check(img != null and img.get_width() > 200, "real rendered frame")
	img.save_png("res://outputs/sunroom-1-6-" + label + ".png")
