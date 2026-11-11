@tool
extends SceneTree
## 架构增量专项QA；只读实际生成root、Mesh和ConcavePolygonShape3D，不读取quality代替几何证据。

const Recipe = preload("res://src/workshop/recipe.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const ShellGenerator = preload("res://src/workshop/shell_generator.gd")
const ShellGeometry = preload("res://src/workshop/shell_geometry.gd")
const Session = preload("res://src/workshop/session.gd")
const Store = preload("res://src/workshop/store.gd")

const REPORT_PATH: String = "res://outputs/workshop_architecture_report.json"
const WELD: float = 0.00001
const EPS: float = 0.0001
const SAMPLE_PATHS: Array[String] = [
	"res://data/workshop/samples/workshop_sample_001.recipe.json",
	"res://data/workshop/samples/workshop_sample_002.recipe.json"
]

var checks: int = 0
var failures: Array[String] = []
var report: Dictionary = {
	"suite": "workshop-architecture",
	"fixtures": {},
	"invalid_cases": {},
	"legacy_samples": {},
	"store": {},
	"visual_acceptance": "未执行；本专项只报告实际mesh/root与实际凹碰撞"
}

func _init() -> void:
	call_deferred("run")

func check(value: bool, meaning: String, detail: String = "") -> void:
	checks += 1
	if not value:
		var message: String = meaning + ("：" + detail if not detail.is_empty() else "")
		failures.append(message)
		printerr("FAIL [workshop-architecture] ", message)

func run() -> void:
	var catalog: Dictionary = Catalog.definitions()
	check(not catalog.is_empty() and Catalog.validate(catalog).is_empty(), "组件目录有效")
	_test_recipe_compatibility(catalog)
	_test_config_precedence()
	_test_legacy_samples(catalog)
	_test_noarchitecture_shell_equivalence(catalog)

	var base: Dictionary = _recipe("architecture_rectangle", "rectangle", 12.0, 9.0, 3)
	_test_fixture("rectangle_default_arch_none", base, catalog)
	_test_shape("l_12x12_f2_wing_42_58", base, catalog, "l", 12.0, 12.0, 2, Vector2(0.42, 0.58), Vector2(3.0, 3.0))
	_test_shape("t_12x12_f2_wing_42_58", base, catalog, "t", 12.0, 12.0, 2, Vector2(0.42, 0.58), Vector2(4.0, 3.0))
	_test_shape("u_15x12_f3_wing_42_58", base, catalog, "u", 15.0, 12.0, 3, Vector2(0.42, 0.58), Vector2(0.0, 3.0))
	_test_setback(base, catalog)
	_test_mixed_roof(base, catalog)
	_test_windows(base, catalog)
	_test_invalid_cases(base, catalog)
	_test_session_atomic(base, catalog)
	_test_store(base, catalog)
	await process_frame
	_finish()

func _recipe(building_id: String, shape: String, width: float, depth: float, floors: int) -> Dictionary:
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe["building_id"] = building_id
	recipe["shape"] = shape
	recipe["width"] = width
	recipe["depth"] = depth
	recipe["floors"] = floors
	recipe["taper"] = 0.0
	recipe["vegetation_density"] = 0.0
	recipe["damage"] = 0.0
	return recipe

func _test_recipe_compatibility(catalog: Dictionary) -> void:
	var defaults: Dictionary = Recipe.defaults()
	var default_fingerprint: String = Recipe.fingerprint(defaults)
	check(not defaults.has("architecture"), "Recipe.defaults不注入architecture")
	check(Recipe.fingerprint(Recipe.normalized(defaults)) == default_fingerprint, "Recipe.defaults fingerprint不因架构默认值变化")
	check(Recipe.validate(defaults, catalog).is_empty(), "旧Recipe.defaults仍可验证")
	var authoring: Dictionary = Recipe.authoring_defaults()
	var authoring_architecture: Dictionary = authoring.get("architecture", {}) as Dictionary
	check(authoring.has("architecture") and Config.validate(authoring_architecture, int(authoring.floors)).is_empty(), "authoring_defaults具有有效architecture增量", str(authoring_architecture))
	check(bool((authoring_architecture.get("window", {}) as Dictionary).get("sill_enabled", false)) and str((authoring_architecture.get("roof", {}) as Dictionary).get("mode", "")) == "parapet", "authoring默认含窗台板与女儿墙")
	check(str(authoring.get("construction_mode", "")) == "shell_v2", "authoring_defaults使用shell_v2")

func _test_config_precedence() -> void:
	var recipe: Dictionary = _recipe("config_precedence", "rectangle", 12.0, 9.0, 3)
	var architecture: Dictionary = Config.defaults()
	architecture["window"] = {"type": "awning", "open_angle": 25.0, "frame_depth": 0.16}
	architecture["floor_windows"] = {"1": {"height": 1.7, "sill": 1.1}}
	architecture["facade_windows"] = {"front": {"type": "casement_left", "open_angle": 35.0, "width": 1.25}}
	architecture["window_overrides"] = {"opening_front_0_2": {"enabled": false, "height": 1.55}}
	recipe["architecture"] = architecture
	var settings: Dictionary = Config.window_settings(recipe, 0, "front", "opening_front_0_2")
	check(str(settings.get("type", "")) == "casement_left", "Config.window_settings按global到floor到facade到single覆盖type")
	check(float(settings.get("open_angle", -1.0)) == 35.0, "Config.window_settings保留facade open_angle覆盖")
	check(float(settings.get("frame_depth", -1.0)) == 0.16, "Config.window_settings保留global frame_depth")
	check(float(settings.get("height", -1.0)) == 1.55 and not bool(settings.get("enabled", true)), "Config.window_settings最后应用single覆盖")
	var floor_settings: Dictionary = Config.window_settings(recipe, 1, "front", "opening_front_1_0")
	check(float(floor_settings.get("height", -1.0)) == 1.7 and float(floor_settings.get("sill", -1.0)) == 1.1, "Config.window_settings楼层覆盖位于立面覆盖之前")
	check(str(Config.window_settings(recipe, 0, "back", "opening_back_0_0").get("type", "")) == "awning", "Config.window_settings未命中立面时使用global")

func _test_noarchitecture_shell_equivalence(catalog: Dictionary) -> void:
	var authoring: Dictionary = _recipe("noarchitecture_shell", "rectangle", 12.0, 9.0, 3)
	var without_architecture: Dictionary = authoring.duplicate(true)
	without_architecture.erase("architecture")
	var explicit_none: Dictionary = authoring.duplicate(true)
	explicit_none["architecture"] = Config.defaults()
	var implicit: Dictionary = _adopt_build_root(Generator.build(without_architecture, catalog))
	var explicit: Dictionary = _adopt_build_root(Generator.build(explicit_none, catalog))
	var implicit_root: Node3D = implicit.get("root") as Node3D
	var explicit_root: Node3D = explicit.get("root") as Node3D
	check(bool(implicit.get("ok", false)) and bool(explicit.get("ok", false)) and implicit_root != null and explicit_root != null, "无architecture与显式none shell均生成", str(implicit.get("reason", explicit.get("reason", ""))))
	if implicit_root != null and explicit_root != null:
		check(_structural_signature(implicit_root) == _structural_signature(explicit_root), "无architecture shell结构geometry与显式none保持一致")
		check(_parts_have_no_architecture_accessory(_inventory(implicit_root).parts), "无architecture shell不生成新窗扇/窗沿/屋顶附件")
	_free_build_root(implicit)
	_free_build_root(explicit)

func _parts_have_no_architecture_accessory(parts: Dictionary) -> bool:
	for id: String in parts:
		if id.begins_with("sash_") or id.begins_with("sill_") or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_"):
			return false
	return true

func _floor_base(recipe: Dictionary, floor: int) -> float:
	var base: float = 0.0
	for index: int in floor:
		var override: Dictionary = recipe.get("floor_overrides", {}).get(str(index), {})
		base += float(override.get("floor_height", recipe.get("floor_height", 0.0)))
	return base

func _test_legacy_samples(catalog: Dictionary) -> void:
	var defaults: Dictionary = Recipe.defaults()
	for path: String in SAMPLE_PATHS:
		var source_hash: String = FileAccess.get_sha256(path)
		var sample: Dictionary = _read_json(path)
		check(not sample.is_empty(), "旧sample可读取", path)
		if sample.is_empty():
			continue
		check(not sample.has("architecture"), "旧sample没有被写入architecture", path)
		var implicit: Dictionary = _adopt_build_root(Generator.build(sample, catalog))
		var explicit_recipe: Dictionary = sample.duplicate(true)
		explicit_recipe["construction_mode"] = "modular_v1"
		var explicit: Dictionary = _adopt_build_root(Generator.build(explicit_recipe, catalog))
		var implicit_root: Node3D = implicit.get("root") as Node3D
		var explicit_root: Node3D = explicit.get("root") as Node3D
		check(bool(implicit.get("ok", false)) and bool(explicit.get("ok", false)) and implicit_root != null and explicit_root != null, "旧sample隐式/显式legacy均可生成", path)
		if implicit_root != null and explicit_root != null:
			check(_root_signature(implicit_root) == _root_signature(explicit_root), "旧sample隐式/显式legacy实际mesh不变", path)
			check(JSON.stringify(implicit.get("slots", [])) == JSON.stringify(explicit.get("slots", [])), "旧sample隐式/显式legacy槽位不变", path)
			check(str(implicit_root.get_meta("generator_version", "")) == Generator.GENERATOR_VERSION, "旧sample仍由legacy generator生成", path)
		_free_build_root(implicit)
		_free_build_root(explicit)
		check(FileAccess.get_sha256(path) == source_hash, "旧sample文件未改写", path)
	check(not defaults.has("architecture"), "legacy兼容检查结束后defaults仍无architecture")

func _test_fixture(label: String, recipe: Dictionary, catalog: Dictionary) -> Dictionary:
	var result: Dictionary = _adopt_build_root(Generator.build(recipe, catalog))
	var root: Node3D = result.get("root") as Node3D
	check(bool(result.get("ok", false)) and root != null, label + "生成实际root", str(result.get("reason", "")))
	if root == null:
		report.fixtures[label] = {"ok": false, "reason": str(result.get("reason", ""))}
		return result
	var inventory: Dictionary = _inventory(root)
	var topology: Dictionary = _audit_parts(inventory.parts)
	var actual_collisions: bool = _collision_matches_visual(inventory)
	check(str(root.get_meta("generator_version", "")) == ShellGenerator.GENERATOR_VERSION, label + " root metadata为当前shell生成器")
	check(str(root.get_meta("construction_mode", "")) == "shell_v2", label + " root metadata construction_mode正确")
	check(root.transform.is_equal_approx(Transform3D.IDENTITY), label + " root变换恒等")
	check(int(inventory.visual_meshes) > 0 and int(inventory.triangles) > 0, label + "实际Mesh存在面")
	check(_all_parts_closed_oriented(topology), label + "所有实际新part闭合定向且nonmanifold为0", str(topology.get("bad_parts", {})))
	check(actual_collisions, label + "实际Concave碰撞与结构视觉part一一对应")
	check(int(inventory.invalid_collision_shapes) == 0, label + "实际碰撞全部是ConcavePolygonShape3D")
	report.fixtures[label] = {
		"ok": true,
		"visual_meshes": inventory.visual_meshes,
		"triangles": inventory.triangles,
		"collision_shapes": inventory.collision_shapes,
		"parts": _sorted_strings(inventory.parts.keys()),
		"topology": topology,
		"root_metadata": {
			"generator_version": root.get_meta("generator_version", ""),
			"construction_mode": root.get_meta("construction_mode", ""),
			"recipe_fingerprint": root.get_meta("recipe_fingerprint", "")
		}
	}
	return result

func _test_shape(label: String, base: Dictionary, catalog: Dictionary, shape: String, width: float, depth: float, floors: int, wing: Vector2, void_point: Vector2) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = label
	recipe["shape"] = shape
	recipe["width"] = width
	recipe["depth"] = depth
	recipe["floors"] = floors
	recipe["architecture"]["plan"]["wing_x"] = wing.x
	recipe["architecture"]["plan"]["wing_z"] = wing.y
	var result: Dictionary = _test_fixture(label, recipe, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root)
	var height: float = _height(recipe)
	var void_hits: int = _ray_hits(_all_faces(inventory.parts), Vector3(void_point.x, height + 2.0, void_point.y), Vector3(void_point.x, -1.0, void_point.y))
	check(void_hits == 0, label + " roof top ray不封L/T/U内部void", str(void_hits))
	report.fixtures[label]["void_top_ray_hits"] = void_hits
	_free_build_root(result)

func _test_setback(base: Dictionary, catalog: Dictionary) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = "rectangle_setback_f3_start2_step035"
	recipe["architecture"]["plan"]["setback_start"] = 2
	recipe["architecture"]["plan"]["setback_step"] = 0.35
	var result: Dictionary = _test_fixture("rectangle_setback_f3_start2_step035", recipe, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root)
	var wall_1: AABB = _bounds(inventory.parts.get("wall_shell_1", PackedVector3Array()))
	var wall_2: AABB = _bounds(inventory.parts.get("wall_shell_2", PackedVector3Array()))
	check(wall_2.size.x < wall_1.size.x - EPS and wall_2.size.z < wall_1.size.z - EPS, "setback floor2实际wall_shell bounds变窄")
	check(_has_roof_surface(result.get("roof_surfaces", []), "terrace_floor_2"), "setback实际roof_surfaces保留terrace_floor_2 top")
	var slab_2: PackedVector3Array = inventory.parts.get("slab_2", PackedVector3Array())
	var floor_2_top: float = _floor_base(recipe, 2)
	var slab_top_hits: int = _ray_hits(slab_2, Vector3(0.0, floor_2_top + 1.0, 0.0), Vector3(0.0, floor_2_top - 1.0, 0.0))
	check(slab_top_hits > 0, "setback slab2实际mesh存在terrace top")
	var no_setback: Dictionary = base.duplicate(true)
	no_setback["building_id"] = "rectangle_no_setback_roof_edges"
	no_setback["architecture"]["roof"]["mode"] = "parapet"
	var no_setback_result: Dictionary = _adopt_build_root(Generator.build(no_setback, catalog))
	var no_setback_root: Node3D = no_setback_result.get("root") as Node3D
	check(no_setback_root != null and bool(no_setback_result.get("ok", false)), "无退台屋顶边界fixture生成", str(no_setback_result.get("reason", "")))
	if no_setback_root != null:
		var no_setback_parts: Dictionary = _inventory(no_setback_root).parts
		check(not _has_id_containing(no_setback_parts, "terrace_floor_0"), "无退台时slab0没有roof edge part")
	_free_build_root(no_setback_result)
	report.fixtures["rectangle_setback_f3_start2_step035"]["wall_shell_1_bounds"] = _aabb_json(wall_1)
	report.fixtures["rectangle_setback_f3_start2_step035"]["wall_shell_2_bounds"] = _aabb_json(wall_2)
	report.fixtures["rectangle_setback_f3_start2_step035"]["slab2_top_ray_hits"] = slab_top_hits
	_free_build_root(result)

func _test_mixed_roof(base: Dictionary, catalog: Dictionary) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = "rectangle_roof_mixed"
	recipe["architecture"]["roof"]["mode"] = "mixed"
	var result: Dictionary = _test_fixture("rectangle_roof_mixed", recipe, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root)
	check(_has_id_prefix(inventory.parts, "parapet_"), "roof_main mixed实际存在parapet part")
	check(_has_id_prefix(inventory.parts, "roofcap_"), "roof_main mixed实际存在roofcap part")
	check(_has_id_prefix(inventory.parts, "railing_"), "roof_main mixed实际存在railing part")
	check(_collision_matches_visual(inventory), "roof_main mixed每个附属结构均有实际Concave碰撞")
	var gap_recipe: Dictionary = recipe.duplicate(true)
	gap_recipe["building_id"] = "rectangle_roof_mixed_edge_gap"
	gap_recipe["architecture"]["roof"]["edge_overrides"] = {"edge_0": {"gap_center": 0.5, "gap_width": 2.0}}
	var gap_result: Dictionary = _adopt_build_root(Generator.build(gap_recipe, catalog))
	var gap_root: Node3D = gap_result.get("root") as Node3D
	check(gap_root != null and bool(gap_result.get("ok", false)), "roof edge gap fixture生成", str(gap_result.get("reason", "")))
	if gap_root != null:
		var gap_inventory: Dictionary = _inventory(gap_root)
		var fragments: Array[String] = []
		for id: String in gap_inventory.parts:
			if id.begins_with("parapet_roof_main_0_") or id.begins_with("roofcap_roof_main_0_") or id.begins_with("railing_roof_main_0_"):
				fragments.append(id)
		check(fragments.size() >= 6, "roof edge gap实际生成两端fragment并保持三类边件")
		var gap_point: Vector2 = Vector2(0.0, -float(gap_recipe["depth"]) * 0.5 - 0.14)
		var end_point: Vector2 = Vector2(-float(gap_recipe["width"]) * 0.25, -float(gap_recipe["depth"]) * 0.5 - 0.14)
		var gap_ray: int = _ray_hits(_all_faces(gap_inventory.parts), Vector3(gap_point.x, _height(gap_recipe) + 0.25, gap_point.y - 1.0), Vector3(gap_point.x, _height(gap_recipe) + 0.25, gap_point.y + 1.0))
		var end_ray: int = _ray_hits(_all_faces(gap_inventory.parts), Vector3(end_point.x, _height(gap_recipe) + 0.25, end_point.y - 1.0), Vector3(end_point.x, _height(gap_recipe) + 0.25, end_point.y + 1.0))
		check(gap_ray == 0 and end_ray > 0, "roof edge gap中段无barrier且fragment端部闭合")
		report.fixtures["rectangle_roof_mixed"]["edge_gap"] = {"fragment_parts": fragments, "gap_ray_hits": gap_ray, "end_ray_hits": end_ray}
	_free_build_root(gap_result)
	report.fixtures["rectangle_roof_mixed"]["roof_parts"] = _filter_roof_parts(inventory.parts)
	_free_build_root(result)

func _test_windows(base: Dictionary, catalog: Dictionary) -> void:
	var windows: Dictionary = base.duplicate(true)
	windows["building_id"] = "windows_fixed_casement_awning_sill"
	windows["architecture"]["window"] = {
		"type": "fixed", "open_angle": 0.0, "sill_enabled": true,
		"sill_projection": 0.2, "sill_thickness": 0.1, "sill_extension": 0.08
	}
	windows["architecture"]["facade_windows"] = {
		"left": {"type": "casement_left", "open_angle": 35.0},
		"right": {"type": "awning", "open_angle": 25.0}
	}
	var result: Dictionary = _test_fixture("windows_fixed_casement_awning_sill", windows, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root)
	var fixed_ok: bool = false
	var casement_ok: bool = false
	var awning_ok: bool = false
	var sill_ok: bool = false
	for opening: Dictionary in result.get("openings", []):
		if str(opening.get("type", "")) != "window":
			continue
		var opening_id: String = str(opening.get("id", ""))
		var suffix: String = opening_id.trim_prefix("opening_")
		var settings: Dictionary = opening.get("settings", {})
		var frame_id := "frame_" + suffix
		var glass_id := "glass_" + suffix
		fixed_ok = fixed_ok or (str(settings.get("type", "")) == "fixed" and inventory.parts.has(frame_id) and inventory.parts.has(glass_id))
		casement_ok = casement_ok or (str(settings.get("type", "")) == "casement_left" and float(settings.get("open_angle", -1.0)) == 35.0 and inventory.parts.has("sash_" + suffix))
		awning_ok = awning_ok or (str(settings.get("type", "")) == "awning" and float(settings.get("open_angle", -1.0)) == 25.0 and inventory.parts.has("sash_" + suffix))
		sill_ok = sill_ok or (bool(settings.get("sill_enabled", false)) and inventory.parts.has("sill_" + suffix))	
	check(fixed_ok, "fixed窗实际frame与glass存在")
	check(casement_ok, "casement_left 35度实际sash存在")
	check(awning_ok, "awning 25度实际sash存在")
	check(sill_ok, "固定窗实际sill存在")
	_free_build_root(result)

	var disabled: Dictionary = windows.duplicate(true)
	disabled["building_id"] = "windows_single_disabled"
	disabled["architecture"]["window_overrides"] = {"opening_front_0_2": {"enabled": false}}
	var disabled_result: Dictionary = _adopt_build_root(Generator.build(disabled, catalog))
	var disabled_root: Node3D = disabled_result.get("root") as Node3D
	check(disabled_root != null and bool(disabled_result.get("ok", false)), "单窗enabled=false生成", str(disabled_result.get("reason", "")))
	if disabled_root != null:
		var disabled_inventory: Dictionary = _inventory(disabled_root)
		var disabled_suffix := "front_0_2"
		check(not disabled_inventory.parts.has("glass_" + disabled_suffix) and not disabled_inventory.parts.has("frame_" + disabled_suffix) and not disabled_inventory.parts.has("sash_" + disabled_suffix) and not disabled_inventory.parts.has("sill_" + disabled_suffix), "enabled=false移除实际glass/frame/sash/sill")
		var disabled_wall: PackedVector3Array = disabled_inventory.parts.get("wall_shell_0", PackedVector3Array())
		var disabled_target: Dictionary = {}
		for opening: Dictionary in result.get("openings", []):
			if str(opening.get("id", "")) == "opening_front_0_2":
				disabled_target = opening
				break
		var target_center: Vector3 = disabled_target.get("center", Vector3(1.5, 1.9, -4.5))
		var target_outward: Vector3 = disabled_target.get("outward", Vector3(0.0, 0.0, -1.0))
		var hit: int = _ray_hits(disabled_wall, target_center + target_outward, target_center - target_outward)
		check(hit > 0, "enabled=false洞口位置实际wall ray命中")
		var enabled_ids: Array[String] = _window_ids(result.get("openings", []))
		var disabled_ids: Array[String] = _window_ids(disabled_result.get("openings", []))
		check(not disabled_ids.has("opening_front_0_2"), "enabled=false不伪造已禁用opening记录")
		for id: String in enabled_ids:
			if id != "opening_front_0_2":
				check(disabled_ids.has(id), "enabled=false保持其他window ordinal identity", id)
		report.fixtures["windows_single_disabled"] = {"ok": true, "disabled_part_ids": ["frame_front_0_2", "glass_front_0_2", "sash_front_0_2", "sill_front_0_2"], "window_ids": disabled_ids, "disabled_wall_ray_hits": hit}
	_free_build_root(disabled_result)

	var changed: Dictionary = windows.duplicate(true)
	changed["building_id"] = "windows_depth_glass_sill_dimensions"
	changed["architecture"]["window"]["frame_depth"] = 0.18
	changed["architecture"]["window"]["glass_thickness"] = 0.03
	changed["architecture"]["window"]["sill_projection"] = 0.2
	var baseline_result: Dictionary = _adopt_build_root(Generator.build(windows, catalog))
	var changed_result: Dictionary = _adopt_build_root(Generator.build(changed, catalog))
	var baseline_root: Node3D = baseline_result.get("root") as Node3D
	var changed_root: Node3D = changed_result.get("root") as Node3D
	check(baseline_root != null and changed_root != null and bool(baseline_result.get("ok", false)) and bool(changed_result.get("ok", false)), "窗frame_depth/glass/sill尺寸对照均生成")
	if baseline_root != null and changed_root != null:
		var before_inventory: Dictionary = _inventory(baseline_root)
		var after_inventory: Dictionary = _inventory(changed_root)
		var suffix: String = _first_window_suffix(baseline_result.get("openings", []), "fixed")
		var frame_changed: bool = _bounds_changed(before_inventory.parts.get("frame_" + suffix, PackedVector3Array()), after_inventory.parts.get("frame_" + suffix, PackedVector3Array()))
		var glass_changed: bool = _bounds_changed(before_inventory.parts.get("glass_" + suffix, PackedVector3Array()), after_inventory.parts.get("glass_" + suffix, PackedVector3Array()))
		check(frame_changed and glass_changed, "frame_depth .18与glass_thickness .03改变实际AABB")
		check(after_inventory.parts.has("sill_" + suffix), "sill_projection .2生成实际sill part")
	_free_build_root(baseline_result)
	_free_build_root(changed_result)

func _test_invalid_cases(base: Dictionary, catalog: Dictionary) -> void:
	var invalids: Array[Dictionary] = []
	var fixed_angle: Dictionary = base.duplicate(true)
	fixed_angle.building_id = "invalid_fixed_angle"
	fixed_angle.architecture.window.open_angle = 35.0
	invalids.append({"id": "fixed_angle", "recipe": fixed_angle})
	var envelope: Dictionary = base.duplicate(true)
	envelope.building_id = "invalid_open_envelope"
	envelope.architecture.window.type = "casement_left"
	envelope.architecture.window.open_angle = 80.0
	envelope.architecture.window.width = 2.99
	envelope.architecture.window.frame_depth = 0.5
	envelope.architecture.window.recess = 0.27
	envelope.architecture.window.sill = 1.0
	envelope.architecture.window.height = 3.5
	envelope.wall_thickness = 0.6
	invalids.append({"id": "open_envelope_over_bay", "recipe": envelope})
	var roof_mode: Dictionary = base.duplicate(true)
	roof_mode.building_id = "invalid_roof_mode"
	roof_mode.architecture.roof.mode = "balcony"
	invalids.append({"id": "roof_invalid_mode", "recipe": roof_mode})
	var roof_height: Dictionary = base.duplicate(true)
	roof_height.building_id = "invalid_roof_height"
	roof_height.architecture.roof.height = 0.3
	invalids.append({"id": "roof_invalid_bounds", "recipe": roof_height})
	var u_wing: Dictionary = base.duplicate(true)
	u_wing.building_id = "invalid_u_wing"
	u_wing.shape = "u"
	u_wing.architecture.plan.wing_x = 0.2
	invalids.append({"id": "u_invalid_wing", "recipe": u_wing})
	var old_t: Dictionary = base.duplicate(true)
	old_t.building_id = "invalid_t_modular"
	old_t.shape = "t"
	old_t.construction_mode = "modular_v1"
	invalids.append({"id": "t_old_modular", "recipe": old_t})
	for entry: Dictionary in invalids:
		var invalid_recipe: Dictionary = entry.recipe
		var reason: String = Recipe.validate(invalid_recipe, catalog)
		check(not reason.is_empty(), str(entry.id) + "被Recipe/architecture边界拒绝", reason)
		report.invalid_cases[str(entry.id)] = {"rejected": not reason.is_empty(), "reason": reason}

func _test_session_atomic(base: Dictionary, catalog: Dictionary) -> void:
	var session: RefCounted = Session.new(catalog)
	var accepted: Dictionary = session.call("accept_loaded", base, catalog)
	check(bool(accepted.get("ok", false)), "session装入shell architecture recipe", str(accepted.get("reason", "")))
	if not bool(accepted.get("ok", false)):
		return
	var built: Dictionary = _adopt_build_root(session.call("build"))
	var root: Node3D = built.get("root") as Node3D
	check(root != null and bool(built.get("ok", false)), "session last_build.root实际生成", str(built.get("reason", "")))
	if root == null:
		return
	var before_snapshot: String = JSON.stringify(session.call("snapshot"))
	var before_root: Node = session.get("_last_build").get("root") as Node
	var invalid_architecture: Dictionary = base.architecture.duplicate(true)
	invalid_architecture.roof.mode = "invalid_session_mode"
	var rejected: Dictionary = session.call("apply_patch", {"architecture": invalid_architecture})
	check(not bool(rejected.get("ok", false)) and not str(rejected.get("reason", "")).is_empty(), "session架构patch在commit前原子拒绝")
	check(JSON.stringify(session.call("snapshot")) == before_snapshot, "session拒绝patch保持snapshot")
	check(session.get("_last_build").get("root") == before_root and session.get("_last_build").get("root") == root, "session拒绝patch保持lastbuild root身份")
	report["session_atomic"] = {"rejected": not bool(rejected.get("ok", false)), "reason": rejected.get("reason", ""), "root_retained": session.get("_last_build").get("root") == root}
	_free_build_root(built)
	(session.get("_last_build") as Dictionary).clear()

func _test_store(base: Dictionary, catalog: Dictionary) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = "architecture_store_roundtrip"
	recipe["architecture"]["roof"]["mode"] = "mixed"
	recipe["architecture"]["window"]["frame_depth"] = 0.18
	var store: RefCounted = Store.new()
	var base_dir: String = "user://building_workshop/workshop_architecture_suite"
	var exported: Dictionary = store.call("export_revision", recipe, catalog, base_dir)
	check(bool(exported.get("ok", false)), "Store导出shell architecture recipe", str(exported.get("reason", "")))
	if not bool(exported.get("ok", false)):
		return
	var loaded: Dictionary = store.call("load_recipe", str(exported.get("recipe_path", "")))
	check(bool(loaded.get("ok", false)), "Store architecture recipe roundtrip可读取", str(loaded.get("reason", "")))
	if bool(loaded.get("ok", false)):
		var loaded_recipe: Dictionary = loaded.get("recipe", {})
		var exported_recipe: Dictionary = exported.get("recipe", {})
		check(Recipe.fingerprint(loaded_recipe) == Recipe.fingerprint(exported_recipe), "Store roundtrip保持architecture recipe fingerprint")
		var loaded_architecture: Variant = loaded_recipe.get("architecture", null)
		var exported_architecture: Variant = exported_recipe.get("architecture", null)
		var architecture_roundtrip: bool = loaded_recipe.has("architecture") and exported_recipe.has("architecture")
		architecture_roundtrip = architecture_roundtrip and loaded_architecture is Dictionary and exported_architecture is Dictionary
		if architecture_roundtrip:
			architecture_roundtrip = Config.validate(loaded_architecture, int(loaded_recipe.get("floors", 0))).is_empty()
			architecture_roundtrip = architecture_roundtrip and _same_json(loaded_architecture, exported_architecture)
		check(architecture_roundtrip, "Store roundtrip保留有效且数值等价的architecture对象")
	var scene: PackedScene = ResourceLoader.load(str(exported.get("scene_path", "")), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(scene != null, "Store导出场景可重载")
	if scene != null:
		var root: Node3D = scene.instantiate() as Node3D
		root = _adopt_node(root) as Node3D
		check(root != null, "Store导出场景可实例化")
		if root != null:
			check(str(root.get_meta("construction_mode", "")) == "shell_v2", "Store保存root metadata construction_mode正确")
			check(str(root.get_meta("generator_version", "")) == ShellGenerator.GENERATOR_VERSION, "Store保存root metadata generator_version正确")
			check(str(root.get_meta("recipe_fingerprint", "")) == Recipe.fingerprint(exported.get("recipe", {})), "Store保存root metadata recipe_fingerprint正确")
			var saved_inventory: Dictionary = _inventory(root)
			check(_all_parts_closed_oriented(_audit_parts(saved_inventory.parts)), "Store重载root实际parts闭合定向")
			report.store = {"directory": exported.get("directory", ""), "recipe_path": exported.get("recipe_path", ""), "scene_path": exported.get("scene_path", ""), "metadata": {"construction_mode": root.get_meta("construction_mode", ""), "generator_version": root.get_meta("generator_version", ""), "recipe_fingerprint": root.get_meta("recipe_fingerprint", "")}}
		_free_build_root({"root": root})
	scene = null

func _adopt_build_root(result: Dictionary) -> Dictionary:
	var root: Node = result.get("root") as Node
	if root != null:
		result["root"] = _adopt_node(root)
	return result

func _adopt_node(node: Node) -> Node:
	if node != null and node.get_parent() == null:
		get_root().add_child(node)
	return node

func _free_build_root(result: Dictionary) -> void:
	var root: Node = result.get("root") as Node
	if is_instance_valid(root):
		_release_node_resources(root)
		root.free()
	result.clear()

func _release_node_resources(node: Node) -> void:
	for child: Node in node.get_children():
		_release_node_resources(child)
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = mesh_node.mesh
		mesh_node.mesh = null
		mesh_node.material_override = null
		mesh_node.material_overlay = null
		if mesh is ArrayMesh:
			(mesh as ArrayMesh).clear_surfaces()
	elif node is CollisionShape3D:
		(node as CollisionShape3D).shape = null

func _inventory(root: Node3D) -> Dictionary:
	var result: Dictionary = {"parts": {}, "collisions": {}, "visual_meshes": 0, "collision_shapes": 0, "invalid_collision_shapes": 0, "triangles": 0}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node.mesh != null:
				var id: String = str(node.get_meta("slot_id", node.name))
				var faces: PackedVector3Array = _transformed(mesh_node.mesh.get_faces(), _relative(mesh_node, root))
				var current: PackedVector3Array = result.parts.get(id, PackedVector3Array())
				current.append_array(faces)
				result.parts[id] = current
				result.visual_meshes += 1
				result.triangles += int(faces.size() / 3)
		if node is CollisionShape3D:
			result.collision_shapes += 1
			var shape_node: CollisionShape3D = node as CollisionShape3D
			if shape_node.disabled or not shape_node.shape is ConcavePolygonShape3D:
				result.invalid_collision_shapes += 1
			else:
				var collision_faces: PackedVector3Array = _transformed((shape_node.shape as ConcavePolygonShape3D).get_faces(), _relative(shape_node, root))
				var collision_id: String = str(node.get_meta("slot_id", node.get_parent().get_meta("slot_id", node.name)))
				var existing: PackedVector3Array = result.collisions.get(collision_id, PackedVector3Array())
				existing.append_array(collision_faces)
				result.collisions[collision_id] = existing
		for child: Node in node.get_children():
			stack.append(child)
	return result

func _audit_parts(parts: Dictionary) -> Dictionary:
	var result: Dictionary = {"part_count": parts.size(), "bad_parts": {}, "topology": {}}
	for id: String in parts:
		var audit: Dictionary = _topology(parts[id])
		result.topology[id] = audit
		if not bool(audit.get("closed", false)) or not bool(audit.get("oriented", false)) or int(audit.get("nonmanifold_edges", -1)) != 0:
			result.bad_parts[id] = audit
	return result

func _all_parts_closed_oriented(audit: Dictionary) -> bool:
	return int(audit.get("part_count", 0)) > 0 and (audit.get("bad_parts", {}) as Dictionary).is_empty()

func _topology(faces: PackedVector3Array) -> Dictionary:
	var indices := PackedInt32Array()
	for index: int in faces.size():
		indices.append(index)
	return ShellGeometry._topology({"v": faces, "i": indices})

func _collision_matches_visual(inventory: Dictionary) -> bool:
	var structural_count: int = 0
	for id: String in inventory.parts:
		if not _is_collidable_part(id):
			continue
		structural_count += 1
		if not inventory.collisions.has(id):
			return false
		if int((inventory.parts[id] as PackedVector3Array).size()) != int((inventory.collisions[id] as PackedVector3Array).size()):
			return false
	for id: String in inventory.collisions:
		if not _is_collidable_part(id):
			return false
	return structural_count == int(inventory.collisions.size())

func _is_collidable_part(id: String) -> bool:
	return id.begins_with("wall_shell_") or id.begins_with("slab_") or id == "roof_main" or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_")

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node3D = node
	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

func _transformed(faces: PackedVector3Array, transform: Transform3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(faces.size())
	for index: int in faces.size():
		result[index] = transform * faces[index]
	return result

func _all_faces(parts: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	for faces: PackedVector3Array in parts.values():
		result.append_array(faces)
	return result

func _ray_hits(faces: PackedVector3Array, from: Vector3, to: Vector3) -> int:
	var direction: Vector3 = to - from
	var hits: int = 0
	for start: int in range(0, faces.size() - 2, 3):
		var a: Vector3 = faces[start]
		var edge_1: Vector3 = faces[start + 1] - a
		var edge_2: Vector3 = faces[start + 2] - a
		var cross: Vector3 = direction.cross(edge_2)
		var determinant: float = edge_1.dot(cross)
		if absf(determinant) < 0.000000001:
			continue
		var inverse: float = 1.0 / determinant
		var offset: Vector3 = from - a
		var u: float = offset.dot(cross) * inverse
		if u < -EPS or u > 1.0 + EPS:
			continue
		var q: Vector3 = offset.cross(edge_1)
		var v: float = direction.dot(q) * inverse
		if v < -EPS or u + v > 1.0 + EPS:
			continue
		var t: float = edge_2.dot(q) * inverse
		if t >= 0.0 and t <= 1.0:
			hits += 1
	return hits

func _bounds(faces: PackedVector3Array) -> AABB:
	if faces.is_empty():
		return AABB()
	var result: AABB = AABB(faces[0], Vector3.ZERO)
	for point: Vector3 in faces:
		result = result.expand(point)
	return result

func _bounds_changed(before: PackedVector3Array, after: PackedVector3Array) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	var a: AABB = _bounds(before)
	var b: AABB = _bounds(after)
	return a.position.distance_to(b.position) > EPS or a.size.distance_to(b.size) > EPS

func _root_signature(root: Node3D) -> String:
	var inventory: Dictionary = _inventory(root)
	var ids: Array[String] = _sorted_strings(inventory.parts.keys())
	var data: Array = []
	for id: String in ids:
		data.append([id, inventory.parts[id]])
	return var_to_bytes(data).hex_encode().sha256_text()

func _structural_signature(root: Node3D) -> String:
	var inventory: Dictionary = _inventory(root)
	var ids: Array[String] = []
	for id: String in inventory.parts:
		if _is_collidable_part(id):
			ids.append(id)
	ids.sort()
	var data: Array = []
	for id: String in ids:
		data.append([id, inventory.parts[id]])
	return var_to_bytes(data).hex_encode().sha256_text()

func _window_ids(openings: Array) -> Array[String]:
	var result: Array[String] = []
	for opening: Dictionary in openings:
		if str(opening.get("type", "")) == "window":
			result.append(str(opening.get("id", "")))
	result.sort()
	return result

func _first_window_suffix(openings: Array, window_type: String) -> String:
	for opening: Dictionary in openings:
		if str(opening.get("type", "")) == "window" and str(opening.get("window_type", "")) == window_type:
			return str(opening.get("id", "")).trim_prefix("opening_")
	return ""

func _has_roof_surface(surfaces: Array, surface_id: String) -> bool:
	for surface: Dictionary in surfaces:
		if str(surface.get("id", "")) == surface_id:
			return true
	return false

func _has_id_prefix(parts: Dictionary, prefix: String) -> bool:
	for id: String in parts:
		if id.begins_with(prefix):
			return true
	return false

func _has_id_containing(parts: Dictionary, text: String) -> bool:
	for id: String in parts:
		if id.contains(text):
			return true
	return false

func _filter_roof_parts(parts: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id: String in parts:
		if id == "roof_main" or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_"):
			result.append(id)
	result.sort()
	return result

func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result

func _height(recipe: Dictionary) -> float:
	var total: float = 0.0
	for floor: int in int(recipe.get("floors", 0)):
		var override: Dictionary = recipe.get("floor_overrides", {}).get(str(floor), {})
		total += float(override.get("floor_height", recipe.get("floor_height", 0.0)))
	return total

func _aabb_json(box: AABB) -> Dictionary:
	return {"position": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]}

func _same_json(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		var left: Dictionary = a
		var right: Dictionary = b
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_json(left[key], right[key]):
				return false
		return true
	if a is Array and b is Array:
		var left_array: Array = a
		var right_array: Array = b
		if left_array.size() != right_array.size():
			return false
		for index: int in left_array.size():
			if not _same_json(left_array[index], right_array[index]):
				return false
		return true
	return a == b

func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}

func _finish() -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	check(directory_error == OK, "报告目录可用", error_string(directory_error))
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "架构报告可写", error_string(FileAccess.get_open_error()))
	if file != null:
		report["checks"] = checks
		report["failures"] = failures.duplicate()
		report["failure_count"] = failures.size()
		file.store_string(JSON.stringify(report, "\t"))
		var write_error: Error = file.get_error()
		file.close()
		file = null
		if write_error != OK:
			check(false, "架构报告写入成功", error_string(write_error))
	report.clear()
	print("[workshop-architecture] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
