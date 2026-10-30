extends SceneTree
## Imported PaletteUV and role bindings, plus native frames of every kit component.
const Catalog=preload("res://src/building/building_catalog.gd")
var checks:=0
var failures:=0
var gallery: Node3D
var camera: Camera3D
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func frame(name: String,target: Vector3,offset: Vector3,span: float) -> void:
	camera.global_position=target+offset;camera.look_at(target);camera.size=span
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/kit-uv-"+name+".png")
func run() -> void:
	gallery=Node3D.new();root.add_child(gallery)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("#5d858d")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("#eef9f5");env.environment.ambient_light_energy=.6
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;gallery.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-25,0);sun.light_energy=1.5;gallery.add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.1;camera.far=200;gallery.add_child(camera);camera.current=true
	var index:=0
	var targets: Dictionary={}
	for kind: String in Catalog.RECIPES:
		if not Catalog.is_kit(kind): continue
		var node: Node3D=load(Catalog.RECIPES[kind].prefab).instantiate();gallery.add_child(node)
		node.position=Vector3((index%6)*4.8,0,(index/6)*4.8);index+=1
		targets[kind]=node.global_position
		var role_counts: Dictionary={}
		for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var source: Material=mesh.mesh.surface_get_material(surface)
				check(source!=null and source.resource_name.begins_with("SEA_"),kind+" role survives export")
				var live: Material=mesh.get_surface_override_material(surface)
				check(live is StandardMaterial3D and live.albedo_texture!=null and live.albedo_texture.resource_path=="res://assets/textures/shared/sea_cozy_8x8_512.png",kind+" shared palette bound")
				var uv: PackedVector2Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
				var tiles: Dictionary={}
				for point: Vector2 in uv: tiles[Vector2i(int(floor(point.x*8)),int(floor(point.y*8)))]=true
				check(not uv.is_empty() and tiles.size()==1,kind+" UV0 stays in one authored palette tile")
				if source!=null:
					role_counts[source.resource_name]=int(role_counts.get(source.resource_name,0))+1
					if source.resource_name=="SEA_Emission": check((live as StandardMaterial3D).emission_enabled and (live as StandardMaterial3D).emission_texture!=null,kind+" flame alone emits through palette")
		if kind in ["oil_lamp","lamp_post"]:
			check(role_counts.has("SEA_Emission") and role_counts.has("SEA_Gloss") and role_counts.has("SEA_Metal"),kind+" separate flame glass and metal")
	check(index==22,"all 22 imported components inspected")
	await frame("all",Vector3(12,1,7),Vector3(19,24,27),32)
	for kind: String in ["raft_4x4","wall","oil_lamp","flower_pot","windmill"]:
		var at: Vector3=targets[kind]
		await frame(kind,at+Vector3.UP*.65,Vector3(4,3,5),5.3 if kind=="raft_4x4" else 3.3)
	print("[kit-uv] %d checks, %d failures"%[checks,failures])
	gallery.queue_free();await process_frame;quit(1 if failures else 0)
