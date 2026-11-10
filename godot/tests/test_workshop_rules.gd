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
	print("[workshop-rules] %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
