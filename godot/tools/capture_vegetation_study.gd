extends SceneTree
## Source/texture macro review independent of concurrently edited gameplay bootstrap.
var camera: Camera3D
func _init() -> void: call_deferred("run")
func image_at(label: String,target: Vector3,distance: float) -> void:
	camera.position=target+Vector3(-.12,.65,1).normalized()*distance
	camera.look_at(target); camera.fov=35
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/study_"+label+".png")
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var scene=load("res://scenes/facilities/solar_cabin_surface.tscn").instantiate();world.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.1,.38,.43)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.72,.83,.80);env.environment.ambient_light_energy=.6
	world.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-30,0);sun.light_color=Color(1,.96,.86);sun.light_energy=.9;world.add_child(sun)
	camera=Camera3D.new();camera.near=.02;world.add_child(camera)
	var wind=load("res://src/ambient/vegetation/wind_controller.gd").new();world.add_child(wind);wind.frozen=true;wind.sample_at(10)
	await image_at("macro",Vector3(5.5,10.95,-.7),1.7)
	await image_at("roof",Vector3(6.8,10.5,-.3),9)
	print("[vegetation-study] complete");quit(0)
