extends SceneTree
## 独立外壳QA；由runner的workshop-shell入口执行，不加载UI或Main。
## 此文件不签署视觉验收；所有几何结论来自实际mesh/碰撞三角面。

const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const ShellGenerator = preload("res://src/workshop/shell_generator.gd")
const ShellGeometry = preload("res://src/workshop/shell_geometry.gd")
const Session = preload("res://src/workshop/session.gd")
const Store = preload("res://src/workshop/store.gd")
const Adapter = preload("res://addons/building_workshop/catalog_adapter.gd")
const MeshBuilder = preload("res://src/workshop/mesh_builder.gd")
const SHARED_MATERIAL_PATHS: Dictionary = {
	"SEA_Matte": "res://assets/materials/solar_cabin/sunny_matte.tres",
	"SEA_Metal": "res://assets/materials/solar_cabin/sunny_metal.tres",
	"SEA_Gloss": "res://assets/materials/solar_cabin/sunny_gloss.tres",
	"SEA_Emission": "res://assets/materials/solar_cabin/sunny_emission.tres"
}
const SHARED_PALETTE_PATH: String = "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const REPORT_PATH: String = "res://outputs/workshop_shell_report.json"
const WELD: float = 0.00001
const SAVE_EPS: float = 0.0001
const SAMPLE_PATHS: Array[String] = [
	"res://data/workshop/samples/workshop_sample_001.recipe.json",
	"res://data/workshop/samples/workshop_sample_002.recipe.json"
]

var checks: int = 0
var failures: Array[String] = []
var report: Dictionary = {"suite": "workshop-shell", "fixtures": {}, "legacy_samples": {}, "prefabs": {}, "saved_scene": "", "visual_acceptance": "未执行；数值QA不能代替professional model视觉验收"}
var image_cache: Dictionary = {}
var palette: Dictionary = {}
var run_id: String = ""
var shared_materials: Dictionary = {}
var shared_material_state: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(value: bool, meaning: String, detail: String = "") -> void:
	checks += 1
	if not value:
		var message: String = meaning + ("：" + detail if not detail.is_empty() else "")
		failures.append(message)
		printerr("FAIL [workshop-shell] ", message)

func run() -> void:
	run_id = "qa_shell_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var catalog: Dictionary = Catalog.definitions()
	palette = _read_json("res://data/workshop/palette_cells_v1.json")
	check(not catalog.is_empty() and Catalog.validate(catalog).is_empty(), "组件目录有效")
	check(not palette.get("semantics", {}).is_empty(), "独立调色板契约可读取")
	var recipe: Dictionary = Recipe.authoring_defaults()
	check(str(recipe.get("construction_mode", "")) == "shell_v2", "创作默认模式为shell_v2")
	check(str(recipe.get("component_bindings", {}).get("wall", "")) == "wall_sun", "创作默认墙为wall_sun")
	check(float(recipe.get("aging", -1.0)) == 0.0 and float(recipe.get("damage", -1.0)) == 0.0 and float(recipe.get("vegetation_density", -1.0)) == 0.0, "创作默认为干净无损无植物")
	_test_auditor()
	_test_shared_scene_materials(recipe, catalog)
	var fixtures: Array[Dictionary] = []
	for spec: Array in [["rect_12x9_f3", "rectangle", 9.0, 3], ["l_12x12_f3", "l", 12.0, 3], ["rect_f1", "rectangle", 9.0, 1], ["rect_f5", "rectangle", 9.0, 5], ["l_f1", "l", 12.0, 1], ["l_f5", "l", 12.0, 5]]:
		var fixture: Dictionary = recipe.duplicate(true)
		fixture.merge({"building_id": str(spec[0]), "shape": str(spec[1]), "width": 12.0, "depth": float(spec[2]), "floors": int(spec[3]), "taper": 0.02}, true)
		# 本文件用显式taper做受控基线；形体开启后taper是派生值，必须关掉，否则断言口径与几何不一致。
		fixture["architecture"]["form"]["enabled"] = false
		fixtures.append(fixture)
	var per_floor: Dictionary = fixtures[0].duplicate(true)
	per_floor.building_id = "floor_1_override"
	per_floor.floor_overrides = {"1": {"floor_height": 6.1, "slab_thickness": 0.25}}
	fixtures.append(per_floor)
	var left_disabled: Dictionary = fixtures[0].duplicate(true)
	left_disabled.building_id = "left_windows_disabled"
	left_disabled.facade_overrides = {"left": {"windows": false}}
	fixtures.append(left_disabled)
	for fixture: Dictionary in fixtures:
		_test_fixture(fixture, catalog)
	_test_legacy_samples(catalog)
	_test_damage(fixtures[0], catalog)
	_test_window_weathering(recipe, catalog)
	_test_store(fixtures[0], catalog, "baseline")
	_test_prefabs(fixtures[0], catalog)
	_finish()

func _test_shared_scene_materials(recipe: Dictionary, catalog: Dictionary) -> void:
	shared_materials = MeshBuilder.shared_materials()
	check(not shared_materials.is_empty(), "MeshBuilder提供shared_materials；缺失不得跳过")
	for role: String in SHARED_MATERIAL_PATHS:
		var source: ShaderMaterial = load(str(SHARED_MATERIAL_PATHS[role])) as ShaderMaterial
		check(source != null, role + " 正式资源可读取")
		if source != null: shared_material_state[role] = _shared_material_snapshot(source)
	shared_materials = MeshBuilder.shared_materials()
	check(shared_materials.size() == 4, "shared_materials恰好四个SEA角色")
	var texture: Texture2D = load(SHARED_PALETTE_PATH) as Texture2D
	check(texture != null and texture.get_width() == 512 and texture.get_height() == 512, "四材质正式共享色盘为512x512")
	var identities: Dictionary = {}
	for role: String in SHARED_MATERIAL_PATHS:
		var material: ShaderMaterial = shared_materials.get(role) as ShaderMaterial
		check(material != null, role + " 为ShaderMaterial")
		if material == null: continue
		identities[material.get_instance_id()] = true
		check(material == load(str(SHARED_MATERIAL_PATHS[role])) and material.resource_path == str(SHARED_MATERIAL_PATHS[role]) and material.resource_name == role and not material.resource_local_to_scene, role + " identity/path/name与正式场景一致且不按场景复制")
		check(texture != null and material.get_shader_parameter("palette") == texture, role + " 使用同一个512texture实例")
	check(identities.size() == 4, "四角色为四个不同共享实例")
	var cache: Dictionary = {}
	for role: String in SHARED_MATERIAL_PATHS:
		for color: String in ["cozy", "glass", "timber"]:
			for aging: float in [0.0, 0.8]:
				check(MeshBuilder.material(color, aging, cache, role) == shared_materials.get(role), role + " 显式角色优先于配色和老化且不复制")
	check(MeshBuilder.material("glass", 0.0, {}) == shared_materials.get("SEA_Gloss") and MeshBuilder.material("cozy", 0.8, {}) == shared_materials.get("SEA_Matte"), "默认glass为Gloss其余Matte")
	var original: String = JSON.stringify(recipe)
	var catalog_hash: String = Catalog.fingerprint(catalog)
	var built: Dictionary = Generator.build(recipe, catalog)
	var root: Node3D = built.get("root") as Node3D
	check(bool(built.get("ok", false)) and root != null, "四材质验收生成默认shell", str(built.get("reason", "")))
	if root != null:
		var baseline: Dictionary = _inventory(root)
		var used: Array = _check_shell_materials("默认shell", baseline, catalog)
		check(used.size() > 0 and used.size() <= 4, "默认shell材质实例仅来自共享4个")
		for iteration: int in 3:
			var repeat: Dictionary = Generator.build(recipe, catalog)
			var repeat_root: Node3D = repeat.get("root") as Node3D
			check(bool(repeat.get("ok", false)) and repeat_root != null, "重复shell生成成功%d" % iteration, str(repeat.get("reason", "")))
			if repeat_root == null: continue
			var repeated: Dictionary = _inventory(repeat_root)
			check(_same_geometry(baseline, repeated) and baseline.geometry_hash == repeated.geometry_hash, "重复生成全部几何/法线/UV/碰撞不变%d" % iteration)
			check(_check_shell_materials("重复shell%d" % iteration, repeated, catalog) == used, "重复生成不新增材质实例%d" % iteration)
			repeat_root.free()
		for role: String in SHARED_MATERIAL_PATHS:
			var assigned: Dictionary = catalog.duplicate(true)
			for definition: Dictionary in assigned.components.values():
				if str(definition.get("kind", "")) == "parametric": definition["material_role"] = role
			var role_build: Dictionary = Generator.build(recipe, assigned)
			var role_root: Node3D = role_build.get("root") as Node3D
			check(bool(role_build.get("ok", false)) and role_root != null, role + " definition.material_role生成成功", str(role_build.get("reason", "")))
			if role_root == null: continue
			var role_inventory: Dictionary = _inventory(role_root)
			var role_ids: Array = _check_shell_materials(role + " definition覆盖", role_inventory, assigned)
			var expected: ShaderMaterial = shared_materials.get(role) as ShaderMaterial
			check(expected != null and role_ids == [expected.get_instance_id()], role + " 完整SEA角色覆盖含glass的所有参数组件")
			check(_same_geometry(baseline, role_inventory) and baseline.geometry_hash == role_inventory.geometry_hash, role + " 仅换材质不改变任何几何/法线/UV/碰撞")
			role_root.free()
		root.free()
	var railing_recipe: Dictionary = recipe.duplicate(true)
	railing_recipe["architecture"]["roof"]["mode"] = "railing"
	var railing_build: Dictionary = Generator.build(railing_recipe, catalog)
	var railing_root: Node3D = railing_build.get("root") as Node3D
	check(bool(railing_build.get("ok", false)) and railing_root != null, "railing fixture生成成功", str(railing_build.get("reason", "")))
	if railing_root != null:
		var railing: Dictionary = _inventory(railing_root)
		_check_shell_materials("railing fixture", railing, catalog)
		var railing_count: int = 0
		for record: Dictionary in railing.mesh_records:
			if not str(record.id).begins_with("railing_"): continue
			railing_count += 1
			var node: MeshInstance3D = record.node
			var mesh: Mesh = record.mesh
			for surface: int in mesh.get_surface_count():
				check(node.get_active_material(surface) == shared_materials.get("SEA_Metal"), str(record.id) + " 默认明确使用共享Metal")
		check(railing_count > 0, "railing fixture确实含栏杆而非空测")
		railing_root.free()
	check(JSON.stringify(recipe) == original and Catalog.fingerprint(catalog) == catalog_hash, "共享材质验收不改原始配方和目录")
	_check_shared_materials_unchanged("角色及重复生成后")

