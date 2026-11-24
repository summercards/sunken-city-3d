extends SceneTree

const NON_SOLID := ["planter", "planter_small", "flag", "wind_chime"]
const INTERACTIVE := ["planter", "planter_small", "storage_crate", "water_barrel"]

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(result: bool, message: String) -> void:
	checks += 1
	if not result:
		failures += 1
		printerr("FAIL ", message)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main._title_active = false
	main.set_process(false)
	await process_frame
	var service = main.building
	var world = main.building_world
	var rows := []
	for kind: String in service.catalog():
		var index := rows.size()
		rows.append({"id":"audit_" + kind, "kind":kind, "left":1.0, "turn":index % 4,
			"support":"", "x":0, "z":0, "positioned":kind == "deck",
			"px":60.0 + float(index % 7)*8, "pz":40.0 + floorf(index/7.0)*8,
			"py":2.8 if kind == "upper_floor" else 0.0})
	# The full catalog can be inspected independently of legal build-site fixtures.
	service.set("_rows", rows)
	world.sync()
	check(rows.size() == 36, "entire catalog covered")
	for row: Dictionary in rows:
		var preview: Node3D = world.node_for(row.id)
		check(not preview.has_node("Construction") and not preview.has_node("InteractionTrigger"), row.kind + " construction ghost")
		for body: StaticBody3D in preview.find_children("*", "StaticBody3D", true, false):
			check(body.collision_layer == 0, row.kind + " ghost has no blocking layer")

	service.tick(2.0)
	var targets := {}
	for row: Dictionary in rows:
		var component: Node3D = world.node_for(row.id)
		var label: String = row.kind
		var bodies := component.find_children("*", "StaticBody3D", true, false)
		check(bodies.is_empty() == (label in NON_SOLID), label + " local collision policy")
		check(component.has_node("InteractionTrigger") == (label in INTERACTIVE), label + " interaction ownership")
		var overlay := component.get_node_or_null("Construction")
		check(overlay != null, label + " starts from completion event")
		if overlay == null:
			continue
		var player: AnimationPlayer = overlay.get_node("AnimationPlayer")
		var clip := player.get_animation(&"construction")
		var parts := overlay.get_child_count() - 1
		print("[construction-component] %s %d %.3f" % [label, parts, clip.length])
		# Every renderable from the model and independent rotor has a track.
		var expected := component.get_node("Model").find_children("*", "MeshInstance3D", true, false).size()
		var rotor := component.get_node_or_null("Rotor")
		if rotor != null: expected += rotor.find_children("*", "MeshInstance3D", true, false).size()
		check(parts > 0 and parts == expected and clip.get_track_count() == parts * 3, label + " tracks cover all elements")
		if label == "stairs_5m":
			check(parts == 30, "27 treads plus three supports are separable")
			for i in 3:
				var part: MeshInstance3D = overlay.get_child(i).get_child(0)
				check("StairSupport" in part.mesh.resource_name, "stair support precedes treads")
		if label == "platform_5x5": check(parts == 9, "six planks plus three supports are separable")
		if label == "lamp_post":
			for i in 2:
				var part: MeshInstance3D = overlay.get_child(i).get_child(0)
				check(String(part.name).begins_with(["foot", "post"][i]), "lamp foot and pole precede lamp head")
		var previous_start := -1.0
		for i in parts:
			var visibility := i * 3
			var position := visibility + 1
			var scale_track := visibility + 2
			var start := clip.track_get_key_time(position, 0)
			var high: Vector3 = clip.track_get_key_value(position, 0)
			var low: Vector3 = clip.track_get_key_value(position, 2)
			check(start > previous_start, label + " ordered elements")
			check(high.y > low.y and is_equal_approx(high.x,low.x) and is_equal_approx(high.z,low.z), label + " vertical approach")
			check((clip.track_get_key_value(scale_track, 2) as Vector3).x > 1.0 and
				clip.track_get_key_value(scale_track, 4) == Vector3.ONE, label + " overshoot and exact settle")
			previous_start = start
		targets[label] = player
		player.pause()

	await physics_frame
	var floor_piece: Node3D = world.node_for("audit_upper_floor")
	for x in [-0.75,0.0,0.75]:
		check(hit(floor_piece, Vector3(x,.3,0), Vector3(x,-.3,0)), "legacy floor has continuous support")
	var mill: Node3D = world.node_for("audit_windmill")
	check(hit(mill, Vector3(0,.5,1), Vector3(0,.5,-1)), "windmill pole blocks")
	var frame: Node3D = world.node_for("audit_door_frame_5m")
	check(not hit(frame, Vector3(0,1,1), Vector3(0,1,-1)), "door opening stays clear")
	check(hit(frame, Vector3(1.6,1,1), Vector3(1.6,1,-1)), "door wall stays solid")
	if DisplayServer.get_name() != "headless":
		await capture(world.node_for("audit_lamp_post"), targets["lamp_post"], "lamp", 4.9, 1.8)
		await capture(world.node_for("audit_stairs_5m"), targets["stairs_5m"], "stairs", 9.5, 3.1)
	for player: AnimationPlayer in targets.values():
		var clip := player.get_animation(&"construction")
		player.seek(clip.length, true)
		for i in clip.get_track_count() / 3:
			var target: Node3D = player.get_parent().get_child(i)
			check(target.visible and target.position.is_equal_approx(clip.track_get_key_value(i * 3 + 1, 2))
				and target.scale.is_equal_approx(Vector3.ONE), "final overlay matches settled position and scale")
		player.play(&"construction")
		player.seek(clip.length - .001, true)
		player.advance(.01)
	await process_frame
	for row: Dictionary in rows:
		var component: Node3D = world.node_for(row.id)
		check(not component.has_node("Construction") and component.get_node("Model").is_visible_in_tree(), row.kind + " final model restored")
	world.reset_projection()
	world.sync()
	for row: Dictionary in rows:
		check(not world.node_for(row.id).has_node("Construction"), row.kind + " completed layout does not replay")
	main.queue_free()
	await process_frame
	print("[building-construction] %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func hit(component: Node3D, from: Vector3, to: Vector3) -> bool:
	var request := PhysicsRayQueryParameters3D.create(component.to_global(from), component.to_global(to), 8192)
	var result := root.world_3d.direct_space_state.intersect_ray(request)
	return result.has("collider") and component.is_ancestor_of(result.collider)

func capture(component: Node3D, player: AnimationPlayer, label: String, framing: float, focus_y: float) -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(720, 720)
	stage.own_world_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var parent := component.get_parent()
	var pose := component.transform
	component.reparent(stage, false)
	component.position = Vector3.ZERO
	component.rotation.y = 0.0

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#c9d7d8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e2eaf3")
	environment.ambient_light_energy = 0.75
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	camera.environment = environment
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = framing
	var target := Vector3.UP * focus_y
	camera.position = target + Vector3(6.0, 3.0, 5.0)
	camera.look_at(target)
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#a1b3ac")
	ground.material_override = material
	ground.position.y = -0.025
	stage.add_child(ground)

	var clip := player.get_animation(&"construction")
	var timing := [0.16, clip.length * 0.48, clip.length * 0.71, clip.length]
	for i in timing.size():
		player.seek(timing[i], true)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := stage.get_texture().get_image()
		check(image.save_png("res://outputs/construction-%s-%d.png" % [label, i]) == OK, label + " real render %d" % i)
	component.reparent(parent, false)
	component.transform = pose
	stage.queue_free()
