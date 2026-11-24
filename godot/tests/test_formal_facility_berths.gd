extends SceneTree

const Transfer = preload("res://src/navigation/berth_transfer.gd")
var count := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	main._autosave_on = false
	var boat: Boat = main.boat
	var player: CharacterBody3D = main.player
	var state := root.get_node("GameState")
	var transfer := Transfer.new()
	for id in ["zone1", "zone2", "zone5", "sea_supply", "rooftop_ranch", "neon_garden_quarter", "rooftop_arcade"]:
		var zone: Node3D = main._zone_nodes[id]
		for berth: Node3D in zone.landing_points():
			var park := berth.get_node("BoatPark") as Marker3D
			boat.place_at(park.global_position, park.global_rotation.y)
			for frame in 4: await physics_frame
			var result := transfer.inspect(boat, player, berth, true, true)
			var key := str(id) + "/" + str(berth.landing_id)
			_check(result.has("point"), key + " " + str(result) + " stand " + str(berth.global_position) + " park " + str(park.global_position))
			if result.has("point"):
				# The live handoff is allowed during propulsion. The accepted action
				# itself stops and parks the hull, so the query must not require rest.
				boat.set_drive(Vector2(0.0, -1.0))
				await physics_frame
				var moving_result := transfer.inspect(boat, player, berth, true, false)
				_check(moving_result.has("point"), key + " accepts moving hull in trigger")
				boat.stop_drive()
				main.actor_controller.restore_pose({"mode": 0, "player": [result.point.x, result.point.y, result.point.z]})
				state.landing_id = berth.landing_id
				state.enter_zone(id)
				await physics_frame
				var boarding := transfer.inspect(boat, player, berth, false, true)
				_check(boarding.has("point"), key + " boards " + str(boarding) + " " + str(player.global_position) + " " + str(result.point))
				main.actor_controller.restore_pose({"mode": 1})
			boat.place_at(park.global_position + Vector3(0, 0, 20), park.global_rotation.y)
			for frame in 3: await physics_frame
			_check(not transfer.hull_at_berth(boat, berth), key + " rejects distant hull")
	var fishery: Node3D = main._fishery_visual
	fishery.apply_upgrade(true)
	var salvage: Node3D = main._zone_nodes.zone1.landing_point("salvage")
	var fishery_park := salvage.get_node("BoatPark") as Marker3D
	boat.place_at(fishery_park.global_position, fishery_park.global_rotation.y)
	for frame in 4: await physics_frame
	var fishery_result := transfer.inspect(boat, player, salvage, true, true)
	_check(fishery_result.has("point"), "upgraded fishery landing " + str(fishery_result))
	for id in ["floating_rest_stop", "water_building_001", "water_building_002"]:
		var site := main.get_node("World/SeaStructures/" + id) as Node3D
		_check(_sweep_decorative_hull(boat, site), id + " stops a boat hull sweep at its placed position")
	main.set_physics_process(false)
	await _check_open_water_turn(boat)
	await _check_wall_release(main, boat)
	current_scene = null
	root.remove_child(main)
	main.free()
	print("[formal-facility-berths] %d checks, %d failures" % [count, failures])
	quit(0 if failures == 0 else 1)

func _check_open_water_turn(boat: Boat) -> void:
	var origin := Vector3(1000.0, boat.WATER_LEVEL, 1000.0)
	for degrees in [90.0, 180.0]:
		boat.place_at(origin, 0.0)
		var target := Vector2.RIGHT.rotated(deg_to_rad(degrees - 90.0))
		boat.set_drive(target)
		var frames := 0
		while frames < 160:
			var bow := -boat.global_basis.z
			if Vector2(bow.x, bow.z).dot(target) >= cos(deg_to_rad(12.0)):
				break
			await physics_frame
			frames += 1
		print("[open-turn] degrees=", degrees, " seconds=", frames / float(Engine.physics_ticks_per_second))
		_check(frames <= (56 if degrees == 90.0 else 102), "open-water heading responds promptly from rest")

func _check_wall_release(main: Node3D, boat: Boat) -> void:
	var origin := Vector3(1000.0, boat.WATER_LEVEL, 1000.0)
	var wall := _wall(main, origin + Vector3(-0.25, 0, 0), Vector3(0.5, 4, 18))
	boat.place_at(origin + Vector3(1.61, 0, 0), 0.0)
	await physics_frame
	var start := boat.global_position
	boat.set_drive(Vector2(-1, -1), true)
	var clear := true
	for frame in 70:
		await physics_frame
		clear = clear and boat.hull_clear()
	print("[wall-release] slide=", boat.global_position - start, " yaw=", boat.global_rotation.y, " clear=", clear)
	_check(clear and start.z - boat.global_position.z > 0.6, "a blocked turn slides along the wall with the original steering input")
	_check(absf(boat.global_rotation.y) < 0.45, "sliding keeps the hull roughly parallel to the wall")

	_wall(main, origin + Vector3(4, 0, -3.41), Vector3(8, 4, 0.5))
	boat.place_at(origin + Vector3(1.61, 0, 0), 0.0)
	await physics_frame
	start = boat.global_position
	boat.set_drive(Vector2.DOWN)
	for frame in 210:
		await physics_frame
		clear = clear and boat.hull_clear()
	print("[wall-release] reverse=", boat.global_position - start, " yaw=", boat.global_rotation.y, " clear=", clear)
	_check(clear and boat.global_position.z > start.z + 1.0, "the hull backs out of a corner while its turn is blocked")
	boat.set_drive(Vector2.RIGHT)
	for frame in 150:
		await physics_frame
		clear = clear and boat.hull_clear()
	print("[wall-release] exit=", boat.global_position - start, " yaw=", boat.global_rotation.y, " clear=", clear)
	_check(clear and boat.global_position.x > start.x + 1.5 and -boat.global_basis.z.dot(Vector3.RIGHT) > 0.9,
		"the boat regains steering after clearing the corner")
	boat.place_at(origin + Vector3(1.61, 0, 0), 0.0)
	await physics_frame
	start = boat.global_position
	boat.set_drive(Vector2.UP)
	for frame in 74:
		await physics_frame
	_check(boat.hull_clear() and absf(boat.global_position.x - start.x) < 0.015 and boat.global_position.z > start.z - 0.07,
		"holding directly into the corner neither pushes through nor drifts sideways")
	wall.queue_free()

func _wall(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4096
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	body.global_position = at
	return body

func _sweep_decorative_hull(boat: Boat, site: Node3D) -> bool:
	var collider := site.get_node("HullCollision")
	var center := Vector3(site.global_position.x, boat.WATER_LEVEL, site.global_position.z)
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var side: Vector3 = direction.cross(Vector3.UP)
		var yaw := atan2(-direction.x, -direction.z)
		for offset in [0.0, -3.0, 3.0, -6.0, 6.0]:
			var pose := Transform3D(Basis(Vector3.UP, yaw), center + side * offset - direction * 25.0)
			if not boat.hull_clear_at(pose):
				continue
			var contact := KinematicCollision3D.new()
			if boat.test_move(pose, direction * 28.0, contact) and contact.get_collider() == collider:
				return true
	return false

func _check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