func _shared_material_snapshot(material: ShaderMaterial) -> Dictionary:
	var parameters: Dictionary = {}
	if material.shader != null:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var key: String = str(uniform.name)
			var value: Variant = material.get_shader_parameter(key)
			if value == null:
				value = {"roughness_value": 0.62, "metallic_value": 0.0, "emission_value": 0.0, "grid_role": false, "home_window": false, "home_window_recessed": false, "home_window_column": 3, "alpha_value": 0.81, "tint": Color.WHITE, "interior_glass": false}.get(key)
			parameters[key] = snappedf(float(value), 0.000001) if value is float or value is int else value
	return {"id": material.get_instance_id(), "path": material.resource_path, "name": material.resource_name, "local": material.resource_local_to_scene, "priority": material.render_priority, "next_pass": material.next_pass, "shader": material.shader, "shader_code": material.shader.code if material.shader != null else "", "parameters": parameters.duplicate(true), "file_hash": FileAccess.get_sha256(material.resource_path), "shader_hash": FileAccess.get_sha256(material.shader.resource_path) if material.shader != null else "", "texture_hash": FileAccess.get_sha256(SHARED_PALETTE_PATH)}

func _check_shared_materials_unchanged(label: String) -> void:
	if shared_material_state.is_empty(): return
	var current: Dictionary = MeshBuilder.shared_materials()
	check(current.size() == 4, label + " shared_materials仍恰好四项")
	for role: String in shared_material_state:
		var material: ShaderMaterial = current.get(role) as ShaderMaterial
		var current_state: Dictionary = _shared_material_snapshot(material) if material != null else {}
		var differences: Array[String] = []
		for key: String in current_state:
			if current_state[key] != shared_material_state[role].get(key): differences.append(key + ": " + str(shared_material_state[role].get(key)) + " -> " + str(current_state[key]))
		check(material != null and material == shared_materials.get(role) and differences.is_empty(), label + " " + role + " identity/参数/文件hash前后不变", str(differences))

func _check_shell_materials(label: String, inventory: Dictionary, catalog: Dictionary) -> Array:
	var used: Dictionary = {}
	for record: Dictionary in inventory.mesh_records:
		var node: MeshInstance3D = record.node
		var mesh: Mesh = record.mesh
		var id: String = str(record.id)
		var definition: Dictionary = catalog.components.get(str(node.get_meta("component_id", "")), {})
		var role: String = str(definition.get("material_role", ""))
		if role.is_empty(): role = "SEA_Gloss" if id.begins_with("glass_") else ("SEA_Metal" if id.begins_with("railing_") else "SEA_Matte")
		var attached: Array[Material] = [node.material_override, node.material_overlay]
		for surface: int in mesh.get_surface_count():
			attached.append(mesh.surface_get_material(surface))
			attached.append(node.get_surface_override_material(surface))
		for material: Material in attached:
			if material == null: continue
			var attached_role: String = material.resource_name
			check(material is ShaderMaterial and SHARED_MATERIAL_PATHS.has(attached_role) and material == shared_materials.get(attached_role), label + " " + id + " 所有底层及覆盖材质均属于共享四实例")
			used[material.get_instance_id()] = true
		for surface: int in mesh.get_surface_count():
			var material: ShaderMaterial = node.get_active_material(surface) as ShaderMaterial
			check(material != null and SHARED_MATERIAL_PATHS.has(role) and material == shared_materials.get(role) and material.resource_path == str(SHARED_MATERIAL_PATHS.get(role, "")) and material.resource_name == role, label + " " + id + " role/path/identity正确", role)
			if material != null: used[material.get_instance_id()] = true
	var ids: Array = used.keys()
	ids.sort()
	return ids

func _test_fixture(recipe: Dictionary, catalog: Dictionary) -> void:
	var label: String = str(recipe.building_id)
	var original: String = JSON.stringify(recipe)
	var catalog_hash: String = Catalog.fingerprint(catalog)
	var build: Dictionary = Generator.build(recipe, catalog)
	check(bool(build.get("ok", false)), label + " 生成真实外壳", str(build.get("reason", "")))
	var building: Node3D = build.get("root") as Node3D
	if building == null:
		report.fixtures[label] = {"ok": false, "reason": str(build.get("reason", "没有root"))}
		return
	var inventory: Dictionary = _inventory(building)
	var audit: Dictionary = _audit_inventory(inventory)
	var fixture_report: Dictionary = _public_inventory(inventory, audit)
	fixture_report["recipe"] = recipe.duplicate(true)
	fixture_report["generator_version"] = building.get_meta("generator_version", "")
	fixture_report["openings"] = _json_value(build.get("openings", []))
	report.fixtures[label] = fixture_report
	check(str(building.get_meta("generator_version", "")) == ShellGenerator.GENERATOR_VERSION, label + " build分派到当前shell生成器")
	check(str(building.get_meta("construction_mode", "")) == "shell_v2", label + " 根metadata模式正确")
	check(building.transform.is_equal_approx(Transform3D.IDENTITY), label + " 根变换恒等")
	var floors: int = int(recipe.floors)
	var walls: int = 0
	var slabs: int = 0
	var roofs: int = 0
	var pillars: int = 0
	var obsolete: Array[String] = []
	for id: String in inventory.parts:
		if id.begins_with("wall_shell_"): walls += 1
		elif id.begins_with("wall_"): obsolete.append(id)
		if id.begins_with("slab_"): slabs += 1
		if id.begins_with("roof_"):
			roofs += 1
			if id != "roof_main": obsolete.append(id)
		if id.begins_with("pillar_"): pillars += 1
	check(walls == floors, label + " 每层恰好一个wall_shell", str(walls))
	check(slabs == floors and roofs == 1, label + " 楼板每层一件且屋顶仅一件", "%d/%d" % [slabs, roofs])
	check(pillars == 0, label + " 没有满立面柱式拼盒支撑")
	check(obsolete.is_empty(), label + " 没有旧分段墙或cell roof", str(obsolete))
	check(int(inventory.nodes) <= 2000 and int(inventory.triangles) <= 180000, label + " 实数节点和面数在预算内")
	_check_audit(label, audit)
	check(int(inventory.invalid_collision_shapes) == 0, label + " 碰撞全部来自ConcavePolygon实际三角面")
	check(int(inventory.collision_shapes) >= floors * 2 + 1, label + " 至少每层墙壳楼板与屋顶有碰撞")
	var non_structural: Array[String] = []
	for collision_id: String in inventory.collisions:
		if not _structural(collision_id): non_structural.append(collision_id)
	check(non_structural.is_empty(), label + " 仅墙壳楼板屋顶及屋顶围护有碰撞", str(non_structural))
	check(_collision_matches_visual(inventory), label + " 每件结构碰撞与实际视觉三角面一致")
	check(_no_accessory_collision(inventory), label + " 窗框与玻璃均无碰撞")
	_test_levels(label, recipe, inventory)
	fixture_report["actual_outer_radius"] = _test_outer_radius(label, recipe, inventory)
	fixture_report["rays"] = _test_rays(label, recipe, inventory, build.get("openings", []))
	var repeat_input: Dictionary = _parse_dictionary(JSON.parse_string(original))
	var repeated: Dictionary = Generator.build(repeat_input, catalog)
	var repeat_root: Node3D = repeated.get("root") as Node3D
	check(bool(repeated.get("ok", false)) and repeat_root != null, label + " 同JSON可重复生成", str(repeated.get("reason", "")))
	if repeat_root != null:
		var repeat_inventory: Dictionary = _inventory(repeat_root)
		check(str(inventory.geometry_hash) == str(repeat_inventory.geometry_hash) and _same_geometry(inventory, repeat_inventory), label + " 同JSON实际geometry稳定hash及碰撞保持")
		check(_slot_signature(build.get("slots", [])) == _slot_signature(repeated.get("slots", [])), label + " 同JSON槽位映射稳定")
		repeat_root.free()
	check(JSON.stringify(recipe) == original and Catalog.fingerprint(catalog) == catalog_hash, label + " 生成不修改输入配方或目录")
	var legacy_recipe: Dictionary = recipe.duplicate(true)
	legacy_recipe.construction_mode = "modular_v1"
	# 真正的旧版modular配方没有architecture；带非默认架构不允许降级成modular。
	legacy_recipe.erase("architecture")
	var legacy: Dictionary = Generator.build(legacy_recipe, catalog)
	var legacy_root: Node3D = legacy.get("root") as Node3D
	check(bool(legacy.get("ok", false)) and legacy_root != null, label + " 可生成真实legacy对照", str(legacy.get("reason", "")))
	if legacy_root != null:
		var legacy_inventory: Dictionary = _inventory(legacy_root)
		fixture_report["legacy_structure_triangles"] = legacy_inventory.structure_triangles
		fixture_report["structure_triangle_ratio"] = float(inventory.structure_triangles) / maxf(1.0, float(legacy_inventory.structure_triangles))
		check(int(inventory.structure_triangles) < int(legacy_inventory.structure_triangles) * 0.65, label + " 结构面数显著低于legacy而非细分盒子", str(fixture_report.structure_triangle_ratio))
		legacy_root.free()
	building.free()

func _check_audit(label: String, audit: Dictionary) -> void:
	for field: String in ["boundary_edges", "nonmanifold_edges", "orientation_errors", "duplicate_triangles", "degenerate_triangles", "nonfinite_vertices", "normal_errors", "uv_area_errors", "uv_safe_errors", "colour_errors"]:
		check(int(audit[field]) == 0, label + " " + field + "为0", str(audit.get("bad_parts", {}).get(field, [])))
	check(int(audit.disconnected_parts) == 0, label + " 每个实际part按共享边图仅一个连通分量", str(audit.get("bad_parts", {}).get("disconnected_parts", [])))
	check(int(audit.window_ring_errors) == 0 and int(audit.window_frames) > 0, label + " 每窗框是单个闭合环而非四个盒子")
	check(int(audit.nonpositive_volumes) == 0, label + " 每件闭合实体CW朝外且体积为正")

