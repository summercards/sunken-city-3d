extends TextureRect
## A cached photograph of the actual component geometry in an isolated 3D world.
## Thumbnails never create gameplay nodes, farm registration, lights or interactions.
const Catalog=preload("res://src/building/building_catalog.gd")
static var cache: Dictionary={}
var kind:=""
var viewport: SubViewport
var _rendering:=false

func configure(recipe: String) -> void:
	kind=recipe;mouse_filter=Control.MOUSE_FILTER_IGNORE
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE;stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if cache.has(kind): texture=cache[kind]
func request_image() -> void:
	if DisplayServer.get_name()=="headless": return
	if texture!=null or _rendering or kind=="": return
	if cache.has(kind): texture=cache[kind];return
	_rendering=true
	viewport=SubViewport.new();viewport.size=Vector2i(288,240);viewport.transparent_bg=true
	viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_4X;viewport.handle_input_locally=false;add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var environment:=WorldEnvironment.new();var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color(0,0,0,0)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("#fff3dc");env.ambient_light_energy=.75
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment.environment=env;world.add_child(environment)
	var model:=_model()
	world.add_child(model)
	# AABB coordinates include each GLB child transform and the legacy deck's generated boards.
	var box:=AABB();var first:=true
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		box=bounds if first else box.merge(bounds);first=false
	if first: box=AABB(Vector3(-.5,0,-.5),Vector3.ONE)
	var center:=box.get_center()
	var camera:=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var radius:=box.size.length()*.5
	camera.size=maxf(.5,radius*2.0);camera.position=center+Vector3(1.1,.85,1.45).normalized()*maxf(3.0,radius*4.0)
	camera.look_at(center);camera.current=true;camera.near=.01;camera.far=100
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-40,-35,0);key.light_color=Color("#fff7e6");key.light_energy=1.0;world.add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,135,0);fill.light_color=Color("#dae7e0");fill.light_energy=.4;world.add_child(fill)
	texture=viewport.get_texture()
	# Allow deferred resources and rendering to settle before copying the transparent frame.
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_inside_tree(): return
	var rendered:=viewport.get_texture().get_image()
	if rendered!=null and not rendered.is_empty():
		var photo:=ImageTexture.create_from_image(rendered);cache[kind]=photo;texture=photo
	viewport.queue_free();viewport=null;_rendering=false

func _model() -> Node3D:
	if Catalog.is_kit(kind):
		var model: Node3D=load("res://assets/models/building_kit/"+kind+"/"+kind+".glb").instantiate()
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			for i in mesh.mesh.get_surface_count():
				var source: Material=mesh.mesh.surface_get_material(i);var role:="matte"
				if source!=null:
					for name in ["Metal","Gloss","Emission"]:
						if name in source.resource_name: role=name.to_lower()
				mesh.set_surface_override_material(i,load("res://assets/materials/building_kit/"+role+".tres"))
		return model
	if kind=="deck": return load("res://scenes/buildables/wood_deck.tscn").instantiate()
	# Reuse the existing farm-cell mesh builder without entering its gameplay lifecycle.
	var cell=load("res://src/farming/farm_plot.gd").new();cell._build_box()
	var model:=Node3D.new()
	for child in cell.get_children(): cell.remove_child(child);model.add_child(child)
	cell.free()
	var footprint: Vector2=Catalog.RECIPES[kind].footprint
	model.scale=Vector3(footprint.x/1.30,.65,footprint.y/.90)
	return model
