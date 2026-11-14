extends SceneTree
## B3：真实服务命令拒绝内容漂移，旧三参吸附入口保持兼容。
const Catalog=preload("res://src/building/building_catalog.gd")
const Rules=preload("res://src/building/assembly_rules.gd")
const Service=preload("res://src/building/building_service.gd")
var checks:=0
var failures:=0
var payments: Array=[]
var refunds: Array=[]
var events:=0
var energy_spent:=0
var poison_port:=""

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func poison(port: String) -> void:
	if poison_port==port: Catalog.RECIPES.oil_lamp.cost.wood+=7
func model() -> RefCounted:
	var service:=Service.new()
	service.configure({
		"eligibility":func(): poison("eligibility");return "",
		"space_reason":func(_request): poison("space_reason");return "",
		"capacity_reason":func(_rows): poison("capacity_reason");return "",
		"layout_reason":func(_before,_after,_request): poison("layout_reason");return "",
		"energy_reason":func(_action): poison("energy_reason");return "",
		"spend_energy":func(_action): energy_spent+=1,
		"pay":func(cost): payments.append(cost.duplicate(true));return true,
		"refund":func(cost): refunds.append(cost.duplicate(true));return true})
	service.changed.connect(func(): events+=1)
	return service
func lamp(at: Vector2=Vector2.ZERO) -> Dictionary:
	return {"kind":"oil_lamp","px":at.x,"pz":at.y,"turn":0,"support":"@base"}
func footprint_drift() -> void:
	Catalog.RECIPES.oil_lamp.footprint+=Vector2(1,1)
func unchanged(service: RefCounted,before: Dictionary,counters: Array,label: String) -> void:
	check(service.to_dict()==before,label+" 布局、计时与序列不变")
	check([payments.size(),refunds.size(),events,energy_spent]==counters,label+" 不支付、不退款、不发事件、不扣体力")
	check(not service.busy(),label+" 提交锁未遗留")