func _test_levels(label: String, recipe: Dictionary, inventory: Dictionary) -> void:
	var base: float = 0.0
	var total: float = _height(recipe)
	var levels_ok: bool = true
	var taper_ok: bool = true
	for floor: int in int(recipe.floors):
		var slab: PackedVector3Array = inventory.parts.get("slab_%d" % floor, PackedVector3Array())
		var wall: PackedVector3Array = inventory.parts.get("wall_shell_%d" % floor, PackedVector3Array())
		if slab.is_empty() or wall.is_empty():
			levels_ok = false
			continue
		var slab_bounds: AABB = _bounds(slab)
		var wall_bounds: AABB = _bounds(wall)
		var next: int = mini(floor + 1, int(recipe.floors) - 1)
		# 墙与板的重叠量由 shell_geometry.INSET 决定（0.8mm，仅防浮点缝）；断言读生成器导出的实际值，不写死数字。
		var joint: float = _joint_inset(inventory)
		var wall_top: float = base + _floor_value(recipe, floor, "floor_height") - _floor_value(recipe, next, "slab_thickness") + joint
		levels_ok = levels_ok and absf(slab_bounds.end.y - base) <= SAVE_EPS and absf(slab_bounds.size.y - _floor_value(recipe, floor, "slab_thickness")) <= SAVE_EPS
		levels_ok = levels_ok and absf(wall_bounds.position.y - (base - joint)) <= SAVE_EPS and absf(wall_bounds.end.y - wall_top) <= SAVE_EPS
		for y: float in [wall_bounds.position.y, wall_bounds.end.y]:
			var extent: float = 0.0
			for point: Vector3 in wall:
				if absf(point.y - y) <= WELD: extent = maxf(extent, absf(point.x))
			var expected: float = float(recipe.width) * 0.5 * (1.0 - float(recipe.taper) * clampf(y / total, 0.0, 1.0))
			taper_ok = taper_ok and absf(extent - expected) <= SAVE_EPS
		base += _floor_value(recipe, floor, "floor_height")
	var roof: PackedVector3Array = inventory.parts.get("roof_main", PackedVector3Array())
	if roof.is_empty():
		levels_ok = false
	else:
		var roof_bounds: AABB = _bounds(roof)
		levels_ok = levels_ok and absf(roof_bounds.end.y - total) <= SAVE_EPS and absf(roof_bounds.size.y - _floor_value(recipe, int(recipe.floors) - 1, "slab_thickness")) <= SAVE_EPS
	check(levels_ok, label + " 实际层高板厚与逐层覆盖相符")
	check(taper_ok, label + " 实际墙壳所有楼层共用整栋0.02 taper")
	if str(recipe.building_id) == "left_windows_disabled":
		var accessories: int = 0
		for id: String in inventory.parts:
			if id.begins_with("frame_left_") or id.begins_with("glass_left_"): accessories += 1
		check(accessories == 0, label + " left windows关闭后没有遗留窗框玻璃")
		var y: float = float(recipe.window_sill) + float(recipe.window_height) * 0.5
		var point: Vector3 = _mapped(Vector3(-float(recipe.width) * 0.5, y, -float(recipe.depth) * 0.25), recipe)
		check(int(_ray(inventory.collisions.get("wall_shell_0", PackedVector3Array()), point - Vector3.RIGHT, point + Vector3.RIGHT).hits) >= 1, label + " 禁窗立面原窗高位置确有实墙")

func _test_outer_radius(label: String, recipe: Dictionary, inventory: Dictionary) -> Dictionary:
	var x: float = float(recipe.width) * 0.5
	var z: float = float(recipe.depth) * 0.5
	var polygon: Array[Vector2] = [Vector2(-x, -z), Vector2(x, -z), Vector2(x, z), Vector2(-x, z)]
	if str(recipe.shape) == "l":
		polygon = [Vector2(-x, -z), Vector2(x, -z), Vector2(x, 0.0), Vector2.ZERO, Vector2(0.0, z), Vector2(-x, z)]
	var radius: float = 0.07
	var faces: PackedVector3Array = inventory.parts.get("wall_shell_0", PackedVector3Array())
	var sample_y: float = faces[0].y if not faces.is_empty() else 0.0
	for vertex: Vector3 in faces: sample_y = maxf(sample_y, vertex.y)
	var total_height: float = _height(recipe)
	var scale: float = 1.0 - float(recipe.taper) * clampf(sample_y / total_height, 0.0, 1.0)
	var section: Dictionary = {}
	# 只测实际最高平面上的原始顶点，不把跨越y=0的三角边插值当成global map采样。
	# 每个顶点以自身真实高度反解taper；不从斜面中插出缺失的30/60度弧顶点。
	for vertex: Vector3 in faces:
		if absf(vertex.y - sample_y) > WELD: continue
		var vertex_scale: float = 1.0 - float(recipe.taper) * clampf(vertex.y / total_height, 0.0, 1.0)
		var inverse: Vector3 = Vector3(vertex.x / vertex_scale, sample_y, vertex.z / vertex_scale)
		section[_position_key(inverse)] = Vector2(inverse.x, inverse.z)
	var result: Dictionary = {"sample_y": sample_y, "sample_height": sample_y, "sample_source": "actual_wall_top_vertex_ring", "unique_ring_vertices": section.size(), "inverse_taper_scale": scale, "expected_radius": radius, "corners": []}
	for corner: int in polygon.size():
		var incoming: Vector2 = (polygon[corner] - polygon[(corner - 1 + polygon.size()) % polygon.size()]).normalized()
		var outgoing: Vector2 = (polygon[(corner + 1) % polygon.size()] - polygon[corner]).normalized()
		if incoming.cross(outgoing) <= 0.0: continue
		var center: Vector2 = polygon[corner] - incoming * radius + outgoing * radius
		var samples: Array[Dictionary] = []
		var unique: Dictionary = {}
		var radius_ok: bool = true
		var angles_ok: bool = true
		var mids: int = 0
		for degrees: float in [0.0, 30.0, 60.0, 90.0]:
			var angle: float = deg_to_rad(degrees)
			var target: Vector2 = center + (incoming * sin(angle) - outgoing * cos(angle)) * radius
			var nearest: Vector2 = Vector2.ZERO
			var distance: float = INF
			for candidate: Vector2 in section.values():
				var error: float = candidate.distance_to(target)
				if error < distance:
					distance = error
					nearest = candidate
			var delta: Vector2 = nearest - center
			var actual_radius: float = delta.length()
			var actual_degrees: float = rad_to_deg(atan2(delta.dot(incoming), delta.dot(-outgoing)))
			var key: String = _position_key(Vector3(nearest.x, sample_y, nearest.y))
			var vertex_distance: float = distance
			var matched: bool = distance <= SAVE_EPS and vertex_distance <= SAVE_EPS and absf(actual_degrees - degrees) <= 0.1
			if matched and not unique.has(key) and degrees > 0.0 and degrees < 90.0: mids += 1
			unique[key] = true
			radius_ok = radius_ok and not section.is_empty() and absf(actual_radius - radius) <= SAVE_EPS
			angles_ok = angles_ok and matched
			samples.append({"expected_degrees": degrees, "actual_degrees": actual_degrees, "radius": actual_radius, "xz": [nearest.x, nearest.y], "target_distance": distance, "actual_vertex_column_distance": vertex_distance})
		var detail: String = "sample_height=%s，actual_wall_top_vertex_ring，samples=%s" % [str(sample_y), str(samples)]
		var corner_label: String = label + " 凸外角%d" % corner
		check(radius_ok, corner_label + " 实际顶点环反解后半径为0.07m", detail)
		check(unique.size() >= 4 and angles_ok, corner_label + " 存在0/30/60/90度四个不同实际弧点", detail)
		check(mids == 2, corner_label + " 存在30/60度两个中间弧顶点而非单段chamfer", detail)
		result.corners.append({"corner": corner, "center": [center.x, center.y], "unique_xz": unique.size(), "mid_vertices": mids, "samples": samples})
	var expected_corners: int = 5 if str(recipe.shape) == "l" else 4
	check(result.corners.size() == expected_corners, label + " 测完全部凸角：矩形4个/L形5个")
	return result

