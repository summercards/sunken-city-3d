extends SceneTree
var checks := 0
var failures := 0
var main: Node
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func nodes(n: Node) -> Array:
	var out := [n]
	for c in n.get_children(): out.append_array(nodes(c))
	return out
func box_of(n: Node3D) -> AABB:
	var box := AABB();var first := true
	for child in nodes(n):
		var boxes: Array = []
		if child is MeshInstance3D: boxes.append(child.global_transform*child.mesh.get_aabb())
		if child is MultiMeshInstance3D:
			for xf in child.get_meta("instance_transforms",[]): boxes.append(child.global_transform*xf*child.multimesh.mesh.get_aabb())
		for b in boxes: box=b if first else box.merge(b);first=false
	return box
func run() -> void:
	for path in ["res://scenes/decorations/animals/bird.tscn","res://scenes/decorations/animals/fish_school.tscn","res://scenes/decorations/animals/whale.tscn","res://scenes/decorations/water/lily_leaf.tscn"]:
		var component=load(path).instantiate();root.add_child(component)
		check(box_of(component).size.length()>0.1,"standalone decoration builds geometry "+path)
		component.free()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false
	for i in 4: await process_frame
	var ids := {};var furnishing_count := 0;var attachment_count := 0
	for n in nodes(main):
		if not n.has_method("describe"): continue
		var d: Dictionary=n.describe()
		check(not ids.has(d.instance_id) and d.instance_id!="","unique component instance "+d.instance_id)
		ids[d.instance_id]=true
		if d.category=="furnishing":
			furnishing_count+=1
			var before: Transform3D=n.transform
			check(n.request_interaction("relocate"),"furnishing exposes relocate intent")
			check(n.transform==before,"intent does not silently move or save")
			check(not n.request_interaction("harvest"),"no inventory side effect")
		if d.category=="upgrade_attachment": attachment_count+=1;check(not d.movable,"upgrade plants not loose furniture")
	check(furnishing_count>=20,"independent movable furniture")
	check(attachment_count>=50,"independent upgrade plants")
	var solar: Node3D=main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋")
	var bounds := box_of(solar)
	print("[decorations] solar_bounds=",bounds," roof_y=",bounds.end.y)
	for bird in main.bird_root.get_children():
		bird.set_process(false)
		for sample in 121:
			bird.sample(sample*0.25)
			check(box_of(bird).position.y>bounds.end.y+1.0,"bird complete orbit clears roof")
			# 鸟模型烘焙自 Three（body 锥尖在局部 +Y，导出后指向世界 +Z）。
			# Godot 侧朝向公式必须让鼻尖对着切线，否则整群鸥屁股朝前倒着飞。
			if sample%15==0:
				var body: MeshInstance3D=bird.get_child(0)
				var nose: Vector3=(body.global_transform.basis*Vector3(0,1,0)).normalized()
				var a: float=sample*0.25*bird.speed+bird.phase
				var tangent:=Vector3(-sin(a)*bird.radius.x,0,cos(a)*bird.radius.y).normalized()
				check(nose.dot(tangent)>0.9,"bird nose leads flight path")
	var schools := 0;var whales := 0;var leaves := 0
	for n in nodes(main):
		if not n.has_method("describe"): continue
		var d: Dictionary=n.describe()
		if d.asset_id=="SEA-DECO-ANIMAL-FISH-SCHOOL":
			# 条数按群自己声明的 count 校验：水面群 10 条、水下群 18 条，
			# 写死 18 会让「水面群减到 10 条」变成一个假失败。
			schools+=1;check(n.members.size()==n.count,"school restored with its declared fish count")
			n.sample(0);var first: Transform3D=n.transforms[0];n.sample(2)
			check(not first.is_equal_approx(n.transforms[0]),"fish really animate")
		if d.asset_id=="SEA-DECO-ANIMAL-WHALE": whales+=1;check(box_of(n).size.length()>8,"large animal geometry")
		if d.subcategory=="water_plants": leaves+=1
	check(schools==10,"3 surface decorative + 7 dive schools")
	check(whales==1,"one large whale")
	check(leaves==24,"24 independent original lily leaves")
	var migrated=main.get_node("World/Zones/Zone2YokohamaStation/WaterDecorations")
	check(migrated.get_meta("retired_triangles")==840,"all 15 original leaves removed exactly once")
	# zone1 不再飘粒子（2026-10-28 主人截图：花瓣飘在阳光房上层平台中间）。
	# 撤的是植物场景的 effect 数据，不是 plant_effect.gd 的代码路径，
	# 所以这里盯住「zone1 一个发射器都不建」+「摆动参数还在」两件事。
	var zone1_plants: Node3D=main.get_node("World/Zones/Zone1HomeHarbor/Plants")
	var emitters := 0
	for n in nodes(zone1_plants):
		if n is GPUParticles3D: emitters+=1
	check(emitters==0,"zone1 builds no ambient particle emitter")
	check(zone1_plants.effect_node==null,"zone1 plant field holds no effect node")
	var sway_kept := 0
	for p in zone1_plants.plants:
		if p.effect=="" and p.wind_strength>0.0: sway_kept+=1
	check(sway_kept>=10,"zone1 plants keep sway after petals removed")
	var component=preload("res://src/ambient/scene_component.gd").new()
	component.component_kind="upgrade_attachment";component.unlock_level=2
	component.set_upgrade_level(1);check(not component.visible,"plant upgrade locked")
	component.set_upgrade_level(2);check(component.visible,"plant upgrade unlocked")
	component.free()
	print("[decorations] furniture=",furnishing_count," plants=",attachment_count," schools=",schools," whales=",whales," leaves=",leaves)
	if DisplayServer.get_name()!="headless":
		main.hud.hide();main.markers.hide();main.ribbon.hide();main.cam.suspend_follow()
		for pose in [["home",Vector3(4,6,5),45.0,Vector3(-.6,.7,.8)],["animals",Vector3(-3,-1,25),35.0,Vector3(-.3,.95,.4)],["lilies",Vector3(-27,1,-18),30.0,Vector3(-.3,.9,.4)]]:
			main.cam.target=pose[1];main.cam.distance=pose[2];main.cam.orbit_dir=pose[3];main.cam.refresh()
			for i in 12: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://outputs/decorations-"+pose[0]+".png")
		var original_environment: Environment=main.world_env.environment
		main._on_dive()
		main.dive.debug_teleport(Vector3(1,-13,-12))
		for i in 8: await process_frame
		main.dive.set_process(false)
		main.dive.freeze_time(0.0)
		var dive_camera: Camera3D=main.dive.camera
		dive_camera.global_position=Vector3(5,-10,-9)
		dive_camera.look_at(Vector3(1,-13,-16))
		main.dive.deco.update(0,0,Vector3(1,-13,-12),dive_camera)
		check(main.dive.visible and not main.world_root.visible,"decorations follow dive lifecycle")
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/decorations-dive-fish.png")
		main.dive.surface()
		main.dive.set_process(true)
		for i in 180:
			if not main.dive.active: break
			await process_frame
		check(not main.dive.active,"public surface action completes through exit state")
		check(main.world_env.environment==original_environment,"surface environment restored")
	main.queue_free();await process_frame
	print("[decorations] ",checks," checks, failures=",failures)
	quit(0 if failures==0 else 1)
