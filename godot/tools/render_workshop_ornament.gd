extends SceneTree
## 承重柱与腰线出图：正立面 / 斜角 / 转角近景 / 楼层节点近景。
## 柱与墙同色，只有斜角和近景才看得出凸出——正视不是验收机位。

const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")

const SIZE := Vector2i(1500, 1150)

func _initialize() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var out_dir: String = str(args[0]) if args.size() > 0 else "D:/projects/sea-work/building_workshop/ornament_v001"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var jobs: Array = [
		{"name": "orn_all", "pilaster": [true, true, true], "band": [true, 0.09, 0.26]},
		{"name": "orn_none", "pilaster": [false, false, false], "band": [false, 0.09, 0.26]},
		{"name": "orn_corner", "pilaster": [true, true, false], "band": [true, 0.09, 0.26]},
		{"name": "orn_middle", "pilaster": [true, false, true], "band": [true, 0.09, 0.26]},
		{"name": "orn_band_off", "pilaster": [true, true, true], "band": [false, 0.09, 0.26]},
		{"name": "orn_deep", "pilaster": [true, true, true], "band": [true, 0.20, 0.34]},
		{"name": "orn_flat", "pilaster": [true, true, true], "band": [true, 0.04, 0.14]}
	]
	for job in jobs:
		await _shot(job, out_dir)
	quit()

func _recipe(job: Dictionary) -> Dictionary:
	var r: Dictionary = Recipe.authoring_defaults()
	r["building_id"] = "orn_" + str(job.name)
	r["taper"] = 0.0
	var arch: Dictionary = (r["architecture"] as Dictionary).duplicate(true)
	arch["form"]["enabled"] = false
	var p: Array = job.pilaster
	arch["pilaster"] = {"enabled": bool(p[0]), "corner": bool(p[1]), "middle": bool(p[2]),
		"width": 0.36, "projection": 0.18, "bite": 0.06, "bevel": 0.014}
	var b: Array = job.band
	arch["band"] = {"enabled": bool(b[0]), "projection": float(b[1]), "thickness": float(b[2]), "bevel": 0.010}
	r["architecture"] = arch
	return r

func _shot(job: Dictionary, out_dir: String) -> void:
	var recipe: Dictionary = _recipe(job)
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
	environment.ambient_light_color = Color(0.58, 0.63, 0.72)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = environment
	world.add_child(world_env)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	# 斜射光：柱子要投影才看得见，正面平光下同色柱会和墙糊成一片。
	key_light.rotation_degrees = Vector3(-38.0, -52.0, 0.0)
	key_light.light_energy = 1.6
	key_light.shadow_enabled = true
	key_light.shadow_blur = 1.5
	world.add_child(key_light)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_energy = 0.35
	world.add_child(fill)
	world.add_child(root)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 32.0
	camera.far = 400.0
	world.add_child(camera)
	var depth_half: float = float(recipe.get("depth", 9.0)) * 0.5
	var width_half: float = float(recipe.get("width", 12.0)) * 0.5
	# 斜角：柱的正面与侧面明暗分开，凸出量才读得出来。
	await _capture(viewport, camera, out_dir, str(job.name) + "_three_quarter",
		Vector3(width_half + 15.0, 10.5, -(depth_half + 18.0)), Vector3(0.0, 4.6, 0.0))
	# 转角近景：一根角柱 + 一段腰线。机位要低、要正对转角，斜射光才把柱的侧面照出来。
	await _capture(viewport, camera, out_dir, str(job.name) + "_corner",
		Vector3(width_half + 2.6, 3.3, -(depth_half + 2.6)), Vector3(width_half - 0.35, 3.9, -(depth_half - 0.35)))
	# 楼层节点近景：腰线与上下层的关系。
	await _capture(viewport, camera, out_dir, str(job.name) + "_joint",
		Vector3(-2.6, 4.5, -(depth_half + 7.0)), Vector3(-2.6, 3.6, -depth_half))
	print("SAVED ", job.name)

func _capture(viewport: SubViewport, camera: Camera3D, out_dir: String, name: String, eye: Vector3, focus: Vector3) -> void:
	camera.look_at_from_position(eye, focus)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
