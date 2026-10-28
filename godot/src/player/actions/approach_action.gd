extends RefCounted
func execute(c, target: Node3D) -> bool:
	if not is_instance_valid(target) or c.mode()==3: return false
	if target.has_method("blocked_reason"):
		var reason: String = target.blocked_reason()
		if reason!="":
			c.notify(reason)
			return false
	var zone: Node3D = c.ports.zone.call()
	if zone==null: return false
	if target.has_meta("approach_points"):
		var best := Vector3.INF
		var best_area: Node3D
		var distance := INF
		for point: Vector3 in target.get_meta("approach_points"):
			var ground=zone.area_containing(point.x,point.z)
			if ground==null or ground.path_between(c.actor.global_position,point).is_empty(): continue
			var d: float=c.actor.global_position.distance_squared_to(point)
			if d<distance: distance=d;best=point;best_area=ground
		if best==Vector3.INF or not c.start_walk(best_area,best): return false
		var route: Array=c.walk_path.duplicate();route.push_front(c.actor.global_position)
		c.machine.change("approaching",{"area":best_area,"target":best,"path":route,"subject":target})
		return true
	var area = zone.area_containing(target.global_position.x,target.global_position.z)
	if area==null: return false
	var direction: Vector3 = c.actor.global_position-target.global_position
	direction.y=0
	if direction.length()<0.01: direction=Vector3.FORWARD
	var point: Vector2 = area.clamp_point(target.global_position.x+direction.normalized().x*1.35,target.global_position.z+direction.normalized().z*1.35)
	if not c.start_walk(area,Vector3(point.x,area.surface_y,point.y)): return false
	# Keep the already validated path; switching states uses an owned copy.
	var path: Array = c.walk_path.duplicate()
	path.push_front(c.actor.global_position)
	c.machine.change("approaching",{"area":area,"target":c.walk_target,"path":path,"subject":target})
	c.notify("前往 · "+str(target.label))
	return true
