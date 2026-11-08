extends SceneTree
## sea promo - real-time frame recording (30 FPS / 3600 frames = 120.0 s)
##
##   godot --path project --resolution 1920x1080 --fixed-fps 30 \
##         --write-movie out.avi --script res://tools/record_promo_2min.gd
##
## Timeline (seconds)
##   0.0- 6.0  title, slow dolly in
##   6.0-13.5  home, wide aerial down to deck level
##   13.5-19.0 walk from the dock to the planter
##   19.0-24.5 plant (close-up)
##   24.5-32.5 water, then a time-lapse of growth
##   32.5-38.5 ripe, harvest
##   38.5-44.0 build handbook
##   44.0-54.5 sea expansion: four decks appear one by one
##   54.5-67.0 cast off, sail to Yokohama platform
##   67.0-73.0 supply station
##   73.0-79.0 Yokohama station platform
##   79.0-87.0 back home, dive
##   87.0-98.0 sunken city underwater
##   98.0-110.0 surface, night at home
##   110.0-120.0 pull back, fade out

const TOTAL := 3600
const FPS := 30

var main: Node
var cam: Camera3D
var fade: ColorRect
var f := 0

# Camera intent. Re-asserted every frame so nothing else can steal the shot.
var want_lock := false
var want_target := Vector3.ZERO
var want_dist := 0.0
var want_dir := Vector3.FORWARD
var last_t := 0.0

func _init() -> void:
	call_deferred("run")

func w(n := 1) -> void:
	for i in n:
		await RenderingServer.frame_pre_draw
		_quiet()
		f += 1
		last_t = float(f) / FPS

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
	if want_lock:
		if cam.target.distance_to(want_target) > 0.01 \
				or absf(cam.distance - want_dist) > 0.01 \
				or cam.dir.distance_to(want_dir) > 0.002:
			_apply_pose()

func till(target: int) -> void:
	while f < target:
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
		dir0: Vector3, dir1: Vector3, frames: int) -> void:
	for i in frames:
		var k := smooth(float(i + 1) / float(frames))
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

func fade_to(alpha: float, frames: int) -> void:
	var a0: float = fade.color.a
	for i in frames:
		fade.color.a = lerpf(a0, alpha, float(i + 1) / float(frames))
		await w(1)

func wait_walk(limit: int) -> void:
	var start := f
	while main.actor_controller.walking() and f - start < limit:
		await w(1)

func wait_until(cond: Callable, limit: int) -> void:
	var start := f
	while not cond.call() and f - start < limit:
		await w(1)

func mark(tag: String) -> void:
	print("[mark] %s f=%d t=%.2f" % [tag, f, last_t])