func _test_rays(label: String, recipe: Dictionary, inventory: Dictionary, openings: Array) -> Dictionary:
	var results: Dictionary = {}
	var wall: PackedVector3Array = inventory.collisions.get("wall_shell_0", PackedVector3Array())
	var door: Dictionary = {}
	var window: Dictionary = {}
	for opening: Dictionary in openings:
		if int(opening.get("floor", -1)) != 0: continue
		if str(opening.get("facade", "")) == "front" and str(opening.get("type", "")) == "door": door = opening
		if window.is_empty() and str(opening.get("type", "")) == "window": window = opening
	check(not door.is_empty(), label + " 首层真实front door声明存在")
	if not door.is_empty():
		var center: Vector3 = door.center
		var outward: Vector3 = door.outward
		results["front_door"] = _ray(wall, center + outward, center - outward)
		check(int(results.front_door.hits) == 0, label + " 门洞净空穿墙碰撞三角面零命中")
	var wall_point: Vector3 = _mapped(Vector3(-float(recipe.width) * 0.5 + 0.7, 0.47, -float(recipe.depth) * 0.5), recipe)
	results["solid_wall"] = _ray(wall, wall_point + Vector3.FORWARD, wall_point + Vector3.BACK)
	check(int(results.solid_wall.hits) >= 1, label + " 非洞口实墙射线命中")
	var joined: bool = true
	for side: float in [-1.0, 1.0]:
		var corner: Vector3 = Vector3(side * float(recipe.width) * 0.5, 0.47, -float(recipe.depth) * 0.5)
		var front: Vector3 = _mapped(corner + Vector3(-side * 0.12, 0.0, 0.0), recipe)
		var adjacent: Vector3 = _mapped(corner + Vector3(0.0, 0.0, 0.12), recipe)
		var join_point: Vector3 = _mapped(corner, recipe)
		var front_hit: Dictionary = _ray(wall, front + Vector3.FORWARD, front + Vector3.BACK)
		var side_hit: Dictionary = _ray(wall, adjacent + Vector3(side, 0.0, 0.0), adjacent - Vector3(side, 0.0, 0.0))
		var diagonal: Vector3 = Vector3(side, 0.0, -1.0).normalized()
		var seam_hit: Dictionary = _ray(wall, join_point + diagonal, join_point - diagonal)
		results["corner_left" if side < 0.0 else "corner_right"] = {"front": front_hit, "side": side_hit, "seam": seam_hit}
		joined = joined and int(front_hit.hits) > 0 and int(side_hit.hits) > 0 and int(seam_hit.hits) > 0
	check(joined, label + " 左右前墙角两相邻墙及圆弧接缝均无漏射线")
	var roof: PackedVector3Array = inventory.parts.get("roof_main", PackedVector3Array())
	var collision_roof: PackedVector3Array = inventory.collisions.get("roof_main", PackedVector3Array())
	var height: float = _height(recipe)
	var thickness: float = _floor_value(recipe, int(recipe.floors) - 1, "slab_thickness")
	var inside: Vector3 = Vector3(-float(recipe.width) * 0.23, height, -float(recipe.depth) * 0.21)
	results["roof_top"] = _ray(roof, inside + Vector3.UP, inside + Vector3.DOWN * (thickness + 0.5))
	results["roof_bottom"] = _ray(roof, inside + Vector3.DOWN * (thickness + 1.0), inside + Vector3.UP)
	results["roof_collision"] = _ray(collision_roof, inside + Vector3.UP, inside + Vector3.DOWN * (thickness + 0.5))
	check(int(results.roof_top.hits) > 0 and int(results.roof_collision.hits) > 0, label + " 屋顶实体内部视觉和碰撞均命中")
	check(int(results.roof_top.hits) > 0 and absf(float(results.roof_top.position[1]) - height) <= SAVE_EPS and float(results.roof_top.normal[1]) > 0.99, label + " 屋顶顶面高度及CW外法线朝上")
	check(int(results.roof_bottom.hits) > 0 and absf(float(results.roof_bottom.position[1]) - (height - thickness)) <= SAVE_EPS and float(results.roof_bottom.normal[1]) < -0.99, label + " 屋顶底面高度及CW外法线朝下")
	if str(recipe.shape) == "l":
		var courtyard: Vector3 = Vector3(float(recipe.width) * 0.25, height + 1.0, float(recipe.depth) * 0.25)
		results["l_courtyard_visual"] = _ray(roof, courtyard, courtyard + Vector3.DOWN * (height + 2.0))
		results["l_courtyard_collision"] = _ray(collision_roof, courtyard, courtyard + Vector3.DOWN * (height + 2.0))
		check(int(results.l_courtyard_visual.hits) == 0 and int(results.l_courtyard_collision.hits) == 0, label + " L庭院上方真实屋顶及碰撞都不封空")
		var concave_x: Dictionary = _ray(wall, Vector3(1.0, 0.47, 0.12), Vector3(-1.0, 0.47, 0.12))
		var concave_z: Dictionary = _ray(wall, Vector3(0.12, 0.47, 1.0), Vector3(0.12, 0.47, -1.0))
		results["l_concave_corner"] = {"x": concave_x, "z": concave_z}
		check(int(concave_x.hits) > 0 and int(concave_z.hits) > 0, label + " L凹角两个墙面均连续")
	if not window.is_empty():
		var center: Vector3 = window.center
		var outward: Vector3 = window.outward
		var suffix: String = str(window.id).trim_prefix("opening_")
		var frame_faces: PackedVector3Array = inventory.parts.get("frame_" + suffix, PackedVector3Array())
		var glass_faces: PackedVector3Array = inventory.parts.get("glass_" + suffix, PackedVector3Array())
		results["window_frame_center"] = _ray(frame_faces, center + outward, center - outward)
		results["window_glass_center"] = _ray(glass_faces, center + outward, center - outward)
		results["window_collision_clear"] = _ray(wall, center + outward, center - outward)
		check(int(results.window_frame_center.hits) == 0, label + " 闭合窗环中心确实为空")
		check(int(results.window_glass_center.hits) > 0 and int(results.window_collision_clear.hits) == 0, label + " 窗中心实际玻璃可见而墙碰撞为空")
	return results

func _test_damage(recipe: Dictionary, catalog: Dictionary) -> void:
	var session: RefCounted = Session.new(catalog)
	var accepted: Dictionary = session.call("accept_loaded", recipe, catalog)
	check(bool(accepted.get("ok", false)), "原子拒绝测试装入真实shell会话")
	if not bool(accepted.get("ok", false)): return
	var good: Dictionary = session.call("build")
	var preview: Node3D = good.get("root") as Node3D
	check(bool(good.get("ok", false)) and preview != null, "原子拒绝前会话可生成预览")
	if preview == null: return
	var before_hash: String = str(_inventory(preview).geometry_hash)
	var before_snapshot: Dictionary = session.call("snapshot")
	var before_json: String = JSON.stringify(before_snapshot)
	var before_state: String = _session_state(session)
	var invalids: Array[Dictionary] = [
		{"id": "wall_disabled", "patch": {"slot_overrides": {"wall_shell_0": {"disabled": true}}}},
		{"id": "wall_excluded", "patch": {"excluded_slots": ["wall_shell_0"]}},
		{"id": "wall_offset", "patch": {"slot_overrides": {"wall_shell_0": {"offset": [0.1, 0.0, 0.0]}}}},
		{"id": "damage_negative", "patch": {"damage": -0.1}},
		{"id": "damage_over_one", "patch": {"damage": 1.1}},
		{"id": "damage_seed_negative", "patch": {"damage_seed": -1}}
	]
	var cases: Array[Dictionary] = []
	for invalid: Dictionary in invalids:
		cases.append({"id": str(invalid.id) + "_patch", "method": "apply_patch", "data": invalid.patch})
		var candidate: Dictionary = recipe.duplicate(true)
		candidate.merge(invalid.patch, true)
		cases.append({"id": str(invalid.id) + "_loaded", "method": "accept_loaded", "data": candidate})
	var unknown: Dictionary = recipe.duplicate(true)
	unknown.construction_mode = "shell_unknown_mode"
	var validation_reason: String = Recipe.validate(unknown, catalog)
	check(not validation_reason.is_empty(), "未知construction_mode首先被Recipe.validate拒绝", validation_reason)
	cases.append({"id": "newborn_unknown_mode", "method": "new_document", "data": unknown})
	report["session_atomic_rejections"] = {}
	for entry: Dictionary in cases:
		var rejected: Dictionary = {}
		match str(entry.method):
			"apply_patch":
				rejected = session.call("apply_patch", entry.data)
			"accept_loaded":
				rejected = session.call("accept_loaded", entry.data, catalog)
			"new_document":
				rejected = session.call("new_document", "qa_invalid_newborn", entry.data)
		var reason: String = str(rejected.get("reason", ""))
		var label: String = str(entry.id)
		check(not bool(rejected.get("ok", false)) and not reason.is_empty(), label + " 操作当场明确拒绝而非commit后build失败", reason)
		check(rejected.get("root") == null, label + " 不返回假成功预览")
		var after_snapshot: Dictionary = session.call("snapshot")
		var snapshot_unchanged: bool = JSON.stringify(after_snapshot) == before_json
		check(snapshot_unchanged, label + " 原子拒绝保持snapshot不变")
		var retained: Dictionary = session.get("_last_build")
		var retained_preview: bool = is_instance_valid(preview) and retained.get("root") == preview
		check(retained_preview, label + " 原子拒绝保持last_build.root身份")
		var geometry_unchanged: bool = false
		if is_instance_valid(preview): geometry_unchanged = str(_inventory(preview).geometry_hash) == before_hash
		check(geometry_unchanged, label + " 失败不释放或改变已有预览几何")
		var state_unchanged: bool = _session_state(session) == before_state
		check(state_unchanged, label + " 失败不改catalog/撤销重做历史/dirty及保存身份")
		report.session_atomic_rejections[label] = {"method": entry.method, "reason": reason, "snapshot_unchanged": snapshot_unchanged, "retained_preview": retained_preview, "geometry_unchanged": geometry_unchanged, "state_unchanged": state_unchanged}
		var failed_root: Node3D = rejected.get("root") as Node3D
		if is_instance_valid(failed_root) and failed_root != preview: failed_root.free()
	if is_instance_valid(preview): preview.free()

