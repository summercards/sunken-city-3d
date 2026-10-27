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
	elif not area.contains_world(start.x,start.z) or absf(start.y-area.surface_y)>0.4:
		c.notify("这里与脚下地面不连通，请换泊位上岸")
		return {"ok":false}
	var path: Array[Vector3] = area.path_between(start,target)
	if path.is_empty():
		c.notify("地面不连通，无法直接走过去")
		return {"ok":false}
	return {"ok":true,"path":path,"start":start}

func step(c, delta: float) -> bool:
	var budget := SPEED*delta
	while not c.walk_path.is_empty() and budget>0.0:
		var next: Vector3 = c.walk_path[0]
		var offset: Vector3 = next-c.actor.global_position
		var distance := offset.length()
		var length := minf(distance,budget)
		if distance>0.0001:
			var candidate: Vector3 = c.actor.global_position + offset/distance*length
			if not is_instance_valid(c.walk_area) or not c.walk_area.contains_world(candidate.x,candidate.z):
				c.cancel()
				return false
			c.actor.global_position = candidate
			c.actor.rotation.y = lerp_angle(c.actor.rotation.y,atan2(-offset.z,offset.x),1.0-exp(-12.0*delta))
		budget -= length
		if distance<=length+0.0001: c.walk_path.pop_front()
		else: break
	return c.walk_path.is_empty()
