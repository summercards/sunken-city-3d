extends RefCounted
## 原创程序配件：所有网格归明确的角色局部挂点所有，不写任何玩法状态。
const D = preload("res://src/avatar/avatar_dimensions.gd")
const Shape = preload("res://src/avatar/avatar_morphology.gd")
const INK := Color("#536166")
const BRASS := Color("#c7a568")
const PAPER := Color("#f1e3c5")
const LEATHER := Color("#9b7761")
const GREEN := Color("#819875")
const ROSE := Color("#c58b99")
const GLASS := Color("#90bdc4")
static var _materials: Dictionary = {}
var _roots: Array[Node3D] = []
var _id := ""

func clear() -> void:
	# 立即脱离树再释放；同一帧重配也不会残留旧命名根。
	for node in _roots:
		if is_instance_valid(node):
			if node.get_parent() != null: node.get_parent().remove_child(node)
			node.free()
	_roots.clear()
	_id = ""

func configure(actor, id: String) -> void:
	clear()
	_id = id
	var f: Dictionary = actor.avatar_geometry_report().factors
	match id:
		"signal_spool":
			_rope(_cloth_mount(actor, f, "RopeCoil", -.095, false))
			_route(_cloth_mount(actor, f, "RouteClasp", -.065, true))
		"seed_pouch":
			_seeds(_cloth_mount(actor, f, "SeedPouch", -.085, false))
			_leaf(_cloth_mount(actor, f, "LeafBrooch", -.065, true))
		"diving_goggle":
			_goggles(_mount(actor.head_pivot.get_node("AvatarHead"), "ForeheadGoggles", Vector3.ZERO, false))
			_tube(_cloth_mount(actor, f, "SealedRecordTube", -.09, false))
		"joint_pencil":
			_pencil(_mount(actor.head_pivot.get_node("AvatarHead"), "EarPencil", Vector3(.316,.0,.025), false))
			_tools(_cloth_mount(actor, f, "ToolBelt", 0.0, false), actor, f)
		"lantern_badge":
			_lantern(_cloth_mount(actor, f, "LampBadge", -.065, true))
			_book(_cloth_mount(actor, f, "ArchiveBook", -.08, false))
		"petal_visor":
			_visor(_mount(actor.hat, "PetalVisor", Vector3(0,.243,.20), false))
			_shears(_cloth_mount(actor, f, "PruningShears", -.085, false))
		"stock_clip":
			_clip(_cloth_mount(actor, f, "CargoTagClip", -.065, true))
			var pack := _cloth_mount(actor, f, "WaistPack", 0.0, false)
			_waistband(pack,f,INK)
			_pack(pack)

func _mount(parent: Node3D, id: String, pos: Vector3, scaled: bool) -> Node3D:
	var node := Node3D.new()
	node.name = "NpcAccessory_" + id
	parent.add_child(node)
	node.position = pos
	# 头/帽父节点已包含1.5；衣服父节点仅有width/depth，网格在此乘一次。
	if scaled: node.scale = Vector3.ONE * D.SCALE
	node.set_meta("npc_accessory_part", id)
	node.set_meta("mount_transform", node.transform)
	_roots.append(node)
	return node

func _cloth_mount(actor, f: Dictionary, id: String, x: float, chest: bool) -> Node3D:
	var y := .725 * D.SCALE if chest else float(f.hip_y) + .065 * D.SCALE
	var px := x * D.SCALE
	var z := Shape.shirt_front(px, y, f)
	return _mount(actor.body_pivot.get_node("AvatarBody"), id, Vector3(px,y,z), true)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .84
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.rim_enabled = true
		mat.rim = .14
		mat.rim_tint = .35
		_materials[key] = mat
	return _materials[key]

