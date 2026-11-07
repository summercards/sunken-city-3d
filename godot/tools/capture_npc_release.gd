extends "res://tests/test_npc_integration.gd"
## 只捕获正式 main：沿用其灯光、海水、现有天台草地、七人和业务面板；无替身展示场景。
const RELEASE_MAX_DISTANCE := 77.8
var shots: Array[String] = []
var rooftop_pose: Dictionary = {}
var rooftop_frame_points: Array[Vector3] = []
var visual_occluders: Array = []

func run() -> void:
	marker = "npc-release-render"
	if not check(DisplayServer.get_name() != "headless", "必须用 DisplayServer real，禁止 headless 截图假通过"):
		await finish(); return
	if not await boot():
		await finish(); return
	root.size = Vector2i(1920, 1080)
	if not landing_fixture("rooftop_ranch"):
		await finish(); return
	await frames(8)
	if not await until(func():
		for resident in world.world_snapshot().residents.values():
			if resident.remaining_waypoints > 0: return false
		return true, 45.0, "截图前七人沿真实日程落位"):
		await finish(); return
	world.set_physics_process(false)
	cache_visual_occluders()
	main.cam.pose_lock = true
	main.cam.follow_enabled = false
	if not await fit_rooftop_camera():
		await finish(); return
	await frames(4)
	check(harbor.is_visible_in_tree() and provider.is_visible_in_tree(), "天台全景使用真实草地和 NpcStations")
	for id in Catalog.ids():
		check(grass_support(world.actor(id).global_position), "全景居民真实站在原天台草皮 " + id)
	await seven_visible("overview")
	# 两张全景各自检查同框尺寸和胸部视线，不用一张图的检查替另一张背书。
	await seven_visible("seven-residents")
	for id in Catalog.ids():
		var body = world.actor(id)
		if not await fit_actor_camera(body):
			await finish(); return
		await frames(3)
		check(actor_visible(body, 110.0), "近景真实模型可见且足够辨认 " + id)
		var report: Dictionary = body.appearance_report()
		check(report.npc_id == id and report.accessory_id == Catalog.get_npc(id).accessory_id,
			"近景是实际 NPC 外观和专用配件 " + id)
		await shot(id.trim_prefix("npc_"))
	check(economy.inventory.add("coins", 200).ok, "购买截图使用真实 Inventory 余额")
	aim(world.actor("npc_hua_yi").global_position, 18.0)
	if await vendor("npc_hua_yi", "shop_flower"):
		var panel = main.shop_panel
		var quote: Dictionary = main.shop_service.quote("shop_flower", panel._selected_id, 1)
		if check(quote.ok and not panel._buy.disabled, "花店购买面板实际可购买"):
			var coins: int = economy.inventory.count("coins")
			var owned: int = economy.inventory.count(quote.item)
			panel._buy.pressed.emit()
			await frames(2)
			check(economy.inventory.count("coins") == coins - int(quote.total_cost)
				and economy.inventory.count(quote.item) == owned + 1 and panel._feedback.text.contains("已购入"),
				"花店截图显示真实购买反馈，不伪造 UI 文本")
			await shot("flower-purchase")
	await close_modals()
	if await vendor("npc_bao_he", "shop_general"):
		check(main.shop_panel._product_buttons.size() >= 6 and main.shop_panel._details.is_visible_in_tree(), "综合面板有真实商品与报价")
		await shot("general-shop")
	await close_modals()
	var durable: Dictionary = main.npc_service.to_dict()
	for id in Catalog.ids():
		durable.graph.met[id] = true
		durable.graph.affinity[id] = 500
	if check(main.npc_service.from_dict(durable).ok, "剧情取景只通过正式 strict durable 前置"):
		if await open_npc("npc_luo_yan") and await npc_press("events") and await npc_press("event", "route_1"):
			var reached := false
			for step in 30:
				var dialogue: Dictionary = main.npc_service.dialogue_state()
				if not dialogue.get("active", false): break
				if dialogue.page.has("choices") and not dialogue.typing:
					reached = true
					break
				if not await npc_press("advance"): break
			if check(reached, "真实剧情到达等待选择页"):
				var choices := 0
				for button: Button in world.panel._buttons:
					if button.get_meta("npc_action") == "choice" and button.is_visible_in_tree() and not button.disabled: choices += 1
				check(choices == 2 and world.panel._text.is_visible_in_tree()
					and world.panel._text.visible_characters == -1, "剧情文字完整且两项真实选择同时可见")
				await shot("story-choice")
	await close_modals()
	if await open_npc("npc_luo_yan") and await npc_press("relationships"):
		var relationships := 0
		for child in world.panel._body.get_children():
			if child is Label and child.is_visible_in_tree() and child.text.contains("关系"): relationships += 1
		check(relationships > 0, "关系网显示真实已相识居民关系，不是空页")
		await shot("relationships")
	await close_modals()
	if await open_career("npc_luo_yan", "ship"):
		check(main.npc_career_panel._title.text == "船只与航行" and main.npc_career_panel._identity.text.contains(Catalog.get_npc("npc_luo_yan").display_name), "船面板可见且归属真实船匠")
		await shot("ship-career")
	for required in ["overview", "seven-residents", "flower-purchase", "general-shop", "story-choice", "relationships", "ship-career"]:
		check(required in shots, "必需正式截图已产出 " + required)
	for id in Catalog.ids(): check(id.trim_prefix("npc_") in shots, "七人可辨近景已产出 " + id)
	check(shots.size() == 14, "正式天台验收恰有14张有效PNG")
	await close_modals()
	await finish()

