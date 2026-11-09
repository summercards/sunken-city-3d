extends SceneTree
## sea gameplay trailer — 90 s, 60 fps, real gameplay only.
##
##   godot --path project --resolution 1920x1080 --fixed-fps 60 \
##         --write-movie out.avi --script res://tools/record_promo_90s.gd
##
## Timeline (seconds)      shot / what the player does
##   0.4- 6.0  arrival      the skiff rows home across open water, low over the surface
##   6.0- 8.8  the house    docked, rise to the deck, step ashore
##   8.8-12.2  walk         walk from the dock to the planter
##  12.2-15.6  plant        seed the plot (close-up)
##  15.6-18.0  water        water it
##  18.0-21.0  growth       16-step growth time-lapse
##  21.0-24.4  harvest      bend, lift, into the bag
##  24.4-28.0  handbook     the build handbook
##  28.0-39.6  expansion    four decks assembled one by one on open water
##  39.6-41.8  reveal       pull back: the new ground beside the house
##  41.8-44.6  cast off     the boat leaves the dock
##  44.6-49.6  at sea       chase camera, wake
##  49.6-56.4  driftwood    row over, stop, gather bar, +7 wood
##  56.4-60.0  dive         sail past the home shallows, iris closes
##  60.0-68.6  the reef     shallow coral garden: swim, sink, find, open a chest
##  68.6-70.0  surface      back up
##  70.0-72.6  dusk         windows come on
##  72.6-76.0  the room     enter, the bedroom
##  76.0-78.6  night        back outside, the house glowing
##  78.6-87.8  wide         all the way out, every window lit
##  87.8-90.0  fade out
##
## Every gameplay input below goes through the same entry point a player's click or
## key press reaches: boarding via the landing marker, walking via _approach,
## planting via FarmPlot.perform, building via begin/tick, salvage via
## _press_sea_pick, diving via _on_dive, the room via room_controller.enter,
## sleeping via _rest_for_day. No visible teleport, no faked reward: boat
## positions between acts are set inside a cut, the way a player would have
## simply sailed there.

const FPS := 60
const TOTAL := 5400
const WATER := 1.12
const HOME_PARK := Vector3(3.066625, 1.12, 20.53675)

var main: Node
var cam: Camera3D
var eco
var fade: ColorRect
var f := 0
var last_t := 0.0

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
		last_t = float(f) / float(FPS)

## Two UI elements are chrome for a still frame, not gameplay: the zoom readout
## (it re-arms every time the camera moves) and the bottom action card (it sits
## there the whole time you stand next to a hotspot).
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

func sec(s: float) -> int:
	return int(round(s * FPS))

func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

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

func chase(back: float, side: float, height: float) -> void:
	var yaw: float = main.boat.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var off: Vector3 = -fwd * back + right * side + Vector3.UP * height
	pose(main.boat.global_position + Vector3.UP * 1.1, off.length(), off)

func fade_to(alpha: float, frames: int) -> void:
	var a0: float = fade.color.a
	for i in frames:
		fade.color.a = lerpf(a0, alpha, float(i + 1) / float(frames))
		await w(1)

func wait_until(cond: Callable, limit: int) -> int:
	var start := f
	while not cond.call() and f - start < limit:
		await w(1)
	return f - start

func mark(tag: String) -> void:
	print("[mark] %s f=%d t=%.2f" % [tag, f, last_t])