func guard_commands() -> void:
	var service:=model()
	var original: Dictionary=Catalog.RECIPES.oil_lamp.duplicate(true)
	var built: Dictionary=service.begin(lamp())
	check(built.ok and payments[-1]==original.cost,"基线真实 begin 按原价支付")
	if not built.ok: return
	service.tick(30)
	var destination:=lamp(Vector2(1,0))
	for field in ["cost","footprint"]:
		var before: Dictionary=service.to_dict()
		var counters: Array=[payments.size(),refunds.size(),events,energy_spent]
		if field=="cost": Catalog.RECIPES.oil_lamp.cost.wood+=7
		else: footprint_drift()
		var reason:=Catalog.verify_content()
		check(reason.contains("oil_lamp") and reason.contains("定义被改写"),field+" 漂移原因明确")
		check(service.context_reason()==reason,field+" 资格入口拒绝")
		check(service.can_place(destination)==reason,field+" can_place 拒绝")
		check(service.preview_reason(destination)==reason and service.preview_reason(destination,true)==reason,field+" 两档预览拒绝")
		var started: Dictionary=service.begin(destination)
		check(not started.ok and started.reason==reason,field+" 真实 begin 拒绝")
		check(service.can_move(built.id,destination)==reason,field+" can_move 拒绝")
		var moved: Dictionary=service.move(built.id,destination)
		check(not moved.ok and moved.reason==reason,field+" 真实 move 拒绝")
		check(service.can_remove(built.id)==reason,field+" can_remove 拒绝")
		var removed: Dictionary=service.remove(built.id)
		check(not removed.ok and removed.reason==reason,field+" 真实 remove 拒绝")
		check(Service.validate_snapshot(before)==reason and not service.from_dict(Service.empty_snapshot()),field+" 快照恢复不绕过")
		unchanged(service,before,counters,field)
		Catalog.RECIPES.oil_lamp=original.duplicate(true)
		check(Catalog.verify_content()=="" and service.can_place(destination)=="",field+" 恢复基线后 can_place 正常")
		var recovered: Dictionary=service.begin(destination)
		check(recovered.ok and payments[-1]==original.cost,field+" 恢复后真实 begin 按原价支付")
		if recovered.ok:
			service.tick(30)
			check(service.remove(recovered.id).ok and refunds[-1]==original.cost,field+" 恢复后真实退款仍为原价")
	# 改的是无关配方也必须阻止命令，不能只检查请求中的 kind。
	var before: Dictionary=service.to_dict()
	var counters: Array=[payments.size(),refunds.size(),events,energy_spent]
	Catalog.RECIPES.oil_lamp.cost.wood+=7
	var platform: Dictionary={"kind":"platform_5x5","px":200.0,"pz":200.0,"origin":"boat"}
	check(service.can_place(platform)==Catalog.verify_content() and not service.begin(platform).ok,"无关配方漂移同样全局拒绝")
	unchanged(service,before,counters,"无关配方")
	Catalog.RECIPES.oil_lamp=original.duplicate(true)
	# 查询与布局端口内发生漂移，也不能在末次预检后越过支付/退款/写入。
	for port in ["eligibility","space_reason","capacity_reason","layout_reason","energy_reason"]:
		for operation in ["begin","move","remove"]:
			if operation=="remove" and port=="space_reason": continue
			before=service.to_dict()
			counters=[payments.size(),refunds.size(),events,energy_spent]
			poison_port=port
			var result: Dictionary
			if operation=="begin": result=service.begin(destination)
			elif operation=="move": result=service.move(built.id,destination)
			else: result=service.remove(built.id)
			poison_port=""
			check(not result.ok and str(result.reason).contains("oil_lamp"),operation+" 拒绝 "+port+" 回调造成的漂移")
			unchanged(service,before,counters,operation+" / "+port)
			Catalog.RECIPES.oil_lamp=original.duplicate(true)
	# active 继续是合法运行开关，停用不破坏旧实例的搬移和回收。
	Catalog.RECIPES.oil_lamp.active=false
	check(Catalog.verify_content()=="" and not service.begin(destination).ok,"active 开关不是内容漂移且仍阻止新建")
	check(service.move(built.id,destination).ok,"active 停用不破坏旧实例搬移")
	check(service.remove(built.id).ok and refunds[-1]==original.cost,"active 停用不破坏旧实例回收")
	Catalog.RECIPES.oil_lamp=original.duplicate(true)
	var pending: Dictionary=service.begin(lamp())
	before=service.to_dict();counters=[payments.size(),refunds.size(),events,energy_spent]
	footprint_drift();service.tick(30)
	unchanged(service,before,counters,"漂移期间施工不写布局")
	Catalog.RECIPES.oil_lamp=original.duplicate(true)
	service.tick(30)
	check(pending.ok and service.row(pending.id).left==0,"基线恢复后施工正常完成")
	check(Catalog.verify_content()=="","测试恢复全部目录内容")
func row(kind: String,id: int,at: Vector2,height: float=0.0,turn: int=0) -> Dictionary:
	return {"id":"built_%d"%id,"kind":kind,"x":0,"z":0,"px":at.x,"pz":at.y,"py":height,"turn":turn,"support":"","left":0.0}
func snap_samples() -> Array:
	var samples: Array=[]
	for kind in ["stairs","stairs_5m"]:
		for turn in 4:
			var origin:=Vector2(100.123,100.456)
			var extent: Vector2=Catalog.RECIPES[kind].footprint
			var base:=row("platform_5x5",9,origin)
			var lower:=row(kind,7,origin,0,turn);lower.support=base.id
			var twin:=base.duplicate(true);twin.id="built_2"
			var pending:=base.duplicate(true);pending.id="built_1";pending.left=1.0
			for reverse in [false,true]:
				var rows: Array=[base,twin,pending,lower]
				if reverse: rows.reverse()
				for target in [Vector2(extent.x,0),Vector2(0,-extent.y)]:
					var height:=0.0 if target.x!=0 else Catalog.stair_rise(lower)
					var at: Vector2=origin+target.rotated(-float(turn)*PI/2)
					for offset in [Vector2.ZERO,Vector2(.08,.06),Vector2(-.08,-.06),Vector2(.35,0),Vector2(20,20)]:
						var request:=row(kind,20,at+offset,height,turn);request.support="stale"
						for assist in [false,true]:
							samples.append({"request":request,"rows":rows,"assist":assist,"result":Catalog.snap_stairs(request,rows,assist)})
	return samples
