extends Node3D
class_name SeaProps
var give_resource: Callable
var can_receive: Callable
var spawn_area := Rect2()
var planks_only := false
var crate_count := 9
var school_count := 7
var ocean_enabled := false
var ocean = preload("res://src/pickups/ocean_population.gd").new()
var _legacy_population: Dictionary = {}
var _population_cell := Vector2i(2147483647,2147483647)
signal blocked(reason: String)
var zones: Node
## 海面可交互物件：漂流物资 + 鱼群（对齐网页版 drift-crates.js / fish-schools.js）。
##
## 两者都只有「船/人靠得够近」或「点击目标」才结算，
## 顺路划过不收 —— 这是网页版刻意的设计，别看漏。

signal collected(kind: String, label: String, reward: Dictionary)
signal fish_collected(label: String)

const WATER_LEVEL := 1.12

const CRATE_KINDS := {
	"crate": {"reward": {"wood": 2, "parts": 1}, "label": "漂流物资箱"},
	"planks": {"reward": {"wood": 3}, "label": "漂流浮木"},
	"barrel": {"reward": {"parts": 2, "wood": 1}, "label": "漂流零件桶"},
}

# 水道里能漂东西的范围（避开五个区块的陆地）
const SPAWN := {"min_x": -54.0, "max_x": 54.0, "min_z": -64.0, "max_z": 26.0}
const PICKUP_RADIUS := 1.7
const FISH_PICKUP_RADIUS := 3.2
const FISH_NEAR := 7.0

var crates: Array = []
var schools: Array = []
var _pending: Array = []
var _pending_fish: Array = []
var _next_id := 1
var _t := 0.0
var _rng := RandomNumberGenerator.new()
const FishVisual = preload("res://src/pickups/fish_school_visual.gd")
# Existing web snapshot positions, recovered from environment and zone geom 751 pairs.
const WEB_ANCHORS = [Vector2(18.50664, -23.00175), Vector2(-13.04740, -9.35030), Vector2(44.09835, 17.45034), Vector2(43.61626, -31.29347), Vector2(-45.09357, -47.52166), Vector2(-20.83852, 9.64335), Vector2(29.22829, 15.19535)]
var water_surface: MeshInstance3D
var water_point_clear := Callable()
var _fish_rng := RandomNumberGenerator.new()
var _fish_bounds := Rect2()
var _anchor_index := 0


func build() -> void:
	_rng.seed = 20261019
	_fish_rng.seed = 20261023
	if ocean_enabled: return
	_fish_bounds = _school_bounds()
	for i in crate_count:
		_spawn_crate()
	for i in school_count:
		_spawn_school()


# ---------------------------------------------------------------- 漂流物资

func _spawn_crate(point := Vector2.INF, slot := "") -> void:
	var p := _random_water_point() if point == Vector2.INF else point
	if point == Vector2.INF and p == Vector2.ZERO:
		return
	var roll := _rng.randf()
	var kind := "planks" if planks_only else ("crate" if roll < 0.5 else ("planks" if roll < 0.8 else "barrel"))
	var root := _build_crate_mesh(kind)
	root.position = Vector3(p.x, WATER_LEVEL, p.y)
	root.get_node("Ring").material_override.set_shader_parameter("phase", p.x * 0.7 + p.y * 0.3)
	add_child(root)
	crates.append({
		"id":_next_id,
		"slot":slot,
		"kind": kind,
		"root": root,
		"base": Vector3(p.x, WATER_LEVEL, p.y),
		"phase": _rng.randf() * TAU,
		"yaw": _rng.randf() * TAU,
		"ring": root.get_node_or_null("Ring"),
	})
	_next_id += 1


