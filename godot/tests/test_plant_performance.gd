extends SceneTree
## 只在正式隔离 runner 运行；静态保真与真实规模基准分别报告，不代表 Main 或移动/Web。
const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const Wind = preload("res://src/plant_authoring/wind_runtime.gd")
var checks := 0
var failures := 0
const SCALE_WARMUP_FRAMES := 30
const SCALE_SAMPLE_FRAMES := 90
# TIME_PROCESS按周期更新，至少跨两次更新，不能把同步构建峰值当稳定帧成本。
const SCALE_MIN_WINDOW_USEC := 2200000
var report := {"models": [], "leaf_checks": [], "visual": [], "image_metrics": [], "fps_measured": false,
	"scale_benchmark": {"scope": "批量共享候选场景；非当前Store动态导出默认实例路径，禁止据此宣称导出收益", "runs": [], "summary": []},
	"dynamic_instance_benchmark": {"scope": "当前动态候选的local_to_scene逐实例风策略；本机独立场景，非Main/移动/Web；内存PackedScene，不计磁盘I/O", "runs": [], "summary": []}}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("[plant-performance] FAIL " + label)

func _run() -> void:
	var old := Recipe.defaults()
	old.foliage_mode = "geometry"
	old.erase("leaf_geometry")
	_check(Recipe.validate(old).is_empty() and Recipe.normalized(old).leaf_geometry == "balanced", "旧配方补 balanced")
	old.leaf_geometry = "flat"
	_check(not Recipe.validate(old).is_empty(), "拒绝未知质量档")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/plant_performance"))
	for species in Recipe.SPECIES:
		var definition: Dictionary = Species.definitions()[species]
		_test_leaf(species, definition)
		var roots: Dictionary = {}
		var metrics: Dictionary = {}
		for profile in ["reference", "high", "balanced"]:
			var recipe := Recipe.defaults(species)
			recipe.foliage_mode = "geometry"
			recipe.leaf_geometry = profile
			var before := OS.get_static_memory_usage()
			var started := Time.get_ticks_usec()
			var built := Generator.build(recipe)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			_check(built.ok, species + "/" + profile + " 构建成功")
			if not built.ok:
				continue
			var retained := OS.get_static_memory_usage() - before
			roots[profile] = built.root
			var metric := {"species": species, "profile": profile, "seed": recipe.seed,
				"build_ms": elapsed, "cpu_retained_delta_bytes": retained,
				"process_static_peak_bytes": OS.get_static_memory_peak_usage(),
				"leaf_count": built.stats.leaf_count, "vertices": 0, "triangles": 0,
				"nodes": 0, "mesh_nodes": 0, "surfaces": 0, "cpu_array_payload_bytes": 0}
			_measure(built.root, metric)
			var warm_ms: Array[float] = []
			for repeat in 3:
				var warm_start := Time.get_ticks_usec()
				var warm := Generator.build(recipe)
				warm_ms.append((Time.get_ticks_usec() - warm_start) / 1000.0)
				warm.root.free()
			warm_ms.sort()
			metric.warm_build_ms_samples = warm_ms
			metric.warm_build_ms_median = warm_ms[1]
			metrics[profile] = metric
			report.models.append(metric)
			print("[plant-performance] MODEL " + JSON.stringify(metric))
		for profile in ["high", "balanced"]:
			_check(metrics[profile].leaf_count == metrics.reference.leaf_count, species + " 叶数一致 " + profile)
			_check(metrics[profile].nodes == metrics.reference.nodes and metrics[profile].surfaces == metrics.reference.surfaces, species + " 节点/表面不膨胀 " + profile)
			_check(metrics[profile].vertices < metrics.reference.vertices * 0.65, species + " 顶点至少降低35% " + profile)
			_check(metrics[profile].cpu_array_payload_bytes < metrics.reference.cpu_array_payload_bytes, species + " CPU数组减小 " + profile)
			_compare_foliage(roots.reference, roots[profile], definition, profile)
		_check(metrics.high.triangles == metrics.reference.triangles, species + " high保留原面数")
		_check(metrics.balanced.triangles < metrics.reference.triangles, species + " balanced减少内部三角形")
		if DisplayServer.get_name() != "headless":
			await _capture_pair(species, roots.reference, roots.balanced, false)
			var ref_leaf := _leaf_node(definition, "reference", species)
			var opt_leaf := _leaf_node(definition, "balanced", species)
			await _capture_pair(species, ref_leaf, opt_leaf, true)
			await _capture_pair(species, ref_leaf, opt_leaf, true, true)
			ref_leaf.free()
			opt_leaf.free()
		for node: Node in roots.values():
			node.free()
	report.fidelity_checks = checks
	report.fidelity_failures = failures
	await _scale_benchmark()
	report.shared_candidate_checks = checks
	report.shared_candidate_failures = failures
	await _scale_benchmark(true)
	report.checks = checks
	report.failures = failures
	report.renderer = RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "headless"
	report.memory_note = "cpu_array_payload为解码数组字节；retained是进程静态分配差值；peak为进程累计峰值，均不是GPU显存或独立单模型峰值"
	var file := FileAccess.open("res://outputs/plant_performance/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[plant-performance] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _single(definition: Dictionary, profile: String) -> Dictionary:
	var buffer := Generator._buffer()
	Geometry.append_leaf(Vector3.ZERO, Vector3.FORWARD, 0.36 * float(definition.leaf_width_ratio), 0.36 * float(definition.leaf_length_ratio), 0.0324,
		definition.leaf_shape, Vector3(0.0, -0.12, 0.08), 0.68, buffer.v, buffer.n, buffer.i, buffer.uv, 28,
		int(definition.leaf_subdivisions), float(definition.leaf_tip), float(definition.leaf_cup), profile)
	return buffer

func _test_leaf(species: String, definition: Dictionary) -> void:
	var reference := _single(definition, "reference")
	var wall_count := Geometry.leaf_outline(definition.leaf_shape).size() * int(definition.leaf_subdivisions) * 4
	var reference_curve_error := 0.0
	for profile in ["high", "balanced"]:
		var optimized := _single(definition, profile)
		var wall_error := 0.0
		for offset in wall_count:
			wall_error = maxf(wall_error, reference.v[reference.v.size() - wall_count + offset].distance_to(optimized.v[optimized.v.size() - wall_count + offset]))
		_check(wall_error == 0.0, species + "/" + profile + " 所有边壁采样逐位相等")
		var retained_error := 0.0
		var retained_normal_error := 0.0
		var retained_uv_error := 0.0
		for vertex in range(optimized.v.size() - wall_count):
			var nearest := INF
			var matched := 0
			for candidate in range(reference.v.size() - wall_count):
				var distance: float = reference.v[candidate].distance_squared_to(optimized.v[vertex])
				if distance < nearest:
					nearest = distance
					matched = candidate
			retained_error = maxf(retained_error, sqrt(nearest))
			retained_normal_error = maxf(retained_normal_error, reference.n[matched].distance_to(optimized.n[vertex]))
			retained_uv_error = maxf(retained_uv_error, reference.uv[matched].distance_to(optimized.uv[vertex]))
		_check(retained_error < 0.000001 and retained_normal_error < 0.000001 and retained_uv_error < 0.000001, species + "/" + profile + " 保留点解析位置/法线/色板UV一致")
		var edges: Dictionary = {}
		var degenerate := 0
		var wrong_winding := 0
		for face in range(0, optimized.i.size(), 3):
			var a: int = optimized.i[face]
			var b: int = optimized.i[face + 1]
			var c: int = optimized.i[face + 2]
			var cross: Vector3 = (optimized.v[c] - optimized.v[a]).cross(optimized.v[b] - optimized.v[a])
			if cross.length() < 1e-10:
				degenerate += 1
			if cross.dot(optimized.n[a] + optimized.n[b] + optimized.n[c]) < -1e-9:
				wrong_winding += 1
			for pair in [[a, b], [b, c], [c, a]]:
				var keys: Array[String] = [_position_key(optimized.v[pair[0]]), _position_key(optimized.v[pair[1]])]
				keys.sort()
				var key := "|".join(keys)
				edges[key] = int(edges.get(key, 0)) + 1
		var unclosed := 0
		for uses: int in edges.values():
			if uses != 2:
				unclosed += 1
		_check(unclosed == 0 and degenerate == 0 and wrong_winding == 0, species + "/" + profile + " 闭合无裂缝/退化/反面 " + str([unclosed, degenerate, wrong_winding]))
		var max_error := 0.0
		if profile == "high":
			var flesh_indices: int = reference.i.size() - wall_count / 4 * 6
			for index in reference.i.size():
				var mapped: int = index
				if index < flesh_indices:
					mapped = int(index / 6) * 3 + index % 3 + (int(flesh_indices / 2) if index % 6 >= 3 else 0)
				max_error = maxf(max_error, reference.v[reference.i[index]].distance_to(optimized.v[optimized.i[mapped]]))
			_check(max_error < 0.000001, species + " high逐三角形与reference一致")
		var topology := Geometry.leaf_topology(definition.leaf_shape, int(definition.leaf_subdivisions), float(definition.leaf_tip), float(definition.leaf_cup), profile)
		var curve_error := 0.0
		for face in range(0, topology.indices.size(), 3):
			var a: Vector2 = topology.points[topology.indices[face]]
			var b: Vector2 = topology.points[topology.indices[face + 1]]
			var c: Vector2 = topology.points[topology.indices[face + 2]]
			for u in 9:
				for v in range(9 - u):
					var weights := Vector3(1.0 - float(u + v) / 8.0, float(u) / 8.0, float(v) / 8.0)
					var point := a * weights.x + b * weights.y + c * weights.z
					var linear := Geometry._leaf_dome(a, definition.leaf_tip, definition.leaf_cup) * weights.x + Geometry._leaf_dome(b, definition.leaf_tip, definition.leaf_cup) * weights.y + Geometry._leaf_dome(c, definition.leaf_tip, definition.leaf_cup) * weights.z
					curve_error = maxf(curve_error, absf(linear - Geometry._leaf_dome(point, definition.leaf_tip, definition.leaf_cup)))
		if profile == "high":
			reference_curve_error = curve_error
		_check(curve_error <= reference_curve_error + Geometry.LEAF_CURVE_ERROR, species + "/" + profile + " 不放大原曲面采样误差 " + str(curve_error))
		report.leaf_checks.append({"species": species, "profile": profile, "vertices": optimized.v.size(), "triangles": optimized.i.size() / 3,
			"boundary_error_m": wall_error, "reference_vertex_error_m": max_error,
			"surface_error_in_thickness_units": curve_error, "unclosed_edges": unclosed})

func _position_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000000.0), roundi(point.y * 1000000.0), roundi(point.z * 1000000.0)]

