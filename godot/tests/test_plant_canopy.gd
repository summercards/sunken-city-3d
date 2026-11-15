extends SceneTree
## 专项只由隔离 runner 调度；真实渲染与基准不得和其它渲染任务并发。
const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")
const Store = preload("res://src/plant_authoring/store.gd")
const Wind = preload("res://src/plant_authoring/wind_runtime.gd")
const Foliage = preload("res://src/plant_authoring/lightweight_foliage.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const MODES := ["volumes", "cards", "geometry"]
# 仅证据/基准标识；volumes_pure的配方枚举仍为volumes。
const VARIANTS := ["volumes", "cards", "volumes_pure", "geometry"]
const ATLAS := "res://assets/textures/vegetation/workshop_leaf_atlas_512.png"
const CLUSTER_ATLAS := "res://assets/textures/vegetation/workshop_leaf_clusters_512.png"
const PREPARATION_ROOT := "res://outputs/plant_canopy_sources"
const OUTPUT := "res://outputs/plant_canopy"
var preview_only := false
const MAX_SURFACES := 8
const MAX_TRIANGLES := 12000
const MIN_WINDOW_USEC := 2200000
const MIN_SAMPLE_FRAMES := 90
const NO_DRAW_TIMEOUT_USEC := 10000000
const ROUND_TIMEOUT_USEC := 60000000
var benchmark_draw_count := 0
var benchmark_draw_usec := 0
var checks := 0
var failures := 0
var store := Store.new()
var saved_scenes: Dictionary = {}
var report := {
	"schema_version": 1, "scope": "本机隔离独立树场景；不代表Main、移动或Web，不代签单叶外观艺术终审",
	"budget": {"surfaces": MAX_SURFACES, "triangles": MAX_TRIANGLES, "scope": "三树种volumes默认12外叶/cards及volumes_pure完整树，保留默认苔藓、藤蔓和草"},
	"failures_detail": [], "models": [], "roundtrips": [], "textures": [], "visual": [], "wind": [], "batch_comparisons": [], "volume_cards": [], "texture_decodes": [], "stage_timings": [],
	"benchmark": {"runs": [], "summary": [], "comparisons": [], "geometry_64": "未测：geometry默认逐实例资源较重；按约定只测1/16棵，不外推64棵"},
	"visual_review": "待人工检查三树种整树及单叶可辨近景；像素变化与截图存在不等于外观通过",
	"fps_measured": false
}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		report.failures_detail.append(label)
		printerr("[plant-canopy] FAIL " + label)

func _run() -> void:
	preview_only = OS.get_cmdline_user_args().has("--preview-only")
	if preview_only:
		report.scope = "visual_only"
		report.not_executed = "仅外观计数与截图；未执行配方/几何专项、Store往返、风固定验收或性能基准"
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK, "创建隔离证据目录")
	var fixed_fps := false
	for argument in OS.get_cmdline_args():
		fixed_fps = fixed_fps or argument == "--fixed-fps" or argument.begins_with("--fixed-fps=")
	_check(not fixed_fps, "真实基准禁止fixed-fps")
	_check(DisplayServer.get_name() != "headless", "必须使用真实渲染后端")
	if fixed_fps or DisplayServer.get_name() == "headless":
		report.not_executed = "渲染前置条件失败；未执行截图、保存及基准"
		_finish()
		return
	if not preview_only:
		_test_recipe()
		_test_foliage_primitives()
	if not FileAccess.file_exists(ATLAS) or not FileAccess.file_exists(CLUSTER_ATLAS):
		_check(false, "依赖未就绪：等待主线程生成指定PNG；测试不生成替代贴图")
		report.not_executed = "缺少指定源PNG；未执行模型、保存、渲染及基准"
		_finish()
		return
	_test_atlas(ATLAS)
	_test_atlas(CLUSTER_ATLAS)
	if preview_only:
		await _preview()
		_finish()
		return
	for species: String in Recipe.SPECIES:
		var bounds := AABB()
		var close_target := Vector3.ZERO
		var reference_counts: Dictionary = {}
		# 先获得geometry对照镜头，后续两种模式复用，不能各自拍最有利的构图。
		for mode: String in ["geometry", "volumes", "cards", "volumes_pure"]:
			var recipe := Recipe.defaults(species)
			recipe["foliage_mode"] = "volumes" if mode == "volumes_pure" else mode
			if mode == "volumes_pure":
				recipe["volume_leaf_cards"] = 0
			recipe.leaf_geometry = "balanced"
			var started := Time.get_ticks_usec()
			var built := Generator.build(recipe)
			var build_ms := (Time.get_ticks_usec() - started) / 1000.0
			_check(bool(built.ok), "%s/%s 构建：%s" % [species, mode, str(built.get("reason", ""))])
			if not built.ok:
				_write_progress("model_failed/" + species + "/" + mode)
				continue
			var model: Node3D = built.root
			var metric := _counts(model)
			metric.merge({"species": species, "mode": mode, "leaf_geometry": "balanced", "seed": recipe.seed,
				"build_ms": build_ms, "leaf_count": built.stats.leaf_count, "branch_count": built.stats.branch_count,
				"foliage_mode": recipe.foliage_mode, "volume_leaf_cards": recipe.get("volume_leaf_cards", -1),
				"surface_card_count": built.stats.get("surface_card_count", -1)})
			for field in ["triangles", "vertices", "mesh_nodes", "surfaces"]:
				_check(built.stats.has(field) and int(built.stats.get(field, -1)) == int(metric[field]), species + "/" + mode + " 独立计数核对 " + field)
			_check(metric.triangles > 0 and metric.surfaces > 0 and metric.leaf_count > 0, "完整树计数非空 " + species + mode)
			if mode == "geometry":
				bounds = built.stats.bounds
				close_target = _close_target(model)
				reference_counts = metric
			else:
				_check(metric.surfaces <= MAX_SURFACES, "%s/%s 完整树surfaces<=%d，实际%d" % [species, mode, MAX_SURFACES, metric.surfaces])
				_check(metric.triangles <= MAX_TRIANGLES, "%s/%s 默认tris<=%d，实际%d" % [species, mode, MAX_TRIANGLES, metric.triangles])
				if not reference_counts.is_empty():
					_check(metric.leaf_count == reference_counts.leaf_count, species + mode + " 逻辑叶计数保持，不把叶团数当单叶数")
					_check(metric.branch_count == reference_counts.branch_count, species + mode + " 主枝数保持")
					_check(metric.triangles < reference_counts.triangles and metric.surfaces < reference_counts.surfaces, species + mode + " 真实减面及合批")
				if mode == "cards":
					_check(_atlas_bindings(model, species + "/" + mode, recipe) > 0, species + mode + " 实际叶材质引用指定atlas")
					_test_card_uv(model, species)
				else:
					_test_volume_meshes(model, species)
					_test_volume_cards(model, recipe, built.stats)
					if mode == "volumes":
						_check(_atlas_bindings(model, species + "/" + mode, recipe) > 0, species + " 默认混合树冠实际加载atlas")
					else:
						_check(_atlas_bindings(model, species + "/" + mode, recipe) == 0, species + " 纯体块无atlas绑定")
			report.models.append(metric)
			print("[plant-canopy] MODEL " + JSON.stringify(metric))
			_write_progress("model_measured/" + species + "/" + mode)
			await _roundtrip(recipe, model, mode)
			if mode != "geometry" and bounds.size != Vector3.ZERO:
				var batch_started := Time.get_ticks_usec()
				await _batch_comparison(recipe, model, bounds, mode)
				_record_timing(species + "/" + mode, "batch_comparison", batch_started)
			if bounds.size != Vector3.ZERO:
				var visual_started := Time.get_ticks_usec()
				await _visual_and_wind(species, mode, model, bounds, close_target)
				_record_timing(species + "/" + mode, "visual_and_wind", visual_started)
			else:
				_check(false, species + mode + " 缺少geometry同条件取景基线")
			model.free()
			_write_progress("model_complete/" + species + "/" + mode)
		# 默认12与纯体块0已走完整流程，补实际几何的最小非零值和上边界。
		for outer_count in [1, 16]:
			var edge_recipe := Recipe.defaults(species)
			edge_recipe["volume_leaf_cards"] = outer_count
			var edge_built := Generator.build(edge_recipe)
			_check(bool(edge_built.ok), species + " 外叶数边界实际构建 " + str(outer_count))
			if edge_built.ok:
				_test_volume_cards(edge_built.root, edge_recipe, edge_built.stats)
				if not reference_counts.is_empty():
					_check(edge_built.stats.leaf_count == reference_counts.leaf_count, species + " 外叶count不冒充逻辑叶预算")
				edge_built.root.free()
	await _benchmark()
	_write_progress("benchmark_complete_or_stopped")
	_finish()

