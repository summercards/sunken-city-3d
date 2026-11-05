extends "res://tools/capture_vegetation.gd"
## Real upstream scatter nodes/modifier stack and native demo assets, not a replacement RNG.
const Scatter=preload("res://addons/proton_scatter/src/scatter.gd")
const Item=preload("res://addons/proton_scatter/src/scatter_item.gd")
const Shape=preload("res://addons/proton_scatter/src/scatter_shape.gd")
const Box=preload("res://addons/proton_scatter/src/shapes/box_shape.gd")
const Stack=preload("res://addons/proton_scatter/src/stack/modifier_stack.gd")
const RandomPoints=preload("res://addons/proton_scatter/src/modifiers/create_inside_random.gd")
const RandomTransform=preload("res://addons/proton_scatter/src/modifiers/randomize_transforms.gd")
var generators: Array=[]
var authoring: Node3D
var measurements: Array=[]
func measure(label: String) -> void:
	var gpu:=[];var cpu:=[]
	for i in 20:await process_frame
	for i in 90:
		await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	gpu.sort();cpu.sort();measurements.append({"mode":label,"gpu_ms_p50":gpu[45],"gpu_ms_p95":gpu[85],"render_cpu_ms_p95":cpu[85],"samples":90})
func box_shape(scatter: Node3D,label: String,rect: Array,negative: bool) -> void:
	var node=Shape.new();node.name=label.validate_node_name();node.negative=negative
	var box=Box.new();box.size=Vector3(rect[2]-rect[0],1.0,rect[3]-rect[1]);node.shape=box
	node.position=Vector3((rect[0]+rect[2])*0.5,0,(rect[1]+rect[3])*0.5);scatter.add_child(node)
func make_scatter(label: String,amount: int,sources: Array,scale: float,margin: float) -> Node3D:
	var scatter=Scatter.new();scatter.name=label;scatter.global_seed=110505+generators.size()
	scatter.force_rebuild_on_load=false;scatter.enable_updates_in_game=false;scatter.dbg_disable_thread=true
	scatter.keep_static_colliders=false;scatter.use_chunks=true;scatter.chunk_dimensions=Vector3(8,4,8)
	var stack=Stack.new();var points=RandomPoints.new();points.amount=amount;points.restrict_height=true;stack.add(points)
	var randomize=RandomTransform.new();randomize.rotation=Vector3(0,180,0);randomize.scale=Vector3(.32,.32,.32);stack.add(randomize)
	scatter.modifier_stack=stack
	for source in sources:
		var item=Item.new();item.name=String(source).get_file().get_basename()
		# The native wrappers reference old imported node names. Use the unchanged
		# raw GLB and ScatterItem's supported material override on the actual mesh.
		item.path=String(source).get_base_dir()+"/models/"+String(source).get_file().get_basename()+".glb"
		item.override_material=load("res://addons/proton_scatter/demos/assets/materials/"+("m_bush" if label=="NativeBushes" else "m_grass")+".tres")
		item.source_scale_multiplier=scale;item.override_cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		item.lod_generate=false;scatter.add_child(item)
	box_shape(scatter,"Roof_Include",[-21.8,-13.8,21.8,13.8],false)
	var recipe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/vegetation/layouts/rooftop_ranch.json"))
	for region in recipe.regions:
		for cut in region.exclusions:
			var rect: Array=cut.rect.duplicate()
			rect=[rect[0]-margin,rect[1]-margin,rect[2]+margin,rect[3]+margin]
			box_shape(scatter,String(cut.id),rect,true)
	# Bushes occupy perimeter islands; reserve the open farming middle.
	if label=="NativeBushes":box_shape(scatter,"Open_Farm_Core",[-14,-7,14,8],true)
	generators.append(scatter);return scatter
func own_recursive(node: Node,owner_root: Node) -> void:
	for child in node.get_children():
		if child.name=="ScatterOutput":continue
		child.owner=owner_root;own_recursive(child,owner_root)
func output_summary() -> Array:
	var output:=[]
	for scatter in generators:
		var batch_count:=0;var instances:=0
		for batch in scatter.find_children("*","MultiMeshInstance3D",true,false):
			batch.extra_cull_margin=1.0;batch_count+=1;instances+=batch.multimesh.instance_count
			var material: Material=batch.material_override if batch.material_override!=null else batch.multimesh.mesh.surface_get_material(0)
			if not material is ShaderMaterial:
				failures+=1;printerr("FAIL native material missing on actual mesh")
		if scatter._body_rid.is_valid() or not scatter._collision_shapes.is_empty():
			failures+=1;printerr("FAIL plugin generated physics RIDs")
		var positions:=[]
		for xf in scatter.transforms.list:
			if not scatter.domain.is_point_inside(xf.origin):failures+=1;printerr("FAIL scatter exclusion")
			positions.append([xf.origin.x,xf.origin.y,xf.origin.z])
		output.append({"node":scatter.name,"generated_transforms":scatter.transforms.size(),"render_instances":instances,"batches":batch_count,"seed":scatter.global_seed,"keep_static_colliders":false,"positions":positions})
	return output
