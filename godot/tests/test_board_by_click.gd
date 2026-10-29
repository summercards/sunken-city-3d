extends SceneTree
## 点船就上船；靠岸图标跟着「这次点击会干什么」换宿主。
##
## 起因（2026-10-29）：同一个图标承担上船/靠岸两个方向，却一律钉在码头边缘
## （dockEdge）。船停在它旁边 2.5 米，俯视下图标看起来就压在船上 ——
## 点船像是点了「码头的图标」，动作来源说不清；而船本身点不动。
##
## 本测试锁死四条契约：
##   1. 人在岸上、船在泊位 → 图标贴到船上（点它 / 点船都是上船）；
##   2. 人在船上 → 图标回到码头边缘（点它靠岸）；
##   3. 人在岸上但船不在泊位 → 图标回到码头边缘，不误导；
##   4. 点击船体命中、点远处不命中，且岸上点船会被消费成上船流程。

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	main.cam.suspend_follow()
	var gs: Node = root.get_node("GameState")
	var zones: Node = root.get_node("Zones")
	for i in 12:
		await process_frame

	main.cam.target = main.boat.global_position
	main.cam.distance = 22.0
	main.cam.orbit_dir = Vector3(-0.55, 0.72, 0.42)
	main.cam.refresh()
	for i in 6:
		await process_frame

	var zone: String = String(gs.current_zone)
	var landing: String = String(gs.landing_id)
	var fallback := Vector3(99.0, 99.0, 99.0)

	# 不依赖存档落点：显式把状态摆成「人在岸上、船停在这个泊位」。
	# 套件里每条检查有独立存档，起手可能是船上或别的区块，断言必须自己立前提。
	var l: Dictionary = zones.landing(zone, landing)
	check(not l.is_empty(), "取到当前泊位")
	var park := Vector3(float(l.boatPark[0]), 1.12, float(l.boatPark[2]))
	main.actor_controller.reconcile_mode(0)
	main.boat.place_at(park, float(l.boatYaw))
	for i in 4:
		await process_frame

	# 船位摆好后重新对准镜头，保证 pick_hull 用的屏幕坐标是有效的。
	main.cam.target = main.boat.global_position
	main.cam.refresh()
	for i in 4:
		await process_frame

	check(int(gs.mode) == 0, "起手在岸上")
	check(main.boat.position.distance_to(park) < 0.2, "船停在当前泊位")

	# ---- 1. 岸上：图标贴到船上 ----
	var on_boat: Vector3 = main._landing_icon_world(zone, landing, fallback)
	var flat := Vector2(on_boat.x - main.boat.global_position.x,
		on_boat.z - main.boat.global_position.z).length()
	check(flat < 0.2, "岸上时图标水平贴合船身（实际 %.3f 米）" % flat)
	check(on_boat.y - main.boat.global_position.y > 1.0, "图标抬到船舱上方，不被船体挡住")
	check(on_boat != fallback, "岸上时图标不再留在码头边缘")

	# ---- 4. 点船命中 ----
	var sp: Vector2 = main.cam.unproject_position(main.boat.global_position)
	check(main.boat.pick_hull(sp, main.cam), "点船体命中")
	var far: Vector2 = main.cam.unproject_position(
		main.boat.global_position + Vector3(14.0, 0.0, 0.0))
	check(not main.boat.pick_hull(far, main.cam), "点 14 米外不命中船体")

	# 岸上点船 = 上船流程（返回 true 表示这次点击被消费掉）
	check(main._click_boat(sp), "岸上点船被消费为上船")
	main.actor_controller.cancel()
	await process_frame

	# ---- 2. 船上：图标回到码头边缘 ----
	main.actor_controller.reconcile_mode(1)
	await process_frame
	var on_dock: Vector3 = main._landing_icon_world(zone, landing, fallback)
	check(on_dock == fallback, "在船上时图标回到码头边缘")
	check(not main._click_boat(sp), "在船上点船体不再触发上船")

	# ---- 3. 岸上但船不在泊位：不误导 ----
	main.actor_controller.reconcile_mode(0)
	await process_frame
	var saved: Vector3 = main.boat.position
	main.boat.position += Vector3(8.0, 0.0, 0.0)
	await process_frame
	var away: Vector3 = main._landing_icon_world(zone, landing, fallback)
	check(away == fallback, "船不在泊位时图标留在码头边缘")
	main.boat.position = saved

	print("[board-click] %d checks, %d failures" % [checks, failures])
	quit()
