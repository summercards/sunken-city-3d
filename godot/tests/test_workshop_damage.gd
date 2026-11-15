extends SceneTree
## 实际网格、洞内射线、物理碰撞、PaletteUV、原子事务及静态往返专项。
const Recipe = preload("res://src/workshop/recipe.gd")
const Generator = preload("res://src/workshop/shell_generator.gd")
const Damage = preload("res://src/workshop/structural_damage.gd")
const Union = preload("res://src/workshop/shell_union_geometry.gd")
const Session = preload("res://src/workshop/session.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
var checks: int = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		failures.append(label + ": " + str(detail))
		printerr("FAIL [workshop-damage] ", label, " ", detail)

static func fixture() -> Dictionary:
	var r: Dictionary = Recipe.authoring_defaults()
	r.architecture.form.enabled = false
	r.taper = 0.0
	r.structural_damage = Damage.defaults()
	r.structural_damage.merge({"enabled": true, "center_u": 0.5, "center_y": 1.7, "width": 4.8, "height": 2.8}, true)
	return JSON.parse_string(JSON.stringify(r))

func run() -> void:
	var filtered: String = OS.get_environment("SEA_DAMAGE_CASE")
	for shape: String in Damage.SHAPES:
		for facade: String in Damage.FACADES:
			var id: String = shape + "_" + facade
			if not filtered.is_empty() and not id.contains(filtered): continue
			var r: Dictionary = fixture()
			r.structural_damage.shape = shape
			r.structural_damage.facade = facade
			await test_case(r, id)
	if filtered.is_empty():
		for d: Dictionary in [{"center_u": 0.04, "width": 5.0}, {"center_y": 3.6, "height": 4.8}]:
			var r: Dictionary = fixture()
			r.structural_damage.merge(d, true)
			r.structural_damage.shape = "breach"
			await test_case(r, "open_edge_" + str(d))
		test_disabled_and_atomic()
	var report := {"checks": checks, "failures": failures, "visual": "未执行，本专项为实际几何与物理断言"}
	var file := FileAccess.open("res://outputs/workshop_damage_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-damage] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_case(r: Dictionary, id: String) -> void:
	for key: Variant in r:
		check(Recipe._finite_tree(r[key]), id + " JSON字段 " + str(key), r[key] if not Recipe._finite_tree(r[key]) else "")
	var built: Dictionary = Generator.build(r)
	check(bool(built.ok), id + " 真实差集生成", built.reason)
	if not bool(built.ok): return
	var building: Node3D = built.root
	var mesh: Mesh = building.get_node("GeneratedVisual/structure_union").mesh
	var faces: PackedVector3Array = mesh.get_faces()
	var topology: Dictionary = Union.audit_faces(faces)
	var disconnected_ok: bool = str(r.structural_damage.shape) == "breach" and bool(topology.closed) and bool(topology.oriented) and int(topology.boundary_edges) == 0 and int(topology.nonmanifold_edges) == 0 and int(topology.degenerate_triangles) == 0 and int(topology.nonfinite_vertices) == 0
	check(bool(topology.valid) or disconnected_ok, id + " 实际闭合/定向/有限/单连通", topology)
	check(built.damage_openings.size() == 1, id + " 宿主洞接口")
	var opening: Dictionary = built.damage_openings[0]
	check(opening.center.is_finite() and opening.normal.is_finite() and opening.profile.size() >= 8, id + " 洞轮廓有限")
	var bvh := TriangleMesh.new()
	bvh.create_from_faces(faces)
	var n: Vector3 = opening.normal
	var axis: Vector3 = opening.axis
	var rays: Array = []
	for x: float in [-0.25, 0.0, 0.25]:
		for y: float in [-0.3, 0.0, 0.3]:
			var center: Vector3 = opening.center + axis * x + Vector3.UP * y
			# 跨层洞保留楼板，采样点避开实际板带；roof/slab不冒称被挖穿。
			var in_slab: bool = false
			for floor: int in int(r.floors) + 1:
				var top: float = float(floor) * float(r.floor_height)
				if center.y <= top + 0.001 and center.y >= top - float(r.slab_thickness) - 0.001: in_slab = true
			if in_slab: continue
			var from: Vector3 = center + n * 0.75
			var to: Vector3 = center - n * (float(r.wall_thickness) + 0.5)
			check(bvh.intersect_segment(from, to).is_empty(), id + " 洞内实际三角射线无遮挡", center)
			rays.append([from, to])
	var uv_errors: int = 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i: int in range(0, uv.size(), 3):
			if not uv[i].is_finite() or absf((uv[i + 1] - uv[i]).cross(uv[i + 2] - uv[i])) <= 1.0e-10: uv_errors += 1
			for corner: int in 3:
				if Vector2i(uv[i + corner] * 8) != Vector2i(uv[i] * 8): uv_errors += 1
	check(uv_errors == 0, id + " 包含封边的全部三角PaletteUV有面积且不跨格", uv_errors)
	var collision_faces := PackedVector3Array()
	for body: Node in building.get_node("Spatial/Collision").get_children():
		if str(body.get_meta("part_id", "")) == "structure_union": collision_faces = body.get_child(0).shape.get_faces()
	check(collision_faces == faces, id + " 碰撞直接取损毁mesh")
	var removed: int = 0
	for window: Dictionary in built.openings:
		if not bool(window.get("removed_by_structural_damage", false)): continue
		removed += 1
		var suffix: String = str(window.id).trim_prefix("opening_")
		for prefix: String in ["frame_", "glass_", "sash_", "sill_", "door_"]:
			check(not building.has_node("GeneratedVisual/" + prefix + suffix), id + " 相交门窗无悬浮 " + prefix + suffix)
	check(removed > 0, id + " 大洞与门窗真实相交")
	root.add_child(building)
	await physics_frame
	await physics_frame
	for ray: Array in rays:
		var query := PhysicsRayQueryParameters3D.create(ray[0], ray[1], 256)
		check(building.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), id + " 实际物理射线穿过洞口")
	root.remove_child(building)
	var packed := PackedScene.new()
	check(packed.pack(building) == OK, id + " 静态打包")
	var path: String = "user://damage_roundtrip.tscn"
	check(ResourceSaver.save(packed, path) == OK, id + " 静态保存")
	var reloaded: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var restored: Node3D = reloaded.instantiate()
	check(restored.get_node("GeneratedVisual/structure_union").mesh.get_faces() == faces, id + " 重载实际几何一致")
	check(restored.get_meta("damage_openings") == opening_array(built), id + " 重载宿主接口一致")
	for body: Node in restored.get_node("Spatial/Collision").get_children():
		if str(body.get_meta("part_id", "")) == "structure_union": check(body.get_child(0).shape.get_faces() == faces, id + " 重载碰撞一致")
	var json: String = JSON.stringify(r)
	var again: Dictionary = Generator.build(JSON.parse_string(json))
	check(bool(again.ok), id + " 配方JSON重建", again.reason)
	if bool(again.ok):
		check(again.root.get_node("GeneratedVisual/structure_union").mesh.get_faces() == faces, id + " 配方重建确定性")
		again.root.free()
	restored.free()
	building.free()

func opening_array(built: Dictionary) -> Array:
	return built.damage_openings

func test_disabled_and_atomic() -> void:
	var r: Dictionary = JSON.parse_string(JSON.stringify(fixture()))
	r.erase("structural_damage")
	var clean: Dictionary = Generator.build(r)
	check(bool(clean.ok), "完整模型基线", clean.reason)
	if not bool(clean.ok): return
	var faces: PackedVector3Array = clean.root.get_node("GeneratedVisual/structure_union").mesh.get_faces()
	for mode: int in 3:
		r = JSON.parse_string(JSON.stringify(fixture()))
		r.structural_damage = JSON.parse_string(JSON.stringify(Damage.defaults()))
		r.structural_damage.enabled = mode != 0
		if mode == 1: r.structural_damage.width = 0.0
		if mode == 2: r.structural_damage.height = 0.0
		var built: Dictionary = Generator.build(r)
		check(bool(built.ok), "disabled/零值接受", built)
		if bool(built.ok):
			check(built.root.get_node("GeneratedVisual/structure_union").mesh.get_faces() == faces, "disabled/零值逐点不改旧几何")
			built.root.free()
	clean.root.free()
	var session := Session.new(Catalog.definitions())
	var session_recipe: Dictionary = JSON.parse_string(JSON.stringify(fixture()))
	check(bool(session.new_document("damage_atomic", session_recipe).ok), "事务基线创建")
	var before: String = Recipe.fingerprint(session.snapshot())
	var undo_count: int = session._undo.size()
	for bad: Dictionary in [{"facade": "roof"}, {"facade": "slab"}, {"width": -1.0}, {"center_y": 90.0}, {"width": 1000.0}, {"seed": 1.5}, {"unknown": 1}]:
		var d: Dictionary = Damage.defaults()
		d.enabled = true
		d.merge(bad, true)
		var result: Dictionary = session.apply_patch({"structural_damage": d})
		check(not bool(result.ok), "非法损毁明确拒绝", bad)
		check(Recipe.fingerprint(session.snapshot()) == before and session._undo.size() == undo_count, "失败原子保留配方/撤销", bad)