func _test_window_weathering(source: Dictionary, catalog: Dictionary) -> void:
	check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "门窗风化QA仅在主线程执行")
	var original: String = JSON.stringify(source)
	var recipe: Dictionary = source.duplicate(true)
	recipe.merge({"building_id": "window_weathering", "shape": "rectangle", "width": 12.0, "depth": 9.0, "floors": 3, "taper": 0.0, "aging": 0.0, "damage": 0.0, "vegetation_density": 0.0}, true)
	recipe.architecture.form.enabled = false
	var built: Dictionary = Generator.build(recipe, catalog)
	var root: Node3D = built.get("root") as Node3D
	check(bool(built.get("ok", false)) and root != null, "门窗风化clean基线生成", str(built.get("reason", "")))
	if root == null: return
	var clean: Dictionary = _inventory(root)
	_check_audit("门窗风化clean", _audit_inventory(clean))
	var clean_glass: String = _prefix_hash(clean, "glass_")
	var clean_door: String = _prefix_hash(clean, "door_")
	var uv_hashes: Dictionary = {}
	var patch_hashes: Dictionary = {}
	report["window_weathering"] = {"aging": {}, "damage": {}}
	for amount: float in [0.0, 0.2, 0.5, 0.9]:
		var aged_recipe: Dictionary = recipe.duplicate(true)
		aged_recipe.aging = amount
		var aged_build: Dictionary = Generator.build(aged_recipe, catalog)
		var aged_root: Node3D = aged_build.get("root") as Node3D
		var label: String = "aging=%s" % str(amount)
		check(bool(aged_build.get("ok", false)) and aged_root != null, label + " 生成真实网格", str(aged_build.get("reason", "")))
		if aged_root == null: continue
		var aged: Dictionary = _inventory(aged_root)
		_check_audit(label, _audit_inventory(aged, amount))
		_check_weathering_parts(label, aged, 4 * int(recipe.floors), amount > 0.0)
		check(_preserved_parts(clean, aged, false) and _same_collision_faces(clean, aged), label + " 原件几何与全部结构碰撞不变，仅增斑驳及换UV")
		var uv_hash: String = _prefix_hash(aged, "wall_shell_", true)
		var patch_hash: String = _prefix_hash(aged, "wall_weathering_")
		check(not uv_hashes.has(uv_hash), label + " 四档墙UV互异")
		uv_hashes[uv_hash] = true
		if amount > 0.0:
			check(not patch_hashes.has(patch_hash), label + " 斑驳实际面随老化改变")
			patch_hashes[patch_hash] = true
		else:
			check(_same_geometry(clean, aged) and clean.geometry_hash == aged.geometry_hash, label + " 零值严格保持clean几何/UV/数量")
		_check_shell_materials(label, aged, catalog)
		report.window_weathering.aging[str(amount)] = {"wall_uv_hash": uv_hash, "patch_geometry_hash": patch_hash, "inventory": _public_inventory(aged, {})}
		aged_root.free()
	var previous_glass: String = clean_glass
	var previous_volume: float = _prefix_volume(clean, "glass_")
	var previous_door_volume: float = _prefix_volume(clean, "door_")
	var session: RefCounted = Session.new(catalog)
	check(bool(session.call("accept_loaded", recipe, catalog).get("ok", false)), "damage接受测试载入shell会话")
	for amount: float in [0.0, 0.4, 0.9, 1.0]:
		var patched: Dictionary = session.call("apply_patch", {"damage": amount})
		var label: String = "damage=%s" % str(amount)
		var loaded_session: RefCounted = Session.new(catalog)
		var candidate: Dictionary = recipe.duplicate(true)
		candidate.damage = amount
		var loaded: Dictionary = loaded_session.call("accept_loaded", candidate, catalog)
		check(bool(loaded.get("ok", false)), label + " accept_loaded当场接受合法0..1", str(loaded.get("reason", "")))
		check(bool(patched.get("ok", false)), label + " apply_patch当场接受合法0..1", str(patched.get("reason", "")))
		var damaged_build: Dictionary = session.call("build")
		var damaged_root: Node3D = damaged_build.get("root") as Node3D
		check(bool(damaged_build.get("ok", false)) and damaged_root != null, label + " 实际生成", str(damaged_build.get("reason", "")))
		if damaged_root == null: continue
		var damaged: Dictionary = _inventory(damaged_root)
		_check_audit(label, _audit_inventory(damaged))
		check(damaged.parts.size() == clean.parts.size() and _preserved_parts(clean, damaged, true) and _same_collision_faces(clean, damaged), label + " 不删除整件，除玻璃门扇外全部原件及碰撞保持，门洞墙板不变")
		for id: String in clean.parts:
			if not id.begins_with("glass_") and not id.begins_with("door_"): continue
			var actual_faces: PackedVector3Array = damaged.parts.get(id, PackedVector3Array())
			check(not actual_faces.is_empty() and (amount == 0.0 or not _same_faces(clean.parts[id], actual_faces)), label + " 每件填充仍存在且非零值确实裁口：" + id)
		check(_collision_matches_visual(damaged) and _no_accessory_collision(damaged) and int(damaged.invalid_collision_shapes) == 0, label + " 结构碰撞仍匹配实际三角面，填充件无碰撞")
		var glass_hash: String = _prefix_hash(damaged, "glass_")
		var door_hash: String = _prefix_hash(damaged, "door_")
		var volume: float = _prefix_volume(damaged, "glass_")
		var door_volume: float = _prefix_volume(damaged, "door_")
		if amount > 0.0:
			check(glass_hash != clean_glass and glass_hash != previous_glass and door_hash != clean_door, label + " 实际玻璃面/hash和木门缺口变化")
			check(volume > 0.0 and volume < previous_volume and door_volume > 0.0 and door_volume < previous_door_volume, label + " 缺失量递增且仍保留完整连通实体")
			_check_damage_profile(label, clean, damaged, "glass_front_0_0", false)
			_check_damage_profile(label, clean, damaged, "door_front_0_1", true)
		else:
			check(clean.geometry_hash == damaged.geometry_hash and _same_geometry(clean, damaged), label + " 严格走原完整门窗路径")
		previous_glass = glass_hash
		previous_volume = volume
		previous_door_volume = door_volume
		_check_shell_materials(label, damaged, catalog)
		var snapshot: Dictionary = session.call("snapshot")
		var repeat: Dictionary = Generator.build(snapshot, catalog)
		var repeat_root: Node3D = repeat.get("root") as Node3D
		check(bool(repeat.get("ok", false)) and repeat_root != null, label + " 同seed重复生成")
		if repeat_root != null:
			var repeated: Dictionary = _inventory(repeat_root)
			check(damaged.geometry_hash == repeated.geometry_hash and _same_geometry(damaged, repeated), label + " 同damage_seed面/UV/碰撞确定性")
			repeat_root.free()
		if amount == 0.9:
			var changed_seed: Dictionary = snapshot.duplicate(true)
			changed_seed.damage_seed = int(snapshot.damage_seed) + 1
			var seeded_build: Dictionary = Generator.build(changed_seed, catalog)
			var seeded_root: Node3D = seeded_build.get("root") as Node3D
			check(bool(seeded_build.get("ok", false)) and seeded_root != null, "不同damage_seed实际生成")
			if seeded_root != null:
				var seeded: Dictionary = _inventory(seeded_root)
				check(_prefix_hash(seeded, "glass_") != glass_hash and _preserved_parts(damaged, seeded, true) and _same_collision_faces(damaged, seeded), "换damage_seed仅改变填充件，不串结构")
				seeded_root.free()
			var combined: Dictionary = snapshot.duplicate(true)
			combined.aging = 0.9
			_test_store(combined, catalog, "weathered_damaged")
		report.window_weathering.damage[str(amount)] = {"glass_hash": glass_hash, "door_hash": door_hash, "glass_volume": volume, "door_volume": door_volume, "inventory": _public_inventory(damaged, {})}
		damaged_root.free()
	root.free()
	check(JSON.stringify(source) == original, "门窗风化不修改源配方")
	_check_shared_materials_unchanged("门窗风化后")

func _check_damage_profile(label: String, clean: Dictionary, damaged: Dictionary, id: String, door: bool) -> void:
	var original: PackedVector3Array = clean.parts.get(id, PackedVector3Array())
	var actual: PackedVector3Array = damaged.parts.get(id, PackedVector3Array())
	check(not original.is_empty() and not actual.is_empty(), label + " 缺口射线目标存在：" + id)
	if original.is_empty() or actual.is_empty(): return
	var box: AABB = _bounds(original)
	var missing: int = 0
	var retained: int = 0
	var intact_edges: bool = true
	for row: int in range(1, 20):
		for column: int in range(1, 20):
			var u: float = float(column) / 20.0
			var v: float = float(row) / 20.0
			var point: Vector3 = Vector3(box.position.x + box.size.x * u, box.position.y + box.size.y * v, box.get_center().z)
			var before_hit: bool = int(_ray(original, point + Vector3.FORWARD, point + Vector3.BACK).hits) > 0
			var after_hit: bool = int(_ray(actual, point + Vector3.FORWARD, point + Vector3.BACK).hits) > 0
			if before_hit and not after_hit: missing += 1
			if after_hit: retained += 1
			if row == 19 or (not door and row == 1): intact_edges = intact_edges and after_hit
			if door and v >= 0.30: intact_edges = intact_edges and after_hit
	check(missing > 0 and retained > 0 and intact_edges, label + (" 木门仅下缘真实缺口，上部保留" if door else " 玻璃侧破口真实贯穿，上下缘保留") + "：" + id, "missing=%d retained=%d" % [missing, retained])

func _prefix_hash(inventory: Dictionary, prefix: String, uv_only: bool = false) -> String:
	var entries: Array[String] = []
	for record: Dictionary in inventory.mesh_records:
		if not str(record.id).begins_with(prefix): continue
		var mesh: Mesh = record.mesh
		var data: Array = []
		for surface: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			data.append(arrays[Mesh.ARRAY_TEX_UV] if uv_only else arrays)
		entries.append(str(record.id) + var_to_bytes([record.transform, data]).hex_encode().sha256_text())
	entries.sort()
	return "|".join(entries).sha256_text()

func _prefix_volume(inventory: Dictionary, prefix: String) -> float:
	var volume: float = 0.0
	for id: String in inventory.parts:
		if id.begins_with(prefix): volume += float(_topology(inventory.parts[id]).signed_volume)
	return volume

func _preserved_parts(before: Dictionary, after: Dictionary, damage: bool) -> bool:
	for id: String in before.parts:
		if damage and (id.begins_with("glass_") or id.begins_with("door_")): continue
		if not after.parts.has(id) or not _same_faces(before.parts[id], after.parts[id]): return false
	for id: String in after.parts:
		if not before.parts.has(id) and not id.begins_with("wall_weathering_"): return false
	return true

func _same_collision_faces(before: Dictionary, after: Dictionary) -> bool:
	if before.collisions.size() != after.collisions.size(): return false
	for id: String in before.collisions:
		if not after.collisions.has(id) or not _same_faces(before.collisions[id], after.collisions[id]): return false
	return true

func _check_weathering_parts(label: String, inventory: Dictionary, max_patches: int, enabled: bool) -> void:
	var seen: Dictionary = {}
	var count: int = 0
	for record: Dictionary in inventory.mesh_records:
		var id: String = str(record.id)
		if not id.begins_with("wall_weathering_"): continue
		count += 1
		var address: PackedStringArray = id.trim_prefix("wall_weathering_").split("_")
		var valid_address: bool = address.size() == 2 and address[0].is_valid_int() and address[1].is_valid_int()
		if valid_address: valid_address = int(address[0]) >= 0 and int(address[0]) < int(max_patches / 4) and int(address[1]) >= 0 and int(address[1]) < 4
		check(valid_address, label + " 斑驳地址属于真实floor/run：" + id)
		check(not seen.has(id), label + " 每floor/run至多一片斑驳：" + id)
		seen[id] = true
		var faces: PackedVector3Array = inventory.parts[id]
		check(_closed_single(_topology(faces)) and not inventory.collisions.has(id), label + " 斑驳单连通闭合且无碰撞：" + id)
		var mesh_node: MeshInstance3D = record.node
		check(mesh_node.visible and not faces.is_empty(), label + " 斑驳是可见真实几何：" + id)
	check((count > 0 and count <= max_patches) if enabled else count == 0, label + " 斑驳数量符合每run至多一片", str(count))

func _session_state(session: RefCounted) -> String:
	return Catalog.fingerprint({"catalog": session.get("catalog"), "undo": session.get("_undo"), "redo": session.get("_redo"), "saved_fingerprint": session.get("_saved_fingerprint"), "dirty": session.call("is_dirty")})