func _mesh(parent: Node3D, id: String, mesh: Mesh, color: Color, pos: Vector3, size := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	node.scale = size
	node.rotation = rot
	parent.add_child(node)
	return node

func _blob(p: Node3D, id: String, c: Color, pos: Vector3, size: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	_mesh(p,id,mesh,c,pos,size)

func _box(p: Node3D, id: String, c: Color, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	_mesh(p,id,mesh,c,pos,size,rot)

func _cylinder(p: Node3D, id: String, c: Color, pos: Vector3, radius: float, height: float, rot := Vector3.ZERO, top := -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0.0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	_mesh(p,id,mesh,c,pos,Vector3.ONE,rot)

func _line(p: Node3D, id: String, c: Color, a: Vector3, b: Vector3, radius: float) -> void:
	var direction := b-a
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = direction.length()
	mesh.radial_segments = 12
	var node := _mesh(p,id,mesh,c,(a+b)*.5)
	node.quaternion = Quaternion(Vector3.UP,direction.normalized())

func _ring(p: Node3D, id: String, c: Color, pos: Vector3, radius: float, thickness: float, size := Vector3.ONE, rot := Vector3(PI/2,0,0)) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-thickness
	mesh.outer_radius = radius+thickness
	mesh.rings = 32
	mesh.ring_segments = 10
	_mesh(p,id,mesh,c,pos,size,rot)

func _tab(p: Node3D, c := LEATHER) -> void:
	_box(p,"AttachmentTab",c,Vector3(0,.032,.012),Vector3(.032,.070,.024))
	_blob(p,"TabRivet",BRASS,Vector3(0,.054,.027),Vector3(.007,.007,.004))

func _rope(p: Node3D) -> void:
	_tab(p)
	for i in 5:
		_ring(p,"WoundRope%d"%i,PAPER.darkened(i*.018),Vector3(0,-.025,.034+i*.009),.062,.0065,Vector3(.8,1,1.22))
	_box(p,"CoilBinding",LEATHER,Vector3(0,-.025,.090),Vector3(.021,.13,.013))
	_line(p,"LooseRope",PAPER,Vector3(.046,-.04,.067),Vector3(.075,-.105,.064),.006)
	_ring(p,"RopeEndKnot",PAPER,Vector3(.075,-.10,.064),.012,.004)

func _route(p: Node3D) -> void:
	_box(p,"RouteEnamel",INK,Vector3(0,0,.012),Vector3(.075,.070,.024))
	_ring(p,"BrassBuckle",BRASS,Vector3(0,0,.028),.030,.004)
	_line(p,"RouteA",PAPER,Vector3(-.019,-.013,.035),Vector3(.006,.015,.035),.0025)
	_line(p,"RouteB",PAPER,Vector3(.006,.015,.035),Vector3(.020,-.004,.035),.0025)
	for point in [Vector3(-.019,-.013,.035),Vector3(.006,.015,.035),Vector3(.020,-.004,.035)]:
		_blob(p,"RoutePin"+str(p.get_child_count()),BRASS,point,Vector3.ONE*.004)

func _seeds(p: Node3D) -> void:
	_tab(p,GREEN.darkened(.2))
	_blob(p,"GatheredCanvas",GREEN,Vector3(0,-.030,.045),Vector3(.066,.074,.043))
	_box(p,"PouchNeck",GREEN.lightened(.1),Vector3(0,.025,.043),Vector3(.092,.022,.053))
	_line(p,"Drawstring",PAPER,Vector3(-.05,.022,.077),Vector3(.05,.022,.077),.003)
	for side in [-1,1]:
		_ring(p,"CordBow"+str(side),PAPER,Vector3(side*.012,.022,.080),.012,.0025,Vector3(1,1,.6))
		_blob(p,"SeedStamp"+str(side),PAPER,Vector3(side*.013,-.027,.086),Vector3(.008,.014,.003))

func _leaf(p: Node3D) -> void:
	# 尖叶闭合透镜体，不以普通圆球代替职业图案。
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge: Array[Vector3] = [Vector3(0,-.040,.018),Vector3(-.025,-.012,.018),Vector3(-.021,.020,.018),Vector3(0,.047,.018),Vector3(.021,.020,.018),Vector3(.025,-.012,.018)]
	for i in edge.size():
		for v in [edge[(i+1)%edge.size()],edge[i],Vector3(0,0,.031),edge[i],edge[(i+1)%edge.size()],Vector3(0,0,.006)]: surface.add_vertex(v)
	surface.generate_normals()
	_mesh(p,"PointedLeaf",surface.commit(),GREEN,Vector3.ZERO)
	_line(p,"LeafVein",PAPER,Vector3(0,-.029,.032),Vector3(0,.035,.032),.002)
	for side in [-1,1]: _line(p,"SideVein"+str(side),PAPER,Vector3(0,-.006,.032),Vector3(side*.015,.012,.026),.0015)

func _goggles(p: Node3D) -> void:
	# 环带依头椭圆绕行；双镜停在额头，最低点高于眉眼。
	for i in 40:
		var a := TAU*i/40.0
		var b := TAU*(i+1)/40.0
		_line(p,"HeadStrap%d"%i,LEATHER,Vector3(cos(a)*.278,.155,sin(a)*.288),Vector3(cos(b)*.278,.155,sin(b)*.288),.010)
	for side in [-1,1]:
		_ring(p,"GoggleFrame"+str(side),BRASS,Vector3(side*.064,.157,.300),.048,.007,Vector3(1,1,.72))
		_blob(p,"OpaqueLens"+str(side),GLASS,Vector3(side*.064,.157,.303),Vector3(.040,.030,.007))
		_line(p,"LensGlint"+str(side),PAPER,Vector3(side*.064-.015,.169,.311),Vector3(side*.064+.002,.178,.311),.002)
	_line(p,"NoseBridge",BRASS,Vector3(-.019,.157,.300),Vector3(.019,.157,.300),.006)

func _tube(p: Node3D) -> void:
	_tab(p)
	_cylinder(p,"RecordCase",GLASS,Vector3(0,-.027,.045),.030,.152)
	_cylinder(p,"RolledLog",PAPER,Vector3(0,-.027,.077),.010,.104)
	for side in [-1,1]:
		_cylinder(p,"SealedCap"+str(side),BRASS,Vector3(0,-.027+side*.076,.045),.035,.017)
		_cylinder(p,"SealRing"+str(side),INK,Vector3(0,-.027+side*.058,.045),.031,.007)
	_box(p,"CaseHarness",LEATHER,Vector3(0,-.027,.082),Vector3(.073,.022,.012))

func _pencil(p: Node3D) -> void:
	p.rotation.z = -.13
	p.set_meta("mount_transform",p.transform)
	_cylinder(p,"CedarPencil",Color("#d7aa68"),Vector3(0,.015,0),.008,.177)
	_cylinder(p,"SharpenedWood",PAPER,Vector3(0,-.086,0),.008,.025,Vector3(0,0,PI),0.0)
	_cylinder(p,"GraphiteTip",INK,Vector3(0,-.100,0),.003,.012,Vector3(0,0,PI),0.0)
	_cylinder(p,"EraserFerrule",BRASS,Vector3(0,.101,0),.009,.015)
	_cylinder(p,"Eraser",ROSE,Vector3(0,.113,0),.008,.012)
	_box(p,"EarRetainingClip",INK,Vector3(-.011,.013,-.007),Vector3(.026,.025,.018))

func _waistband(p: Node3D, f: Dictionary, color: Color) -> void:
	# 腰带沿实际衣服截面一圈；局部网格只使用参考米。
	var radius := Shape.shirt_radius_at(p.position.y,f)
	var rx := D.SHIRT_HALF.x*radius
	var rz := D.SHIRT_HALF.z*radius
	for i in 40:
		var a := TAU*i/40.0
		var b := TAU*(i+1)/40.0
		_line(p,"BeltSegment%d"%i,color,Vector3(cos(a)*(rx+.006),0,sin(a)*(rz+.006)-p.position.z/D.SCALE),Vector3(cos(b)*(rx+.006),0,sin(b)*(rz+.006)-p.position.z/D.SCALE),.010)

func _tools(p: Node3D, actor, f: Dictionary) -> void:
	_waistband(p,f,LEATHER)
	_box(p,"BeltBuckle",BRASS,Vector3(0,.025,.018),Vector3(.040,.030,.016))
	_box(p,"ToolPocket",LEATHER.darkened(.08),Vector3(-.080,-.047,.033),Vector3(.078,.105,.035))
	_line(p,"HammerHandle",PAPER,Vector3(-.082,-.085,.059),Vector3(-.082,.045,.059),.009)
	_box(p,"HammerHead",INK,Vector3(-.082,.045,.059),Vector3(.070,.025,.026))
	_box(p,"Ruler",PAPER,Vector3(.078,-.016,.032),Vector3(.028,.145,.014))
	for i in 7: _box(p,"RulerTick%d"%i,INK,Vector3(.083,.045-i*.018,.041),Vector3(.015,.002,.003))
	# 仅使用传入actor建立可审计的挂点，不缓存角色引用。
	p.set_meta("belt_parent",str(actor.body_pivot.get_path_to(p.get_parent())))

func _lantern(p: Node3D) -> void:
	_box(p,"BadgeBacking",LEATHER,Vector3(0,0,.008),Vector3(.060,.088,.016))
	_ring(p,"LanternHandle",BRASS,Vector3(0,.039,.025),.016,.003)
	_box(p,"WarmLampGlass",Color("#e9ca83"),Vector3(0,-.004,.026),Vector3(.037,.046,.025))
	for side in [-1,1]: _line(p,"LampFrame"+str(side),BRASS,Vector3(side*.024,-.029,.043),Vector3(side*.024,.026,.043),.003)
	for side in [-1,1]: _box(p,"LampCap"+str(side),BRASS,Vector3(0,-.003+side*.031,.030),Vector3(.059,.012,.038))
	_blob(p,"Wick",PAPER,Vector3(0,-.003,.041),Vector3(.005,.012,.003))

func _book(p: Node3D) -> void:
	_tab(p)
	_box(p,"ArchivePages",PAPER,Vector3(0,-.030,.041),Vector3(.089,.127,.027))
	for side in [-1,1]: _box(p,"BookCover"+str(side),INK,Vector3(0,-.030,.041+side*.019),Vector3(.103,.140,.009))
	_box(p,"BookSpine",INK,Vector3(-.048,-.030,.041),Vector3(.012,.14,.046))
	_box(p,"ArchiveTitle",BRASS,Vector3(0,.006,.065),Vector3(.061,.022,.004))
	for i in 3: _box(p,"PageEdge%d"%i,LEATHER,Vector3(.046,-.055+i*.022,.041),Vector3(.002,.002,.022))
	_box(p,"BookRetainer",LEATHER,Vector3(.018,-.030,.071),Vector3(.017,.155,.009))

func _visor(p: Node3D) -> void:
	# 在现有bucket檐上接五片花瓣；不另造穿过头颅的帽盘。
	for i in 5:
		var x := (i-2)*.072
		var z := .075-.025*absf(i-2)
		_blob(p,"Petal%d"%i,ROSE.lightened(.035*(i%2)),Vector3(x,0,z),Vector3(.058,.016,.117))
		_line(p,"PetalSeam%d"%i,PAPER,Vector3(x,.016,z-.025),Vector3(x,.016,z+.068),.0015)
	_line(p,"VisorBinding",ROSE.darkened(.2),Vector3(-.185,-.005,-.010),Vector3(.185,-.005,-.010),.009)

func _shears(p: Node3D) -> void:
	_tab(p)
	_box(p,"ShearHolster",LEATHER,Vector3(0,-.047,.027),Vector3(.062,.111,.039))
	for side in [-1,1]:
		_ring(p,"PrunerGrip"+str(side),GREEN,Vector3(side*.021,.022,.056),.022,.005,Vector3(.80,1,1.12))
		_line(p,"ClosedBlade"+str(side),INK,Vector3(side*.014,.002,.056),Vector3(-side*.008,-.080,.056),.004)
	_blob(p,"PrunerPivot",BRASS,Vector3(0,-.017,.062),Vector3.ONE*.007)

func _clip(p: Node3D) -> void:
	_box(p,"TagBacking",LEATHER,Vector3(0,-.008,.014),Vector3(.072,.097,.024))
	_box(p,"BlankCargoTag",PAPER,Vector3(0,-.014,.030),Vector3(.062,.079,.008))
	_box(p,"SpringClip",INK,Vector3(0,.035,.039),Vector3(.045,.025,.018))
	_ring(p,"ClipLever",BRASS,Vector3(0,.054,.041),.013,.0025)
	for i in 3: _box(p,"TagLine%d"%i,GLASS.darkened(.15),Vector3(-.004,.004-i*.018,.036),Vector3(.036-i*.006,.003,.002))

func _pack(p: Node3D) -> void:
	_box(p,"WaistWebbing",INK,Vector3(0,.027,.010),Vector3(.225,.027,.020))
	_blob(p,"CanvasPack",Color("#7999a7"),Vector3(0,-.029,.048),Vector3(.113,.062,.047))
	_box(p,"PackFlap",INK,Vector3(0,-.005,.083),Vector3(.183,.050,.014))
	_line(p,"ZipSeam",PAPER,Vector3(-.077,.019,.075),Vector3(.077,.019,.075),.0025)
	_ring(p,"ZipPull",BRASS,Vector3(.065,.006,.086),.010,.0025)
	for side in [-1,1]: _box(p,"PackLoop"+str(side),LEATHER,Vector3(side*.091,.026,.026),Vector3(.020,.048,.030))

func metrics(actor) -> Dictionary:
	var parts: Array = []
	var mesh_count := 0
	var face_hits := 0
	var skull_hits := 0
	var finite := true
	var face: Node3D = actor.head_pivot.get_node("AvatarHead") if actor.head_pivot != null else null
	for node in _roots:
		if not is_instance_valid(node): continue
		var bounds := AABB()
		var first := true
		var vertices := 0
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			mesh_count += 1
			finite = finite and mesh.global_transform.basis.determinant() > 0.000000001
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.get_mesh_arrays() if mesh.mesh is PrimitiveMesh else mesh.mesh.surface_get_arrays(surface)
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in points:
					var world: Vector3 = mesh.global_transform*v
					var local: Vector3 = actor.to_local(world)
					finite = finite and local.is_finite()
					bounds = AABB(local,Vector3.ZERO) if first else bounds.expand(local)
					first = false
					vertices += 1
					if face != null:
						var q: Vector3 = face.to_local(world)
						if (q/Vector3(.258,.25,.253)).length_squared() < .97: skull_hits += 1
						if absf(q.x)<.215 and q.y>-.15 and q.y<.095 and q.z>.18: face_hits += 1
		parts.append({"id":str(node.get_meta("npc_accessory_part")), "path":str(actor.get_path_to(node)),
			"parent":str(actor.get_path_to(node.get_parent())), "local_transform":node.transform,
			"mount_transform":node.get_meta("mount_transform"), "bounds":bounds, "vertices":vertices})
	return {"id":_id, "root_count":parts.size(), "mesh_count":mesh_count, "parts":parts,
		"finite":finite, "face_occlusion_vertices":face_hits, "skull_penetration_vertices":skull_hits,
		"scale_contract":D.SCALE, "material_style":"shared_soft_toon"}
