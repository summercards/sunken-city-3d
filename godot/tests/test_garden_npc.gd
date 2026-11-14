extends SceneTree
## 霓虹花园菜园桥：可走面从模型派生、豆豆站上去、靠近时头顶招呼一句。
##
## 主场景真实装配（含用户手摆变换），不写存档、不改场景。
## 完成标记：[garden-npc] N checks, 0 failures

var main
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func ok(value: bool, name: String) -> void:
	checks += 1
	print("[garden-npc] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	main.set("_autosave_on", false)
	for i in 8:
		await process_frame
	var quarter: Node3D = main.get_node_or_null("World/SeaStructures/neon_garden_quarter")
	ok(quarter != null, "霓虹花园在正式主场景里")
	if quarter == null:
		finish(); return
	print("[garden-npc] quarter global=", quarter.global_position)
	var deck: Node3D = quarter.get_node_or_null("WalkAreas/WalkGardenDeck")
	ok(deck != null, "菜园桥可走面存在")
	if deck != null:
		print("[garden-npc] deck surface_y=", deck.get("surface_y"), " rects=", deck.get("rects").size(),
			" active=", deck.get("active"), " built=", deck.get("_built"))
		ok(deck.get("rects").size() > 0 and deck.get("active") == true, "菜园桥可走面已从模型派生")
	# 强制按当前日程刷一次，否则 NPC 还停在上一轮的站位
	main.npc_world_presenter.sync_world(main._npc_world_query(), true)
	for i in 6:
		await process_frame
	var hub_anchors: Dictionary = main.get_node("NpcAnchorHub").anchor_snapshot()
	ok(hub_anchors.size() == 40, "四个站位 provider 聚合40个有效锚点")
	var muhe_row: Dictionary = main.npc_world_presenter.world_snapshot().get("residents", {}).get("npc_mu_he", {})
	ok(not bool(muhe_row.get("fallback", true)) and str(muhe_row.get("anchor_id", "")).begins_with("residence_garden_bridge"),
		"豆豆按日程落在菜园桥且不走 fallback")
	# 豆豆的实际站位
	var body = main.npc_world_presenter.actor("npc_mu_he")
	ok(is_instance_valid(body), "豆豆的 actor 存在")
	if is_instance_valid(body):
		var p: Vector3 = body.global_position
		print("[garden-npc] 豆豆世界位置=", p)
		var local: Vector3 = quarter.to_local(p)
		print("[garden-npc] 豆豆局部=", local, " 菜园桥土面局部 y≈28.35")
		ok(absf(local.y - 28.35) < 1.2, "豆豆站在菜园桥土面高度（局部 y %.2f）" % local.y)
		ok(local.x > -10.5 and local.x < 10.5 and local.z > -1.5 and local.z < 6.0,
			"豆豆的水平位置落在菜园桥范围内（x %.2f z %.2f）" % [local.x, local.z])
	# 锚点解析
	var stations = quarter.get_node_or_null("NpcStations")
	ok(stations != null, "霓虹花园 NpcStations 存在")
	if stations != null:
		var snaps: Dictionary = stations.anchor_snapshot()
		print("[garden-npc] 霓虹花园锚点=", snaps.keys())
		ok(snaps.size() == 5, "菜园桥五个锚点全部有效")
		var max_height_error := 0.0
		for id in ["residence_garden_bridge", "residence_garden_bridge_work",
			"residence_garden_bridge_social", "residence_garden_bridge_rest",
			"residence_garden_bridge_door"]:
			var station_id := "residence_garden_bridge"
			var kind: String = "Home" if id == station_id else id.trim_prefix(station_id + "_").capitalize()
			var marker: Marker3D = stations.get_node("%s/%s" % [station_id, kind])
			var anchor: Dictionary = snaps.get(id, {})
			var support: Vector3 = deck.surface_point(marker.global_position)
			var error := INF if anchor.is_empty() else marker.global_position.distance_to(anchor.position)
			print("[garden-npc] anchor_probe id=", id, " marker_local=", quarter.to_local(marker.global_position),
				" support_local=", quarter.to_local(support), " support=", support, " error=", error)
			max_height_error = maxf(max_height_error, error)
			ok(not anchor.is_empty() and bool(anchor.get("support_validated", false)),
				"菜园桥锚点支撑有效 " + id)
		print("[garden-npc] 菜园桥锚点最大高度/支撑误差=", max_height_error)
		ok(max_height_error <= 0.05, "菜园桥 height mismatch 已收敛到 SUPPORT_TOLERANCE")
		var work: Dictionary = snaps.get("residence_garden_bridge_work", {})
		ok(not work.is_empty(), "菜园桥工作锚点可解析")
		if not work.is_empty():
			print("[garden-npc] work anchor=", work.position)
	# 头顶气泡
	var bubble = main._garden_bubble
	ok(bubble != null, "招呼气泡已装配")
	ok(main._garden_lines.size() >= 10, "每日招呼台词条数 %d" % main._garden_lines.size())
	if bubble != null and is_instance_valid(body):
		# 把玩家挪到楼下，模拟船经过
		main.player.global_position = quarter.to_global(Vector3(0, 0, 9))
		# 气泡是屏幕空间的，角色必须在镜头里才会显示。这里按玩家的实际视角
		# 抬头看楼顶 —— 不这样做测的是「相机没对着她时也硬画一张纸条」，
		# 那不是要验的行为。
		main.cam.follow_enabled = false
		main.cam.pose_lock = true
		main.cam.target = body.global_position + Vector3.UP * 1.4
		main.cam.dir = Vector3(0.25, 0.55, 1.0).normalized()
		main.cam.set_distance(24.0)
		main.cam.apply_pose()
		for i in 4:
			await process_frame
		main.set("_garden_probe_cooldown", 0.0)
		main.set("_garden_spoken_day", -1)
		main._tick_garden_greeting(0.016)
		for i in 3:
			await process_frame
		print("[garden-npc] bubble text=", bubble.text(), " visible=", bubble.visible)
		ok(bubble.visible and bubble.text() != "", "抬头看向楼顶时气泡显示台词")
		# 气泡比原来大一倍多：字号 30、宽上限 468，保证远处也读得清。
		ok(bubble.get_global_rect().size.y > 90.0 and bubble.get_global_rect().size.x > 300.0,
			"气泡按远读尺寸排版（%.0fx%.0f）" % [bubble.get_global_rect().size.x, bubble.get_global_rect().size.y])
		ok(bubble.text() == str(main._garden_lines[int(main._garden_spoken_day - 1) % main._garden_lines.size()]),
			"当天台词按日次取，同日固定")
		var first: String = bubble.text()
		# 同一天第二次靠近不再喊
		main.set("_garden_probe_cooldown", 0.0)
		main._tick_garden_greeting(0.016)
		ok(bubble.text() == first, "同一天不会换一句、也不会重喊")
		# 换天再靠近，换一句
		main.set("_garden_spoken_day", -1)
		main.cam.apply_pose()
		main.world_clock.day += 1
		main.set("_garden_probe_cooldown", 0.0)
		main._tick_garden_greeting(0.016)
		await process_frame
		ok(bubble.text() != first, "换一天说的是另一句")
		# 把镜头转到看不见她的方向：气泡应该藏起来，而不是在屏幕边缘挂一张
		# 指向画外的纸条；转回来还要能接着看到。
		# 转动方向没用：相机是绕 target 转的，而 target 就是她本人。
		# 要让她真的出画，得把相机看向别处。
		main.cam.target = body.global_position + Vector3(46.0, 0.0, 0.0)
		main.cam.apply_pose()
		for i in 4:
			await process_frame
		ok(not bubble.visible, "角色出画时气泡收起，不在屏边挂纸条")
		main.cam.target = body.global_position + Vector3.UP * 1.4
		main.cam.apply_pose()
		for i in 4:
			await process_frame
		ok(bubble.visible, "再回到画面里气泡恢复")
	print("[garden-npc] %d checks, %d failures" % [checks, failures])
	finish()

func finish() -> void:
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
