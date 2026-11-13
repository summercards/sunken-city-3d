@tool
extends RefCounted
## 连续外壳的静态装配层；不依赖旧生成器、不挂树、不保存文件。

const Geometry = preload("res://src/workshop/shell_geometry.gd")
const StructureUnion = preload("res://src/workshop/shell_union_geometry.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const MeshBuilder = preload("res://src/workshop/mesh_builder.gd")
const GENERATOR_VERSION := "sea_workshop_structural_union_v3"
const STANDARDS_PATH := "res://data/workshop/standards_v1.json"
const MAX_NODES := 2000
const MAX_TRIANGLES := 180000
const BOUNDS_EPS := 0.0001
const POINT_EPS := 0.00001

static func build(recipe: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "root": null, "slots": [], "stats": {}, "walk_surfaces": [], "water_blockers": [], "warnings": [], "quality": {}, "openings": []}
	if not Recipe._finite_tree(recipe):
		return _fail(result, "配方必须为有限JSON数据")
	var r: Dictionary = Recipe.normalized(recipe)
	if not recipe.has("vegetation_density"): r.vegetation_density = 0.0
	if not recipe.has("taper"): r.taper = 0.02
	var c: Dictionary = catalog.duplicate(true) if not catalog.is_empty() else Catalog.definitions()
	var reason: String = Catalog.validate(c)
	if not reason.is_empty(): return _fail(result, reason)
	reason = _validate_wrapper(r, c)
	if not reason.is_empty(): return _fail(result, reason)
	# 几何层只接收参数组件；替件、整件禁用和植物由本层负责。
	var geometry_recipe: Dictionary = r.duplicate(true)
	for family in ["wall", "slab", "frame", "glass"]:
		var component: String = str(r.component_bindings.get(family, ""))
		if str(c.components[component].kind) == "prefab":
			var fallback: String = _parametric_component(c, family)
			if fallback.is_empty(): return _fail(result, "替件缺少几何母型: " + family)
			geometry_recipe.component_bindings[family] = fallback
	var geometry_overrides: Dictionary = {}
	for id in r.slot_overrides:
		if str(id).begins_with("plant_"): continue
		var override: Dictionary = r.slot_overrides[id]
		if override.has("component_id") and str(c.components[str(override.component_id)].kind) == "parametric":
			geometry_overrides[id] = {"component_id": str(override.component_id)}
	geometry_recipe.slot_overrides = geometry_overrides
	var geometry: Dictionary = Geometry.generate(geometry_recipe, c)
	result.quality = geometry.get("quality", {}).duplicate(true)
	if not bool(geometry.get("ok", false)):
		return _fail(result, str(geometry.get("reason", "几何生成失败")))
	result.openings = geometry.openings.duplicate(true)
	result["roof_surfaces"] = geometry.get("roof_surfaces", []).duplicate(true)
	var plans: Array = []
	var seen: Dictionary = {}
	var budget: Dictionary = {"nodes": 5, "triangles": 0, "visual_meshes": 0, "collision_shapes": 0, "plant_meshes": 0}
	for raw_part in geometry.parts:
		var part: Dictionary = raw_part.duplicate(false)
		var id: String = str(part.id)
		seen[id] = true
		if _disabled(r, id):
			result.warnings.append("整件已禁用，连续外壳完整性不再保证: " + id)
			continue
		var family: String = _shell_part_family(part, id)
		if family.is_empty() or not r.component_bindings.has(family):
			_release_plans(plans)
			return _fail(result, "连续外壳part缺少组件族映射: " + id)
		part.component_id = Geometry._component(r, str(part.kind), id)
		part.kind = family
		part.collidable = bool(part.collidable) and family != "plant" and str(r.spatial_profile) != "scenic_underwater"
		var definition: Dictionary = c.components[str(part.component_id)]
		if str(definition.kind) == "prefab":
			var prepared: Dictionary = _prepare_prefab(part, definition)
			if not bool(prepared.ok):
				_release_plans(plans)
				return _fail(result, str(prepared.reason))
			part = prepared.part
			result.warnings.append("整件prefab替换，不缩放；倒角宽度未测量: " + id)
		else:
			part["instance"] = null
			part["mesh_records"] = [{"mesh": part.mesh, "transform": Transform3D.IDENTITY}]
			part["node_count"] = 1
		plans.append(part)
		_accumulate_budget(budget, part)
		if _over_budget(budget):
			_release_plans(plans)
			return _fail(result, "装配预检超出2000节点或180000三角面预算")
	for id in r.slot_overrides:
		if not str(id).begins_with("plant_") and not seen.has(id):
			result.warnings.append("槽覆盖未匹配实际part: " + str(id))
	var union_result: Dictionary = StructureUnion.combine(plans)
	if not bool(union_result.ok):
		_release_plans(plans)
		return _fail(result, str(union_result.reason))
	var structure: Dictionary = {"id": "structure_union", "kind": "structure", "floor": -1, "facade": "", "component_id": "", "position": Vector3.ZERO, "mesh": union_result.mesh, "mesh_records": [{"mesh": union_result.mesh, "transform": Transform3D.IDENTITY}], "instance": null, "node_count": 1, "collidable": str(r.spatial_profile) != "scenic_underwater", "source_slots": union_result.source_slots}
	var roof_source: Dictionary = _plan_by_id(plans, "roof_main")
	var roof: Dictionary = structure.duplicate(false)
	roof["surface_y"] = snappedf(_part_bounds(roof_source).end.y, 0.0001)
	var anchors: Array = _plant_anchors(roof, r) if float(r.vegetation_density) > 0.0 or not r.locked_vegetation.is_empty() else []
	var plant_result: Dictionary = _prepare_plants(anchors, roof, r, c, budget, result.warnings)
	if not bool(plant_result.ok):
		_release_plans(plans)
		return _fail(result, str(plant_result.reason))
	plans.append_array(plant_result.parts)
	result.quality["structure_union"] = {"backend": union_result.backend, "audit": union_result.audit, "boundary_audit": union_result.boundary_audit, "source_slots": union_result.source_slots, "visible_source_meshes": 0, "acceptance": "geometry_checked_not_visual_acceptance", "internal_surface_verification": "实际faces每面两个内点、0.1mm双侧、三方向源实体射线奇偶多数票；独立专项另行验收", "mesh_quantization_m": 0.0001}
	var root: Node3D = Node3D.new()
	root.name = "WorkshopBuilding_" + str(r.building_id)
	root.set_meta("workshop_building_id", str(r.building_id))
	root.set_meta("asset_id", "SEA-WORKSHOP-" + str(r.building_id).to_upper())
	root.set_meta("spatial_profile", str(r.spatial_profile))
	root.set_meta("generator_version", GENERATOR_VERSION)
	root.set_meta("construction_mode", "shell_v2")
	root.set_meta("recipe_fingerprint", Recipe.fingerprint(r))
	root.set_meta("catalog_fingerprint", Catalog.fingerprint(c))
	root.set_meta("standards_fingerprint", FileAccess.get_sha256(STANDARDS_PATH))
	var visual: Node3D = _branch(root, root, "GeneratedVisual")
	var vegetation: Node3D = _branch(root, root, "Vegetation")
	var spatial: Node3D = _branch(root, root, "Spatial")
	var collision_root: Node3D = _branch(spatial, root, "Collision")
	var actual_topology: Dictionary = {}
	var semantic_sources: Array = []
	# 仅返回给编辑端口的内存来源，不挂入静态树或metadata，避免重复可见结构。
	result["semantic_sources"] = {}
	for part: Dictionary in plans:
		if StructureUnion.owns(str(part.id)):
			semantic_sources.append(part)
			result.semantic_sources[str(part.id)] = {"position": part.position, "mesh_records": part.mesh_records.duplicate(true), "component_id": part.component_id, "kind": part.kind, "floor": part.floor}
			part["semantic_only"] = true
			part["collidable"] = false
	plans.append(structure)
	for part in plans:
		var parent: Node3D = vegetation if str(part.kind) == "plant" else visual
		var semantic_only: bool = bool(part.get("semantic_only", false))
		var node: Node3D = part.instance as Node3D
		if semantic_only:
			node = Node3D.new()
			node.position = part.position
			node.set_meta("semantic_source_only", true)
			node.set_meta("structure_node", "../structure_union")
		elif node == null:
			var mesh_node: MeshInstance3D = MeshInstance3D.new()
			mesh_node.mesh = part.mesh
			node = mesh_node
			node.position = part.position
		node.name = str(part.id)
		parent.add_child(node)
		_tag_tree(node, root, part)
		var bounds: AABB = _part_bounds(part)
		var slot: Dictionary = {"id": str(part.id), "kind": str(part.kind), "floor": int(part.floor), "facade": str(part.facade), "component_id": str(part.component_id), "position": _xyz(part.position), "size": _xyz(bounds.size), "node_path": str(root.get_path_to(node)), "bounds_position": _xyz(bounds.position), "bounds_size": _xyz(bounds.size), "bevel_width": float(part.get("bevel_width", 0.0))}
		if str(part.kind) == "plant":
			slot["growth_key"] = str(part.growth_key)
			slot["plant_profile"] = str(part.plant_profile)
			slot["anchor_position"] = _xyz(part.anchor_position)
		else:
			var audit: Dictionary = _audit_part(part)
			actual_topology[str(part.id)] = audit
			node.set_meta("topology", audit)
			if not bool(audit.closed) or not bool(audit.oriented):
				root.free()
				_release_plans(plans)
				return _fail(result, "整件替换必须保持闭合定向实体: " + str(part.id))
			if part.instance != null:
				slot["bevel_source"] = "prefab_geometry_unmeasured"
				slot["bevel_measured"] = false
		if semantic_only:
			slot["semantic_source_only"] = true
			slot["structure_node_path"] = "GeneratedVisual/structure_union"
		if str(part.kind) != "structure": result.slots.append(slot)
		if bool(part.collidable):
			for record in part.mesh_records:
				var mesh: Mesh = record.mesh
				var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape() as ConcavePolygonShape3D
				if shape == null:
					root.free()
					_release_plans(plans)
					return _fail(result, "真实网格碰撞生成失败: " + str(part.id))
				var body: StaticBody3D = StaticBody3D.new()
				body.name = "Collision_" + str(part.id) + "_" + str(collision_root.get_child_count())
				body.collision_layer = 256 if str(r.spatial_profile) == "above_water" else 1024
				body.collision_mask = 0
				body.transform = Transform3D(Basis.IDENTITY, part.position) * record.transform
				collision_root.add_child(body)
				body.owner = root
				_tag(body, part)
				var shape_node: CollisionShape3D = CollisionShape3D.new()
				shape_node.name = "Shape"
				shape_node.shape = shape
				body.add_child(shape_node)
				shape_node.owner = root
				_tag(shape_node, part)
		if str(part.kind) == "structure":
			node.set_meta("source_slots", part.source_slots)
		if str(r.spatial_profile) != "scenic_underwater" and (str(part.id).begins_with("slab_") or str(part.id) == "roof_main"):
			var top: Dictionary = _union_top_surface(structure, part) if semantic_only else _top_surface(part)
			for index in top.rects.size():
				var rect: Rect2 = top.rects[index]
				result.walk_surfaces.append({"id": "walk_" + str(part.id) + "_" + str(index), "floor": int(part.floor), "position": Vector3(rect.get_center().x, float(top.y), rect.get_center().y), "size": [rect.size.x, rect.size.y], "source_slots": [str(part.id)], "source_node_path": "GeneratedVisual/structure_union" if semantic_only else str(root.get_path_to(node)), "kind": "local_candidate_rectangle", "coordinate_space": "root_local"})
			if top.rects.is_empty() and not top.loops.is_empty():
				result.walk_surfaces.append({"id": "walk_" + str(part.id), "floor": int(part.floor), "kind": "local_candidate_polygon", "polygons": _public_loops(top.loops), "surface_y": top.y, "source_slots": [str(part.id)], "source_node_path": "GeneratedVisual/structure_union" if semantic_only else str(root.get_path_to(node)), "coordinate_space": "root_local"})
			if str(r.spatial_profile) == "above_water" and str(part.id) == "slab_0" and absf(float(top.y)) <= BOUNDS_EPS:
				if top.rects.is_empty() and not top.loops.is_empty():
					result.water_blockers.append({"id": "water_floor0_polygon", "kind": "local_candidate_floor0_polygon", "polygons": _public_loops(top.loops), "waterline_y": top.y, "coordinate_space": "root_local", "source_slots": ["slab_0"], "source_node_path": "GeneratedVisual/structure_union", "note": "最终结构实际水平面轮廓；不自动接入世界水线"})
				for index in top.rects.size():
					var rect: Rect2 = top.rects[index]
					result.water_blockers.append({"id": "water_floor0_" + str(index), "kind": "local_candidate_floor0_footprint", "position": [rect.get_center().x, rect.get_center().y], "size": [rect.size.x, rect.size.y], "waterline_y": 0.0, "coordinate_space": "root_local", "source_slots": ["slab_0"], "source_node_path": "GeneratedVisual/structure_union" if semantic_only else str(root.get_path_to(node)), "note": "floor0实际板顶占地候选；不代表世界物理水线或正式水面接入"})
	_release_plans(semantic_sources)
	var stats: Dictionary = _count_tree(root)
	if _over_budget(stats):
		root.free()
		return _fail(result, "实际装配超出节点或三角面预算")
	result.quality["topology"] = actual_topology
	result.quality["triangles"] = stats.triangles
	result.quality["topology_scope"] = "最终structure_union实际Mesh.get_faces单连通、闭合、定向、正体积、无重复/退化；语义源槽只供编辑，不代表分件可见结构"
	result.quality["verification"] = "生成器已检查最终实际网格的闭合和定向；独立几何专项与真实渲染证据另行记录，不代表美术终验"
	result.quality["assembly_restrictions"] = "结构语义槽保留参数与替件身份，不保留可见源网格；替件后必须真实union并通过单连通闭合定向门禁；禁用/排除/非零位移仍拒绝"
	result.quality["assembly"] = {"collision": "实际mesh三角面静态凹碰撞", "coordinates": "root_local；根变换恒等时与world一致", "walk": "实际水平板顶轮廓的不重叠矩形分解；不填L缺口", "water": "floor0实际板顶在local y=0的占地候选，不承诺物理waterline", "vegetation": "屋顶实际顶面锚点；植物独立、无碰撞", "frame_glass_offset": "非零位移明确拒绝", "disabled_parts": "结构禁用拒绝；柱腰线由配方开关控制并重新union", "structure": "墙/板/屋顶/柱/腰线/束带/勒脚真实布尔边界，单一MeshInstance3D，无可见源壳"}
	# 只存可序列化审计值；不把parts或Mesh资源塞入metadata。
	root.set_meta("quality", result.quality.duplicate(true))
	root.set_meta("openings", result.openings.duplicate(true))
	root.set_meta("warnings", result.warnings.duplicate(true))
	root.set_meta("walk_surfaces", result.walk_surfaces.duplicate(true))
	root.set_meta("water_blockers", result.water_blockers.duplicate(true))
	result.stats = stats
	result.root = root
	result.ok = true
	return result

static func _validate_wrapper(r: Dictionary, c: Dictionary) -> String:
	if not Recipe._safe_id(str(r.building_id)): return "building_id非法"
	if not r.component_bindings is Dictionary: return "component_bindings必须是对象"
	for family in ["wall", "slab", "frame", "glass", "plant"]:
		var binding_reason: String = Recipe._check_component(str(r.component_bindings.get(family, "")), family, c)
		if not binding_reason.is_empty(): return binding_reason
	var reason: String = Recipe._validate_slot_overrides(r.slot_overrides, r.excluded_slots, c)
	if not reason.is_empty(): return reason
	reason = Recipe._validate_locked_vegetation(r.locked_vegetation)
	if not reason.is_empty(): return reason
	if not (r.vegetation_density is int or r.vegetation_density is float) or float(r.vegetation_density) < 0.0 or float(r.vegetation_density) > 1.0: return "vegetation_density必须在0..1"
	if not Recipe._validate_growth_weights(r.growth_weights): return "growth_weights非法"
	if not Recipe._math_integer(r.vegetation_seed) or int(r.vegetation_seed) < 0: return "vegetation_seed必须为非负整数"
	for id in r.excluded_slots:
		if not str(id).begins_with("plant_"):
			return "连续结构不允许排除整件；请修改轮廓或门窗设置: " + str(id)
	for id in r.slot_overrides:
		var entry: Dictionary = r.slot_overrides[id]
		if str(id).begins_with("plant_"): continue
		if bool(entry.get("disabled", false)):
			return "连续结构不允许禁用整件导致断壳: " + str(id)
		if entry.has("growth_key"): return "growth_key仅支持植物槽: " + str(id)
		if entry.has("offset") and _vector(entry.offset).length_squared() > 0.0:
			return "连续结构不允许位移；frame/glass不能静默脱离洞口: " + str(id)
	return ""

static func _parametric_component(c: Dictionary, family: String) -> String:
	for id in Catalog.ids(c):
		var definition: Dictionary = c.components[id]
		if str(definition.family) == family and str(definition.kind) == "parametric": return id
	return ""

static func _prepare_prefab(part: Dictionary, definition: Dictionary) -> Dictionary:
	var fail: Dictionary = {"ok": false, "reason": "静态prefab接口不兼容: " + str(part.component_id)}
	var path: String = str(definition.get("prefab", ""))
	if not path.begins_with(Catalog.PREFAB_ROOT) or path.contains("..") or not path.ends_with(".tscn"): return fail
	var packed: PackedScene = load(path) as PackedScene
	if packed == null or not _safe_scene_state(packed.get_state()): return fail
	var raw_instance: Node = packed.instantiate()
	if raw_instance == null: return fail
	if not raw_instance is Node3D:
		raw_instance.free()
		return fail
	var instance: Node3D = raw_instance as Node3D
	var records: Array = []
	var stack: Array[Node] = [instance]
	var bounds: AABB = AABB()
	var initialized: bool = false
	var node_count: int = 0
	var triangle_count: int = 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		node_count += 1
		if node_count > MAX_NODES or node.get_class() not in ["Node3D", "MeshInstance3D", "Marker3D"] or node.get_script() != null:
			instance.free()
			return fail
		var spatial: Node3D = node as Node3D
		if spatial.top_level or not spatial.visible or not _unit_basis(spatial.transform.basis):
			instance.free()
			return fail
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node.mesh != null:
				if not mesh_node.is_visible() or mesh_node.skin != null or mesh_node.mesh.get_blend_shape_count() > 0:
					instance.free()
					return fail
				var transform: Transform3D = instance.transform * _relative(mesh_node, instance)
				var faces: PackedVector3Array = mesh_node.mesh.get_faces()
				if faces.is_empty() or faces.size() % 3 != 0:
					instance.free()
					return fail
				triangle_count += int(faces.size() / 3)
				if triangle_count > MAX_TRIANGLES:
					instance.free()
					return {"ok": false, "reason": "单件prefab超过180000三角面预算"}
				for point in faces:
					var actual: Vector3 = transform * point
					if not actual.is_finite():
						instance.free()
						return fail
					bounds = bounds.expand(actual) if initialized else AABB(actual, Vector3.ZERO)
					initialized = true
				records.append({"mesh": mesh_node.mesh, "transform": transform})
		for child in node.get_children(): stack.append(child)
	var yaw: float = float({"-Z": 0.0, "+Z": PI, "+X": PI * 0.5, "-X": -PI * 0.5}.get(str(definition.front_axis), 0.0))
	var orientation: Basis = Basis(Vector3.UP, yaw)
	var nominal: Vector3 = _vector(definition.nominal_size)
	var pivot: Vector3 = _vector(definition.pivot)
	var oriented: AABB = Transform3D(orientation, Vector3.ZERO) * bounds
	if not initialized or not _matches(bounds.size, nominal) or not _matches(oriented.size, part.size) or not _matches(pivot, bounds.get_center()):
		instance.free()
		fail.reason = "prefab实际meshbounds/nominal/整part包络或实际中心pivot不匹配(1e-4，禁止scale): " + str(part.component_id)
		return fail
	var center_offset: Vector3 = Vector3.ZERO
	if str(part.kind) == "plant":
		center_offset.y = oriented.size.y * (-0.5 if str(part.plant_profile) == "vine" else 0.5)
	var placement: Transform3D = Transform3D(orientation, center_offset - orientation * bounds.get_center())
	for record in records: record.transform = placement * record.transform
	instance.transform = Transform3D(Basis.IDENTITY, part.position) * placement * instance.transform
	part["instance"] = instance
	part["mesh_records"] = records
	part["node_count"] = node_count
	part["bevel_width"] = 0.0
	part.erase("mesh")
	return {"ok": true, "part": part}

static func _safe_scene_state(state: SceneState) -> bool:
	if state == null or Catalog._state_contains_script(state): return false
	var base: SceneState = state.get_base_scene_state()
	if base != null and not _safe_scene_state(base): return false
	for index in state.get_node_count():
		var nested: PackedScene = state.get_node_instance(index)
		if nested != null and not _safe_scene_state(nested.get_state()): return false
	return true

static func _unit_basis(basis: Basis) -> bool:
	return basis.is_equal_approx(basis.orthonormalized()) and absf(basis.determinant() - 1.0) <= POINT_EPS

static func _prepare_plants(anchors: Array, roof: Dictionary, r: Dictionary, c: Dictionary, budget: Dictionary, warnings: Array) -> Dictionary:
	var parts: Array = []
	var support: Dictionary = _top_surface(roof) if not roof.is_empty() else {"loops": []}
	var locked: Dictionary = {}
	for entry in r.locked_vegetation: locked[str(entry.slot_id)] = entry
	var emitted: Dictionary = {}
	var cache: Dictionary = {}
	for anchor in anchors:
		var id: String = str(anchor.id)
		if _disabled(r, id): continue
		var override: Dictionary = r.slot_overrides.get(id, {})
		var component: String = str(override.get("component_id", r.component_bindings.plant))
		var definition: Dictionary = c.components[component]
		var profile: String = str(definition.profile)
		if profile not in ["tree", "shrub", "moss", "vine"]:
			_release_plans(parts)
			return {"ok": false, "reason": "植物组件profile不支持: " + component}
		if (profile == "vine") != bool(anchor.edge): continue
		var entry: Dictionary = locked.get(id, {})
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = (str(r.vegetation_seed) + ":" + id).sha256_text().substr(0, 8).hex_to_int()
		if rng.randf() >= float(r.vegetation_density) and entry.is_empty(): continue
		var growth: String = str(override.get("growth_key", entry.get("growth_key", _choose_growth(r.growth_weights, rng))))
		var position: Vector3 = _vector(entry.position) if not entry.is_empty() else anchor.position
		# 锁定记录保存无offset锚点；先恢复锚点，再只应用一次槽位移。
		position.y = float(anchor.position.y)
		if not _supported_anchor(Vector2(position.x, position.z), support.loops, profile == "vine"):
			warnings.append("锁定植物锚点已不在实际屋顶或屋檐上: " + id)
			continue
		var anchor_position: Vector3 = position
		position += _vector(override.get("offset", [0.0, 0.0, 0.0]))
		if not _supported_anchor(Vector2(position.x, position.z), support.loops, profile == "vine"):
			warnings.append("植物位移离开实际屋顶或屋檐，跳过该槽: " + id)
			continue
		var mesh_data: Dictionary = MeshBuilder.plant_mesh(profile, growth, str(definition.color), float(r.aging), cache)
		var part: Dictionary = {"id": id, "kind": "plant", "floor": int(r.floors), "facade": "roof", "component_id": component, "position": position, "anchor_position": anchor_position, "mesh": mesh_data.mesh, "size": mesh_data.mesh.get_aabb().size, "collidable": false, "bevel_width": 0.0, "growth_key": growth, "plant_profile": profile, "instance": null, "node_count": 1}
		if str(definition.kind) == "prefab":
			var prepared: Dictionary = _prepare_prefab(part, definition)
			if not bool(prepared.ok):
				_release_plans(parts)
				return prepared
			part = prepared.part
		else:
			part["mesh_records"] = [{"mesh": part.mesh, "transform": Transform3D.IDENTITY}]
		parts.append(part)
		_accumulate_budget(budget, part)
		if _over_budget(budget):
			_release_plans(parts)
			return {"ok": false, "reason": "植物加入后超过2000节点或180000三角面预算"}
		emitted[id] = true
	for id in locked:
		if not emitted.has(id): warnings.append("锁定植物的同id屋顶锚点不存在、类型不匹配或已禁用: " + str(id))
	for id in r.slot_overrides:
		if str(id).begins_with("plant_") and not emitted.has(id) and not _disabled(r, str(id)):
			warnings.append("植物槽覆盖未命中本次生成实例: " + str(id))
	return {"ok": true, "parts": parts}

static func _plant_anchors(roof: Dictionary, r: Dictionary) -> Array:
	var anchors: Array = []
	if roof.is_empty(): return anchors
	var top: Dictionary = _top_surface(roof)
	if top.loops.is_empty(): return anchors
	var bounds: AABB = _part_bounds(roof)
	var nx: int = maxi(1, ceili(float(r.width) / float(r.bay_width))) * 3
	var nz: int = maxi(1, ceili(float(r.depth) / float(r.bay_width))) * 3
	for x in nx:
		for z in nz:
			var point: Vector2 = Vector2(bounds.position.x + bounds.size.x * (float(x) + 0.5) / nx, bounds.position.z + bounds.size.z * (float(z) + 0.5) / nz)
			if _inside_loops(point, top.loops):
				anchors.append({"id": "plant_roof_" + str(x) + "_" + str(z), "position": Vector3(point.x, float(top.y), point.y), "edge": false})
	# 藤蔓锚点来自实际屋檐边，不读旧cell屋顶；0.14m出挑和整栋taper已在实际轮廓中。
	var edge_index: int = 0
	for loop in top.loops:
		for i in loop.size():
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % loop.size()]
			var count: int = maxi(1, ceili(a.distance_to(b) / (float(r.bay_width) / 3.0)))
			for index in count:
				var point: Vector2 = a.lerp(b, (float(index) + 0.5) / count)
				anchors.append({"id": "plant_roof_edge_" + str(edge_index) + "_" + str(index), "position": Vector3(point.x, float(top.y), point.y), "edge": true})
			edge_index += 1
	return anchors

