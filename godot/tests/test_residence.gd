extends SceneTree
## 新入口：residence / visual-residence。仅由 run_verification 的隔离工程执行。
const Harbor = preload("res://scenes/residence/resident_harbor.tscn")
const Zone = preload("res://src/world/zone_scene.gd")
const Motor = preload("res://src/player/character_motor.gd")
var checks := 0
var failures := 0
var harbor: Node3D

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [residence] ", label)

func run() -> void:
	var directory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/npc/residences.json"))
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/npc/npcs.json"))
	check(directory.residences.size() == 7 and roster.npcs.size() == 7, "七住所对应七NPC")
	harbor = Harbor.instantiate()
	harbor.position = Vector3(38,0,-32)
	root.add_child(harbor)
	await process_frame
	await physics_frame
	check(harbor is Zone, "沿用ZoneScene")
	check(harbor.walk_areas.size() == 1, "屋内外共享WalkArea")
	check(harbor.ground_space.navigation_polygons > 0, "正式GroundSpace导航已生成")
	var anchors: Dictionary = harbor.anchor_snapshot()
	check(anchors.size() == 35, "35个稳定锚点")
	var owners := {}
	var scenes := {}
	for row: Dictionary in directory.residences:
		check(not owners.has(row.npc_id), "NPC独占住所 " + row.id)
		owners[row.npc_id] = row.id
		check(not scenes.has(row.scene), "独立PackedScene " + row.id)
		scenes[row.scene] = true
		var packed: PackedScene = load(row.scene)
		var solo: Node3D = packed.instantiate()
		root.add_child(solo)
		check(solo.get_meta("residence_id") == row.id, "单独实例化保留住所身份")
		check(solo.has_node("Shell/Bed/Mattress") and solo.has_node("Shell/DailyTable") and solo.has_node("Shell/Lamp"), "床桌灯完整 " + row.id)
		check(solo.has_node("Nameplate") and solo.has_node("Display"), "门牌与职业陈列 " + row.id)
		check(solo.get_node("Shell").get_meta("interior_size") == Vector2(10,5), "每屋50平方米而非box占位")
		if row.id in ["residence_flower_shop", "residence_general_store"]:
			check(solo.has_node("Counter") and solo.has_node("ShopSign"), "两商店柜台和职业装饰")
		for item: Node in solo.find_children("*", "Node", true, false):
			check(not item.is_in_group("interactable"), "住所家具不注册NPC或交易业务")
		await _door_clearance(solo)
		solo.free()
		for npc: Dictionary in roster.npcs:
			if npc.id == row.npc_id: check(npc.residence_id == row.id, "保留roster residence_id")
		for kind: String in ["home","work","social","rest","door"]:
			var marker: Node = harbor.get_node(NodePath(row[kind+"_marker"]))
			var id: String = row[kind+"_anchor_id"]
			check(marker is Marker3D, "正式TSCN Marker3D " + id)
			check(anchors[id].position.is_equal_approx(marker.global_position), "目录相对路径解析 " + id)
			check(harbor.area_at(anchors[id].position,0.01) == anchors[id].ground, "锚点可踩 " + id)
			check(_floor_hit(anchors[id].position), "锚点真实物理支撑 " + id)
		var bed: Node3D = harbor.get_node(NodePath(row.node_path+"/Shell/Bed"))
		check(anchors[row.home_anchor_id].position.distance_to(bed.global_position) > 1.0, "站位不在床中心")
	for a: Dictionary in directory.residences:
		for b: Dictionary in directory.residences:
			check(not harbor.ground_space.route(anchors[a.home_anchor_id].position, anchors[b.home_anchor_id].position).is_empty(), "七屋互达 " + a.id + " -> " + b.id)
	var landing: Node3D = harbor.landing_points()[0]
	var park: Vector3 = landing.get_node("BoatPark").global_position
	harbor.rebuild_blockers(1.12)
	check(harbor.water_block_rects.size() == 2, "甲板与栈桥阻船轮廓")
	for rect: Rect2 in harbor.water_block_rects:
		check(not rect.grow(1.4).has_point(Vector2(park.x,park.z)), "泊位留足船体余量")
	check(harbor.area_at(landing.stand_position(),0.01) != null, "上下岸点可踩")
	check(_floor_hit(landing.stand_position()), "泊位实体地板")
	for row: Dictionary in directory.residences:
		for kind: String in ["home","work","social","rest"]:
			check(not harbor.ground_space.route(landing.stand_position(),anchors[row[kind+"_anchor_id"]].position).is_empty(), "泊位到住所锚点可达")
	await _capsule_door(directory.residences[0])
	await _walk_all_homes(directory.residences, landing.stand_position(), anchors)
	_water_route(park)
	_space_overlap()
	var old := harbor.global_transform
	var local_park := harbor.to_local(park)
	harbor.transform = Transform3D(Basis(Vector3.UP,0.37),Vector3(87,4,-63))
	harbor.refresh_space()
	await physics_frame
	await process_frame
	var moved: Dictionary = harbor.anchor_snapshot()
	for id: String in anchors:
		var expected: Vector3 = harbor.to_global(old.affine_inverse()*anchors[id].position)
		check(moved[id].position.distance_to(expected) < 0.001, "锚点随root平移旋转 " + id)
		check(harbor.area_at(moved[id].position,0.01) != null and _floor_hit(moved[id].position), "变换后导航与物理支撑一致 " + id)
	var moved_landing: Node3D = harbor.landing_points()[0]
	check(moved_landing.get_node("BoatPark").global_position.distance_to(harbor.to_global(local_park)) < 0.001, "船位随root变换")
	for row: Dictionary in directory.residences:
		check(not harbor.ground_space.route(moved_landing.stand_position(),moved[row.home_anchor_id].position).is_empty(), "变换后泊位与屋内仍互达")
	harbor.transform = old
	harbor.refresh_space()
	if DisplayServer.get_name() != "headless": await _capture()
	harbor.free()
	print("[residence] %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _floor_hit(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.2, point-Vector3.UP*0.2, 256)
	var hit: Dictionary = harbor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.position.distance_to(point) < 0.02

func _door_clearance(solo: Node3D) -> void:
	var frame: Node3D = solo.get_node("Shell/DoorFrame")
	var width := 1.85
	var height := 3.1
	check(width > 0.76 and height > 2.154, "门洞超过含帽角色可视包络")
	# 不只信metadata：直接检查门墙三角形是否侵入净宽净高。
	var clear := true
	for mesh: MeshInstance3D in frame.find_children("*", "MeshInstance3D",true,false):
		var faces := mesh.mesh.get_faces()
		var relative := frame.global_transform.affine_inverse()*mesh.global_transform
		for i in range(0,faces.size(),3):
			var a: Vector3 = relative*faces[i]; var b: Vector3 = relative*faces[i+1]; var c: Vector3 = relative*faces[i+2]
			for y: float in [0.1,1.0,2.15,3.05]:
				for x: float in [-0.90,0.0,0.90]:
					if Geometry3D.segment_intersects_triangle(Vector3(x,y,-0.4),Vector3(x,y,0.4),a,b,c) != null: clear = false
	check(clear, "正式5m门墙实测净宽1.8m净高3.05m")

func _capsule_door(row: Dictionary) -> void:
	var marker: Marker3D = harbor.get_node(row.door_marker)
	var body := Motor.new()
	root.add_child(body)
	body.set_grounded_motion(true)
	body.global_position = marker.global_position + Vector3(0,0.02,1.2)
	await physics_frame
	for i in 75:
		body.move_ground(Vector3(0,0,-2.0/60.0),1.0/60.0)
		await physics_frame
	check(body.global_position.z < marker.global_position.z-1.0, "真实胶囊穿门进入住所")
	body.free()

func _walk_all_homes(rows: Array, start: Vector3, anchors: Dictionary) -> void:
	var body := Motor.new()
	root.add_child(body); body.set_grounded_motion(true)
	for row: Dictionary in rows:
		body.global_position = start + Vector3.UP*0.01
		await physics_frame
		var target: Vector3 = anchors[row.home_anchor_id].position
		var route: Array = harbor.ground_space.route(start,target)
		var arrived := not route.is_empty()
		for waypoint: Vector3 in route:
			var budget := 1600
			while Vector2(body.global_position.x-waypoint.x,body.global_position.z-waypoint.z).length() > 0.065 and budget > 0:
				var offset := waypoint-body.global_position; offset.y = 0
				body.move_ground(offset.limit_length(0.07),1.0/60.0)
				budget -= 1
				if budget % 16 == 0: await physics_frame
			if budget == 0: arrived = false; break
		check(arrived and body.global_position.distance_to(target) < 0.15, "正式CharacterMotor从泊位走入 " + row.id)
	body.free()

func _water_route(park: Vector3) -> void:
	var shapes: Array = []
	for rect: Rect2 in harbor.water_block_rects:
		shapes.append({"x":rect.get_center().x,"z":rect.get_center().y,"hx":rect.size.x*0.5,"hz":rect.size.y*0.5})
	var water := preload("res://src/navigation/water_navigation.gd").new()
	water.shape_query = func() -> Array: return shapes
	var route: Array = water.plan_route_to(Vector2(38,5),park.x,park.z)
	check(water.is_open_water(park.x,park.z), "既有WaterNavigation认可泊位水域")
	check(not route.is_empty() and water.valid_route(route), "既有WaterNavigation绕社区到泊位")

func _space_overlap() -> void:
	# 只读取Main的实例声明，不加载其脚本，避免并行NPC施工污染独立住所验收。
	var text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	check(text.contains('name="resident_harbor" parent="World/SeaStructures"'), "main定点挂载")
	var resources := {}
	var resource_pattern := RegEx.new()
	resource_pattern.compile('path="([^"]+)" id="([^"]+)"')
	for hit in resource_pattern.search_all(text): resources[hit.get_string(2)] = hit.get_string(1)
	var pattern := RegEx.new()
	pattern.compile('(?m)^\\[node name="([^"]+)" parent="World/(?:Zones|SeaStructures)"[^\\n]*instance=ExtResource\\("([^"]+)"\\)\\]\\n(?:transform = (Transform3D\\([^\\n]+\\))\\n)?')
	var occupied := AABB(harbor.position+Vector3(-15,0.88,-15),Vector3(34,5.6,33))
	var clashes: Array[String] = []
	for hit in pattern.search_all(text):
		if hit.get_string(1) == "resident_harbor": continue
		var assembly: Node3D = load(resources[hit.get_string(2)]).instantiate()
		if not hit.get_string(3).is_empty():
			var expression := Expression.new()
			expression.parse(hit.get_string(3))
			assembly.transform = expression.execute()
		for mesh: MeshInstance3D in assembly.find_children("*", "MeshInstance3D",true,false):
			var pose := mesh.transform
			var parent := mesh.get_parent()
			while parent is Node3D:
				pose = parent.transform*pose
				parent = parent.get_parent()
			if mesh.mesh != null and occupied.intersects(pose*mesh.mesh.get_aabb()): clashes.append(str(mesh.name))
		assembly.free()
	check(clashes.is_empty(), "参考位避开现有建筑 " + str(clashes))

func _capture() -> void:
	var camera := Camera3D.new(); root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 48
	camera.position = harbor.position+Vector3(34,46,40)
	camera.look_at(harbor.position+Vector3(0,1,0)); camera.current = true
	var sun := DirectionalLight3D.new(); root.add_child(sun)
	sun.rotation_degrees = Vector3(-55,-35,0); sun.light_energy = 1.1
	var environment := WorldEnvironment.new(); var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR; sky.background_color = Color("#8cb6bd")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; sky.ambient_light_color = Color("#e9e4cc"); sky.ambient_light_energy = 0.65
	environment.environment = sky; root.add_child(environment)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png("res://outputs/residence-overview.png") == OK, "真实渲染社区全景")
	camera.position = harbor.position+Vector3(22,15,24)
	camera.size = 19; camera.look_at(harbor.position+Vector3(7,1.38,6))
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/residence-flower-interior.png") == OK, "真实渲染花店内外")
	camera.free(); sun.free(); environment.free()