func vendor(id: String, shop_id: String) -> bool:
	if not await open_npc(id) or not await npc_press("services") or not await npc_press("vendor"): return false
	await frames(3)
	var panel = main.shop_panel
	return check(panel.is_open() and panel._shop_id == shop_id and panel._overlay.is_visible_in_tree()
		and panel._title.text == main.shop_service.shop_snapshot(shop_id).display_name
		and not main.hud.is_panel_open(), "正式商店标题与内容可见，不打开旧 HUD " + shop_id)

func aim(point: Vector3, distance := 22.0) -> void:
	# 捕获入口不扩展正式玩家缩放范围，也不修改FOV或投影类型。
	check(distance <= RELEASE_MAX_DISTANCE and main.cam.zoom_max <= RELEASE_MAX_DISTANCE, "截图机位不突破正式77.8米上限")
	main.cam.follow_enabled = false
	main.cam.pose_lock = true
	main.cam.target = point + Vector3.UP
	main.cam.dir = Vector3(0.22, 0.85, 1.0).normalized()
	main.cam.set_distance(distance)

func fit_rooftop_camera() -> bool:
	var bounds := AABB()
	var first := true
	# 完整草皮边界来自真实网格；中心来自 provider Marker，标高来自当前天台。
	for mesh: MeshInstance3D in harbor.get_node("Models/ORF3_中央草皮基底").find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not check(not first, "从正式天台草皮取得完整取景边界"): return false
	var center := Vector3.ZERO
	var anchors: Dictionary = provider.anchor_snapshot()
	for anchor in anchors.values(): center += anchor.position
	if not check(anchors.size() == 35, "取景中心来自35个正式草地 Marker"): return false
	center /= float(anchors.size())
	var roof_y: float = harbor.to_global(Vector3(0, harbor.ROOF_Y, 0)).y
	check(absf(center.y - roof_y) < 0.05, "取景使用当前 roof 高度，不使用旧天台草地0.35米高度")
	for x in [bounds.position.x, bounds.end.x]:
		for z in [bounds.position.z, bounds.end.z]:
			rooftop_frame_points.append(Vector3(x, roof_y, z))
	var target := Vector3(center.x, roof_y + 1.5, center.z)
	var best := {}
	var best_pixels := -1.0
	var diagnostics: Array = []
	var positions := {}
	for id in Catalog.ids(): positions[id] = world.actor(id).global_transform
	for distance: float in [65.0, 68.0, 70.0, 72.0, 75.0]:
		for pitch_degrees: float in [32.0, 36.0, 40.0, 44.0, 48.0, 52.0]:
			for yaw_degrees: float in [0.0, -30.0, 30.0, -60.0, 60.0, -90.0, 90.0, -120.0, 120.0, -150.0, 150.0, 180.0]:
				var pitch := deg_to_rad(pitch_degrees)
				var yaw := deg_to_rad(yaw_degrees)
				main.cam.target = target
				main.cam.dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				main.cam.set_distance(distance)
				var viewport: Rect2 = root.get_visible_rect().grow(-24.0)
				var fits := true
				for point in rooftop_frame_points:
					fits = fits and not main.cam.is_position_behind(point) and viewport.has_point(main.cam.unproject_position(point))
				var minimum := INF
				var visible := 0
				for id in Catalog.ids():
					var metrics := actor_metrics(world.actor(id))
					minimum = minf(minimum, metrics.pixels)
					if metrics.visible and metrics.pixels >= 28.0: visible += 1
				diagnostics.append({"distance": distance, "pitch": pitch_degrees, "yaw": yaw_degrees, "fits": fits, "visible": visible, "min_pixels": minimum})
				if fits and visible == 7 and minimum > best_pixels:
					best_pixels = minimum
					best = {"target": target, "direction": main.cam.dir, "distance": distance, "pitch": pitch_degrees, "yaw": yaw_degrees}
		await process_frame
	if not check(not best.is_empty(), "65至75米内正式天台草地完整入镜且七人均达28px、胸部视线无遮挡"):
		printerr("[npc-release-fit-candidates] ", diagnostics)
		return false
	rooftop_pose = best
	main.cam.target = best.target
	main.cam.dir = best.direction
	main.cam.set_distance(best.distance)
	await frames(3)
	for id in positions: check(world.actor(id).global_transform == positions[id], "机位搜索未挪动正式居民 " + id)
	check(main.cam.distance <= RELEASE_MAX_DISTANCE and main.cam.zoom_max <= RELEASE_MAX_DISTANCE, "天台草地机位保持正式缩放上限")
	print("[npc-release-fit] ", best, " min_pixels=", best_pixels, " viewport=", root.get_visible_rect())
	return true