static func _union_top_surface(structure: Dictionary, source: Dictionary) -> Dictionary:
	return _top_surface(structure, snappedf(_part_bounds(source).end.y, 0.0001))

static func _top_surface(part: Dictionary, surface_y: float = INF) -> Dictionary:
	var faces: PackedVector3Array = _part_faces(part)
	var top: float = float(part.get("surface_y", _part_bounds(part).end.y)) if is_inf(surface_y) else surface_y
	var edges: Dictionary = {}
	var points: Dictionary = {}
	for i in range(0, faces.size(), 3):
		var a: Vector3 = faces[i]
		var b: Vector3 = faces[i + 1]
		var c: Vector3 = faces[i + 2]
		if absf(a.y - top) > POINT_EPS or absf(b.y - top) > POINT_EPS or absf(c.y - top) > POINT_EPS: continue
		if -(b - a).cross(c - a).y <= POINT_EPS * POINT_EPS: continue
		var triangle: Array[Vector3] = [a, b, c]
		for edge in 3:
			var p: Vector3 = triangle[edge]
			var q: Vector3 = triangle[(edge + 1) % 3]
			var kp: Vector2i = Vector2i(roundi(p.x / POINT_EPS), roundi(p.z / POINT_EPS))
			var kq: Vector2i = Vector2i(roundi(q.x / POINT_EPS), roundi(q.z / POINT_EPS))
			points[kp] = Vector2(p.x, p.z)
			points[kq] = Vector2(q.x, q.z)
			var key: String = str(kp) + ":" + str(kq) if str(kp) < str(kq) else str(kq) + ":" + str(kp)
			if edges.has(key): edges[key].count += 1
			else: edges[key] = {"a": kp, "b": kq, "count": 1}
	var adjacency: Dictionary = {}
	for edge in edges.values():
		if int(edge.count) != 1: continue
		if not adjacency.has(edge.a): adjacency[edge.a] = []
		if not adjacency.has(edge.b): adjacency[edge.b] = []
		adjacency[edge.a].append(edge.b)
		adjacency[edge.b].append(edge.a)
	var loops: Array = []
	var remaining: Dictionary = adjacency.duplicate(true)
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		var current: Vector2i = start
		var previous: Vector2i = Vector2i(2147483647, 2147483647)
		var loop: PackedVector2Array = PackedVector2Array()
		var closed: bool = false
		for step in adjacency.size() + 1:
			if not adjacency.has(current) or adjacency[current].size() != 2: break
			loop.append(points[current])
			remaining.erase(current)
			var neighbors: Array = adjacency[current]
			var next: Vector2i = neighbors[0] if neighbors[0] != previous else neighbors[1]
			previous = current
			current = next
			if current == start:
				closed = true
				break
		if not closed: return {"y": top, "loops": [], "rects": []}
		loops.append(_simplify_loop(loop))
	return {"y": top, "loops": loops, "rects": _rectangles(loops)}

