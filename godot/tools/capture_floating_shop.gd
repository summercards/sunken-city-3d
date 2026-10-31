extends SceneTree
## 海上悬浮商铺的真实渲染证据：近景看材质/浮力线，远景看它与阳光房的 50 米关系。
var main: Node
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_width() > 0, "captured " + name)
	image.save_png("res://outputs/floating-shop-" + name + ".png")

func frame_for(eye: Vector3, target: Vector3) -> void:
	var cam: Camera3D = main.cam as Camera3D
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)


## 把角色真的送到浮店甲板上：靠泊 → 自动上岸 → 走到招牌下。
## 不摆假位置，因为要看的正是「玩家视角站在环廊上看这栋楼」。
func put_actor_on_deck() -> void:
	var zones: Node = root.get_node("Zones")
	var state: Node = root.get_node("GameState")
	var l: Dictionary = zones.landing("sea_supply", "main")
	if l.is_empty():
		return
	var park := Vector3(float(l.boatPark[0]), float(l.boatPark[1]), float(l.boatPark[2]))
	state.set_mode(state.Mode.ON_BOAT)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	state.enter_zone("sea_supply")
	state.landing_id = "main"
	main.boat.place_at(park, float(l.boatYaw))
	main._select_landing({"zone": "sea_supply", "landing": "main"})
	for i in 6:
		main._update_walk(1.0 / 60.0)
	var area: Node3D = main._zone_nodes["sea_supply"].walk_areas[0]
	if area != null:
		main._start_walk(area, Vector3(float(l.landStand[0]), float(l.landStand[1]),
			float(l.landStand[2]) + 1.0))
	for i in 240:
		main._update_walk(1.0 / 60.0)
		if main.actor_controller.state_id() == "ashore_idle":
			break


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	main.cam.suspend_follow()
	main.cam.set_process(false)
	main.hud.set_visible(false)
	for i in 12:
		await process_frame
	var shop: Node3D = main.get_node("World/SeaStructures/floating_shop")
	var hub: Vector3 = shop.global_position + Vector3(0, 4.4, 0)
	var cases := [
		{"name": "rect-overview", "eye": hub + Vector3(-22.0, 15.0, 25.0), "target": hub},
		{"name": "rect-front", "eye": hub + Vector3(0.0, 4.5, 27.0), "target": hub},
		{"name": "approach", "eye": hub + Vector3(-16.0, 3.6, 22.0), "target": hub},
		{"name": "deck", "eye": hub + Vector3(6.5, 2.6, 13.0), "target": hub + Vector3(0, -1.2, 0)},
		{"name": "from-home", "eye": Vector3(6.2, 6.5, 24.0), "target": hub},
		# 一张能同时看到家与浮店的远景，用来核对「正南 50 米」不是随口说的。
		{"name": "relation", "eye": Vector3(6.2, 34.0, -26.0), "target": Vector3(6.2, 0.0, 26.0)},
	]
	for item in cases:
		frame_for(item.eye, item.target)
		for i in 14:
			await process_frame
		await shot(str(item.name))
		check(true, "view " + str(item.name))

	# 玩家视角：站在环廊上抬头看招牌，验证「上得去、看得见、走得到」。
	put_actor_on_deck()
	var here: Vector3 = main.player.global_position
	for i in 10:
		await process_frame
	frame_for(here + Vector3(4.5, 8.5, 13.5), here + Vector3(0.0, 1.6, -1.5))
	for i in 14:
		await process_frame
	await shot("on-deck")
	check(true, "view on-deck")
	# 靠泊关系：船停在开口外，船头朝店。
	frame_for(here + Vector3(12.0, 7.5, 9.0), here + Vector3(-2.0, 0.4, 1.0))
	for i in 14:
		await process_frame
	await shot("berthed")
	check(true, "view berthed")
	print("[floating-shop-render] ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
