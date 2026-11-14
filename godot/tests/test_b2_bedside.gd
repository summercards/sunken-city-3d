extends SceneTree
## B2 G07：独立验证默认床、四朝向合法矩阵、真实胶囊净空及到门物理路线。
const BodyScale = preload("res://src/avatar/avatar_dimensions.gd")
const RoomService = preload("res://src/room/room_service.gd")
var checks := 0
var failures := 0
var main
var room
var service
var physical_layouts := 0
var walked_routes := 0
var approached_routes := 0
var detoured_routes := 0
var messages: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _world_point(local: Vector2) -> Vector3:
	return room.to_global(Vector3(local.x, 0.0, local.y))

func _physical_clear(local: Vector2) -> bool:
	var collision: CollisionShape3D = main.player.get_node("BodyCollision")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = Transform3D(Basis.IDENTITY, _world_point(local) + Vector3.UP * (BodyScale.BODY_HEIGHT * 0.5 + 0.004))
	query.collision_mask = 256
	query.exclude = [main.player.get_rid()]
	return room.get_world_3d().direct_space_state.intersect_shape(query, 32).is_empty()

func _walk_route(route: Array) -> bool:
	var first: Vector3 = room.to_global(route[0])
	main.actor_controller.restore_pose({"mode": 0, "player": [first.x, first.y, first.z]})
	for local: Vector3 in route:
		var target: Vector3 = room.to_global(local)
		for step in 300:
			var offset: Vector3 = target - main.player.global_position
			offset.y = 0.0
			if offset.length() < 0.008:
				break
			var before: Vector3 = main.player.global_position
			main.player.move_ground(offset.limit_length(0.04), 1.0 / 60.0)
			if before.distance_to(main.player.global_position) < 0.00001:
				return false
		if Vector2(target.x - main.player.global_position.x, target.z - main.player.global_position.z).length() > 0.02:
			return false
	walked_routes += 1
	return main.player.global_position.distance_to(room.entry_position()) < 0.04

## 独立细采样，不用候选到门路线或生产净空判定替代真实接近证据。
func _route_clear(route: Array) -> bool:
	var radius: float = BodyScale.BODY_RADIUS / room.uniform_scale()
	for index in range(1, route.size()):
		var from: Vector3 = room.to_local(route[index - 1])
		var to: Vector3 = room.to_local(route[index])
		var samples := maxi(1, ceili(from.distance_to(to) / 0.01))
		for sample in range(samples + 1):
			var at := from.lerp(to, float(sample) / samples)
			var point := Vector2(at.x, at.z)
			var local: Vector2 = (point - Vector2(service.bed_position.x, service.bed_position.z)).rotated(service.bed_yaw)
			var nearest := Vector2(clampf(local.x, -0.58, 0.58), clampf(local.y, -1.015, 1.015))
			if local.distance_to(nearest) < radius:
				return false
			for item in RoomService.FIXED_FOOTPRINTS:
				if item.name == "门口通道": continue
				var footprint := Rect2(item.center - item.half, item.half * 2.0)
				if footprint.grow(radius).has_point(point): return false
	return true

func _approach(target: Node3D, start: Vector2, label: String, expect_detour := false) -> void:
	var controller = main.actor_controller
	var at := _world_point(start)
	controller.restore_pose({"mode": 0, "player": [at.x, at.y, at.z]})
	messages.clear()
	check(_physical_clear(start), label + " 实际角色起点净空")
	var accepted: bool = controller.approach(target)
	check(accepted and controller.state_id() == "approaching", label + " 正式 ActorController.approach 进入 Approaching")
	if not accepted: return
	var goal: Vector3 = controller.walk_target
	var route: Array = controller.walk_path.duplicate()
	route.push_front(main.player.global_position)
	check(_route_clear(route), label + " 实际起点到候选全段胶囊净空")
	if expect_detour:
		check(not _route_clear([at, goal]), label + " 直线反例确实擦床角或穿床")
		check(route.size() > 2, label + " 正式流程保留绕床航点")
		detoured_routes += 1
	var clear := true
	for step in 1800:
		if controller.state_id() != "approaching": break
		controller.tick(1.0 / 60.0)
		var local: Vector3 = room.to_local(main.player.global_position)
		clear = clear and _physical_clear(Vector2(local.x, local.z))
	check(controller.state_id() == "interacting", label + " 真实运动完成并进入 Interacting，不取消或卡住")
	check(main.player.global_position.distance_to(goal) < 0.025, label + " 到达候选而非床中心或前厅")
	check(clear and messages.all(func(text: String): return text.begins_with("前往 · ")), label + " 行走全程无碰撞穿床和阻挡反馈")
	check(controller.auto_target == target and main.interactor.preferred_target == target, label + " 保留正式交互目标")
	if controller.state_id() == "interacting": approached_routes += 1
	controller.cancel()

