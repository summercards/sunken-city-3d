extends SceneTree
## 根tests原件保留；本文件为runner正式入口，只在隔离项目执行。
const Catalog = preload("res://src/building_attachments/catalog.gd")
const Recipe = preload("res://src/building_attachments/recipe.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const Geometry = preload("res://src/building_attachments/geometry.gd")
const Glyphs = preload("res://src/building_attachments/glyphs.gd")
const Store = preload("res://src/building_attachments/store.gd")
var checks: int = 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var condition_hashes: Dictionary = {}
var fresh_hashes: Dictionary = {}
var shared_hashes: Dictionary = {}
var physics_rows: Array[Dictionary] = []
var custom_rows: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, meaning: String) -> void:
	checks += 1
	if not value:
		failures.append(meaning)
		printerr("FAIL [building-attachments] ", meaning)

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		printerr("FAIL 仅允许隔离且无Main的runner项目")
		quit(1)
		return
	var catalog: Dictionary = Catalog.definitions()
	check(Catalog.entries().size() == 32, "目录冻结恰好32类型")
	for category: String in ["signage", "hvac", "water", "shelter"]:
		check(Catalog.list(category).size() == 8, "每族8个：" + category)
	check(Catalog.search("横招").size() == 1, "中文搜索")
	check(Catalog.search("ac_wall").size() == 2, "稳定ID搜索")
	for path: String in catalog.materials.values():
		shared_hashes[path] = FileAccess.get_sha256(path)
	for entry: Dictionary in Catalog.entries():
		var hashes: Array[String] = []
		for condition: String in Catalog.CONDITIONS:
			var recipe: Dictionary = Recipe.defaults(entry.type_id)
			recipe.condition = condition
			check(Recipe.validate(recipe).is_empty(), "%s/%s默认有效" % [entry.type_id, condition])
			var result: Dictionary = Generator.build(recipe)
			check(result.ok, "%s/%s生成：%s" % [entry.type_id, condition, result.reason])
			if not result.ok: continue
			inspect_result(result, recipe)
			var hash_value: String = independent_fingerprint(result.root, true)
			check(not condition_hashes.has(hash_value), "96件无ID/颜色盐的实网格指纹唯一：" + str(entry.type_id) + "/" + condition)
			condition_hashes[hash_value] = true
			hashes.append(independent_fingerprint(result.root, false))
			if condition == "fresh":
				check(not fresh_hashes.has(hash_value), "32类不是同盒换尺寸：" + str(entry.type_id))
				fresh_hashes[hash_value] = entry.type_id
			rows.append({"type_id": entry.type_id, "condition": condition, "stats": result.stats, "anchor": result.mount_anchor, "independent_geometry_sha256": hashes[-1]})
			var repeated: Dictionary = Generator.build(recipe)
			check(repeated.ok and repeated.fingerprint == result.fingerprint, "确定性指纹：" + str(entry.type_id))
			if repeated.ok: repeated.root.free()
			result.root.free()
		check(hashes.size() == 3 and hashes[0] != hashes[1] and hashes[1] != hashes[2] and hashes[0] != hashes[2], "三状态真实几何不同：" + str(entry.type_id))
	test_validation()
	test_geometry_rejection()
	test_text()
	test_custom_variants()
	test_colors_and_scale()
	test_collision_switch()
	test_store()
	test_symlink_storage()
	await test_physics()
	for path: String in shared_hashes:
		check(FileAccess.get_sha256(path) == shared_hashes[path], "共享材质字节不变：" + path)
	var report: Dictionary = {"suite": "building-attachments", "passed": failures.is_empty(), "checks": checks, "failures": failures, "variants": rows, "actual_variant_count": rows.size(), "actual_type_count": fresh_hashes.size(), "custom_variants": custom_rows, "actual_total_variant_count": rows.size() + custom_rows.size(), "physics": physics_rows, "real_rendering": "未执行；本项仅逻辑和真实物理", "world_installation": "未执行", "expected_failures": [], "exit_code": 0 if failures.is_empty() else 1}
	var path := "res://outputs/building_attachments_report.json"
	var report_error: String = Store.write_json(path, report)
	if not report_error.is_empty():
		failures.append("报告写入失败：" + report_error)
		printerr("FAIL [building-attachments] ", report_error)
	print("BUILDING_ATTACHMENTS_RESULT ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "variant_count": rows.size(), "report": ProjectSettings.globalize_path(path)}))
	quit(0 if failures.is_empty() else 1)

func independent_fingerprint(node: Node3D, normalized: bool) -> String:
	var bounds := AABB()
	var initialized := false
	for mesh_node: Node in node.get_children():
		if not mesh_node is MeshInstance3D: continue
		for point: Vector3 in mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if not initialized:
				bounds = AABB(point, Vector3.ZERO)
				initialized = true
			bounds = bounds.expand(point)
	var faces: Array[String] = []
	for mesh_node: Node in node.get_children():
		if not mesh_node is MeshInstance3D: continue
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i: int in range(0, indices.size(), 3):
			var points: Array[String] = []
			for j: int in 3:
				var point: Vector3 = vertices[indices[i + j]]
				if normalized: point = (point - bounds.position) / bounds.size
				var precision: float = 1000.0 if normalized else 100000.0
				points.append("%d,%d,%d" % [roundi(point.x * precision), roundi(point.y * precision), roundi(point.z * precision)])
			points.sort()
			faces.append("/".join(points))
	faces.sort()
	return "|".join(faces).sha256_text()

func inspect_result(result: Dictionary, recipe: Dictionary) -> void:
	var node: Node3D = result.root
	var label: String = str(recipe.type_id) + "/" + str(recipe.condition)
	check(scriptfree(node), label + "全层级无脚本/TextMesh/CSG")
	check(node.transform.is_equal_approx(Transform3D.IDENTITY), label + "根恒等")
	check(node.get_meta("visual_only", false), label + "排除世界自动派生")
	check(node.get_meta("text_input") == recipe.text, label + "文字metadata完整")
	var stats: Dictionary = result.stats
	check(int(stats.triangles) > 0 and int(stats.triangles) <= int(stats.budget), label + "实际三角面预算")
	check(int(stats.budget) <= (3500 if recipe.text.length() > 8 else 1800), label + "预算硬上限")
	check(int(stats.mesh_nodes) >= 2 and int(stats.mesh_nodes) <= 4 and int(stats.surfaces) == int(stats.mesh_nodes), label + "角色合批2..4mesh")
	check(count_class(node, "Marker3D") == 1 and str(result.mount_anchor.name) in ["mount_back", "mount_roof"], label + "仅两种安装锚点契约")
	var minimum: Vector3 = Geometry.from_vec(stats.bounds.position)
	var size: Vector3 = Geometry.from_vec(stats.bounds.size)
	check(absf(minimum.y) < 0.00001 and absf(minimum.x + size.x * 0.5) < 0.00001 and absf(minimum.z + size.z * 0.5) < 0.00001, label + "真实底心")
	var anchor: Marker3D = node.get_node(NodePath(str(result.mount_anchor.name))) as Marker3D
	check(anchor != null, label + "锚点存在")
	if anchor != null and result.mount_anchor.name == "mount_back":
		check(absf(anchor.position.z - (minimum.z + size.z)) < 0.00001 and absf(anchor.position.y - size.y * 0.5) < 0.00001, label + "墙锚maxZ/中Y")
	elif anchor != null:
		check(anchor.position.is_equal_approx(Vector3.ZERO), label + "屋顶锚底心")
	var actual_triangles: int = 0
	var actual_vertices: int = 0
	var mesh_count: int = 0
	var materials: Dictionary = Catalog.definitions().materials
	for child: Node in node.get_children():
		if not child is MeshInstance3D: continue
		mesh_count += 1
		check(child.transform.is_equal_approx(Transform3D.IDENTITY), label + "mesh恒等")
		check(child.mesh is ArrayMesh and child.mesh.get_surface_count() == 1, label + "静态单surface")
		var material: Material = child.mesh.surface_get_material(0)
		check(material != null and material.resource_path == str(materials[str(child.name)]), label + "正式共享材质")
		check(material == load(str(materials[str(child.name)])), label + "共享同一资源对象")
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		actual_triangles += indices.size() / 3
		actual_vertices += vertices.size()
		check(uv.size() == vertices.size() and normals.size() == vertices.size(), label + "逐顶点UV/法线")
		var bad_uv: int = 0
		var bad_normal: int = 0
		var bad_geometry: int = 0
		for i: int in vertices.size():
			if not vertices[i].is_finite() or not normals[i].is_finite() or not uv[i].is_finite(): bad_geometry += 1
			if absf(normals[i].length() - 1.0) > 0.001: bad_normal += 1
		for i: int in range(0, indices.size(), 3):
			var ia: int = indices[i]
			var ib: int = indices[i + 1]
			var ic: int = indices[i + 2]
			var a: Vector2 = uv[ia] * 512
			var b: Vector2 = uv[ib] * 512
			var c: Vector2 = uv[ic] * 512
			if absf((b - a).cross(c - a)) < 1.0: bad_uv += 1
			var target_cell := Vector2i(floori(a.x / 64), floori(a.y / 64))
			for point: Vector2 in [a, b, c]:
				var local: Vector2 = point - Vector2(target_cell) * 64
				if local.x < 8 or local.x > 56 or local.y < 8 or local.y > 56: bad_uv += 1
			var cross: Vector3 = (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
			if cross.length() < 0.000000001: bad_geometry += 1
			for index: int in [ia, ib, ic]:
				if cross.normalized().dot(normals[index]) > -0.98: bad_normal += 1
		check(bad_uv == 0, label + "PaletteUV有面积/8px内缩")
		check(bad_normal == 0, label + "单位外法线/顺时针")
		check(bad_geometry == 0, label + "无非有限/退化")
	check(actual_triangles == int(stats.triangles) and actual_vertices == int(stats.vertices) and mesh_count == int(stats.mesh_nodes), label + "实网格统计")
	check(independent_fingerprint(node, false) == result.fingerprint.geometry_sha256, label + "独立复算指纹吻合")
	var bodies: int = count_class(node, "StaticBody3D")
	var shapes: int = count_class(node, "CollisionShape3D")
	check(bodies == int(stats.physics_bodies) and shapes == int(stats.collision_shapes), label + "真实碰撞计数")
	if recipe.collision_enabled:
		check(shapes > 0 and bodies == 1, label + "默认或显式碰撞挡人")
		var body: StaticBody3D = node.get_node("AttachmentCollision") as StaticBody3D
		check(body.collision_layer == 256 and body.collision_mask == 0, label + "layer256/mask0")
		check(shapes == result.snapshot.collision_proxies.size(), label + "残体proxy对应")
	else:
		check(shapes == 0 and bodies == 0, label + "关闭碰撞0shape")
	var parser := JSON.new()
	check(parser.parse(JSON.stringify(result.snapshot)) == OK and parser.data is Dictionary, label + "快照JSON自包含")
	for part: Dictionary in result.source_parts:
		check(part.has("dimensions") and part.has("rho") and part.has("contacts") and part.has("kind"), label + "source part完整")
		audit_closed_part(result.snapshot, part, label)
		audit_support_and_taper(result.snapshot, part, label)

func part_faces(snapshot: Dictionary, part: Dictionary) -> Array:
	var faces: Array = []
	for mesh: Dictionary in snapshot.meshes:
		if mesh.material_role != part.material_role: continue
		for i: int in range(int(part.triangle_start) * 3, (int(part.triangle_start) + int(part.triangle_count)) * 3, 3):
			faces.append([Geometry.from_vec(mesh.vertices[mesh.indices[i]]), Geometry.from_vec(mesh.vertices[mesh.indices[i + 1]]), Geometry.from_vec(mesh.vertices[mesh.indices[i + 2]])])
	return faces

func contains_real_part(snapshot: Dictionary, part: Dictionary, point: Vector3) -> bool:
	# 独立立体角求和，不调用产品_contains_point，也不只检查metadata。
	var angle := 0.0
	for face: Array in part_faces(snapshot, part):
		var edge0: Vector3 = face[1] - face[0]
		var edge1: Vector3 = face[2] - face[0]
		var normal: Vector3 = edge0.cross(edge1).normalized()
		var delta: Vector3 = point - face[0]
		if absf(delta.dot(normal)) < 0.00001:
			var denominator: float = edge0.dot(edge0) * edge1.dot(edge1) - pow(edge0.dot(edge1), 2)
			var u: float = (edge1.dot(edge1) * delta.dot(edge0) - edge0.dot(edge1) * delta.dot(edge1)) / denominator
			var v: float = (edge0.dot(edge0) * delta.dot(edge1) - edge0.dot(edge1) * delta.dot(edge0)) / denominator
			if u >= -0.00001 and v >= -0.00001 and u + v <= 1.00001: return true
		var a: Vector3 = face[0] - point
		var b: Vector3 = face[1] - point
		var c: Vector3 = face[2] - point
		if minf(a.length(), minf(b.length(), c.length())) < 0.000001: return true
		angle += 2.0 * atan2(a.dot(b.cross(c)), a.length() * b.length() * c.length() + a.dot(b) * c.length() + b.dot(c) * a.length() + c.dot(a) * b.length())
	return absf(angle) > TAU

func audit_support_and_taper(snapshot: Dictionary, part: Dictionary, label: String) -> void:
	var witnesses := 0
	for contact: Dictionary in part.contacts:
		if not contact.has("witness"): continue
		var host: Dictionary = {}
		for candidate: Dictionary in snapshot.source_parts:
			if candidate.name == contact.attached_to: host = candidate
		var point: Vector3 = Geometry.from_vec(contact.witness)
		check(not host.is_empty() and contains_real_part(snapshot, part, point) and contains_real_part(snapshot, host, point), label + "/" + str(part.name) + "独立实际三角立体角承托witness")
		witnesses += 1
	if part.get("required_connection", false) or part.has("glyph"):
		check(witnesses > 0, label + "/" + str(part.name) + "全部字笔/必需连接有实证承托")
	if part.kind != "beveled_tapered_prism": return
	var basis := Basis.from_euler(Geometry.from_vec(part.rotation_euler))
	var center: Vector3 = Geometry.from_vec(part.center)
	var axis: int = int(part.taper_along)
	var low := INF
	var high := -INF
	var points: Array[Vector3] = []
	for face: Array in part_faces(snapshot, part):
		for world: Vector3 in face:
			var local: Vector3 = basis.transposed() * (world - center)
			points.append(local)
			low = minf(low, local[axis])
			high = maxf(high, local[axis])
	for transverse: int in [(axis + 1) % 3, (axis + 2) % 3]:
		var bottom := 0.0
		var top := 0.0
		for point: Vector3 in points:
			if absf(point[axis] - low) < 0.00001: bottom = maxf(bottom, absf(point[transverse]))
			if absf(point[axis] - high) < 0.00001: top = maxf(top, absf(point[transverse]))
		var actual: float = 1.0 - top / bottom if bottom > 0 else -1.0
		var target: float = 0.048 if part.get("form_role", "") == "rod_bar" else 0.035
		check(absf(actual - target) < 0.001 and (actual >= 0.047 if target > 0.04 else actual >= 0.034), label + "/" + str(part.name) + "实际顶点端截面收分=" + str(actual))

func audit_closed_part(snapshot: Dictionary, part: Dictionary, label: String) -> void:
	var mesh: Dictionary = {}
	for candidate: Dictionary in snapshot.meshes:
		if candidate.material_role == part.material_role: mesh = candidate
	var edges: Dictionary = {}
	for i: int in range(int(part.triangle_start) * 3, (int(part.triangle_start) + int(part.triangle_count)) * 3, 3):
		var keys: Array[String] = []
		for j: int in 3:
			var point: Vector3 = Geometry.from_vec(mesh.vertices[int(mesh.indices[i + j])])
			keys.append("%d,%d,%d" % [roundi(point.x * 10000), roundi(point.y * 10000), roundi(point.z * 10000)])
		for j: int in 3:
			var pair: Array[String] = [keys[j], keys[(j + 1) % 3]]
			pair.sort()
			var key: String = "|".join(pair)
			edges[key] = int(edges.get(key, 0)) + 1
	var open_edges: int = 0
	for count: int in edges.values():
		if count != 2: open_edges += 1
	check(open_edges == 0, label + "/" + str(part.name) + "声明实体/字形/管壁逐part闭合边=" + str(open_edges))

func scriptfree(node: Node) -> bool:
	if node.get_script() != null or node is CSGShape3D or (node is MeshInstance3D and node.mesh is TextMesh): return false
	for child: Node in node.get_children():
		if not scriptfree(child): return false
	return true

func count_class(node: Node, type: String) -> int:
	var count: int = 1 if node.is_class(type) else 0
	for child: Node in node.get_children(): count += count_class(child, type)
	return count

func test_validation() -> void:
	for patch: Dictionary in [{"condition": "SF-A"}, {"state": "fresh"}, {"scale": 0.0}, {"scale": NAN}, {"scale": 1.251}, {"text": "sea"}, {"text": "海"}, {"text": "A\nB"}, {"text": "ABCDEFGHIJKLMNOPQRSTUVWXY"}, {"text": ""}, {"text": "  "}, {"attachment_id": "../escape"}, {"collision_enabled": 1}, {"usage": "underwater"}, {"type_id": "unknown"}, {"style": "SF-C"}, {"colors": {"SEA_Matte": -1, "SEA_Metal": 64, "SEA_Gloss": 1, "SEA_Emission": 2}}]:
		var recipe: Dictionary = Recipe.defaults("sign_fascia")
		recipe.merge(patch, true)
		var before: String = JSON.stringify(recipe)
		check(not Recipe.validate(recipe).is_empty(), "拒绝坏配方：" + str(patch))
		check(JSON.stringify(recipe) == before, "validate不改输入")
		var built: Dictionary = Generator.build(recipe)
		check(not built.ok and built.root == null and JSON.stringify(built.recipe) == before, "拒绝生成仍保原配方")
	for axis: String in ["width", "height", "depth"]:
		for ratio: float in [0.749, 1.251, NAN, INF]:
			var recipe: Dictionary = Recipe.defaults("tank_rect")
			recipe.dimensions[axis] *= ratio
			check(not Recipe.validate(recipe).is_empty(), "每轴越界/非有限拒绝：" + axis)
		for ratio: float in [0.75, 1.25]:
			var recipe: Dictionary = Recipe.defaults("tank_rect")
			recipe.dimensions[axis] *= ratio
			check(Recipe.validate(recipe).is_empty(), "每轴端点有效：" + axis)
	var recipe: Dictionary = Recipe.defaults("tank_round_short")
	recipe.usage = "decorative_underwater"
	check(not Recipe.validate(recipe).is_empty() and recipe.collision_enabled, "水下拒绝true不默改")
	recipe.collision_enabled = false
	check(Recipe.validate(recipe).is_empty(), "水下明确关闭有效")
	var copy: Array[Dictionary] = Catalog.entries()
	copy[0].dimensions.width = 999
	check(float(Catalog.entries()[0].dimensions.width) != 999, "目录深副本")

func test_geometry_rejection() -> void:
	for points: Array in [[Vector3.ZERO, Vector3.RIGHT, Vector3.UP], [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, "invalid"], [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3(NAN, 0, 0)]]:
		var geometry := Geometry.new(Recipe.defaults("tank_rect"))
		geometry.begin("invalid_proxy", "SEA_Matte", Vector3.ZERO, Vector3.ONE, Vector3.ZERO, "qa", 0.03, true)
		geometry.proxy(points)
		check(not geometry.errors.is_empty() and not geometry.validate(), "proxy错误显式传播，拒绝短数组/非Vector3/非有限")
	var open := Geometry.new(Recipe.defaults("tank_rect"))
	open.begin("open_part", "SEA_Matte", Vector3.ZERO, Vector3.ONE, Vector3.ZERO, "qa", 0.03, false)
	open.triangle(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	check(not open.validate() and not open.errors.is_empty(), "开放单面真实几何校验拒绝")

func test_text() -> void:
	for character: String in Recipe.SUPPORTED:
		check(Glyphs.TABLE.has(character), "原创字表：" + character)
		check(Glyphs.stroke_count(character) * 12 <= 128, "单字128面：" + character)
	for entry: Dictionary in Catalog.list("signage"):
		var type_id: String = entry.type_id
		for style: String in Catalog.STYLES:
			var recipe: Dictionary = Recipe.defaults(type_id)
			recipe.style = style
			recipe.text = "QQQQQQQQQQQQQQQQQQQQQQQQ"
			var built: Dictionary = Generator.build(recipe)
			check(built.ok, "最密24字跨风格双面预算：" + type_id + "/" + style)
			if built.ok:
				check(int(built.stats.triangles) <= 3500 and int(built.stats.mesh_nodes) <= 4, "长文硬门禁")
				built.root.free()
	for text: String in ["OBR", "AB 12.-!&", " ABC ", "BBBBBBBBBBBBBBBBBBBBBBBB", "SEA MARKET", "OLD HARBOR"]:
		var recipe: Dictionary = Recipe.defaults("sign_fascia")
		recipe.text = text
		var built: Dictionary = Generator.build(recipe)
		check(built.ok, "真实文字build：" + text)
		if not built.ok: continue
		check(built.snapshot.text.input == text and built.root.get_meta("text_input") == text, "空格逐字保留")
		for face: Dictionary in built.stats.text:
			check(face.input == text and face.glyphs.size() == text.length(), "逐字账本")
			for glyph: Dictionary in face.glyphs:
				check(int(glyph.triangles) <= 128, "实测单字<=128")
		check(int(built.stats.mesh_nodes) <= 4, "长文合批")
		built.root.free()
	var orientation := Geometry.new(Recipe.defaults("sign_letters"))
	Glyphs.add(orientation, "F", Vector3.ZERO, 0.72, 1.0, 0.08)
	var stem_x := 0.0
	var arm_x := 0.0
	for part: Dictionary in orientation.parts:
		if str(part.name).ends_with("_fe"): stem_x = float(part.center[0])
		if str(part.name).ends_with("_a"): arm_x = float(part.center[0])
	check(stem_x > arm_x, "前轴-Z观察时F竖笔必须位于观众左侧+X，文字不可镜像")
	for character: String in ["O", "B", "R"]:
		var geometry := Geometry.new(Recipe.defaults("sign_letters"))
		Glyphs.add(geometry, character, Vector3.ZERO, 0.72, 1.0, 0.08)
		var bucket: Dictionary = geometry.buckets.SEA_Gloss
		for target: Vector2 in ([Vector2(0, 0)] if character == "O" else [Vector2(0, 0.24), Vector2(0, -0.24)] if character == "B" else [Vector2(0, 0.24)]):
			var hit: bool = false
			for i: int in range(0, bucket.indices.size(), 3):
				var polygon := PackedVector2Array()
				for j: int in 3:
					var point: Vector3 = Geometry.from_vec(bucket.vertices[int(bucket.indices[i + j])])
					polygon.append(Vector2(point.x, point.y))
				if absf((polygon[1] - polygon[0]).cross(polygon[2] - polygon[0])) > 0.000001 and Geometry2D.is_point_in_polygon(target, polygon): hit = true
			check(not hit, "OBR真洞：" + character + str(target))
	# 仅改隔离副本目录夹具，触发生产预算分支，随后恢复原字节。
	var original := FileAccess.get_file_as_string(Catalog.PATH)
	var fixture: Dictionary = Catalog.definitions()
	for entry: Dictionary in fixture.entries:
		entry.budget = 1
		entry.long_text_budget = 1
	var file := FileAccess.open(Catalog.PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture))
	file.close()
	for text: String in ["SEA", "SEA MARKET"]:
		var recipe: Dictionary = Recipe.defaults("sign_fascia")
		recipe.text = text
		var rejected: Dictionary = Generator.build(recipe)
		check(not rejected.ok and rejected.root == null and rejected.reason.contains("预算") and rejected.recipe.text == text, "真实超预算负例完整拒绝：" + text)
	file = FileAccess.open(Catalog.PATH, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	check(FileAccess.get_file_as_string(Catalog.PATH) == original, "隔离预算夹具恢复原字节")

func test_custom_variants() -> void:
	for text: String in ["SEA MARKET", "OLD HARBOR"]:
		var recipe: Dictionary = Recipe.defaults("sign_fascia")
		recipe.text = text
		var built: Dictionary = Generator.build(recipe)
		check(built.ok, "第97/98自定义变体：" + text)
		if built.ok:
			inspect_result(built, recipe)
			custom_rows.append({"type_id": recipe.type_id, "text": text, "stats": built.stats, "sha256": independent_fingerprint(built.root, false)})
			built.root.free()
	check(rows.size() + custom_rows.size() == 98, "96目录变体+2改字=98实测变体")

func test_colors_and_scale() -> void:
	var recipe: Dictionary = Recipe.defaults("tank_rect")
	var baseline: Dictionary = Generator.build(recipe)
	check(baseline.ok, "配色基线")
	if not baseline.ok: return
	recipe.colors = {"SEA_Matte": 3, "SEA_Metal": 7, "SEA_Gloss": 21, "SEA_Emission": 10}
	var recolored: Dictionary = Generator.build(recipe)
	check(recolored.ok and recolored.fingerprint == baseline.fingerprint, "换色不冒充几何")
	if recolored.ok: recolored.root.free()
	recipe.attachment_id = "different_identity_same_geometry"
	var renamed: Dictionary = Generator.build(recipe)
	check(renamed.ok and renamed.fingerprint == baseline.fingerprint, "attachment_id不作为几何指纹盐")
	if renamed.ok: renamed.root.free()
	for ratio: float in [0.75, 1.25]:
		recipe.scale = ratio
		var scaled: Dictionary = Generator.build(recipe)
		check(scaled.ok and scaled.fingerprint.geometry_sha256 != baseline.fingerprint.geometry_sha256, "比例端点烘入顶点")
		if scaled.ok:
			check(scaled.root.scale.is_equal_approx(Vector3.ONE), "比例不残留根变换")
			scaled.root.free()
	baseline.root.free()

func test_collision_switch() -> void:
	for entry: Dictionary in Catalog.entries():
		var type_id: String = entry.type_id
		for condition: String in Catalog.CONDITIONS:
			var recipe: Dictionary = Recipe.defaults(type_id)
			recipe.condition = condition
			recipe.collision_enabled = true
			var on: Dictionary = Generator.build(recipe)
			check(on.ok and int(on.stats.get("collision_shapes", 0)) > 0, "可选碰撞：" + type_id + "/" + condition)
			if not on.ok: continue
			recipe.collision_enabled = false
			var off: Dictionary = Generator.build(recipe)
			check(off.ok and int(off.stats.get("collision_shapes", -1)) == 0 and count_class(off.root, "CollisionShape3D") == 0, "关闭零节点")
			if off.ok:
				check(off.fingerprint == on.fingerprint, "碰撞开关不改几何")
				off.root.free()
			on.root.free()

func test_store() -> void:
	var recipe: Dictionary = Recipe.defaults("tank_tower_cone")
	recipe.attachment_id = "qa_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	recipe.condition = "ruined"
	var first: Dictionary = Store.export_revision(recipe, "user://building_attachments/qa_store")
	check(first.ok, "候选导出")
	if not first.ok: return
	var scene_hash: String = FileAccess.get_sha256(first.scene_path)
	var second: Dictionary = Store.export_revision(recipe, "user://building_attachments/qa_store")
	check(second.ok and int(second.revision) == int(first.revision) + 1, "重复保存新revision")
	check(FileAccess.get_sha256(first.scene_path) == scene_hash, "首revision不变")
	var loaded: Dictionary = Store.load_recipe(first.recipe_path)
	var canonical := JSON.new()
	check(canonical.parse(JSON.stringify(recipe, "", true, true)) == OK, "配方标准JSON可解析")
	check(loaded.ok and loaded.recipe == canonical.data, "JSON完整重载且数值语义等价")
	var packed: PackedScene = ResourceLoader.load(first.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(packed != null, "静态冷重载")
	if packed != null:
		var node: Node = packed.instantiate()
		check(scriptfree(node) and node.get_meta("text_input") == recipe.text, "重载静态metadata")
		check(count_class(node, "CollisionShape3D") == int(first.stats.collision_shapes), "重载碰撞")
		node.free()
	check(first.manifest.runtime_path == null and first.manifest.immutable, "不伪报接入")
	check(not Store.export_revision(recipe, "res://scenes/components/facilities/building_attachments/v001").ok, "候选不写正式库")
	check(not Store.export_revision(recipe, "user://building_attachments/../escape").ok, "导出防穿越")
	check(not Store.load_recipe("user://building_attachments/../escape").ok, "重载防穿越")

func test_symlink_storage() -> void:
	var base := "user://building_attachments/qa_symlink"
	check(Store.create_directory(base).is_empty(), "建立隔离symlink夹具目录")
	var recipe: Dictionary = Recipe.defaults("tank_rect")
	recipe.attachment_id = "original"
	var original: Dictionary = Store.export_revision(recipe, base)
	check(original.ok, "symlink负例原候选保存")
	if not original.ok: return
	var original_hash: String = FileAccess.get_sha256(original.scene_path)
	var script := """
import os,sys,pathlib,shutil
root=pathlib.Path(sys.argv[1]); source=pathlib.Path(sys.argv[2])
assert root.is_absolute() and '/sea-verification/' in str(root)
assert os.path.commonpath([root,source]) == str(root)
target=root/'target'; target.mkdir(); (target/'sentinel').write_bytes(b'UNCHANGED')
os.symlink(target,root/'base_link',target_is_directory=True)
(root/'id_case').mkdir(); os.symlink(target,root/'id_case'/'blocked',target_is_directory=True)
(root/'rev_case'/'blocked').mkdir(parents=True); os.symlink(target,root/'rev_case'/'blocked'/'revision_0001',target_is_directory=True)
for name in ['attachment.tscn','attachment.recipe.json','geometry.native.json','candidate_manifest.json']:
    case=root/('file_'+name.replace('.','_')); shutil.copytree(source,case)
    (case/name).rename(case/(name+'.retained'))
    os.symlink(target/'sentinel',case/name)
"""
	var output: Array = []
	var code: int = OS.execute(Store.python_path(), PackedStringArray(["-I", "-c", script, ProjectSettings.globalize_path(base), ProjectSettings.globalize_path(original.directory)]), output, true)
	check(code == 0, "仅隔离user目录创建真实base/id/revision/file符号链接")
	if code != 0: return
	recipe.attachment_id = "blocked"
	for candidate: String in [base + "/base_link", base + "/id_case", base + "/rev_case"]:
		var rejected: Dictionary = Store.export_revision(recipe, candidate)
		check(not rejected.ok, "真实符号链接导出拒绝：" + candidate)
	for name: String in ["attachment.tscn", "attachment.recipe.json", "geometry.native.json", "candidate_manifest.json"]:
		var candidate: String = base.path_join("file_" + name.replace(".", "_"))
		check(not Store.load_recipe(candidate).ok, "真实候选文件symlink重载拒绝：" + name)
		check(not Store.write_json(candidate.path_join(name), {"attack": true}).is_empty(), "真实symlink写入拒绝且不覆盖：" + name)
	check(FileAccess.get_sha256(original.scene_path) == original_hash and Store.load_recipe(original.directory).ok, "全部失败后原候选hash/可加载性不变")
	check(FileAccess.get_file_as_string(base + "/target/sentinel") == "UNCHANGED" and DirAccess.get_files_at(base + "/target").size() == 1, "链接目标无新文件/无覆盖")
	for text: String in ["{bad", "[]", "null"]:
		var path := base.path_join("malformed_%d.json" % text.length())
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		check(not Store.read_json(path).ok, "JSON.new.parse有界拒绝畸形根不制造引擎error")

func ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	return not space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 256)).is_empty()

func capsule_motion(world: Node3D, a: Vector3, b: Vector3, radius: float, height: float = -1.0) -> Dictionary:
	var actor := CharacterBody3D.new()
	actor.collision_layer = 0
	actor.collision_mask = 256
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = radius * 3.0 if height < 0 else height
	shape.shape = capsule
	actor.add_child(shape)
	world.add_child(actor)
	actor.position = a
	await physics_frame
	await process_frame
	var collision: KinematicCollision3D = actor.move_and_collide(b - a)
	var result := {"hit": collision != null, "from": str(a), "to": str(b), "actual": str(actor.position), "radius": radius, "height": capsule.height}
	actor.free()
	return result

func test_physics() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for type_id: String in ["tank_rect", "tank_tower_cone", "duct_straight", "pipe_elbow"]:
		for condition: String in Catalog.CONDITIONS:
			var recipe: Dictionary = Recipe.defaults(type_id)
			recipe.condition = condition
			recipe.collision_enabled = true
			var built: Dictionary = Generator.build(recipe)
			if not built.ok: continue
			var node: Node3D = built.root
			world.add_child(node)
			await physics_frame
			await process_frame
			var space := world.get_world_3d().direct_space_state
			var hit_count := 0
			var sampled_parts: Dictionary = {}
			for proxy: Dictionary in built.snapshot.collision_proxies:
				if sampled_parts.has(proxy.part): continue
				sampled_parts[proxy.part] = true
				var center := Vector3.ZERO
				for point: Array in proxy.points: center += Geometry.from_vec(point)
				center /= proxy.points.size()
				if ray(space, center + Vector3(0, 0, -10), center + Vector3(0, 0, 10)): hit_count += 1
			check(hit_count == sampled_parts.size() and hit_count > 0, type_id + "/" + condition + "存活壳体逐part射线真实挡")
			var target_part: Dictionary = built.source_parts[0]
			for part: Dictionary in built.source_parts:
				if part.name == "rect_back" or part.name == "tower_floor" or part.name == "straight_duct_side_-1" or part.name == "elbow_segment_0": target_part = part
			var center: Vector3 = Geometry.from_vec(target_part.center)
			var blocked: Dictionary = await capsule_motion(world, center + Vector3(0, 0, -10), center + Vector3(0, 0, 10), 0.05)
			check(blocked.hit, type_id + "/" + condition + "真实胶囊运动撞存活壳体")
			var character_blocked: Dictionary = await capsule_motion(world, center + Vector3(0, 0, -10), center + Vector3(0, 0, 10), 0.22, 1.30)
			check(character_blocked.hit, type_id + "/" + condition + "正式人物规格胶囊0.22/1.30确实被挡")
			var gap: Dictionary = {}
			if type_id == "duct_straight":
				var size: Vector3 = Geometry.from_vec(built.stats.bounds.size)
				var a := Vector3(0, size.y * 0.5, -size.z)
				var b := Vector3(0, size.y * 0.5, size.z)
				check(not ray(space, a, b), condition + "风管空腔射线未被凸包封死")
				gap = await capsule_motion(world, a, b, minf(size.x, size.y) * 0.06)
				check(not gap.hit, condition + "真实胶囊穿风管空腔")
			elif type_id == "tank_tower_cone":
				var size: Vector3 = Geometry.from_vec(built.stats.bounds.size)
				var a := Vector3(0, size.y * 0.20, -size.z)
				var b := Vector3(0, size.y * 0.20, size.z)
				check(not ray(space, a, b), condition + "水塔脚间射线不封闭")
				gap = await capsule_motion(world, a, b, 0.05)
				check(not gap.hit, condition + "胶囊穿水塔脚间")
				var player_gap: Dictionary = await capsule_motion(world, a, b, 0.22, 1.30)
				check(not player_gap.hit, condition + "正式人物胶囊穿水塔脚间未被整凸包封死")
				gap["character_capsule"] = player_gap
			elif type_id == "pipe_elbow":
				for part: Dictionary in built.source_parts:
					if part.name != "elbow_segment_0": continue
					var centerline: Vector3 = Geometry.from_vec(part.center)
					var basis := Basis.from_euler(Geometry.from_vec(part.rotation_euler))
					var length: float = float(part.dimensions[1])
					var a: Vector3 = centerline - basis.y * length * 0.45
					var b: Vector3 = centerline + basis.y * length * 0.45
					check(not ray(space, a, b), condition + "圆管管洞射线不封闭")
					gap = await capsule_motion(world, a, b, float(part.dimensions[0]) * 0.08)
					check(not gap.hit, condition + "胶囊穿圆管洞")
			physics_rows.append({"type_id": type_id, "condition": condition, "surviving_parts": sampled_parts.size(), "ray_hits": hit_count, "shell_capsule": blocked, "character_capsule": character_blocked, "gap_capsule": gap})
			node.free()
			await physics_frame
			await process_frame
			recipe.collision_enabled = false
			var off: Dictionary = Generator.build(recipe)
			if off.ok:
				world.add_child(off.root)
				await physics_frame
				await process_frame
				check(not ray(space, center + Vector3(0, 0, -10), center + Vector3(0, 0, 10)), "关闭后射线穿过：" + type_id + condition)
				var pass_through: Dictionary = await capsule_motion(world, center + Vector3(0, 0, -10), center + Vector3(0, 0, 10), 0.05)
				check(not pass_through.hit, "关闭后胶囊不挡：" + type_id + condition)
				off.root.free()
	world.free()