func _build_crate_mesh(kind: String) -> Node3D:
	var g := Node3D.new()
	g.name = "DriftCrate"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 12

	if kind == "planks":
		for i in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = cyl
			mi.material_override = _flat(Color("#b98b61") if i % 2 else Color("#cba97c"))
			mi.position = Vector3((i - 1) * 0.26, 0.04 + i * 0.02, 0)
			mi.rotation.x = PI * 0.5
			mi.scale = Vector3(0.12, 1.5 - i * 0.18, 0.12)
			g.add_child(mi)
		for z in [0.45, -0.45]:
			var strap := MeshInstance3D.new()
			strap.mesh = box
			strap.material_override = _flat(Color("#8d7a5a"))
			strap.position = Vector3(0, 0.13, z)
			strap.scale = Vector3(0.9, 0.05, 0.08)
			g.add_child(strap)
	elif kind == "barrel":
		var body := MeshInstance3D.new()
		body.mesh = cyl
		body.material_override = _flat(Color("#a9764c"))
		body.position = Vector3(0, 0.30, 0)
		body.scale = Vector3(0.30, 0.62, 0.30)
		g.add_child(body)
		for y in [0.18, 0.44]:
			var hoop := MeshInstance3D.new()
			hoop.mesh = cyl
			hoop.material_override = _flat(Color("#7d6a4c"))
			hoop.position = Vector3(0, y, 0)
			hoop.scale = Vector3(0.318, 0.04, 0.318)
			g.add_child(hoop)
		var lid := MeshInstance3D.new()
		lid.mesh = cyl
		lid.material_override = _flat(Color("#d9c39a"))
		lid.position = Vector3(0, 0.60, 0)
		lid.scale = Vector3(0.27, 0.05, 0.27)
		g.add_child(lid)
	else:
		var body := MeshInstance3D.new()
		body.mesh = box
		body.material_override = _flat(Color("#c8a06a"))
		body.position = Vector3(0, 0.24, 0)
		body.scale = Vector3(0.62, 0.48, 0.52)
		g.add_child(body)
		var top := MeshInstance3D.new()
		top.mesh = box
		top.material_override = _flat(Color("#e2c79a"))
		top.position = Vector3(0, 0.49, 0)
		top.scale = Vector3(0.66, 0.06, 0.56)
		g.add_child(top)
		var band := MeshInstance3D.new()
		band.mesh = box
		band.material_override = _flat(Color("#8f7550"))
		band.position = Vector3(0, 0.24, 0)
		band.scale = Vector3(0.66, 0.09, 0.56)
		g.add_child(band)
		var label := MeshInstance3D.new()
		label.mesh = box
		label.material_override = _flat(Color("#f2e2bb"))
		label.position = Vector3(0, 0.30, 0.28)
		label.scale = Vector3(0.20, 0.12, 0.03)
		g.add_child(label)

	var ring := FishVisual.make_ripple(1.12, 0.0)
	ring.name = "Ring"
	g.add_child(ring)
	return g


# ---------------------------------------------------------------- 鱼群

func _spawn_school(point := Vector2.INF, slot := "") -> void:
	var p := _school_point() if point == Vector2.INF else point
	if p == Vector2.INF:
		return
	var root := FishVisual.new()
	root.name = "FishSchool"
	root.position = Vector3(p.x, WATER_LEVEL, p.y)
	add_child(root)
	var phase := _fish_rng.randf() * TAU
	root.build(_fish_rng, _fish_rng.randi_range(3, 6), phase)
	schools.append({"id":_next_id,"slot":slot,"root": root, "base": root.position, "phase": phase, "fish": root.fish})

	_next_id += 1

func _school_bounds() -> Rect2:
	if spawn_area.has_area(): return spawn_area
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for zone in zones.list:
		# Browser derives the region from each zone's primary landing, plus 12 m.
		for key in ["boatPark", "dockEdge", "landStand"]:
			var p: Array = zone.landings[0][key]
			lo = lo.min(Vector2(p[0], p[2]))
			hi = hi.max(Vector2(p[0], p[2]))
	return Rect2(lo - Vector2.ONE * 12.0, hi - lo + Vector2.ONE * 24.0)

func _school_water(p: Vector2) -> bool:
	if not ocean_enabled and not _fish_bounds.has_point(p): return false
	if water_point_clear.is_valid() and not water_point_clear.call(p): return false
	for c in crates:
		if p.distance_to(Vector2(c.base.x,c.base.z))<4.0: return false
	for zone in zones.list:
		for walk in zone.get("walk", []):
			for r in walk.rects:
				var nearest := Vector2(clampf(p.x, r[0], r[1]), clampf(p.y, r[2], r[3]))
				if p.distance_to(nearest) < 2.6: return false
	return true

func _school_point() -> Vector2:
	for attempt in 260:
		var p: Vector2
		if _anchor_index < WEB_ANCHORS.size():
			p = WEB_ANCHORS[_anchor_index]
			_anchor_index += 1
		else:
			p = Vector2(_fish_rng.randf_range(_fish_bounds.position.x, _fish_bounds.end.x), _fish_rng.randf_range(_fish_bounds.position.y, _fish_bounds.end.y))
		if not _school_water(p): continue
		var clear := true
		for s in schools:
			if p.distance_to(Vector2(s.base.x, s.base.z)) < 9.0: clear = false
		if clear: return p
	return Vector2.INF


