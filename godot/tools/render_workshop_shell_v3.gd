extends SceneTree
## 交付用模型渲染：按整栋大图 + 局部近景分别出图，供人工目检。
## 只读 src/workshop 生成结果；输出到 sea-work，不写工程内资源。

const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")

const SIZE := Vector2i(1600, 1200)

func _initialize() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var out_dir: String = str(args[0]) if args.size() > 0 else "D:/projects/sea-work/building_workshop/shell_v3"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var design: Dictionary = _design()
	await _shot(design, out_dir, "rect_three_quarter", Vector3(24.0, 15.0, 26.0), Vector3(0.0, 5.4, 0.0), 34.0, "rect")
	# 门与雨棚在 -Z 立面（_facade 把 -Z 记为 front）；正面图必须看 -Z，否则交付图会漏掉入口构造。
	await _shot(design, out_dir, "rect_front", Vector3(0.0, 7.0, -30.0), Vector3(0.0, 5.4, 0.0), 30.0, "rect")
	await _shot(design, out_dir, "rect_back", Vector3(0.0, 7.0, 30.0), Vector3(0.0, 5.4, 0.0), 30.0, "rect")
	# 门在正面 -Z、x≈0；墙角近景取 +X/-Z 凸角。
	await _shot(design, out_dir, "rect_corner_detail", Vector3(12.6, 7.2, -12.6), Vector3(4.6, 6.4, -4.0), 32.0, "rect")
	# 入口近景取近正视：过斜会让前置的雨棚柱投影盖住门洞，读起来像柱子挡门。
	await _shot(design, out_dir, "rect_entrance_detail", Vector3(-0.4, 2.6, -11.0), Vector3(-1.5, 2.0, -4.4), 34.0, "rect")
	await _shot(design, out_dir, "l_three_quarter", Vector3(24.0, 15.0, 26.0), Vector3(0.0, 5.4, 0.0), 34.0, "l")
	await _shot(design, out_dir, "u_terrace_three_quarter", Vector3(30.0, 17.0, 30.0), Vector3(0.0, 5.4, 0.0), 34.0, "u")
	quit()

func _design() -> Dictionary:
	var r: Dictionary = Recipe.authoring_defaults()
	r["building_id"] = "shell_v3_delivery"
	var architecture: Dictionary = (r["architecture"] as Dictionary).duplicate(true)
	var roof: Dictionary = (architecture["roof"] as Dictionary).duplicate(true)
	roof["mode"] = "parapet"
	architecture["roof"] = roof
	r["architecture"] = architecture
	return r

func _variant(base: Dictionary, key: String) -> Dictionary:
	var r: Dictionary = base.duplicate(true)
	r["building_id"] = "shell_v3_" + key
	match key:
		"l":
			r["shape"] = "l"
			r["depth"] = 12.0
		"u":
			r["shape"] = "u"
			r["width"] = 16.0
			r["depth"] = 13.0
			var architecture: Dictionary = (r["architecture"] as Dictionary).duplicate(true)
			var plan: Dictionary = (architecture["plan"] as Dictionary).duplicate(true)
			plan["wing_x"] = 0.42
			plan["wing_z"] = 0.58
			plan["setback_start"] = 2
			plan["setback_step"] = 0.35
			architecture["plan"] = plan
			r["architecture"] = architecture
	return r

func _shot(design: Dictionary, out_dir: String, name: String, eye: Vector3, target: Vector3, fov: float, key: String) -> void:
	var recipe: Dictionary = _variant(design, key)
	var build: Dictionary = Generator.build(recipe, Catalog.definitions())
	if not bool(build.get("ok", false)):
		print("SKIP ", name, " ", build.get("reason"))
		return
	var root: Node3D = build.get("root") as Node3D
	var viewport: SubViewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
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
	key_light.directional_shadow_max_distance = 120.0
	world.add_child(key_light)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	fill.light_energy = 0.32
	world.add_child(fill)
	world.add_child(root)
	var camera: Camera3D = Camera3D.new()
	camera.fov = fov
	camera.far = 400.0
	world.add_child(camera)
	camera.look_at_from_position(eye, target)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var path: String = out_dir.path_join(name + ".png")
	image.save_png(path)
	print("SAVED ", path, " ", image.get_size())
	viewport.queue_free()
	await process_frame
