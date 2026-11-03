extends SceneTree
## 顶层牧场 v005 验收：主场景里的真实区块 + 水面以上单段消防梯。
##
## 钉住四件事：水线、单段梯、上岸点、模型与 WalkArea 一致。
## v005 明确不把水下楼层、剩余消防梯或楼顶路线伪造成可行走。

const RANCH_SCENE := "res://scenes/facilities/rooftop_ranch.tscn"
const ROOT_Y := -43.68
const WATER_Y := 1.12
const BOARD_DECK_Y := 1.38
const UPPER_DECK_WORLD_Y := 3.88
const MAIN_INSTANCE := Vector3(46.0, ROOT_Y, -52.0)

var checks := 0
var failures := 0
var main: Node
var ranch: Node3D
var area: Node3D

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 12:
		await process_frame
	ranch = main._zone_nodes.get("rooftop_ranch", null)
	check(ranch != null, "main 里登记了 rooftop_ranch（顶层牧场）")
	if ranch == null:
		_finish()
		return
	check(ranch.zone_label == "顶层牧场", "区块名就是「顶层牧场」")
	check(ranch.global_position.is_equal_approx(MAIN_INSTANCE), "摆在家园东南约 60 米的开阔海面")
	area = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
	_check_waterline()
	_check_walk_surface()
	_check_roof_cutouts()
	_test_independent_upgrades()
	_check_boat_park_clearance()
	await _test_capsule_single_flight()
	await _test_formal_flow()
	_finish()

## 水面与上岸口：平台甲板只比水面高 0.26 米，和码头/浮店的登船高差一致。
func _check_waterline() -> void:
	var landing: Node3D = area.get_node("Landing_main")
	var stand: Vector3 = landing.stand_position()
	var park: Marker3D = landing.get_node("BoatPark")
	check(absf(stand.y - BOARD_DECK_Y) < 0.05, "上岸口站在甲板上（y=%.2f）" % stand.y)
	check(absf(park.global_position.y - WATER_Y) < 0.05, "船位落在水面（y=%.2f）" % park.global_position.y)
	check(stand.y - park.global_position.y > 0.15 and stand.y - park.global_position.y < 0.45,
		"甲板比船位高 0.26 米量级（实测 %.2f）" % (stand.y - park.global_position.y))
	check(ranch.global_position.y + ranch.board_deck_local_y() - WATER_Y < 0.30,
		"水面没有淹到上岸平台")
	var edge: Marker3D = landing.get_node("DockEdge")
	check(edge.global_position.x > stand.x, "上船边在平台外沿一侧")
	check(absf(edge.global_position.y - BOARD_DECK_Y) < 0.05, "上船边与甲板同高")

## 可行走面：只覆盖水面以上的一段梯、下平台和上平台；与可见模型严格一致。
func _check_walk_surface() -> void:
	check(area.surface_triangles.size() == 18, "行走面只有下平台、单段斜梯和上平台")
	check(absf(area.surface_y - UPPER_DECK_WORLD_Y) < 0.05, "surface_y 是单段消防梯上平台高度")
	var entry: Vector3 = area.get_node("Landing_main").stand_position()
	var upper: Vector3 = area.surface_point(Vector3(MAIN_INSTANCE.x + 26.0, UPPER_DECK_WORLD_Y, MAIN_INSTANCE.z + 2.0))
	check(entry.is_finite() and upper.is_finite(), "上下两个平台都有有效支撑点")
	var path: Array[Vector3] = area.path_between(entry, upper)
	check(path.size() >= 3 and path.size() <= 20, "上岸口到单段梯上平台路径长度正确（%d 点）" % path.size())
	check(upper.y > entry.y + 1.5 and upper.y < entry.y + 3.0, "单段梯确实只上升约 2.5 米")
	# 不能把水塔屋顶等高处伪造成可走面。
	check(not area.surface_point(Vector3(MAIN_INSTANCE.x, UPPER_DECK_WORLD_Y + 10.0, MAIN_INSTANCE.z)).is_finite(), "楼顶高处没有被伪造为通行面")

## v005 楼顶不在当前可行走范围，相关缺口不参与本轮通行判定。
func _check_roof_cutouts() -> void:
	var obstacles: Node = ranch.get_node_or_null("ActorObstacles")
	check(obstacles != null, "角色物理阻挡已建立")
	# 仍要求可见的单段上平台与其 WalkArea 对齐。
	check(area.contains_world(MAIN_INSTANCE.x + 26.0, MAIN_INSTANCE.z + 2.0), "单段消防梯上平台可走")
	check(not area.surface_point(Vector3(MAIN_INSTANCE.x, UPPER_DECK_WORLD_Y + 10.0, MAIN_INSTANCE.z)).is_finite(), "楼顶不属于当前WalkArea")

