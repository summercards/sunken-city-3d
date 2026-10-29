extends SceneTree
## Only in-memory physics/navigation fixtures. No shipped room or content model.
const GroundSpace = preload("res://src/navigation/ground_space.gd")
const WalkArea = preload("res://src/navigation/walk_area.gd")
var checks := 0
var failures := 0
var host: Node3D
class Vessel extends Node3D:
	func starts_sailing() -> bool: return false

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func flat(id: String, rect: Rect2, y: float, radius: float=0.38) -> Node3D:
	var area := WalkArea.new()
	area.area_id = id
	area.surface_y = y
	area.body_radius = radius
	area.rects = [rect]
	host.add_child(area)
	return area

func make_space(areas: Array) -> Node3D:
	var space := GroundSpace.new()
	host.add_child(space)
	space.configure(areas)
	return space

func settle() -> void:
	for i in 3:
		await physics_frame
		await process_frame

func capsule(point: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 512
	body.collision_mask = 256
	body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.22
	shape.height = 1.30
	collision.shape = shape
	collision.position.y = 0.65
	body.add_child(collision)
	host.add_child(body)
	body.global_position = point
	return body

func run() -> void:
	host = Node3D.new()
	root.add_child(host)
	var lower := flat("lower",Rect2(0,0,4,4),0.0)
	var upper := flat("upper",Rect2(0,0,4,4),3.0)
	var space := make_space([lower,upper])
	check(not space.route(Vector3(1,0,1),Vector3(3,0,3)).is_empty(),"native route is ready for immediate command queries")
	await settle()
	print("[ground-space] stacked polygons=",space.navigation_polygons," closest=",NavigationServer3D.map_get_closest_point(space._map,Vector3(2,0,2)))
	check(space.area_at(Vector3(2,0.1,2))==lower,"lower storey selected by saved height")
	check(space.area_at(Vector3(2,3.1,2))==upper,"upper storey selected at overlapping XZ")
	check(space.area_at(Vector3(2,1.5,2))==null,"unsupported height is not silently projected to a floor")
	check(space.surface_point(Vector3(2,3.1,2)).is_equal_approx(Vector3(2,3,2)),"upper surface resolves to its own height")
	check(space.route(Vector3(1,0,1),Vector3(3,0,3)).size()>=2,"engine path exists on ground floor")
	var upper_path: Array = space.route(Vector3(1,3,1),Vector3(3,3,3))
	check(upper_path.size()>=2,"engine path exists upstairs")
	var correct_height := not upper_path.is_empty()
	for p: Vector3 in upper_path: correct_height = correct_height and absf(p.y-3.0)<0.03
	check(correct_height,"upper route keeps upper height")
	check(space.route(Vector3(1,0,1),Vector3(3,3,3)).is_empty(),"disconnected storeys are not joined by XZ projection")
	check(space.route(Vector3(1,0,1),Vector3(20,0,20)).is_empty(),"distant water is not snapped to a nearby nav polygon")
	var body := capsule(Vector3(2,0.2,2))
	await settle()
	var floor_hit := body.move_and_collide(Vector3(0,-0.4,0))
	check(floor_hit!=null and absf(body.global_position.y)<0.01,"real capsule lands on derived physical floor")
	body.global_position = Vector3(2,0.01,2)
	var wall_hit := body.move_and_collide(Vector3(5,0,0))
	check(wall_hit!=null and body.global_position.x<3.80,"physical outer boundary blocks a direct move")
	body.queue_free()
	space.clear()
	check(lower.ground_space==null and upper.ground_space==null,"clear releases surface ownership references")
	space.queue_free(); lower.queue_free(); upper.queue_free()
	await settle()

	# A continuous ramp connects two surfaces. No teleport, floor-id shortcut or
	# hand-written point path is supplied to the engine query.
	lower = flat("ramp_lower",Rect2(0,0,4,4),0.0)
	upper = flat("ramp_upper",Rect2(10,0,4,4),3.0)
	var ramp := WalkArea.new()
	ramp.area_id = "slope"
	ramp.surface_triangles = PackedVector3Array([
		Vector3(4,0,0),Vector3(4,0,4),Vector3(10,3,4),
		Vector3(4,0,0),Vector3(10,3,4),Vector3(10,3,0)])
	host.add_child(ramp)
	space = make_space([lower,ramp,upper])
	await settle()
	var slope_point: Vector3 = space.surface_point(Vector3(7,1.5,2))
	check(slope_point.distance_to(Vector3(7,1.5,2))<0.001,"slope support has interpolated height")
	var ascent: Array = space.route(Vector3(2,0,2),Vector3(12,3,2))
	check(ascent.size()>=3,"engine route crosses lower surface, ramp and upper surface")
	check(not ascent.is_empty() and ascent[0].distance_to(Vector3(2,0,2))<0.001 and ascent[-1].distance_to(Vector3(12,3,2))<0.001,"route preserves exact requested surface endpoints")
	var cast := PhysicsRayQueryParameters3D.create(Vector3(7,7,2),Vector3(7,-1,2),256)
	var ramp_hit := root.get_world_3d().direct_space_state.intersect_ray(cast)
	check(not ramp_hit.is_empty() and absf(float(ramp_hit.position.y)-1.5)<0.002,"real ray hits ramp collision at interpolated height")
	# A capsule passing the lower/ramp seam must not meet an invented wall.
	var seam_probe := capsule(Vector3(3.5,0.5,2))
	await settle()
	var seam_hit := seam_probe.move_and_collide(Vector3(1,0.5,0))
	check(seam_hit==null,"shared ramp seam creates no external boundary wall")
	seam_probe.queue_free()
	# Drive the formal controller and capsule together across the engine path.
	var actor = preload("res://src/player/character.gd").new()
	host.add_child(actor); actor.set_process(false)
	var vessel := Vessel.new(); host.add_child(vessel)
	var controller = preload("res://src/player/actor_controller.gd").new()
	controller.configure(actor,vessel,host,null,{"notify":func(_text): pass,"landing":func(): return null,"zone":func(): return null,"input_blocked":func(): return false})
	controller.restore_pose({"mode":0,"player":[2.0,0.0,2.0]})
	await settle()
	check(controller.start_walk(upper,Vector3(12,3,2)),"formal controller accepts connected upper floor")
	for i in 900:
		controller.tick(1.0/60.0)
		if not controller.walking(): break
	check(actor.global_position.distance_to(Vector3(12,3,2))<0.03 and controller.state_id()=="ashore_idle","formal motor follows native ramp route and stops upstairs pos="+str(actor.global_position)+" path="+str(controller.walk_path))
	check(controller.start_walk(lower,Vector3(2,0,2)),"formal controller accepts return downstairs")
	for i in 900:
		controller.tick(1.0/60.0)
		if not controller.walking(): break
	check(actor.global_position.distance_to(Vector3(2,0,2))<0.03,"formal motor follows descending path without teleport pos="+str(actor.global_position)+" path="+str(controller.walk_path))
	controller.ports.clear(); controller = null
	actor.queue_free(); vessel.queue_free()
	space.clear(); space.queue_free(); lower.queue_free(); upper.queue_free(); ramp.queue_free()
	await settle()

	var dynamic := flat("dynamic",Rect2(0,0,1,4),0.0,0.0)
	dynamic.rects.append_array([Rect2(3,0,1,4),Rect2(1,0,2,1),Rect2(1,3,2,1),Rect2(900,-700,2,2)])
	space = make_space([dynamic])
	await settle()
	check(not space.route(Vector3(0.03,0,1),Vector3(0.03,0,3)).is_empty(),"already-inset dynamic corridor is not eroded twice")
	check(space.route(Vector3(0.5,0,0.5),Vector3(901,0,-699)).is_empty(),"remote platform has no route across intervening ocean")
	check(space.surface_point(Vector3(2,0,2))==Vector3.INF,"planter hole remains outside the walking domain")
	var hole_probe := capsule(Vector3(0.6,0.01,2))
	await settle()
	var hole_hit := hole_probe.move_and_collide(Vector3(2.0,0,0))
	check(hole_hit!=null and hole_probe.global_position.x<1.03,"physical hole wall respects compensated actor-centre clearance")
	hole_probe.queue_free()
	var revision: int = space.revision
	space.rebuild(dynamic)
	check(space.revision==revision,"unchanged construction progress does not rebuild geometry")
	dynamic.rects = [Rect2(20,0,4,4)]
	space.rebuild(dynamic)
	await settle()
	check(space.revision==revision+1,"layout mutation refreshes derived projection")
	check(space.route(Vector3(0.5,0,0.5),Vector3(0.5,0,3.5)).is_empty(),"removed layout cannot keep a stale navigation route")
	check(not space.route(Vector3(21,0,1),Vector3(23,0,3)).is_empty(),"new layout becomes navigable immediately after rebuild")
	var removed_cast := PhysicsRayQueryParameters3D.create(Vector3(0.5,3,2),Vector3(0.5,-1,2),256)
	check(root.get_world_3d().direct_space_state.intersect_ray(removed_cast).is_empty(),"removed floor and boundary do not keep stale physics")
	# A very narrow centre strip still represents a full-width physical path.
	# Individual shifted wall endpoints used to block this legal union seam.
	dynamic.rects=[Rect2(0,0,2,2),Rect2(2,0.99,2,0.004),Rect2(4,0,2,2)]
	space.rebuild(dynamic); await settle()
	var narrow_probe:=capsule(Vector3(1,0.01,0.992))
	await settle()
	check(not space.route(Vector3(1,0,0.992),Vector3(5,0,0.992)).is_empty(),"narrow actor-centre seam remains navigable")
	var narrow_hit:=narrow_probe.move_and_collide(Vector3(4,0,0))
	check(narrow_hit==null and narrow_probe.global_position.x>4.99,"compensated union walls do not invent a barrier across a legal centre seam")
	narrow_probe.queue_free()
	space.clear()
	space.queue_free(); dynamic.queue_free()
	await settle()
	host.queue_free()
	await process_frame
	print("[ground-space] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