func _preview() -> void:
	report.capture_policy = "force_draw截图；无Store、无性能采样，不代表完整专项通过"
	for species: String in Recipe.SPECIES:
		var bounds := AABB()
		var close_target := Vector3.ZERO
		for variant: String in ["volumes", "cards", "volumes_pure"]:
			var recipe := Recipe.defaults(species)
			recipe.foliage_mode = "cards" if variant == "cards" else "volumes"
			if variant == "volumes_pure": recipe.volume_leaf_cards = 0
			var built := Generator.build(recipe)
			_check(bool(built.ok), species + "/" + variant + " 预览构建 " + str(built.get("reason", "")))
			if not built.ok: continue
			var model: Node3D = built.root
			var metric := _counts(model)
			metric.merge({"species": species, "mode": variant, "foliage_mode": recipe.foliage_mode,
				"volume_leaf_cards": recipe.volume_leaf_cards, "leaf_count": built.stats.leaf_count,
				"surface_card_count": built.stats.get("surface_card_count", -1)})
			report.models.append(metric)
			_check(metric.surfaces <= MAX_SURFACES and metric.triangles <= MAX_TRIANGLES, species + variant + " 预览仍保留8surface/12000tri硬预算")
			var bindings := _atlas_bindings(model, species + "/" + variant, recipe)
			_check(bindings == 0 if variant == "volumes_pure" else bindings > 0, species + variant + " 预览图集与配方一致")
			if variant == "volumes":
				bounds = built.stats.bounds
				close_target = _close_target(model)
			if bounds.size == Vector3.ZERO:
				_check(false, species + variant + " 缺少默认混合同机位基线")
				model.free()
				continue
			var stage := _stage()
			var camera: Camera3D = stage.camera
			stage.scene.add_child(model)
			var materials := Wind.prepare(model)
			for view: String in ["whole", "close", "edge"]:
				var target := bounds.get_center() if view == "whole" else close_target
				camera.size = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.18 if view == "whole" else 1.6
				var direction := Vector3(1.8, 0.15, 0.4) if view == "edge" else Vector3(1.1, 0.6, 1.5)
				camera.position = target + direction.normalized() * 20.0
				camera.look_at(target)
				for seconds: float in [0.0, 1.75]:
					Wind.apply_sample(materials, seconds)
					var image := await _image(stage.viewport)
					var path := _save_image(image, "preview_%s_%s_%s_t%s" % [species, variant, view, str(seconds)])
					report.visual.append({"species": species, "mode": variant, "view": view, "time": seconds,
						"path": path, "camera_transform": str(camera.transform), "camera_size": camera.size, "forced_draw": true})
			stage.viewport.free()
	_check(report.models.size() == 9 and report.visual.size() == 54, "快速预览三树种三外观三机位两帧完整")

func _write_progress(stage: String) -> void:
	# 只在模型/轮次之间序列化，不把报告I/O放入自然帧采样区间。
	report.checks = checks
	report.failures = failures
	report.progress = {"stage": stage, "complete": false, "ticks_usec": Time.get_ticks_usec()}
	report.full_suite_passed = false
	var file := FileAccess.open(OUTPUT + "/progress.json", FileAccess.WRITE)
	_check(file != null, "进度报告可写 " + stage)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

