extends SceneTree
## sea gameplay showcase v3 - 120 s, this-week updates foregrounded.
##
##   godot --path project --resolution 1920x1080 --fixed-fps 30 \
##         --write-movie out.avi --script res://tools/record_showcase_2min.gd
##
## Timeline (seconds)
##   0.0- 6.0  title
##   6.0-12.0  home, aerial down to deck
##  12.0-24.0  sunroom: broken ladder -> repair -> climb -> upper deck restored
##  24.0-32.0  plant, water, time-lapse, harvest (new hand gesture)
##  32.0-42.0  build handbook, sea expansion: four decks
##  42.0-52.0  cast off, sail out
##  52.0-64.0  gift kiosk: POSTCARDS exterior, awning, interior
##  64.0-74.0  shop icon grid UI, talk to the shopkeeper
##  74.0-88.0  neon garden: three towers, garden bridge, rooftop greeting bubble
##  88.0-102.0 dive, canyon of towers underwater
## 102.0-112.0 surface, night
## 112.0-120.0 pull back, fade

const TOTAL := 3600
const FPS := 30

var main: Node
var cam: Camera3D
var fade: ColorRect
var f := 0
var want_lock := false
var want_target := Vector3.ZERO
var want_dist := 0.0
var want_dir := Vector3.FORWARD

func _init() -> void:
	call_deferred("run")

func w(n := 1) -> void:
	for i in n:
		await RenderingServer.frame_pre_draw
		_quiet()
		f += 1

func _quiet() -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.hud != null:
		main.hud._zoom_left = 0.0
		if main.hud._zoom != null:
			main.hud._zoom.visible = false
		main._zoom_seen = main.cam.distance
	if main.prompt != null and main.prompt._panel != null:
		main.prompt._panel.visible = false
	if want_lock and (cam.target.distance_to(want_target) > 0.01
			or absf(cam.distance - want_dist) > 0.01
			or cam.dir.distance_to(want_dir) > 0.002):
		_apply_pose()

func till(t: int) -> void:
	while f < t:
		await w(1)

func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func sec(s: float) -> int:
	return int(round(s * FPS))

func _apply_pose() -> void:
	cam.follow_enabled = false
	cam.pose_lock = true
	cam.orbit_only = false
	cam.target = want_target
	cam.distance = want_dist
	cam.orbit_dir = want_dir
	cam.dir = want_dir
	cam._cur_target = want_target
	cam._cur_distance = want_dist
	cam._update_pose()

func pose(t: Vector3, d: float, dir: Vector3) -> void:
	want_lock = true
	want_target = t
	want_dist = d
	want_dir = dir.normalized()
	_apply_pose()

func glide(t0: Vector3, t1: Vector3, d0: float, d1: float,
		dir0: Vector3, dir1: Vector3, n: int) -> void:
	for i in n:
		var k := smooth(float(i + 1) / float(n))
		pose(t0.lerp(t1, k), lerpf(d0, d1, k), dir0.lerp(dir1, k))
		await w(1)

func follow(distance: float, dir: Vector3) -> void:
	want_lock = false
	cam.pose_lock = false
	cam.orbit_only = false
	cam.orbit_dir = dir.normalized()
	cam.dir = dir.normalized()
	cam.distance = distance
	cam.resume_follow()

func fade_to(a: float, n: int) -> void:
	var a0: float = fade.color.a
	for i in n:
		fade.color.a = lerpf(a0, a, float(i + 1) / float(n))
		await w(1)

func wait_walk(limit: int) -> void:
	var s := f
	while main.actor_controller.walking() and f - s < limit:
		await w(1)

func wait_until(c: Callable, limit: int) -> void:
	var s := f
	while not c.call() and f - s < limit:
		await w(1)

func mark(tag: String) -> void:
	print("[mark] %s f=%d t=%.2f" % [tag, f, float(f) / FPS])

