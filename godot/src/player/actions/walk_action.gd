extends RefCounted
const SPEED := 2.3
func prepare(c, area: Node3D, target: Vector3) -> Dictionary:
	if area == null or c.vessel.starts_sailing() or c.mode()==3: return {"ok":false}
	var start: Vector3 = c.actor.global_position
	var landing: Node3D = c.current_landing()
	if c.mode()!=0:
		if landing==null or landing.ground()!=area:
			c.notify("请先停靠这块地面的泊位")
			return {"ok":false}
		var park: Vector3 = landing.get_node("BoatPark").global_position
		if Vector2(c.vessel.position.x-park.x,c.vessel.position.z-park.z).length()>1.0:
			c.notify("请先靠泊再上岸")
			return {"ok":false}
		start = landing.stand_position()
	elif not _has_support(area, start):
		c.notify("这里与脚下地面不连通，请换泊位上岸")
		return {"ok":false}
	var path: Array[Vector3] = area.path_between(start,target)
	if path.is_empty():
		c.notify("地面不连通，无法直接走过去")
		return {"ok":false}
	return {"ok":true,"path":path,"start":start}

func _has_support(area: Node3D, point: Vector3) -> bool:
	if is_instance_valid(area.ground_space):
		return area.ground_space.area_at(point, 0.5) != null
	return area.contains_position(point, 0.5)

func step(c, delta: float) -> bool:
	var budget := SPEED*delta
	while not c.walk_path.is_empty() and budget>0.0:
		var next: Vector3 = c.walk_path[0]
		if is_instance_valid(c.walk_area.ground_space):
			next = c.walk_area.ground_space.body_point(next)
		var offset: Vector3 = next-c.actor.global_position
		var distance := offset.length()
		var length := minf(distance,budget)
		if distance>0.0001:
			var candidate: Vector3 = c.actor.global_position + offset/distance*length
			if not is_instance_valid(c.walk_area) or not _has_support(c.walk_area, candidate):
				c.cancel()
				return false
			var result: Dictionary = c.actor.move_ground(offset/distance*length, delta)
			if bool(result.blocked) and (result.moved as Vector3).length() < length * 0.05:
				c.notify("前面被挡住了")
				c.cancel()
				return false
			# Character 的脸、脚尖朝局部 +Z；偏航必须将 +Z 对齐行走方向。
			c.actor.rotation.y = lerp_angle(c.actor.rotation.y,atan2(offset.x,offset.z),1.0-exp(-12.0*delta))
		budget -= length
		# The capsule rests a fraction above the face (physics safe margin).
		# Do not keep chasing that sub-millimetre vertical recovery forever.
		var rest: Vector3 = c.actor.global_position-next
		if Vector2(rest.x,rest.z).length() <= 0.0005 and absf(rest.y) <= 0.02: c.walk_path.pop_front()
		else: break
	return c.walk_path.is_empty()
