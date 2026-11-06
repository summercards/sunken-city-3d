extends SceneTree
## 正式 Main 集成验收；必须经统一 runner 的隔离工程运行，不接触玩家槽位。
## runner 负责 Autoload 前 user:// 隔离；本脚本沿 surfaces 模式关闭自动推进后显式 tick。
## 注册入口：tests/test_building_5m_experience.gd；成功标记见 finish()。
const Catalog = preload("res://src/building/building_catalog.gd")
const Assembly = preload("res://src/building/assembly_rules.gd")
const Service = preload("res://src/building/building_service.gd")
const Save = preload("res://src/save/save_game.gd")
const H := 5.086335
const DT := 1.0 / 60.0
const NEW_KINDS := ["platform_5x5", "wall_5m", "window_wall_5m", "door_frame_5m", "post_5m", "beam_5m", "railing_5m", "stairs_5m", "roof_slope_5x5", "roof_flat_5x5"]
var checks := 0
var failures := 0
var main: Node
var econ: Node
var editor: Node
var zone: Node
var parallel: Dictionary = {}
var serial: Dictionary = {}
var legacy_board := ""
var legacy_upper := ""
var crop_id := ""
var crop_before: Dictionary = {}
var save_path := ""
var walk_samples: Array[Vector3] = []
var completed_stages: Array[String] = []
const REQUIRED_STAGES := ["catalog", "all_ten", "seams", "parallel_mouse", "parallel_walks", "serial", "directions", "business", "demolition", "save"]

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = "") -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [building-5m-experience] ", label, " | ", str(detail))
	return ok

