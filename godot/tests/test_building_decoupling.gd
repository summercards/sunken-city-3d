extends SceneTree
## SEA-BUILDING 维护边界：目录共享对象被改写时必须可被发现；模块不得反向依赖
## 全局单例、场景树或测试代码。这些断言守的是「可独立维护」，不是玩法。
const Catalog = preload("res://src/building/building_catalog.gd")
const Service = preload("res://src/building/building_service.gd")
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func run() -> void:
	# 1. A freshly loaded catalog matches its source file.
	check(Catalog.verify_content()=="","a fresh catalog matches building_kit.json")

	# 2. Repricing a shared entry is caught. This is the defect the signature
	#    exists for: cost is read by the card, the charge and the projection,
	#    all from the same mutable dictionary.
	var original: Variant=Catalog.RECIPES.oil_lamp.cost.wood
	Catalog.RECIPES.oil_lamp.cost.wood=float(original)+7.0
	check(Catalog.verify_content()!="","a rewritten cost is reported")
	check("oil_lamp" in Catalog.verify_content(),"the report names the changed recipe")
	Catalog.RECIPES.oil_lamp.cost.wood=original
	check(Catalog.verify_content()=="","restoring the cost clears the report")

	# 3. Deleting an entry is caught too — that is how a save loses its support.
	var backup: Dictionary=Catalog.RECIPES.post.duplicate(true)
	Catalog.RECIPES.erase("post")
	check(Catalog.verify_content()!="","a removed recipe is reported")
	check("post" in Catalog.verify_content(),"the report names the removed recipe")
	Catalog.RECIPES.post=backup
	check(Catalog.verify_content()=="","re-inserting the definition clears the report")

	# 4. Adding an unknown entry is caught; unknown content must not appear as a
	#    buildable object just because someone appended to the table.
	Catalog.RECIPES["ghost_piece"]={"name":"幽灵构件","cost":{"wood":1},"seconds":1.0,
		"category":Catalog.CATEGORY_DECORATION,"footprint":Vector2(1,1)}
	check(Catalog.verify_content()!="","an appended recipe is reported")
	Catalog.RECIPES.erase("ghost_piece")
	check(Catalog.verify_content()=="","removing the appended entry clears the report")

	# 5. `active` is a runtime switch, not content drift. Retiring content is a
	#    supported operation and must not read as corruption.
	var was: bool=bool(Catalog.RECIPES.oil_lamp.get("active",true))
	Catalog.RECIPES.oil_lamp.active=false
	check(Catalog.verify_content()=="","retiring a recipe is not treated as drift")
	check(not Catalog.enabled("oil_lamp"),"retirement still takes effect for new builds")
	Catalog.RECIPES.oil_lamp.active=was
	check(Catalog.verify_content()=="","re-enabling a recipe leaves content unchanged")

	# 6. Values the service hands out are copies. A caller that mutates a query
	#    result must never move an object in the real layout.
	var service:=Service.new()
	service.configure({"eligibility":func(): return "", "space_reason":func(_r): return "",
		"pay":func(_c): return true, "refund":func(_c): return true,
		"layout_reason":func(_b:Array,_a:Array,_r:Dictionary): return ""})
	var built: Dictionary=service.begin({"kind":"raft_4x4","px":300.0,"pz":300.0,"py":0.0,
		"turn":0,"support":"","origin":"boat"})
	check(built.ok,"fixture platform built")
	service.tick(10)
	var rows: Array=service.query()
	rows[0]["px"]=12345.0
	rows[0]["kind"]="wall"
	check(is_equal_approx(float(service.row(built.id).px),300.0),"a query copy cannot move the real instance")
	check(str(service.row(built.id).kind)=="raft_4x4","a query copy cannot retype the real instance")
	var catalog_copy: Dictionary=service.catalog()
	catalog_copy["raft_4x4"]="clobbered"
	check(Catalog.RECIPES.raft_4x4 is Dictionary,"service.catalog hands out a copy, not the live table")
	check(Catalog.verify_content()=="","reading the catalog through the service changes nothing")

	# 7. The module must not reach for global owners or the scene tree. These are
	#    the boundaries check_architecture.py enforces; asserting them here keeps
	#    the failure next to the build feature that broke them.
	var source_dir: String="res://src/building/"
	for file in ["building_service.gd","assembly_rules.gd","assembly_surfaces.gd","building_catalog.gd",
			"building_space.gd","building_boundary.gd","material_shop.gd"]:
		var text: String=FileAccess.get_file_as_string(source_dir+file)
		check(not text.is_empty(),"source is readable: "+file)
		for banned in ["Economy.","GameState.","Zones."]:
			check(not banned in text,"%s does not touch %s" % [file,banned])
		check(not "res://tests/" in text,"%s does not depend on tests" % file)

	# 8. Every catalog entry must be resolvable through the public helpers the
	#    rest of the game uses, so a new entry cannot be half-registered.
	var unresolved: Array[String]=[]
	for kind: String in Catalog.RECIPES:
		if str(Catalog.category(kind))=="": unresolved.append(kind+" 缺 category")
		if Catalog.role(kind)=="" and not Catalog.is_furnishing(kind): unresolved.append(kind+" 缺 role")
		if not Catalog.RECIPES[kind].has("footprint"): unresolved.append(kind+" 缺 footprint")
		if not Catalog.RECIPES[kind].has("cost"): unresolved.append(kind+" 缺 cost")
	check(unresolved.is_empty(),"every recipe resolves through the public API: "+str(unresolved))
	check(Catalog.verify_content()=="","the audit itself leaves the catalog untouched")

	# 9. validate_snapshot loads its own script by path string, so the compiler
	#    never sees that link: renaming or moving the file would disable save
	#    validation at runtime with no build error. Extract every string-form
	#    `load("res://…")` from the module and require each path to resolve.
	var scanner:=RegEx.new()
	scanner.compile('load\\("(res://[^"]+)"\\)')
	var dead_links: Array[String]=[]
	var scanned:=0
	for file in ["building_service.gd","building_space.gd","assembly_surfaces.gd",
			"building_boundary.gd","building_world.gd","building_controller.gd"]:
		var text: String=FileAccess.get_file_as_string("res://src/building/"+file)
		for found in scanner.search_all(text):
			scanned+=1
			var path: String=found.get_string(1)
			if not FileAccess.file_exists(path): dead_links.append(file+" -> "+path)
	check(scanned>0,"the scan actually found string-form loads (%d)"%scanned)
	check(dead_links.is_empty(),"every string-form load path resolves: "+str(dead_links))
	# The replay validator must still point at its own script; a rename there is
	# exactly the failure this group exists to catch.
	var service_source: String=FileAccess.get_file_as_string("res://src/building/building_service.gd")
	check("load(\"res://src/building/building_service.gd\")" in service_source,
		"snapshot replay still loads its own script by path")
	var validator_script: Variant=load("res://src/building/building_service.gd")
	check(validator_script is GDScript,"the replay script resolves and parses")
	if validator_script is GDScript:
		var live: Variant=(validator_script as GDScript).new()
		check(live!=null,"the replay script is instantiable")
		if live!=null:
			check(live.has_method("validate_snapshot"),"replay validator still exposes validate_snapshot")
			check(live.has_method("geometry_reason"),"replay validator still offers geometry_reason")
			check(live.has_method("_index"),"replay validator still indexes supports")

	print("[building-decoupling] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