# ---------------------------------------------------------------- 通用

func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


func _random_water_point() -> Vector2:
	for i in 200:
		var bounds := spawn_area if spawn_area.has_area() else Rect2(SPAWN.min_x,SPAWN.min_z,SPAWN.max_x-SPAWN.min_x,SPAWN.max_z-SPAWN.min_z)
		var x: float = _rng.randf_range(bounds.position.x,bounds.end.x)
		var z: float = _rng.randf_range(bounds.position.y,bounds.end.y)
		if water_point_clear.is_valid() and not water_point_clear.call(Vector2(x,z)): continue
		if _is_land(x, z):
			continue
		var ok := true
		for c in crates:
			var b: Vector3 = c.base
			if Vector2(b.x - x, b.z - z).length() < 7.0:
				ok = false
				break
		if not ok:
			continue
		for s in schools:
			var b: Vector3 = s.base
			if Vector2(b.x - x, b.z - z).length() < 8.0:
				ok = false
				break
		if ok:
			return Vector2(x, z)
	return Vector2.ZERO


func _is_land(x: float, z: float) -> bool:
	for zone in zones.list:
		for w in zone.get("walk", []):
			for r in w.rects:
				if x >= r[0] - 1.0 and x <= r[1] + 1.0 and z >= r[2] - 1.0 and z <= r[3] + 1.0:
					return true
	return false


func _process(delta: float) -> void:
	_t += delta

	for c in crates:
		var phase: float = c.phase
		var base: Vector3 = c.base
		var root: Node3D = c.root
		root.position = Vector3(
			base.x + sin(_t * 0.24 + phase) * 0.45,
			WATER_LEVEL + sin(_t * 1.15 + phase) * 0.07,
			base.z + cos(_t * 0.19 + phase) * 0.45
		)
		root.rotation.y = c.yaw + sin(_t * 0.3 + phase) * 0.35
		root.rotation.z = sin(_t * 0.9 + phase) * 0.05
		var ring: MeshInstance3D = c.ring
		if ring != null:
			# Follow water independently of the floating crate's roll/bob.
			ring.global_transform = Transform3D(Basis.IDENTITY, Vector3(root.position.x, WATER_LEVEL, root.position.z))
			FishVisual.sync_ripple(ring, water_surface, _t)

	for s in schools:
		var phase: float = s.phase
		var base: Vector3 = s.base
		var candidate := Vector2(base.x + sin(_t * 0.21 + phase) * 0.12 * delta, base.z + cos(_t * 0.18 + phase) * 0.12 * delta)
		# Streamed schools keep a stable resource slot; individual fish still swim.
		if ocean_enabled: candidate = Vector2(base.x, base.z)
		if not ocean_enabled and _school_water(candidate):
			s.base = Vector3(candidate.x, WATER_LEVEL, candidate.y)
		var root: Node3D = s.root
		root.position = s.base
		root.animate(_t, water_surface)

	# Relative timers freeze while paused/offline and cannot outlive a restored snapshot.
	for schedule in ([] if ocean_enabled else [_pending,_pending_fish]):
		for i in range(schedule.size()-1,-1,-1):
			schedule[i]=maxf(0.0,float(schedule[i])-delta)
			if schedule[i]<=0.0:
				schedule.remove_at(i)
				if is_same(schedule,_pending): _spawn_crate()
				else: _spawn_school()



## 船停着 / 正在开往目标 / 人走到旁边才结算。
##
## 注意：`try_pickup`（停船一碰就瞬收）已随「停下才打捞」的规则调整删掉。
## 现在停船只代表「可以开始捞」，捞多久由场景侧的拾取阶段计时负责，
## 结算仍走 collect_crate / collect_fish。要判断「船边有没有货」用
## `nearest_crate(pos, PICKUP_RADIUS)`，它只查不结算。
func collect_crate(crate: Dictionary) -> Dictionary:
	if not crates.has(crate): return {}
	var spec: Dictionary = CRATE_KINDS.get(crate.kind, CRATE_KINDS.crate)
	for key in spec.reward:
		if can_receive.is_valid() and not can_receive.call(key,int(spec.reward[key])):
			blocked.emit("背包已满，浮木留在水上")
			return {}
	crates.erase(crate)
	var root: Node3D = crate.root
	root.queue_free()
	if ocean_enabled: ocean.collect(str(crate.slot), false, _rng)
	else: _pending.append(_rng.randf_range(4.0,9.0))
	for key in spec.reward.keys():
		give_resource.call(key, int(spec.reward[key]))
	collected.emit(crate.kind, spec.label, spec.reward)
	return {"label": spec.label, "reward": spec.reward}


