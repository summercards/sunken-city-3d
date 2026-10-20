extends Node3D
class_name SeaProps
## 海面可交互物件：漂流物资 + 鱼群（对齐网页版 drift-crates.js / fish-schools.js）。
##
## 两者都只有「船/人靠得够近」或「点击目标」才结算，
## 顺路划过不收 —— 这是网页版刻意的设计，别看漏。

signal collected(kind: String, label: String, reward: Dictionary)
signal fish_collected(label: String)

const WATER_LEVEL := 1.12

const CRATE_KINDS := {
	"crate": {"reward": {"wood": 2, "parts": 1}, "label": "漂流物资箱"},
	"planks": {"reward": {"wood": 3}, "label": "漂流水料"},
	"barrel": {"reward": {"parts": 2, "wood": 1}, "label": "漂流零件桶"},
}

# 水道里能漂东西的范围（避开五个区块的陆地）
const SPAWN := {"min_x": -54.0, "max_x": 54.0, "min_z": -64.0, "max_z": 26.0}
const PICKUP_RADIUS := 1.7
const FISH_PICKUP_RADIUS := 3.2
const FISH_NEAR := 7.0

var crates: Array = []
var schools: Array = []
var _pending := {}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _fish_icon_tex: Texture2D


func build() -> void:
	_rng.seed = 20261019
	for i in 9:
		_spawn_crate()
	for i in 7:
		_spawn_school()


# ---------------------------------------------------------------- 漂流物资

func _spawn_crate() -> void:
	var p := _random_water_point()
	if p == Vector2.ZERO:
		return
	var roll := _rng.randf()
	var kind := "crate" if roll < 0.5 else ("planks" if roll < 0.8 else "barrel")
	var root := _build_crate_mesh(kind)
	root.position = Vector3(p.x, WATER_LEVEL, p.y)
	add_child(root)
	crates.append({
		"kind": kind,
		"root": root,
		"base": Vector3(p.x, WATER_LEVEL, p.y),
		"phase": _rng.randf() * TAU,
		"yaw": _rng.randf() * TAU,
		"ring": root.get_node_or_null("Ring"),
	})


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

	# 水面浮标圈（俯视时更容易看见）
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.62
	ring_mesh.outer_radius = 0.78
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.92, 0.96, 0.85, 0.42)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	ring.position = Vector3(0, 0.02, 0)
	g.add_child(ring)
	return g


# ---------------------------------------------------------------- 鱼群

func _spawn_school() -> void:
	var p := _random_water_point()
	if p == Vector2.ZERO:
		return
	var root := Node3D.new()
	root.name = "FishSchool"
	root.position = Vector3(p.x, WATER_LEVEL, p.y)
	add_child(root)

	var fish := _build_fish_mesh()
	for i in 7:
		var child := fish.duplicate() as Node3D
		var a := _rng.randf() * TAU
		var r := 0.7 + _rng.randf() * 1.5
		child.position = Vector3(cos(a) * r, -0.12 - _rng.randf() * 0.06, sin(a) * r)
		child.scale = Vector3.ONE * (0.75 + _rng.randf() * 0.4)
		root.add_child(child)

	# 双涟漪（贴水面，俯视时的可见信号）
	for k in 2:
		var ripple := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.1 + k * 0.55
		torus.outer_radius = 1.22 + k * 0.55
		torus.rings = 24
		torus.ring_segments = 6
		ripple.mesh = torus
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(0.78, 0.98, 1.0, 0.22 - k * 0.07)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ripple.material_override = rm
		ripple.position = Vector3(0, 0.03 + k * 0.002, 0)
		root.add_child(ripple)

	schools.append({
		"root": root,
		"base": Vector3(p.x, WATER_LEVEL, p.y),
		"phase": _rng.randf() * TAU,
		"fish": root.get_children().filter(func(c): return c is Node3D and c.name.begins_with("FishGroup")),
	})


