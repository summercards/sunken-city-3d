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
		# Match start_walk's disembark preparation: the shore route begins at
		# the current landing, not at the actor's seat outside the walk surface.
		var start: Vector3 = c.actor.global_position
		var landing: Node3D = c.current_landing()
		if c.mode()!=0:
			if landing==null:
				c.notify("请先停靠这块地面的泊位")
				return false
			start=landing.stand_position()
		var best := Vector3.INF
		var best_area: Node3D
		var best_route: Array = []
		var custom_path := target.has_method("approach_path")
		var distance := INF
		for point: Vector3 in target.get_meta("approach_points"):
			var ground=zone.area_at(point,1.4)
			if ground==null: continue
			if c.mode()!=0 and landing.ground()!=ground: continue
			var candidate_route: Array = target.approach_path(start, point) if custom_path else ground.path_between(start, point)
			if candidate_route.is_empty(): continue
			var d: float=start.distance_squared_to(point)
			if d<distance: distance=d;best=point;best_area=ground;best_route=candidate_route
		if best==Vector3.INF:
			c.notify("那里够不着，换一处岸边再试")
			return false
		if not c.start_walk(best_area,best): return false
		# start_walk 保留支撑面、靠泊与状态准备检查；可选端口的净空路线不能被普通求路覆盖。
		var route: Array = best_route.duplicate() if custom_path else c.walk_path.duplicate()
		if not custom_path: route.push_front(c.actor.global_position)
		c.machine.change("approaching",{"area":best_area,"target":best,"path":route,"subject":target})
		return true
	var area = zone.area_at(anchor,1.4)
	if area==null:
		c.notify("那里走不过去")
		return false
	var direction: Vector3 = c.actor.global_position-anchor
	direction.y=0
	if direction.length()<0.01: direction=Vector3.FORWARD
	# 站位距离 = 目标的「站在多远能够到」+ 一点让开自身轮廓的余量。
	#
	# 原来写死 1.35 米。对码头上的箱子够用，但**大件物品会把人放进它自己的身体里**：
	# 2026-11-06 房间放大 1.5 倍后，床的半长变成 1.52 米，1.35 的落点落在床垫上，
	# 角色一走过去就被床挡住 → `walk_action.step` 判「前面被挡住了」→ `cancel()`，
	# 于是点床边永远睡不着，而且没有任何报错。
	#
	# `effective_focus_radius()` 本来就是「这个物件要站多近才算够得着」，
	# 它已经按视觉尺寸放大过（`auto_radius`）。站位取它再让 0.35 米，
	# 小物件行为不变（1.35 是下限），大物件自动站远。
	var stand_off := 1.35
	if target.has_method("effective_focus_radius"):
		stand_off = clampf(float(target.effective_focus_radius()) + 0.35, 1.35, 2.6)
	var point: Vector2 = area.clamp_point(anchor.x+direction.normalized().x*stand_off,
		anchor.z+direction.normalized().z*stand_off)
	var support: Vector3 = area.surface_point(Vector3(point.x,anchor.y,point.y))
	if not support.is_finite():
		c.notify("那里没有可以站立的地面")
		return false
	# start_walk 内部会再核一次「同不同一块地面 / 路径通不通」，失败时它自己会 notify。
	if not c.start_walk(area,support): return false
	# Keep the already validated path; switching states uses an owned copy.
	var path: Array = c.walk_path.duplicate()
	path.push_front(c.actor.global_position)
	c.machine.change("approaching",{"area":area,"target":c.walk_target,"path":path,"subject":target})
	c.notify("前往 · "+str(target.label))
	return true