func _measure(node: Node, metric: Dictionary) -> void:
	metric.nodes += 1
	if node is MeshInstance3D:
		metric.mesh_nodes += 1
		metric.surfaces += node.mesh.get_surface_count()
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			metric.vertices += arrays[Mesh.ARRAY_VERTEX].size()
			metric.triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
			for attribute in arrays:
				if attribute != null:
					metric.cpu_array_payload_bytes += attribute.to_byte_array().size()
	for child in node.get_children():
		_measure(child, metric)

func _compare_foliage(reference: Node3D, optimized: Node3D, definition: Dictionary, profile: String) -> void:
	var ref_stride: int = 40 + _single(definition, "reference").v.size()
	var opt_stride: int = 40 + _single(definition, profile).v.size()
	var wall_count: int = Geometry.leaf_outline(definition.leaf_shape).size() * int(definition.leaf_subdivisions) * 4
	var leaves := 0
	var max_position := 0.0
	var max_uv := 0.0
	var max_weight := 0.0
	var max_normal := 0.0
	for branch in reference.get_node("Leaves").get_children():
		var left: MeshInstance3D = branch.get_node("Foliage")
		var right: MeshInstance3D = optimized.get_node(reference.get_path_to(left))
		_check(branch.transform == right.get_parent().transform, "分枝位置保持")
		var a := left.mesh.surface_get_arrays(0)
		var b := right.mesh.surface_get_arrays(0)
		var count: int = a[Mesh.ARRAY_VERTEX].size() / ref_stride
		_check(b[Mesh.ARRAY_VERTEX].size() == count * opt_stride, "每枝叶数保持")
		var legacy_weights := Wind._weights(a, "Plant_leaf")
		for vertex in legacy_weights.size():
			max_weight = maxf(max_weight, absf(legacy_weights[vertex].r - a[Mesh.ARRAY_COLOR][vertex].r))
		for leaf in count:
			leaves += 1
			for offset in 40 + wall_count:
				var ai := leaf * ref_stride + (offset if offset < 40 else ref_stride - wall_count + offset - 40)
				var bi := leaf * opt_stride + (offset if offset < 40 else opt_stride - wall_count + offset - 40)
				max_position = maxf(max_position, a[Mesh.ARRAY_VERTEX][ai].distance_to(b[Mesh.ARRAY_VERTEX][bi]))
				max_uv = maxf(max_uv, a[Mesh.ARRAY_TEX_UV][ai].distance_to(b[Mesh.ARRAY_TEX_UV][bi]))
				max_weight = maxf(max_weight, absf(a[Mesh.ARRAY_COLOR][ai].r - b[Mesh.ARRAY_COLOR][bi].r))
				max_normal = maxf(max_normal, a[Mesh.ARRAY_NORMAL][ai].distance_to(b[Mesh.ARRAY_NORMAL][bi]))
		_check(bool(right.mesh.surface_get_material(0).get_shader_parameter("wind_vertex_weights")), "显式风权重材质协议")
	_check(max_position == 0.0 and max_uv == 0.0, "全部%d叶柄/边界位置与色板UV零差 %s" % [leaves, profile])
	_check(max_normal < 0.0002, "边壁/叶柄法线保持")
	_check(max_weight <= 1.0 / 255.0 + 0.00001, "风权重保持原公式（COLOR压缩容差） " + str(max_weight))
	var before: Array = []
	for branch in optimized.get_node("Leaves").get_children():
		before.append(branch.get_node("Foliage").mesh.surface_get_arrays(0))
	Wind.prepare(optimized)
	var index := 0
	for branch in optimized.get_node("Leaves").get_children():
		var visual: MeshInstance3D = branch.get_node("Foliage")
		var after := visual.mesh.surface_get_arrays(0)
		_check(not visual.has_meta("plant_wind_prepare_rejected"), "runtime首次准备接受")
		_check(before[index][Mesh.ARRAY_COLOR] == after[Mesh.ARRAY_COLOR] and before[index][Mesh.ARRAY_VERTEX] == after[Mesh.ARRAY_VERTEX] and before[index][Mesh.ARRAY_INDEX] == after[Mesh.ARRAY_INDEX], "runtime保留显式权重与索引位置")
		index += 1

