extends SceneTree
## 诊断：靠岸后键位与 E 键的可达性缺口（2026-11-06）。
## 只打印事实，不断言；用来定位「哪里按 E 没用」而不是猜。

var main: Node
var state: Node


func _init() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func press(actions: Array) -> void:
	release_all()
	for a in actions:
		Input.action_press(a)


func release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	state = root.get_node("GameState")
	root.get_node("Economy").ticking = false
	await frames(12)
	main.cam.suspend_follow()

	state.enter_zone("zone1")
	state.landing_id = "main"
	var landing: Node3D = main._current_landing()
	var data: Dictionary = main._landing_data("zone1", "main")
	var park := Vector3(float(data.boatPark[0]), 1.12, float(data.boatPark[2]))
	main.boat.place_at(park, float(data.boatYaw))
	main.actor_controller.restore_pose({"mode": 1})
	await frames(6)

	print("[gap] mode=", main.actor_controller.mode(), " docking=", main._landing_is_docked(),
		" key_action=", main._boat_key_action(), " shortcut='", main._boat_shortcut_text(), "'")
	print("[gap] player=", main.player.global_position, " stand=", landing.stand_position(),
		" dist=", flat(main.player.global_position, landing.stand_position()))

	# 船上朝「岸那边」按方向键。方向是镜头相对的，先把镜头前向对准登陆点，
	# 这样 move_forward 就等于「按玩家心里的往岸上走」（SEA-MOVE-R24）。
	var boat0: Vector3 = main.boat.position
	var stand0: Vector3 = landing.stand_position()
	var shore := Vector3(stand0.x - boat0.x, 0.0, stand0.z - boat0.z).normalized()
	main.cam.suspend_follow()
	main.cam.target = boat0
	main.cam.position = boat0 - shore * 24.0 + Vector3.UP * 20.0
	main.cam.look_at(boat0, Vector3.UP)
	main.cam._cur_target = boat0
	press(["move_forward"])
	for i in 30:
		main._update_keyboard_move(1.0 / 60.0)
		main.actor_controller.tick(1.0 / 60.0)
		main.boat._process(1.0 / 60.0)
		await process_frame
	print("[gap] 船上朝岸按方向键 30帧: boat_moved=", flat(boat0, main.boat.position),
		" mode=", main.actor_controller.mode(), " sailing=", main.boat.starts_sailing(),
		" driving=", main.boat.driving(), " toast='", main.hud.toast_snapshot().text, "'")
	release_all()
	main.boat.stop_drive()

	# 上岸后八方向能不能走
	main.boat.place_at(park, float(data.boatYaw))
	main.actor_controller.restore_pose({"mode": 1})
	await frames(4)
	var boarded: bool = main._toggle_boat_by_key()
	await frames(90)
	print("[gap] E 上岸 ->", boarded, " mode=", main.actor_controller.mode(),
		" pos=", main.player.global_position, " toilet=", main.hud.toast_snapshot().text)
	var stand: Vector3 = main.player.global_position
	for pair in [["move_forward", Vector2(0, -1)], ["move_back", Vector2(0, 1)],
			["move_left", Vector2(-1, 0)], ["move_right", Vector2(1, 0)]]:
		main.actor_controller.restore_pose({"mode": 0, "player": [stand.x, stand.y, stand.z]})
		await frames(3)
		main.actor_controller.walk_area = landing.ground()
		var from: Vector3 = main.player.global_position
		press([pair[0]])
		for i in 40:
			main._update_keyboard_move(1.0 / 60.0)
			main.actor_controller.tick(1.0 / 60.0)
			main.player._process(1.0 / 60.0)
			await physics_frame
		var moved: float = flat(from, main.player.global_position)
		print("[gap] 岸上 %s 40帧 位移=%.3f m  state=%s" % [pair[0], moved, main.actor_controller.state_id()])
		release_all()

	# 岸上所有可交互物：E 能不能选中
	main.actor_controller.restore_pose({"mode": 0, "player": [stand.x, stand.y, stand.z]})
	await frames(20)
	print("[gap] interactor active=", main.interactor.active, " target=", main.interactor.target)
	var here: Vector3 = main.player.global_position
	for node in get_nodes_in_group("interactable"):
		var spot: Node3D = node
		if not is_instance_valid(spot) or not spot.is_visible_in_tree():
			continue
		var focus: Vector3 = spot.focus_position() if spot.has_method("focus_position") else spot.global_position
		var d := flat(here, focus)
		if d > 14.0:
			continue
		print("[gap] 物 %-28s dist=%.2f radius=%.2f can=%s reach='%s' verb=%s" % [
			spot.name, d, float(spot.effective_focus_radius()) if spot.has_method("effective_focus_radius") else -1.0,
			spot.can_interact(), main._land_reach_reason(spot), str(spot.verb)])

	# 海面可拾取物：有没有键位入口
	var near: Dictionary = main.props.nearest_crate(main.player.global_position, 60.0)
	if not near.is_empty():
		var root: Node3D = near.root
		print("[gap] 最近漂流物 ", root.global_position, " 距=", flat(here, root.global_position))
	else:
		print("[gap] 60 米内无漂流物")
	print("[gap] props pick 接口=", main.props.has_method("pick"), " nets=", main.props.crates.size(), " schools=", main.props.schools.size())

	# 全量可交互物：按区域归组，看谁「站不到跟前」
	var by_zone := {}
	for node in get_nodes_in_group("interactable"):
		var s2: Node3D = node
		if not is_instance_valid(s2):
			continue
		var kind_value: Variant = s2.get("kind")
		var kind := "" if kind_value == null else str(kind_value)
		var zone_of := ""
		for id2 in main._zone_nodes.keys():
			if main._zone_nodes[id2].is_ancestor_of(s2):
				zone_of = id2
				break
		var fp: Vector3 = s2.focus_position() if s2.has_method("focus_position") else s2.global_position
		var standable := ""
		for id3 in main._zone_nodes.keys():
			var z3: Node = main._zone_nodes[id3]
			if z3.has_method("area_at"):
				var a3: Variant = z3.area_at(fp, 1.4)
				if a3 != null:
					standable = id3
					break
		var verb_value: Variant = s2.get("verb")
		var key := "%s/%s" % [zone_of, "?" if verb_value == null else str(verb_value)]
		by_zone[key] = int(by_zone.get(key, 0)) + 1
		if kind != "" or str(verb_value) == "采集":
			print("[gap] 采集点 zone=%-10s kind=%-6s standable=%-6s pos=%s vis=%s" % [
				zone_of, kind, standable, fp, s2.is_visible_in_tree()])
	print("[gap] 交互物统计 ", by_zone)
	print("[gap] gather 节点=", main.gather, " spots=", main.gather.spots.size() if main.gather != null else -1)
	if main.gather != null:
		for sp in main.gather.spots.slice(0, 12):
			print("[gap] spot %-14s in_group=%s in_tree=%s vis=%s pos=%s avail=%s" % [
				str(sp.name), sp.is_in_group("interactable"), sp.is_inside_tree(),
				sp.is_visible_in_tree(), sp.global_position, str(sp.get("available"))])

	# 场景里所有 zone 的登陆点/采集点数量
	for id in main._zone_nodes.keys():
		var zone: Node = main._zone_nodes[id]
		var landings: Array = zone.landing_points() if zone.has_method("landing_points") else []
		print("[gap] zone=", id, " landings=", landings.size(), " walk_areas=", zone.walk_areas.size())

	main.queue_free()
	await process_frame
	quit(0)
