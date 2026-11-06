extends SceneTree
## 只读旧城真实几何，生成持久化 Terrain3D 高度图；不运行游戏逻辑。
const DATA_DIR := "res://terrain/sunken_seabed"
const SCENE_PATH := "res://scenes/world/sunken_seabed.tscn"
const MATERIAL_PATH := "res://assets/materials/sunken_city/seabed_material.tres"
const STEP := 2.0
const SIZE := 256
const OUTER_Y := -62.0
const PLATFORM := 12.0
const SLOPE := 96.0
const GAP := 0.15
var grounds: Array[Dictionary] = []
var bounds := Rect2()
var checks := 0
var failures: Array[String] = []
var city: Node3D
var surface_cache: Dictionary = {}

func cached_hits(x: float, z: float) -> Vector2:
	var key := Vector2(x, z)
	if not surface_cache.has(key):
		surface_cache[key] = ground_hits(x, z)
	return surface_cache[key]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _init() -> void:
	call_deferred("run")

func read_ground_geometry() -> void:
	# 仅读取主场景序列化变换，不加载 main 脚本及其游戏依赖。
	var text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var pattern := RegEx.new()
	pattern.compile('\\[node name="SunkenCity"[^\\n]*\\]\\ntransform = Transform3D\\(([^\\n]+)\\)')
	var matched := pattern.search(text)
	var city_transform := Transform3D.IDENTITY
	check(matched != null, "读取主场景真实城市变换")
	if matched != null:
		var values := matched.get_string(1).split(",")
		city_transform = Transform3D(Vector3(float(values[0]), float(values[1]), float(values[2])), Vector3(float(values[3]), float(values[4]), float(values[5])), Vector3(float(values[6]), float(values[7]), float(values[8])), Vector3(float(values[9]), float(values[10]), float(values[11])))
	city = (load("res://scenes/world/sunken_city.tscn") as PackedScene).instantiate()
	city.transform = city_transform
	root.add_child(city)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for ground in city.get_children():
		if ground.get_meta("urban_role", "") != "aligned_ground_domain":
			continue
		var faces := PackedVector3Array()
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		for child in ground.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := child as MeshInstance3D
			for vertex in mesh_node.mesh.get_faces():
				var point: Vector3 = mesh_node.global_transform * vertex
				faces.append(point)
				minimum = minimum.min(point)
				maximum = maximum.max(point)
		var triangle := TriangleMesh.new()
		triangle.create_from_faces(faces)
		grounds.append({"id": str(ground.name), "key": str(ground.get_meta("key", "")), "triangles": triangle, "min": minimum, "max": maximum})
		low = low.min(Vector2(minimum.x, minimum.z))
		high = high.max(Vector2(maximum.x, maximum.z))
	bounds = Rect2(low, high - low)

func ground_hits(x: float, z: float) -> Vector2:
	var bottom := INF
	var top := -INF
	for ground in grounds:
		var lo: Vector3 = ground["min"]
		var hi: Vector3 = ground["max"]
		if x < lo.x - 0.001 or x > hi.x + 0.001 or z < lo.z - 0.001 or z > hi.z + 0.001:
			continue
		var triangle: TriangleMesh = ground["triangles"]
		var below := triangle.intersect_ray(Vector3(x, -200.0, z), Vector3.UP)
		var above := triangle.intersect_ray(Vector3(x, 200.0, z), Vector3.DOWN)
		if not below.is_empty() and not above.is_empty():
			bottom = minf(bottom, below["position"].y)
			top = maxf(top, above["position"].y)
	return Vector2(bottom, top)

func seabed_height(x: float, z: float) -> float:
	var cx := clampf(x, bounds.position.x + 0.001, bounds.end.x - 0.001)
	var cz := clampf(z, bounds.position.y + 0.001, bounds.end.y - 0.001)
	var distance := Vector2(x - cx, z - cz).length()
	if distance >= PLATFORM + SLOPE:
		return OUTER_Y
	# z=84贯穿完整的薄底街道坡道，按真实geometry取连续x断面；厚楔体底部台阶不复制为陡坎。
	var profile := cached_hits(cx, 84.0)
	var height := profile.x - GAP
	# 运河真实表面低于街道断面；16m邻域包络提供插值净空并平滑连接。
	var near_canal := cx >= -90.0 and cx <= 66.0
	for dz in (range(-16, 17) if near_canal else []):
		for dx in range(-16, 17):
			var point := Vector2(clampf(cx + dx, bounds.position.x + 0.001, bounds.end.x - 0.001), clampf(cz + dz, bounds.position.y + 0.001, bounds.end.y - 0.001))
			var hit := cached_hits(point.x, point.y)
			if is_finite(hit.y) and hit.y < cached_hits(point.x, 84.0).x + 0.25:
				height = minf(height, hit.y - 0.85 + Vector2(cx, cz).distance_to(point) * 0.25)
	var t := clampf((distance - PLATFORM) / SLOPE, 0.0, 1.0)
	return lerpf(height, OUTER_Y, t * t * (3.0 - 2.0 * t))

