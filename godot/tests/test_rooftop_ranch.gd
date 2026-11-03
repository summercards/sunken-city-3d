extends SceneTree
## 顶层牧场验收：主场景里的真实区块 + 真实角色链路。
##
## 钉住四件事，任何一件坏了这块农场就退回「看得见、上不去」的景观：
##   1) 水面位置按用户红线：保留段最下面那层消防梯平台（甲板 44.80）在水面上 0.26 米，
##      船正好停在这层平台的外沿，人从这里上船/下船；
##   2) 六段折返梯 + 七层平台 + 入口板 + 楼顶真的连成一片可行走面，不是一段段悬空；
##   3) 楼顶被抬高露台、棚屋、鸡舍、温室、水塔占掉的地方不是地面（既挖走路面，也有物理阻挡）；
##   4) 真实角色按正式链路：靠泊 → 上岸 → 走 15 米楼梯 → 到楼顶草地，而不是只断言路径存在。

const RANCH_SCENE := "res://scenes/facilities/rooftop_ranch.tscn"
const ROOT_Y := -43.42
const WATER_Y := 1.12
const BOARD_DECK_Y := 1.38
const ROOF_WORLD_Y := 16.58
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
	await _test_capsule_climb()
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

## 可行走面：六段梯 + 七层平台 + 入口板 + 楼顶，全部用本地三角形表达。
func _check_walk_surface() -> void:
	check(area.surface_triangles.size() >= 90, "行走面覆盖七层平台、六段梯、入口板和楼顶")
	check(absf(area.surface_y - ROOF_WORLD_Y) < 0.05, "surface_y 是楼顶的世界高度")
	var entry: Vector3 = area.get_node("Landing_main").stand_position()
	var lawn: Vector3 = area.surface_point(Vector3(MAIN_INSTANCE.x, ROOF_WORLD_Y, MAIN_INSTANCE.z))
	check(entry.is_finite() and lawn.is_finite(), "上岸口与楼顶都有有效支撑点")
	var path: Array[Vector3] = area.path_between(entry, lawn)
	check(path.size() >= 6, "上岸口到楼顶的路径穿过楼梯节点（%d 点）" % path.size())
	if path.is_empty():
		return
	var climbed := false
	for point: Vector3 in path:
		if point.y > entry.y + 8.0 and point.y < lawn.y - 0.5:
			climbed = true
			break
	check(climbed, "路径中段确实在爬楼梯，而不是绕到楼顶")

## 楼顶挖洞：抬高露台、棚屋、鸡舍、温室、水塔压住的地方不能当地面。
func _check_roof_cutouts() -> void:
	## 本地 +Z 在世界上仍是 +Z（区块只平移不旋转），所以世界点 = 原点 + 本地偏移。
	var cuts := [
		["抬高露台", Vector3(MAIN_INSTANCE.x - 16.0, ROOF_WORLD_Y, MAIN_INSTANCE.z + 8.0)],
		["棚屋", Vector3(MAIN_INSTANCE.x - 7.0, ROOF_WORLD_Y, MAIN_INSTANCE.z + 9.0)],
		["鸡舍", Vector3(MAIN_INSTANCE.x - 17.0, ROOF_WORLD_Y, MAIN_INSTANCE.z + 0.9)],
		["温室", Vector3(MAIN_INSTANCE.x + 7.0, ROOF_WORLD_Y, MAIN_INSTANCE.z - 7.5)],
		["水塔", Vector3(MAIN_INSTANCE.x + 18.2, ROOF_WORLD_Y, MAIN_INSTANCE.z - 10.0)],
	]
	for row: Array in cuts:
		var point: Vector3 = row[1]
		check(not area.contains_world(point.x, point.z), "楼顶挖掉了%s占地" % row[0])
	var obstacles := ranch.get_node_or_null("ActorObstacles")
	check(obstacles != null, "角色物理阻挡已建立")
	if obstacles != null:
		for id in ["UpperTerrace", "Shed", "Coop", "Greenhouse", "WaterTower"]:
			check(obstacles.get_node_or_null(id) != null, "%s 有角色物理阻挡" % id)
	# 空地仍然可走：楼顶北侧与南侧各取一点。
	check(area.contains_world(MAIN_INSTANCE.x, MAIN_INSTANCE.z + 13.0), "楼顶北侧空草地仍可走")
	check(area.contains_world(MAIN_INSTANCE.x - 5.0, MAIN_INSTANCE.z + 6.0), "楼顶西侧草地仍可走")

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

## 真实胶囊沿路径爬上去：位移要真实发生，终点要落在楼顶。
func _test_capsule_climb() -> void:
	var entry: Vector3 = area.get_node("Landing_main").stand_position()
	var lawn: Vector3 = area.surface_point(Vector3(MAIN_INSTANCE.x, ROOF_WORLD_Y, MAIN_INSTANCE.z))
	var path: Array[Vector3] = area.path_between(entry, lawn)
	if path.is_empty():
		check(false, "胶囊爬楼前需要一条路径")
		return
	var capsule := Character.new()
	root.add_child(capsule)
	capsule.ensure_body()
	# 从甲板上方 0.3 米落下，避免出生就嵌进地板里把整个移动判定卡死。
	capsule.global_position = entry + Vector3.UP * 0.30
	capsule.set_grounded_motion(true)
	await physics_frame
	var start := capsule.global_position
	var moved := 0.0
	for i in 6000:
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
	check(moved > 5.0, "胶囊沿楼梯真实移动了（%.1f 米）" % moved)
	check(capsule.global_position.y > ROOF_WORLD_Y - 1.0, "胶囊爬到了楼顶高度（y=%.2f）" % capsule.global_position.y)
	check(capsule.global_position.distance_to(lawn) < 1.2,
		"胶囊落在楼顶草地（差 %.2f 米）" % capsule.global_position.distance_to(lawn))
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
	var lawn: Vector3 = area.surface_point(Vector3(MAIN_INSTANCE.x, ROOF_WORLD_Y, MAIN_INSTANCE.z))
	check(main.actor_controller.start_walk(area, lawn), "从平台可以走上楼顶")
	for i in 6000:
		main.actor_controller.tick(1.0 / 60.0)
		if not main.actor_controller.walking():
			break
	var top: Vector3 = main.player.global_position
	check(top.y > ROOF_WORLD_Y - 1.0, "角色顺着消防梯走到了楼顶（y=%.2f）" % top.y)
	check(top.distance_to(lawn) < 1.5, "角色落在楼顶草地上（差 %.2f 米）" % top.distance_to(lawn))

func _finish() -> void:
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	print("[rooftop-ranch] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