func _build_fish_mesh() -> Node3D:
	# 一尾小鱼：椭圆身体 + 三角尾鳍
	var root := Node3D.new()
	root.name = "FishGroup"
	var body := SphereMesh.new()
	body.radius = 1.0
	body.height = 2.0
	body.radial_segments = 10
	body.rings = 6
	var bi := MeshInstance3D.new()
	bi.mesh = body
	bi.material_override = _flat(Color("#4fd6c8"))
	bi.scale = Vector3(0.17, 0.1, 0.09)
	root.add_child(bi)

	var tail := PrismMesh.new()
	tail.size = Vector3(0.14, 0.18, 0.02)
	var ti := MeshInstance3D.new()
	ti.mesh = tail
	ti.material_override = _flat(Color("#ffe98a"))
	ti.position = Vector3(-0.19, 0, 0)
	ti.rotation.y = PI * 0.5
	ti.rotation.z = PI * 0.5
	root.add_child(ti)
	return root


# ---------------------------------------------------------------- 通用

func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


func _random_water_point() -> Vector2:
	for i in 200:
		var x: float = _rng.randf_range(SPAWN.min_x, SPAWN.max_x)
		var z: float = _rng.randf_range(SPAWN.min_z, SPAWN.max_z)
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
	for zone in Zones.list:
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
		var ring = c.ring
		if ring and ring.material_override:
			ring.material_override.albedo_color.a = 0.34 + sin(_t * 1.6 + phase) * 0.14

	for s in schools:
		var phase: float = s.phase
		var base: Vector3 = s.base
		var root: Node3D = s.root
		root.position = Vector3(
			base.x + sin(_t * 0.12 + phase) * 1.1,
			WATER_LEVEL,
			base.z + cos(_t * 0.1 + phase) * 1.1
		)
		for i in s.fish.size():
			var f: Node3D = s.fish[i]
			var a: float = _t * (0.7 + i * 0.06) + i * 1.7
			var r: float = 0.9 + (i % 3) * 0.45
			f.position = Vector3(cos(a) * r, -0.12 + sin(_t * 1.6 + i) * 0.03, sin(a) * r)
			f.rotation.y = -a + PI * 0.5

	# 补货
	var now := Time.get_ticks_msec() / 1000.0
	for key in _pending.keys():
		if now >= float(key):
			_spawn_crate()
			_pending.erase(key)


## 船停着 / 正在开往目标 / 人走到旁边才结算。
func try_pickup(boat_pos: Vector3, boat_stopped: bool) -> Dictionary:
	if not boat_stopped:
		return {}
	for c in crates:
		var root: Node3D = c.root
		if Vector2(root.position.x - boat_pos.x, root.position.z - boat_pos.z).length() <= PICKUP_RADIUS:
			return collect_crate(c)
	return {}


func collect_crate(crate: Dictionary) -> Dictionary:
	var spec: Dictionary = CRATE_KINDS.get(crate.kind, CRATE_KINDS.crate)
	crates.erase(crate)
	var root: Node3D = crate.root
	root.queue_free()
	_pending[Time.get_ticks_msec() / 1000.0 + _rng.randf_range(4.0, 9.0)] = true
	for key in spec.reward.keys():
		Economy.add_resource(key, int(spec.reward[key]))
	collected.emit(crate.kind, spec.label, spec.reward)
	return {"label": spec.label, "reward": spec.reward}


func collect_fish(school: Dictionary) -> bool:
	var root: Node3D = school.root
	schools.erase(school)
	root.queue_free()
	Economy.add_resource("fish", 1)
	fish_collected.emit("鱼群")
	# 鱼群换个地方重聚
	get_tree().create_timer(_rng.randf_range(14.0, 30.0)).timeout.connect(_spawn_school)
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
		var sp2: Vector2 = cam.unproject_position(root.global_position + Vector3.UP * 0.3)
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
