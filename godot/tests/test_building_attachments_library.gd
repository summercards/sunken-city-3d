extends SceneTree
## 已审核交付库的只读独立加载，不执行候选文件；仅在隔离副本与user目录重存。
const BASE := "res://scenes/components/facilities/building_attachments/v002"
const Catalog = preload("res://src/building_attachments/catalog.gd")
const Recipe = preload("res://src/building_attachments/recipe.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const Geometry = preload("res://src/building_attachments/geometry.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var file_hashes: Dictionary = {}
var totals := {"loaded_scenes": 0, "reloaded_scenes": 0, "triangles": 0, "vertices": 0, "surfaces": 0, "collision_shapes": 0, "default_collision_variants": 0}

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL [attachment-library] ", label)

func json_file(path: String) -> Dictionary:
	var parser := JSON.new()
	var error: Error = parser.parse(FileAccess.get_file_as_string(path))
	check(error == OK and parser.data is Dictionary, "JSON对象可解析：" + path)
	return parser.data if error == OK and parser.data is Dictionary else {}

func audited_path(relative: String) -> String:
	check(not relative.begins_with("/") and not relative.contains("..") and not relative.contains(":"), "交付路径相对且无穿越：" + relative)
	return BASE.path_join(relative)

func static_tree(node: Node) -> bool:
	if node.get_script() != null or node is CSGShape3D or (node is MeshInstance3D and node.mesh is TextMesh): return false
	for child: Node in node.get_children():
		if not static_tree(child): return false
	return true

func count_class(node: Node, type: String) -> int:
	var count := 1 if node.is_class(type) else 0
	for child: Node in node.get_children(): count += count_class(child, type)
	return count

func mesh_fingerprint(node: Node3D) -> String:
	var faces: Array[String] = []
	for child: Node in node.get_children():
		if not child is MeshInstance3D: continue
		for surface: int in child.mesh.get_surface_count():
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index: int in range(0, indices.size(), 3):
				var points: Array[String] = []
				for j: int in 3:
					var point: Vector3 = vertices[indices[index + j]]
					points.append("%d,%d,%d" % [roundi(point.x * 100000), roundi(point.y * 100000), roundi(point.z * 100000)])
				points.sort()
				faces.append("/".join(points))
	faces.sort()
	return "|".join(faces).sha256_text()

func same_recipe(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_recipe(a[key], b[key]): return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return is_finite(float(a)) and is_finite(float(b)) and absf(float(a) - float(b)) <= 0.000000001
	return typeof(a) == typeof(b) and a == b

func inspect(node: Node3D, native: Dictionary, recipe: Dictionary, record: Dictionary) -> Dictionary:
	var label: String = str(recipe.type_id) + "/" + str(recipe.condition)
	check(static_tree(node), label + "全层级无脚本/CSG/TextMesh")
	check(node.transform.is_equal_approx(Transform3D.IDENTITY), label + "根恒等")
	check(same_recipe(node.get_meta("attachment_recipe", {}), recipe) and same_recipe(recipe, native.recipe), label + "静态metadata/native/recipe逐字段语义一致（有限数值1e-9容差，字符串bool键不变）")
	check(node.get_meta("attachment_type_id", "") == recipe.type_id and node.get_meta("attachment_condition", "") == recipe.condition, label + "身份元数据一致")
	check(node.get_meta("visual_only", false) and node.get_meta("collision_enabled") == recipe.collision_enabled, label + "显式用途与碰撞开关metadata")
	var result := {"triangles": 0, "vertices": 0, "surfaces": 0, "mesh_nodes": 0, "collision_shapes": count_class(node, "CollisionShape3D")}
	var bounds := AABB()
	var initialized := false
	for child: Node in node.get_children():
		if not child is MeshInstance3D: continue
		result.mesh_nodes += 1
		check(child.mesh is ArrayMesh and child.transform.is_equal_approx(Transform3D.IDENTITY), label + "静态ArrayMesh根空间")
		var source: Dictionary = {}
		for candidate: Dictionary in native.meshes:
			if candidate.material_role == str(child.name): source = candidate
		check(not source.is_empty(), label + "角色mesh在native中存在：" + str(child.name))
		if source.is_empty(): continue
		check(child.mesh.get_surface_count() == 1, label + "每角色单surface")
		for surface: int in child.mesh.get_surface_count():
			result.surfaces += 1
			var material: Material = child.mesh.surface_get_material(surface)
			var expected_path: String = Catalog.definitions().materials[str(child.name)]
			check(material != null and material.resource_path == expected_path and material == load(expected_path), label + "正式外链共享材质identity")
			if material is ShaderMaterial:
				var texture: Texture2D = material.get_shader_parameter("palette")
				check(texture != null and texture.resource_path == str(Catalog.definitions().palette_texture) and texture == load(str(Catalog.definitions().palette_texture)), label + "纹理外链同一资源")
			else: check(false, label + "四共享角色须为正式ShaderMaterial")
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			result.triangles += indices.size() / 3
			result.vertices += vertices.size()
			check(vertices.size() == source.vertices.size() and indices == PackedInt32Array(source.indices) and normals.size() == vertices.size() and uv.size() == vertices.size(), label + "真实数组长度/索引匹配native")
			var bad_vertex := 0
			var bad_uv := 0
			var bad_normal := 0
			for i: int in vertices.size():
				if not vertices[i].is_finite() or vertices[i].distance_to(Geometry.from_vec(source.vertices[i])) > 0.000001: bad_vertex += 1
				if not initialized:
					bounds = AABB(vertices[i], Vector3.ZERO)
					initialized = true
				bounds = bounds.expand(vertices[i])
				if not normals[i].is_finite() or normals[i].dot(Geometry.from_vec(source.normals[i])) < 0.999: bad_normal += 1
				var expected_uv := Vector2(float(source.uv[i][0]), float(source.uv[i][1]))
				if uv[i].distance_to(expected_uv) > 0.00001: bad_uv += 1
			for i: int in range(0, indices.size(), 3):
				var a: Vector2 = uv[indices[i]] * 512
				var b: Vector2 = uv[indices[i + 1]] * 512
				var c: Vector2 = uv[indices[i + 2]] * 512
				if absf((b-a).cross(c-a)) < 1: bad_uv += 1
				var cell := Vector2(floor(a.x / 64), floor(a.y / 64)) * 64
				for point: Vector2 in [a,b,c]:
					var local: Vector2 = point - cell
					if local.x < 8 or local.x > 56 or local.y < 8 or local.y > 56: bad_uv += 1
				var cross: Vector3 = (vertices[indices[i+1]]-vertices[indices[i]]).cross(vertices[indices[i+2]]-vertices[indices[i]])
				if cross.length() < 0.000000001: bad_vertex += 1
				if cross.normalized().dot(normals[indices[i]]) > -0.98: bad_normal += 1
			check(bad_vertex == 0, label + "静态顶点/native一致且无退化")
			check(bad_uv == 0, label + "静态UV/native一致且8px内缩有面积")
			check(bad_normal == 0, label + "静态外法线/native一致")
	check(bounds.position.distance_to(Geometry.from_vec(native.bounds.position)) < 0.00001 and bounds.size.distance_to(Geometry.from_vec(native.bounds.size)) < 0.00001, label + "真实bounds/native一致")
	for key: String in ["triangles", "vertices", "surfaces", "mesh_nodes", "collision_shapes"]:
		check(int(result[key]) == int(record.stats[key]), label + "真实统计匹配manifest：" + key)
	var native_hash: String = Generator.fingerprints(native).geometry_sha256
	check(mesh_fingerprint(node) == native_hash and native_hash == str(record.stats.fingerprint.geometry_sha256), label + "静态/native/manifest几何指纹一致")
	var body: StaticBody3D = node.get_node_or_null("AttachmentCollision")
	if recipe.collision_enabled:
		check(body != null and count_class(node, "StaticBody3D") == 1 and body.collision_layer == 256 and body.collision_mask == 0, label + "默认碰撞layer256/mask0")
		check(result.collision_shapes == native.collision_proxies.size(), label + "静态碰撞代理数量匹配实际残体")
		if body != null:
			for i: int in body.get_child_count():
				var shape: CollisionShape3D = body.get_child(i)
				var proxy: Dictionary = native.collision_proxies[i]
				var bad := 0
				check(shape.shape is ConvexPolygonShape3D and shape.get_meta("source_part") == proxy.part, label + "proxy类与部件对应")
				if shape.shape is ConvexPolygonShape3D:
					var points: PackedVector3Array = shape.shape.points
					check(points.size() == proxy.points.size(), label + "凸代理顶点数量")
					for j: int in mini(points.size(), proxy.points.size()):
						if points[j].distance_to(Geometry.from_vec(proxy.points[j])) > 0.000001: bad += 1
					check(bad == 0, label + "凸代理真实点逐项匹配")
	else: check(body == null and result.collision_shapes == 0, label + "默认关闭真的无body/shape")
	return result

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		quit(1)
		return
	var delivery: Dictionary = json_file(BASE.path_join("delivery_manifest.json"))
	var library: Dictionary = json_file(BASE.path_join("library_manifest.json"))
	check(delivery.get("runtime_world_installed") == false and library.get("runtime_world_installation") == false, "只验authoring library，不声称Main接入")
	check(delivery.records.size() == 96 and Catalog.entries().size() == 32, "交付32类型96静态记录")
	for item: Dictionary in delivery.files:
		var path: String = audited_path(item.path)
		file_hashes[path] = FileAccess.get_sha256(path)
		check(file_hashes[path] == item.sha256 and FileAccess.get_file_as_bytes(path).size() == int(item.bytes), "交付原件hash/bytes：" + str(item.path))
	var identities: Dictionary = {}
	for entry: Dictionary in Catalog.entries():
		var registration: Dictionary = json_file(BASE.path_join(str(entry.type_id)).path_join("registration_manifest.json"))
		check(registration.library_manifest_sha256 == delivery.original_library_manifest.sha256 and registration.runtime_world_installed == false, "32类型登记回链原manifest且非世界安装")
	var out := "user://building_attachments/library_roundtrip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for record: Dictionary in delivery.records:
		var identity: String = str(record.type_id) + "/" + str(record.condition)
		check(not identities.has(identity) and Catalog.CONDITIONS.has(record.condition) and not Catalog.get_entry(record.type_id).is_empty(), "交付身份唯一且目录有效：" + identity)
		identities[identity] = true
		for role: String in ["scene", "native_geometry", "recipe"]:
			var item: Dictionary = record[role]
			var path: String = audited_path(item.path)
			check(path == item.resource_path and FileAccess.get_sha256(path) == item.sha256, identity + "records实际路径与hash：" + role)
		var recipe: Dictionary = json_file(audited_path(record.recipe.path))
		var native: Dictionary = json_file(audited_path(record.native_geometry.path))
		check(Recipe.validate(recipe).is_empty() and recipe.type_id == record.type_id and recipe.condition == record.condition, identity + "recipe有效且匹配")
		var packed: PackedScene = ResourceLoader.load(audited_path(record.scene.path), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(packed != null, identity + "可信正式静态TSCN独立冷加载")
		if packed == null: continue
		var node: Node3D = packed.instantiate() as Node3D
		check(node != null, identity + "实例为Node3D")
		if node == null: continue
		var stats: Dictionary = inspect(node, native, recipe, record)
		totals.loaded_scenes += 1
		for key: String in ["triangles", "vertices", "surfaces", "collision_shapes"]: totals[key] += int(stats[key])
		if recipe.collision_enabled: totals.default_collision_variants += 1
		var current: Dictionary = Generator.build(recipe)
		check(current.ok, identity + "当前Generator对照构建")
		if current.ok:
			check(mesh_fingerprint(node) == current.fingerprint.geometry_sha256, identity + "正式静态与当前生成器几何一致（不以Store哈希冒充几何变更）")
			current.root.free()
		var opposite: Dictionary = recipe.duplicate(true)
		opposite.collision_enabled = not recipe.collision_enabled
		var switched: Dictionary = Generator.build(opposite)
		check(switched.ok, identity + "碰撞开关对照构建")
		if switched.ok:
			check(mesh_fingerprint(switched.root) == mesh_fingerprint(node) and (count_class(switched.root, "CollisionShape3D") > 0) == bool(opposite.collision_enabled), identity + "开关不改视觉且真实shape跟随")
			switched.root.free()
		var saved := PackedScene.new()
		var target: String = out.path_join(str(record.type_id) + "__" + str(record.condition) + ".tscn")
		check(saved.pack(node) == OK and ResourceSaver.save(saved, target) == OK, identity + "只在隔离user重存")
		node.free()
		var reloaded: PackedScene = ResourceLoader.load(target, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		check(reloaded != null, identity + "重存后冷重载")
		if reloaded != null:
			var again: Node3D = reloaded.instantiate()
			inspect(again, native, recipe, record)
			again.free()
			totals.reloaded_scenes += 1
		rows.append({"type_id": record.type_id, "condition": record.condition, "stats": stats, "scene": record.scene.resource_path, "roundtrip": target})
	check(identities.size() == 96 and totals.loaded_scenes == 96 and totals.reloaded_scenes == 96, "96独立静态load及隔离roundtrip全部完成，不声称新生成96独特模型")
	check(totals.default_collision_variants == 15, "五类重设备三状态默认碰撞共15件")
	for path: String in file_hashes: check(FileAccess.get_sha256(path) == file_hashes[path], "静态原件字节未修改：" + path)
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "generator_version": Generator.GENERATOR_VERSION, "scope": "可信正式v002静态库独立加载与隔离user重存；未Main/未Blender/非新模型生成验收", "totals": totals, "variants": rows, "real_rendering": false, "expected_errors": [], "exit_code": 0 if failures.is_empty() else 1}
	var file := FileAccess.open("res://outputs/attachment_library_report.json", FileAccess.WRITE)
	if file == null:
		printerr("FAIL [attachment-library] 报告写入失败")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("[attachment-library] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