func tune_materials() -> void:
	for name in ["m_grass","m_bush"]:
		var material: ShaderMaterial=load("res://addons/proton_scatter/demos/assets/materials/"+name+".tres")
		material.set_shader_parameter("wind_strength",.45)
		var gradient:=Gradient.new();gradient.offsets=PackedFloat32Array([0,.48,1])
		gradient.colors=PackedColorArray([Color(.09,.16,.025),Color(.20,.36,.07),Color(.40,.58,.18)])
		var texture:=GradientTexture1D.new();texture.gradient=gradient;material.set_shader_parameter("texture_gradient",texture)
	for scatter in generators:
		for item in scatter.items:
			item.override_material=item.override_material.duplicate(true)
		scatter.full_rebuild.call_deferred()
		await scatter.build_completed
func run() -> void:
	main=load("res://scenes/vegetation_authoring/proton_capture_stage.tscn").instantiate();root.add_child(main);main._autosave_on=false;main.set_process(false)
	for i in 20:await process_frame
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await shot("scatter_previous",Vector3(46,4.5,-52),Vector3(-.28,.95,1),95)
	await measure("previous_v003")
	var ranch: Node3D=main._zone_nodes.rooftop_ranch
	ranch.get_node("VegetationTurf").hide()
	authoring=Node3D.new();authoring.name="ProtonScatterNativeTrial";authoring.set_meta("visual_only",true)
	authoring.add_child(make_scatter("NativeGrass",11500,["res://addons/proton_scatter/demos/assets/grass.tscn","res://addons/proton_scatter/demos/assets/grass_2.tscn"],.8,.10))
	authoring.add_child(make_scatter("NativeBushes",42,["res://addons/proton_scatter/demos/assets/bush.tscn"],1.65,.8))
	ranch.add_child(authoring);authoring.position=Vector3(0,60.05,0)
	for scatter in generators:
		scatter.full_rebuild.call_deferred()
		await scatter.build_completed
	for i in 20:await process_frame
	var summary:=output_summary()
	await shot("scatter_stock",Vector3(46,4.5,-52),Vector3(-.28,.95,1),95)
	await shot("scatter_stock_close",Vector3(63,4.7,-42),Vector3(-.3,.7,1),22)
	await tune_materials()
	await shot("scatter_green",Vector3(46,4.5,-52),Vector3(-.28,.95,1),95)
	await measure("proton_native_green")
	await shot("scatter_green_close",Vector3(63,4.7,-42),Vector3(-.3,.7,1),22)
	await shot("scatter_green_far",Vector3(46,4.5,-52),Vector3(-.28,.95,1),135)
	await shot("scatter_motion_start",Vector3(61,4.8,-42),Vector3(-.2,.6,1),38)
	DirAccess.make_dir_recursive_absolute("res://outputs/scatter_motion")
	for frame in 120:
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/scatter_motion/%03d.png"%frame)
	# Save a genuinely editable modifier-stack preset. Generated children remain transient.
	var original_position:=authoring.position;authoring.position=Vector3.ZERO
	for scatter in generators:scatter.force_rebuild_on_load=true
	own_recursive(authoring,authoring)
	var packed:=PackedScene.new();var code:=packed.pack(authoring)
	if code!=OK:failures+=1;printerr("FAIL pack plugin authoring preset")
	else:ResourceSaver.save(packed,"res://outputs/rooftop_scatter_authoring.tscn")
	authoring.position=original_position
	FileAccess.open("res://outputs/scatter_trial_report.json",FileAccess.WRITE).store_string(JSON.stringify({"plugin":"ProtonScatter 4.2.0","commit":"7198cc00078ebde61307578137c3f35223c6e438","actual_plugin_nodes":generators.size(),"generation":"upstream Create Inside Random + Randomize Transforms + positive/negative ScatterShape","stock_assets":true,"stock_shader":true,"green_preview_changes":"gradient colors and wind_strength .45 only; stock shader unchanged","layers":summary,"root_viewport_measurements":measurements,"failures":failures},"  "))
	print("[proton-scatter-trial] %d failures"%failures);quit(0 if failures==0 else 1)