func _test_legacy_samples(catalog: Dictionary) -> void:
	check(str(Recipe.defaults().get("construction_mode", "")) == "modular_v1", "旧defaults仍为modular_v1")
	for path: String in SAMPLE_PATHS:
		var source_hash: String = FileAccess.get_sha256(path)
		var sample: Dictionary = _read_json(path)
		check(not sample.is_empty(), "旧sample配方可读取", path)
		if sample.is_empty(): continue
		check(str(Recipe.normalized(sample).get("construction_mode", "")) == "modular_v1", "缺省旧sample仍映射modular_v1", path)
		var explicit: Dictionary = sample.duplicate(true)
		explicit.construction_mode = "modular_v1"
		var implicit_build: Dictionary = Generator.build(sample, catalog)
		var explicit_build: Dictionary = Generator.build(explicit, catalog)
		var implicit_root: Node3D = implicit_build.get("root") as Node3D
		var explicit_root: Node3D = explicit_build.get("root") as Node3D
		check(bool(implicit_build.get("ok", false)) and bool(explicit_build.get("ok", false)) and implicit_root != null and explicit_root != null, "旧sample两种模式写法均可生成", path)
		if implicit_root != null and explicit_root != null:
			var first: Dictionary = _inventory(implicit_root)
			var second: Dictionary = _inventory(explicit_root)
			check(str(first.geometry_hash) == str(second.geometry_hash), "旧sample缺省与显式modular几何不变", path)
			check(_slot_signature(implicit_build.get("slots", [])) == _slot_signature(explicit_build.get("slots", [])), "旧sample槽位映射不变", path)
			check(str(implicit_root.get_meta("generator_version", "")) == Generator.GENERATOR_VERSION and not first.parts.has("wall_shell_0") and not first.parts.has("roof_main"), "旧sample未被迁移为shell", path)
			report.legacy_samples[path] = _public_inventory(first, {})
		if implicit_root != null: implicit_root.free()
		if explicit_root != null: explicit_root.free()
		check(FileAccess.get_sha256(path) == source_hash, "旧sample文件未改写", path)

func _test_store(recipe: Dictionary, catalog: Dictionary, label: String) -> void:
	var store: RefCounted = Store.new()
	var base_dir: String = "user://building_workshop/" + run_id + "/" + label
	var exported: Dictionary = store.call("export_revision", recipe, catalog, base_dir)
	check(bool(exported.get("ok", false)), label + " Store.export_revision真实保存", str(exported.get("reason", "")))
	var entry: Dictionary = {"ok": bool(exported.get("ok", false)), "reason": str(exported.get("reason", "")), "saved_scene": str(exported.get("scene_path", ""))}
	if not report.has("store"): report["store"] = {}
	report.store[label] = entry
	if not bool(exported.get("ok", false)): return
	var scene_path: String = str(exported.get("scene_path", ""))
	if label == "baseline": report.saved_scene = scene_path
	check(scene_path.begins_with(base_dir + "/"), label + " 保存仅使用隔离user路径")
	var loaded_document: Dictionary = store.call("load_recipe", str(exported.recipe_path))
	check(bool(loaded_document.get("ok", false)), label + " 配方及catalog可往返读取", str(loaded_document.get("reason", "")))
	if bool(loaded_document.get("ok", false)):
		check(Recipe.fingerprint(loaded_document.recipe) == Recipe.fingerprint(exported.recipe), label + " 配方往返保持身份")
		check(Catalog.fingerprint(loaded_document.catalog) == Catalog.fingerprint(catalog), label + " prefab目录快照往返保持身份")
	var packed: PackedScene = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(packed != null, label + " 已保存PackedScene可重载")
	if packed == null: return
	var saved_root: Node3D = packed.instantiate() as Node3D
	check(saved_root != null, label + " 已保存静态场景可实例化")
	if saved_root == null: return
	var before_build: Dictionary = Generator.build(exported.recipe, catalog)
	var before_root: Node3D = before_build.get("root") as Node3D
	check(before_root != null and bool(before_build.get("ok", false)), label + " 保存对照可重新生成", str(before_build.get("reason", "")))
	var saved: Dictionary = _inventory(saved_root)
	var audit: Dictionary = _audit_inventory(saved, float(exported.recipe.get("aging", 0.0)))
	_check_shell_materials(label + " 保存重载", saved, catalog)
	_check_weathering_parts(label + " 保存重载", saved, 4 * int(recipe.floors), float(recipe.get("aging", 0.0)) > 0.0)
	entry["reload"] = _public_inventory(saved, audit)
	_check_audit(label + " 保存重载", audit)
	check(int(saved.scripts) == 0 and int(saved.unowned_nodes) == 0, label + " 重载静态树无脚本且owner完整")
	check(str(saved_root.get_meta("generator_version", "")) == ShellGenerator.GENERATOR_VERSION, label + " 保存根generator metadata为当前shell版本")
	check(str(saved_root.get_meta("construction_mode", "")) == "shell_v2", label + " 保存根construction_mode仍为shell_v2")
	if before_root != null:
		var before: Dictionary = _inventory(before_root)
		check(int(saved.collision_shapes) == int(before.collision_shapes), label + " 保存重载collision数量保持")
		check(_same_geometry(before, saved), label + " 保存重载实际视觉及碰撞三角面保持尺寸与位置")
		check(_prefix_hash(before, "wall_shell_", true) == _prefix_hash(saved, "wall_shell_", true), label + " 保存重载墙UV hash保持")
		check(_prefix_hash(before, "glass_") == _prefix_hash(saved, "glass_") and _prefix_hash(before, "door_") == _prefix_hash(saved, "door_") and _prefix_hash(before, "wall_weathering_") == _prefix_hash(saved, "wall_weathering_"), label + " 保存重载玻璃缺口/门扇/斑驳mesh hash保持")
		before_root.free()
	var manifest: Dictionary = _read_json(str(exported.manifest_path))
	entry["manifest_generator"] = manifest.get("generator", "")
	check(str(manifest.get("generator", "")) == ShellGenerator.GENERATOR_VERSION, label + " manifest生成器版本不得误标为legacy", str(manifest.get("generator", "")))
	check(str(saved_root.get_meta("recipe_fingerprint", "")) == Recipe.fingerprint(exported.recipe), label + " 保存根配方fingerprint为当前revision")
	check(_collision_matches_visual(saved) and _no_accessory_collision(saved), label + " 重载结构真碰撞与玻璃无碰撞契约保持")
	saved_root.free()

