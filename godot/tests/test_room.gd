extends SceneTree
## SEA-ROOM 专项：进出房间的过场、剖切、室内行走、床铺睡觉与布置、存档往返。
##
## 不用「只查常量」的写法：每条断言都在真实 main.tscn 上跑一遍，
## 包括真实相机取景的点选、真实胶囊的行走、真实圆幕过场的相位。

var checks := 0
var failures := 0
var main
var room
var service
var rc
var gs


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		root.push_input(event, true)
		await process_frame


func settle(frames := 2) -> void:
	for i in frames:
		await process_frame


func inside_room(node: Node3D) -> bool:
	var local: Vector3 = room.to_local(node.global_position)
	return absf(local.x) < 3.2 and local.z > -3.2 and local.z < 5.2 and absf(node.global_position.y - room.global_position.y) < 1.2


## 床当前占地的房间局部 AABB（含朝向），给"压不压东西"的断言用。
func _bed_rect() -> Rect2:
	var extent: Vector2 = service.bed_extent(service.bed_yaw)
	return Rect2(Vector2(service.bed_position.x, service.bed_position.z) - extent, extent * 2.0)



## 取组件里第一片玻璃（Gloss 角色）的材质，验证室内玻璃覆盖真的挂上了。
func _glass_material(component: Node) -> ShaderMaterial:
	for node in component.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var material: Material = mesh_instance.get_surface_override_material(surface)
			if material is ShaderMaterial and str(material.resource_name) == "SEA_Room_Glass":
				return material as ShaderMaterial
	return null


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.interactor.set_process(false)
	root.get_node("Economy").set_process(false)
	main.cam.set_process(false)
	await settle(3)
	room = main.room
	service = main.room_service
	rc = main.room_controller
	gs = root.get_node("GameState")

	# ---- 结构 -----------------------------------------------------------------
	check(room != null and main._zone_nodes.get("room") == room, "房间作为区块登记（zone_id=room）")
	check(not room.visible and room.process_mode == Node.PROCESS_MODE_DISABLED, "室外时房间收起且不参与处理")
	# 房间位置只为隔离：必须远离所有室外内容（海面 1.12、屋顶 ~11.9、海鸥 14–18、水下）。
	# 不要求它在太阳房上 —— 玩家进屋后看不到外面，位置没有视觉含义。
	check(room.global_position.y > 50.0, "房间远离室外所有内容（海面/屋顶/海鸥飞行层）")
	check(not room.global_position.is_equal_approx(Vector3(2.5, 12.6, 1.0)), "房间不再压在太阳房顶上")
	# 放大 1.5 倍：几何 1:1 建模，scale 在这里。
	check(absf(room.scale.x - 1.5) < 0.001, "房间整体放大 1.5 倍，跟随角色 SCALE")
	var floor_area: Node3D = room.get_node("WalkAreas/Walk_room_floor")
	check(absf(floor_area.surface_y - room.global_position.y) < 0.01, "站立面高度取自房间世界高度")
	check(room.area_at(room.global_position + Vector3(0, 1, 8), 0.6) == null, "房间外的空中不是可走面")
	check(room.area_at(room.global_position + Vector3(0, 0.05, 0), 0.5) != null, "室内中心是可走面")
	var door = main._zone_nodes.zone1.get_node_or_null("Objects/RoomDoor")
	check(door != null, "太阳房入口节点存在")
	check(main._zone_nodes.zone1.get_node_or_null("Objects/SleepCheckpoint") == null, "旧睡觉点已移除")
	check(str(door.verb) == "进入房间", "入口按钮文案是「进入房间」")
	var bed = room.get_node("Furnishings/Bed")
	check(bed != null and bed.id == "room_bed", "床铺是独立可交互物")
	check(not bed.sleep_requested.get_connections().is_empty(), "床铺绑定睡觉命令")
	check(bed.get_node_or_null("Block") != null, "床自带角色遮挡（跟着床走）")
	check(not main._outdoor_nodes().is_empty() and not main._outdoor_nodes().has(room), "室外收起名单不含房间本身")

	# ---- 从门口进屋：点得到、走得到、圆幕无文字 ---------------------------------
	main.restore_world_state({"zone": "zone1", "landing": "main", "mode": 0,
		"player": [8.35, 1.38, 10.6], "far_sea": false})
	main.cam.global_position = Vector3(18.0, 15.0, 26.0)
	main.cam.look_at(door.global_position)
	main.cam.fov = 40
	await settle(2)
	var door_point: Vector2 = main.cam.unproject_position(door.global_position + Vector3.UP * 0.6)
	check(main.hover._pick(door_point).get("node") == door, "门口在画面里点得到")
	await click(door_point)
	await create_timer(0.25).timeout
	check(main.hud.world_actions.active, "点门口弹出操作气泡")
	var first: Button = main.hud.world_actions.buttons[0]
	check(str(first.text).contains("进入房间") or str(first.text) == "", "气泡第一项是进入房间")
	await click(first.get_global_transform_with_canvas() * (first.size * 0.5))
	await create_timer(0.20).timeout
	for i in 900:
		main.actor_controller.tick(1.0 / 60.0)
		main.interactor.active = not main.actor_controller.walking()
		main.interactor.update(1.0 / 60.0, main.interactor.auto_hold)
		if rc.busy:
			break
		if not main.actor_controller.walking() and not rc.busy:
			# 走得到之后由交互器按住完成；没走到就再等一帧。
			main.interactor.update(1.0 / 60.0, main.interactor.auto_hold)
	check(rc.busy, "走到门口后开始进屋过场")
	check(main.input_blocked(), "过场期间输入被锁")
	# 圆幕合拢期间不能有文字（用户要求：进房间的过场不写字）。
	# 用真实时间而不是帧数等：headless 一帧远快于一帧的墙钟时间，数帧会等不到合拢。
	var saw_text := false
	var deadline: int = Time.get_ticks_msec() + 6000
	while rc.busy and Time.get_ticks_msec() < deadline:
		await process_frame
		if main.sleep_curtain.caption.text != "" or main.sleep_curtain.caption.modulate.a > 0.001:
			saw_text = true
	check(not saw_text, "进屋圆幕全程没有文字")
	await create_timer(0.1).timeout
	check(main.sleep_curtain.phase == "idle" and not main.sleep_curtain.visible, "过场结束后圆幕收起")
	check(service.inside, "进屋后状态是「在屋里」")
	check(gs.current_zone == "room", "进屋后当前区块是 room")
	check(room.visible and room.process_mode != Node.PROCESS_MODE_DISABLED, "房间已显示")
	check(not main.zones_root.visible, "室外内容已收起")
	check(inside_room(main.player), "角色站在房间内")
	check(main.hud.is_room_mode(), "界面切到房间模式")
	check(main.hud._room_exit.visible, "右下角出现出门按钮")
	check(not main.hud.corner.toolbar.visible, "屋外工具栏在房间里收起")
	check(main.cam.orbit_only and not main.cam.follow_enabled and not main.cam.pose_lock,
		"相机接管成室内环绕机位（能转、不跟人跑）")
	var cam_gap: float = main.cam.global_position.distance_to(room.center_position())
	check(cam_gap < float(room.camera_pose().distance) * 1.6, "机位在房间附近（按缩放后的距离判），没飘到海上")
	check(absf(main.cam.distance - float(room.camera_pose().distance)) < 0.05, "进屋用的是房间给的默认距离")
	# 房间是室内：窗外与前厅外面不该有海、有天、有任何东西。
	var sea: Node3D = main.world_root.get_node_or_null("Water")
	check(sea != null and not sea.visible, "进屋后海面收起，窗里不会露出海")
	var env: Environment = (main.world_root.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(env.background_mode == Environment.BG_COLOR
		and env.background_color.r < 0.02 and env.background_color.g < 0.02 and env.background_color.b < 0.02,
		"进屋后世界背景是纯黑（不画天空盒）")
	# 海鸥不该飞进卧室。2026-11-06 用户截图里那几个白色剪影就是它们：
	# 进屋时虽然藏了，但 `birds.set_hour` 会在时段切换时把 visible 设回去 ——
	# 「在屋里睡一觉到天亮」正好走这条路径。这里把整条路径演一遍。
	var birds: Node3D = main.bird_root
	check(birds.has_method("set_interior_hidden") and bool(birds.suppressed),
		"进屋后鸟群进入室内抑制")
	birds.set_hour(19.0)
	await settle(1)
	check(not birds.visible, "屋里到 19:00（鸟本该落）仍然不可见")
	birds.set_hour(6.5)
	await settle(1)
	check(not birds.visible, "屋里跨到次日 06:30（鸟本该起飞）仍然不可见")
	# 窗玻璃与前厅玻璃用室内玻璃实例：颜色固定深灰，不会乘上天空色盘读成蓝天。
	var pane := _glass_material(room.get_node("Shell/WallWindow"))
	check(pane != null and bool(pane.get_shader_parameter("interior_glass")), "窗玻璃走室内玻璃（不再取色盘 ice 格）")
	var pane_tint: Color = pane.get_shader_parameter("tint")
	check(pane_tint.v < 0.2, "室内玻璃是近乎无彩的深色，不会读成天空")

	# ---- 房间里的镜头自由：能转、能拉近拉远，但不能把自己转丢 -------------------
	var home_dir: Vector3 = main.cam.orbit_dir
	var home_target: Vector3 = main.cam.target
	main.cam.orbit(deg_to_rad(55.0), 0.0)
	await settle(2)
	check(main.cam.orbit_dir.distance_to(home_dir) > 0.3, "右键拖动可以把镜头绕房间转开")
	check(main.cam.target.distance_to(home_target) < 0.001, "转镜头不会把视点从房间上挪走")
	# 俯仰有上下限，且室内比室外窄（26–72 度）。
	main.cam.orbit(0.0, deg_to_rad(80.0))
	await settle(1)
	var pitch_high := rad_to_deg(asin(clampf(main.cam.dir.y, -1.0, 1.0)))
	check(pitch_high <= 72.5 and pitch_high >= 70.0, "室内俯仰上限收到 72 度左右")
	main.cam.orbit(0.0, deg_to_rad(-120.0))
	await settle(1)
	var pitch_low := rad_to_deg(asin(clampf(main.cam.dir.y, -1.0, 1.0)))
	check(pitch_low >= 25.5 and pitch_low <= 28.0, "室内俯仰下限收到 26 度左右")
	# 缩放：滚轮能拉近拉远，并且被夹在 8–24 之间。
	main.cam.distance = 6.0
	main.cam.refresh()
	check(main.cam.distance >= main.cam.orbit_zoom_min - 0.001, "拉太近会被室内下限挡住")
	main.cam.distance = 60.0
	main.cam.refresh()
	check(main.cam.distance <= main.cam.orbit_zoom_max + 0.001, "拉太远会被室内上限挡住")
	check(main.cam.orbit_zoom_max < main.cam.zoom_max, "室内缩放上限比室外更近")
	# 左键在室内不平移：按住拖动不该改视点（左键留给点地面/点家具）。
	var before_left: Vector3 = main.cam.target
	main.cam.panning = false
	main.cam._begin_pan(Vector2(600, 400))
	check(not main.cam.panning, "室内左键不启动平移")
	check(main.cam.target.distance_to(before_left) < 0.001, "室内左键拖动不改视点")
	# 绕一圈都得能看：每个方位下，朝向镜头那一侧的墙必须收、对面必须留，
	# 而且前厅在镜头这一侧时整座都得收（侧玻璃按法线是「远侧」，会留下暗板）。
	var pivot: Vector3 = room.global_position
	for case in [[0.0, "南"], [90.0, "东"], [180.0, "北"], [270.0, "西"]]:
		var yaw: float = deg_to_rad(float(case[0]))
		var pitch: float = deg_to_rad(47.0)
		main.cam.orbit_dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
		main.cam.refresh()
		main.cam.apply_pose()
		await settle(3)
		var offset: Vector3 = main.cam.global_position - pivot
		var visible_walls := 0
		for path in ["Shell/WallWindow", "Shell/WallDoor", "Shell/WallEast", "Shell/WallWest"]:
			if room.get_node(path).visible:
				visible_walls += 1
		check(visible_walls == 3, "绕到%s侧时正好三面墙可见、朝向镜头的那一面收起" % str(case[1]))
		check(offset.z > 2.4 or room.get_node("Shell/Porch").get_children().size() > 0, "前厅实例一直在场景里")
		if offset.z > 2.4:
			# 站在前厅前面：玻璃、立柱、裙墙、圈梁全都压在镜头与室内之间。
			# 按名字前缀判，不按父子关系 —— 前厅的构件都嵌在 GLB 的
			# `Visual` 节点下，`get_parent()` 指向的是 Visual，不是 Porch。
			var porch_left: Array = []
			var porch_root: Node3D = room.get_node("Shell/Porch")
			for node in porch_root.find_children("*", "Node3D", true, false):
				var label := String(node.name)
				for prefix in room.PORCH_NORMALS:
					if label.begins_with(prefix) and node.visible:
						porch_left.append(label)
					break
			check(porch_left.is_empty(),
				"相机站在前厅前侧时，前厅构件全部收起（不留暗板）：%s" % str(porch_left))

	# 复位成默认机位，后面的剖切断言按 +Z 侧的构图来判。
	main.room_controller._apply_room_camera()
	await settle(3)

	# ---- 剖切：对着镜头的那面墙看不见 -------------------------------------------
	await settle(4)
	var centre: Vector3 = room.global_position
	var cam_offset: Vector3 = main.cam.global_position - centre
	check(not room.get_node("Shell/WallDoor").visible, "镜头侧的墙（+Z 前墙）看不见")
	check(room.get_node("Shell/WallWindow").visible, "对面带窗的后墙可见")
	check(cam_offset.z > 0.0 and room.get_node("Shell/WallWindow").visible, "相机确实在 +Z 一侧")
	check(not room.get_node("Shell/Ceiling").visible, "俯视机位下天花收起，否则整屋看不见")
	check(room.get_node("Shell/Porch").visible, "玻璃前厅在剖切下仍然可见")
	# 反过来把相机放到后墙外侧，藏起来的应该换成后墙。
	main.cam.global_position = centre + Vector3(0.0, 6.0, -8.0)
	await settle(3)
	check(not room.get_node("Shell/WallWindow").visible and room.get_node("Shell/WallDoor").visible,
		"换到另一侧时藏起来的换成那一侧的墙")
	main.cam.global_position = centre + cam_offset
	await settle(3)

	# ---- 室内走动 ---------------------------------------------------------------
	var hit: Dictionary = room.pick_walk(room.global_position + Vector3(1.2, 2.0, 1.4), Vector3.DOWN)
	check(not hit.is_empty(), "室内地面点得到落点")
	var before: Vector3 = main.player.global_position
	check(main._start_walk(hit.area, hit.point), "室内可以走")
	for i in 400:
		main.actor_controller.tick(1.0 / 60.0)
		if not main.actor_controller.walking():
			break
	check(main.player.global_position.distance_to(before) > 0.4, "角色真的走动了")
	check(inside_room(main.player), "走动没有走出房间")

	# ---- 床铺睡觉 ---------------------------------------------------------------
	var day: int = main.world_clock.day
	bed.sleep_requested.emit()
	await main.sleep_cycle.woke
	check(main.world_clock.day == day + 1 and main.world_clock.query().hour == 6.0, "床上睡一觉到次日 06:00")
	check(service.inside and room.visible, "醒来还在房间里")
	check(inside_room(main.player) and main.actor_controller.mode() == 0, "醒来站在床边、岸上姿态")
	check(main.cam.orbit_only and not main.cam.follow_enabled, "醒来仍是室内环绕机位")
	check(main.hud.is_room_mode(), "醒来界面仍是房间模式")

	# ---- 出门 -------------------------------------------------------------------
	main._on_click_command("room_exit")
	await rc.exited
	check(not service.inside, "出门后状态是「在屋外」")
	check(gs.current_zone == "zone1", "出门后回到 zone1")
	check(not room.visible, "房间收起")
	check(main.zones_root.visible, "室外内容恢复")
	check((main.world_root.get_node("Water") as Node3D).visible, "出门后海面恢复可见")
	var birds_out: Node3D = main.bird_root
	check(not bool(birds_out.suppressed), "出门后鸟群的室内抑制解除")
	birds_out.set_hour(6.5)
	await settle(1)
	check(birds_out.visible, "出门且在白天时海鸥照常飞")
	var back_env: Environment = (main.world_root.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(back_env.background_mode == Environment.BG_SKY, "出门后世界背景恢复成天空盒")
	check(not main.hud.is_room_mode() and not main.hud._room_exit.visible, "出门按钮与房间模式撤掉")
	check(not main.cam.pose_lock and not main.cam.orbit_only and main.cam.follow_enabled,
		"相机退出室内环绕、恢复跟随")
	check(main.player.global_position.distance_to(rc.exit_position) < 1.2, "角色站回太阳房门口")
	check(main.validate_world_state(main.capture_world_state()) == "", "出门后的世界状态合法")

	# ---- 床铺布置：位置/朝向由状态拥有，能夹取、能拒绝 ---------------------------
	var placed: Dictionary = service.place_bed(Vector3(0.9, 0.0, -0.9), PI / 2.0)
	check(placed.ok, "床可以搬到别处并旋转")
	check(absf(service.bed_yaw - PI / 2.0) < 0.01, "朝向被记录")
	var clamped: Dictionary = service.place_bed(Vector3(-99.0, 0.0, 99.0), 0.0)
	check(clamped.ok and absf(service.bed_position.x) < 2.0 and absf(service.bed_position.z) < 2.0,
		"超出房间的落点被夹回屋里")
	# 拖到床头柜上 / 拖到门口：不硬拒，就近滑到最近的空位（布置的手感），
	# 但最终落点必须两样都不占。
	var blocked: Dictionary = service.place_bed(Vector3(-0.95, 0.0, -2.29), 0.0)
	check(blocked.ok and str(blocked.get("reason", "")) == "", "拖到床头柜上会被挪到最近的空位")
	check(not _bed_rect().intersects(Rect2(Vector2(-1.235, -2.56), Vector2(0.57, 0.54))),
		"挪开后的床不再压住床头柜")
	var doorway: Dictionary = service.place_bed(Vector3(0.0, 0.0, 2.15), 0.0)
	check(doorway.ok and not _bed_rect().intersects(Rect2(Vector2(-0.85, 1.6), Vector2(1.7, 1.1))),
		"拖到门口会被挪开，床不堵门")
	# 真的没有空位时仍然要拒绝，而不是把人塞进墙里。
	var tiny := Rect2(Vector2(-0.05, -0.05), Vector2(0.1, 0.1))
	check(service._nearest_free(Vector2.ZERO, 0.0, tiny) == Vector2.INF, "没有空位时不返回假落点")
	service.place_bed(Vector3(0.9, 0.0, -0.9), PI / 2.0)
	check(main.room.get_node("Furnishings/Bed").position.distance_to(Vector3(0.9, 0, -0.9)) < 0.01,
		"布局状态落到场景上的床节点")

	# ---- 存档：屋里的位置与床的摆放都能往返 -------------------------------------
	rc.enter(true)
	await settle(2)
	check(service.inside, "再次进屋（瞬时路径）")
	var world: Dictionary = main.capture_world_state()
	check(str(world.zone) == "zone1", "屋里存档把世界位置记成室外门口")
	check(main.validate_world_state(world) == "", "屋里存档的世界状态合法")
	main._save_path = "user://room-save.json"
	var saved: Dictionary = main.save_game("", true)
	check(saved.get("ok", false), "屋里可以存档")
	var reload: Dictionary = preload("res://src/save/save_game.gd").read("user://room-save.json")
	check(reload.get("ok", false) and bool(reload.snapshot.room.inside), "存档记下了「在屋里」")
	check(absf(float(reload.snapshot.room.bed.position[0]) - 0.9) < 0.01, "存档记下了床的位置")
	# 改掉现场状态再读档，确认真的从存档恢复回来。
	rc.exit(true)
	await settle(2)
	check(not service.inside, "读档前先出门")
	var restored: Dictionary = preload("res://src/save/save_game.gd").restore(main, reload.snapshot)
	check(restored.get("ok", false), "读档成功")
	check(service.inside, "读档后回到屋里")
	check(main.room.visible and gs.current_zone == "room", "读档后场景与区块都回到房间")
	check(absf(service.bed_position.x - 0.9) < 0.01, "读档后床在自己被搬到的位置")
	check(main.validate_world_state(main.capture_world_state()) == "", "读档后的世界状态合法")

	# ---- 在屋里读一份「屋外存下的档」：世界必须还原，不能停在黑屏 --------------
	var outside: Dictionary = reload.snapshot.duplicate(true)
	outside.room = {"version": 1, "bed": {"position": [-1.86, 0.0, -1.425], "yaw": 0.0}, "inside": false}
	check(service.inside, "读这份档之前人在屋里")
	var restored_out: Dictionary = preload("res://src/save/save_game.gd").restore(main, outside)
	check(restored_out.get("ok", false), "屋外档读档成功")
	check(not service.inside, "读屋外档后状态是「在屋外」")
	check((main.world_root.get_node("Water") as Node3D).visible, "读屋外档后海面恢复，不是一片黑")
	var out_env: Environment = (main.world_root.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(out_env.background_mode == Environment.BG_SKY, "读屋外档后天空盒恢复")
	check(not room.visible and not main.hud.is_room_mode(), "读屋外档后房间收起、界面退出房间模式")

	# ---- 旧档兼容：没有 room 字段的 v4 存档照样能读 -----------------------------
	var legacy: Dictionary = reload.snapshot.duplicate(true)
	legacy.erase("room")
	legacy.room = {"version": 1, "bed": {"position": [-1.86, 0.0, -1.425], "yaw": 0.0}, "inside": false}
	check(service.validate_snapshot(legacy.room) == "", "默认房间快照合法")

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/room-inside.png")
	print("[room] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
