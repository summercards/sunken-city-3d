extends SceneTree
## runner入口：visual-npc-appearance。只在隔离工程运行，PNG由runner搬出工程。
const Actor = preload("res://src/npc/npc_actor.gd")
const QA = preload("res://tests/test_npc_appearance.gd")
const Support = preload("res://tests/avatar_customization_support.gd")
const OUTPUT := "res://outputs/npc-appearance-"
var actors: Array = []
var rows: Array = []
var world: Node3D
var camera: Camera3D
var caption: Label
var failures := 0
var files: Array = []

func _init() -> void: call_deferred("run")

func environment() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#eee9df")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#fff4e4")
	env.environment.ambient_light_energy = .72
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-28,0)
	light.light_energy = .85
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20,145,0)
	fill.light_color = Color("#b9d6df")
	fill.light_energy = .35
	world.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .01
	camera.far = 100.0
	camera.current = true
	world.add_child(camera)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(30,20)
	caption.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded())
	caption.add_theme_font_size_override("font_size",26)
	caption.add_theme_color_override("font_color",Color("#544f47"))
	layer.add_child(caption)

func aim(center: Vector3, size: float, direction := Vector3(0,.06,1)) -> void:
	camera.size = size
	camera.position = center+direction.normalized()*20.0
	camera.look_at(center)

func shot(id: String, text: String) -> Image:
	caption.text = text
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var path := OUTPUT+id+".png"
	if image.save_png(path) != OK:
		failures += 1
		printerr("[npc-appearance-render] PNG保存失败 ",path)
	else: files.append(path)
	# 非空真实渲染探针；不可用headless占位图代替。
	var background := image.get_pixel(image.get_width()-2,image.get_height()-2)
	var count := 0
	for y in range(100,image.get_height()-50,6):
		for x in range(50,image.get_width()-50,6):
			var p := image.get_pixel(x,y)
			if Vector3(p.r-background.r,p.g-background.g,p.b-background.b).length()>.12: count += 1
	if count < 100:
		failures += 1
		printerr("[npc-appearance-render] 实际画面为空 ",id)
	return image

func gallery(yaw: float) -> void:
	for i in actors.size():
		var actor = actors[i]
		actor.show()
		# 展示板式两排：上排四人、下排三人，行间留空，不让后排被前排遮住。
		var upper := i < 4
		var column := i if upper else i-4
		actor.position = Vector3((column-(1.5 if upper else 1.0))*1.65,2.65 if upper else 0.0,0)
		QA.sample(actor,"idle",.12+i*.07)
		actor.set_preview_yaw(yaw)
	aim(Vector3(0,2.30,0),8.0,Vector3(0,0,1))

func solo(index: int, yaw := 0.0) -> void:
	for i in actors.size(): actors[i].visible = i==index
	var actor = actors[index]
	actor.position = Vector3.ZERO
	QA.sample(actor,"idle",.27)
	actor.set_preview_yaw(yaw)
	# 实际可见网格包围盒包括原生帽发，保证极值头型不会裁切。
	var points := PackedVector3Array()
	for mesh in Support.meshes(actor):
		if mesh.get_parent()==actor.limb_skinning: continue
		points.append_array(Support.points(mesh))
	for id in actor.limb_skinning.limb_ids():
		for p in actor.limb_skinning.deformed_points(id): points.append(actor.limb_skinning.to_global(p))
	var box := Support.bounds(points)
	var center := box.get_center()
	aim(center,maxf(2.25,box.size.y*1.24),Vector3(0,.02,1))

func detail(index: int, part: Dictionary) -> void:
	solo(index,.0)
	var actor = actors[index]
	var node: Node3D = actor.get_node(part.path)
	var points := PackedVector3Array()
	for mesh in Support.meshes(node): points.append_array(Support.points(mesh))
	var box := Support.bounds(points)
	var center := box.get_center()
	var size := maxf(.34,maxf(box.size.x,box.size.y)*1.7)
	# 保留少量衣服/头部上下文，能看清配件的接触位置。
	var direction := Vector3(.45,.15,1) if part.id=="EarPencil" else Vector3(-.20,.16,1)
	aim(center,size,direction)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("[npc-appearance-render] 必须由runner使用真实渲染器")
		quit(1)
		return
	root.size = Vector2i(1600,1100)
	root.content_scale_size = Vector2i(1600,1100)
	root.msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	environment()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/npc/npcs.json"))
	rows = source.npcs
	for row in rows:
		var actor = Actor.new()
		world.add_child(actor)
		actor.configure(row)
		actor.set_process(false)
		actor.set_physics_process(false)
		actors.append(actor)
	for view in [{"id":"front","yaw":0.0,"label":"正面"},{"id":"side","yaw":PI/2,"label":"侧面"},{"id":"back","yaw":PI,"label":"背面"}]:
		gallery(view.yaw)
		await shot("group-"+view.id,"七位海上居民 · "+view.label+" · 上排：牵线 / 叶脉 / 回声 / 榫口；下排：灯芯 / 花序 / 货架")
	var report: Array = []
	for i in actors.size():
		var actor = actors[i]
		var id: String = rows[i].id
		for view in [{"id":"front","yaw":0.0},{"id":"three-quarter","yaw":-.38},{"id":"side","yaw":PI/2},{"id":"back","yaw":PI}]:
			solo(i,view.yaw)
			await shot(id+"-"+view.id,rows[i].display_name+" · "+rows[i].role+" · "+view.id)
		solo(i)
		for part in actor.accessory_metrics().parts:
			detail(i,part)
			await shot(id+"-detail-"+part.id,rows[i].display_name+" · 职业配件 / "+part.id)
		# 七人×七动作，三相位拼板保留真实同步证据。
		for action in QA.ACTIONS:
			var sheet := Image.create(2400,550,false,Image.FORMAT_RGBA8)
			for phase in 3:
				solo(i)
				var times: Array = [.37,1.20,2.15] if action=="harvesting" else [.11,.37,.69]
				QA.sample(actor,action,times[phase])
				aim(Vector3(0,1.25,0),3.35)
				var image: Image = await shot(id+"-"+action+"-%d"%phase,rows[i].display_name+" · "+action+" · 相位%d"%(phase+1))
				image.resize(800,550,Image.INTERPOLATE_LANCZOS)
				sheet.blit_rect(image,Rect2i(0,0,800,550),Vector2i(phase*800,0))
			var path: String = OUTPUT+id+"-"+str(action)+"-phases.png"
			if sheet.save_png(path)!=OK: failures += 1
			else: files.append(path)
		solo(i)
		report.append(actor.appearance_report())
	var file := FileAccess.open(OUTPUT+"capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"entry":"visual-npc-appearance","renderer":DisplayServer.get_name(),"failures":failures,"files":files,"actors":report},"\t"))
	file.close()
	world.queue_free()
	await process_frame
	print("[npc-appearance-render] %d PNG, %d failures"%[files.size(),failures])
	quit(1 if failures else 0)
