extends SceneTree

const Recipe=preload("res://src/workshop/recipe.gd")
const Catalog=preload("res://src/workshop/catalog.gd")
const Generator=preload("res://src/workshop/generator.gd")
const Session=preload("res://src/workshop/session.gd")
const Store=preload("res://src/workshop/store.gd")
var checks:=0
var failures:Array[String]=[]
func ck(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);print("FAIL ",message)
func _initialize()->void:call_deferred("run")
func run()->void:
	printerr("[workshop-stage] rule entry")
	var catalog:Dictionary=Catalog.definitions()
	ck(Catalog.validate(catalog)=="","catalog valid")
	var recipe:Dictionary=Recipe.defaults()
	ck(Recipe.validate(recipe,catalog)=="","default recipe valid")
	var parsed:Dictionary=JSON.parse_string(JSON.stringify(recipe))
	ck(Recipe.validate(parsed,catalog)=="","JSON numeric roundtrip valid")
	var bad:Dictionary=recipe.duplicate(true);bad.schema_version=1.5
	ck(Recipe.validate(bad,catalog)!="","fractional version refused")
	bad=recipe.duplicate(true);bad.width=NAN
	ck(Recipe.validate(bad,catalog)!="","nonfinite refused")
	bad=recipe.duplicate(true);bad.building_id="../outside"
	ck(Recipe.validate(bad,catalog)!="","path traversal refused")
	bad=recipe.duplicate(true);bad.component_bindings.wall="plant_shrub"
	ck(Recipe.validate(bad,catalog)!="","incompatible binding refused")
	printerr("[workshop-stage] building default")
	var result:Dictionary=Generator.build(recipe,catalog)
	printerr("[workshop-stage] default complete ",result.get("reason",""))
	ck(result.ok,"default build: "+str(result.reason))
	if result.ok:
		ck(result.slots.size()>20,"real structure slots")
		ck(result.stats.triangles>100,"real mesh geometry")
		ck(result.stats.collision_shapes>0,"above water collision")
		ck(result.root.get_script()==null,"root static")
		var again:Dictionary=Generator.build(recipe,catalog)
		ck(again.ok and JSON.stringify(result.slots)==JSON.stringify(again.slots),"deterministic generated slots")
		if again.ok:again.root.free()
		result.root.free()
	var scenic:Dictionary=recipe.duplicate(true);scenic.spatial_profile="scenic_underwater";scenic.shape="l"
	var scene:Dictionary=Generator.build(scenic,catalog)
	ck(scene.ok,"scenic L build")
	if scene.ok:
		ck(scene.stats.collision_shapes==0 and scene.walk_surfaces.is_empty() and scene.water_blockers.is_empty(),"scenic has no space responsibilities")
		scene.root.free()
	var session=Session.new()
	var old:Dictionary=session.snapshot()
	ck(session.apply_patch({"width":15.0}).ok,"apply edit")
	ck(session.undo() and session.snapshot().width==old.width,"undo")
	ck(session.redo() and session.snapshot().width==15.0,"redo")
	ck(not session.apply_patch({"unknown":true}).ok,"unknown edit rejected")
	var store=Store.new()
	printerr("[workshop-stage] export start")
	var export:Dictionary=store.export_revision(recipe,catalog)
	printerr("[workshop-stage] export done ",export.get("reason",""))
	ck(export.ok,"export static and recipe: "+str(export.reason))
	if export.ok:
		var loaded:Dictionary=store.load_recipe(export.recipe_path)
		ck(loaded.ok,"read exported recipe")
		var static_scene=ResourceLoader.load(export.scene_path,"",ResourceLoader.CACHE_MODE_IGNORE)
		ck(static_scene is PackedScene,"static scene independently loads")
		if static_scene is PackedScene:
			var instance=static_scene.instantiate();ck(instance.get_script()==null,"baked root no rebuild script");instance.free()
		var next:Dictionary=store.export_revision(recipe,catalog)
		ck(next.ok and next.directory!=export.directory,"repeat export keeps previous revision")
	verify_palette()
	verify_shading()
	print("[workshop-rules] %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func verify_shading() -> void:
	var config = preload("res://src/workshop/architecture_config.gd")
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe.architecture.shading = {"materials": {"SEA_Matte": {"roughness": 0.74, "metallic": 0.02, "specular": 0.31, "emission_energy": 0.0, "transparency": 0.0}, "SEA_Gloss": {"roughness": 0.16, "metallic": 0.12, "specular": 0.72, "emission_energy": 0.0, "transparency": 0.68}}}
	ck(Recipe.validate(recipe, Catalog.definitions()).is_empty(), "材质角色实例参数合法")
	var bad: Dictionary = recipe.duplicate(true)
	bad.architecture.shading.materials.SEA_Matte.metallic = 0.8
	ck(not Recipe.validate(bad, Catalog.definitions()).is_empty(), "Matte超出合规金属度拒绝")
	var session = Session.new(Catalog.definitions())
	ck(session.replace_recipe(recipe).ok, "材质参数进入Session")
	var built: Dictionary = session.build()
	ck(built.ok, "材质实例参数构建")
	var found_matte: bool = false
	if built.ok:
		for raw: Node in built.root.find_children("*", "MeshInstance3D", true, false):
			var node: MeshInstance3D = raw as MeshInstance3D
			if node == null: continue
			for surface: int in node.mesh.get_surface_count():
				if node.get_active_material(surface) == preload("res://src/workshop/mesh_builder.gd").shared_materials().get("SEA_Matte"):
					found_matte = true
					ck(is_equal_approx(float(node.get_instance_shader_parameter("sea_matte_controls").x), 0.74), "Matte实例粗糙度写入MeshInstance")
					ck(is_equal_approx(float(node.get_instance_shader_parameter("sea_matte_controls").y), 0.02), "Matte实例金属度写入MeshInstance")
					break
		ck(found_matte, "找到共享SEA_Matte可见节点")
		built.root.free()

func verify_palette() -> void:
	var config = preload("res://src/workshop/architecture_config.gd")
	var builder = preload("res://src/workshop/mesh_builder.gd")
	var settings: Dictionary = {"color_mode": "manual", "color_cell": [0, 0], "color_seed": 12}
	var source: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE])
	var shared: Dictionary = builder.shared_materials()
	for index: int in 64:
		settings.color_cell = [index / 8, index % 8]
		ck(config.validate_palette(settings).is_empty(), "64格合法 " + str(index))
		var uv: PackedVector2Array = builder.encode_cell_uv(source, settings.color_cell)
		var correct: bool = absf((uv[1] - uv[0]).cross(uv[2] - uv[0])) > 0.000001
		for point: Vector2 in uv:
			var px: Vector2 = point * 512.0 - Vector2(index % 8, index / 8) * 64.0
			correct = correct and px.x >= 16.0 and px.x <= 48.0 and px.y >= 16.0 and px.y <= 48.0
		ck(correct, "64格真实非零面积及16px安全边 " + str(index))
	for bad: Variant in [[-1, 0], [8, 0], [0.5, 0], [true, 0], ["1", 0], [0], null]:
		settings.color_cell = bad
		ck(not config.validate_palette(settings).is_empty(), "非法格拒绝 " + str(bad))
	settings.color_cell = [0, 0]
	for bad: Variant in [-1, 0.5, true, "1", NAN, 9007199254740992.0]:
		settings.color_seed = bad
		ck(not config.validate_palette(settings).is_empty(), "非法seed拒绝 " + str(bad))
	for bad: Variant in [{"color_mode": "random"}, {"slots": {"walls": {}}}, {"materials": {"SEA_Fake": {}}}, {"slots": []}, {"slots": {"wall": {"typo": 1}}}, {"materials": {"SEA_Matte": 1}}]:
		ck(not config.validate_palette(bad).is_empty(), "未知模式/目标/覆盖拒绝 " + str(bad))
	for role: String in config.PALETTE_ROLES:
		var by_role: Dictionary = Recipe.authoring_defaults()
		by_role.architecture.palette = {"materials": {role: {"color_mode": "manual", "color_cell": [7, 6]}}}
		ck(Recipe.validate(by_role).is_empty() and config.palette_cell(config.palette_settings(by_role, "frame", role), "frame_front_0_1", role) == [7, 6], "四材质角色选格 " + role)
	settings = {"color_mode": "auto", "color_seed": 11010}
	var seen: Dictionary = {}
	for index: int in 512:
		settings.color_seed = index
		var cell: Array = config.palette_cell(settings, "frame_front_0_1", "SEA_Matte")
		seen[str(cell)] = true
		ck(cell == config.palette_cell(settings, "frame_front_0_1", "SEA_Matte") and int(cell[0]) in range(8) and int(cell[1]) in range(8), "auto稳定0..63 " + str(index))
	ck(seen.size() == 64, "自动选色可达全部64格")
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe.architecture.palette = {"color_mode": "manual", "color_cell": [1, 2], "materials": {"SEA_Matte": {"color_cell": [3, 4]}}, "slots": {"wall": {"color_cell": [5, 6]}}}
	ck(config.palette_cell(config.palette_settings(recipe, "wall", "SEA_Matte"), "wall_shell_0", "SEA_Matte") == [5, 6], "部件优先于角色")
	ck(config.palette_cell(config.palette_settings(recipe, "frame", "SEA_Matte"), "frame_front_0_1", "SEA_Matte") == [3, 4], "角色覆盖全局")
	ck(Recipe.fingerprint(recipe) == Recipe.fingerprint(JSON.parse_string(JSON.stringify(recipe))), "调色JSON重载指纹一致")
	var data: Dictionary = builder.rounded_box(Vector3.ONE, 0.02, 3)
	var recolored: ArrayMesh = builder.recolor_mesh(data.mesh, {"color_mode": "manual", "color_cell": [7, 7]}, "plant_0", "SEA_Matte")
	ck(recolored.get_faces() == data.mesh.get_faces() and recolored.surface_get_material(0) == data.mesh.surface_get_material(0), "仅UV变化且共享材质身份不变")
	ck(recolored.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != data.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV], "真实UV变化")
	ck(shared == builder.shared_materials(), "四共享材质未复制")