func collect_fish(school: Dictionary) -> bool:
	if not schools.has(school): return false
	if can_receive.is_valid() and not can_receive.call("fish",1):
		blocked.emit("背包已满，先把物品存入仓库")
		return false
	var root: Node3D = school.root
	schools.erase(school)
	root.queue_free()
	give_resource.call("fish", 1)
	fish_collected.emit("鱼群")
	# 鱼群换个地方重聚
	if ocean_enabled: ocean.collect(str(school.slot), true, _rng)
	else: _pending_fish.append(_rng.randf_range(14.0,30.0))
	return true


## 屏幕点击：找出鼠标附近最近的漂流箱 / 鱼群。
func pick(screen_pos: Vector2, cam: Camera3D, radius := 26.0) -> Dictionary:
	var best := {}
	var best_d := radius
	for c in crates:
		var root: Node3D = c.root
		if cam.is_position_behind(root.global_position):
			continue
		var sp: Vector2 = cam.unproject_position(root.global_position + Vector3.UP * 0.4)
		var d: float = sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = {"type": "crate", "item": c, "screen": sp}
	for s in schools:
		var root: Node3D = s.root
		if cam.is_position_behind(root.global_position):
			continue
		# 鱼群整条沉在浪面之下（fish_school_visual.SUBMERGE + 半高 ≈ 0.5 m），
		# 点击锚点跟着挪到鱼身上；仍按水面位置取锚点会偏出小半米。
		var sp2: Vector2 = cam.unproject_position(root.global_position - Vector3.UP * 0.45)
		var d2: float = sp2.distance_to(screen_pos)
		if d2 < best_d:
			best_d = d2
			best = {"type": "fish", "item": s, "screen": sp2}
	return best


