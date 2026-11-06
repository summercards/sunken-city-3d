extends SceneTree
## 专属纯规则门禁：无 Main、Autoload 查询、渲染或玩家存档读写。
const Catalog=preload("res://src/building/building_catalog.gd")
const Rules=preload("res://src/building/assembly_rules.gd")
const Surfaces=preload("res://src/building/assembly_surfaces.gd")
const Service=preload("res://src/building/building_service.gd")
const Space=preload("res://src/building/building_space.gd")
const World=preload("res://src/building/building_world.gd")
var checks:=0
var failures:=0
var payments:=0
var refunds:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func row(kind: String,id: int,at: Vector2,height: float=0.0,turn: int=0,support: String="") -> Dictionary:
	return {"id":"built_%d"%id,"kind":kind,"x":0,"z":0,"px":at.x,"pz":at.y,"py":height,"turn":turn,"support":support,"left":0.0}
func model() -> RefCounted:
	var service:=Service.new()
	service.configure({"eligibility":func(): return "","space_reason":func(_r): return "","pay":func(_c): payments+=1;return true,"refund":func(_c): refunds+=1;return true})
	return service
func at_offset(origin: Vector2,offset: Vector2,turn: int) -> Vector2:
	return origin+offset.rotated(-float(turn)*PI/2)
func same_saved_schema(a: Dictionary,b: Dictionary) -> bool:
	if int(a.get("version",-1))!=int(b.get("version",-1)) or int(a.get("next_id",-1))!=int(b.get("next_id",-1)): return false
	var left: Array=a.get("instances",[]);var right: Array=b.get("instances",[])
	if left.size()!=right.size(): return false
	for i in left.size():
		var x: Dictionary=left[i];var y: Dictionary=right[i]
		for key in ["id","kind","support"]:
			if str(x.get(key,""))!=str(y.get(key,"")): return false
		for key in ["x","z","turn"]:
			if int(x.get(key,0))!=int(y.get(key,0)): return false
		for key in ["px","pz","py","left"]:
			if absf(float(x.get(key,0))-float(y.get(key,0)))>.000001: return false
		if bool(x.get("positioned",false))!=bool(y.get("positioned",false)): return false
	return true
func has_ground_return(rows: Array,actor: Vector3) -> bool:
	var parts: Array=Surfaces.records(rows)
	var groups: Array=Surfaces.groups(parts)
	var actor_groups: Array=Surfaces.point_groups(parts,groups,actor)
	for i in parts.size():
		var part: Dictionary=parts[i]
		if part.slope.is_empty() and Catalog.same_level(float(part.height),0.0) and actor_groups.has(groups[i]): return true
	return false
func connected_slopes(rows: Array) -> bool:
	var parts: Array=Surfaces.records(rows)
	var slopes: Array=parts.filter(func(part): return not part.slope.is_empty())
	return slopes.size()==2 and Surfaces.connected(slopes[0],slopes[1])
