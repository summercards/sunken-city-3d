extends SceneTree
## Actual mesh projections against the supplied image, plus real renderer views.
const Catalog=preload("res://src/avatar/avatar_catalog.gd")
var checks:=0
var failures:=0
var actor: Node3D
var camera: Camera3D
var stage: SubViewport
var contract: Dictionary
var metrics: Dictionary={}

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar-proportions] ","PASS " if ok else "FAIL ",label)

func project_meshes(meshes: Array) -> Rect2:
	var bounds:=Rect2(); var first:=true
	for node in meshes:
		var vertices: PackedVector3Array=node.mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX] if node.mesh is PrimitiveMesh else node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point: Vector2=camera.unproject_position(node.global_transform*vertex)
			if first: bounds=Rect2(point,Vector2.ZERO); first=false
			else: bounds=bounds.expand(point)
	return bounds

func project_skinned(parts: Array, region: String) -> Rect2:
	var bounds:=Rect2(); var first:=true
	for part in parts:
		for vertex in actor.limb_skinning.deformed_points(part,region):
			var point: Vector2=camera.unproject_position(actor.limb_skinning.to_global(vertex))
			if first: bounds=Rect2(point,Vector2.ZERO); first=false
			else: bounds=bounds.expand(point)
	return bounds

func measure() -> void:
	var head: Node3D=actor.head_pivot.get_node("AvatarHead")
	var face:=project_meshes([head.get_node("Face"),head.get_node("EarLeft"),head.get_node("EarRight")])
	var shoulders:=project_skinned(["arm.L","arm.R"],"shoulder")
	var torso:=project_meshes([actor.body_pivot.get_node("AvatarBody/Shirt")])
	var feet:=project_skinned(["leg.L","leg.R"],"foot")
	var hip:=camera.unproject_position((actor.left_leg.global_position+actor.right_leg.global_position)*0.5)
	var chin:=camera.unproject_position(head.to_global(Vector3(0,-0.25,0)))
	var sole:=camera.unproject_position(Vector3.ZERO)
	metrics={"face_width_over_face_height":face.size.x/face.size.y,
		"shoulder_span_over_face_width":shoulders.size.x/face.size.x,
		"torso_width_over_face_width":torso.size.x/face.size.x,
		"leg_length_over_face_height":absf(sole.y-hip.y)/face.size.y,
		"torso_length_over_face_height":absf(hip.y-chin.y)/face.size.y,
		"foot_span_over_face_width":feet.size.x/face.size.x}
	for id in contract.targets:
		var target: Dictionary=contract.targets[id]
		var error: float=absf(metrics[id]-float(target.value))
		check(error<=float(target.tolerance),"%s actual=%.4f reference=%.4f relative_error=%.2f%%" % [id,metrics[id],target.value,error/float(target.value)*100])
	var collider: CapsuleShape3D=actor.get_node("BodyCollision").shape
	check(is_equal_approx(collider.radius,0.22) and is_equal_approx(collider.height,1.30),"reference proportions preserve gameplay capsule")
	check(actor.scale==Vector3.ONE and actor.body_pivot.scale==Vector3.ONE,"no hidden gameplay or whole-body scaling")
	var hand: Node3D=actor.left_elbow.get_child(1)
	check(hand.global_position.y<actor.left_leg.global_position.y+0.08,"resting hands finish near hip, not short torso")
	var min_y:=INF
	for vertex in actor.limb_skinning.deformed_points("leg.L","foot"): min_y=minf(min_y,vertex.y)
	check(absf(min_y)<0.008,"actual shoe sole meets root ground")
	var report: Dictionary={"reference":contract,"measured_mesh_ratios":metrics,"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"note":"Mesh vertices measured after projection at fixed matching 3/4 camera. Anatomy ignores hat/hair and bag, which are separate accessories."}
	var file:=FileAccess.open("res://outputs/avatar-proportions.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()

func label(value: String, position: Vector2, pixels:=24) -> Label:
	var node:=Label.new(); node.text=value; node.position=position
	node.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded())
	node.add_theme_font_size_override("font_size",pixels); node.add_theme_color_override("font_color",Color("#625744")); return node

func shot(id: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/avatar-reference-"+id+".png")==OK,"real render "+id)

func fit_camera() -> void:
	var meshes: Array=[]
	for mesh in actor.find_children("*","MeshInstance3D",true,false):
		if mesh.is_visible_in_tree(): meshes.append(mesh)
	var bounds:=project_meshes(meshes)
	camera.size*=bounds.size.y/444.8
	bounds=project_meshes(meshes)
	camera.position+=camera.global_basis.y*(547.2-bounds.end.y)*camera.size/float(stage.size.y)

func run() -> void:
	contract=JSON.parse_string(FileAccess.get_file_as_string("res://outputs/avatar-reference-contract.json"))
	root.size=Vector2i(1280,900); root.content_scale_size=Vector2i(1280,900)
	var ui:=Control.new(); ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(ui)
	var background:=ColorRect.new(); background.color=Color("#fff9e8"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ui.add_child(background)
	ui.add_child(label("用户参考 · 原图",Vector2(55,35),28))
	ui.add_child(label("实际角色 · 同角度比例验收",Vector2(490,35),28))
	var reference:=TextureRect.new(); reference.texture=ImageTexture.create_from_image(Image.load_from_file("res://outputs/avatar-reference.png"))
	reference.position=Vector2(40,125); reference.size=Vector2(368,560); reference.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; reference.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ui.add_child(reference)
	var container:=SubViewportContainer.new(); container.position=Vector2(455,85); container.size=Vector2(740,730); ui.add_child(container)
	stage=SubViewport.new(); stage.size=Vector2i(740,730); stage.own_world_3d=true; stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS; stage.msaa_3d=Viewport.MSAA_4X; container.add_child(stage)
	var world:=Node3D.new(); stage.add_child(world)
	var env:=WorldEnvironment.new(); var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color("#eee9da")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color.WHITE; environment.ambient_light_energy=0.65; env.environment=environment; world.add_child(env)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-25,0); light.light_energy=0.75; world.add_child(light)
	actor=preload("res://src/player/character.gd").new(); world.add_child(actor); actor.build(); actor.set_process(false); actor._reset_action_pose()
	var appearance:=Catalog.defaults(); appearance.merge({"hair_style":"crop","hair_color":"black","top":"vest","top_color":"plum","bottom":"trousers","bottom_color":"navy","shoes":"dress","shoe_color":"navy","hat":"fedora","hat_color":"plum","blush":"none"},true)
	actor.apply_appearance(appearance)
	# The reference has no bag. This separate accessory is excluded only in the
	# anatomy plate; the subsequent gameplay/editor captures include the real bag.
	actor._item_receive.bag.hide(); actor.body_pivot.get_node("SatchelStrap").hide()
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=1.85; camera.near=0.01; camera.current=true
	world.add_child(camera); camera.position=Vector3(-0.42,0.23,1).normalized()*5+Vector3.UP*0.73; camera.look_at(Vector3.UP*0.73)
	for i in 5: await process_frame
	measure()
	fit_camera()
	ui.add_child(label("头脸宽 / 肩宽 / 腰宽 / 躯干 / 腿脚：逐项量测，保留原始数据。",Vector2(65,830),23))
	await shot("three-quarter")
	camera.position=Vector3(0,0.73,5); camera.look_at(Vector3.UP*0.73); fit_camera(); await shot("front")
	camera.position=Vector3(5,0.73,0); camera.look_at(Vector3.UP*0.73); fit_camera(); await shot("side")
	ui.queue_free(); await process_frame
	print("[avatar-proportions] %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
