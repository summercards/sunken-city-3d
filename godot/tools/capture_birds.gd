extends SceneTree
## 海鸥朝向专项验收：真实渲染近景，证明鼻尖对着飞行方向而不是屁股朝前。
## 运行：python scripts/run_verification.py visual-birds
##
## 为什么单独一个工具：鸥群是从 Three 烘焙的资产，Three 的 lookAt 以 +Z 为前，
## Godot 默认按 -Z 为前，两个约定差 180°。这种错位用包围盒、轨道高度、
## 可见性全都查不出来 —— 只有「鼻尖 vs 切线」这条断言和一张侧拍图能抓住。
var main: Node
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

## 机位不能用 cam.target/distance 摆：orbit camera 的 distance 会被 zoom_min(9.0) 夹住，
## 而海鸥在 19+12≈31 m 高空，9 m 之外只剩米粒大。这里直接停掉跟随逻辑，
## 手动摆 position/look_at —— 短距特写只在这个专项里用，不污染正式相机。
func shot(label: String, target: Vector3, distance: float, orbit: Vector3) -> void:
	var cam: Camera3D = main.cam
	cam.set_process(false)
	cam.global_position = target + orbit.normalized() * distance
	cam.look_at(target, Vector3.UP)
	for i in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/birds-" + label + ".png")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("_autosave_on", false)
	root.get_node("Economy").ticking = false
	for i in 8:
		await process_frame
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()
	var birds: Array = main.bird_root.get_children()
	check(birds.size() >= 5, "海鸥数量够（实际 %d）" % birds.size())
	for b in birds:
		(b as Node3D).set_process(false)
	# 冻结四分之一圈：切线朝向最好读，俯冲与转弯的歧义最小。
	var t := 0.9
	var first: Node3D = birds[0]
	first.sample(t)
	for i in 4:
		await process_frame
	# body 是 parts[0]，锥尖落在局部 +Y（烘焙时被 Three 的 rotation.x=PI/2 从 +Y 转到 +Z）。
	var body: MeshInstance3D = first.get_child(0)
	var nose: Vector3 = (body.global_transform.basis * Vector3(0, 1, 0)).normalized()
	var a: float = t * first.speed + first.phase
	var tangent := Vector3(-sin(a) * first.radius.x, 0, cos(a) * first.radius.y).normalized()
	check(nose.dot(tangent) > 0.9, "鼻尖朝前（dot=%.3f）" % nose.dot(tangent))
	# 侧拍：相机站在切线右侧。鸟头朝画面左/右都行，屁股对着镜头才是回归。
	var right := nose.cross(Vector3.UP).normalized()
	await shot("nose-side", body.global_position, 2.6, right + Vector3.UP * 0.28)
	await shot("nose-front", body.global_position, 2.6, nose + Vector3.UP * 0.3)
	# 全景：整群仍在屋顶上方绕飞，不是贴地穿插。
	await shot("flock-wide", first.flight_center + Vector3.UP * first.altitude, 26.0,
		Vector3(-0.45, 0.8, 0.6))
	print("[birds] ", checks, " checks, failures=", failures)
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
