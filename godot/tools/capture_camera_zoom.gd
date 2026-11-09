extends SceneTree
## 缩放上限的真实渲染证据（SEA-CAMERA-R11）。
##
## 只抓图与断言，不改玩法：连续往外滚 20 档，距离必须钉在 zoom_max(35.14)；
## 再连续往里滚 20 档，必须停到 zoom_min(13.82)。三个机位各存一张图
## （最远 / 顶到上限后 / 最近），便于肉眼核对「最远 38% / 最近 7%」就是主人给的两张截图取景。
##
## 机位锚在**船**上而不是甲板某点：13.82 m 的最近档离目标只有十几米，
## 对着甲板会被屋子挡住，拍出来是一整屏空景，看不出取景对不对。
##
## 跑法：python3 scripts/run_verification.py visual-camera-zoom

const OUT_DIR := "res://outputs"

var main: Node
var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)


func _init() -> void:
	call_deferred("run")


## 滚轮缩放是「朝光标缩放」：`zoom_action` 会让指针下的那块地保持不动，
## 也就是给 `target` 加位移。抓图工具若固定传屏幕某点（曾经的 540,337），
## 20 档滚下来 target 会被拖到 20 米外，最近那张自然拍成一片空水面 ——
## 看着像「缩到最近就没东西了」，其实是靶子跑了。
## 这里每档都把锚点设在**目标自己的屏幕位置**，缩放只改远近、不搬视点。
func _wheel(cam: Camera3D, factor: float, steps: int) -> void:
	for i in steps:
		cam.zoom_action.execute(cam, factor, cam.unproject_position(cam._cur_target))


func shot(name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null, "frame " + name)
	if image != null:
		check(image.save_png(OUT_DIR + "/" + name) == OK, "saved " + name)
		print("[camera-zoom-shot] ", name, " ", image.get_width(), "x", image.get_height())


## 最近档的方位角：固定顺序试 8 个方位，取第一个「相机位置在水面之上、
## 到船之间没有遮挡」的。遮挡用物理射线判，不靠猜房子在哪。
##
## 之所以按 `zoom_min` 算相机位置而不是 `zoom_max`：近景最容易埋进建筑，
## 远景基本不会；用近景位置选出来的方位，拉到最远只会更开阔。
func _clear_orbit_dir(main: Node, focus: Vector3, dist: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var boat := main.get("boat") as Node3D
	if boat is CollisionObject3D:
		exclude.append((boat as CollisionObject3D).get_rid())
	var fallback := Vector3(-0.5, 0.7, 0.5)
	for i in 8:
		var yaw := TAU * float(i) / 8.0
		var d := Vector3(sin(yaw) * cos(deg_to_rad(44.7)), sin(deg_to_rad(44.7)), cos(yaw) * cos(deg_to_rad(44.7)))
		var probe: Vector3 = focus + d * dist
		if probe.y < 2.5:
			continue
		var query := PhysicsRayQueryParameters3D.create(probe, focus, 0xFFFFFFFF, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			print("[camera-zoom-shot] orbit yaw=%.1f° 无遮挡" % rad_to_deg(yaw))
			return d
	print("[camera-zoom-shot] 8 个方位都有遮挡，退回落日方向")
	return fallback


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	root.get_node("Economy").set_process(false)
	main.world_clock.paused = true
	main.world_clock.from_dict({"day": 1, "seconds": 21 * 3600 + 39 * 60, "day_length": 1200})
	main.daylight_rig.apply(21.65)
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()

	var cam: Camera3D = main.cam
	check(absf(cam.zoom_max - 35.14) < 0.001, "缩放上限=35.14")
	check(absf(cam.zoom_min - 13.82) < 0.001, "缩放下限=13.82")
	# 机位对**船**，不对甲板上的某个点：13.82 m 时镜头离目标只有十来米，
	# 对着甲板块会被屋子/檐口挡住，拍出来是一整屏空景（7% 那张曾是这样，
	# 看着像「缩到最近就没东西了」）。方位角也不钉死：船停在码头边，
	# 换个存档朝向就换一面墙挡镜头，所以这里挑「相机在开阔水面 + 到船无遮挡」的那个方位。
	var boat: Node3D = main.boat
	var focus: Vector3 = boat.global_position + Vector3(0.0, 1.2, 0.0)
	cam.suspend_follow()
	cam.target = focus
	cam.orbit_dir = _clear_orbit_dir(main, focus, cam.zoom_min)
	cam.distance = cam.zoom_max
	cam.refresh()

	# 最远档就是主人给的第一张图：读数必须仍是「视野 38%」。
	check(is_equal_approx(cam.distance, cam.zoom_max), "拉到顶=上限")
	check(absf(cam.zoom_ratio() - 0.38) < 0.01, "最远读作 38%% 实际=%.3f" % cam.zoom_ratio())
	print("[camera-zoom-focus] boat=", boat.global_position, " target=", cam.target)
	check(cam.is_position_in_frustum(boat.global_position), "最远档船在取景内")
	await shot("camera-zoom-far.png")

	# 连续往外滚 20 档：一格 0.86 的倒数，20 档足以从任何位置到顶。
	_wheel(cam, 1.0 / 0.86, 20)
	for i in 20:
		cam._process(1.0 / 60.0)
	check(absf(cam.distance - cam.zoom_max) < 0.001, "滚轮拉不出去 distance=" + str(cam.distance))
	check(absf(cam._cur_distance - cam.zoom_max) < 0.001, "平滑后仍停上限 实际=" + str(cam._cur_distance))
	check(cam.position.distance_to(cam._cur_target) < cam.zoom_max + 0.5, "相机没被甩出上限")
	await shot("camera-zoom-clamped.png")

	# 往里滚到底：下限 9 m 仍然有效，说明上限收紧没有把缩放整体压死。
	_wheel(cam, 0.86, 20)
	# 平滑收敛：ZOOM_DAMP=9，20 帧只走 90%，读数会停在 8.5% 而不是 7%。
	for i in 60:
		cam._process(1.0 / 60.0)
	check(absf(cam.distance - cam.zoom_min) < 0.001, "拉到最近 13.82m 实际=" + str(cam.distance))
	check(absf(cam.zoom_ratio() - 0.07) < 0.01, "最近读作 7%% 实际=%.3f" % cam.zoom_ratio())
	# 最近档最容易出事：镜头离目标只剩十几米，稍有偏移就会埋进建筑，拍出一屏空景。
	print("[camera-zoom-shot] near cam=", cam.global_position, " boat=", boat.global_position,
		" target=", cam._cur_target, " screen=", cam.unproject_position(boat.global_position))
	check(cam.is_position_in_frustum(boat.global_position), "最近档船仍在取景内")
	check(cam.global_position.y > 1.5, "最近档镜头仍在水面之上 y=" + str(cam.global_position.y))
	await shot("camera-zoom-near.png")

	print("[camera-zoom] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