func four_directions() -> void:
	for turn in 4:
		for kind in ["stairs","stairs_5m"]:
			var label: String=kind+" 方向"+str(turn)
			var origin:=Vector2(100,100)
			var extent: Vector2=Catalog.RECIPES[kind].footprint
			var rise:=Catalog.stair_rise({"kind":kind})
			var base:=row("platform_5x5",1,origin)
			var lower:=row(kind,2,origin,0,turn,"built_1")
			var upper:=row(kind,3,at_offset(origin,Vector2(0,-extent.y),turn),rise,turn,"built_2")
			check(Rules.reason(lower,[base])=="",label+" 完整平台支撑")
			check(Rules.reason(upper,[base,lower])=="",label+" 首尾连续无需整段平台")
			check(connected_slopes([lower,upper]),label+" 首尾导航连通")
			var edge: Array=Catalog.stairs_low_edge(lower)
			var middle: Vector2=(edge[0]+edge[1])/2
			var partial:=row("upper_floor",4,at_offset(middle,Vector2(.6,.5),turn),0,turn)
			var low_partial:=lower.duplicate();low_partial.support="built_4"
			check(Rules.reason(low_partial,[partial])=="",label+" 低端部分平台接缝")
			var parallel:=row(kind,4,at_offset(origin,Vector2(extent.x,0),turn),0,turn,"built_1")
			check(Rules.reason(parallel,[base,lower])=="",label+" 并排零间隔可放")
			check(Catalog.stairs_parallel(lower,parallel),label+" 并排识别")
			var opposite:=parallel.duplicate();opposite.turn=(turn+2)%4
			check(not Catalog.stairs_parallel(lower,opposite) and not connected_slopes([lower,opposite]),label+" 逆向侧边不产生虚假导航")
			var mismatched:=parallel.duplicate();mismatched.kind="stairs" if kind=="stairs_5m" else "stairs_5m"
			check(not Catalog.stairs_parallel(lower,mismatched),label+" 不同rise与length不判并排")
			check(connected_slopes([lower,parallel]),label+" 并排侧边导航无0.44米缝")
			var overlap:=parallel.duplicate()
			var overlap_at:=at_offset(origin,Vector2(extent.x-.05,0),turn)
			overlap.px=overlap_at.x;overlap.pz=overlap_at.y
			check(Rules.reason(overlap,[base,lower])!="",label+" 实体重叠拒绝")
			var gap:=upper.duplicate()
			var gap_at:=at_offset(Vector2(upper.px,upper.pz),Vector2(0,-.02),turn)
			gap.px=gap_at.x;gap.pz=gap_at.y
			check(Rules.reason(gap,[base,lower])!="",label+" 2厘米隔空首尾拒绝")
			var wrong:=upper.duplicate();wrong.py+=.1
			check(Rules.reason(wrong,[base,lower])!="",label+" 错层拒绝")
			var reverse:=upper.duplicate();reverse.turn=(turn+2)%4
			check(Rules.reason(reverse,[base,lower])!="",label+" 逆向不误联")
			var floating:=lower.duplicate();floating.support="missing"
			check(Rules.reason(floating,[])!="",label+" 无支撑拒绝")
			var near:=parallel.duplicate()
			var near_at:=at_offset(Vector2(near.px,near.pz),Vector2(.08,.06),turn)
			near.px=near_at.x;near.pz=near_at.y;near.support="stale"
			var snapped:=Catalog.snap_stairs(near,[base,lower])
			check(Catalog.stairs_parallel(lower,snapped) and Rules.reason(snapped,[base,lower])=="",label+" 并排矩形吸附并更新支撑")
			var no_assist:=Catalog.snap_stairs(near,[base,lower],false)
			check(no_assist.px==near.px and no_assist.pz==near.pz,label+" G关闭不改坐标")
			var manual:=Catalog.snap_stairs(parallel,[base,lower],false)
			check(Rules.reason(manual,[base,lower])=="",label+" 关闭吸附仍可手动贴边")
			var end_near:=upper.duplicate();end_near.px+=.08;end_near.pz+=.06;end_near.support=""
			var end_snap:=Catalog.snap_stairs(end_near,[base,lower])
			check(Rules.reason(end_snap,[base,lower])=="",label+" 首尾吸附")
			var distant:=upper.duplicate();distant.px+=20;distant.pz+=20
			var distant_snap:=Catalog.snap_stairs(distant,[base,lower])
			check(distant_snap.px==distant.px and distant_snap.pz==distant.pz,label+" 远处不强吸")
			var parts: Array=Surfaces.records([lower,parallel])
			var shared:=at_offset(origin,Vector2(extent.x/2,0),turn)
			var groups: Array=Surfaces.groups(parts)
			check(not Surfaces.point_groups(parts,groups,Vector3(shared.x,rise/2,shared.y)).is_empty(),label+" 共享侧边可站立")
			var high:=Catalog.snap_foundation("platform_5x5",at_offset(origin,Vector2(0,-extent.y/2-1),turn),turn,[base,lower],false,rise)
			check(Catalog.stairs_top_contact(Catalog.footprint_rect(high),lower)>=Catalog.JOIN_MIN,label+" 顶部同种平台接续")