func snap_equivalence() -> void:
	var source:=FileAccess.get_file_as_string("res://src/building/building_catalog.gd")
	check('load("res://src/building/assembly_rules.gd")' in source and not "_bind_stair_rules" in source,"Catalog 旧入口显式装配，不依赖静态注入")
	var rules_source:=FileAccess.get_file_as_string("res://src/building/assembly_rules.gd")
	check(not "src/bootstrap/" in rules_source and not "src/building/ui/" in rules_source,"规则层不反向依赖 UI/Bootstrap")
	var samples:=snap_samples()
	var baseline_path:=OS.get_environment("SEA_B3_SNAP_BASELINE")
	if baseline_path!="":
		var baseline: Variant=JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
		check(baseline is Array and baseline.size()==samples.size(),"解环前样例数量与当前一致")
		if baseline is Array and baseline.size()==samples.size():
			for i in samples.size():
				check(JSON.stringify(Catalog._canonical(samples[i]))==JSON.stringify(Catalog._canonical(baseline[i])), "旧实现吸附输出、顺序与输入逐字段等价 #"+str(i))
	for sample in samples:
		var request: Dictionary=sample.request
		var rows: Array=sample.rows
		var before:=request.duplicate(true);var rows_before:=rows.duplicate(true)
		var snapped:=Catalog.snap_stairs(request,rows,sample.assist)
		check(snapped==Rules.snap_stairs(request,rows,sample.assist),"公开纯规则与旧入口逐字段等价")
		check(request==before and rows==rows_before,"吸附不修改请求或布局")
		var ids:=Rules.support_ids(snapped,rows)
		check(str(snapped.support)==("" if ids.is_empty() else ids[0]),"吸附仍选用原规则首个有序支撑")
		if not sample.assist: check(snapped.px==request.px and snapped.pz==request.pz,"关闭辅助不改变坐标")
func hot_path_guards() -> void:
	var service:=model()
	var built: Dictionary=service.begin(lamp())
	check(built.ok,"热路径夹具真实建造")
	if not built.ok: return
	var count: int=Catalog._full_verification_count
	var started:=Time.get_ticks_usec()
	for i in 120:
		service.tick(0.001)
		check(service.context_reason()=="" and service.geometry_reason(lamp(Vector2(1,0)))=="" and service.preview_reason(lamp(Vector2(1,0)))=="","热路径正常预览 #"+str(i))
		service.snap_planter(lamp(Vector2(3.3,0)))
	check(Catalog._full_verification_count==count,"连续 tick、资格、几何、轻预览与吸附不做完整序列化校验")
	print("[b3-hot-path] 120 组 tick/preview/snap: %d us, full verify delta=%d"%[Time.get_ticks_usec()-started,Catalog._full_verification_count-count])
	var original: Dictionary=Catalog.RECIPES.oil_lamp.duplicate(true)
	var before: Dictionary=service.to_dict()
	var counters: Array=[payments.size(),refunds.size(),events,energy_spent]
	# 已经检查为安全后，通过先前取得的嵌套引用写入；不能靠容器身份或每帧缓存放行。
	var shared_cost: Dictionary=Catalog.RECIPES.oil_lamp.cost
	for mutation in ["nested","footprint","removed","added","type"]:
		if mutation=="nested": shared_cost.wood+=7
		elif mutation=="footprint": footprint_drift()
		elif mutation=="removed": Catalog.RECIPES.erase("oil_lamp")
		elif mutation=="added": Catalog.RECIPES.b3_unknown=original.duplicate(true)
		else: Catalog.RECIPES.oil_lamp="坏类型"
		service.tick(30)
		check(service.context_reason()!="" and service.preview_reason(lamp())!="",mutation+" 公开写入立即被热路径发现")
		unchanged(service,before,counters,mutation+" 热路径拒绝")
		check(Catalog._full_verification_count==count,mutation+" 漂移拒绝不触发完整校验")
		check(Catalog.verify_content()!="",mutation+" 完整校验同样拒绝")
		Catalog.RECIPES.erase("b3_unknown")
		Catalog.RECIPES.oil_lamp=original.duplicate(true)
		count=Catalog._full_verification_count
		check(Catalog.content_reason()=="","恢复后不遗留失败缓存")
	# 数字等价与 active 豁免沿用完整签名语义，其他新增字段不豁免。
	Catalog.RECIPES.oil_lamp.cost.wood=float(original.cost.wood)
	Catalog.RECIPES.oil_lamp.active=false
	check(Catalog.content_reason()=="" and Catalog.verify_content()=="","轻量校验允许等值数字与 active 开关")
	Catalog.RECIPES.oil_lamp.cost.active=false
	check(Catalog.content_reason()!="" and Catalog.verify_content()!="","active 豁免仅限配方顶层")
	Catalog.RECIPES.oil_lamp=original.duplicate(true)
	count=Catalog._full_verification_count
	check(service.preview_reason(lamp(Vector2(1,0)),true)=="" and Catalog._full_verification_count>count,"显式 full preview 执行完整校验")
	count=Catalog._full_verification_count
	check(Service.validate_snapshot(before)=="" and Catalog._full_verification_count>count,"快照验证执行完整校验")
	service.tick(30)
	check(service.row(built.id).left==0,"恢复后施工正常完成")