func run() -> void:
	read_ground_geometry()
	check(city.get_child_count() == 388, "原388旧城实例保留")
	check(grounds.size() == 100, "只读100个真实ground几何")
	var destination := OS.get_environment("SEA_SEABED_AUTHOR_ROOT")
	check(not destination.is_empty(), "作者输出根目录明确指定")
	if destination.is_empty():
		quit(1)
		return
	var terrain := Terrain3D.new()
	terrain.name = "SunkenSeabed"
	terrain.region_size = SIZE
	terrain.vertex_spacing = STEP
	terrain.collision_mode = 0
	terrain.free_editor_textures = false
	terrain.mesh_size = 256
	terrain.material = load(MATERIAL_PATH)
	terrain.assets = Terrain3DAssets.new()
	for key in ["visual_only"]:
		terrain.set_meta(key, true)
	terrain.set_meta("water_layer", "submerged")
	terrain.set_meta("water_layer_role", "none")
	for key in ["collision", "blocks_water", "shoreline_source"]:
		terrain.set_meta(key, false)
	var output_data := destination.path_join("terrain/sunken_seabed")
	DirAccess.make_dir_recursive_absolute(output_data)
	var albedo := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	albedo.fill(Color(0.14, 0.20, 0.19, 1.0))
	var normal := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 1.0, 1.0))
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var texture := Terrain3DTextureAsset.new()
	texture.name = "海床哑光"
	var albedo_texture := ImageTexture.create_from_image(albedo)
	var normal_texture := ImageTexture.create_from_image(normal)
	check(ResourceSaver.save(albedo_texture, DATA_DIR.path_join("albedo.res")) == OK, "独立albedo纹理保存")
	check(ResourceSaver.save(normal_texture, DATA_DIR.path_join("normal.res")) == OK, "独立normal纹理保存")
	texture.albedo_texture = load(DATA_DIR.path_join("albedo.res"))
	texture.normal_texture = load(DATA_DIR.path_join("normal.res"))
	terrain.assets.set_texture_asset(0, texture)
	root.add_child(terrain)
	terrain.material.show_checkered = false
	var samples := 0
	var zero_samples := 0
	var low := INF
	var high := -INF
	for rz in range(-1, 1):
		for rx in range(-1, 1):
			var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RF)
			for iz in SIZE:
				for ix in SIZE:
					var height := seabed_height(float(rx * SIZE + ix) * STEP, float(rz * SIZE + iz) * STEP)
					image.set_pixel(ix, iz, Color(height, 0, 0, 1))
					samples += 1
					zero_samples += int(is_zero_approx(height))
					low = minf(low, height)
					high = maxf(high, height)
			var images: Array[Image] = [image, null, null]
			terrain.data.import_images(images, Vector3(rx * SIZE * STEP, 0, rz * SIZE * STEP), 0.0, 1.0)
	check(samples == 262144 and zero_samples == 0, "四region全部262144像素写满且无0高度")
	terrain.data.save_directory(output_data)
	check(ResourceSaver.save(terrain.assets, DATA_DIR.path_join("assets.tres")) == OK, "独立Terrain3DAssets持久化")
	# 不在存活Terrain上重载刚写出的数据，避免扩展重入崩溃；打包文本声明标准目录。
	terrain.show_checkered = false
	var packed := PackedScene.new()
	check(packed.pack(terrain) == OK, "Terrain3D场景序列化")
	var scene_file := destination.path_join("scenes/world/sunken_seabed.tscn")
	check(ResourceSaver.save(packed, scene_file) == OK, "保存正式海床场景")
	# Terrain3D编辑/运行默认值不同，必须显式序列化collision_mode=0。
	var scene_text := FileAccess.get_file_as_string(scene_file)
	scene_text = scene_text.replace("\nmaterial =", '\ndata_directory = "' + DATA_DIR + '"\nshow_checkered = false\nmaterial =')
	if not "\ncollision_mode =" in scene_text:
		scene_text = scene_text.replace("\nvertex_spacing = 2.0", "\nvertex_spacing = 2.0\ncollision_mode = 0")
	FileAccess.open(scene_file, FileAccess.WRITE).store_string(scene_text)
	var profiles := {}
	for z in [-108.0, -84.0, 0.0, 84.0, 108.0]:
		var samples_x := []
		for x in range(-120, 121):
			samples_x.append([x, ground_hits(float(x), z).x, ground_hits(float(x), z).y])
		profiles[str(z)] = samples_x
	FileAccess.open(OS.get_environment("SEA_SEABED_EVIDENCE").path_join("geometry_profiles.json"), FileAccess.WRITE).store_string(JSON.stringify(profiles))
	var geometry: Array[Dictionary] = []
	for ground in grounds:
		geometry.append({"id": ground["id"], "min": str(ground["min"]), "max": str(ground["max"])})
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "samples": samples,
		"zero_samples": zero_samples, "region_count": terrain.data.get_region_count(), "domain": "[-512,512) x [-512,512)",
		"height_range": [low, high], "ground_count": grounds.size(), "city_instances": city.get_child_count(),
		"city_transform": str(city.transform), "ground_bounds": str(bounds), "platform_m": PLATFORM, "slope_m": SLOPE,
		"bottom_gap_m": GAP, "outer_y": OUTER_Y, "geometry": geometry, "autoload_disabled": root.get_child_count() == 2}
	var evidence := OS.get_environment("SEA_SEABED_EVIDENCE")
	FileAccess.open(evidence.path_join("authoring.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	terrain.queue_free()
	city.queue_free()
	await process_frame
	print("[seabed-authoring-final] ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