func save_and_demolition() -> void:
	for first_kind in ["stairs","stairs_5m"]:
		for turn in 4:
			var second_kind: String="stairs_5m" if first_kind=="stairs" else "stairs"
			var first_extent: Vector2=Catalog.RECIPES[first_kind].footprint
			var second_extent: Vector2=Catalog.RECIPES[second_kind].footprint
			var origin:=Vector2(200.123,200.456)
			var base:=row("platform_5x5",1,origin)
			var first:=row(first_kind,2,origin,0,turn,"built_1")
			var second_at:=at_offset(origin,Vector2(0,-(first_extent.y+second_extent.y)/2),turn)
			var second:=row(second_kind,3,second_at,Catalog.stair_rise(first),turn,"built_2")
			var top:=Catalog.stair_rise(first)+Catalog.stair_rise(second)
			var floor_at:=at_offset(second_at,Vector2(0,-second_extent.y/2-2.5),turn)
			var floor:=row("platform_5x5",4,floor_at,top,turn)
			var furniture:=row("oil_lamp",5,floor_at,top,0,"built_4")
			var grid: Dictionary={"id":"built_6","kind":"deck","x":20,"z":20,"px":0.0,"pz":0.0,"turn":0,"support":"","left":0.0}
			var snapshot: Dictionary={"version":1,"next_id":7,"instances":[base,first,second,floor,furniture,grid]}
			var label: String=first_kind+" 混合方向"+str(turn)
			check(Service.validate_snapshot(snapshot)=="",label+" 混合存档合法")
			var reversed:=snapshot.duplicate(true);reversed.instances.reverse()
			check(Service.validate_snapshot(reversed)=="",label+" 反序合法")
			var model_a:=model()
			var json: Dictionary=JSON.parse_string(JSON.stringify(reversed))
			check(model_a.from_dict(json),label+" JSON反序恢复")
			check(same_saved_schema(model_a.to_dict(),json),label+" 原schema字段和坐标往返不变")
			check(Catalog.placement_levels(model_a.query()).any(func(height): return absf(height-top)<.000001),label+" 混合高度精确保留")
			check(model_a.can_remove("built_2")!="",label+" 不许拆下梯留上梯孤儿")
			check(model_a.can_remove("built_3")!="",label+" 最后一梯保护未命名上层板")
			var floating:=row("platform_5x5",7,Vector2(500,500),top,turn)
			floating.origin="boat"
			check(not model_a.begin(floating).ok,label+" 有限任意高不等于可独立起板")
			var before_pay:=payments;var before: Dictionary=model_a.to_dict()
			for i in 3:
				model_a.preview_reason(floating)
				Catalog.snap_stairs(second,model_a.query(),false)
			check(payments==before_pay and model_a.to_dict()==before,label+" 预览后取消不扣费不修改")
	# 双梯给同一上层面提供两个真实根，允许拆第一条但禁止拆最后一条。
	var base:=row("platform_5x5",1,Vector2(300,300))
	var first:=row("stairs_5m",2,Vector2(299.25,300),0,0,"built_1")
	var second:=row("stairs_5m",3,Vector2(300.75,300),0,0,"built_1")
	var floor:=row("platform_5x5",4,Vector2(300,295),Catalog.LAYER_HEIGHT,0,"built_2")
	var extension:=row("platform_5x5",5,Vector2(305,295),Catalog.LAYER_HEIGHT)
	# 梯长与原底板同为5米；仅有底板时坡脚之外没有落地面，原夹具本已不可返程。
	var landing:=row("platform_5x5",6,Vector2(300,305))
	var data: Dictionary={"version":1,"next_id":7,"instances":[landing,extension,floor,second,first,base]}
	var actor:=Vector3(300,Catalog.LAYER_HEIGHT,295)
	var service:=model();check(service.from_dict(data),"双梯反序夹具恢复")
	check(has_ground_return(service.query(),actor),"双梯拆前角色已有真实坡脚落地返程")
	var first_removed: Array=service.query().filter(func(item): return str(item.id)!="built_2")
	check(has_ground_return(first_removed,actor),"替代楼梯仍连接上层角色与0层落地面")
	check(Surfaces.safety_reason(service.query(),first_removed,actor,true,[])=="","有替代梯路允许安全拆第一梯")
	check(service.can_remove("built_2")=="","其他真实支撑存在允许拆梯")
	check(service.remove("built_2").ok,"拆梯提交成功")
	check(str(service.row("built_4").support)=="built_3","拆梯后主支撑重绑定")
	check(Service.validate_snapshot(service.to_dict())=="","重绑定后的存档合法")
	check(service.can_remove("built_3")!="","平台互接不形成承载循环，最后一梯拒绝")
	var after: Array=service.query().filter(func(item): return str(item.id)!="built_3")
	check(has_ground_return(service.query(),actor),"最后一梯拆前角色仍有真实返程")
	check(not has_ground_return(after,actor),"最后一梯拆后角色失去真实返程")
	check(Surfaces.contains(actor,after),"拆后上层落脚点仍在，拒绝原因不是角色悬空")
	check(Surfaces.safety_reason(service.query(),after,actor,true,[])!="","角色返程楼层保护")