func cache_visual_occluders() -> void:
	for mesh: MeshInstance3D in harbor.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		# 使用正式网格三角形；物理胸射线之外再检查无碰撞墙/柜台的真实遮挡。
		var faces := mesh.mesh.get_faces()
		if not faces.is_empty(): visual_occluders.append({"mesh": mesh, "faces": faces, "inverse": mesh.global_transform.affine_inverse(), "bounds": mesh.global_transform * mesh.get_aabb()})

func visual_blocker(target: Vector3) -> String:
	var origin: Vector3 = main.cam.global_position
	var direction: Vector3 = (target - origin).normalized()
	for entry in visual_occluders:
		if not entry.mesh.is_visible_in_tree() or not entry.bounds.intersects_ray(origin, direction): continue
		var start: Vector3 = entry.inverse * origin
		var end: Vector3 = entry.inverse * target
		var faces: PackedVector3Array = entry.faces
		for index in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2]) != null:
				return str(entry.mesh.get_path())
	return ""

func fit_actor_camera(body: Node3D) -> bool:
	var best := {}
	var score := -1.0
	for pitch_degrees: float in [40.0, 48.0, 56.0, 64.0, 72.0]:
		for yaw_degrees: float in [0.0, -30.0, 30.0, -60.0, 60.0, -90.0, 90.0, 180.0]:
			var pitch := deg_to_rad(pitch_degrees)
			var yaw := deg_to_rad(yaw_degrees)
			main.cam.target = body.global_position + Vector3.UP
			main.cam.dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			main.cam.set_distance(12.0)
			var metrics := actor_metrics(body)
			if metrics.visible and metrics.pixels >= 110.0 and metrics.pixels > score:
				score = metrics.pixels
				best = {"direction": main.cam.dir, "pitch": pitch_degrees, "yaw": yaw_degrees}
	if not check(not best.is_empty(), "正式网格无遮挡的居民近景机位 " + str(body.name)): return false
	main.cam.dir = best.direction
	main.cam.apply_pose()
	await frames(2)
	print("[npc-release-closeup-fit] ", body.name, " pose=", best, " pixels=", score)
	return true