func catalog_only_process() -> void:
	# 独立最小工程没有 Autoload、Service 或 Rules preload，避免宿主预加载掩盖顺序问题。
	var root:=ProjectSettings.globalize_path("user://b3-catalog-only")
	for directory in [root,root+"/src/building",root+"/assets/data"]:
		check(DirAccess.make_dir_recursive_absolute(directory)==OK,"创建独立夹具目录")
	for relative in ["src/building/building_catalog.gd","src/building/assembly_rules.gd","assets/data/building_kit.json","assets/data/building_kit_5m.json"]:
		var file:=FileAccess.open(root+"/"+relative,FileAccess.WRITE)
		file.store_string(FileAccess.get_file_as_string("res://"+relative))
		file.close()
	var config:=FileAccess.open(root+"/project.godot",FileAccess.WRITE)
	config.store_string('config_version=5\n[application]\nconfig/name="B3 Catalog only"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="sea-verification/b3-catalog-only"\n')
	config.close()
	var fixture:=FileAccess.open(root+"/fixture.gd",FileAccess.WRITE)
	fixture.store_string('''extends SceneTree
const Catalog=preload("res://src/building/building_catalog.gd")
func _init() -> void:
	for kind in ["stairs","stairs_5m"]:
		var z: float=Catalog.BASE.position.y-Catalog.RECIPES[kind].footprint.y/2
		var request: Dictionary={"kind":kind,"px":0.0,"pz":z-0.08,"py":0.0,"turn":0,"support":"stale"}
		var before: Dictionary=request.duplicate(true)
		var raw: Dictionary=Catalog.snap_stairs(request,[],false)
		var snapped: Dictionary=Catalog.snap_stairs(request,[])
		var explicit: Dictionary=Catalog.snap_stairs(request,[],true)
		if request!=before or raw.pz!=request.pz or raw.support!="" or not is_equal_approx(snapped.pz,z) or snapped.support!="@base" or snapped!=explicit:
			printerr("FAIL Catalog 单独加载的旧入口吸附")
			quit(1)
			return
	print("[b3-catalog-only] 旧入口正常")
	quit(0)
''')
	fixture.close()
	var output: Array=[]
	var code:=OS.execute(OS.get_executable_path(),["--headless","--path",root,"--script","res://fixture.gd"],output,true)
	var text:="\n".join(output)
	print("[b3-catalog-only-process] exit=%d\n%s"%[code,text])
	check(code==0 and "[b3-catalog-only] 旧入口正常" in text and not "ERROR" in text,"仅 preload Catalog 的独立进程退出码与标记正常")

func run() -> void:
	if OS.get_environment("SEA_B3_SNAP_CAPTURE")=="1":
		var file:=FileAccess.open("res://outputs/b3-snap-baseline.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(snap_samples()))
		check(file!=null,"保存修改前吸附样例")
	else:
		guard_commands()
		hot_path_guards()
		catalog_only_process()
		snap_equivalence()
	print("[b3-building-guards] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
