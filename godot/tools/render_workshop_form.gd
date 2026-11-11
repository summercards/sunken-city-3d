extends SceneTree
## 形体对比出图：同一机位下 关形体 / 三档区间 / 三个种子，用于目检"变形是否可调且克制"。

const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const Config = preload("res://src/workshop/architecture_config.gd")

const SIZE := Vector2i(1400, 1100)

func _initialize() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var out_dir: String = str(args[0]) if args.size() > 0 else "D:/projects/sea-work/building_workshop/form_v001"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# 8° 倾角下：12×9×3层可用收分约12.6%，瘦高 9×9×8层约24%，都能把幅度调到肉眼可见。
	var tall: bool = args.size() > 1 and str(args[1]) == "tall"
	var jobs: Array = [
		{"name": "form_tall_off", "enabled": false, "seed": 11010, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "mixed", "tall": true},
		{"name": "form_tall_sfb", "enabled": true, "seed": 11010, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "mixed", "tall": true},
		{"name": "form_tall_sfc", "enabled": true, "seed": 11010, "structure": [0.080, 0.100], "opening": [0.060, 0.100], "accessory": [0.090, 0.150], "sign": "mixed", "tall": true},
		{"name": "form_off", "enabled": false, "seed": 11010, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "mixed"},
		{"name": "form_sfa", "enabled": true, "seed": 11010, "structure": [0.020, 0.040], "opening": [0.020, 0.038], "accessory": [0.025, 0.060], "sign": "mixed"},
		{"name": "form_sfb", "enabled": true, "seed": 11010, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "mixed"},
		{"name": "form_sfc", "enabled": true, "seed": 11010, "structure": [0.060, 0.100], "opening": [0.055, 0.095], "accessory": [0.080, 0.150], "sign": "mixed"},
		{"name": "form_sign_positive", "enabled": true, "seed": 11010, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "positive"},
		{"name": "form_sign_negative", "enabled": true, "seed": 11010, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "negative"},
		{"name": "form_seed_1", "enabled": true, "seed": 1, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "mixed"},
		{"name": "form_seed_2", "enabled": true, "seed": 2, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "mixed"},
		{"name": "form_seed_3", "enabled": true, "seed": 3, "structure": [0.030, 0.060], "opening": [0.030, 0.060], "accessory": [0.040, 0.100], "sign": "mixed"}
	]
	for job in jobs:
		await _shot(job, out_dir)
	quit()

func _recipe(job: Dictionary) -> Dictionary:
	var r: Dictionary = Recipe.authoring_defaults()
	r["building_id"] = "form_" + str(job.name)
	if bool(job.get("tall", false)):
		r["width"] = 9.0
		r["depth"] = 9.0
		r["floors"] = 8
		r["bay_width"] = 3.0
	var architecture: Dictionary = (r["architecture"] as Dictionary).duplicate(true)
	var form: Dictionary = (architecture["form"] as Dictionary).duplicate(true)
	form["enabled"] = bool(job.enabled)
	form["seed"] = int(job.seed)
	form["max_tilt_deg"] = 8.0
	for category in ["structure", "opening", "accessory"]:
		var bounds: Array = job[category]
		var sign_mode: String = "positive" if category != "opening" else str(job.get("sign", "mixed"))
		form[category] = {"min": float(bounds[0]), "max": float(bounds[1]), "sign": sign_mode}
	architecture["form"] = form
	r["architecture"] = architecture
	return r

func _shot(job: Dictionary, out_dir: String) -> void:
	var recipe: Dictionary = _recipe(job)
	var resolved: Dictionary = Config.resolve_form(Recipe.normalized(recipe))
	var build: Dictionary = Generator.build(recipe, Catalog.definitions())
	if not bool(build.get("ok", false)):
		print("SKIP ", job.name, " ", build.get("reason"))
		return
	var root: Node3D = build.get("root") as Node3D
	var viewport: SubViewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var world_env: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.105, 0.115, 0.135)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.60, 0.65, 0.74)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = environment
	world.add_child(world_env)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-46.0, -40.0, 0.0)
	key_light.light_energy = 1.45
	key_light.shadow_enabled = true
	world.add_child(key_light)
	world.add_child(root)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 30.0
	camera.far = 400.0
	world.add_child(camera)
	# 同一机位，便于叠图比较形变幅度。
	var tall_factor: float = 2.0 if bool(job.get("tall", false)) else 1.0
	camera.look_at_from_position(Vector3(0.0, 6.6 * tall_factor, -40.0 * tall_factor), Vector3(0.0, 5.2 * tall_factor, 0.0))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var path: String = out_dir.path_join(str(job.name) + ".png")
	image.save_png(path)
	# 低机位仰视：整楼收分在轮廓上才看得见，正视几乎不可察（这是"克制"的必然结果）。
	camera.look_at_from_position(Vector3(-9.0 * tall_factor, 1.6, -20.0 * tall_factor), Vector3(0.0, 8.4 * tall_factor, 0.0))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var up: Image = viewport.get_texture().get_image()
	var up_path: String = out_dir.path_join(str(job.name) + "_up.png")
	up.save_png(up_path)
	# 窗洞特写：正面贴墙拍首层中间三个开间，梯形方向在这一档才看得清（整楼图里只有几个像素）。
	var depth_half: float = float(recipe.get("depth", 9.0)) * 0.5
	camera.fov = 30.0
	camera.look_at_from_position(Vector3(0.0, 3.05, -(depth_half + 15.0)), Vector3(0.0, 2.85, -depth_half))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var closeup: Image = viewport.get_texture().get_image()
	var closeup_path: String = out_dir.path_join(str(job.name) + "_windows.png")
	closeup.save_png(closeup_path)
	print("SAVED ", path, " structure=", snappedf(float(resolved.get("structure", 0.0)), 0.0001), " opening=", snappedf(float(resolved.get("opening", 0.0)), 0.0001), " accessory=", snappedf(float(resolved.get("accessory", 0.0)), 0.0001))
	viewport.queue_free()
	await process_frame