func _finish() -> void:
	report.progress = {"stage": "finished", "complete": true, "ticks_usec": Time.get_ticks_usec()}
	report.checks = checks
	report.failures = failures
	report.full_suite_passed = not preview_only and failures == 0 and report.fps_measured
	report.preview_only = preview_only
	report.renderer = RenderingServer.get_current_rendering_method()
	report.device = RenderingServer.get_video_adapter_name()
	report.engine = Engine.get_version_info()
	report.source_hashes = {}
	for path in ["res://tests/test_plant_canopy.gd", "res://src/plant_authoring/recipe.gd", "res://src/plant_authoring/generator.gd", "res://src/plant_authoring/geometry.gd", "res://src/plant_authoring/store.gd", "res://src/plant_authoring/wind_runtime.gd", "res://src/plant_authoring/leaf.gdshader",
		"res://src/plant_authoring/lightweight_foliage.gd", "res://src/plant_authoring/foliage_batch.gd",
		"res://src/plant_authoring/trunk_path.gd", "res://src/plant_authoring/game_wind.gdshaderinc", "res://src/plant_authoring/leaf_card.gdshader",
		"res://src/plant_authoring/leaf_volume.gdshader", "res://src/plant_authoring/species.gd", ATLAS, ATLAS + ".import",
		CLUSTER_ATLAS, CLUSTER_ATLAS + ".import", PREPARATION_ROOT + "/preparation.json", PREPARATION_ROOT + "/clusters_preparation.json"]:
		report.source_hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "缺失"
	var file := FileAccess.open(OUTPUT + "/report.json", FileAccess.WRITE)
	if file == null:
		_check(false, "无法写入专项JSON")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if preview_only:
		print("[plant-canopy-preview] visual_only %d checks, %d failures" % [checks, failures])
	else:
		print("[plant-canopy] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_recipe() -> void:
	_check(Recipe.SPECIES.size() == 3, "首批恰好三树种")
	for species: String in ["camphor", "maple", "birch"]:
		var fresh := Recipe.defaults(species)
		_check(fresh.get("foliage_mode") == "volumes", species + " 新建默认volumes")
		_check(fresh.get("volume_leaf_cards") == 12, species + " 新建默认每簇12外叶")
		var old_volumes := fresh.duplicate(true)
		old_volumes.erase("volume_leaf_cards")
		_check(Recipe.validate(old_volumes).is_empty() and Recipe.normalized(old_volumes).get("volume_leaf_cards") == 0 and not old_volumes.has("volume_leaf_cards"), species + " 旧缺字段保持纯体块且不改输入")
		for count in range(17):
			var valid_count := fresh.duplicate(true)
			valid_count["volume_leaf_cards"] = count
			_check(Recipe.validate(valid_count).is_empty() and Recipe.normalized(valid_count).get("volume_leaf_cards") == count, species + " 接受每簇外叶整数0..16 " + str(count))
		for count in [-1, 17, 1.5, "12", null, true]:
			var bad_count := fresh.duplicate(true)
			bad_count["volume_leaf_cards"] = count
			_check(not Recipe.validate(bad_count).is_empty(), species + " 拒绝非法外叶数 " + str(count))
		for profile: String in ["balanced", "high", "reference"]:
			var old := fresh.duplicate(true)
			old.erase("foliage_mode")
			old.leaf_geometry = profile
			var normalized := Recipe.normalized(old)
			_check(Recipe.validate(old).is_empty() and normalized.get("foliage_mode") == "geometry", species + profile + " 旧缺字段归一geometry")
			_check(normalized.leaf_geometry == profile and not old.has("foliage_mode"), "保留旧三档且归一不改输入")
			for mode: String in MODES:
				var valid := fresh.duplicate(true)
				valid["foliage_mode"] = mode
				valid.leaf_geometry = profile
				_check(Recipe.validate(valid).is_empty(), species + mode + profile + " 模式及旧质量档可组合")
		var legacy := fresh.duplicate(true)
		legacy.erase("foliage_mode")
		legacy.erase("leaf_geometry")
		_check(Recipe.normalized(legacy).get("foliage_mode") == "geometry" and Recipe.normalized(legacy).leaf_geometry == "balanced", "双缺字段旧档保留geometry/balanced")
		for invalid in ["", "billboard", "Volumes", "volumes_pure", 0, null, true]:
			var bad := fresh.duplicate(true)
			bad["foliage_mode"] = invalid
			_check(not Recipe.validate(bad).is_empty(), "拒绝非法foliage_mode " + str(invalid))

func _test_atlas(atlas_path: String) -> void:
	var source := Image.new()
	var source_error := source.load_png_from_buffer(FileAccess.get_file_as_bytes(atlas_path))
	_check(source_error == OK and not source.is_empty(), "源PNG字节可解码 " + atlas_path)
	if source_error != OK or source.is_empty():
		return
	_check(source.get_size() == Vector2i(512, 512) and source.get_format() == Image.FORMAT_RGBA8, "源PNG严格512² RGBA8")
	var tile_rows: Array = []
	if source.get_size() == Vector2i(512, 512):
		for tile in 4:
			var opaque := 0
			var transparent := 0
			var envelope_min := Vector2i(256, 256)
			var envelope_max := Vector2i(-1, -1)
			for y in range(int(tile / 2) * 256, int(tile / 2) * 256 + 256):
				for x in range((tile % 2) * 256, (tile % 2) * 256 + 256):
					var alpha := source.get_pixel(x, y).a
					opaque += int(alpha >= 0.9)
					transparent += int(alpha <= 0.1)
					if alpha >= 0.42:
						var pixel := Vector2i(x % 256, y % 256)
						envelope_min = envelope_min.min(pixel)
						envelope_max = envelope_max.max(pixel)
			_check(opaque > 0 and transparent > 0, "2×2 atlas每格含叶片及透明轮廓 " + str(tile))
			_check(envelope_min == Vector2i(8, 8) and envelope_max == Vector2i(247, 247), "每tile按实际alpha裁剪阈值0.42的有效包络严格8..247 " + str(tile))
			tile_rows.append({"tile": tile, "opaque_pixels": opaque, "transparent_pixels": transparent,
				"alpha_cutoff": 0.42, "envelope_min": [envelope_min.x, envelope_min.y], "envelope_max": [envelope_max.x, envelope_max.y]})
	var texture := ResourceLoader.load(atlas_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	_check(texture != null, "通过ResourceLoader实际加载导入纹理，不以源PNG代替")
	if texture != null:
		var image := texture.get_image()
		_check(texture.resource_path == atlas_path and texture.get_size() == Vector2(512, 512), "加载纹理来源及尺寸不变")
		_check(image != null and image.has_mipmaps(), "实际导入纹理含mipmap，不只检查import配置 " + atlas_path)
		if image != null:
			var decoded := image.duplicate() as Image
			var decode_error := decoded.decompress() if decoded.is_compressed() else OK
			_check(decoded != image and decode_error == OK and not decoded.is_compressed(), "双图集独立副本实际解码成功 " + atlas_path)
			if decode_error == OK and not decoded.is_compressed():
				_check(decoded.detect_alpha() != Image.ALPHA_NONE and decoded.get_size() == Vector2i(512, 512), "实际导入图集解码后alpha和尺寸有效 " + atlas_path)
		report.textures.append({"path": texture.resource_path, "sha256": FileAccess.get_sha256(atlas_path), "source_format": source.get_format(),
			"width": texture.get_width(), "height": texture.get_height(), "mipmaps": image.has_mipmaps() if image != null else false, "tiles": tile_rows})

func _expected_atlas(recipe: Dictionary) -> String:
	if recipe.foliage_mode == "cards": return ATLAS
	if recipe.foliage_mode == "volumes" and int(recipe.get("volume_leaf_cards", 0)) > 0: return CLUSTER_ATLAS
	return ""

func _atlas_bindings(model: Node, label: String, recipe: Dictionary) -> int:
	var expected := _expected_atlas(recipe)
	var count := 0
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	_resources(model, meshes, materials)
	for material: Material in materials.values():
		if not material is ShaderMaterial or material.shader == null:
			continue
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform.name)
			if value is Texture2D and (value.resource_path in [ATLAS, CLUSTER_ATLAS] or str(uniform.name) == "leaf_atlas"):
				_check(not expected.is_empty() and value.resource_path == expected, label + " 图集绑定必须匹配配方 " + expected)
				count += 1
				var image: Image = value.get_image()
				_check(value.get_width() == 512 and value.get_height() == 512 and image != null and image.has_mipmaps(), label + " 已绑定纹理实际尺寸及mipmap")
				var sampler_mipmaps := false
				for line: String in material.shader.code.split("\n"):
					if line.contains("uniform sampler2D " + str(uniform.name)) and line.contains("mipmap"):
						sampler_mipmaps = true
				_check(sampler_mipmaps, label + " atlas采样器实际启用mipmap过滤")
	return count

func _test_card_uv(model: Node3D, species: String) -> void:
	var tiles := {"camphor": Vector2(0, 0), "maple": Vector2(1, 0), "birch": Vector2(0, 1)}
	var group := model.get_node_or_null("Leaves")
	_check(group != null, species + " 叶卡Leaves分组存在")
	if group == null:
		return
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	_resources(group, meshes, materials)
	var cards := 0
	var definition: Dictionary = Species.definitions()[species]
	var recipe := Recipe.defaults(species)
	var envelope := _outline_size(definition.leaf_shape, float(recipe.leaf_size) * float(definition.leaf_width_ratio), float(recipe.leaf_size) * float(definition.leaf_length_ratio))
	for mesh: Mesh in meshes.values():
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var layout_ok := points.size() > 0 and points.size() % 10 == 0 and indices.size() == int(points.size() / 10) * 18
			layout_ok = layout_ok and uv.size() == points.size() and colors.size() == points.size() and normals.size() == points.size()
			_check(layout_ok, species + " 每叶4柄顶点+6卡顶点，2柄面+4卡面，通道齐全")
			if not layout_ok:
				continue
			for first in range(0, points.size(), 10):
				cards += 1
				var label := species + " 实际叶" + str(cards)
				var uv_valid := true
				for vertex in 10:
					var actual := uv[first + vertex]
					if vertex < 4:
						uv_valid = uv_valid and actual == Vector2(-1, -1)
					else:
						var row := int((vertex - 4) / 2)
						var expected: Vector2 = (tiles[species] * 256.0 + Vector2(8.5 + ((vertex - 4) % 2) * 239.0, 247.5 - row * 119.5)) / 512.0
						uv_valid = uv_valid and actual.is_finite() and actual.distance_to(expected) < 0.000001
				_check(uv_valid, label + " 仅柄UV2=-1，全部有效卡UV严格命中8..247像素中心及正确树种格")
				var topology := true
				var offset := int(first / 10) * 18
				for face in 6:
					for corner in 3:
						var index := indices[offset + face * 3 + corner] - first
						topology = topology and (index >= 0 and index < 4 if face < 2 else index >= 4 and index < 10)
				_check(topology, label + " 柄面与卡面不混接、不引用其它叶")
				var nondegenerate := topology
				if topology:
					for face in 6:
						var a := points[indices[offset + face * 3]]
						var b := points[indices[offset + face * 3 + 1]]
						var c := points[indices[offset + face * 3 + 2]]
						nondegenerate = nondegenerate and (b - a).cross(c - a).length_squared() > 1.0e-22
				_check(nondegenerate, label + " 实际柄卡六面均非退化")
				_check_card_geometry(points, normals, colors, first, label, 0.0002)
				var width := points[first + 5].distance_to(points[first + 4])
				var length := ((points[first + 8] + points[first + 9]) * 0.5).distance_to((points[first + 4] + points[first + 5]) * 0.5)
				var scale_x := width / envelope.x
				var scale_y := length / envelope.y
				_check(scale_x >= 0.84 - 0.00001 and scale_x <= 1.14 + 0.00001 and absf(scale_x - scale_y) < 0.00001, label + " 卡尺寸保持树种轮廓包络及原随机尺寸域")
	_check(cards > 0, species + " 实际卡片检查非空")

func _outline_size(shape: String, width: float, length: float) -> Vector2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector2 in Geometry.leaf_outline(shape):
		low = low.min(point)
		high = high.max(point)
	return (high - low) * Vector2(width, length)

func _check_card_geometry(points: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, first: int, label: String, normal_tolerance: float) -> void:
	var base := (points[first] + points[first + 1]) * 0.5
	var join := (points[first + 2] + points[first + 3]) * 0.5
	var card_root := (points[first + 4] + points[first + 5]) * 0.5
	var tip := (points[first + 8] + points[first + 9]) * 0.5
	_check(join.distance_to(card_root) < 0.000001 and base.distance_to(join) > 0.00001, label + " 实际柄端中心连接卡根且柄非零长")
	var fixed := true
	for vertex in 6:
		fixed = fixed and colors[first + vertex].r == 0.0 and colors[first + vertex].g == 0.0
	_check(fixed and colors[first + 8].r == 1.0 and colors[first + 9].r == 1.0, label + " 整柄及卡根严格固定，尖端风权重为1")
	var side := (points[first + 5] - points[first + 4]).normalized()
	var forward := (tip - card_root).normalized()
	var hemisphere := side.cross(forward).normalized()
	var valid := true
	for vertex in range(4, 10):
		var normal := normals[first + vertex]
		valid = valid and normal.is_finite() and absf(normal.length() - 1.0) < normal_tolerance and normal.dot(hemisphere) >= -normal_tolerance
	_check(valid, label + " 卡法线有限单位且不翻出基础法线半球")
	var middle := (points[first + 6] + points[first + 7]) * 0.5
	_check(middle.distance_to(card_root.lerp(tip, 0.5) + hemisphere * tip.distance_to(card_root) * 0.07) < 0.000001, label + " 卡中线保留7%轻弯")

func _test_foliage_primitives() -> void:
	for species: String in Recipe.SPECIES:
		var definition: Dictionary = Species.definitions()[species]
		for size: float in [0.08, 0.36, 1.2]:
			var expected := _outline_size(definition.leaf_shape, size * float(definition.leaf_width_ratio), size * float(definition.leaf_length_ratio))
			var actual := Foliage.card_size(definition.leaf_shape, size * float(definition.leaf_width_ratio), size * float(definition.leaf_length_ratio))
			_check(actual.distance_to(expected) < 0.000001, species + " helper尺寸等于独立轮廓包络")
			for axis: Vector3 in [Vector3.FORWARD, Vector3.UP, Vector3(0.3, -0.2, 0.8).normalized()]:
				for blend: float in [0.0, 0.68, 1.0]:
					var buffer := Generator._buffer()
					var base := Vector3(0.2, 0.3, -0.1)
					var join := base + axis * 0.12
					Foliage.append_petiole(buffer, base, join, 28)
					# 故意将球形法线中心置于另一侧，覆盖半球纠正而非只有顺向样例。
					var side := axis.cross(Vector3.UP).normalized()
					if side.length_squared() < 0.01: side = Vector3.RIGHT
					Foliage.append_card(buffer, join, axis, actual.x, actual.y, species, 28, join + side.cross(axis) * 2.0, blend)
					_check(buffer.v.size() == 10 and buffer.i.size() == 18, species + " helper实际生成4tri卡+2tri柄")
					if buffer.v.size() != 10 or buffer.n.size() != 10 or buffer.colors.size() != 10: continue
					_check_card_geometry(buffer.v, buffer.n, buffer.colors, 0, species + " helper", 0.000001)
					var width: float = buffer.v[4].distance_to(buffer.v[5])
					var length: float = ((buffer.v[8] + buffer.v[9]) * 0.5).distance_to((buffer.v[4] + buffer.v[5]) * 0.5)
					_check(absf(width - expected.x) < 0.000001 and absf(length - expected.y) < 0.000001, species + " helper实际顶点宽长保持轮廓米制尺寸")
	for radii: Vector3 in [Vector3(0.12, 0.035, 0.09), Vector3(0.6, 0.2, 0.9), Vector3(0.4, 1.2, 0.3)]:
		for blend: float in [0.0, 0.68, 1.0]:
			var buffer := Generator._buffer()
			Foliage.append_volume(buffer, Vector3(0.3, 1.7, -0.2), radii, 28, blend)
			_check(buffer.i.size() == 72, "体块helper实际24三角形")
			_audit_volume(buffer.v, buffer.n, buffer.i, buffer.colors, "体块helper", 0.000001)

func _audit_volume(points: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, colors: PackedColorArray, label: String, normal_tolerance: float) -> void:
	var complete := points.size() > 0 and normals.size() == points.size() and colors.size() == points.size() and indices.size() > 0 and indices.size() % 3 == 0
	_check(complete, label + " 体块实际几何通道完整")
	if not complete: return
	var edge_uses: Dictionary = {}
	var edge_balance: Dictionary = {}
	var weights: Dictionary = {}
	var valid := true
	var consistent := true
	var center := Vector3.ZERO
	for point: Vector3 in points: center += point
	center /= points.size()
	for vertex in points.size():
		var point := points[vertex]
		var normal := normals[vertex]
		var weight := Vector2(colors[vertex].r, colors[vertex].g)
		valid = valid and point.is_finite() and normal.is_finite() and absf(normal.length() - 1.0) < normal_tolerance
		valid = valid and weight.is_finite() and weight.x > 0.0 and weight.x <= 1.0
		if weights.has(point): consistent = consistent and weights[point] == weight
		else: weights[point] = weight
	for face in range(0, indices.size(), 3):
		var ids := [indices[face], indices[face + 1], indices[face + 2]]
		if ids.min() < 0 or ids.max() >= points.size():
			valid = false
			continue
		var a := points[ids[0]]
		var b := points[ids[1]]
		var c := points[ids[2]]
		var normal := (c - a).cross(b - a)
		valid = valid and normal.length_squared() > 1.0e-22 and normal.dot((a + b + c) / 3.0 - center) > 0.0
		for edge in [[a, b], [b, c], [c, a]]:
			var keys: Array[String] = [var_to_bytes(edge[0]).hex_encode(), var_to_bytes(edge[1]).hex_encode()]
			var direction := 1 if keys[0] < keys[1] else -1
			keys.sort()
			var key := "|".join(keys)
			edge_uses[key] = int(edge_uses.get(key, 0)) + 1
			edge_balance[key] = int(edge_balance.get(key, 0)) + direction
	var closed := not edge_uses.is_empty()
	for edge: String in edge_uses:
		closed = closed and edge_uses[edge] == 2 and edge_balance[edge] == 0
	_check(valid, label + " 体块有限、单位法线、非退化、全部朝外")
	_check(closed, label + " 体块每空间边恰被两面反向使用，闭合无裂缝")
	_check(consistent and weights.size() < points.size(), label + " 同位置重复顶点风权重/相位严格一致")

func _test_volume_meshes(model: Node3D, species: String) -> void:
	var group := model.get_node_or_null("Leaves")
	_check(group != null, species + " 体块Leaves分组存在")
	if group == null: return
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	_resources(group, meshes, materials)
	var volumes := 0
	for material: Material in materials.values():
		if material is ShaderMaterial and material.shader != null and material.shader.resource_path == "res://src/plant_authoring/leaf_card.gdshader":
			continue
		_check(material is ShaderMaterial and material.shader != null and material.shader.resource_path == "res://src/plant_authoring/leaf_volume.gdshader", species + " 体块实际使用独立shader")
		if material is ShaderMaterial and material.shader != null:
			_check(material.shader.code.contains("render_mode cull_back"), species + " 体块shader背面剔除")
			for uniform: Dictionary in material.shader.get_shader_uniform_list():
				_check(not (material.get_shader_parameter(uniform.name) is Texture2D or material.get_shader_parameter(uniform.name) is Texture3D or material.get_shader_parameter(uniform.name) is TextureLayered), species + " 体块实际无纹理绑定 " + str(uniform.name))
	for mesh: Mesh in meshes.values():
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			if material == null or material.shader == null or material.shader.resource_path != "res://src/plant_authoring/leaf_volume.gdshader":
				continue
			var complete := points.size() > 0 and points.size() % 72 == 0 and indices.size() == points.size() and normals.size() == points.size() and colors.size() == points.size()
			_check(complete, species + " 合批体块仍每24面一闭合组件且通道完整")
			if not complete: continue
			for first in range(0, points.size(), 72):
				var local_indices := PackedInt32Array()
				for index in range(first, first + 72): local_indices.append(indices[index] - first)
				_audit_volume(points.slice(first, first + 72), normals.slice(first, first + 72), local_indices, colors.slice(first, first + 72), species + " 实际体块" + str(volumes), 0.0002)
				volumes += 1
	_check(volumes > 0, species + " 实际体块闭合检查非空")

func _test_volume_cards(model: Node3D, recipe: Dictionary, stats: Dictionary) -> void:
	var label := str(recipe.species) + "/volumes/" + str(recipe.get("volume_leaf_cards", -1))
	var group := model.get_node_or_null("Leaves")
	_check(group != null, label + " 混合Leaves分组存在")
	if group == null: return
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	_resources(group, meshes, materials)
	var count := 0
	var volume_count := 0
	var card_surfaces := 0
	var volume_surfaces := 0
	var tiles := {"camphor": Vector2(0, 0), "maple": Vector2(1, 0), "birch": Vector2(0, 1)}
	for mesh: Mesh in meshes.values():
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			_check(material != null and material.shader != null, label + " 实际表面材质有效")
			if material == null or material.shader == null: continue
			var arrays := mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if material.shader.resource_path == "res://src/plant_authoring/leaf_volume.gdshader":
				volume_surfaces += 1
				volume_count += int(points.size() / 72)
				continue
			_check(material.shader.resource_path == "res://src/plant_authoring/leaf_card.gdshader", label + " 外叶仅使用叶卡shader")
			if material.shader.resource_path != "res://src/plant_authoring/leaf_card.gdshader": continue
			card_surfaces += 1
			var atlas := material.get_shader_parameter("leaf_atlas") as Texture2D
			_check(atlas != null and atlas.resource_path == CLUSTER_ATLAS, label + " 外叶实际绑定指定alpha图集")
			if atlas != null:
				var image := atlas.get_image()
				_check(image != null and image.has_mipmaps(), label + " 外叶实际导入原图含mipmap")
				if image != null:
					var original_format := image.get_format()
					var original_compressed := image.is_compressed()
					var original_data := image.get_data()
					var decoded := image.duplicate() as Image
					_check(decoded != null and decoded != image, label + " alpha核验使用独立Image副本")
					if decoded != null and decoded != image:
						var decode_error := decoded.decompress() if decoded.is_compressed() else OK
						_check(decode_error == OK and not decoded.is_compressed() and not decoded.is_empty(), label + " 图集副本显式解压成功，错误码" + str(decode_error))
						var alpha := Image.ALPHA_NONE
						if decode_error == OK and not decoded.is_compressed() and not decoded.is_empty():
							alpha = decoded.detect_alpha()
							_check(alpha != Image.ALPHA_NONE, label + " 解码后的实际导入图集必须含alpha")
						report.texture_decodes.append({"label": label, "source_format": original_format,
							"source_compressed": original_compressed, "source_mipmaps": image.has_mipmaps(),
							"decode_error": decode_error, "decoded_format": decoded.get_format(), "alpha": alpha})
					_check(image.get_format() == original_format and image.is_compressed() == original_compressed and image.get_data() == original_data, label + " 解码不改共享导入图像格式或字节")
			_check(material.shader.code.contains("texel.a < 0.42") and material.shader.code.contains("discard;") and not material.shader.code.contains("ALPHA ="), label + " 外叶alpha裁剪而非透明混合")
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var complete := points.size() > 0 and points.size() % 6 == 0 and indices.size() == int(points.size() / 6) * 12 and normals.size() == points.size() and uv.size() == points.size() and colors.size() == points.size()
			_check(complete, label + " 外叶为6顶点4tri卡，不套用原单叶平柄布局")
			if not complete: continue
			for first in range(0, points.size(), 6):
				count += 1
				var valid := true
				var base := (points[first] + points[first + 1]) * 0.5
				var tip := (points[first + 4] + points[first + 5]) * 0.5
				var side := (points[first + 1] - points[first]).normalized()
				var normal := side.cross((tip - base).normalized()).normalized()
				for vertex in 6:
					var expected: Vector2 = (tiles[recipe.species] * 256.0 + Vector2(8.5 + (vertex % 2) * 239.0, 247.5 - int(vertex / 2) * 119.5)) / 512.0
					valid = valid and uv[first + vertex].is_finite() and uv[first + vertex].distance_to(expected) < 0.000001
					valid = valid and normals[first + vertex].is_finite() and absf(normals[first + vertex].length() - 1.0) < 0.0002 and normals[first + vertex].dot(normal) >= -0.0002
					valid = valid and points[first + vertex].is_finite()
				var offset := int(first / 6) * 12
				for face in 4:
					var ids := [indices[offset + face * 3], indices[offset + face * 3 + 1], indices[offset + face * 3 + 2]]
					if ids.min() < first or ids.max() >= first + 6:
						valid = false
						continue
					valid = valid and (points[ids[1]] - points[ids[0]]).cross(points[ids[2]] - points[ids[0]]).length_squared() > 1.0e-22
				_check(valid, label + " 外叶" + str(count) + " UV严格命中本树种格、单位法线不翻半球、索引独立且非退化")
	var per_cluster := int(recipe.get("volume_leaf_cards", -1))
	_check(volume_count == int(stats.get("cluster_count", -1)) and volume_count > 0, label + " 真实体块数核对cluster_count")
	_check(count == volume_count * per_cluster and count == int(stats.get("surface_card_count", -1)), label + " 真实外叶数=簇数×每簇count=surface_card_count，实际" + str(count))
	_check(volume_surfaces == 1 and card_surfaces == (1 if per_cluster > 0 else 0), label + " 合批Leaves纯体块1surface/混合2surfaces")
	report.volume_cards.append({"species": recipe.species, "volume_leaf_cards": per_cluster, "actual_clusters": volume_count,
		"actual_surface_cards": count, "reported_surface_cards": stats.get("surface_card_count", -1),
		"logical_leaf_count": stats.get("leaf_count", -1), "volume_surfaces": volume_surfaces, "card_surfaces": card_surfaces})

func _counts(node: Node) -> Dictionary:
	var metric := {"nodes": 1, "mesh_nodes": 0, "surfaces": 0, "vertices": 0, "triangles": 0, "cpu_array_payload_bytes": 0}
	var mesh: Mesh = null
	var instances := 1
	if node is MeshInstance3D:
		mesh = node.mesh
	elif node is MultiMeshInstance3D and node.multimesh != null:
		mesh = node.multimesh.mesh
		instances = node.multimesh.instance_count
	if mesh != null:
		metric.mesh_nodes += 1
		metric.surfaces += mesh.get_surface_count()
		for surface in mesh.get_surface_count():
			_check(mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, "树网格使用三角形")
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			metric.vertices += vertices.size() * instances
			metric.triangles += int((indices.size() if indices != null and indices.size() > 0 else vertices.size()) / 3) * instances
			for attribute in arrays:
				if attribute != null:
					metric.cpu_array_payload_bytes += attribute.to_byte_array().size()
	for child in node.get_children():
		var child_counts := _counts(child)
		for key in metric:
			metric[key] += child_counts[key]
	return metric

func _resources(node: Node, meshes: Dictionary, materials: Dictionary) -> void:
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = node.mesh
	elif node is MultiMeshInstance3D and node.multimesh != null:
		mesh = node.multimesh.mesh
	if mesh != null:
		meshes[mesh.get_instance_id()] = mesh
		for surface in mesh.get_surface_count():
			var material: Material = node.get_active_material(surface) if node is MeshInstance3D else mesh.surface_get_material(surface)
			if material != null:
				materials[material.get_instance_id()] = material
	for child in node.get_children():
		_resources(child, meshes, materials)

func _verification_snapshot(model: Node) -> Dictionary:
	# 保留Store严格比较消费的全部原始字段；不生成本测试从未使用的三份文本指纹。
	# Store.save/save_animated内部仍执行原有指纹、重载及manifest完整流程。
	var snapshot := {"visual_meshes": 0, "triangles": 0, "scripts": 0, "cameras": 0, "lights": 0, "collisions": 0,
		"has_bounds": false, "bounds": AABB(), "nodes": {}, "materials": {}, "unreadable_multimeshes": 0}
	store._snapshot_node(model, model, Transform3D.IDENTITY, snapshot)
	var bounds: AABB = snapshot.bounds
	snapshot.bounds_position = [bounds.position.x, bounds.position.y, bounds.position.z]
	snapshot.bounds_size = [bounds.size.x, bounds.size.y, bounds.size.z]
	return snapshot

func _record_timing(label: String, stage: String, started: int) -> void:
	var timing := {"label": label, "stage": stage, "elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0}
	report.stage_timings.append(timing)
	print("[plant-canopy] TIMING " + JSON.stringify(timing))

func _roundtrip(recipe: Dictionary, model: Node3D, variant: String) -> void:
	var label := str(recipe.species) + "/" + variant
	var export_recipe := recipe.duplicate(true)
	export_recipe.name = "canopy-" + str(recipe.species) + "-" + variant
	var stage_started := Time.get_ticks_usec()
	var first := store.save(export_recipe)
	_record_timing(label, "store_save_static", stage_started)
	_check(bool(first.ok), label + " 静态保存 " + str(first.get("reason", "")))
	if not first.ok:
		return
	var old_hashes: Dictionary = {}
	for field in ["recipe_path", "scene_path", "manifest_path"]:
		old_hashes[first[field]] = FileAccess.get_sha256(first[field])
	stage_started = Time.get_ticks_usec()
	var dynamic := store.save_animated(export_recipe)
	_record_timing(label, "store_save_animated", stage_started)
	_check(bool(dynamic.ok), label + " 动态保存 " + str(dynamic.get("reason", "")))
	if not dynamic.ok:
		return
	_check(dynamic.directory != first.directory, label + " 动态保存新增revision")
	for path: String in old_hashes:
		_check(FileAccess.get_sha256(path) == old_hashes[path], label + " 旧版本字节不变 " + path.get_file())
	stage_started = Time.get_ticks_usec()
	var static_baseline := model.duplicate() as Node3D
	store._prepare_static_tree(static_baseline)
	var static_snapshot := _verification_snapshot(static_baseline)
	var static_counts := _counts(static_baseline)
	static_baseline.free()
	_record_timing(label, "static_baseline_snapshot", stage_started)
	for bundle: Dictionary in [first, dynamic]:
		stage_started = Time.get_ticks_usec()
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(bundle.manifest_path))
		_check(manifest is Dictionary, label + " 保存manifest可读取")
		if manifest is Dictionary:
			var expected_atlas := _expected_atlas(recipe)
			var source_hashes: Dictionary = manifest.get("source_path_hashes", {})
			if not expected_atlas.is_empty():
				_check(source_hashes.get(expected_atlas, "") == FileAccess.get_sha256(expected_atlas), label + " 保存manifest登记正确图集当前哈希")
			else:
				_check(not source_hashes.has(ATLAS) and not source_hashes.has(CLUSTER_ATLAS), label + " 无叶卡配方manifest不登记两图集")
		var reloaded := store.load_recipe(bundle.recipe_path)
		_check(bool(reloaded.ok) and Recipe.fingerprint(reloaded.recipe) == Recipe.fingerprint(export_recipe), label + " 配方全部字段往返")
		var packed := ResourceLoader.load(bundle.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		_check(packed != null, label + " 磁盘静态PackedScene重载")
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		_check(store._verify_static_snapshot(static_snapshot, _verification_snapshot(instance)).is_empty(), label + " 静态逐几何/UV/材质外链往返，沿用既有0.0002容差")
		_check(_counts(instance) == static_counts, label + " 静态独立counts一致")
		if recipe.foliage_mode == "cards" or (recipe.foliage_mode == "volumes" and int(recipe.get("volume_leaf_cards", 0)) > 0):
			_check(_atlas_bindings(instance, label + "静态重载", recipe) > 0, label + " 静态atlas不内嵌替换")
		elif recipe.foliage_mode == "volumes":
			_check(_atlas_bindings(instance, label + "纯体块静态重载", recipe) == 0, label + " 纯体块静态不引入atlas")
		instance.free()
		_record_timing(label, "static_reload_verify_revision_" + str(bundle.revision), stage_started)
	static_snapshot.clear()
	stage_started = Time.get_ticks_usec()
	var packed := ResourceLoader.load(dynamic.animated_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	_check(packed != null, label + " 磁盘动态PackedScene重载")
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	_check(store._verify_wind_scripts(instance, instance).is_empty(), label + " 仅根WindRuntime白名单且无owner分组")
	var baseline := model.duplicate() as Node3D
	store._prepare_static_tree(baseline)
	Wind.apply_sample(Wind.prepare(baseline), 0.0)
	# 单独审计脚本后移除再比较，其它资源/数据不改动。
	instance.set_script(null)
	_check(store._verify_static_snapshot(_verification_snapshot(baseline), _verification_snapshot(instance)).is_empty(), label + " 动态逐数据与外链往返")
	_check(_counts(instance) == _counts(baseline), label + " 动态独立counts一致")
	if recipe.foliage_mode == "cards" or (recipe.foliage_mode == "volumes" and int(recipe.get("volume_leaf_cards", 0)) > 0):
		_check(_atlas_bindings(instance, label + "动态重载", recipe) > 0, label + " 动态atlas不内嵌替换")
	elif recipe.foliage_mode == "volumes":
		_check(_atlas_bindings(instance, label + "纯体块动态重载", recipe) == 0, label + " 纯体块动态不引入atlas")
	baseline.free()
	instance.free()
	_record_timing(label, "dynamic_reload_verify", stage_started)
	saved_scenes[label] = dynamic.animated_scene_path
	report.roundtrips.append({"species": recipe.species, "mode": variant, "foliage_mode": recipe.foliage_mode,
		"volume_leaf_cards": recipe.get("volume_leaf_cards", -1), "recipe": export_recipe, "static": first, "animated": dynamic})
	await process_frame

func _stage() -> Dictionary:
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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 300.0
	scene.add_child(camera)
	camera.current = true
	return {"viewport": viewport, "scene": scene, "camera": camera}

func _close_target(model: Node3D) -> Vector3:
	var leaves := model.get_node_or_null("Leaves")
	_check(leaves != null, "保留Leaves分组")
	if leaves == null:
		return Vector3.ZERO
	var visuals := leaves.find_children("*", "MeshInstance3D", true, false)
	_check(not visuals.is_empty(), "存在可观察叶片网格")
	if visuals.is_empty():
		return Vector3.ZERO
	var mesh_node := visuals[0] as MeshInstance3D
	var transform := mesh_node.transform
	var parent := mesh_node.get_parent()
	while parent != model and parent is Node3D:
		transform = parent.transform * transform
		parent = parent.get_parent()
	var points: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var target := transform * mesh_node.mesh.get_aabb().get_center()
	var nearest := -INF
	var view_direction := Vector3(1.1, 0.6, 1.5).normalized()
	for point: Vector3 in points:
		var world_point := transform * point
		if world_point.dot(view_direction) > nearest:
			nearest = world_point.dot(view_direction)
			target = world_point
	return target

func _image(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	# 仅截图主动绘制，避免窗口遮挡后停绘；性能采样不得调用此函数。
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()

func _save_image(image: Image, name: String) -> String:
	var path := OUTPUT + "/" + name + ".png"
	_check(image != null and not image.is_empty(), "真实图像非空 " + name)
	if image == null or image.is_empty():
		return ""
	_check(image.save_png(path) == OK, "保存真实截图 " + name)
	return ProjectSettings.globalize_path(path)

func _changed_pixels(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size() or a.get_format() != b.get_format():
		return -1
	var left := a.get_data()
	var right := b.get_data()
	var channels := int(left.size() / (a.get_width() * a.get_height()))
	var changed := 0
	for pixel in a.get_width() * a.get_height():
		for channel in channels:
			if left[pixel * channels + channel] != right[pixel * channels + channel]:
				changed += 1
				break
	return changed

func _visual_and_wind(species: String, mode: String, model: Node3D, bounds: AABB, close_target: Vector3) -> void:
	var stage := _stage()
	var viewport: SubViewport = stage.viewport
	var camera: Camera3D = stage.camera
	stage.scene.add_child(model)
	var materials := Wind.prepare(model)
	_check(not materials.is_empty(), species + mode + " 真实准备风材质")
	var prepared := _verification_snapshot(model)
	for view: String in ["whole", "close"]:
		var target := bounds.get_center() if view == "whole" else close_target
		camera.size = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.18 if view == "whole" else 1.6
		camera.position = target + Vector3(1.1, 0.6, 1.5).normalized() * 20.0
		camera.look_at(target)
		var images: Array[Image] = []
		for seconds: float in [0.0, 1.75]:
			Wind.apply_sample(materials, seconds, 1.1, Vector2(0.86, 0.5), true)
			var image := await _image(viewport)
			images.append(image)
			var path := _save_image(image, "%s_%s_%s_t%s" % [species, mode, view, str(seconds)])
			report.visual.append({"species": species, "mode": mode, "view": view, "time": seconds, "path": path,
				"camera_transform": str(camera.transform), "camera_size": camera.size, "wind_strength": 1.1})
		_check(_changed_pixels(images[0], images[1]) > 0, species + mode + view + " 两风帧实际像素改变")
	# 三种强度分别验证：无风/普通/强风。单独隔离木干/树皮/苔藓，避免叶片遮挡假阳性。
	camera.size = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.18
	camera.position = bounds.get_center() + Vector3(1.1, 0.6, 1.5).normalized() * 20.0
	camera.look_at(bounds.get_center())
	var trunk := model.get_node_or_null("Trunk")
	_check(trunk != null and _counts(trunk).triangles > 0, species + mode + " 固定像素检查确有木干几何")
	var hidden: Dictionary = {}
	for group: String in ["Leaves", "Vines", "Grass"]:
		var node := model.get_node_or_null(group) as Node3D
		_check(node != null, "保留可隔离分组 " + group)
		if node != null:
			hidden[node] = node.visible
			node.visible = false
	for strength: float in [0.0, 1.1, 2.2]:
		Wind.apply_sample(materials, 0.0, strength)
		var first := await _image(viewport)
		Wind.apply_sample(materials, 1.75, strength)
		var second := await _image(viewport)
		var changed := _changed_pixels(first, second)
		_check(changed == 0, "%s/%s 风%s木干树皮苔藓像素零变化，实际%d" % [species, mode, str(strength), changed])
		report.wind.append({"species": species, "mode": mode, "strength": strength, "fixed_changed_pixels": changed,
			"first": _save_image(first, "%s_%s_fixed_s%s_t0" % [species, mode, str(strength)]),
			"second": _save_image(second, "%s_%s_fixed_s%s_t1.75" % [species, mode, str(strength)])})
	for node: Node3D in hidden:
		node.visible = hidden[node]
	var after := _verification_snapshot(model)
	_check(prepared.nodes == after.nodes, species + mode + " 风采样后所有几何数组/变换严格不变")
	Wind.prepare(model)
	_check(after.nodes == _verification_snapshot(model).nodes, species + mode + " 重复prepare不改变几何")
	stage.scene.remove_child(model)
	viewport.free()

func _batch_comparison(recipe: Dictionary, batched: Node3D, bounds: AABB, variant: String) -> void:
	var unbatched := Generator.build(recipe, false)
	var label := str(recipe.species) + "/" + variant
	_check(bool(unbatched.ok), label + " 合批关闭对照可构建")
	if not unbatched.ok:
		return
	var source: Node3D = unbatched.root
	var a := _counts(source)
	var b := _counts(batched)
	_check(a.triangles == b.triangles and a.vertices == b.vertices, label + " 合批不增删三角形或顶点")
	_check(b.surfaces < a.surfaces, label + " 同模式合批减少surfaces")
	var stage := _stage()
	var camera: Camera3D = stage.camera
	var viewport: SubViewport = stage.viewport
	camera.size = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.18
	camera.position = bounds.get_center() + Vector3(1.1, 0.6, 1.5).normalized() * 20.0
	camera.look_at(bounds.get_center())
	var measurements: Array = []
	var images: Array[Image] = []
	for model: Node3D in [source, batched]:
		stage.scene.add_child(model)
		Wind.apply_sample(Wind.prepare(model), 0.0, 0.0, Vector2(0.86, 0.5), false)
		images.append(await _image(viewport))
		var calls: Array = []
		for frame in 5:
			await process_frame
			RenderingServer.force_draw(false)
			calls.append(RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		measurements.append(_distribution(calls))
		stage.scene.remove_child(model)
	_check(measurements[0].min > 0 and measurements[1].min > 0 and measurements[1].p50 < measurements[0].p50, label + " 同模式同镜头合批开关实际drawcall下降")
	report.batch_comparisons.append({"species": recipe.species, "mode": variant, "foliage_mode": recipe.foliage_mode, "unbatched_draw_calls": measurements[0],
		"batched_draw_calls": measurements[1], "changed_pixels": _changed_pixels(images[0], images[1]),
		"unbatched_image": _save_image(images[0], str(recipe.species) + "_" + variant + "_unbatched"),
		"batched_image": _save_image(images[1], str(recipe.species) + "_" + variant + "_batched"),
		"note": "同配方仅切batch_foliage；五帧force_draw仅比较实际drawcall，不是FPS或自然帧耗时基准，像素差保留供检查"})
	source.free()
	viewport.free()

func _distribution(values: Array) -> Dictionary:
	if values.is_empty():
		return {"available": false}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in sorted:
		total += value
	return {"available": true, "min": sorted[0], "max": sorted[-1], "mean": total / sorted.size(),
		"p50": sorted[int(ceil(sorted.size() * 0.50)) - 1], "p95": sorted[int(ceil(sorted.size() * 0.95)) - 1]}

func _on_benchmark_draw() -> void:
	benchmark_draw_usec = Time.get_ticks_usec()
	benchmark_draw_count += 1

func _benchmark() -> void:
	# macOS 被遮挡窗口可能停止自然绘制；仅采样开始前请求前台，不强制绘制或改步长。
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_title("sea 树冠性能验收 · 自然渲染")
	DisplayServer.window_move_to_foreground()
	root.grab_focus()
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	OS.low_processor_usage_mode = false
	ProjectSettings.set_setting("application/run/low_processor_usage_mode_sleep_usec", 0)
	ProjectSettings.set_setting("application/run/low_processor_usage_mode_sleep_usec_unfocused", 0)
	ProjectSettings.set_setting("application/run/frame_delay_msec", 0)
	_check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "基准关闭VSync")
	_check(get_nodes_in_group(Wind.OWNER_GROUP).is_empty(), "基准没有外部风owner")
	if not get_nodes_in_group(Wind.OWNER_GROUP).is_empty():
		return
	report.benchmark.merge({"species": "birch", "seed": 24117, "resolution": [1280, 800], "msaa": "4x", "shadows": false,
		"variants": {"volumes": {"foliage_mode": "volumes", "volume_leaf_cards": 12}, "volumes_pure": {"foliage_mode": "volumes", "volume_leaf_cards": 0},
			"cards": {"foliage_mode": "cards"}, "geometry": {"foliage_mode": "geometry", "leaf_geometry": "balanced"}},
		"minimum_warmup_seconds": 2.2, "minimum_sample_seconds": 2.2, "minimum_sample_frames": MIN_SAMPLE_FRAMES,
		"no_draw_timeout_seconds": 10, "round_timeout_seconds": 60,
		"watchdog_note": "逻辑帧检查自然draw计数；无draw不采样，停绘/超时保留样本并终止整bench；引擎主线程完全阻塞时只能恢复后检测或由runner外部超时处理",
		"rounds": 2, "orders": [VARIANTS, ["geometry", "volumes_pure", "cards", "volumes"]], "vsync_disabled": true, "fixed_fps": false,
		"resource_policy": "Store.save_animated真实磁盘PackedScene；不改Mesh/Material local_to_scene，不强制共享；每实例_ready/_process推进fallback风；加载/实例化不计入稳定帧",
		"cpu_note": "TIME_PROCESS是周期更新的进程监视器，不是逐帧独立CPU时间；数组字节不是显存，静态峰值为进程累计",
		"gpu_note": "异步视口GPU计时；零/常数/非有限值均标未测，不由CPU或FPS推算",
		"presentation": "真实SubViewport纹理显示于前台置顶宿主窗口；各模式同成本，非隐藏/遮挡窗口；自然draw无force_draw",
		"os": OS.get_name(), "processor": OS.get_processor_name(), "device": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method()})
	RenderingServer.frame_post_draw.connect(_on_benchmark_draw)
	for count in [1, 16, 64]:
		for round_index in 2:
			var modes := VARIANTS if round_index == 0 else ["geometry", "volumes_pure", "cards", "volumes"]
			for mode: String in modes:
				if mode == "geometry" and count == 64:
					continue
				var key := "birch/" + mode
				_check(saved_scenes.has(key), "基准需要真实已保存旁车 " + key)
				if not saved_scenes.has(key):
					report.benchmark.stopped_reason = "缺少真实保存旁车 " + key
					RenderingServer.frame_post_draw.disconnect(_on_benchmark_draw)
					_write_progress("benchmark_stopped_missing_scene")
					return
				_write_progress("benchmark_start/" + mode + "/" + str(count) + "/" + str(round_index + 1))
				var result := await _benchmark_run(saved_scenes[key], mode, count, round_index)
				report.benchmark.runs.append(result)
				print("[plant-canopy] BENCH " + JSON.stringify(result.merged({"samples": "详见专项JSON"}, true)))
				_write_progress("benchmark_round/" + mode + "/" + str(count) + "/" + str(round_index + 1))
				if not bool(result.get("samples_complete", false)):
					report.benchmark.stopped_reason = str(result.get("incomplete_reason", "轮次不完整"))
					report.fps_measured = false
					RenderingServer.frame_post_draw.disconnect(_on_benchmark_draw)
					return
	RenderingServer.frame_post_draw.disconnect(_on_benchmark_draw)
	for count in [1, 16, 64]:
		for mode: String in VARIANTS:
			if mode == "geometry" and count == 64:
				continue
			var pooled: Dictionary = {}
			var rounds := 0
			var gpu_available := true
			for run: Dictionary in report.benchmark.runs:
				if run.get("count") != count or run.get("mode") != mode or not run.has("samples"):
					continue
				rounds += 1
				gpu_available = gpu_available and bool(run.gpu_ms.available)
				for metric: String in run.samples:
					if not pooled.has(metric): pooled[metric] = []
					pooled[metric].append_array(run.samples[metric])
			_check(rounds == 2, "两轮基准完整 " + mode + str(count))
			if rounds != 2:
				continue
			var summary := {"mode": mode, "count": count, "rounds": rounds}
			for metric: String in pooled:
				if metric != "gpu_ms_raw": summary[metric] = _distribution(pooled[metric])
			summary.gpu_ms = _distribution(pooled.gpu_ms_raw) if gpu_available else {"available": false, "reason": "未测：至少一轮GPU计时不可信"}
			report.benchmark.summary.append(summary)
	_compare_benchmarks()
	report.fps_measured = report.benchmark.runs.size() == 22
	for run: Dictionary in report.benchmark.runs:
		report.fps_measured = report.fps_measured and bool(run.get("samples_complete", false)) and bool(run.get("passed", false)) and not bool(run.get("watchdog_triggered", true))

func _benchmark_run(path: String, mode: String, count: int, round_index: int) -> Dictionary:
	var round_started := Time.get_ticks_usec()
	var failures_before := failures
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	_check(packed != null, "基准从磁盘加载动态旁车")
	if packed == null:
		return {"mode": mode, "count": count, "round": round_index + 1, "samples_complete": false, "passed": false, "incomplete_reason": "旁车无法重载"}
	var stage := _stage()
	var viewport: SubViewport = stage.viewport
	var camera: Camera3D = stage.camera
	# 将真实SubViewport呈现在窗口，避免空白宿主窗口被macOS判为无需绘制。
	# 所有模式均有同一呈现成本；采样仍只使用自然draw回调，不force_draw。
	var presentation := TextureRect.new()
	presentation.texture = viewport.get_texture()
	presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(presentation)
	presentation.size = Vector2(root.size)
	var side := int(ceil(sqrt(count)))
	var extent := (side - 1) * 6.5
	var layouts := PackedVector3Array()
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	var instances: Array[Node3D] = []
	var per_instance_resources: Array = []
	var instantiate_started := Time.get_ticks_usec()
	for index in count:
		var instance := packed.instantiate() as Node3D
		instance.position = Vector3((index % side) * 6.5 - extent * 0.5, 0.0, int(index / side) * 6.5 - extent * 0.5)
		layouts.append(instance.position)
		stage.scene.add_child(instance)
		instances.append(instance)
		_check(instance.get_script() == Wind and instance.is_processing(), "默认动态脚本自动运行，不做共享替换")
		_resources(instance, meshes, materials)
		var own_meshes: Dictionary = {}
		var own_materials: Dictionary = {}
		_resources(instance, own_meshes, own_materials)
		per_instance_resources.append({"meshes": own_meshes.size(), "materials": own_materials.size()})
		if Time.get_ticks_usec() - round_started >= ROUND_TIMEOUT_USEC:
			break
	var instantiate_ms := (Time.get_ticks_usec() - instantiate_started) / 1000.0
	camera.size = (extent + 14.0) * 1.2
	var target := Vector3(0.0, 4.7, 0.0)
	camera.position = target + Vector3(0.32, 1.15, 1.5).normalized() * 130.0
	camera.look_at(target)
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var samples := {"wall_frame_ms": [], "cpu_process_ms": [], "viewport_render_cpu_ms": [], "gpu_ms_raw": [], "draw_calls": [], "primitives": [], "objects": []}
	var warmup_start := Time.get_ticks_usec()
	var sample_start := 0
	var previous := 0
	var warmup_frames := 0
	var sampled_frames := 0
	var initial_times: Array[float] = []
	for material: Material in materials.values():
		if material is ShaderMaterial:
			initial_times.append(float(material.get_shader_parameter("local_time")))
	var observed_draw_count := benchmark_draw_count
	var last_draw := warmup_start
	var incomplete_reason := ""
	var watchdog_triggered := false
	var missed_draws := 0
	var largest_draw_gap_usec := 0
	# 信号回调仅记录时刻/计数；逻辑帧不等draw，只有新draw才读取样本。
	# 不force_draw、不删长帧，不把没有画面的逻辑帧伪装成渲染样本。
	while true:
		var wall_now := Time.get_ticks_usec()
		if wall_now - round_started >= ROUND_TIMEOUT_USEC:
			incomplete_reason = "轮次超过60秒上限（含加载/实例化）"
			watchdog_triggered = true
			break
		await process_frame
		wall_now = Time.get_ticks_usec()
		if benchmark_draw_count != observed_draw_count:
			var draw_delta := benchmark_draw_count - observed_draw_count
			missed_draws += maxi(0, draw_delta - 1)
			observed_draw_count = benchmark_draw_count
			var now := benchmark_draw_usec
			var gap := now - last_draw
			largest_draw_gap_usec = maxi(largest_draw_gap_usec, gap)
			last_draw = now
			if sample_start == 0:
				warmup_frames += 1
				if warmup_frames >= 30 and now - warmup_start >= MIN_WINDOW_USEC:
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
			if gap >= NO_DRAW_TIMEOUT_USEC:
				incomplete_reason = "自然draw间隔达到10秒；恢复后的长帧样本已保留"
				watchdog_triggered = true
		if wall_now - last_draw >= NO_DRAW_TIMEOUT_USEC:
			incomplete_reason = "逻辑帧仍运行但超过10秒无自然draw"
			watchdog_triggered = true
		if wall_now - round_started >= ROUND_TIMEOUT_USEC:
			incomplete_reason = "轮次超过60秒上限（含加载/实例化）"
			watchdog_triggered = true
		if missed_draws > 0 and incomplete_reason.is_empty():
			incomplete_reason = "逻辑帧未逐一观测draw，不可冒充完整逐帧样本"
		if not incomplete_reason.is_empty(): break
		if sample_start > 0 and sampled_frames >= MIN_SAMPLE_FRAMES and previous - sample_start >= MIN_WINDOW_USEC:
			break
	var finished := Time.get_ticks_usec()
	var sample_elapsed := previous - sample_start if sample_start > 0 else 0
	var samples_complete := incomplete_reason.is_empty() and sample_start > 0 and sampled_frames >= MIN_SAMPLE_FRAMES and sample_elapsed >= MIN_WINDOW_USEC
	var result := {"mode": mode, "count": count, "round": round_index + 1, "samples": samples,
		"samples_complete": samples_complete, "incomplete_reason": incomplete_reason, "watchdog_triggered": watchdog_triggered,
		"missed_draws": missed_draws, "largest_draw_gap_ms": largest_draw_gap_usec / 1000.0,
		"undrawn_tail_ms": (finished - last_draw) / 1000.0, "round_wall_ms": (finished - round_started) / 1000.0,
		"source_scene": path, "instantiate_ms": instantiate_ms, "runtime_instances": instances.size(),
		"warmup_frames": warmup_frames, "sample_frames": sampled_frames, "warmup_wall_ms": ((sample_start if sample_start > 0 else finished) - warmup_start) / 1000.0,
		"sample_wall_ms": sample_elapsed / 1000.0, "observed_throughput_fps": sampled_frames * 1000000.0 / sample_elapsed if samples_complete and sample_elapsed > 0 else null,
		"layout_sha256": var_to_bytes(layouts).hex_encode().sha256_text(), "camera_transform": str(camera.transform), "camera_size": camera.size,
		"unique_mesh_resources": meshes.size(), "unique_material_resources": materials.size(), "per_instance_resources": per_instance_resources,
		"cpu_static_bytes": OS.get_static_memory_usage(), "cpu_process_peak_bytes": OS.get_static_memory_peak_usage(), "window_focused": root.has_focus()}
	for metric: String in samples:
		if metric != "gpu_ms_raw": result[metric] = _distribution(samples[metric])
	var gpu := _distribution(samples.gpu_ms_raw)
	var gpu_valid: bool = not samples.gpu_ms_raw.is_empty()
	for value: float in samples.gpu_ms_raw:
		gpu_valid = gpu_valid and is_finite(value) and value > 0.0
	result.gpu_ms = gpu if gpu_valid and float(gpu.max) > float(gpu.min) else {"available": false, "reason": "未测：驱动无可信非零变化样本"}
	_check(samples_complete, "自然帧轮次完整 " + mode + str(count) + " " + incomplete_reason)
	_check(float(result.draw_calls.get("min", 0)) > 0 and float(result.primitives.get("min", 0)) > 0 and float(result.objects.get("min", 0)) > 0, "真实渲染提交非零 " + mode + str(count))
	_check(result.sample_frames >= MIN_SAMPLE_FRAMES and result.warmup_wall_ms >= 2200.0 and result.sample_wall_ms >= 2200.0, "预热/采样时间及帧数达标")
	result.stable_window_valid = bool(result.wall_frame_ms.available) and float(result.wall_frame_ms.get("min", 0)) > 0.0 and float(result.wall_frame_ms.get("max", INF)) < 1000.0
	_check(result.stable_window_valid and largest_draw_gap_usec < 1000000, "自然绘制无1秒挂起（含预热）；异常样本保留且失败")
	var active := true
	var index := 0
	var min_time := INF
	var max_time := 0.0
	for material: Material in materials.values():
		if material is ShaderMaterial:
			var seconds := float(material.get_shader_parameter("local_time"))
			active = active and bool(material.get_shader_parameter("preview_wind")) and seconds > initial_times[index]
			min_time = minf(min_time, seconds)
			max_time = maxf(max_time, seconds)
			index += 1
	_check(index > 0 and active and max_time - min_time < 0.001, "真实逐实例fallback时钟推进且相位一致")
	result.wind_time_min = min_time
	result.wind_time_max = max_time
	if round_index == 0 and samples_complete:
		result.screenshot = _save_image(viewport.get_texture().get_image(), "bench_birch_%s_%d" % [mode, count])
	result.passed = samples_complete and failures == failures_before
	RenderingServer.viewport_set_measure_render_time(rid, false)
	presentation.free()
	viewport.free()
	instances.clear()
	meshes.clear()
	materials.clear()
	packed = null
	await process_frame
	return result

func _compare_benchmarks() -> void:
	for count in [1, 16]:
		for round_index in 2:
			var baseline: Dictionary = {}
			for run: Dictionary in report.benchmark.runs:
				if run.count == count and run.mode == "geometry" and run.round == round_index + 1 and run.has("samples"):
					baseline = run
			if baseline.is_empty():
				_check(false, "缺少geometry同轮对照 " + str(count))
				continue
			for run: Dictionary in report.benchmark.runs:
				if run.count != count or run.mode == "geometry" or run.round != round_index + 1 or not run.has("samples"):
					continue
				_check(run.layout_sha256 == baseline.layout_sha256 and run.camera_transform == baseline.camera_transform and run.camera_size == baseline.camera_size, "合批对照同布局同镜头 " + str(count) + run.mode)
				_check(run.draw_calls.p50 < baseline.draw_calls.p50, "实际drawcall必须低于geometry/balanced，不以surface估算 " + run.mode + str(count))
				var comparison := {"count": count, "round": round_index + 1, "mode": run.mode,
					"draw_calls_ratio": float(run.draw_calls.p50) / float(baseline.draw_calls.p50),
					"wall_p50_ratio": run.wall_frame_ms.p50 / baseline.wall_frame_ms.p50,
					"wall_p95_ratio": run.wall_frame_ms.p95 / baseline.wall_frame_ms.p95,
					"p50_regressed": run.wall_frame_ms.p50 > baseline.wall_frame_ms.p50,
					"p95_regressed": run.wall_frame_ms.p95 > baseline.wall_frame_ms.p95}
				report.benchmark.comparisons.append(comparison)
				print("[plant-canopy] COMPARE " + JSON.stringify(comparison))