func _leaf_node(definition: Dictionary, profile: String, species: String) -> Node3D:
	var node := Node3D.new()
	var buffer := _single(definition, profile)
	var reach := 0.01
	for point: Vector3 in buffer.v:
		reach = maxf(reach, point.length())
	for point: Vector3 in buffer.v:
		buffer.colors.append(Color(smoothstep(0.01, reach, point.length()), 0.0, 0.0, 1.0))
	var recipe := Recipe.defaults(species)
	recipe.foliage_mode = "geometry"
	Generator._emit(node, "Leaf", buffer, Generator._material("leaf", recipe, 1.0, 0.86))
	return node

func _capture_pair(species: String, reference: Node3D, optimized: Node3D, close: bool, edge_view: bool = false) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 760)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.17, 0.19)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.85, 0.93, 1.0)
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 1.5
	scene.add_child(light)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var bounds: AABB = Generator._stats(reference).bounds
	var target := bounds.get_center()
	camera.size = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * (1.55 if close else 1.18)
	camera.position = target + (Vector3(0.35, 1.4, 0.8) if close else Vector3(1.1, 0.6, 1.5)).normalized() * (2.0 if close else 20.0)
	if edge_view:
		camera.position = target + Vector3(1.8, 0.28, 0.4)
	camera.look_at(target)
	camera.current = true
	var images: Dictionary = {}
	for profile in ["reference", "balanced"]:
		var model: Node3D = reference if profile == "reference" else optimized
		scene.add_child(model)
		var materials := Wind.prepare(model)
		for time in [0.0, 1.75]:
			Wind.apply_sample(materials, time, 1.1, Vector2(0.86, 0.5), time > 0.0)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var name := "%s_%s_%s_%s" % [species, "edge" if edge_view else "close" if close else "whole", profile, str(time)]
			var path := "res://outputs/plant_performance/" + name + ".png"
			_check(image.save_png(path) == OK, "真实截图 " + name)
			images[profile + str(time)] = image
			report.visual.append(ProjectSettings.globalize_path(path))
		_check(images[profile + "0.0"].get_data() != images[profile + "1.75"].get_data(), "确定风帧真实像素变化 " + species + profile)
		scene.remove_child(model)
	for time in [0.0, 1.75]:
		var a: PackedByteArray = images["reference" + str(time)].get_data()
		var b: PackedByteArray = images["balanced" + str(time)].get_data()
		var error := 0.0
		var changed := 0
		for index in a.size():
			var delta := absi(int(a[index]) - int(b[index]))
			error += delta
			if delta > 8:
				changed += 1
		var result := {"species": species, "close": close, "edge_view": edge_view, "time": time, "mean_channel_error": error / float(a.size()), "channels_delta_over_8_ratio": float(changed) / a.size()}
		report.image_metrics.append(result)
		print("[plant-performance] IMAGE " + JSON.stringify(result))
		_check(result.mean_channel_error < 3.0 and result.channels_delta_over_8_ratio < 0.06, "同机位A/B像素变化有界 " + str(result))
	viewport.free()

