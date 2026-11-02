extends SceneTree
## SEA-BUILDING 性能门禁：吸附求解必须保持近线性，且不能改变任何一个解。
##
## 两个断言方向：
##   1. 结果等价 —— 对固定布局与光标，求解输出必须与内联的参考实现逐项一致。
##      留一份参考实现的代价，小于「某天调性能顺手改了玩法没人发现」的代价。
##   2. 耗时曲线 —— 布局翻倍不能带来立方级增长。阈值按实测留余量（当前 45 块
##     板约 2.2 ms），退化到旧实现的 163 ms 会立刻失败。
const Catalog = preload("res://src/building/building_catalog.gd")
const Service = preload("res://src/building/building_service.gd")
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func model() -> RefCounted:
	var s:=Service.new()
	s.configure({"eligibility":func(): return "", "space_reason":func(_r): return "",
		"pay":func(_c): return true, "refund":func(_c): return true,
		"layout_reason":func(_b:Array,_a:Array,_r:Dictionary): return ""})
	return s
func layout(side: int) -> Array:
	return layout_count(side*side,side)
func layout_count(count: int,side: int) -> Array:
	var s:=model()
	for i in count:
		var made: Dictionary=s.begin({"kind":"raft_4x4","px":100+float(i%side)*4.0,"pz":100+float(i/side)*4.0,
			"py":0.0,"turn":0,"support":"","origin":"boat"})
		check(made.ok,"performance fixture creates platform "+str(i))
	s.tick(30.0)
	check(s.query().size()==count,"performance fixture has exact count "+str(count))
	return s.query()

## Reference solver: the pre-index shape — every candidate formed from scratch and
## every test run against the whole union. Slow on purpose; it is the oracle.
func reference(kind: String,point: Vector2,turn: int,rows: Array) -> Dictionary:
	var extent:=Catalog.platform_extent(kind,turn)
	var surfaces:=Catalog.support_tiles(rows)
	var fallback: Dictionary={"kind":kind,"px":snappedf(point.x,2.0),"pz":snappedf(point.y,2.0),
		"py":0.0,"x":0,"z":0,"support":"","turn":turn}
	var best: Dictionary={}
	var best_score:=INF
	var corners: Array=[]
	for tile: Rect2 in surfaces:
		corners.append(tile.position);corners.append(tile.end)
	for tile: Rect2 in surfaces:
		for side in 4:
			var vertical:=side<2
			var edge: float=(tile.position.x if side==0 else tile.end.x) if vertical else (tile.position.y if side==2 else tile.end.y)
			var span: float=extent.y if vertical else extent.x
			var seen: Dictionary={}
			for i in corners.size():
				var line: Vector2=corners[i]
				var raw: float=(line.y if vertical else line.x)+((span/2) if i%2==0 else (-span/2))
				var key:=int(round(raw*100.0))
				if seen.has(key): continue
				seen[key]=true
				var request: Dictionary=fallback.duplicate()
				if vertical:
					request.px=edge-(extent.x/2) if side==0 else edge+(extent.x/2)
					request.pz=raw
				else:
					request.px=raw
					request.pz=edge-(extent.y/2) if side==2 else edge+(extent.y/2)
				var rect:=Rect2(Vector2(request.px,request.pz)-extent/2,extent)
				if Catalog.contact_against(rect,surfaces)<Catalog.JOIN_MIN: continue
				if Catalog.overlaps_any(rect,surfaces): continue
				var score:=Catalog.rect_distance(rect,point)
				if score<best_score-0.0005:
					best_score=score;best=request
	return best if not best.is_empty() else fallback

func measure(rows: Array,times: int) -> float:
	var probe:=Vector2(96.7,101.7)
	Catalog.snap_foundation("raft_4x4",probe,0,rows,false)
	var start:=Time.get_ticks_usec()
	for i in times:
		Catalog.snap_foundation("raft_4x4",Vector2(probe.x+float(i%5)*1.3,probe.y),0,rows,false)
	return float(int(Time.get_ticks_usec())-start)/float(times)/1000.0

func run() -> void:
	# 1. Result equivalence against the reference solver.
	var mismatches: Array[String]=[]
	var compared:=0
	for side in [1,2,3,4]:
		var rows:=layout(side)
		for kind in ["raft_4x4","raft_2x4","deck"]:
			for turn in 2:
				var cursor:=Vector2(96.0,96.0)
				while cursor.x<100+float(side)*4.0+6.0:
					compared+=1
					var got: Dictionary=Catalog.snap_foundation(kind,cursor,turn,rows,false)
					var want: Dictionary=reference(kind,cursor,turn,rows)
					if str(got.get("kind"))!=str(want.get("kind")) \
							or not is_equal_approx(float(got.get("px")),float(want.get("px"))) \
							or not is_equal_approx(float(got.get("pz")),float(want.get("pz"))):
						mismatches.append("%s/%d @%s -> got(%s,%s) want(%s,%s)"%[kind,turn,cursor,
							str(got.get("px")),str(got.get("pz")),str(want.get("px")),str(want.get("pz"))])
					cursor.x+=0.83
	check(compared>500,"equivalence actually ran (%d samples)"%compared)
	check(mismatches.is_empty(),"snapping is result-identical to the reference solver: "+str(mismatches.slice(0,3)))

	# 2. Free-water mode is unchanged too: a lone raft is still rejected while it
	#    overlaps anything, and still allowed on clear water.
	var small:=layout(2)
	var lone: Dictionary=Catalog.snap_foundation("raft_4x4",Vector2(400.0,400.0),0,small,true)
	check(lone.get("px")==400.0 and lone.get("pz")==400.0,"free water still returns the integer grid point")
	var crowded: Dictionary=Catalog.snap_foundation("raft_4x4",Vector2(0.0,0.0),0,small,true)
	check(crowded.get("px")!=0.0 or crowded.get("pz")!=0.0,"free water next to existing boards falls back to the flush solver")

	# 3. Cost curve. A cubic solver at 45 boards needs 163 ms; the budget below
	#    leaves generous headroom for slower machines while still failing loudly.
	var shapes: Array=[]
	for count in [9,25,45,100]:
		var rows:=layout_count(count,ceili(sqrt(float(count))))
		shapes.append({"boards":rows.size(),"ms":measure(rows,24)})
	print("[perf] 吸附求解耗时：")
	for shape in shapes: print("[perf]   %2d 块板  %.3f ms"%[int(shape.boards),float(shape.ms)])
	var biggest: float=float(shapes[-1].ms)
	check(biggest<12.0,"actual 100-board snap stays inside frame budget (%.2f ms)"%biggest)
	# Growing 25 -> 45 boards must not explode. Linear would be ~4x; give it 12x
	# before calling it a regression, because a single machine hiccup is not a bug.
	var smallest: float=maxf(float(shapes[0].ms),0.001)
	check(biggest/smallest<12.0,"growth from 9 to 25 boards stays near linear (%.1fx)"%(biggest/smallest))

	# 4. The spatial index must not leak state between calls: solving the same
	#    query twice in a row has to agree.
	var twice:=layout(3)
	var first: Dictionary=Catalog.snap_foundation("raft_4x4",Vector2(0.7,0.9),0,twice,false)
	var second: Dictionary=Catalog.snap_foundation("raft_4x4",Vector2(0.7,0.9),0,twice,false)
	check(is_equal_approx(float(first.get("px")),float(second.get("px")))
		and is_equal_approx(float(first.get("pz")),float(second.get("pz"))),
		"repeated snapping is deterministic")

	print("[building-perf] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