func _test_prefabs(recipe: Dictionary, catalog: Dictionary) -> void:
	var session: RefCounted = Session.new(catalog)
	check(session.has_method("replace_document"), "prefab主线程会话实现replace_document；缺失视为失败而非跳过")
	if not session.has_method("replace_document"):
		report.prefabs["failure"] = "TODO失败：session.replace_document尚未实现"
		return
	var accepted: Dictionary = session.call("accept_loaded", recipe, catalog)
	check(bool(accepted.get("ok", false)), "prefab测试载入真实会话", str(accepted.get("reason", "")))
	if not bool(accepted.get("ok", false)): return
	var initial_build: Dictionary = session.call("build")
	var initial_root: Node3D = initial_build.get("root") as Node3D
	check(initial_root != null and bool(initial_build.get("ok", false)), "prefab替换前生成成功", str(initial_build.get("reason", "")))
	if initial_root == null: return
	var initial: Dictionary = _inventory(initial_root)
	var initial_slots: Dictionary = _slot_map(initial_build.get("slots", []))
	var window_suffix: String = ""
	for opening: Dictionary in initial_build.get("openings", []):
		if str(opening.get("type", "")) == "window":
			window_suffix = str(opening.id).trim_prefix("opening_")
			break
	initial_root.free()
	check(not window_suffix.is_empty(), "frame/glass替件有真实窗洞可选")
	var targets: Array[String] = ["wall_shell_0"]
	if not window_suffix.is_empty():
		targets.append("frame_" + window_suffix)
		targets.append("glass_" + window_suffix)
	for id: String in targets:
		var entry: Dictionary = {}
		report.prefabs[id] = entry
		var exported: Dictionary = Adapter.export_slot(session, id, "res://scenes/components/workshop_shell_qa/" + run_id)
		entry["export"] = _json_value(exported)
		check(bool(exported.get("ok", false)), id + " export_slot导出整件而非拆盒", str(exported.get("reason", "")))
		if not bool(exported.get("ok", false)): continue
		var packed: PackedScene = ResourceLoader.load(str(exported.scene_path), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(packed != null, id + " 模块场景可重载")
		if packed == null: continue
		var module: Node3D = packed.instantiate() as Node3D
		check(module != null, id + " 模块可实例化")
		if module == null: continue
		var measured: Dictionary = _inventory(module)
		var faces: PackedVector3Array = _all_faces(measured.parts)
		var topology: Dictionary = _topology(faces)
		entry["actual_topology"] = topology
		check(int(measured.visual_meshes) == 1, id + " 整件导出仅一个实际mesh")
		check(_closed_single(topology), id + " 导出替件仅一个闭合连通实体", str(topology))
		if id.begins_with("frame_"): check(int(topology.euler) == 0, id + " 导出窗框仍是单环")
		check(_identity_bases(module), id + " 导出替件无缩放或旋转烘焙作弊")
		var expected_size: Vector3 = _vector(initial_slots.get(id, {}).get("bounds_size", []))
		check(_bounds(faces).size.distance_to(expected_size) <= SAVE_EPS, id + " 导出替件实际尺寸保持")
		module.free()
		var applied: Dictionary = Adapter.apply_prefab_to_slot(session, id, str(exported.scene_path))
		entry["apply"] = _json_value(applied)
		check(bool(applied.get("ok", false)), id + " apply_prefab_to_slot真实提交", str(applied.get("reason", "")))
		if not bool(applied.get("ok", false)): continue
		var replaced: Dictionary = session.call("build")
		var replaced_root: Node3D = replaced.get("root") as Node3D
		check(bool(replaced.get("ok", false)) and replaced_root != null, id + " 替件后真实build成功", str(replaced.get("reason", "")))
		if replaced_root == null: continue
		var actual: Dictionary = _inventory(replaced_root)
		entry["rebuilt"] = _public_inventory(actual, _audit_inventory(actual))
		check(_same_geometry(initial, actual, false), id + " 替件后整栋真实几何与碰撞位置尺寸不变")
		check(_identity_bases(replaced_root), id + " 替件装配不scale")
		var current_slots: Dictionary = _slot_map(replaced.get("slots", []))
		var target: Dictionary = current_slots.get(id, {})
		check(not target.is_empty() and _vector(target.get("bounds_size", [])).distance_to(expected_size) <= SAVE_EPS and _vector(target.get("position", [])).distance_to(_vector(initial_slots.get(id, {}).get("position", []))) <= SAVE_EPS, id + " 槽位anchor及size身份保持")
		check(str(target.get("component_id", "")) == str(applied.get("component_id", "")), id + " 槽位组件身份指向真实prefab")
		check(_closed_single(_topology(actual.parts.get(id, PackedVector3Array()))), id + " 装配替件保持单闭合part")
		check(_no_accessory_collision(actual), id + " 替件窗框及玻璃仍不碰撞")
		replaced_root.free()
		var current_recipe: Dictionary = session.call("snapshot")
		var current_catalog: Dictionary = session.get("catalog")
		_test_store(current_recipe, current_catalog, "prefab_" + id)

func _inventory(building: Node3D) -> Dictionary:
	var result: Dictionary = {"nodes": 0, "triangles": 0, "structure_triangles": 0, "visual_meshes": 0, "collision_shapes": 0, "invalid_collision_shapes": 0, "scripts": 0, "unowned_nodes": 0, "parts": {}, "collisions": {}, "mesh_records": [], "geometry_hash": ""}
	var stack: Array[Node] = [building]
	var hashes: Array[String] = []
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		result.nodes += 1
		if node.get_script() != null: result.scripts += 1
		if node != building and node.owner == null: result.unowned_nodes += 1
		var id: String = str(node.get_meta("slot_id", str(node.name)))
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			var mesh: Mesh = mesh_node.mesh
			result.visual_meshes += 1
			if mesh != null:
				var transform: Transform3D = _relative(mesh_node, building)
				var faces: PackedVector3Array = _transformed(mesh.get_faces(), transform)
				if not result.parts.has(id): result.parts[id] = PackedVector3Array()
				var combined: PackedVector3Array = result.parts[id]
				combined.append_array(faces)
				result.parts[id] = combined
				var triangles: int = int(faces.size() / 3)
				result.triangles += triangles
				if _structural(id): result.structure_triangles += triangles
				result.mesh_records.append({"id": id, "node": mesh_node, "mesh": mesh, "transform": transform})
				var surface_data: Array = []
				for surface: int in mesh.get_surface_count(): surface_data.append(mesh.surface_get_arrays(surface))
				hashes.append(id + ":" + str(building.get_path_to(node)) + ":" + var_to_bytes([transform, surface_data]).hex_encode().sha256_text())
		if node is CollisionShape3D:
			result.collision_shapes += 1
			var shape_node: CollisionShape3D = node as CollisionShape3D
			if shape_node.disabled or not shape_node.shape is ConcavePolygonShape3D:
				result.invalid_collision_shapes += 1
			else:
				var shape: ConcavePolygonShape3D = shape_node.shape as ConcavePolygonShape3D
				var faces: PackedVector3Array = _transformed(shape.get_faces(), _relative(shape_node, building))
				if not result.collisions.has(id): result.collisions[id] = PackedVector3Array()
				var combined: PackedVector3Array = result.collisions[id]
				combined.append_array(faces)
				result.collisions[id] = combined
		for child: Node in node.get_children(): stack.append(child)
	hashes.sort()
	result.geometry_hash = "\n".join(hashes).sha256_text()
	return result

func _audit_inventory(inventory: Dictionary, aging: float = 0.0) -> Dictionary:
	var result: Dictionary = {"parts": {}, "bad_parts": {}, "boundary_edges": 0, "nonmanifold_edges": 0, "orientation_errors": 0, "duplicate_triangles": 0, "degenerate_triangles": 0, "nonfinite_vertices": 0, "normal_errors": 0, "uv_area_errors": 0, "uv_safe_errors": 0, "colour_errors": 0, "disconnected_parts": 0, "window_ring_errors": 0, "window_frames": 0, "nonpositive_volumes": 0}
	for id: String in inventory.parts:
		var topology: Dictionary = _topology(inventory.parts[id])
		result.parts[id] = topology
		for field: String in ["boundary_edges", "nonmanifold_edges", "orientation_errors", "duplicate_triangles", "degenerate_triangles", "nonfinite_vertices"]:
			_accumulate_issue(result, field, int(topology[field]), id)
		_accumulate_issue(result, "disconnected_parts", 0 if int(topology.components) == 1 else 1, id)
		_accumulate_issue(result, "nonpositive_volumes", 0 if float(topology.signed_volume) > 0.00000001 else 1, id)
		if id.begins_with("frame_"):
			# 门框是U形单实体；窗框则必须是Euler=0的闭合单环。
			var suffix: String = id.trim_prefix("frame_")
			if inventory.parts.has("glass_" + suffix):
				result.window_frames += 1
				_accumulate_issue(result, "window_ring_errors", 0 if _closed_single(topology) and int(topology.euler) == 0 else 1, id)
	for record: Dictionary in inventory.mesh_records:
		var attributes: Dictionary = _attributes(record, aging)
		result.parts[str(record.id)]["attributes"] = attributes
		for field: String in ["normal_errors", "uv_area_errors", "uv_safe_errors", "colour_errors"]:
			_accumulate_issue(result, field, int(attributes[field]), str(record.id))
	return result

func _accumulate_issue(audit: Dictionary, field: String, count: int, id: String) -> void:
	audit[field] = int(audit[field]) + count
	if count > 0:
		if not audit.bad_parts.has(field): audit.bad_parts[field] = []
		if not audit.bad_parts[field].has(id): audit.bad_parts[field].append(id)

func _topology(faces: PackedVector3Array) -> Dictionary:
	var result: Dictionary = {"triangles": int(faces.size() / 3), "vertices": 0, "edges": 0, "boundary_edges": 0, "nonmanifold_edges": 0, "orientation_errors": 0, "duplicate_triangles": 0, "degenerate_triangles": 0, "nonfinite_vertices": 0, "components": 0, "euler": 0, "signed_volume": 0.0}
	var vertices: Dictionary = {}
	var edges: Dictionary = {}
	var triangles: Dictionary = {}
	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(int(result.triangles))
	for triangle: int in int(result.triangles): parents[triangle] = triangle
	for start: int in range(0, faces.size() - 2, 3):
		var triangle: int = int(start / 3)
		var points: Array[Vector3] = [faces[start], faces[start + 1], faces[start + 2]]
		var finite: bool = true
		for point: Vector3 in points:
			if not point.is_finite():
				result.nonfinite_vertices += 1
				finite = false
		if not finite: continue
		var keys: Array[String] = [_position_key(points[0]), _position_key(points[1]), _position_key(points[2])]
		var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
		if cross.length_squared() <= 0.000000000000000001 or keys[0] == keys[1] or keys[1] == keys[2] or keys[2] == keys[0]: result.degenerate_triangles += 1
		result.signed_volume = float(result.signed_volume) - points[0].dot(points[1].cross(points[2])) / 6.0
		var sorted: Array[String] = keys.duplicate()
		sorted.sort()
		var triangle_key: String = "|".join(sorted)
		if triangles.has(triangle_key): result.duplicate_triangles += 1
		triangles[triangle_key] = true
		for edge: int in 3:
			var a: String = keys[edge]
			var b: String = keys[(edge + 1) % 3]
			vertices[a] = true
			var forward: bool = a < b
			var key: String = a + ":" + b if forward else b + ":" + a
			if edges.has(key):
				var entry: Dictionary = edges[key]
				entry.count = int(entry.count) + 1
				entry.orientation = int(entry.orientation) + (1 if forward else -1)
				var first_root: int = _find(parents, int(entry.triangle))
				var this_root: int = _find(parents, triangle)
				if first_root != this_root: parents[this_root] = first_root
			else:
				edges[key] = {"count": 1, "orientation": 1 if forward else -1, "triangle": triangle}
	var components: Dictionary = {}
	for triangle: int in parents.size(): components[_find(parents, triangle)] = true
	for entry: Dictionary in edges.values():
		if int(entry.count) == 1: result.boundary_edges += 1
		elif int(entry.count) != 2: result.nonmanifold_edges += 1
		if int(entry.orientation) != 0: result.orientation_errors += 1
	result.vertices = vertices.size()
	result.edges = edges.size()
	result.components = components.size()
	result.euler = vertices.size() - edges.size() + int(result.triangles)
	return result

func _find(parents: PackedInt32Array, start: int) -> int:
	var current: int = start
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current

func _attributes(record: Dictionary, aging: float = 0.0) -> Dictionary:
	var result: Dictionary = {"normal_errors": 0, "uv_area_errors": 0, "uv_safe_errors": 0, "colour_errors": 0, "colour_samples": []}
	var mesh: Mesh = record.mesh
	var node: MeshInstance3D = record.node
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index: int in vertices.size(): indices.append(index)
		if normals.size() != vertices.size(): result.normal_errors += 1
		if uv.size() != vertices.size():
			result.uv_safe_errors += 1
			result.uv_area_errors += 1
			result.colour_errors += 1
			continue
		var material: ShaderMaterial = node.get_active_material(surface) as ShaderMaterial
		var texture: Texture2D = material.get_shader_parameter("palette") as Texture2D if material != null else null
		var image: Image = null
		if texture != null:
			var cache_key: int = texture.get_instance_id()
			if not image_cache.has(cache_key):
				var captured: Image = texture.get_image()
				if captured != null and captured.is_compressed():
					var decompressed: Error = captured.decompress()
					if decompressed != OK: captured = null
				image_cache[cache_key] = captured
			image = image_cache[cache_key] as Image
		if image == null or image.is_empty() or image.get_size() != Vector2i(512, 512) or texture != load(SHARED_PALETTE_PATH): result.colour_errors += 1
		var triangle_count: int = int(indices.size() / 3)
		var sample_step: int = maxi(1, int(triangle_count / 4))
		for start: int in range(0, indices.size() - 2, 3):
			var a: int = indices[start]
			var b: int = indices[start + 1]
			var c: int = indices[start + 2]
			var expected_normal: Vector3 = -(vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).normalized()
			if normals.size() == vertices.size():
				for index: int in [a, b, c]:
					if not normals[index].is_finite() or absf(normals[index].length() - 1.0) > 0.01 or normals[index].dot(expected_normal) < 0.95: result.normal_errors += 1
			if absf((uv[b] - uv[a]).cross(uv[c] - uv[a])) * 0.5 <= 0.00000001: result.uv_area_errors += 1
			var cell: Vector2i = Vector2i(floori(uv[a].x * 8.0), floori(uv[a].y * 8.0))
			for index: int in [a, b, c]:
				var point: Vector2 = uv[index]
				if not point.is_finite():
					result.uv_safe_errors += 1
					continue
				var pixel: Vector2 = point * 512.0 - Vector2(cell) * 64.0
				if cell.x < 0 or cell.x > 7 or cell.y < 0 or cell.y > 7 or Vector2i(floori(point.x * 8.0), floori(point.y * 8.0)) != cell or pixel.x < 16.0 - WELD or pixel.x > 48.0 + WELD or pixel.y < 16.0 - WELD or pixel.y > 48.0 + WELD: result.uv_safe_errors += 1
			if int(start / 3) % sample_step != 0 or image == null or image.is_empty(): continue
			var center: Vector2 = (uv[a] + uv[b] + uv[c]) / 3.0
			if not center.is_finite():
				result.colour_errors += 1
				continue
			var sampled: Color = image.get_pixel(clampi(floori(center.x * image.get_width()), 0, image.get_width() - 1), clampi(floori(center.y * image.get_height()), 0, image.get_height() - 1))
			var semantic: Dictionary = _semantic(record, cell, aging)
			var expected: Color = Color(str(semantic.get("hex", "#FF00FF")))
			var error: float = maxf(absf(sampled.r - expected.r), maxf(absf(sampled.g - expected.g), absf(sampled.b - expected.b)))
			if semantic.is_empty() or error > 0.055 or material == null: result.colour_errors += 1
			result.colour_samples.append({"cell": [cell.x, cell.y], "rgb": [sampled.r, sampled.g, sampled.b], "expected": semantic.get("hex", ""), "error": error})
	return result

func _semantic(record: Dictionary, cell: Vector2i, aging: float = 0.0) -> Dictionary:
	var semantics: Dictionary = palette.get("semantics", {}).duplicate(true)
	# QA独立列举色格与RGB，不能用被测编码函数自己证明自己正确。
	var stages: Array[Dictionary] = [semantics.get("cozy", {}), semantics.get("cozy_aged_light", semantics.get("slab_aged", {})), semantics.get("cozy_aged_medium", {"row": 0, "column": 5, "hex": "#CACEB0"}), semantics.get("cozy_aged_heavy", {"row": 7, "column": 3, "hex": "#748D97"})]
	var cozy: Dictionary = stages[0 if aging <= 0.0 else (1 if aging < 0.35 else (2 if aging < 0.70 else 3))]
	var weathering: Dictionary = semantics.get("cozy_weathering", semantics.get("timber_aged", {}))
	semantics["shell_cozy"] = cozy
	semantics["shell_weathering"] = weathering
	if str(record.id).begins_with("wall_"):
		var expected: Dictionary = weathering if str(record.id).begins_with("wall_weathering_") else cozy
		return expected if int(expected.get("column", -1)) == cell.x and int(expected.get("row", -1)) == cell.y else {}
	for semantic: Dictionary in semantics.values():
		if int(semantic.get("column", -1)) == cell.x and int(semantic.get("row", -1)) == cell.y: return semantic
	return {}

func _ray(faces: PackedVector3Array, from: Vector3, to: Vector3) -> Dictionary:
	var result: Dictionary = {"hits": 0, "position": [0.0, 0.0, 0.0], "normal": [0.0, 0.0, 0.0]}
	var direction: Vector3 = to - from
	var nearest: float = INF
	for start: int in range(0, faces.size() - 2, 3):
		var a: Vector3 = faces[start]
		var edge1: Vector3 = faces[start + 1] - a
		var edge2: Vector3 = faces[start + 2] - a
		var cross: Vector3 = direction.cross(edge2)
		var determinant: float = edge1.dot(cross)
		if absf(determinant) < 0.000000001: continue
		var inverse: float = 1.0 / determinant
		var offset: Vector3 = from - a
		var u: float = offset.dot(cross) * inverse
		if u < -0.0000001 or u > 1.0000001: continue
		var q: Vector3 = offset.cross(edge1)
		var v: float = direction.dot(q) * inverse
		if v < -0.0000001 or u + v > 1.0000001: continue
		var t: float = edge2.dot(q) * inverse
		if t < 0.0 or t > 1.0: continue
		result.hits += 1
		if t < nearest:
			nearest = t
			result.position = _xyz(from + direction * t)
			result.normal = _xyz(-edge1.cross(edge2).normalized())
	return result

func _test_auditor() -> void:
	var triangle: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	check(int(_topology(triangle).boundary_edges) == 3, "独立QA能识别开放边")
	var duplicated: PackedVector3Array = triangle.duplicate()
	duplicated.append_array(triangle)
	var duplicate_audit: Dictionary = _topology(duplicated)
	check(int(duplicate_audit.duplicate_triangles) == 1 and int(duplicate_audit.orientation_errors) > 0, "独立QA能识别重复面与同向共享边")
	var disconnected: PackedVector3Array = triangle.duplicate()
	disconnected.append_array(PackedVector3Array([Vector3(3.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), Vector3(3.0, 1.0, 0.0)]))
	check(int(_topology(disconnected).components) == 2, "独立QA按边图识别分离件")
	check(int(_topology(PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.UP])).degenerate_triangles) > 0, "独立QA能识别退化面")
	check(int(_topology(PackedVector3Array([Vector3(NAN, 0.0, 0.0), Vector3.RIGHT, Vector3.UP])).nonfinite_vertices) == 1, "独立QA能识别非有限坐标")

