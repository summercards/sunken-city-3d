extends RefCounted
## 走过去，到位后由 main 打开自动长按。
##
## 每一处失败都必须说出原因（2026-10-29）。以前这里 `return false` 是静默的：
## 点在隔水水箱上 → 气泡关掉 → 角色不动 → 玩家读成「点了没反应」。
## 现在「走不过去」「不在这块地面」都走 `notify`，和其它拒绝反馈同一个口径。
##
## 落点一律按 `focus_position()`（视觉包围盒中心）算，和热区判定、悬浮图标同源。
## 出货箱的节点原点与箱子本体差 2 米，用原点会让角色走到旁边空地上再「够不着」。

func execute(c, target: Node3D) -> bool:
	if not is_instance_valid(target):
		c.notify("目标已经不在了")
		return false
	if c.mode()==3:
		c.notify("先浮上水面再过去")
		return false
	if target.has_method("blocked_reason"):
		var reason: String = target.blocked_reason()
		if reason!="":
			c.notify(reason)
			return false
	var zone: Node3D = c.ports.zone.call()
	if zone==null:
		c.notify("这里没有可以走过去的地面")
		return false
	var anchor: Vector3 = target.focus_position() if target.has_method("focus_position") else target.global_position
	if target.has_meta("approach_points"):
		var best := Vector3.INF
		var best_area: Node3D
		var distance := INF
		for point: Vector3 in target.get_meta("approach_points"):
			var ground=zone.area_containing(point.x,point.z)
			if ground==null or ground.path_between(c.actor.global_position,point).is_empty(): continue
			var d: float=c.actor.global_position.distance_squared_to(point)
			if d<distance: distance=d;best=point;best_area=ground
		if best==Vector3.INF:
			c.notify("那里够不着，换一处岸边再试")
			return false
		if not c.start_walk(best_area,best): return false
		var route: Array=c.walk_path.duplicate();route.push_front(c.actor.global_position)
		c.machine.change("approaching",{"area":best_area,"target":best,"path":route,"subject":target})
		return true
	var area = zone.area_containing(anchor.x,anchor.z)
	if area==null:
		c.notify("那里走不过去")
		return false
	var direction: Vector3 = c.actor.global_position-anchor
	direction.y=0
	if direction.length()<0.01: direction=Vector3.FORWARD
	var point: Vector2 = area.clamp_point(anchor.x+direction.normalized().x*1.35,anchor.z+direction.normalized().z*1.35)
	# start_walk 内部会再核一次「同不同一块地面 / 路径通不通」，失败时它自己会 notify。
	if not c.start_walk(area,Vector3(point.x,area.surface_y,point.y)): return false
	# Keep the already validated path; switching states uses an owned copy.
	var path: Array = c.walk_path.duplicate()
	path.push_front(c.actor.global_position)
	c.machine.change("approaching",{"area":area,"target":c.walk_target,"path":path,"subject":target})
	c.notify("前往 · "+str(target.label))
	return true
