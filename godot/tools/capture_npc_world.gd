extends SceneTree
## visual-npc-world：正式住所 + 独立NPC面板真实渲染，不加载Main。
const Harbor = preload("res://scenes/residence/resident_harbor.tscn")
const Presenter = preload("res://src/npc/npc_world_presenter.gd")
const Service = preload("res://src/npc/npc_service.gd")
var checks := 0
var failures := 0
var world
var harbor: Node3D
var service

func clock() -> Dictionary: return {"day": 1, "hour": 12.0, "weather": "clear"}
func count(_id: String) -> int: return 8
func exchange(_costs: Dictionary, _gains: Dictionary) -> bool: return true
func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-world-render] ", label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "截图入口必须使用真实渲染器")
		_finish()
		return
	harbor = Harbor.instantiate()
	root.add_child(harbor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.15
	root.add_child(sun)
	var environment := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("#9bbfc5")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color("#f6edda")
	sky.ambient_light_energy = 0.65
	environment.environment = sky
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 43
	camera.position = Vector3(29, 40, 36)
	camera.look_at(Vector3(0, 1.38, 0))
	camera.current = true
	await process_frame
	await physics_frame
	service = Service.new()
	check(service.configure(clock, exchange, Callable(), count).ok, "配置独立服务")
	world = Presenter.new()
	root.add_child(world)
	check(world.configure(service, harbor, clock).ok, "注入正式住所")
	for frame in 60: await process_frame
	world.set_physics_process(false)
	await shot("npc-world-overview")
	check(world.open_npc("npc_hua_yi").ok, "花店人物仍是居民")
	await shot("npc-world-panel")
	world.panel.session.command("talk")
	await shot("npc-world-dialogue")
	world.panel.session.command("back")
	world.panel.session.command("events")
	await shot("npc-world-stories")
	world.panel.session.command("gifts")
	await shot("npc-world-gifts")
	world.panel.session.command("gift", {"id": "flower_bundle"})
	await shot("npc-world-gift-confirmation")
	world.cancel_session()
	check(not service.dialogue_state().active, "退出不会遗留对白")
	world.free()
	harbor.free()
	camera.free()
	sun.free()
	environment.free()
	service = null
	_finish()

func shot(id: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png("res://outputs/" + id + ".png") == OK, "真实渲染 " + id)

func _finish() -> void:
	print("[npc-world-render] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
