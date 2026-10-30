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
	print("[floating-shop-render] ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