func _scale_benchmark(dynamic_instances: bool = false) -> void:
	var benchmark: Dictionary = report.dynamic_instance_benchmark if dynamic_instances else report.scale_benchmark
	var counts := [1, 8, 16] if dynamic_instances else [1, 16, 64]
	var label := "DYNAMIC_INSTANCE" if dynamic_instances else "SHARED_CANDIDATE"
	var fixed_fps := false
	for argument in OS.get_cmdline_args():
		if argument == "--fixed-fps" or argument.begins_with("--fixed-fps="):
			fixed_fps = true
	_check(not fixed_fps, "真实规模基准禁止 --fixed-fps")
	_check(DisplayServer.get_name() != "headless", "真实规模基准必须使用真实渲染器")
	if fixed_fps or DisplayServer.get_name() == "headless":
		benchmark.skipped_reason = "需要真实渲染器且runner命令不得携带--fixed-fps"
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	OS.low_processor_usage_mode = false
	ProjectSettings.set_setting("application/run/low_processor_usage_mode_sleep_usec", 0)
	ProjectSettings.set_setting("application/run/low_processor_usage_mode_sleep_usec_unfocused", 0)
	ProjectSettings.set_setting("application/run/frame_delay_msec", 0)
	_check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "规模基准关闭vsync")
	benchmark.merge({"species": "birch", "seed": 24117, "resolution": [1280, 800], "msaa": "4x",
		"warmup_frames_per_run": SCALE_WARMUP_FRAMES, "minimum_sample_frames_per_run": SCALE_SAMPLE_FRAMES, "minimum_window_seconds": SCALE_MIN_WINDOW_USEC / 1000000.0,
		"rounds": 2, "order": ["reference,balanced", "balanced,reference"],
		"vsync_disabled": DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,
		"engine_max_fps": Engine.max_fps, "fixed_fps": false,
		"resource_policy": "build+prepare+apply_sample(0)+root.set_script(Wind)+owner pack；不改local_to_scene；每实例_ready/_process/sample_at走真实fallback" if dynamic_instances else "批量共享候选：显式关闭local_to_scene，共享Mesh/Material并整场apply_sample；不是Store默认动态导出路径",
		"wind": {"strength": 1.1, "direction": [0.86, 0.5], "recipe_strength": 0.35, "speed": 1.0},
		"cpu_note": "Performance.TIME_PROCESS为周期更新的全进程CPU处理监视器，采样含重复保持值，不是逐帧独立CPU计时；预热/采样各至少2.2秒排除构建峰值。wall_frame_ms为真实post_draw间隔",
		"gpu_note": "RenderingServer视口GPU计时为异步驱动报告，不是CPU时间推算；零值/常数/非有限值不采信，未用外部GPU分析器校准",
		"render_method": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(),
		"os": OS.get_name(), "processor": OS.get_processor_name(), "engine": Engine.get_version_info()})
	# 相同规模两档镜头一致；每组释放后再测下一组，动态策略最多16份实例资源。
	if dynamic_instances:
		_check(get_nodes_in_group(Wind.OWNER_GROUP).is_empty(), "动态实例统一使用真实fallback，无外部风owner")
		if not get_nodes_in_group(Wind.OWNER_GROUP).is_empty():
			benchmark.skipped_reason = "存在外部风owner，无法保证统一fallback"
			return
	for count in counts:
		for round_index in 2:
			var profiles := ["reference", "balanced"] if round_index == 0 else ["balanced", "reference"]
			for profile: String in profiles:
				var result := await _scale_run(count, profile, round_index, dynamic_instances)
				benchmark.runs.append(result)
				print("[plant-performance] " + label + " " + JSON.stringify(result.merged({"samples": "详见JSON报告"}, true)))
	for count in counts:
		var baseline: Dictionary = {}
		for run: Dictionary in benchmark.runs:
			if run.count != count:
				continue
			if baseline.is_empty():
				baseline = run
			else:
				_check(run.layout_sha256 == baseline.layout_sha256 and run.camera_transform == baseline.camera_transform and run.camera_size == baseline.camera_size, "规模同布局同镜头 %d" % count)
		for profile in ["reference", "balanced"]:
			var pooled: Dictionary = {}
			var all_gpu_valid := true
			var resource_counts: Array = []
			for run: Dictionary in benchmark.runs:
				if run.count == count and run.profile == profile:
					all_gpu_valid = all_gpu_valid and bool(run.gpu_ms.available)
					resource_counts.append({"round": run.round, "meshes": run.unique_mesh_resources, "materials": run.unique_material_resources})
					for metric in run.samples:
						if not pooled.has(metric): pooled[metric] = []
						pooled[metric].append_array(run.samples[metric])
			var summary := {"count": count, "profile": profile, "pooled_samples": pooled.wall_frame_ms.size(), "unique_resources_by_round": resource_counts}
			for metric in pooled:
				if metric != "gpu_ms_raw":
					summary[metric] = _distribution(pooled[metric])
			summary.gpu_ms = _distribution(pooled.gpu_ms_raw) if all_gpu_valid else {"available": false, "reason": "未测：至少一轮GPU计时无效，原始值仅供排查"}
			benchmark.summary.append(summary)
			print("[plant-performance] " + label + "_SUMMARY " + JSON.stringify(summary))
	report.fps_measured = true