func equivalent(a: Variant, b: Variant) -> bool:
	# JSON数字统一读成float；数值容差不放宽坐标，避免int/float类型造成假失败。
	if (a is int or a is float) and (b is int or b is float): return absf(float(a) - float(b)) < 0.000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for field in a:
			if not b.has(field) or not equivalent(a[field], b[field]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equivalent(a[i], b[i]): return false
		return true
	return a == b

func world(point: Vector3) -> Vector3:
	return Catalog.ORIGIN + point

func rotated(origin: Vector2, offset: Vector2, turn: int, height: float = 0.0) -> Vector3:
	var at := origin + offset.rotated(-float(turn) * PI / 2.0)
	return world(Vector3(at.x, height, at.y))

func afloat() -> void:
	editor.close()
	main.actor_controller.restore_pose({"mode":1})

func restore_start(point: Vector3) -> void:
	main.actor_controller.restore_pose({"mode":0, "player":[point.x, point.y, point.z]})

func build_request(request: Dictionary) -> String:
	econ.energy.refill()
	var result: Dictionary = main.building.begin(request)
	if not check(bool(result.get("ok", false)), "正式 Service.begin 开工", {"request":request, "result":result, "wood":econ.count("wood")}):
		return ""
	var id := str(result.get("id", ""))
	main.building.tick(30.0)
	var row: Dictionary = main.building.row(id)
	if not check(not row.is_empty() and float(row.get("left", -1.0)) == 0.0, "正式施工完成 " + id, row):
		return ""
	if not check(is_instance_valid(main.building_world.node_for(id)), "World 完工投影 " + id, row):
		return ""
	return id

func build(kind: String, x: float, z: float, height: float = 0.0, turn: int = 0) -> String:
	var request: Dictionary = {"kind":kind, "px":x, "pz":z, "py":height, "turn":turn, "support":"", "origin":"boat"}
	if kind == "deck": request.positioned = true
	var supports: Array = Assembly.support_ids(request, main.building.query())
	if not Catalog.is_platform(kind) and not supports.is_empty(): request.support = supports[0]
	return build_request(request)

func build_at(kind: String, point: Vector3, turn: int = 0) -> String:
	var local := point - Catalog.ORIGIN
	return build(kind, local.x, local.z, local.y, turn)

func mesh_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var box: AABB = (node.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		result = result.merge(box) if initialized else box
		initialized = true
	return result

func check_dimensions(node: Node3D, kind: String, label: String) -> void:
	var box := mesh_bounds(node)
	var definition: Dictionary = Catalog.RECIPES[kind]
	var extent: Vector2 = definition.footprint
	var expected := Vector3(extent.x, float(definition.height), extent.y)
	# 完整模型含柱帽、踢脚、侧梁及檐口，不能拿完整 Bounds 等同净占地。
	# 允许每轴 12% 或 0.35m 的装饰外伸，但仍能抓出旧尺寸、轴向及单位缩放错误。
	for axis in 3:
		var tolerance := maxf(0.35, expected[axis] * 0.12)
		check(box.size[axis] > 0.0 and absf(box.size[axis] - expected[axis]) <= tolerance,
			label + " " + kind + " meshAABB轴" + str(axis), {"actual":box, "expected":expected, "tolerance":tolerance})
	var expected_bottom := -expected.y if kind == "platform_5x5" else 0.0
	check(absf(box.position.y - expected_bottom) <= 0.35, label + " 米制原点 " + kind, box)

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.relative = Vector2(1, 0)
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func click_button(button: Button) -> void:
	await click(button.get_global_transform_with_canvas() * (button.size / 2.0))

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func camera_at(at: Vector3, target: Vector3, fov: float = 42.0) -> void:
	main.cam.suspend_follow()
	main.cam.global_position = world(at)
	main.cam.look_at(world(target))
	main.cam.fov = fov

func shot(name: String, aim: Vector2 = Vector2.INF) -> void:
	# 正式Main被本专项暂停；手动同步进度投影，避免刚完工旧条留在卡片之上。
	editor.tick(0.0)
	main.hud._toast_left=0.0
	main.hud._toast_box.hide()
	main.hud._toast_tag.hide()
	if DisplayServer.get_name() == "headless":
		print("[building-5m-shot] SKIP headless ", name)
		return
	for i in 4: await process_frame
	# push_input 不移动操作系统鼠标；重算相机射线而不是伪造 preview 或颜色。
	if aim.is_finite(): editor.update_preview(aim)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not check(image != null and not image.is_empty(), "截图有真实渲染内容 " + name): return
	var error := image.save_png("res://outputs/building-5m-" + name + ".png")
	check(error == OK, "截图写盘 " + name, error)

func settle() -> void:
	for i in 3: await physics_frame

func walk_to(goal: Vector3, label: String, max_frames: int = 2000) -> bool:
	walk_samples.clear()
	var start: Vector3 = main.player.global_position
	var start_area: Node3D = zone.ground_space.area_at(start, 0.5)
	var goal_area: Node3D = zone.ground_space.area_at(goal, 0.5)
	var route: Array = zone.ground_space.route(start, goal)
	var area_detail := {"start_area":start_area, "goal_area":goal_area, "assembly_area":main.building_world._assembly_walk, "goal":goal, "actor":start}
	if not check(start_area != null and goal_area != null, label + " 起终点有实际GroundSpace源area", area_detail): return false
	if not check(not route.is_empty(), label + " GroundSpace.route", {"start":start, "goal":goal, "start_area":start_area, "goal_area":goal_area, "route":route}): return false
	print("[5m-route] ", label, " start_area=", start_area, " goal_area=", goal_area, " route=", route)
	var legs: Array = [{"area":goal_area, "goal":goal}]
	var total_travelled := 0.0
	var total_grounded := 0
	var max_step := 0.0
	var peak_y := start.y
	var leg_start := start
	for leg_index in legs.size():
		var leg: Dictionary = legs[leg_index]
		var area: Node3D = leg.area
		var leg_goal: Vector3 = leg.goal
		var prepared: Dictionary = main.actor_controller.ground.prepare(main.actor_controller, area, leg_goal)
		var detail := {"leg":leg_index, "area":area, "start":main.player.global_position, "goal":leg_goal, "prepare":prepared, "full_route":route, "state":main.actor_controller.state_id()}
		if not check(bool(prepared.get("ok", false)), label + " leg%d ground.prepare实际原因" % leg_index, detail): return false
		if not check(main.actor_controller.start_walk(area, leg_goal), label + " leg%d start_walk实际源area" % leg_index, detail): return false
		var leg_travelled := 0.0
		var leg_grounded := 0
		var last: Vector3 = main.player.global_position
		var stagnant := 0
		for i in max_frames:
			await physics_frame
			main.actor_controller.tick(DT)
			var at: Vector3 = main.player.global_position
			walk_samples.append(at)
			var step := at.distance_to(last)
			leg_travelled += step
			max_step = maxf(max_step, step)
			peak_y = maxf(peak_y, at.y)
			if main.player.ground_contact: leg_grounded += 1
			stagnant = stagnant + 1 if step < 0.00001 else 0
			last = at
			if not main.actor_controller.walking() or stagnant >= 120: break
		var leg_distance: float = main.player.global_position.distance_to(leg_goal)
		var leg_near: bool = leg_distance < 0.20
		if not main.actor_controller.walk_path.is_empty():
			var next: Vector3 = main.actor_controller.walk_path[0]
			print("[5m-stuck] at=", main.player.global_position, " next=", next, " body_next=", zone.ground_space.body_point(next), " normal=", zone.ground_space.area_at(next,0.5).surface_normal(next))
		if not check(leg_near and not main.actor_controller.walking(),
			label + " leg%d真实胶囊到达" % leg_index, {"actual":main.player.global_position, "goal":leg_goal, "distance":leg_distance, "remaining":main.actor_controller.walk_path, "area":area, "toast":main.hud._toast.text}):
			main.actor_controller.cancel()
			return false
		total_travelled += leg_travelled
		total_grounded += leg_grounded
		leg_start = main.player.global_position
	var end: Vector3 = main.player.global_position
	var ok := check(end.distance_to(goal) < 0.20 and not main.actor_controller.walking(), label + " 真实胶囊到达",
		{"start":start, "goal":goal, "actual":end, "legs":legs.size(), "state":main.actor_controller.state_id(), "remaining":main.actor_controller.walk_path, "toast":main.hud._toast.text})
	check(max_step < 0.20 and total_travelled >= start.distance_to(end) - 0.20 and total_grounded > 0,
		label + " 连续物理位移且真实接地", {"travelled":total_travelled, "max_step":max_step, "grounded_frames":total_grounded, "peak_y":peak_y, "legs":legs.size()})
	if goal.y > start.y + 1.0: check(peak_y >= goal.y - 0.20, label + " 确实爬升而非同XZ底层", peak_y)
	if not ok: main.actor_controller.cancel()
	return ok

func pump_pending(label: String, max_frames: int = 1600) -> bool:
	for i in max_frames:
		await physics_frame
		main.actor_controller.tick(DT)
		editor.tick(DT)
		if editor.pending.is_empty(): break
	return check(editor.pending.is_empty(), label + " 接近请求结束", {"pending":editor.pending, "actor":main.player.global_position, "toast":main.hud._toast.text})

func standalone_and_catalog() -> bool:
	if not check(Catalog.RECIPES.size() == 35 and is_equal_approx(Catalog.LAYER_HEIGHT, H), "35配方与新层高", Catalog.RECIPES.size()): return false
	var menu: Array[String] = []
	var old_props := 0
	for kind: String in Catalog.RECIPES:
		if Catalog.enabled(kind):
			menu.append(kind)
			if str(Catalog.RECIPES[kind].get("group", "")) == "decoration": old_props += 1
	check(menu.size() == 22 and old_props == 10 and menu.has("planter") and menu.has("planter_small"), "菜单=10新组件+10旧家具+2培养土", menu)
	for kind: String in NEW_KINDS:
		check(menu.has(kind), "新组件进入正式菜单 " + kind)
		var pack := load(str(Catalog.RECIPES[kind].prefab)) as PackedScene
		if not check(pack is PackedScene, "组件可以独立加载 " + kind, Catalog.RECIPES[kind].prefab): return false
		var node: Node3D = pack.instantiate()
		root.add_child(node)
		check_dimensions(node, kind, "独立")
		node.queue_free()
	await process_frame
	return true

func all_ten_built() -> bool:
	afloat()
	var ids: Array[String] = []
	ids.append(build("platform_5x5", 180, 160))
	if ids[-1] == "": return false
	for entry in [["wall_5m", 180.0, 157.5, 0], ["window_wall_5m", 177.5, 160.0, 1], ["door_frame_5m", 180.0, 162.5, 0], ["railing_5m", 182.5, 160.0, 1]]:
		ids.append(build(entry[0], entry[1], entry[2], 0.0, entry[3]))
		if ids[-1] == "": return false
	for point: Vector2 in [Vector2(177.5, 157.5), Vector2(182.5, 157.5), Vector2(177.5, 162.5), Vector2(182.5, 162.5)]:
		ids.append(build("post_5m", point.x, point.y))
		if ids[-1] == "": return false
	ids.append(build("roof_flat_5x5", 180, 160, H))
	if ids[-1] == "": return false
	if build("platform_5x5", 190, 160) == "": return false
	if build("wall_5m", 190, 157.5) == "": return false
	ids.append(build("roof_slope_5x5", 190, 160, H))
	if ids[-1] == "": return false
	if build("platform_5x5", 200, 160) == "": return false
	ids.append(build("stairs_5m", 200, 160))
	if ids[-1] == "": return false
	# 横梁与实墙顶端的实体相交不属于合法挂点；用独立双柱承梁夹具。
	if build("platform_5x5", 210, 160) == "": return false
	if build("post_5m", 207.5, 160) == "": return false
	if build("post_5m", 212.5, 160) == "": return false
	ids.append(build("beam_5m", 210, 160, H - 0.2))
	if ids[-1] == "": return false
	var built: Dictionary = {}
	for id: String in ids:
		var row: Dictionary = main.building.row(id)
		var kind := str(row.kind)
		built[kind] = true
		check_dimensions(main.building_world.node_for(id), kind, "正式完工")
	for kind: String in NEW_KINDS:
		check(built.has(kind), "新10组件全部正式建成 " + kind, built.keys())
	check(Service.validate_snapshot(main.building.to_dict()) == "", "全组件正式布局可保存", Service.validate_snapshot(main.building.to_dict()))
	return true

func platform_seams() -> bool:
	afloat()
	legacy_board = build_request({"kind":"deck", "x":20, "z":20, "origin":"boat"})
	if legacy_board == "": return false
	var old_rect := Catalog.footprint_rect(main.building.row(legacy_board))
	var request := Catalog.snap_foundation("platform_5x5", Vector2(old_rect.end.x + 0.2, old_rect.get_center().y), 0, main.building.query())
	request.origin = "shore"
	var first := build_request(request)
	if first == "": return false
	var a := Catalog.footprint_rect(main.building.row(first))
	check(absf(a.position.x - old_rect.end.x) < 0.0001 and not a.grow(-0.001).intersects(old_rect), "5米平台贴旧网格真实边且无重叠", {"old":old_rect, "new":a})
	check(minf(absf(a.position.y - old_rect.position.y), absf(a.end.y - old_rect.end.y)) < 0.0001, "新旧平台沿边角点不发生错缝", {"old":old_rect, "new":a})
	var next := Catalog.snap_foundation("platform_5x5", Vector2(a.end.x + 0.2, a.get_center().y), 0, main.building.query())
	next.origin = "shore"
	var second := build_request(next)
	if second == "": return false
	var b := Catalog.footprint_rect(main.building.row(second))
	check(absf(b.position.x - a.end.x) < 0.0001 and absf(b.position.y - a.position.y) < 0.0001 and not b.grow(-0.001).intersects(a), "两个5x5完整对边无错缝/重叠", {"a":a, "b":b})
	var start := world(Vector3(old_rect.get_center().x, 0, old_rect.get_center().y))
	# 新板可能沿旧板上边或下边对齐；选择真实共享边中点，避免旧板外的假起点。
	var seam_z := (maxf(old_rect.position.y, a.position.y) + minf(old_rect.end.y, a.end.y)) / 2.0
	restore_start(start)
	await settle()
	if not await walk_to(world(Vector3(a.get_center().x, 0, seam_z)), "旧网格→5米板实走跨缝"): return false
	return await walk_to(world(Vector3(b.get_center().x, 0, seam_z)), "5米板→5米板实走跨缝")

func parallel_mouse_fixture() -> bool:
	afloat()
	parallel.base = build("platform_5x5", 100, 100)
	if parallel.base == "": return false
	parallel.foot = build("platform_5x5", 100, 105)
	if parallel.foot == "": return false
	parallel.left = build("stairs_5m", 99.25, 100)
	if parallel.left == "": return false
	camera_at(Vector3(110, 18, 115), Vector3(100, 2, 100))
	restore_start(world(Vector3(99.25, 0, 107)))
	await settle()
	editor.open()
	editor.select_recipe("stairs_5m")
	editor.turn = 0
	editor.build_level = 0.0
	editor.manual_level = true
	editor.snap_assist = true
	# 0.1m 游标经 snap_stairs 吸到 100.75，不直接写 preview。
	var aim: Vector2 = main.cam.unproject_position(world(Vector3(100.8, 0, 100)))
	editor.update_preview(aim)
	if not check(not editor.preview.is_empty(), "鼠标射线生成第二梯预览", aim): return false
	var candidate: Dictionary = editor.preview.duplicate(true)
	check(absf(float(candidate.px) - 100.75) < 0.001 and absf(float(candidate.pz) - 100.0) < 0.001 and Catalog.same_level(Catalog.elevation(candidate), 0.0), "并排第二梯精确吸附中心", candidate)
	check(str(candidate.support) != str(parallel.left) and Catalog.stair_support_ids(candidate, main.building.query()).has(str(parallel.base)), "第二梯独立由底板承载，不独占第一梯支撑", candidate)
	check(main.building.can_place(candidate) == "", "第二梯正式 can_place 合法", main.building.can_place(candidate))
	if not check(is_instance_valid(editor.focus_ghost), "真实第二梯虚影存在"): return false
	var green := 0
	var red := 0
	for mesh: MeshInstance3D in editor.focus_ghost.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override is StandardMaterial3D:
			var color: Color = mesh.material_override.albedo_color
			if color.g > color.r + 0.2: green += 1
			else: red += 1
	check(editor.focus_ghost.visible and green > 0 and red == 0, "真实第二梯preview为green", {"green_meshes":green, "red_meshes":red, "hint":editor.hint.text})
	await shot("parallel-preview", aim)
	var count_before: int = main.building.query().size()
	var wood_before: int = econ.count("wood")
	econ.energy.refill()
	await click(aim)
	if not check(not editor.pending.is_empty() and main.actor_controller.walking(), "真实鼠标点击先接近，不直接开工", {"pending":editor.pending, "toast":main.hud._toast.text}): return false
	check(main.building.query().size() == count_before and econ.count("wood") == wood_before, "接近前未扣费未新增实例")
	await key(KEY_ESCAPE)
	check(editor.pending.is_empty() and not main.actor_controller.walking(), "Esc取消真实接近请求", editor.pending)
	for i in 12:
		await physics_frame
		main.actor_controller.tick(DT)
		editor.tick(DT)
	check(econ.count("wood") == wood_before and main.building.query().size() == count_before, "取消后继续推进也不扣费不施工")
	econ.energy.refill()
	editor.update_preview(aim)
	var start: Vector3 = main.player.global_position
	await click(aim)
	if not check(not editor.pending.is_empty(), "重新点击仍通过approach排队", main.hud._toast.text): return false
	# 排队中的重复实点击不能二次提交。
	await click(aim)
	if not await pump_pending("第二梯实际鼠标施工"): return false
	if not check(main.building.query().size() == count_before + 1, "到工地后只新增第二梯", main.hud._toast.text): return false
	check(econ.count("wood") == wood_before - int(Catalog.RECIPES.stairs_5m.cost.wood), "第二梯正式开工只扣一次", {"before":wood_before, "after":econ.count("wood")})
	check(main.player.global_position.distance_to(start) > 0.8, "开工前角色实际走到施工位", {"start":start, "end":main.player.global_position})
	for row in main.building.query():
		if str(row.kind) == "stairs_5m" and absf(float(row.px) - 100.75) < 0.001 and absf(float(row.pz) - 100) < 0.001: parallel.right = str(row.id)
	if not check(parallel.has("right"), "按实际世界行找到第二梯ID", main.building.query()): return false
	main.building.tick(30)
	editor.close()
	afloat()
	parallel.upper = build("platform_5x5", 100, 95, H)
	if parallel.upper == "": return false
	return true

func check_stair_lane(x: float, label: String) -> void:
	var samples := 0
	var deviation := 0.0
	for at: Vector3 in walk_samples:
		var local := at - Catalog.ORIGIN
		if local.z < 102.2 and local.z > 97.8:
			samples += 1
			deviation = maxf(deviation, absf(local.x - x))
	check(samples > 10 and deviation < 0.60, label + " 确实沿指定独立梯道", {"samples":samples, "max_lateral_deviation":deviation, "center_x":x})

func check_side_cross(label: String) -> void:
	var escaped := 0
	var crossed := false
	for at: Vector3 in walk_samples:
		var local := at - Catalog.ORIGIN
		if absf(local.z - 100.0) > 0.20 or absf(local.y - H / 2.0) > 0.20: escaped += 1
		if absf(local.x - 100.0) < 0.10: crossed = true
	check(crossed and escaped == 0, label + " 半高直接跨共享边，不绕顶部或底部", {"escaped_samples":escaped, "crossed_x100":crossed})

func parallel_walks() -> bool:
	restore_start(world(Vector3(99.25, 0, 102.7)))
	await settle()
	# 同长双梯的导航漏斗可以选择共享边；用梯内真实目标明确左梯，
	# 两段均由start_walk/胶囊执行，不修改导航path或角色姿态。
	if not await walk_to(world(Vector3(99.25, H * 0.2, 101.5)), "指定左梯内部真实爬升"): return false
	check_stair_lane(99.25, "左梯起步")
	if not await walk_to(world(Vector3(99.25, H, 94.5)), "并排左梯独立爬升"): return false
	check_stair_lane(99.25, "左梯爬升")
	if not await walk_to(world(Vector3(99.25, 0, 102.7)), "并排左梯独立下降"): return false
	check_stair_lane(99.25, "左梯下降")
	if not await walk_to(world(Vector3(100.75, 0, 102.7)), "双梯低端横移"): return false
	if not await walk_to(world(Vector3(100.75, H, 94.5)), "并排右梯独立爬升"): return false
	check_stair_lane(100.75, "右梯爬升")
	if not await walk_to(world(Vector3(100.75, 0, 102.7)), "并排右梯独立下降"): return false
	check_stair_lane(100.75, "右梯下降")
	if not await walk_to(world(Vector3(100.75, H, 94.5)), "右梯再次爬升到目标"): return false
	if not await walk_to(world(Vector3(100.75, H / 2.0, 100)), "沿右梯下到半高"): return false
	if not await walk_to(world(Vector3(99.25, H / 2.0, 100)), "半高共享侧边右→左横穿"): return false
	check_side_cross("右→左")
	if not await walk_to(world(Vector3(100.75, H / 2.0, 100)), "半高共享侧边左→右横穿"): return false
	check_side_cross("左→右")
	if not await walk_to(world(Vector3(100.75, H, 94.5)), "横穿后继续爬到目标平台"): return false
	check(Catalog.stairs_parallel(main.building.row(parallel.left), main.building.row(parallel.right)), "双梯同向共享1.5米侧边")
	return true

func serial_fixture() -> bool:
	afloat()
	serial.base = build("platform_5x5", 130, 130)
	if serial.base == "": return false
	serial.foot = build("platform_5x5", 130, 135)
	if serial.foot == "": return false
	serial.low = build("stairs_5m", 130, 130)
	if serial.low == "": return false
	# 不在(130,125,H)塞一块实心5x5板，否则板面遮住第二梯脚下的连续坡。
	serial.high = build("stairs_5m", 130, 125, H)
	if serial.high == "": return false
	serial.top = build("platform_5x5", 130, 120, 2.0 * H)
	if serial.top == "": return false
	check(str(main.building.row(serial.high).support) == str(serial.low), "上梯首尾直接依附下梯", main.building.row(serial.high))
	restore_start(world(Vector3(130, 0, 132.7)))
	await settle()
	if not await walk_to(world(Vector3(130, 2.0 * H, 119.5)), "首尾连续两梯上第三层", 2400): return false
	check(main.building.can_remove(serial.high) != "" and main.building.can_remove(serial.low) != "", "第三层禁止拆最后返程梯", {"low":main.building.can_remove(serial.low), "high":main.building.can_remove(serial.high)})
	check(main.building.can_remove(serial.top) != "", "禁止拆第三层站脚板", main.building.can_remove(serial.top))
	return await walk_to(world(Vector3(130, 0, 132.7)), "首尾连续两梯实际下楼", 2400)

func four_directions() -> bool:
	# turn=0 已由双梯和连续梯实走，其余三个方向仍正式 Service/World/GroundSpace 建成。
	for turn in range(1, 4):
		afloat()
		var origin := Vector2(230 + turn * 15, 100)
		for offset: Vector2 in [Vector2.ZERO, Vector2(0, 5)]:
			if build_at("platform_5x5", rotated(origin, offset, turn)) == "": return false
		var stair := build_at("stairs_5m", rotated(origin, Vector2.ZERO, turn), turn)
		if stair == "": return false
		var top := build_at("platform_5x5", rotated(origin, Vector2(0, -5), turn, H), turn)
		if top == "": return false
		var foot := rotated(origin, Vector2(0, 2.7), turn)
		var goal := rotated(origin, Vector2(0, -5.5), turn, H)
		check(not zone.ground_space.route(foot, goal).is_empty(), "正式旋转方向%d上楼导航" % turn, {"from":foot, "to":goal})
		check(not zone.ground_space.route(goal, foot).is_empty(), "正式旋转方向%d下楼导航" % turn)
		if turn == 1:
			restore_start(foot)
			await settle()
			if not await walk_to(goal, "90度方向真实爬升"): return false
			if not await walk_to(foot, "90度方向真实下降"): return false
	return true

func farming_and_business() -> bool:
	afloat()
	if build("platform_5x5", 105, 95, H) == "": return false
	crop_id = build("planter_small", 104, 94, H)
	if crop_id == "": return false
	var crate := build("storage_crate", 106, 94, H)
	if crate == "": return false
	var barrel := build("water_barrel", 106, 96, H)
	if barrel == "": return false
	var plot: Node = main.farm_field.find("dynamic/" + crop_id)
	if not check(is_instance_valid(plot), "新层面培养土登记真实 FarmField", crop_id): return false
	econ.inventory.set_count("lettuce_seed", 2)
	econ.energy.refill()
	var planted: Dictionary = plot.perform("plant", "lettuce")
	if not check(planted.get("event") == "planted", "新层面真实播种业务", planted): return false
	crop_before = econ.farm.state("dynamic/" + crop_id).duplicate(true)
	check(str(crop_before.get("crop", "")) == "lettuce", "真实Farm持有作物", crop_before)
	var node_before: Node = main.building_world.node_for(crop_id)
	econ.energy.refill()
	var moved: Dictionary = main.building.move(crop_id, {"px":104.0, "pz":96.0})
	if not check(bool(moved.get("ok", false)), "种植区在新层面搬移", moved): return false
	check(main.building_world.node_for(crop_id) == node_before and main.farm_field.find("dynamic/" + crop_id) == plot, "搬移不重建地格/节点/ID")
	check(econ.farm.state("dynamic/" + crop_id) == crop_before and Catalog.same_level(Catalog.elevation(main.building.row(crop_id)), H), "搬移保留crop、水量、生长及新层高", econ.farm.state("dynamic/" + crop_id))
	check(main.building.can_remove(crop_id) != "", "有作物培养土不能拆除", main.building.can_remove(crop_id))
	restore_start(world(Vector3(100.75, 0, 102.7)))
	await settle()
	if not await walk_to(world(Vector3(104, H, 96)), "从梯脚实走到上层种植区"): return false
	check(econ.farm.state("dynamic/" + crop_id) == crop_before, "真实踩踏不改crop")
	var storage: Node = main.building_world.node_for(crate)
	var water: Node = main.building_world.node_for(barrel)
	if not check(is_instance_valid(storage) and is_instance_valid(water), "上层储物箱与水桶真实节点"): return false
	if not await walk_to(world(Vector3(105, H, 94)), "真实走近上层储物箱"): return false
	check(storage.can_interact() and storage.is_in_group("interactable"), "储物箱接入真实交互组")
	check(storage.interact(main.player).get("event") == "used" and main.hud._tab == "storage", "箱子interaction连接共享仓库UI", main.hud._tab)
	main.hud.close_card()
	if not await walk_to(world(Vector3(105, H, 96)), "真实走近上层补水桶"): return false
	econ.farm.watering_can = 1
	check(water.can_interact() and water.is_in_group("interactable"), "水桶接入真实交互组")
	check(water.interact(main.player).get("event") == "used" and econ.farm.watering_can == 12, "水桶interaction调用真实Farm.refill", econ.farm.watering_can)
	check(main.building.can_remove(str(parallel.upper)) != "", "有人在楼上不能拆必经承载板", main.building.can_remove(str(parallel.upper)))
	return true

func ask_lamp(lamp: String, aim: Vector2) -> bool:
	editor.update_preview(aim)
	if not check(editor.hovered_id == lamp, "相机实际射线命中拆除灯", {"expected":lamp, "actual":editor.hovered_id, "preview":editor.preview}): return false
	await click(aim)
	return check(editor.demolition.confirmation_open() and not main.building.row(lamp).is_empty(), "实际点击仅打开确认不拆除")

func demolition_mouse() -> bool:
	# 当前角色从上一用例实际走到此层；新增灯避开其胶囊与家具。
	var lamp := build("oil_lamp", 103.5, 94, H)
	if lamp == "": return false
	camera_at(Vector3(111, 20, 107), Vector3(103, H, 95))
	editor.open()
	await process_frame
	check(editor.view.book == editor.book and editor.view.guide == editor.guide and editor.view.demolition == editor.demolition, "正式UI由统一view集中持有")
	check(editor.book.visible and editor.guide.visible and not editor.book.get_global_rect().intersects(editor.guide.get_global_rect()), "统一工具栏+手册同屏无遮挡")
	var visible_recipes: Dictionary = {}
	editor.book.category = "all"
	for page in 3:
		editor.book.page = page
		editor.book.refresh()
		for kind: String in editor.book.cards:
			if editor.book.cards[kind].visible: visible_recipes[kind] = true
	check(visible_recipes.size() == 22, "正式手册三页实际展示22个配方", visible_recipes.keys())
	for kind: String in Catalog.RECIPES:
		check(visible_recipes.has(kind) == Catalog.enabled(kind), "手册可见性与目录一致 " + kind)
	editor.book.page = 0
	editor.book.refresh()
	check(is_equal_approx(editor.build_level * H, H), "上层打开UI继承实际height而非整数米", editor.build_level)
	await shot("ui")
	var before: String = editor.recipe
	editor.select_recipe("deck")
	check(editor.recipe == before and editor.book.visible, "旧结构menu_visible=false，controller拒绝旧id正常", editor.recipe)
	await click_button(editor.view.buttons.remove)
	if not check(editor.recipe == "remove" and editor.demolition.active, "实际工具栏鼠标进入拆除"): return false
	var aim: Vector2 = main.cam.unproject_position(main.building_world.position_for(main.building.row(lamp)) + Vector3.UP * 0.30)
	var wood_before: int = econ.count("wood")
	if not await ask_lamp(lamp, aim): return false
	check(root.gui_get_focus_owner() == editor.demolition.no_button, "拆除确认默认焦点否")
	await shot("confirm")
	await key(KEY_ENTER)
	check(not editor.demolition.confirmation_open() and not main.building.row(lamp).is_empty() and econ.count("wood") == wood_before, "默认Enter执行否，保留且不退款")
	if not await ask_lamp(lamp, aim): return false
	await click_button(editor.demolition.no_button)
	check(not editor.demolition.confirmation_open() and not main.building.row(lamp).is_empty() and econ.count("wood") == wood_before, "真实鼠标否保留且不退款")
	if not await ask_lamp(lamp, aim): return false
	await key(KEY_ESCAPE)
	check(not editor.demolition.confirmation_open() and not main.building.row(lamp).is_empty() and econ.count("wood") == wood_before, "Esc取消保留且不退款")
	if not await ask_lamp(lamp, aim): return false
	econ.energy.refill()
	await click_button(editor.demolition.yes_button)
	if not await pump_pending("确认拆除真实接近"): return false
	if not check(main.building.row(lamp).is_empty(), "鼠标确认是拆回指定灯", main.hud._toast.text): return false
	var expected: int = wood_before + int(Catalog.RECIPES.oil_lamp.cost.wood)
	check(econ.count("wood") == expected, "确认只退款一次", {"expected":expected, "actual":econ.count("wood")})
	await click_button(editor.demolition.yes_button)
	var repeated: Dictionary = main.building.remove(lamp)
	check(not repeated.get("ok", false) and econ.count("wood") == expected, "重复确认/重复remove均不能重复退款", repeated)
	editor.close()
	# 独立保留最后返程梯，确认拒绝不改变布局或退款。
	afloat()
	econ.energy.refill()
	var removed: Dictionary = main.building.remove(str(parallel.left))
	if not check(removed.get("ok", false), "双梯仍有右梯时允许拆左梯", removed): return false
	restore_start(world(Vector3(100.75, 0, 102.7)))
	await settle()
	if not await walk_to(world(Vector3(100.75, H, 94.5)), "剩余右梯仍真实可返程"): return false
	var safe_before: Dictionary = main.building.to_dict()
	wood_before = econ.count("wood")
	var last_reason: String = main.building.can_remove(str(parallel.right))
	var foot_reason: String = main.building.can_remove(str(parallel.upper))
	check(last_reason != "" and foot_reason != "", "唯一返程梯与站脚板均保护", {"stairs":last_reason, "board":foot_reason})
	check(not main.building.remove(str(parallel.right)).get("ok", false) and not main.building.remove(str(parallel.upper)).get("ok", false), "正式remove也拒绝危险拆除")
	check(main.building.to_dict() == safe_before and econ.count("wood") == wood_before, "危险拆除无布局变化无退款")
	return true

func mixed_disk_save() -> bool:
	afloat()
	if build("raft_4x4", 160, 100) == "": return false
	if build("stairs", 160, 100) == "": return false
	legacy_upper = build("upper_floor", 160, 97, 2.8)
	if legacy_upper == "": return false
	var board_before: Dictionary = main.building.row(legacy_board)
	var old_before: Dictionary = main.building.row(legacy_upper)
	var high_before: Dictionary = main.building.row(str(serial.top))
	camera_at(Vector3(169, 18, 111), Vector3(160, 2.8, 97))
	editor.open()
	editor.select_recipe("planter_small")
	editor.manual_level = true
	editor.build_level = 2.8 / Catalog.LAYER_HEIGHT
	editor.update_preview(main.cam.unproject_position(world(Vector3(160, 2.8, 97))))
	check(not editor.preview.is_empty() and absf(Catalog.elevation(editor.preview) - 2.8) < 0.000001, "manual_level的float ratio准确投射旧2.8米", editor.preview)
	editor.build_level = 2.0
	camera_at(Vector3(141, 26, 136), Vector3(130, 2.0 * H, 120))
	editor.update_preview(main.cam.unproject_position(world(Vector3(130, 2.0 * H, 120))))
	check(not editor.preview.is_empty() and absf(Catalog.elevation(editor.preview) - 2.0 * H) < 0.000001, "manual_level=2按2H而非2米投射", editor.preview)
	editor.close()
	# 起点恢复仅设置脚下初始姿态；第三层的结果仍必须重新真实爬升取得。
	restore_start(world(Vector3(130, 0, 132.7)))
	await settle()
	if not await walk_to(world(Vector3(130, 2.0 * H, 119.5)), "混合存档前实际爬上第三层", 2400): return false
	var actor_before: Vector3 = main.player.global_position
	var saved: Dictionary = Save.write(save_path, main)
	if not check(saved.get("ok", false), "SaveGame正式整档磁盘写入", saved.get("reason", "")): return false
	var disk: Dictionary = Save.read(save_path)
	if not check(disk.get("ok", false), "SaveGame正式磁盘读取", disk.get("reason", "")): return false
	var snapshot: Dictionary = disk.snapshot
	check(str(snapshot.game.zone) == "zone5" and int(snapshot.game.mode) == 0, "磁盘快照保留建造区scope与岸上模式", snapshot.game)
	var crop_row_before: Dictionary = main.building.row(crop_id)
	var reversed: Dictionary = snapshot.duplicate(true)
	reversed.building.instances.reverse()
	var reason := Service.validate_snapshot(reversed.building)
	if not check(reason == "", "新旧混合反序Service快照合法", reason): return false
	var model := Service.new()
	if not check(model.from_dict(reversed.building), "独立正式Service反序恢复"): return false
	check(equivalent(model.row(legacy_board), board_before) and equivalent(model.row(legacy_upper), old_before) and equivalent(model.row(str(serial.top)), high_before), "Service恢复旧网格/2.8/2H原记录", model.to_dict())
	var restored: Dictionary = Save.restore(main, reversed)
	if not check(restored.get("ok", false), "正式整档从反序磁盘快照恢复", restored): return false
	check(str(root.get_node("GameState").current_zone) == "zone5" and main.actor_controller.mode() == 0 and main._zone_nodes.get("zone5") == zone, "恢复后scope不把角色迁回zone1或船上")
	check(equivalent(main.building.row(crop_id), crop_row_before), "反序磁盘恢复保留种植区搬移后的坐标和py", main.building.row(crop_id))
	check(main.player.global_position.distance_to(actor_before) < 0.20 and absf(main.player.global_position.y - Catalog.ORIGIN.y - 2.0 * H) < 0.20, "磁盘恢复仍站第三层而非底层", main.player.global_position)
	check(equivalent(main.building.row(legacy_board), board_before) and int(board_before.x) == 20 and int(board_before.z) == 20 and not board_before.get("positioned", false), "旧board整数网格与原坐标完全保留", main.building.row(legacy_board))
	check(equivalent(main.building.row(legacy_upper), old_before) and Catalog.same_level(Catalog.elevation(main.building.row(legacy_upper)), 2.8), "旧py2.8保留不按新层高舍入", main.building.row(legacy_upper))
	check(equivalent(main.building.row(str(serial.top)), high_before) and Catalog.same_level(Catalog.elevation(main.building.row(str(serial.top))), 2.0 * H), "新height2H精确保留", main.building.row(str(serial.top)))
	check(equivalent(econ.farm.state("dynamic/" + crop_id), crop_before) and main.farm_field.find("dynamic/" + crop_id) != null, "磁盘整档恢复搬移后的真实crop")
	var reversed_path := save_path.trim_suffix(".json") + "-reversed.json"
	var written: Dictionary = Save.write(reversed_path, main)
	if not check(written.get("ok", false), "反序恢复后的正式SaveGame再次写盘", written.get("reason", "")): return false
	var reversed_disk: Dictionary = Save.read(reversed_path)
	if not check(reversed_disk.get("ok", false), "反序布局实际磁盘读回", reversed_disk.get("reason", "")): return false
	check(reversed_disk.snapshot.building.instances == reversed.building.instances, "磁盘保存保留反序而非依赖支撑排序")
	var again: Dictionary = Save.restore(main, reversed_disk.snapshot)
	if not check(again.get("ok", false), "真正反序磁盘档再次恢复", again): return false
	await settle()
	return await walk_to(world(Vector3(130, 0, 132.7)), "反序磁盘恢复后连续梯仍真实可下楼", 2400)

func finish() -> void:
	check(completed_stages == REQUIRED_STAGES, "必须完整执行全部体验阶段，提前返回不得零失败", {"completed":completed_stages, "required":REQUIRED_STAGES})
	print("[building-5m-stages] ", completed_stages)
	if is_instance_valid(main):
		if is_instance_valid(editor): editor.close()
		main.queue_free()
		await process_frame
	print("[building-5m-experience] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	# 必须在 Main._ready 可能自动读槽位之前检查，禁止直接在真实工程 user:// 启动。
	var isolated := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not check(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) and isolated.begins_with("sea-verification/"), "统一runner的Autoload前存档隔离前置条件", isolated):
		await finish()
		return
	root.size = Vector2i(1600, 1000)
	save_path = "user://building-5m-experience-%d.json" % Time.get_ticks_usec()
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not check(scene is PackedScene, "正式Main场景加载"): await finish(); return
	if not check(OS.get_cmdline_user_args().has("--skip-title"), "统一runner提供--skip-title，避免标题层吞鼠标"): await finish(); return
	main = scene.instantiate()
	# 仅拦截自动保存，正式装配和各业务端口仍由 Main._ready 创建。
	main._autosave_on = false
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.boat.set_process(false)
	main.interactor.set_process(false)
	econ = root.get_node("Economy")
	econ.set_process(false)
	editor = main.building_controller
	zone = main._zone_nodes.get("zone5")
	if not check(is_instance_valid(zone) and is_instance_valid(editor) and main.building_world != null, "正式Main建造依赖完整装配"): await finish(); return
	econ.inventory.set_count("wood", 700)
	econ.inventory.set_count("soil", 30)
	root.get_node("GameState").enter_zone("zone5")
	root.get_node("GameState").landing_id = "main"
	await process_frame
	if not check(main.building.query().is_empty(), "隔离新局无真实存档布局"): await finish(); return
	var capsule: CollisionShape3D = main.player.get_node_or_null("BodyCollision")
	if not check(main.player is CharacterBody3D and capsule != null and capsule.shape is CapsuleShape3D and not capsule.disabled, "使用正式角色真实胶囊而非测试替身"): await finish(); return
	if not check(is_instance_valid(zone.ground_space), "正式Zone装配GroundSpace"): await finish(); return
	if not await standalone_and_catalog(): await finish(); return
	completed_stages.append("catalog")
	if not await all_ten_built(): await finish(); return
	completed_stages.append("all_ten")
	if not await platform_seams(): await finish(); return
	completed_stages.append("seams")
	if not await parallel_mouse_fixture(): await finish(); return
	completed_stages.append("parallel_mouse")
	if not await parallel_walks(): await finish(); return
	completed_stages.append("parallel_walks")
	if not await serial_fixture(): await finish(); return
	completed_stages.append("serial")
	camera_at(Vector3(145, 36, 153), Vector3(115, 4, 115), 52)
	await shot("overview")
	if not await four_directions(): await finish(); return
	completed_stages.append("directions")
	if not await farming_and_business(): await finish(); return
	completed_stages.append("business")
	if not await demolition_mouse(): await finish(); return
	completed_stages.append("demolition")
	if not await mixed_disk_save(): await finish(); return
	completed_stages.append("save")
	check(econ.count("wood") >= 0, "全体验仅用初始700wood，不靠2000或中途补木", econ.count("wood"))
	await finish()
