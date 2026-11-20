@tool
extends SceneTree

const Data = preload("res://addons/building_workshop/surface_paint_data.gd")
const Cache = preload("res://addons/building_workshop/surface_paint_surface.gd")
const Output = preload("res://addons/building_workshop/surface_paint_output.gd")
const Library = preload("res://src/ambient/vegetation/library.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var artifacts: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	rows.append({"label": label, "passed": value, "detail": str(detail)})
	if not value:
		failures.append(label)
		printerr("FAIL [surface-paint] ", label, " ", detail)

func box(parent: Node3D, label: String, center: Vector3, dimensions: Vector3 = Vector3(4, 2, 4)) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	parent.add_child(node)
	node.position = center
	return node

func command(kind: String, origin: Vector3, direction: Vector3, id: String = "logic") -> Dictionary:
	var brush := Data.brush_defaults(kind)
	brush.radius = 0.35
	return {"brush": brush, "origin": origin, "direction": direction, "stroke_id": id, "sequence": 0, "seed": 21, "elapsed": 1.0}

func capture_layer(host: Node3D, layer: Node3D, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 700)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	host.reparent(world)
	host.add_child(layer)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5, 4, 7)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.12, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://outputs/surface_logic_" + label + ".png"
	check(viewport.get_texture().get_image().save_png(path) == OK, "真实表面派生PNG " + label)
	artifacts.append(ProjectSettings.globalize_path(path))
	host.remove_child(layer)
	host.reparent(root)
	viewport.free()

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		quit(1)
		return
	var host := Node3D.new()
	root.add_child(host)
	var visual := Node3D.new()
	visual.name = "GeneratedVisual"
	host.add_child(visual)
	var structure := box(visual, "Structure", Vector3.ZERO)
	await process_frame
	var cache = Cache.new()
	check(cache.build_cache(host).ok, "真实Box三角缓存")
	var empty := Data.empty_snapshot()
	check(Data.validate(empty).is_empty(), "v1 host_local空快照")
	for key: String in ["schema_version", "type", "coordinate_space", "layer_transform", "stamps"]:
		var bad := empty.duplicate(true)
		bad.erase(key)
		check(not Data.validate(bad).is_empty(), "schema缺字段拒绝 " + key)
	var extra := empty.duplicate(true)
	extra.unknown = true
	check(not Data.validate(extra).is_empty(), "schema未知字段拒绝")
	for key: String in Data.PARAM_BOUNDS:
		for value: float in [float(Data.PARAM_BOUNDS[key][0]), float(Data.PARAM_BOUNDS[key][1])]:
			var brush := Data.brush_defaults()
			brush[key] = value
			check(Data.validate_brush(brush).is_empty(), "brush边界合法 " + key + str(value))
		for value: float in [float(Data.PARAM_BOUNDS[key][0]) - 0.001, float(Data.PARAM_BOUNDS[key][1]) + 0.001, NAN, INF]:
			var brush := Data.brush_defaults()
			brush[key] = value
			check(not Data.validate_brush(brush).is_empty(), "brush越界/非有限拒绝 " + key + str(value))
	var grass: Dictionary = cache.apply_brush_command(empty, command("grass", Vector3(0.4, 5, 0.3), Vector3.DOWN))
	check(grass.get("ok", false) and grass.get("added", 0) > 0, "grass真实上朝面生效", grass)
	if grass.get("ok", false) and not grass.snapshot.stamps.is_empty():
		var snapshot: Dictionary = grass.snapshot
		check(empty.stamps.is_empty() and Data.validate(snapshot).is_empty(), "刷涂不改输入快照")
		var normals_ok := true
		for stamp: Dictionary in snapshot.stamps:
			normals_ok = normals_ok and Data.vec(stamp.normal).dot(Vector3.UP) >= 0.7
		check(normals_ok, "grass全部朝上法线")
		var duplicate := snapshot.duplicate(true)
		duplicate.stamps.append(duplicate.stamps[0].duplicate(true))
		check(not Data.validate(duplicate).is_empty(), "duplicate稳定ID拒绝")
		for key: String in ["center_world", "center_local", "normal", "orientation", "scale"]:
			var bad := snapshot.duplicate(true)
			bad.stamps[0][key][0] = NAN
			check(not Data.validate(bad).is_empty(), "印记nonfinite拒绝 " + key)
		var encoded := Data.serialize(snapshot)
		check(encoded.ok and Data.deserialize(encoded.json).ok and Data.fingerprint(Data.deserialize(encoded.json).snapshot) == Data.fingerprint(snapshot), "JSON序列化指纹往返")
		var erase_cmd := command("erase", Vector3(0.4, 5, 0.3), Vector3.DOWN)
		var erased: Dictionary = cache.apply_brush_command(snapshot, erase_cmd)
		check(erased.get("ok", false) and erased.get("removed", 0) == snapshot.stamps.size() and erased.snapshot.stamps.is_empty(), "erase相同球对称擦除全部草", erased)
		var built := Output.build_from_snapshot(snapshot, host)
		check(built.ok, "grass原资源输出", built.get("reason"))
		if built.ok:
			var count := 0
			for batch: Node in built.root.get_children():
				check(batch is MultiMeshInstance3D, "草合并为MultiMesh")
				if batch is MultiMeshInstance3D:
					count += batch.multimesh.instance_count
					check(batch.multimesh.mesh == Library.mesh("grass_soft") and batch.material_override == Library.material("grass_soft"), "保留Library原草mesh/material引用")
					var custom_ok: bool = batch.multimesh.use_custom_data
					for index: int in batch.multimesh.instance_count:
						var custom: Color = batch.multimesh.get_instance_custom_data(index)
						custom_ok = custom_ok and custom.r >= 0 and custom.r <= 1 and custom.g >= 0 and custom.g <= 1 and is_equal_approx(custom.b, 1.0) and is_equal_approx(custom.a, 1.0)
					check(custom_ok and (batch.material_override as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM"), "INSTANCE_CUSTOM随机风契约", {"custom": batch.multimesh.get_instance_custom_data(0), "use_custom_data": batch.multimesh.use_custom_data})
			check(count == snapshot.stamps.size() and built.instances == count and built.chunks == built.root.get_child_count(), "草输出实例/合并块计数")
			check(Data.capture(built.root) == snapshot, "派生层capture只取独立快照")
			await capture_layer(host, built.root, "grass")
			built.root.free()
	check(not cache.apply_brush_command(empty, command("grass", Vector3(0, 0, 5), Vector3.FORWARD)).ok, "草拒绝竖直面")
	var textures := {"moss_atlas": load("res://assets/textures/vegetation/surface_moss_tile_256.png"), "vine_atlas": load("res://assets/textures/vegetation/surface_vine_strip_256.png")}
	for kind: String in ["moss", "vine"]:
		var result: Dictionary = cache.apply_brush_command(empty, command(kind, Vector3(0.4, 0.3, 5), Vector3.FORWARD, kind))
		check(result.get("ok", false) and result.get("added", 0) == 1, kind + "一次真实外墙落笔仅一个印记", result)
		check(not cache.apply_brush_command(empty, command(kind, Vector3.ZERO, Vector3.BACK)).ok, kind + "拒绝从内部穿背面")
		if not result.get("ok", false): continue
		var built := Output.build_from_snapshot(result.snapshot, host, textures)
		check(built.ok, kind + "真实纹理裁切输出", built.get("reason"))
		if not built.ok: continue
		var ids := 0
		var vertices := 0
		var uv_ok := true
		var crosses_diagonal := Vector2i.ZERO
		for batch: Node in built.root.get_children():
			check(batch is MeshInstance3D and batch.mesh is ArrayMesh, kind + "按空间块合并而非逐印记节点")
			ids += batch.get_meta("surface_paint_stamp_ids").size()
			var arrays: Array = batch.mesh.surface_get_arrays(0)
			vertices += arrays[Mesh.ARRAY_VERTEX].size()
			var mat: StandardMaterial3D = batch.material_override
			uv_ok = uv_ok and mat.texture_repeat == (kind == "moss") and mat.albedo_texture == textures[result.snapshot.stamps[0].source]
			for i: int in arrays[Mesh.ARRAY_TEX_UV].size():
				var uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][i]
				var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i] + batch.position
				if p.y > p.x * 0.5 + 0.001: crosses_diagonal.x += 1
				if p.y < p.x * 0.5 - 0.001: crosses_diagonal.y += 1
				var expected := Vector2(p.x, -p.y) / Output.MOSS_TILE_METRES if kind == "moss" else Vector2(0.5 + (p.x - 0.4) / 0.35, (0.3 - p.y) / 0.7)
				uv_ok = uv_ok and uv.distance_to(expected) < 0.0001 and absf(p.z - 2.002) < 0.0001
		check(uv_ok, kind + "真实顶点：统一米制平铺或单图重力方向，贴面无悬空")
		if kind == "moss": check(crosses_diagonal.x > 0 and crosses_diagonal.y > 0, "单苔印记连续跨过两个三角的公共边")
		check(ids == result.snapshot.stamps.size() and vertices == built.patch_vertices and built.chunks == built.root.get_child_count(), kind + "merged patch IDs/顶点/块计数")
		var erased: Dictionary = cache.apply_brush_command(result.snapshot, command("erase", Vector3(0.4, 0.3, 5), Vector3.FORWARD))
		check(erased.get("ok", false) and erased.snapshot.stamps.is_empty(), kind + "erase球对称")
		built.root.free()
		var second := command(kind, Vector3(0.85, 0.3, 5), Vector3.FORWARD, kind + "_next")
		var extended: Dictionary = cache.apply_brush_command(result.snapshot, second)
		check(extended.get("added", 0) == 1 and extended.snapshot.stamps.size() == 2, kind + "横向拖刷可连续落第二笔")
		if extended.get("ok", false):
			var preview_built := Output.build_from_snapshot(extended.snapshot, host, textures)
			check(preview_built.ok, kind + "连续贴面可合批输出")
			if preview_built.ok:
				await capture_layer(host, preview_built.root, kind)
				preview_built.root.free()
	for label: String in ["Vegetation", "Attachments"]:
		var excluded := box(visual, label, Vector3(0.4, 3, 0.3))
		check(cache.build_cache(host).meshes == 1, "缓存排除 " + label)
		var hit: Dictionary = cache.apply_brush_command(empty, command("grass", Vector3(0.4, 8, 0.3), Vector3.DOWN))
		check(hit.get("ok", false) and is_equal_approx(hit.center_world.y, 1.0), label + "不作为受涂/遮挡面")
		excluded.free()
	for label: String in ["Glass", "Transparent"]:
		var blocker := box(visual, label, Vector3(0.4, 3, 0.3))
		if label == "Transparent":
			var material := StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.4
			blocker.material_override = material
		check(cache.build_cache(host).ok, label + "仍保留遮挡几何")
		check(not cache.apply_brush_command(empty, command("grass", Vector3(0.4, 8, 0.3), Vector3.DOWN)).ok, label + "排除受涂且不穿透")
		blocker.free()
	var nested := Node3D.new()
	nested.name = "NestedTransform"
	visual.add_child(nested)
	nested.transform = Transform3D(Basis(Vector3.UP, 0.31).scaled(Vector3(1.2, 0.7, 1.5)), Vector3(2, 0.3, -1))
	visual.remove_child(structure)
	nested.add_child(structure)
	structure.transform = Transform3D(Basis(Vector3.RIGHT, 0.17).scaled(Vector3(0.8, 1.4, 1.1)), Vector3(0.1, 0.2, 0.3))
	structure.name = "Structure"
	var nested_build: Dictionary = cache.build_cache(host)
	check(nested_build.ok, "nested nonuniform初始缓存", nested_build)
	var fingerprint: String = cache.fingerprint()
	host.transform = Transform3D(Basis(Vector3.UP, -0.61).scaled(Vector3(1.8, 0.6, 1.3)), Vector3(27, -5, 16))
	check(cache.build_cache(host).ok and cache.fingerprint() == fingerprint, "nested nonuniform宿主变换不改变局部网格指纹")
	nested.position.x += 0.01
	check(cache.build_cache(host).ok and cache.fingerprint() != fingerprint, "nested局部变换改变指纹")
	host.free()
	var report := {"suite": "surface-paint", "checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "直接逻辑与真实派生层渲染，非GUI；无全局风owner", "rows": rows, "artifacts": artifacts, "expected_failures": [], "not_tested": ["真实GUI由editor-workshop-surface执行", "苔图来源仍pending，不作来源验收"]}
	var file := FileAccess.open("res://outputs/surface_paint_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[surface-paint] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