func _verify_approaches() -> void:
	for yaw in [0.0, PI / 2.0, PI, -PI / 2.0, PI / 4.0, -PI / 4.0]:
		check(service.place_bed(Vector3.ZERO, yaw).ok, "正式接近布局合法")
		room.apply_layout()
		await physics_frame
		await physics_frame
		var candidates: Array = service.bedside_candidates()
		for side in [-1.0, 1.0]:
			var start := Vector2(side, -1.0).rotated(-yaw)
			_approach(room.bed, start, "最近候选 yaw=%s side=%s" % [yaw, side], yaw == 0.0 and side == 1.0)
			if yaw == 0.0 and side == 1.0:
				check(room.to_local(main.actor_controller.walk_target).distance_to(Vector3(0.15, 0.0, -1.211667)) < 0.00001,
					"指定反例仍选择最近床头候选，不靠换候选掩盖擦角")
			# 限定对侧候选，强制覆盖左右两侧出发绕床，不准只挑同侧直走。
			var opposite: Dictionary = candidates[1 if side > 0 else 0]
			room.bed.set_approach_points([_world_point(opposite.point)])
			_approach(room.bed, start, "对侧候选 yaw=%s side=%s" % [yaw, side], true)
			main.room_controller._refresh_bedside_points()
	# 通用 Interactable 不实现新端口：有/无旧 approach_points 两条原流程都要可走。
	var generic = preload("res://src/interaction/interactable.gd").new()
	generic.label = "通用交互回归"
	generic.focus_anchor = "node"
	generic.auto_radius = false
	generic.focus_radius = 1.0
	room.add_child(generic)
	generic.global_position = _world_point(Vector2(1.0, 1.7))
	check(not generic.has_method("approach_path"), "通用 Interactable 不被迫实现新端口")
	_approach(generic, Vector2(-1.0, 1.7), "通用无候选端口")
	generic.set_meta("approach_points", [_world_point(Vector2(0.0, 1.7))])
	_approach(generic, Vector2(-1.0, 1.7), "通用旧候选元数据")
	generic.free()