static func _simplify_loop(loop: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for index in loop.size():
		var a: Vector2 = loop[index] - loop[(index - 1 + loop.size()) % loop.size()]
		var b: Vector2 = loop[(index + 1) % loop.size()] - loop[index]
		if absf(a.cross(b)) > POINT_EPS * maxf(1.0, a.length() + b.length()): result.append(loop[index])
	return result

static func _rectangles(loops: Array) -> Array:
	var xs: Array[float] = []
	var zs: Array[float] = []
	for loop in loops:
		for index in loop.size():
			var a: Vector2 = loop[index]
			var b: Vector2 = loop[(index + 1) % loop.size()]
			if absf(a.x - b.x) > POINT_EPS and absf(a.y - b.y) > POINT_EPS: return []
			xs.append(a.x)
			zs.append(a.y)
	xs = _unique(xs)
	zs = _unique(zs)
	var rects: Array = []
	for x in range(xs.size() - 1):
		var z: int = 0
		while z < zs.size() - 1:
			if not _inside_loops(Vector2((xs[x] + xs[x + 1]) * 0.5, (zs[z] + zs[z + 1]) * 0.5), loops):
				z += 1
				continue
			var low: int = z
			while z < zs.size() - 1 and _inside_loops(Vector2((xs[x] + xs[x + 1]) * 0.5, (zs[z] + zs[z + 1]) * 0.5), loops): z += 1
			var rect: Rect2 = Rect2(Vector2(xs[x], zs[low]), Vector2(xs[x + 1] - xs[x], zs[z] - zs[low]))
			var merged: bool = false
			for index in rects.size():
				var existing: Rect2 = rects[index]
				if absf(existing.end.x - rect.position.x) <= POINT_EPS and absf(existing.position.y - rect.position.y) <= POINT_EPS and absf(existing.size.y - rect.size.y) <= POINT_EPS:
					existing.size.x += rect.size.x
					rects[index] = existing
					merged = true
					break
			if not merged: rects.append(rect)
	return rects

static func _supported_anchor(point: Vector2, loops: Array, edge_only: bool) -> bool:
	if not edge_only: return _inside_loops(point, loops)
	for loop in loops:
		for index in loop.size():
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(point, loop[index], loop[(index + 1) % loop.size()])
			if point.distance_to(nearest) <= BOUNDS_EPS: return true
	return false

static func _inside_loops(point: Vector2, loops: Array) -> bool:
	var inside: bool = false
	for loop in loops:
		if Geometry2D.is_point_in_polygon(point, loop): inside = not inside
	return inside

static func _unique(values: Array[float]) -> Array[float]:
	values.sort()
	var result: Array[float] = []
	for value in values:
		if result.is_empty() or absf(value - result[-1]) > POINT_EPS: result.append(value)
	return result

static func _part_faces(part: Dictionary) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for record in part.mesh_records:
		var mesh: Mesh = record.mesh
		var transform: Transform3D = Transform3D(Basis.IDENTITY, part.position) * record.transform
		for point in mesh.get_faces(): result.append(transform * point)
	return result

static func _part_bounds(part: Dictionary) -> AABB:
	var faces: PackedVector3Array = _part_faces(part)
	if faces.is_empty(): return AABB()
	var result: AABB = AABB(faces[0], Vector3.ZERO)
	for point in faces: result = result.expand(point)
	return result

static func _audit_part(part: Dictionary) -> Dictionary:
	var faces: PackedVector3Array = _part_faces(part)
	var indices: PackedInt32Array = PackedInt32Array()
	for index in faces.size(): indices.append(index)
	return Geometry._topology({"v": faces, "i": indices})

static func _accumulate_budget(budget: Dictionary, part: Dictionary) -> void:
	budget.nodes += int(part.node_count)
	for record in part.mesh_records:
		var mesh: Mesh = record.mesh
		budget.triangles += int(mesh.get_faces().size() / 3)
		budget.visual_meshes += 1
		if str(part.kind) == "plant": budget.plant_meshes += 1
		if bool(part.collidable):
			budget.nodes += 2
			budget.collision_shapes += 1

static func _count_tree(root: Node) -> Dictionary:
	var stats: Dictionary = {"nodes": 0, "triangles": 0, "visual_meshes": 0, "collision_shapes": 0, "plant_meshes": 0}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stats.nodes += 1
		if node is MeshInstance3D:
			stats.visual_meshes += 1
			var mesh: Mesh = (node as MeshInstance3D).mesh
			if mesh != null: stats.triangles += int(mesh.get_faces().size() / 3)
			if str(node.get_meta("slot_kind", "")) == "plant": stats.plant_meshes += 1
		if node is CollisionShape3D: stats.collision_shapes += 1
		for child in node.get_children(): stack.append(child)
	return stats

static func _over_budget(stats: Dictionary) -> bool:
	return int(stats.nodes) > MAX_NODES or int(stats.triangles) > MAX_TRIANGLES

static func _release_plans(plans: Array) -> void:
	for part in plans:
		var instance: Variant = part.get("instance", null)
		if is_instance_valid(instance) and instance is Node and instance.get_parent() == null: instance.free()

static func _branch(parent: Node, root: Node, branch_name: String) -> Node3D:
	var branch: Node3D = Node3D.new()
	branch.name = branch_name
	parent.add_child(branch)
	branch.owner = root
	return branch

static func _tag_tree(node: Node, root: Node, part: Dictionary) -> void:
	node.owner = root
	_tag(node, part)
	if str(part.kind) == "plant":
		node.set_meta("plant_profile", str(part.plant_profile))
		node.set_meta("growth_key", str(part.growth_key))
		node.set_meta("anchor_position", _xyz(part.anchor_position))
		node.set_meta("independent_vegetation", true)
	# 不改共享mesh、材质或阴影；外链scene身份由旧store保存前取消。
	for child in node.get_children(): _tag_tree(child, root, part)

static func _tag(node: Node, part: Dictionary) -> void:
	node.set_meta("slot_id", str(part.id))
	node.set_meta("part_id", str(part.id))
	node.set_meta("component_id", str(part.component_id))
	node.set_meta("slot_kind", str(part.kind))
	node.set_meta("bevel_width", float(part.get("bevel_width", 0.0)))

static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node3D = node
	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

static func _shell_part_family(part: Dictionary, id: String) -> String:
	if id.begins_with("parapet_"): return "wall"
	if id.begins_with("railing_"): return "pillar"
	if id.begins_with("roofcap_"): return "slab"
	if id.begins_with("roof_edge_"):
		var raw_kind: String = str(part.get("kind", ""))
		if raw_kind in ["wall", "pillar", "slab"]: return raw_kind
	var family: String = Recipe._slot_family(id)
	if not family.is_empty(): return family
	var source_kind: String = str(part.get("kind", ""))
	return source_kind if source_kind in ["wall", "slab", "frame", "glass", "pillar"] else ""

static func _disabled(r: Dictionary, id: String) -> bool:
	return r.excluded_slots.has(id) or bool(r.slot_overrides.get(id, {}).get("disabled", false))

static func _plan_by_id(plans: Array, id: String) -> Dictionary:
	for part in plans:
		if str(part.id) == id: return part
	return {}

static func _choose_growth(weights: Array, rng: RandomNumberGenerator) -> String:
	var pick: float = rng.randf() * (float(weights[0]) + float(weights[1]) + float(weights[2]))
	if pick < float(weights[0]): return "small"
	if pick < float(weights[0]) + float(weights[1]): return "medium"
	return "large"

static func _matches(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) <= BOUNDS_EPS and absf(a.y - b.y) <= BOUNDS_EPS and absf(a.z - b.z) <= BOUNDS_EPS

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _public_loops(loops: Array) -> Array:
	var result: Array = []
	for loop in loops:
		var points: Array = []
		for point in loop: points.append([point.x, point.y])
		result.append(points)
	return result

static func _fail(result: Dictionary, reason: String) -> Dictionary:
	result.ok = false
	result.reason = reason
	result.root = null
	result.slots = []
	result.stats = {}
	result.walk_surfaces = []
	result.water_blockers = []
	result.erase("semantic_sources")
	return result
