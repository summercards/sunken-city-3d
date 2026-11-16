extends SceneTree
## 真实SubViewport渲染；面数来自网格，draw calls来自视口统计，不输出固定步长FPS。
const Catalog = preload("res://src/building_attachments/catalog.gd")
const Recipe = preload("res://src/building_attachments/recipe.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const Geometry = preload("res://src/building_attachments/geometry.gd")
const Store = preload("res://src/building_attachments/store.gd")
const OUT := "res://outputs/building_attachments_visual"
var checks := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var view: SubViewport
var world: Node3D
var camera: Camera3D
var caption: Label
var budget_label: Label

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL [building-attachments-visual] ", label)

func frames(count: int = 5) -> void:
	for i: int in count: await process_frame
	await RenderingServer.frame_post_draw

func setup() -> void:
	view = SubViewport.new()
	view.size = Vector2i(640, 480)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	world = Node3D.new()
	view.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("e3e8e5")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ffffff")
	environment.environment.ambient_light_energy = 0.65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.6
	world.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	view.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(18, 14)
	caption.add_theme_font_size_override("font_size", 20)
	caption.add_theme_color_override("font_color", Color("243c40"))
	layer.add_child(caption)
	budget_label = Label.new()
	budget_label.position = Vector2(18, 438)
	budget_label.add_theme_font_size_override("font_size", 16)
	budget_label.add_theme_color_override("font_color", Color("243c40"))
	layer.add_child(budget_label)

func bounds_of(node: Node3D, base: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var initialized := false
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		pending.append_array(child.get_children())
		if not child is MeshInstance3D or child.mesh == null: continue
		var transform: Transform3D = base * node.global_transform.affine_inverse() * child.global_transform
		var box: AABB = transform * child.mesh.get_aabb()
		if not initialized:
			result = box
			initialized = true
		else: result = result.merge(box)
	return result

func actual_stats(node: Node) -> Dictionary:
	var triangles := 0
	var surfaces := 0
	var meshes := 0
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		pending.append_array(child.get_children())
		if not child is MeshInstance3D or child.mesh == null: continue
		meshes += 1
		for surface: int in child.mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return {"triangles": triangles, "surfaces": surfaces, "mesh_nodes": meshes}

func capture(node: Node3D, filename: String, label: String, resolution: Vector2i = Vector2i(640, 480)) -> Image:
	view.size = resolution
	budget_label.position.y = resolution.y - 38
	world.add_child(node)
	var box: AABB = bounds_of(node)
	var target: Vector3 = box.get_center()
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	camera.size = maxf(box.size.y * 1.6, maxf(box.size.x * 1.25 / (float(resolution.x) / resolution.y), box.size.z * 1.1))
	camera.position = target + Vector3(0.42, 0.30, -1).normalized() * maxf(longest * 3.0, 4.0)
	camera.look_at(target)
	caption.text = label
	var stats: Dictionary = actual_stats(node)
	var recipe: Dictionary = node.get_meta("attachment_recipe", {})
	var budget: int = 0
	if not recipe.is_empty():
		var entry: Dictionary = Catalog.get_entry(recipe.type_id)
		budget = mini(int(entry.get("long_text_budget", entry.budget)), 3500) if str(recipe.text).length() > 8 else mini(int(entry.budget), 1800)
	stats["budget"] = budget
	budget_label.text = "%d / %d tris | %d surfaces | sampling draw calls" % [stats.triangles, budget, stats.surfaces]
	await frames(8)
	var draw_calls := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var render_primitives := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	budget_label.text = "%d / %d tris | %d surfaces | %d actual draw calls" % [stats.triangles, budget, stats.surfaces, draw_calls] if budget > 0 else "%d tris | mixed assembly | %d actual draw calls" % [stats.triangles, draw_calls]
	await frames(3)
	var image: Image = view.get_texture().get_image()
	var path: String = OUT.path_join(filename)
	check(image != null and image.get_size() == resolution, "真实渲染尺寸：" + filename)
	if image != null:
		check(image.save_png(path) == OK, "保存PNG：" + filename)
		var foreground := 0
		var background: Color = image.get_pixel(2, resolution.y / 2)
		for y: int in range(resolution.y / 4, resolution.y * 3 / 4, 8):
			for x: int in range(resolution.x / 4, resolution.x * 3 / 4, 8):
				var color: Color = image.get_pixel(x, y)
				if Vector3(color.r - background.r, color.g - background.g, color.b - background.b).length() > 0.04: foreground += 1
		check(foreground > 12, "中心真实模型像素非空：" + filename)
	stats.merge({"path": ProjectSettings.globalize_path(path), "label": label, "resolution": [resolution.x, resolution.y], "viewport_draw_calls": draw_calls, "viewport_render_primitives": render_primitives, "renderer": RenderingServer.get_current_rendering_method(), "fps_claim": null})
	captures.append(stats)
	world.remove_child(node)
	node.free()
	return image

func run() -> void:
	if DisplayServer.get_name() == "headless" or FileAccess.file_exists("res://scenes/main.tscn"):
		printerr("FAIL 仅允许无Main隔离项目且必须真实渲染")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	setup()
	var panels: Array[Image] = []
	for i: int in 8:
		var panel := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
		panel.fill(Color("e3e8e5"))
		panels.append(panel)
	var index := 0
	for entry: Dictionary in Catalog.entries():
		for condition: String in Catalog.CONDITIONS:
			var recipe: Dictionary = Recipe.defaults(entry.type_id)
			recipe.condition = condition
			var built: Dictionary = Generator.build(recipe)
			check(built.ok, "渲染前build：" + str(entry.type_id) + condition)
			if not built.ok: continue
			var label: String = str(entry.type_id) + " / " + condition
			var image: Image = await capture(built.root, str(entry.type_id) + "_" + condition + ".png", label)
			if image != null:
				var tile: Image = image.duplicate()
				tile.convert(Image.FORMAT_RGBA8)
				tile.resize(320, 240, Image.INTERPOLATE_LANCZOS)
				var panel_index: int = index / 12
				var slot: int = index % 12
				panels[panel_index].blit_rect(tile, Rect2i(0, 0, 320, 240), Vector2i((slot % 4) * 320, (slot / 4) * 240))
			index += 1
	check(index == 96, "32x3真实渲染96变体")
	for i: int in panels.size():
		check(panels[i].save_png(OUT.path_join("contact_sheet_%02d.png" % (i + 1))) == OK, "4x3接触表：%d" % i)
	for type_id: String in ["sign_fascia", "ac_wall_single", "tank_tower_cone", "pipe_elbow", "duct_straight", "awning_slope"]:
		for condition: String in Catalog.CONDITIONS:
			var recipe: Dictionary = Recipe.defaults(type_id)
			recipe.condition = condition
			if type_id == "sign_fascia": recipe.text = "SEA MARKET"
			var built: Dictionary = Generator.build(recipe)
			check(built.ok, "近景build：" + type_id + condition)
			if built.ok: await capture(built.root, "close_" + type_id + "_" + condition + ".png", type_id + " / " + condition, Vector2i(1024, 768))
	for type_id: String in ["pipe_t_valve", "utility_junction", "tv_antenna", "vent_mushroom", "duct_straight"]:
		var built: Dictionary = Generator.build(Recipe.defaults(type_id))
		check(built.ok, "v2新修支撑近景：" + type_id)
		if built.ok: await capture(built.root, "support_fresh_" + type_id + ".png", type_id + " / fresh / v2_support", Vector2i(1024, 768))
	var ruined_recipe: Dictionary = Recipe.defaults("sign_letters")
	ruined_recipe.condition = "ruined"
	ruined_recipe.text = "OLD HARBOR"
	var ruined: Dictionary = Generator.build(ruined_recipe)
	check(ruined.ok, "v2残破文字承托近景")
	if ruined.ok: await capture(ruined.root, "support_ruined_letters.png", "OLD HARBOR / ruined / retained carrier", Vector2i(1024, 768))
	for text: String in ["SEA MARKET", "OLD HARBOR"]:
		var recipe: Dictionary = Recipe.defaults("sign_fascia")
		recipe.text = text
		var built: Dictionary = Generator.build(recipe)
		check(built.ok, "改字真几何：" + text)
		if built.ok: await capture(built.root, "text_" + text.replace(" ", "_") + ".png", "Original mesh glyphs / " + text, Vector2i(1024, 768))
	await demo()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "real_rendering": true, "variants": index, "contact_sheets": 8, "captures": captures, "fps_claim": null, "scope": "隔离现有房屋fixture和附件；未接Main，未验生产摆位"}
	var report_error: String = Store.write_json(OUT.path_join("visual_report.json"), report)
	if not report_error.is_empty():
		failures.append("视觉报告写入失败：" + report_error)
		printerr("FAIL [building-attachments-visual] ", report_error)
	print("[building-attachments-visual] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func demo() -> void:
	var path := "res://outputs/attachment_fixtures/house.tscn"
	check(FileAccess.file_exists(path), "existing house fixture存在")
	if not FileAccess.file_exists(path): return
	var packed: PackedScene = load(path) as PackedScene
	check(packed != null, "existing house独立加载")
	if packed == null: return
	var assembly := Node3D.new()
	var house: Node3D = packed.instantiate()
	assembly.add_child(house)
	world.add_child(assembly)
	var box: AABB = bounds_of(assembly)
	world.remove_child(assembly)
	var plans := [
		{"type": "sign_fascia", "position": Vector3(-1.3, box.get_center().y, box.position.z - 0.04), "wall": true},
		{"type": "ac_wall_single", "position": Vector3(2.1, box.get_center().y, box.position.z - 0.04), "wall": true},
		{"type": "tank_tower_cone", "position": Vector3(-2.5, box.end.y + 0.008, 1.2), "wall": false},
		{"type": "duct_straight", "position": Vector3(1.8, box.end.y + 0.008, 0.4), "wall": false},
		{"type": "awning_slope", "position": Vector3(0, 1.4, box.position.z - 0.04), "wall": true}]
	for plan: Dictionary in plans:
		var recipe: Dictionary = Recipe.defaults(plan.type)
		if plan.type == "sign_fascia": recipe.text = "SEA MARKET"
		var built: Dictionary = Generator.build(recipe)
		check(built.ok, "demo附件：" + str(plan.type))
		if not built.ok: continue
		var node: Node3D = built.root
		assembly.add_child(node)
		node.position = plan.position - Geometry.from_vec(built.mount_anchor.position)
	await capture(assembly, "assembly_existing_house.png", "Existing house + separate attachments / not Main", Vector2i(1280, 960))