func _verify_layout(label: String) -> void:
	await physics_frame
	await physics_frame
	var candidates: Array = service.bedside_candidates()
	check(not candidates.is_empty(), label + " 有安全候选")
	if candidates.is_empty():
		return
	physical_layouts += 1
	var center: Vector2 = Vector2(service.bed_position.x, service.bed_position.z)
	check(not _physical_clear(center), label + " 反例：床中心确实被启用碰撞挡住")
	for candidate: Dictionary in candidates:
		check(_physical_clear(candidate.point), label + " " + candidate.side + " 真实胶囊净空")
		var direction := Vector3(sin(float(candidate.yaw)), 0.0, cos(float(candidate.yaw)))
		var toward: Vector3 = service.bed_position - Vector3(candidate.point.x, 0.0, candidate.point.y)
		check(direction.dot(toward.normalized()) > 0.999, label + " 面向床")
	check(_walk_route(candidates[0].route), label + " 真实 Actor.move_ground 沿净空路线到前厅")
	main.room_controller.wake_in_room()
	check(main.player.global_position.distance_to(room.wake_position()) < 0.001, label + " 正式起床接线一致")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.interactor.set_process(false)
	root.get_node("Economy").set_process(false)
	main.cam.set_process(false)
	await process_frame
	room = main.room
	service = main.room_service
	main.room_controller.enter(true)
	await physics_frame
	await physics_frame
	check(room.is_active(), "物理证据前房间已激活")
	check(room.bed.body.collision_layer == 256, "床碰撞层真实启用")
	var capsule: CapsuleShape3D = main.player.get_node("BodyCollision").shape
	check(is_equal_approx(capsule.radius, BodyScale.BODY_RADIUS), "真实 Actor 半径取自 BodyScale")
	check(is_equal_approx(capsule.height, BodyScale.BODY_HEIGHT), "真实 Actor 高度取自 BodyScale")
	check(is_equal_approx(service.body_radius_local() * room.uniform_scale(), capsule.radius), "局部/世界半径一致")
	main.actor_controller.ports.notify = func(text: String): messages.append(text)
	await _verify_layout("默认床")
	await _verify_approaches()
	var legal := 0
	var rejected := 0
	for yaw in [0.0, PI / 2.0, PI, -PI / 2.0]:
		var limits: Rect2 = service.bed_limits(yaw)
		var xs: Array = [limits.position.x, limits.end.x]
		var zs: Array = [limits.position.y, limits.end.y]
		for value in range(-4, 5):
			var coordinate := float(value) * 0.5
			if coordinate > limits.position.x and coordinate < limits.end.x:
				xs.append(coordinate)
			if coordinate > limits.position.y and coordinate < limits.end.y:
				zs.append(coordinate)
		var count := 0
		for x: float in xs:
			for z: float in zs:
				var snapshot: Dictionary = service.to_dict()
				snapshot.bed = {"position": [x, 0.0, z], "yaw": yaw}
				if service.validate_snapshot(snapshot) != "":
					continue
				legal += 1
				count += 1
				var before: Dictionary = service.to_dict()
				var placed: Dictionary = service.place_bed(Vector3(x, 0.0, z), yaw)
				if not placed.ok:
					rejected += 1
					check(service.to_dict() == before and placed.has("reason"), "无安全点拒绝且不改现场")
					continue
				check(service.bed_position == Vector3(x, 0.0, z), "合法边界不改摆床坐标")
				await _verify_layout("矩阵 yaw=%s x=%s z=%s" % [yaw, x, z])
		check(count > 0, "四朝向矩阵存在合法布局")
	# 非正交角度校准 Godot 的 +Y 旋转在 XZ 投影中的符号。
	for yaw in [PI / 4.0, -PI / 4.0]:
		check(service.place_bed(Vector3.ZERO, yaw).ok, "斜向布局合法")
		await _verify_layout("斜向 %s" % yaw)
	# 旧档不因运行时路线查询失效被拒绝，不改布局，恢复前厅安全点。
	var prior: Dictionary = service.to_dict()
	service.route_query = func(_start: Vector2, _goal: Vector2): return []
	check(service.validate_snapshot(prior) == "", "旧档校验不新增路线条件")
	service.from_dict(prior)
	check(service.to_dict() == prior, "恢复不修改既有床布局")
	check(service.bedside_point() == Vector3(0.0, 0.0, 3.25), "无床边候选明确恢复前厅入口")
	check(_physical_clear(Vector2(0.0, 3.25)), "恢复入口真实胶囊净空")
	main.room_controller.wake_in_room()
	check(main.player.global_position.distance_to(room.entry_position()) < 0.001, "无安全候选旧档走正式起床流程回退前厅")
	check(not main.actor_controller.approach(room.bed), "无安全候选不退回普通穿床求路")
	check(not service.place_bed(Vector3.ZERO, 0.0).ok and service.to_dict() == prior, "无路线布局拒绝且不改状态")
	print("[b2-bedside-evidence] legal=%d rejected=%d physical_layouts=%d walked_routes=%d approached_routes=%d detoured_routes=%d" % [legal, rejected, physical_layouts, walked_routes, approached_routes, detoured_routes])
	print("[b2-bedside] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