func _test_independent_upgrades() -> void:
	var greenhouse_unbuilt := ranch.get_node("Models/ORF4_温室_升级前_待建木料堆")
	var greenhouse_complete := ranch.get_node("Models/ORF4_温室_升级后_完整设施")
	var tower_unbuilt := ranch.get_node("Models/ORF4_水塔_升级前_卧放罐体与木支架材料")
	var tower_complete := ranch.get_node("Models/ORF4_水塔_升级后_已搭建")
	check(greenhouse_unbuilt.visible and tower_unbuilt.visible, "默认是升级前的木料堆与卧放水罐")
	check(not greenhouse_complete.visible and not tower_complete.visible, "升级后的两态默认隐藏")
	ranch.set_greenhouse_upgrade_state("complete")
	check(not greenhouse_unbuilt.visible and greenhouse_complete.visible, "温室两态互斥")
	check(tower_unbuilt.visible and not tower_complete.visible, "温室切换不影响水塔")
	ranch.set_water_tower_upgrade_state("complete")
	check(not tower_unbuilt.visible and tower_complete.visible, "水塔两态互斥")
	ranch.set_greenhouse_upgrade_state("unbuilt")
	ranch.set_water_tower_upgrade_state("unbuilt")

## 船位必须是开阔水面（离建筑与平台都留出靠泊余量）。
func _check_boat_park_clearance() -> void:
	var park: Vector3 = area.get_node("Landing_main/BoatPark").global_position
	check(main._is_open_water(park.x, park.z), "船位是开阔水面，没压在建筑阻挡里")
	var edge: Vector3 = area.get_node("Landing_main/DockEdge").global_position
	check(Vector2(edge.x - park.x, edge.z - park.z).length() < 2.0, "上船边紧邻船位")

## 真实胶囊走完这一段：不能把后续不存在的楼梯当作通行目标。
func _test_capsule_single_flight() -> void:
	var entry: Vector3 = area.get_node("Landing_main").stand_position()
	var upper: Vector3 = area.surface_point(Vector3(MAIN_INSTANCE.x + 26.0, UPPER_DECK_WORLD_Y, MAIN_INSTANCE.z + 2.0))
	var path: Array[Vector3] = area.path_between(entry, upper)
	check(not path.is_empty(), "单段消防梯有可走路径")
	if path.is_empty():
		return
	var capsule := Character.new()
	root.add_child(capsule)
	capsule.ensure_body()
	capsule.global_position = entry + Vector3.UP * 0.30
	capsule.set_grounded_motion(true)
	await physics_frame
	var moved := 0.0
	for i in 1800:
		if path.is_empty():
			break
		var target: Vector3 = path[0]
		var delta := target - capsule.global_position
		if Vector2(delta.x, delta.z).length() < 0.06 and absf(delta.y) < 0.12:
			path.pop_front()
			continue
		var step := delta.normalized() * minf(delta.length(), 2.3 / 60.0)
		var before := capsule.global_position
		capsule.move_ground(step, 1.0 / 60.0)
		moved += capsule.global_position.distance_to(before)
	check(moved > 2.0, "胶囊沿单段消防梯真实移动了（%.1f 米）" % moved)
	check(capsule.global_position.y > entry.y + 1.5 and capsule.global_position.y < upper.y + 0.8,
		"胶囊停在单段消防梯上平台高度（y=%.2f）" % capsule.global_position.y)
	capsule.queue_free()
	await process_frame

## 正式链路：把船摆到泊位，走 _step_ashore / actor_controller 上岸，再走上楼顶。
func _test_formal_flow() -> void:
	var state: Node = root.get_node("GameState")
	var landing: Node3D = area.get_node("Landing_main")
	var park: Marker3D = landing.get_node("BoatPark")
	var stand: Vector3 = landing.stand_position()
	state.enter_zone("rooftop_ranch")
	state.landing_id = "main"
	state.set_mode(state.Mode.ON_BOAT)
	main.boat.place_at(park.global_position, park.global_rotation.y)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	check(main._current_landing() == landing, "当前泊位解析到顶层牧场入口")
	check(main._step_ashore(), "靠泊后可以上岸")
	for i in 600:
		main.actor_controller.tick(1.0 / 60.0)
		if not main.actor_controller.walking():
			break
	var landed: Vector3 = main.player.global_position
	check(landed.distance_to(stand) < 1.0, "角色站到了上岸平台（差 %.2f 米）" % landed.distance_to(stand))
	check(absf(landed.y - BOARD_DECK_Y) < 0.4, "角色在上岸平台的高度上（y=%.2f）" % landed.y)
	var upper: Vector3 = area.surface_point(Vector3(MAIN_INSTANCE.x + 26.0, UPPER_DECK_WORLD_Y, MAIN_INSTANCE.z + 2.0))
	check(main.actor_controller.start_walk(area, upper), "角色可以走完露出水面的单段消防梯")
	for i in 1800:
		main.actor_controller.tick(1.0 / 60.0)
		if not main.actor_controller.walking():
			break
	var top: Vector3 = main.player.global_position
	check(top.y > stand.y + 1.5 and top.y < upper.y + 0.8,
		"角色停在单段消防梯上平台（y=%.2f）" % top.y)
	# 楼顶没有外接可走梯，正式链路必须拒绝直接跳到楼顶。
	var roof_probe: Vector3 = area.surface_point(Vector3(MAIN_INSTANCE.x, UPPER_DECK_WORLD_Y + 10.0, MAIN_INSTANCE.z))
	check(not roof_probe.is_finite(), "未露出的楼顶不被误判为可走")

func _finish() -> void:
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	print("[rooftop-ranch] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