func actor_metrics(body: Node3D) -> Dictionary:
	var feet: Vector3 = body.global_position + Vector3.UP * 0.1
	var head: Vector3 = body.global_position + Vector3.UP * 1.9
	var bottom: Vector2 = main.cam.unproject_position(feet)
	var top: Vector2 = main.cam.unproject_position(head)
	var viewport: Rect2 = root.get_visible_rect().grow(-12)
	var target: Vector3 = body.global_position + Vector3.UP * 1.55
	var ray := PhysicsRayQueryParameters3D.create(main.cam.global_position, target, 256)
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(ray)
	var clear: bool = hit.is_empty() or hit.position.distance_to(target) <= 0.25
	var occluder := visual_blocker(target)
	clear = clear and occluder.is_empty()
	var visible: bool = body.is_visible_in_tree() and not main.cam.is_position_behind(feet) and not main.cam.is_position_behind(head)
	visible = visible and viewport.has_point(bottom) and viewport.has_point(top) and clear
	visible = visible and not body.find_children("*", "MeshInstance3D", true, false).is_empty()
	return {"visible": visible, "pixels": top.distance_to(bottom), "chest_clear": clear, "visual_blocker": occluder, "hit": str(hit.get("collider", "")), "feet": bottom, "head": top}

func actor_visible(body: Node3D, minimum_pixels: float) -> bool:
	var metrics := actor_metrics(body)
	print("[npc-release-visibility] ", body.name, " minimum=", minimum_pixels, " metrics=", metrics)
	return metrics.visible and metrics.pixels >= minimum_pixels

func seven_visible(shot_id: String) -> void:
	check(main.cam.distance >= 65.0 and main.cam.distance <= 75.0, "同框截图实际距离处于65至75米 " + shot_id)
	for point in rooftop_frame_points:
		check(root.get_visible_rect().grow(-24).has_point(main.cam.unproject_position(point)), "天台草地边界完整入镜 " + shot_id)
	var centers: Array[Vector2] = []
	var appearances := {}
	for id in Catalog.ids():
		var body = world.actor(id)
		check(actor_visible(body, 28.0), "天台草地七人同框真实可见 " + id)
		var screen: Vector2 = main.cam.unproject_position(body.global_position + Vector3.UP)
		for previous in centers: check(previous.distance_to(screen) > 24.0, "七人投影分离 " + id)
		centers.append(screen)
		var report: Dictionary = body.appearance_report()
		appearances[JSON.stringify(report.profile.appearance)] = true
	check(appearances.size() == 7, "七人正式外观不是同一默认旅人")
	await shot(shot_id)

func shot(id: String) -> void:
	var failures_before := failures
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not check(image != null and not image.is_empty() and image.get_width() >= 1280 and image.get_height() >= 720, "真实 viewport 图像有效 " + id): return
	# 拒绝只有单一背景色的空截图；不以文件存在替代可见内容断言。
	var colors := {}
	for y in range(0, image.get_height(), 32):
		for x in range(0, image.get_width(), 32): colors[image.get_pixel(x, y).to_html()] = true
	check(colors.size() > 24, "正式渲染非空白画面 " + id)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	if not check(error == OK, "正式截图输出目录可写"): return
	var path := "res://outputs/npc-release-" + id + ".png"
	if check(image.save_png(path) == OK, "保存真实画面 " + path) and failures_before == failures:
		shots.append(id)
	print("[npc-release-shot] ", path, " display=", DisplayServer.get_name(), " renderer=", RenderingServer.get_current_rendering_method())