func _scale_owner(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		_scale_owner(child, owner_root)

func _scale_resources(node: Node, meshes: Dictionary, materials: Dictionary, force_shared: bool = true) -> void:
	if node is MeshInstance3D and node.mesh != null:
		meshes[node.mesh.get_instance_id()] = node.mesh
		if force_shared:
			node.mesh.resource_local_to_scene = false
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material != null:
				if force_shared:
					material.resource_local_to_scene = false
				materials[material.get_instance_id()] = material
	for child in node.get_children():
		_scale_resources(child, meshes, materials, force_shared)

func _distribution(values: Array) -> Dictionary:
	if values.is_empty():
		return {"available": false}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in sorted:
		total += value
	return {"available": true, "min": sorted[0], "max": sorted[-1],
		"p50": sorted[clampi(int(ceil(sorted.size() * 0.50)) - 1, 0, sorted.size() - 1)],
		"p95": sorted[clampi(int(ceil(sorted.size() * 0.95)) - 1, 0, sorted.size() - 1)],
		"mean": total / sorted.size()}

func _scale_run(count: int, profile: String, round_index: int, dynamic_instances: bool = false) -> Dictionary:
	var recipe := Recipe.defaults("birch")
	recipe.foliage_mode = "geometry"
	recipe.leaf_geometry = profile
	var built := Generator.build(recipe)
	var source: Node3D = built.root
	var prepared_materials := Wind.prepare(source)
	if dynamic_instances:
		# 对齐Store._save_wind_scene的准备顺序，不改源码、资源local标志或脚本逻辑。
		Wind.apply_sample(prepared_materials, 0.0)
		source.set_script(Wind)
	prepared_materials.clear()
	var source_meshes: Dictionary = {}
	var source_materials: Dictionary = {}
	_scale_resources(source, source_meshes, source_materials, not dynamic_instances)
	_scale_owner(source, source)
	var packed := PackedScene.new()
	_check(packed.pack(source) == OK, "规模基准PackedScene打包 " + profile)
	var source_mesh_count := source_meshes.size()
	var source_material_count := source_materials.size()
	source.free()
	source_meshes.clear()
	source_materials.clear()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.17, 0.19)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.85, 0.93, 1.0)
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 1.5
	light.shadow_enabled = false
	scene.add_child(light)
	var side := int(ceil(sqrt(count)))
	var spacing := 6.5
	var extent := (side - 1) * spacing
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	var layouts := PackedVector3Array()
	var runtime_instances: Array[Node3D] = []
	var per_instance_resources: Array = []
	for index in count:
		var instance := packed.instantiate() as Node3D
		instance.position = Vector3((index % side) * spacing - extent * 0.5, 0.0, int(index / side) * spacing - extent * 0.5)
		layouts.append(instance.position)
		scene.add_child(instance)
		_scale_resources(instance, meshes, materials, not dynamic_instances)
		if dynamic_instances:
			runtime_instances.append(instance)
			var own_meshes: Dictionary = {}
			var own_materials: Dictionary = {}
			_scale_resources(instance, own_meshes, own_materials, false)
			var local_resources := true
			for resource: Resource in own_meshes.values() + own_materials.values():
				local_resources = local_resources and resource.resource_local_to_scene
			_check(local_resources, "动态实例保留Mesh/Material local_to_scene")
			_check(instance.get_script() == Wind and instance.is_processing(), "每实例真实WindRuntime脚本已自动运行")
			per_instance_resources.append({"meshes": own_meshes.size(), "materials": own_materials.size()})
	if dynamic_instances:
		_check(meshes.size() == source_mesh_count * count and materials.size() == source_material_count * count, "动态实例网格/材质独立，不跨实例共享 %s/%d" % [profile, count])
	else:
		_check(meshes.size() == source_mesh_count and materials.size() == source_material_count, "全部实例共享同一套网格与材质 %s/%d" % [profile, count])
	var wind_materials: Array[ShaderMaterial] = []
	for material: Material in materials.values():
		if material is ShaderMaterial:
			wind_materials.append(material)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = (extent + 14.0) * 1.2
	camera.far = 300.0
	var target := Vector3(0.0, 4.7, 0.0)
	camera.position = target + Vector3(0.32, 1.15, 1.5).normalized() * 130.0
	camera.look_at(target)
	camera.current = true
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var samples := {"wall_frame_ms": [], "cpu_process_ms": [], "viewport_render_cpu_ms": [], "gpu_ms_raw": [],
		"draw_calls": [], "primitives": [], "objects": []}
	var warmup_start := Time.get_ticks_usec()
	var previous := 0
	var sample_start := 0
	var warmup_frames := 0
	var sampled_frames := 0
	# 每轮风由真实时钟推进，相同初始相位、强度、方向；不使用固定delta或fixed-fps。
	while sample_start == 0 or sampled_frames < SCALE_SAMPLE_FRAMES or Time.get_ticks_usec() - sample_start < SCALE_MIN_WINDOW_USEC:
		await process_frame
		if not dynamic_instances:
			Wind.apply_sample(wind_materials, (Time.get_ticks_usec() - warmup_start) / 1000000.0, 1.1, Vector2(0.86, 0.5), true)
		# 动态路径完全交给每个实例的_process→_update_wind→sample_at；不调用整场apply_sample。
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if sample_start == 0:
			warmup_frames += 1
			if warmup_frames >= SCALE_WARMUP_FRAMES and now - warmup_start >= SCALE_MIN_WINDOW_USEC:
				sample_start = now
		else:
			sampled_frames += 1
			samples.wall_frame_ms.append((now - previous) / 1000.0)
			samples.cpu_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			samples.viewport_render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			samples.gpu_ms_raw.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			samples.draw_calls.append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
			samples.primitives.append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
			samples.objects.append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))
		previous = now
	var finished := Time.get_ticks_usec()
	var result := {"count": count, "profile": profile, "round": round_index + 1, "samples": samples,
		"warmup_frames": warmup_frames, "sample_frames": sampled_frames,
		"warmup_wall_ms": (sample_start - warmup_start) / 1000.0,
		"sample_wall_ms": (finished - sample_start) / 1000.0,
		"observed_throughput_fps": sampled_frames * 1000000.0 / (previous - sample_start),
		"resource_strategy": "dynamic_local_instances" if dynamic_instances else "shared_batch_candidate",
		"unique_mesh_resources": meshes.size(), "unique_material_resources": materials.size(),
		"per_instance_resources": per_instance_resources,
		"shared_mesh_resources": 0 if dynamic_instances else meshes.size(),
		"shared_material_resources": 0 if dynamic_instances else materials.size(),
		"layout_sha256": var_to_bytes(layouts).hex_encode().sha256_text(),
		"camera_transform": str(camera.transform), "camera_size": camera.size, "shadow_enabled": false,
		"cpu_static_bytes": OS.get_static_memory_usage(), "cpu_process_peak_bytes": OS.get_static_memory_peak_usage(),
		"window_focused": root.has_focus(), "gpu_timing_status": "未测：驱动没有提供可信非零变化样本"}
	if dynamic_instances:
		var min_time := INF
		var max_time := 0.0
		var wind_active := true
		for material: ShaderMaterial in wind_materials:
			var time := float(material.get_shader_parameter("local_time"))
			min_time = minf(min_time, time)
			max_time = maxf(max_time, time)
			wind_active = wind_active and bool(material.get_shader_parameter("preview_wind")) and time > 0.0
		_check(wind_active and max_time - min_time < 0.001, "每实例真实fallback已推进且相位一致")
		result.runtime_wind_time_min = min_time
		result.runtime_wind_time_max = max_time
		result.runtime_instances = runtime_instances.size()
		result.wind_source = "真实WindRuntime逐实例fallback；没有整场apply_sample"
	var gpu := _distribution(samples.gpu_ms_raw)
	var gpu_finite := true
	for value: float in samples.gpu_ms_raw:
		gpu_finite = gpu_finite and is_finite(value) and value > 0.0
	if gpu_finite and float(gpu.max) > float(gpu.min):
		result.gpu_timing_status = "可用：RenderingServer异步视口GPU计时，未经外部分析器校准"
		result.gpu_ms = gpu
	else:
		result.gpu_ms = {"available": false}
	for metric in samples:
		if metric != "gpu_ms_raw":
			result[metric] = _distribution(samples[metric])
	_check(float(result.draw_calls.min) > 0.0 and float(result.primitives.min) > 0.0 and float(result.objects.min) > 0.0, "规模场景真实提交非零")
	_check(samples.wall_frame_ms.size() >= SCALE_SAMPLE_FRAMES and float(result.wall_frame_ms.min) > 0.0, "真实稳定区间帧样本完整")
	result.stable_window_valid = float(result.wall_frame_ms.max) < 1000.0
	_check(result.stable_window_valid, "稳定区间无超过1秒的挂起/外部中断；不丢弃异常样本")
	if round_index == 0:
		# 截图只在采样结束后读取，避免GPU读回污染稳定区间。
		var prefix := "dynamic_instance_birch" if dynamic_instances else "scale_birch"
		var path := "res://outputs/plant_performance/%s_%d_%s.png" % [prefix, count, profile]
		_check(viewport.get_texture().get_image().save_png(path) == OK, "规模场景无overlay实拍")
		result.screenshot = ProjectSettings.globalize_path(path)
	RenderingServer.viewport_set_measure_render_time(rid, false)
	viewport.free()
	wind_materials.clear()
	meshes.clear()
	materials.clear()
	packed = null
	built.clear()
	await process_frame
	await RenderingServer.frame_post_draw
	return result