func reject_restore(service: RefCounted,data: Dictionary,label: String,events: Array) -> void:
	for reverse in [false,true]:
		var candidate:=data.duplicate(true)
		if reverse: candidate.instances.reverse()
		var suffix: String=label+(" 反序" if reverse else " 正序")
		var before: Dictionary=service.to_dict()
		var before_pay:=payments;var before_refund:=refunds;var before_events:=int(events[0])
		check(Service.validate_snapshot(candidate)!="",suffix+" 校验拒绝")
		check(not service.from_dict(candidate),suffix+" 恢复拒绝")
		check(service.to_dict()==before,suffix+" 不修改布局与序列")
		check(payments==before_pay and refunds==before_refund and int(events[0])==before_events,suffix+" 不扣费退款或发出changed")
func snapshot_roots() -> void:
	var service:=model()
	var seed: Dictionary={"version":1,"next_id":2,"instances":[row("platform_5x5",1,Vector2(600,600))]}
	check(service.from_dict(seed),"承载坏档测试初始布局恢复")
	var events: Array=[0]
	service.changed.connect(func(): events[0]+=1)
	for kind in ["platform_5x5","upper_floor","raft_4x4","deck"]:
		var isolated:=row(kind,2,Vector2(620,620),999)
		if kind=="deck": isolated.positioned=true
		reject_restore(service,{"version":1,"next_id":3,"instances":[seed.instances[0],isolated]},kind+" 孤立999米平台",events)
	var old_fractional:=row("upper_floor",2,Vector2(620,620),2.81)
	reject_restore(service,{"version":1,"next_id":3,"instances":[seed.instances[0],old_fractional]},"旧非整层悬空平台",events)
	for kind in ["platform_5x5","upper_floor"]:
		var span: float=Catalog.RECIPES[kind].footprint.x
		var a:=row(kind,2,Vector2(620,620),Catalog.LAYER_HEIGHT,0,"built_3")
		var b:=row(kind,3,Vector2(620+span,620),Catalog.LAYER_HEIGHT,0,"built_2")
		reject_restore(service,{"version":1,"next_id":4,"instances":[seed.instances[0],a,b]},kind+" 高层互接引用循环",events)
	var base:=row("platform_5x5",1,Vector2(650,650))
	var stair:=row("stairs_5m",2,Vector2(650,650),0,0,"built_1")
	var floor:=row("platform_5x5",3,Vector2(650,645),Catalog.LAYER_HEIGHT,0,"built_2")
	var valid: Dictionary={"version":1,"next_id":4,"instances":[floor,stair,base]}
	check(Service.validate_snapshot(valid)=="","反序新高层梯顶具名支撑合法")
	var wrong:=valid.duplicate(true);wrong.instances[0].support="built_1"
	reject_restore(service,wrong,"有真实梯顶根仍拒绝跨层具名底板",events)
	var floating_floor:=valid.duplicate(true);floating_floor.instances[0].py+=.1
	reject_restore(service,floating_floor,"具名梯顶高度错层",events)
	var next_floor:=row("platform_5x5",4,Vector2(655,645),Catalog.LAYER_HEIGHT,0,"built_3")
	valid.instances.append(next_floor);valid.next_id=5
	check(Service.validate_snapshot(valid)=="","高层平台具名同层真实接边合法")
	var far:=valid.duplicate(true);far.instances[-1].px+=20
	reject_restore(service,far,"同高但隔空具名平台",events)
	var pending:=valid.duplicate(true);pending.instances[1].left=1.0
	reject_restore(service,pending,"施工中楼梯不能成为高层承载根",events)
	for key in ["py","px","pz","left"]:
		for invalid in [INF,NAN]:
			var nonfinite:=valid.duplicate(true)
			var future:=row("platform_5x5",5,Vector2(700,700))
			future[key]=invalid
			nonfinite.instances.append(future);nonfinite.next_id=6
			reject_restore(service,nonfinite,"后置记录非有限 "+key+" "+str(invalid),events)
	# 旧2.8米柱/墙顶部挂点必须从原平台派生，且不依赖记录顺序。
	for support_kind in ["post","wall"]:
		var old_base:=row("raft_4x4",1,Vector2(750,750))
		var bearing:=row(support_kind,2,Vector2(750,750),0,0,"built_1")
		var old_floor:=row("upper_floor",3,Vector2(750,750),Catalog.LEGACY_LAYER_HEIGHT,0,"built_2")
		var legacy: Dictionary={"version":1,"next_id":4,"instances":[old_base,bearing,old_floor]}
		check(Service.validate_snapshot(legacy)=="","旧2.8层 "+support_kind+" 真实挂点根合法")
		legacy.instances.reverse()
		var roundtrip:=model()
		check(roundtrip.from_dict(JSON.parse_string(JSON.stringify(legacy))),"旧2.8层 "+support_kind+" 反序恢复合法")
		check(same_saved_schema(roundtrip.to_dict(),legacy),"旧2.8层 "+support_kind+" 坐标与schema不变")
		var bad_bearing:=legacy.duplicate(true);bad_bearing.instances[-1].py=.1
		reject_restore(service,bad_bearing,"旧挂点根所在平台悬空 "+support_kind,events)
	var ground: Dictionary={"version":1,"next_id":3,"instances":[row("platform_5x5",1,Vector2(800,800)),row("raft_4x4",2,Vector2(900,900))]}
	check(Service.validate_snapshot(ground)=="","历史新旧水面孤台继续合法")