## Chase camera: sit behind and above the boat, keep it in the lower third.
func chase(back: float, side: float, height: float, factor := 1.0) -> void:
	var yaw: float = main.boat.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var off: Vector3 = -fwd * back + right * side + Vector3.UP * height
	pose(main.boat.global_position + Vector3.UP * 1.1, off.length() * factor, off)

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
	eco.give({"wood": 300, "soil": 100, "parts": 60, "coins": 1400, "fish": 40})
	main.boat.speed_multiplier = func() -> float: return 2.0
	main.prompt._panel.hide()
	await w(4)

	# A: title
	mark("A")
	await fade_to(0.0, 22)
	var t0: Vector3 = cam.global_transform.origin
	var fwd0: Vector3 = -cam.global_transform.basis.z
	for i in 116:
		var k := smooth(float(i + 1) / 116.0)
		cam.global_transform = Transform3D(cam.global_transform.basis, t0 + fwd0 * 3.2 * k)
		await w(1)
	await till(sec(5.6))
	await fade_to(1.0, 14)
	main._resume_after_avatar_or_title()
	await w(3)

	# B: home, wide to deck level
	mark("B")
	pose(Vector3(2.5, 2.0, 6.5), 78.0, Vector3(-0.55, 0.50, 0.63))
	await fade_to(0.0, 18)
	await glide(Vector3(2.5, 2.0, 6.5), Vector3(2.0, 1.9, 7.5), 78.0, 40.0,
		Vector3(-0.55, 0.50, 0.63), Vector3(-0.40, 0.42, 0.80), 105)
	await glide(Vector3(2.0, 1.9, 7.5), Vector3(1.5, 1.7, 9.5), 40.0, 26.0,
		Vector3(-0.40, 0.42, 0.80), Vector3(-0.28, 0.36, 0.89), 70)
	await till(sec(13.5))

	# C: walk to the planter
	mark("C")
	follow(18.0, Vector3(-0.30, 0.50, 0.81))
	var plot: Node3D = main.farm_field.find("home_plot")
	await w(4)
	main._approach(plot)
	await wait_walk(180)
	await w(4)
	print("[rec] player=", main.player.global_position, " plot=", plot.global_position)
	await till(sec(19.0))

	# D: plant
	mark("D")
	var box: Vector3 = plot.global_position + Vector3(0, 0.55, 0)
	pose(box, 10.6, Vector3(-0.62, 0.52, 0.59))
	await w(8)
	print("[rec] plant=", plot.perform("plant", "lettuce"))
	await w(44)
	await glide(box, box + Vector3(0.0, 0.08, 0.0), 10.6, 9.2,
		Vector3(-0.62, 0.52, 0.59), Vector3(-0.58, 0.48, 0.66), 30)
	await till(sec(24.5))

	# E: water, then time-lapse
	mark("E")
	await w(4)
	print("[rec] water=", plot.perform("water", ""))
	await w(36)
	for step in 16:
		eco.farm.debug_set_growth("home_plot", 0.92 - 0.92 * float(step) / 15.0, true)
		if step % 4 == 0:
			pose(box + Vector3(0, 0.10, 0), maxf(8.0, want_dist - 0.18), want_dir)
		await w(10)
	print("[rec] grown phase=", eco.farm.phase("home_plot"))
	await till(sec(32.5))

	# F: harvest
	mark("F")
	pose(box + Vector3(0, 0.05, 0), 8.4, Vector3(-0.52, 0.46, 0.72))
	await w(24)
	print("[rec] harvest=", plot.perform("harvest", ""))
	await w(56)
	await till(sec(38.5))

	# G: build handbook
	mark("G")
	follow(15.0, Vector3(-0.35, 0.52, 0.78))
	await w(6)
	main._on_click_command("craft")
	await w(62)
	await till(sec(43.0))
	main.building_controller.close()
	await w(10)
	await till(sec(44.0))

	# H: sea expansion
	mark("H")
	main.boat.place_at(Vector3(-6.4, 1.12, 8.2), 0.6)
	main.actor_controller.restore_pose({"mode": 1})
	var site := Vector3(-9.2, 1.62, 3.1)
	pose(site, 12.0, Vector3(-0.45, 0.58, 0.68))
	await w(12)
	var cells := [Vector2(-14, -4), Vector2(-13, -4), Vector2(-14, -5), Vector2(-13, -5)]
	for cell in cells:
		var req := {"kind": "deck", "x": cell.x, "y": 0.0, "z": cell.y, "origin": "boat"}
		var res: Dictionary = main.building.begin(req)
		if not bool(res.get("ok", false)):
			print("[rec] deck fail ", cell, " ", res)
			continue
		for i in 30:
			main.building.tick(0.11)
			await w(1)
		main.building.tick(1.0)
		await w(6)
	print("[rec] decks rows=", main.building.query().size())
	await w(8)
	await glide(site, Vector3(-6.4, 2.2, 5.4), 12.0, 21.0,
		Vector3(-0.45, 0.58, 0.68), Vector3(-0.16, 0.50, 0.85), 50)
	await glide(Vector3(-6.4, 2.2, 5.4), Vector3(1.5, 2.4, 7.0), 21.0, 50.0,
		Vector3(-0.16, 0.50, 0.85), Vector3(0.14, 0.50, 0.85), 66)
	await till(sec(54.5))

	# I: cast off, sail to the Yokohama platform
	mark("I")
	pose(Vector3(3.0, 1.7, 13.5), 19.0, Vector3(-0.26, 0.36, 0.90))
	await w(24)
	main._select_landing({"zone": "zone2", "landing": "main"})
	await wait_until(func() -> bool: return main.actor_controller.mode() == 2, 200)
	print("[rec] sailing f=", f)
	await w(6)
	chase(11.0, 2.0, 5.6)
	await w(100)
	chase(9.0, -2.5, 4.0)
	await w(90)
	chase(15.0, 4.0, 8.5, 1.05)
	await w(80)
	await wait_until(func() -> bool: return not main.boat.starts_sailing(), 200)
	print("[rec] docked f=", f)
	await w(30)
	chase(13.0, 3.0, 7.0)
	await w(20)
	await till(sec(67.0))

	# J: supply station
	mark("J")
	main._debug_teleport("sea_supply")
	await w(6)
	var shop := Vector3(147.571, 4.4, 143.891)
	pose(shop + Vector3(15, 6.5, 17), 30.0, Vector3(0.60, 0.50, 0.62))
	await glide(shop + Vector3(15, 6.5, 17), shop + Vector3(19, 3.6, 21), 30.0, 21.0,
		Vector3(0.60, 0.50, 0.62), Vector3(0.54, 0.30, 0.79), 84)
	await till(sec(73.0))

	# K: Yokohama station
	mark("K")
	main._debug_teleport("zone2")
	await w(4)
	var st := Vector3(-30.0, 4.2, -18.0)
	pose(st + Vector3(-15, 7, 17), 25.0, Vector3(-0.48, 0.44, 0.76))
	await glide(st + Vector3(-15, 7, 17), st + Vector3(-7, 3.6, 13), 25.0, 16.0,
		Vector3(-0.48, 0.44, 0.76), Vector3(-0.38, 0.28, 0.88), 88)
	await till(sec(79.0))

	# L: home, dive
	mark("L")
	main._debug_teleport("zone1")
	await w(6)
	pose(Vector3(3.0, 1.9, 8.0), 32.0, Vector3(-0.48, 0.46, 0.75))
	await glide(Vector3(3.0, 1.9, 8.0), Vector3(3.2, 1.6, 15.0), 32.0, 18.0,
		Vector3(-0.48, 0.46, 0.75), Vector3(-0.30, 0.36, 0.88), 54)
	await w(4)
	main._on_dive()
	await wait_until(func() -> bool: return main.dive.active and not main.dive.switching, 220)
	print("[rec] dive f=", f, " map=", main.dive.map_id)
	await w(10)
	await till(sec(87.0))

	# M: sunken city
	mark("M")
	var rt = main.dive.runtime
	var ctl = rt.get("dive_controller")
	await fade_to(1.0, 8)
	rt.debug_teleport(Vector3(-25.0, 5.0, -30.0))
	if ctl != null:
		ctl.yaw = 2.05
		ctl.pitch = 0.10
	main.dive.toggle_lamp()
	await w(10)
	await fade_to(0.0, 14)
	await w(26)
	print("[rec] uw0=", rt.diver_pos)
	if ctl != null:
		ctl.yaw = 2.55
	await w(78)
	print("[rec] uw1=", rt.diver_pos)
	main.dive.swim_to(rt.diver_pos + Vector3(-9.0, 1.0, -11.0))
	await w(76)
	if ctl != null:
		ctl.yaw = 3.05
	await w(46)
	print("[rec] uw2=", rt.diver_pos)
	if ctl != null:
		ctl.yaw = 2.45
		ctl.pitch = -0.30
	await w(46)
	await till(sec(98.0))

	# N: surface, night
	mark("N")
	main.dive.surface()
	await wait_until(func() -> bool: return not main.dive.active, 380)
	await w(10)
	main._debug_set_clock(1, 21.0 * 3600.0)
	await w(16)
	pose(Vector3(3.0, 2.3, 7.0), 26.0, Vector3(-0.48, 0.40, 0.78))
	await glide(Vector3(3.0, 2.3, 7.0), Vector3(3.0, 2.5, 8.5), 26.0, 18.0,
		Vector3(-0.48, 0.40, 0.78), Vector3(-0.28, 0.32, 0.90), 84)
	await glide(Vector3(3.0, 2.5, 8.5), Vector3(2.0, 3.0, 4.0), 18.0, 32.0,
		Vector3(-0.28, 0.32, 0.90), Vector3(-0.52, 0.46, 0.72), 76)
	await till(sec(110.0))

	# O: finale
	mark("O")
	await glide(Vector3(2.0, 3.0, 4.0), Vector3(0.0, 4.6, 0.0), 32.0, 90.0,
		Vector3(-0.52, 0.46, 0.72), Vector3(-0.62, 0.50, 0.60), 200)
	await w(40)
	await fade_to(1.0, 50)
	await till(TOTAL)
	mark("END")
	quit()