func chase(back: float, side: float, height: float) -> void:
	var yaw: float = main.boat.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var off: Vector3 = -fwd * back + right * side + Vector3.UP * height
	pose(main.boat.global_position + Vector3.UP * 1.1, off.length(), off)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	cam = main.cam
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.07, 0.10, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 200
	main.add_child(layer)
	layer.add_child(fade)
	var eco := root.get_node("Economy")
	eco.give({"wood": 90, "soil": 30, "glass": 10, "parts": 20, "coins": 3200, "fish": 20})
	main.boat.speed_multiplier = func() -> float: return 1.9
	main.prompt._panel.hide()
	await w(4)

	# A title
	mark("A")
	await fade_to(0.0, 22)
	var t0: Vector3 = cam.global_transform.origin
	var fwd0: Vector3 = -cam.global_transform.basis.z
	for i in 112:
		var k := smooth(float(i + 1) / 112.0)
		cam.global_transform = Transform3D(cam.global_transform.basis, t0 + fwd0 * 3.0 * k)
		await w(1)
	await till(sec(5.4))
	await fade_to(1.0, 14)
	main._resume_after_avatar_or_title()
	await w(4)

	# B home
	mark("B")
	pose(Vector3(2.5, 2.0, 6.5), 74.0, Vector3(-0.55, 0.50, 0.63))
	await fade_to(0.0, 18)
	await glide(Vector3(2.5, 2.0, 6.5), Vector3(2.2, 1.9, 7.6), 74.0, 38.0,
		Vector3(-0.55, 0.50, 0.63), Vector3(-0.40, 0.42, 0.80), 70)
	await till(sec(12.0))

	# C sunroom repair chain (11-07 update)
	mark("C")
	var base := Vector3(4.66225, 1.38, 2.708127)
	var roof := Vector3(4.66225, 5.476335, 2.708127)
	main.actor_controller.restore_pose({"mode": 0, "player": [4.66, 1.38, 3.30]})
	main.player.visible = false   # 这一段的主体是梯子，角色先不入画。
	await w(10)
	# C1 broken ladder
	pose(Vector3(4.66, 2.55, 2.71), 8.6, Vector3(-0.72, 0.28, 0.63))
	await w(36)
	print("[rec] stage=", eco.sunroom.stage)
	# C2 repair, ladder becomes solid
	print("[rec] repair=", eco.sunroom.repair_ladder())
	await w(26)
	await glide(Vector3(4.66, 2.55, 2.71), Vector3(4.66, 2.20, 2.71), 8.6, 7.4,
		Vector3(-0.72, 0.28, 0.63), Vector3(-0.74, 0.22, 0.63), 26)
	await w(14)
	# C3 climb：角色出现，等于一次剪辑切点。
	main.player.visible = true
	await w(4)
	var lb: Node = main.sunroom_surface.find_child("SunroomLadderBottom", true, false)
	print("[rec] climb=", main.actor_controller.climb_ladder(base, roof, lb))
	want_lock = false
	cam.pose_lock = false
	await w(6)
	for i in 200:
		var p: Vector3 = main.player.global_position
		pose(Vector3(p.x, p.y + 0.9, p.z), 7.4, Vector3(-0.46, 0.22, 0.86))
		await w(1)
		if not main.actor_controller.climbing():
			break
	# C4 upper deck, then restore
	await w(10)
	pose(Vector3(4.66, 6.6, 2.71), 12.0, Vector3(-0.58, 0.30, 0.76))
	await w(30)
	print("[rec] restore=", eco.sunroom.restore_upper())
	await w(24)
	pose(Vector3(4.66, 6.9, 2.71), 15.0, Vector3(-0.62, 0.34, 0.71))
	await w(30)
	await till(sec(24.0))

	# D plant / water / harvest (11-08 hand gesture)
	mark("D")
	follow(17.0, Vector3(-0.30, 0.50, 0.81))
	var plot: Node3D = main.farm_field.find("home_plot")
	await w(4)
	main._approach(plot)
	await wait_walk(150)
	var box: Vector3 = plot.global_position + Vector3(0, 0.55, 0)
	pose(box, 10.4, Vector3(-0.62, 0.52, 0.59))
	await w(6)
	print("[rec] plant=", plot.perform("plant", "lettuce"))
	await w(26)
	await w(4)
	print("[rec] water=", plot.perform("water", ""))
	await w(24)
	for step in 14:
		eco.farm.debug_set_growth("home_plot", 0.92 - 0.92 * float(step) / 13.0, true)
		if step % 4 == 0:
			pose(box + Vector3(0, 0.10, 0), maxf(8.2, want_dist - 0.16), want_dir)
		await w(8)
	print("[rec] grown=", eco.farm.phase("home_plot"))
	await w(10)
	pose(box + Vector3(0, 0.05, 0), 8.4, Vector3(-0.52, 0.46, 0.72))
	await w(14)
	print("[rec] harvest=", plot.perform("harvest", ""))
	await w(50)
	await till(sec(32.0))

	# E build handbook + sea expansion
	mark("E")
	follow(15.0, Vector3(-0.35, 0.52, 0.78))
	await w(4)
	main._on_click_command("craft")
	await w(46)
	await till(sec(36.5))
	main.building_controller.close()
	await w(8)
	main.boat.place_at(Vector3(-6.4, 1.12, 8.2), 0.6)
	main.actor_controller.restore_pose({"mode": 1})
	var site := Vector3(-9.2, 1.62, 3.1)
	pose(site, 12.0, Vector3(-0.45, 0.58, 0.68))
	await w(10)
	for cell in [Vector2(-14, -4), Vector2(-13, -4), Vector2(-14, -5), Vector2(-13, -5)]:
		var res: Dictionary = main.building.begin({"kind": "deck", "x": cell.x, "y": 0.0, "z": cell.y, "origin": "boat"})
		if not bool(res.get("ok", false)):
			print("[rec] deck fail ", cell, " ", res)
			continue
		for i in 22:
			main.building.tick(0.15)
			await w(1)
		main.building.tick(1.0)
		await w(3)
	print("[rec] decks=", main.building.query().size())
	await glide(site, Vector3(1.0, 2.3, 6.2), 12.0, 44.0,
		Vector3(-0.45, 0.58, 0.68), Vector3(0.10, 0.48, 0.87), 60)
	await till(sec(42.0))

	# F cast off
	mark("F")
	pose(Vector3(3.0, 1.7, 13.5), 19.0, Vector3(-0.26, 0.36, 0.90))
	await w(12)
	main._select_landing({"zone": "sea_supply", "landing": "main"})
	await wait_until(func() -> bool: return main.actor_controller.mode() == 2, 200)
	print("[rec] sailing f=", f)
	await w(6)
	chase(11.0, 2.0, 5.4)
	await w(80)
	chase(9.0, -2.5, 4.0)
	await w(70)
	await wait_until(func() -> bool: return not main.boat.starts_sailing(), 220)
	print("[rec] docked f=", f)
	await w(8)
	await till(sec(52.0))

	# 海底地图有几百兆，等到下潜那一刻才开始加载会让圆幕黑掉近 4 秒。
	# 提前发起线程加载，真正下潜时直接命中缓存。
	ResourceLoader.load_threaded_request("res://scenes/underwater/sunroom_region.tscn", "PackedScene")

	# G gift kiosk
	mark("G")
	var kiosk: Node3D = main.get_node_or_null("World/SeaStructures/floating_shop")
	var kp: Vector3 = kiosk.global_position
	pose(kp + Vector3(0, 3.4, 0), 30.0, Vector3(-0.62, 0.40, 0.68))
	await w(6)
	await glide(kp + Vector3(0, 3.4, 0), kp + Vector3(0, 3.6, 0), 30.0, 20.0,
		Vector3(-0.62, 0.40, 0.68), Vector3(0.10, 0.30, 0.95), 66)
	await w(8)
	# sign close
	pose(kp + Vector3(0, 5.2, 0), 13.0, Vector3(0.16, 0.24, 0.96))
	await w(30)
	# interior：从门口往里看，货架、柜台、店老板同框
	pose(kp + Vector3(0, 2.6, 0), 6.2, Vector3(0.05, 0.18, 0.98))
	await w(36)
	pose(kp + Vector3(0, 3.2, 3.0), 8.0, Vector3(0.0, 0.18, 0.98))
	await w(32)
	await till(sec(64.0))

	# H shop grid + talk
	mark("H")
	main.shop_panel.open_shop("shop_general")
	await w(40)
	await till(sec(68.0))
	main.shop_panel.close()
	await w(10)
	# player on deck in front of the door
	main.actor_controller.restore_pose({"mode": 0, "player": [kp.x, 1.384, kp.z + 7.6]})
	await w(12)
	var nwp = main.get("npc_world_presenter")
	print("[rec] open=", nwp.open_npc("npc_bao_he"))
	pose(kp + Vector3(0, 2.9, 3.0), 17.0, Vector3(0.06, 0.26, 0.96))
	await w(50)
	await till(sec(74.0))

	# I neon garden
	mark("I")
	nwp.cancel_session()
	await w(10)
	main._debug_teleport("neon_garden_quarter")
	await w(8)
	# 先给完整街区：三栋楼、菜园桥、屋顶。
	pose(Vector3(106.0, 11.0, 86.0), 94.0, Vector3(-0.52, 0.40, 0.75))
	await w(6)
	await glide(Vector3(106.0, 11.0, 86.0), Vector3(106.0, 14.0, 81.0), 94.0, 62.0,
		Vector3(-0.52, 0.40, 0.75), Vector3(-0.66, 0.30, 0.69), 96)
	await w(6)
	# 船开进招呼半径，豆豆才抬头喊一句。
	main.boat.place_at(Vector3(106.0, 1.12, 66.0), 0.0)
	main.actor_controller.restore_pose({"mode": 1})
	var mu = nwp.actor("npc_mu_he")
	var mp: Vector3 = mu.global_position
	await wait_until(func() -> bool: return main._garden_bubble != null and main._garden_bubble.is_speaking(), 200)
	print("[rec] bubble=", main._garden_bubble.is_speaking() if main._garden_bubble else false)
	# 中景：豆豆在菜畦里，头顶气泡带箭头。
	await glide(Vector3(106.0, 14.0, 81.0), mp + Vector3(0, 1.3, 0), 62.0, 12.0,
		Vector3(-0.66, 0.30, 0.69), Vector3(-0.28, 0.22, 0.93), 70)
	await w(80)
	# 再拉回：把气泡留在画面里，同时露出三栋楼和菜园桥。
	await glide(mp + Vector3(0, 1.3, 0), Vector3(106.0, 12.0, 84.0), 12.0, 78.0,
		Vector3(-0.28, 0.22, 0.93), Vector3(-0.52, 0.40, 0.75), 96)
	await w(20)
	await till(sec(88.0))

	# J dive, canyon
	mark("J")
	main._debug_teleport("zone1")
	await w(6)
	pose(Vector3(3.0, 1.9, 8.0), 30.0, Vector3(-0.48, 0.46, 0.75))
	await glide(Vector3(3.0, 1.9, 8.0), Vector3(3.2, 1.6, 14.0), 30.0, 17.0,
		Vector3(-0.48, 0.46, 0.75), Vector3(-0.30, 0.36, 0.88), 40)
	await w(4)
	main._on_dive()
	await wait_until(func() -> bool: return main.dive.active and not main.dive.switching, 220)
	print("[rec] dive f=", f)
	await w(10)
	var rt = main.dive.runtime
	var dcam: Camera3D = rt.get_node_or_null("Camera") as Camera3D
	await fade_to(1.0, 8)
	rt.debug_teleport(Vector3(-34.0, -14.0, 92.0))
	main.dive.toggle_lamp()
	await w(10)
	# 沟里 40 米宽，跟进相机贴墙会把两侧楼全挤出画外；这里直接把相机架在沟中央、
	# 沿 +X 看过去，两侧楼墙才同时入画。
	var eye := Vector3(-34.0, -13.0, 92.0)
	if dcam != null:
		dcam.global_position = eye
		dcam.rotation = Vector3(0.045, -1.5708, 0.0)
		dcam.fov = 74.0
	await fade_to(0.0, 14)
	await w(20)
	print("[rec] canyon=", rt.diver_pos)
	# 沿沟前游，相机跟着平移，机位始终在沟中央。
	main.dive.swim_to(rt.diver_pos + Vector3(28.0, 0.0, 0.0))
	for i in 108:
		eye.x += 28.0 / 108.0
		if dcam != null:
			dcam.global_position = eye
			dcam.rotation = Vector3(0.045, -1.5708, 0.0)
		await w(1)
	print("[rec] canyon2=", rt.diver_pos)
	# 抬头看楼缝里的水面天光。
	if dcam != null:
		dcam.rotation = Vector3(-0.30, -1.5708, 0.0)
	await w(56)
	await till(sec(102.0))

	# K surface, night
	mark("K")
	main.dive.surface()
	await wait_until(func() -> bool: return not main.dive.active, 380)
	await w(8)
	main._debug_set_clock(1, 21.0 * 3600.0)
	await w(14)
	pose(Vector3(3.0, 2.3, 7.0), 26.0, Vector3(-0.48, 0.40, 0.78))
	await glide(Vector3(3.0, 2.3, 7.0), Vector3(3.0, 2.5, 8.6), 26.0, 18.0,
		Vector3(-0.48, 0.40, 0.78), Vector3(-0.28, 0.32, 0.90), 70)
	await glide(Vector3(3.0, 2.5, 8.6), Vector3(2.0, 3.0, 4.0), 18.0, 32.0,
		Vector3(-0.28, 0.32, 0.90), Vector3(-0.52, 0.46, 0.72), 66)
	await till(sec(112.0))

	# L finale
	mark("L")
	await glide(Vector3(2.0, 3.0, 4.0), Vector3(0.0, 4.6, 0.0), 32.0, 88.0,
		Vector3(-0.52, 0.46, 0.72), Vector3(-0.62, 0.50, 0.60), 170)
	await w(30)
	await fade_to(1.0, 46)
	await till(TOTAL)
	mark("END")
	quit()