func geometry_and_compatibility() -> void:
	check(Catalog.RECIPES.size()==35,"双目录22+10件与3个旧配方")
	check(Catalog.LAYER_HEIGHT==5.086335 and Catalog.LEGACY_LAYER_HEIGHT==2.8,"新旧层高常量独立")
	check(Catalog.TILE==Vector2(2.15,2.575) and Catalog.BASE==Rect2(-3.225,-2.575,6.45,5.15),"旧网格不变")
	check(not Catalog.enabled("deck") and not Catalog.enabled("wall") and Catalog.api_enabled("wall"),"菜单隐藏与兼容API分离")
	check(Catalog.enabled("platform_5x5") and Catalog.enabled("oil_lamp"),"新平台与旧摆件仍入菜单")
	check(Catalog.valid_level(2.8+5.086335) and not Catalog.valid_level(INF) and not Catalog.valid_level(100001),"混合层高与有限上限")
	for kind in ["wall","wall_5m","beam","beam_5m","railing_5m"]:
		var item:=row(kind,1,Vector2(100,100))
		var points:=Rules.joint_points(item)
		check(absf(points[0].distance_to(points[1])-Catalog.RECIPES[kind].footprint.x)<.0001,"挂点按实际跨度 "+kind)
	for kind in ["door_frame","door_frame_5m"]:
		var item:=row(kind,1,Vector2(100,100))
		var cuts:=Space.blocker_rects(item)
		var width: float=1.85 if kind=="door_frame_5m" else 1.16
		check(absf(cuts[1].position.x-cuts[0].end.x-width)<.0001,"实际门洞宽度 "+kind)
	var service:=model()
	var made: Dictionary=service.begin({"kind":"raft_4x4","px":400.0,"pz":400.0,"origin":"boat"})
	service.tick(30)
	check(made.ok and service.begin({"kind":"stairs","px":400.0,"pz":400.0,"support":made.id}).ok,"旧ID直接begin兼容")
	var world:=World.new()
	# 这里只调用二维工地点分支，不进入场景树或生成渲染模型。
	world.area=preload("res://src/navigation/walk_area.gd").new()
	world.area.rects=[Rect2(Vector2(497.5,497.5),Vector2(5,5))]
	var request:=row("platform_5x5",1,Vector2(505,500))
	var actor:=Catalog.ORIGIN+Vector3(500,0,500)
	var stand: Vector3=world.find_stand_point(actor,Catalog.ORIGIN+Vector3(505,0,500),2.8,request)
	check(stand.is_finite(),"5米平台工地点按实际边界可达")
	world.area.free();world.free()
func run() -> void:
	geometry_and_compatibility()
	four_directions()
	save_and_demolition()
	snapshot_roots()
	print("[building-5m-rules] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