func _same_geometry(before: Dictionary, after: Dictionary, compare_counts: bool = true) -> bool:
	if compare_counts:
		for field: String in ["nodes", "visual_meshes", "triangles", "collision_shapes"]:
			if int(before[field]) != int(after[field]): return false
	for field: String in ["parts", "collisions"]:
		var a: Dictionary = before[field]
		var b: Dictionary = after[field]
		if a.size() != b.size(): return false
		for id: String in a:
			if not b.has(id) or not _same_faces(a[id], b[id]): return false
	return true

func _same_faces(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size(): return false
	for index: int in a.size():
		if not a[index].is_finite() or not b[index].is_finite() or a[index].distance_to(b[index]) > SAVE_EPS: return false
	return true

func _collision_matches_visual(inventory: Dictionary) -> bool:
	for id: String in inventory.parts:
		if _structural(id):
			if not inventory.collisions.has(id) or not _same_faces(inventory.parts[id], inventory.collisions[id]): return false
	for id: String in inventory.collisions:
		if not _structural(id): return false
	return true

func _no_accessory_collision(inventory: Dictionary) -> bool:
	for id: String in inventory.collisions:
		if id.begins_with("frame_") or id.begins_with("glass_") or id.begins_with("door_") or id.begins_with("wall_weathering_"): return false
	return true

func _closed_single(topology: Dictionary) -> bool:
	return int(topology.triangles) > 0 and int(topology.boundary_edges) == 0 and int(topology.nonmanifold_edges) == 0 and int(topology.orientation_errors) == 0 and int(topology.components) == 1 and int(topology.duplicate_triangles) == 0 and int(topology.degenerate_triangles) == 0 and int(topology.nonfinite_vertices) == 0

func _identity_bases(building: Node3D) -> bool:
	var stack: Array[Node] = [building]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and not (node as Node3D).basis.is_equal_approx(Basis.IDENTITY): return false
		for child: Node in node.get_children(): stack.append(child)
	return true

func _public_inventory(inventory: Dictionary, audit: Dictionary) -> Dictionary:
	return {"nodes": inventory.nodes, "triangles": inventory.triangles, "structure_triangles": inventory.structure_triangles, "visual_meshes": inventory.visual_meshes, "collision_shapes": inventory.collision_shapes, "invalid_collision_shapes": inventory.invalid_collision_shapes, "geometry_hash": inventory.geometry_hash, "actual_topology": audit, "collision_triangles": _face_counts(inventory.collisions), "part_triangles": _face_counts(inventory.parts)}

func _face_counts(parts: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in parts:
		var faces: PackedVector3Array = parts[id]
		result[id] = int(faces.size() / 3)
	return result

func _all_faces(parts: Dictionary) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for faces: PackedVector3Array in parts.values(): result.append_array(faces)
	return result

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node3D = node
	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

func _transformed(faces: PackedVector3Array, transform: Transform3D) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(faces.size())
	for index: int in faces.size(): result[index] = transform * faces[index]
	return result

func _bounds(faces: PackedVector3Array) -> AABB:
	if faces.is_empty(): return AABB()
	var result: AABB = AABB(faces[0], Vector3.ZERO)
	for point: Vector3 in faces: result = result.expand(point)
	return result

func _position_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x / WELD), roundi(point.y / WELD), roundi(point.z / WELD)]

## 层间接头重叠量取生成器实际常量，不写死数字；超2mm厚会变成可见凹槽，单独设上限。
func _joint_inset(_inventory: Dictionary) -> float:
	var inset: float = float(ShellGeometry.INSET)
	check(inset > 0.0 and inset <= 0.002, "层间接头重叠量在0..2mm", str(inset))
	return inset

func _structural(id: String) -> bool:
	if id.begins_with("wall_weathering_"): return false
	return id.begins_with("wall_") or id.begins_with("slab_") or id.begins_with("roof_") or id.begins_with("pillar_") or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_")

func _floor_value(recipe: Dictionary, floor: int, field: String) -> float:
	var override: Dictionary = recipe.floor_overrides.get(str(floor), {})
	return float(override.get(field, recipe[field]))

func _height(recipe: Dictionary) -> float:
	var result: float = 0.0
	for floor: int in int(recipe.floors): result += _floor_value(recipe, floor, "floor_height")
	return result

func _mapped(point: Vector3, recipe: Dictionary) -> Vector3:
	var scale: float = 1.0 - float(recipe.taper) * clampf(point.y / _height(recipe), 0.0, 1.0)
	return Vector3(point.x * scale, point.y, point.z * scale)

func _slot_map(slots: Array) -> Dictionary:
	var result: Dictionary = {}
	for slot: Dictionary in slots: result[str(slot.id)] = slot
	return result

func _slot_signature(slots: Array) -> String:
	return Catalog.fingerprint(_slot_map(slots))

func _vector(value: Array) -> Vector3:
	if value.size() != 3: return Vector3(INF, INF, INF)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = _json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_json_value(item))
		return result
	if value is Vector3: return _xyz(value)
	if value is Vector2: return [value.x, value.y]
	if value is float and not is_finite(value): return str(value)
	if value == null or value is String or value is bool or value is int or value is float: return value
	return str(value)

func _parse_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}

func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return _parse_dictionary(parsed)

func _finish() -> void:
	_check_shared_materials_unchanged("全部shell验收结束")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	check(directory_error == OK, "报告输出目录可用", error_string(directory_error))
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "JSON报告可写", error_string(FileAccess.get_open_error()))
	if file != null:
		check(report.fixtures.size() == 8 and not str(report.saved_scene).is_empty(), "报告包含全部fixture与实际saved_scene")
		report["checks"] = checks
		report["failures"] = failures.duplicate()
		report["failure_count"] = failures.size()
		file.store_string(JSON.stringify(_json_value(report), "\t"))
		var write_error: Error = file.get_error()
		file.close()
		if write_error != OK: check(false, "JSON报告写入成功", error_string(write_error))
	print("[workshop-shell] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
