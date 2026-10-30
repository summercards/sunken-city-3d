extends SceneTree
## 海上地图的原生渲染证据：太阳房、浅水养殖台、以及两块之间的海面各一张。
## 只看「你」和「太阳房」是否同时出现在图上，不替代玩法回归。
var main: Node
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_width() > 0, "captured " + name)
	image.save_png("res://outputs/island-atlas-" + name + ".png")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	main.cam.suspend_follow()
	await process_frame

	var zones: Node = root.get_node("Zones")
	var home: Vector2 = zones.footprint("zone1").get_center()
	var aqua: Vector2 = zones.footprint("zone5").get_center()
	var cases := [
		{"name":"home","pos":Vector3(home.x,1.4,home.y)},
		{"name":"aqua","pos":Vector3(aqua.x,1.4,aqua.y)},
		{"name":"between","pos":Vector3((home.x+aqua.x)*0.5,1.2,(home.y+aqua.y)*0.5)},
	]
	for item in cases:
		main.player.global_position = item.pos
		main.hud.open_tab("map")
		for frame in 18: await process_frame
		check(main.hud.is_panel_open() and main.hud._tab == "map", "map open · " + str(item.name))
		await shot(str(item.name))

	print("[island-atlas-render] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