func gates() -> String:
	return ("title=%s exh=%s sw=%s climb=%s sleep=%s roombusy=%s modal=%s salv=%s ord=%s camp=%s grade=%s mode=%s sail=%s dive=%s phase=%s inside=%s" % [
		str(main._title_active), str(main._exhausted_rest), str(main.dive.switching),
		str(main.actor_controller.climbing()), str(main.sleep_cycle.busy),
		str(main.room_controller.busy), str(main.hud.is_modal()),
		str(main.salvage_panel.is_open()), str(main.order_panel.is_open()),
		str(main.cam_panel.is_open()), str(main.grade.visible),
		str(main.actor_controller.mode()), str(main.boat.starts_sailing()),
		str(main.dive.active), str(main._pick_phase), str(main.room_service.inside)])

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	cam = main.cam
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.06, 0.09, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 200
	main.add_child(layer)
	layer.add_child(fade)
	eco = root.get_node("Economy")
	eco.give({"wood": 300, "soil": 100, "glass": 40, "parts": 60, "coins": 1400, "fish": 40})
	main.boat.speed_multiplier = func() -> float: return 2.6
	main.prompt._panel.hide()
	await w(6)
	# Leave the title screen the same way the "开始游戏" button does.
	main._resume_after_avatar_or_title()
	await w(6)
	print("[rec] title_active=", main._title_active)

	# ── A. arrival ───────────────────────────────────────────────────────
	mark("A")
	await fade_to(0.0, 22)
	var park := HOME_PARK
	var out_dir := Vector3(-0.46, 0.0, 0.89).normalized()
	main.boat.place_at(park + out_dir * 10.5, atan2(-out_dir.x, -out_dir.z))
	main.actor_controller.restore_pose({"mode": 2})
	await w(6)
	chase(6.6, 0.0, 1.0)
	await w(6)
	var sail_start := f
	var path: Array = main.plan_route_to(park.x, park.z)
	main.boat.sail_to(park, PI, "zone1", "main", path)
	main.actor_controller.request_mode(2)
	while main.boat.starts_sailing() and f - sail_start < 290:
		var k := clampf(float(f - sail_start) / 170.0, 0.0, 1.0)
		chase(lerpf(6.6, 10.2, k), lerpf(0.0, 2.6, k), lerpf(1.0, 5.4, k * k))
		await w(1)
	print("[rec] arrival sail frames=", f - sail_start)
	var settle := f
	while f - settle < 36:
		chase(10.8, 3.0, 6.0)
		await w(1)
	await till(sec(6.0))

	# ── B. the house ─────────────────────────────────────────────────────
	mark("B")
	pose(Vector3(1.6, 1.9, 8.2), 27.0, Vector3(-0.34, 0.38, 0.86))
	await w(6)
	main._select_landing({"zone": "zone1", "landing": "main"})
	await wait_until(func() -> bool: return main.actor_controller.mode() == 0, 260)
	print("[rec] ashore mode=", main.actor_controller.mode())
	await glide(Vector3(1.6, 1.9, 8.2), Vector3(1.2, 1.8, 8.6), 27.0, 20.0,
		Vector3(-0.34, 0.38, 0.86), Vector3(-0.26, 0.34, 0.90), 50)
	await till(sec(8.8))

	# ── C. walk to the planter ───────────────────────────────────────────
	mark("C")
	follow(14.5, Vector3(-0.28, 0.46, 0.84))
	var plot: Node3D = main.farm_field.find("home_plot")
	await w(3)
	main._approach(plot)
	var walked := await wait_until(func() -> bool: return not main.actor_controller.walking(), 210)
	print("[rec] walk frames=", walked)
	await till(sec(12.2))

	# ── D. plant ─────────────────────────────────────────────────────────
	mark("D")
	var box: Vector3 = plot.global_position + Vector3(0, 0.62, 0)
	pose(box, 9.0, Vector3(-0.58, 0.48, 0.66))
	await w(10)
	print("[rec] plant=", plot.perform("plant", "lettuce"))
	await w(50)
	await glide(box, box + Vector3(0.0, 0.06, 0.0), 9.0, 8.4,
		Vector3(-0.58, 0.48, 0.66), Vector3(-0.54, 0.44, 0.72), 34)
	await till(sec(15.6))

	# ── E. water ─────────────────────────────────────────────────────────
	mark("E")
	await w(4)
	print("[rec] water=", plot.perform("water", ""))
	await w(60)
	await till(sec(18.0))

	# ── F. growth time-lapse ─────────────────────────────────────────────
	mark("F")
	for step in 16:
		eco.farm.debug_set_growth("home_plot", 0.92 - 0.92 * float(step) / 15.0, true)
		if step % 4 == 0:
			pose(box + Vector3(0, 0.08, 0), maxf(7.2, want_dist - 0.14), want_dir)
		await w(10)
	print("[rec] phase=", eco.farm.phase("home_plot"))
	await till(sec(21.0))

	# ── G. harvest ───────────────────────────────────────────────────────
	mark("G")
	pose(box + Vector3(0, 0.04, 0), 7.6, Vector3(-0.50, 0.42, 0.76))
	await w(14)
	print("[rec] harvest=", plot.perform("harvest", ""))
	await w(126)
	await till(sec(24.4))

	# ── H. build handbook ────────────────────────────────────────────────
	mark("H")
	follow(13.5, Vector3(-0.32, 0.48, 0.82))
	await w(6)
	main._on_click_command("craft")
	await w(70)
	await till(sec(27.8))
	main.building_controller.close()
	await w(6)

	# ── I. sea expansion: four decks ───────────────────────────────────
	# Cut to the boat: building on open water needs you aboard. The boat is
	# parked well to one side so it never covers the platform being built.
	mark("I")
	var mtoast: Node = main.hud._toast_box
	if mtoast != null:
		mtoast.visible = false
	main.boat.place_at(Vector3(-2.0, WATER, 9.5), 0.9)
	main.actor_controller.restore_pose({"mode": 1})
	var site := Vector3(-8.0, 1.7, 5.0)
	pose(site, 24.0, Vector3(-0.34, 0.52, 0.78))
	await w(12)
	var cells := [Vector2(-14, -4), Vector2(-13, -4), Vector2(-14, -5), Vector2(-13, -5)]
	for cell in cells:
		var req := {"kind": "deck", "x": cell.x, "y": 0.0, "z": cell.y, "origin": "boat"}
		var res: Dictionary = main.building.begin(req)
		if not bool(res.get("ok", false)):
			print("[rec] deck fail ", cell, " ", res)
			continue
		for i in 38:
			main.building.tick(0.09)
			await w(1)
		main.building.tick(1.0)
		await w(5)
	print("[rec] decks rows=", main.building.query().size())
	await w(6)
	# rise over the new floor: platform, house and boat in one clean frame
	await glide(site, Vector3(-7.0, 2.2, 3.4), 24.0, 30.0,
		Vector3(-0.34, 0.52, 0.78), Vector3(0.55, 0.50, 0.67), 50)
	await till(sec(39.6))

	# ── J. reveal: the new floor beside the old house ───────────────────
	mark("J")
	await glide(Vector3(-7.0, 2.2, 3.4), Vector3(-7.0, 2.2, 3.4), 30.0, 39.0,
		Vector3(0.55, 0.50, 0.67), Vector3(0.58, 0.44, 0.69), 54)
	await till(sec(41.8))

	# ── K. cast off ──────────────────────────────────────────────────────
	mark("K")
	main.boat.place_at(Vector3(1.5, WATER, 24.0), PI)
	main.actor_controller.restore_pose({"mode": 2})
	pose(Vector3(2.0, 1.5, 18.0), 13.5, Vector3(-0.20, 0.32, 0.92))
	await w(12)
	var goal := Vector3(-2.0, WATER, 44.0)
	var p2: Array = main.plan_route_to(goal.x, goal.z)
	main.boat.sail_to_point(goal, p2)
	print("[rec] cast off sailing=", main.boat.starts_sailing())
	await till(sec(44.6))

	# ── L. at sea ────────────────────────────────────────────────────────
	mark("L")
	var sail2 := f
	while main.boat.starts_sailing() and f - sail2 < 240:
		var k2 := clampf(float(f - sail2) / 200.0, 0.0, 1.0)
		chase(lerpf(9.2, 12.2, k2), lerpf(-1.6, 2.4, k2), lerpf(3.8, 6.4, k2))
		await w(1)
	await till(sec(49.6))

	# ── M. driftwood ─────────────────────────────────────
	# Side-on, level with the water: the boat, the bundle, and the bar over the
	# sailor's head all readable in one frame.
	mark("M")
	var boat_p: Vector3 = main.boat.global_position
	var best_d := 9999.0
	var best: Dictionary = {}
	for c in main.props.crates:
		var r: Node3D = c.get("root")
		if not is_instance_valid(r):
			continue
		var d := Vector2(r.global_position.x - boat_p.x, r.global_position.z - boat_p.z).length()
		if d < best_d:
			best_d = d
			best = c
	if best.is_empty():
		print("[rec] no driftwood")
	else:
		var wroot: Node3D = best["root"]
		var dest := wroot.global_position
		var dirv := Vector3(dest.x - boat_p.x, 0.0, dest.z - boat_p.z).normalized()
		var side := Vector3(-dirv.z, 0.0, dirv.x)
		main.boat.place_at(dest - dirv * 5.2, atan2(dirv.x, dirv.z))
		main.actor_controller.restore_pose({"mode": 2})
		await w(8)
		var mid: Vector3 = main.boat.global_position.lerp(dest, 0.62)
		mid.y = dest.y + 0.35
		var cam_dir := (side - dirv * 0.25 + Vector3(0.0, 0.50, 0.0)).normalized()
		pose(mid, 15.5, cam_dir)
		await w(14)
		var cand: Dictionary = main._sea_pick_candidate()
		print("[rec] pickup cand=", cand.get("type"), " d=", cand.get("dist"))
		if not cand.is_empty():
			main._press_sea_pick(cand)
			var gather_seen := false
			var ps := f
			while main._pick_phase != 0 and f - ps < 420:
				if main._pick_phase == 1:
					pose(mid, 15.5, cam_dir)
				elif main._pick_phase == 2 and not gather_seen:
					gather_seen = true
					pose(mid, 13.0, cam_dir)
				await w(1)
			print("[rec] pickup frames=", f - ps, " phase=", main._pick_phase)
			await w(16)
	await till(sec(55.2))

	# ── N. sail out past the home shallows, then dive ────────────────────
	# 家园周围 60 米内的下水点都归「家园海底」：那是 120 米深的旧城，画面偏黑。
	# 浅湾珊瑚园（水深 11 米，紫粉珊瑚 + 光束 + 两个宝箱）要开到锚点 60 米外、
	# 离横滨最近的那片水面才会命中。所以这一段是真开船出去，再下水。
	mark("N")
	main._cancel_pending_pick()
	main.boat.place_at(Vector3(-58.0, WATER, -26.0), 3.05)
	main.actor_controller.restore_pose({"mode": 2})
	await w(4)
	chase(8.2, 1.0, 2.9)
	await w(16)
	print("[rec] dive spot ", main.boat.global_position,
		" source=", main._dive_source_at(main.boat.global_position))
	main._on_dive()
	var dv := await wait_until(func() -> bool: return main.dive.active and not main.dive.switching, 340)
	print("[rec] dive frames=", dv, " map=", main.dive.map_id)
	await till(sec(60.4))

	# ── O. the reef: swim, sink, find a chest, open it ───────────────────
	mark("O")
	var rt = main.dive.runtime
	if rt == null:
		print("[rec] dive runtime missing")
	else:
		var ctl = rt.get("dive_controller")
		var chests: Array = rt.get("_chests")
		main.dive.toggle_lamp()
		# The spawn framing is the good one: coral garden ahead, light shafts
		# overhead. Don't fight it with a forced yaw.
		await w(46)
		print("[rec] reef depth=", rt.dive_water_level() - rt.diver_pos.y, " pos=", rt.diver_pos)
		# drift forward a little, deeper, staying in the garden
		main.dive.swim_to(rt.diver_pos + Vector3(-2.0, -2.4, -3.0))
		await w(40)
		print("[rec] reef2 depth=", rt.dive_water_level() - rt.diver_pos.y)
		# the real loop: navigate to the chest, hold while the search runs,
		# and stay on it until it actually opens.
		if chests.size() > 0:
			var pick: Dictionary = chests[0]
			var chest_d := 9999.0
			for c in chests:
				var d: float = rt.diver_pos.distance_to(c["pos"])
				if d < chest_d:
					chest_d = d
					pick = c
			print("[rec] chest target=", pick["name"], " at ", pick["pos"], " d=", chest_d,
				" depth=", rt.dive_water_level() - pick["pos"].y)
			rt._visit_chest(pick)
			var i := 0
			while not bool(pick["opened"]) and i < 460:
				await w(1)
				i += 1
			print("[rec] chest opened=", pick["opened"], " frames=", i,
				" depth=", rt.dive_water_level() - rt.diver_pos.y)
			await w(26)
	await till(sec(68.6))

	# ── P. surface ───────────────────────────────────────────────────────
	mark("P")
	main.dive.surface()
	await wait_until(func() -> bool: return not main.dive.active, 300)
	await w(10)
	await till(sec(70.6))

	# ── Q. dusk ──────────────────────────────────────────────────────────
	mark("Q")
	main._debug_set_clock(1, 18.2 * 3600.0)
	await w(14)
	pose(Vector3(3.0, 2.2, 7.0), 25.0, Vector3(-0.46, 0.40, 0.79))
	await w(6)
	main._debug_set_clock(1, 19.9 * 3600.0)
	await glide(Vector3(3.0, 2.2, 7.0), Vector3(3.0, 2.4, 8.2), 25.0, 18.0,
		Vector3(-0.46, 0.40, 0.79), Vector3(-0.28, 0.34, 0.90), 66)
	await till(sec(73.0))

	# ── R. the room ──────────────────────────────────────────────────────
	mark("R")
	main.room_controller.enter(false)
	var ent := await wait_until(func() -> bool: return not main.room_controller.busy, 220)
	print("[rec] room enter frames=", ent)
	await w(6)
	pose(Vector3(0, 200.6, 0), 13.2, Vector3(-0.26, 0.42, 0.87))
	await w(30)
	await glide(Vector3(0, 200.6, 0), Vector3(0, 200.6, 0), 13.2, 11.0,
		Vector3(-0.26, 0.42, 0.87), Vector3(-0.10, 0.50, 0.86), 50)
	await till(sec(76.4))

	# ── S. night outside ─────────────────────────────────────────────────
	mark("S")
	main.room_controller.exit(false)
	await wait_until(func() -> bool: return not main.room_controller.busy, 220)
	main._debug_set_clock(1, 20.6 * 3600.0)
	await w(6)
	pose(Vector3(2.6, 2.1, 7.6), 22.0, Vector3(-0.42, 0.40, 0.82))
	await glide(Vector3(2.6, 2.1, 7.6), Vector3(2.2, 2.3, 8.4), 22.0, 16.5,
		Vector3(-0.42, 0.40, 0.82), Vector3(-0.24, 0.34, 0.91), 44)
	await till(sec(79.2))

	# ── T. night wide ────────────────────────────────────────────────────
	mark("T")
	await glide(Vector3(2.2, 2.3, 8.4), Vector3(2.0, 4.2, 4.6), 16.5, 52.0,
		Vector3(-0.24, 0.34, 0.91), Vector3(-0.16, 0.46, 0.87), 300)
	await w(40)
	await tilt_hold(Vector3(2.0, 4.2, 4.6), 52.0, Vector3(-0.16, 0.46, 0.87), 96)
	await till(sec(88.0))

	# ── U. fade ──────────────────────────────────────────────────────────
	mark("U")
	await fade_to(1.0, 60)
	await till(TOTAL)
	mark("END")
	quit()

## Slow breathing push on the final frame instead of a dead hold.
func tilt_hold(t: Vector3, d: float, dir: Vector3, frames: int) -> void:
	for i in frames:
		var k := float(i + 1) / float(frames)
		pose(t, d + 3.5 * k, dir)
		await w(1)