func nearest_crate(pos: Vector3, radius := 12.0) -> Dictionary:
	var best := {}
	var best_d := radius
	for c in crates:
		var root: Node3D = c.root
		var d: float = Vector2(root.position.x - pos.x, root.position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best


func nearest_school(pos: Vector3, radius := 12.0) -> Dictionary:
	var best := {}
	var best_d := radius
	for s in schools:
		var root: Node3D = s.root
		var d: float = Vector2(root.position.x - pos.x, root.position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = s
	return best

func to_dict() -> Dictionary:
	var cargo: Array=[]
	var fish: Array=[]
	for c in crates: cargo.append({"id":c.id,"slot":c.get("slot",""),"kind":c.kind,"base":[c.base.x,c.base.y,c.base.z],"phase":c.phase,"yaw":c.yaw})
	for c in schools: fish.append({"id":c.id,"slot":c.get("slot",""),"base":[c.base.x,c.base.y,c.base.z],"phase":c.phase,"count":c.fish.size()})
	var result := {"crates":cargo,"schools":fish,"pending":_pending.duplicate(),"pending_fish":_pending_fish.duplicate(),"rng":str(_rng.state),"fish_rng":str(_fish_rng.state),"next_id":_next_id,"anchor":_anchor_index,"elapsed":_t}
	if ocean_enabled: result.ocean = ocean.to_dict()
	return result

func from_dict(data: Dictionary) -> void:
	for c in crates: c.root.queue_free()
	for c in schools: c.root.queue_free()
	crates.clear();schools.clear();_pending.clear();_pending_fish.clear()
	_legacy_population.clear()
	ocean = preload("res://src/pickups/ocean_population.gd").new()
	_population_cell = Vector2i(2147483647,2147483647)
	if data.is_empty() or data.get("reset",false):
		_anchor_index=0
		_next_id=1
		build()
		return
	for c in data.get("crates",[]):
		var mesh := _build_crate_mesh(str(c.kind))
		var base := Vector3(c.base[0],c.base[1],c.base[2])
		mesh.position=base
		add_child(mesh)
		crates.append({"id":int(c.id),"slot":str(c.get("slot","")),"kind":str(c.kind),"base":base,"phase":float(c.phase),"yaw":float(c.yaw),"root":mesh,"ring":mesh.get_node_or_null("Ring")})
	for c in data.get("schools",[]):
		var mesh := FishVisual.new()
		mesh.name="FishSchool"
		var base := Vector3(c.base[0],c.base[1],c.base[2])
		mesh.position=base
		add_child(mesh)
		mesh.build(_fish_rng,int(c.count),float(c.phase))
		schools.append({"id":int(c.id),"slot":str(c.get("slot","")),"root":mesh,"base":base,"phase":float(c.phase),"fish":mesh.fish})
	_pending.assign(data.get("pending",[]));_pending_fish.assign(data.get("pending_fish",[]))
	_rng.state=int(data.rng);_fish_rng.state=int(data.fish_rng)
	_next_id=int(data.next_id);_anchor_index=int(data.anchor);_t=float(data.elapsed)
	if ocean_enabled:
		if data.has("ocean"): ocean.from_dict(data.ocean)
		else: _legacy_population = data.duplicate(true)
		_pending.clear(); _pending_fish.clear()
	else: apply_population_scope()

## Clock and boat position are injected by the composition root. No global time,
## inventory or scene lookup, and no real-time respawn timers in ocean mode.
func sync_population(clock: Dictionary, focus: Vector3) -> void:
	if not ocean_enabled: return
	var previous_cycle: int = ocean.cycle
	var changed: bool = ocean.observe(clock)
	var cell: Vector2i = ocean.cell_at(Vector2(focus.x,focus.z))
	if not changed and _population_cell == cell and _legacy_population.is_empty(): return
	_population_cell = cell
	if not _legacy_population.is_empty():
		# Old six-bundle/four-school home saves have only remaining second timers.
		# Keep those missing slots depleted instead of granting an immediate refill.
		var home := Vector2i.ZERO
		for kind in ["wood", "fish"]:
			var count: int = crate_count if kind == "wood" else school_count
			var live: Array = _legacy_population.get("crates" if kind == "wood" else "schools", [])
			for index in range(mini(live.size(), count), count):
				ocean.collect("%d:%d:%s:%d" % [home.x,home.y,kind,index], kind == "fish", _rng)
		_legacy_population.clear()
	var desired: Dictionary = ocean.desired(Vector2(focus.x, focus.z), crate_count, school_count, _ocean_point_clear)
	var live := {}
	for population in [crates, schools]:
		for item in population.duplicate():
			var slot := str(item.get("slot", ""))
			var p := Vector2(item.base.x, item.base.z)
			var moved_home: bool = desired.has(slot) and slot.begins_with("0:0:wood:") and p.distance_to(desired[slot].point)>0.01
			if previous_cycle != ocean.cycle or not desired.has(slot) or moved_home or not _ocean_point_clear(p, population == schools):
				item.root.hide()
				item.root.queue_free()
				population.erase(item)
			else: live[slot] = true
	for slot in desired:
		if live.has(slot): continue
		var target: Dictionary = desired[slot]
		if not _ocean_point_clear(target.point, target.fish): continue
		if target.fish: _spawn_school(target.point, slot)
		else: _spawn_crate(target.point, slot)

func _ocean_point_clear(point: Vector2, fish: bool) -> bool:
	# Include the resource's drift/swim radius, so its visible geometry stays out
	# of fixed buildings, new platforms and closed water, not just its anchor.
	var margin := 2.8 if fish else 1.0
	for offset in [Vector2.ZERO, Vector2(margin,0),Vector2(-margin,0),Vector2(0,margin),Vector2(0,-margin)]:
		var p: Vector2 = point + offset
		if water_point_clear.is_valid() and not water_point_clear.call(p): return false
		if _is_land(p.x,p.y): return false
	return true

func apply_population_scope() -> void:
	if not spawn_area.has_area(): return
	if crate_count == 0:
		for c in crates: c.root.queue_free()
		crates.clear()
		_pending.clear()
	if crate_count>0:
		for c in crates.duplicate():
			var p:=Vector2(c.base.x,c.base.z)
			if not spawn_area.has_point(p) or (water_point_clear.is_valid() and not water_point_clear.call(p)):
				c.root.queue_free();crates.erase(c)
		for i in maxi(0,crate_count-crates.size()-_pending.size()): _spawn_crate()
	var relocated := 0
	for c in schools.duplicate():
		if not _school_water(Vector2(c.base.x,c.base.z)):
			c.root.queue_free()
			schools.erase(c)
			relocated += 1
	for i in mini(relocated,maxi(0,school_count-schools.size()-_pending_fish.size())): _spawn_school()
